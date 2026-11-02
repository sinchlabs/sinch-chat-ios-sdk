import Foundation

/// Connection status of the push relay socket.
public enum SinchPushSocketStatus: Sendable, Equatable {
    /// Not connected: not started, in the background, or disabled.
    case idle
    /// Opening the first connection.
    case connecting
    /// Connected; messages are delivered over the socket.
    case connected
    /// Lost, and reconnecting with back-off.
    case reconnecting
    /// Failed; see ``SinchPushSocketState/lastError``.
    case error
    /// Stopped, for example by `removeIdentity`.
    case stopped
    /// The relay refused the access token. The SDK re-issues it once.
    case authRequired
    /// Another surface took over the relay session.
    case replaced
}

/// State of the push relay socket, published by ``SinchPush/socketStatePublisher``.
public struct SinchPushSocketState: Sendable, Equatable {
    /// Connection status.
    public var status: SinchPushSocketStatus
    /// Whether the relay is enabled. `false` before `setIdentity` succeeds and after `removeIdentity`.
    public var relayEnabled: Bool
    /// Why the relay is not used, when ``relayEnabled`` is `false`. For diagnostics, not display.
    public var disabledReason: String?
    /// The last error from the relay or while starting it.
    public var lastError: String?
    /// The reconnect attempt count.
    public var reconnectAttempts: Int

    public init(status: SinchPushSocketStatus,
                relayEnabled: Bool,
                disabledReason: String? = nil,
                lastError: String? = nil,
                reconnectAttempts: Int = 0) {
        self.status = status
        self.relayEnabled = relayEnabled
        self.disabledReason = disabledReason
        self.lastError = lastError
        self.reconnectAttempts = reconnectAttempts
    }
}

/// A push message received over the relay socket, published by ``SinchPush/socketMessagePublisher``.
public struct SinchPushSocketMessage: Sendable, Equatable {
    /// Relay message id, as ``SinchPush/reportStatus(messageId:status:)`` expects.
    public var id: String
    /// Id of the Sinch message the notification is about.
    public var sinchMessageId: String
    /// `nil` when the message has no title.
    public var title: String?
    /// `nil` when the message has no text.
    public var body: String?
    /// `nil` when the message has no image.
    public var imageUrl: String?
    /// The custom payload, as the APNs payload would carry it.
    public var metadata: [String: String]
    /// When the SDK received the message.
    public var receivedAt: Date
    /// When the relay queued the message.
    public var enqueuedAt: Date

    public init(id: String,
                sinchMessageId: String,
                title: String? = nil,
                body: String? = nil,
                imageUrl: String? = nil,
                metadata: [String: String] = [:],
                receivedAt: Date,
                enqueuedAt: Date) {
        self.id = id
        self.sinchMessageId = sinchMessageId
        self.title = title
        self.body = body
        self.imageUrl = imageUrl
        self.metadata = metadata
        self.receivedAt = receivedAt
        self.enqueuedAt = enqueuedAt
    }
}

/// Delivery status a host app can report for a relay message.
public enum SinchPushMessageStatus: Sendable {
    /// The notification was shown to the user.
    case displayed
    /// The user dismissed the notification.
    case dismissed
}

extension SinchPushSocketStatus {
    init(_ status: SocketStatus) {
        switch status {
        case .idle: self = .idle
        case .connecting: self = .connecting
        case .connected: self = .connected
        case .reconnecting: self = .reconnecting
        case .error: self = .error
        case .stopped: self = .stopped
        case .authRequired: self = .authRequired
        case .replaced: self = .replaced
        }
    }
}

extension SinchPushSocketState {
    init(_ state: SocketState) {
        self.init(status: SinchPushSocketStatus(state.status),
                  relayEnabled: true,
                  lastError: state.lastError,
                  reconnectAttempts: state.reconnectAttempts)
    }
}

extension SinchPushSocketMessage {
    init(_ event: SocketMessageEvent) {
        self.init(id: event.id,
                  sinchMessageId: event.sinchMessageId,
                  title: event.title,
                  body: event.body,
                  imageUrl: event.imageUrl,
                  metadata: event.metadata,
                  receivedAt: Date(timeIntervalSince1970: TimeInterval(event.receivedAt) / 1000),
                  enqueuedAt: Date(timeIntervalSince1970: TimeInterval(event.enqueuedAt) / 1000))
    }
}

extension SinchPushMessageStatus {
    var socketStatus: SocketDeliveryStatus {
        switch self {
        case .displayed: return .displayed
        case .dismissed: return .dismissed
        }
    }
}
