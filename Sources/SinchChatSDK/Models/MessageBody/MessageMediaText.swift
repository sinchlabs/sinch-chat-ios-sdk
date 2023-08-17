import Foundation

struct MessageMediaText: MessageBody, MessageWithURL, MessageWithText {
    var text: String
    var url: String
    var sendDate: Int64?
    var isExpanded: Bool = false

    func getText() -> String {
        return text
    }
    func getReadMore(maxCount: Int, textToAdd: String ) -> String {
        return text.prefix(maxCount) + "... " + "\(textToAdd)"
    }
}
