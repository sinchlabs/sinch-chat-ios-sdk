import Foundation

/// A lifecycle event of an in-app alert, delivered by ``InAppMessages/events``.
///
/// The events are emitted alongside ``InAppMessageDelegate``; the delegate keeps
/// working exactly as before for a host that has one.
public enum InAppMessageEvent: Sendable {
    /// The alert was accepted and queued.
    case presented(InAppMessage)
    /// A choice in the alert was tapped.
    case actionTapped(InAppChoiceAction, in: InAppMessage)
    /// The alert was dismissed by the user, or dropped by `dismissAll()`.
    case dismissed(InAppMessage)
}

/// Fans ``InAppMessageEvent``s out to every stream a host is reading.
///
/// A plain actor is not an option: `AsyncStream` delivers synchronously and the
/// controller emits from the main actor. The lock also lets `onTermination` remove
/// a consumer from any thread.
final class InAppEventMulticaster: @unchecked Sendable {

    private let lock = NSLock()
    private var continuations: [UUID: AsyncStream<InAppMessageEvent>.Continuation] = [:]

    /// The live consumers. Read by tests to prove a terminated stream is removed.
    var consumerCount: Int { lock.withLock { continuations.count } }

    /// A new stream over the same events. Consumers are independent: one leaving
    /// does not affect the others.
    func makeStream() -> AsyncStream<InAppMessageEvent> {
        AsyncStream(bufferingPolicy: .bufferingNewest(64)) { continuation in
            let id = UUID()
            lock.withLock { continuations[id] = continuation }
            continuation.onTermination = { [weak self] _ in
                self?.remove(id)
            }
        }
    }

    /// Emits `event` to every live stream. No consumers: nothing to do.
    func send(_ event: InAppMessageEvent) {
        let live = lock.withLock { Array(continuations.values) }
        for continuation in live {
            continuation.yield(event)
        }
    }

    private func remove(_ id: UUID) {
        _ = lock.withLock { continuations.removeValue(forKey: id) }
    }
}
