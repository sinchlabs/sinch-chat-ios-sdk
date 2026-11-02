import Foundation
import XCTest
@testable import SinchPushSDK

/// The offline tests of the gRPC-web framing and of the answer parsing.
///
/// No network: the bodies are the ones the servers really answered with, captured byte for byte.
final class GrpcWebFramingTests: XCTestCase {

    // MARK: - Request framing

    func testFramePrefixesTheMessageWithItsBigEndianLength() throws {
        let payload = Data([0x0a, 0x03, 0x61, 0x62, 0x63])
        let framed = GrpcWebFraming.frame(payload)

        XCTAssertEqual([UInt8](framed), [0x00, 0x00, 0x00, 0x00, 0x05, 0x0a, 0x03, 0x61, 0x62, 0x63])
    }

    func testFrameOfAnEmptyMessageIsTheHeaderAlone() {
        let framed = GrpcWebFraming.frame(Data())

        XCTAssertEqual([UInt8](framed), [0x00, 0x00, 0x00, 0x00, 0x00])
    }

    func testFrameUsesTheFullThirtyTwoBitLength() {
        let payload = Data(repeating: 0x7f, count: 0x0102)
        let framed = GrpcWebFraming.frame(payload)

        XCTAssertEqual([UInt8](framed.prefix(5)), [0x00, 0x00, 0x00, 0x01, 0x02])
        XCTAssertEqual(framed.count, 5 + 0x0102)
    }

    // MARK: - Answer parsing

    /// The answer of the chat backend for `IssueAnonymousToken`: a message frame and a trailer frame.
    func testParsesAMessageFrameAndATrailerFrame() throws {
        let body = Data([
            0x00, 0x00, 0x00, 0x00, 0x03, 0x0a, 0x01, 0x41,             // message: field 1 = "A"
            0x80, 0x00, 0x00, 0x00, 0x0f,                             // trailer frame
            0x67, 0x72, 0x70, 0x63, 0x2d, 0x73, 0x74, 0x61, 0x74, 0x75, 0x73, 0x3a, 0x30, 0x0d, 0x0a, // "grpc-status:0\r\n"
        ])

        let parsed = try GrpcWebFraming.parse(body)

        XCTAssertEqual(parsed.messages.count, 1)
        XCTAssertEqual(parsed.messages.first, Data([0x0a, 0x01, 0x41]))
        XCTAssertEqual(parsed.trailerStatus, 0)
        XCTAssertEqual(parsed.trailers["grpc-status"], "0")
        XCTAssertNil(parsed.trailerMessage)
    }

    func testParsesTheTrailerMessage() throws {
        let body = GrpcWebFraming.trailerFrame(["grpc-status": "5", "grpc-message": "Client%20not%20found"])

        let parsed = try GrpcWebFraming.parse(body)

        XCTAssertEqual(parsed.trailerStatus, 5)
        XCTAssertEqual(parsed.trailerMessage, "Client%20not%20found")
    }

    func testTrailerKeysAreLowerCasedAndValuesTrimmed() {
        let trailers = GrpcWebFraming.parseTrailers(Data("GRPC-Status: 0\r\nGrpc-Message:  hello \r\n".utf8))

        XCTAssertEqual(trailers["grpc-status"], "0")
        XCTAssertEqual(trailers["grpc-message"], "hello")
    }

    func testParsesSeveralMessageFrames() throws {
        var body = GrpcWebFraming.frame(Data([0x01]))
        body.append(GrpcWebFraming.frame(Data([0x02])))

        let parsed = try GrpcWebFraming.parse(body)

        XCTAssertEqual(parsed.messages, [Data([0x01]), Data([0x02])])
    }

    func testAnEmptyBodyHasNoFrames() throws {
        let parsed = try GrpcWebFraming.parse(Data())

        XCTAssertTrue(parsed.messages.isEmpty)
        XCTAssertTrue(parsed.trailers.isEmpty)
        XCTAssertNil(parsed.trailerStatus)
    }

    /// A frame whose length runs past the end of the body is a cut answer, not an empty message.
    func testACutFrameIsMalformed() {
        let body = Data([0x00, 0x00, 0x00, 0x00, 0x10, 0x01, 0x02])

        XCTAssertThrowsError(try GrpcWebFraming.parse(body)) { error in
            guard case .malformedFrame = error as? GrpcWebError else {
                return XCTFail("expected a malformed frame error, got \(error)")
            }
        }
    }

    func testACutHeaderIsMalformed() {
        let body = Data([0x00, 0x00, 0x00])

        XCTAssertThrowsError(try GrpcWebFraming.parse(body)) { error in
            guard case .malformedFrame = error as? GrpcWebError else {
                return XCTFail("expected a malformed frame error, got \(error)")
            }
        }
    }

    // MARK: - URL building

    func testTheMethodPathKeepsItsSlash() {
        let client = GrpcWebClient(baseURL: URL(string: "https://grpc-web.sinch-chat.prod.sinch.com")!)

        XCTAssertEqual(
            client.url(for: "sinch.chat.sdk.v1alpha2.SdkService/IssueAnonymousToken").absoluteString,
            "https://grpc-web.sinch-chat.prod.sinch.com/sinch.chat.sdk.v1alpha2.SdkService/IssueAnonymousToken"
        )
    }

    func testTheBaseURLMayEndWithASlash() {
        let client = GrpcWebClient(baseURL: URL(string: "https://grpc-web.sinch-chat.prod.sinch.com/")!)

        XCTAssertEqual(
            client.url(for: "sinch.chat.sdk.v1alpha2.SdkService/IssueAnonymousToken").absoluteString,
            "https://grpc-web.sinch-chat.prod.sinch.com/sinch.chat.sdk.v1alpha2.SdkService/IssueAnonymousToken"
        )
    }
}
