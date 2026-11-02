//  FrameCodecTests.swift
//
//  Builds malformed envelopes independently of FrameCodec (see WireTestSupport.swift).

import XCTest

@testable import SinchPushSDK

// MARK: - Tests

final class FrameCodecTests: XCTestCase {

    // MARK: Frame tags

    func testEncodesEachPayloadUnderItsOneofFieldNumber() throws {
        // Numbering per docs/push-socket-protocol.md; RelayGoldenTests checks the same numbers.
        let clientTags: [(String, Sinch_Push_Delivery_V1beta1_Ws_ClientFrame, UInt8)] = [
            ("hello", helloClientFrame(), 1),
            ("poll", pollClientFrame(), 2),
            ("deliveryReport", deliveryReportClientFrame(), 3),
            ("pong", Wire.pongClientFrameOfSize(0), 4),
        ]
        for (name, frame, tag) in clientTags {
            let encoded = try FrameCodec.encodeClientFrame(frame)
            XCTAssertEqual(encoded.bytes.first, tag, "ClientFrame.\(name)")
        }

        let serverTags: [(String, Sinch_Push_Delivery_V1beta1_Ws_ServerFrame, UInt8)] = [
            ("authChallenge", authChallengeServerFrame(), 1),
            ("helloAck", helloAckServerFrame(), 2),
            ("message", messageServerFrame(), 3),
            ("ack", ackServerFrame(), 4),
            ("ping", pingServerFrame(), 5),
            ("pong", pongServerFrame(), 6),
            ("close", closeServerFrame(), 7),
        ]
        for (name, frame, tag) in serverTags {
            let encoded = try FrameCodec.encodeServerFrame(frame)
            XCTAssertEqual(encoded.bytes.first, tag, "ServerFrame.\(name)")
        }
    }

    func testWritesTheInnerPayloadNotAFrameWrapper() throws {
        var hello = Sinch_Push_Delivery_V1beta1_Ws_Hello()
        hello.platform = .android
        var frame = Sinch_Push_Delivery_V1beta1_Ws_ClientFrame()
        frame.payload = .hello(hello)
        let bytes = try FrameCodec.encodeClientFrame(frame).bytes
        let payload = try hello.serializedData()
        XCTAssertEqual(bytes[0], 1)
        XCTAssertLessThan(payload.count, 128)
        XCTAssertEqual(Array(bytes.dropFirst(2)), payload.bytes)
    }

    func testEncodesAnEmptyPollAsAZeroLengthPayload() throws {
        XCTAssertEqual(try FrameCodec.encodeClientFrame(pollClientFrame()).bytes, [2, 0])
    }

    func testRefusesToEncodeAFrameWithNoPayloadSet() {
        let frame = Sinch_Push_Delivery_V1beta1_Ws_ClientFrame()
        XCTAssertThrowsError(try FrameCodec.encodeClientFrame(frame)) { error in
            XCTAssertEqual(error as? FrameCodecError, .noPayloadSet(direction: .client))
        }
        let server = Sinch_Push_Delivery_V1beta1_Ws_ServerFrame()
        XCTAssertThrowsError(try FrameCodec.encodeServerFrame(server)) { error in
            XCTAssertEqual(error as? FrameCodecError, .noPayloadSet(direction: .server))
        }
    }

    // MARK: Round trips

    func testClientFramesRoundTrip() throws {
        for frame in [
            helloClientFrame(), pollClientFrame(), deliveryReportClientFrame(),
            Wire.pongClientFrameOfSize(0), Wire.pongClientFrameOfSize(200),
        ] {
            let decoded = try FrameCodec.decodeClientFrame(try FrameCodec.encodeClientFrame(frame))
            XCTAssertEqual(decoded.payload, frame.payload)
        }
    }

    func testServerFramesRoundTrip() throws {
        for frame in [
            authChallengeServerFrame(), helloAckServerFrame(), messageServerFrame(),
            ackServerFrame(), pingServerFrame(), pongServerFrame(), closeServerFrame(),
        ] {
            let decoded = try FrameCodec.decodeServerFrame(try FrameCodec.encodeServerFrame(frame))
            XCTAssertEqual(decoded.payload, frame.payload)
        }
    }

    // MARK: Unknown frame tags

