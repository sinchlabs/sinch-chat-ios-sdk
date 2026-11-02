import Foundation

/// When a socket message should also be surfaced as a local notification.
enum SocketDisplayRule: String, Sendable, Equatable, CaseIterable {
    /// Post only when the host app has not registered an in-app handler.
    case whenUnhandled
    /// Always post.
    case always
    /// Never post.
    case never
}

/// Everything the client needs for one connection.
///
/// The platform is always iOS, and `background` is not a field: ``SocketClient``
/// writes `Hello.background = false` unconditionally.
///
/// The token is the only secret. It is kept by ``AuthTokenStore`` and never persisted
/// with the rest of the configuration.
struct SocketConfiguration: Sendable, Equatable {
    /// Full WebSocket URL. `ws://` for local development, `wss://` in production.
    var url: String

    /// The sinch-chat JWT the relay verifies.
    var authToken: String

    /// JWT-derived, with the config value as the fallback.
    var projectID: String

    var appID: String

    var userID: String

    /// Poll cadence override; `<= 0` means the server decides. The 1000 ms floor applies to the result.
    var pollIntervalMs: Int

    /// The display rule; `whenUnhandled` by default.
    var displayNotifications: SocketDisplayRule

    /// `Hello.sdk_version` override. `nil` or empty falls back to ``defaultSDKVersion``.
    var sdkVersion: String?

    init(
        url: String,
        authToken: String,
        projectID: String,
        appID: String,
        userID: String,
        pollIntervalMs: Int = 0,
        displayNotifications: SocketDisplayRule = .whenUnhandled,
        sdkVersion: String? = nil
    ) {
        self.url = url
        self.authToken = authToken
        self.projectID = projectID
        self.appID = appID
        self.userID = userID
        self.pollIntervalMs = pollIntervalMs
        self.displayNotifications = displayNotifications
        self.sdkVersion = sdkVersion
    }

    /// The SDK version, shared by `Hello`, `Subscribe` and gRPC metadata.
    static var defaultSDKVersion: String { SinchPushSDK.version }

    static let platform = Sinch_Push_Delivery_V1beta1_Ws_Platform.ios

    var resolvedSDKVersion: String {
        SocketConfiguration.resolveSDKVersion(sdkVersion)
    }

    static func resolveSDKVersion(_ override: String?) -> String {
        guard let override, !override.isEmpty else { return defaultSDKVersion }
        return override
    }

    var persistable: PersistedSocketConfiguration {
        PersistedSocketConfiguration(
            url: url,
            projectID: projectID,
            appID: appID,
            userID: userID,
            pollIntervalMs: pollIntervalMs,
            displayNotifications: displayNotifications,
            sdkVersion: sdkVersion)
    }
}

/// ``SocketConfiguration`` without the credential, safe to write to `UserDefaults`.
struct PersistedSocketConfiguration: Sendable, Codable, Equatable {
    var url: String
    var projectID: String
    var appID: String
    var userID: String
    var pollIntervalMs: Int
    var displayNotifications: String
    var sdkVersion: String?

    init(
        url: String,
        projectID: String,
        appID: String,
        userID: String,
        pollIntervalMs: Int,
        displayNotifications: SocketDisplayRule,
        sdkVersion: String?
    ) {
        self.url = url
        self.projectID = projectID
        self.appID = appID
        self.userID = userID
        self.pollIntervalMs = pollIntervalMs
        self.displayNotifications = displayNotifications.rawValue
        self.sdkVersion = sdkVersion
    }

    /// Rebuilds the configuration. An unknown stored display rule falls back to `whenUnhandled`.
    func configuration(authToken: String) -> SocketConfiguration {
        SocketConfiguration(
            url: url,
            authToken: authToken,
            projectID: projectID,
            appID: appID,
            userID: userID,
            pollIntervalMs: pollIntervalMs,
            displayNotifications: SocketDisplayRule(rawValue: displayNotifications) ?? .whenUnhandled,
            sdkVersion: sdkVersion)
    }
}

