import Foundation
import Network
import Synchronization
#if canImport(UIKit)
import UIKit
#endif

/// App lifecycle transitions the headless models react to.
enum HeadlessLifecycleEvent: Sendable {
    case willEnterForeground
    case didEnterBackground
}

/// Everything the headless models need from the outside world, behind one seam so tests need neither
/// `NWPathMonitor`, `UIApplication` nor the `SinchChatSDK.shared` singleton.
@MainActor
protocol HeadlessEnvironment: Sendable {
    /// `true` while the network is reachable. Yields the current state first, then every change.
    func connectivityUpdates() -> AsyncStream<Bool>
    /// Foreground and background transitions of the app.
    func lifecycleUpdates() -> AsyncStream<HeadlessLifecycleEvent>
    /// Publishes a lifecycle event on `SinchChatSDK.events`.
    func post(_ event: SinchPluginEvent)
    /// Marks the chat as running on behalf of `owner`, so a second chat cannot start and foreground pushes are
    /// suppressed. Returns `false` when another owner (or the chat screen) already holds it. Claiming again with the
    /// same owner succeeds.
    func claimChat(owner: UUID) -> Bool
    /// Marks the chat as idle again. Does nothing when `owner` does not hold the claim, so a conversation can never
    /// release a claim that is not its own.
    func releaseChat(owner: UUID)
}

/// The production environment: `NWPathMonitor`, `NotificationCenter` and the SDK singleton.
///
/// Foreground and background notifications are app-wide (`UIApplication`), not per scene. With several scenes
/// (iPad multi-window), every model reacts when any scene changes state: backgrounding one window suspends the models
/// of all windows until the app enters the foreground again.
struct SystemHeadlessEnvironment: HeadlessEnvironment {

    func connectivityUpdates() -> AsyncStream<Bool> {
        AsyncStream(bufferingPolicy: .bufferingNewest(8)) { continuation in
            let monitor = NWPathMonitor()
            monitor.pathUpdateHandler = { path in
                continuation.yield(path.status == .satisfied)
            }
            monitor.start(queue: DispatchQueue(label: "sinch.headless.connectivity"))
            continuation.onTermination = { _ in monitor.cancel() }
        }
    }

    func lifecycleUpdates() -> AsyncStream<HeadlessLifecycleEvent> {
        #if canImport(UIKit)
        AsyncStream(bufferingPolicy: .bufferingNewest(8)) { continuation in
            let center = NotificationCenter.default
            let foreground = center.addObserver(forName: UIApplication.willEnterForegroundNotification,
                                                object: nil, queue: .main) { _ in
                continuation.yield(.willEnterForeground)
            }
            let background = center.addObserver(forName: UIApplication.didEnterBackgroundNotification,
                                                object: nil, queue: .main) { _ in
                continuation.yield(.didEnterBackground)
            }
            let tokens = ObserverTokens([foreground, background])
            continuation.onTermination = { _ in
                tokens.removeAll()
            }
        }
        #else
        AsyncStream { $0.finish() }
        #endif
    }

    func post(_ event: SinchPluginEvent) {
        SinchChatSDK.shared.eventListenerSubject.send(event)
    }

    /// The flag and its owner token are one fact, changed in one step under one lock (`DefaultSinchChat.claimChat`):
    /// a token that does not match means somebody else holds the flag. The chat screen has its own token
    /// (`DefaultStartViewModel`).
    ///
    /// The chat screen never checks availability before it takes the flag; it wins over a running headless
    /// conversation. That conversation then loses the claim silently (its token no longer matches), and its next
    /// claim (after a reconnect or foreground) fails, which ends in `.failed(.unavailable)`. The screen's flag is
    /// never touched by a conversation: ``releaseChat(owner:)`` is a no-op for a token that is not the current owner.
    func claimChat(owner: UUID) -> Bool {
        SinchChatSDK.shared._chat.claimChat(owner: owner)
    }

    func releaseChat(owner: UUID) {
        SinchChatSDK.shared._chat.releaseChat(owner: owner)
    }
}

