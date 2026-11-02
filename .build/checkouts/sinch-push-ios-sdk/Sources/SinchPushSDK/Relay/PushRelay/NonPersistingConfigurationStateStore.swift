import Foundation

/// Forwards every slice except the configuration, which is never written or read, so no session resumes from it.
final class NonPersistingConfigurationStateStore: SocketStateStore {
    private let wrapped: SocketStateStore

    init(wrapping store: SocketStateStore) {
        self.wrapped = store
    }

    func loadSeenMessageIDs() -> [String] { wrapped.loadSeenMessageIDs() }
    func saveSeenMessageIDs(_ ids: [String]) { wrapped.saveSeenMessageIDs(ids) }

    func loadReportedKeys() -> [String] { wrapped.loadReportedKeys() }
    func saveReportedKeys(_ keys: [String]) { wrapped.saveReportedKeys(keys) }

    func loadLastSeenMessageID() -> String { wrapped.loadLastSeenMessageID() }
    func saveLastSeenMessageID(_ id: String) { wrapped.saveLastSeenMessageID(id) }
    func loadLastSeenEnqueuedAtMs() -> Int64 { wrapped.loadLastSeenEnqueuedAtMs() }
    func saveLastSeenEnqueuedAtMs(_ ms: Int64) { wrapped.saveLastSeenEnqueuedAtMs(ms) }
    func saveLastSeen(id: String, enqueuedAtMs: Int64) { wrapped.saveLastSeen(id: id, enqueuedAtMs: enqueuedAtMs) }

    func loadOutbox() -> [PendingReport] { wrapped.loadOutbox() }
    func saveOutbox(_ reports: [PendingReport]) { wrapped.saveOutbox(reports) }

    func loadPendingMessages() -> [SocketMessageEvent] { wrapped.loadPendingMessages() }
    func savePendingMessages(_ messages: [SocketMessageEvent]) { wrapped.savePendingMessages(messages) }

    func loadConfiguration() -> PersistedSocketConfiguration? { nil }
    func saveConfiguration(_ configuration: PersistedSocketConfiguration) {}
    /// Still forwarded, to remove configuration written by older builds.
    func clearConfiguration() { wrapped.clearConfiguration() }
}
