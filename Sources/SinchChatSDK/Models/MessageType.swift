import Foundation

enum MessageType {
    case text(String)
    case choiceResponseMessage(postbackData: String, entryID: String)
    case image(String)
    case location(latitude: Float, longitude: Float, localizationConfig: SinchSDKConfig.LocalizationConfig)
    
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
            
        case let .location(latitude, longitude, localizationConfig):
        
        var locationMessage = Sinch_Conversationapi_Type_LocationMessage()
            locationMessage.title = localizationConfig.outgoingLocationMessageTitle
        locationMessage.label = localizationConfig.outgoingLocationMessageButtonTitle


        var coordinates = Sinch_Conversationapi_Type_Coordinates()
        coordinates.latitude = latitude
        coordinates.longitude = longitude
        locationMessage.coordinates = coordinates
        contactMessage.message = .locationMessage(locationMessage)
    }
        request.message = contactMessage
        return request
       
    }
}
