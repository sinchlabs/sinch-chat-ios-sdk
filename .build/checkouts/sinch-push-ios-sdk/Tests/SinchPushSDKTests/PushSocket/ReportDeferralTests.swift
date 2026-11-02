//  ReportDeferralTests.swift — a `rate_limited` deferral that is already due.

import XCTest

@testable import SinchPushSDK

final class ReportDeferralTests: XCTestCase {

    func testADeferralDrawnAsZeroIsRetriedWithoutAnyNewTraffic() {
        let harness = makeReportHarness(draw: 0)
        harness.handshake()
        harness.deliverMessage(pooledMessage(messageID: "msg-1"))
        XCTAssertEqual(harness.reports.count, 1)

        harness.ack(accepted: false, error: "rate_limited", token: "msg-1:1")
        harness.scheduler.advance(by: 0)

        XCTAssertEqual(harness.reports.count, 2, "a due deferral was never retried")
        XCTAssertEqual(harness.reports.last?.messageID, "msg-1")
    }

    func testADueDeferralIsRetriedWhenAnotherAckRearmsTheTimer() {
        let harness = makeReportHarness(draw: 0)
        harness.handshake()
        harness.deliverMessage(pooledMessage(messageID: "msg-1"))
        harness.deliverMessage(pooledMessage(messageID: "msg-2"))
        XCTAssertEqual(harness.reports.count, 2)

        // msg-1's deadline is already due when the Ack for msg-2 re-arms the timer.
        harness.ack(accepted: false, error: "rate_limited", token: "msg-1:1")
        harness.ack(accepted: true, token: "msg-2:1")
        harness.scheduler.advance(by: 0)

        XCTAssertEqual(
            harness.reports.filter { $0.messageID == "msg-1" }.count, 2,
            "the first deferral was lost when the second Ack re-armed the timer")
    }

    func testADueDeferralWhileDisconnectedArmsNoZeroDelayTimer() {
        let harness = makeReportHarness(draw: 0.5)
        harness.handshake()
        harness.deliverMessage(pooledMessage(messageID: "msg-1"))
        harness.ack(accepted: false, error: "rate_limited", token: "msg-1:1")

        harness.transport.failTransport(code: 1006)
        // A due deferral must not arm a timer that re-fires at zero.
        harness.scheduler.advance(by: 60_000)
        XCTAssertLessThanOrEqual(harness.pendingTimers, 1)

        harness.handshake(connectionID: "conn-2")
        XCTAssertEqual(harness.reports.count, 1)
        XCTAssertEqual(harness.reports.first?.messageID, "msg-1")
    }
}
