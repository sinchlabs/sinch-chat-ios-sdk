import XCTest
import UIKit
@testable import SinchChatSDK

/// `updateAdaptiveLayout` with an injected hinge frame (the system `reservedRegions` is not available in tests).
@MainActor
final class InboxHingeLayoutTests: InboxSplitFixture {

    private let duo = CGSize(width: 1080, height: 810)

    private func showUnfolded(hinge: CGRect?, layoutDirection: UITraitEnvironmentLayoutDirection = .leftToRight) {
        split.hingeFrameProvider = { _ in hinge }
        show(width: duo.width, height: duo.height, horizontalSizeClass: .regular, layoutDirection: layoutDirection)
    }

    func testHingeSnapsTheSidebarToTheHingeAndInsetsTheChatOnTheTrailingSide() {
        showUnfolded(hinge: CGRect(x: 400, y: 0, width: 40, height: duo.height))

        XCTAssertEqual(split.view.effectiveUserInterfaceLayoutDirection, .leftToRight)
        XCTAssertEqual(split.preferredPrimaryColumnWidth, 400)
        XCTAssertEqual(split.minimumPrimaryColumnWidth, 400)
        XCTAssertEqual(split.maximumPrimaryColumnWidth, 400)
        XCTAssertEqual(split.preferredDisplayMode, .oneBesideSecondary)
        XCTAssertEqual(split.displayModeButtonVisibility, .never)
        let insets = split.detailNavigationController.additionalSafeAreaInsets
        XCTAssertEqual(insets.left, 40)
        XCTAssertEqual(insets.right, 0)
    }

    func testRightToLeftHingeIsMirroredSoTheInsetLandsOnTheSidebarSide() {
        // Physical hinge strip 640...680 in a right-to-left window: the sidebar is on the right, so the strip is
        // 400...440 from the leading (right) edge, exactly the left-to-right case above.
        showUnfolded(hinge: CGRect(x: 640, y: 0, width: 40, height: duo.height), layoutDirection: .rightToLeft)

        XCTAssertEqual(split.view.effectiveUserInterfaceLayoutDirection, .rightToLeft)
        XCTAssertEqual(split.preferredPrimaryColumnWidth, 400)
        XCTAssertEqual(split.preferredDisplayMode, .oneBesideSecondary)
        XCTAssertEqual(split.displayModeButtonVisibility, .never)
        let insets = split.detailNavigationController.additionalSafeAreaInsets
        XCTAssertEqual(insets.right, 40, "the chat column is on the left in RTL, its inset belongs on its right edge")
        XCTAssertEqual(insets.left, 0)
    }

    func testRemovingTheHingeRestoresTheDefaultLayout() {
        var hinge: CGRect? = CGRect(x: 400, y: 0, width: 40, height: duo.height)
        split.hingeFrameProvider = { _ in hinge }
        show(width: duo.width, height: duo.height, horizontalSizeClass: .regular)
        XCTAssertEqual(split.preferredPrimaryColumnWidth, 400)

        hinge = nil
        split.updateAdaptiveLayout()

        XCTAssertEqual(split.preferredPrimaryColumnWidth, InboxAdaptiveLayout.preferredPrimaryWidth)
        XCTAssertEqual(split.minimumPrimaryColumnWidth, InboxAdaptiveLayout.minimumPrimaryWidth)
        XCTAssertEqual(split.maximumPrimaryColumnWidth, InboxAdaptiveLayout.maximumPrimaryWidth)
        XCTAssertNotEqual(split.displayModeButtonVisibility, .never)
        XCTAssertEqual(split.detailNavigationController.additionalSafeAreaInsets, .zero)
    }

    func testHingeOutsideTheSidebarRangeIsIgnoredInsteadOfClamped() {
        // Strip 100...140 is far from the centre of a 1080pt window: ignored, defaults stay.
        showUnfolded(hinge: CGRect(x: 100, y: 0, width: 40, height: duo.height))
        XCTAssertEqual(split.preferredPrimaryColumnWidth, InboxAdaptiveLayout.preferredPrimaryWidth)
        XCTAssertEqual(split.detailNavigationController.additionalSafeAreaInsets, .zero)
    }

    func testHingeSnapAppliesInAMediumWindowToo() {
        split.hingeFrameProvider = { _ in CGRect(x: 360, y: 0, width: 40, height: 1000) }
        show(width: 744, height: 1000, horizontalSizeClass: .regular)

        XCTAssertEqual(split.preferredPrimaryColumnWidth, 360)
        XCTAssertEqual(split.preferredDisplayMode, .oneBesideSecondary)
        XCTAssertEqual(split.detailNavigationController.additionalSafeAreaInsets.left, 40)
    }
}
