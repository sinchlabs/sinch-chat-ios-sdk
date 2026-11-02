import Foundation
import XCTest
@testable import SinchPushSDK

/// The live tests: they talk to the real backends. Skipped unless `SINCH_LIVE_TESTS=1`.
final class LiveGrpcWebTests: XCTestCase {

    private func requireLive() throws {
        try LiveTests.skipUnlessEnabled()
    }

    // MARK: - Chat: IssueAnonymousToken

    /// The chat backend answers `IssueAnonymousToken` with a JWT.
    ///
    /// The chat backend speaks gRPC-web: the answer is `application/grpc-web+proto` and
    /// carries the `grpc-status` in the trailer frame of the body.
    func testChatIssueAnonymousTokenReturnsAJWT() async throws {
        try requireLive()

        for chat in [LiveHosts.chatEU1, LiveHosts.chatUS1, LiveHosts.chatStaging] {
            let app = app(for: chat)
            let client = GrpcWebClient(baseURL: chat.baseURL)

            let response: Sinch_Chat_Sdk_V1alpha2_IssueAnonymousTokenResponse = try await client.unary(
                path: LiveHosts.issueAnonymousTokenPath,
                request: Sinch_Chat_Sdk_V1alpha2_IssueAnonymousTokenRequest.with {
                    $0.projectID = app.projectID
                    $0.clientID = app.clientID
                }
            )

            print("[live] chat \(chat.name) IssueAnonymousToken -> \(response.accessToken.count) chars")
            XCTAssertFalse(response.accessToken.isEmpty, "\(chat.name): no token")
            XCTAssertEqual(response.accessToken.split(separator: ".").count, 3, "\(chat.name): not a JWT")
        }
    }

    /// The chat backend answers `IssueTokenWithSignedUuid` with a JWT.
    ///
    /// The `uuid_hash` is the HMAC-SHA512 of the user id, keyed with the app secret: the
    /// backend refuses a raw secret with `grpc-status: 3` and the message `invalid hash`.
    func testChatIssueTokenWithSignedUuidReturnsAJWT() async throws {
        try requireLive()

        let chat = LiveHosts.chatStaging
        let app = LiveDemoConfig.inAppStaging
        let client = GrpcWebClient(baseURL: chat.baseURL)
        let userID = "spike-user-\(UUID().uuidString)"

        let response: Sinch_Chat_Sdk_V1alpha2_IssueTokenWithSignedUuidResponse = try await client.unary(
            path: LiveHosts.issueTokenWithSignedUuidPath,
            request: Sinch_Chat_Sdk_V1alpha2_IssueTokenWithSignedUuidRequest.with {
                $0.projectID = app.projectID
                $0.clientID = app.clientID
                $0.uuid = userID
                $0.uuidHash = LiveDemoConfig.hmacSHA512Hex(message: userID, key: app.secret ?? "")
            }
        )

        print("[live] chat \(chat.name) IssueTokenWithSignedUuid -> \(response.accessToken.count) chars")
        XCTAssertFalse(response.accessToken.isEmpty)
        XCTAssertEqual(response.accessToken.split(separator: ".").count, 3, "not a JWT")
    }

    /// The chat backend must refuse a call for an unknown project, and the refusal must be
    /// visible: the chat backend is gRPC-web, so it answers with a trailer frame.
    func testChatRefusesAnUnknownProject() async throws {
        try requireLive()

        let client = GrpcWebClient(baseURL: LiveHosts.chatEU1.baseURL)

        do {
            let response: Sinch_Chat_Sdk_V1alpha2_IssueAnonymousTokenResponse = try await client.unary(
                path: LiveHosts.issueAnonymousTokenPath,
                request: Sinch_Chat_Sdk_V1alpha2_IssueAnonymousTokenRequest.with {
                    $0.projectID = "00000000-0000-0000-0000-000000000000"
                    $0.clientID = "01ZZZZZZZZZZZZZZZZZZZZZZZZ"
                }
            )
            XCTFail("an unknown project was accepted: \(response.accessToken)")
        } catch let error as GrpcWebError {
            print("[live] chat eu1 unknown project -> \(error)")
            guard case .grpcStatus(let code, _) = error else {
                return XCTFail("unexpected error: \(error)")
            }
            XCTAssertEqual(code, GrpcWebStatus.notFound, "expected NOT_FOUND, got \(code)")
        }
    }

