import UIKit

final class ImageMessageCell: MessageContentCell {
    
    static let cellId = "imageMessageCell"
    
    /// The image view display the media content.
    var imageView: UIImageView = {
        let imageView = UIImageView()
        imageView.contentMode = .scaleAspectFill
        imageView.backgroundColor = .clear
        imageView.translatesAutoresizingMaskIntoConstraints = false
        return imageView
    }()
    var placeholderLabel: UILabel = {
        let label = UILabel()
        label.font = UIFont.boldSystemFont(ofSize: 10)
        label.textAlignment = .center
        label.translatesAutoresizingMaskIntoConstraints = false
        label.numberOfLines = 0
        
        return label
    }()
    var placeholderImageView: UIImageView = {
        let imageView = UIImageView()
        imageView.contentMode = .scaleAspectFill
        imageView.translatesAutoresizingMaskIntoConstraints = false
        
        return imageView
    }()
    var errorImageView: UIImageView = {
        let imageView = UIImageView()
        imageView.contentMode = .scaleAspectFill
        imageView.translatesAutoresizingMaskIntoConstraints = false
        
        return imageView
    }()
    
    var activityIndicator: UIActivityIndicatorView = {
        let activityIndicatorView: UIActivityIndicatorView
        
        if #available(iOS 13.0, *) {
            activityIndicatorView = UIActivityIndicatorView(style: .medium)
        } else {
            activityIndicatorView = UIActivityIndicatorView(style: .gray)
        }
        activityIndicatorView.hidesWhenStopped = true
        activityIndicatorView.translatesAutoresizingMaskIntoConstraints = false
        
