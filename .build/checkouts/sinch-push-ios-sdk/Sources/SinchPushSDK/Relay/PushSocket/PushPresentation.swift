import Foundation
import os

/// How a Sinch push names its message.
enum PushMessageIdentity {
    /// The metadata key sinch-push sets. Its value is the relay's `PooledMessage.message_id`.
    static let metadataKey = "sinch.push.message_id"

    /// The metadata key sinch-push sets for the subscriber the push was addressed to.
    static let subscriberIdKey = "sinch.push.subscriber_id"

    /// Every key sinch-push adds to the metadata starts with this.
    static let metadataKeyPrefix = "sinch.push."

    /// The id to dedupe on, or `nil` for no dedupe.
    ///
    /// Falls back to the request identifier, but only for a recognisable Sinch push
    /// whose identifier is not a UUID. A missed dedupe costs a duplicate banner, while
    /// a wrong one costs a lost message.
    static func messageId(
        userInfo: [AnyHashable: Any], requestIdentifier: String?
    ) -> String? {
        if let id = userInfo[metadataKey] as? String, !id.isEmpty { return id }
        guard let identifier = requestIdentifier, !identifier.isEmpty,
              UUID(uuidString: identifier) == nil,
              userInfo.keys.contains(where: { ($0 as? String)?.hasPrefix(metadataKeyPrefix) == true })
        else { return nil }
        return identifier
    }

    /// A local notification the socket posted itself (`userInfo["source"]`).
    static func isSocketOriginated(userInfo: [AnyHashable: Any]) -> Bool {
        (userInfo["source"] as? String) == "socket"
    }

    /// The subscriber the push was addressed to, or `nil` when the push does not name one.
    static func subscriberId(userInfo: [AnyHashable: Any]) -> String? {
        guard let id = userInfo[subscriberIdKey] as? String, !id.isEmpty else { return nil }
        return id
    }
}

enum PushPresentationDecision: Equatable {
    /// Hand it to the host or show the content.
    case present
    /// A copy of a message another channel already delivered.
    case suppress
}

/// The `willPresent` and `didReceiveRemoteNotification` rules over the shared registry.
///
/// iOS gives no order between the two paths for a foreground content-available push,
/// so each path suppresses only what *another channel* already delivered. The same
/// push never suppresses itself. Known limit: a second APNs delivery of the same id
/// in the same process is not suppressed.
final class PushPresentationDecider: Sendable {
    /// Ids first marked by the APNs path, bounded by ``SeenSet``.
    private let apnsMarked = OSAllocatedUnfairLock(initialState: SeenSet())
    let registry: SeenMessageRegistry
    /// Told about the first APNs delivery of a message no other channel delivered before.
    private let deliveryReporter: DeliveryReporting?

    init(registry: SeenMessageRegistry, deliveryReporter: DeliveryReporting? = nil) {
        self.registry = registry
        self.deliveryReporter = deliveryReporter
    }

    /// Whether an APNs notification is presented or is a copy another channel delivered.
    /// No id means `.present`. The caller must exclude socket-originated notifications first.
    func decide(
        userInfo: [AnyHashable: Any], requestIdentifier: String?
    ) -> PushPresentationDecision {
        guard
            let id = PushMessageIdentity.messageId(
                userInfo: userInfo, requestIdentifier: requestIdentifier)
        else { return .present }
        let (isNew, isCopy) = check(id)
        if isNew { reportDelivery(userInfo: userInfo) }
        return isCopy ? .suppress : .present
    }

    /// Checks and marks the id in the registry.
    func isCopyFromOtherChannel(_ id: String) -> Bool {
        check(id).isCopy
    }

    private func check(_ id: String) -> (isNew: Bool, isCopy: Bool) {
        if registry.markSeen(id) {
            _ = apnsMarked.withLock { $0.insert(id) }
            return (true, false)
        }
        return (false, !apnsMarked.withLock { $0.contains(id) })
    }

    /// Reports the delivery of a push that names both its message and its subscriber.
    private func reportDelivery(userInfo: [AnyHashable: Any]) {
        guard let reporter = deliveryReporter,
              let messageID = userInfo[PushMessageIdentity.metadataKey] as? String, !messageID.isEmpty,
              let subscriberID = PushMessageIdentity.subscriberId(userInfo: userInfo)
        else { return }
        reporter.reportDelivery(messageID: messageID, subscriberID: subscriberID)
    }
}
