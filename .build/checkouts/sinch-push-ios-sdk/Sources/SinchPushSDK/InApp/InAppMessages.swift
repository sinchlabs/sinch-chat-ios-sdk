import Foundation

/// The public entry point for in-app alerts.
///
/// `SinchPushSDK.shared.inAppMessages` exposes this type once the facade is in
/// place. The state lives in `InAppMessageController.shared`, so the controller
/// and this facade can never disagree.
@MainActor
public final class InAppMessages {

    public static let shared = InAppMessages()

    init() {}

    private var controller: InAppMessageController { .shared }

    /// Receives lifecycle events and can take over rendering.
    public var delegate: InAppMessageDelegate? {
        get { controller.delegate }
        set { controller.delegate = newValue }
    }

    /// Colours, fonts, images and strings for the alerts the SDK renders.
    public var theme: InAppMessageTheme {
        get { controller.theme }
        set { controller.theme = newValue }
    }

    /// When `false`, the SDK does not render in-app alerts and the push pipeline
    /// posts a system notification instead.
    public var isEnabled: Bool {
        get { controller.isEnabled }
        set { controller.isEnabled = newValue }
    }

    /// Parses and queues `message` manually, for a host app that receives push
    /// payloads on its own path.
    @discardableResult
    public func present(_ message: InAppMessage) -> Bool {
        controller.present(message)
    }

    /// The alerts waiting to be shown, oldest first.
    public var queue: [InAppMessage] { controller.queue }
}
