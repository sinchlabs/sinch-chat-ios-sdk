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
    func sendMessage(_ message: MessageType, completion: @escaping (Result<String, MessageDataSourceError>) -> Void)
    func subscribeForMessages(completion: @escaping (Result<Message, MessageDataSourceError>) -> Void)
    func getMessageHistory(completion: @escaping (Result<[Message], MessageDataSourceError>) -> Void)
    func sendConversationMetadata(_ metadata: [SinchMetadata]) -> Result<Void, MessageDataSourceError>
    func cancelSubscription()
    func closeChannel()
    func startChannel()
    func cancelCalls()
    func isSubscribed() -> Bool
    func isFirstPage() -> Bool
    
}

final class DefaultMessageDataSource: MessageDataSource {
       
    var authDataSource: AuthDataSource
    var client: APIClient
    var historyCall: UnaryCall<Sinch_Chat_Sdk_V1alpha2_GetHistoryRequest, Sinch_Chat_Sdk_V1alpha2_GetHistoryResponse>?
    var sendMessageCall: UnaryCall<Sinch_Chat_Sdk_V1alpha2_SendRequest, Sinch_Chat_Sdk_V1alpha2_SendResponse>?
    var uploadStreamMediaCall: ClientStreamingCall<Sinch_Chat_Sdk_V1alpha2_UploadMediaRequest, Sinch_Chat_Sdk_V1alpha2_UploadMediaResponse>?
    var uploadMediaCall: ClientStreamingCall<Sinch_Chat_Sdk_V1alpha2_UploadMediaRequest, Sinch_Chat_Sdk_V1alpha2_UploadMediaResponse>?
    weak var delegate: MessageDataSourceDelegate?
    var firstPage: Bool = true
    lazy var dispatchQueue = DispatchQueue(label: "taskQueue")
    lazy var dispatchSemaphore = DispatchSemaphore(value: 0)
    
    private var nextPageToken: String?
    private let pageSize: Int32 = 10
    private var subscription: ServerStreamingCall<Sinch_Chat_Sdk_V1alpha2_SubscribeToStreamRequest, Sinch_Chat_Sdk_V1alpha2_SubscribeToStreamResponse>?
    
    private let topicModel: TopicModel?
    private let metadata: [SinchMetadata]
    private let shouldInitializeConversation: Bool
    
    private let jsonEncoder = JSONEncoder()
    
