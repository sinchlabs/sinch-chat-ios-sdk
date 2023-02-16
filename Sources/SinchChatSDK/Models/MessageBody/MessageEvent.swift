import Foundation

enum EventType: Codable {
    
    case joined(Agent)
    case left(Agent)
    case composeStarted
    case composeEnd
    
    
    var convertToSinchEvent: Sinch_Chat_Sdk_V1alpha2_SendRequest? {
        var request = Sinch_Chat_Sdk_V1alpha2_SendRequest()
        var eventMessage = Sinch_Conversationapi_Type_ContactEvent()
        
        switch self {
        case .composeStarted:
            eventMessage.event = .composingEvent(Sinch_Conversationapi_Type_ComposingEvent())
        
        case .composeEnd:
            
            eventMessage.event = .composingEndEvent(Sinch_Conversationapi_Type_ComposingEndEvent())
        default:
            
            return nil

    }
        request.event = eventMessage
        return request
       
    }
}

struct MessageEvent: MessageBody {
    
    var type: EventType
    var sendDate: Int64?
    
    var text: String {
        let message: String
        
        switch type {
          
            // TODO : - Add Localization
        case .joined(let agent):
        message  = (agent.type == 1 ? "\(agent.name)" : "Chatbot" )
                    + " joined the conversation"

        case .left(let agent):
            
        message = (agent.type == 1 ? "\(agent.name)" : "Chatbot")
        + " left the conversation"
        case .composeStarted:
            message = ""
        case .composeEnd:
            message = ""
        }
        return message
    }
}

struct Agent: Codable {
    
    var name: String
    var type: Int
    var pictureUrl: String?
    
}
