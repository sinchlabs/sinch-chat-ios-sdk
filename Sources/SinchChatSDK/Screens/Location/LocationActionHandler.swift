import Foundation
import UIKit

@MainActor
internal class LocationActionHandler {
    private let localization: SinchSDKConfig.LocalizationConfig
    
    init(_ localization: SinchSDKConfig.LocalizationConfig) {
        self.localization = localization
    }
    
    /// Builds the "open in maps" action sheet. `source` is the control or cell the user tapped; on regular
    /// width the sheet is a popover pointing at it.
    func makeOpenLocationAlert(source: (any UIPopoverPresentationControllerSourceItem)?,
                               fallbackView: UIView?,
                               title: String?,
                               latitude: Double,
                               longitude: Double) -> UIAlertController {

        let alert = UIAlertController(title: localization.locationOpenActionSheetTitle, message: "", preferredStyle: .actionSheet)
                
        let appleMapsAction = UIAlertAction(title: localization.locationOpenAppleMaps, style: .default) {_ in
            LocationActionHandler.openAppleMaps(title: title, latitude: latitude, longitude: longitude)
        }
        alert.addAction(appleMapsAction)
        
        let googleMapsAction = UIAlertAction(title: localization.locationOpenGoogleMaps, style: .default) {_ in
            LocationActionHandler.openGoogleMaps(latitude: latitude, longitude: longitude)
        }
        
        alert.addAction(googleMapsAction)
        
        alert.addAction(UIAlertAction(title: localization.menuCancel, style: .cancel, handler: { _ in
            debugPrint("User click cancel button")
        }))
        PopoverPresentation.anchor(alert, to: source, fallbackView: fallbackView)
        return alert
    }

    func handleOpenLocationAction(_ viewController: UIViewController,
                                  source: (any UIPopoverPresentationControllerSourceItem)? = nil,
                                  title: String?,
                                  latitude: Double,
                                  longitude: Double) {
        let alert = makeOpenLocationAlert(source: source,
                                          fallbackView: viewController.view,
                                          title: title,
                                          latitude: latitude,
                                          longitude: longitude)
        viewController.present(alert, animated: true)
    }
    
    private static func openAppleMaps(title: String?, latitude: Double, longitude: Double) {
            
        let scheme = "http"
        let host = "maps.apple.com"
        let path = ""
        let queryItem1 = URLQueryItem(name: "q", value: (title ?? ""))
        let queryItem2 = URLQueryItem(name: "ll", value: "\(latitude),\(longitude)")

        var urlComponents = URLComponents()
        urlComponents.scheme = scheme
        urlComponents.host = host
        urlComponents.path = path
        urlComponents.queryItems = [queryItem1, queryItem2]

        if let url = urlComponents.url {
            UIApplication.shared.open(url, options: [:], completionHandler: nil)
            print(url)
        }
    }
    
    private static func openGoogleMaps(latitude: Double, longitude: Double) {
        let directionsURL = "https://maps.google.com/?q=\(latitude),\(longitude)"
        guard let url = URL(string: directionsURL) else {
            return
        }
        
        UIApplication.shared.open(url, options: [:], completionHandler: nil)
    }
}
