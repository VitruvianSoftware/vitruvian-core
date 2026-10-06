// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import ApplicationServices
import Foundation
import VitruvianCore
import VitruvianDesign

package enum AutoQuitWindowEvent: Equatable {
    case windowDestroyed
    case appHidden
    case appDeactivated
    case appActivated
    case mainWindowChanged
    case focusedWindowChanged
    case windowCreated
    case windowDeminiaturized
    case appShown
    case other
}

package enum AutoQuitSupport {
    private static let hostBundleIdentifierKey = "CrBundleIdentifier"
    /// Some guest-app windows run as generated helper apps outside their
    /// container bundle. These identifiers are the only stable relationship
    /// the host exposes between the helper and the app the user excepted.
    private static let guestWindowHostBundleIdentifier = "com.parallels.desktop.console"
    private static let guestWindowBundleIdentifierPrefix = "com.parallels.winapp."

    /// QWERTY position of the W key — only a fallback for when the event carries
    /// no typed character; the service matches the layout-resolved character
    /// first (key codes are positional: 13 types "z" on AZERTY).
    package static let commandWKeyCode: Int64 = 13

    package static func shouldScheduleWindowCheck(for event: AutoQuitWindowEvent,
                                          hasRecentCloseRequest: Bool) -> Bool {
        switch event {
        case .windowDestroyed:
            return true
        case .appHidden:
            return hasRecentCloseRequest
        case .appDeactivated,
             .appActivated,
             .mainWindowChanged,
             .focusedWindowChanged,
             .windowCreated,
             .windowDeminiaturized,
             .appShown,
             .other:
            return false
        }
    }

    /// Every found user window requires a registered destroy notification.
    /// Accessibility-listed windows set that count directly; window-server
    /// evidence when Accessibility lists none still requires one watch.
    /// An app that has never yet shown any window also retries during its initial
    /// watch window so apps creating windows asynchronously on launch are caught.
    package static func needsWindowWatchRetry(registeredWindows: Int,
                                      listedWindows: Int,
                                      foundUserWindow: Bool,
                                      hadPriorWindows: Bool = false) -> Bool {
        if foundUserWindow {
            return registeredWindows < max(listedWindows, 1)
        }
        return !hadPriorWindows && registeredWindows == 0
    }

    /// What one look at an app's windows concludes. The window server is
    /// asked (`serverHasUserWindow`) only when Accessibility listed none. A
    /// window counts as watched only once its destroy notification
    /// registered: Accessibility can list a window and then refuse that
    /// registration, which is exactly the state the retry exists for.
    package static func windowRefresh(listedWindows: Int, watchedWindows: Int, hadWindows: Bool,
                                      serverHasUserWindow: () -> Bool?)
        -> (foundUserWindow: Bool, needsRetry: Bool) {
        let serverWindow = listedWindows == 0 ? serverHasUserWindow() : nil
        let foundUserWindow = listedWindows > 0 || serverWindow == true
        return (foundUserWindow,
                needsWindowWatchRetry(registeredWindows: watchedWindows,
                                      listedWindows: listedWindows,
                                      foundUserWindow: foundUserWindow,
                                      hadPriorWindows: hadWindows || foundUserWindow))
    }

    /// Registers each window notification through `add` and reports whether
    /// the window ended up watched for the one the close path depends on.
    /// Only the destroyed one schedules a check, so it alone decides: a
    /// window that refused the miniaturize notifications is still a window
    /// AutoQuit can act on.
    package static func watchWindow(notifications: [String], add: (String) -> AXError) -> Bool {
        var watched = false
        for notification in notifications {
            let result = add(notification)
            if notification == kAXUIElementDestroyedNotification {
                watched = isWindowNotificationRegistered(result)
            }
        }
        return watched
    }

    /// Whether an app is too busy to answer Accessibility yet, asked through
    /// `copy` of its application element. The probe asks for its windows
    /// rather than the application's role. A Chromium app (Electron, and the
    /// browsers) answers a role query on its application element by
    /// switching its renderers into full accessibility mode, and from then on
    /// it rebuilds and ships an accessibility tree on every DOM change for the
    /// life of the process (issue #953). Windows are the same liveness signal
    /// and leave that mode alone.
    package static func appIsBusy(_ copy: (String) -> AXError) -> Bool {
        copy(kAXWindowsAttribute) == .cannotComplete
    }

    /// When to look at an app after something closed. A window that just went
    /// away is still on screen while it fades out (measured on macOS 27: about
    /// a quarter of a second), and a look that finds a window simply stops
    /// there. A single look was a coin flip against that fade, and losing it
    /// meant the app was never asked to quit at all. Two more looks settle it,
    /// with room for slower machines. All three are offsets from one origin.
    package static let closeCheckOffsets: [TimeInterval] = [0.35, 1.0, 2.2]

    package static func closeCheckDeadlines(from origin: DispatchTime) -> [DispatchTime] {
        closeCheckOffsets.map { origin + $0 }
    }

    /// Whether adding a window notification left the observer watching for it.
    /// Already registered is the ordinary answer, not a failure: every refresh
    /// registers the windows it is already watching again, and counting those
    /// as unwatched would zero the count above on every refresh and leave the
    /// retry firing for as long as the app runs.
    package static func isWindowNotificationRegistered(_ result: AXError) -> Bool {
        result == .success || result == .notificationAlreadyRegistered
    }

    package static func shouldQuitAfterWindowCheck(hadWindows: Bool,
                                           appIsTerminated: Bool,
                                           appIsExcepted: Bool,
                                           appIsHidden: Bool,
                                           hiddenByCloseRequest: Bool,
                                           hasKnownMinimizedWindow: Bool,
                                           hasUserFacingWindow: Bool) -> Bool {
        guard hadWindows, !appIsTerminated, !appIsExcepted else { return false }
        if appIsHidden && !hiddenByCloseRequest { return false }
        if hasKnownMinimizedWindow { return false }
        return !hasUserFacingWindow
    }

    /// An exception for an installed app also covers UI processes bundled
    /// inside it. Some apps put their main windows in a nested application
    /// with a different identifier, even though the user picked the outer app.
    package static func isExcepted(bundleIdentifier: String?,
                           bundleURL: URL?,
                           exceptions: [String]) -> Bool {
        if let bundleIdentifier, exceptions.contains(bundleIdentifier) { return true }
        if let bundleIdentifier,
           bundleIdentifier.hasPrefix(guestWindowBundleIdentifierPrefix),
           exceptions.contains(guestWindowHostBundleIdentifier) {
            return true
        }
        guard var url = bundleURL?.standardizedFileURL.deletingLastPathComponent() else { return false }

        while url.path != "/" {
            if url.pathExtension.caseInsensitiveCompare("app") == .orderedSame,
               let containingIdentifier = Bundle(url: url)?.bundleIdentifier,
               exceptions.contains(containingIdentifier) {
                return true
            }
            let parent = url.deletingLastPathComponent()
            guard parent != url else { break }
            url = parent
        }
        return false
    }

    /// Some standalone apps depend on a separate host process and declare that
    /// relationship in their bundle metadata. Quitting the host while one of
    /// those apps is running would close both from a single window close.
    package static func hasDependentApplication(hostBundleIdentifier: String?,
                                        applicationBundleURLs: [URL]) -> Bool {
        guard let hostBundleIdentifier, !hostBundleIdentifier.isEmpty else { return false }
        return applicationBundleURLs.contains { bundleURL in
            Bundle(url: bundleURL)?.object(forInfoDictionaryKey: hostBundleIdentifierKey) as? String
                == hostBundleIdentifier
        }
    }

    /// Menu bar and background apps (LSUIElement, LSBackgroundOnly) take a
    /// Dock icon only while a window such as Settings is open. Closing that
    /// window is not quitting the app (issue #1824).
    package static func isBackgroundApp(bundleURL: URL?) -> Bool {
        guard let bundleURL, let bundle = Bundle(url: bundleURL) else { return false }
        return ["LSUIElement", "LSBackgroundOnly"].contains { key in
            (bundle.object(forInfoDictionaryKey: key) as? NSNumber)?.boolValue
                ?? (bundle.object(forInfoDictionaryKey: key) as? NSString)?.boolValue
                ?? false
        }
    }

    package static func isCommandW(keyCode: Int64, command: Bool, control: Bool) -> Bool {
        keyCode == commandWKeyCode && command && !control
    }

    /// Phone is kept as a mandatory quit exception for Continuity calls, but on
    /// macOS builds without Phone.app a locked row would show the raw bundle
    /// id. Hide it from the settings list while leaving protection in place.
    package static func shouldDisplayException(bundleID: String, isInstalled: Bool) -> Bool {
        if bundleID == Defaults.phoneBundleIdentifier { return isInstalled }
        return true
    }

    package static func visibleExceptions(_ bundleIDs: [String],
                                  isInstalled: (String) -> Bool) -> [String] {
        bundleIDs.filter { shouldDisplayException(bundleID: $0, isInstalled: isInstalled($0)) }
    }

    /// The exceptions the settings list shows, by name. Whether Phone is
    /// listed depends on whether it is installed on this Mac, which is what
    /// `isInstalled` answers by default.
    package static func listedExceptions(_ bundleIDs: [String],
                                         isInstalled: (String) -> Bool = { InstalledApps.url(for: $0) != nil },
                                         name: (String) -> String = { InstalledApps.name(for: $0) }) -> [String] {
        visibleExceptions(bundleIDs, isInstalled: isInstalled).sorted {
            name($0).localizedCaseInsensitiveCompare(name($1)) == .orderedAscending
        }
    }

    /// Whether a window the screen is not showing still counts as a window the
    /// user has. A window parked on another Space is one swipe away, so it
    /// keeps the app running; a window the app only hid sits on the Space that
    /// is showing right now, and an app that hides its window instead of
    /// destroying it should still quit on close. Accessibility cannot tell the
    /// two apart (both leave the app with no windows at all), the window server
    /// can. Without a Space answer the old rule stands: anything with a title
    /// keeps the app alive.
    package static func offscreenWindowKeepsAppAlive(windowSpaces: [UInt64],
                                             visibleSpaces: Set<UInt64>?,
                                             hasTitle: Bool) -> Bool {
        guard let visibleSpaces, !visibleSpaces.isEmpty, !windowSpaces.isEmpty else { return hasTitle }
        return SpaceHopSupport.isParkedOnHiddenSpace(windowSpaces: windowSpaces,
                                                     visibleSpaces: visibleSpaces)
    }
}

