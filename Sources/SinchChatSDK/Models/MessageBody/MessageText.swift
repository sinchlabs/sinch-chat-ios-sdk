import Foundation

struct MessageText: MessageBody, MessageWithText {
    var text: String
    var sendDate: Int64?
    var isExpanded: Bool = false

    func getText() -> String {
        return text
    }
    func getReadMore(maxCount: Int, textToAdd: String ) -> String {
        
        if text.count > maxCount && !isExpanded {
           
            return text.prefix(maxCount) + "... " + "\(textToAdd)"
            
        }
        
        return text
      
    }
}
