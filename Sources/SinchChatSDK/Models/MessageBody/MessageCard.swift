import Foundation

struct MessageCard: MessageBody {
    
    var title: String
    var description: String
    var choices: [ChoiceMessageType]
    var url: String
    var sendDate: Int64?
}
