import UIKit

final class CarouselMessageSizeCalculator: CardMessageSizeCalculator {
    
    public var carouselButtonInsets = UIEdgeInsets(top: 8, left: 8, bottom: 8, right: 8)
    public var pageControlHeight = 8.0

    override init(layout: ChatFlowLayout? = nil) {
        super.init(layout: layout)
        mediaHeight = 230.0
    }
    func titleLabelSize(for message: Message, cardMessage: MessageCard) -> CGSize {
        let maxWidth = messageContainerMaxWidth(for: message)
        
        var titleLabelSize: CGSize = .zero
        let attributedText: NSAttributedString
        let text = cardMessage.title
        
        attributedText = NSAttributedString(string: text, attributes: [.font: titleLabelFont])
        titleLabelSize = labelSize(for: attributedText, considering: maxWidth - titleLabelInsets.right - titleLabelInsets.left)
        titleLabelSize.height += (titleLabelInsets.top + titleLabelInsets.bottom)
        titleLabelSize.width += (titleLabelInsets.right + titleLabelInsets.left)
        return titleLabelSize
    }
    func messageLabelSize(for message: Message, cardMessage: MessageCard) -> CGSize {
        let maxWidth = messageContainerMaxWidth(for: message)
        
        var messageLabelSize: CGSize = .zero
        let attributedText: NSAttributedString
        let text = cardMessage.description
        
        attributedText = NSAttributedString(string: text, attributes: [.font: messageLabelFont])
        messageLabelSize = labelSize(for: attributedText, considering: maxWidth - messageLabelInsets.right - messageLabelInsets.left)
        messageLabelSize.height += (messageLabelInsets.top + messageLabelInsets.bottom)
        messageLabelSize.width += (messageLabelInsets.right + messageLabelInsets.left)
        return messageLabelSize
    }
    
    override func messageContainerSize(for message: Message) -> CGSize {
        
        var messageContainerSize: CGSize = .zero
        let dateLabelSize = dateLabelSize(for: message)
        
        var numberOfCarouselChoices = 0
        var maxTextHeight = 0.0
        var maxNumberOfChoices = 0
        
        if let carouselMessage = message.body as? MessageCarousel {
            numberOfCarouselChoices = carouselMessage.choices.count
            
            for card in carouselMessage.cards {
                let messageLabelSize: CGSize = messageLabelSize(for: message, cardMessage: card)
                let titleLabelSize: CGSize = titleLabelSize(for: message, cardMessage: card)
                let textSize = titleLabelSize.height + messageLabelSize.height
                if maxTextHeight < textSize {
                    maxTextHeight = textSize
                }
                
                if maxNumberOfChoices < card.choices.count {
                    maxNumberOfChoices = card.choices.count
                }
            }
        }
        
        messageContainerSize.height = mediaHeight + maxTextHeight + buttonInsets.top
        + Double(maxNumberOfChoices) * (buttonHeight + buttonInsets.bottom) + (numberOfCarouselChoices == 0 ? 2 : 3) * buttonInsets.top
        + Double(numberOfCarouselChoices) * (buttonHeight + buttonInsets.bottom) +
        dateLabelSize.height + dateLabelInsets.top + dateLabelInsets.bottom
        
        messageContainerSize.width = messageContainerMaxWidth(for: message)
        
        return messageContainerSize
    }
    private func adjustCardsHeightAndButtonsPosition(_ frames: [CardAttributes], _ maxCardHeight: Double, _ firstButtonMaxYPosition: Double) -> [CardAttributes] {
        
        var cardFrames: [CardAttributes] = []
        for cardAttribute in frames {
            var attribute = cardAttribute
            attribute.frame.size.height = maxCardHeight
            
            var buttonFrames: [CGRect] = []
            for buttonFrame in attribute.buttonFrames {
                var newButtonFrame = buttonFrame
                newButtonFrame.origin.y =  buttonFrame.origin.y + firstButtonMaxYPosition
                buttonFrames.append(newButtonFrame)
            }
            attribute.buttonFrames = buttonFrames
            cardFrames.append(attribute)
        }
        return cardFrames
    }
    
