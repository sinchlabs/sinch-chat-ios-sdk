import Foundation
import GRPC
import Swift

enum MessageError: Error {
    case notSupported
}

struct Message: Encodable {
    let owner: Owner
    let body: MessageBody
    
    enum CodingKeys: String, CodingKey {
        case owner
        case body
    }
    func encode(to encoder: Encoder) throws {
        var cod = encoder.container(keyedBy: CodingKeys.self)
        try cod.encode(owner, forKey: .owner)
        
        if let textMessage = body as? MessageText {
            try cod.encode(textMessage, forKey: .body)
        } else if let messageImage = body as? MessageImage {
            try cod.encode(messageImage, forKey: .body)
        } else if let messageEvent = body as? MessageEvent {
            try cod.encode(messageEvent, forKey: .body)
        }
    }
    
    init(owner: Owner, body: MessageBody) {
        self.owner = owner
        self.body = body
    }
    
    func isFromCurrentUser() -> Bool {
        switch owner {
            
        case .outgoing:
            return true
        case .incoming(_):
            return false
        case .system:
            return false
        }
    }
}

extension Message: Decodable {
    init(from decoder: Swift.Decoder) throws {
        let dec = try decoder.container(keyedBy: CodingKeys.self)
        owner = try dec.decode(Owner.self, forKey: .owner)
        
        if case .system = owner {
            if let messageEvent = try? dec.decode(MessageEvent.self, forKey: .body) {
                body = messageEvent
            } else {
                throw MessageError.notSupported
            }
        } else {
            if let textMessage = try? dec.decode(MessageText.self, forKey: .body) {
                body = textMessage
            } else if let messageImage = try? dec.decode(MessageImage.self, forKey: .body) {
                body = messageImage
            } else {
                throw MessageError.notSupported
            }
        }
    }
}
extension Message {
    var convertToSinchMessage: Sinch_Chat_Sdk_V1alpha2_SendRequest? {
        var request = Sinch_Chat_Sdk_V1alpha2_SendRequest()
        var contactMessage = Sinch_Conversationapi_Type_ContactMessage()
        
        switch body {
        case let text as MessageText:
            var messageText = Sinch_Conversationapi_Type_TextMessage()
            messageText.text = text.text
            contactMessage.message = .textMessage(messageText)

        default:
            return nil
        }
        request.message = contactMessage
        return request
    }
}
