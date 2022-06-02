import UIKit

class TitleButton: UIButton {

    // MARK: - Initialization
    convenience init() {
        self.init(frame: .zero)
    }

    override init(frame: CGRect) {
        super.init(frame: frame)
        setup()
    }

    required init?(coder aDecoder: NSCoder) {
        super.init(coder: aDecoder)
        setup()
    }

    private func setup() {
        backgroundColor = UIColor.white
        layer.cornerRadius = 10
        layer.masksToBounds = true
        titleEdgeInsets = UIEdgeInsets(top: 0.0, left: 8.0, bottom: 0.0, right: 8.0)
    }
   
}
