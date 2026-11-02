import Foundation
import Combine

/// Guards a bridge from a completion handler to a checked continuation.
///
/// The bridged completions are documented to fire exactly once, and a checked continuation traps the process when it
/// is resumed twice. The gate turns a repeated call into a no-op instead, so a completion that misbehaves can never
/// crash a host app.
final class OnceGate: @unchecked Sendable {

    private let lock = NSLock()
    private var isClaimed = false

    /// Returns `true` for the first caller and `false` for every later one.
    func claim() -> Bool {
        lock.lock()
        defer { lock.unlock() }
        guard isClaimed == false else { return false }
        isClaimed = true
        return true
    }
}

/// Holds the Combine subscription behind an `AsyncStream` and cancels it at most once, from whichever thread the
/// stream terminates on.
final class SubscriptionBox: @unchecked Sendable {

    private let lock = NSLock()
    private var cancellable: AnyCancellable?

    init(_ cancellable: AnyCancellable) {
        self.cancellable = cancellable
    }

    func cancel() {
        lock.lock()
        let pending = cancellable
        cancellable = nil
        lock.unlock()
        pending?.cancel()
    }
}

enum EventStream {

    /// A fresh `AsyncStream` over a publisher.
    ///
    /// Nothing is replayed: a subscriber sees the values sent after it subscribed, exactly like a
    /// `PassthroughSubject`. The stream cancels its subscription when the consumer stops iterating (task
    /// cancellation, `break` or the stream going out of scope), so an abandoned observation does not keep the SDK
    /// posting into a dead buffer.
    ///
    /// The buffer is bounded: events are hints, not state (the SDK answers state with `isChatAvailable()` and the
    /// inbox getter), so a consumer that never drains the stream must not grow memory without a limit.
    static func make<P: Publisher>(
        from publisher: P,
        bufferingPolicy: AsyncStream<P.Output>.Continuation.BufferingPolicy = .bufferingNewest(64)
    ) -> AsyncStream<P.Output> where P.Failure == Never, P.Output: Sendable {
        AsyncStream(bufferingPolicy: bufferingPolicy) { continuation in
            let subscription = SubscriptionBox(publisher.sink { continuation.yield($0) })
            continuation.onTermination = { _ in subscription.cancel() }
        }
    }
}
