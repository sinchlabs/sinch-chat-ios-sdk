import UIKit
import Kingfisher
import AVFoundation
final class VideoMessageCell: ImageBaseCell {
    
    static let cellId = "videoMessageCell"
    var message: Message?
    var localizationConfig: SinchSDKConfig.LocalizationConfig?
    
    lazy var playImageView: UIImageView = {
        let imageView = UIImageView()
        imageView.contentMode = .scaleAspectFill
        imageView.backgroundColor = .clear
        imageView.clipsToBounds = true
        imageView.isUserInteractionEnabled = true
        imageView.translatesAutoresizingMaskIntoConstraints = false
        return imageView
    }()
    
    // MARK: - Methods
    
    /// Responsible for setting up the constraints of the cell's subviews.
    func setupConstraints() {
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
      
            playImageView.centerXAnchor.constraint(equalTo: messageContainerView.centerXAnchor),
            playImageView.centerYAnchor.constraint(equalTo: messageContainerView.centerYAnchor),
            playImageView.widthAnchor.constraint(equalToConstant: 32.0),
            playImageView.heightAnchor.constraint(equalToConstant: 32.0),
            
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
        imageView.addSubview(playImageView)
        playImageView.bringSubviewToFront(imageView)
        setupConstraints()
    }
    
    override func apply(_ layoutAttributes: UICollectionViewLayoutAttributes) {
        super.apply(layoutAttributes)
        if let attributes = layoutAttributes as? ChatFlowLayoutAttributes {
            
            dateLabel.messageLabelFont = attributes.dateLabelFont
            dateLabel.textInsets = attributes.dateLabelTextInsets
            dateLabel.frame =  attributes.dateLabelFrame
            imageView.frame = attributes.mediaFrame
        }
    }
       
     func setupTumbnailFromUrl(_ url: URL) {
        let asset = AVAsset(url: url)
        let imageGenerator = AVAssetImageGenerator(asset: asset)
        imageGenerator.appliesPreferredTrackTransform = true
        imageGenerator.maximumSize = CGSize(width: 900.0, height: 900.0)
        let provider = AVAssetImageDataProvider(assetImageGenerator: imageGenerator, time: .zero)
        activityIndicator.startAnimating()
        placeholderLabel.text = ""
        errorImageView.image = nil
        
        self.imageView.setImage(provider: provider) { [weak self] result in
            guard let self = self else {
                return
            }
            self.activityIndicator.stopAnimating()
            
            switch result {
                
            case .success(_):
                self.errorImageView.image = nil
                
            case .failure(_):
                self.errorImageView.image = UIImage(named: "errorIcon",
                                                    in: Bundle.staticBundle, compatibleWith: nil)!
            }
        }
    }
    
    override func configure(with message: Message, at indexPath: IndexPath, and messagesCollectionView: MessageCollectionView) {
        super.configure(with: message, at: indexPath, and: messagesCollectionView)
        self.message = message
        self.localizationConfig =  messagesCollectionView.localizationConfig
        setupContainerView(messagesCollectionView, message)
        setupPlaceholderView(messagesCollectionView, message)

        if let message = message.body as? MessageMedia, let url = URL(string: message.url) {
            setupTumbnailFromUrl(url)
        }

        dateLabel.configure {
            
            if let message = message.body as? MessageMedia,
               let dateInSeconds = message.sendDate {
                dateLabel.text =  Date(timeIntervalSince1970: TimeInterval(dateInSeconds)).getFormattedTime()
            }
        }
        setupDateLabel(messagesCollectionView)
        
        if let dateFont = dateLabel.messageLabelFont {
            dateLabel.font = dateFont
            
        }
    }

    private func setupContainerView(_ messagesCollectionView: MessageCollectionView, _ message: Message) {
        delegate = messagesCollectionView.touchDelegate
        playImageView.image = messagesCollectionView.uiConfig.playVideoImage

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
        
        if let message = message, let mediaMessage = message.body as? MessageMedia,
           let url = URL(string: mediaMessage.url) {
            delegate?.didTapOnVideo(with: url, message: message)
        }
    }
}
