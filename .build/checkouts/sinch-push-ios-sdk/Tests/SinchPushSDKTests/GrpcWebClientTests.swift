import Foundation
import XCTest
@testable import SinchPushSDK

/// A `URLProtocol` that answers with a canned answer, so the client can be tested offline.
final class StubURLProtocol: URLProtocol {
    /// What the next request is answered with.
    struct Answer {
        var statusCode: Int = 200
        var headers: [String: String] = [:]
        var body: Data = Data()
        var error: Error?

        static func frames(_ data: Data) -> Answer { Answer(body: data) }
    }

    /// What the stub recorded. The lock keeps the static state safe under Swift 6.
    final class Store: @unchecked Sendable {
        private let lock = NSLock()
        private var answer: Answer?
        private var lastRequest: URLRequest?
        private var lastBody: Data?

        func set(answer: Answer?) {
            lock.withLock { self.answer = answer }
        }
        func currentAnswer() -> Answer? {
            lock.withLock { answer }
        }
        func record(request: URLRequest, body: Data?) {
            lock.withLock {
                self.lastRequest = request
                self.lastBody = body
            }
        }
        func take() -> (request: URLRequest?, body: Data?) {
            lock.withLock { (lastRequest, lastBody) }
        }
    }

    /// The recorded state of the stub.
    static let store = Store()

    /// The request the client made.
    static var lastRequest: URLRequest? { store.take().request }
    /// The body the client sent.
    static var lastBody: Data? { store.take().body }

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        let body: Data?
        if let stream = request.httpBodyStream {
            body = Self.readAll(stream)
        } else {
            body = request.httpBody
        }
        StubURLProtocol.store.record(request: request, body: body)

        guard let answer = StubURLProtocol.store.currentAnswer() else {
            client?.urlProtocol(self, didFailWithError: URLError(.unsupportedURL))
            return
        }
        if let error = answer.error {
            client?.urlProtocol(self, didFailWithError: error)
            return
        }
        let response = HTTPURLResponse(url: request.url!,
                                       statusCode: answer.statusCode,
                                       httpVersion: "HTTP/1.1",
                                       headerFields: answer.headers)!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: answer.body)
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}

    /// Reads a body stream to its end.
    private static func readAll(_ stream: InputStream) -> Data {
        var data = Data()
        stream.open()
        defer { stream.close() }
        let size = 4096
        var buffer = [UInt8](repeating: 0, count: size)
        while stream.hasBytesAvailable {
            let read = stream.read(&buffer, maxLength: size)
            guard read > 0 else { break }
            data.append(buffer, count: read)
        }
        return data
    }

    /// A session that answers with `answer`.
    static func session(answer: Answer) -> URLSession {
        store.set(answer: answer)
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [StubURLProtocol.self]
        return URLSession(configuration: configuration)
    }
}

/// The offline tests of the client: what it sends, and how it reads an answer.
final class GrpcWebClientTests: XCTestCase {

    override func setUp() {
        super.setUp()
        StubURLProtocol.store.set(answer: nil)
    }

    private func client(answer: StubURLProtocol.Answer) -> GrpcWebClient {
        GrpcWebClient(baseURL: URL(string: "https://example.test")!,
                      session: StubURLProtocol.session(answer: answer))
    }

    // MARK: - The request

    func testTheRequestIsAFramedPost() async throws {
        let session = StubURLProtocol.session(answer: .frames(Data()))
        let client = GrpcWebClient(baseURL: URL(string: "https://example.test")!,
                                   session: session,
                                   missingStatusPolicy: .record)

        _ = try await client.call(path: "sinch.chat.sdk.v1alpha2.SdkService/IssueAnonymousToken",
                                  request: Sinch_Chat_Sdk_V1alpha2_IssueAnonymousTokenRequest.with {
                                      $0.projectID = "p"
                                      $0.clientID = "c"
                                  })

        let request = try XCTUnwrap(StubURLProtocol.lastRequest)
        XCTAssertEqual(request.httpMethod, "POST")
        XCTAssertEqual(request.url?.absoluteString,
                       "https://example.test/sinch.chat.sdk.v1alpha2.SdkService/IssueAnonymousToken")
        XCTAssertEqual(request.value(forHTTPHeaderField: "Content-Type"), "application/grpc-web+proto")
        XCTAssertEqual(request.value(forHTTPHeaderField: "Accept"), "application/grpc-web+proto")
        XCTAssertEqual(request.value(forHTTPHeaderField: "X-Grpc-Web"), "1")
    }

