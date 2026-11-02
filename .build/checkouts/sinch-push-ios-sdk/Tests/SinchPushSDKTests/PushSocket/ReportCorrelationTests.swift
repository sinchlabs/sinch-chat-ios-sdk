//  ReportCorrelationTests.swift — what a delivery report names, and how it is
//  correlated with the relay's answer.

import XCTest

@testable import SinchPushSDK

final class ReportCorrelationTests: XCTestCase {

    // MARK: - The report frame

    func testADedupeMissReportsDeliveredOnce() {
        let harness = makeReportHarness()
        harness.handshake()

        harness.deliverMessage(pooledMessage(messageID: "msg-1"))

        let delivered = harness.reports(.delivered)
        XCTAssertEqual(delivered.count, 1)
        XCTAssertEqual(delivered.first?.messageID, "msg-1")
    }

    func testAPostedNotificationReportsDisplayed() throws {
        let presenter = FakeNotificationPresenter()
        presenter.acceptsPost = true
        let harness = makeHarness(
            configuration: testConfiguration(displayNotifications: .always),
            presenter: presenter)
        harness.handshake()

        harness.deliverMessage(pooledMessage(messageID: "msg-1"))

        XCTAssertEqual(presenter.posted.map(\.id), ["msg-1"])
        XCTAssertEqual(harness.reports(.displayed).count, 1)
        let pending = try XCTUnwrap(harness.client.currentPendingMessages.first)
        XCTAssertTrue(pending.shown)
    }

    func testARefusedNotificationDoesNotReportDisplayed() {
        let presenter = FakeNotificationPresenter()
        presenter.acceptsPost = false
        let harness = makeHarness(
            configuration: testConfiguration(displayNotifications: .always),
            presenter: presenter)
        harness.handshake()

        harness.deliverMessage(pooledMessage(messageID: "msg-1"))

        XCTAssertEqual(harness.reports(.delivered).count, 1)
        XCTAssertEqual(harness.reports(.displayed).count, 0)
    }

    func testTheWhenUnhandledRuleFollowsTheHostRegistration() {
        // DELIVERED is reported either way: it is about delivery, not display.
        let presenter = FakeNotificationPresenter()
        presenter.acceptsPost = true
        let harness = makeHarness(
            configuration: testConfiguration(displayNotifications: .whenUnhandled),
            presenter: presenter)
        harness.handshake()

        harness.deliverMessage(pooledMessage(messageID: "msg-1"))
        XCTAssertEqual(presenter.posted.count, 1)

        harness.client.setHandlerRegistered(true)
        harness.deliverMessage(pooledMessage(messageID: "msg-2"))
        XCTAssertEqual(presenter.posted.map(\.id), ["msg-1"])
        XCTAssertEqual(harness.reports(.delivered).count, 2)
        XCTAssertEqual(harness.reports(.displayed).count, 1)
    }

    func testTheNeverRulePostsNothingAtAll() {
        let presenter = FakeNotificationPresenter()
        presenter.acceptsPost = true
        let harness = makeHarness(
            configuration: testConfiguration(displayNotifications: .never),
            presenter: presenter)
        harness.handshake()

        harness.deliverMessage(pooledMessage(messageID: "msg-1"))

        XCTAssertEqual(presenter.posted.count, 0)
        XCTAssertEqual(harness.reports(.displayed).count, 0)
        XCTAssertEqual(harness.reports(.delivered).count, 1)
    }

    func testADismissedReportIsSentOnceWithTheOriginalMessageId() {
        let harness = makeReportHarness()
        harness.handshake()
        harness.deliverMessage(pooledMessage(messageID: "msg-1"))
        harness.ack(accepted: true, token: "msg-1:1")

        // The pooled id is what the relay correlates on.
        harness.client.report(messageId: "msg-1", status: .dismissed)

        let dismissed = harness.reports(.dismissed)
        XCTAssertEqual(dismissed.count, 1)
        XCTAssertEqual(dismissed.first?.messageID, "msg-1")
        XCTAssertEqual(dismissed.first?.sinchMessageID, "sinch-msg-1")
    }

