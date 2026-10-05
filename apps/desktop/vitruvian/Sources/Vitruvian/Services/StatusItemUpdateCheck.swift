// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 VitruvianSoftware

import AppKit
import VitruvianCore

/// The first launch of a newer version checks, for a bounded time, that the
/// menu bar icon really came back, and rebuilds it once if it did not.
/// Normal launches and activations never disturb an arranged menu bar.
/// `AppDelegate` passes its status item and the system; tests pass doubles.
@MainActor
package struct StatusItemUpdateCheck<Item: AnyObject> {
    /// The app's side: its status item and what it is doing.
    @MainActor
    package struct Host {
        /// The status item now; a reopen or a recovery replaces it.
        package var item: () -> Item?
        package var isTerminating: () -> Bool
        /// The person's own recovery owns the item.
        package var isReshowing: () -> Bool
        package var panelIsShown: () -> Bool
        package var hasMenu: (Item) -> Bool
        package var isVisible: (Item) -> Bool
        package var iconIsOnScreen: () -> Bool
        /// Rebuilds the item, keeping its autosave identity and position.
        package var recreate: () -> Void
        package var log: (_ stage: String) -> Void

        package init(item: @escaping () -> Item?, isTerminating: @escaping () -> Bool,
                     isReshowing: @escaping () -> Bool, panelIsShown: @escaping () -> Bool,
                     hasMenu: @escaping (Item) -> Bool, isVisible: @escaping (Item) -> Bool,
                     iconIsOnScreen: @escaping () -> Bool, recreate: @escaping () -> Void,
                     log: @escaping (String) -> Void) {
            self.item = item
            self.isTerminating = isTerminating
            self.isReshowing = isReshowing
            self.panelIsShown = panelIsShown
            self.hasMenu = hasMenu
            self.isVisible = isVisible
            self.iconIsOnScreen = iconIsOnScreen
            self.recreate = recreate
            self.log = log
        }
    }

    /// The build, the clock, the displays, the menu bar and the session.
    @MainActor
    package struct System {
        package var isDeveloperBuild: () -> Bool
        package var version: () -> String
        package var now: () -> Date
        package var after: (TimeInterval, @escaping @MainActor () -> Void) -> Void
        package var screenFrames: () -> [CGRect]
        package var mouseIsPressed: () -> Bool
        /// The person chose to hide the icon behind the menu bar metrics.
        package var hidesIcon: () -> Bool
        package var menuBarVisible: () -> Bool
        /// The front app hides or auto-hides the menu bar, or is full screen.
        package var presentationHidesMenuBar: () -> Bool
        package var session: () -> [String: Any]?
        /// The menu bar organizer running, if any.
        package var menuBarManager: () -> String?

        package init(isDeveloperBuild: @escaping () -> Bool, version: @escaping () -> String,
                     now: @escaping () -> Date, after: @escaping (TimeInterval, @escaping @MainActor () -> Void) -> Void,
                     screenFrames: @escaping () -> [CGRect], mouseIsPressed: @escaping () -> Bool,
                     hidesIcon: @escaping () -> Bool, menuBarVisible: @escaping () -> Bool,
                     presentationHidesMenuBar: @escaping () -> Bool, session: @escaping () -> [String: Any]?,
                     menuBarManager: @escaping () -> String?) {
            self.isDeveloperBuild = isDeveloperBuild
            self.version = version
            self.now = now
            self.after = after
            self.screenFrames = screenFrames
            self.mouseIsPressed = mouseIsPressed
            self.hidesIcon = hidesIcon
            self.menuBarVisible = menuBarVisible
            self.presentationHidesMenuBar = presentationHidesMenuBar
            self.session = session
            self.menuBarManager = menuBarManager
        }

        /// The running app's, with the organizer lookup the app passes.
        package static func live(menuBarManager: @escaping () -> String?) -> System {
            System(isDeveloperBuild: { AppInfo.isDeveloperBuild },
                   version: { AppInfo.version },
                   now: { Date() },
                   after: { delay, work in DispatchQueue.main.asyncAfter(deadline: .now() + delay) { work() } },
                   screenFrames: { NSScreen.screens.map(\.frame) },
                   mouseIsPressed: { NSEvent.pressedMouseButtons != 0 },
                   hidesIcon: { UserDefaults.standard.bool(forKey: DefaultsKey.menuBarHideIconWithMetrics) },
                   menuBarVisible: { NSMenu.menuBarVisible() },
                   presentationHidesMenuBar: {
                       !NSApp.currentSystemPresentationOptions.intersection(
                           [.autoHideMenuBar, .hideMenuBar, .fullScreen]).isEmpty
                   },
                   session: { CGSessionCopyCurrentDictionary() as? [String: Any] },
                   menuBarManager: menuBarManager)
        }
    }

    package let host: Host
    package let system: System
    /// How long each look waits for the menu bar to settle.
    package let interval: TimeInterval

    package init(host: Host, system: System, interval: TimeInterval) {
        self.host = host
        self.system = system
        self.interval = interval
    }

    /// Starts the check when this launch follows an update from
    /// `previousVersion`; a first install, a downgrade or a developer build
    /// leaves the menu bar alone.
    package func start(previousVersion: String?) {
        guard let previousVersion, !system.isDeveloperBuild(),
              let previous = UpdateServiceSupport.SemanticVersion(raw: previousVersion),
              let current = UpdateServiceSupport.SemanticVersion(raw: system.version()), current > previous,
              let item = host.item() else { return }
        let screens = system.screenFrames()
        guard !screens.isEmpty else { return }
        verify(item, screenFrames: screens, deadline: system.now().addingTimeInterval(30))
    }

    package func verify(_ item: Item, screenFrames: [CGRect], deadline: Date,
                        attemptsLeft: Int = 12, recreated: Bool = false) {
        system.after(interval) { [weak item] in
            // Reopening or explicitly recovering the app replaces this item,
            // cancelling these callbacks. A sleep, display change or hidden bar
            // is not evidence of failed placement, so those stop the check too.
            guard let item, host.item() === item,
                  !host.isTerminating(), !host.isReshowing(),
                  !host.panelIsShown(), !host.hasMenu(item), host.isVisible(item),
                  !system.mouseIsPressed(),
                  system.now() < deadline,
                  !system.hidesIcon(),
                  system.screenFrames() == screenFrames,
                  system.menuBarVisible(),
                  !system.presentationHidesMenuBar(),
                  let session = system.session(),
                  SessionActivitySupport.isOnConsole(session),
                  !KeepAwakeAutomationSupport.isScreenLocked(sessionDictionary: session),
                  system.menuBarManager() == nil else { return }
            if host.iconIsOnScreen() {
                host.log("post-update appeared")
                return
            }
            guard attemptsLeft <= 1 else {
                verify(item, screenFrames: screenFrames, deadline: deadline,
                       attemptsLeft: attemptsLeft - 1, recreated: recreated)
                return
            }
            // Preserve the autosave identity and position. The more disruptive
            // reset remains exclusive to the person's explicit recovery action.
            guard !recreated else {
                host.log("post-update still hidden")
                return
            }
            host.log("post-update recreating")
            host.recreate()
            if let replacement = host.item() {
                verify(replacement, screenFrames: screenFrames, deadline: deadline, recreated: true)
            }
        }
    }
}
