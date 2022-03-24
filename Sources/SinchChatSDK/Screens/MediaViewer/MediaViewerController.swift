import UIKit

final class MediaViewerController: SinchViewController<MediaViewerViewModel, MediaViewerView> {
    
    override func viewDidLoad() {
        super.viewDidLoad()
        
        self.title = mainView.localizationConfiguration.navigationBarImageViewText
                
        if let body = viewModel.mediaMessage.body as? MessageImage, let url = URL(string: body.url) {
            mainView.imageView.setImage(url: url)

        } else if let body = viewModel.mediaMessage.body as? MessageMediaText, let url = URL(string: body.url) {
            mainView.imageView.setImage(url: url)

        } else if let body = viewModel.mediaMessage.body as? MessageCard, let url = URL(string: body.url) {
            mainView.imageView.setImage(url: url)

        }
        
        let swipeDown = UISwipeGestureRecognizer(target: self, action: #selector(respondToSwipeGesture))
            swipeDown.direction = .down
            self.view.addGestureRecognizer(swipeDown)
        
    }
    
    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        
        setNavigationBarStyle(uiConfig: mainView.uiConfig)
        
        addCloseButton()
    }
    @objc func respondToSwipeGesture(gesture: UIGestureRecognizer) {

        if let swipeGesture = gesture as? UISwipeGestureRecognizer {

            switch swipeGesture.direction {
            case .right:
                print("Swiped right")
            case .down:
                closeAction()
            case .left:
                print("Swiped left")
            case .up:
                print("Swiped up")
            default:
                break
            }
        }
    }
    
    private func addCloseButton() {
        let closeImage = UIImage(named: "backArrowIcon",
                                 in: Bundle.staticBundle,
                                 compatibleWith: nil)?.withRenderingMode(.alwaysOriginal)
        navigationItem.leftBarButtonItem = UIBarButtonItem(image: closeImage,
                                                           style: .plain,
                                                           target: self,
                                                           action: #selector(closeAction))
    }
    
    @objc private func closeAction() {
        self.dismiss(animated: true, completion: nil)
    }
}
