import UIKit
import SafariServices
import GRPC
import Connectivity
import AVFoundation
import AVKit

// swiftlint:disable file_length

enum PlayingItem {
    case localMedia(url: URL)
    case mediaMessage(message: Message)
}

class StartViewController: SinchViewController<StartViewModel, StartView > {
    
    var imagePickerHelper: ImagePickerHelper!
    weak var cordinator: RootCoordinator?
    var connectivity = Connectivity()
    
    private(set) lazy var refreshControl: UIRefreshControl = {
        let control = UIRefreshControl()
        control.addTarget(self, action: #selector(loadMoreMessages), for: .valueChanged)
        return control
    }()
    
    var messages: [Message] = []
    var playingItem: PlayingItem?
    
    var additionalBottomInset: CGFloat = 5 {
        didSet {
            let delta = additionalBottomInset - oldValue
            messageCollectionViewBottomInset += delta
        }
    }
    private var isScrolledToBottom = false
    private var isFirstLayout: Bool = true
    
    internal var isMessagesControllerBeingDismissed: Bool = false
    
    internal var messageCollectionViewBottomInset: CGFloat = 0 {
        didSet {
            mainView.collectionView.contentInset.bottom = messageCollectionViewBottomInset
            mainView.collectionView.scrollIndicatorInsets.bottom = messageCollectionViewBottomInset
        }
    }
    var isLastCellVisible: Bool {
        
        if self.messages.isEmpty {
            return true
        }
        
        let lastIndexPath = IndexPath(item: 0, section: self.messages.count - 1)
        guard let layout = self.mainView.collectionView.layoutAttributesForItem(at: lastIndexPath) else { return true }
        let cellFrame = layout.frame
                
        let cellRect = self.mainView.collectionView.convert(cellFrame, to: self.mainView.collectionView.superview)
                
        var visibleRect = CGRect(x: (self.mainView.collectionView.bounds.origin.x),
                                 y: (self.mainView.collectionView.bounds.origin.y),
                                 width: (self.mainView.collectionView.bounds.size.width),
                                 height: (self.mainView.collectionView.bounds.size.height) - (self.mainView.collectionView.contentInset.bottom)
        )
        
        visibleRect = (self.mainView.collectionView.convert(visibleRect, to: self.mainView.collectionView.superview))
        
        if visibleRect.intersects(cellRect) {
            return true
        }
        
        return false
    }
  
    let audioSessionController = AudioSessionController()
    lazy var player = AVPlayerWrapper()
    
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
        player.delegate = self
        audioSessionController.delegate = self
    }
    
    // MARK: - Lifecycle methods
    
    override func viewDidLoad() {
        super.viewDidLoad()
        
        self.title = mainView.localizationConfiguration.navigationBarText
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
        viewModel.onDisappear()
        player.stop()
        viewModel.closeChannel()

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
        _ = mainView.messageComposeView.composeTextView.resignFirstResponder()
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
    func didSelect(video: URL?) {
        if let video = video {
            let videoProcessor = VideoProcessor(video)
            videoProcessor.convertVideoToMP4(completion: { [weak self] url in
                
                guard let self = self else { return }
              
                if let url = url {
                    self.viewModel.sendMedia(.video(url))
                    
                } else {
                    debugPrint("Can not convert to mp4")
                }
            })
        }
    }
    
    func didSelect(image: UIImage?) {
        
        if let image = image {
            
            self.viewModel.sendMedia(.image(image))
        }
    }
}

extension StartViewController: ComposeViewDelegate {
    func scrollToBottomMessage() {
        mainView.collectionView.scrollToLastItem(at: .bottom, animated: true)
        
    }
    
    func showHoldToRecordAudioMessage() {
        DispatchQueue.main.async {
            let alert = UIAlertController(title: "",
                                          message: self.mainView.localizationConfiguration.alertTitleHoldToRecord,
                                          preferredStyle: .alert)
            let okButton = UIAlertAction(title: self.mainView.localizationConfiguration.locationAlertButtonTitleOk, style: .default) { _ in

            }

            alert.addAction(okButton)

            self.present(alert, animated: true, completion: nil)
        }
    }
    
