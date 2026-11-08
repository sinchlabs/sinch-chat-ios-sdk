import Foundation
import UIKit // internal only: the upload path still wants a `UIImage`. No UIKit type appears in a public signature.

extension SinchMedia {

    /// The internal upload representation, or `nil` when the data cannot be decoded.
    var mediaType: MediaType? {
        switch self {
        case .image(let data):
            return UIImage(data: data).map { MediaType.image($0) }
        case .video(let url):
            return .video(url)
        case .audio(let url):
            return .audio(url)
        case .file(let url):
            return .file(url, FileType.getFileType(urlExtension: url.pathExtension.lowercased()))
        }
    }

    /// How the sent message is typed, as `DefaultStartViewModel.createMediaMessage` does.
    var messageMediaType: TypeMessageMedia {
        switch self {
        case .image: return .image
        case .video: return .video
        case .audio: return .audio
        case .file(let url):
            let type = FileType.getFileType(urlExtension: url.pathExtension.lowercased())
            return type == .gif ? .image : .file(type)
        }
    }

    /// What to show while the upload runs: the local file, or nothing for in-memory image data.
    var localURLString: String {
        switch self {
        case .image: return ""
        case .video(let url), .audio(let url), .file(let url): return url.absoluteString
        }
    }

    var isFile: Bool {
        if case .file = self { return true }
        return false
    }
}
