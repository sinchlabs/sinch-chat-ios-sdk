import Foundation
import XCTest
@testable import SinchPushSDK

/// Source-compatibility proof: the 1.0.0 completion call shapes and the 1.1.0 async names coexist.
///
/// Nothing in `OverloadCompileChecks` is called by a test. The point is that every spelling type-checks inside one
/// `async` function — the regression this guards against is an async overload that steals the completion form's call
/// shape, which would make `setIdentity(with:identity:)`, `setIdentity(_:)` and `removeIdentity(nil)` stop compiling
/// without `try await`. If that happened, this file would no longer build.
private enum OverloadCompileChecks {

    /// The 1.0.0 forms, called from an async function exactly as an app written against 1.0.0 does.
    ///
    /// Each call is bound to `Void`, which only the synchronous completion form returns: an async overload resolving
    /// the same spelling would need `try await` and would fail to type-check here.
    @MainActor
    static func completionFormsFromAnAsyncContext(_ config: SinchSDKConfig.AppConfig) async {
        let withConfig: Void = SinchPushSDK.shared.setIdentity(with: config, identity: .anonymous)
        let withoutConfig: Void = SinchPushSDK.shared.setIdentity(.anonymous)
        let logout: Void = SinchPushSDK.shared.removeIdentity(nil)
        let trailing: Void = SinchPushSDK.shared.removeIdentity { _ in }
        _ = (withConfig, withoutConfig, logout, trailing)
    }

    /// The same forms outside an async context, plus the completion labels spelled out.
    @MainActor
    static func completionFormsFromASynchronousContext(_ sdk: SinchPushSDK,
                                                      _ config: SinchSDKConfig.AppConfig) {
        sdk.setIdentity(with: config, identity: .anonymous)
        sdk.setIdentity(with: config, identity: .anonymous, completion: nil)
        sdk.setIdentity(.anonymous)
        sdk.setIdentity(.anonymous, completion: { _ in })
        sdk.removeIdentity(nil)
        sdk.removeIdentity { _ in }
    }

    /// The 1.1.0 async forms, with their distinct labels.
    @MainActor
    static func asyncForms(_ sdk: SinchPushSDK,
                           _ config: SinchSDKConfig.AppConfig) async throws {
        try await sdk.setIdentity(config: config, identity: .anonymous)
        try await sdk.setIdentity(to: .anonymous)
        try await sdk.removeIdentity()
    }

    /// The overloads are distinct functions, not two spellings of one.
    @MainActor
    static func distinctReferences(_ sdk: SinchPushSDK) {
        let completionWithConfig: (SinchSDKConfig.AppConfig, SinchSDKIdentity,
                                   (@Sendable (Result<Void, SinchSDKIdentityError>) -> Void)?) -> Void =
            sdk.setIdentity(with:identity:completion:)
        let completionWithoutConfig: (SinchSDKIdentity,
                                      (@Sendable (Result<Void, SinchSDKIdentityError>) -> Void)?) -> Void =
            sdk.setIdentity(_:completion:)
        let asyncWithConfig: (SinchSDKConfig.AppConfig, SinchSDKIdentity) async throws -> Void =
            sdk.setIdentity(config:identity:)
        let asyncWithoutConfig: (SinchSDKIdentity) async throws -> Void = sdk.setIdentity(to:)
        let completionLogout: ((@Sendable (Result<Void, Error>) -> Void)?) -> Void = sdk.removeIdentity(_:)
        let asyncLogout: () async throws -> Void = sdk.removeIdentity

        _ = (completionWithConfig, completionWithoutConfig, asyncWithConfig, asyncWithoutConfig,
             completionLogout, asyncLogout)
    }
}

/// The completion call shape still reaches the completion implementation when it is written inside an `async` body.
@MainActor
final class OverloadCoexistenceTests: XCTestCase {

    private var config: SinchSDKConfig.AppConfig!

    override func setUp() async throws {
        try await super.setUp()
        config = SinchSDKConfig.AppConfig(clientID: "client-\(UUID().uuidString)",
                                          projectID: "project",
                                          configID: "config-\(UUID().uuidString)",
                                          region: .EU1,
                                          relay: .disabled)
    }

    override func tearDown() async throws {
        KeychainAuthStorage(config: config).deleteToken()
        config = nil
        try await super.tearDown()
    }

    /// The 1.0.0 spelling, compiled and executed from an async test method, goes to the token request as before.
    func testTheCompletionCallShapeFromAnAsyncContextReachesTheTokenRepository() async {
        let sdk = SinchPushSDK()
        sdk.storedAppConfigStore = StoredAppConfigStore(
            defaults: UserDefaults(suiteName: "sinch.tests.overload.\(UUID().uuidString)")!)
        let repository = SignalAuthRepository(config: config)
        sdk.authRepositoryFactory = { _, _ in repository }
        let requested = expectation(description: "the completion implementation ran")
        repository.onAnonymousToken = { requested.fulfill() }

        // No completion argument: the 1.0.0 call shape, resolving to the completion overload.
        sdk.setIdentity(with: config, identity: .anonymous)

        await fulfillment(of: [requested], timeout: 5)
        XCTAssertEqual(repository.anonymousRequests, 1)
    }

    /// The async spelling reaches the same implementation the completion one does.
    func testTheAsyncCallShapeReachesTheSameTokenRepository() async throws {
        let sdk = SinchPushSDK()
        sdk.storedAppConfigStore = StoredAppConfigStore(
            defaults: UserDefaults(suiteName: "sinch.tests.overload.\(UUID().uuidString)")!)
        let repository = SignalAuthRepository(config: config)
        sdk.authRepositoryFactory = { _, _ in repository }

        do {
            try await sdk.setIdentity(config: config, identity: .anonymous)
        } catch {
            guard case .internalError = error else { return XCTFail("unexpected error \(error)") }
        }

        XCTAssertEqual(repository.anonymousRequests, 1)
    }
}

/// A token repository that reports the call and fails, so the test needs no relay or report wiring.
private final class SignalAuthRepository: AuthRepository, @unchecked Sendable {

    enum StubError: Error { case notInThisTest }

    let configID: String
    private(set) var anonymousRequests = 0
    var onAnonymousToken: (@Sendable () -> Void)?

    init(config: SinchSDKConfig.AppConfig) {
        self.configID = config.configID
    }

    func createAnonymouseToken() async throws -> AuthModel {
        anonymousRequests += 1
        onAnonymousToken?()
        throw StubError.notInThisTest
    }

    func createSignedToken(userId: String, secret: String) async throws -> AuthModel {
        throw StubError.notInThisTest
    }

    func createAnonymouseToken(completion: @escaping @Sendable (Result<AuthModel, AuthRepositoryError>) -> Void) {
        anonymousRequests += 1
        onAnonymousToken?()
        completion(.failure(.unknown(StubError.notInThisTest)))
    }

    func createSignedToken(userId: String, secret: String,
                           completion: @escaping @Sendable (Result<AuthModel, AuthRepositoryError>) -> Void) {
        completion(.failure(.unknown(StubError.notInThisTest)))
    }
}
