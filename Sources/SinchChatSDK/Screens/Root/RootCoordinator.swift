// This is required to build project with GRPC generated files.
@_exported import SwiftProtobuf
import UIKit
import Logging
import GRPC
import CoreLocation
import QuickLook

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
    func presentDocumentViewerController(viewController: StartViewController, cell: UICollectionViewCell,
                                      uiConfig: SinchSDKConfig.UIConfig,
                                      localizationConfig: SinchSDKConfig.LocalizationConfig, url: URL) {
        
        let quickLookViewController = PreviewViewController()
        quickLookViewController.uiConfig = uiConfig
        quickLookViewController.localizationConfiguration = localizationConfig
        quickLookViewController.dataSource = viewController
        quickLookViewController.delegate = viewController
       

        if let cell = cell as? FileMessageCell,
           var message = cell.message, var messageBody = message.body as? MessageMedia, let fileURL = messageBody.savedUrl {
            var indexOfFile = 0
            for (index, file) in viewController.fileURLs.enumerated() where file == fileURL {
                indexOfFile = index
                break
            }
            
            quickLookViewController.currentPreviewItemIndex = indexOfFile
            viewController.navigationItem.backBarButtonItem = UIBarButtonItem(title: "", style: .plain, target: nil, action: nil)

            viewController.navigationController?.pushViewController(quickLookViewController, animated: true)
        } else {
            
            let downloadTask = URLSession.shared.downloadTask(with: url) { urlOrNil, responseOrNil, errorOrNil in
                
                guard let fileURL = urlOrNil else { return }
                do {
                    let fileName = responseOrNil?.suggestedFilename ?? responseOrNil?.url?.lastPathComponent ?? fileURL.lastPathComponent

                    let documentsURL = try
                    FileManager.default.url(for: .documentDirectory,
                                            in: .userDomainMask,
                                            appropriateFor: nil,
                                            create: false)
                    let savedURL = documentsURL.appendingPathComponent(fileName)
                    
                    if !FileManager().fileExists(atPath: savedURL.relativePath) {
                        try FileManager.default.moveItem(at: fileURL, to: savedURL)
                    }
                    viewController.fileURLs.append(savedURL.absoluteString)

                    if let cell = cell as? FileMessageCell, var message = cell.message, var messageBody = message.body as? MessageMedia {
                        messageBody.savedUrl = savedURL.absoluteString
                        message.body = messageBody
                        
                        for (index, messageInArray) in viewController.messages.reversed().enumerated() where message.entryId == messageInArray.entryId {
                                
                            viewController.messages[viewController.messages.count - 1 - index] = message
                                DispatchQueue.main.async {
                                    UIView.performWithoutAnimation {
                                        
                                        viewController.mainView.collectionView.reloadSections([viewController.messages.count - 1 - index])
                                    }
                                }
                                break
                        }
                        DispatchQueue.main.async {
                         
                            quickLookViewController.currentPreviewItemIndex =  viewController.fileURLs.count - 1
                            viewController.navigationItem.backBarButtonItem = UIBarButtonItem(title: "", style: .plain, target: nil, action: nil)
                            viewController.navigationController?.pushViewController(quickLookViewController, animated: true)
                        }
                    }
                } catch {
                    print ("file error: \(error)")
                }
            }
            downloadTask.resume()
            
        }
    
//
//        let fileViewController = FileViewController(
//            viewModel: DefaultFileViewerViewModel(url: url),
//            view: .init(uiConfiguration: uiConfig, localizationConfiguration: localizationConfig))
//
//        let fileNavigationController = UINavigationController(rootViewController: fileViewController)
//        fileNavigationController.modalPresentationStyle = .fullScreen
//        fileNavigationController.modalTransitionStyle = .crossDissolve
//        viewController.present(fileNavigationController, animated: true, completion: nil)
        
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
