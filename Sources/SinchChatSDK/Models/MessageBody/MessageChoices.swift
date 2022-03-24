import Foundation

struct MessageChoices: MessageBody {
    
    var text: String
    var choices: [ChoiceMessageType]
    var sendDate: Int64?
}

enum ChoiceMessageType: Codable {
    
    case textMessage(ChoiceText)
    case urlMessage(ChoiceUrl)
    case callMessage(ChoiceCall)
    case locationMessage(ChoiceLocation)

}

struct ChoiceText: Codable {
    var text: String
}

struct ChoiceUrl: Codable {
    var url: String
    var text: String
}

struct ChoiceLocation: Codable {
    var text: String
    var label: String
    var latitude: Double
    var longitude: Double

}

struct ChoiceCall: Codable {
    var text: String
    var phoneNumber: String

}
