//  SocketNotificationRequestTests.swift — the `UNNotificationRequest` the socket presenter builds.

import XCTest

@testable import SinchPushSDK

#if os(iOS)
import UserNotifications

final class SocketNotificationRequestTests: XCTestCase {

    private func event(_ id: String, trigger: String? = nil) -> SocketMessageEvent {
        var pooled = pooledMessage(messageID: id)
        pooled.pushNotification.trigger = trigger ?? ""
        return SocketMessageEvent(pooled: pooled, ackToken: "", receivedAt: 0)
    }

    func testAnAlertingNotificationHasASoundAndTheDefaultInterruptionLevel() {
        let content = SocketNotificationPresenter.makeRequest(for: event("m-1"), alerting: true).content

        XCTAssertNotNil(content.sound)
        XCTAssertEqual(content.interruptionLevel, .active)
    }

    func testASilentNotificationHasNoSoundAndIsPassive() {
        let message = event("m-1")

        let content = SocketNotificationPresenter.makeRequest(for: message, alerting: false).content

        XCTAssertNil(content.sound)
        XCTAssertEqual(content.interruptionLevel, .passive)
        XCTAssertEqual(content.title, message.title)
        XCTAssertEqual(content.body, message.body)
        XCTAssertEqual(content.categoryIdentifier, SocketNotificationPresenter.category)
        XCTAssertEqual(content.userInfo["source"] as? String, "socket")
    }

    func testTheThreadIsTheMessagesTriggerElseTheSharedOne() {
        for alerting in [true, false] {
            XCTAssertEqual(
                SocketNotificationPresenter.makeRequest(for: event("a", trigger: "chat-1"), alerting: alerting)
                    .content.threadIdentifier,
                "chat-1")
            XCTAssertEqual(
                SocketNotificationPresenter.makeRequest(for: event("b"), alerting: alerting)
                    .content.threadIdentifier,
                "sinchpush")
        }
    }

    func testTheRequestIdentifierIsTheMessageIdAndSourceStaysSocket() {
        let request = SocketNotificationPresenter.makeRequest(for: event("msg-42"), alerting: true)

        XCTAssertEqual(request.identifier, "msg-42")
        XCTAssertEqual(request.content.userInfo["source"] as? String, "socket")
        XCTAssertTrue(PushMessageIdentity.isSocketOriginated(userInfo: request.content.userInfo))
    }
}
#endif
