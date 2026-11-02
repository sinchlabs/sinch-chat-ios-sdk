import SinchPushSDKNotificationExtension
import XCTest

@testable import SinchPushSDK

final class GRPCWebReportEventsTests: XCTestCase {

    // MARK: - Request

    /// The generated message, the way the gRPC sender serialises it.
    private func generatedBytes(_ deliveries: [ReportedDelivery]) throws -> Data {
        try DeliveryReportSenderRequest.make(deliveries).serializedData()
    }

    func testTheProtobufIsByteIdenticalToTheGeneratedMessage() throws {
        let deliveries = [
            ReportedDelivery(messageID: "m-1", subscriberID: "s-1"),
            ReportedDelivery(messageID: "6f1c2a52-9d1f-4a43-8f55-0f1d1d3c7a10", subscriberID: "subscriber-with-a-longer-id")
        ]

        XCTAssertEqual(GRPCWebReportEvents.protobuf(for: deliveries), try generatedBytes(deliveries))
    }

    func testALongIdUsesAMultiByteLengthPrefix() throws {
        let deliveries = [ReportedDelivery(messageID: String(repeating: "m", count: 200),
                                           subscriberID: String(repeating: "s", count: 130))]

        XCTAssertEqual(GRPCWebReportEvents.protobuf(for: deliveries), try generatedBytes(deliveries))
    }

    func testAHundredDeliveriesAreByteIdentical() throws {
        let deliveries = (0..<100).map { ReportedDelivery(messageID: "message-\($0)", subscriberID: "subscriber-1") }

        XCTAssertEqual(GRPCWebReportEvents.protobuf(for: deliveries), try generatedBytes(deliveries))
    }

    func testAnEmptyIdIsLeftOutLikeProto3Does() throws {
        let deliveries = [ReportedDelivery(messageID: "m-1", subscriberID: "")]

        XCTAssertEqual(GRPCWebReportEvents.protobuf(for: deliveries), try generatedBytes(deliveries))
    }

    func testTheEventTypeIsDelivered() {
        XCTAssertEqual(GRPCWebReportEvents.deliveredEventType, UInt64(Sinch_Push_Events_V1beta1_PushEventType.delivered.rawValue))
    }

    func testTheBodyIsOneUncompressedFrame() throws {
        let deliveries = [ReportedDelivery(messageID: "m-1", subscriberID: "s-1")]
        let message = try generatedBytes(deliveries)

        let body = GRPCWebReportEvents.body(for: deliveries)

        XCTAssertEqual(body.prefix(5), Data([0x00, 0, 0, 0, UInt8(message.count)]))
        XCTAssertEqual(body.dropFirst(5), message)
    }

    func testTheRequestIsAGrpcWebPostWithTheRawToken() throws {
        let request = GRPCWebReportEvents.request(baseURL: URL(string: "https://grpc.sinch-push.prod.sinch.com")!,
                                                  accessToken: "jwt.value.here")

        XCTAssertEqual(request.url?.absoluteString,
                       "https://grpc.sinch-push.prod.sinch.com/sinch.push.sdk.v1beta1.SdkService/ReportEvents")
        XCTAssertEqual(request.httpMethod, "POST")
        XCTAssertEqual(request.value(forHTTPHeaderField: "Content-Type"), "application/grpc-web+proto")
        XCTAssertEqual(request.value(forHTTPHeaderField: "x-grpc-web"), "1")
        XCTAssertEqual(request.value(forHTTPHeaderField: "authorization"), "jwt.value.here")
    }

    func testThePushHostsOfTheRegions() {
        XCTAssertEqual(Region.EU1.pushReportBaseURL?.absoluteString, "https://grpc.sinch-push.prod.sinch.com")
        XCTAssertEqual(Region.US1.pushReportBaseURL?.absoluteString, "https://grpc.sinch-push.us1.prod.sinch.com")
        XCTAssertEqual(
            Region.custom(host: "chat.example", pushAPIHost: "grpc.sinch-push.eu1tst.staging.sinch.com", port: nil,
                          isSecure: true).pushReportBaseURL?.absoluteString,
            "https://grpc.sinch-push.eu1tst.staging.sinch.com")
    }

