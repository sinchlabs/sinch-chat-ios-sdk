import Foundation
import SinchPushSDKNotificationExtension
import os

/// One APNs delivery, waiting to be reported to sinch-push.
struct DeliveryReport: Codable, Equatable, Sendable {
    /// The message the push carried.
    let messageID: String
    /// The subscriber the push was addressed to.
    let subscriberID: String
    /// When the delivery was queued, in milliseconds since the Unix epoch.
    let enqueuedAtMs: Int64
    /// Set while a background upload carries the delivery: the normal flush leaves it alone until then (milliseconds
    /// since the Unix epoch). Absent in deliveries persisted before the uploads existed.
    var inFlightUntilMs: Int64?

    init(messageID: String, subscriberID: String, enqueuedAtMs: Int64, inFlightUntilMs: Int64? = nil) {
        self.messageID = messageID
        self.subscriberID = subscriberID
        self.enqueuedAtMs = enqueuedAtMs
        self.inFlightUntilMs = inFlightUntilMs
    }

    /// Whether two deliveries are the same one.
    func isSameDelivery(as other: DeliveryReport) -> Bool {
        messageID == other.messageID && subscriberID == other.subscriberID
    }
}

/// Where the queued deliveries are persisted.
protocol DeliveryReportStore: AnyObject, Sendable {
    func loadDeliveryReports() -> [DeliveryReport]
    func saveDeliveryReports(_ reports: [DeliveryReport])
}

/// `UserDefaults`-backed store for the deliveries, under a key of its own.
final class UserDefaultsDeliveryReportStore: DeliveryReportStore, @unchecked Sendable {
    private enum Key {
        static let outbox = "com.sinch.push.deliveryReports.outbox"
    }

    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    func loadDeliveryReports() -> [DeliveryReport] {
        guard let data = defaults.data(forKey: Key.outbox) else { return [] }
        return (try? JSONDecoder().decode([DeliveryReport].self, from: data)) ?? []
    }

    func saveDeliveryReports(_ reports: [DeliveryReport]) {
        guard let data = try? JSONEncoder().encode(reports) else { return }
        defaults.set(data, forKey: Key.outbox)
    }
}

/// The APNs deliveries waiting to be reported to sinch-push.
///
/// A delivery is keyed by the message and the subscriber, so one delivery is reported
/// once. The outbox is bounded, and persisted before an enqueue returns, so a delivery
/// survives a restart.
///
/// Thread-safe: the APNs callbacks run on whatever queue UIKit picks.
final class DeliveryReportOutbox: Sendable {
    /// The most deliveries the outbox holds. The oldest is dropped when it is full.
    static let capacity = 500

    /// How long a delivery stays out of the normal flush while a background upload carries it: as long as the
    /// system keeps trying the upload, which then fails and hands the delivery back.
    static let inFlightDurationMs = Int64(BackgroundReportUploader.resourceTimeout * 1000)

    /// How long a delivery is kept before it is dropped at flush time.
    static let ttlMs: Int64 = 72 * 60 * 60 * 1000

    private struct State {
        var reports: [DeliveryReport] = []
        /// Loaded on first use, so deliveries persisted before construction are queued.
        var didLoad = false
    }

    private let store: DeliveryReportStore
    private let state = OSAllocatedUnfairLock(initialState: State())

    init(store: DeliveryReportStore) {
        self.store = store
    }

    /// Queues a delivery. Returns `false` when the same delivery is already queued.
    @discardableResult
    func enqueue(messageID: String, subscriberID: String, enqueuedAtMs: Int64) -> Bool {
        let report = DeliveryReport(messageID: messageID, subscriberID: subscriberID, enqueuedAtMs: enqueuedAtMs)
        return state.withLock { state in
            loadIfNeeded(&state)
            guard !state.reports.contains(where: { $0.isSameDelivery(as: report) }) else { return false }
            state.reports.append(report)
            while state.reports.count > Self.capacity { state.reports.removeFirst() }
            store.saveDeliveryReports(state.reports)
            return true
        }
    }

    /// The next deliveries to send, oldest first. Deliveries past their time to live are dropped. The ones a
    /// background upload carries are left out until that upload fails or ``inFlightDurationMs`` has passed.
    func nextBatch(nowMs: Int64, limit: Int) -> [DeliveryReport] {
        state.withLock { state in
            loadIfNeeded(&state)
            let expired = state.reports.filter { nowMs - $0.enqueuedAtMs > Self.ttlMs }
            if !expired.isEmpty {
                state.reports.removeAll { report in expired.contains { $0.isSameDelivery(as: report) } }
                store.saveDeliveryReports(state.reports)
            }
            return Array(state.reports.lazy.filter { ($0.inFlightUntilMs ?? 0) <= nowMs }.prefix(limit))
        }
    }

    /// Marks the deliveries as carried by a background upload.
    func markInFlight(_ reports: [DeliveryReport], untilMs: Int64) {
        setInFlight(untilMs, for: reports)
    }

    /// Hands the deliveries back to the normal flush, as their upload failed.
    func clearInFlight(_ reports: [DeliveryReport]) {
        setInFlight(nil, for: reports)
    }

    /// Whether a background upload carries the delivery.
    func isInFlight(_ report: DeliveryReport, nowMs: Int64) -> Bool {
        state.withLock { state in
            loadIfNeeded(&state)
            return state.reports.contains { $0.isSameDelivery(as: report) && ($0.inFlightUntilMs ?? 0) > nowMs }
        }
    }

    private func setInFlight(_ untilMs: Int64?, for reports: [DeliveryReport]) {
        guard !reports.isEmpty else { return }
        state.withLock { state in
            loadIfNeeded(&state)
            for index in state.reports.indices where reports.contains(where: { $0.isSameDelivery(as: state.reports[index]) }) {
                state.reports[index].inFlightUntilMs = untilMs
            }
            store.saveDeliveryReports(state.reports)
        }
    }

    /// Removes the deliveries the server accepted.
    func remove(_ reports: [DeliveryReport]) {
        guard !reports.isEmpty else { return }
        state.withLock { state in
            loadIfNeeded(&state)
            state.reports.removeAll { report in reports.contains { $0.isSameDelivery(as: report) } }
            store.saveDeliveryReports(state.reports)
        }
    }

    /// Drops every queued delivery.
    func clear() {
        state.withLock { state in
            state.reports = []
            state.didLoad = true
            store.saveDeliveryReports([])
        }
    }

    /// Whether nothing is queued.
    var isEmpty: Bool {
        state.withLock { state in
            loadIfNeeded(&state)
            return state.reports.isEmpty
        }
    }

    /// The number of queued deliveries.
    var count: Int {
        state.withLock { state in
            loadIfNeeded(&state)
            return state.reports.count
        }
    }

    private func loadIfNeeded(_ state: inout State) {
        guard !state.didLoad else { return }
        state.didLoad = true
        state.reports = store.loadDeliveryReports()
    }
}
