import UIKit
protocol MessageStatusDelegate: AnyObject {
    func retryTapped()
    
}
final class MessageStatusView: SinchView {
    
    var messageStatus: MessageStatus = .notSent
    weak var delegate: MessageStatusDelegate?
    
    lazy var stackView: UIStackView = {
        let stackView = UIStackView()
        stackView.distribution = .fill
        stackView.translatesAutoresizingMaskIntoConstraints = false
        stackView.alignment = .fill
        stackView.axis = .horizontal
        stackView.spacing = 4
        
        return stackView
    }()
    lazy var retryStatusImageView: UIImageView = {
        let imageView = UIImageView()
        imageView.contentMode = .scaleAspectFit
        imageView.backgroundColor = .clear
        imageView.clipsToBounds = true
        return imageView
    }()
    lazy var statusImageView: UIImageView = {
        let imageView = UIImageView()
        imageView.contentMode = .scaleAspectFit
        imageView.backgroundColor = .clear
        imageView.clipsToBounds = true
        return imageView
    }()
    lazy var statusLabel: UILabel =  {
        var label = UILabel()
        label.textColor = uiConfig.outgoingMessageTextColor
        label.textAlignment = .right
        label.font = UIFont.preferredFont(forTextStyle: .caption2)
        label.translatesAutoresizingMaskIntoConstraints = false
        return label
    }()
    
    override func setupSubviews() {
        
        let labelTap = UITapGestureRecognizer(target: self, action: #selector(self.retryAction(_:)))
        statusLabel.isUserInteractionEnabled = true
        statusLabel.addGestureRecognizer(labelTap)
        let imageTap = UITapGestureRecognizer(target: self, action: #selector(self.retryAction(_:)))
        retryStatusImageView.isUserInteractionEnabled = true
        retryStatusImageView.addGestureRecognizer(imageTap)
        
        stackView.addArrangedSubview(retryStatusImageView)
        stackView.addArrangedSubview(statusLabel)
        stackView.addArrangedSubview(statusImageView)
        
        addSubview(stackView)
        
    }
    @objc func retryAction(_ sender: AnyObject) {
        delegate?.retryTapped()
    }
    override func setupConstraints() {
        
        let stackViewLeft = stackView.leadingAnchor.constraint(equalTo: leadingAnchor)
        let stackViewRight = stackView.centerYAnchor.constraint(equalTo: centerYAnchor)
        let stackViewTop = stackView.topAnchor.constraint(equalTo: topAnchor)
        let stackViewBottom = stackView.bottomAnchor.constraint(equalTo: bottomAnchor)
        
        let statusImageHeight = statusImageView.heightAnchor.constraint(equalToConstant: 10.0)
        let statusImageWidth = statusImageView.widthAnchor.constraint(equalToConstant: 14.0)
        let statusButtonHeight = retryStatusImageView.heightAnchor.constraint(equalToConstant: 10.0)
        let statusButtonWidth = retryStatusImageView.widthAnchor.constraint(equalToConstant: 10.0)
        
        NSLayoutConstraint.activate([
            stackViewLeft,
            stackViewRight,
            stackViewTop,
            stackViewBottom,
            statusImageHeight,
            statusImageWidth,
            statusButtonHeight,
            statusButtonWidth
        ])
    }
    
    func setupStatusView(_ status: MessageStatus, in messagesCollectionView: MessageCollectionView) {
        
        statusLabel.text = status.localizedDescription(localizedConfig: messagesCollectionView.localizationConfig)
        statusImageView.image = status.localizedImage(uiConfig: messagesCollectionView.uiConfig)
        retryStatusImageView.image = messagesCollectionView.uiConfig.refreshStatusImage
        switch status {
            
        case .delivered:
            statusImageView.isHidden = false
            retryStatusImageView.isHidden = true
        case .notSent:
            statusImageView.isHidden = true
            retryStatusImageView.isHidden = false
        case .sending:
            statusImageView.isHidden = true
            retryStatusImageView.isHidden = true
        case .sent:
            statusImageView.isHidden = false
            retryStatusImageView.isHidden = true
        case .seen:
            statusImageView.isHidden = false
            retryStatusImageView.isHidden = true
        }
    }
}