/// The published status.
///
/// `authRequired` and `replaced` are distinct: "the relay refused our token" and
/// "another surface took the session" need different host responses.
enum SocketStatus: String, Sendable, Equatable, CaseIterable {
    case idle
    case connecting
    case connected
    case reconnecting
    case error
    case stopped
    /// `Close(UNAUTHORIZED)`. Terminal until the credential is refreshed.
    case authRequired = "auth_required"
    /// `Close(BG_RESUMED)`. Another surface owns the session.
    case replaced
}

struct SocketState: Sendable, Equatable {
    var status: SocketStatus
    var transport: String = "native"
    var connectionId: String = ""
    var pollIntervalMs: Int = SocketClient.defaultPollIntervalMs
    var reconnectAttempts: Int = 0
    /// Cleared on every new attempt. Carries a `Close` frame's detail, or a `server closed (reason=n)` form.
    var lastError: String?
}

struct SocketMessageEvent: Sendable, Codable, Equatable {
    /// `PooledMessage.message_id`, the dedupe key.
    var id: String
    var sinchMessageId: String
    var ackToken: String
    var title: String?
    var body: String?
    var imageUrl: String?
    var metadata: [String: String]
    var importance: Int
    var trigger: String?
    var enqueuedAt: Int64
    var receivedAt: Int64
    var background: Bool
    /// True once a local notification has been posted, which is when DISPLAYED is reported.
    var shown: Bool

    /// Proto3 has no field presence, so an empty string becomes `nil`.
    init(pooled: Sinch_Push_Delivery_V1beta1_Ws_PooledMessage, ackToken: String, receivedAt: Int64) {
        let notification = pooled.hasPushNotification ? pooled.pushNotification : nil
        let alert = notification?.alert
        self.id = pooled.messageID
        self.sinchMessageId = pooled.sinchMessageID
        self.ackToken = ackToken
        self.title = SocketMessageEvent.absentIfEmpty(alert?.title ?? "")
        self.body = SocketMessageEvent.absentIfEmpty(alert?.message ?? "")
        self.imageUrl = SocketMessageEvent.absentIfEmpty(alert?.imageURL ?? "")
        self.metadata = notification?.metadata ?? [:]
        self.importance = notification?.importance.rawValue ?? 0
        self.trigger = SocketMessageEvent.absentIfEmpty(notification?.trigger ?? "")
        self.enqueuedAt = pooled.enqueuedAtUnixMillis
        self.receivedAt = receivedAt
        self.background = false
        self.shown = false
    }

    static func absentIfEmpty(_ value: String) -> String? {
        value.isEmpty ? nil : value
    }
}

enum SocketDeliveryStatus: String, Sendable, Codable, Equatable, CaseIterable {
    case delivered
    case displayed
    case dismissed
    case failed

    /// The proto enum. Its numeric value is used in the Ack token.
    var proto: Sinch_Push_Delivery_V1beta1_Ws_DeliveryReport.Status {
        switch self {
        case .delivered: return .delivered
        case .displayed: return .displayed
        case .dismissed: return .dismissed
        case .failed: return .failed
        }
    }

    /// The numeric suffix of `Ack.ack_token`: `DELIVERED = 1`, `DISPLAYED = 2`, `FAILED = 3`, `DISMISSED = 4`.
    var tokenSuffix: String { String(proto.rawValue) }
}

///
/// `messageId` is never empty; the relay refuses a report without one.
struct PendingReport: Sendable, Codable, Equatable {
    var messageId: String
    var sinchMessageId: String
    var status: SocketDeliveryStatus
    var reason: String
    var attempts: Int
    /// Earliest millisecond this entry may be sent again, set by a `rate_limited` rejection.
    var deferUntilMs: Int64?

    /// The token the relay echoes back. Constructed, never parsed.
    var ackToken: String { "\(messageId):\(status.tokenSuffix)" }

    var sentKey: String { "\(messageId):\(status.tokenSuffix)" }

    func deliveryReport(reportedAtMs: Int64) -> Sinch_Push_Delivery_V1beta1_Ws_DeliveryReport {
        var report = Sinch_Push_Delivery_V1beta1_Ws_DeliveryReport()
        report.messageID = messageId
        report.sinchMessageID = sinchMessageId
        report.status = status.proto
        report.reason = reason
        report.reportedAtUnixMillis = reportedAtMs
        return report
    }
}
