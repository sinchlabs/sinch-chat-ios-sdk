import Foundation
import XCTest
import SwiftProtobuf

@testable import SinchPushSDK

/// The push repository over gRPC-web: what it posts, and how it reads a refused call.
final class PushRepositoryTests: XCTestCase {

    override func setUp() {
        super.setUp()
        StubURLProtocol.store.set(answer: nil)
    }

    // MARK: - Subscribe over gRPC-web

    func testSendDeviceTokenPostsAFramedSubscribeAndReturnsTheSubscriberID() async throws {
        StubURLProtocol.store.set(answer: .frames(Self.subscribeAnswer(subscriberID: "sub-1")))
        let repository = makeRepository(client: StubTransportPushAPIClient())

        let subscriberID = try await repository.sendDeviceToken(token: "device-token", deviceInfo: nil)

        XCTAssertEqual(subscriberID, "sub-1")
        let request = try XCTUnwrap(StubURLProtocol.lastRequest)
        XCTAssertEqual(request.httpMethod, "POST")
        XCTAssertEqual(request.url?.path, "/sinch.push.sdk.v1beta1.SdkService/Subscribe")
        XCTAssertEqual(request.value(forHTTPHeaderField: "Content-Type"), "application/grpc-web+proto")
        XCTAssertEqual(request.value(forHTTPHeaderField: "X-Grpc-Web"), "1")
        XCTAssertEqual(request.value(forHTTPHeaderField: "authorization"), "token")
        let body = try XCTUnwrap(StubURLProtocol.lastBody)
        let framed = try GrpcWebFraming.parse(body)
        let sent = try Sinch_Push_Sdk_V1beta1_SubscribeRequest(serializedBytes: try XCTUnwrap(framed.firstMessage))
        XCTAssertEqual(sent.token, "device-token")
        XCTAssertEqual(sent.config, "config-1")
    }

    func testAHeaderStatusIsAnErrorEvenWhenNoMessageArrives() async throws {
        StubURLProtocol.store.set(answer: StubURLProtocol.Answer(
            statusCode: 200,
            headers: ["grpc-status": "16"]))
        let repository = makeRepository(client: StubTransportPushAPIClient())

        do {
            try await repository.sendDeviceToken(token: "t", deviceInfo: nil)
            XCTFail("Expected the refused call to throw")
        } catch let error as GrpcWebError {
            XCTAssertEqual(error.grpcStatusCode, GrpcWebStatus.unauthenticated)
        }
    }

    func testAReceivedMessageWithNoVisibleStatusCountsAsSuccess() async throws {
        // What the native gRPC push host answers over HTTP/2: a message frame, no visible status.
        let payload = try Sinch_Push_Sdk_V1beta1_SubscribeResponse.with { $0.subscriberID = "sub-2" }.serializedData()
        StubURLProtocol.store.set(answer: .frames(GrpcWebFraming.frame(payload)))
        let repository = makeRepository(client: StubTransportPushAPIClient())

        let subscriberID = try await repository.sendDeviceToken(token: "t", deviceInfo: nil)

        XCTAssertEqual(subscriberID, "sub-2")
    }

    func testUnsubscribeSwallowsAServerError() async throws {
        StubURLProtocol.store.set(answer: StubURLProtocol.Answer(statusCode: 200,
                                                                 headers: ["grpc-status": "16"]))
        let repository = makeRepository(client: StubTransportPushAPIClient())

        try await repository.unsubscribe("device-token")
    }

    func testWithoutAPushClientSendFails() async {
        let repository = DefaultPushRepository(region: .EU1, authDataSource: MockAuthDataSource(), client: NoPushAPIClient())

        do {
            try await repository.sendDeviceToken(token: "t", deviceInfo: nil)
            XCTFail("Expected no transport")
        } catch {
            XCTAssertEqual(error as? PushRepositoryError, .internalError)
        }
    }

    // MARK: - Subscribe request

    func testSubscribeRequestCarriesTheDeviceInfoWithThePushPlatformEnum() {
        let request = DefaultPushRepository.subscribeRequest(
            token: "device-token",
            config: "config-1",
            deviceInfo: .fixture(installationId: "0b8f3d52-7c1e-4a96-b5d0-2e9f6a4c8d17",
                                 osVersion: "18.1.1",
                                 sdkVersion: "1.0.0-prod",
                                 bundleId: "com.example.app"))

        XCTAssertEqual(request.token, "device-token")
        XCTAssertEqual(request.config, "config-1")
        XCTAssertEqual(request.installationID, "0b8f3d52-7c1e-4a96-b5d0-2e9f6a4c8d17")
        XCTAssertEqual(request.platform, Sinch_Push_V1beta1_Resources_Platform.ios)
        // resources.Platform IOS = 3, not the websocket enum's IOS = 1 (CONTRACT section 2.2).
        XCTAssertEqual(request.platform.rawValue, 3)
        XCTAssertEqual(request.osVersion, "18.1.1")
        XCTAssertEqual(request.sdkVersion, "1.0.0-prod")
        XCTAssertEqual(request.bundleID, "com.example.app")
        XCTAssertEqual(request.backgroundService, Sinch_Push_V1beta1_Resources_BackgroundServiceState.unsupported)
        XCTAssertEqual(request.backgroundService.rawValue, 1)
        XCTAssertTrue(request.hasInstallationID && request.hasPlatform && request.hasOsVersion
                      && request.hasSdkVersion && request.hasBundleID && request.hasBackgroundService)
        // The legacy fields stay untouched.
        XCTAssertFalse(request.hasDeviceToken)
        XCTAssertFalse(request.hasConfigID)
    }

