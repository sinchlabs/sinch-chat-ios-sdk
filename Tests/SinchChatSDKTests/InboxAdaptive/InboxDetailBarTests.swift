import XCTest
import UIKit
@testable import SinchChatSDK

/// The chat column's bar looks like the inbox's and the chat's, and only the SDK's own leading button is stripped.
@MainActor
final class InboxDetailBarTests: InboxSplitFixture {

    private func assertStyled(_ navigationBar: UINavigationBar, file: StaticString = #filePath, line: UInt = #line) {
        let uiConfig = SinchSDKConfig.UIConfig.defaultValue
        let appearances: [(String, UINavigationBarAppearance?)] = [
            ("standard", navigationBar.standardAppearance),
            ("compact", navigationBar.compactAppearance),
            ("scrollEdge", navigationBar.scrollEdgeAppearance),
            ("compactScrollEdge", navigationBar.compactScrollEdgeAppearance)
        ]
        for (name, appearance) in appearances {
            XCTAssertEqual(appearance?.backgroundColor, uiConfig.navigationBarColor, "\(name) background", file: file, line: line)
            XCTAssertEqual(appearance?.titleTextAttributes[.foregroundColor] as? UIColor, uiConfig.navigationBarTitleColor,
                           "\(name) title colour", file: file, line: line)
        }
        XCTAssertEqual(navigationBar.tintColor, uiConfig.navigationBarTitleColor, file: file, line: line)
    }

    func testDetailBarOverTheEmptyPlaceholderUsesTheInboxLook() {
        show(width: 951, height: 669)
        XCTAssertTrue(split.detailNavigationController.viewControllers == [split.emptyDetailViewController])
        assertStyled(split.detailNavigationController.navigationBar)
    }

    func testSidebarBarUsesTheInboxLookAtBarLevel() {
        show(width: 951, height: 669)
        assertStyled(split.primaryNavigationController.navigationBar)
    }

    func testDetailBarFollowsACustomUIConfig() {
        var uiConfig = SinchSDKConfig.UIConfig.defaultValue
        uiConfig.navigationBarColor = .systemTeal
        uiConfig.navigationBarTitleColor = .systemYellow
        let navigationController = InboxDetailNavigationController(rootViewController: UIViewController(), uiConfig: uiConfig)

        XCTAssertEqual(navigationController.navigationBar.compactAppearance?.backgroundColor, .systemTeal)
        XCTAssertEqual(navigationController.navigationBar.scrollEdgeAppearance?.backgroundColor, .systemTeal)
        XCTAssertEqual(navigationController.navigationBar.tintColor, .systemYellow)
    }

    // MARK: Leading button ownership

    private func showRealChat() throws -> StartViewController {
        inbox.chatFactory = { _ in
            StartViewController(viewModel: StartViewModelStub(),
                                view: .init(uiConfiguration: .defaultValue, localizationConfiguration: .defaultValue))
        }
        show(width: 1024, height: 800)
        select(row: 0)
        layoutEverything()
        return try XCTUnwrap(split.detailNavigationController.viewControllers.first as? StartViewController)
    }

    func testDetailKeepsALeadingButtonTheSDKDoesNotOwn() throws {
        let chat = try showRealChat()
        let custom = UIBarButtonItem(title: "Mine", style: .plain, target: nil, action: nil)
        chat.ownsLeadingBarButton = false
        chat.navigationItem.leftBarButtonItem = custom

        split.detailNavigationController.navigationController(split.detailNavigationController, didShow: chat, animated: false)

        XCTAssertTrue(chat.navigationItem.leftBarButtonItem === custom, "an integrator's button is not ours to remove")
    }

    func testDetailStripsTheLeadingButtonTheSDKInstalled() throws {
        let chat = try showRealChat()
        chat.addBackButton()
        chat.ownsLeadingBarButton = true

        split.detailNavigationController.navigationController(split.detailNavigationController, didShow: chat, animated: false)

        XCTAssertNil(chat.navigationItem.leftBarButtonItem)
        XCTAssertFalse(chat.ownsLeadingBarButton)
    }
}
