import Foundation
import Combine

/// Holds a Combine subscription for as long as an ``AsyncStream`` lives. `AnyCancellable`
/// is not `Sendable`, and `onTermination` is, so the subscription sits behind a lock.
final class StreamSubscriptionBox: @unchecked Sendable {

    private let lock = NSLock()
    private var cancellable: AnyCancellable?

    func store(_ cancellable: AnyCancellable) {
        lock.withLock { self.cancellable = cancellable }
    }

    func cancel() {
        lock.withLock {
            cancellable?.cancel()
            cancellable = nil
        }
    }
}

// MARK: - Swift concurrency API

/// Swift-concurrency counterparts of the permission and relay publishers.
///
/// They are extension-only, like the relay defaults above, so a `SinchPush` written
/// before this API existed keeps compiling. The completion and Combine methods are
/// unchanged and still work.
@MainActor
public extension SinchPush {

    /// Asks the user for notification permission and suspends until the system answers.
    ///
    /// The name differs from `askNotificationPermission` on purpose: that base name
    /// already has a no-argument Combine overload, and Swift would pick this `async`
    /// one in an async context, so `push.askNotificationPermission().sink` would stop
    /// compiling. A distinct name keeps both call sites valid.
    /// - Returns: The permission status after the user answered.
    func requestNotificationPermission() async -> SinchSDKNotificationStatus {
        await withCheckedContinuation { continuation in
            askNotificationPermission { status in
                continuation.resume(returning: status)
            }
        }
    }

    /// Reads the current notification permission without asking.
    ///
    /// Named apart from `checkPushPermission()` for the same reason as
    /// ``requestNotificationPermission()``: the no-argument Combine overload keeps
    /// its name and its call sites.
    /// - Returns: The current permission status.
    func notificationPermissionStatus() async -> SinchSDKNotificationStatus {
        await withCheckedContinuation { continuation in
            checkPushPermission { status in
                continuation.resume(returning: status)
            }
        }
    }

    /// The relay state as an `AsyncSequence`: the current state first, then every change.
    ///
    /// Each access starts a new subscription; it is cancelled when the stream is
    /// terminated, so a `for await` loop that leaves does not leak. Slow consumers
    /// keep only the newest state, which is what a state stream should show.
    var socketStates: AsyncStream<SinchPushSocketState> {
        let publisher = socketStatePublisher
        return AsyncStream(bufferingPolicy: .bufferingNewest(1)) { continuation in
            let box = StreamSubscriptionBox()
            box.store(publisher.sink { state in
                continuation.yield(state)
            })
            continuation.onTermination = { _ in box.cancel() }
        }
    }

    /// Relay messages as an `AsyncSequence`, each message once and in order.
    ///
    /// Each access starts a new subscription, cancelled on termination. The stream
    /// buffers recent messages while the consumer is busy; the newest ones win.
    var socketMessages: AsyncStream<SinchPushSocketMessage> {
        let publisher = socketMessagePublisher
        return AsyncStream(bufferingPolicy: .bufferingNewest(100)) { continuation in
            let box = StreamSubscriptionBox()
            box.store(publisher.sink { message in
                continuation.yield(message)
            })
            continuation.onTermination = { _ in box.cancel() }
        }
    }
}
