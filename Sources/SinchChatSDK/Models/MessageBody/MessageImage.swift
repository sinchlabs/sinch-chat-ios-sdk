import UIKit

struct MessageImage: MessageBody {
    
    var url: String
    var sendDate: Int64?

    init(url: String, sendDate: Int64?, placeholderImage: UIImage?) {
        self.url = url
        self.sendDate = sendDate

    }
    func convertStringToImage(strBase64: String) -> UIImage? {
        
        if let data = Data(base64Encoded: strBase64, options: .ignoreUnknownCharacters) {
            return UIImage(data: data)
        } else {
            return nil
        }
    }
}
