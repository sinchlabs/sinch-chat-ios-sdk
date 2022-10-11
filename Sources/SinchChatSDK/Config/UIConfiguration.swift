import Foundation
import UIKit

public extension SinchSDKConfig {
    
    struct UIConfig {
        
        public static let defaultValue = UIConfig()
        
        public var navigationBarColor = UIColor(named: "primaryThemeColor", in: Bundle.staticBundle, compatibleWith: nil)!
        public var navigationBarTitleColor = UIColor(named: "primaryNavigationBarTextColor", in: Bundle.staticBundle, compatibleWith: nil)!

        public var backgroundColor = UIColor(named: "primaryBackgroundColor", in: Bundle.staticBundle, compatibleWith: nil)!
    
        // MARK: - Outgoing messages user interface settings
        public var outgoingMessageBackgroundColor = UIColor(named: "primaryBubbleBackgroundColor", in: Bundle.staticBundle, compatibleWith: nil)!
        
        public var outgoingMessageTextColor = UIColor(named: "primaryTextColor", in: Bundle.staticBundle, compatibleWith: nil)!
        var outgoingMessageSenderNameFont = UIFont.preferredFont(forTextStyle: .body)

        // MARK: - Incoming messages user interface settings
        
        public var incomingMessageBackgroundColor = UIColor(named: "secondaryBubbleBackgroundColor", in: Bundle.staticBundle, compatibleWith: nil)!
        public var incomingMessageTextColor = UIColor(named: "primaryTextColor", in: Bundle.staticBundle, compatibleWith: nil)!
        
        public var incomingMessageChatbotBackgroundColor = UIColor(named: "secondaryBackgroundColor", in: Bundle.staticBundle, compatibleWith: nil)!
        public var incomingMessageSenderBackgroundColor = UIColor(named: "primaryThemeColor", in: Bundle.staticBundle, compatibleWith: nil)!
        public var incomingMessageSenderNameTextColor = UIColor(named: "secondaryTextColor", in: Bundle.staticBundle, compatibleWith: nil)!
        var incomingMessageSenderNameFont = UIFont.systemFont(ofSize: 18)
            
        // MARK: - Common user interface settings
        
        public var messageUrlLinkTextColor = UIColor(named: "primaryLinkColor", in: Bundle.staticBundle, compatibleWith: nil)!
        public var dateMessageLabelTextColor = UIColor(named: "primaryDateTextColor", in: Bundle.staticBundle, compatibleWith: nil)!
        public var buttonTitleColor = UIColor(named: "buttonTitleColor", in: Bundle.staticBundle, compatibleWith: nil)!
        public var tappedButtonTitleColor = UIColor(named: "tappedButtonTitleColor", in: Bundle.staticBundle, compatibleWith: nil)!
        public var buttonTitleFont = UIFont.boldSystemFont(ofSize: 14)
        public var buttonBackgroundColor = UIColor(named: "buttonBackgroundColor", in: Bundle.staticBundle, compatibleWith: nil)!
        public var tappedButtonBackgroundColor = UIColor(named: "tappedButtonBackgroundColor", in: Bundle.staticBundle, compatibleWith: nil)!
        public var locationDotColor = UIColor(named: "primaryThemeColor", in: Bundle.staticBundle, compatibleWith: nil)!

        // MARK: - System messages user interface settings
        
        public var systemEventTextColor = UIColor(named: "ternaryTextColor", in: Bundle.staticBundle, compatibleWith: nil)!
        public var systemEventBackgroundColor = UIColor(named: "primaryEventBackgroundColor", in: Bundle.staticBundle, compatibleWith: nil)!

        public var systemDateTextColor = UIColor(named: "primaryTextColor", in: Bundle.staticBundle, compatibleWith: nil)!
        public var systemDateBackgroundColor = UIColor(named: "primaryDateBackgroundColor", in: Bundle.staticBundle, compatibleWith: nil)!
        
        // MARK: - Input view

        public var inputBarBackgroundColor = UIColor(named: "primaryInputBackgroundColor", in: Bundle.staticBundle, compatibleWith: nil)!
        public var inputTextViewBackgroundColor: UIColor = UIColor(named: "primaryBackgroundColor", in: Bundle.staticBundle, compatibleWith: nil)!
        public var inputTextViewBorderColor: UIColor =  UIColor(named: "primaryBorderColor", in: Bundle.staticBundle, compatibleWith: nil)!
        public var inputTextColor = UIColor(named: "primaryTextColor", in: Bundle.staticBundle, compatibleWith: nil)!
        public var inputPlaceholderTextColor = UIColor(named: "primaryTextColor", in: Bundle.staticBundle, compatibleWith: nil)!
        // MARK: - Images

        public var photoImage = UIImage(named: "photoIcon", in: Bundle.staticBundle, compatibleWith: nil)
        public var plusImage = UIImage(named: "plusIcon", in: Bundle.staticBundle, compatibleWith: nil)
        public var voiceRecordingImage = UIImage(named: "recordVoiceIcon", in: Bundle.staticBundle, compatibleWith: nil)

