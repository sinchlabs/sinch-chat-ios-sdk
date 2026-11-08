import XCTest
import UIKit
import Combine
@testable import SinchChatSDK

/// Switching chats while the SDK allows one running chat only: teardown order, quick taps, failures, selection.
@MainActor
final class InboxChatSwitchingTests: InboxSplitFixture {

    // MARK: Quick taps

    func testQuickTapsOnDifferentRowsLeaveExactlyOneRunningChat() async {
        show(width: 1024)
        select(row: 0)
        select(row: 1)
        select(row: 2)

        XCTAssertEqual(createdChatCount, 3)
        XCTAssertEqual(liveChats.count, 1)
        XCTAssertTrue(liveChats.first === chat(2)!)
        XCTAssertTrue(split.detailNavigationController.viewControllers == [chat(2)!])
        XCTAssertEqual(inbox.selectedChannelID, "channels/three")
        XCTAssertEqual(selectedRow, IndexPath(row: 2, section: 0))

        // Nothing is pending that could create a second chat later.
        for _ in 0..<5 { await Task.yield() }
        try? await Task<Never, Never>.sleep(for: .milliseconds(50))
        XCTAssertEqual(createdChatCount, 3)
        XCTAssertTrue(split.detailNavigationController.viewControllers == [chat(2)!])
        XCTAssertTrue(chatSlot.isRunning)
    }

    func testQuickTapsOnTheSameRowCreateOneChat() async {
        show(width: 1024)
        select(row: 1)
        select(row: 1)
        select(row: 1)
        for _ in 0..<5 { await Task.yield() }

        XCTAssertEqual(createdChatCount, 1)
        XCTAssertFalse(wasTornDown(0))
    }

    func testNewConversationAfterARowReplacesTheChatAndClearsTheSelection() {
        show(width: 1024)
        select(row: 1)
        inbox.startConversationAction()

        XCTAssertEqual(createdChatCount, 2)
        XCTAssertTrue(wasTornDown(0))
        XCTAssertTrue(split.detailNavigationController.viewControllers == [chat(1)!])
        XCTAssertNil(inbox.selectedChannelID)
        XCTAssertNil(selectedRow)
    }

    // MARK: Deinit of a replaced chat

    func testLateDeinitOfAReplacedChatDoesNotReleaseTheSlotUnderTheNextChat() async {
        show(width: 1024)
        select(row: 0)
        select(row: 1)

        // The first chat is no longer on screen and nothing else holds it: it is deallocated like in production.
        await waitUntil { chat(0) == nil }
        // Its `deinit` hops to the main actor to release the slot; give that hop (and a few more) time to run.
        for _ in 0..<5 { await Task.yield() }
        await waitUntil { chatSlot.events.contains("deinit(0)") }

        XCTAssertTrue(chatSlot.isRunning, "the late deinit of chat 0 must not set the slot idle under chat 1")
        XCTAssertEqual(chatSlot.events.filter { !$0.hasPrefix("deinit") }, ["start(0)", "close(0)", "start(1)"],
                       "chat 0 gives the slot back before chat 1 claims it")
        XCTAssertNotNil(chat(1))
        XCTAssertTrue(split.detailNavigationController.viewControllers.first === chat(1))
    }

    // MARK: New conversation

    func testNewConversationRowIsHighlightedOnceItAppearsInTheList() throws {
        show(width: 1024)
        inbox.newTopicIDProvider = { "channels/new" }
        inbox.startConversationAction()

        XCTAssertEqual(inbox.selectedChannelID, "channels/new")
        XCTAssertNil(selectedRow, "the row does not exist yet")

        let viewModel = try XCTUnwrap(inbox.viewModel as? InboxViewModelStub)
        var channel = Sinch_Chat_Sdk_V1alpha2_Channel()
        channel.channelID = "channels/new"
        channel.displayName = "new"
        viewModel.channelsArray.insert(channel, at: 0)
        inbox.didUpdateChannels(viewModel.channelsArray)

        XCTAssertEqual(selectedRow, IndexPath(row: 0, section: 0))
    }

    func testNewConversationWithoutATopicIDHighlightsNothing() {
        show(width: 1024)
        select(row: 1)
        inbox.startConversationAction()

        XCTAssertNil(inbox.selectedChannelID)
        XCTAssertNil(selectedRow)
    }

    // MARK: Real chat