        return activityIndicatorView
    }()
    var dateLabel = MessageLabel()
    var error: Bool?
    
    // MARK: - Methods
    
    /// Responsible for setting up the constraints of the cell's subviews.
    func setupConstraints() {
        imageView.fillSuperview()
        NSLayoutConstraint.activate([
            placeholderImageView.widthAnchor.constraint(equalToConstant: 123.29),
            placeholderImageView.heightAnchor.constraint(equalToConstant: 79.13),
            placeholderImageView.topAnchor.constraint(equalTo: messageContainerView.topAnchor, constant: 31),
            placeholderImageView.centerXAnchor.constraint(equalTo: messageContainerView.centerXAnchor),
            placeholderLabel.centerXAnchor.constraint(equalTo: messageContainerView.centerXAnchor),
            placeholderLabel.leadingAnchor.constraint(equalTo: messageContainerView.leadingAnchor, constant: 20),
            placeholderLabel.trailingAnchor.constraint(equalTo: messageContainerView.trailingAnchor, constant: -20),
            placeholderLabel.topAnchor.constraint(equalTo: placeholderImageView.bottomAnchor, constant: 13),
            placeholderLabel.heightAnchor.constraint(equalToConstant: 30.0),
            
            errorImageView.widthAnchor.constraint(equalToConstant: 20.0),
            errorImageView.heightAnchor.constraint(equalToConstant: 20.0),
            errorImageView.leadingAnchor.constraint(equalTo: messageContainerView.leadingAnchor, constant: 10),
            errorImageView.topAnchor.constraint(equalTo: messageContainerView.topAnchor, constant: 10),
            activityIndicator.centerXAnchor.constraint(equalTo: errorImageView.centerXAnchor),
            activityIndicator.centerYAnchor.constraint(equalTo: errorImageView.centerYAnchor)
            
        ])
    }
    
    override func setupSubviews() {
        super.setupSubviews()
        messageContainerView.addSubview(placeholderImageView)
        messageContainerView.addSubview(placeholderLabel)
        messageContainerView.addSubview(errorImageView)
        messageContainerView.addSubview(imageView)
        messageContainerView.addSubview(activityIndicator)
        
        imageView.addSubview(dateLabel)
        
        setupConstraints()
    }
    
    override func apply(_ layoutAttributes: UICollectionViewLayoutAttributes) {
        super.apply(layoutAttributes)
        if let attributes = layoutAttributes as? ChatFlowLayoutAttributes {
            
            dateLabel.messageLabelFont = attributes.dateLabelFont
            dateLabel.textInsets = attributes.dateLabelTextInsets
            dateLabel.frame =  attributes.dateLabelFrame
        }
    }
    override func prepareForReuse() {
        super.prepareForReuse()
        imageView.image = nil
        dateLabel.text = nil
        placeholderLabel.text = NSLocalizedString("label_trying_download", bundle: Bundle.staticBundle, comment: "")
        errorImageView.image = nil
        activityIndicator.stopAnimating()
        error = false
    }
    
    override func configure(with message: Message, at indexPath: IndexPath, and messagesCollectionView: MessageCollectionView) {
        super.configure(with: message, at: indexPath, and: messagesCollectionView)
        setupContainerView(messagesCollectionView, message)
        setupPlaceholderView(messagesCollectionView, message)
        
        setupImageView(message: message)
        
        dateLabel.configure {
            
            if let message = message.body as? MessageImage,
               let dateInSeconds = message.sendDate {
                dateLabel.text =  Date(timeIntervalSince1970: TimeInterval(dateInSeconds)).getFormattedTime()
            }
        }
        dateLabel.textColor = .white
        dateLabel.layer.cornerRadius = 10.0
        dateLabel.layer.masksToBounds = true
        
        dateLabel.backgroundColor = UIColor(named: "primaryDateMediaBackgroundColor",
                                            in: Bundle.staticBundle, compatibleWith: nil)!
        
        if let dateFont = dateLabel.messageLabelFont {
            dateLabel.font = dateFont
            
        }
    }
    
    func setupImageView(message: Message) {
        
        if let body = message.body as? MessageImage {
            
            if let url = URL(string: body.url) {
                activityIndicator.startAnimating()
                placeholderLabel.text = NSLocalizedString("label_trying_download",
                                                          bundle: Bundle.staticBundle,
                                                          comment: "")
                errorImageView.image = nil

                imageView.setImage(url: url) { [weak self] result in
                    guard let self = self else {
                        return
                    }
                    self.activityIndicator.stopAnimating()
                    
                    switch result {
                        
                    case .success(_):
                        self.placeholderLabel.text = ""
                        self.errorImageView.image = nil
                        
                    case .failure(_):
                        self.placeholderLabel.text = NSLocalizedString("label_download_failed",
                                                                       bundle: Bundle.staticBundle,
                                                                       comment: "")
                        self.errorImageView.image = UIImage(named: "errorIcon",
                                                            in: Bundle.staticBundle, compatibleWith: nil)!
                        self.error = true
                    }
                }
            }
        }
    }
    private func setupPlaceholderView(_ messagesCollectionView: MessageCollectionView, _ message: Message) {
        
        placeholderLabel.textColor = messagesCollectionView.uiConfig.incomingMessageTextColor
        if message.isFromCurrentUser() {
            placeholderImageView.image = UIImage(named: "photoPlaceholderIncoming",
                                                 in: Bundle.staticBundle, compatibleWith: nil)!
            
        } else {
            placeholderImageView.image = UIImage(named: "photoPlaceholderOutgoing",
                                                 in: Bundle.staticBundle, compatibleWith: nil)!
        }
    }
    private func setupContainerView(_ messagesCollectionView: MessageCollectionView, _ message: Message) {
        delegate = messagesCollectionView.touchDelegate
        
        if message.isFromCurrentUser() {
            messageContainerView.backgroundColor = messagesCollectionView.uiConfig.outgoingMessageBackgroundColor
            
        } else {
            messageContainerView.backgroundColor = messagesCollectionView.uiConfig.incomingMessageBackgroundColor
            avatarView.updateWithModel(message, uiConfig: messagesCollectionView.uiConfig)
        }
    }
    
    /// Handle tap gesture on contentView and its subviews.
    override func handleTapGesture(_ gesture: UIGestureRecognizer) {
        let touchLocation = gesture.location(in: imageView)
        
        guard imageView.frame.contains(touchLocation) else {
            delegate?.didTapOutsideOfContent(in: self)
            return
        }
        if !activityIndicator.isAnimating {
            delegate?.didTapImage(in: self)
        }
    }
}
