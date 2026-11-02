//  RelayGoldenTests.swift — conformance against the relay's golden wire vectors
//  (fixture and codec helpers in `RelayGoldenSupport.swift`).

import Foundation
import XCTest

@testable import SinchPushSDK

final class RelayGoldenTests: XCTestCase {

    func testLoadedTheFixtureTheRelayGenerated() throws {
        let golden = try GoldenFixture.load()
        XCTAssertEqual(golden.version, 1)
        // 19 client_to_server + 29 server_to_client; a truncated fixture must fail here.
        XCTAssertEqual(golden.frames.count, 48)
        XCTAssertEqual(golden.negativeCases.count, 14)
    }

    func testAgreesWithTheRelayOnTheSizeContract() throws {
        let golden = try GoldenFixture.load()
        XCTAssertEqual(FrameCodec.maxFramePayloadBytes, golden.sizeContract.maxFramePayloadBytes)
        XCTAssertEqual(FrameCodec.maxFrameTotalBytes, golden.sizeContract.maxWireFrameBytes)
        // canonical_envelope_max_bytes already includes the tag byte and widest varint.
        XCTAssertEqual(
            FrameCodec.maxFrameEmittedBytes,
            golden.sizeContract.maxFramePayloadBytes + golden.sizeContract.canonicalEnvelopeMaxBytes)
        // 1 tag byte + 10-byte length varint.
        XCTAssertEqual(1 + 10, golden.sizeContract.maxFrameEnvelopeBytes)
    }

    func testDecodesEveryPositiveVectorToTheMessageTypeTheRelayNames() throws {
        let golden = try GoldenFixture.load()
        for vector in golden.frames {
            let frame = Data(Wire.bytes(hex: vector.frameHex))
            switch vector.direction {
            case .clientToServer:
                let decoded = try FrameCodec.decodeClientFrame(frame)
                XCTAssertEqual(
                    GoldenWire.clientCaseName(decoded.payload),
                    GoldenWire.camelCase(GoldenWire.frameTypeComponent(vector.frameType)),
                    "\(vector.name) decoded as the wrong payload")
            case .serverToClient:
                let decoded = try FrameCodec.decodeServerFrame(frame)
                XCTAssertEqual(
                    GoldenWire.serverCaseName(decoded.payload),
                    GoldenWire.camelCase(GoldenWire.frameTypeComponent(vector.frameType)),
                    "\(vector.name) decoded as the wrong payload")
            }
        }
    }

    func testEveryPositiveVectorIsDecodedAndReEncoded() throws {
        let golden = try GoldenFixture.load()
        for direction in [Golden.Direction.clientToServer, .serverToClient] {
            let vectors = golden.frames.filter { $0.direction == direction }
            XCTAssertFalse(vectors.isEmpty, "no \(direction) vectors in the fixture")
            for vector in vectors {
                let frame = Data(Wire.bytes(hex: vector.frameHex))
                let reencoded = try GoldenWire.encode(direction, frame)
                var payload: Sinch_Push_Delivery_V1beta1_Ws_ServerFrame.OneOf_Payload?
                if direction == .serverToClient { payload = try FrameCodec.decodeServerFrame(frame).payload }
                if let payload, GoldenWire.carriesMapEntries(payload) {
                    // See carriesMapEntries.
                    XCTAssertEqual(reencoded.bytes[0], frame.bytes[0], "\(vector.name) tag")
                    XCTAssertEqual(reencoded.count, frame.count, "\(vector.name) frame length")
                    try GoldenWire.decode(direction, reencoded)
                } else {
                    XCTAssertEqual(
                        Wire.hex(reencoded), vector.frameHex.lowercased(),
                        "\(vector.name) did not re-encode byte for byte")
                }
            }
        }
    }

    // MARK: - Hello device info

