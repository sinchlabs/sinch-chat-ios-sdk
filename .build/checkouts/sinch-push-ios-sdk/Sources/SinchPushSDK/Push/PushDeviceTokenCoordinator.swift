import Foundation
import CryptoKit
import os

/// Tracks successful Subscribe fingerprints per identity.
final class PushDeviceTokenCoordinator: @unchecked Sendable {
    // Static, because every coordinator over the same defaults must see the same records.
    private static let lock = NSLock()

    private static let deviceTokenKey = "sinch_device_token"
    private static let sentTokenDictionaryKey = "sinch_sent_token_dictionary"
    /// identity hash -> fingerprint of the last successful Subscribe. Separate from the token dictionary, which older SDKs still read.
    private static let sentFingerprintDictionaryKey = "sinch_sent_subscription_fingerprint_dictionary"

    private let userDefaults: UserDefaults

    private let authDataSourceStorage = OSAllocatedUnfairLock<AuthDataSource?>(initialState: nil)
    var authDataSource: AuthDataSource? {
        get { authDataSourceStorage.withLock { $0 } }
        set { authDataSourceStorage.withLock { $0 = newValue } }
    }

    private var tokenToSend: String? {
        get { userDefaults.string(forKey: PushDeviceTokenCoordinator.deviceTokenKey) }
        set { userDefaults.set(newValue, forKey: PushDeviceTokenCoordinator.deviceTokenKey) }
    }
    
    private var sentTokenDictionary: [String: String] {
        get {
            if let data = userDefaults.data(forKey: PushDeviceTokenCoordinator.sentTokenDictionaryKey) {
                return (try? PropertyListDecoder().decode([String: String].self, from: data)) ?? [:]
            }
            return [:]
        }
        set { userDefaults.set(try? PropertyListEncoder().encode(newValue), forKey: PushDeviceTokenCoordinator.sentTokenDictionaryKey) }
    }
    
    private var sentFingerprintDictionary: [String: String] {
        get {
            if let data = userDefaults.data(forKey: PushDeviceTokenCoordinator.sentFingerprintDictionaryKey) {
                return (try? PropertyListDecoder().decode([String: String].self, from: data)) ?? [:]
            }
            return [:]
        }
        set { userDefaults.set(try? PropertyListEncoder().encode(newValue), forKey: PushDeviceTokenCoordinator.sentFingerprintDictionaryKey) }
    }

    init(userDefaults: UserDefaults = UserDefaults.standard) {
        self.userDefaults = userDefaults
    }
    
    func setTokenToSend(deviceToken: Data) {
        Self.lock.withLock {
            tokenToSend = deviceToken.hexEncodedString()
        }
    }
    
    func getLastToken() -> String? {
        Self.lock.withLock { tokenToSend }
    }

    /// The identity a Subscribe would be recorded for, or `nil` when no identity or token is set.
    var subscribableIdentityHash: String? {
        guard let identityHash = authDataSource?.identityHashValue else {
            return nil
        }
        return Self.lock.withLock { tokenToSend != nil } ? identityHash : nil
    }
    
    /// The token to subscribe with, or `nil` when the last successful Subscribe for this identity matches.
    /// A record without a fingerprint never matches, so the first launch after an upgrade re-subscribes.
    func getTokenToSend(deviceInfo: DeviceInfo?, for identityHash: String) -> String? {
        Self.lock.withLock {
            guard let token = tokenToSend else {
                return nil
            }
            if sentFingerprintDictionary[identityHash] == Self.fingerprint(token: token, deviceInfo: deviceInfo) {
                return nil
            }
            return token
        }
    }

    /// Records a successful Subscribe. Pass the values that were sent, and the identity captured when the request was made.
    func recordSubscription(token: String, deviceInfo: DeviceInfo?, for identityHash: String) {
        Self.lock.withLock {
            sentTokenDictionary[identityHash] = token
            sentFingerprintDictionary[identityHash] = Self.fingerprint(token: token, deviceInfo: deviceInfo)
        }
    }

    /// Forgets the subscription for an identity after unsubscribe. The device token is kept.
    func clearSentRecord(for identityHash: String) {
        Self.lock.withLock {
            sentTokenDictionary[identityHash] = nil
            sentFingerprintDictionary[identityHash] = nil
        }
    }

    /// Digest of everything a `Subscribe` carries. Hashed, so the installation id is not stored as text.
    /// A token-only Subscribe has fewer components and never matches a full one.
    static func fingerprint(token: String, deviceInfo: DeviceInfo?) -> String {
        var components = ["v1", token]
        if let info = deviceInfo {
            components += [
                info.installationId,
                info.osVersion,
                info.sdkVersion,
                info.bundleId,
                String(info.backgroundService.rawValue)
            ]
        }
        let digest = SHA256.hash(data: Data(components.joined(separator: "\u{1F}").utf8))
        return digest.map { String(format: "%02x", $0) }.joined()
    }
}
