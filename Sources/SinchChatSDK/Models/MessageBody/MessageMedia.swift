import UIKit

enum TypeMessageMedia: Codable, Equatable {
    case image
    case audio
    case video
    case file(FileType?)
    case unsupported
    
}
enum FileType: String, Codable {
    case pdf = "PDF"
    case doc = "DOC"
    case docx = "DOCX"
    case xls = "XLS"
    case xlsx = "XLSX"
    case pptx = "PPTX"
    case ppt = "PPT"
    case gif = "GIF"
    case unknown = ""

    static func getFileType(urlExtension: String) -> FileType? {
        switch urlExtension {
        case "pdf":
            return .pdf
        case "doc":
            return .doc
        case "docx":
        return .docx
        case "xls":
        return .xls
        case "xlsx":
        return .xlsx
        case "pptx":
        return .pptx
        case "ppt":
        return .ppt
        case "gif":
            return .gif
        default:
            return nil
        }
    }
    
}
struct MessageMedia: MessageBody, MessageWithURL {
    
    var url: String
    var savedUrl: String?
    var sendDate: Int64?
    var type: TypeMessageMedia?
    var isExpanded: Bool = false
    var size: String?

    init(url: String, sendDate: Int64?, placeholderImage: UIImage? = nil, type: TypeMessageMedia? = nil) {
        self.url = url
        self.sendDate = sendDate
        self.type = type
    }
    func convertStringToImage(strBase64: String) -> UIImage? {
        
        if let data = Data(base64Encoded: strBase64, options: .ignoreUnknownCharacters) {
            return UIImage(data: data)
        } else {
            return nil
        }
    }
}