    // MARK: - Response

    private func frame(flag: UInt8, _ payload: Data) -> Data {
        var data = Data([flag])
        withUnsafeBytes(of: UInt32(payload.count).bigEndian) { data.append(contentsOf: $0) }
        return data + payload
    }

    private func trailer(_ text: String) -> Data {
        frame(flag: 0x80, Data(text.utf8))
    }

    func testAnOkTrailerFrameIsASuccess() {
        let body = frame(flag: 0x00, Data()) + trailer("grpc-status: 0\r\n")

        XCTAssertEqual(GRPCWebReportEvents.outcome(httpStatus: 200, headerGrpcStatus: nil, body: body), .success)
    }

    func testANonZeroTrailerStatusFailsWithItsMessage() {
        let body = trailer("grpc-status: 16\r\ngrpc-message: token expired\r\n")

        XCTAssertEqual(GRPCWebReportEvents.outcome(httpStatus: 200, headerGrpcStatus: nil, body: body),
                       .grpcFailure(status: 16, message: "token expired"))
    }

    func testTheHeaderStatusIsReadWhenThereIsNoTrailer() {
        XCTAssertEqual(GRPCWebReportEvents.outcome(httpStatus: 200, headerGrpcStatus: "0", body: Data()), .success)
        XCTAssertEqual(GRPCWebReportEvents.outcome(httpStatus: 200, headerGrpcStatus: "14", body: Data()),
                       .grpcFailure(status: 14, message: nil))
    }

    func testTheTrailerWinsOverTheHeader() {
        let body = trailer("grpc-status: 0\r\n")

        XCTAssertEqual(GRPCWebReportEvents.outcome(httpStatus: 200, headerGrpcStatus: "13", body: body), .success)
    }

    func testAnAnswerWithoutAnyStatusIsMalformedNotASuccess() {
        XCTAssertEqual(GRPCWebReportEvents.outcome(httpStatus: 200, headerGrpcStatus: nil, body: Data()), .malformed)
        let dataOnly = frame(flag: 0x00, Data([1, 2, 3]))
        XCTAssertEqual(GRPCWebReportEvents.outcome(httpStatus: 200, headerGrpcStatus: nil, body: dataOnly), .malformed)
    }

    func testATrailerWithoutAStatusIsMalformed() {
        XCTAssertEqual(GRPCWebReportEvents.outcome(httpStatus: 200, headerGrpcStatus: nil,
                                                   body: trailer("grpc-message: hi\r\n")), .malformed)
    }

    func testAnHttpErrorFailsWhateverTheBodySays() {
        let body = trailer("grpc-status: 0\r\n")

        XCTAssertEqual(GRPCWebReportEvents.outcome(httpStatus: 503, headerGrpcStatus: nil, body: body),
                       .httpFailure(status: 503))
    }

    func testACutShortFrameIsMalformed() {
        let body = Data([0x80, 0, 0, 0, 20, 0x67])

        XCTAssertEqual(GRPCWebReportEvents.outcome(httpStatus: 200, headerGrpcStatus: nil, body: body), .malformed)
    }

    func testTrailerKeysAreCaseInsensitive() {
        let body = trailer("Grpc-Status: 7\r\nGrpc-Message: denied\r\n")

        XCTAssertEqual(GRPCWebReportEvents.outcome(httpStatus: 200, headerGrpcStatus: nil, body: body),
                       .grpcFailure(status: 7, message: "denied"))
    }
}

final class ReportEndpointTests: XCTestCase {

    func testThePresetsAreHttpsOnTheDefaultPort() {
        XCTAssertEqual(ReportEndpoint.baseURL(pushHost: ReportEndpoint.eu1Host)?.absoluteString,
                       "https://grpc.sinch-push.prod.sinch.com")
    }

