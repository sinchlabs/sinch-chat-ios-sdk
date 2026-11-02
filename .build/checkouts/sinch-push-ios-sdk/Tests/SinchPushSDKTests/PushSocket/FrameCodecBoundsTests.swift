//  FrameCodecBoundsTests.swift — payload and envelope size limits.
//  Frames are hand-built as in FrameCodecTests.swift.

import XCTest

@testable import SinchPushSDK

final class FrameCodecBoundsTests: XCTestCase {

    // MARK: Payload and envelope size limits

    func testEncodesAPayloadExactlyAtTheCap() throws {
        let atCap = FrameCodec.maxFramePayloadBytes
        XCTAssertEqual(Wire.pongPayloadOfSize(atCap).count, atCap)
        let frame = try FrameCodec.encodeClientFrame(Wire.pongClientFrameOfSize(atCap))
        // 65536 payload + 1 tag byte + 3-byte canonical varint; tighter than the accepted 65547.
        XCTAssertEqual(frame.count, FrameCodec.maxFrameEmittedBytes)
        XCTAssertEqual(frame.count, 65_540)
        guard case .pong(let pong)? = try FrameCodec.decodeClientFrame(frame).payload else {
            return XCTFail("expected a pong")
        }
        XCTAssertEqual(pong, Wire.pongMessageOfSize(atCap))
    }

    func testEncodesAPayloadOneByteOverTheCapAsATypedError() {
        let overCap = FrameCodec.maxFramePayloadBytes + 1
        XCTAssertEqual(Wire.pongPayloadOfSize(overCap).count, overCap)
        XCTAssertThrowsError(try FrameCodec.encodeClientFrame(Wire.pongClientFrameOfSize(overCap))) { error in
            XCTAssertEqual(
                error as? FrameCodecError, .payloadTooLarge(direction: .client, declaredLength: UInt64(overCap)))
        }
        XCTAssertThrowsError(try FrameCodec.encodeServerFrame(Wire.pongServerFrameOfSize(overCap))) { error in
            XCTAssertEqual(
                error as? FrameCodecError, .payloadTooLarge(direction: .server, declaredLength: UInt64(overCap)))
        }
    }

    func testDecodesAPayloadExactlyAtTheCap() throws {
        let bytes = Wire.envelope(tag: 4, payload: Wire.pongPayloadOfSize(FrameCodec.maxFramePayloadBytes).bytes)
        XCTAssertEqual(bytes.count, FrameCodec.maxFrameEmittedBytes)
        guard case .pong(let pong)? = try FrameCodec.decodeClientFrame(Data(bytes)).payload else {
            return XCTFail("expected a pong")
        }
        XCTAssertEqual(pong, Wire.pongMessageOfSize(FrameCodec.maxFramePayloadBytes))
    }

    func testDecodesADeclaredLengthOneByteOverTheCapAsATypedError() {
        // Declares 65537 and sends nothing.
        let overCap = UInt64(FrameCodec.maxFramePayloadBytes + 1)
        XCTAssertThrowsError(try FrameCodec.decodeServerFrame(Data(Wire.frameDeclaring(tag: 0x06, declared: overCap, bodyBytes: 0)))) { error in
            XCTAssertEqual(
                error as? FrameCodecError, .payloadTooLarge(direction: .server, declaredLength: overCap))
        }
    }

    func testRejectsAFrameLargerThanTheEnvelopeBound() {
        // 1 tag byte + 1 prefix byte + filler = maxFrameTotalBytes + 1.
        let bytes = Wire.bytesOf([0x06, 0x00], [UInt8](repeating: 0x41, count: FrameCodec.maxFrameTotalBytes - 1))
        XCTAssertEqual(bytes.count, FrameCodec.maxFrameTotalBytes + 1)
        XCTAssertThrowsError(try FrameCodec.decodeServerFrame(Data(bytes))) { error in
            XCTAssertEqual(
                error as? FrameCodecError,
                .frameTooLarge(direction: .server, length: FrameCodec.maxFrameTotalBytes + 1))
        }
    }

    func testKeepsThePayloadBoundTheEmittedBoundAndTheAcceptedBoundDistinct() {
        XCTAssertEqual(FrameCodec.maxFramePayloadBytes, 65_536)
        // Accepted: 1 tag + 10-byte varint + payload (the relay's MaxWireFrameBytes).
        XCTAssertEqual(FrameCodec.maxFrameTotalBytes, 65_547)
        // Emitted: 1 tag + canonical 3-byte varint (`80 80 04`) + payload.
        XCTAssertEqual(FrameCodec.maxFrameEmittedBytes, 65_540)
        XCTAssertEqual(Wire.varintBytes(65_536), [0x80, 0x80, 0x04])
        XCTAssertEqual(Wire.varintSize(65_536), 3)
        XCTAssertGreaterThan(FrameCodec.maxFrameTotalBytes, FrameCodec.maxFramePayloadBytes)
        XCTAssertLessThan(FrameCodec.maxFrameEmittedBytes, FrameCodec.maxFrameTotalBytes)
    }

