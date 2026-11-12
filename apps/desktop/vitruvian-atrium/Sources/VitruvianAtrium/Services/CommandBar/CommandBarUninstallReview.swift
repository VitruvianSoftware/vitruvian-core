// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 VitruvianSoftware

import Carbon.HIToolbox
import Foundation
import VitruvianCore

/// The command bar's uninstall review: the checklist an uninstall row opens,
/// the extra confirmation a package-managed app asks for, and every way back
/// out. The bar owns its field and its rows; this decides what the review
/// does to them and to the shared uninstaller.
@MainActor
package final class CommandBarUninstallReview {
    package typealias Mode = CommandBarService.Mode

    /// The parts of the bar the review moves.
    package struct Host {
        /// The uninstaller is installed. Its command-bar toggle is read here.
        package var isAvailable: () -> Bool
        package var defaults: UserDefaults
        package var mode: () -> Mode
        package var setMode: (Mode) -> Void
        /// Keeps what was typed for the way back.
        package var saveQuery: () -> Void
        /// Back to search with `query` in the field, or what was kept when nil.
        package var returnToSearch: (_ query: String?) -> Void
        package var setWarning: (String?) -> Void
        package var refreshPanelLayout: () -> Void
        /// Drops an app that is gone from every row that offered it.
        package var forget: (_ app: URL) -> Void

        // Spelled out because a memberwise initializer never leaves its module.
        package init(isAvailable: @escaping () -> Bool, defaults: UserDefaults,
                     mode: @escaping () -> Mode, setMode: @escaping (Mode) -> Void,
                     saveQuery: @escaping () -> Void,
                     returnToSearch: @escaping (String?) -> Void,
                     setWarning: @escaping (String?) -> Void,
                     refreshPanelLayout: @escaping () -> Void,
                     forget: @escaping (URL) -> Void) {
            self.isAvailable = isAvailable
            self.defaults = defaults
            self.mode = mode
            self.setMode = setMode
            self.saveQuery = saveQuery
            self.returnToSearch = returnToSearch
            self.setWarning = setWarning
            self.refreshPanelLayout = refreshPanelLayout
            self.forget = forget
        }
    }

    package let uninstaller: AppUninstaller
    private let host: Host
    /// An explicit "uninstall what Finder has selected", waiting on its lookup.
    package var finderRequestID: UUID?
    /// What the Homebrew confirmation showed, so what runs is what was confirmed.
    private var pendingHomebrewRemoval: AppUninstaller.HomebrewRemovalConfirmation?

    package init(uninstaller: AppUninstaller, host: Host) {
        self.uninstaller = uninstaller
        self.host = host
    }

    /// An uninstall row was accepted. The row was offered earlier, so the
    /// feature, the toggle and the app are all asked again before the review
    /// opens; a refusal says why instead of opening an empty checklist.
    package func begin(appURL url: URL, entryID: String) {
        guard host.isAvailable(),
              host.defaults[Preferences.uninstallerCommandBarEnabled],
              uninstaller.select(appURL: url) else {
            host.setWarning(uninstaller.isRemoving
                ? L10n.shared.s.uninstallerRemoving : L10n.shared.s.uninstallerSelectionUnavailable)
            host.refreshPanelLayout()
            return
        }
        host.setWarning(nil)
        host.saveQuery()
        host.setMode(.uninstallReview(entryID: entryID))
        host.refreshPanelLayout()
    }

    /// Whether an uninstall row ends on the uninstaller's page. The row is
    /// offered only for an app the shared checks accept, so the one way
    /// `select` still says no is a removal already running; the page then
    /// opens on that removal instead of the bar closing on nothing.
    package static func opensUninstallerPage(for url: URL, in uninstaller: AppUninstaller) -> Bool {
        uninstaller.select(appURL: url) || uninstaller.isRemoving
    }

    /// Return, or the review's own button.
    package func submit() {
        switch host.mode() {
        case .uninstallReview(let id):
            switch uninstaller.phase {
            case .results: confirm(entryID: id)
            case .done: finish()
            case .empty, .scanning, .removing: break
            }
        case .uninstallHomebrewConfirm(let id):
            confirmHomebrewRemoval(entryID: id)
        default:
            break
        }
    }

    /// Esc. The Homebrew confirmation returns to the checklist it came from,
    /// not all the way home; the checklist returns to the search it replaced.
    package func stepBack() {
        switch host.mode() {
        case .uninstallReview:
            if case .done = uninstaller.phase {
                finish()
            } else {
                if !uninstaller.isRemoving {
                    uninstaller.reset()
                }
                host.returnToSearch(nil)
            }
        case .uninstallHomebrewConfirm(let id):
            host.setMode(.uninstallReview(entryID: id))
            host.refreshPanelLayout()
        default:
            break
        }
    }

    /// A key while the review shows. In a checklist, native controls own Tab,
    /// Space and the arrows; only Return in the search field means the
    /// review's primary action.
    package func handleKey(_ keyCode: Int, searchFieldFocused: Bool) -> Bool {
        if keyCode == kVK_Escape {
            stepBack()
            return true
        }
        if (keyCode == kVK_Return || keyCode == kVK_ANSI_KeypadEnter), searchFieldFocused {
            submit()
            return true
        }
        return false
    }

    /// The field changed. A new search leaves both review steps for what was
    /// typed, and cancels an explicit Finder request still waiting.
    package func queryChanged() {
        host.setWarning(nil)
        finderRequestID = nil
        if host.mode().isUninstallFlow {
            uninstaller.reset()
            host.setMode(.search)
        }
    }

    /// The bar is closing some other way than Esc (its shortcut, a click
    /// outside). The review would otherwise keep its target and checklist,
    /// which then showed up unprompted in Settings and the menu panel. A
    /// removal still running, Homebrew or plain, is never torn down.
    package func close() {
        if host.mode().isUninstallFlow, !uninstaller.isRemoving {
            uninstaller.reset()
        }
        finderRequestID = nil
    }

    /// Return (or the Remove button) while the checklist shows results. A
    /// plain app is trashed in place; a Homebrew-managed one needs its own
    /// confirmation first, the way a destructive row guards itself.
    private func confirm(entryID: String) {
        guard uninstaller.phase == .results, !uninstaller.isRemoving else { return }
        if let confirmation = uninstaller.homebrewRemovalConfirmation {
            pendingHomebrewRemoval = confirmation
            host.setMode(.uninstallHomebrewConfirm(entryID: entryID))
            host.refreshPanelLayout()
            return
        }
        uninstaller.removeSelected()
    }

    /// The Homebrew confirmation itself: runs the removal and returns to the
    /// checklist, which shows its live progress.
    private func confirmHomebrewRemoval(entryID: String) {
        if let confirmation = pendingHomebrewRemoval {
            uninstaller.removeSelectedWithHomebrew(confirmation: confirmation)
        }
        pendingHomebrewRemoval = nil
        host.setMode(.uninstallReview(entryID: entryID))
        host.refreshPanelLayout()
    }

    /// Return (or Done) once removal has finished. Nothing is left to review,
    /// so this goes all the way home with an empty field rather than
    /// reoffering what was typed before the review began.
    private func finish() {
        if let url = uninstaller.target?.url, UninstallerSupport.isConfirmedAbsent(at: url) {
            host.forget(url)
        }
        uninstaller.reset()
        host.returnToSearch("")
    }
}
