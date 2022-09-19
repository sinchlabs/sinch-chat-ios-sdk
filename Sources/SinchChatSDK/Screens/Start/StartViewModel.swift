import Foundation
import UIKit

protocol StartViewModel: MessageDataSourceDelegate {
    var delegate: StartViewModelDelegate? { get }

    func setInternetConnectionState(_ state: InternetConnectionState)
    func sendMedia(_ media: MediaType)
    func sendMessage(_ message: MessageType)
    func loadHistory()
    func onLoad()
    func onDisappear()
    func onWillEnterForeground()
    func onDidEnterBackground()
    func onInternetLost()
    func onInternetOn()
    func closeChannel()
    
}

protocol StartViewModelDelegate: AnyObject {
    func didReceiveMessages(_ message: [Message])
    func didReceiveHistoryFirstMessages(_ messages: [Message])
    func didReceiveHistoryMessages(_ messages: [Message])
    func errorLoadingMoreHistory(error: MessageDataSourceError)
    func errorSendingMessage(error: MessageDataSourceError)
    func didChangeInternetState(_ state: InternetConnectionState)
    func setVisibleRefreshActivityIndicator(_ isVisible: Bool)

}

final class DefaultStartViewModel: StartViewModel {
      
    private var dataSource: MessageDataSource
    private let notificationPermission: PushNofiticationPermissionHandler
    
    weak var delegate: StartViewModelDelegate?
    var messagesArrays: [[Message]] = []
    var isMessageSent = false
    var error: Error?
    var state: InternetConnectionState = .notDetermined {
        willSet {
            if state != newValue {
                
                delegate?.didChangeInternetState(newValue)

            }
        }
    }

    init(messageDataSource: MessageDataSource, notificationPermission: PushNofiticationPermissionHandler) {
        dataSource = messageDataSource

        self.notificationPermission = notificationPermission
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

    func setInternetConnectionState(_ state: InternetConnectionState) {
        self.state = state
    }
    
    func processHistoryMessages(_ messages: [Message]) -> [Message] {
        
        var array: [[Message]] = []
        for message in messages.reversed() {
            
            if messagesArrays.isEmpty {
                messagesArrays.append([message])
                array.append([message])
            } else {
                
                if let messageFromHistory = messagesArrays.first?.first,
                   let dateFromHistory = messageFromHistory.body.sendDate,
                   let date =  message.body.sendDate {
                    
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
                }
            }
        }
        
        return createArrayWithDateMessage(array)
    }

    func processNewMessages(_ message: Message) -> [Message] {
        
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
    
            self.setRunningState()

        })
    }
                                      
    func onDidEnterBackground() {
        
        setIdleState()

    }
    func subscribeForMessages() {
        dataSource.subscribeForMessages { [weak self] result in
            
            guard let self = self else {
                return
            }
            
            switch result {
            case .success(let message):
                let messages = self.processNewMessages(message)
                self.delegate?.didReceiveMessages(messages)
            case .failure(let error):
                Logger.verbose(error)
                self.error = error
            }
        }
    }
    
    func loadHistory() {
        
        dataSource.getMessageHistory { [weak self] messages in
            
            guard let self = self else {
                return
            }
            switch messages {
                
            case .success(let messages):
                let processedMessages = self.processHistoryMessages(messages)

                if self.dataSource.isFirstPage() {
                    self.delegate?.didReceiveHistoryFirstMessages(processedMessages)
                    
                } else {
                    
                    self.delegate?.didReceiveHistoryMessages(processedMessages)
                }
            case .failure(let error):
                Logger.verbose(error)
                self.delegate?.errorLoadingMoreHistory(error: error)
                
            }
        }
    }
    
    func sendMessage(_ message: MessageType) {
      
        if state == .isOff {
            self.delegate?.errorSendingMessage(error: .noInternetConnection)
            return
        }
        
        askForNotifications()
        isMessageSent = false
        error = nil
        
        dataSource.sendMessage(message) { [weak self] result in
            
            guard let self = self else {
                return
            }
            
            switch result {
                
            case .success():
                self.isMessageSent = true

            case .failure(let error):
                Logger.verbose(error)
                
                self.error = error
                self.delegate?.errorSendingMessage(error: error)
            }
        }
    }
    
    func sendMedia(_ media: MediaType) {
        
        if state == .isOff {
            self.delegate?.errorSendingMessage(error: .noInternetConnection)
            return
        }
        
        dataSource.uploadMedia(media) { [weak self] result in
            
            guard let self = self else {
                return
            }
            switch result {
                
            case .success(let urlString):
                
                switch media {
                case .image(_):
                    self.sendMessage(.image(urlString))
                case .voice(_):
                    self.sendMessage(.voice(urlString))

                }
                
            case .failure(let error):
                Logger.verbose(error)
                self.error = error
                self.delegate?.errorSendingMessage(error: error)
                
            }
        }
    }
}
extension DefaultStartViewModel: MessageDataSourceDelegate {
    
    func subscriptionError() {
        
        subscribeForMessages()
    }
}
