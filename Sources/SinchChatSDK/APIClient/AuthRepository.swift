import Foundation

enum AuthRepositoryError: Error {
    case unknown(Error)
    // Cannot create api client, report it to us, thank you!
    case internalError
}

typealias AccessToken = String

struct AuthModel: Codable {
    let accessToken: AccessToken
    let sinchIdentity: SinchSDKIdentity
    let clientID: String
    let projectID: String
    let configID: String
    let region: Region

    var identityHash: String? {
        guard let data = try? JSONEncoder().encode(self) else {
            return nil
        }
        return data.base64EncodedString()
    }
}

protocol AuthRepository {
    var configID: String { get }
    
    func createAnonymouseToken(completion: @escaping (Result<AuthModel, AuthRepositoryError>) -> Void)
    func createSignedToken(userId: String, secret: String, completion: @escaping (Result<AuthModel, AuthRepositoryError>) -> Void)
}

final class DefaultAuthRepository: AuthRepository {
    private let config: SinchSDKConfig.AppConfig

    var configID: String {
        config.configID
    }
    
    init(config: SinchSDKConfig.AppConfig) {
        self.config = config
    }

    func createAnonymouseToken(completion: @escaping (Result<AuthModel, AuthRepositoryError>) -> Void) {
        guard let client = DefaultAPIClient(region: config.region) else {
            completion(.failure(.internalError))
            return
        }
        let service = getService(client: client)

        var request = Sinch_Chat_Sdk_V1alpha2_IssueAnonymousTokenRequest()
        request.clientID = config.clientID
        request.projectID = config.projectID

        _ = service.issueAnonymousToken(request, callOptions: .standardCallOptions).response.always { result in
            client.closeChannel()

            switch result {
            case .success(let response):
                completion(.success(.init(accessToken: response.accessToken,
                                          sinchIdentity: .anonymous,
                                          clientID: self.config.clientID,
                                          projectID: self.config.projectID,
                                          configID: "test-config-id",
                                          region: self.config.region)))
            case .failure(let err):
                completion(.failure(.unknown(err)))
            }
        }
    }

    func createSignedToken(userId: String, secret: String, completion: @escaping (Result<AuthModel, AuthRepositoryError>) -> Void) {
        guard let client = DefaultAPIClient(region: config.region) else {
            completion(.failure(.internalError))
            return
        }
        let service = getService(client: client)
        
        var request = Sinch_Chat_Sdk_V1alpha2_IssueTokenWithSignedUuidRequest()

        request.clientID = config.clientID
        request.projectID = config.projectID
        request.uuid = userId
        request.uuidHash = secret

        _ = service.issueTokenWithSignedUuid(request, callOptions: .standardCallOptions).response.always { result in
            
            client.closeChannel()

            switch result {
            case .success(let response):
                completion(.success(.init(accessToken: response.accessToken,
                                          sinchIdentity:.selfSigned(userId: userId, secret: secret),
                                          clientID: self.config.clientID,
                                          projectID: self.config.projectID,
                                          configID: "test-protoc",
                                          region: self.config.region)))
            case .failure(let err):
                completion(.failure(.unknown(err)))
            }
        }
    }

    private func getService(client: APIClient) -> Sinch_Chat_Sdk_V1alpha2_SdkServiceClient {
            Sinch_Chat_Sdk_V1alpha2_SdkServiceClient(channel: client.getChannel())
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
