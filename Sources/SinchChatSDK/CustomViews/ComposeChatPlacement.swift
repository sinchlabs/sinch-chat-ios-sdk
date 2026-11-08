import UIKit

/// Where the chat screen sits, handed to the compose bar by the controller.
///
/// The compose bar is an input accessory view. The system sizes it to the whole window, so it cannot see that
/// the chat may be the detail column of a split view, narrower than the window and offset from its edge, or that
/// the detail has its own safe area (the iPhone Duo hinge, a notch). All frames are in the coordinate space of
/// `space`, normally the chat screen's view; the compose bar converts them into its own.
struct ComposeChatPlacement: Equatable {
    /// The area the chat owns, minus its own safe area. The compose controls stay inside it.
    var detailFrame: CGRect
    /// The centred message column. The compose controls line up with it.
    var columnFrame: CGRect
    /// The whole area the chat owns, safe area included. The compose bar's background fills it, so it reaches the
    /// screen edges under a notch or a status column. When `nil` the background follows `detailFrame`.
    var areaFrame: CGRect?
    weak var space: UIView?

    static func == (lhs: ComposeChatPlacement, rhs: ComposeChatPlacement) -> Bool {
        lhs.detailFrame == rhs.detailFrame && lhs.columnFrame == rhs.columnFrame && lhs.areaFrame == rhs.areaFrame
            && lhs.space === rhs.space
    }
}

/// Rects that come from converting between the app window and the keyboard window are equal only up to rounding.
let composeGeometryTolerance: CGFloat = 0.5

/// Horizontal geometry of the compose bar, all in the bar's own coordinates.
struct ComposeBarColumns: Equatable {
    /// Where the bar's background is drawn. It reaches the window edges the chat reaches, safe area included.
    var background: ClosedRange<CGFloat>
    /// The part of the background inside the safe areas. Full-width content (the voice recorder) lives here.
    var safeBackground: ClosedRange<CGFloat>
    /// Where the controls live: inside the safe areas and the message column.
    var content: ClosedRange<CGFloat>

    /// - Parameters:
    ///   - safe: The bar's safe area range (the whole width minus notch insets).
    ///   - detail: The chat's own range without its safe area, if the chat does not own the whole window.
    ///   - column: The chat's message column, if the controller reported it.
    ///   - bounds: The bar's whole range. Defaults to `safe`.
    ///   - area: The chat's own range including its safe area. Defaults to `detail`.
    ///   - metrics: Used for the column cap when no `column` was reported.
    static func resolve(safe: ClosedRange<CGFloat>,
                        detail: ClosedRange<CGFloat>?,
                        column: ClosedRange<CGFloat>?,
                        bounds: ClosedRange<CGFloat>? = nil,
                        area: ClosedRange<CGFloat>? = nil,
                        metrics: (_ containerWidth: CGFloat) -> ChatLayoutMetrics) -> (columns: ComposeBarColumns, metrics: ChatLayoutMetrics) {
        let tolerance = composeGeometryTolerance
        let whole = bounds ?? safe
        let usable = detail.flatMap { safe.clamped(to: $0, tolerance: tolerance) } ?? safe
        let background = (area ?? detail).flatMap { whole.clamped(to: $0, tolerance: tolerance) }?.snapped(to: whole, tolerance: tolerance) ?? whole
        let safeBackground = background.clamped(to: usable, tolerance: tolerance) ?? usable
        let content: ClosedRange<CGFloat>
        let resolvedMetrics = metrics(safeBackground.upperBound - safeBackground.lowerBound)
        if let column, let inColumn = safeBackground.clamped(to: column, tolerance: tolerance) {
            content = inColumn
        } else {
            let width = min(safeBackground.upperBound - safeBackground.lowerBound, resolvedMetrics.columnMaxWidth ?? .greatestFiniteMagnitude)
            let midX = (safeBackground.lowerBound + safeBackground.upperBound) / 2
            content = (midX - width / 2)...(midX + width / 2)
        }
        return (ComposeBarColumns(background: background, safeBackground: safeBackground, content: content), resolvedMetrics)
    }
}

extension ClosedRange where Bound == CGFloat {
    /// The overlap, `nil` when the ranges are disjoint. Ranges that miss each other by less than `tolerance`
    /// still count as touching and give an empty range at the touching point.
    func clamped(to other: ClosedRange<CGFloat>, tolerance: CGFloat) -> ClosedRange<CGFloat>? {
        let lower = Swift.max(lowerBound, other.lowerBound)
        let upper = Swift.min(upperBound, other.upperBound)
        if lower <= upper { return lower...upper }
        return lower - upper < tolerance ? upper...upper : nil
    }

    /// True when both ends differ by less than `tolerance`.
    func isApproximatelyEqual(to other: ClosedRange<CGFloat>, tolerance: CGFloat = composeGeometryTolerance) -> Bool {
        abs(lowerBound - other.lowerBound) < tolerance && abs(upperBound - other.upperBound) < tolerance
    }

    /// Moves an end that is within `tolerance` of the same end of `other` onto it, so equal-looking ranges compare equal.
    func snapped(to other: ClosedRange<CGFloat>, tolerance: CGFloat = composeGeometryTolerance) -> ClosedRange<CGFloat> {
        let lower = abs(lowerBound - other.lowerBound) < tolerance ? other.lowerBound : lowerBound
        let upper = abs(upperBound - other.upperBound) < tolerance ? other.upperBound : upperBound
        return lower <= upper ? lower...upper : self
    }
}