    func testTheMetadataBecomesHeaders() async throws {
        let session = StubURLProtocol.session(answer: .frames(Data()))
        let client = GrpcWebClient(baseURL: URL(string: "https://example.test")!,
                                   session: session,
                                   missingStatusPolicy: .record)

        _ = try await client.call(path: "svc/Method",
                                  request: Sinch_Chat_Sdk_V1alpha2_IssueAnonymousTokenRequest(),
                                  metadata: ["authorization": "a-jwt"])

        let request = try XCTUnwrap(StubURLProtocol.lastRequest)
        XCTAssertEqual(request.value(forHTTPHeaderField: "authorization"), "a-jwt")
    }

    func testTheBodyIsTheFramedMessage() async throws {
        let session = StubURLProtocol.session(answer: .frames(Data()))
        let client = GrpcWebClient(baseURL: URL(string: "https://example.test")!,
                                   session: session,
                                   missingStatusPolicy: .record)
        let request = Sinch_Chat_Sdk_V1alpha2_IssueAnonymousTokenRequest.with {
            $0.projectID = "p"
            $0.clientID = "c"
        }

        _ = try await client.call(path: "svc/Method", request: request)

        let body = try XCTUnwrap(StubURLProtocol.lastBody)
        let expected = GrpcWebFraming.frame(try request.serializedData())
        XCTAssertEqual(body, expected)
        XCTAssertEqual([UInt8](body.prefix(5))[0], 0x00, "the frame flag is not 0")
    }

    // MARK: - The answer

    func testReadsTheMessageAndTheTrailerFrame() async throws {
        var body = GrpcWebFraming.frame(try Sinch_Chat_Sdk_V1alpha2_IssueAnonymousTokenResponse.with {
            $0.accessToken = "a-jwt"
        }.serializedData())
        body.append(GrpcWebFraming.trailerFrame(["grpc-status": "0"]))

        let client = self.client(answer: .frames(body))

        let response: Sinch_Chat_Sdk_V1alpha2_IssueAnonymousTokenResponse = try await client.unary(
            path: "svc/Method",
            request: Sinch_Chat_Sdk_V1alpha2_IssueAnonymousTokenRequest()
        )

        XCTAssertEqual(response.accessToken, "a-jwt")
    }

    func testANonZeroTrailerStatusIsAnError() async throws {
        var body = GrpcWebFraming.trailerFrame(["grpc-status": "5", "grpc-message": "not found"])
        body = Data([0x80]) + body.dropFirst()

        let client = self.client(answer: .frames(body))

        do {
            let response: Sinch_Chat_Sdk_V1alpha2_IssueAnonymousTokenResponse = try await client.unary(
                path: "svc/Method",
                request: Sinch_Chat_Sdk_V1alpha2_IssueAnonymousTokenRequest()
            )
            XCTFail("the call was accepted: \(response.accessToken)")
        } catch let error as GrpcWebError {
            guard case .grpcStatus(let code, let message) = error else {
                return XCTFail("unexpected error: \(error)")
            }
            XCTAssertEqual(code, 5)
            XCTAssertEqual(message, "not found")
        }
    }

    func testTheStatusMayComeFromAHeader() async throws {
        let client = self.client(answer: StubURLProtocol.Answer(
            headers: ["grpc-status": "12", "grpc-message": "not implemented"],
            body: Data()
        ))

        do {
            let response: Sinch_Chat_Sdk_V1alpha2_IssueAnonymousTokenResponse = try await client.unary(
                path: "svc/Method",
                request: Sinch_Chat_Sdk_V1alpha2_IssueAnonymousTokenRequest()
            )
            XCTFail("the call was accepted: \(response.accessToken)")
        } catch let error as GrpcWebError {
            guard case .grpcStatus(let code, _) = error else {
                return XCTFail("unexpected error: \(error)")
            }
            XCTAssertEqual(code, 12)
        }
    }

