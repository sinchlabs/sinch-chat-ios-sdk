import UIKit
import AVFoundation
import Photos
import MobileCoreServices

public protocol ImagePickerDelegate: AnyObject {
    func didSelect(image: UIImage?)
    func didSelect(video: URL?)

}

final class ImagePickerHelper: NSObject {
    
    private var pickerController: UIImagePickerController = UIImagePickerController()
    private weak var presentationController: UIViewController?
    private weak var delegate: ImagePickerDelegate?
    
    public init(presentationController: UIViewController, delegate: ImagePickerDelegate) {
        
        super.init()
        
        self.presentationController = presentationController
        self.delegate = delegate
        pickerController.delegate = self
        pickerController.allowsEditing = true
        pickerController.sourceType = .photoLibrary
       
    }
    
    func pickPhotoFromGallery() {
        if UIImagePickerController.isSourceTypeAvailable(.photoLibrary) {
            var mediaTypes: [String] = []
            if !SinchChatSDK.shared.disabledFeatures.contains(.sendImageMessageFromGallery) {
                mediaTypes.append(kUTTypeImage as String)
            }
            if !SinchChatSDK.shared.disabledFeatures.contains(.sendVideoMessageFromGallery) {
                mediaTypes.append(contentsOf: [kUTTypeMovie as String, kUTTypeVideo as String, kUTTypeMPEG4 as String])
            }
            pickerController.mediaTypes = mediaTypes
            self.pickerController.videoMaximumDuration = 15
            self.pickerController.sourceType = .photoLibrary
            self.presentationController?.present(self.pickerController, animated: true)
        }
    }
    
    func takePhoto(completion: @escaping (_ success:Bool) -> Void ) {
        if UIImagePickerController.isSourceTypeAvailable(.camera) {
            
            pickerController.sourceType = .camera
            pickerController.cameraCaptureMode = .photo
                pickerController.mediaTypes = [kUTTypeImage as String]
            AVCaptureDevice.requestAccess(for: AVMediaType.video,
                                          completionHandler: { (granted:Bool) -> Void in
                if granted {
                    
                    DispatchQueue.main.async {
                        self.presentationController?.present(self.pickerController, animated: true)
                    }
                    completion(true)
                } else {
                    completion(false)
                }
            })
        } else {
            completion(false)
        }
    }
    
    private func pickerController(_ controller: UIImagePickerController, didSelect image: UIImage?) {
        controller.dismiss(animated: true, completion: nil)
        delegate?.didSelect(image: image)
    }
    private func pickerController(_ controller: UIImagePickerController, didSelectVideo video: URL) {
        
        controller.dismiss(animated: true, completion: nil)
        delegate?.didSelect(video: video)
    }
}
extension ImagePickerHelper: UIImagePickerControllerDelegate, UINavigationControllerDelegate {
    
    public func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
        pickerController(picker, didSelect: nil)
    }
    
    public func imagePickerController(_ picker: UIImagePickerController,
                                      didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]) {
        
        if let image = info[.editedImage] as? UIImage {
            pickerController(picker, didSelect: image)

        } else if let url = info[.mediaURL] as? URL {
         
            self.pickerController(picker, didSelectVideo: url)
            
        } else {
                pickerController(picker, didSelect: nil)
        }
    }
}
