import UIKit

/// What the inbox list needs from the place it shows chats in. Implemented by the split view controller.
@MainActor
protocol InboxDetailHost: AnyObject {
    /// `true` while the sidebar and the chat are on screen side by side (regular width), `false` when collapsed.
    var isShowingDetailBesideList: Bool { get }
    /// `true` while a chat is open in the detail.
    var hasDetailChat: Bool { get }
    /// Shows `chat` in the detail. When collapsed it is pushed on the list.
    func showChat(_ chat: UIViewController)
    /// Tears the open chat down synchronously (it gives up the one running chat slot at once, without waiting for
    /// its deallocation) and replaces it by the empty state. Call it before creating the next chat.
    func clearChat()
}

/// Sidebar (inbox list) plus chat. Collapses to a pushed list on compact width, handled by UIKit.
///
/// No compact column is set on purpose: without one UIKit stacks the primary column with the secondary column
/// on top when collapsing, which is exactly "list, chat pushed on it", and it reuses the one inbox instance
/// (a separate compact controller would need a second inbox with its own subscription).
@MainActor
final class InboxSplitViewController: UISplitViewController, UISplitViewControllerDelegate, UINavigationControllerDelegate, InboxDetailHost {

    let inbox: InboxViewController
    let primaryNavigationController: UINavigationController
    let detailNavigationController: InboxDetailNavigationController
    let emptyDetailViewController: InboxEmptyDetailViewController

    private(set) weak var currentChat: UIViewController?

    /// Replaces the lookup of the system hinge (`reservedRegions`): returns the hinge frame in the split view's
    /// coordinate space, `nil` for no hinge. Injected by tests, `nil` in production.
    var hingeFrameProvider: ((UIView) -> CGRect?)?

    /// `true` while the open chat sits on the primary stack (collapsed), pushed by us.
    private var chatIsOnPrimaryStack = false
    /// `true` while this controller moves screens between the columns itself; those moves are not user pops.
    ///
    /// Not load-bearing: `navigationController(_:didShow:)` additionally requires `chatIsOnPrimaryStack` and a
    /// list-only stack, and every rearrangement here either clears that flag or leaves the chat on the stack. The
    /// flag is a second guard against reading one of our own `setViewControllers` calls as a user pop, and nothing
    /// breaks if it is removed.
    private var isRearrangingScreens = false

    private var appliedHingeSnap: InboxAdaptiveLayout.HingeSnap?
    private var appliedBucket: InboxAdaptiveLayout.WidthBucket?
    private var hingeInteraction: AnyObject?

