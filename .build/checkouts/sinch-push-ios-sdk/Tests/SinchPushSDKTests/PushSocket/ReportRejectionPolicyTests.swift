//  ReportRejectionPolicyTests.swift — what the relay's refusal changes.

import XCTest

@testable import SinchPushSDK

final class ReportRejectionPolicyTests: XCTestCase {

    // MARK: - Report rejection policy

    func testRateLimitedDefersTheReportInsteadOfRetryingOnThePoll() {
        let harness = makeReportHarness()
        harness.handshake()
        harness.deliverMessage(pooledMessage(messageID: "msg-1"))
        XCTAssertEqual(harness.reports.count, 1)

        harness.ack(accepted: false, error: "rate_limited", token: "msg-1:1")

        XCTAssertEqual(
            harness.store.outbox.first?.deferUntilMs, harness.scheduler.nowMs() + 500)
        XCTAssertEqual(harness.recorder.current?.lastError, "rate_limited")
        XCTAssertEqual(harness.recorder.current?.status, .connected)
    }

    func testADeferralIsRetriedOnItsOwnTimerNotOnThePoll() {
        let harness = makeReportHarness()
        harness.handshake()
        harness.deliverMessage(pooledMessage(messageID: "msg-1"))
        harness.ack(accepted: false, error: "rate_limited", token: "msg-1:1")

        harness.scheduler.advance(by: 499)
        XCTAssertEqual(harness.reports.count, 1)

        // Only the one-shot deferral timer retries a rate-limited report.
        harness.scheduler.advance(by: 1)
        XCTAssertEqual(harness.reports.count, 2)

        harness.scheduler.advance(by: 20_000)
        XCTAssertEqual(harness.reports.count, 2)
        XCTAssertGreaterThan(harness.polls.count, 2, "the poll timer kept running")
    }

    func testAPollTickDoesNotRetryADeferredReport() {
        // A 1 s poll interval and a deferral that outlasts it put a poll tick inside the deferral.
        let presenter = FakeNotificationPresenter()
        presenter.acceptsPost = false
        let harness = makeHarness(
            configuration: testConfiguration(
                pollIntervalMs: 1000, displayNotifications: .always),
            random: 0.999,
            presenter: presenter)
        harness.handshake()

        harness.deliverMessage(pooledMessage(messageID: "msg-1"))
        // First refusal: deferred by floor(0.999 · 1000) = 999 ms.
        harness.ack(accepted: false, error: "rate_limited", token: "msg-1:1")
        harness.scheduler.advance(by: 999)
        XCTAssertEqual(harness.reports.count, 2, "the first deferral was never retried")

        // Second refusal: 1998 ms, longer than the poll interval.
        harness.ack(accepted: false, error: "rate_limited", token: "msg-1:1")
        harness.scheduler.advance(by: 1_000)

        XCTAssertEqual(harness.polls.count, 2, "a poll tick happened inside the deferral")
        XCTAssertEqual(
            harness.reports.count, 2, "the poll tick retried a deferred report")

        harness.scheduler.advance(by: 2_000)
        XCTAssertEqual(harness.reports.count, 3)
    }

    func testAForwardFailureRetriesOnThePollTickUpToThreeTimes() {
        let harness = makeReportHarness()
        harness.handshake()
        harness.deliverMessage(pooledMessage(messageID: "msg-1"))

        // Three retries, then the entry is dropped with a log line.
        for attempt in 1...3 {
            harness.ack(accepted: false, error: "upstream_forward_failed", token: "msg-1:1")
            harness.scheduler.advance(by: 5_000)
            XCTAssertEqual(harness.reports.count, attempt + 1, "retry \(attempt)")
        }

        harness.ack(accepted: false, error: "upstream_forward_failed", token: "msg-1:1")
        XCTAssertEqual(harness.store.outbox.count, 0)
        XCTAssertTrue(harness.logger.contains("after 4 forward failures"))

        harness.scheduler.advance(by: 20_000)
        XCTAssertEqual(harness.reports.count, 4, "a dropped entry is not retried again")
    }

    func testAnUnsupportedStatusIsDroppedPermanently() {
        let harness = makeReportHarness()
        harness.handshake()
        harness.deliverMessage(pooledMessage(messageID: "msg-1"))

        harness.ack(accepted: false, error: "unsupported_status", token: "msg-1:1")

        XCTAssertEqual(harness.store.outbox.count, 0)
        XCTAssertEqual(harness.recorder.current?.lastError, "unsupported_status")
        XCTAssertTrue(harness.logger.contains("does not support this status"))

        harness.scheduler.advance(by: 20_000)
        XCTAssertEqual(harness.reports.count, 1)
    }

    func testAnUnrecognisedErrorIsLoggedAndChangesNoEntry() {
        for error in ["", "some_future_code"] {
            let harness = makeReportHarness()
            harness.handshake()
            harness.deliverMessage(pooledMessage(messageID: "msg-1"))

            harness.ack(accepted: false, error: error, token: "msg-1:1")

            XCTAssertEqual(harness.store.outbox.count, 1, "for '\(error)'")
            XCTAssertTrue(harness.logger.contains("ack refused with error '\(error)'"))
            XCTAssertEqual(
                harness.store.outbox.first?.attempts, 0,
                "a retry counter moved on an unknown error")
        }
    }

    func testEveryRejectionSetsLastError() {
        for error in ["rate_limited", "upstream_forward_failed", "unsupported_status", ""] {
            let harness = makeReportHarness()
            harness.handshake()
            harness.deliverMessage(pooledMessage(messageID: "msg-1"))
            XCTAssertNil(harness.recorder.current?.lastError, "precondition for '\(error)'")

            harness.ack(accepted: false, error: error, token: "msg-1:1")

            XCTAssertNotNil(
                harness.recorder.current?.lastError,
                "a rejection of '\(error)' left lastError unset")
        }
    }

    // MARK: - Accepted

    func testAnAcceptedAckIsLoggedAsAccepted() {
        let harness = makeReportHarness()
        harness.handshake()
        harness.deliverMessage(pooledMessage(messageID: "msg-1"))

        harness.ack(accepted: true, token: "msg-1:1")

        XCTAssertTrue(harness.logger.contains("ack accepted=true"))
        XCTAssertEqual(harness.store.outbox.count, 0, "an accepted report leaves the outbox")
        XCTAssertTrue(harness.store.reported.contains("msg-1:1"))
    }

    // MARK: - The close path

    func testACloseWithoutADetailIsAbsentNotEmpty() {
        // An empty `detail` becomes `server closed (reason=n)`, not a lastError of `""`.
        let harness = makeReportHarness()
        harness.handshake()
        harness.serverClose(reason: .shutdown)

        XCTAssertEqual(
            harness.recorder.current?.lastError, "server closed (reason=6)")
        XCTAssertNotEqual(harness.recorder.current?.lastError, "")
    }
}
