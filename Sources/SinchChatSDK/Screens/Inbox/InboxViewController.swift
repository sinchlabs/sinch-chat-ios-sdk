import UIKit
import Network
import os

/// Why the chat of a conversation could not be opened from the inbox.
enum InboxChatError: Error {
    /// `getChatViewController` returned something that is not the chat screen.
    case unexpectedController
}

final class InboxViewController: SinchViewController<InboxViewModel, InboxView>, SinchChatViewController, InboxViewModelDelegate {
    
    var customOptions: GetChatViewControllerOptions =  .init(metadata: [], shouldInitializeConversation: true)

    /// Set when the list is the sidebar of an adaptive inbox. `nil` keeps the stack behaviour (push on `navigationController`).
    weak var detailHost: InboxDetailHost?
    /// Set when the list is wrapped by `InboxContainerViewController`; decides what the button on the left does.
    weak var host: InboxHost?
    /// Channel whose chat is open in the detail. Drives the highlighted row on regular width.
    private(set) var selectedChannelID: String?
    /// Creates the chat for a channel (`nil` for a new conversation). Replaceable in tests.
    var chatFactory: (@MainActor (_ channel: Sinch_Chat_Sdk_V1alpha2_Channel?) throws -> UIViewController)?

    /// Replaces the topic ID a new conversation gets (otherwise a fresh UUID for a signed-in user). Replaceable in tests.
    var newTopicIDProvider: (@MainActor () -> String?)?

    /// Shows the "chat could not be opened" alert. `nil` presents it on this controller. Replaceable in tests.
    var alertPresenter: (@MainActor (UIAlertController) -> Void)?

    private static let logger = Logger(subsystem: "com.sinch.chat.sdk", category: "Inbox")

    lazy var activityIndicator = LoadMoreActivityIndicator(scrollView: mainView.tableView, spacingFromLastCell: 10, spacingFromLastCellOnActionStart: 60)
    let monitor = NWPathMonitor()

