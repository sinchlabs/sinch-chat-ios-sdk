import Foundation
import UIKit
protocol MediaViewerViewModel {
    
    var delegate: MediaViewerModelDelegate? { get }
    var mediaMessage: MessageImage { get }
}
protocol MediaViewerModelDelegate: AnyObject {
}

final class DefaultMediaViewerViewModel: MediaViewerViewModel {

    weak var delegate: MediaViewerModelDelegate?
    var mediaMessage: MessageImage

    init(mediaMessage: MessageImage) {
        self.mediaMessage = mediaMessage
    }
}