    // MARK: - Push: Subscribe and Unsubscribe

    /// The push backend answers `Subscribe` and `Unsubscribe`.
    ///
    /// The push backend is a **native gRPC** server: it answers `application/grpc+proto` and
    /// puts the `grpc-status` in the HTTP/2 trailers, which `URLSession` does not expose.
    /// The transport still works: the answer arrives as a gRPC frame, and a gRPC server
    /// sends a message frame only when the call succeeded. The status of a refused call
    /// stays invisible, so the test records what it saw instead of asserting a status.
    ///
    /// The `config` of an app belongs to the project of its app: the demo apps carry one
    /// config each, so a call with the wrong pair is refused by the server.
    func testPushSubscribeAndUnsubscribe() async throws {
        try requireLive()

        for (chat, push, app) in [(LiveHosts.chatEU1, LiveHosts.pushEU1, LiveDemoConfig.contactProStandard),
                                  (LiveHosts.chatUS1, LiveHosts.pushUS1, LiveDemoConfig.pushLab),
                                  (LiveHosts.chatStaging, LiveHosts.pushStaging, LiveDemoConfig.inAppStaging)] {
            let token = try await issueToken(chat: chat, app: app)
            // The push backend is native gRPC: the status is not visible, so the client
            // records the answer as it is.
            let client = GrpcWebClient(baseURL: push.baseURL, missingStatusPolicy: .record)
            let metadata = ["authorization": token]

            // Subscribe
            do {
                let call = try await client.call(
                    path: LiveHosts.subscribePath,
                    request: Sinch_Push_Sdk_V1beta1_SubscribeRequest.with {
                        $0.config = app.configID
                        $0.token = LiveDemoConfig.dummyAPNsToken
                    },
                    metadata: metadata
                )
                print("[live] push \(push.name) Subscribe -> http=\(call.httpStatus) status=\(call.status.map(String.init) ?? "(not visible)") messages=\(call.messages.count) content-type=\(call.responseHeaders["Content-Type"] ?? call.responseHeaders["content-type"] ?? "-")")
                XCTAssertEqual(call.httpStatus, 200, "\(push.name): the call did not reach the server")
            } catch let error as GrpcWebError {
                print("[live] push \(push.name) Subscribe -> \(error)")
                switch error {
                case .grpcStatus(let code, let message):
                    // The server answered with a status: the transport works.
                    print("[live] push \(push.name) Subscribe grpc-status=\(code) message=\(message ?? "-")")
                default:
                    XCTFail("\(push.name): Subscribe failed: \(error)")
                }
            }

            // Unsubscribe
            do {
                let call = try await client.call(
                    path: LiveHosts.unsubscribePath,
                    request: Sinch_Push_Sdk_V1beta1_UnsubscribeRequest.with {
                        $0.config = app.configID
                        $0.token = LiveDemoConfig.dummyAPNsToken
                    },
                    metadata: metadata
                )
                print("[live] push \(push.name) Unsubscribe -> http=\(call.httpStatus) status=\(call.status.map(String.init) ?? "(not visible)") messages=\(call.messages.count)")
                XCTAssertEqual(call.httpStatus, 200, "\(push.name): the call did not reach the server")
            } catch let error as GrpcWebError {
                print("[live] push \(push.name) Unsubscribe -> \(error)")
                switch error {
                case .grpcStatus(let code, let message):
                    print("[live] push \(push.name) Unsubscribe grpc-status=\(code) message=\(message ?? "-")")
                default:
                    XCTFail("\(push.name): Unsubscribe failed: \(error)")
                }
            }
        }
    }

