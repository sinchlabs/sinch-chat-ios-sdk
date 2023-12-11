// swiftlint:disable file_length type_body_length
import Foundation
import UIKit

protocol StartViewModel: MessageDataSourceDelegate {
    var delegate: StartViewModelDelegate? { get }
    var isStartedFromInbox: Bool { get set }
    
    func setInternetConnectionState(_ state: InternetConnectionState)
    func sendMedia(_ media: MediaType, completion: @escaping (Result<Message, Error>) -> Void)
    func sendMessage(_ message: MessageType, completion: @escaping (Result<Message?, Error>) -> Void)
    func loadHistory()
    func onLoad()
    func onDisappear()
    func onWillEnterForeground()
    func onDidEnterBackground()
    func onInternetLost()
    func onInternetOn()
    func closeChannel()
    func processNewMessages(_ message: Message) -> [Message]
    func sendEvent(_ event: EventType )
    func getChatOptions() -> SinchChatOptions
    
}

protocol StartViewModelDelegate: AnyObject {
    func didReceiveMessages(_ message: [Message])
    func didReceiveHistoryFirstMessages(_ messages: [Message])
    func didReceiveHistoryMessages(_ messages: [Message])
    func errorLoadingMoreHistory(error: MessageDataSourceError)
    func errorSendingMessage(error: MessageDataSourceError)
    func didChangeInternetState(_ state: InternetConnectionState)
    func setVisibleRefreshActivityIndicator(_ isVisible: Bool)
    func setVisibleTypingIndicator(_ isVisible: Bool, animated: Bool)
    
}

final class DefaultStartViewModel: StartViewModel {
    
    private var dataSource: InboxMessageDataSource
    private let notificationPermission: PushNofiticationPermissionHandler
    
    weak var delegate: StartViewModelDelegate?
    var messagesArrays: [[Message]] = []
    var isMessageSent = false
    var isEventSent = false
    var isTypingIndicatorVisible = false
    var isStartedFromInbox = false
    
    var error: Error?
    var state: InternetConnectionState = .notDetermined {
        willSet {
            if state != newValue {
                
                delegate?.didChangeInternetState(newValue)
                
            }
        }
    }
    var timeOfLastReceivedMessage: Date?
    var timer: Timer?
    
    init(messageDataSource: InboxMessageDataSource, notificationPermission: PushNofiticationPermissionHandler, startedFromInbox: Bool = false) {
        dataSource = messageDataSource
        
        self.notificationPermission = notificationPermission
        self.isStartedFromInbox = startedFromInbox
        
    }
    
    deinit {
        timer?.invalidate()
        timer = nil
    }
    // MARK: - Private methods
    
    private func createArrayWithDateMessage(_ arraysOfMessages: [[Message]]) -> [Message] {
        var allMessagesArray : [Message] = []
        for array in arraysOfMessages {
            
            if let date = array.first?.body.sendDate {
                allMessagesArray.append(Message(entryId: "-1", owner: .system, body: MessageDate(sendDate: date)))
            }
            allMessagesArray.append(contentsOf: array)
        }
        return allMessagesArray
    }
    
    private func askForNotifications() {
        notificationPermission.checkIfPermissionIsGranted { [weak self] status in
            switch status {
            case .granted: break
            case .denied:
                self?.notificationPermission.askForPermissions(completion: nil)
            case .notDetermined:
                self?.notificationPermission.askForPermissions(completion: nil)
            }
        }
    }
    func closeChannel() {
        dataSource.closeChannel()
    }
    
    private func setIdleState() {
        dataSource.cancelSubscription()
        
        messagesArrays = []
        self.delegate?.didReceiveHistoryFirstMessages([])
        
        error = nil
        isMessageSent = false
        SinchChatSDK.shared._chat.state = .idle
    }
    
    private func setRunningState() {
        
        SinchChatSDK.shared._chat.state = .running
        loadHistory()
        subscribeForMessages()
        
    }
    
    // MARK: - Public methods
    
    func getChatOptions() -> SinchChatOptions {
        return .init(
            topicID: dataSource.topicModel?.topicID,
            metadata: dataSource.metadata,
            shouldInitializeConversation: dataSource.shouldInitializeConversation
        )
    }
    
