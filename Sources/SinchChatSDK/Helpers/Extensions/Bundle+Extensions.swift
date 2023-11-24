import Foundation

public extension Bundle {
    
    static let staticBundle = {
        let candidates = [
            Bundle.main.resourceURL,
            Bundle(for: SinchChatSDK.self).resourceURL
        ]
        
        let bundleName = "SinchChatSDK_SinchChatSDK"
        
        for candidate in candidates {
            let bundlePath = candidate?.appendingPathComponent(bundleName + ".bundle")
            if let bundle = bundlePath.flatMap(Bundle.init(url:)) {
                return bundle
            }
        }
        
        return Bundle(for: SinchChatSDK.self)
    }()
}
