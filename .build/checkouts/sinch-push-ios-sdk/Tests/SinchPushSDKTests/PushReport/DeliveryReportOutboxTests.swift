import XCTest

@testable import SinchPushSDK

final class DeliveryReportOutboxTests: XCTestCase {

    private let hourMs: Int64 = 60 * 60 * 1000
    private var store: FakeDeliveryReportStore!
    private var outbox: DeliveryReportOutbox!

    override func setUp() {
        super.setUp()
        store = FakeDeliveryReportStore()
        outbox = DeliveryReportOutbox(store: store)
    }

    func testAnEnqueuedDeliveryIsPersistedBeforeEnqueueReturns() {
        XCTAssertTrue(outbox.enqueue(messageID: "m-1", subscriberID: "s-1", enqueuedAtMs: 10))

        XCTAssertEqual(store.stored, [DeliveryReport(messageID: "m-1", subscriberID: "s-1", enqueuedAtMs: 10)])
    }

    func testTheSameMessageAndSubscriberIsQueuedOnce() {
        XCTAssertTrue(outbox.enqueue(messageID: "m-1", subscriberID: "s-1", enqueuedAtMs: 10))
        XCTAssertFalse(outbox.enqueue(messageID: "m-1", subscriberID: "s-1", enqueuedAtMs: 20))

        XCTAssertEqual(outbox.count, 1)
        XCTAssertEqual(store.saveCount, 1)
        XCTAssertEqual(outbox.nextBatch(nowMs: 20, limit: 10).map(\.enqueuedAtMs), [10])
    }

    func testAnotherSubscriberOrMessageIsAnotherDelivery() {
        outbox.enqueue(messageID: "m-1", subscriberID: "s-1", enqueuedAtMs: 10)
        outbox.enqueue(messageID: "m-1", subscriberID: "s-2", enqueuedAtMs: 10)
        outbox.enqueue(messageID: "m-2", subscriberID: "s-1", enqueuedAtMs: 10)

        XCTAssertEqual(outbox.count, 3)
    }

    func testTheOutboxHoldsFiveHundredAndDropsTheOldest() {
        for index in 0..<501 {
            outbox.enqueue(messageID: "m-\(index)", subscriberID: "s-1", enqueuedAtMs: 10)
        }

        XCTAssertEqual(outbox.count, DeliveryReportOutbox.capacity)
        XCTAssertEqual(DeliveryReportOutbox.capacity, 500)
        let batch = outbox.nextBatch(nowMs: 10, limit: 600)
        XCTAssertEqual(batch.first?.messageID, "m-1")
        XCTAssertEqual(batch.last?.messageID, "m-500")
        XCTAssertEqual(store.stored.count, 500)
    }

    func testADeliveryOlderThanSeventyTwoHoursIsDroppedAtFlushTime() {
        outbox.enqueue(messageID: "old", subscriberID: "s-1", enqueuedAtMs: 0)
        outbox.enqueue(messageID: "edge", subscriberID: "s-1", enqueuedAtMs: 1)
        outbox.enqueue(messageID: "new", subscriberID: "s-1", enqueuedAtMs: 10 * hourMs)

        XCTAssertEqual(outbox.count, 3)
        let batch = outbox.nextBatch(nowMs: 72 * hourMs + 1, limit: 10)

        XCTAssertEqual(batch.map(\.messageID), ["edge", "new"])
        XCTAssertEqual(store.stored.map(\.messageID), ["edge", "new"])
    }

    func testTheBatchIsTheOldestDeliveriesUpToTheLimit() {
        for index in 0..<5 {
            outbox.enqueue(messageID: "m-\(index)", subscriberID: "s-1", enqueuedAtMs: 10)
        }

        XCTAssertEqual(outbox.nextBatch(nowMs: 10, limit: 3).map(\.messageID), ["m-0", "m-1", "m-2"])
        XCTAssertEqual(outbox.count, 5)
    }

    func testRemoveDropsOnlyTheGivenDeliveries() {
        outbox.enqueue(messageID: "m-1", subscriberID: "s-1", enqueuedAtMs: 10)
        outbox.enqueue(messageID: "m-2", subscriberID: "s-1", enqueuedAtMs: 10)

        outbox.remove([deliveryReport("m-1", at: 10)])

        XCTAssertEqual(store.stored.map(\.messageID), ["m-2"])
    }

    func testANewOutboxOverTheSameStoreSeesTheDeliveries() {
        outbox.enqueue(messageID: "m-1", subscriberID: "s-1", enqueuedAtMs: 10)
        outbox.enqueue(messageID: "m-2", subscriberID: "s-2", enqueuedAtMs: 11)

        let restarted = DeliveryReportOutbox(store: store)

        XCTAssertEqual(restarted.count, 2)
        XCTAssertFalse(restarted.enqueue(messageID: "m-1", subscriberID: "s-1", enqueuedAtMs: 99))
        XCTAssertEqual(restarted.nextBatch(nowMs: 11, limit: 10).map(\.messageID), ["m-1", "m-2"])
    }

    func testClearEmptiesTheOutboxAndTheStore() {
        outbox.enqueue(messageID: "m-1", subscriberID: "s-1", enqueuedAtMs: 10)

        outbox.clear()

        XCTAssertEqual(outbox.count, 0)
        XCTAssertEqual(store.stored, [])
        XCTAssertEqual(DeliveryReportOutbox(store: store).count, 0)
    }

    func testTheUserDefaultsStoreRoundTripsUnderItsOwnKey() throws {
        let suite = "com.sinch.tests.deliveryReports.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let first = UserDefaultsDeliveryReportStore(defaults: defaults)

        first.saveDeliveryReports([deliveryReport("m-1"), deliveryReport("m-2", subscriber: "s-2")])

        XCTAssertEqual(UserDefaultsDeliveryReportStore(defaults: defaults).loadDeliveryReports().map(\.messageID),
                       ["m-1", "m-2"])
        XCTAssertNotNil(defaults.data(forKey: "com.sinch.push.deliveryReports.outbox"))
        XCTAssertEqual(defaults.dictionaryRepresentation().keys.filter { $0.hasPrefix("com.sinch.push") },
                       ["com.sinch.push.deliveryReports.outbox"])
    }

    func testAnUnreadableStoredValueIsAnEmptyOutbox() throws {
        let suite = "com.sinch.tests.deliveryReports.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        defaults.set(Data("not json".utf8), forKey: "com.sinch.push.deliveryReports.outbox")

        XCTAssertEqual(UserDefaultsDeliveryReportStore(defaults: defaults).loadDeliveryReports(), [])
    }

    func testConcurrentEnqueuesKeepEachDeliveryOnce() {
        let outbox = self.outbox!
        DispatchQueue.concurrentPerform(iterations: 8) { _ in
            for index in 0..<50 {
                outbox.enqueue(messageID: "m-\(index)", subscriberID: "s-1", enqueuedAtMs: 10)
            }
        }

        XCTAssertEqual(outbox.count, 50)
    }
}
