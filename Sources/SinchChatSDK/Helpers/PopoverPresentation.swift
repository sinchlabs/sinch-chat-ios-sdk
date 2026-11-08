import UIKit
import ObjectiveC

/// Anchoring for everything the chat presents from a tapped control.
///
/// Action sheets, activity sheets and pickers must be popovers on regular width; without a source the
/// presentation crashes on iPad. Compact width ignores all of this and keeps the usual sheet or full-screen
/// presentation.
///
/// Two kinds of anchors:
/// - a bar button item or a view that stays in its window (a bubble, a navigation bar button) is handed to UIKit
///   as a `sourceItem`, so the arrow follows it through rotation and window resizing;
/// - a control that may leave its window before or while the popover is up (the compose bar is an input
///   accessory view and goes away with the keyboard) is captured as a rect in a stable host view at tap time,
///   see ``Anchor``. The rect is recomputed when the popover repositions.
@MainActor
enum PopoverPresentation {

    // MARK: - Anchor

    /// Where a popover points, captured while the tapped control is still on screen.
    @MainActor
    struct Anchor {
        weak var host: UIView?
        weak var control: UIView?
        /// Rect of the control in `host` coordinates at capture time. `nil` when the control was not in a window.
        let capturedRect: CGRect?
        let capturedHostSize: CGSize

        /// Without a control in a window the anchor is the centre of `host`, without an arrow.
        init(control: UIView?, in host: UIView) {
            self.host = host
            self.capturedHostSize = host.bounds.size
            if let control, control.window != nil, host.window != nil {
                self.control = control
                self.capturedRect = host.convert(control.bounds, from: control)
            } else {
                self.control = nil
                self.capturedRect = nil
            }
        }

        var hasArrow: Bool { capturedRect != nil }

        /// The rect to point at, in `host` coordinates, right now.
        func currentRect() -> CGRect {
            guard let host else { return .zero }
            guard let capturedRect else {
                return CGRect(x: host.bounds.midX, y: host.bounds.midY, width: 0, height: 0)
            }
            if let control, control.window != nil, host.window != nil {
                return host.convert(control.bounds, from: control)
            }
            // The control left its window (the keyboard went away). Keep the same relative spot in the host,
            // so a rotation or a resize does not leave the arrow outside of it.
            let size = capturedHostSize
            guard size.width > 0, size.height > 0 else { return capturedRect }
            let scaleX = host.bounds.width / size.width
            let scaleY = host.bounds.height / size.height
            return CGRect(x: capturedRect.minX * scaleX, y: capturedRect.minY * scaleY,
                          width: capturedRect.width * scaleX, height: capturedRect.height * scaleY)
        }
    }

    // MARK: - Alerts and activity sheets

    /// Anchors a presentation that UIKit already makes adaptive, like an action sheet or an activity controller.
    static func anchor(_ presented: UIViewController, to source: (any UIPopoverPresentationControllerSourceItem)?, fallbackView: UIView?) {
        guard let popover = presented.popoverPresentationController else { return }
        applySource(source, fallbackView: fallbackView, presented: presented, to: popover)
    }

    /// Anchors to a rect captured at tap time.
    static func anchor(_ presented: UIViewController, to anchor: Anchor, onDismiss: (() -> Void)? = nil) {
        guard let popover = presented.popoverPresentationController else { return }
        install(anchor, on: popover, presented: presented, compactStyle: nil, onDismiss: onDismiss)
    }

    // MARK: - Pickers

    /// Makes a view controller that is normally full screen or a sheet (document and image pickers) a popover on
    /// regular width. On compact width it keeps the presentation it had before, `compactStyle`: the photo library
    /// is a sheet that swipes down, the document picker covers the screen.
    static func prepareAsPopover(_ presented: UIViewController,
                                 source: (any UIPopoverPresentationControllerSourceItem)?,
                                 fallbackView: UIView?,
                                 compactStyle: UIModalPresentationStyle,
                                 onDismiss: (() -> Void)? = nil) {
        if isCompactWidth(fallbackView ?? (source as? UIView)) {
            presentWithoutPopover(presented, style: compactStyle, onDismiss: onDismiss)
            return
        }
        presented.modalPresentationStyle = .popover
        guard let popover = presented.popoverPresentationController else {
            reportSheetDismissal(of: presented, onDismiss: onDismiss)
            return
        }
        if source == nil, let fallbackView {
            install(Anchor(control: nil, in: fallbackView), on: popover, presented: presented,
                    compactStyle: compactStyle, onDismiss: onDismiss)
        } else {
            applySource(source, fallbackView: fallbackView, presented: presented, to: popover)
            retain(Placement(anchor: nil, compactStyle: compactStyle, onDismiss: onDismiss), on: popover, presented: presented)
        }
    }

    /// Same, anchored to a rect captured at tap time.
    static func prepareAsPopover(_ presented: UIViewController,
                                 anchor: Anchor,
                                 compactStyle: UIModalPresentationStyle,
                                 onDismiss: (() -> Void)? = nil) {
        if isCompactWidth(anchor.host) {
            presentWithoutPopover(presented, style: compactStyle, onDismiss: onDismiss)
            return
        }
        presented.modalPresentationStyle = .popover
        guard let popover = presented.popoverPresentationController else {
            reportSheetDismissal(of: presented, onDismiss: onDismiss)
            return
        }
        install(anchor, on: popover, presented: presented, compactStyle: compactStyle, onDismiss: onDismiss)
    }

