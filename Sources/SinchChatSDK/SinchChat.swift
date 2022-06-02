import UIKit

public protocol SinchChat {
    
    /// Checks if chat can be opened.
    /// - Returns: Current Chat availability.
    func isChatAvailable() -> SinchSDKChatAvailability
    
    /// Creating Chat UI. This method may throw
    /// - Parameters:
    ///    - navigationController: Optional UINavigationController
    ///   - uiConfig: Optionally ui changes might be provided with different settings.
    ///   - localizationConfig: Optionally localization might be provided with different text translation.
    /// - Returns: UIViewController which contains chat UI.
    /// - Throws: SinchChatSDKError enum with specific error.
    func getChatViewController(navigationController: UINavigationController?,
                               uiConfig: SinchSDKConfig.UIConfig?,
                               localizationConfig: SinchSDKConfig.LocalizationConfig?) throws -> UIViewController
    
    /// Sets metadata for single conversation. This methods overrides previous metadata.
    /// - Parameters:
    ///    - metadata: Keys with values.
    func setConversationMetadata(_ metadata: [SinchMetadata]) throws
}

public extension SinchChat {
    
    func getChatViewController(navigationController: UINavigationController? = nil,
                               uiConfig: SinchSDKConfig.UIConfig? = nil,
                               localizationConfig: SinchSDKConfig.LocalizationConfig? = nil) throws -> UIViewController {
        try getChatViewController(navigationController:navigationController, uiConfig: uiConfig, localizationConfig: localizationConfig)
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
    
    public func getChatViewController(navigationController: UINavigationController?,
                                      uiConfig: SinchSDKConfig.UIConfig? = nil,
                                      localizationConfig: SinchSDKConfig.LocalizationConfig? = nil) throws -> UIViewController {
        
        guard isChatAvailable() == .available, let authDataSource = authDataSource, let region = region else {
            throw SinchChatSDKError.unavailable
        }
        guard let client = DefaultAPIClient(region: region) else {
            throw SinchChatSDKError.unavailable
        }
                
        apiClient = client
        let messageDataSource = DefaultMessageDataSource(apiClient: apiClient!,
                                                         authDataSource: authDataSource)
        let rootCordinator = RootCoordinator(navigationController: navigationController,
                                             messageDataSource: messageDataSource,
                                             authDataSource: authDataSource,
                                             pushPermissionHandler: pushPermissionHandler)
        
        self.rootCordinator = rootCordinator
        let uiConfig = uiConfig ?? SinchSDKConfig.UIConfig.defaultValue
        let locConfig = localizationConfig ?? SinchSDKConfig.LocalizationConfig.defaultValue

        let startViewController =  rootCordinator.getRootViewController(uiConfig: uiConfig, localizationConfig: locConfig )
        if navigationController == nil {
            let navigationController = UINavigationController(rootViewController: startViewController)
            
            return navigationController
            
        } else {
            return startViewController
            
        }
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
                                                         authDataSource: authDataSource)
        
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
    func getKeyValue() -> (key: String, value: String)
}

public struct SinchMetadataCustom: SinchMetadata {
    let key: String
    let value: String
    
    public init(key: String, value: String) {
        self.key = key
        self.value = value
    }
    
    public func getKeyValue() -> (key: String, value: String) {
        return (key, value)
    }
}

public struct SinchMetadataEmail: SinchMetadata {
    private let key: String = "email"
    private let value: String
    
    public init(value: String) {
        self.value = value
    }
    
    public func getKeyValue() -> (key: String, value: String) {
        return (key, value)
    }
}

public struct SinchMetadataPhoneNumber: SinchMetadata {
    private let key: String = "phone"
    private let value: String

    public init(value: String) {
        self.value = value
    }
    
    public func getKeyValue() -> (key: String, value: String) {
        return (key, value)
    }
}
