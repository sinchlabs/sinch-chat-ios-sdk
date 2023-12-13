import UIKit

public protocol SinchInbox {
    
    /// Creating Inbox UI. This method may throw
    /// - Parameters:
   
    ///   - uiConfig: Optionally ui changes might be provided with different settings.
    ///   - localizationConfig: Optionally localization might be provided with different text translation.

    /// - Returns: UIViewController which contains inbox UI.
    /// - Throws: SinchInboxSDKError enum with specific error.
    func getInboxViewController(uiConfig: SinchSDKConfig.UIConfig?,
                                localizationConfig: SinchSDKConfig.LocalizationConfig?,
                                options: GetChatViewControllerOptions?) throws -> SinchChatViewController
    /// Get latest conversations
    /// - Returns: array of latest conversations
    ///
    ///
    /// 
    func getInboxChats(completion: @escaping ([InboxChat]) -> Void)
   
    /// Creating Chat UI. This method may throw
    /// - Parameters:
    ///
    ///   - InboxChat: Conversation obtained with getInboxChats(completion: @escaping ([InboxChat]) -> Void)
    ///   - uiConfig: Optionally ui changes might be provided with different settings.
    ///   - localizationConfig: Optionally localization might be provided with different text translation.

    /// - Returns: UIViewController which contains chat UI.
    /// - Throws: SinchChatSDKError enum with specific error.
    ///
    func getChatViewController(inboxChat: InboxChat,
                               uiConfig: SinchSDKConfig.UIConfig?,
                               localizationConfig: SinchSDKConfig.LocalizationConfig?
    ) throws -> SinchChatViewController
    
}

public struct InboxChat: Codable {
    
    // display model
    public var text: String
    public var sendDate: Date
    
    public var avatarImage: String?
    public var status: String

    // run model
    public var chatOptions: InboxChatOptions?
    
    public init(text: String, sendDate: Date, avatarImage: String?, status: String, options: InboxChatOptions) {
        self.text = text
        self.sendDate = sendDate
        self.avatarImage = avatarImage
        self.chatOptions = options
        self.status = status
    }
}

public struct InboxChatOptions: Codable {
    
    public let option: SinchChatOptions?
    public let authModel: AuthModel?
    
    // those stuff we can get from AuthDataSource + MessageDataSource
}

public extension SinchInbox {
    
    func getInboxViewController(uiConfig: SinchSDKConfig.UIConfig? = nil,
                                localizationConfig: SinchSDKConfig.LocalizationConfig? = nil,
                                options: GetChatViewControllerOptions? = nil) throws -> SinchChatViewController {
        try getInboxViewController(uiConfig: uiConfig, localizationConfig: localizationConfig, options: options)
    }
}

public enum SinchInboxSDKError: Error {
    case unavailable
}

final class DefaultSinchInbox: SinchInbox {
    
    var lastChatOptions: GetChatViewControllerOptions?
        
    internal var authDataSource: AuthDataSource?
    internal var region: Region?

    private let pushPermissionHandler: PushNofiticationPermissionHandler
    private let chatNotificationHandler = ChatNotificationHandler()
    private var apiClient: APIClient?
    private var rootCoordinator: InboxRootCoordinator?
    private var inbox: InboxViewController?

    init(pushPermissionHandler: PushNofiticationPermissionHandler) {
        self.pushPermissionHandler = pushPermissionHandler
    }
        
    public func getInboxViewController(uiConfig: SinchSDKConfig.UIConfig? = nil,
                                       localizationConfig: SinchSDKConfig.LocalizationConfig? = nil,
                                       options: GetChatViewControllerOptions? = nil) throws -> SinchChatViewController {
       
       guard let authDataSource = authDataSource, let region = region else {
            throw SinchChatSDKError.unavailable
       }
        guard let client = DefaultAPIClient(region: region) else {
            throw SinchChatSDKError.unavailable
        }
        
        apiClient = client
        
        let rootCordinator = DefaultInboxRootCoordinator(uiConfiguration: uiConfig ?? .defaultValue,
                                                         localizationConfiguration: localizationConfig ?? .defaultValue,
                                                         authDataSource: authDataSource, pushPermissionHandler: pushPermissionHandler)
        self.rootCoordinator =  rootCordinator
        let inbox =  rootCordinator.getRootViewController(apiClient: client, options: options)
    
        return inbox

    }
    func getInboxChats(completion: @escaping ([InboxChat]) -> Void) {
       
        if let data = UserDefaults.standard.data(forKey: "lastMessage") {
            do {
                // Create JSON Decoder
                let decoder = JSONDecoder()

                // Decode Note
                let conversation = try decoder.decode(InboxChat.self, from: data)
               
                completion([conversation])
            } catch {
                print("Unable to Decode Note (\(error))")
                completion([])

            }
        }
    }
    
    func getChatViewController(inboxChat: InboxChat, uiConfig: SinchSDKConfig.UIConfig? = nil,
                               localizationConfig: SinchSDKConfig.LocalizationConfig? = nil) throws -> SinchChatViewController {
          
        let options: GetChatViewControllerOptions = .init(topicID:
                                                            inboxChat.chatOptions?.option?.topicID,
                                                          metadata: inboxChat.chatOptions?.option?.metadata ?? [], shouldInitializeConversation: true)
        
        return try SinchChatSDK.shared.chat.getChatViewController(uiConfig: rootCoordinator?.uiConfiguration,
                                                                  localizationConfig: rootCoordinator?.localizationConfiguration,
                                                                  options:options)
        
    }
    
    func initilize() {
      
     //   SinchChatSDK.shared.pushNotificationHandler.registerAddressee(chatNotificationHandler)
    //    chatNotificationHandler.delegate = self
    }
}