    init(inbox: InboxViewController) {
        self.inbox = inbox
        self.primaryNavigationController = UINavigationController(rootViewController: inbox)
        self.emptyDetailViewController = InboxEmptyDetailViewController(
            text: inbox.mainView.localizationConfiguration.inboxEmptyDetailText,
            backgroundColor: inbox.mainView.uiConfig.inboxBackgroundColor
        )
        self.emptyDetailViewController.barAppearance = InboxBarStyle.appearance(inbox.mainView.uiConfig)
        self.detailNavigationController = InboxDetailNavigationController(
            rootViewController: emptyDetailViewController,
            uiConfig: inbox.mainView.uiConfig
        )
        super.init(style: .doubleColumn)

        InboxBarStyle.apply(inbox.mainView.uiConfig, to: primaryNavigationController.navigationBar)
        delegate = self
        preferredSplitBehavior = .automatic
        presentsWithGesture = true
        displayModeButtonVisibility = .automatic
        applyDefaultColumnWidths()

        setViewController(primaryNavigationController, for: .primary)
        setViewController(detailNavigationController, for: .secondary)

        primaryNavigationController.delegate = self
        inbox.detailHost = self
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    // MARK: View lifecycle

    override func viewDidLoad() {
        super.viewDidLoad()
        installHingeInteraction()
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        updateAdaptiveLayout()
    }

    override func viewWillTransition(to size: CGSize, with coordinator: any UIViewControllerTransitionCoordinator) {
        super.viewWillTransition(to: size, with: coordinator)
        coordinator.animate(alongsideTransition: nil) { [weak self] _ in
            self?.updateAdaptiveLayout()
        }
    }

    // MARK: InboxDetailHost

    var isShowingDetailBesideList: Bool { !isCollapsed }

    /// A chat that is alive but no longer on screen (popped, `deinit` not run yet) does not count.
    var hasDetailChat: Bool {
        guard let currentChat else { return false }
        return detailNavigationController.viewControllers.contains(currentChat)
            || primaryNavigationController.viewControllers.contains(currentChat)
    }

    func showChat(_ chat: UIViewController) {
        if let previous = currentChat, previous !== chat { release(previous) }
        currentChat = chat
        isRearrangingScreens = true
        defer { isRearrangingScreens = false }
        if isCollapsed {
            primaryNavigationController.setViewControllers([inbox], animated: false)
            primaryNavigationController.pushViewController(chat, animated: true)
            chatIsOnPrimaryStack = true
        } else {
            detailNavigationController.setViewControllers([chat], animated: false)
            chatIsOnPrimaryStack = false
        }
    }

    func clearChat() {
        releaseCurrentChat()
        guard !isCollapsed else { return }
        isRearrangingScreens = true
        defer { isRearrangingScreens = false }
        detailNavigationController.setViewControllers([emptyDetailViewController], animated: false)
    }

    private func releaseCurrentChat() {
        if let chat = currentChat { release(chat) }
        currentChat = nil
        chatIsOnPrimaryStack = false
    }

    private func release(_ chat: UIViewController) {
        (chat as? InboxReplaceableChat)?.tearDownForReplacement()
    }

    // MARK: UINavigationControllerDelegate (primary column)

    func navigationController(_ navigationController: UINavigationController,
                              didShow viewController: UIViewController,
                              animated: Bool) {
        // The chat was popped off the list on compact width (back button or swipe): nothing is open any more.
        guard navigationController === primaryNavigationController,
              !isRearrangingScreens,
              chatIsOnPrimaryStack,
              viewController === inbox,
              primaryNavigationController.viewControllers.count == 1 else { return }
        releaseCurrentChat()
        inbox.clearSelection()
    }

    // MARK: Host pop gesture

    /// Whether the host's interactive pop gesture (swipe back out of a pushed inbox) may begin at `point`
    /// (in this view's coordinates). Collapsed it is allowed while the list is alone on its stack; side by side it
    /// is allowed only in the sidebar, so it never competes with a chat gesture or the sidebar reveal swipe.
    func allowsHostPopGesture(at point: CGPoint) -> Bool {
        if isCollapsed { return primaryNavigationController.viewControllers.count == 1 }
        guard displayMode != .secondaryOnly else { return false }
        let sidebarFrame = primaryNavigationController.view.convert(primaryNavigationController.view.bounds, to: view)
        return sidebarFrame.contains(point)
    }

    // MARK: UISplitViewControllerDelegate

    func splitViewController(_ svc: UISplitViewController,
                             topColumnForCollapsingToProposedTopColumn proposedTopColumn: UISplitViewController.Column) -> UISplitViewController.Column {
        // Always the list: the empty state must never cover it on a phone. An open chat is pushed on the list
        // in `splitViewControllerDidCollapse`, so the stack is [list, chat] and not a nested navigation controller.
        .primary
    }

    func splitViewControllerDidCollapse(_ svc: UISplitViewController) {
        // Chat (and anything it pushed, e.g. a media preview) moves from the detail onto the list's stack.
        let openScreens = detailNavigationController.viewControllers.filter { $0 !== emptyDetailViewController }
        isRearrangingScreens = true
        defer { isRearrangingScreens = false }
        if !openScreens.isEmpty {
            detailNavigationController.setViewControllers([emptyDetailViewController], animated: false)
            primaryNavigationController.setViewControllers([inbox] + openScreens, animated: false)
            chatIsOnPrimaryStack = currentChat != nil
        }
        inbox.adaptiveStateDidChange()
    }

    func splitViewControllerDidExpand(_ svc: UISplitViewController) {
        // ...and back beside the list.
        let openScreens = Array(primaryNavigationController.viewControllers.dropFirst())
        isRearrangingScreens = true
        defer { isRearrangingScreens = false }
        chatIsOnPrimaryStack = false
        if !openScreens.isEmpty {
            primaryNavigationController.setViewControllers([inbox], animated: false)
            detailNavigationController.setViewControllers(openScreens, animated: false)
        }
        inbox.adaptiveStateDidChange()
        updateAdaptiveLayout(force: true)
    }

    // MARK: Adaptive layout

    private func applyDefaultColumnWidths() {
        preferredPrimaryColumnWidth = InboxAdaptiveLayout.preferredPrimaryWidth
        minimumPrimaryColumnWidth = InboxAdaptiveLayout.minimumPrimaryWidth
        maximumPrimaryColumnWidth = InboxAdaptiveLayout.maximumPrimaryWidth
    }

    /// Re-evaluates the display mode for the current width and the hinge. Cheap when nothing changed.
    func updateAdaptiveLayout(force: Bool = false) {
        guard !isCollapsed, view.bounds.width > 0 else { return }

        let snap = currentHingeSnap()
        let bucket = InboxAdaptiveLayout.widthBucket(for: view.bounds.width)
        guard force || snap != appliedHingeSnap || bucket != appliedBucket else { return }
        appliedHingeSnap = snap
        appliedBucket = bucket

        if let snap {
            // A hinge splits the window: the sidebar ends at the hinge and the chat starts after it.
            // Pin the column to the hinge: the default 360pt maximum would stop short of a centred fold.
            minimumPrimaryColumnWidth = snap.primaryWidth
            maximumPrimaryColumnWidth = snap.primaryWidth
            preferredPrimaryColumnWidth = snap.primaryWidth
            preferredDisplayMode = .oneBesideSecondary
            displayModeButtonVisibility = .never
            let isRightToLeft = view.effectiveUserInterfaceLayoutDirection == .rightToLeft
            detailNavigationController.additionalSafeAreaInsets = UIEdgeInsets(
                top: 0,
                left: isRightToLeft ? 0 : snap.secondaryLeadingInset,
                bottom: 0,
                right: isRightToLeft ? snap.secondaryLeadingInset : 0
            )
        } else {
            applyDefaultColumnWidths()
            preferredDisplayMode = InboxAdaptiveLayout.preferredDisplayMode(for: view.bounds.width)
            displayModeButtonVisibility = .automatic
            detailNavigationController.additionalSafeAreaInsets = .zero
        }
    }

    // MARK: Hinge

    // `UIHingeInteraction` and `UIView.reservedRegions(kind:)` exist only in the iOS 27.1+ SDK headers, and
    // `#available` is a runtime check: an older toolchain would fail to compile the names. SPM integrators build the
    // SDK from source, so every use is also guarded at compile time. Xcode 27.0 and 27.1 report the same Swift
    // compiler (6.4.0.34.1), so the compiler version cannot tell them apart; the first compiler that is only in
    // Xcode 27.2 (and its iOS 27.2 SDK) is 6.4.2. A toolchain below that compiles without the hinge feature: the
    // sidebar then uses the default column widths. The snapping math (`InboxAdaptiveLayout`) is compiled everywhere.
    private func installHingeInteraction() {
        #if compiler(>=6.4.2)
        guard #available(iOS 27.1, *) else { return }
        // The handler is `@MainActor` in the SDK header, so it can call into this controller directly. It runs with
        // the initial state and on every fold change; `viewDidLayoutSubviews` covers region changes that arrive
        // without a fold change.
        let interaction = UIHingeInteraction { [weak self] _, _ in
            self?.updateAdaptiveLayout(force: true)
        }
        view.addInteraction(interaction)
        hingeInteraction = interaction
        #endif
    }

    /// Frame of the hinge dividing the window, `nil` without an active one. Tests replace the lookup.
    private func currentHingeFrame() -> CGRect? {
        if let hingeFrameProvider { return hingeFrameProvider(view) }
        #if compiler(>=6.4.2)
        guard #available(iOS 27.1, *) else { return nil }
        return view.reservedRegions(kind: .division).first(where: { $0.isActive })?.frame
        #else
        return nil
        #endif
    }

    /// The snap for the hinge currently dividing the window, `nil` without an active hinge.
    private func currentHingeSnap() -> InboxAdaptiveLayout.HingeSnap? {
        guard var frame = currentHingeFrame() else { return nil }
        if view.effectiveUserInterfaceLayoutDirection == .rightToLeft {
            // The sidebar is on the right: mirror so that "leading edge" means the edge nearest the sidebar.
            frame.origin.x = view.bounds.width - frame.maxX
        }
        return InboxAdaptiveLayout.hingeSnap(containerSize: view.bounds.size, hingeFrame: frame)
    }
}

// MARK: - Detail navigation

/// The bar look of the inbox, from `uiConfig`, for navigation bars that no screen of ours styles itself: the
/// sidebar's bar and the chat column's bar over the empty placeholder. The list and the chat set the same
/// appearance on their own `navigationItem`s; this is the bar-level fallback. All four appearances are set,
/// because a compact-height window (an unfolded dual-screen phone is 669pt tall) uses the compact ones and
/// a scrolled-to-top bar the scroll-edge ones; an unset one falls back to the system's white bar.
@MainActor
enum InboxBarStyle {

