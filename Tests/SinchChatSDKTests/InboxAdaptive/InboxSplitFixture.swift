import XCTest
import UIKit
@testable import SinchChatSDK
import GRPCCore
import GRPCNIOTransportHTTP2

private struct StubAPIClient: APIClient {
    var isChannelStarted: Bool { false }

    func withClient<Result: Sendable>(handle: (GRPCClient<HTTP2ClientTransport.Posix>) async throws -> Result) async throws -> Result {
        throw SinchChatSDKError.unavailable
    }
    func closeChannel() {}
    func startChannel() {}
}

@MainActor
final class InboxViewModelStub: InboxViewModel {
    var delegate: InboxViewModelDelegate?
    var apiClient: APIClient = StubAPIClient()
    var tokenProvider: ChatTokenProvider = MockTokenProvider()
    var channelsArray: [Sinch_Chat_Sdk_V1alpha2_Channel] = []
    var isLoadingMore = false

    func onInternetLost() {}
    func onInternetOn() {}
    func setIdleState() {}
    func closeChannel() {}
    func setInternetConnectionState(_ state: InternetConnectionState) {}
    func fetchMoreChannels() {}
}

/// Inbox + split + container with three channels and fake chats that mimic the one-running-chat rule.
@MainActor
class InboxSplitFixture: XCTestCase {

    var window: UIWindow!
    var inbox: InboxViewController!
    var container: InboxContainerViewController!
    var split: InboxSplitViewController!
    var chatSlot: FakeChatSlot!

    private struct WeakChat { weak var chat: FakeChatViewController? }
    /// Every chat the factory made, in order, held weakly: a replaced chat is deallocated like in production, so its
    /// `deinit` runs (see `FakeChatViewController`) and the tests can see what it does to the slot.
    private var createdChatRefs: [WeakChat] = []
    var createdChatCount: Int { createdChatRefs.count }
    /// The chat made as number `index`, `nil` once it has been deallocated.
    func chat(_ index: Int) -> FakeChatViewController? { createdChatRefs[index].chat }
    func wasTornDown(_ index: Int) -> Bool { chatSlot.tornDownSerials.contains(index) }
    /// Chats that are still alive and not torn down.
    var liveChats: [FakeChatViewController] { createdChatRefs.compactMap(\.chat).filter { !$0.isTornDown } }

    override func setUp() async throws {
        try await super.setUp()
        let viewModel = InboxViewModelStub()
        viewModel.channelsArray = ["one", "two", "three"].map { name in
            var channel = Sinch_Chat_Sdk_V1alpha2_Channel()
            channel.channelID = "channels/\(name)"
            channel.displayName = name
            return channel
        }
        chatSlot = FakeChatSlot()
        let view = InboxView(uiConfiguration: .defaultValue, localizationConfiguration: .defaultValue)
        inbox = InboxViewController(viewModel: viewModel, view: view)
        inbox.chatFactory = { [unowned self] channel in
            try chatSlot.claim()
            let chat = FakeChatViewController(slot: chatSlot, channelID: channel?.channelID)
            createdChatRefs.append(WeakChat(chat: chat))
            return chat
        }
        inbox.alertPresenter = { [unowned self] alert in shownAlerts.append(alert) }
        split = InboxSplitViewController(inbox: inbox)
        container = InboxContainerViewController(splitController: split)
    }

    override func tearDown() async throws {
        window?.isHidden = true
        window = nil
        container = nil
        split = nil
        inbox = nil
        chatSlot = nil
        createdChatRefs = []
        shownAlerts = []
        try await super.tearDown()
    }

    /// Puts the container in a window of the given size and lays it out.
    func show(width: CGFloat,
              height: CGFloat = 800,
              horizontalSizeClass: UIUserInterfaceSizeClass? = nil,
              layoutDirection: UITraitEnvironmentLayoutDirection? = nil) {
        window = UIWindow(frame: CGRect(x: 0, y: 0, width: width, height: height))
        if let horizontalSizeClass {
            container.traitOverrides.horizontalSizeClass = horizontalSizeClass
        }
        if let layoutDirection {
            container.traitOverrides.layoutDirection = layoutDirection
        }
        window.rootViewController = container
        window.makeKeyAndVisible()
        layoutEverything()
    }

    func layoutEverything() {
        window.layoutIfNeeded()
        container.view.layoutIfNeeded()
        split.view.layoutIfNeeded()
    }

    func select(row: Int) {
        let tableView = inbox.mainView.tableView
        let indexPath = IndexPath(row: row, section: 0)
        tableView.selectRow(at: indexPath, animated: false, scrollPosition: .none)
        inbox.tableView(tableView, didSelectRowAt: indexPath)
    }

    var selectedRow: IndexPath? { inbox.mainView.tableView.indexPathForSelectedRow }

    /// Waits for running push / pop / present animations. UIKit ignores a pop issued while a push is in flight,
    /// which is what a user cannot do either.
    func settleTransitions() async {
        await waitUntil {
            split.primaryNavigationController.transitionCoordinator == nil
                && split.detailNavigationController.transitionCoordinator == nil
        }
        try? await Task<Never, Never>.sleep(for: .milliseconds(400))
    }

    /// The "could not open the chat" alerts. They are captured, not presented: an alert presented in a unit-test
    /// window never finishes its transition, and UIKit then ignores later stack changes.
    var shownAlerts: [UIAlertController] = []
}
