import MapKit
import UIKit

// swiftlint:disable file_length type_body_length

/// Reports taps from inside the alert up to the view controller.
@MainActor
protocol InAppMessageViewDelegate: AnyObject {
    func didSelect(choice: InAppChoice)
    func didSelectMedia(url: URL)
}

/// The alert card.
///
/// One class for all six layouts: the body decides which subviews are added and
/// which constraints are active. That mirrors the chat implementation, where the
/// layout was chosen by the `MessageBody` type.
final class InAppMessageView: InAppBaseView, UIScrollViewDelegate {

    // MARK: - Subviews

    let scrollView: UIScrollView = {
        let scrollView = UIScrollView()
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        scrollView.isScrollEnabled = true
        scrollView.bounces = false
        return scrollView
    }()

    lazy var horizontalScrollView: UIScrollView = {
        let scrollView = UIScrollView()
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        scrollView.isPagingEnabled = true
        scrollView.backgroundColor = .clear
        scrollView.decelerationRate = .fast
        scrollView.bounces = false
        scrollView.showsHorizontalScrollIndicator = false
        scrollView.showsVerticalScrollIndicator = false
        return scrollView
    }()

    let horizontalContentView: UIView = {
        let view = UIView()
        view.translatesAutoresizingMaskIntoConstraints = false
        view.backgroundColor = .clear
        return view
    }()

    lazy var cardsStackView: UIStackView = {
        let stackView = UIStackView()
        stackView.translatesAutoresizingMaskIntoConstraints = false
        stackView.distribution = .fill
        stackView.alignment = .fill
        stackView.axis = .horizontal
        stackView.spacing = 0
        return stackView
    }()

    let contentView: UIView = {
        let view = UIView()
        view.translatesAutoresizingMaskIntoConstraints = false
        view.backgroundColor = .clear
        return view
    }()

    let closeButton: UIButton = {
        let button = UIButton(type: .custom)
        button.translatesAutoresizingMaskIntoConstraints = false
        return button
    }()

