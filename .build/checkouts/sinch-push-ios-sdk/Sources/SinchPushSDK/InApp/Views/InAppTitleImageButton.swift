import UIKit

/// A rounded button with a leading icon, used for the location button.
final class InAppTitleImageButton: UIButton {

    override init(frame: CGRect) {
        super.init(frame: frame)
        setup()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError()
    }

    private func setup() {
        backgroundColor = .white
        layer.cornerRadius = 10
        layer.masksToBounds = true
        setInsets(
            forContentPadding: UIEdgeInsets(top: 0.0, left: 4.0, bottom: 0.0, right: 4.0),
            imageTitlePadding: 10
        )
    }
}

extension UIButton {

    /// Content and title insets that keep icon and text together in both
    /// writing directions.
    func setInsets(forContentPadding contentPadding: UIEdgeInsets, imageTitlePadding: CGFloat) {
        let isRightToLeft = UIView.userInterfaceLayoutDirection(for: semanticContentAttribute) == .rightToLeft
            || UIApplication.shared.userInterfaceLayoutDirection == .rightToLeft

        if isRightToLeft {
            contentEdgeInsets = UIEdgeInsets(
                top: contentPadding.top,
                left: contentPadding.left + imageTitlePadding,
                bottom: contentPadding.bottom,
                right: contentPadding.left
            )
            titleEdgeInsets = UIEdgeInsets(
                top: 0,
                left: -imageTitlePadding,
                bottom: 0,
                right: imageTitlePadding
            )
        } else {
            contentEdgeInsets = UIEdgeInsets(
                top: contentPadding.top,
                left: contentPadding.left,
                bottom: contentPadding.bottom,
                right: contentPadding.right + imageTitlePadding
            )
            titleEdgeInsets = UIEdgeInsets(
                top: 0,
                left: imageTitlePadding,
                bottom: 0,
                right: -imageTitlePadding
            )
        }
    }
}
