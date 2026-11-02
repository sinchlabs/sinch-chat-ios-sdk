import Foundation

#if os(iOS)
import UserNotifications
import os

/// The `userInfo` keys a socket notification carries.
enum SocketNotificationUserInfoKey {
    static let messageId = "messageId"
    static let sinchMessageId = "sinchMessageId"
    static let source = "source"
    static let socketSource = "socket"
}

/// Posts socket notifications.
///
/// `@unchecked Sendable` because it subclasses `NSObject`. Response routing lives in
/// `DefaultSinchPush`. `post` is deliberately not `@MainActor`, since the client's
/// sequencing depends on its completion.
final class SocketNotificationPresenter: NSObject, NotificationPresenting, @unchecked Sendable {
    /// The category of socket notifications. It carries the dismiss action.
    static let category = "sinchpush.socket"

    /// The request identifier of a socket notification, which is the message id itself.
    ///
    /// It matches the `apns-collapse-id`, so an APNs copy and the local copy replace each other.
    static func identifier(messageId: String) -> String { messageId }

    private let registration = OSAllocatedUnfairLock(initialState: false)

    var handlerRegistered: Bool {
        get { registration.withLock { $0 } }
        set { registration.withLock { $0 = newValue } }
    }

    private let center: UNUserNotificationCenter

    init(center: UNUserNotificationCenter = .current()) {
        self.center = center
        super.init()
    }

    func post(
        _ message: SocketMessageEvent, alerting: Bool, completion: @escaping @Sendable (Bool) -> Void
    ) {
        registerCategory()
        let request = SocketNotificationPresenter.makeRequest(for: message, alerting: alerting)
        center.add(request) { error in
            // Only an accepted request counts as shown.
            completion(error == nil)
        }
    }

    /// The request for `message`. The thread, sound and passive rules come from ``SocketNotificationStyle``.
    static func makeRequest(for message: SocketMessageEvent, alerting: Bool) -> UNNotificationRequest {
        let content = UNMutableNotificationContent()
        // An absent title leaves the system's default, which shows the app name.
        if let title = message.title { content.title = title }
        if let body = message.body { content.body = body }
        let style = SocketNotificationStyle(alerting: alerting, trigger: message.trigger)
        content.threadIdentifier = style.threadIdentifier
        if style.playsSound {
            content.sound = .default
        } else {
            content.sound = nil
        }
        if style.passive {
            content.interruptionLevel = .passive
        }
        content.categoryIdentifier = SocketNotificationPresenter.category
        var userInfo: [String: Any] = message.metadata
        userInfo[SocketNotificationUserInfoKey.messageId] = message.id
        userInfo[SocketNotificationUserInfoKey.sinchMessageId] = message.sinchMessageId
        userInfo[SocketNotificationUserInfoKey.source] = SocketNotificationUserInfoKey.socketSource
        content.userInfo = userInfo

        // The identifier is the message id, which is also the APNs `apns-collapse-id`, so the two copies replace each other.
        return UNNotificationRequest(
            identifier: identifier(messageId: message.id),
            content: content, trigger: nil)
    }

    /// Registers `sinchpush.socket`, keeping the host's existing categories.
    func registerCategory() {
        center.getNotificationCategories { [weak self] existing in
            guard let self else { return }
            let category = UNNotificationCategory(
                identifier: SocketNotificationPresenter.category,
                actions: [],
                intentIdentifiers: [],
                // Without this, the system never reports a swipe, so DISMISSED cannot be sent.
                options: [.customDismissAction])
            var merged = existing.filter { $0.identifier != SocketNotificationPresenter.category }
            merged.insert(category)
            self.center.setNotificationCategories(merged)
        }
    }
}

/// Answers whether a notification id is already in the notification centre.
final class SystemDeliveredNotificationLookup: DeliveredNotificationLookup, @unchecked Sendable {
    private let center: UNUserNotificationCenter

    init(center: UNUserNotificationCenter = .current()) {
        self.center = center
    }

    func isDelivered(identifier: String, completion: @escaping @Sendable (Bool) -> Void) {
        center.getDeliveredNotifications { delivered in
            completion(delivered.contains { $0.request.identifier == identifier })
        }
    }
}
#endif
