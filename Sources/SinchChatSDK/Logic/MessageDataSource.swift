import Foundation
import GRPC

protocol MessageDataSourceDelegate: AnyObject {
    
    func subscriptionError()
}

enum MessageDataSourceError: Error {
    case unknown(Error)
    case notLoggedIn
    case unknownTypeOfMessage
    case unknownTypeOfEvent
    case messageIDIsEmpty
    case subscriptionIsAlreadyStarted
    case noMoreMessages
    case unknownTypeOfMedia
    case noInternetConnection
    
}
protocol MessageDataSource {
    
    var delegate: MessageDataSourceDelegate? { get set }
    
    var topicModel: TopicModel? { get }
    var metadata: SinchMetadataArray { get }
    var shouldInitializeConversation: Bool { get }
    
    func uploadMedia(_ media: MediaType, completion: @escaping (Result<String, MessageDataSourceError>) -> Void)
    func uploadMediaViaStream(_ media: MediaType, completion: @escaping (Result<String, MessageDataSourceError>) -> Void)
    func sendMessage(_ message: MessageType, completion: @escaping (Result<String, MessageDataSourceError>) -> Void)
    func sendEvent(_ event: EventType, completion: @escaping (Result<Void, MessageDataSourceError>) -> Void)
    func subscribeForMessages(completion: @escaping (Result<Message, MessageDataSourceError>) -> Void)
    func getMessageHistory(completion: @escaping (Result<[Message], MessageDataSourceError>) -> Void)
    func sendConversationMetadata(_ metadata: SinchMetadataArray) -> Result<Void, MessageDataSourceError>
    func cancelSubscription()
    func closeChannel()
    func startChannel()
    func cancelCalls()
    func isSubscribed() -> Bool
    func isFirstPage() -> Bool
    
}
class InboxMessageDataSource: MessageDataSource {
    
    private let messageDataSource: DefaultMessageDataSource
    
    init(apiClient: APIClient, authDataSource: AuthDataSource, topicModel: TopicModel? = nil, metadata: SinchMetadataArray = [], shouldInitializeConversation: Bool = false) {
        messageDataSource = DefaultMessageDataSource(
            apiClient: apiClient,
            authDataSource: authDataSource,
            topicModel: topicModel,
            metadata: metadata,
            shouldInitializeConversation: shouldInitializeConversation
        )
    }
    
    var delegate: MessageDataSourceDelegate? {
        get {
            return messageDataSource.delegate
        }
        set {
            messageDataSource.delegate = newValue
        }
    }
    
    var topicModel: TopicModel? {
        messageDataSource.topicModel
        
    }
    
    var metadata: SinchMetadataArray {
        get {
            return messageDataSource.metadata
        }
        set {
            messageDataSource.metadata = newValue
        }
    }
    
    var shouldInitializeConversation: Bool {
        
         messageDataSource.shouldInitializeConversation

    }
    
    func uploadMedia(_ media: MediaType, completion: @escaping (Result<String, MessageDataSourceError>) -> Void) {
        messageDataSource.uploadMedia(media, completion: completion)
    }
    
    func uploadMediaViaStream(_ media: MediaType, completion: @escaping (Result<String, MessageDataSourceError>) -> Void) {
        messageDataSource.uploadMediaViaStream(media, completion: completion)
    }
    
    func sendMessage(_ message: MessageType, completion: @escaping (Result<String, MessageDataSourceError>) -> Void) {
        messageDataSource.sendMessage(message, completion: completion)
    }
    
    func sendEvent(_ event: EventType, completion: @escaping (Result<Void, MessageDataSourceError>) -> Void) {
        messageDataSource.sendEvent(event, completion: completion)
    }
    
