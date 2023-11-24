import UIKit

final class InboxView: SinchView {
    
    var tableView: UITableView
    
    override init(uiConfiguration: SinchSDKConfig.UIConfig, localizationConfiguration: SinchSDKConfig.LocalizationConfig) {
        
        tableView = UITableView()
        tableView.register(InboxTableViewCell.self, forCellReuseIdentifier: "inboxCell")

        super.init(uiConfiguration: uiConfiguration, localizationConfiguration: localizationConfiguration)
        
    }
    
    override func setupSubviews() {
        backgroundColor = uiConfig.inboxBackgroundColor
        tableView.translatesAutoresizingMaskIntoConstraints = false
        addSubview(tableView)
       
    }
    override func setupConstraints() {
        
        tableView.topAnchor.constraint(equalTo:  safeAreaLayoutGuide.topAnchor).isActive = true
        tableView.leadingAnchor.constraint(equalTo: safeAreaLayoutGuide.leadingAnchor).isActive = true
        tableView.bottomAnchor.constraint(equalTo:  safeAreaLayoutGuide.bottomAnchor).isActive = true
        tableView.trailingAnchor.constraint(equalTo: safeAreaLayoutGuide.trailingAnchor).isActive = true
    }
}
