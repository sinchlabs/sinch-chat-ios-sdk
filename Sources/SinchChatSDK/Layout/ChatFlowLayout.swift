import UIKit

final class ChatFlowLayout: UICollectionViewFlowLayout {

    override class var layoutAttributesClass: AnyClass {
        return ChatFlowLayoutAttributes.self
    }
    
    lazy public var textMessageSizeCalculator = TextMessageSizeCalculator(layout: self)
    lazy public var imageMessageSizeCalculator = ImageMessageSizeCalculator(layout: self)
    lazy public var fileMessageSizeCalculator = FileMessageSizeCalculator(layout: self)
    lazy public var eventMessageSizeCalculator = EventMessageSizeCalculator(layout: self)
    lazy public var dateMessageSizeCalculator = DateMessageSizeCalculator(layout: self)
    lazy public var typingCellSizeCalculator = TypeIndicatorCellSizeCalculator(layout: self)
    lazy public var mediaTextCellSizeCalculator = MediaTextMessageSizeCalculator(layout: self)
    lazy public var locationCellSizeCalculator = LocationMessageSizeCalculator(layout: self)
    lazy public var voiceMessageCellSizeCalculator = VoiceMessageSizeCalculator(layout: self)
    lazy public var choicesCellSizeCalculator = ChoiceMessageSizeCalculator(layout: self)
    lazy public var cardCellSizeCalculator = CardMessageSizeCalculator(layout: self)
    lazy public var carouselCellSizeCalculator = CarouselMessageSizeCalculator(layout: self)
    lazy public var unsupportedCellSizeCalculator = UnsupportedMessageSizeCalculator(layout: self)
    lazy public var typingIndicatorSizeCalculator = TypeIndicatorCellSizeCalculator(layout: self)

    /// The `MessageCollectionView` that owns this layout object.
    public var messagesCollectionView: MessageCollectionView {
        guard let messagesCollectionView = collectionView as? MessageCollectionView else {
            fatalError()
        }
        return messagesCollectionView
    }
    /// The `ChatDataSource` for the layout's collection view.
    public var chatDataSource: ChatDataSource {
        guard let chatDataSource = messagesCollectionView.chatDataSource else {
            fatalError()
        }
        return chatDataSource
    }
    /// Breakpoints for the current collection view size and size classes. Derived in `prepare()`.
    private(set) var metrics = ChatLayoutMetrics(containerWidth: 0, horizontalSizeClass: .unspecified, verticalSizeClass: .unspecified)

    /// Width of the message column. On regular width the column is capped and centred through
    /// `sectionInset`, so every cell, including the typing indicator, lives inside it while the
    /// collection view (and its background) still fills the whole screen.
    public var itemWidth: CGFloat {
        guard let collectionView = collectionView else { return 0 }
        return collectionView.bounds.width - sectionInset.left - sectionInset.right
    }

    /// Recomputes `metrics` and the centring insets from the collection view. Returns true when they changed.
    @discardableResult
    func updateMetrics() -> Bool {
        guard let collectionView = collectionView else { return false }
        let newMetrics = ChatLayoutMetrics(containerWidth: collectionView.bounds.width,
                                           traitCollection: collectionView.traitCollection)
        let inset = newMetrics.columnSideInset
        let newInsets = UIEdgeInsets(top: sectionInset.top, left: inset, bottom: sectionInset.bottom, right: inset)
        let changed = newMetrics != metrics || newInsets != sectionInset
        metrics = newMetrics
        if newInsets != sectionInset {
            sectionInset = newInsets
        }
        return changed
    }

    /// The Dynamic Type category the size calculators (and their cached fonts) were built for.
    private var calculatorContentSizeCategory: UIContentSizeCategory?

    override func prepare() {
        refreshCalculatorsForContentSizeCategory()
        updateMetrics()
        super.prepare()
    }

    /// Calculators resolve their fonts against the collection view's trait collection. Rebuilding them here, at the
    /// layout pass, means the category is already propagated to the collection view, whichever view in the chain
    /// carried the `traitOverrides` or the system change.
    private func refreshCalculatorsForContentSizeCategory() {
        guard let category = collectionView?.traitCollection.preferredContentSizeCategory,
              category != calculatorContentSizeCategory else { return }
        calculatorContentSizeCategory = category
        resetSizeCalculators()
    }

    var isTypingIndicatorViewHidden: Bool = true
   