    func testAcceptsTheWidestLengthPrefixTheRelayTolerates() throws {
        // Tag 4 is ClientFrame.pong but ServerFrame.ack, and an empty payload parses
        // against any schema, so each direction is paired with the tag it owns.
        let clientEmpty = Wire.envelopeWithPrefix(tag: 4, prefix: Wire.extendedVarint(0, width: 10))
        XCTAssertEqual(clientEmpty.count, 1 + 10)
        guard case .pong(let clientPong)? = try FrameCodec.decodeClientFrame(Data(clientEmpty)).payload
        else {
            return XCTFail("expected a pong")
        }
        XCTAssertEqual(clientPong, Wire.pongMessage(correlationID: ""))

        let serverEmpty = Wire.envelopeWithPrefix(tag: 6, prefix: Wire.extendedVarint(0, width: 10))
        guard case .pong(let serverPong)? = try FrameCodec.decodeServerFrame(Data(serverEmpty)).payload
        else {
            return XCTFail("expected a pong")
        }
        XCTAssertEqual(serverPong, Wire.pongMessage(correlationID: ""))
    }

    func testAcceptsAMaximumSizePayloadBehindANoncanonicalTenByteLength() throws {
        // 65536 padded to a ten-byte varint gives a 1 + 10 + 65536 = 65547-byte frame.
        let atCap = FrameCodec.maxFramePayloadBytes
        let prefix = Wire.extendedVarint(UInt64(atCap), width: 10)
        XCTAssertEqual(prefix, [0x80, 0x80, 0x84, 0x80, 0x80, 0x80, 0x80, 0x80, 0x80, 0x00])

        let clientBytes = Wire.envelopeWithPrefix(
            tag: 4, prefix: prefix, body: Wire.pongPayloadOfSize(atCap).bytes)
        XCTAssertEqual(clientBytes.count, FrameCodec.maxFrameTotalBytes)
        XCTAssertEqual(clientBytes.count, 65_547)
        XCTAssertLessThan(FrameCodec.maxFrameEmittedBytes, clientBytes.count)
        guard case .pong(let pong)? = try FrameCodec.decodeClientFrame(Data(clientBytes)).payload
        else {
            return XCTFail("expected a pong")
        }
        XCTAssertEqual(pong, Wire.pongMessageOfSize(atCap))

        let serverBytes = Wire.envelopeWithPrefix(
            tag: 6, prefix: prefix, body: Wire.pongPayloadOfSize(atCap).bytes)
        XCTAssertEqual(serverBytes.count, FrameCodec.maxFrameTotalBytes)
        guard case .pong(let serverPong)? = try FrameCodec.decodeServerFrame(Data(serverBytes)).payload
        else {
            return XCTFail("expected a pong")
        }
        XCTAssertEqual(serverPong, Wire.pongMessageOfSize(atCap))
    }

    func testDecodesTheSameTagToADifferentMessagePerDirection() throws {
        // Tag 4 is ClientFrame.pong and ServerFrame.ack: the direction identifies the payload.
        let empty = { (tag: UInt8) in
            Data(Wire.envelopeWithPrefix(tag: tag, prefix: Wire.extendedVarint(0, width: 10)))
        }
        guard case .pong? = try FrameCodec.decodeClientFrame(empty(4)).payload else {
            return XCTFail("client tag 4 should be pong")
        }
        guard case .ack? = try FrameCodec.decodeServerFrame(empty(4)).payload else {
            return XCTFail("server tag 4 should be ack")
        }
        // Tag 6 is ServerFrame.pong only.
        guard case .pong? = try FrameCodec.decodeServerFrame(empty(6)).payload else {
            return XCTFail("server tag 6 should be pong")
        }
        XCTAssertThrowsError(try FrameCodec.decodeClientFrame(empty(6))) { error in
            XCTAssertEqual(error as? FrameCodecError, .unknownTag(direction: .client, tag: 6))
        }
    }

    func testStillRefusesAnOversizedPayloadThatFitsInsideTheWidenedEnvelope() {
        // The envelope has room, but the payload cap still refuses 65537.
        let overCap = UInt64(FrameCodec.maxFramePayloadBytes + 1)
        XCTAssertThrowsError(
            try FrameCodec.decodeServerFrame(Data(Wire.frameDeclaring(tag: 0x06, declared: overCap, bodyBytes: 0)))
        ) { error in
            XCTAssertEqual(
                error as? FrameCodecError, .payloadTooLarge(direction: .server, declaredLength: overCap))
        }
    }

    func testRejectsAFrameOneByteOverTheAcceptedBound() {
        let bytes = Wire.bytesOf([0x06, 0x00], [UInt8](repeating: 0x41, count: FrameCodec.maxFrameTotalBytes - 1))
        XCTAssertEqual(bytes.count, FrameCodec.maxFrameTotalBytes + 1)
        XCTAssertThrowsError(try FrameCodec.decodeServerFrame(Data(bytes))) { error in
            XCTAssertEqual(
                error as? FrameCodecError,
                .frameTooLarge(direction: .server, length: FrameCodec.maxFrameTotalBytes + 1))
        }
    }

    func testRejectsTheLargestDecodableVarintOnTheSizeBound() {
        // 2^64-1: a legal varint declaring an impossible payload.
        let bytes = Wire.envelopeWithPrefix(
            tag: 3, prefix: [0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0x01])
        XCTAssertThrowsError(try FrameCodec.decodeClientFrame(Data(bytes))) { error in
            XCTAssertEqual(
                error as? FrameCodecError, .payloadTooLarge(direction: .client, declaredLength: UInt64.max))
        }
    }
}
