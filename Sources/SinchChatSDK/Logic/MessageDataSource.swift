import Foundation
import GRPC

protocol MessageDataSourceDelegate: AnyObject {
    
    func subscriptionError()
}

enum MessageDataSourceError: Error {
    case unknown(Error)
    case notLoggedIn
    case unknownTypeOfMessage
    case messageIDIsEmpty
    case subscriptionIsAlreadyStarted
    case noMoreMessages
    case unknownTypeOfMedia
    case noInternetConnection

}
protocol MessageDataSource {
    
    var delegate: MessageDataSourceDelegate? { get set }
    
    func uploadMedia(_ media: MediaType, completion: @escaping (Result<String, MessageDataSourceError>) -> Void)
    func uploadMediaViaStream(_ media: MediaType, completion: @escaping (Result<String, MessageDataSourceError>) -> Void)
    func sendMessage(_ message: MessageType, completion: @escaping (Result<Void, MessageDataSourceError>) -> Void)
    func subscribeForMessages(completion: @escaping (Result<Message, MessageDataSourceError>) -> Void)
    func getMessageHistory(completion: @escaping (Result<[Message], MessageDataSourceError>) -> Void)
    func cancelSubscription()
    func cancelCalls()
    func isSubscribed() -> Bool
    func isFirstPage() -> Bool

}

final class DefaultMessageDataSource: MessageDataSource {
    
    var authDataSource: AuthDataSource
    var client: APIClient
    private var nextPageToken: String?
    private let pageSize: Int32 = 10
    private var subscription: ServerStreamingCall<Sinch_Chat_Sdk_V1alpha2_SubscribeToStreamRequest, Sinch_Chat_Sdk_V1alpha2_SubscribeToStreamResponse>?
    var historyCall: UnaryCall<Sinch_Chat_Sdk_V1alpha2_GetHistoryRequest, Sinch_Chat_Sdk_V1alpha2_GetHistoryResponse>?
    var sendMessageCall: UnaryCall<Sinch_Chat_Sdk_V1alpha2_SendRequest, Sinch_Chat_Sdk_V1alpha2_SendResponse>?
    var uploadStreamMediaCall: ClientStreamingCall<Sinch_Chat_Sdk_V1alpha2_UploadMediaRequest, Sinch_Chat_Sdk_V1alpha2_UploadMediaResponse>?
    var uploadMediaCall: ClientStreamingCall<Sinch_Chat_Sdk_V1alpha2_UploadMediaRequest, Sinch_Chat_Sdk_V1alpha2_UploadMediaResponse>?
    weak var delegate: MessageDataSourceDelegate?
    var firstPage: Bool = true
    
    init(apiClient: APIClient, authDataSource: AuthDataSource) {
        self.client = apiClient
        self.authDataSource = authDataSource
    }
  
    func getMessageHistory(completion: @escaping (Result<[Message], MessageDataSourceError>) -> Void) {
        if let nextPageToken = nextPageToken {
            if nextPageToken.isEmpty {
                
                completion(.failure(.noMoreMessages))
                return
            }
        }
        do {
            let service = try getService()
            
            var request = Sinch_Chat_Sdk_V1alpha2_GetHistoryRequest()
            request.pageSize = self.pageSize
            if let nextPageToken = nextPageToken {
                firstPage = false
                request.pageToken = nextPageToken
            }
            
            self.historyCall = service.getHistory(request, callOptions: nil)
            
            _ = self.historyCall?.response.always { [weak self] result in
                guard let self = self else {
                    return
                }
                debugPrint("@@@@@@@@@\(result)@@@@@@@@@")
                switch result {
                case .success(let result):
                    
                    self.nextPageToken = result.nextPageToken
                    completion(.success(result.entries.compactMap {
                        return self.handleIncomingMessage($0)
                    }))
                    
                case .failure(let err):
                    completion(.failure(.unknown(err)))
                }
            }
            
        } catch {
            completion(.failure(.notLoggedIn))
        }
    }
    
