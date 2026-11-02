import Foundation

/// Receives in-app alert lifecycle events and can take over presentation.
///
/// All methods are optional: the defaults render every alert and ignore taps
/// that have no built-in behaviour.
@MainActor
public protocol InAppMessageDelegate: AnyObject {

    /// Return `false` to render the alert yourself.
    ///
    /// The SDK has already parsed `message`, so a relay message that is not an
    /// in-app alert never reaches this method: `InAppMessages.isEnabled` and
    /// ingestion return `false` for it instead.
    func shouldPresent(_ message: InAppMessage) -> Bool

    /// A choice was tapped.
    ///
    /// The SDK handles `url`, `call` and `location` itself and still reports
    /// them here. `text` has no built-in behaviour: it is a postback for the
    /// integrator to send.
    func didTapAction(_ action: InAppChoiceAction, in message: InAppMessage)

    /// The alert was dismissed by the user.
    func didDismiss(_ message: InAppMessage)
}

extension InAppMessageDelegate {

    public func shouldPresent(_ message: InAppMessage) -> Bool { true }

    public func didTapAction(_ action: InAppChoiceAction, in message: InAppMessage) {}

    public func didDismiss(_ message: InAppMessage) {}
}
