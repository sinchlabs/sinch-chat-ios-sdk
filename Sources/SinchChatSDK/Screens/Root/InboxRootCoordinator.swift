@MainActor
protocol InboxRootCoordinator: AnyObject {
    var uiConfiguration: SinchSDKConfig.UIConfig { get }
    var localizationConfiguration: SinchSDKConfig.LocalizationConfig { get }
    var inboxDataSource: InboxDataSource { get }

    func getRootViewController(apiClient: APIClient, options: GetChatViewControllerOptions?) -> InboxViewController

    /// Wraps the list in the adaptive inbox: sidebar and chat on regular width, list pushing the chat on compact.
    func getAdaptiveRootViewController(inbox: InboxViewController) -> InboxContainerViewController

}

@MainActor
final class DefaultInboxRootCoordinator: InboxRootCoordinator {
    
    var uiConfiguration: SinchSDKConfig.UIConfig
    var localizationConfiguration: SinchSDKConfig.LocalizationConfig
    var inboxDataSource: InboxDataSource

    private let pushPermissionHandler: PushNofiticationPermissionHandler
    private let tokenProvider: ChatTokenProvider

    init(uiConfiguration: SinchSDKConfig.UIConfig,
         localizationConfiguration: SinchSDKConfig.LocalizationConfig,
         tokenProvider: ChatTokenProvider,
         pushPermissionHandler: PushNofiticationPermissionHandler,
         inboxDataSource: InboxDataSource) {
        
        self.uiConfiguration = uiConfiguration
        self.localizationConfiguration = localizationConfiguration
        self.inboxDataSource = inboxDataSource
        self.tokenProvider = tokenProvider
        self.pushPermissionHandler = pushPermissionHandler
    }
    
    func getRootViewController(apiClient: APIClient, options: GetChatViewControllerOptions? = nil) -> InboxViewController {
        
        let inboxViewModel = DefaultInboxViewModel(pushPermissionHandler: pushPermissionHandler, apiClient: apiClient, tokenProvider: tokenProvider)
        let inboxView = InboxView(uiConfiguration: uiConfiguration, localizationConfiguration: localizationConfiguration)
        
        let inboxViewController = InboxViewController(viewModel: inboxViewModel, view: inboxView)
        
        if let options = options {
            inboxViewController.customOptions = options
        }

        return inboxViewController
    }

    func getAdaptiveRootViewController(inbox: InboxViewController) -> InboxContainerViewController {
        InboxContainerViewController(splitController: InboxSplitViewController(inbox: inbox))
    }
}
