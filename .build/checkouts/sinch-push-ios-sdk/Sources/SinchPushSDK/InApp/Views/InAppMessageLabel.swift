import UIKit

/// A label that can be inset. The chat `MessageLabel` also ran data detectors;
/// the in-app alerts never enabled them, so only the inset support is kept.
final class InAppMessageLabel: UILabel {

    var textInsets: UIEdgeInsets = .zero

    override init(frame: CGRect) {
        super.init(frame: frame)
        numberOfLines = 0
        lineBreakMode = .byWordWrapping
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError()
    }

    override var intrinsicContentSize: CGSize {
        var size = super.intrinsicContentSize
        size.width += textInsets.left + textInsets.right
        size.height += textInsets.top + textInsets.bottom
        return size
    }

    override func drawText(in rect: CGRect) {
        super.drawText(in: rect.inset(by: textInsets))
    }
}
