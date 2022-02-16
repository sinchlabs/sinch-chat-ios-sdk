import Foundation

extension Bundle {

    #if SWIFT_PACKAGE
        static let staticBundle = Bundle.module
    #else
        static let staticBundle = SinchChatSDKResources.resourceBundle
    #endif
}

public final class SinchChatSDKResources {
    public static let resourceBundle: Bundle = {
        let candidates = [
            Bundle.main.resourceURL,
            Bundle(for: SinchChatSDKResources.self).resourceURL
        ]

        let bundleName = "SinchChatSDKBundle"

        for candidate in candidates {
            let bundlePath = candidate?.appendingPathComponent(bundleName + ".bundle")
            if let bundle = bundlePath.flatMap(Bundle.init(url:)) {
                return bundle
            }
        }

        return Bundle(for: SinchChatSDKResources.self)
    }()
}
