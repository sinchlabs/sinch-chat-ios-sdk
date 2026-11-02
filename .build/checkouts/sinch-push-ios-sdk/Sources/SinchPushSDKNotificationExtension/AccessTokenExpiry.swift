import Foundation

/// Reads the expiry of the access token, a JWT, without verifying it.
package enum AccessTokenExpiry {
    /// Whether the token has expired, or will within `leeway` seconds. A token that cannot be read, or that has no
    /// `exp`, counts as not expired: the server decides then.
    package static func isExpired(_ token: String, leeway: TimeInterval, now: Date = Date()) -> Bool {
        guard let expiry = expiry(of: token) else { return false }
        return now.addingTimeInterval(leeway) >= expiry
    }

    /// The `exp` claim.
    package static func expiry(of token: String) -> Date? {
        let segments = token.split(separator: ".", omittingEmptySubsequences: false)
        guard segments.count >= 2, let payload = decode(String(segments[1])),
              let json = try? JSONSerialization.jsonObject(with: payload) as? [String: Any],
              let exp = json["exp"] as? NSNumber else { return nil }
        return Date(timeIntervalSince1970: exp.doubleValue)
    }

    private static func decode(_ base64URL: String) -> Data? {
        var base64 = base64URL.replacingOccurrences(of: "-", with: "+").replacingOccurrences(of: "_", with: "/")
        base64 += String(repeating: "=", count: (4 - base64.count % 4) % 4)
        return Data(base64Encoded: base64)
    }
}
