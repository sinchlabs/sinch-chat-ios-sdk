import UIKit

extension UIImage {

    /// Whether the top-right quarter is mostly dark. Used to pick the close
    /// icon that stays visible on the alert's media.
    var isDark: Bool {
        let rightHigh = CGRect(
            x: size.width - size.width / 4,
            y: 0,
            width: size.width / 4,
            height: size.height / 4
        )
        guard let cropped = cgImage?.cropping(to: rightHigh) else { return false }
        return cropped.isDark
    }
}

extension CGImage {

    var isDark: Bool {
        guard let imageData = dataProvider?.data, let ptr = CFDataGetBytePtr(imageData) else { return false }

        let length = CFDataGetLength(imageData)
        let threshold = Int(Double(width * height) * 0.45)
        var darkPixels = 0

        for counter in stride(from: 0, to: length, by: 4) {
            let red = ptr[counter]
            let green = ptr[counter + 1]
            let blue = ptr[counter + 2]
            let luminance = 0.299 * Double(red) + 0.587 * Double(green) + 0.114 * Double(blue)
            if luminance < 150 {
                darkPixels += 1
                if darkPixels > threshold {
                    return true
                }
            }
        }

        return false
    }
}
