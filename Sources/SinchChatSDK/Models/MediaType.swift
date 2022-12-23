import UIKit
import AVFoundation

enum MediaType {
    case image(UIImage)
    case video(URL)
    case audio(URL)
    
    var convertToSinchMedia: Sinch_Chat_Sdk_V1alpha2_UploadMediaRequest? {
        var request = Sinch_Chat_Sdk_V1alpha2_UploadMediaRequest()
        var data: Data?
        var mimeType: String
        
        switch self {
        case .image(let image):
            data = image.jpegData(compressionQuality: 0.8)
            mimeType = "image/jpg"
            
        case .audio(let url):
            do {
                data =  try Data(contentsOf: url)
                mimeType = "audio/mp4"
            
            } catch {
                mimeType = "audio/mp4"
            }
        case .video(let url):
            do {
                data =  try Data(contentsOf: url)
                mimeType = "video/mp4"
            
            } catch {
                mimeType = "video/mp4"
            }
        }
        guard let data = data else { return nil }
        request.data = data
        request.mimeType = mimeType
        
        return request
    }
}
