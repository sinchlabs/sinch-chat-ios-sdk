import UIKit

struct MessageVoice: MessageBody, MessageWithURL {
    var url: String
    var sendDate: Int64?

    init(url: String, sendDate: Int64?, placeholderImage: UIImage?) {
        self.url = url
        self.sendDate = sendDate

    }
}
