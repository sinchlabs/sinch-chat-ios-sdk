import UIKit

/// Reports taps from inside a carousel page.
@MainActor
protocol InAppCardViewDelegate: AnyObject {
    func didSelect(choice: InAppChoice, in card: InAppCard)
    func didSelectMedia(url: URL, in card: InAppCard)
}

/// One page of a carousel: image, title, description and its own buttons.
final class InAppCardView: InAppBaseView {

    lazy var titleLabel: InAppMessageLabel = {
        let label = InAppMessageLabel()
        label.translatesAutoresizingMaskIntoConstraints = false
        label.backgroundColor = .clear
        label.textColor = theme.textColor
        label.numberOfLines = 0
        label.font = theme.titleFont
        return label
    }()

    lazy var textLabel: InAppMessageLabel = {
        let label = InAppMessageLabel()
        label.translatesAutoresizingMaskIntoConstraints = false
        label.backgroundColor = .clear
        label.font = theme.textFont
        label.textColor = theme.textColor
        label.numberOfLines = 0
        return label
    }()

    lazy var imageView: UIImageView = {
        let imageView = UIImageView()
        imageView.contentMode = .scaleAspectFill
        imageView.translatesAutoresizingMaskIntoConstraints = false
        imageView.backgroundColor = .clear
        imageView.clipsToBounds = true
        imageView.isUserInteractionEnabled = true
        return imageView
    }()

    lazy var backgroundImageView: UIView = {
        let view = UIView()
        view.backgroundColor = theme.imageBackgroundColor
        view.translatesAutoresizingMaskIntoConstraints = false
        return view
    }()

    lazy var placeholderImageView: UIImageView = {
        let imageView = UIImageView()
        imageView.translatesAutoresizingMaskIntoConstraints = false
        imageView.contentMode = .scaleAspectFill
        imageView.backgroundColor = .clear
        imageView.image = theme.imagePlaceholder
        imageView.clipsToBounds = true
        return imageView
    }()

    lazy var buttonsStackView: UIStackView = {
        let stackView = UIStackView()
        stackView.distribution = .fillEqually
        stackView.translatesAutoresizingMaskIntoConstraints = false
        stackView.alignment = .fill
        stackView.axis = .vertical
        stackView.spacing = 10
        return stackView
    }()

    lazy var backgroundView: UIView = {
        let backgroundView = UIView()
        backgroundView.translatesAutoresizingMaskIntoConstraints = false
        backgroundView.backgroundColor = theme.backgroundColor
        backgroundView.isUserInteractionEnabled = true
        backgroundView.clipsToBounds = true
        return backgroundView
    }()

    let card: InAppCard
    let cardIndex: Int
    let maxChoices: Int
    var buttons: [InAppTitleButton] = []
    weak var delegate: InAppCardViewDelegate?

    init(theme: InAppMessageTheme, card: InAppCard, index: Int, maxChoices: Int) {
        self.card = card
        self.cardIndex = index
        self.maxChoices = maxChoices
        super.init(theme: theme)
    }

