import XCTest
import UIKit
@testable import SinchChatSDK

/// The inbox inside the host's navigation: swipe back, the exit handler for SwiftUI hosts, the sidebar toggle.
@MainActor
final class InboxHostNavigationTests: InboxSplitFixture {

    /// Pushes the container on a host navigation controller (as `DevApp/ChatApp` does).
    private func pushOnHostStack(horizontalSizeClass: UIUserInterfaceSizeClass) -> UINavigationController {
        let navigation = UINavigationController(rootViewController: UIViewController())
        window = UIWindow(frame: CGRect(x: 0, y: 0, width: 400, height: 800))
        container.traitOverrides.horizontalSizeClass = horizontalSizeClass
        window.rootViewController = navigation
        window.makeKeyAndVisible()
        navigation.pushViewController(container, animated: false)
        layoutEverything()
        return navigation
    }

    // MARK: Swipe back out of a pushed inbox

    func testHostSwipeBackStaysAvailableWhileTheInboxHidesTheHostBar() async throws {
        let navigation = UINavigationController(rootViewController: UIViewController())
        let gesture = try XCTUnwrap(navigation.interactivePopGestureRecognizer)
        let originalDelegate = gesture.delegate
        window = UIWindow(frame: CGRect(x: 0, y: 0, width: 400, height: 800))
        container.traitOverrides.horizontalSizeClass = .compact
        window.rootViewController = navigation
        window.makeKeyAndVisible()
        navigation.pushViewController(container, animated: false)
        layoutEverything()

        XCTAssertTrue(navigation.isNavigationBarHidden)
        XCTAssertTrue(gesture.delegate === container, "the host's pop gesture must be handled while its bar is hidden")
        XCTAssertTrue(container.gestureRecognizerShouldBegin(gesture), "list alone on the stack: swipe back leaves the inbox")

        select(row: 0)
        XCTAssertFalse(container.gestureRecognizerShouldBegin(gesture), "a pushed chat is popped by the inbox's own stack")
        await settleTransitions()

        split.primaryNavigationController.popViewController(animated: false)
        XCTAssertTrue(container.gestureRecognizerShouldBegin(gesture))

        navigation.popViewController(animated: false)
        layoutEverything()
        await settleTransitions()
        XCTAssertFalse(gesture.delegate === container)
        XCTAssertTrue(gesture.delegate === originalDelegate, "the host's original gesture delegate must be restored")
        XCTAssertFalse(navigation.isNavigationBarHidden)
    }

    func testHostSwipeBackIsRefusedWhenTheInboxIsTheRoot() {
        let navigation = pushOnHostStack(horizontalSizeClass: .compact)
        navigation.popViewController(animated: false)
        navigation.setViewControllers([container], animated: false)
        layoutEverything()
        guard let gesture = navigation.interactivePopGestureRecognizer else { return XCTFail("no pop gesture") }
        XCTAssertFalse(container.gestureRecognizerShouldBegin(gesture), "nothing to pop to")
    }

    func testOnRegularWidthSwipeBackOnlyBeginsInTheSidebar() {
        show(width: 1180, height: 820, horizontalSizeClass: .regular)
        XCTAssertFalse(split.isCollapsed)
        XCTAssertTrue(split.allowsHostPopGesture(at: CGPoint(x: 10, y: 300)))
        XCTAssertFalse(split.allowsHostPopGesture(at: CGPoint(x: 700, y: 300)), "the chat column keeps its own gestures")
    }

    func testWithTheSidebarHiddenTheEdgeSwipeBelongsToTheSystemSidebarReveal() {
        show(width: 744, height: 1000, horizontalSizeClass: .regular)
        split.hide(.primary)
        layoutEverything()
        XCTAssertEqual(split.displayMode, .secondaryOnly)
        XCTAssertFalse(split.allowsHostPopGesture(at: CGPoint(x: 10, y: 300)))
    }

    func testCollapsedSwipeBackIsAllowedOnlyWhileTheListIsAlone() {
        show(width: 400, horizontalSizeClass: .compact)
        XCTAssertTrue(split.allowsHostPopGesture(at: .zero))
        select(row: 0)
        XCTAssertFalse(split.allowsHostPopGesture(at: .zero))
    }

