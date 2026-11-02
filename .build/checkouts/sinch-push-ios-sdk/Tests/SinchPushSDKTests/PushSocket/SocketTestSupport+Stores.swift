import Foundation

@testable import SinchPushSDK

/// An in-memory store that hands the harness the persisted value back.
final class FakeSocketStateStore: SocketStateStore, @unchecked Sendable {
    private(set) var seen: [String] = []
    private(set) var reported: [String] = []
    private(set) var lastSeen = ""
    private(set) var lastSeenEnqueuedAt: Int64 = 0
    private(set) var outbox: [PendingReport] = []
    private(set) var messages: [SocketMessageEvent] = []
    private(set) var configuration: PersistedSocketConfiguration?
    private(set) var clearConfigurationCount = 0
    private(set) var saveReportedKeysCount = 0
    private(set) var saveOutboxCount = 0
    /// Overrides the protocol extension's two-write default so a wrapper's forward of the combined call is observable.
    private(set) var combinedLastSeenSaves: [(id: String, enqueuedAtMs: Int64)] = []
    var onSaveConfiguration: ((PersistedSocketConfiguration) -> Void)?
    var onSaveLastSeen: (() -> Void)?

    init(
        seen: [String] = [],
        reported: [String] = [],
        lastSeen: String = "",
        lastSeenEnqueuedAt: Int64 = 0,
        outbox: [PendingReport] = [],
        messages: [SocketMessageEvent] = [],
        configuration: PersistedSocketConfiguration? = nil
    ) {
        self.seen = seen
        self.reported = reported
        self.lastSeen = lastSeen
        self.lastSeenEnqueuedAt = lastSeenEnqueuedAt
        self.outbox = outbox
        self.messages = messages
        self.configuration = configuration
    }

    func loadSeenMessageIDs() -> [String] { seen }
    func saveSeenMessageIDs(_ ids: [String]) { seen = ids }

    func loadReportedKeys() -> [String] { reported }
    func saveReportedKeys(_ keys: [String]) {
        reported = keys
        saveReportedKeysCount += 1
    }

    func loadLastSeenMessageID() -> String { lastSeen }
    func saveLastSeenMessageID(_ id: String) {
        onSaveLastSeen?()
        lastSeen = id
    }
    func loadLastSeenEnqueuedAtMs() -> Int64 { lastSeenEnqueuedAt }
    func saveLastSeenEnqueuedAtMs(_ milliseconds: Int64) { lastSeenEnqueuedAt = milliseconds }
    func saveLastSeen(id: String, enqueuedAtMs: Int64) {
        combinedLastSeenSaves.append((id, enqueuedAtMs))
        onSaveLastSeen?()
        lastSeen = id
        lastSeenEnqueuedAt = enqueuedAtMs
    }

    func loadOutbox() -> [PendingReport] { outbox }
    func saveOutbox(_ reports: [PendingReport]) {
        outbox = reports
        saveOutboxCount += 1
    }

    func loadPendingMessages() -> [SocketMessageEvent] { messages }
    func savePendingMessages(_ messages: [SocketMessageEvent]) { self.messages = messages }

    func loadConfiguration() -> PersistedSocketConfiguration? { configuration }
    func saveConfiguration(_ value: PersistedSocketConfiguration) {
        configuration = value
        onSaveConfiguration?(value)
    }
    func clearConfiguration() {
        clearConfigurationCount += 1
        configuration = nil
    }

    func persistedText(contains value: String) -> Bool {
        let encoder = JSONEncoder()
        let slices: [AnyEncodableBox] = [
            AnyEncodableBox(seen), AnyEncodableBox(reported), AnyEncodableBox(lastSeen),
            AnyEncodableBox(outbox), AnyEncodableBox(messages), AnyEncodableBox(configuration)
        ]
        return slices.contains { box in
            guard let data = try? encoder.encode(box) else { return false }
            return String(decoding: data, as: UTF8.self).contains(value)
        }
    }
}

private struct AnyEncodableBox: Encodable {
    private let encodeValue: (Encoder) throws -> Void

    init<T: Encodable>(_ value: T) {
        self.encodeValue = { encoder in
            var container = encoder.singleValueContainer()
            try container.encode(value)
        }
    }

    func encode(to encoder: Encoder) throws { try encodeValue(encoder) }
}
