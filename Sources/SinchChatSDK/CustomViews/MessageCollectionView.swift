import UIKit

final class MessageCollectionView: UICollectionView {
   
    weak var chatDataSource: ChatDataSource?
    var uiConfig: SinchSDKConfig.UIConfig!
    weak var touchDelegate: MessageCellDelegate?

    private var indexPathForLastItem: IndexPath? {
        let lastSection = numberOfSections - 1
        guard lastSection >= 0, numberOfItems(inSection: lastSection) > 0 else { return nil }
        return IndexPath(item: numberOfItems(inSection: lastSection) - 1, section: lastSection)
    }

    public override init(frame: CGRect, collectionViewLayout layout: UICollectionViewLayout) {
        super.init(frame: frame, collectionViewLayout: layout)

    }
    
    required public init?(coder aDecoder: NSCoder) {
        super.init(frame: .zero, collectionViewLayout: ChatFlowLayout())
    }

    convenience init(configuration: SinchSDKConfig.UIConfig) {
        
        self.init(frame:  .zero, collectionViewLayout: ChatFlowLayout())
        setupGestureRecognizers()
        self.uiConfig = configuration
        backgroundColor = uiConfig.backgroundColor
    }
   
    private func setupGestureRecognizers() {
        let tapGesture = UITapGestureRecognizer(target: self, action: #selector(handleTapGesture(_:)))
        tapGesture.delaysTouchesBegan = true
        addGestureRecognizer(tapGesture)
    }
    
    @objc func handleTapGesture(_ gesture: UIGestureRecognizer) {
        guard gesture.state == .ended else { return }
        
        let touchLocation = gesture.location(in: self)
        guard let indexPath = indexPathForItem(at: touchLocation) else {
               touchDelegate?.didTapOutsideOfContent()
            return
        
        }
        
        let cell = cellForItem(at: indexPath) as? MessageCollectionViewCell 
        cell?.handleTapGesture(gesture)

    }
    func scrollToLastItem(at pos: UICollectionView.ScrollPosition = .bottom, animated: Bool = true) {
        guard numberOfSections > 0 else { return }
        
        let lastSection = numberOfSections - 1
//        let lastItemIndex = numberOfItems(inSection: lastSection)
//        
//        guard lastSection >= 0 else { return }
        
        let indexPath = IndexPath(row: 0, section: lastSection)
        scrollToItem(at: indexPath, at: pos, animated: animated)
    }
    
    func reloadDataAndKeepOffset() {
        // stop scrolling
        setContentOffset(contentOffset, animated: false)
        
        // calculate the offset and reloadData
        let beforeContentSize = contentSize
        reloadData()
        layoutIfNeeded()
        let afterContentSize = contentSize
        
        // reset the contentOffset after data is updated
        let newOffset = CGPoint(
            x: contentOffset.x + (afterContentSize.width - beforeContentSize.width),
            y: contentOffset.y + (afterContentSize.height - beforeContentSize.height))
        setContentOffset(newOffset, animated: false)
    }
}
