import UIKit

final class InboxViewController: SinchViewController<InboxViewModel, InboxView>, SinchChatViewController {
    
    var customOptions: GetChatViewControllerOptions =  .init(metadata: [], shouldInitializeConversation: true)
    
    var conversations : [InboxChat] = []
    lazy var activityIndicator = LoadMoreActivityIndicator(scrollView: mainView.tableView, spacingFromLastCell: 10, spacingFromLastCellOnActionStart: 60)
    
    override func viewDidLoad() {
        super.viewDidLoad()
        
        self.title = mainView.localizationConfiguration.inboxNavigationBarText
        self.navigationItem.backBarButtonItem = UIBarButtonItem(title: "", style: .plain, target: nil, action: nil)
        mainView.tableView.delegate = self
        mainView.tableView.dataSource = self
    }
    
    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        
        setNavigationBarStyle(uiConfig: mainView.uiConfig)
        addStartConversationButton()
      
        if let data = UserDefaults.standard.data(forKey: "lastMessage") {
            do {
                // Create JSON Decoder
                let decoder = JSONDecoder()

                // Decode Note
                let conversation = try decoder.decode(InboxChat.self, from: data)
                conversations = [conversation]
                mainView.tableView.reloadData()
            } catch {
                print("Unable to Decode Note (\(error))")
            }
        }
        if isModal {
            addCloseButton()
        } else {
            addBackButton()
        }
        
    }
    deinit {
               
        viewModel.closeChannel()
        
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

}
extension InboxViewController: UITableViewDataSource {
    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        return conversations.count
    }
    
    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        guard let cell = tableView.dequeueReusableCell(withIdentifier: "inboxCell", for: indexPath) as? InboxTableViewCell else {
            return UITableViewCell()
        }
        
        cell.updateWithData(inboxChat:conversations[indexPath.row],
                            uiConfig: mainView.uiConfig,
                            localizationConfig: mainView.localizationConfiguration)
        
        return cell
    }
}
extension InboxViewController: UITableViewDelegate {
    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
    
        showChatForConversation(self.conversations[indexPath.row])
    }
    
    func scrollViewDidScroll(_ scrollView: UIScrollView) {
//        activityIndicator.start {
//            
//            DispatchQueue.global(qos: .utility).async {
//                sleep(1)
//                
//                DispatchQueue.main.async { [weak self] in
//                    self?.numberOfConversations += 10
//                    self?.mainView.tableView.reloadData()
//                    self?.activityIndicator.stop()
//                }
//            }
//        }
    }
    func showChatForConversation(_ conversation: InboxChat) {
        
       customOptions = .init(topicID: conversation.chatOptions?.option?.topicID,
                                                          metadata: conversation.chatOptions?.option?.metadata ?? [], shouldInitializeConversation: true)
        SinchChatSDK.shared._chat.apiClient = viewModel.apiClient
        
        guard let chatViewController = (try? SinchChatSDK.shared.chat.getChatViewController(
            uiConfig: mainView.uiConfig,
            localizationConfig: mainView.localizationConfiguration,
            options: customOptions)
        ) as? StartViewController else {
            return
        }
        chatViewController.viewModel.isStartedFromInbox = true
        
        self.navigationController?.pushViewController(chatViewController, animated: true)
    }
    
    func showChat() {
        
        SinchChatSDK.shared._chat.apiClient = viewModel.apiClient
        guard let chatViewController = (try? SinchChatSDK.shared.chat.getChatViewController(
            uiConfig: mainView.uiConfig,
            localizationConfig: mainView.localizationConfiguration,
            options: customOptions)
        ) as? StartViewController else {
            return
        }
        chatViewController.viewModel.isStartedFromInbox = true
        
        self.navigationController?.pushViewController(chatViewController, animated: true)
    }
}
