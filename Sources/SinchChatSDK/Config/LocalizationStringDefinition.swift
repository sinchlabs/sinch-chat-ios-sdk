import Foundation

public extension SinchSDKConfig {

    struct LocalizationConfig {

        public static let defaultValue = LocalizationConfig()
        
        public var inputPlaceholderText = NSLocalizedString("label_input_placeholder", bundle: Bundle.staticBundle, comment: "")
        public var navigationBarText = "Sinch chat"
        public var navigationBarImageViewText = NSLocalizedString("label_image", bundle: Bundle.staticBundle, comment: "")
        public var today = NSLocalizedString("label_today", bundle: Bundle.staticBundle, comment: "")
        public var yesterday = NSLocalizedString("label_yesterday", bundle: Bundle.staticBundle, comment: "")
        public var downloadFailed = NSLocalizedString("label_download_failed", bundle: Bundle.staticBundle, comment: "")
        public var tryingToDownload = NSLocalizedString("label_trying_download", bundle: Bundle.staticBundle, comment: "")
        public var connected = NSLocalizedString("label_connected", bundle: Bundle.staticBundle, comment: "")
        public var noInternetConnection = NSLocalizedString("label_no_internet_connection", bundle: Bundle.staticBundle, comment: "")
        public var alertMessageCouldNotLoadHistory = NSLocalizedString("alert_could_not_load_history", bundle: Bundle.staticBundle, comment: "")
        public var alertMessageNotSent = NSLocalizedString("alert_message_not_sent", bundle: Bundle.staticBundle, comment: "")
        public var alertTitleError = NSLocalizedString("alert_title_error", bundle: Bundle.staticBundle, comment: "")
        public var alertButtonTitleOk = NSLocalizedString("alert_button_title_ok", bundle: Bundle.staticBundle, comment: "")
        public var menuTitleOptions = NSLocalizedString("menu_title_options", bundle: Bundle.staticBundle, comment: "")
        public var menuButtonTitleCopy = NSLocalizedString("menu_button_title_copy", bundle: Bundle.staticBundle, comment: "")

    }
}
