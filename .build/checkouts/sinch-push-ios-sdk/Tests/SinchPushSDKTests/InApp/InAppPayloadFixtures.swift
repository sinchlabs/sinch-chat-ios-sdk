import Foundation
@testable import SinchPushSDK

/// Builds the base64 `protobufPayload` the backend sends, so the parser tests
/// exercise the real wire format instead of a hand-written dictionary.
enum InAppPayloadFixtures {

    static func text(_ text: String) -> Sinch_Conversationapi_Type_AppMessage {
        Sinch_Conversationapi_Type_AppMessage.with {
            $0.textMessage = Sinch_Conversationapi_Type_TextMessage.with { $0.text = text }
        }
    }

    static func media(_ url: String) -> Sinch_Conversationapi_Type_AppMessage {
        Sinch_Conversationapi_Type_AppMessage.with {
            $0.mediaMessage = Sinch_Conversationapi_Type_MediaMessage.with { $0.url = url }
        }
    }

    static func location(
        title: String,
        label: String,
        latitude: Float,
        longitude: Float
    ) -> Sinch_Conversationapi_Type_AppMessage {
        Sinch_Conversationapi_Type_AppMessage.with {
            $0.locationMessage = locationMessage(
                title: title,
                label: label,
                latitude: latitude,
                longitude: longitude
            )
        }
    }

    static func locationMessage(
        title: String,
        label: String,
        latitude: Float,
        longitude: Float
    ) -> Sinch_Conversationapi_Type_LocationMessage {
        Sinch_Conversationapi_Type_LocationMessage.with {
            $0.title = title
            $0.label = label
            $0.coordinates = Sinch_Conversationapi_Type_Coordinates.with {
                $0.latitude = latitude
                $0.longitude = longitude
            }
        }
    }

    static func choices(
        text: String,
        _ choices: [Sinch_Conversationapi_Type_Choice]
    ) -> Sinch_Conversationapi_Type_AppMessage {
        Sinch_Conversationapi_Type_AppMessage.with {
            $0.choiceMessage = Sinch_Conversationapi_Type_ChoiceMessage.with {
                $0.textMessage = Sinch_Conversationapi_Type_TextMessage.with { $0.text = text }
                $0.choices = choices
            }
        }
    }

    static func card(_ card: Sinch_Conversationapi_Type_CardMessage) -> Sinch_Conversationapi_Type_AppMessage {
        Sinch_Conversationapi_Type_AppMessage.with {
            $0.cardMessage = card
        }
    }

    static func carousel(
        cards: [Sinch_Conversationapi_Type_CardMessage],
        choices: [Sinch_Conversationapi_Type_Choice] = []
    ) -> Sinch_Conversationapi_Type_AppMessage {
        Sinch_Conversationapi_Type_AppMessage.with {
            $0.carouselMessage = Sinch_Conversationapi_Type_CarouselMessage.with {
                $0.cards = cards
                $0.choices = choices
            }
        }
    }

    static func cardMessage(
        title: String,
        description: String,
        media: String,
        choices: [Sinch_Conversationapi_Type_Choice] = []
    ) -> Sinch_Conversationapi_Type_CardMessage {
        Sinch_Conversationapi_Type_CardMessage.with {
            $0.title = title
            $0.description_p = description
            $0.mediaMessage = Sinch_Conversationapi_Type_MediaMessage.with { $0.url = media }
            $0.choices = choices
        }
    }

    // MARK: - Choices

    static func textChoice(title: String, postbackData: String) -> Sinch_Conversationapi_Type_Choice {
        Sinch_Conversationapi_Type_Choice.with {
            $0.textMessage = Sinch_Conversationapi_Type_TextMessage.with { $0.text = title }
            $0.postbackData = postbackData
        }
    }

    static func urlChoice(title: String, url: String) -> Sinch_Conversationapi_Type_Choice {
        Sinch_Conversationapi_Type_Choice.with {
            $0.urlMessage = Sinch_Conversationapi_Type_UrlMessage.with {
                $0.title = title
                $0.url = url
            }
        }
    }

    static func callChoice(title: String, phoneNumber: String) -> Sinch_Conversationapi_Type_Choice {
        Sinch_Conversationapi_Type_Choice.with {
            $0.callMessage = Sinch_Conversationapi_Type_CallMessage.with {
                $0.title = title
                $0.phoneNumber = phoneNumber
            }
        }
    }

    static func locationChoice(
        title: String,
        label: String,
        latitude: Float,
        longitude: Float
    ) -> Sinch_Conversationapi_Type_Choice {
        Sinch_Conversationapi_Type_Choice.with {
            $0.locationMessage = locationMessage(
                title: title,
                label: label,
                latitude: latitude,
                longitude: longitude
            )
        }
    }

    // MARK: - Payloads

    /// The base64 string that goes into `protobufPayload`.
    static func base64(_ message: Sinch_Conversationapi_Type_AppMessage) -> String {
        // A fixture that cannot serialise is a broken test, not a broken parser.
        (try? message.serializedData().base64EncodedString()) ?? ""
    }

    /// An APNs `userInfo` carrying `message`.
    static func userInfo(_ message: Sinch_Conversationapi_Type_AppMessage) -> [AnyHashable: Any] {
        [
            "owner": "sinch",
            "protobufPayload": base64(message)
        ]
    }

    /// Relay `metadata` carrying `message`.
    static func relayMetadata(_ message: Sinch_Conversationapi_Type_AppMessage) -> [String: String] {
        [
            "owner": "sinch",
            "protobufPayload": base64(message)
        ]
    }

    /// A payload that is not an in-app message at all.
    static let foreignMetadata: [String: String] = [
        "owner": "sinch",
        "protobufPayload": "bm90IGEgcHJvdG9idWYgbWVzc2FnZQ=="
    ]
}
