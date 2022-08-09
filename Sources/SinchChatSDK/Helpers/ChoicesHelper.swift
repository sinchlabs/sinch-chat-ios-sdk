import UIKit
import Foundation

class ChoicesHelper {
    
    static func callNumber(phoneNumber:String) {
        let trimmedPhoneNumber = phoneNumber.replacingOccurrences(of: " ", with: "")
        if let phoneCallURL = URL(string: "tel://\(trimmedPhoneNumber)") {
            
            let application = UIApplication.shared
            if application.canOpenURL(phoneCallURL) {
                application.open(phoneCallURL, options: [:], completionHandler: nil)
            }
        }
    }
    
    static func openAppleMaps(choice: ChoiceLocation) {
        guard let title = choice.text.replacingOccurrences(of: " ", with: "+").addingPercentEncoding(withAllowedCharacters: .urlHostAllowed) else {
            return
        }
        let directionsURL = "http://maps.apple.com/?q=\(title)&ll=\(choice.latitude),\(choice.longitude)"
        guard let url = URL(string: directionsURL) else {
            return
        }
        
        UIApplication.shared.open(url, options: [:], completionHandler: nil)
        
    }
    
}