    func testTheSameMessageAndStatusIsNeverReportedTwice() {
        let harness = makeReportHarness()
        harness.handshake()
        harness.deliverMessage(pooledMessage(messageID: "msg-1"))

        harness.client.report(messageId: "msg-1", status: .dismissed)
        harness.client.report(messageId: "msg-1", status: .dismissed)
        harness.client.report(messageId: "msg-1", status: .dismissed)

        XCTAssertEqual(harness.reports(.dismissed).count, 1)

        harness.ack(accepted: true, token: "msg-1:4")
        harness.client.report(messageId: "msg-1", status: .dismissed)
        XCTAssertEqual(harness.reports(.dismissed).count, 1)
        XCTAssertTrue(harness.store.reported.contains("msg-1:4"))
    }

    func testDifferentStatusesForOneMessageAreBothReported() {
        let harness = makeReportHarness()
        harness.handshake()
        harness.deliverMessage(pooledMessage(messageID: "msg-1"))

        harness.client.report(messageId: "msg-1", status: .displayed)
        harness.client.report(messageId: "msg-1", status: .dismissed)

        XCTAssertEqual(harness.reports(.displayed).count, 1)
        XCTAssertEqual(harness.reports(.dismissed).count, 1)
    }

    func testAReportCarriesEveryFieldTheRelayRequires() throws {
        let harness = makeReportHarness()
        harness.handshake()
        harness.deliverMessage(pooledMessage(messageID: "msg-1"))

        let report = try XCTUnwrap(harness.reports.first)
        XCTAssertEqual(report.messageID, "msg-1")
        XCTAssertEqual(report.sinchMessageID, "sinch-msg-1")
        XCTAssertEqual(report.status, .delivered)
        XCTAssertEqual(report.reason, "")
        XCTAssertEqual(report.reportedAtUnixMillis, harness.scheduler.nowMs())
    }

    func testTheTrackersFailedReasonIsPrefixedWithDecode() {
        // Asserted on the tracker: the client cannot reach this path.
        let store = FakeSocketStateStore()
        let scheduler = ManualScheduler()
        let tracker = ReportTracker(
            store: store,
            logger: SilentSocketLogger(),
            random: ScriptedRandomSource(fixed: 0.5),
            now: { scheduler.nowMs() })

        tracker.queueFailure(messageId: "msg-7", sinchMessageId: "sinch-7", detail: "no payload")

        XCTAssertEqual(store.outbox.count, 1)
        XCTAssertEqual(store.outbox.first?.status, .failed)
        XCTAssertEqual(store.outbox.first?.reason, "decode: no payload")
    }

    func testAReportCanNeverCarryAnEmptyMessageId() {
        let store = FakeSocketStateStore()
        let tracker = ReportTracker(
            store: store,
            logger: SilentSocketLogger(),
            random: ScriptedRandomSource(fixed: 0.5),
            now: { 1 })

        tracker.queueFailure(messageId: "", sinchMessageId: "", detail: "message frame without a pooled message")

        XCTAssertEqual(store.outbox.count, 0)
        XCTAssertEqual(tracker.reportsToSend(nowMs: 1, mode: .all).count, 0)
    }

    // MARK: - The correlation token

    func testTheAckTokenIsTheNumericStatusSuffix() {
        XCTAssertEqual(SocketDeliveryStatus.delivered.tokenSuffix, "1")
        XCTAssertEqual(SocketDeliveryStatus.displayed.tokenSuffix, "2")
        XCTAssertEqual(SocketDeliveryStatus.failed.tokenSuffix, "3")
        XCTAssertEqual(SocketDeliveryStatus.dismissed.tokenSuffix, "4")
        XCTAssertEqual(
            PendingReport(
                messageId: "msg-1", sinchMessageId: "s", status: .displayed,
                reason: "", attempts: 0, deferUntilMs: nil).ackToken,
            "msg-1:2")
    }

