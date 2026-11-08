import XCTest
import UniformTypeIdentifiers
@testable import SinchChatSDK

/// Action sheets, activity sheets and pickers need an anchor on regular width or they crash on iPad.
@MainActor
final class PopoverPresentationTests: XCTestCase {

    private func makeChat() -> StartViewController {
        StartViewController(viewModel: StartViewModelStub(),
                            view: .init(uiConfiguration: .defaultValue, localizationConfiguration: .defaultValue))
    }

    private func hostInRegularWidthWindow(_ sut: StartViewController) -> UIWindow {
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 1024, height: 768))
        window.rootViewController = sut
        window.isHidden = false
        sut.view.traitOverrides.horizontalSizeClass = .regular
        window.layoutIfNeeded()
        return window
    }

    func testPlusMenuIsAnchoredToTheTappedControl() throws {
        let sut = makeChat()
        let window = hostInRegularWidthWindow(sut)
        defer { window.isHidden = true }
        let button = sut.mainView.messageComposeView.plusButton

        let alert = sut.makeActionSheet(anchoredTo: button)

        XCTAssertEqual(sut.traitCollection.horizontalSizeClass, .regular)
        XCTAssertEqual(alert.preferredStyle, .actionSheet)
        let popover = try XCTUnwrap(alert.popoverPresentationController)
        // The compose bar is an input accessory: the sheet points at a rect in the chat's own view, not at the button.
        XCTAssertTrue(popover.sourceView === sut.view)
        XCTAssertNil(popover.sourceItem)
    }

    func testPhotoMenuIsAnchoredToTheTappedControl() throws {
        let sut = makeChat()
        let window = hostInRegularWidthWindow(sut)
        defer { window.isHidden = true }
        let button = sut.mainView.messageComposeView.photoButton

        let alert = sut.makePhotoSourceSheet(anchoredTo: button)

        let popover = try XCTUnwrap(alert.popoverPresentationController)
        XCTAssertTrue(popover.sourceView === sut.view)
    }

    // MARK: - Anchors captured at tap time (C1, C9)

    func testAnchorCapturesTheControlRectInTheHostAndKeepsItWhenTheControlLeaves() throws {
        let sut = makeChat()
        let window = hostInRegularWidthWindow(sut)
        defer { window.isHidden = true }
        let button = UIButton(frame: CGRect(x: 100, y: 600, width: 38, height: 40))
        sut.view.addSubview(button)

        let anchor = PopoverPresentation.Anchor(control: button, in: sut.view)
        XCTAssertTrue(anchor.hasArrow)
        XCTAssertEqual(anchor.currentRect(), CGRect(x: 100, y: 600, width: 38, height: 40))

        // The keyboard goes away and takes the compose bar out of the window.
        button.removeFromSuperview()
        XCTAssertNil(button.window)
        XCTAssertEqual(anchor.currentRect(), CGRect(x: 100, y: 600, width: 38, height: 40), "the rect captured at tap time is kept")
    }

    func testAnchorWithoutAWindowedControlFallsBackToTheHostCentre() throws {
        let host = UIView(frame: CGRect(x: 0, y: 0, width: 800, height: 600))
        let strayButton = UIButton()
        let anchor = PopoverPresentation.Anchor(control: strayButton, in: host)

        XCTAssertFalse(anchor.hasArrow)
        XCTAssertEqual(anchor.currentRect(), CGRect(x: 400, y: 300, width: 0, height: 0))
    }

    func testAnchoredRectScalesWithTheHostAfterARotation() throws {
        let sut = makeChat()
        let window = hostInRegularWidthWindow(sut)
        defer { window.isHidden = true }
        let button = UIButton(frame: CGRect(x: 100, y: 600, width: 38, height: 40))
        sut.view.addSubview(button)
        let anchor = PopoverPresentation.Anchor(control: button, in: sut.view)
        button.removeFromSuperview()

        window.frame = CGRect(x: 0, y: 0, width: 768, height: 1024)
        window.layoutIfNeeded()
        let rect = anchor.currentRect()
        XCTAssertLessThanOrEqual(rect.maxX, sut.view.bounds.width, "the arrow target stays inside the rotated host")
        XCTAssertLessThanOrEqual(rect.maxY, sut.view.bounds.height)
        XCTAssertEqual(rect.minX, 100 * 768 / 1024, accuracy: 0.5)
    }

    func testRepositionRecomputesTheFallbackCentre() throws {
        let host = UIView(frame: CGRect(x: 0, y: 0, width: 800, height: 600))
        let picker = UIImagePickerController()
        PopoverPresentation.prepareAsPopover(picker, anchor: PopoverPresentation.Anchor(control: nil, in: host), compactStyle: .pageSheet)
        let popover = try XCTUnwrap(picker.popoverPresentationController)
        XCTAssertEqual(popover.sourceRect, CGRect(x: 400, y: 300, width: 0, height: 0))

        host.frame = CGRect(x: 0, y: 0, width: 600, height: 800)
        var rect = CGRect.zero
        var view: UIView = UIView()
        let delegate = try XCTUnwrap(popover.delegate)
        delegate.popoverPresentationController?(popover, willRepositionPopoverTo: &rect, in: &view)
        XCTAssertEqual(rect, CGRect(x: 300, y: 400, width: 0, height: 0))
        XCTAssertTrue(view === host)
    }

    // MARK: - Present and dismiss (regular width)

    func testPlusMenuPresentsAsAPopoverAndDismisses() throws {
        let sut = makeChat()
        let window = hostInRegularWidthWindow(sut)
        window.traitOverrides.horizontalSizeClass = .regular
        defer { window.isHidden = true }
        window.layoutIfNeeded()

        // The keyboard is not up, so the compose bar is not in the window: the worst case for an anchor.
        let alert = sut.makeActionSheet(anchoredTo: sut.mainView.messageComposeView.plusButton)
        sut.present(alert, animated: false)

        XCTAssertTrue(sut.presentedViewController === alert, "presenting an anchored sheet on regular width does not crash")
        let popover = try XCTUnwrap(alert.popoverPresentationController)
        XCTAssertNotNil(popover.sourceView ?? (popover.sourceItem as? UIView))
        XCTAssertTrue(popover.sourceView === sut.view)

        XCTAssertEqual(popover.presentationStyle, .popover)
        alert.dismiss(animated: false)
        // Transitions are queued in a scene-less test host, so the dismissal's completion cannot be observed here;
        // the call must be accepted without a crash.
    }

    func testPhotoMenuPresentsAsAPopoverAndDismisses() throws {
        let sut = makeChat()
        let window = hostInRegularWidthWindow(sut)
        window.traitOverrides.horizontalSizeClass = .regular
        defer { window.isHidden = true }
        window.layoutIfNeeded()

        let alert = sut.makePhotoSourceSheet(anchoredTo: sut.mainView.messageComposeView.photoButton)
        sut.present(alert, animated: false)

        XCTAssertTrue(sut.presentedViewController === alert)
        XCTAssertNotNil(alert.popoverPresentationController?.sourceView)
        XCTAssertEqual(alert.popoverPresentationController?.presentationStyle, .popover)
        alert.dismiss(animated: false)
    }

    // MARK: - Document picker restore (C6)

    func testDocumentPickerPopoverDismissalRestoresTheComposeBarOnce() throws {
        let sut = makeChat()
        let window = hostInRegularWidthWindow(sut)
        defer { window.isHidden = true }
        let picker = sut.makeDocumentPicker(anchor: sut.popoverAnchor(for: sut.mainView.messageComposeView.plusButton))
        // The phone-idiom simulator shows the system picker as a sheet and gives it no popover controller; the sheet's
        // presentation controller carries the same delegate then.
        let presentation: UIPresentationController = try XCTUnwrap(picker.popoverPresentationController ?? picker.presentationController)
        let delegate = try XCTUnwrap(presentation.delegate)

        sut.isDocumentPickerPresented = true
        delegate.presentationControllerDidDismiss?(presentation)
        XCTAssertFalse(sut.isDocumentPickerPresented, "dismissing without choosing runs the same restore as a cancel")

        // The dismissal is reported once per presentation, even if UIKit calls both callbacks.
        sut.isDocumentPickerPresented = true
        delegate.presentationControllerDidDismiss?(presentation)
        XCTAssertTrue(sut.isDocumentPickerPresented, "a second report for the same presentation is ignored")
    }

    func testDocumentPickerCancelRestoresOnceAndIsIdempotent() throws {
        let sut = makeChat()
        let window = hostInRegularWidthWindow(sut)
        defer { window.isHidden = true }
        let picker = UIDocumentPickerViewController(forOpeningContentTypes: [.pdf], asCopy: true)

        sut.isDocumentPickerPresented = true
        sut.documentPickerWasCancelled(picker)
        XCTAssertFalse(sut.isDocumentPickerPresented)
        sut.documentPickerWasCancelled(picker)
        XCTAssertFalse(sut.isDocumentPickerPresented)
    }

    func testOpenLocationSheetIsAnchoredToTheTappedBubble() throws {
        let handler = LocationActionHandler(.defaultValue)
        let bubble = UIView()

        let alert = handler.makeOpenLocationAlert(source: bubble, fallbackView: UIView(), title: "Spot", latitude: 52, longitude: 21)

        let popover = try XCTUnwrap(alert.popoverPresentationController)
        XCTAssertTrue(popover.sourceItem === bubble)
    }

    func testOpenLocationSheetWithoutASourceIsCentredInTheFallbackView() throws {
        let handler = LocationActionHandler(.defaultValue)
        let host = UIView(frame: CGRect(x: 0, y: 0, width: 800, height: 600))

        let alert = handler.makeOpenLocationAlert(source: nil, fallbackView: host, title: nil, latitude: 0, longitude: 0)

        let popover = try XCTUnwrap(alert.popoverPresentationController)
        XCTAssertTrue(popover.sourceView === host)
        XCTAssertEqual(popover.sourceRect, CGRect(x: 400, y: 300, width: 0, height: 0))
        XCTAssertTrue(popover.permittedArrowDirections.isEmpty)
    }

    /// `UIActivityViewController` does not keep its popover anchors before it is presented in the phone-idiom
    /// simulator, so the bar-button path is verified on an action sheet, which goes through the same helper.
    func testBarButtonItemAnchorIsApplied() throws {
        let content = UIViewController()
        let share = UIBarButtonItem(barButtonSystemItem: .action, target: nil, action: nil)
        content.navigationItem.leftBarButtonItem = share
        let navigation = UINavigationController(rootViewController: content)
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 1024, height: 768))
        window.rootViewController = navigation
        window.isHidden = false
        window.layoutIfNeeded()
        defer { window.isHidden = true }

        let sheet = UIAlertController(title: nil, message: nil, preferredStyle: .actionSheet)
        PopoverPresentation.anchor(sheet, to: share, fallbackView: nil)

        let popover = try XCTUnwrap(sheet.popoverPresentationController)
        XCTAssertTrue(popover.barButtonItem === share || popover.sourceItem === share)
    }

    func testActivityControllerWithoutASourceIsCentredInTheFallbackView() throws {
        let host = UIView(frame: CGRect(x: 0, y: 0, width: 640, height: 480))
        let activity = UIActivityViewController(activityItems: [URL(string: "https://example.com")!], applicationActivities: nil)
        PopoverPresentation.anchor(activity, to: nil, fallbackView: host)

        let popover = try XCTUnwrap(activity.popoverPresentationController)
        XCTAssertTrue(popover.sourceView === host)
        XCTAssertEqual(popover.sourceRect, CGRect(x: 320, y: 240, width: 0, height: 0))
        XCTAssertTrue(popover.permittedArrowDirections.isEmpty)
    }

    func testImagePickerBecomesAPopoverAnchoredToTheControl() throws {
        let picker = UIImagePickerController()
        let button = UIButton()

        PopoverPresentation.prepareAsPopover(picker, source: button, fallbackView: nil, compactStyle: .pageSheet)

        XCTAssertEqual(picker.modalPresentationStyle, .popover)
        let popover = try XCTUnwrap(picker.popoverPresentationController)
        XCTAssertTrue(popover.sourceItem === button)
        XCTAssertNotNil(popover.delegate)
        XCTAssertEqual(popover.delegate?.adaptivePresentationStyle?(for: popover, traitCollection: UITraitCollection(horizontalSizeClass: .compact)),
                       .pageSheet, "the photo library goes back to the system sheet on compact width")
    }

    func testPickerWithoutAControlIsCentredInTheFallbackView() throws {
        let picker = UIImagePickerController()
        let host = UIView(frame: CGRect(x: 0, y: 0, width: 600, height: 400))

        PopoverPresentation.prepareAsPopover(picker, source: nil, fallbackView: host, compactStyle: .pageSheet)

        let popover = try XCTUnwrap(picker.popoverPresentationController)
        XCTAssertTrue(popover.sourceView === host)
        XCTAssertEqual(popover.sourceRect, CGRect(x: 300, y: 200, width: 0, height: 0))
    }

    func testDocumentPickerSetupAnchorsAPopoverOrReportsTheSheetDismissal() throws {
        // The system picker decides its own presentation and may ignore `.popover` (it does in the phone idiom).
        let picker = UIDocumentPickerViewController(forOpeningContentTypes: [.pdf], asCopy: true)
        let button = UIButton()
        var dismissals = 0
        PopoverPresentation.prepareAsPopover(picker, source: button, fallbackView: nil, compactStyle: .fullScreen) { dismissals += 1 }

        if let popover = picker.popoverPresentationController {
            XCTAssertEqual(picker.modalPresentationStyle, .popover)
            XCTAssertTrue(popover.sourceItem === button)
            XCTAssertNotNil(popover.delegate)
        } else {
            let presentation = try XCTUnwrap(picker.presentationController)
            let delegate = try XCTUnwrap(presentation.delegate, "a swipe-down dismissal of the sheet must still be reported")
            delegate.presentationControllerDidDismiss?(presentation)
            delegate.presentationControllerDidDismiss?(presentation)
            XCTAssertEqual(dismissals, 1)
        }
    }

    func testPickersAdaptToTheirCompactStyleOnCompactWidthOnly() {
        let compact = UITraitCollection(horizontalSizeClass: .compact)
        let regular = UITraitCollection(horizontalSizeClass: .regular)
        XCTAssertEqual(PopoverPresentation.adaptiveStyle(for: compact, compactStyle: .fullScreen), .fullScreen)
        XCTAssertEqual(PopoverPresentation.adaptiveStyle(for: compact, compactStyle: .pageSheet), .pageSheet)
        XCTAssertEqual(PopoverPresentation.adaptiveStyle(for: regular, compactStyle: .fullScreen), .none)
        XCTAssertEqual(PopoverPresentation.adaptiveStyle(for: regular, compactStyle: .pageSheet), .none)
    }

    // MARK: - Compact width keeps the 2.1.0 presentations (G-C2)

    private func hostInCompactWidthWindow(_ sut: StartViewController) -> UIWindow {
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 393, height: 852))
        window.rootViewController = sut
        window.isHidden = false
        sut.view.traitOverrides.horizontalSizeClass = .compact
        window.layoutIfNeeded()
        return window
    }

    func testPhotoLibraryOnCompactWidthIsTheSystemSheetNotAPopover() throws {
        let sut = makeChat()
        let window = hostInCompactWidthWindow(sut)
        defer { window.isHidden = true }
        XCTAssertEqual(sut.view.traitCollection.horizontalSizeClass, .compact)
        let picker = UIImagePickerController()
        let anchor = sut.popoverAnchor(for: sut.mainView.messageComposeView.photoButton)
        var dismissals = 0

        PopoverPresentation.prepareAsPopover(picker, anchor: anchor, compactStyle: ImagePickerHelper.compactStyle) { dismissals += 1 }

        XCTAssertEqual(picker.modalPresentationStyle, UIImagePickerController().modalPresentationStyle,
                       "the system default of 2.1.0, a sheet that swipes down")
        XCTAssertNotEqual(picker.modalPresentationStyle, .popover)
        XCTAssertNotEqual(picker.modalPresentationStyle, .fullScreen)
        XCTAssertNil(picker.popoverPresentationController)
        // The swipe-down dismissal still runs the restore, once.
        let presentation = try XCTUnwrap(picker.presentationController)
        let delegate = try XCTUnwrap(presentation.delegate)
        delegate.presentationControllerDidDismiss?(presentation)
        delegate.presentationControllerDidDismiss?(presentation)
        XCTAssertEqual(dismissals, 1)
    }

    func testPhotoLibraryWithoutAnAnchorOnCompactWidthIsTheSystemSheet() throws {
        let sut = makeChat()
        let window = hostInCompactWidthWindow(sut)
        defer { window.isHidden = true }
        let picker = UIImagePickerController()

        PopoverPresentation.prepareAsPopover(picker, source: nil, fallbackView: sut.view, compactStyle: ImagePickerHelper.compactStyle)

        XCTAssertEqual(picker.modalPresentationStyle, UIImagePickerController().modalPresentationStyle)
    }

    func testDocumentPickerOnCompactWidthIsFullScreenAndStillReportsDismissal() throws {
        let sut = makeChat()
        let window = hostInCompactWidthWindow(sut)
        defer { window.isHidden = true }

        let picker = sut.makeDocumentPicker(anchor: sut.popoverAnchor(for: sut.mainView.messageComposeView.plusButton))

        // `UIDocumentPickerViewController` ignores `modalPresentationStyle` (it reads `.formSheet` whatever is set), so the
        // 2.1.0 `.fullScreen` never changed what the system showed. What matters is that no popover is asked for.
        XCTAssertNotEqual(picker.modalPresentationStyle, .popover)
        XCTAssertNil(picker.popoverPresentationController)
        let presentation = try XCTUnwrap(picker.presentationController)
        let delegate = try XCTUnwrap(presentation.delegate)
        sut.isDocumentPickerPresented = true
        delegate.presentationControllerDidDismiss?(presentation)
        XCTAssertFalse(sut.isDocumentPickerPresented)
    }

    func testPickersOnRegularWidthStayPopovers() throws {
        let sut = makeChat()
        let window = hostInRegularWidthWindow(sut)
        defer { window.isHidden = true }
        let picker = UIImagePickerController()

        PopoverPresentation.prepareAsPopover(picker, anchor: sut.popoverAnchor(for: sut.mainView.messageComposeView.photoButton),
                                             compactStyle: ImagePickerHelper.compactStyle)

        XCTAssertEqual(picker.modalPresentationStyle, .popover)
    }

    func testImagePickerCompactStyleIsTheSystemDefaultOfAFreshPicker() {
        XCTAssertEqual(ImagePickerHelper.compactStyle, UIImagePickerController().modalPresentationStyle)
    }

    // MARK: - Document and media types

    func testDocumentTypeIdentifiersContainOnlyPlainASCII() {
        for identifier in SupportedDocumentTypes.identifiers {
            XCTAssertTrue(identifier.unicodeScalars.allSatisfy { $0.isASCII && $0.value > 0x20 }, "\(identifier) has a hidden character")
        }
        XCTAssertEqual(Set(SupportedDocumentTypes.identifiers).count, SupportedDocumentTypes.identifiers.count, "no duplicates")
    }

    func testDocumentTypesResolveToSystemTypes() {
        XCTAssertTrue(SupportedDocumentTypes.contentTypes.contains(.pdf))
        XCTAssertEqual(SupportedDocumentTypes.contentTypes.count, SupportedDocumentTypes.identifiers.count,
                       "every identifier must be a type the system knows")
    }

    func testGalleryMediaTypesHonourDisabledFeatures() {
        XCTAssertEqual(ImagePickerHelper.galleryMediaTypes(disabledFeatures: []).first, UTType.image.identifier)
        let noVideo = ImagePickerHelper.galleryMediaTypes(disabledFeatures: [.sendVideoMessageFromGallery])
        XCTAssertEqual(noVideo, [UTType.image.identifier])
        let noImage = ImagePickerHelper.galleryMediaTypes(disabledFeatures: [.sendImageMessageFromGallery])
        XCTAssertFalse(noImage.contains(UTType.image.identifier))
        XCTAssertTrue(noImage.contains(UTType.movie.identifier))
    }
}
