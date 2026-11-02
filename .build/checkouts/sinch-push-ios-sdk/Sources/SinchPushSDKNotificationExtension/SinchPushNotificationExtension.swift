import Foundation
import UserNotifications

/// Reports the delivery of a Sinch push from a Notification Service Extension.
///
/// An extension runs for every visible push that carries `mutable-content: 1`, also when the app was force-quit,
/// which no background wake of the app does. Add the `SinchPushSDKNotificationExtension` library to the extension
/// target only, and call ``didReceive(_:appGroup:)`` first thing in
/// `UNNotificationServiceExtension.didReceive(_:withContentHandler:)`.
/// See `Documentation/NotificationServiceExtension.md`.
public enum SinchPushNotificationExtension {

    /// Queues a DELIVERED report for a Sinch push and hands it to a background `URLSession` upload; returns quickly.
    /// The upload outlives the extension, so call this and then your `contentHandler` straight away.
    ///
    /// The report is signed with the access token the app mirrors into the App Group, so the app must have called
    /// `SinchPushSDK.shared.initialize(config:options:)` with `appGroup` set and `setIdentity` at least once.
    ///
    /// If the upload fails (the server refuses it, a 5xx, no network), or the mirrored token has expired and the
    /// upload is not even tried, the delivery is stored in the App Group and the app reports it the next time it runs.
    ///
    /// - Parameters:
    ///   - request: The request the extension received.
    ///   - appGroup: The App Group id shared by the app and the extension, the one passed to `initialize`.
    /// - Returns: `false` for a push that is not a Sinch push, when no shared session exists (the app never called
    ///   `initialize` with `appGroup`, or has no identity), and when the upload could not be started; `true` when the
    ///   delivery was handed to the upload, was left to the app, or was reported before.
    @discardableResult
    public static func didReceive(_ request: UNNotificationRequest, appGroup: String) -> Bool {
        didReceive(userInfo: request.content.userInfo, container: ReportContainer(appGroup: appGroup)) { container in
            // A session of its own for each upload, released once the upload is started: the extension process may
            // live on idle, and must not hold an identifier the app wants to open.
            BackgroundReportUploader(identifier: BackgroundReportUploader.makeExtensionIdentifier(),
                                     container: container, invalidatesSessionAfterUpload: true)
        }
    }

    /// The same, over a container and an uploader the caller supplies. Tests use it.
    package static func didReceive(userInfo: [AnyHashable: Any],
                                   container: ReportContainer,
                                   uploader: (ReportContainer) -> BackgroundReportUploader) -> Bool {
        guard let messageID = userInfo[PayloadKey.messageID] as? String, !messageID.isEmpty,
              let subscriberID = userInfo[PayloadKey.subscriberID] as? String, !subscriberID.isEmpty,
              container.isShared,
              let credentials = SharedReportCredentialsStore(container: container).read() else { return false }
        let delivery = ReportedDelivery(messageID: messageID, subscriberID: subscriberID)
        if SentReportMarkerStore(container: container).contains(delivery) { return true }
        let pending = PendingDeliveryStore(container: container)
        // The extension cannot refresh the token. Leave the delivery to the app, which can.
        if AccessTokenExpiry.isExpired(credentials.accessToken, leeway: tokenLeeway) {
            pending.append([delivery])
            return true
        }
        let started = uploader(container).upload([delivery], accessToken: credentials.accessToken,
                                                 baseURL: credentials.reportBaseURL)
        if !started { pending.append([delivery]) }
        return started
    }

    /// The extension does not upload with a token that expires within this many seconds: the upload would reach the
    /// server after the token expired, and be refused.
    package static let tokenLeeway: TimeInterval = 60

    /// The payload keys sinch-push sets.
    package enum PayloadKey {
        package static let messageID = "sinch.push.message_id"
        package static let subscriberID = "sinch.push.subscriber_id"
    }
}
