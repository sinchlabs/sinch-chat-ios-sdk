import Foundation
@testable import SinchPushSDK

/// An in-memory ``AuthDataSource`` for the push tests.
final class MockAuthDataSource: AuthDataSource, @unchecked Sendable {
    var currentAuthorization: AuthModel?

    var isLoggedIn: Bool = false

    var identityHashValue: String?

    var currentConfigID: String = ""

    var accessToken: String = "token"

    var generateTokenCompletion: Result<AuthModel, AuthRepositoryError> = .success(
        AuthModel(accessToken: "", sinchIdentity: .anonymous, clientID: "", projectID: "", configID: "", region: .EU1))

    var isTokenDeleted = false

    func generateToken(config: SinchSDKConfig.AppConfig, identity: SinchSDKIdentity) async throws -> AuthModel {
        isLoggedIn = true
        switch generateTokenCompletion {
        case .success(let token): return token
        case .failure(let error): throw error
        }
    }

    func generateToken(config: SinchSDKConfig.AppConfig, identity: SinchSDKIdentity,
                       completion: @escaping @Sendable (Result<AuthModel, AuthRepositoryError>) -> Void) {
        isLoggedIn = true
        completion(generateTokenCompletion)
    }

    func refreshToken() async throws -> AuthModel {
        try await generateToken(config: SinchSDKConfig.AppConfig(clientID: "", projectID: "", configID: "", region: .EU1),
                                identity: .anonymous)
    }

    func currentAccessToken() throws -> String {
        accessToken
    }

    func deleteToken() {
        isTokenDeleted = true
    }
}
