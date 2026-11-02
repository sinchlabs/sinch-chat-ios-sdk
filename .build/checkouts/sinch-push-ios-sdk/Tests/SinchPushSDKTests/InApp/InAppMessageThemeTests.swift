import UIKit
import XCTest
@testable import SinchPushSDK

/// Proves the asset catalogue and the strings ship inside the resource bundle,
/// which is the part `resources:` in `Package.swift` (and `resource_bundles` in
/// the podspec) can silently get wrong.
@MainActor
final class InAppMessageThemeTests: XCTestCase {

    func testDefaultThemeLoadsBundledColours() {
        for name in [
            "primaryInAppMessageBackground",
            "inAppTextColor",
            "inAppButtonTitleColor",
            "inAppMessageButtonBackgroundColor",
            "tappedButtonBackgroundColor",
            "inAppBorderColor",
            "inAppImageBackgroundColor",
            "inAppCarouselSeparatorColor",
            "primaryPageControlColor",
            "secondaryPageControlColor"
        ] {
            XCTAssertNotNil(InAppBundle.color(name), "missing colour \(name)")
        }
    }

    func testDefaultThemeLoadsBundledImages() {
        for name in ["inAppCloseIcon", "inAppDarkCloseIcon", "inAppLightCloseIcon", "inAppLocationIcon", "mediaPlaceholder"] {
            XCTAssertNotNil(InAppBundle.image(name), "missing image \(name)")
        }
    }

    func testDefaultThemeLoadsBundledStrings() {
        let theme = InAppMessageTheme.default

        // `en` and `ar` both carry these at the moment; the point is that the
        // lookup finds a table at all instead of falling back to the key.
        XCTAssertEqual(theme.cancelButtonTitle, "CLOSE")
        XCTAssertEqual(theme.locationActionSheetTitle, "Choose app")
        XCTAssertEqual(theme.locationAppleMapsTitle, "Apple Maps")
        XCTAssertEqual(theme.locationGoogleMapsTitle, "Google Maps")
        XCTAssertEqual(theme.locationCancelTitle, "Cancel")
    }

    func testDefaultThemeMatchesChatDefaults() {
        let theme = InAppMessageTheme.default

        XCTAssertEqual(theme.cornerRadius, 10)
        XCTAssertEqual(theme.buttonTitleFont.pointSize, 14)
        XCTAssertEqual(theme.dimmingColor.cgColor.alpha, 0.7, accuracy: 0.01)
    }
}
