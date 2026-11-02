import Foundation

/// Schedules the queue's follow-up work.
///
/// Injected so tests can drive the 0.5 s gap and the 5 s alert back-off without
/// waiting in real time.
@MainActor
protocol InAppScheduling: AnyObject {

    /// Runs `work` after `delay`. Scheduling again replaces the pending work.
    func schedule(after delay: TimeInterval, _ work: @escaping @MainActor () -> Void)

    /// Drops the pending work, if any.
    func cancel()
}

@MainActor
final class InAppTaskScheduler: InAppScheduling {

    private var pending: Task<Void, Never>?

    func schedule(after delay: TimeInterval, _ work: @escaping @MainActor () -> Void) {
        cancel()
        pending = Task { @MainActor [weak self] in
            do {
                try await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
            } catch {
                return
            }
            guard !Task.isCancelled else { return }
            self?.pending = nil
            work()
        }
    }

    func cancel() {
        pending?.cancel()
        pending = nil
    }
}
