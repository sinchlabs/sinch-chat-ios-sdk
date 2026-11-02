import XCTest

@testable import SinchChatSDK

/// The async `setIdentity`/`removeIdentity` of `SinchChatSDK`: the same call and side effects as the completion
/// forms, awaited instead of called back.
///
/// The push facade is stubbed through `pushSetIdentity`/`pushRemoveIdentity`, so the tests never touch the network or
/// the Keychain. Everything after the stub — the chat side effects of a success, the identity event, the error
/// propagation — is the real implementation.
@MainActor
final class IdentityAPITests: XCTestCase {

    private let config = modernAPIConfig()

    // MARK: - setIdentity

    func testAsyncSetIdentityForwardsTheCallAndAppliesTheChatSideEffects() async throws {
        let sdk = SinchChatSDK()
        let receivedConfig = Locked<SinchSDKConfig.AppConfig?>(nil)
        let receivedIdentity = Locked<SinchSDKIdentity?>(nil)

        sdk.pushSetIdentity = { config, identity, completion in
            receivedConfig.value = config
            receivedIdentity.value = identity
            completion(.success(()))
        }

        try await sdk.setIdentity(config: config, identity: .selfSigned(userId: "user", secret: "secret"))

        XCTAssertEqual(receivedConfig.value, config, "the async form must forward the config unchanged")
        XCTAssertEqual(receivedIdentity.value, .selfSigned(userId: "user", secret: "secret"),
                       "the async form must forward the identity unchanged")
        XCTAssertEqual(sdk.config, config, "a successful setIdentity records the config, as the completion form does")
    }

    func testAsyncSetIdentityWaitsForTheCompletionHandler() async throws {
        let sdk = SinchChatSDK()
        let didComplete = Locked(false)

        sdk.pushSetIdentity = { _, _, completion in
            DispatchQueue.global().asyncAfter(deadline: .now() + 0.1) {
                didComplete.value = true
                completion(.success(()))
            }
        }

        try await sdk.setIdentity(config: config, identity: .anonymous)

        XCTAssertTrue(didComplete.value, "the async call must return only after the completion handler ran")
    }

    func testAsyncSetIdentityPropagatesTheIdentityErrorAndSkipsTheChatSetup() async {
        let sdk = SinchChatSDK()

        sdk.pushSetIdentity = { _, _, completion in
            completion(.failure(.internalError(tracingID: "tracing-id")))
        }

        do {
            try await sdk.setIdentity(config: config, identity: .anonymous)
            XCTFail("expected the identity error to be thrown")
        } catch {
            guard case let .internalError(tracingID) = error else {
                return XCTFail("unexpected error \(error)")
            }
            XCTAssertEqual(tracingID, "tracing-id")
        }

        XCTAssertNil(sdk.config, "a failed setIdentity must not record the config")
    }

    func testACompletionThatFiresTwiceDoesNotTrap() async throws {
        let sdk = SinchChatSDK()
        let calls = Locked(0)

        sdk.pushSetIdentity = { _, _, completion in
            calls.mutate { $0 += 1 }
            completion(.success(()))
            completion(.success(()))
        }

        // A second resume of a checked continuation would trap the process: the wrapper ignores it instead.
        try await sdk.setIdentity(config: config, identity: .anonymous)

        XCTAssertEqual(calls.value, 1)
    }

    // MARK: - removeIdentity

    func testAsyncRemoveIdentityForwardsTheCallAndSendsThePluginEvent() async throws {
        let sdk = SinchChatSDK()
        let forwarded = Locked(false)
        let recorder = PluginEventRecorder(subject: SinchChatSDK.shared.eventListenerSubject)

        sdk.pushRemoveIdentity = { completion in
            forwarded.value = true
            completion(.success(()))
        }

        try await sdk.removeIdentity()

        XCTAssertTrue(forwarded.value, "the async form must forward to the push SDK")
        XCTAssertEqual(recorder.count(of: .didRemoveIdentity), 1,
                       "a successful removeIdentity sends .didRemoveIdentity")
    }

    func testAsyncRemoveIdentityWaitsForTheCompletionHandler() async throws {
        let sdk = SinchChatSDK()
        let didComplete = Locked(false)

        sdk.pushRemoveIdentity = { completion in
            DispatchQueue.global().asyncAfter(deadline: .now() + 0.1) {
                didComplete.value = true
                completion(.success(()))
            }
        }

        try await sdk.removeIdentity()

        XCTAssertTrue(didComplete.value, "the async call must return only after the completion handler ran")
    }

    func testAsyncRemoveIdentityPropagatesTheError() async {
        let sdk = SinchChatSDK()

        sdk.pushRemoveIdentity = { completion in
            completion(.failure(ModernAPIError.boom))
        }

        do {
            try await sdk.removeIdentity()
            XCTFail("expected the error to be thrown")
        } catch {
            XCTAssertEqual(error as? ModernAPIError, .boom)
        }
    }
}
