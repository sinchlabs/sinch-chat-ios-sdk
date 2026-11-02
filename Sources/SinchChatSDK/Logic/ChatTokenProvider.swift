import Foundation
@_spi(SinchChat) import SinchPushSDK

/// The identity and token state chat needs from the push SDK.
///
/// Chat no longer issues tokens: `SinchPushSDK` owns the identity, the Keychain token and its refresh. This protocol is
/// the slice of ``PushTokenProvider`` the chat code (and its tests) talks to.
protocol ChatTokenProvider: AnyObject, Sendable {
    /// Whether a stored identity exists.
    var isLoggedIn: Bool { get }
    /// The stored token.
    var currentAuthorization: AuthModel? { get }
    /// The access token used to authenticate outbound RPCs.
    func currentAccessToken() throws -> String
}

extension PushTokenProvider: ChatTokenProvider {}

extension ChatTokenProvider {
    /// The region of the stored token. Chat needs it to pick its gRPC host, and the token is the only place the push
    /// SDK exposes it: `SinchSDKConfig.AppConfig`'s fields are internal to `SinchPushSDK`.
    var currentRegion: Region? {
        currentAuthorization?.region
    }
}
