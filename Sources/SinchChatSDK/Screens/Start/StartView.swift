import UIKit

final class StartView: SinchView {
    
    var uiConfig: SinchSDKConfig.UIConfig
    var messageComposeView: ComposeView
    var collectionView: MessageCollectionView
    let errorView = ErrorView()
    let label = UILabel()
    var errorViewTopConstraint: NSLayoutConstraint?
    
    init(uiConfig: SinchSDKConfig.UIConfig) {
        self.uiConfig = uiConfig
        messageComposeView = ComposeView(configuration: uiConfig)
        collectionView = MessageCollectionView(configuration:uiConfig)
        super.init()
        
    }
    
    override func setupSubviews() {
        backgroundColor = uiConfig.backgroundColor
        collectionView.register(TextMessageCell.self, forCellWithReuseIdentifier: TextMessageCell.cellId)
        collectionView.register(ImageMessageCell.self, forCellWithReuseIdentifier: ImageMessageCell.cellId)
        collectionView.register(EventMessageCell.self, forCellWithReuseIdentifier: EventMessageCell.cellId)
        collectionView.register(DateMessageCell.self, forCellWithReuseIdentifier: DateMessageCell.dateCellId)
        
        collectionView.translatesAutoresizingMaskIntoConstraints = false
        addSubview(collectionView)
        
        errorView.translatesAutoresizingMaskIntoConstraints = false
        addSubview(errorView)
        
    }
    override func setupConstraints() {
        
        errorViewTopConstraint = errorView.topAnchor.constraint(equalTo:  self.safeAreaLayoutGuide.topAnchor, constant: -40)
        let errorViewBottom = errorView.bottomAnchor.constraint(equalTo:  collectionView.topAnchor)
        let errorViewLeading = errorView.leadingAnchor.constraint(equalTo:  safeAreaLayoutGuide.leadingAnchor)
        let errorViewTrailing = errorView.trailingAnchor.constraint(equalTo:  safeAreaLayoutGuide.trailingAnchor)
        let errorViewHeight = errorView.heightAnchor.constraint(equalToConstant: 40)
                
        let top = collectionView.topAnchor.constraint(equalTo: errorView.bottomAnchor)
        let bottom = collectionView.bottomAnchor.constraint(equalTo: bottomAnchor)
        let leading = collectionView.leadingAnchor.constraint(equalTo: safeAreaLayoutGuide.leadingAnchor)
        let trailing = collectionView.trailingAnchor.constraint(equalTo: safeAreaLayoutGuide.trailingAnchor)
        NSLayoutConstraint.activate([top,
                                     bottom,
                                     trailing,
                                     leading,
                                     errorViewBottom,
                                     errorViewLeading,
                                     errorViewTrailing,
                                     errorViewHeight])
        
        guard let errorViewTop = errorViewTopConstraint else {
            return
        }
        
        NSLayoutConstraint.activate([errorViewTop])
        
    }
    
    func setErrorViewState(_ state: InternetConnectionState) {
        
        switch state {
        case .isOn:
            errorView.updateToState(state)
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
            self.errorViewTopConstraint?.constant = -40
            UIView.animate(withDuration: 0.6) {
                self.layoutIfNeeded()
            }
            }
        case .isOff:
            errorView.updateToState(state)
            errorViewTopConstraint?.constant = 0
            UIView.animate(withDuration: 0.6) {
                self.layoutIfNeeded()
            }
        case .notDetermined:
            break
        }
        
    }
}
