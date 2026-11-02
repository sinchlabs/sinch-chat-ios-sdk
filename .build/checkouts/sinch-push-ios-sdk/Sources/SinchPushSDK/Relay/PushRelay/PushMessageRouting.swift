import Foundation
import UserNotifications

extension PushMessageIdentity {
    /// Whether the socket presenter posted the notification. `source` alone is not proof, since a remote payload can carry it.
    static func isSocketSourced(userInfo: [AnyHashable: Any], categoryIdentifier: String? = nil) -> Bool {
        guard isSocketOriginated(userInfo: userInfo) else { return false }
        guard let categoryIdentifier else { return true }
        return categoryIdentifier == SocketNotificationPresenter.category
    }

    /// The `messageId` entry, or the request identifier, which the presenter sets to the message id.
    static func socketMessageId(userInfo: [AnyHashable: Any], requestIdentifier: String?) -> String? {
        if let id = userInfo[SocketNotificationUserInfoKey.messageId] as? String, !id.isEmpty { return id }
        if let requestIdentifier, !requestIdentifier.isEmpty { return requestIdentifier }
        return nil
    }
}

/// Presentation options for a relay notification that no addressee claimed.
enum SocketPresentation {
    /// Banner and sound.
    static let alerting: UNNotificationPresentationOptions = [.banner, .list, .sound]
    /// The list only, silently.
    static let silent: UNNotificationPresentationOptions = [.list]

    /// The deprecated `.alert`, spelled by raw value to avoid the deprecation warning.
    static let legacyAlert = UNNotificationPresentationOptions(rawValue: 1 << 2)

    /// At most the list and the badge. The legacy `.alert` becomes banner and list, which the list-only rule then drops.
    static func silenced(_ options: UNNotificationPresentationOptions) -> UNNotificationPresentationOptions {
        var options = options
        if options.contains(legacyAlert) { options.formUnion([.banner, .list]) }
        return options.intersection([.list, .badge])
    }
}
