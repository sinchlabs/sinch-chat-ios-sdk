import Foundation
import SinchPushSDKNotificationExtension

enum AuthRepositoryError: Error, Sendable {
    case unknown(any Error)
    // Cannot create api client, report it to us, thank you!
    case internalError(tracingID: String)
    case cannotEstablishConnection
}

public typealias AccessToken = String

public struct AuthModel: Codable, Equatable, Sendable {
    public let accessToken: AccessToken
    public let sinchIdentity: SinchSDKIdentity
    public let clientID: String
    public let projectID: String
    public let configID: String
    public let region: Region

    public var identityHash: String? {
        guard let data = try? JSONEncoder().encode(self) else {
            return nil
        }
        return data.base64EncodedString()
    }

    public func getUserID() -> String? {
        do {
            let payload = try JWTDecoder.decode(jwtToken: accessToken)
            return payload["uuid"] as? String

        } catch {
            return nil

        }
    }

    public static func == (lhs: AuthModel, rhs: AuthModel) -> Bool {
        lhs.accessToken == rhs.accessToken &&
        lhs.identityHash == rhs.identityHash &&
        compareWithoutAccessToken(lhs: lhs, rhs: rhs)
    }

    public static func compareWithoutAccessToken(lhs: AuthModel, rhs: AuthModel) -> Bool {
        return lhs.clientID == rhs.clientID &&
        lhs.configID == rhs.configID &&
        lhs.projectID == rhs.projectID &&
        lhs.region == rhs.region &&
        lhs.getUserID() == rhs.getUserID()
    }
}

/// The chat backend's two token RPCs over gRPC-web.
///
/// Push calls sinch-chat only to get an access token; everything else goes to sinch-push. The chat backend speaks
/// gRPC-web, so the status arrives in the trailer frame of the body (or in the headers when the call is refused).
struct ChatAuthClient: Sendable {

    static let issueAnonymousTokenPath = "sinch.chat.sdk.v1alpha2.SdkService/IssueAnonymousToken"
    static let issueTokenWithSignedUuidPath = "sinch.chat.sdk.v1alpha2.SdkService/IssueTokenWithSignedUuid"

    let client: GrpcWebClient

    /// `nil` when the region has no usable host.
    init?(region: Region) {
        guard let url = Self.baseURL(region: region) else { return nil }
        self.client = GrpcWebClient(baseURL: url, missingStatusPolicy: .fail)
    }

    /// The gRPC-web base URL of the chat backend of a region.
    static func baseURL(region: Region) -> URL? {
        ReportEndpoint.baseURL(pushHost: region.chatHost, port: region.port, isSecure: region.isSecure)
    }
}

protocol AuthRepository: Sendable {
    var configID: String { get }

    /// Async token issuance. Preferred for new code paths.
    func createAnonymouseToken() async throws -> AuthModel
    func createSignedToken(userId: String, secret: String) async throws -> AuthModel

    /// Backwards-compatible completion-handler entry points. Implemented in
    /// terms of the async methods above.
    func createAnonymouseToken(completion: @escaping @Sendable (Result<AuthModel, AuthRepositoryError>) -> Void)
    func createSignedToken(userId: String, secret: String,
                           completion: @escaping @Sendable (Result<AuthModel, AuthRepositoryError>) -> Void)
}

final class DefaultAuthRepository: AuthRepository, @unchecked Sendable {
    private let config: SinchSDKConfig.AppConfig
    private let client: ChatAuthClient?
    private let metadata: StandardMetadata

    var configID: String {
        config.configID
    }

    /// - Parameter client: The chat token service. `nil` builds one from the region, which may still fail to resolve.
    init(config: SinchSDKConfig.AppConfig, client: ChatAuthClient? = nil, metadata: StandardMetadata = .init()) {
        self.config = config
        self.client = client ?? ChatAuthClient(region: config.region)
        self.metadata = metadata
    }

    deinit {}

    /// The token RPCs answer within a few seconds, or the user waits for a login that will not happen.
    static let callTimeout: Duration = .seconds(5)

    // MARK: - Async API