    func setInternetConnectionState(_ state: InternetConnectionState) {
        self.state = state
    }
    
    func processHistoryMessages(_ messages: [Message], callback: @escaping ([Message]) -> Void) {
        
        Task(priority: .userInitiated) {
            
            var array: [[Message]] = []
            for notProcessedMessage in messages.reversed() {
                
                guard let message = await processPluginMessageAsync(notProcessedMessage) else {
                    continue
                }
                if let msgEvent = message.body as? MessageEvent,
                   msgEvent.text?.isEmpty ?? true {
                    continue
                }
                
                if messagesArrays.isEmpty {
                    messagesArrays.append([message])
                    array.append([message])
                } else {
                    
                    if let messageFromHistory = messagesArrays.first?.first,
                       let dateFromHistory = messageFromHistory.body.sendDate,
                       let date = message.body.sendDate {
                        
                        if dateFromHistory.isSameDay(date) {
                            messagesArrays[0].insert(message, at: 0)
                            if array.isEmpty {
                                array.append([message])
                            } else {
                                array[0].insert(message, at: 0)
                                
                            }
                            
                        } else {
                            messagesArrays.insert([message], at: 0)
                            
                            if array.isEmpty {
                                array.append([message])
                            } else {
                                array.insert([message], at: 0)
                                
                            }
                        }
                    } else {
                        messagesArrays.insert([message], at: 0)
                        
                        if array.isEmpty {
                            array.append([message])
                        } else {
                            array.insert([message], at: 0)
                            
                        }
                    }
                }
                
            }
            callback(createArrayWithDateMessage(array))
        }
        
    }
    
    func processNewMessages(_ message: Message) -> [Message] {
        
        if let msgEvent = message.body as? MessageEvent,
           msgEvent.text?.isEmpty ?? true {
            return []
        }
        
        let startCount = messagesArrays.count
        
        if messagesArrays.isEmpty {
            messagesArrays.append([message])
        } else {
            
            if let messageFromHistory = messagesArrays.last?.last,
               let dateFromHistory = messageFromHistory.body.sendDate,
               let date =  message.body.sendDate {
                
                if dateFromHistory.isSameDay(date) {
                    messagesArrays[messagesArrays.count - 1].append(message)
                    
                } else {
                    messagesArrays.append([message])
                }
            }
        }
        let endCount = messagesArrays.count
        
        if startCount == endCount {
            return [message]
        } else {
            return createArrayWithDateMessage([[message]])
        }
    }
    
    func onLoad() {
        
        dataSource.cancelCalls()
        setRunningState()
        
    }
    
    func onDisappear() {
        setIdleState()
    }
    
    func onInternetOn() {
        if !messagesArrays.isEmpty {
            messagesArrays = []
            self.delegate?.didReceiveHistoryFirstMessages([])
        }
        
        dataSource.cancelCalls()
        setRunningState()
        
    }
    func onInternetLost() {
        dataSource.cancelSubscription()
        error = nil
        isMessageSent = false
        SinchChatSDK.shared._chat.state = .idle
    }
    