    init(apiClient: APIClient, authDataSource: AuthDataSource, topicModel: TopicModel? = nil, metadata: [SinchMetadata] = [], shouldInitializeConversation: Bool = false) {
        self.client = apiClient
        self.authDataSource = authDataSource
        
        // Optional mode
        self.topicModel = topicModel
        self.metadata = metadata
        self.shouldInitializeConversation = shouldInitializeConversation
        
        let metadataToSend = metadata.filter({ $0.getKeyValue().mode == .withEachMessage })
        
        if metadataToSend.isEmpty == false {
            _ = sendConversationMetadata(metadataToSend)
        }
    }
    func closeChannel() {
        self.client.closeChannel()
    }
    func startChannel() {
        self.client.startChannel()
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
            
            if let topicModel = topicModel {
                request.topicID = topicModel.topicID
            }
            
            self.historyCall = service.getHistory(request, callOptions: nil)
            
            _ = self.historyCall?.response.always { [weak self] result in
                guard let self = self else {
                    return
                }
                switch result {
                case .success(let result):
                    
                    self.nextPageToken = result.nextPageToken
                    var messages: [Message] = []
                    
                    self.dispatchQueue.async {
                        
                        for entry in result.entries {
                            let message = self.handleIncomingMessage(entry)
                            
                            guard var message = message else { continue }
                            
                            if let mediaMessage = message.body as? MessageMedia {
                                
                                self.getMediaMessageTypeFromMessage(mediaMessage, completion: { messageBody in
                                    if let messageBody = messageBody {
                                        
                                        if messageBody.type != .unsupported {
                                            message.body = messageBody
                                            
                                        } else {
                                            message.body = MessageUnsupported(sendDate: messageBody.sendDate)
                                        }
                                        
                                        messages.append(message)
                                    }
                                    
                                    self.dispatchSemaphore.signal()
                                })
                                
                                self.dispatchSemaphore.wait()
                            } else {
                                
                                messages.append(message)
                            }
                        }
                    }
                    
                    self.dispatchQueue.async {
                        completion(.success(messages))
                    }
                    
                case .failure(let err):
                    completion(.failure(.unknown(err)))
                }
            }
        } catch {
            completion(.failure(.notLoggedIn))
        }
    }
    
    func sendMessage(_ message: MessageType, completion: @escaping (Result<String, MessageDataSourceError>) -> Void) {
        do {
            let service = try getService()
            
            guard var message = message.convertToSinchMessage else {
                completion(.failure(.unknownTypeOfMessage))
                return
            }
            if let topicModel = topicModel {
                message.topicID = topicModel.topicID
            }
            if let metadata = convertSinchMetadataToMetadataJson(metadata: metadata.filter({ $0.getKeyValue().mode == .withEachMessage })) {
                message.metadata = metadata
            }
            
//            let test = Sinch_Chat_Sdk_V1alpha2_SendRequest()
//            test.message = .init()
//            test.message.fallbackMessage
            

            sendMessageCall = service.send(message)
            
            _ = sendMessageCall?.response.always { result in
                
                switch result {
                case .success(let response):
                    
                    completion(.success(response.messageID))
                    
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
            var request = Sinch_Chat_Sdk_V1alpha2_SubscribeToStreamRequest()
            if let topicModel = topicModel {
                request.topicID = topicModel.topicID
            }
            
            let subscription = service.subscribeToStream(request, callOptions: nil) { [weak self] response in
                guard let self = self else {
                    return
                }
                
                let message = self.handleIncomingMessage(response.entry)
                
                guard var message = message else { return }
                
                self.dispatchQueue.async {
                    
                    if let mediaMessage = message.body as? MessageMedia {
                        
                        self.getMediaMessageTypeFromMessage(mediaMessage, completion: { messageBody in
                            
                            if let messageBody = messageBody {
                                
                                if messageBody.type != .unsupported {
                                    
                                    message.body = messageBody
                                    
                                } else {
                                    message.body = MessageUnsupported(sendDate: messageBody.sendDate)
                                }
                                self.dispatchSemaphore.signal()
                                
                            }
                        })
                        self.dispatchSemaphore.wait()
                        
                    }
                }
                
                self.dispatchQueue.async {
                    
                    completion(.success(message))
                    
                }
                
            }
            
            self.subscription = subscription
            
            if shouldInitializeConversation {
                self.sendMessage(.fallbackMessage("conversation_start")) { _ in }
            }
            
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
    
    func sendConversationMetadata(_ metadata: [SinchMetadata]) -> Result<Void, MessageDataSourceError> {
        
        var keyValueDictionary: [String: String] = [:]
        metadata.forEach { metadata in
            let data = metadata.getKeyValue()
            keyValueDictionary[data.key] = data.value
        }
        do {
            let encodedData = try jsonEncoder.encode(keyValueDictionary)
            
            var request = Sinch_Chat_Sdk_V1alpha2_SendRequest()
            request.metadata = String(bytes: encodedData, encoding: .utf8) ?? "{}"
            
            try getService().send(request).status.whenComplete { result in
                switch result {
                case .failure(let err):
                    Logger.warning("cannot set conversation metadata", err.localizedDescription)
                case .success:
                    break
                }
            }
            
            return .success(())
            
        } catch let error {
            return .failure(.unknown(error))
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
    
    func getMediaMessageTypeFromMessage(_ message: MessageMedia, completion: @escaping (MessageMedia?) -> Void) {
        
        guard let url = URL(string: message.url) else {
            completion(message)
            return
            
        }
        var mediaMessage = message
        var request = URLRequest(url: url)
        request.httpMethod = "HEAD"
        
        let task = URLSession.shared.dataTask(with: request, completionHandler: {  _, response, error in
            
            if error != nil {
                completion(nil)
            }
            
            //https://developer.apple.com/library/archive/documentation/2DDrawing/Conceptual/DrawingPrintingiOS/LoadingImages/LoadingImages.html
            
            if let response = response as? HTTPURLResponse, let type = response.allHeaderFields["Content-Type"] as? String {
                
                switch type {
                case "video/mp4", "video/mov":
                    mediaMessage.type = .video
                case "audio/aac", "audio/adts", "audio/ac3","audio/aif","audio/aiff","audio/aifc", "audio/caf",
                    "audio/mp4", "audio/mp3", "audio/m4a", "audio/snd", "audio/au", "audio/wav", "audio/sd2":
                    mediaMessage.type = .audio
                case "image/jpg", "image/jpeg", "image/png", "image/tif", "image/tiff", "image/gif", "image/bmp",
                    "image/BMPf", "image/ico", "image/cur", "image/xbm":
                    mediaMessage.type = .image
                    
                default:
                    mediaMessage.type = .unsupported
                }
            }
            
            completion(mediaMessage)
        })
        
        task.resume()
    }
    
    // swiftlint:disable function_body_length cyclomatic_complexity
    private func handleIncomingMessage(_ entry: Sinch_Chat_Sdk_V1alpha2_Entry) -> Message? {
        
        if entry.hasDeliveryTime {
            
            // MARK: - Outgoing messages
            
            let outgoingText = entry.contactMessage.textMessage.text
            if !outgoingText.isEmpty {
                return Message(entryId: entry.entryID, owner: .outgoing, body: MessageText(text: outgoingText, sendDate: entry.deliveryTime.seconds))
            }
            
            let outgoingUrl = entry.contactMessage.mediaMessage.url
            if !outgoingUrl.isEmpty {
                
                return Message(entryId: entry.entryID, owner: .outgoing, body: MessageMedia(url: outgoingUrl, sendDate: entry.deliveryTime.seconds))
            }
            // MARK: - Incoming messages
            
            let incomingText = entry.appMessage.textMessage.text
            if !incomingText.isEmpty {
                if entry.appMessage.hasAgent {
                    let agent = entry.appMessage.agent
                    
                    return Message(entryId: entry.entryID,
                                   owner: .incoming(.init(name: agent.displayName, type: agent.type.rawValue, pictureUrl: agent.pictureURL)),
                                   body: MessageText(text: incomingText, sendDate: entry.deliveryTime.seconds))
                } else {
                    
                    return Message(entryId: entry.entryID, owner: .incoming(nil),
                                   body: MessageText(text: incomingText,
                                                     sendDate: entry.deliveryTime.seconds))
                }
            }
            let outgoingLocationMessage = entry.contactMessage.locationMessage
            if outgoingLocationMessage.hasCoordinates {
                let messageBody = MessageLocation(label: outgoingLocationMessage.label,
                                                  title: outgoingLocationMessage.title,
                                                  latitude: Double(outgoingLocationMessage.coordinates.latitude),
                                                  longitude: Double(outgoingLocationMessage.coordinates.longitude),
                                                  sendDate: entry.deliveryTime.seconds)
                
                return Message(entryId: entry.entryID, owner: .outgoing, body: messageBody)
            }
            
            let incomingLocationMessage = entry.appMessage.locationMessage
            if incomingLocationMessage.hasCoordinates {
                let messageBody = MessageLocation(label: incomingLocationMessage.label,
                                                  title: incomingLocationMessage.title,
                                                  latitude: Double(incomingLocationMessage.coordinates.latitude),
                                                  longitude: Double(incomingLocationMessage.coordinates.longitude),
                                                  sendDate: entry.deliveryTime.seconds)
                
                if entry.appMessage.hasAgent {
                    let agent = entry.appMessage.agent
                    
                    return Message(entryId: entry.entryID, owner: .incoming(.init(name: agent.displayName,
                                                                                  type: agent.type.rawValue)),
                                   body:  messageBody)
                } else {
                    
                    return Message(entryId: entry.entryID, owner: .incoming(nil), body: messageBody)
                }
            }
            
            let incomingChoiceMessage = entry.appMessage.choiceMessage
            if incomingChoiceMessage.hasTextMessage {
                
                // EntryID is messageID in case od message types.
                let choicesArray = DefaultMessageDataSource.createChoicesArray(incomingChoiceMessage.choices, entryID: entry.entryID)
                
                let messageBody = MessageChoices(text: incomingChoiceMessage.textMessage.text,
                                                 choices: choicesArray,
                                                 sendDate: entry.deliveryTime.seconds)
                
                if entry.appMessage.hasAgent {
                    let agent = entry.appMessage.agent
                    
                    return Message(entryId: entry.entryID, owner: .incoming(.init(name: agent.displayName, type: agent.type.rawValue)),
                                   body:  messageBody)
                } else {
                    
                    return Message(entryId: entry.entryID, owner: .incoming(nil), body: messageBody)
                }
            }
            let incomingCardMessage = entry.appMessage.cardMessage
            
            if incomingCardMessage.hasMediaMessage {
                
                // EntryID is messageID in case od message types.
                let choicesArray = DefaultMessageDataSource.createChoicesArray(incomingCardMessage.choices, entryID: entry.entryID)
                
                let messageBody = MessageCard(title: incomingCardMessage.title,
                                              description: incomingCardMessage.description_p,
                                              choices: choicesArray,
                                              url: incomingCardMessage.mediaMessage.url,
                                              sendDate: entry.deliveryTime.seconds)
                
                if entry.appMessage.hasAgent {
                    let agent = entry.appMessage.agent
                    
                    return Message(entryId: entry.entryID, owner: .incoming(.init(name: agent.displayName, type: agent.type.rawValue)),
                                   body:  messageBody)
                } else {
                    
                    return Message(entryId: entry.entryID, owner: .incoming(nil), body: messageBody)
                }
            }
            
            let incomingCarouselMessage = entry.appMessage.carouselMessage
            
            if !incomingCarouselMessage.cards.isEmpty {
                
                let carouselChoicesArray = DefaultMessageDataSource.createChoicesArray(incomingCarouselMessage.choices, entryID: entry.entryID)
                
                var cardsArray: [MessageCard] = []
                
                for incomingCardMessage in incomingCarouselMessage.cards {
                    
                    let choicesArray = DefaultMessageDataSource.createChoicesArray(incomingCardMessage.choices, entryID: entry.entryID)
                    let messageBody = MessageCard(title: incomingCardMessage.title,
                                                  description: incomingCardMessage.description_p ,
                                                  choices: choicesArray,
                                                  url: incomingCardMessage.mediaMessage.url,
                                                  sendDate: entry.deliveryTime.seconds)
                    
                    cardsArray.append(messageBody)
                    
                }
                
                let messageBody = MessageCarousel(cards: cardsArray, choices: carouselChoicesArray, sendDate: entry.deliveryTime.seconds)
                
                if entry.appMessage.hasAgent {
                    let agent = entry.appMessage.agent
                    
                    return Message(entryId: entry.entryID, owner: .incoming(.init(name: agent.displayName, type: agent.type.rawValue)),
                                   body:  messageBody)
                } else {
                    
                    return Message(entryId: entry.entryID, owner: .incoming(nil), body: messageBody)
                }
            }
            
            let incomingUrl = entry.appMessage.mediaMessage.url
            
            if !incomingUrl.isEmpty {
                if entry.appMessage.hasAgent {
                    let agent = entry.appMessage.agent
                    
                    return Message(entryId: entry.entryID, owner: .incoming(.init(name: agent.displayName, type: agent.type.rawValue)),
                                   body: MessageMedia(url: incomingUrl,
                                                      sendDate: entry.deliveryTime.seconds, placeholderImage: nil))
                } else {
                    return Message(entryId: entry.entryID, owner: .incoming(nil),
                                   body: MessageMedia(url: incomingUrl,
                                                      sendDate: entry.deliveryTime.seconds, placeholderImage: nil))
                }
            }
            
            // MARK: - Events
            
            if entry.appEvent.agentLeftEvent.hasAgent {
                
                let agentThatLeft = entry.appEvent.agentLeftEvent.agent
                
                return Message(entryId: entry.entryID, owner: .system,
                               body: MessageEvent(type: .left(Agent(name: agentThatLeft.displayName,
                                                                    type: agentThatLeft.type.rawValue,
                                                                    pictureUrl: agentThatLeft.pictureURL)),
                                                  sendDate: entry.deliveryTime.seconds))
                
            }
            
            if entry.appEvent.agentJoinedEvent.hasAgent {
                
                let agentThatJoined = entry.appEvent.agentJoinedEvent.agent
                
                return Message(entryId: entry.entryID, owner: .system,
                               body: MessageEvent(type: .joined(Agent(name: agentThatJoined.displayName,
                                                                      type: agentThatJoined.type.rawValue,
                                                                      pictureUrl: agentThatJoined.pictureURL)),
                                                  sendDate: entry.deliveryTime.seconds))
                
            }
            
            // TODO: NEEDs attenchion - Skipping clicks on buttons on christmas BOT.
            if entry.contactMessage.choiceResponseMessage.postbackData != ""
                || entry.contactMessage.fallbackMessage.rawMessage.isEmpty == false {
                return nil
            }
            
            return Message(entryId: entry.entryID, owner: .incoming(nil), body: MessageUnsupported(sendDate: entry.deliveryTime.seconds))
        }
        
        return nil
    }
    
    private func convertSinchMetadataToMetadataJson(metadata: [SinchMetadata]) -> String? {
        var dictMetadata: [String: String] = [:]
        
        metadata.forEach({
            let tuple = $0.getKeyValue()
            dictMetadata[tuple.key] = tuple.value
        })
        
        guard let encodedMetadata = try? JSONEncoder().encode(dictMetadata) else {
            return nil
        }
        
        return String(data: encodedMetadata, encoding: .utf8)
    }
    
    static func createChoicesArray(_ choices: [Sinch_Conversationapi_Type_Choice], entryID: String) -> [ChoiceMessageType] {
        
        var choicesArray: [ChoiceMessageType] = []
        
        for choice in choices {
            guard let message = choice.choice else {
                break
            }
            switch message {
            case .textMessage( let textMessage):
                choicesArray.append(.textMessage((ChoiceText(text: textMessage.text, postback: choice.postbackData, entryID: entryID))))
            case .urlMessage(let urlMessage):
                choicesArray.append(.urlMessage(ChoiceUrl(url: urlMessage.url, text: urlMessage.title)))
            case .callMessage(let callMessage):
                choicesArray.append(.callMessage(ChoiceCall(text: callMessage.title, phoneNumber: callMessage.phoneNumber)))
            case .locationMessage(let locationMessage):
                choicesArray.append(.locationMessage(ChoiceLocation(text: locationMessage.title,
                                                                    label: locationMessage.label,
                                                                    latitude: Double(locationMessage.coordinates.latitude),
                                                                    longitude: Double(locationMessage.coordinates.longitude))))
            }
        }
        return choicesArray
    }
}

struct TopicModel {
    let topicID: String
    
}
