import XCTest

@testable import SinchPushSDK

final class BackoffTests: XCTestCase {

    private static let nearTop = 0.9999

    // MARK: - Full jitter

    func testEverySampleStaysInsideTheWindow() {
        for attempts in 1...12 {
            let ceiling = min(30_000, 1000 * (1 << (attempts - 1)))
            for _ in 0..<1000 {
                let delay = ReconnectBackoff.delayMs(attempts: attempts, using: SystemRandomSource())
                XCTAssertGreaterThanOrEqual(delay, 0, "attempt \(attempts)")
                XCTAssertLessThanOrEqual(delay, ceiling, "attempt \(attempts)")
            }
        }
    }

    func testTheDistributionSpreadsInsteadOfClustering() {
        let ceiling = min(30_000, 1000 * (1 << 5))  // attempt 6
        var delays: [Int] = []
        for _ in 0..<1000 {
            delays.append(ReconnectBackoff.delayMs(attempts: 6, using: SystemRandomSource()))
        }

        let highest = delays.max() ?? 0
        XCTAssertGreaterThan(
            highest, ceiling / 2,
            "full jitter should occupy a healthy share of the window")
        let inFirstTenth = delays.filter { $0 < ceiling / 10 }.count
        XCTAssertLessThan(
            inFirstTenth, delays.count / 4,
            "too many samples piled into the first tenth of the window")
    }

    func testTheCapIsThirtySecondsHoweverManyAttemptsFailed() {
        for attempts in [1, 6, 12, 50, 1_000] {
            for _ in 0..<100 {
                let delay = ReconnectBackoff.delayMs(attempts: attempts, using: SystemRandomSource())
                XCTAssertLessThanOrEqual(delay, 30_000)
            }
        }
        XCTAssertEqual(ReconnectBackoff.ceilingMs(attempts: 5), 16_000)
        XCTAssertEqual(ReconnectBackoff.ceilingMs(attempts: 6), 30_000)
        XCTAssertEqual(ReconnectBackoff.ceilingMs(attempts: 1_000), 30_000)
    }

    func testANonPositiveAttemptCountClampsToTheBaseWindow() {
        XCTAssertEqual(ReconnectBackoff.ceilingMs(attempts: 0), 1000)
        XCTAssertEqual(ReconnectBackoff.ceilingMs(attempts: -5), 1000)
    }

    // MARK: - Handshake reset

    func testHelloAckZeroesTheBudgetAndArmsTheReset() {
        let harness = makeHarness(random: BackoffTests.nearTop)

        // The relay completes `HelloAck` before it spends the handshake budget, so the
        // reset has to be earned again; budget denials are what accumulate attempts.
        for _ in 0..<3 {
            harness.handshake()
            harness.serverClose(reason: .poolFull, detail: "rate_limited")
            harness.scheduler.advance(by: 60_000)
        }
        XCTAssertEqual(harness.client.backoffState.attempts, 3)

        harness.handshake()

        XCTAssertEqual(harness.client.backoffState.attempts, 0)
        XCTAssertEqual(harness.recorder.current?.reconnectAttempts, 0)
        XCTAssertTrue(harness.client.backoffState.resetArmed)
    }

    func testAHealthySessionStillStartsFromAttemptOne() {
        let harness = makeHarness()
        var attemptsPerDrop: [Int] = []

        for _ in 0..<4 {
            harness.handshake()
            harness.serverClose(reason: .shutdown)
            attemptsPerDrop.append(harness.client.backoffState.attempts)
            harness.scheduler.advance(by: 60_000)
        }

        XCTAssertEqual(attemptsPerDrop, [1, 1, 1, 1])
    }

    // MARK: - Capacity rejection

    func testABudgetDenialEscalatesInsteadOfRestartingAtAttemptOne() {
        let harness = makeHarness()
        var attemptsPerDenial: [Int] = []

        for _ in 0..<6 {
            harness.handshake()
            harness.serverClose(reason: .poolFull, detail: "rate_limited")
            attemptsPerDenial.append(harness.client.backoffState.attempts)
            harness.scheduler.advance(by: 60_000)
        }

        XCTAssertEqual(attemptsPerDenial, [1, 2, 3, 4, 5, 6])
    }

