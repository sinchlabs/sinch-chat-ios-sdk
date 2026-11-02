import Foundation

/// Bridge between the push pipeline and the in-app queue.
///
/// Conforms to `InAppMessagePresenting` (declared in `Push/`), which the push
/// facade calls from `handleNotification` and from the relay presenter. The
/// return value is the contract with the push pipeline: `true` means the alert
/// was consumed and no system notification should be posted for it.
extension InAppMessageController: InAppMessagePresenting {

    /// Relay path: a message's `[String: String]` metadata.
    public func present(metadata: [String: String]) -> Bool {
        guard let message = InAppMessageParser.message(fromRelayMetadata: metadata) else {
            return false
        }
        return present(message)
    }

    /// APNs path: the notification's `userInfo`.
    public func present(userInfo: [AnyHashable: Any]) -> Bool {
        guard let message = InAppMessageParser.message(fromUserInfo: userInfo) else {
            return false
        }
        return present(message)
    }
}
