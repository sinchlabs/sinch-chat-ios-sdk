import UIKit

enum TypeMessageMedia: Codable {
    case image
    case audio
    case video
    case unsupported
}
struct MessageMedia: MessageBody, MessageWithURL {
    
    var url: String
    var sendDate: Int64?
    var type: TypeMessageMedia?

    init(url: String, sendDate: Int64?, placeholderImage: UIImage? = nil, type: TypeMessageMedia? = nil) {
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
