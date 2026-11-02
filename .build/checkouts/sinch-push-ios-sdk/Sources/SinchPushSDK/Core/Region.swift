import Foundation

/// The Sinch region a config runs against.
public enum Region: Codable, Equatable, Sendable {
    case EU1
    case US1
    /// - Parameters:
    ///   - host: The gRPC host of the sinch-chat backend that issues the access token.
    ///   - pushAPIHost: The host of the sinch-push gRPC API (Subscribe, Unsubscribe, ReportEvents).
    ///     A `host:port` or a URL with a scheme is accepted too.
    ///   - relayURL: WebSocket URL of the push relay for this environment. `nil` disables the relay.
    ///     `wss://` is always accepted; `ws://` only with `AppConfig.allowInsecureRelay`. `isSecure` concerns the chat
    ///     channel only and has no effect on the relay.
    ///
    /// `relayURL` is optional in the encoded form, so values persisted before it existed still decode.
    case custom(host: String, pushAPIHost: String, port: Int?, isSecure: Bool?, relayURL: URL? = nil)

    /// The gRPC-web host of the sinch-chat backend that issues the tokens.
    var chatHost: String {
        switch self {
        case .EU1: return "grpc-web.sinch-chat.prod.sinch.com"
        case .US1: return "grpc-web.sinch-chat.us1.prod.sinch.com"
        case .custom(let host, _, _, _, _): return host
        }
    }

    /// The host of the sinch-push API. It is a native gRPC host; the gRPC-web framing works against it too.
    var pushAPIHost: String {
        switch self {
        case .EU1: return "grpc.sinch-push.prod.sinch.com"
        case .US1: return "grpc.sinch-push.us1.prod.sinch.com"
        case .custom(_, let pushAPIHost, _, _, _): return pushAPIHost
        }
    }

    /// The port of a custom region, for both backends. The production regions use the scheme default (443).
    var port: Int? {
        switch self {
        case .EU1, .US1: return nil
        case .custom(_, _, let port, _, _): return port
        }
    }

    /// Whether the custom region uses TLS. The production regions do.
    var isSecure: Bool {
        switch self {
        case .EU1, .US1: return true
        case .custom(_, _, _, let isSecure, _): return isSecure ?? true
        }
    }
}
