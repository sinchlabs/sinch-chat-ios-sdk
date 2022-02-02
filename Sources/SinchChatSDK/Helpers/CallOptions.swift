import UIKit
import GRPC

extension CallOptions {

    static var standardCallOptions: CallOptions {
        var options = CallOptions()

        options.customMetadata.add(name: "bundleID", value: Bundle.main.bundleIdentifier ?? "")
        options.customMetadata.add(name: "appVersion", value: (Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String) ?? "")
        options.customMetadata.add(name: "lang", value: SinchChatSDK.shared.config?.locale.identifier ?? "")
        options.customMetadata.add(name: "sdkVersion", value: SinchChatSDK.version)
        options.customMetadata.add(name: "system", value: UIDevice.current.systemName)
        options.customMetadata.add(name: "systemVersion", value: UIDevice.current.systemVersion)

        return options
    }
}
