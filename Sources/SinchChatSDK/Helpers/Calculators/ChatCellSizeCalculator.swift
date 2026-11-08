import UIKit

@MainActor
class ChatCellSizeCalculator {

    public weak var layout: UICollectionViewFlowLayout?
    
    open func configure(attributes: UICollectionViewLayoutAttributes) {}
    
    open func sizeForItem(at indexPath: IndexPath) -> CGSize { return .zero }
    
    public init() {}

    /// A Dynamic Type font resolved against the chat's own trait collection. `UIFont.preferredFont(forTextStyle:)`
    /// alone follows the app-wide category and ignores `traitOverrides` on the chat screen or its window.
    func preferredFont(_ style: UIFont.TextStyle, bold: Bool = false) -> UIFont {
        let font = UIFont.preferredFont(forTextStyle: style, compatibleWith: layout?.collectionView?.traitCollection)
        guard bold, let descriptor = font.fontDescriptor.withSymbolicTraits(.traitBold) else { return font }
        return UIFont(descriptor: descriptor, size: 0)
    }

}
