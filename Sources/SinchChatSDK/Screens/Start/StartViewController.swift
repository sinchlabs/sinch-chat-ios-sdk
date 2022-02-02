import UIKit
import SafariServices
import GRPC
import Connectivity

class StartViewController: SinchViewController<StartViewModel, StartView> {
    
    var imagePickerHelper: ImagePickerHelper!
    weak var cordinator: RootCoordinator?
    var connectivity = Connectivity()
    
    private(set) lazy var refreshControl: UIRefreshControl = {
        let control = UIRefreshControl()
        control.addTarget(self, action: #selector(loadMoreMessages), for: .valueChanged)
        return control
    }()
    
    var messages: [Message] = []
    
    var additionalBottomInset: CGFloat = 5 {
        didSet {
            let delta = additionalBottomInset - oldValue
            messageCollectionViewBottomInset += delta
        }
    }
    
    private var isFirstLayout: Bool = true
    
    internal var isMessagesControllerBeingDismissed: Bool = false
    
    internal var messageCollectionViewBottomInset: CGFloat = 0 {
        didSet {
            mainView.collectionView.contentInset.bottom = messageCollectionViewBottomInset
            mainView.collectionView.scrollIndicatorInsets.bottom = messageCollectionViewBottomInset
        }
    }
    
    override func commonInit() {
        
        extendedLayoutIncludesOpaqueBars = true
        
        mainView.messageComposeView.delegate = self
        mainView.collectionView.delegate = self
        mainView.collectionView.chatDataSource = self
        mainView.collectionView.touchDelegate = self
        mainView.collectionView.dataSource = self
        mainView.collectionView.keyboardDismissMode = .interactive
        mainView.collectionView.alwaysBounceVertical = true
        mainView.collectionView.refreshControl = refreshControl
        
        if #available(iOS 13.0, *) {
            mainView.collectionView.automaticallyAdjustsScrollIndicatorInsets = false
        }
        mainView.collectionView.showsHorizontalScrollIndicator = false
        
        (viewModel as? DefaultStartViewModel)?.delegate = self
        imagePickerHelper = ImagePickerHelper(presentationController: self, delegate: self)
    }
    
    // MARK: - Lifecycle methods
    
    override func viewDidLoad() {
        super.viewDidLoad()
        
        self.title = mainView.uiConfig.navigationBarText
        refreshControl.beginRefreshing()
        addObservers()
        addNoInternetObservers()
        
    }
    
    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        setNavigationBarStyle(uiConfig: mainView.uiConfig)
        
        if !isFirstLayout {
            addKeyboardObservers()
        }
        