    fileprivate func saveLastMessage(_ message: Message) -> Bool {
        // save to user efaults this message but delete others.
        // Create Note
        if let auth = self.messageDataSource.authDataSource.currentAuthorization, let messageText = message.convertToText {
            
            // todo
            let date = message.body.sendDate ?? Int64(Date().timeIntervalSince1970)
            let conversation = InboxChat(text: messageText, sendDate:  Date(timeIntervalSince1970: TimeInterval(date)),
                                         avatarImage: nil, status: "",
                                                 options: InboxChatOptions(option: .init(
                                                                    topicID: self.messageDataSource.topicModel?.topicID,
                                                                    metadata: self.messageDataSource.metadata,
                                                                    shouldInitializeConversation: self.messageDataSource.shouldInitializeConversation),
                                                                    authModel:auth))
            
            do {
                // Create JSON Encoder
                let encoder = JSONEncoder()
                
                // Encode Note
                let data = try encoder.encode(conversation)
                
                // Write/Set Data
                UserDefaults.standard.set(data, forKey: "lastMessage")
                UserDefaults.standard.synchronize()
                return true
            } catch {
                print("Unable to Encode Conversation (\(error))")
                return false
            }
            
        } else {
            return false
        }
    }
    
    func subscribeForMessages(completion: @escaping (Result<Message, MessageDataSourceError>) -> Void) {
        messageDataSource.subscribeForMessages(completion: { result in
            
            switch result {
            case .success(let message):
                self.saveLastMessage(message)
                
            case .failure:
                break
            }
            
            completion(result)
        })
    }
    
    func getMessageHistory(completion: @escaping (Result<[Message], MessageDataSourceError>) -> Void) {
        messageDataSource.getMessageHistory(completion: { result in
                
                switch result {
                case .success(let messages):
                    if self.messageDataSource.firstPage {
                        for index in stride(from: messages.count - 1, through: 0, by: -1) {
                            
                            if self.saveLastMessage(messages[index]) {
                                break
                            }
                        }
                    }
                case .failure:
                    break
                }
                
                completion(result)
            })
    }
    
    func sendConversationMetadata(_ metadata: SinchMetadataArray) -> Result<Void, MessageDataSourceError> {
        messageDataSource.sendConversationMetadata(metadata)
    }
    
    func cancelSubscription() {
        messageDataSource.cancelSubscription()
    }
    
    func closeChannel() {
        messageDataSource.closeChannel()
    }
    
    func startChannel() {
        messageDataSource.startChannel()
    }
    
    func cancelCalls() {
        messageDataSource.cancelCalls()
    }
    
    func isSubscribed() -> Bool {
        messageDataSource.isSubscribed()
    }
    
    func isFirstPage() -> Bool {
        messageDataSource.isFirstPage()
    }
    
}

final class DefaultMessageDataSource: MessageDataSource {

    var authDataSource: AuthDataSource
    var client: APIClient
    var historyCall: UnaryCall<Sinch_Chat_Sdk_V1alpha2_GetHistoryRequest, Sinch_Chat_Sdk_V1alpha2_GetHistoryResponse>?
    var sendMessageAndEventCall: UnaryCall<Sinch_Chat_Sdk_V1alpha2_SendRequest, Sinch_Chat_Sdk_V1alpha2_SendResponse>?
    var uploadStreamMediaCall: ClientStreamingCall<Sinch_Chat_Sdk_V1alpha2_UploadMediaRequest, Sinch_Chat_Sdk_V1alpha2_UploadMediaResponse>?
    var uploadMediaCall: ClientStreamingCall<Sinch_Chat_Sdk_V1alpha2_UploadMediaRequest, Sinch_Chat_Sdk_V1alpha2_UploadMediaResponse>?
    weak var delegate: MessageDataSourceDelegate?
    var firstPage: Bool = true
    lazy var dispatchQueue = DispatchQueue(label: "taskQueue")
    lazy var dispatchSemaphore = DispatchSemaphore(value: 0)
    
    private var nextPageToken: String?
    private let pageSize: Int32 = 10
    private var subscription: ServerStreamingCall<Sinch_Chat_Sdk_V1alpha2_SubscribeToStreamRequest, Sinch_Chat_Sdk_V1alpha2_SubscribeToStreamResponse>?
    
    let topicModel: TopicModel?
    var metadata: SinchMetadataArray
    let shouldInitializeConversation: Bool
    
