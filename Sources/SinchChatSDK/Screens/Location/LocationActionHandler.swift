import Foundation
import UIKit

internal class LocationActionHandler {
    private let localization: SinchSDKConfig.LocalizationConfig
    
    init(_ localization: SinchSDKConfig.LocalizationConfig) {
        self.localization = localization
    }
    
    func handleOpenLocationAction(_ viewController: UIViewController, title: String?, latitude: Double, longitude: Double) {

        let alert = UIAlertController(title: localization.locationOpenActionSheetTitle, message: "", preferredStyle: .actionSheet)
                
        let appleMapsAction = UIAlertAction(title: localization.locationOpenAppleMaps, style: .default) {_ in
            LocationActionHandler.openAppleMaps(title: title, latitude: latitude, longitude: longitude)
        }
        alert.addAction(appleMapsAction)
        
        let googleMapsAction = UIAlertAction(title: localization.locationOpenGoogleMaps, style: .default) {_ in
            LocationActionHandler.openGoogleMaps(latitude: latitude, longitude: longitude)
        }
        
        alert.addAction(googleMapsAction)
        alert.popoverPresentationController?.sourceView = viewController.view
        
        viewController.present(alert, animated: true)
    }
    
    private static func openAppleMaps(title: String?, latitude: Double, longitude: Double) {
        let directionsURL = "http://maps.apple.com/?q=\(title ?? "")&ll=\(latitude),\(longitude)"
        print(directionsURL)
        guard let url = URL(string: directionsURL) else {
            return
        }
    
        UIApplication.shared.open(url, options: [:], completionHandler: nil)
    }
    
    private static func openGoogleMaps(latitude: Double, longitude: Double) {
        let directionsURL = "https://maps.google.com/?q=\(latitude),\(longitude)"
        guard let url = URL(string: directionsURL) else {
            return
        }
        
        UIApplication.shared.open(url, options: [:], completionHandler: nil)
    }
}
