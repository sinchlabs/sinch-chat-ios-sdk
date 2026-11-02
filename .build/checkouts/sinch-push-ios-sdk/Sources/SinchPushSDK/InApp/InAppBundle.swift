import UIKit

/// Locates the bundle that holds the in-app assets and strings.
///
/// SPM puts them in `Bundle.module` (a `SinchPushSDK_SinchPushSDK.bundle` next
/// to the framework). CocoaPods with `resource_bundles` puts them in
/// `SinchPushSDK.bundle`, which is looked up next to the class and in the main
/// bundle.
public enum InAppBundle {

    public static var current: Bundle {
        #if SWIFT_PACKAGE
        return Bundle.module
        #else
        return resourceBundle ?? Bundle(for: BundleToken.self)
        #endif
    }

    static let bundleNames = [
        "SinchPushSDK",
        "SinchPushSDK_SinchPushSDK",
        "SinchPushSdk-SinchPushSDK_SinchPushSDK"
    ]

    private static let resourceBundle: Bundle? = {
        let anchor = Bundle(for: BundleToken.self)
        let containers = [anchor.resourceURL, Bundle.main.resourceURL, Bundle.main.bundleURL]

        for container in containers {
            for name in bundleNames {
                if let url = container?.appendingPathComponent(name + ".bundle"),
                   let bundle = Bundle(url: url) {
                    return bundle
                }
            }
        }
        return nil
    }()

    /// Looks a string up in the in-app table, falling back to the key so a
    /// missing translation never renders as an empty button.
    static func localized(_ key: String) -> String {
        let value = NSLocalizedString(key, tableName: nil, bundle: current, value: key, comment: "")
        return value
    }

    static func color(_ name: String) -> UIColor? {
        UIColor(named: name, in: current, compatibleWith: nil)
    }

    static func image(_ name: String) -> UIImage? {
        UIImage(named: name, in: current, compatibleWith: nil)
    }
}

private final class BundleToken {}