    func disabledMicrophoneAccess() {
        DispatchQueue.main.async {
            let alert = UIAlertController(title: self.mainView.localizationConfiguration.alertTitleError,
                                          message: self.mainView.localizationConfiguration.microphoneAlertMessage,
                                          preferredStyle: .alert)
            let okButton = UIAlertAction(title: self.mainView.localizationConfiguration.locationAlertButtonTitleOk, style: .default) { _ in

            }
            let settingsButton = UIAlertAction(title: self.mainView.localizationConfiguration.microphoneAlertButtonTitleSettings, style: .default) { _ in
                if let url = URL(string: UIApplication.openSettingsURLString) {
                    if UIApplication.shared.canOpenURL(url) {
                        UIApplication.shared.open(url, options: [:], completionHandler: nil)
                    }
                }
            }

            alert.addAction(okButton)
            alert.addAction(settingsButton)

            self.present(alert, animated: true, completion: nil)
        }
    }
    
    func sendVoiceMessage(url: URL) {
        viewModel.sendMedia(.voice(url))
    }
    
    func startPlayingRecordedMessage(url: URL) {
        try? audioSessionController.set(category: .playback)

        if !audioSessionController.audioSessionIsActive {
            try? audioSessionController.activateSession()
        }
        
        if let playingItem = playingItem {

            switch playingItem {
            case .localMedia( _):
                player.togglePlaying()
                
            case .mediaMessage( _):
                stopAudioPlayer()
                self.playingItem = .localMedia(url: url)
                player.load(from: url, playWhenReady: true, options: nil)
            }
        } else {
            
            self.playingItem = .localMedia(url: url)
            player.load(from: url, playWhenReady: true, options: nil)
            
        }
    }
    
    func chooseAction() {
        
        let alert = UIAlertController(title: nil, message: nil, preferredStyle: .actionSheet)

        if !SinchChatSDK.shared.disabledFeatures.contains(.sendLocationSharingMessage) {
            
            let action  = UIAlertAction(title: mainView.localizationConfiguration.menuShareLocation, style: .default, handler: { _ in
                self.cordinator?.presentLocation(viewController: self,
                                                 uiConfig: self.mainView.uiConfig,
                                                 localizationConfig: self.mainView.localizationConfiguration)
            })
            
            action.setupActionWithImage(mainView.uiConfig.shareLocationMenuImage,
                                        textColor:  mainView.uiConfig.menuButtonTextColor)
            
            alert.addAction(action)
        }
        
        alert.addAction(UIAlertAction(title: mainView.localizationConfiguration.menuCancel, style: .cancel, handler: { _ in
            debugPrint("User click cancel button")
        }))
        
        self.present(alert, animated: true, completion: nil)
        
    }
    
    func choosePhoto() {
        
        showChoiceBetweenGalleryAndCamera()
        resignFirstResponderView()
    }
    
    func sendMessage(text: String) {
        
        viewModel.sendMessage(.text(text))
    }
    
    func sendChoiceResponseMessage(postbackData: String, entryID: String) {
        
        viewModel.sendMessage(.choiceResponseMessage(postbackData: postbackData, entryID: entryID))
    }
    
    func stopAudioPlayerIfPlaying(isRecording: Bool) {
        
        if let playingItem = playingItem {
            switch playingItem {
            case .localMedia(url: _):
                player.stop()
                self.playingItem = nil
                
                // todo when adding recording
            case .mediaMessage(message: _):
                
                if isRecording {
                    player.stop()
                    updateAcivePlayerView()
                    self.playingItem = nil

                } else {
                    updateAcivePlayerView()

                }
            }
        }
    }
    