    func testThrowsUnknownTagWhenDecodingAServerFrame() {
        XCTAssertThrowsError(try FrameCodec.decodeServerFrame(Data([0x63, 0x00]))) { error in
            XCTAssertEqual(error as? FrameCodecError, .unknownTag(direction: .server, tag: 0x63))
        }
    }

    func testThrowsUnknownTagWhenDecodingAClientFrame() {
        XCTAssertThrowsError(try FrameCodec.decodeClientFrame(Data([0x63, 0x00]))) { error in
            XCTAssertEqual(error as? FrameCodecError, .unknownTag(direction: .client, tag: 0x63))
        }
    }

    func testRejectsTagsOutsideTheOneofPayloadRange() {
        // ServerFrame.payload uses 1..7 and ClientFrame.payload uses 1..4.
        for tag: UInt8 in [0, 8, 99, 255] {
            XCTAssertThrowsError(try FrameCodec.decodeServerFrame(Data([tag, 0]))) { error in
                XCTAssertEqual(error as? FrameCodecError, .unknownTag(direction: .server, tag: tag))
            }
        }
        for tag: UInt8 in [0, 5, 99, 255] {
            XCTAssertThrowsError(try FrameCodec.decodeClientFrame(Data([tag, 0]))) { error in
                XCTAssertEqual(error as? FrameCodecError, .unknownTag(direction: .client, tag: tag))
            }
        }
    }

    // MARK: Malformed envelopes

    func testRejectsAFrameTooShortToHoldATagAndALength() {
        for bytes in [[] as [UInt8], [1]] {
            XCTAssertThrowsError(try FrameCodec.decodeServerFrame(Data(bytes))) { error in
                XCTAssertEqual(error as? FrameCodecError, .tooShort(direction: .server))
            }
        }
    }

    func testRejectsAPayloadShorterThanTheDeclaredLength() {
        // tag 2, length 10, only 2 payload bytes present.
        XCTAssertThrowsError(try FrameCodec.decodeServerFrame(Data([2, 10, 0x0a, 0x02]))) { error in
            XCTAssertEqual(
                error as? FrameCodecError,
                .truncatedPayload(direction: .server, declaredLength: 10, available: 2))
        }
    }

    func testIgnoresBytesPastTheDeclaredPayload() throws {
        // One frame per WebSocket message, so bytes past the declared payload are ignored.
        let frame = try FrameCodec.encodeClientFrame(pollClientFrame())
        let withTrailer = Data(frame.bytes + [0xDE, 0xAD])
        XCTAssertEqual(
            try FrameCodec.decodeClientFrame(withTrailer).payload,
            pollClientFrame().payload)
    }

    // MARK: Direction asymmetry

    func testRejectsTheServerOnlyTagsOnTheClientSideAndViceVersa() throws {
        // ServerFrame.payload owns 5..7; ClientFrame.payload owns 1..4.
        let cases: [(tag: UInt8, isPing: Bool)] = [(5, true), (6, false), (7, false)]
        for (tag, isPing) in cases {
            let frame = Data(Wire.envelope(tag: tag, payload: []))
            guard let payload = try FrameCodec.decodeServerFrame(frame).payload else {
                return XCTFail("server tag \(tag) should decode")
            }
            if isPing {
                guard case .ping = payload else {
                    return XCTFail("server tag \(tag) should be ping, got \(payload)")
                }
            } else if tag == 6 {
                guard case .pong = payload else {
                    return XCTFail("server tag \(tag) should be pong, got \(payload)")
                }
            } else {
                guard case .close = payload else {
                    return XCTFail("server tag \(tag) should be close, got \(payload)")
                }
            }
            XCTAssertThrowsError(try FrameCodec.decodeClientFrame(frame)) { error in
                XCTAssertEqual(error as? FrameCodecError, .unknownTag(direction: .client, tag: tag))
            }
        }
    }

    // MARK: int64 boundaries

