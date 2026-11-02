import XCTest

@testable import SinchPushSDK

final class CloseReconnectTests: XCTestCase {

    // MARK: - Retryable close reasons

    func testPoolFullIsRetryablePressureNotTerminal() {
        let harness = makeHarness()
        harness.handshake()

        harness.serverClose(reason: .poolFull, detail: "rate_limited")

        XCTAssertEqual(harness.recorder.current?.status, .reconnecting)
        XCTAssertEqual(harness.recorder.current?.reconnectAttempts, 1)
        XCTAssertEqual(harness.recorder.current?.lastError, "rate_limited")
        XCTAssertFalse(harness.published(.stopped))
        XCTAssertFalse(harness.published(.error))
    }

    func testShutdownInternalAndUnspecifiedAreAllJustRetryablePressure() {
        let retryable: [Sinch_Push_Delivery_V1beta1_Ws_CloseReason] = [
            .poolFull, .shutdown, .internal, .unspecified
        ]

        for reason in retryable {
            let harness = makeHarness()
            harness.handshake()
            harness.serverClose(reason: reason, detail: "whatever")

            XCTAssertEqual(
                harness.recorder.current?.status, .reconnecting,
                "reason \(reason.rawValue) should be retryable")
            XCTAssertEqual(harness.recorder.current?.reconnectAttempts, 1)

            harness.scheduler.advance(by: 500)
            XCTAssertEqual(harness.socketCount, 2, "reason \(reason.rawValue) should reconnect")
        }
    }

    func testAPoolFullCloseIsIndistinguishableFromOtherPressure() {
        let withDetail = makeHarness()
        withDetail.handshake()
        withDetail.serverClose(reason: .poolFull, detail: "rate_limited")
        let pooledState = withDetail.recorder.current

        let withOtherDetail = makeHarness()
        withOtherDetail.handshake()
        withOtherDetail.serverClose(reason: .poolFull, detail: "renamed_by_the_relay")
        let renamedState = withOtherDetail.recorder.current

        XCTAssertEqual(pooledState?.status, renamedState?.status)
        XCTAssertEqual(pooledState?.reconnectAttempts, renamedState?.reconnectAttempts)
        XCTAssertEqual(withOtherDetail.scheduler.pendingDelays, withDetail.scheduler.pendingDelays)
    }

    // MARK: - Retry delay

    func testAShedDoesNotRedialInTheSameTick() {
        let harness = makeHarness()
        harness.handshake()

        harness.serverClose(reason: .poolFull, detail: "rate_limited")
        XCTAssertEqual(harness.socketCount, 1)

        harness.scheduler.advance(by: 0)
        XCTAssertEqual(harness.socketCount, 1)
        XCTAssertEqual(harness.scheduler.pendingDelays, [500])

        harness.scheduler.advance(by: 500)
        XCTAssertEqual(harness.socketCount, 2)
    }

    // MARK: - Stale session

    func testStaleReconnectsImmediatelyWithNoTimerAtAll() {
        let harness = makeHarness()
        harness.handshake()

        harness.serverClose(reason: .stale, detail: "session expired")

        XCTAssertEqual(harness.socketCount, 2)
        XCTAssertEqual(harness.pendingTimers, 0)
        XCTAssertTrue(harness.logger.contains("session stale"))
    }

    func testStaleResetsTheBackoffBudget() {
        let harness = makeHarness()

        for _ in 0..<3 {
            harness.handshake()
            harness.serverClose(reason: .poolFull, detail: "rate_limited")
            harness.scheduler.advance(by: 60_000)
        }
        XCTAssertEqual(harness.client.backoffState.attempts, 3)

        harness.handshake()
        harness.serverClose(reason: .stale)
        XCTAssertEqual(harness.client.backoffState.attempts, 0)

        harness.handshake(connectionID: "conn-after-stale")
        harness.serverClose(reason: .internal)

        XCTAssertEqual(harness.client.backoffState.attempts, 1)
        XCTAssertEqual(harness.recorder.current?.reconnectAttempts, 1)
    }

    // MARK: - Unauthorized close

