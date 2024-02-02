import UIKit

public protocol SinchChat {
     var inbox: SinchInbox { get }

    /// Advanced settings and method of Sinch Chat.
    var advanced: SinchChatAdvanced { get }
    
    /// Checks if chat can be opened.
    /// - Returns: Current Chat availability.
    func isChatAvailable() -> SinchSDKChatAvailability
    
    /// Creating Chat UI. This method may throw
    /// - Parameters:
   
    ///   - uiConfig: Optionally ui changes might be provided with different settings.
    ///   - localizationConfig: Optionally localization might be provided with different text translation.
    ///   - options: Optionally custom chat options.
    /// - Returns: UIViewController which contains chat UI.
    /// - Throws: SinchChatSDKError enum with specific error.
    func getChatViewController(uiConfig: SinchSDKConfig.UIConfig?,
                               localizationConfig: SinchSDKConfig.LocalizationConfig?,
                               options: GetChatViewControllerOptions?) throws -> SinchChatViewController
    
}

public class SinchChatViewController: StartViewController {
}

public extension SinchChat {
    
    func getChatViewController(uiConfig: SinchSDKConfig.UIConfig? = nil,
                               localizationConfig: SinchSDKConfig.LocalizationConfig? = nil,
                               options: GetChatViewControllerOptions? = nil) throws -> SinchChatViewController {
        try getChatViewController(uiConfig: uiConfig, localizationConfig: localizationConfig, options: options)
    }
}

public enum SinchSDKChatAvailability {
    /// The Chat is ready to user.
    case available
    /// The Chat is not initialized
    /// Tip: use initialize method to initialize chat.
    case uninitialized
    /// The chat is not authorized
    /// Tip: User setIdentity method to authorize the client.
    case authorizationNeeded
    
    /// The chat is opened
    /// You cannot run two chats at once.
    case currentlyRunning
}

public enum SinchChatSDKError: Error {
    case unavailable
}

public enum SinchChatState {
    case running
    case idle
}

final class DefaultSinchChat: SinchChat {
    
    /// Contains all methods connected with Inbox. Before using the inbox you should use method `setIdentity`.
    public var inbox: SinchInbox { _inbox }

    lazy var _inbox = DefaultSinchInbox(pushPermissionHandler: pushPermissionHandler)

    var state: SinchChatState = .idle
    
    var lastChatOptions: GetChatViewControllerOptions?
    
    var advanced: SinchChatAdvanced = .init()
    
    internal var authDataSource: AuthDataSource? {
        didSet {
            _inbox.authDataSource = authDataSource
        }
    }
    internal var region: Region? {
        didSet {
            _inbox.region = region
        }
    }
    internal var apiClient: APIClient?

    private let pushPermissionHandler: PushNofiticationPermissionHandler
    private let chatNotificationHandler = ChatNotificationHandler()
    private var rootCordinator: RootCoordinator?

    init(pushPermissionHandler: PushNofiticationPermissionHandler,
         apiClient: APIClient? = nil) {
        self.pushPermissionHandler = pushPermissionHandler
    }
    
    public func isChatAvailable() -> SinchSDKChatAvailability {
        guard state != .running else {
            return SinchSDKChatAvailability.currentlyRunning
        }
        
        guard let authDataSource = authDataSource, region != nil else {
            return SinchSDKChatAvailability.uninitialized
        }
        
        guard authDataSource.isLoggedIn == true else {
            return SinchSDKChatAvailability.authorizationNeeded
        }
        
        return SinchSDKChatAvailability.available
    }
    
