import SafariServices
import UIKit

@MainActor
protocol InAppMessageViewControllerDelegate: AnyObject {
    /// A choice was tapped. The controller has already performed the built-in
    /// behaviour (`url`, `call`, `location`); this reports it to the public
    /// delegate.
    func inAppMessageViewController(
        _ controller: InAppMessageViewController,
        didSelect action: InAppChoiceAction,
        in message: InAppMessage
    )

    /// The alert was dismissed and the queue can move on.
    func inAppMessageViewControllerDidClose(_ controller: InAppMessageViewController)
}

/// The alert's view controller. It owns the built-in actions; everything that
/// needs a host app decision goes back through the delegate.
@MainActor
final class InAppMessageViewController: InAppBaseViewController<InAppMessageViewModel, InAppMessageView>,
    InAppMessageViewDelegate {

    weak var delegate: InAppMessageViewControllerDelegate?

    override func viewDidLoad() {
        super.viewDidLoad()

        mainView.closeButton.addTarget(self, action: #selector(closeInAppAction), for: .touchUpInside)
        mainView.cancelButton.addTarget(self, action: #selector(closeInAppAction), for: .touchUpInside)
        mainView.delegate = self
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        mainView.layoutTrait(traitCollection: traitCollection)
    }

    @objc private func closeInAppAction() {
        dismiss(animated: true) { [weak self] in
            guard let self else { return }
            self.delegate?.inAppMessageViewControllerDidClose(self)
        }
    }

    func didSelect(choice: InAppChoice) {
        perform(choice.action)
        delegate?.inAppMessageViewController(self, didSelect: choice.action, in: viewModel.message)
    }

    func didSelectMedia(url: URL) {
        present(InAppMediaViewerController.make(for: url, theme: mainView.theme), animated: true)
    }

    private func perform(_ action: InAppChoiceAction) {
        switch action {
        case .text:
            // Postback only: the host app decides what to do with it.
            break

        case .url(let string):
            guard let url = InAppChoiceHandler.webURL(from: string) else { return }
            present(SFSafariViewController(url: url), animated: true)

        case .call(let phoneNumber):
            InAppChoiceHandler.call(phoneNumber: phoneNumber)

        case .location(let location):
            InAppLocationActionHandler(theme: mainView.theme).handleOpenLocation(
                self,
                title: location.title,
                latitude: location.latitude,
                longitude: location.longitude
            )
        }
    }
}
