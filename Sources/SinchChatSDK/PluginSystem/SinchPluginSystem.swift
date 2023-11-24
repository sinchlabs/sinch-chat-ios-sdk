import UIKit
import Combine

public protocol SinchPlugin {
    func initialize(methods: SinchPluginAvailablePluginMethods)
}

public protocol SinchPluginAvailablePluginMethods: AnyObject {
    var eventListenerSubject: PassthroughSubject<SinchPluginEvent, Never> { get }
    
    var customMessageTypeHandlers: [(_ model: Message) -> Message?] { get set }
    
    var additionalMetadata: SinchMetadataArray { get set }
    
    func getAuthorizationToken() -> AuthModel?
    
    func sendMessage(_ message: MessageType, authModel: AuthModel?, chatOptions: SinchChatOptions?, completion: @escaping (Result<String, Error>) -> Void)
    
    func presentViewController(_ viewController: UIViewController, _ animated: Bool, completion: (() -> Void)?)
    
    func startChatWithCurrentConfig()
}

public protocol SinchPluginListener {
    func cancel()
}

public enum SinchPluginEvent {
    case didSetIdentity(AuthModel)
    case didStartChat(chatViewController: UIViewController, chatOptions: SinchChatOptions)
    case didCloseChat
    case didRemoveIdentity

}

public struct SinchChatOptions: Codable, Equatable {
    public var topicID: String?
    public var metadata: SinchMetadataArray?
    public var shouldInitializeConversation: Bool?
    
    public static func == (lhs: SinchChatOptions, rhs: SinchChatOptions) -> Bool {
        lhs.topicID == rhs.topicID &&
        lhs.metadata == rhs.metadata &&
        lhs.shouldInitializeConversation == lhs.shouldInitializeConversation
    }
}
