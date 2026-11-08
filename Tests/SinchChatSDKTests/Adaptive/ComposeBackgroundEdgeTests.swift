import XCTest
@testable import SinchChatSDK

/// The compose bar's background reaches the screen edges (under a notch or a status column) while its controls
/// stay inside the safe area and the message column.
@MainActor
final class ComposeBackgroundEdgeTests: XCTestCase {

    private var windows: [UIWindow] = []

    override func tearDown() {
        windows.forEach { $0.isHidden = true }
        windows.removeAll()
        super.tearDown()
    }

    private let metrics: (CGFloat) -> ChatLayoutMetrics = {
        ChatLayoutMetrics(containerWidth: $0, horizontalSizeClass: .regular, verticalSizeClass: .regular)
    }

    // MARK: - Hosting

    /// A window whose root view has the given safe area insets, with a compose bar as wide as the window. The root
    /// view stands in for the chat screen (`chatArea`), so it can be used as the placement's space.
    private func hostCompose(width: CGFloat, insets: UIEdgeInsets) -> (compose: ComposeView, chatArea: UIView) {
        let controller = UIViewController()
        controller.additionalSafeAreaInsets = insets
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: width, height: 700))
        window.rootViewController = controller
        window.isHidden = false
        windows.append(window)
        let compose = ComposeView(uiConfiguration: .defaultValue, localizatioConfiguration: .defaultValue)
        let container = UIView(frame: CGRect(x: 0, y: 400, width: width, height: 200))
        controller.view.addSubview(container)
        container.addSubview(compose)
        NSLayoutConstraint.activate([
            compose.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            compose.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            compose.topAnchor.constraint(equalTo: container.topAnchor)
        ])
        window.layoutIfNeeded()
        return (compose, controller.view)
    }

    private func layout(_ compose: ComposeView) {
        compose.superview?.layoutIfNeeded()
        compose.layoutIfNeeded()
    }

    // MARK: - Not in a split view

    func testBackgroundReachesTheTrailingEdgeWithATrailingSafeAreaInset() throws {
        // Duo folded: 466 pt wide, the panel keeps an 84 pt status column on the trailing side.
        let (compose, chatArea) = hostCompose(width: 466, insets: UIEdgeInsets(top: 0, left: 0, bottom: 0, right: 84))
        XCTAssertEqual(compose.safeAreaInsets.right, 84, accuracy: 0.5, "precondition: the bar sees the inset")
        let safe = CGRect(x: 0, y: 0, width: 382, height: 700)
        compose.updateLayoutEnvironment(horizontalSizeClass: .compact, verticalSizeClass: .regular,
                                        placement: ComposeChatPlacement(detailFrame: safe, columnFrame: safe,
                                                                        areaFrame: chatArea.bounds, space: chatArea))
        layout(compose)

        XCTAssertEqual(compose.backgroundView.frame.minX, 0, accuracy: 0.5)
        XCTAssertEqual(compose.backgroundView.frame.maxX, 466, accuracy: 0.5, "no empty strip on the trailing side")
        XCTAssertTrue(compose.point(inside: CGPoint(x: 440, y: 30), with: nil), "the strip is part of the bar")
    }

    func testBackgroundReachesBothEdgesWithoutAPlacement() {
        let (compose, _) = hostCompose(width: 844, insets: UIEdgeInsets(top: 0, left: 47, bottom: 0, right: 47))
        compose.updateLayoutEnvironment(horizontalSizeClass: .compact, verticalSizeClass: .compact)
        layout(compose)

        XCTAssertEqual(compose.backgroundView.frame.minX, 0, accuracy: 0.5, "iPhone landscape, notch side")
        XCTAssertEqual(compose.backgroundView.frame.maxX, 844, accuracy: 0.5)
    }

    func testBackgroundIsUnchangedWithoutInsets() {
        let (compose, chatArea) = hostCompose(width: 390, insets: .zero)
        compose.updateLayoutEnvironment(horizontalSizeClass: .compact, verticalSizeClass: .regular,
                                        placement: ComposeChatPlacement(detailFrame: chatArea.bounds, columnFrame: chatArea.bounds,
                                                                        areaFrame: chatArea.bounds, space: chatArea))
        layout(compose)

        XCTAssertEqual(compose.backgroundView.frame.minX, 0, accuracy: 0.5)
        XCTAssertEqual(compose.backgroundView.frame.maxX, 390, accuracy: 0.5)
        XCTAssertEqual(compose.contentGuide.layoutFrame.minX, 0, accuracy: 0.5)
        XCTAssertEqual(compose.contentGuide.layoutFrame.maxX, 390, accuracy: 0.5)
    }

    // MARK: - Split detail

    func testBackgroundReachesTheTrailingEdgeAsSplitDetailWithATrailingInset() throws {
        // Duo unfolded: 951 pt wide, 320 pt sidebar, an 84 pt status column on the trailing side.
        let (compose, window) = hostCompose(width: 951, insets: UIEdgeInsets(top: 0, left: 0, bottom: 0, right: 84))
        let chatArea = UIView(frame: CGRect(x: 320, y: 0, width: 631, height: 700))
        window.addSubview(chatArea)
        let safe = CGRect(x: 0, y: 0, width: 547, height: 700)
        compose.updateLayoutEnvironment(horizontalSizeClass: .regular, verticalSizeClass: .regular,
                                        placement: ComposeChatPlacement(detailFrame: safe, columnFrame: safe,
                                                                        areaFrame: chatArea.bounds, space: chatArea))
        layout(compose)

        XCTAssertEqual(compose.backgroundView.frame.minX, 320, accuracy: 0.5, "does not cover the sidebar")
        XCTAssertEqual(compose.backgroundView.frame.maxX, 951, accuracy: 0.5, "reaches the trailing window edge")
        XCTAssertFalse(compose.point(inside: CGPoint(x: 100, y: 30), with: nil), "touches over the sidebar pass through")
        XCTAssertTrue(compose.point(inside: CGPoint(x: 930, y: 30), with: nil))
    }

    // MARK: - Content

    func testContentStaysInsideTheSafeArea() {
        let (compose, chatArea) = hostCompose(width: 466, insets: UIEdgeInsets(top: 0, left: 40, bottom: 0, right: 84))
        let safe = CGRect(x: 40, y: 0, width: 342, height: 700)
        compose.updateLayoutEnvironment(horizontalSizeClass: .compact, verticalSizeClass: .regular,
                                        placement: ComposeChatPlacement(detailFrame: safe, columnFrame: safe,
                                                                        areaFrame: chatArea.bounds, space: chatArea))
        layout(compose)

        XCTAssertEqual(compose.backgroundView.frame.minX, 0, accuracy: 0.5)
        XCTAssertEqual(compose.backgroundView.frame.maxX, 466, accuracy: 0.5)
        XCTAssertEqual(compose.contentGuide.layoutFrame.minX, 40, accuracy: 0.5)
        XCTAssertEqual(compose.contentGuide.layoutFrame.maxX, 382, accuracy: 0.5)
        let stacks = [compose.leftStackView, compose.rightStackView, compose.textButtonContainer]
        for view in stacks where !view.isHidden {
            let frame = compose.convert(view.bounds, from: view)
            XCTAssertGreaterThanOrEqual(frame.minX, 40 - 0.5, "\(type(of: view)) starts inside the safe area")
            XCTAssertLessThanOrEqual(frame.maxX, 382 + 0.5, "\(type(of: view)) ends inside the safe area")
        }
    }

    func testContentOfASplitDetailStaysInsideItsSafeAreaAndTheColumn() {
        let (compose, window) = hostCompose(width: 951, insets: UIEdgeInsets(top: 0, left: 0, bottom: 0, right: 84))
        let chatArea = UIView(frame: CGRect(x: 320, y: 0, width: 631, height: 700))
        window.addSubview(chatArea)
        let safe = CGRect(x: 0, y: 0, width: 547, height: 700)
        let column = CGRect(x: 12, y: 0, width: 523, height: 700)
        compose.updateLayoutEnvironment(horizontalSizeClass: .regular, verticalSizeClass: .regular,
                                        placement: ComposeChatPlacement(detailFrame: safe, columnFrame: column,
                                                                        areaFrame: chatArea.bounds, space: chatArea))
        layout(compose)

        XCTAssertEqual(compose.contentGuide.layoutFrame.minX, 332, accuracy: 0.5)
        XCTAssertEqual(compose.contentGuide.layoutFrame.maxX, 855, accuracy: 0.5, "inside the column, short of the status column at 867")
    }

    // MARK: - Resolution

    func testResolutionExtendsTheBackgroundButNotTheContent() {
        // Window 0...466, safe 0...382 (trailing inset), chat owns everything.
        let alone = ComposeBarColumns.resolve(safe: 0...382, detail: 0...382, column: 0...382, bounds: 0...466, area: 0...466, metrics: metrics)
        XCTAssertEqual(alone.columns.background, 0...466)
        XCTAssertEqual(alone.columns.safeBackground, 0...382)
        XCTAssertEqual(alone.columns.content, 0...382)

        // Split detail: the background starts at the detail's leading edge and ends at the window edge.
        let split = ComposeBarColumns.resolve(safe: 0...867, detail: 320...867, column: 332...855, bounds: 0...951, area: 320...951, metrics: metrics)
        XCTAssertEqual(split.columns.background, 320...951)
        XCTAssertEqual(split.columns.safeBackground, 320...867)
        XCTAssertEqual(split.columns.content, 332...855)
    }

    func testResolutionWithoutAPlacementFillsTheBar() {
        let resolved = ComposeBarColumns.resolve(safe: 47...797, detail: nil, column: nil, bounds: 0...844, area: nil, metrics: metrics)
        XCTAssertEqual(resolved.columns.background, 0...844)
        XCTAssertEqual(resolved.columns.safeBackground, 47...797)
    }

    // MARK: - Tolerance (R-C3)

    func testRangesThatDifferByLessThanHalfAPointAreEqual() {
        XCTAssertTrue((0...390).isApproximatelyEqual(to: 0.4...389.6))
        XCTAssertFalse((0...390).isApproximatelyEqual(to: 0.5...390))
        XCTAssertFalse((0...390).isApproximatelyEqual(to: 0...388))
    }

    func testBackgroundThatMissesTheBarByRoundingIsNotLimited() {
        // The converted detail range is off by a fraction of a point: the bar is still full width.
        let resolved = ComposeBarColumns.resolve(safe: 0...390, detail: 0.3...389.8, column: nil, bounds: 0...390, area: 0.3...389.8, metrics: metrics)
        XCTAssertEqual(resolved.columns.background, 0...390)
        XCTAssertTrue(resolved.columns.background.isApproximatelyEqual(to: 0...390))
    }

    func testClampAcceptsRangesThatMissEachOtherByLessThanTolerance() {
        XCTAssertNil((0...100).clamped(to: 100.3...200, tolerance: 0))
        XCTAssertNotNil((0...100).clamped(to: 100.3...200, tolerance: 0.5))
        XCTAssertNil((0...100).clamped(to: 101...200, tolerance: 0.5))
    }

    func testBarWithRoundingNoiseStaysFullWidthAndPassesTouchesThrough() {
        let (compose, chatArea) = hostCompose(width: 390, insets: .zero)
        let nearlyFull = CGRect(x: 0.3, y: 0, width: 389.5, height: 700)
        compose.updateLayoutEnvironment(horizontalSizeClass: .compact, verticalSizeClass: .regular,
                                        placement: ComposeChatPlacement(detailFrame: nearlyFull, columnFrame: nearlyFull,
                                                                        areaFrame: nearlyFull, space: chatArea))
        layout(compose)

        XCTAssertTrue(compose.point(inside: CGPoint(x: 0.1, y: 30), with: nil), "not treated as a limited background")
        XCTAssertEqual(compose.backgroundView.frame.minX, 0, accuracy: 0.01)
        XCTAssertEqual(compose.backgroundView.frame.maxX, 390, accuracy: 0.01)
    }
}
