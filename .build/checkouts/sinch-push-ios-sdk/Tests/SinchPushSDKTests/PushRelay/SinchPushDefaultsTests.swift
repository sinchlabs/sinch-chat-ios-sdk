import Combine
import UserNotifications
import XCTest
@testable import SinchPushSDK

/// A host's own `SinchPush` (a test mock) written before the relay API existed: it implements none of it and must
/// keep compiling and behave like a relay that is not there.
@MainActor
private final class LegacyMockPush: SinchPush {
    func sendDeviceToken(_ token: Data) {}
    func handleNotification(_ payload: [AnyHashable: Any]) -> IsHandled { false }
    func handleNotificationResponse(_ notificationResponse: UNNotificationResponse) -> IsHandled { false }
    func handleWillPresentNotification(_ notification: UNNotification) -> UNNotificationPresentationOptions? { nil }
    func askNotificationPermission(completion: @escaping (SinchSDKNotificationStatus) -> Void) {}
    func checkPushPermission(completion: @escaping (SinchSDKNotificationStatus) -> Void) {}
    func askNotificationPermission() -> AnyPublisher<SinchSDKNotificationStatus, Never> { Empty().eraseToAnyPublisher() }
    func checkPushPermission() -> AnyPublisher<SinchSDKNotificationStatus, Never> { Empty().eraseToAnyPublisher() }
}

@MainActor
final class SinchPushDefaultsTests: XCTestCase {

    func testAMockWithoutTheRelayApiReportsADisabledRelay() {
        let push: SinchPush = LegacyMockPush()

        XCTAssertEqual(push.socketState.status, .idle)
        XCTAssertFalse(push.socketState.relayEnabled)
        XCTAssertNotNil(push.socketState.disabledReason)
        XCTAssertNil(push.installationId)
        push.reportStatus(messageId: "m-1", status: .displayed)
        push.setRelayEnabled(true)
        XCTAssertTrue(push.isRelayEnabled, "the toggle keeps its own default (on); socketState says whether a relay runs")
    }

    func testTheDefaultPublishersAreInertButSubscribable() {
        let push: SinchPush = LegacyMockPush()
        let states = PublisherCollector(push.socketStatePublisher)
        let messages = PublisherCollector(push.socketMessagePublisher)

        XCTAssertEqual(states.values, [push.socketState], "the current state is replayed once")
        XCTAssertTrue(messages.values.isEmpty)
    }

    func testTheSdksImplementationOverridesTheDefaults() {
        let rig = RelayTestHarness()
        let push: SinchPush = DefaultSinchPush(pushNotificationHandler: RoutingHandlerStub(),
                                               inAppPresenter: InAppControllerStub(),
                                               socketManager: rig.manager, relaySettings: rig.settings)
        XCTAssertEqual(push.installationId, "install-1")
        XCTAssertEqual(push.socketState.disabledReason, "relay not started (setIdentity has not succeeded yet)")
    }
}
