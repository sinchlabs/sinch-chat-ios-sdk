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

    /// In-app lifecycle events as an `AsyncSequence`, emitted alongside ``delegate``.
    ///
    /// Each access is an independent consumer and is removed when its stream
    /// terminates. Use it instead of the delegate when a `for await` loop fits the
    /// app better; both can be used at the same time.
    ///
    /// ```swift
    /// for await event in SinchPushSDK.shared.inAppMessages.events {
    ///     switch event {
    ///     case .presented(let message): break
    ///     case .actionTapped(let action, let message): break
    ///     case .dismissed(let message): break
    ///     }
    /// }
    /// ```
    public var events: AsyncStream<InAppMessageEvent> { controller.events }

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
