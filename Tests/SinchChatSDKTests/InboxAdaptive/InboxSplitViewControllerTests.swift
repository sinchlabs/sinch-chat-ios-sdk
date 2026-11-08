import XCTest
import UIKit
@testable import SinchChatSDK

@MainActor
final class InboxSplitViewControllerTests: InboxSplitFixture {

    // MARK: Configuration

    func testSplitIsDoubleColumnWithInboxAsPrimaryAndPlaceholderAsSecondary() throws {
        XCTAssertEqual(split.style, .doubleColumn)
        let primary = try XCTUnwrap(split.viewController(for: .primary) as? UINavigationController)
        XCTAssertTrue(primary.viewControllers.first === inbox)
        let secondary = try XCTUnwrap(split.viewController(for: .secondary) as? UINavigationController)
        XCTAssertTrue(secondary.viewControllers.first is InboxEmptyDetailViewController)
    }

    func testColumnWidths() {
        XCTAssertEqual(split.preferredPrimaryColumnWidth, 320)
        XCTAssertEqual(split.minimumPrimaryColumnWidth, 280)
        XCTAssertEqual(split.maximumPrimaryColumnWidth, 360)
    }

    func testNoSeparateCompactControllerSoUIKitStacksTheColumns() {
        XCTAssertNil(split.viewController(for: .compact))
    }

    func testContainerEmbedsTheSplitAsChild() {
        show(width: 1024)
        XCTAssertTrue(split.parent === container)
        XCTAssertTrue(split.view.superview === container.view)
    }

    func testWideWindowKeepsSidebarVisibleBesideTheChat() {
        show(width: 1180, height: 820)
        XCTAssertFalse(split.isCollapsed)
        XCTAssertEqual(split.preferredDisplayMode, .oneBesideSecondary)
        XCTAssertEqual(split.displayMode, .oneBesideSecondary)
        XCTAssertEqual(split.primaryColumnWidth, 320, accuracy: 1)
    }

    func testMediumWindowLetsTheSystemHideTheSidebar() {
        show(width: 744, height: 1000)
        XCTAssertFalse(split.isCollapsed)
        XCTAssertEqual(split.preferredDisplayMode, .automatic)
        XCTAssertNotEqual(split.displayModeButtonVisibility, .never)
    }

    func testEmptyStateUsesLocalizedTextFromTheLocalizationConfig() throws {
        show(width: 1024)
        let placeholder = split.emptyDetailViewController
        _ = placeholder.view
        let configuration = try XCTUnwrap(placeholder.contentUnavailableConfiguration as? UIContentUnavailableConfiguration)
        XCTAssertEqual(configuration.text, SinchSDKConfig.LocalizationConfig.defaultValue.inboxEmptyDetailText)
        XCTAssertFalse(SinchSDKConfig.LocalizationConfig.defaultValue.inboxEmptyDetailText.isEmpty)
        XCTAssertEqual(SinchSDKConfig.LocalizationConfig.defaultValue.inboxEmptyDetailText, "Select a conversation")
    }

    // MARK: Selection

    func testSelectingARowShowsTheChatInTheDetailAndKeepsTheRowHighlighted() {
        show(width: 1024)
        select(row: 1)

        XCTAssertEqual(createdChatCount, 1)
        XCTAssertTrue(split.detailNavigationController.viewControllers.first === chat(0)!)
        XCTAssertTrue(split.hasDetailChat)
        XCTAssertEqual(inbox.selectedChannelID, "channels/two")
        XCTAssertEqual(inbox.mainView.tableView.indexPathForSelectedRow, IndexPath(row: 1, section: 0))

        let cell = inbox.tableView(inbox.mainView.tableView, cellForRowAt: IndexPath(row: 1, section: 0))
        XCTAssertEqual(cell.selectionStyle, .default)
    }

    func testSelectingTheOpenConversationAgainDoesNotRecreateTheChat() {
        show(width: 1024)
        select(row: 0)
        select(row: 0)
        XCTAssertEqual(createdChatCount, 1)
    }

    func testSelectingAnotherConversationReplacesTheChatAtOnce() {
        show(width: 1024)
        select(row: 0)
        select(row: 2)

        // Synchronous: the old chat is still alive here (the test holds it), yet the next one could be created,
        // because the old one was torn down explicitly instead of waiting for its deallocation.
        XCTAssertEqual(createdChatCount, 2)
        XCTAssertTrue(wasTornDown(0))
        XCTAssertFalse(wasTornDown(1))
        XCTAssertTrue(chatSlot.isRunning)
        XCTAssertTrue(split.detailNavigationController.viewControllers.first === chat(1)!)
        XCTAssertEqual(inbox.selectedChannelID, "channels/three")
        XCTAssertEqual(selectedRow, IndexPath(row: 2, section: 0))
    }

    func testRowsAreNotHighlightedWhenTheListIsNotBesideTheChat() {
        show(width: 400, horizontalSizeClass: .compact)
        XCTAssertTrue(split.isCollapsed)
        let cell = inbox.tableView(inbox.mainView.tableView, cellForRowAt: IndexPath(row: 0, section: 0))
        XCTAssertEqual(cell.selectionStyle, .none)
    }

    // MARK: Collapse and expand