    static func appearance(_ uiConfig: SinchSDKConfig.UIConfig) -> UINavigationBarAppearance {
        let appearance = UINavigationBarAppearance()
        appearance.configureWithOpaqueBackground()
        appearance.backgroundColor = uiConfig.navigationBarColor
        appearance.titleTextAttributes = [
            .foregroundColor: uiConfig.navigationBarTitleColor,
            .font: UIFont.boldSystemFont(ofSize: 16)
        ]
        return appearance
    }

    static func apply(_ uiConfig: SinchSDKConfig.UIConfig, to navigationBar: UINavigationBar) {
        let appearance = appearance(uiConfig)
        navigationBar.standardAppearance = appearance
        navigationBar.compactAppearance = appearance
        navigationBar.scrollEdgeAppearance = appearance
        navigationBar.compactScrollEdgeAppearance = appearance
        navigationBar.tintColor = uiConfig.navigationBarTitleColor
    }
}

/// Navigation controller of the chat column. In the column the chat is the root, so the back or close button it
/// installs for a pushed or modal chat would do nothing or dismiss the whole inbox: it is removed, leaving the
/// system sidebar toggle. Its bar carries the inbox look, so the column is not white over the empty placeholder.
final class InboxDetailNavigationController: UINavigationController, UINavigationControllerDelegate {

