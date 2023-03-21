// This is required to build project with GRPC generated files.
@_exported import SwiftProtobuf
import UIKit
import Logging
import GRPC
import CoreLocation

final class RootCoordinator: BaseCoordinator {
    
    private var messageDataSource: MessageDataSource
    private let pushPermissionHandler: PushNofiticationPermissionHandler
    private let authDataSource: AuthDataSource
    lazy var locationManager = CLLocationManager()

    init(messageDataSource: MessageDataSource,
         authDataSource: AuthDataSource,
         pushPermissionHandler: PushNofiticationPermissionHandler) {
        
        self.messageDataSource = messageDataSource
        self.authDataSource = authDataSource
        self.pushPermissionHandler = pushPermissionHandler
        super.init()
    }
    
    override func start() {
        
    }
    
    func getRootViewController(uiConfig: SinchSDKConfig.UIConfig, localizationConfig: SinchSDKConfig.LocalizationConfig) -> SinchChatViewController {
        let startViewModel: StartViewModel = DefaultStartViewModel(messageDataSource: messageDataSource, notificationPermission: pushPermissionHandler)
        messageDataSource.delegate = startViewModel
        let startViewController = StartViewController(viewModel: startViewModel, view: .init(uiConfiguration: uiConfig, localizationConfiguration: localizationConfig))
        startViewController.cordinator = self
        return startViewController
    }
    
    func presentMediaViewerController(viewController: UIViewController,
                                      uiConfig: SinchSDKConfig.UIConfig,
                                      localizationConfig: SinchSDKConfig.LocalizationConfig, url: URL) {
        
        let mediaViewController = MediaViewerController(
            viewModel: DefaultMediaViewerViewModel(url: url),
            view: .init(uiConfiguration: uiConfig, localizationConfiguration: localizationConfig))
        
        let mediaNavigationController = UINavigationController(rootViewController: mediaViewController)
        mediaNavigationController.modalPresentationStyle = .fullScreen
        mediaNavigationController.modalTransitionStyle = .crossDissolve
        viewController.present(mediaNavigationController, animated: true, completion: nil)
        
    }
    func presentLocation(viewController: StartViewController,
                         uiConfig: SinchSDKConfig.UIConfig,
                         localizationConfig: SinchSDKConfig.LocalizationConfig) {
        
        let locationViewController = LocationViewController(
            viewModel: DefaultLocationViewModel(),
            view: .init(uiConfiguration: uiConfig, localizationConfiguration: localizationConfig))
        locationViewController.delegate = viewController
        locationViewController.locationManager = locationManager
        locationViewController.modalPresentationStyle = .fullScreen
        locationViewController.modalTransitionStyle = .crossDissolve
        viewController.present(locationViewController, animated: true, completion: nil)
        
    }
}
