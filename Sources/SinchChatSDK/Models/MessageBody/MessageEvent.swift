import Foundation

enum EventType: Codable {
    
    case joined(Agent)
    case left(Agent)
    
}

struct MessageEvent: MessageBody {
    
    var type: EventType
    var sendDate: Int64?
    
    var text: String {
        let message: String
        
        switch type {
            
        case .joined(let agent):
        message  = (agent.type == 1 ? "\(agent.name)" : "Chatbot" )
                    + " joined the conversation"

        case .left(let agent):
            
        message = (agent.type == 1 ? "\(agent.name)" : "Chatbot")
        + " left the conversation"
        }
        return message
    }
}

struct Agent: Codable {
    
    var name: String
    var type: Int
    var pictureUrl: String?
    
}
