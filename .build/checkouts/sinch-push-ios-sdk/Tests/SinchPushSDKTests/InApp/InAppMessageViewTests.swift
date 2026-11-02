import UIKit
import XCTest
@testable import SinchPushSDK

/// Builds and lays out every layout. This is the cheap guard against the
/// constraint and view-hierarchy mistakes that only surface at runtime.
@MainActor
final class InAppMessageViewTests: XCTestCase {

    private let phoneSize = CGSize(width: 375, height: 812)

    private let location = InAppLocation(title: "Sinch", label: "HQ", latitude: 50.06, longitude: 19.94)

    private let choices = [
        InAppChoice(title: "Yes", action: .text(postbackData: "yes")),
        InAppChoice(title: "Docs", action: .url("https://docs.example.com")),
        InAppChoice(title: "Call", action: .call(phoneNumber: "+48123456789")),
        InAppChoice(title: "Map", action: .location(InAppLocation(title: "HQ", label: "HQ", latitude: 50.06, longitude: 19.94)))
    ]

    private var allBodies: [InAppMessage.Body] {
        [
            .text(text: "Hello"),
            .media(url: "https://cdn.example.com/a.png"),
            .location(location),
            .choices(text: "Pick", choices: choices),
            .card(InAppCard(title: "Title", description: "Description", media: "https://cdn.example.com/c.png", choices: choices)),
            .carousel(
                cards: [
                    InAppCard(title: "One", description: "First", media: "https://cdn.example.com/1.png", choices: choices),
                    InAppCard(title: "Two", description: "Second", media: "https://cdn.example.com/2.png", choices: [])
                ],
                choices: [InAppChoice(title: "All", action: .url("https://example.com"))]
            )
        ]
    }

    func testEveryLayoutBuildsAndLaysOut() {
        for body in allBodies {
            let message = InAppMessage(body: body)
            let view = InAppMessageView(theme: .default, message: message)
            view.frame = CGRect(origin: .zero, size: phoneSize)

            view.layoutIfNeeded()

            XCTAssertEqual(view.scrollView.frame.width, phoneSize.width, accuracy: 1, "\(body)")
        }
    }

    func testEveryLayoutRendersInAViewController() {
        for body in allBodies {
            let message = InAppMessage(body: body)
            let controller = InAppMessageViewController(
                viewModel: DefaultInAppMessageViewModel(message: message),
                view: InAppMessageView(theme: .default, message: message)
            )

            controller.loadViewIfNeeded()
            controller.view.frame = CGRect(origin: .zero, size: phoneSize)
            controller.view.layoutIfNeeded()

            XCTAssertNotNil(controller.mainView)
        }
    }

    func testChoiceButtonsMatchTheChoices() {
        let message = InAppMessage(body: .choices(text: "Pick", choices: choices))
        let view = InAppMessageView(theme: .default, message: message)
        view.frame = CGRect(origin: .zero, size: phoneSize)

        XCTAssertEqual(view.buttons.count, choices.count)
        XCTAssertEqual(view.buttons.map(\.tag), [0, 1, 2, 3])
        XCTAssertEqual(view.buttons.map { $0.title(for: .normal) }, ["Yes", "Docs", "Call", "HQ"])
    }

    func testCardButtonsMatchTheCard() {
        let card = InAppCard(title: "Title", description: "Description", media: "", choices: choices)
        let view = InAppMessageView(theme: .default, message: InAppMessage(body: .card(card)))
        view.frame = CGRect(origin: .zero, size: phoneSize)

        XCTAssertEqual(view.buttons.count, choices.count)
    }

    func testCarouselBuildsOneCardViewPerCard() {
        let cards = [
            InAppCard(title: "One", description: "First", media: "", choices: []),
            InAppCard(title: "Two", description: "Second", media: "", choices: [])
        ]
        let view = InAppMessageView(
            theme: .default,
            message: InAppMessage(body: .carousel(cards: cards, choices: []))
        )
        view.frame = CGRect(origin: .zero, size: phoneSize)

        XCTAssertEqual(view.cards.count, cards.count)
        XCTAssertEqual(view.pageControl.numberOfPages, cards.count)
    }

    func testCarouselUsesTheWidestChoiceCountSoPagesDoNotJump() {
        let cards = [
            InAppCard(title: "One", description: "First", media: "", choices: [choices[0]]),
            InAppCard(title: "Two", description: "Second", media: "", choices: choices)
        ]
        let view = InAppMessageView(
            theme: .default,
            message: InAppMessage(body: .carousel(cards: cards, choices: []))
        )
        view.frame = CGRect(origin: .zero, size: phoneSize)

        // Each card pads its stack to the widest one, plus its own buttons.
        for cardView in view.cards {
            XCTAssertEqual(cardView.buttonsStackView.arrangedSubviews.count, choices.count)
        }
    }
}