    func testACustomPortAndPlaintextAreKept() {
        XCTAssertEqual(ReportEndpoint.baseURL(pushHost: "push.local", port: 8443, isSecure: true)?.absoluteString,
                       "https://push.local:8443")
        XCTAssertEqual(ReportEndpoint.baseURL(pushHost: "push.local", port: 8080, isSecure: false)?.absoluteString,
                       "http://push.local:8080")
        XCTAssertEqual(ReportEndpoint.baseURL(pushHost: "push.local", isSecure: false)?.absoluteString,
                       "http://push.local")
    }

    func testAPortInTheHostWinsOverThePortOfTheRegion() {
        XCTAssertEqual(ReportEndpoint.baseURL(pushHost: "push.local:9000", port: 8443)?.absoluteString,
                       "https://push.local:9000")
    }

    func testASchemeAndAPathInTheHostAreTolerated() {
        XCTAssertEqual(ReportEndpoint.baseURL(pushHost: "http://push.local:8080/ignored")?.absoluteString,
                       "http://push.local:8080")
        XCTAssertEqual(ReportEndpoint.baseURL(pushHost: "https://push.local/")?.absoluteString, "https://push.local")
    }

    func testABareIPv6HostIsAHostWithoutAPort() {
        XCTAssertEqual(ReportEndpoint.baseURL(pushHost: "::1")?.absoluteString, "https://[::1]")
        XCTAssertEqual(ReportEndpoint.baseURL(pushHost: "::1", port: 8443, isSecure: false)?.absoluteString,
                       "http://[::1]:8443")
        XCTAssertEqual(ReportEndpoint.baseURL(pushHost: "2001:db8::1")?.absoluteString, "https://[2001:db8::1]")
    }

    func testABracketedIPv6HostMayCarryAPort() {
        XCTAssertEqual(ReportEndpoint.baseURL(pushHost: "[::1]")?.absoluteString, "https://[::1]")
        XCTAssertEqual(ReportEndpoint.baseURL(pushHost: "[::1]:8443")?.absoluteString, "https://[::1]:8443")
        XCTAssertEqual(ReportEndpoint.baseURL(pushHost: "http://[::1]:8080/x")?.absoluteString, "http://[::1]:8080")
    }

    func testAnUnusableHostHasNoURL() {
        XCTAssertNil(ReportEndpoint.baseURL(pushHost: ""))
        XCTAssertNil(ReportEndpoint.baseURL(pushHost: "[::1"))
        XCTAssertNil(ReportEndpoint.baseURL(pushHost: "[::1]:port"))
        XCTAssertNil(ReportEndpoint.baseURL(pushHost: "push.local:port"))
        XCTAssertNil(ReportEndpoint.baseURL(pushHost: "push.local", port: 70000))
    }

    func testTheRegionsMapToTheirEndpoints() {
        XCTAssertEqual(Region.EU1.pushReportBaseURL?.absoluteString, "https://grpc.sinch-push.prod.sinch.com")
        XCTAssertEqual(Region.US1.pushReportBaseURL?.absoluteString, "https://grpc.sinch-push.us1.prod.sinch.com")
        XCTAssertEqual(Region.custom(host: "chat.local", pushAPIHost: "push.local", port: 8443, isSecure: true)
                        .pushReportBaseURL?.absoluteString, "https://push.local:8443")
        XCTAssertEqual(Region.custom(host: "chat.local", pushAPIHost: "push.local", port: 8080, isSecure: false)
                        .pushReportBaseURL?.absoluteString, "http://push.local:8080")
        XCTAssertEqual(Region.custom(host: "chat.local", pushAPIHost: "push.local:9000", port: nil, isSecure: nil)
                        .pushReportBaseURL?.absoluteString, "https://push.local:9000")
    }
}

/// The request the gRPC sender builds, by the sender's own code.
enum DeliveryReportSenderRequest {
    static func make(_ deliveries: [ReportedDelivery]) -> Sinch_Push_Sdk_V1beta1_ReportEventsRequest {
        PushAPIDeliveryReportSender.reportRequest(deliveries.map {
            DeliveryReport(messageID: $0.messageID, subscriberID: $0.subscriberID, enqueuedAtMs: 0)
        })
    }
}
