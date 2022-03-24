import Foundation
import UIKit
protocol MediaViewerViewModel {
    
    var delegate: MediaViewerModelDelegate? { get }
    var mediaMessage: Message { get }
}
protocol MediaViewerModelDelegate: AnyObject {
}

final class DefaultMediaViewerViewModel: MediaViewerViewModel {

    weak var delegate: MediaViewerModelDelegate?
    var mediaMessage: Message

    init(mediaMessage: Message) {
        self.mediaMessage = mediaMessage
    }
}