    public override init() {
        super.init()
        setupView()
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    func setupView() {
        
        sectionInset = UIEdgeInsets(top: 0, left: 0, bottom: 0, right: 0)
        scrollDirection = .vertical
        
    }
    
    /// A method that by default checks if the section is the last in the
    /// `messagesCollectionView` and that `isTypingIndicatorViewHidden`
    /// is FALSE
    ///
    /// - Parameter section
    /// - Returns: A Boolean indicating if the TypingIndicator should be presented at the given section
    func isSectionReservedForTypingIndicator(_ section: Int) -> Bool {
        return !isTypingIndicatorViewHidden && section == messagesCollectionView.numberOfSections - 1
    }
    /// Note:
    /// - If you override this method, remember to call MessageLayoutDelegate's
    /// customCellSizeCalculator(for:at:in:) method for MessageKind.custom messages, if necessary
    /// - If you are using the typing indicator be sure to return the `typingIndicatorSizeCalculator`
    /// when the section is reserved for it, indicated by `isSectionReservedForTypingIndicator`
    func cellSizeCalculator(at indexPath: IndexPath) -> ChatCellSizeCalculator {
        if isSectionReservedForTypingIndicator(indexPath.section) {
            return typingIndicatorSizeCalculator
        }
        
        let message =  chatDataSource.messageForItem(at: indexPath, in: messagesCollectionView)
        if message.body is MessageText {
            return textMessageSizeCalculator
        } else if let messageBody = message.body as? MessageMedia {
            
            switch messageBody.type {
            case .file:
                return fileMessageSizeCalculator

            case .audio:
                return voiceMessageCellSizeCalculator
            default:
                return imageMessageSizeCalculator
            }

        } else if message.body is MessageEvent {
            return eventMessageSizeCalculator 
        } else if message.body is MessageDate {
            return dateMessageSizeCalculator
        } else if message.body is MessageMediaText {
            return mediaTextCellSizeCalculator
        } else if message.body is MessageLocation {
            return locationCellSizeCalculator
        } else if message.body is MessageChoices {
            return choicesCellSizeCalculator
        } else if message.body is MessageCard {
            return cardCellSizeCalculator
        } else if message.body is MessageCarousel {
            return carouselCellSizeCalculator
        } else if message.body is MessageUnsupported {
            return unsupportedCellSizeCalculator
        }

        return ChatCellSizeCalculator()
    }

    func sizeForItem(at indexPath: IndexPath) -> CGSize {
        let calculator = cellSizeCalculator(at: indexPath)
        return calculator.sizeForItem(at: indexPath)
    }
    // MARK: - Attributes

    override func layoutAttributesForElements(in rect: CGRect) -> [UICollectionViewLayoutAttributes]? {
        guard let attributesArray = super.layoutAttributesForElements(in: rect) as? [ChatFlowLayoutAttributes] else {
            return nil
        }
        for attributes in attributesArray where attributes.representedElementCategory == .cell {
            let cellSizeCalculator = cellSizeCalculator(at: attributes.indexPath)
            cellSizeCalculator.configure(attributes: attributes)
        }
        return attributesArray
    }

    override func layoutAttributesForItem(at indexPath: IndexPath) -> UICollectionViewLayoutAttributes? {
        guard let attributes = super.layoutAttributesForItem(at: indexPath) as? ChatFlowLayoutAttributes else {
            return nil
        }
        if attributes.representedElementCategory == .cell {
            let cellSizeCalculator = cellSizeCalculator(at: attributes.indexPath)
            cellSizeCalculator.configure(attributes: attributes)
        }
        return attributes
    }

    // MARK: - Layout Invalidation

    override func shouldInvalidateLayout(forBoundsChange newBounds: CGRect) -> Bool {
        return collectionView?.bounds.width != newBounds.width
    }

    override func invalidationContext(forBoundsChange newBounds: CGRect) -> UICollectionViewLayoutInvalidationContext {
        let context = super.invalidationContext(forBoundsChange: newBounds)
        guard let flowLayoutContext = context as? UICollectionViewFlowLayoutInvalidationContext else { return context }
        flowLayoutContext.invalidateFlowLayoutDelegateMetrics = shouldInvalidateLayout(forBoundsChange: newBounds)
        return flowLayoutContext
    }

    /// Drops everything derived from the environment and relays out. Called on size class, window size
    /// and Dynamic Type changes (rotation, Split View, Stage Manager resize, fold / unfold).
    func invalidateForEnvironmentChange() {
        // Dynamic Type needs no flag here: `prepare()` notices a new category and rebuilds the calculators.
        let context = UICollectionViewFlowLayoutInvalidationContext()
        context.invalidateFlowLayoutDelegateMetrics = true
        context.invalidateFlowLayoutAttributes = true
        invalidateLayout(with: context)
    }

    private func resetSizeCalculators() {
        textMessageSizeCalculator = TextMessageSizeCalculator(layout: self)
        imageMessageSizeCalculator = ImageMessageSizeCalculator(layout: self)
        fileMessageSizeCalculator = FileMessageSizeCalculator(layout: self)
        eventMessageSizeCalculator = EventMessageSizeCalculator(layout: self)
        dateMessageSizeCalculator = DateMessageSizeCalculator(layout: self)
        typingCellSizeCalculator = TypeIndicatorCellSizeCalculator(layout: self)
        mediaTextCellSizeCalculator = MediaTextMessageSizeCalculator(layout: self)
        locationCellSizeCalculator = LocationMessageSizeCalculator(layout: self)
        voiceMessageCellSizeCalculator = VoiceMessageSizeCalculator(layout: self)
        choicesCellSizeCalculator = ChoiceMessageSizeCalculator(layout: self)
        cardCellSizeCalculator = CardMessageSizeCalculator(layout: self)
        carouselCellSizeCalculator = CarouselMessageSizeCalculator(layout: self)
        unsupportedCellSizeCalculator = UnsupportedMessageSizeCalculator(layout: self)
        typingIndicatorSizeCalculator = TypeIndicatorCellSizeCalculator(layout: self)
    }

    // MARK: - Typing indicator
    
    func typingIndicatorViewSize() -> CGSize {
        let collectionViewWidth = messagesCollectionView.bounds.width
        let contentInset = messagesCollectionView.contentInset
        let inset = sectionInset.left + sectionInset.right + contentInset.left + contentInset.right
        return CGSize(width: collectionViewWidth - inset, height: 54)
    }
}
