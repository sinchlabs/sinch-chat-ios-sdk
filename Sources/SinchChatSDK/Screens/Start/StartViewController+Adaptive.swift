import UIKit

/// Adaptive-layout glue of the chat screen: where it sits (for the compose bar), the leading navigation button
/// inside a split view, bottom insets across size changes, and anchors for popovers.
extension StartViewController {

    // MARK: - Compose bar placement

    /// Size classes and placement of this screen, pushed into the compose bar that is hosted outside this hierarchy.
    func pushLayoutEnvironmentToComposeView() {
        mainView.messageComposeView.updateLayoutEnvironment(horizontalSizeClass: traitCollection.horizontalSizeClass,
                                                            verticalSizeClass: traitCollection.verticalSizeClass,
                                                            placement: composePlacement())
    }

    /// A push or an interactive pop moves this view inside the window without changing its size, so the placement
    /// the compose bar derived from the frames can be stale once the transition ends. Recompute and relayout.
    func refreshComposeBarAfterTransition() {
        pushLayoutEnvironmentToComposeView()
        mainView.messageComposeView.setNeedsLayout()
    }

    /// The chat's own area and message column in this view's coordinates. The detail frame excludes the safe area
    /// (so an `additionalSafeAreaInsets` hinge inset of a split detail is respected by the controls), the area frame
    /// includes it (so the bar's background reaches the screen edges), and the column is the one `ChatFlowLayout`
    /// centres, so the compose controls line up with the bubbles.
    func composePlacement() -> ComposeChatPlacement {
        let collectionView = mainView.collectionView
        let metrics = ChatLayoutMetrics(containerWidth: collectionView.frame.width, traitCollection: collectionView.traitCollection)
        let inset = metrics.columnSideInset
        let column = CGRect(x: collectionView.frame.minX + inset, y: collectionView.frame.minY,
                            width: max(0, collectionView.frame.width - 2 * inset), height: collectionView.frame.height)
        let safe = view.safeAreaLayoutGuide.layoutFrame
        let detail = CGRect(x: safe.minX, y: view.bounds.minY, width: safe.width, height: view.bounds.height)
        return ComposeChatPlacement(detailFrame: detail, columnFrame: column, areaFrame: view.bounds, space: view)
    }

    // MARK: - Leading navigation button

    /// True when this chat is the root of the detail column of an expanded inbox split view. The close button would
    /// dismiss the whole inbox and a back button would have nothing to go back to there, so none is shown.
    var isRootOfExpandedSplitDetail: Bool {
        navigationController is InboxDetailNavigationController
            && navigationController?.viewControllers.first === self
            && splitViewController?.isCollapsed == false
    }

    /// Installs, replaces or removes the close / back button. Safe to call whenever the context may have changed:
    /// after a modal is dismissed, and when the split view collapses or expands.
    func updateLeadingBarButton() {
        let isSplitRoot = isRootOfExpandedSplitDetail
        lastEvaluatedAsSplitRoot = isSplitRoot
        if isSplitRoot {
            if ownsLeadingBarButton {
                navigationItem.leftBarButtonItem = nil
                ownsLeadingBarButton = false
            }
            return
        }
        if isModal {
            addCloseButton()
        } else {
            addBackButton()
        }
        ownsLeadingBarButton = true
    }

    /// The split view collapses and expands without telling the chat directly (the size class can flip before
    /// `isCollapsed` does), so layout re-checks the one condition the button depends on.
    func reevaluateLeadingBarButtonIfContextChanged() {
        guard lastEvaluatedAsSplitRoot != nil, isRootOfExpandedSplitDetail != lastEvaluatedAsSplitRoot else { return }
        updateLeadingBarButton()
    }

    // MARK: - Bottom inset

    /// The bottom inset for what is on screen now: the last keyboard frame this controller acted on, or only the
    /// compose bar when there has been none.
    func currentBottomInset() -> CGFloat {
        guard let screenFrame = lastKeyboardEndFrameInScreen else { return requiredInitialScrollViewBottomInset() }
        return requiredScrollViewBottomInset(forKeyboardFrame: keyboardFrameInView(screenFrame))
    }

    /// A rotation, fold or resize finished. With the keyboard up the inset has to keep covering it.
    func restoreBottomInsetAfterTransition() {
        messageCollectionViewBottomInset = currentBottomInset()
    }

    // MARK: - Popovers

    /// Captures where the tapped control is now. The compose bar is an input accessory view and leaves its window
    /// with the keyboard, so a popover cannot be anchored to the control itself.
    func popoverAnchor(for control: UIView) -> PopoverPresentation.Anchor {
        PopoverPresentation.Anchor(control: control, in: view)
    }

    /// The system document picker, a popover on regular width. Dismissing the popover by tapping outside does not
    /// call the picker's delegate, so the popover's own dismissal runs the same restore.
    func makeDocumentPicker(anchor: PopoverPresentation.Anchor) -> UIDocumentPickerViewController {
        // `asCopy: true` is the replacement of the deprecated `.import` mode.
        let picker = UIDocumentPickerViewController(forOpeningContentTypes: SupportedDocumentTypes.contentTypes, asCopy: true)
        picker.delegate = self
        // Full screen on compact width, as in 2.1.0.
        PopoverPresentation.prepareAsPopover(picker, anchor: anchor, compactStyle: .fullScreen) { [weak self] in
            self?.finishDocumentPicker()
        }
        return picker
    }

    func presentDocumentPicker(anchor: PopoverPresentation.Anchor) {
        let picker = makeDocumentPicker(anchor: anchor)
        isDocumentPickerPresented = true
        present(picker, animated: true) { [weak self] in
            guard let self, self.isDocumentPickerPresented else { return }
            self.removeKeyboardObservers()
        }
    }

    /// Brings the compose bar back after the document picker, however it went away. Runs once per presentation.
    func finishDocumentPicker() {
        guard isDocumentPickerPresented else { return }
        isDocumentPickerPresented = false
        addKeyboardObservers()
        becomeFirstResponder()
    }
}