    override func viewDidLoad() {
        super.viewDidLoad()
        
        self.title = mainView.localizationConfiguration.inboxNavigationBarText
        self.navigationItem.backBarButtonItem = UIBarButtonItem(title: "", style: .plain, target: nil, action: nil)
        mainView.tableView.delegate = self
        mainView.tableView.dataSource = self
        addNoInternetObservers()

        (viewModel as? DefaultInboxViewModel)?.delegate = self
    }
    
    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        
        setNavigationBarStyle(uiConfig: mainView.uiConfig)
        addStartConversationButton()
        updateLeadingBarButton()
    }

    /// Installs, replaces or removes the sidebar's leading button for what the host offers right now. Runs on every
    /// appearance and when the host's exit changes while the list is on screen (`SinchInboxView(onClose:)` updated).
    func updateLeadingBarButton() {
        if let host {
            switch host.exitStyle {
            case .back: addBackButton()
            case .close: addCloseButton()
            case .none: navigationItem.leftBarButtonItem = nil
            }
        } else if isModal {
            addCloseButton()
        } else {
            addBackButton()
        }
    }

    override func closeAction() {
        if let host { host.exitInbox() } else { super.closeAction() }
    }

    override func backAction() {
        if let host { host.exitInbox() } else { super.backAction() }
    }

    /// Called when the split view collapses or expands: only regular width highlights the selected row.
    func adaptiveStateDidChange() {
        guard isViewLoaded else { return }
        mainView.tableView.reloadData()
        syncSelection()
    }

    /// Nothing is open any more (the chat left the primary stack): forget the selection so that a later expand
    /// to regular width does not highlight a conversation that is not shown.
    func clearSelection() {
        selectedChannelID = nil
        guard isViewLoaded else { return }
        syncSelection()
    }

    private var showsPersistentSelection: Bool {
        detailHost?.isShowingDetailBesideList ?? false
    }

    /// Highlights the row of the open chat on regular width, clears the highlight otherwise.
    func syncSelection() {
        let tableView = mainView.tableView
        guard showsPersistentSelection,
              let selectedChannelID,
              let row = viewModel.channelsArray.firstIndex(where: { $0.channelID == selectedChannelID }) else {
            if let selected = tableView.indexPathForSelectedRow {
                tableView.deselectRow(at: selected, animated: false)
            }
            return
        }
        let indexPath = IndexPath(row: row, section: 0)
        if tableView.indexPathForSelectedRow != indexPath {
            tableView.selectRow(at: indexPath, animated: false, scrollPosition: .none)
        }
    }

    deinit {
        let viewModel = self.viewModel
        let monitor = self.monitor
        Task { @MainActor in
            viewModel.setIdleState()
            viewModel.closeChannel()
        }
        monitor.cancel()

    }
    private func addStartConversationButton() {
        
        let startConversationButton = UIButton(type: .custom)
        startConversationButton.setImage(mainView.uiConfig.inboxStartConversationImage, for: .normal)
        startConversationButton.addTarget(self, action: #selector(startConversationAction), for: .touchUpInside)

        let rightBarButton = UIBarButtonItem(customView: startConversationButton)
        navigationItem.rightBarButtonItem = rightBarButton
        
    }
    @objc func startConversationAction() {
        showChat()
    }
    
    func addNoInternetObservers() {
        
        monitor.pathUpdateHandler = { [weak self] path in
            DispatchQueue.main.async { [weak self] in
                if path.status == .satisfied {
                    self?.viewModel.setInternetConnectionState(.isOn)
                } else {
                    self?.viewModel.setInternetConnectionState(.isOff)
                }
            }
        }
        let queue = DispatchQueue(label: "internetConnectionMonitor")
        monitor.start(queue: queue)
    }
    
    func didChangeInternetState(_ state: InternetConnectionState) {
        switch state {
            
        case .isOn:
            debugPrint("ON ***********")
                    
            viewModel.onInternetOn()
            
        case .isOff:
            debugPrint("OFF ***********")

            viewModel.onInternetLost()
            
        case .notDetermined:
            break
        }
        
        mainView.setErrorViewState(state)
    }
    
    func didUpdateChannels(_ channels: [Sinch_Chat_Sdk_V1alpha2_Channel]) {

        debugPrint("didUpdateChannels")
        mainView.tableView.reloadData()
        syncSelection()
        self.activityIndicator.stop()

    }

    func didUpdateChannelAtIndex(_ index: Int) {
        debugPrint("didUpdateChannel")
       // if let row = viewModel.channelsArray.firstIndex(where: { $0.channelID == channel.channelID }) {
        mainView.tableView.reloadRows(at: [IndexPath(row: index, section: 0)], with: .none)
        syncSelection()

    }
    func moveChannelToTopFromIndex(_ index: Int) {
        debugPrint("moveChannelToTopFromIndex")

        mainView.tableView.beginUpdates()
        mainView.tableView.moveRow(at: IndexPath(row: index, section: 0), to: IndexPath(row: 0, section: 0))
        mainView.tableView.endUpdates()
        syncSelection()

    }
    func handleError(_ error: Error) {
        debugPrint("handleError")

     //   DispatchQueue.main.async {
            
            self.activityIndicator.stop()
     //   }
    }
}
extension InboxViewController: UITableViewDataSource {
    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        return viewModel.channelsArray.count
    }
    
    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        guard let cell = tableView.dequeueReusableCell(withIdentifier: "inboxCell", for: indexPath) as? InboxTableViewCell else {
            return UITableViewCell()
        }
        if showsPersistentSelection {
            // Sidebar: the row of the open chat stays highlighted, with a semantic system fill.
            cell.selectionStyle = .default
            let selectedBackground = UIView()
            selectedBackground.backgroundColor = .tertiarySystemFill
            cell.selectedBackgroundView = selectedBackground
        } else {
            cell.selectionStyle = .none
            cell.selectedBackgroundView = nil
        }
        cell.updateWithChannel(viewModel.channelsArray[indexPath.row],
                               uiConfig: mainView.uiConfig,
                               localizationConfig: mainView.localizationConfiguration)
        
        return cell
    }
}
extension InboxViewController: UITableViewDelegate {
    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
    