    /// A push call with a token of the right project succeeds: the server sends a response
    /// message, which is the proof a gRPC server sends only when the call succeeded.
    func testPushSubscribeSucceedsWithAMatchingProjectAndConfig() async throws {
        try requireLive()

        let client = GrpcWebClient(baseURL: LiveHosts.pushUS1.baseURL, missingStatusPolicy: .record)

        let call = try await client.call(
            path: LiveHosts.subscribePath,
            request: Sinch_Push_Sdk_V1beta1_SubscribeRequest.with {
                $0.config = LiveDemoConfig.pushLab.configID
                $0.token = LiveDemoConfig.dummyAPNsToken
            },
            metadata: ["authorization": try await issueToken(chat: LiveHosts.chatUS1, app: LiveDemoConfig.pushLab)]
        )

        print("[live] push us1 Subscribe (matching project and config) -> http=\(call.httpStatus) messages=\(call.messages.count)")
        XCTAssertEqual(call.httpStatus, 200)
        XCTAssertTrue(call.sawResponseMessage, "the server sent no response message: the call did not succeed")
    }

    /// The push backend must refuse a call without a token.
    ///
    /// The refusal comes back as `grpc-status: 16` in the HTTP/2 trailers, which
    /// `URLSession` does not expose, so the client sees a 200 with no message frame.
    func testPushSubscribeWithoutATokenIsRefused() async throws {
        try requireLive()

        let client = GrpcWebClient(baseURL: LiveHosts.pushUS1.baseURL, missingStatusPolicy: .record)

        let call = try await client.call(
            path: LiveHosts.subscribePath,
            request: Sinch_Push_Sdk_V1beta1_SubscribeRequest.with {
                $0.config = LiveDemoConfig.pushLab.configID
                $0.token = LiveDemoConfig.dummyAPNsToken
            }
        )

        print("[live] push us1 Subscribe without a token -> http=\(call.httpStatus) status=\(call.status.map(String.init) ?? "(not visible)") messages=\(call.messages.count)")
        XCTAssertEqual(call.httpStatus, 200)
        XCTAssertFalse(call.sawResponseMessage, "the call without a token was accepted")
    }

    /// The push backend does not implement `ReportEvents` in the production regions.
    ///
    /// The refusal is `grpc-status: 12`, and it comes back in the HTTP headers: the push
    /// backend answers a call it cannot route with the status in the headers, not in the
    /// HTTP/2 trailers.
    func testPushReportEventsIsNotImplementedInProduction() async throws {
        try requireLive()

        let client = GrpcWebClient(baseURL: LiveHosts.pushUS1.baseURL)

        do {
            _ = try await client.call(
                path: LiveHosts.reportEventsPath,
                request: Sinch_Push_Sdk_V1beta1_ReportEventsRequest.with {
                    $0.events = [
                        Sinch_Push_Sdk_V1beta1_ReportedEvent.with {
                            $0.messageID = "0123456789012345678901234"
                            $0.subscriberID = "01M676PNEF1G67JXQEJ1CKEQRP"
                            $0.eventType = .delivered
                        }
                    ]
                },
                metadata: ["authorization": try await issueToken(chat: LiveHosts.chatUS1, app: LiveDemoConfig.pushLab)]
            )
            XCTFail("the production push backend implemented ReportEvents")
        } catch let error as GrpcWebError {
            print("[live] push us1 ReportEvents -> \(error)")
            guard case .grpcStatus(let code, let message) = error else {
                return XCTFail("unexpected error: \(error)")
            }
            XCTAssertEqual(code, GrpcWebStatus.unimplemented, "expected UNIMPLEMENTED, got \(code) \(message ?? "")")
        }
    }

    // MARK: - Helpers

    private func app(for chat: LiveHosts.Chat) -> LiveDemoConfig.App {
        switch chat.name {
        case "eu1": return LiveDemoConfig.contactProStandard
        case "us1": return LiveDemoConfig.pushLab
        default: return LiveDemoConfig.inAppStaging
        }
    }

    private func issueToken(chat: LiveHosts.Chat, app: LiveDemoConfig.App) async throws -> String {
        let client = GrpcWebClient(baseURL: chat.baseURL)
        let response: Sinch_Chat_Sdk_V1alpha2_IssueAnonymousTokenResponse = try await client.unary(
            path: LiveHosts.issueAnonymousTokenPath,
            request: Sinch_Chat_Sdk_V1alpha2_IssueAnonymousTokenRequest.with {
                $0.projectID = app.projectID
                $0.clientID = app.clientID
            }
        )
        return response.accessToken
    }
}
