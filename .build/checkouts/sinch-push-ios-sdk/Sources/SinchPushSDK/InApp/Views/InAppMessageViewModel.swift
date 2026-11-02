import Foundation

protocol InAppMessageViewModel {
    var message: InAppMessage { get }
}

final class DefaultInAppMessageViewModel: InAppMessageViewModel {

    let message: InAppMessage

    init(message: InAppMessage) {
        self.message = message
    }
}
