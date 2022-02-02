import Foundation
import UIKit

public extension SinchSDKConfig {
    
    struct UIConfig {
        
        public static let defaultValue = UIConfig()
        
        public var navigationBarText = "Sinch Chat"
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
        public var inputPlaceholderText: String? = "Type message here"
        public var inputPlaceholderTextColor = UIColor(named: "primaryTextColor", in: Bundle.staticBundle, compatibleWith: nil)!
        
        // MARK: - Images

        public var photoImage = UIImage(named: "photoIcon", in: Bundle.staticBundle, compatibleWith: nil)
        public var emojiImage = UIImage(named: "emojiIcon", in: Bundle.staticBundle, compatibleWith: nil)
        public var sendImage = UIImage(named: "sendIcon", in: Bundle.staticBundle, compatibleWith: nil)
        public var chatBotImage = UIImage(named: "chatBotIcon", in: Bundle.staticBundle, compatibleWith: nil)

    }
}