    func testANonSuccessHTTPStatusIsAnError() async throws {
        let client = self.client(answer: StubURLProtocol.Answer(statusCode: 404, body: Data("nope".utf8)))

        do {
            let response: Sinch_Chat_Sdk_V1alpha2_IssueAnonymousTokenResponse = try await client.unary(
                path: "svc/Method",
                request: Sinch_Chat_Sdk_V1alpha2_IssueAnonymousTokenRequest()
            )
            XCTFail("the call was accepted: \(response.accessToken)")
        } catch let error as GrpcWebError {
            guard case .httpStatus(let code, _) = error else {
                return XCTFail("unexpected error: \(error)")
            }
            XCTAssertEqual(code, 404)
        }
    }

    func testATransportFailureIsAnError() async throws {
        let client = self.client(answer: StubURLProtocol.Answer(error: URLError(.networkConnectionLost)))

        do {
            let response: Sinch_Chat_Sdk_V1alpha2_IssueAnonymousTokenResponse = try await client.unary(
                path: "svc/Method",
                request: Sinch_Chat_Sdk_V1alpha2_IssueAnonymousTokenRequest()
            )
            XCTFail("the call was accepted: \(response.accessToken)")
        } catch let error as GrpcWebError {
            guard case .transport = error else {
                return XCTFail("unexpected error: \(error)")
            }
        }
    }

    /// A native gRPC server over HTTP/2 answers without a status: the answer carries no
    /// trailer frame and no `grpc-status` header.
    func testAMissingStatusFailsByDefault() async throws {
        let client = self.client(answer: .frames(Data()))

        do {
            let response: Sinch_Chat_Sdk_V1alpha2_IssueAnonymousTokenResponse = try await client.unary(
                path: "svc/Method",
                request: Sinch_Chat_Sdk_V1alpha2_IssueAnonymousTokenRequest()
            )
            XCTFail("the call was accepted: \(response.accessToken)")
        } catch let error as GrpcWebError {
            guard case .missingStatus(let sawResponseMessage) = error else {
                return XCTFail("unexpected error: \(error)")
            }
            XCTAssertFalse(sawResponseMessage)
        }
    }

    func testAMissingStatusWithAMessageIsAcceptedByTheLenientPolicy() async throws {
        // The message frame carries field 1 = "abc".
        let body = GrpcWebFraming.frame(Data([0x0a, 0x03, 0x61, 0x62, 0x63]))
        let session = StubURLProtocol.session(answer: .frames(body))
        let client = GrpcWebClient(baseURL: URL(string: "https://example.test")!,
                                   session: session,
                                   missingStatusPolicy: .acceptIfMessageReceived)

        let response: Sinch_Chat_Sdk_V1alpha2_IssueAnonymousTokenResponse = try await client.unary(
            path: "svc/Method",
            request: Sinch_Chat_Sdk_V1alpha2_IssueAnonymousTokenRequest()
        )

        XCTAssertEqual(response.accessToken, "abc")
    }

    func testAMissingStatusIsRecordedByTheRecordPolicy() async throws {
        let client = GrpcWebClient(baseURL: URL(string: "https://example.test")!,
                                   session: StubURLProtocol.session(answer: .frames(Data())),
                                   missingStatusPolicy: .record)

        let call = try await client.call(path: "svc/Method",
                                         request: Sinch_Chat_Sdk_V1alpha2_IssueAnonymousTokenRequest())

        XCTAssertNil(call.status)
        XCTAssertFalse(call.sawResponseMessage)
        XCTAssertEqual(call.httpStatus, 200)
    }

    func testAnEmptyAnswerDecodesToAnEmptyMessage() async throws {
        var body = GrpcWebFraming.frame(Data())
        body.append(GrpcWebFraming.trailerFrame(["grpc-status": "0"]))

        let client = self.client(answer: .frames(body))

        let response: Sinch_Push_Sdk_V1beta1_SubscribeResponse = try await client.unary(
            path: "svc/Method",
            request: Sinch_Push_Sdk_V1beta1_SubscribeRequest()
        )

        XCTAssertFalse(response.hasSubscriberID)
    }
}
