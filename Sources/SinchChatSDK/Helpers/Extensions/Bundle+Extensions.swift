import Foundation

extension Bundle {
    
    static func getBundle(bundleName: String) -> Bundle? {
        var resourceBundle: Bundle?
        for includedBundles in Bundle.allBundles {
            if let resourceBundlePath = includedBundles.path(forResource: bundleName, ofType: "bundle") {
                resourceBundle = Bundle(path: resourceBundlePath)
                break
            }
        }
        return resourceBundle
    }

    static let staticBundle = Bundle.module
}
