import XCTest
import UIKit
@testable import SinchChatSDK

/// The sizing rules are pure functions: no view controller, no window.
final class InboxAdaptiveLayoutTests: XCTestCase {

    // MARK: Width buckets

    func testWidthBuckets() {
        XCTAssertEqual(InboxAdaptiveLayout.widthBucket(for: 320), .narrow)
        XCTAssertEqual(InboxAdaptiveLayout.widthBucket(for: 599.5), .narrow)
        XCTAssertEqual(InboxAdaptiveLayout.widthBucket(for: 600), .medium)
        XCTAssertEqual(InboxAdaptiveLayout.widthBucket(for: 820), .medium)
        XCTAssertEqual(InboxAdaptiveLayout.widthBucket(for: 900), .medium)
        XCTAssertEqual(InboxAdaptiveLayout.widthBucket(for: 900.5), .wide)
        XCTAssertEqual(InboxAdaptiveLayout.widthBucket(for: 1366), .wide)
    }

    func testDisplayModeKeepsSidebarVisibleOnlyOnWideWindows() {
        XCTAssertEqual(InboxAdaptiveLayout.preferredDisplayMode(for: 1024), .oneBesideSecondary)
        XCTAssertEqual(InboxAdaptiveLayout.preferredDisplayMode(for: 744), .automatic)
        XCTAssertEqual(InboxAdaptiveLayout.preferredDisplayMode(for: 500), .automatic)
    }

    func testSidebarWidthConstants() {
        XCTAssertEqual(InboxAdaptiveLayout.preferredPrimaryWidth, 320)
        XCTAssertEqual(InboxAdaptiveLayout.minimumPrimaryWidth, 280)
        XCTAssertEqual(InboxAdaptiveLayout.maximumPrimaryWidth, 360)
    }

    // MARK: Hinge snapping

    private let duoUnfolded = CGSize(width: 1080, height: 810)

    private func hinge(x originX: CGFloat, width: CGFloat, height: CGFloat? = nil) -> CGRect {
        CGRect(x: originX, y: 0, width: width, height: height ?? duoUnfolded.height)
    }

    func testNoHingeMeansNoSnap() {
        XCTAssertNil(InboxAdaptiveLayout.hingeSnap(containerSize: duoUnfolded, hingeFrame: nil))
        XCTAssertNil(InboxAdaptiveLayout.hingeSnap(containerSize: duoUnfolded, hingeFrame: .zero))
        XCTAssertNil(InboxAdaptiveLayout.hingeSnap(containerSize: duoUnfolded, hingeFrame: .null))
        XCTAssertNil(InboxAdaptiveLayout.hingeSnap(containerSize: .zero, hingeFrame: hinge(x: 500, width: 40)))
    }

    func testCentredVerticalHingeEndsSidebarAtLeadingEdgeAndInsetsChat() throws {
        // Hinge strip 400...440 inside a 1080pt window: sidebar 400pt wide, chat skips the 40pt strip.
        let snap = try XCTUnwrap(InboxAdaptiveLayout.hingeSnap(containerSize: duoUnfolded,
                                                               hingeFrame: hinge(x: 400, width: 40)))
        XCTAssertEqual(snap.primaryWidth, 400)
        XCTAssertEqual(snap.secondaryLeadingInset, 40)
        // Nothing straddles: sidebar ends where the strip starts, chat content starts where it ends.
        XCTAssertEqual(snap.primaryWidth + snap.secondaryLeadingInset, 440)
    }

