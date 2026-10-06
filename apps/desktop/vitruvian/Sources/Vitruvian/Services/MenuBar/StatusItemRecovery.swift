// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 VitruvianSoftware

import CoreGraphics
import Foundation
import VitruvianCore

/// The menu bar icon's anchoring and recovery decisions. The app delegate and
/// the status item controller own the live items and call these with what
/// they read off them.
package enum StatusItemRecovery {
    /// The frame the Shelf's docked chip hangs under, or nil when the item is
    /// hidden, has no window, or its window sits where no menu bar is: a bar
    /// that hides itself parks the window out of sight, and a chip anchored
    /// there would land in a screen corner.
    package static func anchorFrame(isVisible: Bool, windowFrame: CGRect?, screenFrames: [CGRect]) -> CGRect? {
        guard isVisible, let windowFrame,
              StatusItemAnchorSupport.isTrustworthyStatusFrame(windowFrame, screenFrames: screenFrames)
        else { return nil }
        return windowFrame
    }

    /// Whether a point falls on one of the app's status items: the main one,
    /// the clipboard preview's, or a metric's. A hidden item keeps its last
    /// frame, which another app's item may occupy by now, and a frame outside
    /// every menu bar band is not where any icon is drawn, so neither counts.
    package static func containsItem<Item>(at point: CGPoint,
                                           main: Item?,
                                           clipboardPreview: Item?,
                                           metrics: [Item],
                                           isVisible: (Item) -> Bool,
                                           windowFrame: (Item) -> CGRect?,
                                           screenFrames: [CGRect]) -> Bool {
        let items = [main, clipboardPreview].compactMap { $0 } + metrics
        return items.filter { isVisible($0) }.contains { item in
            guard let frame = windowFrame(item),
                  StatusItemAnchorSupport.isTrustworthyStatusFrame(frame, screenFrames: screenFrames)
            else { return false }
            return frame.insetBy(dx: -4, dy: -8).contains(point)
        }
    }

    /// Whether the icon is really in a menu bar. A hidden item is not, whatever
    /// frame its window last had, and intersecting a screen is not enough: an
    /// item macOS never places keeps a full-size window at the main display's
    /// bottom-left origin (#1394).
    package static func iconIsOnScreen(isVisible: Bool, windowFrame: CGRect?, screenFrames: [CGRect]) -> Bool {
        guard isVisible, let windowFrame else { return false }
        return StatusItemPlacementSupport.isPlacedStatusFrame(windowFrame, screenFrames: screenFrames)
    }

    /// What reopening the running app does.
    package enum Reopen: Equatable {
        /// Sent by the system on its own, such as by Siri or Shortcuts: nothing opens.
        case ignore
        /// A window is already showing; the system's own handling is enough.
        case handled
        /// A person reopened the app with nothing showing: the panel or Settings
        /// comes back, after the icon is rebuilt when it went missing.
        case recover(rebuildIcon: Bool)
    }

    /// Who asked is judged before anything else, so a reopen the system sent
    /// never touches the icon, the panel or Settings. An item the app took out
    /// of the bar itself, for Dynamic Island or for metrics, is not missing,
    /// and a healthy icon is left alone: a rebuild can strand the panel's
    /// anchor.
    package static func reopen(sender: ReopenRequestSupport.Sender?,
                               hasVisibleWindows: Bool,
                               hiddenByChoice: Bool,
                               iconIsOnScreen: () -> Bool) -> Reopen {
        guard ReopenRequestSupport.isPersonOpeningApp(sender) else { return .ignore }
        guard !hasVisibleWindows else { return .handled }
        return .recover(rebuildIcon: !hiddenByChoice && !iconIsOnScreen())
    }

    /// "Show menu bar icon" is an explicit request to see it, so neither way
    /// of hiding it may put it straight back.
    package static func clearIconHiding(in defaults: UserDefaults) {
        defaults[Preferences.menuBarHideIconWithMetrics] = false
        defaults[Preferences.notchHidesMenuBarIcon] = false
    }

    /// The next step of checking that a rebuilt icon came back.
    package enum ReshowStep: Equatable {
        /// A later choice to hide the icon cancels the recovery.
        case stop
        case appeared
        /// The newborn window is still settling; look again without spending an attempt.
        case waitForSettling
        case lookAgain
        /// The app is switched off under "Allow in the Menu Bar": name the setting.
        case reportDisallowed
        /// Start the item over with a fresh identity and look again.
        case resetPlacement
        case reportStillHidden
    }

    /// The setting under System Settings > Menu Bar is read only once the
    /// attempts run out, and before the identity reset: with the app switched
    /// off there, macOS never places the item whatever its identity, so a reset
    /// would only burn the arranged spot.
    package static func reshowStep(hidingChosen: Bool,
                                   isOnScreen: Bool,
                                   isSettling: Bool,
                                   settlingGraceLeft: Int,
                                   attemptsLeft: Int,
                                   placementWasReset: Bool,
                                   allowance: () -> MenuBarAllowanceSupport.Allowance) -> ReshowStep {
        guard !hidingChosen else { return .stop }
        if isOnScreen { return .appeared }
        if StatusItemPlacementSupport.shouldKeepWaitingForSettlement(isOnScreen: false,
                                                                     isSettling: isSettling,
                                                                     settlingGraceLeft: settlingGraceLeft) {
            return .waitForSettling
        }
        guard attemptsLeft <= 1 else { return .lookAgain }
        if allowance() == .disallowed { return .reportDisallowed }
        guard placementWasReset else { return .resetPlacement }
        return .reportStillHidden
    }

    /// What the alert ending a recovery says. A disallowed item names the
    /// System Settings switch instead of blaming a full bar; an item still
    /// hidden names a running menu bar organizer that may be holding it.
    package static func alertBody(for step: ReshowStep, strings: Strings, menuBarManager: String?) -> String? {
        switch step {
        case .reportDisallowed:
            return strings.menuBarIconDisallowedBody
        case .reportStillHidden:
            var body = strings.menuBarIconStillHiddenBody
            if let menuBarManager {
                body += "\n\n" + String(format: strings.menuBarIconManagerHintFormat, menuBarManager, menuBarManager)
            }
            return body
        case .stop, .appeared, .waitForSettling, .lookAgain, .resetPlacement:
            return nil
        }
    }
}
