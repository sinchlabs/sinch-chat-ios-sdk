import XCTest
@testable import SinchChatSDK

/// Drives the real `ChatFlowLayout` through a `StartViewController` hosted in a window of a given size.
@MainActor
// swiftlint:disable:next type_body_length
final class AdaptiveChatLayoutTests: XCTestCase {

    private var windows: [UIWindow] = []

    override func tearDown() {
        windows.forEach { $0.isHidden = true }
        windows.removeAll()
        super.tearDown()
    }

    private func makeChat(width: CGFloat,
                          height: CGFloat = 800,
                          horizontal: UIUserInterfaceSizeClass,
                          vertical: UIUserInterfaceSizeClass = .regular,
                          messages: [Message]) -> StartViewController {
        let sut = StartViewController(viewModel: StartViewModelStub(),
                                      view: .init(uiConfiguration: .defaultValue, localizationConfiguration: .defaultValue))
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: width, height: height))
        window.rootViewController = sut
        window.isHidden = false
        windows.append(window)
        sut.view.traitOverrides.horizontalSizeClass = horizontal
        sut.view.traitOverrides.verticalSizeClass = vertical
        sut.messages = messages
        window.layoutIfNeeded()
        sut.mainView.collectionView.reloadData()
        sut.mainView.collectionView.layoutIfNeeded()
        return sut
    }

    private func attributes(_ sut: StartViewController, section: Int) throws -> ChatFlowLayoutAttributes {
        let layout = sut.mainView.collectionView.chatCollectionViewFlowLayout
        return try XCTUnwrap(layout.layoutAttributesForItem(at: IndexPath(item: 0, section: section)) as? ChatFlowLayoutAttributes)
    }

    private let longText = String(repeating: "A reasonably long sentence that has to wrap. ", count: 12)

    private func text(_ owner: Owner, id: String = "1") -> Message {
        Message(entryId: id, owner: owner, body: MessageText(text: longText, sendDate: 1637058195))
    }

    private func choices() -> Message {
        Message(entryId: "c", owner: .incoming(nil),
                body: MessageChoices(text: "Pick one", choices: [], sendDate: 1637058195))
    }

    func testCompactWidthUsesTheFullWidth() throws {
        let sut = makeChat(width: 390, horizontal: .compact, messages: [text(.outgoing), text(.incoming(nil), id: "2")])
        let layout = sut.mainView.collectionView.chatCollectionViewFlowLayout

        XCTAssertEqual(layout.sectionInset.left, 0)
        XCTAssertEqual(layout.itemWidth, sut.mainView.collectionView.bounds.width)
        let bubble = try attributes(sut, section: 0).messageContainerSize.width
        XCTAssertLessThanOrEqual(bubble, sut.mainView.collectionView.bounds.width * 0.78 + 0.5)
        XCTAssertGreaterThan(bubble, 150)
    }

    func testRegularWidthCentresAndCapsTheColumn() throws {
        let sut = makeChat(width: 1024, horizontal: .regular, messages: [text(.outgoing), text(.incoming(nil), id: "2")])
        let layout = sut.mainView.collectionView.chatCollectionViewFlowLayout

        XCTAssertEqual(layout.metrics.columnWidth, 760)
        XCTAssertEqual(layout.sectionInset.left, 132)
        XCTAssertEqual(layout.sectionInset.right, 132)
        XCTAssertEqual(layout.itemWidth, 760)

        for section in 0..<2 {
            let attrs = try attributes(sut, section: section)
            XCTAssertEqual(attrs.frame.minX, 132, "cells start at the column edge")
            XCTAssertEqual(attrs.frame.width, 760)
            XCTAssertLessThanOrEqual(attrs.messageContainerSize.width, 520 + 0.5, "bubble cap")
        }
        // The collection view itself still spans the whole screen.
        XCTAssertEqual(sut.mainView.collectionView.bounds.width, 1024)
    }

    func testRichCardsGrowTo360OnRegularAndStayAt300OnCompact() throws {
        let regular = makeChat(width: 1024, horizontal: .regular, messages: [choices()])
        XCTAssertEqual(try attributes(regular, section: 0).messageContainerSize.width, 360, accuracy: 0.5)

        let compact = makeChat(width: 600, horizontal: .compact, messages: [choices()])
        XCTAssertEqual(try attributes(compact, section: 0).messageContainerSize.width, 300, accuracy: 0.5)
    }

    func testCompactHeightDropsTheAvatar() throws {
        let portrait = makeChat(width: 390, horizontal: .compact, vertical: .regular, messages: [text(.incoming(nil))])
        let portraitAttrs = try attributes(portrait, section: 0)
        XCTAssertEqual(portraitAttrs.avatarSize.width, 30)
        XCTAssertEqual(portraitAttrs.avatarLeadingTrailingPadding, 24)

        let landscape = makeChat(width: 844, height: 390, horizontal: .compact, vertical: .compact, messages: [text(.incoming(nil))])
        let attrs = try attributes(landscape, section: 0)
        XCTAssertEqual(attrs.avatarSize, .zero)
        XCTAssertEqual(attrs.avatarLeadingTrailingPadding, 8, "only a small gutter remains without the avatar")
        XCTAssertEqual(attrs.frame.width, 844, "the cell still spans the whole compact-width column")
    }

    // MARK: - Compact widths keep the widths the phone layout always had

    /// The bubble room before the adaptive layout: row width, minus avatar, minus both paddings, minus the avatar gap.
    /// Incoming: 30 pt avatar, 10 / 71 pt padding. Outgoing: no avatar, 71 / 24 pt padding. The avatar gap is 24 pt.
    private func legacyMaxWidth(row: CGFloat, incoming: Bool) -> CGFloat {
        incoming ? row - 30 - 10 - 71 - 24 : row - 0 - 71 - 24 - 24
    }

    func testCompactBubbleRoomMatchesThePreChangeFormula() throws {
        struct Expected { let width, incoming, outgoing: CGFloat }
        let expected = [Expected(width: 320, incoming: 185, outgoing: 201),
                        Expected(width: 393, incoming: 258, outgoing: 274),
                        Expected(width: 430, incoming: 295, outgoing: 311)]
        for entry in expected {
            let sut = makeChat(width: entry.width, horizontal: .compact, messages: [text(.incoming(nil)), text(.outgoing, id: "2")])
            let layout = sut.mainView.collectionView.chatCollectionViewFlowLayout
            XCTAssertEqual(layout.itemWidth, entry.width, "row width at \(entry.width)")
            XCTAssertEqual(legacyMaxWidth(row: entry.width, incoming: true), entry.incoming)
            XCTAssertEqual(legacyMaxWidth(row: entry.width, incoming: false), entry.outgoing)

            let base = MessageSizeCalculator(layout: layout)
            let incoming = sut.messages[0]
            let outgoing = sut.messages[1]
            XCTAssertEqual(base.messageContainerMaxWidth(for: incoming), entry.incoming, accuracy: 0.001, "incoming at \(entry.width)")
            XCTAssertEqual(base.messageContainerMaxWidth(for: outgoing), entry.outgoing, accuracy: 0.001, "outgoing at \(entry.width)")

            // Text bubbles lose their 8 + 8 pt label insets from that room.
            XCTAssertEqual(layout.textMessageSizeCalculator.messageContainerMaxWidth(for: incoming), entry.incoming - 16, accuracy: 0.001)
            XCTAssertEqual(layout.textMessageSizeCalculator.messageContainerMaxWidth(for: outgoing), entry.outgoing - 16, accuracy: 0.001)

            // The measured long text wraps inside that room: wide, and never wider than it.
            let incomingWidth = try attributes(sut, section: 0).messageContainerSize.width
            let outgoingWidth = try attributes(sut, section: 1).messageContainerSize.width
            XCTAssertLessThanOrEqual(incomingWidth, entry.incoming + 0.5)
            XCTAssertGreaterThan(incomingWidth, entry.incoming - 40)
            XCTAssertLessThanOrEqual(outgoingWidth, entry.outgoing + 0.5)
            XCTAssertGreaterThan(outgoingWidth, entry.outgoing - 40)
        }
    }

    func testCompactPaddingsAreUntouched() throws {
        let sut = makeChat(width: 393, horizontal: .compact, messages: [text(.incoming(nil)), text(.outgoing, id: "2")])
        let incoming = try attributes(sut, section: 0)
        let outgoing = try attributes(sut, section: 1)
        XCTAssertEqual(incoming.messageContainerPadding, UIEdgeInsets(top: 5, left: 10, bottom: 5, right: 71))
        XCTAssertEqual(outgoing.messageContainerPadding, UIEdgeInsets(top: 5, left: 71, bottom: 5, right: 24))
        XCTAssertEqual(incoming.avatarLeadingTrailingPadding, 24)
    }

    // MARK: - Trait flips without a resize

    func testSizeClassFlipWithoutAResizeRelaysOutTheColumn() throws {
        let sut = makeChat(width: 700, horizontal: .compact, messages: [text(.outgoing)])
        let layout = sut.mainView.collectionView.chatCollectionViewFlowLayout
        XCTAssertEqual(layout.itemWidth, 700)

        sut.view.traitOverrides.horizontalSizeClass = .regular
        windows[0].layoutIfNeeded()
        sut.mainView.collectionView.layoutIfNeeded()
        XCTAssertEqual(layout.itemWidth, 680, "the regular column is capped")
        XCTAssertEqual(layout.sectionInset.left, 10)
        XCTAssertEqual(sut.mainView.collectionView.bounds.width, 700, "no resize happened")

        sut.view.traitOverrides.horizontalSizeClass = .compact
        windows[0].layoutIfNeeded()
        sut.mainView.collectionView.layoutIfNeeded()
        XCTAssertEqual(layout.itemWidth, 700)
        XCTAssertEqual(layout.sectionInset.left, 0)
    }

    func testVerticalSizeClassFlipWithoutAResizeTogglesTheAvatar() throws {
        let sut = makeChat(width: 600, height: 600, horizontal: .compact, vertical: .regular, messages: [text(.incoming(nil))])
        XCTAssertEqual(try attributes(sut, section: 0).avatarSize.width, 30)

        sut.view.traitOverrides.verticalSizeClass = .compact
        windows[0].layoutIfNeeded()
        sut.mainView.collectionView.layoutIfNeeded()
        XCTAssertEqual(try attributes(sut, section: 0).avatarSize, .zero)

        sut.view.traitOverrides.verticalSizeClass = .regular
        windows[0].layoutIfNeeded()
        sut.mainView.collectionView.layoutIfNeeded()
        XCTAssertEqual(try attributes(sut, section: 0).avatarSize.width, 30)
    }

    // MARK: - Dynamic Type

    func testContentSizeCategoryChangeRelaysOutWithTallerBubbles() throws {
        let sut = makeChat(width: 393, horizontal: .compact, messages: [text(.outgoing)])
        let before = try attributes(sut, section: 0).messageContainerSize.height

        sut.view.traitOverrides.preferredContentSizeCategory = .accessibilityExtraExtraExtraLarge
        windows[0].layoutIfNeeded()
        sut.mainView.collectionView.layoutIfNeeded()
        let large = try attributes(sut, section: 0).messageContainerSize.height
        XCTAssertGreaterThan(large, before * 1.5, "an accessibility category makes the wrapped text much taller")

        sut.view.traitOverrides.preferredContentSizeCategory = .extraSmall
        windows[0].layoutIfNeeded()
        sut.mainView.collectionView.layoutIfNeeded()
        XCTAssertLessThan(try attributes(sut, section: 0).messageContainerSize.height, before)
    }

    // MARK: - Keyboard inset across a size change (C2, C11)

    private func keyboardFrame(in sut: StartViewController, height: CGFloat) throws -> CGRect {
        let screen = try XCTUnwrap(sut.view.window?.screen)
        let viewInScreen = sut.view.convert(sut.view.bounds, to: screen.coordinateSpace)
        return CGRect(x: viewInScreen.minX, y: viewInScreen.maxY - height, width: viewInScreen.width, height: height)
    }

    private func postKeyboardChange(from start: CGRect, to end: CGRect, local: Bool = true) {
        NotificationCenter.default.post(name: UIResponder.keyboardWillChangeFrameNotification, object: nil, userInfo: [
            UIResponder.keyboardFrameBeginUserInfoKey: NSValue(cgRect: start),
            UIResponder.keyboardFrameEndUserInfoKey: NSValue(cgRect: end),
            UIResponder.keyboardIsLocalUserInfoKey: local
        ])
    }

    func testKeyboardInsetSurvivesATransition() throws {
        let sut = makeChat(width: 393, horizontal: .compact, messages: [text(.outgoing)])
        let accessoryOnly = sut.mainView.collectionView.contentInset.bottom
        let keyboard = try keyboardFrame(in: sut, height: 300)
        postKeyboardChange(from: keyboard.offsetBy(dx: 0, dy: 300), to: keyboard)
        let withKeyboard = sut.mainView.collectionView.contentInset.bottom
        XCTAssertEqual(withKeyboard, 300 + sut.additionalBottomInset, accuracy: 1)
        XCTAssertGreaterThan(withKeyboard, accessoryOnly)

        // What `viewWillTransition`'s completion runs after a rotation or a fold with the keyboard up.
        sut.restoreBottomInsetAfterTransition()
        XCTAssertEqual(sut.mainView.collectionView.contentInset.bottom, withKeyboard, accuracy: 1, "the keyboard inset is kept")

        // A keyboard that has left the view drops the keyboard part of the inset, and a transition keeps it that way.
        let hidden = keyboard.offsetBy(dx: 0, dy: 300)
        postKeyboardChange(from: keyboard, to: hidden)
        let withoutKeyboard = sut.mainView.collectionView.contentInset.bottom
        XCTAssertEqual(withoutKeyboard, sut.additionalBottomInset, accuracy: 1)
        sut.restoreBottomInsetAfterTransition()
        XCTAssertEqual(sut.mainView.collectionView.contentInset.bottom, withoutKeyboard, accuracy: 1)
    }

    func testTransitionWithoutAnyKeyboardUsesTheAccessoryInset() throws {
        let sut = makeChat(width: 393, horizontal: .compact, messages: [text(.outgoing)])
        sut.mainView.collectionView.contentInset.bottom = 1
        sut.restoreBottomInsetAfterTransition()
        XCTAssertEqual(sut.mainView.collectionView.contentInset.bottom, sut.requiredInitialScrollViewBottomInset(), accuracy: 0.001)
    }

    func testSafeAreaChangeKeepsTheKeyboardInset() throws {
        let sut = makeChat(width: 393, horizontal: .compact, messages: [text(.outgoing)])
        let keyboard = try keyboardFrame(in: sut, height: 280)
        postKeyboardChange(from: keyboard.offsetBy(dx: 0, dy: 280), to: keyboard)
        let withKeyboard = sut.mainView.collectionView.contentInset.bottom

        sut.viewSafeAreaInsetsDidChange()
        XCTAssertEqual(sut.mainView.collectionView.contentInset.bottom, withKeyboard, accuracy: 1)
    }

    func testEmptyStartFrameOnPhoneStillMovesTheInsetWhenTheKeyboardCoversTheView() throws {
        let sut = makeChat(width: 393, horizontal: .compact, messages: [text(.outgoing)])
        let before = sut.mainView.collectionView.contentInset.bottom
        let keyboard = try keyboardFrame(in: sut, height: 300)

        postKeyboardChange(from: .zero, to: keyboard)
        XCTAssertGreaterThan(sut.mainView.collectionView.contentInset.bottom, before, "a first keyboard has an empty start frame")
    }

    /// The undocking glitch of the iPad keyboard (zero start frame, end frame that is not over the view) is dropped
    /// on the pad idiom only, as the original workaround was.
    func testEmptyStartFrameFarAwayFromTheViewIsIgnoredOnPad() throws {
        let sut = makeChat(width: 1024, horizontal: .regular, messages: [text(.outgoing)])
        sut.traitOverrides.userInterfaceIdiom = .pad
        XCTAssertEqual(sut.traitCollection.userInterfaceIdiom, .pad)
        let before = sut.mainView.collectionView.contentInset.bottom
        let elsewhere = CGRect(x: 5_000, y: 5_000, width: 300, height: 300)

        postKeyboardChange(from: .zero, to: elsewhere)
        XCTAssertEqual(sut.mainView.collectionView.contentInset.bottom, before)
        XCTAssertNil(sut.lastKeyboardEndFrameInScreen)
    }

    func testEmptyStartFrameFarAwayFromTheViewIsNotDroppedOnPhone() throws {
        let sut = makeChat(width: 393, horizontal: .compact, messages: [text(.outgoing)])
        sut.traitOverrides.userInterfaceIdiom = .phone
        XCTAssertEqual(sut.traitCollection.userInterfaceIdiom, .phone)
        let before = sut.mainView.collectionView.contentInset.bottom
        let elsewhere = CGRect(x: 5_000, y: 5_000, width: 300, height: 300)

        postKeyboardChange(from: .zero, to: elsewhere)
        XCTAssertEqual(sut.lastKeyboardEndFrameInScreen, elsewhere, "a phone acts on every keyboard frame change, as in 2.1.0")
        XCTAssertEqual(sut.mainView.collectionView.contentInset.bottom, before, "a keyboard that is not over the view adds no inset")
    }

    func testKeyboardOfAnotherAppIsIgnored() throws {
        let sut = makeChat(width: 393, horizontal: .compact, messages: [text(.outgoing)])
        let before = sut.mainView.collectionView.contentInset.bottom
        let keyboard = try keyboardFrame(in: sut, height: 300)
        postKeyboardChange(from: keyboard.offsetBy(dx: 0, dy: 300), to: keyboard, local: false)
        XCTAssertEqual(sut.mainView.collectionView.contentInset.bottom, before)
    }

    // MARK: - Compose placement (C4)

    func testComposePlacementFollowsTheCenteredColumn() throws {
        let sut = makeChat(width: 1024, horizontal: .regular, messages: [text(.outgoing)])
        let placement = sut.composePlacement()
        XCTAssertEqual(placement.columnFrame.width, 760)
        XCTAssertEqual(placement.columnFrame.minX, 132)
        XCTAssertEqual(placement.detailFrame.width, 1024)
        XCTAssertTrue(placement.space === sut.view)
    }

    func testLayoutFollowsAWindowResize() throws {
        let sut = makeChat(width: 1024, horizontal: .regular, messages: [text(.outgoing)])
        let layout = sut.mainView.collectionView.chatCollectionViewFlowLayout
        XCTAssertEqual(layout.itemWidth, 760)

        // Stage Manager / Split View: the window shrinks, size class stays regular.
        windows[0].frame = CGRect(x: 0, y: 0, width: 700, height: 800)
        windows[0].layoutIfNeeded()
        sut.mainView.collectionView.layoutIfNeeded()
        XCTAssertEqual(layout.metrics.columnWidth, 680)
        XCTAssertEqual(layout.itemWidth, 680)
        XCTAssertEqual(layout.sectionInset.left, 10)
    }

    /// The compose bar is an input accessory whose width the system fixes; mimic that with a container.
    private func hostCompose(_ compose: ComposeView, width: CGFloat) -> UIView {
        let container = UIView(frame: CGRect(x: 0, y: 0, width: width, height: 200))
        container.addSubview(compose)
        NSLayoutConstraint.activate([
            compose.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            compose.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            compose.topAnchor.constraint(equalTo: container.topAnchor)
        ])
        return container
    }

    func testComposeBarContentIsCappedAndCentredOnRegularWidth() {
        let compose = ComposeView(uiConfiguration: .defaultValue, localizatioConfiguration: .defaultValue)
        let container = hostCompose(compose, width: 1024)
        compose.updateLayoutEnvironment(horizontalSizeClass: .regular, verticalSizeClass: .regular)
        container.layoutIfNeeded()
        compose.layoutIfNeeded()

        XCTAssertEqual(compose.layoutMetrics.columnWidth, 760)
        XCTAssertEqual(compose.contentGuide.layoutFrame.width, 760, accuracy: 0.5)
        XCTAssertEqual(compose.contentGuide.layoutFrame.midX, 512, accuracy: 0.5)
        XCTAssertEqual(compose.backgroundView.frame.width, 1024, accuracy: 0.5, "background spans the full width")
    }

    func testComposeBarFillsTheWidthOnCompact() {
        let compose = ComposeView(uiConfiguration: .defaultValue, localizatioConfiguration: .defaultValue)
        let container = hostCompose(compose, width: 390)
        compose.updateLayoutEnvironment(horizontalSizeClass: .compact, verticalSizeClass: .regular)
        container.layoutIfNeeded()
        compose.layoutIfNeeded()
        XCTAssertEqual(compose.contentGuide.layoutFrame.width, 390, accuracy: 0.5)
    }

    func testComposeBarStaysOneLineHighInPhoneLandscape() {
        let compose = ComposeView(uiConfiguration: .defaultValue, localizatioConfiguration: .defaultValue)
        let container = hostCompose(compose, width: 844)
        compose.updateLayoutEnvironment(horizontalSizeClass: .compact, verticalSizeClass: .compact)
        container.layoutIfNeeded()
        compose.layoutIfNeeded()
        XCTAssertLessThanOrEqual(compose.bounds.height, 70, "one text line plus padding")
    }

    // MARK: - Compose bar inside a narrower chat column (C4, I4)

    /// A window with the chat's own area (`chatFrame`) to the right of a sidebar, and a compose bar as wide as the window.
    private func hostComposeBesideASidebar(chatFrame: CGRect) -> (compose: ComposeView, chatArea: UIView) {
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 1024, height: 768))
        window.isHidden = false
        windows.append(window)
        let chatArea = UIView(frame: chatFrame)
        window.addSubview(chatArea)
        let compose = ComposeView(uiConfiguration: .defaultValue, localizatioConfiguration: .defaultValue)
        let container = UIView(frame: CGRect(x: 0, y: 500, width: 1024, height: 200))
        window.addSubview(container)
        container.addSubview(compose)
        NSLayoutConstraint.activate([
            compose.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            compose.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            compose.topAnchor.constraint(equalTo: container.topAnchor)
        ])
        return (compose, chatArea)
    }

    func testComposeBarCentresOnTheChatColumnNotTheWindow() {
        let chatFrame = CGRect(x: 320, y: 0, width: 704, height: 768)
        let (compose, chatArea) = hostComposeBesideASidebar(chatFrame: chatFrame)
        let column = CGRect(x: 12, y: 0, width: 680, height: 768)
        compose.updateLayoutEnvironment(horizontalSizeClass: .regular, verticalSizeClass: .regular,
                                        placement: ComposeChatPlacement(detailFrame: chatArea.bounds, columnFrame: column, space: chatArea))
        compose.superview?.layoutIfNeeded()
        compose.layoutIfNeeded()

        XCTAssertEqual(compose.contentGuide.layoutFrame.width, 680, accuracy: 0.5)
        XCTAssertEqual(compose.contentGuide.layoutFrame.minX, 332, accuracy: 0.5, "320 pt sidebar + 12 pt column inset")
        XCTAssertEqual(compose.contentGuide.layoutFrame.midX, 672, accuracy: 0.5, "the middle of the chat, not of the window (512)")
    }

    func testComposeBackgroundStaysInsideTheChatColumnArea() {
        let chatFrame = CGRect(x: 320, y: 0, width: 704, height: 768)
        let (compose, chatArea) = hostComposeBesideASidebar(chatFrame: chatFrame)
        compose.updateLayoutEnvironment(horizontalSizeClass: .regular, verticalSizeClass: .regular,
                                        placement: ComposeChatPlacement(detailFrame: chatArea.bounds,
                                                                        columnFrame: CGRect(x: 12, y: 0, width: 680, height: 768),
                                                                        space: chatArea))
        compose.superview?.layoutIfNeeded()
        compose.layoutIfNeeded()

        XCTAssertEqual(compose.backgroundView.frame.minX, 320, accuracy: 0.5, "does not cover the sidebar")
        XCTAssertEqual(compose.backgroundView.frame.maxX, 1024, accuracy: 0.5)
        XCTAssertFalse(compose.point(inside: CGPoint(x: 100, y: 30), with: nil), "touches over the sidebar pass through")
        XCTAssertTrue(compose.point(inside: CGPoint(x: 600, y: 30), with: nil))
    }

    func testComposeBarRespectsTheDetailsOwnSafeAreaInset() {
        // The detail has a 60 pt hinge inset on its leading side, so its safe range starts at 380.
        let chatFrame = CGRect(x: 320, y: 0, width: 704, height: 768)
        let (compose, chatArea) = hostComposeBesideASidebar(chatFrame: chatFrame)
        let safeDetail = CGRect(x: 60, y: 0, width: 644, height: 768)
        compose.updateLayoutEnvironment(horizontalSizeClass: .regular, verticalSizeClass: .regular,
                                        placement: ComposeChatPlacement(detailFrame: safeDetail,
                                                                        columnFrame: CGRect(x: 60, y: 0, width: 644, height: 768),
                                                                        space: chatArea))
        compose.superview?.layoutIfNeeded()
        compose.layoutIfNeeded()

        XCTAssertEqual(compose.backgroundView.frame.minX, 380, accuracy: 0.5)
        XCTAssertEqual(compose.contentGuide.layoutFrame.minX, 380, accuracy: 0.5)
    }

    func testComposeColumnsResolution() {
        let metrics: (CGFloat) -> ChatLayoutMetrics = { ChatLayoutMetrics(containerWidth: $0, horizontalSizeClass: .regular, verticalSizeClass: .regular) }
        // No placement: the bar owns the window and caps itself.
        let alone = ComposeBarColumns.resolve(safe: 0...1024, detail: nil, column: nil, metrics: metrics)
        XCTAssertEqual(alone.columns.background, 0...1024)
        XCTAssertEqual(alone.columns.content, 132...892)

        // A detail narrower than the window.
        let detail = ComposeBarColumns.resolve(safe: 0...1024, detail: 320...1024, column: 332...1012, metrics: metrics)
        XCTAssertEqual(detail.columns.background, 320...1024)
        XCTAssertEqual(detail.columns.content, 332...1012)

        // A column wider than the detail is clamped to it.
        let clamped = ComposeBarColumns.resolve(safe: 0...1024, detail: 320...1024, column: 0...2000, metrics: metrics)
        XCTAssertEqual(clamped.columns.content, 320...1024)

        // A placement that does not overlap the bar at all falls back to the bar's own range.
        let disjoint = ComposeBarColumns.resolve(safe: 0...400, detail: 500...900, column: 500...900, metrics: metrics)
        XCTAssertEqual(disjoint.columns.background, 0...400)
    }
}
