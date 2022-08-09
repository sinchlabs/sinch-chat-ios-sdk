import UIKit

public protocol ImagePickerDelegate: AnyObject {
    func didSelect(image: UIImage?)
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
        pickerController.mediaTypes = ["public.image"]
    }
    
    func pickPhoto() {
        if UIImagePickerController.isSourceTypeAvailable(.photoLibrary) {
            presentationController?.present(self.pickerController, animated: true)
        }
    }
    
    private func pickerController(_ controller: UIImagePickerController, didSelect image: UIImage?) {
        controller.dismiss(animated: true, completion: nil)
        
        delegate?.didSelect(image: image)
    }
}
extension ImagePickerHelper: UIImagePickerControllerDelegate, UINavigationControllerDelegate {
    
    public func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
        pickerController(picker, didSelect: nil)
    }
    
    public func imagePickerController(_ picker: UIImagePickerController,
                                      didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]) {
        guard let image = info[.editedImage] as? UIImage else {
            return pickerController(picker, didSelect: nil)
        }
        
        pickerController(picker, didSelect: image)
    }
}