    init(rootViewController: UIViewController, uiConfig: SinchSDKConfig.UIConfig = .defaultValue) {
        super.init(rootViewController: rootViewController)
        delegate = self
        InboxBarStyle.apply(uiConfig, to: navigationBar)
    }

    @available(*, unavailable)
    required init?(coder aDecoder: NSCoder) { fatalError("init(coder:) is not supported") }

    func navigationController(_ navigationController: UINavigationController,
                              didShow viewController: UIViewController,
                              animated: Bool) {
        // Only the button the SDK installed itself is removed; one the integrator put there stays.
        guard let chat = viewController as? StartViewController,
              chat.ownsLeadingBarButton,
              chat === navigationController.viewControllers.first,
              splitViewController?.isCollapsed == false else { return }
        chat.navigationItem.leftBarButtonItem = nil
        chat.ownsLeadingBarButton = false
    }
}

/// Quiet native placeholder shown in the chat column while no conversation is selected.
final class InboxEmptyDetailViewController: UIViewController {

    private let text: String
    private let backgroundColor: UIColor

    init(text: String, backgroundColor: UIColor) {
        self.text = text
        self.backgroundColor = backgroundColor
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    /// Set before the view loads, so the placeholder's bar carries the inbox look like the chat's does. Known gap:
    /// in a compact-height wide window (iPhone Duo unfolded) UIKit shows no bar over the placeholder at all.
    var barAppearance: UINavigationBarAppearance?

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = backgroundColor
        if let barAppearance {
            navigationItem.standardAppearance = barAppearance
            navigationItem.compactAppearance = barAppearance
            navigationItem.scrollEdgeAppearance = barAppearance
            navigationItem.compactScrollEdgeAppearance = barAppearance
        }

        var configuration = UIContentUnavailableConfiguration.empty()
        configuration.image = UIImage(systemName: "bubble.left.and.bubble.right")
        configuration.text = text
        contentUnavailableConfiguration = configuration
    }
}
