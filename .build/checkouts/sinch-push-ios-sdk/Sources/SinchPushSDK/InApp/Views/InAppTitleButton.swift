import UIKit

/// A choice button. It flashes the tapped colours for half a second before the
/// alert moves on, which is what the chat SDK did.
final class InAppTitleButton: UIButton {

    private let theme: InAppMessageTheme
    private let highlightDuration: TimeInterval = 0.5

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
        backgroundColor = theme.buttonBackgroundColor
        layer.cornerRadius = theme.cornerRadius
        layer.masksToBounds = true
        titleEdgeInsets = UIEdgeInsets(top: 0.0, left: 8.0, bottom: 0.0, right: 8.0)
    }

    func flashTappedAppearance() {
        backgroundColor = theme.buttonTappedBackgroundColor
        isSelected = true

        DispatchQueue.main.asyncAfter(deadline: .now() + highlightDuration) { [weak self] in
            guard let self else { return }
            self.backgroundColor = self.theme.buttonBackgroundColor
            self.isSelected = false
        }
    }
}
