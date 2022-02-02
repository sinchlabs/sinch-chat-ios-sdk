import UIKit

class SinchViewController<T, V: SinchView>: UIViewController {

    let viewModel: T
    let mainView: V
    
    init(viewModel: T, view: V) {
        self.mainView = view
        self.viewModel = viewModel
        super.init(nibName: nil, bundle: nil)
        commonInit()
    }

    override func loadView() {
        self.view = mainView
    }

    @available(*, unavailable, message: "Use init(_:_:)")
    required init?(coder: NSCoder) {
        fatalError()
    }

    func commonInit() {

    }
    
    func setNavigationBarStyle(uiConfig: SinchSDKConfig.UIConfig) {
        
        let textAttributes = [ NSAttributedString.Key.foregroundColor: uiConfig.navigationBarTitleColor,
                               NSAttributedString.Key.font: UIFont.boldSystemFont(ofSize: 16)]
        
        if #available(iOS 13.0, *) {
            let appearance = UINavigationBarAppearance()
            appearance.configureWithOpaqueBackground()
            appearance.backgroundColor = uiConfig.navigationBarColor
            appearance.titleTextAttributes = textAttributes
            navigationController?.navigationBar.standardAppearance = appearance
            navigationController?.navigationBar.scrollEdgeAppearance = appearance
            navigationController?.navigationBar.tintColor = uiConfig.navigationBarTitleColor

        } else {
            navigationController?.navigationBar.barTintColor = uiConfig.navigationBarColor
            navigationController?.navigationBar.tintColor = uiConfig.navigationBarTitleColor
            navigationController?.navigationBar.titleTextAttributes = textAttributes
        }
    }
}