        if isModal {
            addCloseButton()
        }
    }
    
    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        isMessagesControllerBeingDismissed = false
        
    }
    
    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        isMessagesControllerBeingDismissed = true
        removeKeyboardObservers()
    }
    
    override func viewDidDisappear(_ animated: Bool) {
        super.viewDidDisappear(animated)
        isMessagesControllerBeingDismissed = false
    }
    
    override func viewDidLayoutSubviews() {
        // Used to prevent animation of the contentInset after viewDidAppear
        if isFirstLayout {
            defer { isFirstLayout = false }
            addKeyboardObservers()
            messageCollectionViewBottomInset = requiredInitialScrollViewBottomInset()
        }
    }
    
    override func viewSafeAreaInsetsDidChange() {
        super.viewSafeAreaInsetsDidChange()
        messageCollectionViewBottomInset = requiredInitialScrollViewBottomInset()
    }
    
    deinit {
        
        NotificationCenter.default.removeObserver(self, name: UIApplication.willEnterForegroundNotification, object: nil)
        NotificationCenter.default.removeObserver(self, name: UIApplication.didEnterBackgroundNotification, object: nil)
        connectivity.stopNotifier()
        viewModel.onDisappear()
        
    }
    
    override var canBecomeFirstResponder: Bool {
        true
    }
    
    override var inputAccessoryView: UIView? {
        mainView.messageComposeView
    }
    
    func addObservers() {
        NotificationCenter.default.addObserver(self,
                                               selector: #selector(appWillEnterForeground),
                                               name: UIApplication.willEnterForegroundNotification,
                                               object: nil)
        NotificationCenter.default.addObserver(self,
                                               selector: #selector(appDidEnterBackground),
                                               name: UIApplication.didEnterBackgroundNotification,
                                               object: nil)
    }
    
    @objc func appDidEnterBackground() {
        
        viewModel.onDidEnterBackground()
        
    }
    
    @objc func appWillEnterForeground() {
        viewModel.onWillEnterForeground()
    }
    
    func isLastItemVisible() -> Bool {
        
        guard !messages.isEmpty else { return false }
        
        let lastIndexPath = IndexPath(item: 0, section: messages.count - 1)
        
        return  mainView.collectionView.indexPathsForVisibleItems.contains(lastIndexPath)
    }
    
    func resignFirstResponderView() {
        _ = mainView.messageComposeView.resignFirstResponder()
    }
    
    private func addCloseButton() {
        let closeImage = UIImage(named: "closeIcon",
                                 in: Bundle.staticBundle,
                                 compatibleWith: nil)?.withRenderingMode(.alwaysOriginal)
        navigationItem.rightBarButtonItems = [UIBarButtonItem(image: closeImage,
                                                              style: .plain,
                                                              target: self,
                                                              action: #selector(closeAction))
        ]
    }
    
    @objc private func closeAction() {
        self.dismiss(animated: true, completion: nil)
    }
    
    @objc func loadMoreMessages() {
        viewModel.loadHistory()
    }
}
extension StartViewController: ImagePickerDelegate {
    func didSelect(image: UIImage?) {
        
        if let image = image {
            
            self.viewModel.sendMedia(.image(image))
        }
    }
}

extension StartViewController: ComposeViewDelegate {
    func choosePhoto() {
        
        imagePickerHelper.pickPhoto()
        resignFirstResponderView()
    }
    
    func sendMessage(text: String) {
        
        viewModel.sendMessage(.text(text))
    }
}
extension StartViewController: StartViewModelDelegate {
    func setVisibleRefreshActivityIndicator(_ isVisible: Bool) {
        if isVisible {
            if !refreshControl.isRefreshing {
                refreshControl.beginRefreshing()

            }
        } else {
            refreshControl.endRefreshing()
        }
    }
    
    func didChangeInternetState(_ state: InternetConnectionState) {
        switch state {
            
        case .isOn:
            debugPrint("ON ***********")

            mainView.collectionView.refreshControl = refreshControl
            setVisibleRefreshActivityIndicator(true)
            
            viewModel.onInternetOn()
        case .isOff:
            debugPrint("OFF ***********")
            setVisibleRefreshActivityIndicator(false)
            mainView.collectionView.refreshControl = nil
            viewModel.onInternetLost()
            
        case .notDetermined:
            break
        }
        
        mainView.setErrorViewState(state)
    }
    
    func errorSendingMessage(error: MessageDataSourceError) {
        DispatchQueue.main.async {
            debugPrint(error)
            let alert = UIAlertController(title: NSLocalizedString("alert_title_error", bundle: Bundle.staticBundle, comment: ""),
                                          message: NSLocalizedString("alert_message_not_sent", bundle: Bundle.staticBundle, comment: ""),
                                          preferredStyle: .alert)
            alert.addAction(UIAlertAction(title: NSLocalizedString("alert_button_title_ok", bundle: Bundle.staticBundle, comment: ""),
                                          style: .default,
                                          handler: nil))
            self.present(alert, animated: true, completion: nil)
        }
    }
    
    func errorLoadingMoreHistory(error: MessageDataSourceError) {
        DispatchQueue.main.async {
            self.refreshControl.endRefreshing()
            switch error {
                
            case .unknown(_):
                let alert = UIAlertController(title: NSLocalizedString("alert_title_error", bundle: Bundle.staticBundle, comment: ""),
                                              message: NSLocalizedString("alert_could_not_load_history", bundle: Bundle.staticBundle, comment: ""),
                                              preferredStyle: .alert)
                alert.addAction(UIAlertAction(title: NSLocalizedString("alert_button_title_ok", bundle: Bundle.staticBundle, comment: ""),
                                              style: .default,
                                              handler: nil))
                self.present(alert, animated: true, completion: nil)
                
            default :
                break
            }
        }
    }
    
