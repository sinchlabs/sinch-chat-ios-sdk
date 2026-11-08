#if canImport(SwiftUI) && canImport(UIKit)
import SwiftUI
import UIKit

/// SwiftUI wrapper around the SDK chat view controller.
public struct SinchChatView: UIViewControllerRepresentable {

    private let uiConfig: SinchSDKConfig.UIConfig?
    private let localizationConfig: SinchSDKConfig.LocalizationConfig?
    private let options: GetChatViewControllerOptions?
    private let onError: ((Error) -> Void)?

    public init(
        uiConfig: SinchSDKConfig.UIConfig? = nil,
        localizationConfig: SinchSDKConfig.LocalizationConfig? = nil,
        options: GetChatViewControllerOptions? = nil,
        onError: ((Error) -> Void)? = nil
    ) {
        self.uiConfig = uiConfig
        self.localizationConfig = localizationConfig
        self.options = options
        self.onError = onError
    }

    public func makeUIViewController(context: Context) -> UINavigationController {
        do {
            let viewController = try SinchChatSDK.shared.chat.getChatViewController(
                uiConfig: uiConfig,
                localizationConfig: localizationConfig,
                options: options
            )
            return Self.navigationController(for: viewController)
        } catch {
            onError?(error)
            return UINavigationController(rootViewController: UIViewController())
        }
    }

    public func updateUIViewController(_ uiViewController: UINavigationController, context: Context) {}

    /// Wraps the chat in a navigation controller unless it already is one (no double wrapping).
    static func navigationController(for viewController: UIViewController) -> UINavigationController {
        if let navigationController = viewController as? UINavigationController {
            return navigationController
        }
        return UINavigationController(rootViewController: viewController)
    }
}

#endif
