import Foundation
import UIKit
protocol InboxViewModel {
    
    var delegate: InboxViewModelDelegate? { get }
    var apiClient: APIClient { get }
    var authDataSource: AuthDataSource { get }

    func closeChannel() 

}
protocol InboxViewModelDelegate: AnyObject {
}

final class DefaultInboxViewModel: InboxViewModel {

    weak var delegate: InboxViewModelDelegate?
    private let pushPermissionHandler: PushNofiticationPermissionHandler
    var apiClient: APIClient
    var authDataSource: AuthDataSource
    
    init(pushPermissionHandler: PushNofiticationPermissionHandler, apiClient: APIClient, authDataSource: AuthDataSource) {
        self.pushPermissionHandler = pushPermissionHandler
        self.apiClient = apiClient
        self.authDataSource = authDataSource
    }
    
    func closeChannel() {
        apiClient.closeChannel()
    }
}
