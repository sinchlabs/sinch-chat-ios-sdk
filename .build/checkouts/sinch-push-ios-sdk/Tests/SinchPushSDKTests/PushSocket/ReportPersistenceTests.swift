//  ReportPersistenceTests.swift — the outbox and the bounded sent set.

import XCTest

@testable import SinchPushSDK

final class ReportPersistenceTests: XCTestCase {

    private func makeCountingTracker(_ store: FakeSocketStateStore) -> ReportTracker {
        ReportTracker(
            store: store, logger: SilentSocketLogger(), random: ScriptedRandomSource(fixed: 0.5),
            now: { 0 })
    }

    private func ack(
        _ id: String, accepted: Bool, error: String = ""
    ) -> Sinch_Push_Delivery_V1beta1_Ws_Ack {
        var frame = Sinch_Push_Delivery_V1beta1_Ws_Ack()
        frame.ackToken = "\(id):\(SocketDeliveryStatus.delivered.tokenSuffix)"
        frame.accepted = accepted
        frame.error = error
        return frame
    }

    // MARK: - The bounded sent set

    func testTheSentSetIsBoundedAtEightThousandAndEvictsOldestFirst() {
        XCTAssertEqual(ReportTracker.sentSetCapacity, 8000)
        XCTAssertEqual(ReportTracker.sentSetCapacity, SeenSet.capacity * 4)

        let store = FakeSocketStateStore()
        let tracker = makeCountingTracker(store)
        let suffix = SocketDeliveryStatus.delivered.tokenSuffix
        func accept(_ id: String) {
            XCTAssertTrue(tracker.queue(messageId: id, sinchMessageId: "s", status: .delivered))
            var ack = Sinch_Push_Delivery_V1beta1_Ws_Ack()
            ack.ackToken = "\(id):\(suffix)"
            ack.accepted = true
            XCTAssertEqual(tracker.handle(ack), .accepted)
        }
        for index in 0..<ReportTracker.sentSetCapacity { accept("m-\(index)") }
        XCTAssertEqual(tracker.reportedKeys.count, ReportTracker.sentSetCapacity)

        accept("m-new")

        let keys = tracker.reportedKeys
        XCTAssertEqual(keys.count, ReportTracker.sentSetCapacity)
        XCTAssertFalse(keys.contains("m-0:\(suffix)"), "oldest kept")
        XCTAssertEqual(keys.first, "m-1:\(suffix)")
        XCTAssertEqual(keys.last, "m-new:\(suffix)")
        XCTAssertTrue(tracker.queue(messageId: "m-0", sinchMessageId: "s", status: .delivered))
        XCTAssertFalse(tracker.queue(messageId: "m-5", sinchMessageId: "s", status: .delivered))

        XCTAssertEqual(makeCountingTracker(store).reportedKeys, keys)
    }

    func testQueueWritesTheOutboxButNotTheSentKeys() {
        let store = FakeSocketStateStore()
        let tracker = makeCountingTracker(store)

        XCTAssertTrue(tracker.queue(messageId: "m-1", sinchMessageId: "s", status: .delivered))

        XCTAssertEqual(store.saveOutboxCount, 1)
        XCTAssertEqual(store.outbox.map(\.messageId), ["m-1"])
        XCTAssertEqual(store.saveReportedKeysCount, 0)
    }

    func testAnAcceptedAckWritesTheSentKeysOnce() {
        let store = FakeSocketStateStore()
        let tracker = makeCountingTracker(store)
        tracker.queue(messageId: "m-1", sinchMessageId: "s", status: .delivered)

        XCTAssertEqual(tracker.handle(ack("m-1", accepted: true)), .accepted)

        XCTAssertEqual(store.saveReportedKeysCount, 1)
        XCTAssertEqual(store.reported, ["m-1:\(SocketDeliveryStatus.delivered.tokenSuffix)"])
        XCTAssertEqual(store.outbox, [], "the accepted entry leaves the persisted outbox")
    }