    func testSustainedRefusalReachesTheThirtySecondCap() {
        let harness = makeHarness(random: BackoffTests.nearTop)

        for _ in 0..<8 {
            harness.handshake()
            harness.serverClose(reason: .poolFull, detail: "rate_limited")
            harness.scheduler.advance(by: 60_000)
        }
        XCTAssertEqual(harness.client.backoffState.attempts, 8)

        let before = harness.socketCount
        harness.handshake()
        harness.serverClose(reason: .poolFull, detail: "rate_limited")
        XCTAssertEqual(harness.client.backoffState.attempts, 9)

        // Attempt 9 hits the 30 s cap; the pinned draw puts the delay at 29997 ms.
        harness.scheduler.advance(by: 29_900)
        XCTAssertEqual(harness.socketCount, before, "reconnected before the cap expired")
        harness.scheduler.advance(by: 200)
        XCTAssertEqual(harness.socketCount, before + 1)
    }

    func testTheForfeitIsKeyedOnTheReasonNotTheDetail() {
        let renamed = makeHarness()
        var attempts: [Int] = []
        for _ in 0..<3 {
            renamed.handshake()
            renamed.serverClose(reason: .poolFull, detail: "shed_by_a_newer_relay")
            attempts.append(renamed.client.backoffState.attempts)
            renamed.scheduler.advance(by: 60_000)
        }
        XCTAssertEqual(attempts, [1, 2, 3], "the forfeit must not depend on the detail text")

        let notShed = makeHarness()
        notShed.handshake()
        notShed.serverClose(reason: .shutdown, detail: "rate_limited")
        XCTAssertEqual(notShed.client.backoffState.attempts, 1)
    }

    // MARK: - Healthy session

    func testAPooledMessageSpendsTheReset() {
        let harness = makeHarness(configuration: testConfiguration(displayNotifications: .never))
        escalateTo(harness, denials: 3)
        XCTAssertEqual(harness.client.backoffState.attempts, 3)

        harness.handshake()
        XCTAssertTrue(harness.client.backoffState.resetArmed)
        harness.deliverMessage(pooledMessage(messageID: "msg-work"))
        XCTAssertFalse(harness.client.backoffState.resetArmed)

        harness.serverClose(reason: .poolFull, detail: "rate_limited")

        XCTAssertEqual(harness.client.backoffState.attempts, 1)
    }

    func testAnAcceptedReportSpendsTheReset() {
        let harness = makeHarness(configuration: testConfiguration(displayNotifications: .never))
        escalateTo(harness, denials: 3)

        harness.handshake()
        harness.client.report(messageId: "msg-9", status: .displayed)
        harness.ack(accepted: true, token: "msg-9:2")
        XCTAssertFalse(harness.client.backoffState.resetArmed)

        harness.serverClose(reason: .poolFull, detail: "rate_limited")

        XCTAssertEqual(harness.client.backoffState.attempts, 1)
    }

    func testABarePollDoesNotSpendTheReset() {
        let harness = makeHarness(configuration: testConfiguration(displayNotifications: .never))
        escalateTo(harness, denials: 3)

        harness.handshake()
        XCTAssertTrue(harness.client.backoffState.resetArmed)

        let pollsBefore = harness.polls.count
        harness.scheduler.advance(by: 5_000)
        XCTAssertGreaterThan(harness.polls.count, pollsBefore)
        XCTAssertTrue(harness.client.backoffState.resetArmed)

        harness.serverClose(reason: .poolFull, detail: "rate_limited")

        XCTAssertEqual(harness.client.backoffState.attempts, 4, "an unspent reset is forfeited")
    }

    func testARejectedReportDoesNotSpendTheReset() {
        for error in ["rate_limited", "upstream_forward_failed"] {
            let harness = makeHarness(configuration: testConfiguration(displayNotifications: .never))
            escalateTo(harness, denials: 3)
            XCTAssertEqual(harness.client.backoffState.attempts, 3, "precondition for \(error)")

            harness.handshake()
            harness.client.report(messageId: "msg-9", status: .displayed)
            harness.ack(accepted: false, error: error, token: "msg-9:2")
            XCTAssertTrue(
                harness.client.backoffState.resetArmed,
                "a rejection spent the reset (\(error))")

            harness.serverClose(reason: .poolFull, detail: "rate_limited")

            XCTAssertEqual(harness.client.backoffState.attempts, 4, "for \(error)")
        }
    }
}

// MARK: - Helpers

private func escalateTo(_ harness: SocketHarness, denials: Int) {
    for _ in 0..<denials {
        harness.handshake()
        harness.serverClose(reason: .poolFull, detail: "rate_limited")
        harness.scheduler.advance(by: 60_000)
    }
}