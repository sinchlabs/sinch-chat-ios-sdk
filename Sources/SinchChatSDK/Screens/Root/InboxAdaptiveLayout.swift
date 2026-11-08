import UIKit

/// How the inbox presents conversations.
///
/// The choice is made by the integrator, never by device model. With `.automatic` the layout is driven
/// by the size classes of the window the inbox lives in.
public enum SinchInboxLayout: Sendable, Equatable {
    /// A sidebar with the selected chat beside it on regular width (iPad, wide Split View or Stage Manager
    /// windows, an unfolded dual-screen phone). On compact width the list pushes the chat, as before.
    case automatic
    /// Always a list that pushes the chat on a navigation stack. The returned controller must be placed in a
    /// `UINavigationController` by the caller (this was the behaviour before `.automatic` existed).
    case stack
}

/// Pure sizing rules of the adaptive inbox. No UIKit state is read here, so everything is unit-testable.
enum InboxAdaptiveLayout {

    // MARK: Sidebar widths

    static let preferredPrimaryWidth: CGFloat = 320
    static let minimumPrimaryWidth: CGFloat = 280
    static let maximumPrimaryWidth: CGFloat = 360

    /// Narrowest sidebar that may snap to a hinge. There is no upper bound: a centred fold gives the sidebar the
    /// whole leading page, and `hingeCentreTolerance` already keeps it near the middle.
    static let hingeMinimumPrimaryWidth: CGFloat = 280

    // MARK: Window buckets

    /// Above this window width the sidebar is permanently visible.
    static let permanentSidebarMinimumWidth: CGFloat = 900
    /// From this width up the sidebar may be hidden with the system sidebar toggle.
    static let hideableSidebarMinimumWidth: CGFloat = 600

    enum WidthBucket: Equatable {
        case narrow          // < 600
        case medium          // 600...900
        case wide            // > 900
    }

    static func widthBucket(for width: CGFloat) -> WidthBucket {
        if width > permanentSidebarMinimumWidth { return .wide }
        if width >= hideableSidebarMinimumWidth { return .medium }
        return .narrow
    }

    static func preferredDisplayMode(for width: CGFloat) -> UISplitViewController.DisplayMode {
        switch widthBucket(for: width) {
        case .wide: return .oneBesideSecondary
        case .medium, .narrow: return .automatic
        }
    }

    // MARK: Hinge

    /// What the sidebar and chat columns should do so nothing straddles a vertical hinge.
    struct HingeSnap: Equatable {
        /// Width of the sidebar so that it ends at the hinge's leading edge.
        var primaryWidth: CGFloat
        /// Extra leading inset for the chat column, so its content starts after the hinge.
        var secondaryLeadingInset: CGFloat
    }

    /// A hinge that is further than this fraction of the container width from the centre is ignored.
    static let hingeCentreTolerance: CGFloat = 0.15
    /// A hinge region must cover at least this fraction of the container height to count as a vertical hinge.
    static let hingeMinimumHeightFraction: CGFloat = 0.9

    /// Computes the snap for a hinge or division region.
    ///
    /// - Parameters:
    ///   - containerSize: Size of the split view.
    ///   - hingeFrame: Frame of the hinge region in the split view's coordinate space (margins included),
    ///     or `nil` when the device has no active hinge.
    /// - Returns: `nil` when the hinge must be ignored: no hinge, a horizontal (tabletop) hinge, one far from
    ///   the centre of the window, or one whose leading edge is closer than `hingeMinimumPrimaryWidth`.
    static func hingeSnap(containerSize: CGSize, hingeFrame: CGRect?) -> HingeSnap? {
        guard let hingeFrame, containerSize.width > 0, containerSize.height > 0 else { return nil }
        guard !hingeFrame.isNull, !hingeFrame.isEmpty else { return nil }

        // Vertical book posture: a tall, narrow strip spanning (almost) the whole height.
        guard hingeFrame.height >= containerSize.height * hingeMinimumHeightFraction,
              hingeFrame.width < hingeFrame.height else { return nil }

        let centreOffset = abs(hingeFrame.midX - containerSize.width / 2)
        guard centreOffset <= containerSize.width * hingeCentreTolerance else { return nil }

        // The sidebar must end exactly at the hinge. Clamping a too-narrow width would move its edge across the
        // hinge, so such a hinge is ignored instead.
        let width = hingeFrame.minX
        guard width >= hingeMinimumPrimaryWidth else { return nil }
        // The chat column starts where the sidebar ends and additionally skips the hinge strip.
        return HingeSnap(primaryWidth: width, secondaryLeadingInset: hingeFrame.width)
    }
}
