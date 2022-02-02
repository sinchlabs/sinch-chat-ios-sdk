import UIKit

enum MediaType {
    case image(UIImage)
    
    var convertToSinchMedia: Sinch_Chat_Sdk_V1alpha2_UploadMediaRequest? {
        var request = Sinch_Chat_Sdk_V1alpha2_UploadMediaRequest()
        var data: Data?
        var mimeType: String

        switch self {
        case .image(let image):
            data = image.jpegData(compressionQuality: 0.8)
            mimeType = "image/jpg"
        }
        
        guard let data = data else { return nil }
        request.data = data
        request.mimeType = mimeType

        return request
       
        }
    
}
