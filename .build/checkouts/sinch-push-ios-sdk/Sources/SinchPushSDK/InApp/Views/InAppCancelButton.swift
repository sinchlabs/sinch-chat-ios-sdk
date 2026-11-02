import UIKit

/// The bordered `CLOSE` / `Cancel` button.
final class InAppCancelButton: UIButton {

    private let theme: InAppMessageTheme

    init(theme: InAppMessageTheme) {
        self.theme = theme
        super.init(frame: .zero)
        setup()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError()
    }

    private func setup() {
        applyBorderedStyle()
    }

    func applyBorderedStyle() {
        backgroundColor = .clear
        layer.cornerRadius = theme.cornerRadius
        layer.borderColor = theme.cancelButtonBorderColor.cgColor
        setTitleColor(theme.cancelButtonTitleColor, for: .normal)
        layer.borderWidth = 1.0
        layer.masksToBounds = true
        titleEdgeInsets = UIEdgeInsets(top: 0.0, left: 8.0, bottom: 0.0, right: 8.0)
    }
}
