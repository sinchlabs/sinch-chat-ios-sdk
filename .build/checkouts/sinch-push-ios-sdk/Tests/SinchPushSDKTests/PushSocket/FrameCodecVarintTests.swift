//  FrameCodecVarintTests.swift — the payload-length varint: widths, boundaries and
//  malformed prefixes. Frames are hand-built as in FrameCodecTests.swift.

import XCTest

@testable import SinchPushSDK

final class FrameCodecVarintTests: XCTestCase {

    // MARK: Multi-byte varint payload length

    func testEncodesAClientPongAgainstTheExactExpectedBytes() throws {
        // Payload: 0x0a, 200 as varint (0xc8 0x01), 200 'A' = 203 bytes; 203 is 0xcb 0x01.
        let correlationID = String(repeating: "A", count: 200)
        var frame = Sinch_Push_Delivery_V1beta1_Ws_ClientFrame()
        frame.payload = .pong(Wire.pongMessage(correlationID: correlationID))
        let expected = Wire.bytesOf(
            [0x04],  // ClientFrame.pong field number
            [0xcb, 0x01],  // payload length 203
            [0x0a],  // field 1, wire type 2 (length-delimited)
            [0xc8, 0x01],  // string length 200
            [UInt8](repeating: 0x41, count: 200)  // 'A' * 200
        )
        let encoded = try FrameCodec.encodeClientFrame(frame)
        XCTAssertEqual(encoded.bytes, expected)
        XCTAssertEqual(encoded.count, encoded.bytes.count)
        guard case .pong(let pong)? = try FrameCodec.decodeClientFrame(encoded).payload else {
            return XCTFail("expected a pong")
        }
        XCTAssertEqual(pong.correlationID, correlationID)
    }

    func testEncodesAServerHelloAckAgainstTheExactExpectedBytes() throws {
        // connection_id (203 B) + poll_interval_ms = 5000 (0x18, 0x88 0x27) = 206 B; 206 is 0xce 0x01.
        var ack = Sinch_Push_Delivery_V1beta1_Ws_HelloAck()
        ack.connectionID = String(repeating: "C", count: 200)
        ack.pollIntervalMs = 5000
        var frame = Sinch_Push_Delivery_V1beta1_Ws_ServerFrame()
        frame.payload = .helloAck(ack)
        let expected = Wire.bytesOf(
            [0x02],  // ServerFrame.hello_ack field number
            [0xce, 0x01],  // payload length 206
            [0x0a],  // field 1, wire type 2
            [0xc8, 0x01],  // connection_id length 200
            [UInt8](repeating: 0x43, count: 200),  // 'C' * 200
            [0x18],  // field 3, wire type 0 (varint)
            [0x88, 0x27]  // 5000
        )
        XCTAssertEqual(try FrameCodec.encodeServerFrame(frame).bytes, expected)
    }

    // MARK: Payload length varint width boundaries

    func testPayloadLengthVarintWidthBoundaries() throws {
        // The prefix widens at 128 and again at 16384.
        for size in [127, 128, 16383, 16384] {
            let prefixWidth = Wire.varintSize(UInt64(size))

            let clientEncoded = try FrameCodec.encodeClientFrame(Wire.pongClientFrameOfSize(size))
            XCTAssertEqual(clientEncoded.count, 1 + prefixWidth + size)
            XCTAssertEqual(clientEncoded.bytes[0], 4)
            XCTAssertEqual(
                Array(clientEncoded.bytes[1..<(1 + prefixWidth)]), Wire.varintBytes(UInt64(size)))
            guard case .pong(let pong)? = try FrameCodec.decodeClientFrame(clientEncoded).payload
            else {
                return XCTFail("expected a pong")
            }
            XCTAssertEqual(pong, Wire.pongMessageOfSize(size))

            let serverEncoded = try FrameCodec.encodeServerFrame(Wire.pongServerFrameOfSize(size))
            XCTAssertEqual(serverEncoded.count, 1 + prefixWidth + size)
            guard case .pong(let serverPong)? = try FrameCodec.decodeServerFrame(serverEncoded).payload
            else {
                return XCTFail("expected a pong")
            }
            XCTAssertEqual(serverPong, Wire.pongMessageOfSize(size))

            let handBuiltClient = Wire.envelope(tag: 4, payload: Wire.pongPayloadOfSize(size).bytes)
            XCTAssertEqual(handBuiltClient.count, 1 + prefixWidth + size)
            guard case .pong(let handBuiltPong)? =
                try FrameCodec.decodeClientFrame(Data(handBuiltClient)).payload
            else {
                return XCTFail("expected a pong")
            }
            XCTAssertEqual(handBuiltPong, Wire.pongMessageOfSize(size))

            let handBuiltServer = Wire.envelope(tag: 6, payload: Wire.pongPayloadOfSize(size).bytes)
            XCTAssertEqual(handBuiltServer.count, 1 + prefixWidth + size)
            guard case .pong(let handBuiltServerPong)? =
                try FrameCodec.decodeServerFrame(Data(handBuiltServer)).payload
            else {
                return XCTFail("expected a pong")
            }
            XCTAssertEqual(handBuiltServerPong, Wire.pongMessageOfSize(size))
        }

        XCTAssertEqual(Wire.varintSize(127), 1)
        XCTAssertEqual(Wire.varintSize(128), 2)
        XCTAssertEqual(Wire.varintSize(16383), 2)
        XCTAssertEqual(Wire.varintSize(16384), 3)
    }

