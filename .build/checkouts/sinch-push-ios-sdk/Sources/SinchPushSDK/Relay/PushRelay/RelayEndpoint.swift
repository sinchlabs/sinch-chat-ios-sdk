import Foundation

/// Outcome of resolving the push relay WebSocket URL for a configuration.
enum RelayResolution: Equatable, Sendable {
    case enabled(URL)
    /// The relay is not used; `reason` is meant for logs and for `SinchPushSocketState.disabledReason`.
    case disabled(reason: String)
}

/// Resolves the relay endpoint for a region.
enum RelayEndpoint {

    /// The relay of the EU production environment. It mirrors the push host `grpc.sinch-push.prod.sinch.com`.
    static let eu1URL = URL(string: "wss://relay.sinch-push.prod.sinch.com/ws")!

    /// The relay of the US production environment. It mirrors the push host `grpc.sinch-push.us1.prod.sinch.com`.
    static let us1URL = URL(string: "wss://relay.sinch-push.us1.prod.sinch.com/ws")!

    /// The relay of the staging environments (eu1tst).
    static let stagingURL = URL(string: "wss://relay.sinch-push.eu1tst.staging.sinch.com/ws")!

    /// The relay of a custom region, derived from its push host. The push hosts are matched case-insensitively.
    private static let relayURLByPushHost: [String: URL] = [
        "grpc.sinch-push.staging.sinch.com": stagingURL,
        "grpc.sinch-push.eu1tst.staging.sinch.com": stagingURL,
        "grpc.sinch-push.prod.sinch.com": eu1URL,
        "grpc.sinch-push.us1.prod.sinch.com": us1URL,
    ]

    /// - Parameter allowInsecure: `AppConfig.allowInsecureRelay`, the only thing that permits `ws://`.
    static func resolve(region: Region, option: SinchSDKConfig.RelayOption,
                        allowInsecure: Bool = false) -> RelayResolution {
        guard option == .enabled else {
            return .disabled(reason: "relay disabled by configuration (relay: .disabled)")
        }

        let url: URL
        switch region {
        case .EU1:
            url = eu1URL
        case .US1:
            url = us1URL
        case .custom(_, let pushAPIHost, _, _, let relayURL):
            if let relayURL {
                // An explicit relay URL always wins over the derived one.
                url = relayURL
            } else if let derived = relayURLByPushHost[pushAPIHost.lowercased()] {
                url = derived
            } else {
                return .disabled(reason: "no relay host for push host \(pushAPIHost)")
            }
        }

        guard let host = url.host, !host.isEmpty else {
            return .disabled(reason: "relay URL has no host: \(url.absoluteString)")
        }
        switch url.scheme?.lowercased() {
        case "wss":
            return .enabled(url)
        case "ws":
            guard allowInsecure else {
                return .disabled(reason: "ws:// relay URLs require allowInsecureRelay == true")
            }
            return .enabled(url)
        default:
            return .disabled(reason: "relay URL must use the ws:// or wss:// scheme: \(url.absoluteString)")
        }
    }
}

extension Region {
    /// The region without its relay URL. Cached tokens depend on this, so a relay URL change must not invalidate them.
    var withoutRelayURL: Region {
        switch self {
        case .EU1, .US1:
            return self
        case let .custom(host, pushAPIHost, port, isSecure, _):
            return .custom(host: host, pushAPIHost: pushAPIHost, port: port, isSecure: isSecure, relayURL: nil)
        }
    }
}