    override func setupSubviews() {
        titleLabel.textColor = theme.textColor
        titleLabel.text = card.title
        backgroundView.addSubview(titleLabel)

        textLabel.textColor = theme.textColor
        textLabel.text = card.description
        backgroundView.addSubview(textLabel)

        backgroundView.addSubview(backgroundImageView)

        imageView.addGestureRecognizer(
            UITapGestureRecognizer(target: self, action: #selector(imageTapped))
        )
        backgroundView.addSubview(placeholderImageView)
        backgroundView.addSubview(imageView)
        setImageFromURL(card.media)
        backgroundView.addSubview(buttonsStackView)

        buttons = setupButtons(choices: card.choices)
        addSubview(backgroundView)
    }

    override func setupConstraints() {
        backgroundView.translatesAutoresizingMaskIntoConstraints = false
        buttonsStackView.translatesAutoresizingMaskIntoConstraints = false

        NSLayoutConstraint.activate([
            backgroundView.topAnchor.constraint(equalTo: topAnchor, constant: 0),
            backgroundView.trailingAnchor.constraint(equalTo: trailingAnchor, constant: 0),
            backgroundView.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 0),
            backgroundView.bottomAnchor.constraint(equalTo: bottomAnchor),

            backgroundImageView.topAnchor.constraint(equalTo: backgroundView.topAnchor, constant: 0),
            backgroundImageView.trailingAnchor.constraint(equalTo: backgroundView.trailingAnchor, constant: 0),
            backgroundImageView.leadingAnchor.constraint(equalTo: backgroundView.leadingAnchor, constant: 0),
            backgroundImageView.heightAnchor.constraint(equalToConstant: 200),

            imageView.topAnchor.constraint(equalTo: backgroundImageView.topAnchor, constant: 0),
            imageView.bottomAnchor.constraint(equalTo: backgroundImageView.bottomAnchor, constant: 0),
            imageView.trailingAnchor.constraint(equalTo: backgroundImageView.trailingAnchor, constant: 0),
            imageView.leadingAnchor.constraint(equalTo: backgroundImageView.leadingAnchor, constant: 0),

            placeholderImageView.centerXAnchor.constraint(equalTo: backgroundImageView.centerXAnchor, constant: 0),
            placeholderImageView.centerYAnchor.constraint(equalTo: backgroundImageView.centerYAnchor, constant: 0),
            placeholderImageView.widthAnchor.constraint(equalToConstant: 100),
            placeholderImageView.heightAnchor.constraint(equalToConstant: 100),

            titleLabel.topAnchor.constraint(equalTo: imageView.bottomAnchor, constant: 25),
            titleLabel.trailingAnchor.constraint(equalTo: backgroundView.trailingAnchor, constant: -25),
            titleLabel.leadingAnchor.constraint(equalTo: backgroundView.leadingAnchor, constant: 25),

            textLabel.topAnchor.constraint(equalTo: titleLabel.bottomAnchor, constant: 16),
            textLabel.trailingAnchor.constraint(equalTo: backgroundView.trailingAnchor, constant: -25),
            textLabel.leadingAnchor.constraint(equalTo: backgroundView.leadingAnchor, constant: 25),

            buttonsStackView.topAnchor.constraint(greaterThanOrEqualTo: textLabel.bottomAnchor, constant: 16),
            buttonsStackView.trailingAnchor.constraint(equalTo: backgroundView.trailingAnchor, constant: -25),
            buttonsStackView.leadingAnchor.constraint(equalTo: backgroundView.leadingAnchor, constant: 25),
            buttonsStackView.bottomAnchor.constraint(equalTo: backgroundView.bottomAnchor, constant: -16)
        ])
    }

    private func setupButtons(choices: [InAppChoice]) -> [InAppTitleButton] {
        var result: [InAppTitleButton] = []

        for (index, choice) in choices.enumerated() {
            let button = InAppTitleButton(theme: theme)
            button.titleLabel?.font = theme.buttonTitleFont
            button.setTitleColor(theme.buttonTitleColor, for: .normal)
            button.setTitleColor(theme.tappedButtonTitleColor, for: .selected)
            button.backgroundColor = theme.buttonBackgroundColor
            button.setTitle(choice.title, for: .normal)

            if case .location(let location) = choice.action {
                button.setTitle(location.label.isEmpty ? location.title : location.label, for: .normal)
                button.setImage(theme.locationImage, for: .normal)
                button.setInsets(
                    forContentPadding: UIEdgeInsets(top: 0.0, left: 4.0, bottom: 0.0, right: 4.0),
                    imageTitlePadding: 10
                )
            }

            button.tag = index
            button.addTarget(self, action: #selector(choiceButtonTapped(_:)), for: .touchUpInside)
            button.heightAnchor.constraint(equalToConstant: 36).isActive = true
            result.append(button)
            buttonsStackView.addArrangedSubview(button)
        }

        // Cards in a carousel keep a shared button height so paging does not jump.
        for _ in 0..<max(0, maxChoices - result.count) {
            let spacer = UIView()
            spacer.backgroundColor = .clear
            spacer.heightAnchor.constraint(equalToConstant: 36).isActive = true
            buttonsStackView.addArrangedSubview(spacer)
        }

        return result
    }

    private func setImageFromURL(_ urlString: String) {
        // `placeholderImageView` shows the empty state.
        InAppImageLoader.shared.load(URL(string: urlString), into: imageView)
    }

    @objc private func imageTapped() {
        guard let url = URL(string: card.media) else { return }
        delegate?.didSelectMedia(url: url, in: card)
    }

    @objc private func choiceButtonTapped(_ sender: InAppTitleButton) {
        sender.flashTappedAppearance()

        let index = sender.tag
        guard card.choices.indices.contains(index) else { return }
        delegate?.didSelect(choice: card.choices[index], in: card)
    }
}