    func sendMessage(_ message: MessageType, completion: @escaping (Result<Void, MessageDataSourceError>) -> Void) {
        do {
            let service = try getService()
            
            guard let message = message.convertToSinchMessage else {
                completion(.failure(.unknownTypeOfMessage))
                return
            }
            
            sendMessageCall = service.send(message)
            
            _ = sendMessageCall?.response.always { result in
                
                switch result {
                case .success(_):
                    
                    completion(.success(()))
                    
                case .failure(let err):
                    completion(.failure(.unknown(err)))
                }
            }
            
        } catch {
            completion(.failure(.notLoggedIn))
        }
    }
    func uploadMediaViaStream(_ media: MediaType, completion: @escaping (Result<String, MessageDataSourceError>) -> Void) {
        do {
            
            guard let request = media.convertToSinchMedia else {
                completion(.failure(.unknownTypeOfMedia))
                return
            }
            
            let service = try getService()
            uploadStreamMediaCall = service.uploadMediaStream()
            
            uploadStreamMediaCall?.response.whenComplete({ result in
                
                switch result {
                case .success(let response):
                    completion(.success(response.url))
                    
                case .failure(let err):
                    completion(.failure(.unknown(err)))
                }
            })
            
            _ = uploadStreamMediaCall?.sendMessage(request)
            _ = uploadStreamMediaCall?.sendEnd()
            
        } catch {
            completion(.failure(.notLoggedIn))
        }
    }
    func uploadMedia(_ media: MediaType, completion: @escaping (Result<String, MessageDataSourceError>) -> Void) {
        do {
            
            guard let request = media.convertToSinchMedia else {
                completion(.failure(.unknownTypeOfMedia))
                return
            }
            
            let service = try getService()
            let call = service.uploadMedia(request)
            
            call.response.whenComplete({ result in
                
                switch result {
                case .success(let response):
                    completion(.success(response.url))
                    
                case .failure(let err):
                    completion(.failure(.unknown(err)))
                }
            })
            
        } catch {
            completion(.failure(.notLoggedIn))
        }
    }
    func subscribeForMessages(completion: @escaping (Result<Message, MessageDataSourceError>) -> Void) {
        guard subscription == nil else {
            completion(.failure(.subscriptionIsAlreadyStarted))
            return
        }
        do {
            let service = try getService()
            let request = Sinch_Chat_Sdk_V1alpha2_SubscribeToStreamRequest()
            
            let subscription = service.subscribeToStream(request, callOptions: nil) { [weak self] response in
                guard let self = self else {
                    return
                }
                if let message = self.handleIncomingMessage(response.entry) {
                    completion(.success(message))
                }
            }
            
            self.subscription = subscription
            
            self.subscription?.status.whenComplete({ [weak self] response in
                
                guard let self = self else {
                    return
                }
                debugPrint(response)
                switch response {
                    
                case .success(let status):
                    debugPrint(status)
                    if status.code == GRPCStatus.Code(rawValue: 14) {
                        self.subscription = nil
                        self.delegate?.subscriptionError()
                    }
                    
                case .failure(_):
                    break
                }
            })
        } catch {
            completion(.failure(.notLoggedIn))
        }
    }
    func cancelCalls() {
        historyCall?.cancel(promise: nil)
        sendMessageCall?.cancel(promise: nil)
        uploadStreamMediaCall?.cancel(promise: nil)
    }
    
    func cancelSubscription() {
        nextPageToken = nil
        subscription?.cancel(promise: nil)
        subscription = nil
        firstPage = true
        
    }
    func isSubscribed() -> Bool {
        (subscription != nil)
    }
    func isFirstPage() -> Bool {
        return firstPage
    }
    
    private func getService() throws -> Sinch_Chat_Sdk_V1alpha2_SdkServiceClient {
        try Sinch_Chat_Sdk_V1alpha2_SdkServiceClient(channel: client.getChannel(), defaultCallOptions: authDataSource.signRequest(.standardCallOptions))
    }
    
    private func handleIncomingMessage(_ entry: Sinch_Chat_Sdk_V1alpha2_Entry) -> Message? {
        
        if entry.hasDeliveryTime {
            
            // MARK: - Outgoing messages
            
            let outgoingText = entry.contactMessage.textMessage.text
            if !outgoingText.isEmpty {
                return Message(owner: .outgoing, body: MessageText(text: outgoingText, sendDate: entry.deliveryTime.seconds))
            }
            
            let outgoingUrl = entry.contactMessage.mediaMessage.url
            if !outgoingUrl.isEmpty {
                
                return Message(owner: .outgoing, body: MessageImage(url: outgoingUrl, sendDate: entry.deliveryTime.seconds, placeholderImage: nil))
            }
            // MARK: - Incoming messages
            
            let incomingText = entry.appMessage.textMessage.text
            if !incomingText.isEmpty {
                if entry.appMessage.hasAgent {
                    let agent = entry.appMessage.agent
                    
                    return Message(owner: .incoming(.init(name: agent.displayName, type: agent.type.rawValue)),
                                   body: MessageText(text: incomingText,
                                                     sendDate: entry.deliveryTime.seconds))
                } else {
                    
                    return Message(owner: .incoming(nil),
                                   body: MessageText(text: incomingText,
                                                     sendDate: entry.deliveryTime.seconds))
                }
            }
        
        let incomingUrl = entry.appMessage.mediaMessage.url
        
        if !incomingUrl.isEmpty {
            if entry.appMessage.hasAgent {
                let agent = entry.appMessage.agent
                
                return Message(owner: .incoming(.init(name: agent.displayName, type: agent.type.rawValue)),
                               body: MessageImage(url: incomingUrl,
                                                  sendDate: entry.deliveryTime.seconds, placeholderImage: nil))
            } else {
                return Message(owner: .incoming(nil),
                               body: MessageImage(url: incomingUrl,
                                                  sendDate: entry.deliveryTime.seconds, placeholderImage: nil))
            }
        }
        
        // MARK: - Events
        
        if entry.appEvent.agentLeftEvent.hasAgent {
            
            let agentThatLeft = entry.appEvent.agentLeftEvent.agent
            
            return Message(owner: .system,
                           body: MessageEvent(type: .left(Agent(name: agentThatLeft.displayName,
                                                                type: agentThatLeft.type.rawValue,
                                                                pictureUrl: agentThatLeft.pictureURL)),
                                              sendDate: entry.deliveryTime.seconds))
            
        }
        
        if entry.appEvent.agentJoinedEvent.hasAgent {
            
            let agentThatJoined = entry.appEvent.agentJoinedEvent.agent
            
            return Message(owner: .system,
                           body: MessageEvent(type: .joined(Agent(name: agentThatJoined.displayName,
                                                                  type: agentThatJoined.type.rawValue,
                                                                  pictureUrl: agentThatJoined.pictureURL)),
                                              sendDate: entry.deliveryTime.seconds))
            
        }
    }
    
    return nil
}
}
