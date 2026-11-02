import Foundation
import os

/// The dedupe set shared by the socket and the APNs paths. One instance per process,
/// owned by the SDK, so a message arriving over both channels is shown once.
///
/// Thread-safe: the socket runs on its scheduler, and the APNs callbacks run on
/// whatever queue UIKit picks. Persists under `seenMessageIds` through ``SocketStateStore``.
final class SeenMessageRegistry: Sendable {
    private struct State {
        var seen = SeenSet()
        /// Loaded on first use, so ids persisted before construction are seen.
        var didLoad = false
    }

    private let store: SocketStateStore
    private let state = OSAllocatedUnfairLock(initialState: State())

    init(store: SocketStateStore) {
        self.store = store
    }

    /// Records `id`. Returns `true` when new, and `false` on a hit, when the caller
    /// presents nothing again. The set is persisted under the lock before returning,
    /// so the id is durable before DELIVERED is sent.
    @discardableResult
    func markSeen(_ id: String) -> Bool {
        state.withLock { state in
            loadIfNeeded(&state)
            guard state.seen.insert(id) else { return false }
            store.saveSeenMessageIDs(state.seen.persisted)
            return true
        }
    }

    /// Whether `id` has been marked, without marking it.
    func contains(_ id: String) -> Bool {
        state.withLock { state in
            loadIfNeeded(&state)
            return state.seen.contains(id)
        }
    }

    /// Oldest first.
    var snapshot: [String] {
        state.withLock { state in
            loadIfNeeded(&state)
            return state.seen.persisted
        }
    }

    private func loadIfNeeded(_ state: inout State) {
        guard !state.didLoad else { return }
        state.didLoad = true
        state.seen = SeenSet(persisted: store.loadSeenMessageIDs())
    }
}