/// `NSObjectProtocol` observer tokens are not `Sendable`; they are only ever removed, which is thread-safe.
private final class ObserverTokens: @unchecked Sendable {
    private let tokens: [any NSObjectProtocol]

    init(_ tokens: [any NSObjectProtocol]) {
        self.tokens = tokens
    }

    func removeAll() {
        tokens.forEach { NotificationCenter.default.removeObserver($0) }
    }
}

// MARK: - Lifetime helpers

/// Cancels the tasks it holds when it is released, so a model that is dropped without `stop()` leaves nothing behind.
/// The model owns the only strong reference; its tasks capture the model weakly.
final class HeadlessTaskBag: @unchecked Sendable {
    /// What a dropped model leaves behind, in the order it is torn down.
    enum ReleaseSlot: Int, CaseIterable {
        /// Held from `start()` until `stop()`: the server subscription and the channel.
        case started
        /// Held while the model owns the "chat is running" flag. Offline, background and `.failed` give the flag back
        /// (and clear this slot) but keep the model started.
        case claim
    }

    private let tasks = Mutex<[String: Task<Void, Never>]>([:])
    private let releaseActions = Mutex<[ReleaseSlot: @Sendable () -> Void]>([:])

    init() {}

    deinit {
        let all = tasks.withLock { dict -> [Task<Void, Never>] in
            let values = Array(dict.values)
            dict.removeAll()
            return values
        }
        all.forEach { $0.cancel() }
        let actions = releaseActions.withLock { dict -> [@Sendable () -> Void] in
            let ordered = ReleaseSlot.allCases.compactMap { dict[$0] }
            dict.removeAll()
            return ordered
        }
        actions.forEach { $0() }
    }

    /// Runs when the bag is released while the slot is still set. A model sets `.started` in `start()` and clears it
    /// in `stop()`, and `.claim` while it holds the flag; they are independent, so a model that is dropped while
    /// offline, in the background or `.failed` (no claim held) still closes what `start()` opened.
    ///
    /// The action runs in `deinit`, which can be on any thread: it may only call thread-safe things directly and has
    /// to hop to the main actor for the rest (the environment is main-actor bound). The hop makes the release and the
    /// event arrive a moment after the model is gone; the owner token keeps a late release from clearing a newer claim.
    func setReleaseAction(_ slot: ReleaseSlot, _ action: (@Sendable () -> Void)?) {
        releaseActions.withLock { $0[slot] = action }
    }

    /// Stores `task` under `key`, cancelling the one it replaces.
    func set(_ key: String, _ task: Task<Void, Never>) {
        let previous = tasks.withLock { $0.updateValue(task, forKey: key) }
        previous?.cancel()
    }

    func cancel(_ key: String) {
        let task = tasks.withLock { $0.removeValue(forKey: key) }
        task?.cancel()
    }

    func cancelAll() {
        let all = tasks.withLock { dict -> [Task<Void, Never>] in
            let values = Array(dict.values)
            dict.removeAll()
            return values
        }
        all.forEach { $0.cancel() }
    }
}

/// Fans one stream of values out to any number of `AsyncStream` subscribers.
final class UpdateBroadcaster<Element: Sendable>: @unchecked Sendable {
    /// Undelivered events kept per stream; the oldest is dropped beyond that.
    static var bufferSize: Int { 256 }

    /// What one subscriber needs: its continuation, and whether a resync is already waiting in its buffer.
    private final class Subscriber: @unchecked Sendable {
        let continuation: AsyncStream<Element>.Continuation
        /// A resync was yielded and the subscriber has not drained its buffer since. Owned by `send`, which has a
        /// single caller (the model's actor).
        var resyncQueued = false
        /// Events yielded after that resync. The buffer holds `bufferSize` events, so beyond that the resync itself
        /// could have been dropped.
        var sinceResync = 0

        init(_ continuation: AsyncStream<Element>.Continuation) {
            self.continuation = continuation
        }
    }

    private let subscribers = Mutex<[UUID: Subscriber]>([:])

    deinit {
        finishAll()
    }