    func testUnauthorizedIsTerminal() {
        let harness = makeHarness()
        harness.handshake()

        harness.serverClose(reason: .unauthorized, detail: "bad token")

        XCTAssertEqual(harness.recorder.current?.status, .authRequired)
        XCTAssertEqual(harness.recorder.current?.lastError, "bad token")

        let sockets = harness.socketCount
        harness.advanceToNoFutureTimer()
        XCTAssertEqual(harness.socketCount, sockets, "an unauthorized close must not reconnect")
        XCTAssertEqual(harness.pendingTimers, 0)
    }

    func testUnauthorizedWithoutADetailStillNamesTheReason() {
        let harness = makeHarness()
        harness.handshake()

        harness.serverClose(reason: .unauthorized)

        XCTAssertEqual(
            harness.recorder.current?.lastError,
            "server closed (reason=\(Sinch_Push_Delivery_V1beta1_Ws_CloseReason.unauthorized.rawValue))")
    }

    func testTheHostIsAskedToRefreshTheCredentialExactlyOnce() throws {
        let harness = makeHarness()
        harness.handshake()

        harness.serverClose(reason: .unauthorized, detail: "expired")

        XCTAssertEqual(harness.recorder.authRequiredCount, 1)
        XCTAssertEqual(harness.recorder.current?.status, .authRequired)
    }

    func testARefreshedCredentialIsTheOnlyWayBack() {
        let harness = makeHarness()
        harness.handshake()
        harness.serverClose(reason: .unauthorized, detail: "expired")
        let sockets = harness.socketCount

        harness.client.updateConfiguration(testConfiguration(authToken: "fresh.token.value"))
        XCTAssertEqual(harness.socketCount, sockets + 1)

        harness.transport.openSocket()
        XCTAssertEqual(harness.hello?.authToken, "fresh.token.value")
        XCTAssertNil(harness.recorder.current?.lastError)
    }

    // MARK: - Background resumed

    func testBackgroundResumedStopsWithoutFightingTheOtherSurface() {
        let harness = makeHarness()
        harness.handshake()

        harness.serverClose(reason: .bgResumed)

        XCTAssertEqual(harness.recorder.current?.status, .replaced)

        let sockets = harness.socketCount
        harness.advanceToNoFutureTimer()
        XCTAssertEqual(harness.socketCount, sockets, "the other surface owns the session")
        XCTAssertEqual(harness.pendingTimers, 0)
    }

    // MARK: - Transport failure before connect

    func testATransportFailureBeforeTheSocketEverOpenedIsRetryable() {
        let harness = makeHarness()
        XCTAssertEqual(harness.socketCount, 1)
        XCTAssertFalse(harness.transport.isOpen)

        harness.transport.failTransport(code: 1006)

        XCTAssertEqual(harness.recorder.current?.status, .reconnecting)
        XCTAssertEqual(harness.recorder.current?.reconnectAttempts, 1)

        XCTAssertEqual(harness.scheduler.pendingDelays, [500])
        harness.scheduler.advance(by: 500)
        XCTAssertEqual(harness.socketCount, 2)
    }

    // MARK: - Idempotent reconnects

    func testOneDisconnectSchedulesExactlyOneReconnect() {
        let harness = makeHarness()

        for round in 1...3 {
            harness.handshake()
            harness.serverClose(reason: .shutdown)

            XCTAssertEqual(harness.pendingTimers, 1, "round \(round) stacked timers")
            XCTAssertEqual(harness.client.backoffState.attempts, 1, "round \(round) double-counted")

            let before = harness.socketCount
            harness.scheduler.advance(by: 30_000)
            XCTAssertEqual(harness.socketCount, before + 1, "one timer, one socket (round \(round))")
        }
    }

    func testAReplacedSocketCannotDriveASecondReconnect() {
        let harness = makeHarness()
        harness.handshake()
        let replaced = harness.transport

        harness.transport.failTransport(code: 1006)
        harness.scheduler.advance(by: 500)
        harness.handshake(connectionID: "conn-2")
        XCTAssertEqual(harness.socketCount, 2)

        let sockets = harness.socketCount
        let states = harness.recorder.statuses.count

        replaced.replayRetainedClose()

        XCTAssertEqual(harness.socketCount, sockets)
        XCTAssertEqual(harness.recorder.statuses.count, states, "a replaced socket must be inert")
        XCTAssertEqual(harness.client.backoffState.attempts, 0)
    }