        public var emojiImage = UIImage(named: "emojiIcon", in: Bundle.staticBundle, compatibleWith: nil)
        public var sendImage = UIImage(named: "sendIcon", in: Bundle.staticBundle, compatibleWith: nil)
        public var chatBotImage = UIImage(named: "chatBotIcon", in: Bundle.staticBundle, compatibleWith: nil)
        public var locationMessageImage = UIImage(named: "locationIcon", in: Bundle.staticBundle, compatibleWith: nil)
        public var locationMarkerImage = UIImage(named: "locationIcon", in: Bundle.staticBundle, compatibleWith: nil)
        public var menuButtonTextColor = UIColor(named: "primaryTextColor", in: Bundle.staticBundle, compatibleWith: nil)!

        public var shareLocationMenuImage = UIImage(named: "locationBlueIcon", in: Bundle.staticBundle, compatibleWith: nil)
        public var pageControlSelectedColor = UIColor(named: "primaryPageControlColor", in: Bundle.staticBundle, compatibleWith: nil)
        public var pageControlUnselectedColor = UIColor(named: "secondaryPageControlColor", in: Bundle.staticBundle, compatibleWith: nil)
        
        public var playButtonImage = UIImage(named: "playIcon", in: Bundle.staticBundle, compatibleWith: nil)
        public var pauseButtonImage = UIImage(named: "pauseIcon", in: Bundle.staticBundle, compatibleWith: nil)
        public var primaryAudioBarBackgroundColor = UIColor(named: "primaryAudioBarBackgroundColor", in: Bundle.staticBundle, compatibleWith: nil)!
        public var topAudioBarBackgroundColor = UIColor(named: "secondaryAudioBarBackgroundColor", in: Bundle.staticBundle, compatibleWith: nil)!
        public var recordingRedColor = UIColor(named: "primaryRedColor", in: Bundle.staticBundle, compatibleWith: nil)!
        
        public var recordButtonImage = UIImage(named: "recordIcon", in: Bundle.staticBundle, compatibleWith: nil)
        public var sendFilledImage = UIImage(named: "sendFilledIcon", in: Bundle.staticBundle, compatibleWith: nil)
        public var deleteImage = UIImage(named: "deleteIcon", in: Bundle.staticBundle, compatibleWith: nil)
        public var progressBarBackgroundColor = UIColor(named: "primaryProgressBarBackgroundColor", in: Bundle.staticBundle, compatibleWith: nil)!
        public var scrollToBottomImage = UIImage(named: "scrollToBottomIcon", in: Bundle.staticBundle, compatibleWith: nil)

        // MARK: - InAppMessaging
        
        public var inAppMessageBackgroundColor = UIColor(named: "primaryInAppMessageBackground", in: Bundle.staticBundle, compatibleWith: nil)!
        public var inAppMessageinAppCloseImage = UIImage(named: "inAppCloseIcon", in: Bundle.staticBundle, compatibleWith: nil)
        public var inAppMessageDarkCloseImage = UIImage(named: "inAppDarkCloseIcon", in: Bundle.staticBundle, compatibleWith: nil)
        public var inAppMessageLightCloseImage = UIImage(named: "inAppLightCloseIcon", in: Bundle.staticBundle, compatibleWith: nil)
        public var inAppMessageButtonTitleColor = UIColor(named: "inAppButtonTitleColor", in: Bundle.staticBundle, compatibleWith: nil)!
        public var inAppMessageTappedButtonTitleColor = UIColor(named: "tappedButtonTitleColor", in: Bundle.staticBundle, compatibleWith: nil)!

        public var inAppMessageButtonBackgroundColor = UIColor(named: "inAppMessageButtonBackgroundColor", in: Bundle.staticBundle, compatibleWith: nil)!
        public var inAppMessageButtonTappedBackgroundColor = UIColor(named: "tappedButtonBackgroundColor", in: Bundle.staticBundle, compatibleWith: nil)!

        public var inAppMessageButtonTitleFont = UIFont.boldSystemFont(ofSize: 14)
        public var inAppMessageTextFont = UIFont.preferredFont(forTextStyle: .body)
        public var inAppMessageTitleFont = UIFont(descriptor:
                                                    UIFontDescriptor.preferredFontDescriptor(withTextStyle: .title3).withSymbolicTraits(.traitBold) ?? UIFontDescriptor(),
                                                  size: 0.0)

        public var inAppMessageMaybeLaterButtonTitleColor = UIColor(named: "inAppMaybeButtonTitleColor", in: Bundle.staticBundle, compatibleWith: nil)!
        public var inAppMessageMaybeLaterButtonBorderColor = UIColor(named: "inAppMaybeButtonBorderColor", in: Bundle.staticBundle, compatibleWith: nil)!
        public var inAppMessageTextColor = UIColor(named: "inAppTextColor", in: Bundle.staticBundle, compatibleWith: nil)!
        public var inAppMessageImagePlaceholder = UIImage(named: "mediaPlaceholder", in: Bundle.staticBundle, compatibleWith: nil)
        public var inAppMessageImageBackgroundColor = UIColor(named:  "inAppImageBackgroundColor", in: Bundle.staticBundle, compatibleWith: nil)
        
    }
}
