//  ReportDedupeTests.swift — the seen set and the dedupe of a redelivery.

import XCTest

@testable import SinchPushSDK

final class ReportDedupeTests: XCTestCase {

    // MARK: - The dedupe key

    func testTheDedupeKeyIsThePooledMessageIdNotTheAckToken() {
        let harness = makeReportHarness()
        harness.handshake()

        harness.deliverMessage(pooledMessage(messageID: "msg-1"), ackToken: "token-a")
        harness.deliverMessage(pooledMessage(messageID: "msg-1"), ackToken: "token-b")

        XCTAssertEqual(harness.deliveredMessageIDs, ["msg-1"])
        XCTAssertEqual(harness.reports(.delivered).count, 1)
    }

    func testAColonInAMessageIdNeedsNoEscaping() {
        let harness = makeReportHarness()
        harness.handshake()

        harness.deliverMessage(pooledMessage(messageID: "a:b:c"), ackToken: "token-a")
        harness.deliverMessage(pooledMessage(messageID: "a:b:c"), ackToken: "token-b")

        XCTAssertEqual(harness.deliveredMessageIDs, ["a:b:c"])
        XCTAssertEqual(harness.reports(.delivered).map(\.messageID), ["a:b:c"])
    }

    // MARK: - A dedupe hit

    func testASocketDuplicateIsNotPresentedAndSendsNoSecondReport() {
        let presenter = FakeNotificationPresenter()
        presenter.acceptsPost = true
        let harness = makeHarness(
            configuration: testConfiguration(displayNotifications: .always),
            presenter: presenter)
        harness.handshake()

        harness.deliverMessage(pooledMessage(messageID: "msg-1"))
        let reportsAfterFirst = harness.reports.count
        let eventsAfterFirst = harness.deliveredMessageIDs
        XCTAssertEqual(reportsAfterFirst, 2)

        harness.deliverMessage(pooledMessage(messageID: "msg-1"))

        // The hit is still acked; one DELIVERED per `(message_id, status)` is what holds this.
        XCTAssertEqual(harness.reports.count, reportsAfterFirst, "a socket duplicate reported again")
        XCTAssertEqual(harness.reports(.delivered).count, 1)
        XCTAssertEqual(harness.reports(.displayed).count, 1)
        XCTAssertEqual(harness.deliveredMessageIDs, eventsAfterFirst, "one event for one delivery")
        XCTAssertEqual(presenter.posted.count, 1, "a socket duplicate posted a notification")
        XCTAssertTrue(harness.logger.contains("duplicate message msg-1; acked, no event, no notification"))
    }

    func testAHitOnAnIdAnotherProcessMarkedIsAckedDeliveredOnce() throws {
        let store = FakeSocketStateStore()
        let registry = SeenMessageRegistry(store: store)
        // An earlier launch (or the APNs handler) marked it; nobody reported it.
        XCTAssertTrue(registry.markSeen("msg-1"))
        XCTAssertEqual(store.seen, ["msg-1"])
        let presenter = FakeNotificationPresenter()
        presenter.acceptsPost = true
        let harness = makeHarness(
            configuration: testConfiguration(displayNotifications: .always),
            presenter: presenter, registry: registry)
        harness.handshake()

        harness.deliverMessage(pooledMessage(messageID: "msg-1"))

        let delivered = harness.reports(.delivered)
        XCTAssertEqual(delivered.count, 1)
        XCTAssertEqual(try XCTUnwrap(delivered.first).messageID, "msg-1")
        // Presentation is what dedupe decides: no event, no banner, no DISPLAYED.
        XCTAssertEqual(harness.deliveredMessageIDs, [])
        XCTAssertEqual(presenter.posted.count, 0)
        XCTAssertEqual(harness.reports(.displayed).count, 0)
        XCTAssertEqual(harness.client.currentPendingMessages.count, 0, "a hit is not a pending message")

        // Hit-then-hit with no Ack in between: only the tracker's "already queued" check catches the second.
        harness.deliverMessage(pooledMessage(messageID: "msg-1"))

        XCTAssertEqual(harness.reports(.delivered).count, 1, "a hit re-reported before the first Ack")
    }

    func testAMessageWithAnEmptyIdIsDroppedWithoutAReport() {
        let harness = makeReportHarness()
        harness.handshake()

        harness.deliverMessage(pooledMessage(messageID: ""))

        XCTAssertEqual(harness.reports.count, 0)
        XCTAssertEqual(harness.deliveredMessageIDs, [])
        XCTAssertTrue(harness.logger.contains("empty message_id"))
    }

    // MARK: - The bounded seen set

    func testTheSeenSetIsBoundedAtTwoThousand() {
        var seen = SeenSet()
        for index in 0..<SeenSet.capacity {
            XCTAssertTrue(seen.insert("msg-\(index)"))
        }
        XCTAssertEqual(seen.count, 2000)
        XCTAssertEqual(SeenSet.capacity, 2000)

        XCTAssertTrue(seen.insert("msg-2000"))
        XCTAssertEqual(seen.count, 2000)
        XCTAssertFalse(seen.contains("msg-0"))
        XCTAssertTrue(seen.contains("msg-2000"))
        XCTAssertEqual(seen.persisted.first, "msg-1")
    }

    func testTheEvictedMessageCanBeDeliveredAgain() {
        let harness = makeReportHarness()
        harness.handshake()

        // An evicted id is no longer deduped, so the relay may count it twice.
        for index in 0..<(SeenSet.capacity + 1) {
            harness.deliverMessage(pooledMessage(messageID: "msg-\(index)"))
        }
        XCTAssertEqual(harness.deliveredMessageIDs.count, SeenSet.capacity + 1)

        harness.deliverMessage(pooledMessage(messageID: "msg-0"))

        XCTAssertEqual(
            harness.deliveredMessageIDs.count, SeenSet.capacity + 2, "msg-0 was never evicted")
        XCTAssertEqual(harness.deliveredMessageIDs.filter { $0 == "msg-0" }.count, 2)
    }

    func testTheSeenSetSurvivesARestart() {
        let store = FakeSocketStateStore()

        let first = makeReportHarness(store: store)
        first.handshake()
        first.deliverMessage(pooledMessage(messageID: "msg-1"))
        // Answer the report so the restart is about dedupe only.
        first.ack(accepted: true, token: "msg-1:1")
        XCTAssertEqual(store.seen, ["msg-1"])
        XCTAssertEqual(store.outbox.count, 0)

        let second = makeReportHarness(store: store)
        second.handshake()
        second.deliverMessage(pooledMessage(messageID: "msg-1"))

        XCTAssertEqual(second.deliveredMessageIDs, [], "dedupe did not survive the restart")
        XCTAssertEqual(second.reports.count, 0)
        // The reported-keys set persists with the seen set, so the redelivery's ack is a no-op.
        XCTAssertTrue(second.logger.contains("suppressing duplicate delivered report for msg-1"))
    }

    // MARK: - The replay cursor

    func testTheNewestProcessedIdIsEchoedInTheNextHello() {
        let harness = makeReportHarness()
        harness.handshake()
        XCTAssertEqual(harness.hello?.lastSeenMessageID, "", "empty on a first connect")

        harness.deliverMessage(pooledMessage(messageID: "msg-1"))
        harness.deliverMessage(pooledMessage(messageID: "msg-2"))
        XCTAssertEqual(harness.store.lastSeen, "msg-2")

        harness.serverClose(reason: .shutdown)
        harness.scheduler.advance(by: 60_000)
        harness.transport.openSocket()

        XCTAssertEqual(harness.hello?.lastSeenMessageID, "msg-2")
    }
}
