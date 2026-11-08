import UIKit

/// How the inbox leaves the screen when the user taps the button in the sidebar's navigation bar.
enum InboxExitStyle: Equatable {
    /// Pop the host's navigation stack.
    case back
    /// Dismiss the modal presentation.
    case close
    /// Nothing to leave: the host owns the navigation (embedded in a SwiftUI view, a child controller, ...).
    case none
}

@MainActor
protocol InboxHost: AnyObject {
    var exitStyle: InboxExitStyle { get }

    func exitInbox()
}

/// What `getInboxViewController` returns for `SinchInboxLayout.automatic`.
///
/// A plain view controller that embeds the split view controller as its child, so integrators can push it,
/// present it (bare or inside their own navigation controller), embed it as a child or wrap it in SwiftUI,
/// exactly like the list controller returned before. A `UISplitViewController` itself could only be a root.
final class InboxContainerViewController: UIViewController, SinchChatViewController, InboxHost, UIGestureRecognizerDelegate {

    let splitController: InboxSplitViewController
    private var navigationBarWasHidden: Bool?
    /// The host navigation controller whose bar this controller hid (see `viewWillAppear`).
    private weak var hiddenBarNavigationController: UINavigationController?
    /// Delegate of the host's pop gesture before this controller took it over (see `viewWillAppear`).
    private var originalPopGestureDelegate: UIGestureRecognizerDelegate?
    private var didTakeOverPopGesture = false

    /// Set by a host that has no UIKit navigation to leave through, e.g. SwiftUI (`SinchInboxView(onClose:)`).
    /// When set, the sidebar shows a back button that calls it.
    var exitHandler: (() -> Void)? {
        didSet {
            // The sidebar decides its leading button when it appears; a handler that arrives or goes later has to
            // reach it too. Before the list is loaded, `viewWillAppear` reads the handler itself. SwiftUI hands over a
            // new closure on every update: only a handler that arrives or goes changes the button, because rebuilding
            // it on every update would reset VoiceOver focus.
            guard (oldValue == nil) != (exitHandler == nil), splitController.inbox.isViewLoaded else { return }
            splitController.inbox.updateLeadingBarButton()
        }
    }

    init(splitController: InboxSplitViewController) {
        self.splitController = splitController
        super.init(nibName: nil, bundle: nil)
        splitController.inbox.host = self
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    override func viewDidLoad() {
        super.viewDidLoad()
        addChild(splitController)
        splitController.view.frame = view.bounds
        splitController.view.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        view.addSubview(splitController.view)
        splitController.didMove(toParent: self)
    }

    // The sidebar and the chat bring their own navigation bars. When the host pushed this controller on its
    // stack, its bar would be a second one above them.
    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        if let navigationController = hostNavigationController {
            hiddenBarNavigationController = navigationController
            navigationBarWasHidden = navigationController.isNavigationBarHidden
            navigationController.setNavigationBarHidden(true, animated: animated)
            takeOverPopGesture(of: navigationController)
        }
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        // When the host pops this controller, UIKit has already removed it from `viewControllers` by now, so the
        // navigation controller is the one remembered in `viewWillAppear`, not `hostNavigationController`.
        if let navigationController = hiddenBarNavigationController, let wasHidden = navigationBarWasHidden {
            navigationController.setNavigationBarHidden(wasHidden, animated: animated)
        }
        navigationBarWasHidden = nil
        restorePopGesture()
        hiddenBarNavigationController = nil
    }

    // MARK: Host pop gesture

    // Hiding the bar disables the host's swipe-back gesture (its delegate refuses while the bar is hidden). The
    // gesture is kept alive here, but only where it cannot clash with the inbox: see `allowsHostPopGesture(at:)`.
    private func takeOverPopGesture(of navigationController: UINavigationController) {
        guard !didTakeOverPopGesture, let gesture = navigationController.interactivePopGestureRecognizer else { return }
        originalPopGestureDelegate = gesture.delegate
        gesture.delegate = self
        didTakeOverPopGesture = true
    }

    private func restorePopGesture() {
        guard didTakeOverPopGesture else { return }
        didTakeOverPopGesture = false
        let gesture = (hiddenBarNavigationController ?? navigationController)?.interactivePopGestureRecognizer
        if let gesture, gesture.delegate === self { gesture.delegate = originalPopGestureDelegate }
        originalPopGestureDelegate = nil
    }

    func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
        // UIKit's own delegate refuses a pop while a push or pop is still animating; starting one then can freeze
        // or corrupt the stack, so keep that rule.
        guard let navigationController = hostNavigationController,
              navigationController.transitionCoordinator == nil,
              navigationController.viewControllers.count > 1,
              navigationController.topViewController === self else { return false }
        return splitController.allowsHostPopGesture(at: gestureRecognizer.location(in: splitController.view))
    }

    // The remaining answers stay UIKit's, so conflicts with the list's scrolling and swipe actions are unchanged.

    func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldReceive touch: UITouch) -> Bool {
        originalPopGestureDelegate?.gestureRecognizer?(gestureRecognizer, shouldReceive: touch) ?? true
    }

    func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer,
                           shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer) -> Bool {
        originalPopGestureDelegate?.gestureRecognizer?(gestureRecognizer,
                                                       shouldRecognizeSimultaneouslyWith: otherGestureRecognizer) ?? false
    }

    func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer,
                           shouldBeRequiredToFailBy otherGestureRecognizer: UIGestureRecognizer) -> Bool {
        originalPopGestureDelegate?.gestureRecognizer?(gestureRecognizer, shouldBeRequiredToFailBy: otherGestureRecognizer) ?? false
    }

    override var childForStatusBarStyle: UIViewController? { splitController }
    override var childForStatusBarHidden: UIViewController? { splitController }

    // MARK: InboxHost

    /// The navigation controller that holds this controller on its stack, if the host pushed it.
    private var hostNavigationController: UINavigationController? {
        guard let navigationController = parent as? UINavigationController,
              navigationController.viewControllers.contains(self) else { return nil }
        return navigationController
    }

    /// The ancestor (or self) that was presented modally, if any.
    private var presentedAncestor: UIViewController? {
        var candidate: UIViewController? = self
        while let current = candidate {
            if current.presentingViewController != nil { return current }
            candidate = current.parent
        }
        return nil
    }

    var exitStyle: InboxExitStyle {
        if exitHandler != nil { return .back }
        if let navigationController = hostNavigationController,
           let index = navigationController.viewControllers.firstIndex(of: self), index > 0 {
            return .back
        }
        return presentedAncestor != nil ? .close : .none
    }

    func exitInbox() {
        if let exitHandler {
            exitHandler()
            return
        }
        switch exitStyle {
        case .back:
            hostNavigationController?.popViewController(animated: true)
        case .close:
            presentedAncestor?.dismiss(animated: true)
        case .none:
            break
        }
    }
}
