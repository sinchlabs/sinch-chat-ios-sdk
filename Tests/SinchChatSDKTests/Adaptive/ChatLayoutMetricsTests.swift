import XCTest
@testable import SinchChatSDK

final class ChatLayoutMetricsTests: XCTestCase {

    private func metrics(_ width: CGFloat,
                         _ horizontal: UIUserInterfaceSizeClass,
                         _ vertical: UIUserInterfaceSizeClass = .regular) -> ChatLayoutMetrics {
        ChatLayoutMetrics(containerWidth: width, horizontalSizeClass: horizontal, verticalSizeClass: vertical)
    }

    // MARK: - Column

    func testCompactWidthColumnFillsTheContainer() {
        for width: CGFloat in [320, 375, 430, 700] {
            let result = metrics(width, .compact)
            XCTAssertNil(result.columnMaxWidth)
            XCTAssertEqual(result.columnWidth, width)
            XCTAssertEqual(result.columnSideInset, 0)
        }
    }

    func testRegularWidthColumnIsCappedAt680UpTo900() {
        XCTAssertEqual(metrics(600, .regular).columnWidth, 600)
        XCTAssertEqual(metrics(678, .regular).columnWidth, 678)
        XCTAssertEqual(metrics(700, .regular).columnWidth, 680)
        XCTAssertEqual(metrics(900, .regular).columnWidth, 680, "900 still belongs to the 600-900 band")
        XCTAssertEqual(metrics(900, .regular).columnMaxWidth, 680)
    }

    func testRegularWidthColumnIsCappedAt760AboveWide() {
        XCTAssertEqual(metrics(901, .regular).columnMaxWidth, 760)
        XCTAssertEqual(metrics(1024, .regular).columnWidth, 760)
        XCTAssertEqual(metrics(1366, .regular).columnWidth, 760)
    }

    func testColumnIsCentred() {
        let result = metrics(1024, .regular)
        XCTAssertEqual(result.columnSideInset, 132)
        XCTAssertEqual(result.columnSideInset * 2 + result.columnWidth, 1024)
        // An odd leftover rounds down, so the column never exceeds its cap.
        let odd = metrics(851, .regular)
        XCTAssertEqual(odd.columnSideInset, 85)
        XCTAssertLessThanOrEqual(odd.columnSideInset * 2 + odd.columnWidth, 851)
    }

    func testRegularWidthNarrowerThanColumnHasNoInset() {
        let result = metrics(507, .regular)
        XCTAssertEqual(result.columnWidth, 507)
        XCTAssertEqual(result.columnSideInset, 0)
    }

    func testUnspecifiedSizeClassFallsBackToThePhoneLayout() {
        let result = metrics(1000, .unspecified, .unspecified)
        XCTAssertFalse(result.isRegularWidth)
        XCTAssertEqual(result.columnWidth, 1000)
        XCTAssertEqual(result.richCardWidth, 300)
        XCTAssertTrue(result.showsIncomingAvatar)
    }

    func testNegativeWidthIsClamped() {
        XCTAssertEqual(metrics(-10, .regular).columnWidth, 0)
    }

    // MARK: - Bubbles and cards

    func testCompactBubbleIs78PercentOfTheColumn() {
        let result = metrics(390, .compact)
        XCTAssertEqual(result.bubbleMaxWidth(inColumnOfWidth: 390), 390 * 0.78, accuracy: 0.001)
        XCTAssertEqual(result.richCardWidth, 300)
        XCTAssertEqual(result.fileBubbleMaxWidth, 280)
    }

    func testRegularBubbleIsMin78PercentAnd520() {
        let result = metrics(1024, .regular)
        XCTAssertEqual(result.bubbleMaxWidth(inColumnOfWidth: 760), 520, "78% of 760 is 592, capped at 520")
        XCTAssertEqual(result.bubbleMaxWidth(inColumnOfWidth: 680), 520, "78% of 680 is 530.4, capped at 520")
        XCTAssertEqual(result.bubbleMaxWidth(inColumnOfWidth: 600), 468, accuracy: 0.001)
        XCTAssertEqual(result.richCardWidth, 360)
        XCTAssertGreaterThan(result.fileBubbleMaxWidth, 520)
    }

    // MARK: - Chrome

    func testCompactHeightHidesTheAvatar() {
        XCTAssertFalse(metrics(844, .compact, .compact).showsIncomingAvatar)
        XCTAssertFalse(metrics(956, .regular, .compact).showsIncomingAvatar)
        XCTAssertTrue(metrics(390, .compact, .regular).showsIncomingAvatar)
        XCTAssertTrue(metrics(1024, .regular, .regular).showsIncomingAvatar)
    }

    // MARK: - Environments that matter

    func testDuoFoldedBehavesLikeAPhoneAndUnfoldedLikeAnIPad() {
        let folded = metrics(402, .compact)
        let unfolded = metrics(820, .regular)
        XCTAssertEqual(folded.columnWidth, 402)
        XCTAssertEqual(unfolded.columnWidth, 680)
        XCTAssertEqual(unfolded.richCardWidth, 360)
    }

    func testResizingAWindowAcrossTheThresholdChangesTheColumn() {
        XCTAssertEqual(metrics(900, .regular).columnWidth, 680)
        XCTAssertEqual(metrics(920, .regular).columnWidth, 760)
        XCTAssertNotEqual(metrics(900, .regular), metrics(920, .regular))
    }
}
