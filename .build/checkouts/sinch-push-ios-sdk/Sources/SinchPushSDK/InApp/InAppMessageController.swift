import UIKit

/// Queues in-app alerts and presents them one at a time.
///
/// Presentation rules, unchanged from the chat SDK:
/// - on the top-most view controller, `.overFullScreen`, `.crossDissolve`;
/// - while a `UIAlertController` is in front, wait 5 s and look again;
/// - between two alerts, wait 0.5 s.
@MainActor
public final class InAppMessageController: Sendable {

    public static let shared = InAppMessageController()

    /// Receives lifecycle events and can veto presentation. Weak: the host owns it.
    public weak var delegate: InAppMessageDelegate?

    /// Colours, fonts, images and strings for the next alert.
    public var theme: InAppMessageTheme = .default

    /// When `false`, ingestion returns `false` and nothing is rendered, so the
    /// push pipeline can fall back to a system notification.
    public var isEnabled: Bool = true

    /// Alerts waiting to be shown, oldest first. The head is the one on screen.
    public private(set) var queue: [InAppMessage] = []

    /// Emits lifecycle events alongside ``delegate``. Internal; `InAppMessages.events` is the public door.
    let eventStream = InAppEventMulticaster()

    /// A new stream of in-app lifecycle events. Each call is an independent consumer.
    var events: AsyncStream<InAppMessageEvent> { eventStream.makeStream() }

    /// Gap between the end of one alert and the next one.
    var presentationGap: TimeInterval = 0.5

    /// Wait before looking again when a `UIAlertController` is in front, or when
    /// no view controller can host the alert yet.
    var alertBackoff: TimeInterval = 5.0

    var scheduler: InAppScheduling = InAppTaskScheduler()

    /// Where a message is shown. Injected so the queue can be tested without a
    /// window.
    var hostProvider: @MainActor () -> UIViewController? = {
        InAppWindowHelper.topMostViewController()
    }

    /// How a message is shown. Injected for the same reason.
    var presentAction: @MainActor (UIViewController, UIViewController) -> Void = { host, controller in
        host.present(controller, animated: true)
    }

    /// Whether an alert is currently on screen.
    private(set) var isPresenting = false

    init() {}

    // MARK: - Ingestion

    /// Queues `message`.
    ///
    /// - Returns: `true` when the alert was accepted (now or behind others),
    ///   `false` when it is disabled or the delegate took over.
    @discardableResult
    public func present(_ message: InAppMessage) -> Bool {
        guard isEnabled else { return false }
        guard delegate?.shouldPresent(message) ?? true else { return false }

        queue.append(message)
        eventStream.send(.presented(message))

        if queue.count == 1 {
            showNextMessage()
        }

        return true
    }

    /// The alert on screen was closed by the user.
    ///
    /// Removes it from the queue, tells the delegate and schedules the next one
    /// after `presentationGap`.
    func messageDidClose(_ message: InAppMessage) {
        if queue.first == message {
            queue.removeFirst()
        } else {
            queue.removeAll { $0 == message }
        }

        isPresenting = false
        delegate?.didDismiss(message)
        eventStream.send(.dismissed(message))

        guard !queue.isEmpty else { return }

        scheduler.schedule(after: presentationGap) { [weak self] in
            self?.showNextMessage()
        }
    }

    /// Drops everything that has not been shown yet and closes the current alert.
    public func dismissAll() {
        scheduler.cancel()

        let remaining = queue
        queue.removeAll()
        isPresenting = false

        if let presented = hostProvider() as? InAppMessageViewController {
            presented.dismiss(animated: false)
        }

        remaining.forEach {
            delegate?.didDismiss($0)
            eventStream.send(.dismissed($0))
        }
    }

    // MARK: - Presentation

    private func showNextMessage() {
        guard !isPresenting, let message = queue.first else { return }

        guard let host = hostingViewController() else {
            waitForHost()
            return
        }

        isPresenting = true

        let controller = InAppMessageViewController(
            viewModel: DefaultInAppMessageViewModel(message: message),
            view: InAppMessageView(theme: theme, message: message)
        )
        controller.delegate = self
        controller.modalPresentationStyle = .overFullScreen
        controller.modalTransitionStyle = .crossDissolve

        presentAction(host, controller)
    }

    private func hostingViewController() -> UIViewController? {
        guard let top = hostProvider() else { return nil }

        // Let the app finish with its own alert first.
        if top is UIAlertController { return nil }

        return top
    }

    private func waitForHost() {
        scheduler.schedule(after: alertBackoff) { [weak self] in
            self?.showNextMessage()
        }
    }
}

// MARK: - InAppMessageViewControllerDelegate

extension InAppMessageController: InAppMessageViewControllerDelegate {

    func inAppMessageViewController(
        _ controller: InAppMessageViewController,
        didSelect action: InAppChoiceAction,
        in message: InAppMessage
    ) {
        delegate?.didTapAction(action, in: message)
        eventStream.send(.actionTapped(action, in: message))
    }

    func inAppMessageViewControllerDidClose(_ controller: InAppMessageViewController) {
        messageDidClose(controller.viewModel.message)
    }
}
