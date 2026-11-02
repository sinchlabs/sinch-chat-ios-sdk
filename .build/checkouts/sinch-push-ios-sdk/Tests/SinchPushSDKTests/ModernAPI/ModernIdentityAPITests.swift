import Foundation
import XCTest
@testable import SinchPushSDK

/// The async identity API added in 1.1.0: it awaits the completion-handler implementation,
/// so these tests also cover that the token, the config and the logout path still run.
@MainActor
final class ModernIdentityAPITests: XCTestCase {

    private var sdk: SinchPushSDK!
    private var config: SinchSDKConfig.AppConfig!
    private var repository: StubAuthRepository!
    private var relay: RelayTestHarness!

    override func setUp() async throws {
        try await super.setUp()
        // `removeIdentity` reads the device token from standard defaults.
        UserDefaults.standard.removeObject(forKey: "sinch_device_token")
        config = SinchSDKConfig.AppConfig(clientID: "client-\(UUID().uuidString)",
                                          projectID: "project",
                                          configID: "config-\(UUID().uuidString)",
                                          region: .EU1,
                                          relay: .disabled)
        repository = StubAuthRepository(config: config)
        sdk = SinchPushSDK()
        sdk.storedAppConfigStore = StoredAppConfigStore(
            defaults: UserDefaults(suiteName: "sinch.tests.modern.identity.\(UUID().uuidString)")!)
        sdk.deliveryReportClientFactory = { _ in StubPushAPIClient() }
        sdk.authRepositoryFactory = { [repository] _, _ in repository! }
        // The live relay manager would need a notification centre; the fake wiring never connects.
        relay = RelayTestHarness()
        sdk.pushSocketManagerFactory = { [relay] in relay!.manager }
    }

    override func tearDown() async throws {
        KeychainAuthStorage(config: config).deleteToken()
        UserDefaults.standard.removeObject(forKey: "sinch_device_token")
        sdk = nil
        relay = nil
        try await super.tearDown()
    }

    // MARK: - setIdentity

    func testAsyncSetIdentityWithConfigSucceeds() async throws {
        try await sdk.setIdentity(config: config, identity: .anonymous)

        XCTAssertEqual(sdk.config, config)
        XCTAssertEqual(repository.anonymousRequests, 1, "the token was issued")
        XCTAssertEqual(sdk.storedAppConfigStore.load(), config,
                       "the success path persisted the config for background delivery reports")
    }

    func testAsyncSetIdentityWithConfigMapsTheBackendError() async {
        repository.result = .failure(.unknown(TestError.backend))

        do {
            try await sdk.setIdentity(config: config, identity: .anonymous)
            XCTFail("setIdentity must throw")
        } catch {
            guard case .internalError(let tracingID) = error else {
                return XCTFail("expected an internalError, got \(error)")
            }
            XCTAssertEqual(tracingID, "unknown", "an unmapped error keeps the completion API's mapping")
        }
        XCTAssertNil(sdk.authDataSource?.currentAuthorization)
        XCTAssertNil(sdk.storedAppConfigStore.load(), "a failed setIdentity persists nothing")
    }

    func testAsyncSetIdentityWithoutConfigSucceeds() async throws {
        sdk.initialize(config: config, options: .init(environment: .off))

        try await sdk.setIdentity(to: .anonymous)

        XCTAssertEqual(repository.anonymousRequests, 1, "the token was issued")
        XCTAssertEqual(sdk.storedAppConfigStore.load(), config)
    }

    func testAsyncSetIdentityWithoutConfigThrowsWithoutInitialize() async {
        do {
            try await sdk.setIdentity(to: .anonymous)
            XCTFail("setIdentity must throw without a config")
        } catch {
            guard case .internalError(let tracingID) = error else {
                return XCTFail("expected an internalError, got \(error)")
            }
            XCTAssertEqual(tracingID, "initialize(config:) was not called")
        }
    }

    // MARK: - removeIdentity

    func testAsyncRemoveIdentityDeletesTheToken() async throws {
        let auth = MockAuthDataSource()
        sdk.authDataSource = auth

        try await sdk.removeIdentity()

        XCTAssertTrue(auth.isTokenDeleted, "logout deletes the stored token")
    }

    func testAsyncRemoveIdentitySurfacesTheUnsubscribeError() async {
        sdk.pushRepositoryFactory = { [error = TestError.unsubscribe] _, _, _ in
            FailingPushRepository(error: error)
        }
        sdk.authDataSource = MockAuthDataSource()
        UserDefaults.standard.set("device-token", forKey: "sinch_device_token")

        do {
            try await sdk.removeIdentity()
            XCTFail("removeIdentity must throw when the unsubscribe fails")
        } catch {
            XCTAssertEqual(error as? TestError, .unsubscribe)
        }
    }
}

// MARK: - Doubles

private enum TestError: Error, Equatable {
    case backend
    case unsubscribe
}

/// The token repository `setIdentity` would build over the chat host, with the result under test.
private final class StubAuthRepository: AuthRepository, @unchecked Sendable {

    let configID: String
    var result: Result<AuthModel, AuthRepositoryError>
    private(set) var anonymousRequests = 0

    init(config: SinchSDKConfig.AppConfig,
         result: Result<AuthModel, AuthRepositoryError>? = nil) {
        self.configID = config.configID
        self.result = result ?? .success(
            AuthModel(accessToken: makeJWT(["uuid": "user-1"]),
                      sinchIdentity: .anonymous,
                      clientID: config.clientID,
                      projectID: config.projectID,
                      configID: config.configID,
                      region: config.region))
    }

    func createAnonymouseToken() async throws -> AuthModel {
        anonymousRequests += 1
        return try result.get()
    }

    func createSignedToken(userId: String, secret: String) async throws -> AuthModel {
        try result.get()
    }

    func createAnonymouseToken(completion: @escaping @Sendable (Result<AuthModel, AuthRepositoryError>) -> Void) {
        Task { [weak self] in
            guard let self else { return completion(.failure(.cannotEstablishConnection)) }
            do {
                completion(.success(try await self.createAnonymouseToken()))
            } catch let error as AuthRepositoryError {
                completion(.failure(error))
            } catch {
                completion(.failure(.unknown(error)))
            }
        }
    }

    func createSignedToken(userId: String, secret: String,
                           completion: @escaping @Sendable (Result<AuthModel, AuthRepositoryError>) -> Void) {
        Task { [weak self] in
            guard let self else { return completion(.failure(.cannotEstablishConnection)) }
            do {
                completion(.success(try await self.createSignedToken(userId: userId, secret: secret)))
            } catch let error as AuthRepositoryError {
                completion(.failure(error))
            } catch {
                completion(.failure(.unknown(error)))
            }
        }
    }
}

/// Fails every call, so `removeIdentity` takes its error path without the network.
private final class FailingPushRepository: PushRepository, @unchecked Sendable {

    let error: Error

    init(error: Error) {
        self.error = error
    }

    func sendDeviceToken(token: String, deviceInfo: DeviceInfo?) async throws -> String? { throw error }
    func unsubscribe(_ currentDeviceToken: String) async throws { throw error }

    func sendDeviceToken(token: String, deviceInfo: DeviceInfo?,
                         completion: @escaping @Sendable (Result<Void, Error>) -> Void) {
        completion(.failure(error))
    }

    func unsubscribe(_ currentDeviceToken: String,
                     _ completion: @escaping @Sendable (Result<Void, Error>) -> Void) {
        completion(.failure(error))
    }
}