    private func makeRealChat() -> StartViewController {
        let viewModel = DefaultStartViewModel(messageDataSource: MessageDataSourceStub(),
                                              notificationPermission: PushNotificationHandlerStub())
        viewModel.isStartedFromInbox = true
        return StartViewController(viewModel: viewModel,
                                   view: .init(uiConfiguration: .defaultValue, localizationConfiguration: .defaultValue))
    }

    private final class CloseCounter { var count = 0 }

    private func countCloseEvents() -> (CloseCounter, AnyCancellable) {
        let counter = CloseCounter()
        let subscription = SinchChatSDK.shared.eventListenerSubject.sink { event in
            if case .didCloseChat = event { counter.count += 1 }
        }
        return (counter, subscription)
    }

    func testRealChatDeinitAfterTearDownForReplacementPostsNoSecondCloseAndKeepsTheNextChatsState() async {
        let previousState = SinchChatSDK.shared._chat.state
        let previousOwner = SinchChatSDK.shared._chat.stateOwner
        defer { SinchChatSDK.shared._chat.setFlag(state: previousState, owner: previousOwner) }
        let (closes, subscription) = countCloseEvents()
        defer { subscription.cancel() }

        var chat: StartViewController? = makeRealChat()
        weak var weakChat = chat
        chat?.tearDownForReplacement()
        XCTAssertEqual(closes.count, 1, "the teardown posts .didCloseChat once")

        // The next chat claims the slot, then the old one is deallocated.
        SinchChatSDK.shared._chat.setFlag(state: .running, owner: nil)
        chat = nil
        await waitUntil { weakChat == nil }
        for _ in 0..<5 { await Task.yield() }
        try? await Task<Never, Never>.sleep(for: .milliseconds(50))

        XCTAssertEqual(closes.count, 1, "deinit must not post a second .didCloseChat")
        XCTAssertEqual(SinchChatSDK.shared._chat.state, .running, "deinit must not set the next chat's state idle")
    }

    func testRealChatDeinitWithoutTearDownStillPostsCloseAndSetsTheStateIdle() async {
        let previousState = SinchChatSDK.shared._chat.state
        let previousOwner = SinchChatSDK.shared._chat.stateOwner
        defer { SinchChatSDK.shared._chat.setFlag(state: previousState, owner: previousOwner) }
        let (closes, subscription) = countCloseEvents()
        defer { subscription.cancel() }

        // Control for the test above: an ordinary chat still cleans up in deinit, so that test would notice a change.
        var chat: StartViewController? = makeRealChat()
        weak var weakChat = chat
        SinchChatSDK.shared._chat.setFlag(state: .running, owner: nil)
        chat = nil
        await waitUntil { weakChat == nil }
        await waitUntil { SinchChatSDK.shared._chat.state == .idle }

        XCTAssertEqual(closes.count, 1)
        XCTAssertEqual(SinchChatSDK.shared._chat.state, .idle)
    }

    // MARK: Failure

    func testFailedSwitchShowsTheErrorAndDoesNotKeepTheRowSelected() {
        show(width: 1024)
        select(row: 0)
        chatSlot.failNextClaim = true
        select(row: 1)

        XCTAssertNil(inbox.selectedChannelID)
        XCTAssertNil(selectedRow, "a row whose chat did not open must not stay selected")
        XCTAssertTrue(split.detailNavigationController.viewControllers == [split.emptyDetailViewController])
        XCTAssertFalse(split.hasDetailChat)
        XCTAssertEqual(shownAlerts.last?.title, SinchSDKConfig.LocalizationConfig.defaultValue.alertTitleError)
    }

    func testTappingAgainAfterAFailureOpensTheChat() {
        show(width: 1024)
        select(row: 0)
        chatSlot.failNextClaim = true
        select(row: 1)
        XCTAssertEqual(shownAlerts.count, 1)
        select(row: 1)

        XCTAssertEqual(inbox.selectedChannelID, "channels/two")
        XCTAssertEqual(selectedRow, IndexPath(row: 1, section: 0))
        XCTAssertEqual(split.detailNavigationController.viewControllers.count, 1)
        XCTAssertTrue(split.detailNavigationController.viewControllers.first === chat(createdChatCount - 1))
        XCTAssertEqual(shownAlerts.count, 1, "the second tap worked, so no second alert")
    }