    func makeStream() -> AsyncStream<Element> {
        let id = UUID()
        let (stream, continuation) = AsyncStream<Element>.makeStream(bufferingPolicy: .bufferingNewest(Self.bufferSize))
        subscribers.withLock { $0[id] = Subscriber(continuation) }
        continuation.onTermination = { [weak self] _ in
            _ = self?.subscribers.withLock { $0.removeValue(forKey: id) }
        }
        return stream
    }

    /// Ends every open stream, so `for await` loops over them finish.
    func finishAll() {
        let all = subscribers.withLock { dict -> [Subscriber] in
            let values = Array(dict.values)
            dict.removeAll()
            return values
        }
        all.forEach { $0.continuation.finish() }
    }

    /// Delivers `element` to every stream. A subscriber whose buffer is full loses its oldest event; it then also
    /// gets `resync` (when given), which replaces everything it missed. That is one resync per overflow, not one per
    /// event: the events that follow it apply on top of it, and the next resync is due only when the subscriber has
    /// drained its buffer and fallen behind again (or has not read for a whole buffer's worth of events, so that the
    /// queued resync itself could be gone).
    func send(_ element: Element, resync: @autoclosure () -> Element? = nil) {
        let all = subscribers.withLock { Array($0.values) }
        var fallback: Element?
        var computed = false
        for subscriber in all {
            let result = subscriber.continuation.yield(element)
            var needsResync = false
            switch result {
            case .dropped:
                needsResync = !subscriber.resyncQueued
            case let .enqueued(remaining):
                // Room for everything but this event: the buffer was empty, so the subscriber has read the resync.
                if remaining == Self.bufferSize - 1 {
                    subscriber.resyncQueued = false
                    subscriber.sinceResync = 0
                }
            default:
                break
            }
            if subscriber.resyncQueued {
                subscriber.sinceResync += 1
                if subscriber.sinceResync >= Self.bufferSize { needsResync = true }
            }
            guard needsResync else { continue }
            if !computed {
                fallback = resync()
                computed = true
            }
            guard let fallback else { continue }
            subscriber.continuation.yield(fallback)
            subscriber.resyncQueued = true
            subscriber.sinceResync = 0
        }
    }
}

/// Lets a caller wait for a run that somebody else started, without being part of it: when the waiting task is
/// cancelled it stops waiting and throws ``SinchHeadlessError/cancelled``; the run itself goes on.
private final class JoinGate: @unchecked Sendable {
    private enum State {
        case fresh
        case waiting(CheckedContinuation<Void, any Error>)
        case cancelledEarly
        case finished
    }

    private let state = Mutex<State>(.fresh)

    func arm(_ continuation: CheckedContinuation<Void, any Error>) {
        let resumeNow = state.withLock { state -> Bool in
            if case .cancelledEarly = state {
                state = .finished
                return true
            }
            state = .waiting(continuation)
            return false
        }
        if resumeNow { continuation.resume(throwing: SinchHeadlessError.cancelled) }
    }

    func complete(_ result: Result<Void, any Error>) {
        let continuation = state.withLock { state -> CheckedContinuation<Void, any Error>? in
            guard case let .waiting(continuation) = state else { return nil }
            state = .finished
            return continuation
        }
        continuation?.resume(with: result)
    }

    func cancel() {
        let continuation = state.withLock { state -> CheckedContinuation<Void, any Error>? in
            switch state {
            case .fresh:
                state = .cancelledEarly
                return nil
            case let .waiting(continuation):
                state = .finished
                return continuation
            case .cancelledEarly, .finished:
                return nil
            }
        }
        continuation?.resume(throwing: SinchHeadlessError.cancelled)
    }
}

/// Waits for `run` as a joiner: the result of the run is this call's result, and cancelling the calling task ends only
/// this wait (with ``SinchHeadlessError/cancelled``). The run is neither cancelled nor otherwise touched.
func joinRun(_ run: Task<Void, any Error>) async throws {
    let gate = JoinGate()
    try await withTaskCancellationHandler {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, any Error>) in
            gate.arm(continuation)
            Task {
                let result: Result<Void, any Error>
                do {
                    try await run.value
                    result = .success(())
                } catch {
                    result = .failure(error)
                }
                gate.complete(result)
            }
        }
    } onCancel: {
        gate.cancel()
    }
}
