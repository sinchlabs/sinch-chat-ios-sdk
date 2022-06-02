enum MessageType {
    case text(String)
    case choiceResponseMessage(postbackData: String, entryID: String)
    case image(String)
    
    var convertToSinchMessage: Sinch_Chat_Sdk_V1alpha2_SendRequest? {
        var request = Sinch_Chat_Sdk_V1alpha2_SendRequest()
        var contactMessage = Sinch_Conversationapi_Type_ContactMessage()
        
        switch self {
        case .text(let text):
            
            var messageText = Sinch_Conversationapi_Type_TextMessage()
                messageText.text = text
            contactMessage.message = .textMessage(messageText)
        case let .choiceResponseMessage(postbackData, entryID):
            
            var messageChoice = Sinch_Conversationapi_Type_ChoiceResponseMessage()
            messageChoice.postbackData = postbackData
            messageChoice.messageID = entryID
            contactMessage.choiceResponseMessage = messageChoice
        case .image(let urlString):
            
            var messageImage = Sinch_Conversationapi_Type_MediaMessage()
            messageImage.url = urlString
            contactMessage.message = .mediaMessage(messageImage)
        }
        
        request.message = contactMessage
        return request
       
    }
}
