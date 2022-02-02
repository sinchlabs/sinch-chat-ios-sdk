import UIKit

/// The layout attributes used by a `MessageCollectionViewCell` to layout its subviews.
 class ChatFlowLayoutAttributes: UICollectionViewLayoutAttributes {
    
    // MARK: - Properties
    
    public var avatarSize: CGSize = .zero
    public var avatarLeadingTrailingPadding: CGFloat = 0
    public var messageContainerSize: CGSize = .zero
    public var messageContainerPadding: UIEdgeInsets = .zero
    public var messageLabelFrame: CGRect = .zero
    public var messageLabelFont: UIFont = UIFont.preferredFont(forTextStyle: .body)
    public var messageLabelTextInsets: UIEdgeInsets = .zero
    public var dateLabelFrame: CGRect = .zero
    public var dateLabelInsets: UIEdgeInsets = .zero
    public var dateLabelTextInsets: UIEdgeInsets = .zero
    public var dateLabelFont: UIFont = UIFont.preferredFont(forTextStyle: .caption2)
    
    public var avatarPosition = AvatarPosition(horizontal: .notSet)
    
    // MARK: - Methods
    
    override func copy(with zone: NSZone? = nil) -> Any {
        // swiftlint:disable force_cast
        let copy = super.copy(with: zone) as! ChatFlowLayoutAttributes
        copy.avatarSize = avatarSize
        copy.avatarPosition = avatarPosition
        copy.avatarLeadingTrailingPadding = avatarLeadingTrailingPadding
        copy.messageContainerSize = messageContainerSize
        copy.messageContainerPadding = messageContainerPadding
        copy.messageLabelFrame = messageLabelFrame
        copy.messageLabelFont = messageLabelFont
        copy.messageLabelTextInsets = messageLabelTextInsets
        copy.dateLabelFrame = dateLabelFrame
        copy.dateLabelTextInsets = dateLabelTextInsets
        copy.dateLabelInsets = dateLabelInsets
        copy.dateLabelFont = dateLabelFont
        
        return copy
        // swiftlint:enable force_cast
    }
    
    override func isEqual(_ object: Any?) -> Bool {
        // MARK: - LEAVE this as is
        if let attributes = object as? ChatFlowLayoutAttributes {
            return super.isEqual(object) && attributes.avatarSize == avatarSize
            && attributes.avatarLeadingTrailingPadding == avatarLeadingTrailingPadding
            && attributes.messageContainerSize == messageContainerSize
            && attributes.messageContainerPadding == messageContainerPadding
            && attributes.messageLabelFrame == messageLabelFrame
            && attributes.messageLabelFont == messageLabelFont
            && attributes.messageLabelTextInsets == messageLabelTextInsets
            && attributes.dateLabelFrame == dateLabelFrame
            && attributes.dateLabelInsets == dateLabelInsets
            && attributes.dateLabelTextInsets == dateLabelTextInsets
            && attributes.dateLabelFont == dateLabelFont
            
        } else {
            return false
        }
    }
}