    func testInt64FieldBoundariesRoundTrip() throws {
        let values: [Int64] = [
            0, 1, -1, 1_770_000_000_000,
            Int64.max, Int64.min, Int64.max - 1, Int64.min + 1,
            9_007_199_254_740_993,  // 2^53 + 1: one past the largest safe double
        ]
        for value in values {
            let report = deliveryReportClientFrame(reportedAt: value)
            let decodedReport = try FrameCodec.decodeClientFrame(try FrameCodec.encodeClientFrame(report))
            guard case .deliveryReport(let out)? = decodedReport.payload else {
                return XCTFail("expected a delivery report")
            }
            XCTAssertEqual(out.reportedAtUnixMillis, value)

            var challenge = Sinch_Push_Delivery_V1beta1_Ws_AuthChallenge()
            challenge.nonce = "n"
            challenge.issuedAtUnixMillis = value
            var serverFrame = Sinch_Push_Delivery_V1beta1_Ws_ServerFrame()
            serverFrame.payload = .authChallenge(challenge)
            let decodedChallenge = try FrameCodec.decodeServerFrame(
                try FrameCodec.encodeServerFrame(serverFrame))
            guard case .authChallenge(let outChallenge)? = decodedChallenge.payload else {
                return XCTFail("expected an auth challenge")
            }
            XCTAssertEqual(outChallenge.issuedAtUnixMillis, value)
        }
    }

    func testInt64BoundaryDoesNotDetourThroughADouble() throws {
        // 2^53 + 1 is not representable as a Double.
        let exact: Int64 = 9_007_199_254_740_993
        XCTAssertEqual(Double(exact), 9_007_199_254_740_992)
        XCTAssertNotEqual(Int64(Double(exact)), exact)
        var challenge = Sinch_Push_Delivery_V1beta1_Ws_AuthChallenge()
        challenge.issuedAtUnixMillis = exact
        var frame = Sinch_Push_Delivery_V1beta1_Ws_ServerFrame()
        frame.payload = .authChallenge(challenge)
        let encoded = try! FrameCodec.encodeServerFrame(frame)
        guard case .authChallenge(let decoded)? = try! FrameCodec.decodeServerFrame(encoded).payload
        else {
            return XCTFail("expected an auth challenge")
        }
        XCTAssertEqual(decoded.issuedAtUnixMillis, exact)
    }

    // MARK: Malformed payloads

    func testAPayloadThatDoesNotParseIsTypedSeparatelyFromAnUnknownTag() {
        // tag 2 (HelloAck), length 2, bytes 0xff 0xff: field 0 does not exist, so this
        // is malformed bytes, not an unknown tag.
        let bytes: [UInt8] = [0x02, 0x02, 0xff, 0xff]
        XCTAssertThrowsError(try FrameCodec.decodeServerFrame(Data(bytes))) { error in
            guard case .malformedPayload(let direction, let tag, _)? = error as? FrameCodecError else {
                return XCTFail("expected a malformed-payload error, got \(error)")
            }
            XCTAssertEqual(direction, .server)
            XCTAssertEqual(tag, 2)
        }
    }

    // MARK: String validation

    func testIllFormedUTF8InAStringIsRefusedNotSubstituted() {
        // Must be refused, not replaced with U+FFFD, which would change the id the relay
        // correlates on.
        //
        // ServerFrame.pong, field 1 (correlation_id), wire type 2:
        //   0x0a | 0x03 | 0x41 0xc3 0x28   -> "A" + an ill-formed two-byte sequence
        let payload = Wire.bytesOf([0x0a, 0x03, 0x41, 0xc3, 0x28])
        let frame = Wire.envelope(tag: 0x06, payload: payload)
        XCTAssertThrowsError(try FrameCodec.decodeServerFrame(Data(frame))) { error in
            guard case .malformedPayload(let direction, let tag, _)? = error as? FrameCodecError else {
                return XCTFail("expected a malformed-payload error, got \(error)")
            }
            XCTAssertEqual(direction, .server)
            XCTAssertEqual(tag, 0x06)
        }
    }

    func testAValidUTF8CorrelationIDInTheSameFieldStillDecodes() throws {
        // Control for the test above: legal multi-byte scalars (U+00E9, U+4E2D) still decode.
        var pong = Sinch_Push_Delivery_V1beta1_Ws_Pong()
        pong.correlationID = "A\u{00E9}\u{4E2D}"
        let frame = Wire.envelope(tag: 0x06, payload: [UInt8](try pong.serializedData()))
        guard case .pong(let decoded)? = try FrameCodec.decodeServerFrame(Data(frame)).payload else {
            return XCTFail("expected a pong")
        }
        XCTAssertEqual(decoded.correlationID, "A\u{00E9}\u{4E2D}")
    }
}
