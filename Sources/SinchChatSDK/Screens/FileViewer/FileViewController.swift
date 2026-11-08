import UIKit

class FileViewController: SinchViewController <FileViewerViewModel, FileViewerView> {
        
    override func viewDidLoad() {
        super.viewDidLoad()
        
        self.title = mainView.localizationConfiguration.navigationBarImageViewText
        mainView.webview.load(URLRequest(url: viewModel.url))
    }
    
    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        
        setNavigationBarStyle(uiConfig: mainView.uiConfig)
        
        addCloseButton()
        addShareButton()
    }
    private(set) var shareBarButtonItem: UIBarButtonItem?

    func addShareButton() {
        let shareButton = UIBarButtonItem(barButtonSystemItem: .action, target: self, action: #selector(shareButtonPressed))

        shareBarButtonItem = shareButton
        navigationItem.leftBarButtonItem = shareButton
    }
    
    @objc func shareButtonPressed() {
        
        let vc = UIActivityViewController(activityItems: [viewModel.url], applicationActivities: [])
        // The share button is the left bar button item; anchoring to the right one left the popover without a source.
        PopoverPresentation.anchor(vc, to: shareBarButtonItem ?? navigationItem.leftBarButtonItem, fallbackView: view)
        present(vc, animated: true)
        
    }
}
