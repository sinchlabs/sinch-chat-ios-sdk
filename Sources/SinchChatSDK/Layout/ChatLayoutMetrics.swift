import UIKit

/// Breakpoints and caps for the chat screen.
///
/// A pure function of the container width and the two size classes, never of the device model or the
/// user interface idiom. That keeps iPhone, iPhone Duo (folded and unfolded), iPad full screen, Split View,
/// Slide Over and Stage Manager windows on one code path, and keeps the numbers unit-testable.
///
/// | Environment                              | Message column      | Text / file bubble       | Rich cards |
/// |------------------------------------------|---------------------|--------------------------|------------|
/// | Compact width                            | full width          | 78 % of the column       | 300 pt     |
/// | Regular width, container 900 pt or less  | min(width, 680 pt)  | min(78 % of column, 520) | 360 pt     |
/// | Regular width, container wider than 900  | min(width, 760 pt)  | min(78 % of column, 520) | 360 pt     |
///
/// Compact height (phone landscape) additionally hides the incoming avatar to win horizontal space.
struct ChatLayoutMetrics: Equatable, Sendable {

    // MARK: - Tunables

    /// Largest container width that still gets the narrower regular-width column.
    static let wideContainerThreshold: CGFloat = 900
    static let regularColumnMaxWidth: CGFloat = 680
    static let wideColumnMaxWidth: CGFloat = 760
    static let bubbleWidthFraction: CGFloat = 0.78
    static let regularBubbleMaxWidth: CGFloat = 520
    static let compactRichCardWidth: CGFloat = 300
    static let regularRichCardWidth: CGFloat = 360
    /// File bubbles keep their historical cap on compact width.
    static let compactFileBubbleMaxWidth: CGFloat = 280
    /// On regular width the opposite-side reserve of a bubble shrinks to this, because the column is
    /// already capped and the 71 pt phone reserve would only waste room.
    static let regularSideReserve: CGFloat = 24

    // MARK: - Inputs

    let containerWidth: CGFloat
    let isRegularWidth: Bool
    let isCompactHeight: Bool

    init(containerWidth: CGFloat,
         horizontalSizeClass: UIUserInterfaceSizeClass,
         verticalSizeClass: UIUserInterfaceSizeClass) {
        self.containerWidth = max(0, containerWidth)
        // `.unspecified` (a view that is not in a window yet) falls back to the phone layout.
        self.isRegularWidth = horizontalSizeClass == .regular
        self.isCompactHeight = verticalSizeClass == .compact
    }

    init(containerWidth: CGFloat, traitCollection: UITraitCollection) {
        self.init(containerWidth: containerWidth,
                  horizontalSizeClass: traitCollection.horizontalSizeClass,
                  verticalSizeClass: traitCollection.verticalSizeClass)
    }

    // MARK: - Column

    /// Cap of the message column, `nil` when the column simply fills the container.
    var columnMaxWidth: CGFloat? {
        guard isRegularWidth else { return nil }
        return containerWidth > Self.wideContainerThreshold ? Self.wideColumnMaxWidth : Self.regularColumnMaxWidth
    }

    var columnWidth: CGFloat {
        guard let cap = columnMaxWidth else { return containerWidth }
        return min(containerWidth, cap)
    }

    /// Space left empty on each side of the column. Rounded down so both sides stay on whole points.
    var columnSideInset: CGFloat {
        max(0, ((containerWidth - columnWidth) / 2).rounded(.down))
    }

    // MARK: - Bubbles and cards

    /// Maximum width of a text or file bubble inside a column of the given width.
    func bubbleMaxWidth(inColumnOfWidth width: CGFloat) -> CGFloat {
        let proportional = width * Self.bubbleWidthFraction
        return isRegularWidth ? min(proportional, Self.regularBubbleMaxWidth) : proportional
    }

    /// Width of cards, choices, images, locations, media-text and voice messages.
    var richCardWidth: CGFloat {
        isRegularWidth ? Self.regularRichCardWidth : Self.compactRichCardWidth
    }

    /// Hard cap for file bubbles, on top of ``bubbleMaxWidth(inColumnOfWidth:)``.
    var fileBubbleMaxWidth: CGFloat {
        isRegularWidth ? .greatestFiniteMagnitude : Self.compactFileBubbleMaxWidth
    }

    // MARK: - Chrome

    var showsIncomingAvatar: Bool { !isCompactHeight }
}
