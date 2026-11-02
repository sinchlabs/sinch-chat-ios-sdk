import Combine
import UserNotifications
import XCTest
import SinchPushSDK

/// Source-compatibility proof for 1.1.0: the new async members and the existing
/// completion and Combine members are all reachable from the call sites an app uses.
final class ModernAPICompileTests: XCTestCase {

    @MainActor
    func testTheAsyncAndCompletionIdentityCallsCoexist() throws {
        // Only references, no network: the closure only has to type-check.
        let asyncWithConfig: (SinchPushSDK, SinchSDKConfig.AppConfig, SinchSDKIdentity) async throws -> Void = {
            try await $0.setIdentity(config: $1, identity: $2)
        }
        let asyncWithoutConfig: (SinchPushSDK, SinchSDKIdentity) async throws -> Void = {
            try await $0.setIdentity(to: $1)
        }
        let asyncLogout: (SinchPushSDK) async throws -> Void = {
            try await $0.removeIdentity()
        }
        let completionWithConfig: (SinchPushSDK, SinchSDKConfig.AppConfig, SinchSDKIdentity,
                                   (@Sendable (Result<Void, SinchSDKIdentityError>) -> Void)?) -> Void = {
            $0.setIdentity(with: $1, identity: $2, completion: $3)
        }
        let completionWithoutConfig: (SinchPushSDK, SinchSDKIdentity,
                                      (@Sendable (Result<Void, SinchSDKIdentityError>) -> Void)?) -> Void = {
            $0.setIdentity($1, completion: $2)
        }
        let completionLogout: (SinchPushSDK, (@Sendable (Result<Void, Error>) -> Void)?) -> Void = {
            $0.removeIdentity($1)
        }

        XCTAssertNotNil(asyncWithConfig)
        XCTAssertNotNil(asyncWithoutConfig)
        XCTAssertNotNil(asyncLogout)
        XCTAssertNotNil(completionWithConfig)
        XCTAssertNotNil(completionWithoutConfig)
        XCTAssertNotNil(completionLogout)
    }

    /// The async permission methods are named apart, so the Combine overload keeps
    /// resolving at its call site even inside an async function.
    @MainActor
    func testTheAsyncAndCombinePermissionCallsCoexist() async {
        let push: SinchPush = CompilePushStub()

        let asyncRequest: (SinchPush) async -> SinchSDKNotificationStatus = {
            await $0.requestNotificationPermission()
        }
        let asyncStatus: (SinchPush) async -> SinchSDKNotificationStatus = {
            await $0.notificationPermissionStatus()
        }
        let combineAsk: (SinchPush) -> AnyPublisher<SinchSDKNotificationStatus, Never> = {
            $0.askNotificationPermission()
        }
        let combineCheck: (SinchPush) -> AnyPublisher<SinchSDKNotificationStatus, Never> = {
            $0.checkPushPermission()
        }
        let completionAsk: (SinchPush, @escaping (SinchSDKNotificationStatus) -> Void) -> Void = {
            $0.askNotificationPermission(completion: $1)
        }
        let completionCheck: (SinchPush, @escaping (SinchSDKNotificationStatus) -> Void) -> Void = {
            $0.checkPushPermission(completion: $1)
        }

        // The Combine call site still compiles unawaited in an async context.
        let publisher: AnyPublisher<SinchSDKNotificationStatus, Never> = push.askNotificationPermission()
        let stream: AsyncStream<SinchPushSocketState> = push.socketStates
        let messages: AsyncStream<SinchPushSocketMessage> = push.socketMessages
        let events: AsyncStream<InAppMessageEvent> = SinchPushSDK.shared.inAppMessages.events

        XCTAssertNotNil(asyncRequest)
        XCTAssertNotNil(asyncStatus)
        XCTAssertNotNil(combineAsk)
        XCTAssertNotNil(combineCheck)
        XCTAssertNotNil(completionAsk)
        XCTAssertNotNil(completionCheck)
        XCTAssertNotNil(publisher)
        XCTAssertNotNil(stream)
        XCTAssertNotNil(messages)
        XCTAssertNotNil(events)
    }
}

/// The call-site checks need a `SinchPush`, not a running SDK.
@MainActor
private final class CompilePushStub: SinchPush {
    func sendDeviceToken(_ token: Data) {}
    func handleNotification(_ payload: [AnyHashable: Any]) -> IsHandled { false }
    func handleNotificationResponse(_ notificationResponse: UNNotificationResponse) -> IsHandled { false }
    func handleWillPresentNotification(_ notification: UNNotification) -> UNNotificationPresentationOptions? { nil }
    func askNotificationPermission(completion: @escaping (SinchSDKNotificationStatus) -> Void) {
        completion(.notDetermined)
    }
    func checkPushPermission(completion: @escaping (SinchSDKNotificationStatus) -> Void) {
        completion(.notDetermined)
    }
    func askNotificationPermission() -> AnyPublisher<SinchSDKNotificationStatus, Never> {
        Empty().eraseToAnyPublisher()
    }
    func checkPushPermission() -> AnyPublisher<SinchSDKNotificationStatus, Never> {
        Empty().eraseToAnyPublisher()
    }
}