    private let jsonEncoder = JSONEncoder()
    
    private var wasSomeMessageSent = false
    
    init(apiClient: APIClient, authDataSource: AuthDataSource, topicModel: TopicModel? = nil, metadata: SinchMetadataArray = [], shouldInitializeConversation: Bool = false) {
        self.client = apiClient
        self.authDataSource = authDataSource
        
        // Optional mode
        self.topicModel = topicModel
        self.metadata = metadata
        self.shouldInitializeConversation = shouldInitializeConversation
    
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
                    // On first entry if there is no history send conversation_start message
                    if shouldInitializeConversation {
                        if self.nextPageToken == nil && result.entries.isEmpty {
                       
                            self.sendMessage(.fallbackMessage("conversation_start")) { _ in
                                
                                debugPrint("*********SEND CONVERSATION START MESSAGE **********")
                            }
                        }
                    }
                    
                    self.nextPageToken = result.nextPageToken
                    var messages: [Message] = []
                    
                    self.dispatchQueue.async {
                        
                        for entry in result.entries {
                            let message = self.handleIncomingMessage(entry)
                            
                            if let body = message?.body, let event = body as? MessageEvent {

                                switch event.type {
                                case .composeEnd, .composeStarted :
                                    continue
                                default:
                                    break
                                }
                            }

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
            if let metadata = convertSinchMetadataToMetadataJson(metadata: metadata.filter({
                // if this is first message then we want to send all metadata
                return $0.getKeyValue().mode == .withEachMessage
            })) {
                message.metadata = metadata
            }
            
            sendEmptyMessageWithMetadataIfNeeded { [weak self] in
                guard let self = self else { return }
                
                sendMessageAndEventCall = service.send(message)
                
                _ = sendMessageAndEventCall?.response.always { [weak self] result in
                    
                    switch result {
                    case .success(let response):
                        self?.wasSomeMessageSent = true
                        completion(.success(response.messageID))
                        
                    case .failure(let err):
                        completion(.failure(.unknown(err)))
                    }
                }
            }
            
        } catch {
            completion(.failure(.notLoggedIn))
        }
    }
    
    func sendEmptyMessageWithMetadataIfNeeded(_ completion: @escaping () -> Void) {
        let metadataOnce = convertSinchMetadataToMetadataJson(metadata: metadata)
        guard wasSomeMessageSent == false, metadata.contains(where: { $0.getKeyValue().mode == .once }), let metadata = metadataOnce else {
            completion()
            return
        }
        
        do {
            
            let service = try getService()
            
            var request = Sinch_Chat_Sdk_V1alpha2_SendRequest()
            request.metadata = metadata
            
            sendMessageAndEventCall = service.send(request)
            
            _ = sendMessageAndEventCall?.response.always({ _ in
                completion()
            })
            
        } catch {
            completion()
        }
        
    }
    
    func sendEvent(_ event: EventType, completion: @escaping (Result<Void, MessageDataSourceError>) -> Void) {
        do {
            let service = try getService()

            guard var request = event.convertToSinchEvent else {
                completion(.failure(.unknownTypeOfEvent))
                return
            }
            if let topicModel = topicModel {
                request.topicID = topicModel.topicID
            }
            if let metadata = convertSinchMetadataToMetadataJson(metadata: metadata.filter({ $0.getKeyValue().mode == .withEachMessage })) {
                request.metadata = metadata
            }

            sendEmptyMessageWithMetadataIfNeeded { [weak self] in
                guard let self = self else { return }
                
                sendMessageAndEventCall = service.send(request)
                
                _ = sendMessageAndEventCall?.response.always { result in
                    
                    switch result {
                    case .success(_):
                        
                        completion(.success(()))
                        
                    case .failure(let err):
                        completion(.failure(.unknown(err)))
                    }
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
    
    // swiftlint:disable:next cyclomatic_complexity
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
    
    func sendConversationMetadata(_ metadata: SinchMetadataArray) -> Result<Void, MessageDataSourceError> {
        
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
        sendMessageAndEventCall?.cancel(promise: nil)
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
    
    private func getService() throws -> Sinch_Chat_Sdk_V1alpha2_SdkServiceNIOClient {
        try Sinch_Chat_Sdk_V1alpha2_SdkServiceNIOClient(channel: client.getChannel(), defaultCallOptions: authDataSource.signRequest(.standardCallOptions))
    }
    
    private func addSize(_ response: HTTPURLResponse, mediaMessage: inout MessageMedia) {
        if let size = response.allHeaderFields["Content-Length"] as? String, let sized = Double(size) {
            
            let sizeInMb = sized / (1024.0 * 1024.0)
            if sizeInMb < 1 {
                let sizeInKB = sized / 1024.0
                mediaMessage.size = String(format: "%.1f KB", sizeInKB)

            } else {
                mediaMessage.size = String(format: "%.1f MB", sizeInMb)
            }
        }
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
                case "audio/aac", "audio/adts", "audio/ac3", "audio/aif","audio/aiff", "audio/aifc", "audio/caf",
                    "audio/mp4", "audio/mp3", "audio/m4a", "audio/snd", "audio/au", "audio/wav", "audio/sd2":
                    mediaMessage.type = .audio
                case "image/jpg", "image/jpeg", "image/png", "image/tif", "image/tiff", "image/gif", "image/bmp",
                    "image/BMPf", "image/ico", "image/cur", "image/xbm":
                    mediaMessage.type = .image
                case "application/pdf":
                    mediaMessage.type = .file(.pdf)
                case "application/vnd.openxmlformats-officedocument.wordprocessingml.document":
                    mediaMessage.type = .file(.docx)
                case "application/msword":
                    mediaMessage.type = .file(.doc)
                case "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet":
                    mediaMessage.type = .file(.xlsx)
                case  "application/vnd.ms-excel":
                    mediaMessage.type = .file(.xls)
                case "application/vnd.openxmlformats-officedocument.presentationml.presentation":
                    mediaMessage.type = .file(.pptx)
                case "application/vnd.ms-powerpoint":
                    mediaMessage.type = .file(.ppt)

                default:
                    mediaMessage.type = .file(.unknown)
                    
                }
                self.addSize(response, mediaMessage: &mediaMessage)

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
                                   body: MessageText(text: incomingText, sendDate: entry.deliveryTime.seconds, isExpanded: false))
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
            
            if !entry.contactMessage.fallbackMessage.rawMessage.isEmpty {
                return Message(entryId: entry.entryID, owner: .system, body: MessageEvent(type: .fallbackMessage(
                    payload: entry.contactMessage.fallbackMessage.rawMessage
                )))
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

            if case .composingEvent(_)? =  entry.appEvent.event {
                return Message(entryId: entry.entryID, owner: .system,
                               body: MessageEvent(type: .composeStarted,
                                                  sendDate: entry.deliveryTime.seconds))

            } else if case .composingEndEvent(_)? =  entry.appEvent.event {
                return Message(entryId: entry.entryID, owner: .system,
                               body: MessageEvent(type: .composeEnd,
                                                  sendDate: entry.deliveryTime.seconds))
                
            } else if case .composingEvent(_)? =  entry.contactEvent.event {
                return nil
            
            } else if case .composingEndEvent(_)? =  entry.contactEvent.event {
                return nil
            }

            if !entry.contactEvent.unknownFields.data.isEmpty {
                return nil

            }

            if entry.appEvent.event != nil {
                return nil
            }

            return Message(entryId: entry.entryID, owner: .incoming(nil), body: MessageUnsupported(sendDate: entry.deliveryTime.seconds))
        }
        
        return nil
    }
    
    private func convertSinchMetadataToMetadataJson(metadata: SinchMetadataArray) -> String? {
        if metadata.isEmpty, SinchChatSDK.shared.additionalMetadata.isEmpty {
            return nil
        }
        var dictMetadata: [String: String] = [:]
        
        SinchChatSDK.shared.additionalMetadata.forEach({
            let tuple = $0.getKeyValue()
            dictMetadata[tuple.key] = tuple.value
        })
        
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
