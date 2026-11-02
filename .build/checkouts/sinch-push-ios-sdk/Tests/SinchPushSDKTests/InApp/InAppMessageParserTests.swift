import XCTest
@testable import SinchPushSDK

/// Every layout, from both ingest paths: APNs `userInfo` and relay metadata.
@MainActor
final class InAppMessageParserTests: XCTestCase {

    // MARK: - Text

    func testTextFromUserInfo() {
        let message = InAppMessageParser.message(fromUserInfo: InAppPayloadFixtures.userInfo(InAppPayloadFixtures.text("Hello")))

        XCTAssertEqual(message, InAppMessage(body: .text(text: "Hello")))
    }

    func testTextFromRelayMetadata() {
        let message = InAppMessageParser.message(
            fromRelayMetadata: InAppPayloadFixtures.relayMetadata(InAppPayloadFixtures.text("Hello"))
        )

        XCTAssertEqual(message, InAppMessage(body: .text(text: "Hello")))
    }

    // MARK: - Media

    func testMedia() {
        let expected = InAppMessage(body: .media(url: "https://cdn.example.com/a.png"))

        XCTAssertEqual(
            InAppMessageParser.message(fromUserInfo: InAppPayloadFixtures.userInfo(InAppPayloadFixtures.media("https://cdn.example.com/a.png"))),
            expected
        )
        XCTAssertEqual(
            InAppMessageParser.message(
                fromRelayMetadata: InAppPayloadFixtures.relayMetadata(InAppPayloadFixtures.media("https://cdn.example.com/a.png"))
            ),
            expected
        )
    }

    // MARK: - Location

    func testLocation() {
        let payload = InAppPayloadFixtures.location(title: "Sinch", label: "Kraków", latitude: 50.06, longitude: 19.94)
        let expected = InAppMessage(
            body: .location(
                // `Coordinates` is `float` on the wire, so the expected value is
                // the float round-trip, not the literal.
                InAppLocation(
                    title: "Sinch",
                    label: "Kraków",
                    latitude: Double(Float(50.06)),
                    longitude: Double(Float(19.94))
                )
            )
        )

        XCTAssertEqual(InAppMessageParser.message(fromUserInfo: InAppPayloadFixtures.userInfo(payload)), expected)
        XCTAssertEqual(
            InAppMessageParser.message(fromRelayMetadata: InAppPayloadFixtures.relayMetadata(payload)),
            expected
        )
    }

    // MARK: - Choices

    func testChoicesMapAllFourActions() {
        let payload = InAppPayloadFixtures.choices(
            text: "Pick one",
            [
                InAppPayloadFixtures.textChoice(title: "Yes", postbackData: "yes"),
                InAppPayloadFixtures.urlChoice(title: "Docs", url: "https://docs.example.com"),
                InAppPayloadFixtures.callChoice(title: "Call us", phoneNumber: "+48123456789"),
                InAppPayloadFixtures.locationChoice(title: "Office", label: "HQ", latitude: 50.06, longitude: 19.94)
            ]
        )

        let expected = InAppMessage(
            body: .choices(
                text: "Pick one",
                choices: [
                    InAppChoice(title: "Yes", action: .text(postbackData: "yes")),
                    InAppChoice(title: "Docs", action: .url("https://docs.example.com")),
                    InAppChoice(title: "Call us", action: .call(phoneNumber: "+48123456789")),
                    InAppChoice(
                        title: "Office",
                        action: .location(
                            InAppLocation(
                                title: "Office",
                                label: "HQ",
                                latitude: Double(Float(50.06)),
                                longitude: Double(Float(19.94))
                            )
                        )
                    )
                ]
            )
        )

        XCTAssertEqual(InAppMessageParser.message(fromUserInfo: InAppPayloadFixtures.userInfo(payload)), expected)
        XCTAssertEqual(
            InAppMessageParser.message(fromRelayMetadata: InAppPayloadFixtures.relayMetadata(payload)),
            expected
        )
    }

    func testChoiceWithoutPostbackUsesEmptyPostback() {
        let choice = Sinch_Conversationapi_Type_Choice.with {
            $0.textMessage = Sinch_Conversationapi_Type_TextMessage.with { $0.text = "Yes" }
        }

        let payload = InAppPayloadFixtures.choices(text: "Pick", [choice])
        let message = InAppMessageParser.message(fromRelayMetadata: InAppPayloadFixtures.relayMetadata(payload))

        XCTAssertEqual(
            message,
            InAppMessage(
                body: .choices(
                    text: "Pick",
                    choices: [InAppChoice(title: "Yes", action: .text(postbackData: ""))]
                )
            )
        )
    }