    lazy var cancelButton: InAppCancelButton = {
        let button = InAppCancelButton(theme: theme)
        button.translatesAutoresizingMaskIntoConstraints = false
        button.titleLabel?.font = theme.buttonTitleFont
        button.setTitle(theme.cancelButtonTitle, for: .normal)
        return button
    }()

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
        view.translatesAutoresizingMaskIntoConstraints = false
        view.backgroundColor = theme.imageBackgroundColor
        return view
    }()

    lazy var placeholderImageView: UIImageView = {
        let imageView = UIImageView()
        imageView.contentMode = .scaleAspectFill
        imageView.translatesAutoresizingMaskIntoConstraints = false
        imageView.backgroundColor = .clear
        imageView.image = theme.imagePlaceholder
        imageView.clipsToBounds = true
        return imageView
    }()

    lazy var buttonsStackView: UIStackView = {
        let stackView = UIStackView()
        stackView.translatesAutoresizingMaskIntoConstraints = false
        stackView.distribution = .fillEqually
        stackView.alignment = .fill
        stackView.axis = .vertical
        stackView.spacing = 16
        return stackView
    }()

    lazy var mapView: MKMapView = {
        let mapView = MKMapView()
        mapView.translatesAutoresizingMaskIntoConstraints = false
        return mapView
    }()

    lazy var locationButton: InAppTitleImageButton = {
        let button = InAppTitleImageButton()
        button.translatesAutoresizingMaskIntoConstraints = false
        return button
    }()

    let backgroundView: UIView = {
        let backgroundView = UIView()
        backgroundView.layer.cornerRadius = 10
        backgroundView.isUserInteractionEnabled = true
        backgroundView.translatesAutoresizingMaskIntoConstraints = false
        backgroundView.clipsToBounds = true
        return backgroundView
    }()

    let lineView: UIView = {
        let view = UIView()
        view.translatesAutoresizingMaskIntoConstraints = false
        view.backgroundColor = .clear
        return view
    }()

    let pageControl = UIPageControl()
    var pageWidth: CGFloat = 240.0

    // MARK: - State

    let message: InAppMessage
    var buttons: [InAppTitleButton] = []
    weak var delegate: InAppMessageViewDelegate?
    var cards: [InAppCardView] = []

    private var compactConstraints: [NSLayoutConstraint] = []
    private var regularConstraints: [NSLayoutConstraint] = []

    init(theme: InAppMessageTheme, message: InAppMessage) {
        self.message = message
        super.init(theme: theme)
    }

    // MARK: - Body helpers

    private var mediaURLString: String? {
        switch message.body {
        case .media(let url): return url
        case .card(let card): return card.media
        case .text, .location, .choices, .carousel: return nil
        }
    }

    private var choices: [InAppChoice] {
        switch message.body {
        case .choices(_, let choices): return choices
        case .carousel(_, let choices): return choices
        case .text, .media, .location, .card: return []
        }
    }

    // MARK: - Layout

    override func layoutSubviews() {
        super.layoutSubviews()
        layoutIfNeeded()
        pageWidth = backgroundView.frame.width

        if horizontalScrollView.contentSize.width != 0 {
            horizontalScrollView.setContentOffset(
                CGPoint(x: CGFloat(pageControl.currentPage) * pageWidth, y: 0.0),
                animated: false
            )
        }
    }

    override func setupSubviews() {
        addSubview(scrollView)
        scrollView.addSubview(contentView)
        contentView.addSubview(backgroundView)

        backgroundColor = .clear
        contentView.backgroundColor = theme.dimmingColor
        backgroundView.backgroundColor = theme.backgroundColor
        backgroundView.layer.cornerRadius = theme.cornerRadius

        closeButton.setImage(theme.closeButtonImage, for: .normal)
        closeButton.accessibilityLabel = theme.closeButtonAccessibilityLabel
        closeButton.isHidden = true

        cancelButton.titleLabel?.font = theme.buttonTitleFont
        cancelButton.setTitle(theme.cancelButtonTitle, for: .normal)

        textLabel.isHidden = true
        titleLabel.isHidden = true

        switch message.body {
        case .text(let text):
            textLabel.text = text
            textLabel.isHidden = false
            backgroundView.addSubview(textLabel)

        case .media(let url):
            backgroundView.addSubview(backgroundImageView)
            backgroundView.addSubview(placeholderImageView)
            backgroundView.addSubview(imageView)

            configureMediaInteraction()
            setImageFromURL(url)
            closeButton.isHidden = false

        case .location(let location):
            locationButton.titleLabel?.font = theme.buttonTitleFont
            locationButton.setTitleColor(theme.buttonTitleColor, for: .normal)
            locationButton.setImage(theme.locationImage, for: .normal)
            locationButton.backgroundColor = theme.buttonBackgroundColor

            backgroundView.addSubview(mapView)

            textLabel.text = location.title
            textLabel.isHidden = false
            backgroundView.addSubview(textLabel)

            locationButton.setTitle(location.label.isEmpty ? location.title : location.label, for: .normal)
            locationButton.addTarget(self, action: #selector(openMaps), for: .touchUpInside)
            backgroundView.addSubview(locationButton)
            setupMapView(location)

        case .choices(let text, let choices):
            textLabel.text = text
            textLabel.isHidden = false
            backgroundView.addSubview(textLabel)

            buttons = setupButtons(choices: choices)
            backgroundView.addSubview(buttonsStackView)
            for button in buttons {
                buttonsStackView.addArrangedSubview(button)
            }

        case .card(let card):
            backgroundView.addSubview(backgroundImageView)
            backgroundView.addSubview(placeholderImageView)

            titleLabel.isHidden = false
            titleLabel.text = card.title

            textLabel.text = card.description
            textLabel.isHidden = false

            configureMediaInteraction()
            setImageFromURL(card.media)

            backgroundView.addSubview(imageView)
            backgroundView.addSubview(titleLabel)
            backgroundView.addSubview(textLabel)

            buttons = setupButtons(choices: card.choices)
            backgroundView.addSubview(buttonsStackView)
            for button in buttons {
                buttonsStackView.addArrangedSubview(button)
            }
            closeButton.isHidden = false

        case .carousel(let cards, let choices):
            backgroundView.addSubview(horizontalScrollView)
            horizontalScrollView.addSubview(horizontalContentView)
            horizontalContentView.addSubview(cardsStackView)
            horizontalScrollView.delegate = self
            let maxChoices = cards.map(\.choices.count).max() ?? 0

            for (index, card) in cards.enumerated() {
                let cardView = InAppCardView(theme: theme, card: card, index: index, maxChoices: maxChoices)
                cardView.translatesAutoresizingMaskIntoConstraints = false
                cardView.delegate = self
                self.cards.append(cardView)
                cardsStackView.addArrangedSubview(cardView)
            }

            backgroundView.addSubview(pageControl)
            setupPageControl()
            buttons = setupButtons(choices: choices)
            lineView.backgroundColor = theme.carouselSeparatorColor
            backgroundView.addSubview(lineView)
            backgroundView.addSubview(buttonsStackView)
            for button in buttons {
                buttonsStackView.addArrangedSubview(button)
            }
            closeButton.isHidden = false
        }

        backgroundView.addSubview(cancelButton)
        backgroundView.addSubview(closeButton)
    }

    private func configureMediaInteraction() {
        imageView.addGestureRecognizer(
            UITapGestureRecognizer(target: self, action: #selector(imageTapped))
        )
    }

    func setupMapView(_ location: InAppLocation) {
        let coordinate = CLLocationCoordinate2D(latitude: location.latitude, longitude: location.longitude)
        let region = MKCoordinateRegion(center: coordinate, latitudinalMeters: 1000, longitudinalMeters: 1000)
        mapView.setRegion(region, animated: false)

        let annotation = MKPointAnnotation()
        annotation.coordinate = coordinate
        mapView.addAnnotation(annotation)
    }

    func setupPageControl() {
        guard case .carousel(let cards, _) = message.body else { return }

        pageControl.numberOfPages = cards.count
        pageControl.currentPage = 0
        pageControl.currentPageIndicatorTintColor = theme.pageIndicatorSelectedColor
        pageControl.pageIndicatorTintColor = theme.pageIndicatorColor
        pageControl.isUserInteractionEnabled = false
        pageControl.hidesForSinglePage = true
        pageControl.translatesAutoresizingMaskIntoConstraints = false
    }

    private func setupButtons(choices: [InAppChoice]) -> [InAppTitleButton] {
        choices.enumerated().map { index, choice in
            let button = InAppTitleButton(theme: theme)
            button.titleLabel?.font = theme.buttonTitleFont
            button.setTitleColor(theme.buttonTitleColor, for: .normal)
            button.setTitleColor(theme.tappedButtonTitleColor, for: .selected)
            button.backgroundColor = theme.buttonBackgroundColor
            button.translatesAutoresizingMaskIntoConstraints = false
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
            return button
        }
    }

    // MARK: - Constraints

    private func addSharedConstraints() {
        compactConstraints.append(contentsOf: [
            backgroundView.topAnchor.constraint(greaterThanOrEqualTo: contentView.topAnchor, constant: 25),
            backgroundView.bottomAnchor.constraint(lessThanOrEqualTo: contentView.bottomAnchor, constant: -25),
            backgroundView.centerYAnchor.constraint(equalTo: contentView.centerYAnchor),
            backgroundView.centerXAnchor.constraint(equalTo: contentView.centerXAnchor),
            backgroundView.trailingAnchor.constraint(equalTo: safeAreaLayoutGuide.trailingAnchor, constant: -25),
            backgroundView.leadingAnchor.constraint(equalTo: safeAreaLayoutGuide.leadingAnchor, constant: 25),
            backgroundView.heightAnchor.constraint(greaterThanOrEqualToConstant: 60)
        ])

        regularConstraints.append(contentsOf: [
            backgroundView.topAnchor.constraint(greaterThanOrEqualTo: contentView.topAnchor, constant: 25),
            backgroundView.bottomAnchor.constraint(lessThanOrEqualTo: contentView.bottomAnchor, constant: -25),
            backgroundView.centerYAnchor.constraint(equalTo: contentView.centerYAnchor),
            backgroundView.centerXAnchor.constraint(equalTo: contentView.centerXAnchor),
            backgroundView.heightAnchor.constraint(greaterThanOrEqualToConstant: 60),
            backgroundView.widthAnchor.constraint(equalToConstant: 460)
        ])

        layoutTrait(traitCollection: traitCollection)

        let scrollConstraint = contentView.heightAnchor.constraint(
            greaterThanOrEqualTo: scrollView.heightAnchor,
            constant: 0.0
        )
        scrollConstraint.priority = UILayoutPriority(250)

        NSLayoutConstraint.activate([
            closeButton.topAnchor.constraint(equalTo: backgroundView.topAnchor, constant: 13),
            closeButton.trailingAnchor.constraint(equalTo: backgroundView.trailingAnchor, constant: -13),
            closeButton.heightAnchor.constraint(equalToConstant: 40),
            closeButton.widthAnchor.constraint(equalToConstant: 40),

            scrollView.topAnchor.constraint(equalTo: safeAreaLayoutGuide.topAnchor),
            scrollView.leadingAnchor.constraint(equalTo: safeAreaLayoutGuide.leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: safeAreaLayoutGuide.trailingAnchor),
            scrollView.bottomAnchor.constraint(equalTo: safeAreaLayoutGuide.bottomAnchor),

            contentView.topAnchor.constraint(equalTo: scrollView.topAnchor),
            contentView.leadingAnchor.constraint(equalTo: scrollView.leadingAnchor),
            contentView.trailingAnchor.constraint(equalTo: scrollView.trailingAnchor),
            contentView.bottomAnchor.constraint(equalTo: scrollView.bottomAnchor),
            contentView.widthAnchor.constraint(equalTo: scrollView.widthAnchor),

            scrollConstraint,

            cancelButton.bottomAnchor.constraint(equalTo: backgroundView.bottomAnchor, constant: -25),
            cancelButton.trailingAnchor.constraint(equalTo: backgroundView.trailingAnchor, constant: -25),
            cancelButton.leadingAnchor.constraint(equalTo: backgroundView.leadingAnchor, constant: 25),
            cancelButton.heightAnchor.constraint(equalToConstant: 36)
        ])
    }

    override func setupConstraints() {
        addSharedConstraints()

        switch message.body {
        case .text:
            NSLayoutConstraint.activate([
                textLabel.topAnchor.constraint(equalTo: backgroundView.topAnchor, constant: 25),
                textLabel.trailingAnchor.constraint(equalTo: backgroundView.trailingAnchor, constant: -25),
                textLabel.leadingAnchor.constraint(equalTo: backgroundView.leadingAnchor, constant: 25),
                cancelButton.topAnchor.constraint(equalTo: textLabel.bottomAnchor, constant: 16)
            ])

        case .media:
            NSLayoutConstraint.activate([
                backgroundImageView.topAnchor.constraint(equalTo: backgroundView.topAnchor, constant: 0),
                backgroundImageView.bottomAnchor.constraint(equalTo: backgroundView.bottomAnchor, constant: -86),
                backgroundImageView.trailingAnchor.constraint(equalTo: backgroundView.trailingAnchor, constant: 0),
                backgroundImageView.leadingAnchor.constraint(equalTo: backgroundView.leadingAnchor, constant: 0),
                backgroundImageView.heightAnchor.constraint(equalToConstant: 400),

                imageView.topAnchor.constraint(equalTo: backgroundImageView.topAnchor, constant: 0),
                imageView.bottomAnchor.constraint(equalTo: backgroundImageView.bottomAnchor, constant: 0),
                imageView.trailingAnchor.constraint(equalTo: backgroundImageView.trailingAnchor, constant: 0),
                imageView.leadingAnchor.constraint(equalTo: backgroundImageView.leadingAnchor, constant: 0),

                placeholderImageView.centerXAnchor.constraint(equalTo: backgroundView.centerXAnchor, constant: 0),
                placeholderImageView.centerYAnchor.constraint(equalTo: imageView.centerYAnchor, constant: 0),
                placeholderImageView.heightAnchor.constraint(equalToConstant: 134),
                placeholderImageView.widthAnchor.constraint(equalToConstant: 134),

                cancelButton.topAnchor.constraint(equalTo: imageView.bottomAnchor, constant: 25)
            ])

        case .location:
            NSLayoutConstraint.activate([
                mapView.topAnchor.constraint(equalTo: backgroundView.topAnchor, constant: 0),
                mapView.trailingAnchor.constraint(equalTo: backgroundView.trailingAnchor, constant: 0),
                mapView.leadingAnchor.constraint(equalTo: backgroundView.leadingAnchor, constant: 0),
                mapView.heightAnchor.constraint(equalToConstant: 200.0),

                textLabel.topAnchor.constraint(equalTo: mapView.bottomAnchor, constant: 25),
                textLabel.trailingAnchor.constraint(equalTo: backgroundView.trailingAnchor, constant: -25),
                textLabel.leadingAnchor.constraint(equalTo: backgroundView.leadingAnchor, constant: 25),

                locationButton.topAnchor.constraint(equalTo: textLabel.bottomAnchor, constant: 16),
                locationButton.trailingAnchor.constraint(equalTo: backgroundView.trailingAnchor, constant: -25),
                locationButton.leadingAnchor.constraint(equalTo: backgroundView.leadingAnchor, constant: 25),
                locationButton.heightAnchor.constraint(equalToConstant: 36.0),

                cancelButton.topAnchor.constraint(equalTo: locationButton.bottomAnchor, constant: 16)
            ])

        case .choices:
            NSLayoutConstraint.activate([
                textLabel.topAnchor.constraint(equalTo: backgroundView.topAnchor, constant: 25),
                textLabel.trailingAnchor.constraint(equalTo: backgroundView.trailingAnchor, constant: -25),
                textLabel.leadingAnchor.constraint(equalTo: backgroundView.leadingAnchor, constant: 25),

                buttonsStackView.topAnchor.constraint(equalTo: textLabel.bottomAnchor, constant: 16),
                buttonsStackView.trailingAnchor.constraint(equalTo: backgroundView.trailingAnchor, constant: -25),
                buttonsStackView.leadingAnchor.constraint(equalTo: backgroundView.leadingAnchor, constant: 25),
                cancelButton.topAnchor.constraint(equalTo: buttonsStackView.bottomAnchor, constant: 16)
            ])

        case .card:
            NSLayoutConstraint.activate([
                backgroundImageView.topAnchor.constraint(equalTo: backgroundView.topAnchor, constant: 0),
                backgroundImageView.trailingAnchor.constraint(equalTo: backgroundView.trailingAnchor, constant: 0),
                backgroundImageView.leadingAnchor.constraint(equalTo: backgroundView.leadingAnchor, constant: 0),
                backgroundImageView.heightAnchor.constraint(equalToConstant: 200),

                imageView.topAnchor.constraint(equalTo: backgroundImageView.topAnchor, constant: 0),
                imageView.trailingAnchor.constraint(equalTo: backgroundImageView.trailingAnchor, constant: 0),
                imageView.leadingAnchor.constraint(equalTo: backgroundImageView.leadingAnchor, constant: 0),
                imageView.bottomAnchor.constraint(equalTo: backgroundImageView.bottomAnchor, constant: 0),

                placeholderImageView.centerXAnchor.constraint(equalTo: backgroundImageView.centerXAnchor, constant: 0),
                placeholderImageView.centerYAnchor.constraint(equalTo: imageView.centerYAnchor, constant: 0),
                placeholderImageView.heightAnchor.constraint(equalToConstant: 100),
                placeholderImageView.widthAnchor.constraint(equalToConstant: 100),

                titleLabel.topAnchor.constraint(equalTo: imageView.bottomAnchor, constant: 25),
                titleLabel.trailingAnchor.constraint(equalTo: backgroundView.trailingAnchor, constant: -25),
                titleLabel.leadingAnchor.constraint(equalTo: backgroundView.leadingAnchor, constant: 25),

                textLabel.topAnchor.constraint(equalTo: titleLabel.bottomAnchor, constant: 16),
                textLabel.trailingAnchor.constraint(equalTo: backgroundView.trailingAnchor, constant: -25),
                textLabel.leadingAnchor.constraint(equalTo: backgroundView.leadingAnchor, constant: 25),

                buttonsStackView.topAnchor.constraint(equalTo: textLabel.bottomAnchor, constant: 16),
                buttonsStackView.trailingAnchor.constraint(equalTo: backgroundView.trailingAnchor, constant: -25),
                buttonsStackView.leadingAnchor.constraint(equalTo: backgroundView.leadingAnchor, constant: 25),

                cancelButton.topAnchor.constraint(equalTo: buttonsStackView.bottomAnchor, constant: 16)
            ])

        case .carousel(let cardModels, let choices):
            var constraints: [NSLayoutConstraint] = [
                horizontalScrollView.topAnchor.constraint(equalTo: backgroundView.topAnchor, constant: 0),
                horizontalScrollView.trailingAnchor.constraint(equalTo: backgroundView.trailingAnchor, constant: 0),
                horizontalScrollView.leadingAnchor.constraint(equalTo: backgroundView.leadingAnchor, constant: 0),

                horizontalContentView.topAnchor.constraint(equalTo: horizontalScrollView.topAnchor, constant: 0),
                horizontalContentView.trailingAnchor.constraint(equalTo: horizontalScrollView.trailingAnchor, constant: 0),
                horizontalContentView.leadingAnchor.constraint(equalTo: horizontalScrollView.leadingAnchor, constant: 0),
                horizontalContentView.bottomAnchor.constraint(equalTo: horizontalScrollView.bottomAnchor, constant: 0),
                horizontalContentView.heightAnchor.constraint(equalTo: horizontalScrollView.heightAnchor, constant: 0.0),

                cardsStackView.topAnchor.constraint(equalTo: horizontalContentView.topAnchor, constant: 0),
                cardsStackView.trailingAnchor.constraint(equalTo: horizontalContentView.trailingAnchor, constant: 0),
                cardsStackView.leadingAnchor.constraint(equalTo: horizontalContentView.leadingAnchor, constant: 0),
                cardsStackView.bottomAnchor.constraint(equalTo: horizontalContentView.bottomAnchor, constant: 0)
            ]

            for card in cards {
                constraints.append(card.widthAnchor.constraint(equalTo: backgroundView.widthAnchor, constant: 0))
            }

            constraints.append(contentsOf: [
                pageControl.topAnchor.constraint(equalTo: horizontalScrollView.bottomAnchor, constant: 2),
                pageControl.trailingAnchor.constraint(equalTo: backgroundView.trailingAnchor, constant: -25),
                pageControl.leadingAnchor.constraint(equalTo: backgroundView.leadingAnchor, constant: 25),
                pageControl.heightAnchor.constraint(equalToConstant: 8)
            ])

            if cardModels.count == 1 {
                constraints.append(lineView.topAnchor.constraint(equalTo: cardsStackView.bottomAnchor, constant: 8))
            } else {
                constraints.append(lineView.topAnchor.constraint(equalTo: pageControl.bottomAnchor, constant: 16))
            }

            constraints.append(contentsOf: [
                lineView.trailingAnchor.constraint(equalTo: backgroundView.trailingAnchor, constant: 0),
                lineView.leadingAnchor.constraint(equalTo: backgroundView.leadingAnchor, constant: 0),
                lineView.heightAnchor.constraint(equalToConstant: 1),

                buttonsStackView.topAnchor.constraint(equalTo: lineView.bottomAnchor, constant: 16),
                buttonsStackView.trailingAnchor.constraint(equalTo: backgroundView.trailingAnchor, constant: -25),
                buttonsStackView.leadingAnchor.constraint(equalTo: backgroundView.leadingAnchor, constant: 25),

                cardsStackView.widthAnchor.constraint(
                    equalTo: backgroundView.widthAnchor,
                    multiplier: CGFloat(max(cards.count, 1))
                )
            ])

            if choices.isEmpty {
                constraints.append(cancelButton.topAnchor.constraint(equalTo: lineView.bottomAnchor, constant: 16))
            } else {
                constraints.append(cancelButton.topAnchor.constraint(equalTo: buttonsStackView.bottomAnchor, constant: 16))
            }

            NSLayoutConstraint.activate(constraints)
        }
    }

    func layoutTrait(traitCollection: UITraitCollection) {
        if traitCollection.horizontalSizeClass == .compact && traitCollection.verticalSizeClass == .regular {
            if regularConstraints.contains(where: \.isActive) {
                NSLayoutConstraint.deactivate(regularConstraints)
            }
            NSLayoutConstraint.activate(compactConstraints)
        } else {
            if compactConstraints.contains(where: \.isActive) {
                NSLayoutConstraint.deactivate(compactConstraints)
            }
            NSLayoutConstraint.activate(regularConstraints)
        }
    }

    // MARK: - Actions

    @objc private func choiceButtonTapped(_ sender: InAppTitleButton) {
        sender.flashTappedAppearance()

        let index = sender.tag
        guard choices.indices.contains(index) else { return }
        delegate?.didSelect(choice: choices[index])
    }

    @objc private func imageTapped() {
        guard let mediaURLString, let url = URL(string: mediaURLString) else { return }
        delegate?.didSelectMedia(url: url)
    }

    @objc private func openMaps() {
        guard case .location(let location) = message.body else { return }
        delegate?.didSelect(choice: InAppChoice(title: location.label, action: .location(location)))
    }

    func scrollViewWillEndDragging(
        _ scrollView: UIScrollView,
        withVelocity velocity: CGPoint,
        targetContentOffset: UnsafeMutablePointer<CGPoint>
    ) {
        guard scrollView == horizontalScrollView else { return }

        targetContentOffset.pointee.x = InAppScrollViewHelper.targetContentOffset(
            scrollView: scrollView,
            velocity: velocity,
            pageWidth: pageWidth
        )
    }

    func scrollViewDidEndDecelerating(_ scrollView: UIScrollView) {
        guard scrollView == horizontalScrollView else { return }

        let page = InAppScrollViewHelper.currentPage(scrollView: scrollView, pageWidth: pageWidth)
        pageControl.currentPage = Int(page)
    }

    // MARK: - Media

    private func setImageFromURL(_ urlString: String) {
        // The separate `placeholderImageView` covers the empty state, so the
        // image view itself stays empty until the real image arrives.
        InAppImageLoader.shared.load(
            URL(string: urlString),
            into: imageView
        ) { [weak self] image in
            guard let self, let image else { return }

            if image.isDark {
                self.closeButton.setImage(self.theme.lightCloseButtonImage, for: .normal)
            } else {
                self.closeButton.setImage(self.theme.darkCloseButtonImage, for: .normal)
            }
        }
    }
}

extension InAppMessageView: InAppCardViewDelegate {

    func didSelect(choice: InAppChoice, in card: InAppCard) {
        delegate?.didSelect(choice: choice)
    }

    func didSelectMedia(url: URL, in card: InAppCard) {
        delegate?.didSelectMedia(url: url)
    }
}