    func testHingeWithinTheSidebarRangeSnapsAtBothEnds() throws {
        let container = CGSize(width: 700, height: 800)
        let atMinimum = try XCTUnwrap(InboxAdaptiveLayout.hingeSnap(
            containerSize: container, hingeFrame: CGRect(x: 280, y: 0, width: 40, height: 800)))
        XCTAssertEqual(atMinimum.primaryWidth, InboxAdaptiveLayout.hingeMinimumPrimaryWidth)
        XCTAssertEqual(atMinimum.secondaryLeadingInset, 40)

        let atMaximum = try XCTUnwrap(InboxAdaptiveLayout.hingeSnap(
            containerSize: container, hingeFrame: CGRect(x: 420, y: 0, width: 40, height: 800)))
        XCTAssertEqual(atMaximum.primaryWidth, 420)
        XCTAssertEqual(atMaximum.primaryWidth + atMaximum.secondaryLeadingInset, 460)
    }

    func testHingeTooCloseToTheLeadingEdgeIsIgnoredInsteadOfClamped() {
        // Strip starts at 279.5: a 280pt sidebar would straddle it, so nothing snaps.
        XCTAssertNil(InboxAdaptiveLayout.hingeSnap(containerSize: CGSize(width: 700, height: 800),
                                                   hingeFrame: CGRect(x: 279.5, y: 0, width: 40, height: 800)))
        // Hinge at 200 in a 480pt window (dead centre): same.
        XCTAssertNil(InboxAdaptiveLayout.hingeSnap(containerSize: CGSize(width: 480, height: 800),
                                                   hingeFrame: CGRect(x: 200, y: 0, width: 80, height: 800)))
    }

    func testCentredFoldSnapsTheSidebarToTheWholeLeadingPage() throws {
        // A real centred fold on the unfolded Duo: the sidebar ends exactly at the hinge.
        let centred = try XCTUnwrap(InboxAdaptiveLayout.hingeSnap(
            containerSize: duoUnfolded, hingeFrame: hinge(x: duoUnfolded.width / 2 - 20, width: 40)))
        XCTAssertEqual(centred.primaryWidth, duoUnfolded.width / 2 - 20)
        XCTAssertEqual(centred.secondaryLeadingInset, 40)
        let wide = try XCTUnwrap(InboxAdaptiveLayout.hingeSnap(containerSize: CGSize(width: 1200, height: 800),
                                                               hingeFrame: CGRect(x: 600, y: 0, width: 40, height: 800)))
        XCTAssertEqual(wide.primaryWidth, 600)
    }

    func testFarOffCentreHingeIsIgnored() {
        // 1080pt window, hinge at 100: 440pt away from the centre, more than 15% of the width.
        XCTAssertNil(InboxAdaptiveLayout.hingeSnap(containerSize: duoUnfolded, hingeFrame: hinge(x: 100, width: 40)))
        XCTAssertNil(InboxAdaptiveLayout.hingeSnap(containerSize: duoUnfolded, hingeFrame: hinge(x: 950, width: 40)))
    }

    func testHingeJustInsideTheToleranceStillSnaps() {
        let width = duoUnfolded.width
        let tolerance = width * InboxAdaptiveLayout.hingeCentreTolerance
        let originX = width / 2 - 20 - tolerance + 1   // centre is tolerance - 1 left of the middle
        XCTAssertNotNil(InboxAdaptiveLayout.hingeSnap(containerSize: duoUnfolded, hingeFrame: hinge(x: originX, width: 40)))
    }

    func testHorizontalTabletopHingeIsIgnored() {
        // A strip across the window (wider than tall) is not a vertical book posture.
        let tabletop = CGRect(x: 0, y: 385, width: 1080, height: 40)
        XCTAssertNil(InboxAdaptiveLayout.hingeSnap(containerSize: duoUnfolded, hingeFrame: tabletop))
    }

    func testRegionThatDoesNotSpanTheHeightIsIgnored() {
        XCTAssertNil(InboxAdaptiveLayout.hingeSnap(containerSize: duoUnfolded,
                                                   hingeFrame: hinge(x: 520, width: 40, height: 300)))
    }

    // MARK: Public layout option

    func testLayoutDefaultsAreDistinct() {
        XCTAssertNotEqual(SinchInboxLayout.automatic, SinchInboxLayout.stack)
    }
}