    func testTheDeviceInfoHelloVectorsDecodeIntoTheNamedFields() throws {
        // A byte round trip would also pass with fields 9-12 held as unknown data,
        // so assert the named fields.
        let golden = try GoldenFixture.load()
        for (name, expected) in GoldenHelloVectors.deviceInfo {
            let (_, hello) = try GoldenHelloVectors.vector(golden, named: name)
            XCTAssertEqual(GoldenDeviceInfo(hello), expected, "\(name): fields 9-12 decoded wrongly")
            if name == "client_hello_relay_disabled" {
                XCTAssertEqual(hello.platform, .android, "\(name): platform")
                XCTAssertFalse(hello.background, "\(name): background")
            }
        }
    }

    func testADeviceInfoHelloCanBeChangedAndPutsTheNewValueOnTheWire() throws {
        // Write direction: unknown fields cannot be assigned, so this needs fields 9-12.
        let golden = try GoldenFixture.load()
        for (name, expected) in GoldenHelloVectors.deviceInfo {
            let (_, decoded) = try GoldenHelloVectors.vector(golden, named: name)
            var hello = decoded
            hello.osVersion = "17.4"
            var frame = Sinch_Push_Delivery_V1beta1_Ws_ClientFrame()
            frame.payload = .hello(hello)
            let reencoded = try FrameCodec.encodeClientFrame(frame)
            let decodedAgain = try FrameCodec.decodeClientFrame(reencoded)
            guard case .some(.hello(let round)) = decodedAgain.payload else {
                throw GoldenVectorError.rewriteIsNotAHello(name)
            }
            XCTAssertEqual(
                GoldenDeviceInfo(round),
                GoldenDeviceInfo(
                    installationID: expected.installationID,
                    osVersion: "17.4",
                    bundleID: expected.bundleID,
                    backgroundService: expected.backgroundService),
                "\(name): rewriting os_version lost or changed another device-info field")
            XCTAssertEqual(reencoded.bytes.first, 1, "\(name): the rewritten frame is not a client Hello")
        }
    }

    func testAnOlderHelloCarriesNoDeviceInfo() throws {
        // Predates fields 9-12; they must read as absent.
        let golden = try GoldenFixture.load()
        let (_, hello) = try GoldenHelloVectors.vector(golden, named: "client_hello_full")
        XCTAssertEqual(hello.sdkVersion, "1.2.3")
        XCTAssertEqual(hello.installationID, "")
        XCTAssertEqual(hello.osVersion, "")
        XCTAssertEqual(hello.bundleID, "")
        XCTAssertEqual(hello.backgroundService, .unspecified)
    }

    // MARK: - The relay-disabled Hello

    func testTheRelayDisabledHelloVectorDecodesIntoTheNamedFields() throws {
        // `RELAY_DISABLED = 5` must arrive as the named case, not an unknown number.
        let golden = try GoldenFixture.load()
        let (vector, hello) = try GoldenHelloVectors.vector(golden, named: "client_hello_relay_disabled")
        XCTAssertEqual(hello.backgroundService, .relayDisabled)
        XCTAssertEqual(hello.backgroundService.rawValue, 5)
        XCTAssertEqual(GoldenRelayDisabledHello(hello), GoldenHelloVectors.relayDisabled)
        // Nothing was dropped on decode.
        XCTAssertEqual(try hello.serializedData().count, vector.payloadLen)
    }

    func testTheRelayDisabledHelloGoesOutByteForByte() throws {
        // A Hello built from scratch must encode to exactly the relay's bytes.
        let golden = try GoldenFixture.load()
        let (vector, _) = try GoldenHelloVectors.vector(golden, named: "client_hello_relay_disabled")
        var hello = Sinch_Push_Delivery_V1beta1_Ws_Hello()
        hello.authToken = "header.payload.signature"
        hello.projectID = "proj-1"
        hello.appID = "app-1"
        hello.userID = "user-1"
        hello.platform = .android
        hello.background = false
        hello.lastSeenMessageID = "m-last"
        hello.sdkVersion = "1.2.3"
        hello.installationID = "3c9e1f7a-52b4-4d08-9a6e-1b7c2d5e8f40"
        hello.osVersion = "14"
        hello.bundleID = "com.sinch.example"
        hello.backgroundService = .relayDisabled
        var frame = Sinch_Push_Delivery_V1beta1_Ws_ClientFrame()
        frame.payload = .hello(hello)
        XCTAssertEqual(
            Wire.hex(try FrameCodec.encodeClientFrame(frame)),
            vector.frameHex.lowercased(),
            "the SDK's own RELAY_DISABLED Hello is not the relay's bytes")
    }