        let channel = viewModel.channelsArray[indexPath.row]
        
        showChatForChannel(channel)
    }
    
    func scrollViewDidScroll(_ scrollView: UIScrollView) {
        if self.viewModel.isLoadingMore {
            return
        }
        activityIndicator.start {

            DispatchQueue.global(qos: .utility).async {
                sleep(1)
                Task { @MainActor in
                    self.viewModel.fetchMoreChannels()
                }
            }
        }
    }
    func showChatForChannel(_ channel: Sinch_Chat_Sdk_V1alpha2_Channel) {

        // Same conversation as the one already open beside the list: nothing to do.
        if let detailHost, detailHost.isShowingDetailBesideList,
           detailHost.hasDetailChat, selectedChannelID == channel.channelID {
            return
        }

        customOptions = .init(
            topicID: channel.channelID,
            metadata: customOptions.metadata,
            shouldInitializeConversation: customOptions.shouldInitializeConversation,
            sendDocumentAsTextMessage: customOptions.sendDocumentAsTextMessage
        )
        present(chatFor: channel)
    }

    func showChat() {

        // Only a topic ID made here names the new row. `customOptions.topicID` may still hold the one of the row that
        // was opened before, which is not this conversation.
        var newTopicID = newTopicIDProvider?()
        if newTopicID == nil, viewModel.tokenProvider.currentAuthorization?.getUserID() != nil {
            newTopicID = "\(UUID().uuidString)"
        }
        if let newTopicID { customOptions.topicID = newTopicID }
        // A new conversation has no row yet. When its topic ID is known (signed-in user) it becomes the channel ID,
        // so the row is highlighted as soon as it shows up in the list (`syncSelection` runs on every list update).
        present(chatFor: nil, selecting: newTopicID)
        customOptions.topicID = nil
    }

    /// Creates the chat with the existing code path (`SinchChat.getChatViewController`, started from the inbox).
    private func makeChatViewController(for channel: Sinch_Chat_Sdk_V1alpha2_Channel?) throws -> UIViewController {
        if let chatFactory { return try chatFactory(channel) }
        let chat = try SinchChatSDK.shared.chat.getChatViewController(
            uiConfig: mainView.uiConfig,
            localizationConfig: mainView.localizationConfiguration,
            options: customOptions)
        guard let chatViewController = chat as? StartViewController else { throw InboxChatError.unexpectedController }
        chatViewController.viewModel.isStartedFromInbox = true
        return chatViewController
    }

    /// The one path every switch goes through: beside the list (regular), pushed on the list (collapsed), or pushed
    /// on the navigation stack when the inbox has no detail (`SinchInboxLayout.stack`).
    ///
    /// Only one chat can run at a time and `getChatViewController` is refused while the old one runs, so the open
    /// chat is torn down synchronously (`clearChat`) before the next one is created. Nothing is deferred, so a quick
    /// second tap cannot interleave with a half-finished switch. The row stays selected only when the new chat opened.
    private func present(chatFor channel: Sinch_Chat_Sdk_V1alpha2_Channel?, selecting newChannelID: String? = nil) {
        guard let detailHost else {
            do {
                navigationController?.pushViewController(try makeChatViewController(for: channel), animated: true)
            } catch {
                reportChatFailure(error)
            }
            return
        }

        detailHost.clearChat()
        do {
            detailHost.showChat(try makeChatViewController(for: channel))
            selectedChannelID = channel?.channelID ?? newChannelID
        } catch {
            selectedChannelID = nil
            reportChatFailure(error)
        }
        syncSelection()
    }

    private func reportChatFailure(_ error: Error) {
        Self.logger.error("Could not open the chat: \(String(describing: error), privacy: .public)")
        guard viewIfLoaded?.window != nil else { return }
        let alert = UIAlertController(title: mainView.localizationConfiguration.alertTitleError,
                                      message: nil,
                                      preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: mainView.localizationConfiguration.locationAlertButtonTitleOk, style: .default))
        if let alertPresenter {
            alertPresenter(alert)
        } else if presentedViewController == nil {
            present(alert, animated: true)
        }
    }

}
