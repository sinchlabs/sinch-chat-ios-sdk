// This is required to build project with GRPC generated files.
@_exported import SwiftProtobuf
import UIKit
import Logging
import GRPC

final class RootCoordinator: BaseCoordinator {

    private var messageDataSource: MessageDataSource
    private let pushPermissionHandler: PushNofiticationPermissionHandler
    private let authDataSource: AuthDataSource

    init(navigationController: UINavigationController?,
         messageDataSource: MessageDataSource,
         authDataSource: AuthDataSource,
         pushPermissionHandler: PushNofiticationPermissionHandler) {
        
        self.messageDataSource = messageDataSource
        self.authDataSource = authDataSource
        self.pushPermissionHandler = pushPermissionHandler
        super.init(navigationController: navigationController)
    }
    
    override func start() {
        
    }
    
    func getRootViewController(uiConfig: SinchSDKConfig.UIConfig, localizationConfig: SinchSDKConfig.LocalizationConfig) -> StartViewController {
        let startViewModel: StartViewModel = DefaultStartViewModel(messageDataSource: messageDataSource, notificationPermission: pushPermissionHandler)
        messageDataSource.delegate = startViewModel
        let startViewController = StartViewController(viewModel: startViewModel, view: .init(uiConfiguration: uiConfig, localizationConfiguration: localizationConfig))
        startViewController.cordinator = self
        return startViewController
    }

    func presentMediaViewerController(viewController: UIViewController, uiConfig: SinchSDKConfig.UIConfig, localizationConfig: SinchSDKConfig.LocalizationConfig, mediaMessage: Message) {
        
        let mediaViewController = MediaViewerController(
            viewModel: DefaultMediaViewerViewModel(mediaMessage: mediaMessage),
            view: .init(uiConfiguration: uiConfig, localizationConfiguration: localizationConfig))
        
        let mediaNavigationController = UINavigationController(rootViewController: mediaViewController)
        mediaNavigationController.modalPresentationStyle = .fullScreen
        mediaNavigationController.modalTransitionStyle = .crossDissolve
        viewController.present(mediaNavigationController, animated: true, completion: nil)
        
    }
}