    public func getChatViewController(uiConfig: SinchSDKConfig.UIConfig? = nil,
                                      localizationConfig: SinchSDKConfig.LocalizationConfig? = nil,
                                      options: GetChatViewControllerOptions? = nil) throws -> SinchChatViewController {
        
        guard isChatAvailable() == .available, let authDataSource = authDataSource, let region = region else {
            throw SinchChatSDKError.unavailable
        }
        
        if let apiClient = self.apiClient {
            
            if !apiClient.isChannelStarted {
                let client = DefaultAPIClient(region: region)
                
                self.apiClient = client
            }
            
        } else {
            let client = DefaultAPIClient(region: region)
            
            apiClient = client
        }
        
        var topicModel: TopicModel?
        if let topicID = options?.topicID {
            topicModel = TopicModel(topicID: topicID)
        }
        
        let messageDataSource = InboxMessageDataSource(
            apiClient: apiClient!,
            authDataSource: authDataSource,
            topicModel: topicModel,
            metadata: options?.metadata ?? [],
            shouldInitializeConversation: options?.shouldInitializeConversation ?? false,
            sendDocumentAsText: options?.sendDocumentAsTextMessage ?? false)
        let rootCordinator = DefaultRootCoordinator(messageDataSource: messageDataSource,
                                                    authDataSource: authDataSource,
                                                    pushPermissionHandler: pushPermissionHandler)
        
        self.rootCordinator = rootCordinator
        let uiConfig = uiConfig ?? SinchSDKConfig.UIConfig.defaultValue
        let locConfig = localizationConfig ?? SinchSDKConfig.LocalizationConfig.defaultValue
        
        lastChatOptions = options
        return rootCordinator.getRootViewController(uiConfig: uiConfig, localizationConfig: locConfig, sendDocumentAsText: options?.sendDocumentAsTextMessage ?? false)
        
    }

    func initilize() {
        _inbox.initilize()
        SinchChatSDK.shared.pushNotificationHandler.registerAddressee(chatNotificationHandler)
        chatNotificationHandler.delegate = self
    }
}

extension DefaultSinchChat: ChatNotificationHandlerDelegate {
    
    func getChatState() -> SinchChatState {
        state
    }
}

public protocol SinchMetadata: Codable, Hashable {
    // swiftlint:disable:next large_tuple
    func getKeyValue() -> (key: String, value: String, mode: SinchMetadataMode)
}

public typealias SinchMetadataArray = Array<SinchMetadataCustom>

public enum SinchMetadataMode: Codable {
    case once
    case withEachMessage
}

public struct GetChatViewControllerOptions {
    let topicID: String?
    let metadata: SinchMetadataArray
    let shouldInitializeConversation: Bool
    let sendDocumentAsTextMessage: Bool
    
    public init(
        topicID: String? = nil,
        metadata: SinchMetadataArray,
        shouldInitializeConversation: Bool = false,
        sendDocumentAsTextMessage: Bool = false
    ) {
        self.topicID = topicID
        self.metadata = metadata
        self.shouldInitializeConversation = shouldInitializeConversation
        self.sendDocumentAsTextMessage = sendDocumentAsTextMessage
    }
}

public struct SinchMetadataCustom: Codable, Equatable, SinchMetadata {
    let key: String
    let value: String
    let mode: SinchMetadataMode
    
    public init(key: String, value: String, mode: SinchMetadataMode) {
        self.key = key
        self.value = value
        self.mode = mode
    }
    
    // swiftlint:disable:next large_tuple
    public func getKeyValue() -> (key: String, value: String, mode: SinchMetadataMode) {
        return (key, value, mode)
    }
    
    public static func == (lhs: SinchMetadataCustom, rhs: SinchMetadataCustom) -> Bool {
        lhs.key == rhs.key &&
        lhs.value == rhs.value &&
        lhs.mode == rhs.mode
    }
}

public class SinchChatAdvanced {
    
    internal init() {}
    
    internal var _isSendingMessagesEnabled: Bool = true
    internal var enableSendingMessagesHandler: (() -> Void)?
    internal var disableSendingMessagesHandler: (() -> Void)?
    
    /// Provides information if sending messages feature is enabled.
    public var isSendingMessagesEnabled: Bool {
        _isSendingMessagesEnabled
    }
    
    /// Enables possibility to sending messages.
    public func enableSendingMessages() {
        _isSendingMessagesEnabled = true
        self.enableSendingMessagesHandler?()
    }
    
    /// Disables possibility to sending messages.
    public func disableSendingMessages() {
        _isSendingMessagesEnabled = false
        self.disableSendingMessagesHandler?()
    }
    
}
