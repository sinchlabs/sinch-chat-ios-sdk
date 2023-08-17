import UIKit
//TODO

open class SinchViewController<T, V: SinchView>: UIViewController {

    public let viewModel: T
    public let mainView: V
    
    public init(viewModel: T, view: V) {
        self.mainView = view
        self.viewModel = viewModel
        super.init(nibName: nil, bundle: nil)
        commonInit()
    }

    public override func loadView() {
        self.view = mainView
    }

    @available(*, unavailable, message: "Use init(_:_:)")
    public required init?(coder: NSCoder) {
        fatalError()
    }

    public func commonInit() {

    }
    
    func setNavigationBarStyle(uiConfig: SinchSDKConfig.UIConfig) {
        
        let textAttributes = [ NSAttributedString.Key.foregroundColor: uiConfig.navigationBarTitleColor,
                               NSAttributedString.Key.font: UIFont.boldSystemFont(ofSize: 16)]
        
        if #available(iOS 13.0, *) {
            let appearance = UINavigationBarAppearance()
            appearance.configureWithOpaqueBackground()
            appearance.backgroundColor = uiConfig.navigationBarColor
            appearance.titleTextAttributes = textAttributes
            
            navigationItem.standardAppearance = appearance
            navigationItem.scrollEdgeAppearance = appearance
            navigationController?.navigationBar.tintColor = uiConfig.navigationBarTitleColor

        } else {
            navigationController?.navigationBar.barTintColor = uiConfig.navigationBarColor
            navigationController?.navigationBar.tintColor = uiConfig.navigationBarTitleColor
            navigationController?.navigationBar.titleTextAttributes = textAttributes
        }
    }
    func addCloseButton() {
        let closeImage = UIImage(named: "backArrowIcon",
                                 in: Bundle.staticBundle,
                                 compatibleWith: nil)?.withRenderingMode(.alwaysOriginal)
        navigationItem.leftBarButtonItem = UIBarButtonItem(image: closeImage,
                                                           style: .plain,
                                                           target: self,
                                                           action: #selector(closeAction))
    }
    
    @objc func closeAction() {
        self.dismiss(animated: true, completion: nil)
    }
}