    // MARK: - Negative vectors

    func testEveryNegativeVectorIsHandledTheWayTheRelayExpects() throws {
        let golden = try GoldenFixture.load()
        for negative in golden.negativeCases {
            let frame = Data(Wire.bytes(hex: negative.frameHex))
            if negative.expect == "accepted" {
                XCTAssertNoThrow(
                    try GoldenWire.decode(negative.direction, frame),
                    "\(negative.name): \(negative.expect) but the codec threw")
                continue
            }
            XCTAssertThrowsError(
                try GoldenWire.decode(negative.direction, frame),
                "\(negative.name): expected a failure but the frame decoded")
        }
    }

    func testNegativeVectorsFailWithATypedErrorInTheExpectedClass() throws {
        let golden = try GoldenFixture.load()
        for negative in golden.negativeCases where negative.expect != "accepted" {
            let frame = Data(Wire.bytes(hex: negative.frameHex))
            do {
                try GoldenWire.decode(negative.direction, frame)
                XCTFail("\(negative.name): expected \(negative.expect) but it decoded")
            } catch let error as FrameCodecError {
                XCTAssertTrue(
                    GoldenClassification.acceptable(error, for: negative.expect),
                    "\(negative.name): expected \(negative.expect), got \(error)")
            }
        }
    }

    func testZeroPaddedLengthVarintsAreToleratedTheWayTheRelayToleratesThem() throws {
        // The length varint may be zero-padded to 10 bytes; the relay accepts it.
        let golden = try GoldenFixture.load()
        let padded = try XCTUnwrap(
            golden.negativeCases.first(where: { $0.name == "length_zero_padded_accepted" }),
            "the fixture no longer carries length_zero_padded_accepted")
        XCTAssertNoThrow(try GoldenWire.decode(padded.direction, Data(Wire.bytes(hex: padded.frameHex))))
    }

    // MARK: - The tag table

    func testTheRelayTagTableMatchesTheTagsTheEncoderEmits() throws {
        // FrameCodec reads tags off the generated `traverse`; the fixture is the
        // independent source of the numbers.
        let golden = try GoldenFixture.load()
        XCTAssertFalse(golden.frameTypes.isEmpty)
        for entry in golden.frameTypes {
            switch entry.direction {
            case .clientToServer:
                let frame = GoldenWire.clientFrameFor(frameType: entry.frameType)
                XCTAssertEqual(
                    try FrameCodec.encodeClientFrame(frame).bytes.first, UInt8(entry.tag),
                    "\(entry.frameType) should go out on tag \(entry.tag)")
            case .serverToClient:
                let frame = GoldenWire.serverFrameFor(frameType: entry.frameType)
                XCTAssertEqual(
                    try FrameCodec.encodeServerFrame(frame).bytes.first, UInt8(entry.tag),
                    "\(entry.frameType) should go out on tag \(entry.tag)")
            }
        }
    }

    func testTheRelayTagTableCoversExactlyThePayloadsTheProtosDeclare() throws {
        let golden = try GoldenFixture.load()
        XCTAssertEqual(
            Set(golden.frameTypes.filter { $0.direction == .clientToServer }.map(\.tag)),
            [1, 2, 3, 4])
        XCTAssertEqual(
            Set(golden.frameTypes.filter { $0.direction == .serverToClient }.map(\.tag)),
            [1, 2, 3, 4, 5, 6, 7])
    }
}
