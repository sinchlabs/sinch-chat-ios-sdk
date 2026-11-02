//  ProtocolFrameTests.swift — inbound frames the client must survive: Ping,
//  AuthChallenge, and unreadable frames. Bad frames are hand-built (see WireTestSupport).

import XCTest

@testable import SinchPushSDK

final class ProtocolFrameTests: XCTestCase {

    private func harness() -> SocketHarness {
        makeHarness(configuration: testConfiguration(displayNotifications: .never))
    }

    // MARK: - Ping

    func testAPingIsAnsweredWithAPongThatEchoesTheCorrelationId() {
        let harness = self.harness()
        harness.handshake()

        var ping = Sinch_Push_Delivery_V1beta1_Ws_Ping()
        ping.correlationID = "corr-7"
        harness.transport.deliver(makeServerFrame(ping))

        XCTAssertEqual(harness.pongs.count, 1)
        XCTAssertEqual(harness.pongs.first?.correlationID, "corr-7")
    }

    func testAPingDoesNotDisturbThePollTimerOrTheBudget() {
        let harness = self.harness()
        harness.handshake()
        let pollsBefore = harness.polls.count
        let timersBefore = harness.pendingTimers

        var ping = Sinch_Push_Delivery_V1beta1_Ws_Ping()
        ping.correlationID = "corr-1"
        harness.transport.deliver(makeServerFrame(ping))

        XCTAssertEqual(harness.polls.count, pollsBefore)
        XCTAssertEqual(harness.pendingTimers, timersBefore)
        XCTAssertEqual(harness.client.backoffState.attempts, 0)

        harness.scheduler.advance(by: 5_000)
        XCTAssertEqual(harness.polls.count, pollsBefore + 1)
    }

    func testAPingWithNoCorrelationIdIsStillAnswered() {
        let harness = self.harness()
        harness.handshake()

        harness.transport.deliver(makeServerFrame(Sinch_Push_Delivery_V1beta1_Ws_Ping()))

        XCTAssertEqual(harness.pongs.count, 1)
        XCTAssertEqual(harness.pongs.first?.correlationID, "")
    }

    // MARK: - Auth challenge

    func testAnAuthChallengeKeepsTheConnectionAndIsLogged() {
        let harness = self.harness()
        harness.handshake()

        var challenge = Sinch_Push_Delivery_V1beta1_Ws_AuthChallenge()
        challenge.nonce = "nonce-1"
        harness.transport.deliver(makeServerFrame(challenge))

        // Reserved: neither closes nor reconnects.
        XCTAssertEqual(harness.recorder.current?.status, .connected)
        XCTAssertEqual(harness.socketCount, 1)
        XCTAssertTrue(harness.logger.contains("auth challenge"))
        XCTAssertFalse(harness.logger.contains("unknown frame tag"))
    }

    func testAnUnexpectedPongIsIgnoredWithoutAReply() {
        let harness = self.harness()
        harness.handshake()
        let frames = harness.sentFrames.count

        var pong = Sinch_Push_Delivery_V1beta1_Ws_Pong()
        pong.correlationID = "corr-stray"
        harness.transport.deliver(makeServerFrame(pong))

        XCTAssertEqual(harness.sentFrames.count, frames)
        XCTAssertEqual(harness.recorder.current?.status, .connected)
    }

    // MARK: - Malformed and unknown frames

    func testAnUnknownTagIsLoggedAndIgnored() {
        let harness = self.harness()
        harness.handshake()

        // A valid envelope tag with no payload in this build: the peer is a version ahead.
        harness.transport.deliverRaw(Wire.envelope(tag: 200, payload: [0x01, 0x02]))

        XCTAssertTrue(harness.logger.contains("unknown frame tag 200"))
        XCTAssertEqual(harness.recorder.current?.status, .connected)
        XCTAssertEqual(harness.socketCount, 1)
    }

    func testAMalformedEnvelopeIsLoggedSeparatelyAndSurvives() {
        let harness = self.harness()
        harness.handshake()

        // Too short for a tag and a length.
        harness.transport.deliverRaw([0x01])
        // Declared length longer than the body.
        harness.transport.deliverRaw(Wire.frameDeclaring(tag: 2, declared: 64, bodyBytes: 3))

        XCTAssertTrue(harness.logger.contains("malformed server frame"))
        XCTAssertFalse(
            harness.logger.contains("unknown frame tag"),
            "a malformed envelope was logged as an unknown tag")
        XCTAssertEqual(harness.recorder.current?.status, .connected)
        XCTAssertEqual(harness.socketCount, 1)
    }

    func testTheTwoFrameFailuresAreDistinguishableLines() {
        let harness = self.harness()
        harness.handshake()

        harness.transport.deliverRaw(Wire.envelope(tag: 200, payload: []))
        harness.transport.deliverRaw([0x01])

        let unknown = harness.logger.lines.filter { $0.contains("unknown frame tag 200") }
        let malformed = harness.logger.lines.filter { $0.contains("malformed server frame") }
        XCTAssertEqual(unknown.count, 1)
        XCTAssertEqual(malformed.count, 1)
        XCTAssertNotEqual(unknown.first, malformed.first)
    }

    func testABadFrameDoesNotStopTheClientFromCarryingOn() {
        let harness = self.harness()
        harness.handshake()

        harness.transport.deliverRaw(Wire.envelope(tag: 200, payload: []))
        harness.deliverMessage(pooledMessage(messageID: "msg-after-garbage"))

        XCTAssertEqual(harness.deliveredMessageIDs, ["msg-after-garbage"])
        XCTAssertEqual(harness.reports(.delivered).count, 1)
    }
}
