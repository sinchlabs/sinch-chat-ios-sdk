import Foundation

public enum SinchSDKIdentity: Codable, Equatable, Sendable {
    /// Creates anonymous session with random user identifier.
    case anonymous
    /// Creates session with a specific user identifier using a pre-computed
    /// HMAC-SHA512(uuid, appSecret) digest as `secret`. Retained for
    /// backwards compatibility with existing integrations.
    case selfSigned(userId: String, secret: String)
    /// Creates session with a specific user identifier. The SDK computes
    /// HMAC-SHA512(uuid, appSecret) internally so host apps never handle
    /// the hash directly. The raw `appSecret` is held in memory only for
    /// the duration of `setIdentity` and is not persisted.
    case selfSignedWithAppSecret(userId: String, appSecret: String)
}

public enum SinchSDKIdentityError: Error {
    /// Our internal issue.
    case internalError(tracingID: String)
    /// Secret is invalid. Make sure it is generated correctly.
    case invalidSecret
}