    func didReceiveHistoryFirstMessages(_ messages: [Message]) {
        DispatchQueue.main.async {
            CATransaction.begin()
            CATransaction.setCompletionBlock({
            self.messages =  messages
            self.mainView.collectionView.reloadData()
            self.mainView.collectionView.scrollToLastItem(at: .bottom, animated: false)
            })
            self.refreshControl.endRefreshing()
            
            CATransaction.commit()
        }
    }
    func didReceiveHistoryMessages(_ messages: [Message]) {
        var shouldRemoveFirstMessage: Bool = false
        
        DispatchQueue.main.async {
            CATransaction.begin()
            CATransaction.setCompletionBlock({
                if let messageSendDate = self.messages.first?.body.sendDate, let olderMessageSendDate = messages.last?.body.sendDate {
                    if messageSendDate.isSameDay(olderMessageSendDate) {
                        shouldRemoveFirstMessage = true
                    }
                }
                if shouldRemoveFirstMessage {
                    self.messages.remove(at: 0)
                }
                self.messages.insert(contentsOf: messages, at: 0)
                self.mainView.collectionView.reloadDataAndKeepOffset()
                
            })
            self.refreshControl.endRefreshing()
            
            CATransaction.commit()
            
        }
    }
    
    func didReceiveMessages(_ messages: [Message]) {
        
        DispatchQueue.main.async { [weak self] in
            
            self?.insertMessages(messages)
            self?.mainView.collectionView.scrollToLastItem(animated: true)
        }
    }
    func insertMessages(_ newMessages: [Message]) {
        self.mainView.collectionView.performBatchUpdates({
            
            if newMessages.count == 1 {
                self.messages.append(newMessages[0])
                self.mainView.collectionView.insertSections([ self.messages.count - 1])
            } else if newMessages.count == 2 {
                self.messages.append(contentsOf: newMessages)
                self.mainView.collectionView.insertSections([self.messages.count - 2, self.messages.count - 1])
                
            }
        }, completion: { [weak self] _ in
            if self?.isLastItemVisible() == true {
                self?.mainView.collectionView.scrollToLastItem(animated: false)
            }
        })
    }
}

extension StartViewController: UICollectionViewDataSource, UICollectionViewDelegate, UICollectionViewDelegateFlowLayout {
    
    func numberOfSections(in collectionView: UICollectionView) -> Int {
        messages.count
    }
    
    func collectionView(_ collectionView: UICollectionView, numberOfItemsInSection section: Int) -> Int {
        1
    }
    
    func collectionView(_ collectionView: UICollectionView, cellForItemAt indexPath: IndexPath) -> UICollectionViewCell {
        
        let message = messages[indexPath.section]
        debugPrint(indexPath.section)
        
        if message.body is MessageText {
            let cell = collectionView.dequeueReusableCell(withReuseIdentifier:  TextMessageCell.cellId, for: indexPath) as! TextMessageCell
            cell.configure(with: message, at: indexPath, and: mainView.collectionView)
            return cell
            
        } else if message.body is MessageImage {
            
            let cell = collectionView.dequeueReusableCell(withReuseIdentifier:  ImageMessageCell.cellId, for: indexPath) as! ImageMessageCell
            cell.configure(with: message, at: indexPath, and: mainView.collectionView)
            return cell
        } else if message.body is MessageEvent {
            
            let cell = collectionView.dequeueReusableCell(withReuseIdentifier:  EventMessageCell.cellId, for: indexPath) as! EventMessageCell
            cell.configure(with: message, at: indexPath, and: mainView.collectionView)
            return cell
        } else if message.body is MessageDate {
            
            let cell = collectionView.dequeueReusableCell(withReuseIdentifier:  DateMessageCell.dateCellId, for: indexPath) as! DateMessageCell
            cell.configure(with: message, at: indexPath, and: mainView.collectionView)
            return cell
            
        } else {
            return MessageCollectionViewCell()
        }
    }
    open func collectionView(_ collectionView: UICollectionView, layout collectionViewLayout: UICollectionViewLayout, sizeForItemAt indexPath: IndexPath) -> CGSize {
        guard let chatFlowLayout = collectionViewLayout as? ChatFlowLayout else { return .zero }
        debugPrint(chatFlowLayout.sizeForItem(at: indexPath))
        return chatFlowLayout.sizeForItem(at: indexPath)
    }
    
