import XCTest
@testable import SinchChatSDK

/// Scene scoping (C3), the leading button inside a split detail (I3) and the window lookup (C5).
@MainActor
final class AdaptiveLifecycleTests: XCTestCase {

    private var windows: [UIWindow] = []

    override func tearDown() {
        windows.forEach { $0.isHidden = true }
        windows.removeAll()
        super.tearDown()
    }

    private func makeChat() -> StartViewController {
        StartViewController(viewModel: StartViewModelStub(),
                            view: .init(uiConfiguration: .defaultValue, localizationConfiguration: .defaultValue))
    }

    private func firstScene() throws -> UIWindowScene {
        guard let scene = UIApplication.shared.connectedScenes.compactMap({ $0 as? UIWindowScene }).first else {
            throw XCTSkip("the package test runner has no UIWindowScene; run the suite app-hosted to cover this")
        }
        return scene
    }

    // MARK: - C3 scene observers

    /// `viewWillAppear` can run before the view has a window; only `viewIsAppearing` is late enough.
    func testObserversAreScopedFromViewIsAppearingNotViewWillAppear() {
        let sut = makeChat()
        _ = sut.view
        let afterLoad = sut.observerSetupCount
        XCTAssertNil(sut.windowAtLastObserverSetup, "viewDidLoad runs before the view is in a window")

        sut.viewWillAppear(false)
        XCTAssertEqual(sut.observerSetupCount, afterLoad, "viewWillAppear must not set the observers up")

        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 400, height: 800))
        windows.append(window)
        window.rootViewController = sut
        window.isHidden = false
        window.layoutIfNeeded()

        XCTAssertGreaterThan(sut.observerSetupCount, afterLoad, "viewIsAppearing sets them up")
        XCTAssertTrue(sut.windowAtLastObserverSetup === window, "the view is in its window by then")
    }

    /// Needs a real `UIWindowScene`, which the package's test runner does not have; runs in an app-hosted test run.
    func testLifecycleObserversNarrowToTheHostingScene() throws {
        let scene = try firstScene()
        let window = UIWindow(windowScene: scene)
        window.frame = CGRect(x: 0, y: 0, width: 400, height: 800)
        windows.append(window)
        let sut = makeChat()
        _ = sut.view
        XCTAssertNil(sut.observedScene, "before the view is in a window the app-wide notifications are the placeholder")

        window.rootViewController = sut
        window.isHidden = false
        window.layoutIfNeeded()

        XCTAssertTrue(sut.hasLifecycleObservers)
        XCTAssertTrue(sut.observedScene === scene, "viewIsAppearing re-registers once the window is known")
    }

    // MARK: - I3 leading button in a split detail

    private func makeSplit(width: CGFloat, chat: StartViewController) -> (split: UISplitViewController, window: UIWindow) {
        let split = UISplitViewController(style: .doubleColumn)
        split.setViewController(UINavigationController(rootViewController: UIViewController()), for: .primary)
        split.setViewController(InboxDetailNavigationController(rootViewController: chat), for: .secondary)
        split.preferredDisplayMode = .oneBesideSecondary
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: width, height: 800))
        window.rootViewController = split
        window.isHidden = false
        window.layoutIfNeeded()
        windows.append(window)
        return (split, window)
    }

    func testChatAsRootOfAnExpandedSplitDetailHasNoLeadingButton() {
        let chat = makeChat()
        let (split, window) = makeSplit(width: 1100, chat: chat)

        XCTAssertFalse(split.isCollapsed)
        XCTAssertTrue(chat.isRootOfExpandedSplitDetail)
        XCTAssertNil(chat.navigationItem.leftBarButtonItem)
        _ = window
    }

    func testLeadingButtonStaysAbsentAfterAFullScreenModalComesBack() {
        let chat = makeChat()
        let (_, window) = makeSplit(width: 1100, chat: chat)
        let picker = UIViewController()
        picker.modalPresentationStyle = .fullScreen
        chat.present(picker, animated: false)
        chat.dismiss(animated: false)

        // The same calls UIKit makes when the chat appears again after the picker, camera or file viewer.
        chat.beginAppearanceTransition(true, animated: false)
        chat.endAppearanceTransition()
        chat.viewWillAppear(false)

        XCTAssertNil(chat.navigationItem.leftBarButtonItem, "the close button would dismiss the whole inbox")
        _ = window
    }

    func testLeadingButtonFlipsWhenTheSplitCollapsesAndExpands() async {
        let chat = makeChat()
        let (split, window) = makeSplit(width: 1100, chat: chat)
        XCTAssertNil(chat.navigationItem.leftBarButtonItem)

        // Collapse: compact width.
        window.traitOverrides.horizontalSizeClass = .compact
        window.layoutIfNeeded()
        split.view.layoutIfNeeded()
        XCTAssertTrue(split.isCollapsed)
        XCTAssertFalse(chat.isRootOfExpandedSplitDetail)
        await waitUntil { chat.navigationItem.leftBarButtonItem != nil }
        XCTAssertNotNil(chat.navigationItem.leftBarButtonItem, "pushed on the list: a back button again")

        // Expand again.
        window.traitOverrides.horizontalSizeClass = .regular
        window.layoutIfNeeded()
        split.view.layoutIfNeeded()
        XCTAssertFalse(split.isCollapsed)
        XCTAssertTrue(chat.isRootOfExpandedSplitDetail)
        await waitUntil { chat.navigationItem.leftBarButtonItem == nil }
        XCTAssertNil(chat.navigationItem.leftBarButtonItem)
    }

    func testChatInAPlainNavigationStackKeepsItsBackButton() {
        let chat = makeChat()
        let root = UIViewController()
        let navigation = UINavigationController(rootViewController: root)
        navigation.pushViewController(chat, animated: false)
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 400, height: 800))
        window.rootViewController = navigation
        window.isHidden = false
        window.layoutIfNeeded()
        windows.append(window)

        XCTAssertFalse(chat.isRootOfExpandedSplitDetail)
        XCTAssertNotNil(chat.navigationItem.leftBarButtonItem)
    }

    func testModalChatKeepsItsCloseButton() {
        let chat = makeChat()
        let navigation = UINavigationController(rootViewController: chat)
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 400, height: 800))
        window.rootViewController = UIViewController()
        window.isHidden = false
        windows.append(window)
        window.layoutIfNeeded()
        window.rootViewController?.present(navigation, animated: false)
        window.layoutIfNeeded()

        XCTAssertTrue(chat.isModal)
        // Appearance of a presented controller is deferred in a scene-less test host; run the step it triggers.
        chat.viewWillAppear(false)
        XCTAssertNotNil(chat.navigationItem.leftBarButtonItem, "a modal chat keeps its close button")
        XCTAssertFalse(chat.isRootOfExpandedSplitDetail)
    }

    // MARK: - G-C8 compose bar after a push or an interactive pop

    func testViewDidAppearRecomputesTheComposeBarPlacement() {
        let sut = makeChat()
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 1024, height: 768))
        window.rootViewController = sut
        window.isHidden = false
        windows.append(window)
        window.layoutIfNeeded()
        let compose = sut.mainView.messageComposeView
        let stale = ComposeChatPlacement(detailFrame: .zero, columnFrame: .zero, areaFrame: .zero, space: nil)
        compose.updateLayoutEnvironment(horizontalSizeClass: sut.traitCollection.horizontalSizeClass,
                                        verticalSizeClass: sut.traitCollection.verticalSizeClass,
                                        placement: stale)
        XCTAssertNotEqual(compose.chatPlacement, sut.composePlacement())

        sut.viewDidAppear(false)

        XCTAssertEqual(compose.chatPlacement, sut.composePlacement())
    }

    // MARK: - G-C3 window lookup entry points

    func testVisibleControllerAgreesWithTheLegacyEntryPointOnMain() {
        XCTAssertTrue(WindowHelper.visibleController() === WindowHelper.getVisibleController())
    }

    func testLegacyVisibleControllerOffMainReturnsWithoutDeadlockWhileMainIsFree() async {
        let onMain = WindowHelper.visibleController().map(ObjectIdentifier.init)
        let offMain = await Task.detached { WindowHelper.getVisibleController().map(ObjectIdentifier.init) }.value
        XCTAssertEqual(onMain, offMain)
    }

    // MARK: - C5 window lookup

    func testAppWindowIgnoresOverlayWindows() throws {
        let scene = try firstScene()
        let appWindow = UIWindow(windowScene: scene)
        appWindow.rootViewController = UIViewController()
        appWindow.isHidden = false
        let overlay = UIWindow(windowScene: scene)
        overlay.windowLevel = .alert + 1
        overlay.rootViewController = UIViewController()
        overlay.isHidden = false
        overlay.makeKey()
        windows.append(contentsOf: [appWindow, overlay])

        let found = try XCTUnwrap(WindowHelper.appWindow(in: scene))
        XCTAssertEqual(found.windowLevel, .normal)
        XCTAssertFalse(found === overlay)
    }
}