    func createAnonymouseToken() async throws -> AuthModel {
        guard let client else { throw AuthRepositoryError.internalError(tracingID: "no chat host for the region") }
        let request = Sinch_Chat_Sdk_V1alpha2_IssueAnonymousTokenRequest.with {
            $0.clientID = config.clientID
            $0.projectID = config.projectID
        }

        do {
            let response: Sinch_Chat_Sdk_V1alpha2_IssueAnonymousTokenResponse = try await client.client.unary(
                path: ChatAuthClient.issueAnonymousTokenPath,
                request: request,
                metadata: metadata.headers(),
                timeout: Self.callTimeout)
            return AuthModel(
                accessToken: response.accessToken,
                sinchIdentity: .anonymous,
                clientID: config.clientID,
                projectID: config.projectID,
                configID: config.configID,
                region: config.region
            )
        } catch {
            throw Self.mapError(error)
        }
    }

    func createSignedToken(userId: String, secret: String) async throws -> AuthModel {
        guard let client else { throw AuthRepositoryError.internalError(tracingID: "no chat host for the region") }
        let request = Sinch_Chat_Sdk_V1alpha2_IssueTokenWithSignedUuidRequest.with {
            $0.clientID = config.clientID
            $0.projectID = config.projectID
            $0.uuid = userId
            $0.uuidHash = secret
        }

        do {
            let response: Sinch_Chat_Sdk_V1alpha2_IssueTokenWithSignedUuidResponse = try await client.client.unary(
                path: ChatAuthClient.issueTokenWithSignedUuidPath,
                request: request,
                metadata: metadata.headers(),
                timeout: Self.callTimeout)
            return AuthModel(
                accessToken: response.accessToken,
                sinchIdentity: .selfSigned(userId: userId, secret: secret),
                clientID: config.clientID,
                projectID: config.projectID,
                configID: config.configID,
                region: config.region
            )
        } catch {
            throw Self.mapError(error)
        }
    }

    // MARK: - Completion-handler API (compatibility layer)

    func createAnonymouseToken(completion: @escaping @Sendable (Result<AuthModel, AuthRepositoryError>) -> Void) {
        Task { [config] in
            do {
                let token = try await createAnonymouseToken()
                completion(.success(token))
            } catch let error as AuthRepositoryError {
                completion(.failure(error))
            } catch {
                completion(.failure(.unknown(error)))
            }
        }
    }

    func createSignedToken(userId: String, secret: String,
                           completion: @escaping @Sendable (Result<AuthModel, AuthRepositoryError>) -> Void) {
        Task { [config] in
            do {
                let token = try await createSignedToken(userId: userId, secret: secret)
                completion(.success(token))
            } catch let error as AuthRepositoryError {
                completion(.failure(error))
            } catch {
                completion(.failure(.unknown(error)))
            }
        }
    }

    // MARK: - Private

    /// The mapping the grpc-swift-2 `RPCError` codes had: the codes that mean "the SDK cannot recover" become an
    /// internal error with the server message as the tracing id, everything else keeps the underlying error.
    static func mapError(_ error: Error) -> AuthRepositoryError {
        guard case let GrpcWebError.grpcStatus(code, message) = error else {
            return .unknown(error)
        }
        switch code {
        case GrpcWebStatus.deadlineExceeded,
             GrpcWebStatus.unauthenticated,
             GrpcWebStatus.internalError,
             GrpcWebStatus.unknown,
             GrpcWebStatus.dataLoss,
             GrpcWebStatus.failedPrecondition:
            return .internalError(tracingID: message ?? "")
        default:
            return .unknown(error)
        }
    }
}

extension AccessToken {

    var userID: String? {
        guard let decodedJWT = try? decode(jwtToken: self) else {
            return nil
        }
        return decodedJWT["uuid"] as? String
    }

    private func decode(jwtToken jwt: String) throws -> [String: Any] {

        enum DecodeErrors: Error {
            case badToken
            case other
        }

        func base64Decode(_ base64: String) throws -> Data {
            let padded = base64.padding(toLength: ((base64.count + 3) / 4) * 4, withPad: "=", startingAt: 0)
            guard let decoded = Data(base64Encoded: padded) else {
                throw DecodeErrors.badToken
            }
            return decoded
        }

        func decodeJWTPart(_ value: String) throws -> [String: Any] {
            let bodyData = try base64Decode(value)
            let json = try JSONSerialization.jsonObject(with: bodyData, options: [])
            guard let payload = json as? [String: Any] else {
                throw DecodeErrors.other
            }
            return payload
        }

        let segments = jwt.components(separatedBy: ".")
        if segments.count != 3 {
            return [:]
        }
        return try decodeJWTPart(segments[1])
    }

}
