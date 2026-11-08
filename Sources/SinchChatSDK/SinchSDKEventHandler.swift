import UIKit

extension SinchChatSDK: SinchPluginAvailablePluginMethods {
    
    public func getAuthorizationToken() -> AuthModel? {
        _chat.tokenProvider?.currentAuthorization
    }
    
    // If AuthModel is nil then we will use current AuthModel.
    public func sendMessage(_ message: MessageType, authModel: AuthModel?, chatOptions: SinchChatOptions?, completion: @escaping @Sendable (Result<String, Error>) -> Void) {
                
        guard let client = apiClient ?? Default2APIClient(region: region ?? .EU1),
              let tokenProvider = tokenProvider else {
            completion(.failure(SinchChatSDKError.unavailable))
            return
        }
        
        var topicModel: TopicModel?
        if let topicID = chatOptions?.topicID {
            topicModel = TopicModel(topicID: topicID)
        }
        
        let messageDataSource = DefaultMessageDataSource(
            apiClient: client,
            tokenProvider: tokenProvider,
            topicModel: topicModel,
            metadata: chatOptions?.metadata ?? [],
            shouldInitializeConversation: chatOptions?.shouldInitializeConversation ?? false,
            sendDocumentAsText: chatOptions?.sendDocumentAsText ?? false
        )
        
        messageDataSource.sendMessage(message) { result in
            switch result {
            case .failure(let error):
                completion(.failure(error))
            case .success(let payload):
                completion(.success(payload))
            }
        }
    }
    
    public func presentViewController(_ viewController: UIViewController, _ animated: Bool, completion: (@Sendable () -> Void)?) {
        // Plugins may call from a background queue; presenting must happen on main.
        guard Thread.isMainThread else {
            nonisolated(unsafe) let viewController = viewController
            DispatchQueue.main.async { self.presentViewController(viewController, animated, completion: completion) }
            return
        }
        getTopViewController()?.present(viewController, animated: animated, completion: {
            completion?()
        })
    }
    
    public func startChatWithCurrentConfig() {
        guard Thread.isMainThread else {
            DispatchQueue.main.async { self.startChatWithCurrentConfig() }
            return
        }
        guard config != nil,
              let chatVC = try? _chat.getChatViewController() else {
            return
        }
        
        let navigationController = UINavigationController(rootViewController: chatVC)
        
        getTopViewController()?.present(navigationController, animated: true)
    }
    
    /// Callers have checked `Thread.isMainThread`.
    private func getTopViewController() -> UIViewController? {
        // Scene-aware, so it finds the right window on iPad with several windows or scenes.
        MainActor.assumeIsolated { WindowHelper.visibleController() }
    }
}