    func cardFrames(for message: Message, messageContainerSize: CGSize) -> [CardAttributes] {
        
        var frames: [CardAttributes] = []
        var cardFrames: [CardAttributes] = []
        
        var numberOfCards = 0
        var firstButtonMaxYPosition = 0.0
        var maxCardHeight = 0.0
        
        if let carouselMessage = message.body as? MessageCarousel {
            numberOfCards = carouselMessage.cards.count
            
            for (index, card) in carouselMessage.cards.enumerated() {
                var cardRect: CGRect = .zero
                let mediaFrame = CGRect(x:  0,
                                        y: 0,
                                        width: messageContainerSize.width,
                                        height: mediaHeight)
                
                let messageLabelSize: CGSize = messageLabelSize(for: message, cardMessage: card)
                let titleLabelSize: CGSize = titleLabelSize(for: message, cardMessage: card)
                let buttonYPosition = mediaFrame.size.height + titleLabelSize.height + messageLabelSize.height
                
                if firstButtonMaxYPosition < buttonYPosition {
                    firstButtonMaxYPosition = buttonYPosition
                }
                
                cardRect.origin.x = CGFloat(index) * messageContainerSize.width
                cardRect.size.height = mediaHeight + titleLabelSize.height + messageLabelSize.height + buttonInsets.top
                + Double(card.choices.count) * (buttonHeight + buttonInsets.bottom)
                cardRect.size.width = messageContainerSize.width
                
                if maxCardHeight < cardRect.size.height {
                    maxCardHeight = cardRect.size.height
                }
                
                let dataSource = messagesLayout.chatDataSource
                let isFromCurrentSender = dataSource.isFromCurrentSender(message: message)
                let xCordMessage: CGFloat
                let xCordTitle: CGFloat
                
                if UIView.userInterfaceLayoutDirection(
                    for: messagesLayout.messagesCollectionView.semanticContentAttribute) == .rightToLeft {
                    
                    xCordMessage =  messageContainerSize.width - messageLabelSize.width
                    xCordTitle =  messageContainerSize.width - titleLabelSize.width
                } else {
                    xCordMessage = isFromCurrentSender ? messageContainerSize.width - messageLabelSize.width : 0
                    xCordTitle =  isFromCurrentSender ? messageContainerSize.width - titleLabelSize.width : 0
                    
                }
                
                let titleLabelFrame =  CGRect(x:  xCordTitle,
                                              y: mediaFrame.maxY,
                                              width: titleLabelSize.width,
                                              height: titleLabelSize.height)
                let messageLabelFrame =  CGRect(x:  xCordMessage,
                                                y: titleLabelFrame.maxY,
                                                width: messageLabelSize.width,
                                                height: messageLabelSize.height)
                var buttonsFrame: [CGRect] = []
                
                for counter in 0..<card.choices.count {
                    
                    let buttonFrame = CGRect(x: buttonInsets.left,
                                             y: buttonInsets.top  + (Double(counter) * (buttonHeight + buttonInsets.bottom)),
                                             width: messageContainerSize.width - buttonInsets.left - buttonInsets.right,
                                             height: buttonHeight)
                    buttonsFrame.append(buttonFrame)
                }
                
                frames.append(CardAttributes(frame: cardRect,
                                             mediaFrame: mediaFrame,
                                             titleFrame: titleLabelFrame,
                                             messageFrame: messageLabelFrame,
                                             buttonFrames: buttonsFrame))
            }
            
            cardFrames = adjustCardsHeightAndButtonsPosition(frames, maxCardHeight, firstButtonMaxYPosition)
        }
        return cardFrames
    }
    public override func configure(attributes: UICollectionViewLayoutAttributes) {
        super.configure(attributes: attributes)
        guard let attributes = attributes as? ChatFlowLayoutAttributes else { return }
        
        let dataSource = messagesLayout.chatDataSource
        let indexPath = attributes.indexPath
        let message = dataSource.messageForItem(at: indexPath, in: messagesLayout.messagesCollectionView)
        var numberOfChoices = 0
        if let message = message.body as? MessageCarousel {
            numberOfChoices = message.choices.count
        }
        
        attributes.carouselCardFrames = cardFrames(for: message, messageContainerSize: attributes.messageContainerSize)
        let maxCardHeight = attributes.carouselCardFrames.map { $0.frame.size.height }.max()
        
        var buttonsFrame: [CGRect] = []
        
        for counter in 0..<numberOfChoices {
            debugPrint(maxCardHeight ?? 0 )
            debugPrint(Double(counter) * (buttonHeight + buttonInsets.bottom))
            
            let buttonFrame = CGRect(x: buttonInsets.left,
                                     y: (maxCardHeight ?? 0) + 3 * buttonInsets.top  + (Double(counter) * (buttonHeight + buttonInsets.bottom)),
                                     width: attributes.messageContainerSize.width - buttonInsets.left - buttonInsets.right,
                                     height: buttonHeight)
            buttonsFrame.append(buttonFrame)
        }
        
        let dateLabelSize = dateLabelSize(for: message)
        let dateLabelFrame = CGRect(x: attributes.messageContainerSize.width - dateLabelSize.width - dateLabelInsets.right,
                                    y:  attributes.messageContainerSize.height - dateLabelSize.height - dateLabelInsets.bottom,
                                    width: dateLabelSize.width,
                                    height: dateLabelSize.height)
        
        attributes.carouselCardFrames = cardFrames(for: message, messageContainerSize: attributes.messageContainerSize)
        attributes.pageControlFrame = CGRect(x: 0,
                                             y: (maxCardHeight ?? 0) + buttonInsets.top - pageControlHeight/2,
                                             width: attributes.messageContainerSize.width,
                                             height: pageControlHeight)

        attributes.buttonsFrame = buttonsFrame
        attributes.dateLabelInsets = dateLabelInsets
        attributes.dateLabelTextInsets = dateLabelTextInsets
        attributes.dateLabelFont = dateLabelFont
        attributes.dateLabelFrame = dateLabelFrame
        
    }
}