/// What AutoQuit defers per app: a refresh waiting for the next run loop
/// turn, and the bounded round of looks at an app that Accessibility lists no
/// window for while the window server still shows one: it answers late for an
/// app that is busy, and it cannot describe a window parked on a Space that is
/// not visible. Either way the app is marked eligible with nothing to watch,
/// so the close that should quit it destroys a window nobody registered for
/// (issue #1008). Everything an app deferred goes with the app (`detach`) and
/// with the service (`removeAll`): left pending, it would run against an
/// observer that is gone.
package struct AutoQuitDeferredWork {
    /// Offsets from the start of one round, not delays chained from each look.
    /// Accessibility usually catches up within the first; when it never does,
    /// the round ends rather than polling for the life of the app.
    package static let retryOffsets: [TimeInterval] = [0.5, 1.5, 4.0]

    private struct Round {
        let origin: DispatchTime
        var looksScheduled: Int
        var pendingLook: UUID?
    }

    private var pendingRefreshes = Set<pid_t>()
    private var rounds: [pid_t: Round] = [:]

    package init() {}

    /// Asks for a refresh of `pid` on the next run loop turn. False when one
    /// is already waiting: a burst of notifications collapses into one.
    package mutating func requestRefresh(_ pid: pid_t) -> Bool {
        pendingRefreshes.insert(pid).inserted
    }

    /// Takes the waiting refresh as it runs; false once the app has gone.
    package mutating func takeRefresh(_ pid: pid_t) -> Bool {
        pendingRefreshes.remove(pid) != nil
    }

    /// The next look to arm for `pid`, starting a round at `now` when none is
    /// running: its deadline, and the token that alone may run it. Nil while
    /// a look is pending, and once the round has used every offset.
    package mutating func nextLook(for pid: pid_t, now: DispatchTime) -> (deadline: DispatchTime, token: UUID)? {
        var round = rounds[pid] ?? Round(origin: now, looksScheduled: 0, pendingLook: nil)
        guard round.pendingLook == nil, round.looksScheduled < Self.retryOffsets.count else { return nil }
        let token = UUID()
        let deadline = round.origin + Self.retryOffsets[round.looksScheduled]
        round.looksScheduled += 1
        round.pendingLook = token
        rounds[pid] = round
        return (deadline, token)
    }

    /// Whether the look `token` may run now; it stops being pending when it
    /// does. A look from a round that ended, or started again, never runs.
    package mutating func runLook(_ token: UUID, for pid: pid_t) -> Bool {
        guard var round = rounds[pid], round.pendingLook == token else { return false }
        round.pendingLook = nil
        rounds[pid] = round
        return true
    }

    /// The app needs no more looks.
    package mutating func endRetries(for pid: pid_t) {
        rounds[pid] = nil
    }

    /// Ends every round, for a Space change to start each again: the apps to
    /// look at now. Any look armed in an ended round is stale.
    package mutating func rearm() -> [pid_t] {
        let pids = Array(rounds.keys)
        rounds.removeAll()
        return pids
    }

    /// The app went: nothing it deferred may run.
    package mutating func detach(_ pid: pid_t) {
        pendingRefreshes.remove(pid)
        rounds[pid] = nil
    }

    package mutating func removeAll() {
        pendingRefreshes.removeAll()
        rounds.removeAll()
    }
}
