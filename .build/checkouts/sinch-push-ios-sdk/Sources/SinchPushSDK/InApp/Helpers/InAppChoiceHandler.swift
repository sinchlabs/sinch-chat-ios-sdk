import UIKit

/// Opening a `tel:` link and a maps app, the two side effects that are not a
/// view controller presentation.
enum InAppChoiceHandler {

    static func call(phoneNumber: String) {
        let trimmed = phoneNumber.replacingOccurrences(of: " ", with: "")
        guard let url = URL(string: "tel://\(trimmed)") else { return }

        let application = UIApplication.shared
        guard application.canOpenURL(url) else { return }
        application.open(url, options: [:], completionHandler: nil)
    }

    static func openAppleMaps(title: String?, latitude: Double, longitude: Double) {
        var components = URLComponents()
        components.scheme = "http"
        components.host = "maps.apple.com"
        components.queryItems = [
            URLQueryItem(name: "q", value: title ?? ""),
            URLQueryItem(name: "ll", value: "\(latitude),\(longitude)")
        ]

        guard let url = components.url else { return }
        UIApplication.shared.open(url, options: [:], completionHandler: nil)
    }

    static func openGoogleMaps(latitude: Double, longitude: Double) {
        guard let url = URL(string: "https://maps.google.com/?q=\(latitude),\(longitude)") else { return }
        UIApplication.shared.open(url, options: [:], completionHandler: nil)
    }

    /// `SFSafariViewController` crashes on schemes it does not serve, so only
    /// web URLs are ever offered to it.
    static func webURL(from string: String) -> URL? {
        guard let url = URL(string: string),
              ["http", "https"].contains(url.scheme?.lowercased() ?? "") else {
            return nil
        }
        return url
    }
}
