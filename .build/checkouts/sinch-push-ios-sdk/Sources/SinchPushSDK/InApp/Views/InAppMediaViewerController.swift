import UIKit

/// Full-screen media viewer opened by tapping an alert's image.
@MainActor
final class InAppMediaViewerController: InAppBaseViewController<URL, InAppMediaViewerView> {

    override func viewDidLoad() {
        super.viewDidLoad()

        InAppImageLoader.shared.load(viewModel, into: mainView.imageView)

        let swipeDown = UISwipeGestureRecognizer(target: self, action: #selector(respondToSwipeGesture))
        swipeDown.direction = .down
        view.addGestureRecognizer(swipeDown)
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        applyNavigationBarStyle()
        addCloseButton()
    }

    @objc private func respondToSwipeGesture(gesture: UIGestureRecognizer) {
        guard let swipe = gesture as? UISwipeGestureRecognizer, swipe.direction == .down else { return }
        closeAction()
    }

    static func make(for url: URL, theme: InAppMessageTheme) -> UIViewController {
        let controller = InAppMediaViewerController(viewModel: url, view: InAppMediaViewerView(theme: theme))
        let navigation = UINavigationController(rootViewController: controller)
        navigation.modalPresentationStyle = .fullScreen
        navigation.modalTransitionStyle = .crossDissolve
        return navigation
    }
}

final class InAppMediaViewerView: InAppBaseView {

    lazy var zoomingScrollView: UIScrollView = {
        let scrollView = UIScrollView(frame: bounds)
        scrollView.backgroundColor = theme.mediaViewerBackgroundColor
        scrollView.alwaysBounceVertical = false
        scrollView.alwaysBounceHorizontal = false
        scrollView.showsVerticalScrollIndicator = true
        scrollView.flashScrollIndicators()
        scrollView.minimumZoomScale = 1.0
        scrollView.maximumZoomScale = 3.0
        scrollView.contentInsetAdjustmentBehavior = .never
        return scrollView
    }()

    lazy var imageView: UIImageView = {
        let view = UIImageView(frame: .zero)
        view.backgroundColor = theme.mediaViewerBackgroundColor
        view.contentMode = .scaleAspectFit
        view.isUserInteractionEnabled = true
        return view
    }()

    override func setupSubviews() {
        backgroundColor = theme.mediaViewerBackgroundColor
        zoomingScrollView.addSubview(imageView)
        addSubview(zoomingScrollView)
    }

    override func setupConstraints() {
        zoomingScrollView.translatesAutoresizingMaskIntoConstraints = false
        zoomingScrollView.fillSuperview()

        imageView.translatesAutoresizingMaskIntoConstraints = false
        imageView.contentMode = .scaleAspectFit

        NSLayoutConstraint.activate([
            imageView.topAnchor.constraint(equalTo: safeAreaLayoutGuide.topAnchor),
            imageView.bottomAnchor.constraint(equalTo: safeAreaLayoutGuide.bottomAnchor),
            imageView.leadingAnchor.constraint(equalTo: safeAreaLayoutGuide.leadingAnchor),
            imageView.trailingAnchor.constraint(equalTo: safeAreaLayoutGuide.trailingAnchor)
        ])
    }
}

extension UIView {

    func fillSuperview() {
        guard let superview else { return }
        translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            leftAnchor.constraint(equalTo: superview.leftAnchor),
            rightAnchor.constraint(equalTo: superview.rightAnchor),
            topAnchor.constraint(equalTo: superview.topAnchor),
            bottomAnchor.constraint(equalTo: superview.bottomAnchor)
        ])
    }
}