    func testARejectedAckDoesNotWriteTheSentKeys() {
        for error in ["rate_limited", "upstream_forward_failed", "unsupported_status", "other"] {
            let store = FakeSocketStateStore()
            let tracker = makeCountingTracker(store)
            tracker.queue(messageId: "m-1", sinchMessageId: "s", status: .delivered)

            XCTAssertEqual(
                tracker.handle(ack("m-1", accepted: false, error: error)), .rejected(error: error))

            XCTAssertEqual(store.saveReportedKeysCount, 0, error)
            XCTAssertEqual(store.reported, [], error)
        }
    }

    func testTheAcceptedKeyIsStillKnownAfterARestart() {
        let store = FakeSocketStateStore()
        let first = makeCountingTracker(store)
        first.queue(messageId: "m-1", sinchMessageId: "s", status: .delivered)
        first.handle(ack("m-1", accepted: true))

        let restarted = makeCountingTracker(store)

        XCTAssertEqual(restarted.reportedKeys, first.reportedKeys)
        XCTAssertFalse(restarted.queue(messageId: "m-1", sinchMessageId: "s", status: .delivered))
        XCTAssertTrue(restarted.queue(messageId: "m-1", sinchMessageId: "s", status: .displayed))
    }

    // MARK: - The outbox

    func testAReportQueuedWhileDisconnectedIsSentAfterTheNextHandshake() {
        let harness = makeReportHarness()
        XCTAssertEqual(harness.recorder.current?.status, .connecting)

        // A notification dismissed while the socket is closed must be held, not dropped.
        harness.client.report(messageId: "msg-1", status: .dismissed)
        XCTAssertEqual(harness.reports.count, 0)
        XCTAssertEqual(harness.store.outbox.count, 1)

        harness.handshake()

        XCTAssertEqual(harness.reports.map(\.messageID), ["msg-1"])
        XCTAssertEqual(harness.store.outbox.count, 1, "still in flight until the relay answers")
    }

    func testAQueuedReportSurvivesAClientRestart() throws {
        let store = FakeSocketStateStore()

        let before = makeReportHarness(store: store)
        before.client.report(messageId: "msg-1", status: .dismissed)
        XCTAssertEqual(store.outbox.count, 1)
        XCTAssertEqual(store.outbox.first?.status, .dismissed)

        let after = makeReportHarness(store: store)
        after.handshake()

        let sent = try XCTUnwrap(after.reports.first)
        XCTAssertEqual(sent.messageID, "msg-1")
        XCTAssertEqual(sent.status, .dismissed)
    }

    func testTheOutboxIsBoundedAtTwoHundredEntries() {
        let existing = (0..<ReportTracker.outboxCapacity).map { index in
            PendingReport(
                messageId: "old-\(index)", sinchMessageId: "s", status: .delivered,
                reason: "", attempts: 0, deferUntilMs: nil)
        }
        XCTAssertEqual(ReportTracker.outboxCapacity, 200)
        let harness = makeReportHarness(store: FakeSocketStateStore(outbox: existing))

        harness.client.report(messageId: "new-1", status: .dismissed)

        XCTAssertEqual(harness.store.outbox.count, 200)
        XCTAssertNil(harness.store.outbox.first { $0.messageId == "old-0" })
        XCTAssertEqual(harness.store.outbox.last?.messageId, "new-1")
        XCTAssertTrue(harness.logger.contains("outbox full"))
    }

    func testAReportInFlightIsResentAfterTheConnectionDrops() {
        let harness = makeReportHarness()
        harness.handshake()
        harness.deliverMessage(pooledMessage(messageID: "msg-1"))
        XCTAssertEqual(harness.reports.count, 1)

        // The Ack can never arrive, so the report goes back to queued.
        harness.transport.failTransport(code: 1006)
        harness.scheduler.advance(by: 500)
        harness.handshake(connectionID: "conn-2")

        XCTAssertEqual(harness.reports.map(\.messageID), ["msg-1"])
    }
}