    // MARK: - Card

    func testCard() {
        let payload = InAppPayloadFixtures.card(
            InAppPayloadFixtures.cardMessage(
                title: "Title",
                description: "Description",
                media: "https://cdn.example.com/card.png",
                choices: [InAppPayloadFixtures.textChoice(title: "Open", postbackData: "open")]
            )
        )

        let expected = InAppMessage(
            body: .card(
                InAppCard(
                    title: "Title",
                    description: "Description",
                    media: "https://cdn.example.com/card.png",
                    choices: [InAppChoice(title: "Open", action: .text(postbackData: "open"))]
                )
            )
        )

        XCTAssertEqual(InAppMessageParser.message(fromUserInfo: InAppPayloadFixtures.userInfo(payload)), expected)
        XCTAssertEqual(
            InAppMessageParser.message(fromRelayMetadata: InAppPayloadFixtures.relayMetadata(payload)),
            expected
        )
    }

    // MARK: - Carousel

    func testCarousel() {
        let payload = InAppPayloadFixtures.carousel(
            cards: [
                InAppPayloadFixtures.cardMessage(
                    title: "One",
                    description: "First",
                    media: "https://cdn.example.com/1.png",
                    choices: [InAppPayloadFixtures.textChoice(title: "A", postbackData: "a")]
                ),
                InAppPayloadFixtures.cardMessage(
                    title: "Two",
                    description: "Second",
                    media: "https://cdn.example.com/2.png"
                )
            ],
            choices: [InAppPayloadFixtures.urlChoice(title: "All", url: "https://example.com")]
        )

        let expected = InAppMessage(
            body: .carousel(
                cards: [
                    InAppCard(
                        title: "One",
                        description: "First",
                        media: "https://cdn.example.com/1.png",
                        choices: [InAppChoice(title: "A", action: .text(postbackData: "a"))]
                    ),
                    InAppCard(
                        title: "Two",
                        description: "Second",
                        media: "https://cdn.example.com/2.png",
                        choices: []
                    )
                ],
                choices: [InAppChoice(title: "All", action: .url("https://example.com"))]
            )
        )

        XCTAssertEqual(InAppMessageParser.message(fromUserInfo: InAppPayloadFixtures.userInfo(payload)), expected)
        XCTAssertEqual(
            InAppMessageParser.message(fromRelayMetadata: InAppPayloadFixtures.relayMetadata(payload)),
            expected
        )
    }

    // MARK: - Rejections

    func testEmptyPayloadIsRejected() {
        XCTAssertNil(InAppMessageParser.message(fromUserInfo: [:]))
        XCTAssertNil(InAppMessageParser.message(fromRelayMetadata: [:]))
    }

    func testForeignOwnerIsRejected() {
        let payload = InAppPayloadFixtures.base64(InAppPayloadFixtures.text("Hello"))

        XCTAssertNil(InAppMessageParser.message(fromUserInfo: ["owner": "someone", "protobufPayload": payload]))
        XCTAssertNil(InAppMessageParser.message(fromRelayMetadata: ["owner": "someone", "protobufPayload": payload]))
    }

    func testMissingPayloadIsRejected() {
        XCTAssertNil(InAppMessageParser.message(fromUserInfo: ["owner": "sinch"]))
        XCTAssertNil(InAppMessageParser.message(fromRelayMetadata: ["owner": "sinch"]))
    }

    func testInvalidBase64IsRejected() {
        let metadata = ["owner": "sinch", "protobufPayload": "!!!not base64!!!"]
        XCTAssertNil(InAppMessageParser.message(fromRelayMetadata: metadata))
        XCTAssertNil(InAppMessageParser.message(fromUserInfo: metadata))
    }

    func testNonProtoPayloadIsRejected() {
        XCTAssertNil(InAppMessageParser.message(fromRelayMetadata: InAppPayloadFixtures.foreignMetadata))
        XCTAssertNil(InAppMessageParser.message(fromUserInfo: InAppPayloadFixtures.foreignMetadata))
    }

    func testAppMessageWithoutContentIsRejected() {
        let empty = Sinch_Conversationapi_Type_AppMessage()
        XCTAssertNil(InAppMessageParser.message(fromUserInfo: InAppPayloadFixtures.userInfo(empty)))
        XCTAssertNil(InAppMessageParser.message(fromRelayMetadata: InAppPayloadFixtures.relayMetadata(empty)))
    }
}