    /// The adaptation rule shared by every picker: popover on regular width, `compactStyle` on compact width.
    static func adaptiveStyle(for traitCollection: UITraitCollection,
                              compactStyle: UIModalPresentationStyle) -> UIModalPresentationStyle {
        traitCollection.horizontalSizeClass == .compact ? compactStyle : .none
    }

    private static func isCompactWidth(_ view: UIView?) -> Bool {
        view?.traitCollection.horizontalSizeClass == .compact
    }

    /// Compact width never gets a popover, so the picker keeps the presentation it had without one. The dismissal
    /// the user makes by swiping a sheet down is still reported.
    private static func presentWithoutPopover(_ presented: UIViewController,
                                              style: UIModalPresentationStyle,
                                              onDismiss: (() -> Void)?) {
        presented.modalPresentationStyle = style
        reportSheetDismissal(of: presented, onDismiss: onDismiss)
    }

    // MARK: - Internals

    private static func applySource(_ source: (any UIPopoverPresentationControllerSourceItem)?,
                                    fallbackView: UIView?,
                                    presented: UIViewController,
                                    to popover: UIPopoverPresentationController) {
        if let barButtonItem = source as? UIBarButtonItem {
            popover.barButtonItem = barButtonItem
        } else if let source {
            popover.sourceItem = source
        } else if let fallbackView {
            // No control to point at: centre the popover in the presenting view, without an arrow.
            install(Anchor(control: nil, in: fallbackView), on: popover, presented: presented, compactStyle: nil, onDismiss: nil)
        }
    }

    /// `compactStyle` is the style a picker adapts to on compact width; `nil` leaves the adaptation to UIKit
    /// (action sheets and activity controllers).
    private static func install(_ anchor: Anchor,
                                on popover: UIPopoverPresentationController,
                                presented: UIViewController,
                                compactStyle: UIModalPresentationStyle?,
                                onDismiss: (() -> Void)?) {
        guard let host = anchor.host else { return }
        popover.sourceView = host
        popover.sourceRect = anchor.currentRect()
        if !anchor.hasArrow {
            popover.permittedArrowDirections = []
        }
        retain(Placement(anchor: anchor, compactStyle: compactStyle, onDismiss: onDismiss), on: popover, presented: presented)
    }

    /// Some system pickers refuse `.popover` (the document picker in the phone idiom) and are shown as a sheet.
    /// Their swipe-down dismissal is still reported to `onDismiss`; the presentation style stays the one set.
    private static func reportSheetDismissal(of presented: UIViewController, onDismiss: (() -> Void)?) {
        guard let onDismiss, let presentation = presented.presentationController else { return }
        let placement = Placement(anchor: nil, compactStyle: nil, onDismiss: onDismiss)
        objc_setAssociatedObject(presented, &placementKey, placement, .OBJC_ASSOCIATION_RETAIN_NONATOMIC)
        presentation.delegate = placement
    }

    private static var placementKey: UInt8 = 0

    /// `UIPopoverPresentationController.delegate` is weak; the presented controller keeps the delegate alive.
    private static func retain(_ placement: Placement, on popover: UIPopoverPresentationController, presented: UIViewController) {
        objc_setAssociatedObject(presented, &placementKey, placement, .OBJC_ASSOCIATION_RETAIN_NONATOMIC)
        popover.delegate = placement
    }

    /// Popover delegate: keeps the anchor correct while the popover is up and reports a dismissal that
    /// bypasses the picker's own delegate (tap outside the popover).
    @MainActor
    private final class Placement: NSObject, UIPopoverPresentationControllerDelegate {
        private let anchor: Anchor?
        private let compactStyle: UIModalPresentationStyle?
        private let onDismiss: (() -> Void)?
        private var didReportDismissal = false

        init(anchor: Anchor?, compactStyle: UIModalPresentationStyle?, onDismiss: (() -> Void)?) {
            self.anchor = anchor
            self.compactStyle = compactStyle
            self.onDismiss = onDismiss
        }

        /// Pickers adapt to their pre-popover style (`compactStyle`) on compact width. Action sheets keep UIKit's own
        /// adaptation, so this answers "no opinion" for them by not being asked: see `responds(to:)`.
        func adaptivePresentationStyle(for controller: UIPresentationController,
                                       traitCollection: UITraitCollection) -> UIModalPresentationStyle {
            PopoverPresentation.adaptiveStyle(for: traitCollection, compactStyle: compactStyle ?? .fullScreen)
        }

        override func responds(to selector: Selector!) -> Bool {
            if selector == #selector(UIAdaptivePresentationControllerDelegate.adaptivePresentationStyle(for:traitCollection:)) {
                return compactStyle != nil
            }
            return super.responds(to: selector)
        }

        func popoverPresentationController(_ popoverPresentationController: UIPopoverPresentationController,
                                           willRepositionPopoverTo rect: UnsafeMutablePointer<CGRect>,
                                           in view: AutoreleasingUnsafeMutablePointer<UIView>) {
            guard let anchor, let host = anchor.host else { return }
            view.pointee = host
            rect.pointee = anchor.currentRect()
        }

        func presentationControllerDidDismiss(_ presentationController: UIPresentationController) {
            reportDismissal()
        }

        func popoverPresentationControllerDidDismissPopover(_ popoverPresentationController: UIPopoverPresentationController) {
            reportDismissal()
        }

        /// UIKit may call both dismissal callbacks for one dismissal.
        private func reportDismissal() {
            guard !didReportDismissal else { return }
            didReportDismissal = true
            onDismiss?()
        }
    }
}
