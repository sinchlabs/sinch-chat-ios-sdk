import UIKit

class SinchView: UIView {
    
    var uiConfig = SinchSDKConfig.UIConfig.defaultValue
    var localizationConfiguration = SinchSDKConfig.LocalizationConfig.defaultValue
    
    init() {
               
        super.init(frame: .zero)
        commonInit()
    }
    
    init(uiConfiguration: SinchSDKConfig.UIConfig, localizationConfiguration: SinchSDKConfig.LocalizationConfig) {
        self.uiConfig = uiConfiguration
        self.localizationConfiguration = localizationConfiguration
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
