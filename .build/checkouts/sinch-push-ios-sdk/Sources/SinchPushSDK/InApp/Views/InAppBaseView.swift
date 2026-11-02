import UIKit

/// Base class for the in-app alert views: a theme instead of the chat UI config.
open class InAppBaseView: UIView {

    public let theme: InAppMessageTheme

    public init(theme: InAppMessageTheme) {
        self.theme = theme
        super.init(frame: .zero)
        commonInit()
    }

    @available(*, unavailable, message: "Use init(theme:)")
    public required init?(coder: NSCoder) {
        fatalError()
    }

    public func commonInit() {
        setupProperties()
        setupSubviews()
        setupConstraints()
    }

    open func setupProperties() {}
    open func setupSubviews() {}
    open func setupConstraints() {}
}

/// A view controller whose `view` is a typed in-app view.
open class InAppBaseViewController<T, V: InAppBaseView>: UIViewController {

    public let viewModel: T
    public let mainView: V

    public init(viewModel: T, view: V) {
        self.mainView = view
        self.viewModel = viewModel
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable, message: "Use init(viewModel:view:)")
    public required init?(coder: NSCoder) {
        fatalError()
    }

    public override func loadView() {
        view = mainView
    }

    func applyNavigationBarStyle() {
        let attributes: [NSAttributedString.Key: Any] = [
            .foregroundColor: mainView.theme.mediaViewerTintColor,
            .font: UIFont.boldSystemFont(ofSize: 16)
        ]

        let appearance = UINavigationBarAppearance()
        appearance.configureWithOpaqueBackground()
        appearance.backgroundColor = mainView.theme.mediaViewerBackgroundColor
        appearance.titleTextAttributes = attributes

        navigationItem.standardAppearance = appearance
        navigationItem.compactAppearance = appearance
        navigationItem.scrollEdgeAppearance = appearance
        navigationController?.navigationBar.tintColor = mainView.theme.mediaViewerTintColor
    }

    func addCloseButton() {
        navigationItem.leftBarButtonItem = UIBarButtonItem(
            image: UIImage(systemName: "xmark"),
            style: .plain,
            target: self,
            action: #selector(closeAction)
        )
    }

    @objc func closeAction() {
        dismiss(animated: true)
    }
}