    func testSubscribeRequestSurvivesTheWireWithTheDeviceFields() throws {
        let request = DefaultPushRepository.subscribeRequest(
            token: "t", config: "c", deviceInfo: .fixture())
        let bytes: [UInt8] = try request.serializedBytes()
        let decoded = try Sinch_Push_Sdk_V1beta1_SubscribeRequest(serializedBytes: bytes)
        XCTAssertEqual(decoded, request)
        XCTAssertEqual(decoded.platform.rawValue, 3)
    }

    func testSubscribeRequestDoesNotSetEmptyTokenOrConfig() {
        let request = DefaultPushRepository.subscribeRequest(token: "", config: "", deviceInfo: nil)

        XCTAssertFalse(request.hasToken)
        XCTAssertFalse(request.hasConfig)
    }

    func testSubscribeRequestWithoutDeviceInfoHasNoDeviceFields() {
        let request = DefaultPushRepository.subscribeRequest(token: "t", config: "c", deviceInfo: nil)

        XCTAssertEqual(request.token, "t")
        XCTAssertEqual(request.config, "c")
        assertNoDeviceFields(request)
    }

    func testSubscribeRequestWithoutInstallationIdHasNoDeviceFieldsAtAll() {
        let request = DefaultPushRepository.subscribeRequest(
            token: "t", config: "c", deviceInfo: .fixture(installationId: ""))
        assertNoDeviceFields(request)
        XCTAssertEqual(request.token, "t")
    }

    private func assertNoDeviceFields(_ request: Sinch_Push_Sdk_V1beta1_SubscribeRequest,
                                      file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertFalse(request.hasInstallationID, file: file, line: line)
        XCTAssertFalse(request.hasPlatform, file: file, line: line)
        XCTAssertFalse(request.hasOsVersion, file: file, line: line)
        XCTAssertFalse(request.hasSdkVersion, file: file, line: line)
        XCTAssertFalse(request.hasBundleID, file: file, line: line)
        XCTAssertFalse(request.hasBackgroundService, file: file, line: line)
    }

    // The wrappers must call back even when the last owner is released before the Task starts.
    func testCompletionVariantsCallBackAfterTheLastOwnerIsReleased() {
        let iterations = 100
        let done = expectation(description: "completions")
        done.expectedFulfillmentCount = iterations * 2

        for _ in 0..<iterations {
            let repository = DefaultPushRepository(
                region: .EU1,
                authDataSource: MockAuthDataSource(),
                client: NoPushAPIClient())
            repository.sendDeviceToken(token: "t", deviceInfo: nil) { _ in done.fulfill() }
            repository.unsubscribe("t") { _ in done.fulfill() }
        }

        wait(for: [done], timeout: 10)
    }

    // MARK: - Helpers

    private func makeRepository(client: PushAPIClient) -> DefaultPushRepository {
        let auth = MockAuthDataSource()
        auth.currentConfigID = "config-1"
        auth.accessToken = "token"
        return DefaultPushRepository(region: .EU1, authDataSource: auth, client: client)
    }

    /// A Subscribe answer the gRPC-web client reads: a message frame and a trailer frame with `grpc-status: 0`.
    private static func subscribeAnswer(subscriberID: String) -> Data {
        let message = Sinch_Push_Sdk_V1beta1_SubscribeResponse.with { $0.subscriberID = subscriberID }
        var body = GrpcWebFraming.frame(try! message.serializedData())
        body.append(GrpcWebFraming.trailerFrame(["grpc-status": "0"]))
        return body
    }
}

/// A push client whose region resolved, but which has no transport to make the test's calls with.
private struct NoPushAPIClient: PushAPIClient {
    var grpcWebClient: GrpcWebClient? { nil }
    func closeChannel() {}
}

/// A push client over the ``StubURLProtocol``'s answer (which the test sets on the store).
struct StubTransportPushAPIClient: PushAPIClient {
    let grpcWebClient: GrpcWebClient?

    init() {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [StubURLProtocol.self]
        self.grpcWebClient = GrpcWebClient(
            baseURL: URL(string: "https://grpc.sinch-push.prod.sinch.com")!,
            session: URLSession(configuration: configuration),
            missingStatusPolicy: .acceptIfMessageReceived)
    }

    func closeChannel() {}
}