    func onWillEnterForeground() {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5, execute: {
            self.dataSource.startChannel()
            self.setRunningState()
            
        })
    }
    
    func onDidEnterBackground() {
        setIdleState()
        dataSource.closeChannel()
        
    }
    
    func shouldHandleTypingIndicator() -> Bool {
        
        if let timeOfLastReceivedMessage = timeOfLastReceivedMessage {
            let delta = Double(Date() - timeOfLastReceivedMessage)
            if delta < 1 {
                return false
            }
        }
        return true
    }
    func subscribeForMessages() {
        dataSource.subscribeForMessages { [weak self] result in
            
            guard let self = self else {
                return
            }
            
            switch result {
            case .success(let message):
                self.processPluginMessage(message) { processedMessageByPlugins in
                    guard let processedMessageByPlugins = processedMessageByPlugins else {
                        return
                    }
                    
                    if let event = processedMessageByPlugins.body as? MessageEvent {
                        
                        switch event.type {
                        case .composeStarted:
                            if self.shouldHandleTypingIndicator() {
                                self.isTypingIndicatorVisible = true
                                self.delegate?.setVisibleTypingIndicator( self.isTypingIndicatorVisible, animated: true)
                                DispatchQueue.main.async {
                                    
                                    self.timer?.invalidate()
                                    self.timer = Timer.scheduledTimer(withTimeInterval: 30.0, repeats: false) { [weak self] _ in
                                        
                                        guard let self = self else { return }
                                        self.isTypingIndicatorVisible = false
                                        self.delegate?.setVisibleTypingIndicator(self.isTypingIndicatorVisible, animated: true)
                                        
                                    }
                                }
                            }
                            return
                        case .composeEnd :
                            self.timer?.invalidate()
                            self.isTypingIndicatorVisible = false
                            self.delegate?.setVisibleTypingIndicator(self.isTypingIndicatorVisible, animated: true)
                            
                            return
                        default:
                            break
                        }
                    }
                    let messages = self.processNewMessages(processedMessageByPlugins)
                    if !messages.isEmpty {
                        self.timeOfLastReceivedMessage = Date()
                        self.delegate?.didReceiveMessages(messages)
                    }
                }
                
            case .failure(let error):
                Logger.verbose(error)
                self.error = error
            }
        }
    }
    
    func loadHistory() {
        error = nil
        
        dataSource.getMessageHistory { [weak self] messages in
            
            guard let self = self else {
                return
            }
            switch messages {
                
            case .success(let messages):
                self.processHistoryMessages(messages) { [weak self] processedMessages in
                    guard let self = self else {
                        return
                    }
                    
                    if self.dataSource.isFirstPage() {
                        self.delegate?.didReceiveHistoryFirstMessages(processedMessages)
                        
                    } else {
                        
                        self.delegate?.didReceiveHistoryMessages(processedMessages)
                    }
                }
            case .failure(let error):
                Logger.verbose(error)
                self.error = error
                self.delegate?.errorLoadingMoreHistory(error: error)
                
            }
        }
    }
    
    func sendMessage(_ message: MessageType, completion: @escaping (Result<Message?, Error>) -> Void) {
        
        isMessageSent = false
        
        if state == .isOff {
            self.delegate?.errorSendingMessage(error: .noInternetConnection)
            return
        }
        askForNotifications()
        error = nil
        
        processMessageBeforeSending(messagePayload: message) { [weak self] messageToSend in
            guard let self = self, let messageToSend = messageToSend else {
                completion(.success(nil))
                return
            }
            dataSource.sendMessage(messageToSend) { [weak self] result in
                guard let self = self else {
                    return
                }
                
                switch result {
                    
                case .success(let entryId):
                    self.isMessageSent = true
                    completion(.success(self.createMessage(entryId: entryId, messageType: messageToSend)))
                case .failure(let error):
                    Logger.verbose(error)
                    self.error = error
                    completion(.failure(error))
                }
            }
        }
    }
    
    private func processMessageBeforeSending(messagePayload: MessageType, callback: @escaping (MessageType?) -> Void) {
        guard let message = self.createMessage(entryId: UUID().uuidString, messageType: messagePayload) else {
            callback(nil)
            return
        }
        
        processPluginMessage(message) { processedMessage in
            guard let processedMessage = processedMessage else {
                callback(nil)
                return
            }
            
            if let textMessage = processedMessage.body as? MessageText {
                callback(.text(textMessage.text))
                return
            }
            
            callback(messagePayload)
        }
    }
    
    func createMessage(entryId: String, messageType: MessageType) -> Message? {
        
        var messageBody: MessageBody
        let date = Int64(Date().timeIntervalSince1970)
        switch messageType {
        case .text(let text):
            messageBody = MessageText(text: text, sendDate: date)
            
        case .choiceResponseMessage(postbackData: _, entryID: _):
            return nil
            
        case .media(let message):
            
            if let messageContent = message.body as? MessageMedia {
                messageBody = messageContent
                
            } else {
                messageBody = MessageMedia(url: "", sendDate: date)
                
            }
            
        case let .location(latitude, longitude, localizationConfig):
            messageBody = MessageLocation(label: localizationConfig.outgoingLocationMessageButtonTitle,
                                          title: localizationConfig.outgoingLocationMessageTitle,
                                          latitude: Double(latitude),
                                          longitude: Double(longitude), sendDate: date)
            
        case .fallbackMessage:
            return nil
            
        case .genericEvent:
            return nil
        }
        
        return Message(entryId: entryId, owner: .outgoing, body: messageBody, status: .sending)
    }
    
    func sendEvent(_ event: EventType ) {
        
        isEventSent = false
        
        if state == .isOff {
            self.delegate?.errorSendingMessage(error: .noInternetConnection)
            return
        }
        
        dataSource.sendEvent(event) { [weak self] result in
            
            guard let self = self else {
                return
            }
            
            switch result {
                
            case .success():
                self.isEventSent = true
                
            case .failure(let error):
                self.isEventSent = false
                Logger.verbose(error)
                
            }
        }
    }
    func sendMedia(_ media: MediaType, completion: @escaping (Result<Message, Error>) -> Void) {
        
        if state == .isOff {
            self.delegate?.errorSendingMessage(error: .noInternetConnection)
            return
        }
        error = nil
        
        dataSource.uploadMedia(media) { [weak self] result in
            
            guard let self = self else {
                return
            }
            switch result {
                
            case .success(let urlString):
                
                completion(.success(self.createMediaMessage(urlString: urlString, mediaType: media)))
                
            case .failure(let error):
                Logger.verbose(error)
                self.error = error
                completion(.failure(error))
                
            }
        }
    }
    
    func createMediaMessage(urlString: String, mediaType: MediaType) -> Message {
        
        var messageBody: MessageBody
        
        switch mediaType {
        case .audio(_):
            messageBody = MessageMedia(url: urlString, sendDate: Int64(Date().timeIntervalSince1970),
                                       placeholderImage: nil, type: .audio)
        case .image(_):
            messageBody = MessageMedia(url: urlString, sendDate: Int64(Date().timeIntervalSince1970),
                                       placeholderImage: nil, type: .image)
        case .video(_):
            messageBody = MessageMedia(url: urlString, sendDate: Int64(Date().timeIntervalSince1970),
                                       placeholderImage: nil, type: .video)
            
        case .file(_, let type):
            
            if type == .gif {
                messageBody = MessageMedia(url: urlString, sendDate: Int64(Date().timeIntervalSince1970),
                                           placeholderImage: nil, type: .image)
            } else {
                messageBody = MessageMedia(url: urlString, sendDate: Int64(Date().timeIntervalSince1970),
                                           placeholderImage: nil, type: .file(type))
            }
        }
        return Message(entryId: "-1", owner: .outgoing, body: messageBody, status: .sending)
    }
    
    private func processPluginMessage(_ message: Message, callback: @escaping (Message?) -> Void) {
        Task(priority: .utility) {
            var processedMessage: Message? = message
            SinchChatSDK.shared.customMessageTypeHandlers.forEach { handler in
                if let msg = processedMessage {
                    processedMessage = handler(msg)
                }
            }
            
            if processedMessage == nil {
                callback(processedMessage)
                return
            }
            
            for handler in SinchChatSDK.shared.customMessageTypeHandlersAsync {
                if let msg = processedMessage {
                    processedMessage = await convertCallBackWithMessageToAsync(message: msg, callback: handler)
                }
            }
            
            callback(processedMessage)
        }
    }
    
    private func processPluginMessageAsync(_ message: Message) async -> Message? {
        await withCheckedContinuation { continuation in
            processPluginMessage(message) { processed in
                continuation.resume(returning: processed)
            }
        }
    }
    
    private func convertCallBackWithMessageToAsync(message: Message, callback: (Message, @escaping (Message?) -> Void) -> Void) async -> Message? {
        await withCheckedContinuation { continuation in
            callback(message) { processedMessage in
                continuation.resume(returning: processedMessage)
            }
        }
    }
}

extension DefaultStartViewModel: MessageDataSourceDelegate {
    
    func subscriptionError() {
        
        subscribeForMessages()
    }
}
// swiftlint:enable file_length type_body_length
