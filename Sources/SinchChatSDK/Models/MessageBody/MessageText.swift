import Foundation

struct MessageText: MessageBody, MessageWithText {
    var text: String
    var sendDate: Int64?
    
    func getText() -> String {
        return text
    }
}