    // MARK: Exit handler (SwiftUI hosts)

    func testExitHandlerGivesTheSidebarABackButtonThatCallsIt() {
        var closed = 0
        container.exitHandler = { closed += 1 }
        show(width: 400, horizontalSizeClass: .compact)

        XCTAssertEqual(container.exitStyle, .back)
        XCTAssertNotNil(inbox.navigationItem.leftBarButtonItem)
        inbox.backAction()
        XCTAssertEqual(closed, 1)
    }

    /// `SinchInboxView.updateUIViewController` hands over a new `onClose` while the list is on screen.
    func testExitHandlerSetOrClearedWhileOnScreenUpdatesTheSidebarButton() {
        show(width: 400, horizontalSizeClass: .compact)
        XCTAssertNil(inbox.navigationItem.leftBarButtonItem, "embedded without a handler: nothing to leave through")

        var closed = 0
        container.exitHandler = { closed += 1 }
        XCTAssertNotNil(inbox.navigationItem.leftBarButtonItem, "a handler that arrives later adds the button")
        inbox.backAction()
        XCTAssertEqual(closed, 1)

        container.exitHandler = nil
        XCTAssertNil(inbox.navigationItem.leftBarButtonItem, "a handler that goes removes it")
    }

    /// SwiftUI sets a new closure on every update; rebuilding the button each time would reset VoiceOver focus.
    func testReplacingTheExitHandlerWhileOnScreenKeepsTheSameButton() throws {
        container.exitHandler = {}
        show(width: 400, horizontalSizeClass: .compact)
        let button = try XCTUnwrap(inbox.navigationItem.leftBarButtonItem)

        var closed = 0
        container.exitHandler = { closed += 1 }

        XCTAssertTrue(inbox.navigationItem.leftBarButtonItem === button, "same nilness: the button instance stays")
        inbox.backAction()
        XCTAssertEqual(closed, 1, "the new handler is the one that runs")
    }

    func testWithoutAnExitHandlerAnEmbeddedInboxHasNoButton() {
        show(width: 400, horizontalSizeClass: .compact)
        XCTAssertEqual(container.exitStyle, .none)
        XCTAssertNil(inbox.navigationItem.leftBarButtonItem)
    }

    // MARK: Sidebar toggle

    /// The system sidebar toggle is not an item in the chat's `navigationItem`: with `.doubleColumn` UIKit places it
    /// in the secondary column's bar itself, and only while the chat has no leading item of its own (the chat's
    /// back or close button would replace it). That is what can be asserted: the real chat (which installs a back
    /// button in `viewWillAppear`) has no leading item once it is the root of the detail, and the toggle is not
    /// switched off. That UIKit then draws the toggle is verified on a device, not here.
    func testRealChatInTheDetailHasNoLeadingItemSoTheSystemSidebarToggleCanShow() throws {
        inbox.chatFactory = { _ in
            StartViewController(viewModel: StartViewModelStub(),
                                view: .init(uiConfiguration: .defaultValue, localizationConfiguration: .defaultValue))
        }
        for width: CGFloat in [600, 744, 900] {
            show(width: width, height: 1000, horizontalSizeClass: .regular)
            XCTAssertFalse(split.isCollapsed, "\(width)pt")
            XCTAssertNotEqual(split.displayModeButtonVisibility, .never, "\(width)pt")
            XCTAssertEqual(split.preferredDisplayMode, .automatic, "\(width)pt lets the system hide the sidebar")

            select(row: 0)
            layoutEverything()
            let chat = try XCTUnwrap(split.detailNavigationController.viewControllers.first as? StartViewController)
            XCTAssertNil(chat.navigationItem.leftBarButtonItem, "\(width)pt: a leading item would replace the toggle")
            XCTAssertNil(chat.navigationItem.leftBarButtonItems, "\(width)pt")
            XCTAssertTrue(chat.navigationItem.leadingItemGroups.isEmpty, "\(width)pt")
            XCTAssertTrue(split.detailNavigationController.navigationBar.items?.last === chat.navigationItem, "\(width)pt")
            window.isHidden = true
        }
    }
}
