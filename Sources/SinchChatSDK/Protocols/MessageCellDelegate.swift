import Foundation
/// A protocol used by `MessageContentCell` subclasses to detect taps in the cell's subviews.
 protocol MessageCellDelegate: MessageLabelDelegate {

    func didTapMedia(with url: URL)
    func didTapOutsideOfContent(in cell: MessageCollectionViewCell)
    func didTapOutsideOfContent()
    func didTapOnChoice(_ text: ChoiceMessageType, in cell: MessageCollectionViewCell)

}
