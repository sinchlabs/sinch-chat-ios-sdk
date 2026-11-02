import UIKit

/// Colours, fonts, images and strings for the SDK-rendered in-app alerts.
///
/// `InAppMessageTheme.default` reproduces the previous SinchChatSDK look. Set
/// `InAppMessages.shared.theme` before the first alert arrives; a theme change
/// applies to the next alert, not the one already on screen.
public struct InAppMessageTheme {

    // MARK: - Container

    /// Card background.
    public var backgroundColor: UIColor
    /// Dimming behind the card.
    public var dimmingColor: UIColor
    /// Corner radius of the card and of the buttons.
    public var cornerRadius: CGFloat

    // MARK: - Text

    public var textColor: UIColor
    public var titleFont: UIFont
    public var textFont: UIFont

    // MARK: - Buttons

    public var buttonTitleFont: UIFont
    public var buttonBackgroundColor: UIColor
    public var buttonTitleColor: UIColor
    public var buttonTappedBackgroundColor: UIColor
    public var tappedButtonTitleColor: UIColor
    public var cancelButtonBorderColor: UIColor
    public var cancelButtonTitleColor: UIColor

    // MARK: - Media

    public var imageBackgroundColor: UIColor
    public var imagePlaceholder: UIImage?
    /// Drawn in the top-right corner of media and card alerts. White.
    public var closeButtonImage: UIImage?
    /// Drawn on light media, for alerts whose close button sits on an image.
    public var darkCloseButtonImage: UIImage?
    /// Drawn on dark media.
    public var lightCloseButtonImage: UIImage?
    /// Media viewer background.
    public var mediaViewerBackgroundColor: UIColor
    public var mediaViewerTintColor: UIColor

    // MARK: - Location

    public var locationImage: UIImage?

    // MARK: - Carousel

    public var carouselSeparatorColor: UIColor
    public var pageIndicatorSelectedColor: UIColor
    public var pageIndicatorColor: UIColor

    // MARK: - Strings

    /// The `CLOSE` button under the text.
    public var cancelButtonTitle: String
    /// Accessibility label of the top-right close icon.
    public var closeButtonAccessibilityLabel: String
    public var locationActionSheetTitle: String
    public var locationAppleMapsTitle: String
    public var locationGoogleMapsTitle: String
    public var locationCancelTitle: String

    public init(
        backgroundColor: UIColor,
        dimmingColor: UIColor,
        cornerRadius: CGFloat,
        textColor: UIColor,
        titleFont: UIFont,
        textFont: UIFont,
        buttonTitleFont: UIFont,
        buttonBackgroundColor: UIColor,
        buttonTitleColor: UIColor,
        buttonTappedBackgroundColor: UIColor,
        tappedButtonTitleColor: UIColor,
        cancelButtonBorderColor: UIColor,
        cancelButtonTitleColor: UIColor,
        imageBackgroundColor: UIColor,
        imagePlaceholder: UIImage?,
        closeButtonImage: UIImage?,
        darkCloseButtonImage: UIImage?,
        lightCloseButtonImage: UIImage?,
        mediaViewerBackgroundColor: UIColor,
        mediaViewerTintColor: UIColor,
        locationImage: UIImage?,
        carouselSeparatorColor: UIColor,
        pageIndicatorSelectedColor: UIColor,
        pageIndicatorColor: UIColor,
        cancelButtonTitle: String,
        closeButtonAccessibilityLabel: String,
        locationActionSheetTitle: String,
        locationAppleMapsTitle: String,
        locationGoogleMapsTitle: String,
        locationCancelTitle: String
    ) {
        self.backgroundColor = backgroundColor
        self.dimmingColor = dimmingColor
        self.cornerRadius = cornerRadius
        self.textColor = textColor
        self.titleFont = titleFont
        self.textFont = textFont
        self.buttonTitleFont = buttonTitleFont
        self.buttonBackgroundColor = buttonBackgroundColor
        self.buttonTitleColor = buttonTitleColor
        self.buttonTappedBackgroundColor = buttonTappedBackgroundColor
        self.tappedButtonTitleColor = tappedButtonTitleColor
        self.cancelButtonBorderColor = cancelButtonBorderColor
        self.cancelButtonTitleColor = cancelButtonTitleColor
        self.imageBackgroundColor = imageBackgroundColor
        self.imagePlaceholder = imagePlaceholder
        self.closeButtonImage = closeButtonImage
        self.darkCloseButtonImage = darkCloseButtonImage
        self.lightCloseButtonImage = lightCloseButtonImage
        self.mediaViewerBackgroundColor = mediaViewerBackgroundColor
        self.mediaViewerTintColor = mediaViewerTintColor
        self.locationImage = locationImage
        self.carouselSeparatorColor = carouselSeparatorColor
        self.pageIndicatorSelectedColor = pageIndicatorSelectedColor
        self.pageIndicatorColor = pageIndicatorColor
        self.cancelButtonTitle = cancelButtonTitle
        self.closeButtonAccessibilityLabel = closeButtonAccessibilityLabel
        self.locationActionSheetTitle = locationActionSheetTitle
        self.locationAppleMapsTitle = locationAppleMapsTitle
        self.locationGoogleMapsTitle = locationGoogleMapsTitle
        self.locationCancelTitle = locationCancelTitle
    }
}

