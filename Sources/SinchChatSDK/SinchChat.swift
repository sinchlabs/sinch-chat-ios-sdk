import UIKit

public protocol SinchChat {
    
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
    
    /// Sets metadata for single conversation. This methods overrides previous metadata.
    /// - Parameters:
    ///    - metadata: Keys with values.
    func setConversationMetadata(_ metadata: [SinchMetadata]) throws
    
    
    
}

public protocol SinchChatViewController: UIViewController {
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
    
    var state: SinchChatState = .idle
    
    var lastChatOptions: GetChatViewControllerOptions?
    
    var advanced: SinchChatAdvanced = .init()
    
    private var authDataSource: AuthDataSource?
    private let pushPermissionHandler: PushNofiticationPermissionHandler
    private let chatNotificationHandler = ChatNotificationHandler()
    private var region: Region?
    private var rootCordinator: RootCoordinator?
    private var apiClient: APIClient?

    init(pushPermissionHandler: PushNofiticationPermissionHandler) {
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
        guard let client = DefaultAPIClient(region: region) else {
            throw SinchChatSDKError.unavailable
        }
                
        apiClient = client
        
        var topicModel: TopicModel?
        if let topicID = options?.topicID {
            topicModel = TopicModel(topicID: topicID)
        }
        
        let messageDataSource = DefaultMessageDataSource(
            apiClient: apiClient!,
            authDataSource: authDataSource,
            topicModel: topicModel,
            metadata: options?.metadata ?? [],
            shouldInitializeConversation: options?.shouldInitializeConversation ?? false)
        let rootCordinator = RootCoordinator(messageDataSource: messageDataSource,
                                             authDataSource: authDataSource,
                                             pushPermissionHandler: pushPermissionHandler)
        
        self.rootCordinator = rootCordinator
        let uiConfig = uiConfig ?? SinchSDKConfig.UIConfig.defaultValue
        let locConfig = localizationConfig ?? SinchSDKConfig.LocalizationConfig.defaultValue

        lastChatOptions = options
        return rootCordinator.getRootViewController(uiConfig: uiConfig, localizationConfig: locConfig )
    }
    
    public func setConversationMetadata(_ metadata: [SinchMetadata]) throws {
        guard isChatAvailable() == .available, let authDataSource = authDataSource, let region = region else {
            throw SinchChatSDKError.unavailable
        }
        if apiClient == nil {
            guard let client = DefaultAPIClient(region: region) else {
                throw SinchChatSDKError.unavailable
            }
            apiClient = client
        }
        
        let messageDataSource = DefaultMessageDataSource(apiClient: apiClient!,
                                                         authDataSource: authDataSource,
                                                         topicModel: nil)
        
        _ = messageDataSource.sendConversationMetadata(metadata)
    }
    
    func initilize(region: Region, authDataSource: AuthDataSource) {
        self.authDataSource = authDataSource
        self.region = region
        SinchChatSDK.shared.pushNotificationHandler.registerAddressee(chatNotificationHandler)
        chatNotificationHandler.delegate = self
    }
}

extension DefaultSinchChat: ChatNotificationHandlerDelegate {
    
    func getChatState() -> SinchChatState {
        state
    }
}

public protocol SinchMetadata {
    // swiftlint:disable:next large_tuple
    func getKeyValue() -> (key: String, value: String, mode: SinchMetadataMode)
}

public enum SinchMetadataMode {
    case once
    case withEachMessage
}

public struct GetChatViewControllerOptions {
    let topicID: String?
    let metadata: [SinchMetadata]
    let shouldInitializeConversation: Bool
    
    public init(topicID: String? = nil, metadata: [SinchMetadata], shouldInitializeConversation: Bool = false) {
        self.topicID = topicID
        self.metadata = metadata
        self.shouldInitializeConversation = shouldInitializeConversation
    }
}

public struct SinchMetadataCustom: SinchMetadata {
    let key: String
    let value: String
    let mode: SinchMetadataMode
    
    public init(key: String, value: String, mode: SinchMetadataMode) {
        self.key = key
        self.value = value
        self.mode = mode
    }
    
    public func getKeyValue() -> (key: String, value: String, mode: SinchMetadataMode) {
        return (key, value, mode)
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
