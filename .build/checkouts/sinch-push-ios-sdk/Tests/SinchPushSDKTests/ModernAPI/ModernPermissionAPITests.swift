import Combine
import UserNotifications
import XCTest
@testable import SinchPushSDK

/// The async permission API, exercised through the real `DefaultSinchPush` and the
/// permission handler it forwards to.
@MainActor
final class ModernPermissionAPITests: XCTestCase {

    private var rig: RelayTestHarness!
    private var handler: PermissionHandlerStub!
    private var push: DefaultSinchPush!

    override func setUp() async throws {
        try await super.setUp()
        rig = RelayTestHarness()
        handler = PermissionHandlerStub()
        push = DefaultSinchPush(pushNotificationHandler: handler,
                                inAppPresenter: InAppControllerStub(),
                                socketManager: rig.manager,
                                relaySettings: rig.settings)
    }

    func testRequestNotificationPermissionAwaitsTheHandler() async {
        handler.askResult = .granted

        let status = await push.requestNotificationPermission()

        XCTAssertEqual(status, .granted)
        XCTAssertEqual(handler.askCount, 1)
    }

    func testNotificationPermissionStatusDoesNotAsk() async {
        handler.checkResult = .denied
        handler.askResult = .granted

        let status = await push.notificationPermissionStatus()

        XCTAssertEqual(status, .denied)
        XCTAssertEqual(handler.checkCount, 1)
        XCTAssertEqual(handler.askCount, 0, "checking must not prompt the user")
    }

    /// The completion and Combine methods keep their names and their call sites; the
    /// async methods are named apart, so nothing becomes ambiguous.
    func testTheCompletionAndCombineApisStillCompileAndRun() {
        handler.askResult = .granted
        var completionStatuses: [SinchSDKNotificationStatus] = []
        push.askNotificationPermission { completionStatuses.append($0) }

        let combinePublisher: AnyPublisher<SinchSDKNotificationStatus, Never> = push.checkPushPermission()

        XCTAssertEqual(completionStatuses, [.granted])
        XCTAssertEqual(handler.askCount, 1)
        _ = combinePublisher
    }

    /// A `SinchPush` written against 1.0.0, with no async members of its own, gets the
    /// async defaults.
    func testAConformerWithoutTheAsyncApiGetsTheDefaults() async {
        let legacy = LegacyCompletionPush()
        let typed: SinchPush = legacy

        let requested = await typed.requestNotificationPermission()
        let current = await typed.notificationPermissionStatus()

        XCTAssertEqual(requested, .notDetermined)
        XCTAssertEqual(current, .granted)
        XCTAssertEqual(legacy.askCount, 1)
        XCTAssertEqual(legacy.checkCount, 1)
    }
}

// MARK: - Doubles

/// Records the permission calls and answers with the configured status.
final class PermissionHandlerStub: PushNotificationHandler, @unchecked Sendable {

    var pushRepository: PushRepository?
    var authDataSource: AuthDataSource?
    var askResult: SinchSDKNotificationStatus = .notDetermined
    var checkResult: SinchSDKNotificationStatus = .notDetermined
    private(set) var askCount = 0
    private(set) var checkCount = 0

    func sendDeviceToken(token: Data) {}
    func resubscribeIfNeeded() {}
    func unsubscribe(_ completion: @escaping @Sendable (Result<Void, Error>) -> Void) { completion(.success(())) }
    func handleNotification(payload: [AnyHashable: Any]) -> IsHandled { false }
    func handleWillPresentNotification(_ payload: [AnyHashable: Any]) -> UNNotificationPresentationOptions? { nil }
    func registerAddressee(_ service: PushNotificationAddressee) {}
    func removeAddressee(_ service: PushNotificationAddressee) {}
    func getAddressee(id: PushNotificationAddresseeName) -> PushNotificationAddressee? { nil }

    func askForPermissions(completion: ((SinchSDKNotificationStatus) -> Void)?) {
        askCount += 1
        completion?(askResult)
    }

    func checkIfPermissionIsGranted(completion: @escaping (SinchSDKNotificationStatus) -> Void) {
        checkCount += 1
        completion(checkResult)
    }
}

/// A host's own `SinchPush` from before the async API existed.
@MainActor
private final class LegacyCompletionPush: SinchPush {
    private(set) var askCount = 0
    private(set) var checkCount = 0

    func sendDeviceToken(_ token: Data) {}
    func handleNotification(_ payload: [AnyHashable: Any]) -> IsHandled { false }
    func handleNotificationResponse(_ notificationResponse: UNNotificationResponse) -> IsHandled { false }
    func handleWillPresentNotification(_ notification: UNNotification) -> UNNotificationPresentationOptions? { nil }

    func askNotificationPermission(completion: @escaping (SinchSDKNotificationStatus) -> Void) {
        askCount += 1
        completion(.notDetermined)
    }

    func checkPushPermission(completion: @escaping (SinchSDKNotificationStatus) -> Void) {
        checkCount += 1
        completion(.granted)
    }

    func askNotificationPermission() -> AnyPublisher<SinchSDKNotificationStatus, Never> {
        Empty().eraseToAnyPublisher()
    }

    func checkPushPermission() -> AnyPublisher<SinchSDKNotificationStatus, Never> {
        Just(.granted).eraseToAnyPublisher()
    }
}
