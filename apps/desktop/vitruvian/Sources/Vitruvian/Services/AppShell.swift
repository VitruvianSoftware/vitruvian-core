// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 VitruvianSoftware

import AppKit
import VitruvianCore

/// What services and views may ask of the running app: its windows, the menu
/// bar popover and the status item. `AppDelegate` conforms, so nothing below
/// the app layer names it (REFACTOR.md step 3.2).
///
/// The requirements carry `AppDelegate`'s own signatures, defaults left out;
/// the extension below supplies the short forms callers use. Main actor, like
/// the delegate itself.
@MainActor protocol AppShell: AnyObject {
    func openSettingsWindow()
    func openSettingsFromHighlights()
    func closePopover(animated: Bool, after delay: TimeInterval, preservingNotch: Bool,
                      reason: PanelCloseReason, completion: (() -> Void)?)
    func isOverStatusItem(_ point: NSPoint) -> Bool
    func reshowStatusItem()
    func openFeedbackWindow(kind: FeedbackKind)
    func showOnboarding()
    func showUpdateHighlights(isReview: Bool)
    func showUpdatePreview()
    func showPermissionGuide(for kind: PermissionKind)
    func relaunchApp()
}

extension AppShell {
    /// `AppDelegate.closePopover`'s defaults, for callers that only choose
    /// whether the Dynamic Island stays open.
    func closePopover(preservingNotch: Bool = false) {
        closePopover(animated: true, after: 0, preservingNotch: preservingNotch,
                     reason: .action, completion: nil)
    }

    func openFeedbackWindow() {
        openFeedbackWindow(kind: .bug)
    }
}

/// The running app's shell, nil only when the application delegate is
/// something else.
func appShell() -> AppShell? {
    NSApp.delegate as? AppShell
}
