import UIKit
import AVFoundation
import Photos
import UniformTypeIdentifiers

@MainActor
public protocol ImagePickerDelegate: AnyObject {
    func didSelect(image: UIImage?)
    func didSelect(video: URL?)

}

@MainActor
final class ImagePickerHelper: NSObject {

    private var pickerController: UIImagePickerController = UIImagePickerController()
    private weak var presentationController: UIViewController?
    private weak var delegate: ImagePickerDelegate?
    /// True from the moment the library picker is shown until it reports its dismissal once.
    private var isPickerPresented = false

    public init(presentationController: UIViewController, delegate: ImagePickerDelegate) {

        super.init()

        self.presentationController = presentationController
        self.delegate = delegate
        pickerController.delegate = self
        pickerController.allowsEditing = true
        pickerController.sourceType = .photoLibrary
    }

    /// Media types the photo library picker offers, honouring the disabled features.
    static func galleryMediaTypes(disabledFeatures: Set<SinchEnabledFeatures>) -> [String] {
        var mediaTypes: [String] = []
        if !disabledFeatures.contains(.sendImageMessageFromGallery) {
            mediaTypes.append(UTType.image.identifier)
        }
        if !disabledFeatures.contains(.sendVideoMessageFromGallery) {
            mediaTypes.append(contentsOf: [UTType.movie.identifier, UTType.video.identifier, UTType.mpeg4Movie.identifier])
        }
        return mediaTypes
    }

    /// The photo library on compact width keeps the style a fresh `UIImagePickerController` has, which is what 2.1.0
    /// presented: the system sheet that swipes down. A test pins it to the system default.
    static let compactStyle: UIModalPresentationStyle = .formSheet

    /// Shows the photo library. On regular width it is a popover pointing at `anchor` (captured when the user tapped
    /// the control, because the control may be gone by now); on compact width it is the system sheet as before.
    func pickPhotoFromGallery(anchor: PopoverPresentation.Anchor? = nil) {
        if UIImagePickerController.isSourceTypeAvailable(.photoLibrary) {
            pickerController.mediaTypes = Self.galleryMediaTypes(disabledFeatures: SinchChatSDK.shared.disabledFeatures)

            self.pickerController.videoMaximumDuration = 15
            self.pickerController.sourceType = .photoLibrary

            if let anchor {
                PopoverPresentation.prepareAsPopover(pickerController, anchor: anchor, compactStyle: Self.compactStyle) { [weak self] in
                    self?.handleInteractiveDismissal()
                }
            } else {
                PopoverPresentation.prepareAsPopover(pickerController, source: nil, fallbackView: presentationController?.view,
                                                     compactStyle: Self.compactStyle) { [weak self] in
                    self?.handleInteractiveDismissal()
                }
            }
            isPickerPresented = true
            self.presentationController?.present(self.pickerController, animated: true, completion: {
                if let presentationController = self.presentationController as? StartViewController {
                    presentationController.removeKeyboardObservers()
                }
            })
        }
    }

    func takePhoto(completion: @escaping (_ success:Bool) -> Void ) {
        if UIImagePickerController.isSourceTypeAvailable(.camera) {

            pickerController.sourceType = .camera
            // The camera is a full-screen experience on every device; only the library becomes a popover.
            pickerController.modalPresentationStyle = .fullScreen
            var mode: UIImagePickerController.CameraCaptureMode = .photo

            var mediaTypes: [String] = []
            if !SinchChatSDK.shared.disabledFeatures.contains(.sendImageFromCamera) {
                mediaTypes.append(UTType.image.identifier)
            }
            if !SinchChatSDK.shared.disabledFeatures.contains(.sendVideoMessageFromCamera) {
                mediaTypes.append(contentsOf: [UTType.movie.identifier, UTType.video.identifier, UTType.mpeg4Movie.identifier])
                if SinchChatSDK.shared.disabledFeatures.contains(.sendImageFromCamera) {
                    mode = .video

                }
            }

            pickerController.mediaTypes = mediaTypes
            pickerController.cameraCaptureMode = mode

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
        isPickerPresented = false
        controller.dismiss(animated: true, completion: nil)
        delegate?.didSelect(image: image)
        self.presentationController?.inputAccessoryView?.isHidden = false

    }
    private func pickerController(_ controller: UIImagePickerController, didSelectVideo video: URL) {

        isPickerPresented = false
        controller.dismiss(animated: true, completion: nil)
        self.presentationController?.inputAccessoryView?.isHidden = false

        delegate?.didSelect(video: video)

    }

    /// The user dismissed the picker without choosing (swipe down on a sheet, tap outside a popover).
    private func handleInteractiveDismissal() {
        guard isPickerPresented else { return }
        isPickerPresented = false
        self.presentationController?.inputAccessoryView?.isHidden = false
        delegate?.didSelect(image: nil)
    }
}
extension ImagePickerHelper: UIImagePickerControllerDelegate, UINavigationControllerDelegate {

    public func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
        pickerController(picker, didSelect: nil)
        self.presentationController?.inputAccessoryView?.isHidden = false

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
