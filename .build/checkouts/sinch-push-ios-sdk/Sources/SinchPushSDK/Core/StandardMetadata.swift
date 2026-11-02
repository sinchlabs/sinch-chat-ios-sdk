import Foundation
import UIKit

/// The standard SDK metadata every RPC carries as request headers: bundle id, app version, locale, SDK version and
/// system info. The locale and the SDK version are injected by ``SinchPushSDK`` so this type never reads the facade's
/// mutable state, and a test can pin both.
struct StandardMetadata: Sendable {
    var locale: Locale
    var sdkVersion: String

    init(locale: Locale = .current, sdkVersion: String = SinchPushSDK.version) {
        self.locale = locale
        self.sdkVersion = sdkVersion
    }

    /// The headers of a call. `token` is the raw access token; the SDK sends it without a `Bearer` prefix, as the
    /// React Native SDK does.
    func headers(token: String? = nil) -> [String: String] {
        var headers: [String: String] = [:]
        headers["bundleID"] = Bundle.main.bundleIdentifier ?? ""
        headers["appVersion"] = (Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String) ?? ""
        headers["lang"] = locale.identifier
        headers["sdkVersion"] = sdkVersion
        headers["system"] = UIDevice.current.systemName
        headers["systemVersion"] = UIDevice.current.systemVersion
        if let token {
            headers["authorization"] = token
        }
        return headers
    }
}