    func testCompactWindowShowsTheListAloneWhenNoChatIsOpen() {
        show(width: 400, horizontalSizeClass: .compact)
        XCTAssertTrue(split.isCollapsed)
        let primary = split.primaryNavigationController
        XCTAssertEqual(primary.viewControllers.count, 1)
        XCTAssertTrue(primary.topViewController === inbox)
    }

    func testCompactSelectionPushesTheChatOnTheList() {
        show(width: 400, horizontalSizeClass: .compact)
        select(row: 0)

        XCTAssertEqual(createdChatCount, 1)
        let primary = split.primaryNavigationController
        XCTAssertTrue(primary.viewControllers.first === inbox)
        XCTAssertTrue(primary.viewControllers.contains(chat(0)!),
                      "chat must be pushed on the list, got \(primary.viewControllers)")
        XCTAssertTrue(primary.topViewController === chat(0)!)
    }

    func testCollapsingKeepsTheOpenChatPushedOnTheList() {
        show(width: 1024)
        select(row: 1)
        XCTAssertFalse(split.isCollapsed)

        container.traitOverrides.horizontalSizeClass = .compact
        window.layoutIfNeeded()
        split.view.layoutIfNeeded()

        XCTAssertTrue(split.isCollapsed)
        let primary = split.primaryNavigationController
        XCTAssertTrue(primary.viewControllers.first === inbox)
        XCTAssertTrue(primary.topViewController === chat(0)!,
                      "open chat must stay on top of the list, got \(primary.viewControllers)")
        XCTAssertEqual(createdChatCount, 1, "collapsing must not recreate the chat")
    }

    func testCollapsingWithoutAChatShowsTheListNotThePlaceholder() {
        show(width: 1024)
        container.traitOverrides.horizontalSizeClass = .compact
        window.layoutIfNeeded()

        XCTAssertTrue(split.isCollapsed)
        XCTAssertTrue(split.primaryNavigationController.topViewController === inbox)
        XCTAssertFalse(split.primaryNavigationController.viewControllers.contains { $0 is InboxEmptyDetailViewController })
    }

    func testExpandingRestoresTheChatBesideTheList() async {
        show(width: 1024, horizontalSizeClass: .compact)
        XCTAssertTrue(split.isCollapsed)
        select(row: 2)
        XCTAssertTrue(split.primaryNavigationController.topViewController === chat(0)!)

        container.traitOverrides.horizontalSizeClass = .regular
        window.layoutIfNeeded()
        split.view.layoutIfNeeded()
        await waitUntil { split.primaryNavigationController.viewControllers.count == 1 }

        XCTAssertFalse(split.isCollapsed)
        XCTAssertEqual(split.primaryNavigationController.viewControllers.count, 1)
        XCTAssertTrue(split.primaryNavigationController.topViewController === inbox)
        XCTAssertTrue(split.detailNavigationController.viewControllers.first === chat(0)!)
        XCTAssertEqual(createdChatCount, 1, "expanding must not recreate the chat")
        XCTAssertEqual(inbox.mainView.tableView.indexPathForSelectedRow, IndexPath(row: 2, section: 0))
    }

    // MARK: Hosting

    func testPresentedBareTheContainerOffersClose() {
        let presenter = UIViewController()
        window = UIWindow(frame: CGRect(x: 0, y: 0, width: 400, height: 800))
        window.rootViewController = presenter
        window.makeKeyAndVisible()
        presenter.present(container, animated: false)
        XCTAssertEqual(container.exitStyle, .close)
    }

    func testPushedOnAHostStackTheContainerOffersBackAndHidesTheHostBar() {
        let root = UIViewController()
        let navigation = UINavigationController(rootViewController: root)
        window = UIWindow(frame: CGRect(x: 0, y: 0, width: 400, height: 800))
        window.rootViewController = navigation
        window.makeKeyAndVisible()
        navigation.pushViewController(container, animated: false)
        window.layoutIfNeeded()

        XCTAssertEqual(container.exitStyle, .back)
        XCTAssertTrue(navigation.isNavigationBarHidden)
        container.exitInbox()
        XCTAssertEqual(navigation.viewControllers.count, 1)
    }

    func testEmbeddedAsAChildThereIsNothingToExit() {
        let parent = UIViewController()
        window = UIWindow(frame: CGRect(x: 0, y: 0, width: 400, height: 800))
        window.rootViewController = parent
        window.makeKeyAndVisible()
        parent.addChild(container)
        parent.view.addSubview(container.view)
        container.didMove(toParent: parent)
        XCTAssertEqual(container.exitStyle, .none)
    }

    // MARK: SwiftUI wrappers

    func testSwiftUIInboxWrapperDoesNotNestTheAdaptiveInboxInANavigationController() {
        XCTAssertTrue(SinchInboxView.hostViewController(for: container) === container)
        let list = UIViewController()
        let wrapped = SinchInboxView.hostViewController(for: list)
        XCTAssertTrue((wrapped as? UINavigationController)?.viewControllers.first === list)
    }

    func testSwiftUIChatWrapperDoesNotWrapTwice() {
        let navigation = UINavigationController(rootViewController: UIViewController())
        XCTAssertTrue(SinchChatView.navigationController(for: navigation) === navigation)
        let chat = UIViewController()
        XCTAssertTrue(SinchChatView.navigationController(for: chat).viewControllers.first === chat)
    }
}