    func collectionView(_ collectionView: UICollectionView, didSelectItemAt indexPath: IndexPath) {
    }
    
    @available(iOS 13.0, *)
    func collectionView(_ collectionView: UICollectionView, contextMenuConfigurationForItemAt indexPath: IndexPath, point: CGPoint) -> UIContextMenuConfiguration? {
        
        let message = self.messages[indexPath.section]
        if message.body is MessageText {
            return configureContextMenu(index: indexPath.section)
        } else {
            return nil
        }
    }
    
    private func populatePasteBoardIfTextMessage(_ index: Int) {
        let pasteBoard = UIPasteboard.general
        let message = messages[index]
        if let message = message.body as? MessageText {
            pasteBoard.string = message.text
            
        }
    }
    @available(iOS 13.0, *)
    func configureContextMenu(index: Int) -> UIContextMenuConfiguration {
        
        let context = UIContextMenuConfiguration(identifier: nil, previewProvider: nil) { _ in
            let copy = UIAction(title: NSLocalizedString("menu_button_title_copy",
                                                         bundle: Bundle.staticBundle, comment: ""),
                                image: nil, identifier: nil,
                                discoverabilityTitle: nil, state: .off) { [weak self] _ in
                guard let self = self else {
                    return
                }
                self.populatePasteBoardIfTextMessage(index)
            }
            
            return UIMenu(title: NSLocalizedString("menu_title_options", bundle: Bundle.staticBundle, comment: ""),
                          image: nil, identifier: nil, options: UIMenu.Options.displayInline, children: [copy])
        }
        
        return context
        
    }
    
    func collectionView(_ collectionView: UICollectionView, shouldShowMenuForItemAt indexPath: IndexPath) -> Bool {
        let message = messages[indexPath.section]
        if message.body is MessageText {
            return true
        } else {
            return false
        }
    }
    
    func collectionView(_ collectionView: UICollectionView, canPerformAction action: Selector, forItemAt indexPath: IndexPath, withSender sender: Any?) -> Bool {
        
        return (action == NSSelectorFromString("copy:"))
    }
        
    func collectionView(_ collectionView: UICollectionView, performAction action: Selector, forItemAt indexPath: IndexPath, withSender sender: Any?) {
        
        populatePasteBoardIfTextMessage(indexPath.section)
    }
    
}
extension StartViewController: ChatDataSource {
    
    func numberOfSections(in messagesCollectionView: MessageCollectionView) -> Int {
        messages.count
    }
    
    func messageForItem(at indexPath: IndexPath, in messagesCollectionView: MessageCollectionView) -> Message {
        messages[indexPath.section]
    }
}

extension StartViewController: MessageCellDelegate {
    
    func didSelectURL(_ url: URL) {
        // htpps is recognized as link so we need to check if link contains http or https so SFSafariViewController dont crash
        if ["http", "https"].contains(url.scheme?.lowercased() ?? "") {
            
            present(SFSafariViewController(url: url), animated: true)
        }
    }
    func didTapImage(in cell: MessageCollectionViewCell) {
        
        guard let cell  = cell as? ImageMessageCell,
              let indexPath = mainView.collectionView.indexPath(for: cell),
              let message = mainView.collectionView.chatDataSource?.messageForItem(at: indexPath, in: mainView.collectionView) else {
                  debugPrint("Failed to identify message")
                  return
              }
        
        if  let error = cell.error, error {
            
            cell.setupImageView(message: message)
            
        } else {
            if let body = message.body as? MessageImage {
                
                cordinator?.presentMediaViewerController(viewController:self, uiConfig: mainView.uiConfig, mediaMessage: body)
            }
            
        }
    }
    func didTapOutsideOfContent(in cell: MessageCollectionViewCell) {
        resignFirstResponderView()
    }
    
    func didTapOutsideOfContent() {
        resignFirstResponderView()

    }
}