    // MARK: Malformed length prefixes

    func testRejectsTheFourGiBDeclarationThatUsedToDecodeAsAnEmptyHelloAck() {
        // Regression: `80 80 80 80 10` is 4294967296; a 32-bit reader truncated it to 0 and
        // decoded an empty HelloAck.
        let bytes: [UInt8] = [0x02, 0x80, 0x80, 0x80, 0x80, 0x10]
        XCTAssertThrowsError(try FrameCodec.decodeServerFrame(Data(bytes))) { error in
            XCTAssertEqual(
                error as? FrameCodecError,
                .payloadTooLarge(direction: .server, declaredLength: 4_294_967_296))
            XCTAssertTrue("\(error)".contains("4294967296"))
        }
    }

    func testRejectsAPrefixThatIsCutOffAfterTheTag() {
        // tag 2 and a continuation byte with nothing after it.
        let cut = [[0x02, 0x80], [0x02, 0x80, 0x80, 0x80, 0x80, 0x80]] as [[UInt8]]
        for bytes in cut {
            assertLengthVarintError(bytes)
        }
    }

    func testRejectsAVarintThatRunsPast64Bits() {
        // Eleven bytes: cannot finish inside 64 bits.
        assertLengthVarintError(Wire.bytesOf([0x02], [UInt8](repeating: 0x80, count: 11), [0x01]))
        // Ten bytes whose last byte carries more than the one bit free at shift 63.
        assertLengthVarintError(Wire.bytesOf([0x02], [UInt8](repeating: 0x80, count: 9), [0x02]))
        assertLengthVarintError(Wire.bytesOf([0x02], [UInt8](repeating: 0x80, count: 9), [0x81]))
    }

    func testAcceptsTheLargestCanonicalVarintShapeAndRejectsItOnThePayloadCap() {
        // 2^63 is a valid ten-byte varint; the payload cap rejects it.
        let bytes = Wire.bytesOf([0x02], [UInt8](repeating: 0x80, count: 9), [0x01])
        XCTAssertThrowsError(try FrameCodec.decodeServerFrame(Data(bytes))) { error in
            XCTAssertEqual(
                error as? FrameCodecError,
                .payloadTooLarge(direction: .server, declaredLength: 1 << 63))
        }
    }

    func testRejectsADeclaredLengthLongerThanTheBytesPresent() {
        // tag 2, declares 1024, sends 4.
        assertTruncated(
            Wire.frameDeclaring(tag: 0x02, declared: 1024, bodyBytes: 4),
            direction: .server, declared: 1024)
        assertTruncated(
            Wire.frameDeclaring(tag: 0x02, declared: 10, bodyBytes: 9),
            direction: .server, declared: 10)
        assertTruncated(
            Wire.bytesOf([0x02, 0x0a], [UInt8](repeating: 0x41, count: 9)),
            direction: .server, declared: 10)
    }

    func testChecksTheLengthBeforeTheTagSoABadPrefixIsNeverTrusted() {
        // Tag 99 is unknown, but the prefix declares 2^35 bytes: the bounds error wins.
        XCTAssertThrowsError(
            try FrameCodec.decodeServerFrame(Data([0x63, 0x80, 0x80, 0x80, 0x80, 0x80, 0x10]))
        ) { error in
            XCTAssertEqual(
                error as? FrameCodecError,
                .payloadTooLarge(direction: .server, declaredLength: 549_755_813_888))
        }
    }

    func testReportsTheDirectionItWasDecoding() {
        // Tag 1 is ClientFrame.hello and an unknown tag on the server side.
        assertTruncated(
            Wire.frameDeclaring(tag: 0x01, declared: 1024, bodyBytes: 4),
            direction: .client, declared: 1024)
        assertTruncated(
            Wire.frameDeclaring(tag: 0x02, declared: 1024, bodyBytes: 4),
            direction: .server, declared: 1024)
    }

    // MARK: Helpers

    private func assertLengthVarintError(
        _ bytes: [UInt8], file: StaticString = #filePath, line: UInt = #line
    ) {
        XCTAssertThrowsError(
            try FrameCodec.decodeServerFrame(Data(bytes)), file: file, line: line
        ) { error in
            guard case .lengthVarint(let direction, _)? = error as? FrameCodecError else {
                return XCTFail("expected a length-varint error, got \(error)", file: file, line: line)
            }
            XCTAssertEqual(direction, .server, file: file, line: line)
        }
    }

    private func assertTruncated(
        _ bytes: [UInt8], direction: FrameDirection, declared: Int,
        file: StaticString = #filePath, line: UInt = #line
    ) {
        XCTAssertThrowsError(
            try direction == .client
                ? FrameCodec.decodeClientFrame(Data(bytes)) as Any
                : FrameCodec.decodeServerFrame(Data(bytes)) as Any,
            file: file, line: line
        ) { error in
            guard case .truncatedPayload(let gotDirection, let gotDeclared, _)? =
                error as? FrameCodecError
            else {
                return XCTFail(
                    "expected a truncated-payload error, got \(error)", file: file, line: line)
            }
            XCTAssertEqual(gotDirection, direction, file: file, line: line)
            XCTAssertEqual(gotDeclared, declared, file: file, line: line)
        }
    }
}
