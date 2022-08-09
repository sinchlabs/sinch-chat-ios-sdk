import Foundation

struct MessageCard: MessageBody, MessageWithURL, MessageWithChoices, MessageWithText {
    
    var title: String
    var description: String
    var choices: [ChoiceMessageType]
    var url: String
    var sendDate: Int64?
    
    func getText() -> String {
        return description
    }
}