    func testFailureOfTheFirstChatInTheSplitShowsTheError() {
        show(width: 1024)
        chatSlot.failNextClaim = true
        select(row: 2)

        XCTAssertTrue(createdChatCount == 0)
        XCTAssertNil(inbox.selectedChannelID)
        XCTAssertNil(selectedRow)
        XCTAssertEqual(shownAlerts.count, 1)
    }

    // MARK: Collapse and expand

    func testCollapsingMovesTheChatAndAPushedPreviewOntoTheListAndExpandingMovesThemBack() {
        show(width: 1024)
        select(row: 1)
        let preview = UIViewController()
        split.detailNavigationController.pushViewController(preview, animated: false)
        XCTAssertTrue(split.detailNavigationController.viewControllers == [chat(0)!, preview])

        container.traitOverrides.horizontalSizeClass = .compact
        layoutEverything()

        XCTAssertTrue(split.isCollapsed)
        XCTAssertTrue(split.primaryNavigationController.viewControllers == [inbox, chat(0)!, preview])
        XCTAssertTrue(split.detailNavigationController.viewControllers == [split.emptyDetailViewController])
        XCTAssertFalse(wasTornDown(0), "collapsing must not stop the chat")
        XCTAssertEqual(createdChatCount, 1)

        container.traitOverrides.horizontalSizeClass = .regular
        layoutEverything()

        XCTAssertFalse(split.isCollapsed)
        XCTAssertTrue(split.primaryNavigationController.viewControllers == [inbox])
        XCTAssertTrue(split.detailNavigationController.viewControllers == [chat(0)!, preview])
        XCTAssertFalse(wasTornDown(0))
        XCTAssertEqual(inbox.selectedChannelID, "channels/two", "expanding must keep the selection of the open chat")
        XCTAssertEqual(selectedRow, IndexPath(row: 1, section: 0))
    }

    // MARK: Selection after leaving the chat

    func testPoppingTheChatOnCompactWidthClearsTheSelectionAndReleasesTheSlot() async {
        show(width: 400, horizontalSizeClass: .compact)
        select(row: 0)
        await settleTransitions()
        XCTAssertTrue(split.primaryNavigationController.topViewController === chat(0)!)
        XCTAssertEqual(inbox.selectedChannelID, "channels/one")

        split.primaryNavigationController.popViewController(animated: false)
        // UIKit reports the pop (`didShow`) one runloop turn later.
        await waitUntil { inbox.selectedChannelID == nil }

        XCTAssertNil(inbox.selectedChannelID)
        XCTAssertTrue(wasTornDown(0), "the popped chat must give the slot back without waiting for deinit")
        XCTAssertFalse(chatSlot.isRunning)
        XCTAssertFalse(split.hasDetailChat)

        // The next tap right after the pop works.
        select(row: 1)
        XCTAssertEqual(createdChatCount, 2)
        XCTAssertTrue(split.primaryNavigationController.topViewController === chat(1)!)
    }

    func testExpandingAfterAPopDoesNotHighlightTheStaleRow() async {
        show(width: 1024, horizontalSizeClass: .compact)
        select(row: 2)
        await settleTransitions()
        split.primaryNavigationController.popViewController(animated: false)
        await waitUntil { inbox.selectedChannelID == nil }

        container.traitOverrides.horizontalSizeClass = .regular
        layoutEverything()

        XCTAssertFalse(split.isCollapsed)
        XCTAssertNil(inbox.selectedChannelID)
        XCTAssertNil(selectedRow)
        XCTAssertTrue(split.detailNavigationController.viewControllers == [split.emptyDetailViewController])
    }

    func testCollapsingAndExpandingByItselfDoesNotClearTheSelection() {
        show(width: 1024)
        select(row: 0)
        container.traitOverrides.horizontalSizeClass = .compact
        layoutEverything()
        XCTAssertEqual(inbox.selectedChannelID, "channels/one")
        container.traitOverrides.horizontalSizeClass = .regular
        layoutEverything()
        XCTAssertEqual(inbox.selectedChannelID, "channels/one")
        XCTAssertEqual(selectedRow, IndexPath(row: 0, section: 0))
    }

    func testRealStartViewControllerIsReplaceable() {
        // The production chat opts in to the synchronous teardown through `StartViewController+Replacement.swift`.
        XCTAssertTrue((StartViewController.self as Any) is InboxReplaceableChat.Type)
    }
}
