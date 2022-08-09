import Foundation

struct MessageMediaText: MessageBody, MessageWithURL, MessageWithText {
    var text: String
    var url: String
    var sendDate: Int64?
    
    func getText() -> String {
        return text
    }
}
