#if canImport(SwiftUI) && canImport(UIKit)
import SwiftUI
import UIKit

/// SwiftUI wrapper around the SDK inbox view controller.
///
/// With the default `.automatic` layout the inbox is a sidebar with the selected chat beside it on regular
/// width, and a list that pushes the chat on compact width. The adaptive inbox brings its own navigation, so
/// it is not wrapped in a `UINavigationController` (a split view must not be nested in one).
///
/// ## Inside a SwiftUI `NavigationStack`
/// The inbox draws its own navigation bars (sidebar and chat). Pushed on a `NavigationStack` it would sit under
/// the stack's bar, giving two bars, so hide the stack's bar on the destination and give the inbox a way out:
///
/// ```swift
/// SinchInboxView(onClose: { path.removeLast() })
///     .toolbar(.hidden, for: .navigationBar)
///     .ignoresSafeArea()
/// ```
///
/// `onClose` is called by the back button in the sidebar's bar. Without it the sidebar shows a close button only
/// when SwiftUI presents the inbox modally (a sheet or full-screen cover): that button dismisses the presentation.
/// Pushed on a `NavigationStack`, or embedded in other content, it has no button without `onClose`, because a
/// SwiftUI host owns that navigation. Pass `onClose` to get a button there, or to run your own code on close.
/// The layout parameter has no effect on a custom `SinchInbox` implementation, see `SinchInbox`.
public struct SinchInboxView: UIViewControllerRepresentable {

    private let uiConfig: SinchSDKConfig.UIConfig?
    private let localizationConfig: SinchSDKConfig.LocalizationConfig?
    private let options: GetChatViewControllerOptions?
    private let layout: SinchInboxLayout
    private let onClose: (() -> Void)?
    private let onError: ((Error) -> Void)?

    /// - Parameter onClose: Makes the sidebar show a back button that calls it. Use it when the inbox is pushed or
    ///   presented by SwiftUI and the host's own navigation bar is hidden. It is the last parameter so that an
    ///   existing trailing closure keeps meaning `onError`.
    public init(
        uiConfig: SinchSDKConfig.UIConfig? = nil,
        localizationConfig: SinchSDKConfig.LocalizationConfig? = nil,
        options: GetChatViewControllerOptions? = nil,
        layout: SinchInboxLayout = .automatic,
        onError: ((Error) -> Void)? = nil,
        onClose: (() -> Void)? = nil
    ) {
        self.uiConfig = uiConfig
        self.localizationConfig = localizationConfig
        self.options = options
        self.layout = layout
        self.onClose = onClose
        self.onError = onError
    }

    public func makeUIViewController(context: Context) -> UIViewController {
        do {
            let viewController = try SinchChatSDK.shared.chat.inbox.getInboxViewController(
                uiConfig: uiConfig,
                localizationConfig: localizationConfig,
                options: options,
                layout: layout
            )
            (viewController as? InboxContainerViewController)?.exitHandler = onClose
            return Self.hostViewController(for: viewController)
        } catch {
            onError?(error)
            return UINavigationController(rootViewController: UIViewController())
        }
    }

    public func updateUIViewController(_ uiViewController: UIViewController, context: Context) {
        (uiViewController as? InboxContainerViewController)?.exitHandler = onClose
    }

    /// The adaptive inbox and anything that is already a navigation controller are used as they are; the plain
    /// list (`.stack`) needs a navigation controller to push the chat on.
    static func hostViewController(for viewController: UIViewController) -> UIViewController {
        if viewController is UINavigationController || viewController is InboxContainerViewController {
            return viewController
        }
        return UINavigationController(rootViewController: viewController)
    }
}

#endif
