import UIKit

class SinchView: UIView {

    init() {
        super.init(frame: .zero)
        commonInit()
    }

    @available(*, unavailable, message: "Use init")
    required init?(coder: NSCoder) {
        fatalError()
    }

    func commonInit() {
        setupProperties()
        setupSubviews()
        setupConstraints()
    }

    func setupSubviews() {}
    func setupConstraints() {}
    func setupProperties() {}
}