    func testAnAckTokenThatDiffersFromTheMessageIdIsNotBranchedOn() throws {
        let harness = makeReportHarness()
        harness.handshake()

        harness.deliverMessage(pooledMessage(messageID: "msg-1"), ackToken: "an-independent-token")

        let pending = try XCTUnwrap(harness.client.currentPendingMessages.first)
        XCTAssertEqual(pending.id, "msg-1")
        XCTAssertEqual(pending.ackToken, "an-independent-token")
    }

    func testATokenForAnUnknownReportChangesNothing() {
        let harness = makeReportHarness()
        harness.handshake()
        harness.deliverMessage(pooledMessage(messageID: "msg-1"))

        harness.ack(accepted: false, error: "rate_limited", token: "msg-other:1")

        XCTAssertEqual(harness.store.outbox.count, 1, "an uncorrelated Ack changed the entry")
        XCTAssertTrue(harness.logger.contains("matches no queued report"))
    }

    func testAnEmptyTokenIsUncorrelatableRatherThanTheEmptyIdReport() {
        let harness = makeReportHarness()
        harness.handshake()
        harness.deliverMessage(pooledMessage(messageID: "msg-1"))

        harness.ack(accepted: true, token: "")

        XCTAssertEqual(harness.store.outbox.count, 1)
        XCTAssertTrue(harness.logger.contains("empty token is uncorrelatable"))
    }

    func testTheReportedIdIsTheChannelMessageIdAndNothingElse() throws {
        let harness = makeReportHarness()
        harness.handshake()
        harness.deliverMessage(pooledMessage(messageID: "msg-1"))

        let report = try XCTUnwrap(harness.reports.first)
        // Four facts, not one equality: a lone `== pooled.id` passes on a value that was never correlated.
        XCTAssertFalse(report.messageID.isEmpty)
        XCTAssertEqual(report.messageID, "msg-1")
        XCTAssertNotEqual(report.messageID, report.sinchMessageID)
        XCTAssertNotEqual(report.messageID, "msg-1:1")
        XCTAssertNotEqual(report.messageID, harness.hello?.authToken)
    }

    func testAMessageFrameWithNoPooledMessageIsNotSilentlyDropped() {
        let harness = makeReportHarness()
        harness.handshake()

        var empty = Sinch_Push_Delivery_V1beta1_Ws_Message()
        empty.ackToken = "ack-only"
        harness.transport.deliver(makeServerFrame(empty))

        XCTAssertTrue(harness.logger.contains("message frame without a pooled message"))
        XCTAssertEqual(harness.reports.count, 0, "a report with an empty message_id was sent")
        XCTAssertEqual(harness.deliveredMessageIDs, [])
        XCTAssertEqual(harness.recorder.current?.status, .connected)
        XCTAssertEqual(harness.socketCount, 1)
    }

    // MARK: - The message a report names

    func testAnExplicitlyEmptyAlertFieldIsAbsentRatherThanEmpty() throws {
        let harness = makeReportHarness()
        harness.handshake()

        harness.deliverMessage(blankPooledMessage(messageID: "msg-1"))

        let pending = try XCTUnwrap(harness.client.currentPendingMessages.first)
        // proto3 cannot tell never-set from empty; the display layer then renders the app label.
        XCTAssertNil(pending.title)
        XCTAssertNil(pending.body)
        XCTAssertNil(pending.imageUrl)
        XCTAssertNil(pending.trigger)
    }

    func testAPopulatedAlertArrivesIntact() throws {
        let harness = makeReportHarness()
        harness.handshake()

        harness.deliverMessage(pooledMessage(messageID: "msg-1"))

        let pending = try XCTUnwrap(harness.client.currentPendingMessages.first)
        XCTAssertEqual(pending.title, "Grüße 🎉")
        XCTAssertEqual(pending.body, "body ✓")
        XCTAssertEqual(pending.imageUrl, "https://example.test/i.png")
        XCTAssertEqual(pending.trigger, "push")
        XCTAssertEqual(pending.metadata, ["campaign": "spring", "locale": "de-DE"])
    }
}