extension InAppMessageTheme {

    /// The look the in-app alerts had in SinchChatSDK, read from the bundled
    /// asset catalogue and `Localizable.strings`.
    public static var `default`: InAppMessageTheme {
        InAppMessageTheme(
            backgroundColor: InAppBundle.color("primaryInAppMessageBackground") ?? .systemBackground,
            dimmingColor: UIColor.black.withAlphaComponent(0.7),
            cornerRadius: 10,
            textColor: InAppBundle.color("inAppTextColor") ?? .label,
            titleFont: UIFont(
                descriptor: UIFontDescriptor
                    .preferredFontDescriptor(withTextStyle: .title3)
                    .withSymbolicTraits(.traitBold) ?? UIFontDescriptor(),
                size: 0
            ),
            textFont: .preferredFont(forTextStyle: .body),
            buttonTitleFont: .boldSystemFont(ofSize: 14),
            buttonBackgroundColor: InAppBundle.color("inAppMessageButtonBackgroundColor") ?? .secondarySystemBackground,
            buttonTitleColor: InAppBundle.color("inAppButtonTitleColor") ?? .label,
            buttonTappedBackgroundColor: InAppBundle.color("tappedButtonBackgroundColor") ?? .systemGray4,
            tappedButtonTitleColor: InAppBundle.color("tappedButtonTitleColor") ?? .label,
            cancelButtonBorderColor: InAppBundle.color("inAppBorderColor") ?? .separator,
            cancelButtonTitleColor: InAppBundle.color("inAppBorderColor") ?? .label,
            imageBackgroundColor: InAppBundle.color("inAppImageBackgroundColor") ?? .secondarySystemBackground,
            imagePlaceholder: InAppBundle.image("mediaPlaceholder"),
            closeButtonImage: InAppBundle.image("inAppCloseIcon"),
            darkCloseButtonImage: InAppBundle.image("inAppDarkCloseIcon"),
            lightCloseButtonImage: InAppBundle.image("inAppLightCloseIcon"),
            mediaViewerBackgroundColor: InAppBundle.color("primaryBackgroundColor") ?? .systemBackground,
            mediaViewerTintColor: InAppBundle.color("buttonTitleColor") ?? .label,
            locationImage: InAppBundle.image("inAppLocationIcon"),
            carouselSeparatorColor: InAppBundle.color("inAppCarouselSeparatorColor") ?? .separator,
            pageIndicatorSelectedColor: InAppBundle.color("primaryPageControlColor") ?? .label,
            pageIndicatorColor: InAppBundle.color("secondaryPageControlColor") ?? .systemGray4,
            cancelButtonTitle: InAppBundle.localized("button_title_close"),
            closeButtonAccessibilityLabel: InAppBundle.localized("button_title_close"),
            locationActionSheetTitle: InAppBundle.localized("location_action_sheet_title"),
            locationAppleMapsTitle: InAppBundle.localized("location_action_sheet_apple_maps"),
            locationGoogleMapsTitle: InAppBundle.localized("location_action_sheet_google_maps"),
            locationCancelTitle: InAppBundle.localized("button_title_cancel")
        )
    }
}