    private func showChoiceBetweenGalleryAndCamera() {

        let alert = UIAlertController(title: nil, message: nil, preferredStyle: .actionSheet)
        
        if !SinchChatSDK.shared.disabledFeatures.contains(.sendImageFromCamera) {
            
            let cameraAction  = UIAlertAction(title: mainView.localizationConfiguration.menuCamera, style: .default, handler: { _ in
                
                self.imagePickerHelper.takePhoto { success in
                    if !success {
                        DispatchQueue.main.async {
                            let alert = UIAlertController(title: self.mainView.localizationConfiguration.alertTitleError,
                                                          message:self.mainView.localizationConfiguration.alertTitleErrorCameraDisabled,
                                                          preferredStyle: .alert)
                            let settingsAction = UIAlertAction(title: self.mainView.localizationConfiguration.locationAlertButtonTitleSettings, style: .default) { _ in
                                if let url = URL(string: UIApplication.openSettingsURLString) {
                                    if UIApplication.shared.canOpenURL(url) {
                                        UIApplication.shared.open(url, options: [:], completionHandler: nil)
                                    }
                                }
                            }
                            alert.addAction(settingsAction)
                            alert.addAction(UIAlertAction(title: self.mainView.localizationConfiguration.alertButtonTitleOk,
                                                          style: .default,
                                                          handler: nil))
                            
                            self.present(alert, animated: true, completion: nil)
                        }
                    }
                }
                
            })
            
            cameraAction.setupActionWithImage(mainView.uiConfig.cameraMenuImage,
                                              textColor: mainView.uiConfig.menuButtonTextColor)
            
            alert.addAction(cameraAction)
        }
        
        if !SinchChatSDK.shared.disabledFeatures.contains(.sendImageFromCamera) {
            
            let cameraAction  = UIAlertAction(title: mainView.localizationConfiguration.menuImageGallery, style: .default, handler: { _ in
                self.imagePickerHelper.pickPhotoFromGallery()
            })
            
            cameraAction.setupActionWithImage(mainView.uiConfig.galleryMenuImage,
                                              textColor: mainView.uiConfig.menuButtonTextColor)
            
            alert.addAction(cameraAction)
        }
        
        alert.addAction(UIAlertAction(title: mainView.localizationConfiguration.menuCancel, style: .cancel, handler: { _ in
            debugPrint("User click cancel button")
        }))
        
        self.present(alert, animated: true, completion: nil)
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
            let alert = UIAlertController(title: self.mainView.localizationConfiguration.alertTitleError,
                                          message: self.mainView.localizationConfiguration.alertMessageNotSent,
                                          preferredStyle: .alert)
            alert.addAction(UIAlertAction(title: self.mainView.localizationConfiguration.alertButtonTitleOk,
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
                let alert = UIAlertController(title: self.mainView.localizationConfiguration.alertTitleError,
                                              message: self.mainView.localizationConfiguration.alertMessageCouldNotLoadHistory,
                                              preferredStyle: .alert)
                alert.addAction(UIAlertAction(title: self.mainView.localizationConfiguration.alertButtonTitleOk,
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
            self.mainView.messageComposeView.scrollToBottomButton.isHidden = true

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
            guard let self = self else { return }
            self.insertMessages(messages)

        }
    }
    func insertMessages(_ newMessages: [Message]) {

        self.mainView.collectionView.performBatchUpdates({
            debugPrint(messages.count)
            if newMessages.count == 1 {
                self.messages.append(newMessages[0])
                self.mainView.collectionView.insertSections([ self.messages.count - 1])
            } else if newMessages.count == 2 {
                self.messages.append(contentsOf: newMessages)
                self.mainView.collectionView.insertSections([self.messages.count - 2, self.messages.count - 1])
                
            }
        }, completion: { [weak self] _ in
            guard let self = self else { return }
          
            if self.isScrolledToBottom && !(self.mainView.collectionView.isDragging || self.mainView.collectionView.isDecelerating) {
                   self.mainView.collectionView.scrollToLastItem(animated: true)
            } else {
                self.handleBottomButtonVisibility()
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
        
        if message.body is MessageText {
            let cell = collectionView.dequeueReusableCell(withReuseIdentifier:  TextMessageCell.cellId, for: indexPath) as! TextMessageCell
            cell.configure(with: message, at: indexPath, and: mainView.collectionView)
            return cell
            
        } else if let messageBody = message.body as? MessageMedia {
            
            switch messageBody.type {
            case .video:
                let cell = collectionView.dequeueReusableCell(withReuseIdentifier:  VideoMessageCell.cellId, for: indexPath) as! VideoMessageCell
                cell.configure(with: message, at: indexPath, and: mainView.collectionView)
                return cell
            case .audio:
                let cell = collectionView.dequeueReusableCell(withReuseIdentifier:  VoiceMessageCell.cellId, for: indexPath) as! VoiceMessageCell
                cell.configure(with: message, at: indexPath, and: mainView.collectionView, player: player, playingItem: playingItem)
                cell.audioDelegate = self
                return cell
            default:
                let cell = collectionView.dequeueReusableCell(withReuseIdentifier:  ImageMessageCell.cellId, for: indexPath) as! ImageMessageCell
                cell.configure(with: message, at: indexPath, and: mainView.collectionView)
                return cell
            }
        } else if message.body is MessageEvent {
            
            let cell = collectionView.dequeueReusableCell(withReuseIdentifier:  EventMessageCell.cellId, for: indexPath) as! EventMessageCell
            cell.configure(with: message, at: indexPath, and: mainView.collectionView)
            return cell
        } else if message.body is MessageDate {
            
            let cell = collectionView.dequeueReusableCell(withReuseIdentifier:  DateMessageCell.dateCellId, for: indexPath) as! DateMessageCell
            cell.configure(with: message, at: indexPath, and: mainView.collectionView)
            return cell
            
        } else if message.body is MessageMediaText {
            
            let cell = collectionView.dequeueReusableCell(withReuseIdentifier:  MediaTextMessageCell.cellId, for: indexPath) as! MediaTextMessageCell
            cell.configure(with: message, at: indexPath, and: mainView.collectionView)
            return cell
        } else if message.body is MessageLocation {
            
            let cell = collectionView.dequeueReusableCell(withReuseIdentifier:  LocationMessageCell.cellId, for: indexPath) as! LocationMessageCell
            cell.configure(with: message, at: indexPath, and: mainView.collectionView)
            return cell
        } else if message.body is MessageChoices {
            
            let cell = collectionView.dequeueReusableCell(withReuseIdentifier:  ChoicesMessageCell.cellId, for: indexPath) as! ChoicesMessageCell
            cell.configure(with: message, at: indexPath, and: mainView.collectionView)
            return cell
        } else if message.body is MessageCard {
            
            let cell = collectionView.dequeueReusableCell(withReuseIdentifier:  CardMessageCell.cellId, for: indexPath) as! CardMessageCell
            cell.configure(with: message, at: indexPath, and: mainView.collectionView)
            return cell
        } else if message.body is MessageCarousel {
            
            let cell = collectionView.dequeueReusableCell(withReuseIdentifier:  CarouselMessageCell.cellId, for: indexPath) as! CarouselMessageCell
            cell.configure(with: message, at: indexPath, and: mainView.collectionView)
            return cell
        } else if message.body is MessageUnsupported {
            
            let cell = collectionView.dequeueReusableCell(withReuseIdentifier:  UnsupportedMessageCell.cellId, for: indexPath) as! UnsupportedMessageCell
            cell.configure(with: message, at: indexPath, and: mainView.collectionView)
            return cell
                        
        } else {
            return MessageCollectionViewCell()
        }
    }
    open func collectionView(_ collectionView: UICollectionView, layout collectionViewLayout: UICollectionViewLayout, sizeForItemAt indexPath: IndexPath) -> CGSize {
        guard let chatFlowLayout = collectionViewLayout as? ChatFlowLayout else { return .zero }
        return chatFlowLayout.sizeForItem(at: indexPath)
    }
    
    func collectionView(_ collectionView: UICollectionView, didSelectItemAt indexPath: IndexPath) {
    }
    
    @available(iOS 13.0, *)
    func collectionView(_ collectionView: UICollectionView, contextMenuConfigurationForItemAt indexPath: IndexPath, point: CGPoint) -> UIContextMenuConfiguration? {
        
        let message = self.messages[indexPath.section]
        if message.body is MessageText || message.body is MessageMediaText ||
            message.body is MessageLocation || message.body is MessageChoices
            || message.body is MessageCard {
            
            return configureContextMenu(index: indexPath.section)
        } else {
            return nil
        }
    }
    
    private func populatePasteBoard(_ index: Int) {
        let pasteBoard = UIPasteboard.general
        let message = messages[index]
        if let message = message.body as? MessageText {
            pasteBoard.string = message.text
        } else if let message = message.body as? MessageMediaText {
            pasteBoard.string = message.text
            
        } else if let message = message.body as? MessageLocation {
            pasteBoard.string = message.title
            
        } else if let message = message.body as? MessageChoices {
            pasteBoard.string = message.text
            
        } else if let message = message.body as? MessageCard {
            pasteBoard.string = message.description
            
        }
    }
    
    @available(iOS 13.0, *)
    func configureContextMenu(index: Int) -> UIContextMenuConfiguration {
        
        let context = UIContextMenuConfiguration(identifier: nil, previewProvider: nil) {  [weak self] _ in
            
            let copy = UIAction(title: NSLocalizedString(self?.mainView.localizationConfiguration.menuButtonTitleCopy ?? "",
                                                         bundle: Bundle.staticBundle, comment: ""),
                                image: nil, identifier: nil,
                                discoverabilityTitle: nil, state: .off) { [weak self] _ in
                guard let self = self else {
                    return
                }
                self.populatePasteBoard(index)
            }
            
            return UIMenu(title: self?.mainView.localizationConfiguration.menuTitleOptions ?? "",
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
        
        populatePasteBoard(indexPath.section)
    }
    
    func handleBottomButtonVisibility() {

        if !isLastCellVisible {
            if self.mainView.messageComposeView.scrollToBottomButton.isHidden && !isScrolledToBottom {
                DispatchQueue.main.async {
                    self.mainView.messageComposeView.scrollToBottomButton.isHidden = false
                    UIView.animate(withDuration: 0.5, animations: {
                        self.mainView.messageComposeView.scrollToBottomButton.alpha = 1.0
                    })
                }
            }
        } else {
            DispatchQueue.main.async {
                UIView.animate(withDuration: 0.5, animations: {
                    self.mainView.messageComposeView.scrollToBottomButton.alpha = 0.0
                }, completion: {_ in
                    self.mainView.messageComposeView.scrollToBottomButton.isHidden = true
                })
            }
        }
    }
    
    func collectionView(_ collectionView: UICollectionView, willDisplay cell: UICollectionViewCell, forItemAt indexPath: IndexPath) {
        handleBottomButtonVisibility()
    }

    func handleIsScrolledToBottom(_ scrollView: UIScrollView) {
        let height = scrollView.frame.size.height
        let contentYOffset = scrollView.contentOffset.y
        let distanceFromBottom = scrollView.contentSize.height - contentYOffset
        
         isScrolledToBottom = distanceFromBottom < height
    }
    
    func scrollViewDidEndScrollingAnimation(_ scrollView: UIScrollView) {
        handleBottomButtonVisibility()
        handleIsScrolledToBottom(scrollView)
    }
    func scrollViewDidScroll(_ scrollView: UIScrollView) {
        handleBottomButtonVisibility()
        handleIsScrolledToBottom(scrollView)

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
    func didTapMedia(with url:URL) {

        cordinator?.presentMediaViewerController(viewController: self,
                                                 uiConfig: mainView.uiConfig,
                                                 localizationConfig: mainView.localizationConfiguration,
                                                 url: url)
        
    }
    func didTapOnVideo(with url: URL, message: Message) {
        
        if let playingItem = playingItem {
            
            switch playingItem {
            case .localMedia(_):
                player.stop()
                mainView.messageComposeView.updateAudioComposeView(player: player)

            case .mediaMessage(_):

                stopAudioPlayer()
            }
            self.playingItem = nil
        }
        
        let player = AVPlayer(url: url)
        let playerVC = AVPlayerViewController()
        playerVC.player = player

        present(playerVC, animated: true) {
            playerVC.player?.play()
        }
    }
    
    func didTapOutsideOfContent(in cell: MessageCollectionViewCell) {
        resignFirstResponderView()
    }
    
    func didTapOutsideOfContent() {
        resignFirstResponderView()
        
    }
    func didTapOnChoice(_ choice: ChoiceMessageType, in cell: MessageCollectionViewCell) {
        
        switch choice {
        case .textMessage(let message):
            sendChoiceResponseMessage(postbackData: message.postback, entryID: message.entryID)
            
        case .urlMessage(let message):
            if let url = URL(string: message.url) {
                didSelectURL(url)
            }
            
        case .callMessage(let message):
            ChoicesHelper.callNumber(phoneNumber: message.phoneNumber)
        case .locationMessage(let message):
            let locationActionHandler = LocationActionHandler(mainView.localizationConfiguration)
            DispatchQueue.main.async {
                locationActionHandler.handleOpenLocationAction(self, title: message.text, latitude: message.latitude, longitude: message.longitude)
            }
        }
    }
}
extension StartViewController: LocationDelegate {
    func didShareLocation(latitude: Float, longitude: Float) {
        
        viewModel.sendMessage(.location(latitude: latitude,
                                        longitude: longitude,
                                        localizationConfig: mainView.localizationConfiguration))
    }
}

extension StartViewController: AudioDelegate {
    
    private func stopAudioPlayer() {
        player.stop()
    }
    
    func stopPlaying(model: Message) {
        playingItem = nil
        stopAudioPlayer()
    }
    
    private func playMessageFrom(_ model: Message) {
        try? audioSessionController.set(category: .playback)

        if !audioSessionController.audioSessionIsActive {
            try? audioSessionController.activateSession()
        }
        guard let mediaMessage = model.body as? MessageMedia,
              let url = URL(string: mediaMessage.url) else { return }
        
        self.playingItem = .mediaMessage(message: model)
        player.load(from: url, playWhenReady: true, options: nil)
    }
    
    func startPlaying(model: Message) {

        if let playingItem = playingItem {
            
            switch playingItem {
            case .localMedia(_):
                player.stop()
                mainView.messageComposeView.updateAudioComposeView(player: player)
                playMessageFrom(model)

            case .mediaMessage(let message):
                if message.entryId == model.entryId {
                    player.togglePlaying()

                } else {
                    stopAudioPlayer()
                    playMessageFrom(model)
                }
            }
                        
        } else {
                playMessageFrom(model)
        }
    }
}
extension StartViewController: AudioSessionControllerDelegate {
    func handleInterruption(type: InterruptionType) {
        switch type {
        case .began:
            print("began")
            stopAudioPlayer()
            updateAcivePlayerView()
            playingItem = nil
        case .ended( _):
            
            do {
                
            } catch let error as NSError {
                print(error.localizedDescription)
            }
        }
    }
}
extension StartViewController: AVPlayerWrapperDelegate {
    
    func AVWrapper(didChangeState state: AVPlayerWrapperState) {
        debugPrint("state \(state.rawValue)")
        updateAcivePlayerView()
        
        if state == .paused && player.currentTime == player.duration {
            playingItem = nil
        }
    }
    
    func AVWrapper(secondsElapsed seconds: Double) {
        updateAcivePlayerView()
        
    }
    
    func AVWrapper(failedWithError error: Error?) {
        updateAcivePlayerView()
        
    }
    
    func AVWrapper(seekTo seconds: Int, didFinish: Bool) {
        
    }
    
    func AVWrapper(didUpdateDuration duration: Double) {
        updateAcivePlayerView()
        
    }
    
    func AVWrapper(didReceiveMetadata metadata: [AVTimedMetadataGroup]) {
        
    }
    
    func AVWrapperItemDidPlayToEndTime() {
        debugPrint("end playing")

        updateAcivePlayerView()
        
    }
    
    func AVWrapperDidRecreateAVPlayer() {
        debugPrint("DidRecreateAVPlayer")
        try? audioSessionController.set(category: .playback)

    }
    
    func updateAcivePlayerView() {
        
        if let playingItem = playingItem {
            switch playingItem {
            case .localMedia(url: _):
                mainView.messageComposeView.updateAudioComposeView(player: player)

            case .mediaMessage(message: let message):
                if let section = getPlayingSection(mediaMessage: message) {
                    let indexSet = IndexSet(integer: section)
                    UIView.performWithoutAnimation {
                        mainView.collectionView.reloadSections(indexSet)
                    }
                }
            }
        }
    }
        
    private func getPlayingSection(mediaMessage: Message) -> Int? {
        
        for (index, message) in self.messages.enumerated() where message.body is MessageMedia && message.entryId == mediaMessage.entryId {
            return index
        }
        
        return nil
    }
}
