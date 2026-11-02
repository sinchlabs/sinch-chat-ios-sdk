import Foundation

/// A delivery the extension could not report, left for the app to report.
package struct PendingDelivery: Codable, Equatable, Sendable {
    package let messageId: String
    package let subscriberId: String
    /// When the extension gave up on the delivery.
    package let failedAt: Date

    package init(messageId: String, subscriberId: String, failedAt: Date) {
        self.messageId = messageId
        self.subscriberId = subscriberId
        self.failedAt = failedAt
    }
}

extension ReportContainer {
    /// The deliveries the extension could not report, oldest first, removed from the store in the same step.
    /// The app queues them in its own outbox, which retries them.
    package func takePendingDeliveries() -> [PendingDelivery] {
        PendingDeliveryStore(container: self).take()
    }
}

/// The deliveries the extension could not report: its upload failed (the server refused it, 5xx, transport error), or
/// the mirrored access token had expired and the extension did not even try. Shared with the app through the App
/// Group, which reports them the next time it runs. Bounded in count and age, like the sent markers.
package struct PendingDeliveryStore: Sendable {
    package static let capacity = 1000
    package static let maxAge: TimeInterval = 7 * 24 * 60 * 60

    private static let fileName = "pending-deliveries.json"
    private static let lockName = "pending-deliveries.lock"
    private let container: ReportContainer
    private let now: @Sendable () -> Date

    package init(container: ReportContainer, now: @escaping @Sendable () -> Date = { Date() }) {
        self.container = container
        self.now = now
    }

    /// Adds `deliveries` that failed now. One already stored is kept as it is.
    package func append(_ deliveries: [ReportedDelivery]) {
        guard !deliveries.isEmpty, let url = fileURL else { return }
        container.withFileLock(named: Self.lockName) {
            var pending = load()
            let stamp = now()
            for delivery in deliveries
            where !pending.contains(where: { $0.messageId == delivery.messageID && $0.subscriberId == delivery.subscriberID }) {
                pending.append(PendingDelivery(messageId: delivery.messageID, subscriberId: delivery.subscriberID,
                                               failedAt: stamp))
            }
            if pending.count > Self.capacity { pending.removeFirst(pending.count - Self.capacity) }
            save(pending, to: url)
        }
    }

    /// Returns the stored deliveries, oldest first, and empties the store.
    package func take() -> [PendingDelivery] {
        guard let url = fileURL else { return [] }
        return container.withFileLock(named: Self.lockName) {
            let pending = load()
            if FileManager.default.fileExists(atPath: url.path) { save([], to: url) }
            return pending
        }
    }

    private var fileURL: URL? {
        container.directory?.appendingPathComponent(Self.fileName)
    }

    private func save(_ pending: [PendingDelivery], to url: URL) {
        guard let data = try? JSONEncoder().encode(pending) else { return }
        container.write(data, to: url)
    }

    /// The stored deliveries within `maxAge`, oldest first.
    private func load() -> [PendingDelivery] {
        guard let url = fileURL,
              let data = try? Data(contentsOf: url),
              let pending = try? JSONDecoder().decode([PendingDelivery].self, from: data) else { return [] }
        let oldest = now().addingTimeInterval(-Self.maxAge)
        return pending.filter { $0.failedAt >= oldest }
    }
}