    func testAReplacedSocketCannotDeliverAMessageEither() {
        let harness = makeHarness(configuration: testConfiguration(displayNotifications: .never))
        harness.handshake()
        let replaced = harness.transport

        harness.transport.failTransport(code: 1006)
        harness.scheduler.advance(by: 500)
        harness.handshake(connectionID: "conn-2")

        replaced.replayRetainedBinary(
            makeServerFrame(.message(messageFrame(pooled: pooledMessage(messageID: "msg-ghost")))))

        XCTAssertEqual(harness.deliveredMessageIDs, [], "a replaced socket must not deliver")
    }

    // MARK: - Shutdown does not latch

    func testShutdownRetriesIntoAFreshSessionWithoutLatching() {
        let harness = makeHarness()
        harness.handshake(connectionID: "conn-1")

        harness.serverClose(reason: .shutdown)

        XCTAssertFalse(harness.published(.stopped))
        XCTAssertFalse(harness.published(.error))
        XCTAssertFalse(harness.published(.authRequired))
        XCTAssertFalse(harness.published(.replaced))

        harness.scheduler.advance(by: 500)
        harness.handshake(connectionID: "conn-2")

        XCTAssertEqual(harness.recorder.current?.status, .connected)
        XCTAssertEqual(harness.recorder.current?.connectionId, "conn-2")
    }

    // MARK: - Timers

    func testTerminalTransitionsLeaveNoTimerBehind() {
        let terminal: [(String, Sinch_Push_Delivery_V1beta1_Ws_CloseReason)] = [
            ("UNAUTHORIZED", .unauthorized), ("BG_RESUMED", .bgResumed)
        ]

        for (name, reason) in terminal {
            let harness = makeHarness()
            harness.handshake()
            XCTAssertEqual(harness.pendingTimers, 1, "\(name): a connected client polls")

            harness.serverClose(reason: reason)

            XCTAssertEqual(harness.pendingTimers, 0, "\(name) left a timer behind")
        }

        let stale = makeHarness()
        stale.handshake()
        stale.serverClose(reason: .stale)
        XCTAssertEqual(stale.pendingTimers, 0, "STALE left a timer behind")
        XCTAssertEqual(stale.socketCount, 2)
    }

    func testAStoppedClientCannotBeRevivedByAClock() {
        let harness = makeHarness()
        harness.handshake()

        harness.client.stop()

        XCTAssertEqual(harness.recorder.current?.status, .stopped)
        XCTAssertEqual(harness.pendingTimers, 0)
        let sockets = harness.socketCount
        harness.advanceToNoFutureTimer()
        XCTAssertEqual(harness.socketCount, sockets)
    }

    func testStopCancelsAPendingReconnect() {
        let harness = makeHarness()
        harness.handshake()
        harness.transport.failTransport(code: 1006)
        XCTAssertEqual(harness.pendingTimers, 1, "a reconnect is pending")

        harness.client.stop()

        XCTAssertEqual(harness.pendingTimers, 0)
        let sockets = harness.socketCount
        harness.scheduler.advance(by: 60_000)
        XCTAssertEqual(harness.socketCount, sockets)
    }

    // MARK: - Stop vs. start

    func testStartAfterStopReconnects() {
        let harness = makeHarness()
        harness.handshake()
        harness.client.stop()
        let sockets = harness.socketCount

        harness.client.start()

        XCTAssertEqual(harness.socketCount, sockets + 1)
        XCTAssertEqual(harness.recorder.statuses.last, .connecting)
    }
}

// MARK: - Helpers

private func messageFrame(
    pooled: Sinch_Push_Delivery_V1beta1_Ws_PooledMessage
) -> Sinch_Push_Delivery_V1beta1_Ws_Message {
    var message = Sinch_Push_Delivery_V1beta1_Ws_Message()
    message.message = pooled
    return message
}