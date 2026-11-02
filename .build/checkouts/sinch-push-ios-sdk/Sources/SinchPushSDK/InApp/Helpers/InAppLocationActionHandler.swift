import UIKit

/// Offers the location in Apple or Google Maps.
@MainActor
final class InAppLocationActionHandler {

    private let theme: InAppMessageTheme

    init(theme: InAppMessageTheme) {
        self.theme = theme
    }

    func handleOpenLocation(_ viewController: UIViewController, title: String?, latitude: Double, longitude: Double) {
        let alert = UIAlertController(
            title: theme.locationActionSheetTitle,
            message: "",
            preferredStyle: .actionSheet
        )

        alert.addAction(
            UIAlertAction(title: theme.locationAppleMapsTitle, style: .default) { _ in
                InAppChoiceHandler.openAppleMaps(title: title, latitude: latitude, longitude: longitude)
            }
        )

        alert.addAction(
            UIAlertAction(title: theme.locationGoogleMapsTitle, style: .default) { _ in
                InAppChoiceHandler.openGoogleMaps(latitude: latitude, longitude: longitude)
            }
        )

        alert.addAction(UIAlertAction(title: theme.locationCancelTitle, style: .cancel))

        alert.popoverPresentationController?.sourceView = viewController.view
        viewController.present(alert, animated: true)
    }
}
