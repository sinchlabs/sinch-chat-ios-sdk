import Foundation
import SwiftProtobuf

/// Turns the push payload into an `InAppMessage`.
///
/// Both entry points look for the same two fields: `owner` must be `sinch` and
/// `protobufPayload` must be a base64-encoded
/// `Sinch_Conversationapi_Type_AppMessage`. Anything else is "not an in-app
/// message", not an error.
public enum InAppMessageParser {

    public static let ownerKey = "owner"
    public static let payloadKey = "protobufPayload"
    public static let sinchOwner = "sinch"

    /// Parses an APNs payload (`UNNotificationRequest.content.userInfo` or the
    /// raw launch dictionary).
    public static func message(fromUserInfo userInfo: [AnyHashable: Any]) -> InAppMessage? {
        guard let owner = userInfo[ownerKey] as? String, owner == sinchOwner else { return nil }
        guard let encoded = userInfo[payloadKey] as? String else { return nil }
        return message(fromBase64: encoded)
    }

    /// Parses the `[String: String]` metadata of a relay message.
    public static func message(fromRelayMetadata metadata: [String: String]) -> InAppMessage? {
        guard let owner = metadata[ownerKey], owner == sinchOwner else { return nil }
        guard let encoded = metadata[payloadKey] else { return nil }
        return message(fromBase64: encoded)
    }

    static func message(fromBase64 encoded: String) -> InAppMessage? {
        guard let data = Data(base64Encoded: encoded) else { return nil }
        return message(fromProtobufData: data)
    }

    static func message(fromProtobufData data: Data) -> InAppMessage? {
        guard let appMessage = try? Sinch_Conversationapi_Type_AppMessage(serializedBytes: data),
              let content = appMessage.message else {
            return nil
        }

        switch content {
        case .textMessage(let text):
            return InAppMessage(body: .text(text: text.text))

        case .mediaMessage(let media):
            return InAppMessage(body: .media(url: media.url))

        case .locationMessage(let location):
            return InAppMessage(body: .location(locationModel(location)))

        case .choiceMessage(let choiceMessage):
            return InAppMessage(
                body: .choices(
                    text: choiceMessage.textMessage.text,
                    choices: choices(from: choiceMessage.choices)
                )
            )

        case .cardMessage(let card):
            return InAppMessage(body: .card(cardModel(card)))

        case .carouselMessage(let carousel):
            return InAppMessage(
                body: .carousel(
                    cards: carousel.cards.map(cardModel),
                    choices: choices(from: carousel.choices)
                )
            )
        }
    }

    // MARK: - Mapping

    /// Mirrors `DefaultMessageDataSource.createChoicesArray`.
    ///
    /// A `Choice` without any of the four known content types stops the list,
    /// which is what the chat SDK did: an unrecognised choice cannot be
    /// rendered and truncating is better than shifting the remaining buttons.
    static func choices(from protobufChoices: [Sinch_Conversationapi_Type_Choice]) -> [InAppChoice] {
        var result: [InAppChoice] = []

        for choice in protobufChoices {
            guard let content = choice.choice else { break }

            switch content {
            case .textMessage(let text):
                result.append(
                    InAppChoice(
                        title: text.text,
                        action: .text(postbackData: choice.postbackData)
                    )
                )

            case .urlMessage(let url):
                result.append(
                    InAppChoice(
                        title: url.title,
                        action: .url(url.url)
                    )
                )

            case .callMessage(let call):
                result.append(
                    InAppChoice(
                        title: call.title,
                        action: .call(phoneNumber: call.phoneNumber)
                    )
                )

            case .locationMessage(let location):
                result.append(
                    InAppChoice(
                        title: location.title,
                        action: .location(locationModel(location))
                    )
                )
            }
        }

        return result
    }

    static func cardModel(_ card: Sinch_Conversationapi_Type_CardMessage) -> InAppCard {
        InAppCard(
            title: card.title,
            description: card.description_p,
            media: card.mediaMessage.url,
            choices: choices(from: card.choices)
        )
    }

    static func locationModel(_ location: Sinch_Conversationapi_Type_LocationMessage) -> InAppLocation {
        InAppLocation(
            title: location.title,
            label: location.label,
            latitude: Double(location.coordinates.latitude),
            longitude: Double(location.coordinates.longitude)
        )
    }
}
