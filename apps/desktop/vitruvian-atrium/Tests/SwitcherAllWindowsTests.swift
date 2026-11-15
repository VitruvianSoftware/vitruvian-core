// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import AppKit
import Carbon.HIToolbox
import VitruvianAtriumCore
import VitruvianAtriumServices

/// The all-windows session's list, start, shortcut routing and preferences,
/// run against synthetic windows. Key events are inspected in memory, never
/// posted to the desktop or registered as hotkeys.
enum SwitcherAllWindowsTests {

    static func run(_ suite: TestSuite) {
        let first = SwitcherItem.window(id: 1, title: "Editor one", appName: "Editor", pid: 10,
                                        isOnScreen: true, frame: .zero)
        let second = SwitcherItem.window(id: 2, title: "Editor two", appName: "Editor", pid: 10,
                                         isOnScreen: true, frame: .zero)
        let browser = SwitcherItem.window(id: 3, title: "Browser", appName: "Browser", pid: 20,
                                          isOnScreen: true, frame: .zero)
        let minimized = SwitcherItem.window(id: 4, title: "Minimized", appName: "Editor", pid: 10,
                                            isOnScreen: false, isMinimized: true, frame: .zero)
        let fullscreen = SwitcherItem.window(id: 5, title: "Fullscreen", appName: "Browser", pid: 20,
                                             isOnScreen: false, isFullscreen: true, frame: .zero)
            .withHiddenSpaceState(true)
        let windowless = SwitcherItem.appOnly(appName: "Empty app", pid: 30)
        let items = [first, second, browser, minimized, fullscreen, windowless]
        let expectedIDs = [first, second, browser, minimized, fullscreen].map(\.id)
        let allWindows = SwitcherSupport.windowsForSession(items, scope: .allWindows, frontmostPID: 10)
        suite.expect(allWindows.map(\.id) == expectedIDs,
                     "all windows preserves window order, minimized and fullscreen entries, excluding windowless apps")
        suite.expect(SwitcherSupport.windowsForSession(items, scope: .allApps, frontmostPID: 10).map(\.id)
                     == items.map(\.id), "the existing app shortcut keeps windowless entries")
        suite.expect(SwitcherSupport.windowsForSession(items, scope: .frontmostApp, frontmostPID: 10).map(\.id)
                     == [first.id, second.id, minimized.id], "the existing window shortcut stays within one app")
        suite.expect(SwitcherSupport.windowsForSession([windowless], scope: .allWindows, frontmostPID: 30).isEmpty,
                     "all windows does not open an app-only session when no windows are eligible")
        suite.expect(SwitcherSupport.windowsForSession([browser], scope: .allWindows, frontmostPID: 10).map(\.id)
                     == [browser.id], "all windows never reintroduces windows removed by display, Space or app filters")

        // The first two MRU windows belong to the same app: grouping them would
        // skip the second window, the behavior this shortcut is meant to avoid.
        // A window-scoped session, all windows included, starts on the next
        // window rather than the next app.
        suite.expect(SwitcherSupport.initialWindowScopedSelectionIndex(itemCount: allWindows.count,
                                                                      hasForegroundItem: true, reversed: false) == 1,
                     "a quick press reaches the other window of the same app")
        suite.expect(SwitcherSupport.initialWindowScopedSelectionIndex(itemCount: allWindows.count,
                                                                      hasForegroundItem: true, reversed: true) == 4,
                     "reverse starts at the last eligible window")
        suite.expect(SwitcherSupport.initialWindowScopedSelectionIndex(itemCount: allWindows.count,
                                                                      hasForegroundItem: false, reversed: false) == 0,
                     "a filtered foreground starts at the first visible entry")
        for merge in [false, true] {
            suite.expect(SwitcherSupport.usesWindowRow(simpleMode: true, mergeWindowsByApp: merge,
                                                       sessionScope: .allWindows),
                         "Simple list shows each window even with app grouping \(merge)")
            suite.expect(!SwitcherSupport.usesWindowRow(simpleMode: false, mergeWindowsByApp: merge,
                                                        sessionScope: .allWindows),
                         "Large icons keeps its app icons and selected app's preview strip, grouped \(merge)")
        }
        suite.expect(!SwitcherSupport.usesWindowRow(simpleMode: true, mergeWindowsByApp: true, sessionScope: .allApps),
                     "the existing grouped app shortcut keeps its app rows")

        windowlessCapChecks(suite)
        shortcutChecks(suite)
        preferenceChecks(suite)
    }

    private static func shortcutChecks(_ suite: TestSuite) {
        func event(_ shortcut: GlobalShortcut, reversed: Bool = false) -> CGEvent {
            let event = CGEvent(keyboardEventSource: nil, virtualKey: CGKeyCode(shortcut.keyCode), keyDown: true)!
            event.flags = shortcut.modifiers.cgFlags
            if reversed { event.flags.insert(.maskShift) }
            return event
        }
        for (shortcut, scope) in [(GlobalShortcut.switcherDefault, SwitcherSessionScope.allApps),
                                  (.switcherWindowDefault, .frontmostApp),
                                  (.switcherAllWindowsDefault, .allWindows)] {
            for reversed in [false, true] {
                let match = SwitcherSupport.shortcutMatch(event: event(shortcut, reversed: reversed),
                                                          appsShortcut: .switcherDefault,
                                                          windowShortcut: .switcherWindowDefault,
                                                          allWindowsShortcut: .switcherAllWindowsDefault)
                suite.expect(match?.scope == scope && match?.shortcut == shortcut && match?.reversed == reversed,
                             "\(scope) routes its own shortcut and reverse direction")
            }
        }
        suite.expect(SwitcherSupport.shortcutMatch(event: event(.switcherAllWindowsDefault),
                                                   appsShortcut: .switcherDefault,
                                                   windowShortcut: .switcherWindowDefault) == nil,
                     "disabled all-windows shortcut leaves Option-Tab untouched")
        for existing in [GlobalShortcut.switcherDefault, .switcherWindowDefault] {
            let match = SwitcherSupport.shortcutMatch(event: event(existing), appsShortcut: .switcherDefault,
                                                      windowShortcut: .switcherWindowDefault,
                                                      allWindowsShortcut: existing)
            suite.expect(match?.scope != .allWindows, "a conflicting imported shortcut preserves the existing binding")
        }
        let custom = GlobalShortcut(keyCode: Int64(kVK_ANSI_J), modifiers: [.control, .option, .shift])
        suite.expect(SwitcherSupport.shortcutMatch(event: event(custom), appsShortcut: .switcherDefault,
                                                   windowShortcut: .switcherWindowDefault,
                                                   allWindowsShortcut: custom)?.reversed == false,
                     "Shift required by a custom shortcut does not reverse its first step")

        let native = [LiveSystemShortcut(id: 1, shortcut: .switcherDefault, enabled: true),
                      LiveSystemShortcut(id: 2, shortcut: GlobalShortcut(keyCode: 48, modifiers: [.command, .shift]), enabled: true)]
        for takeOver in [false, true] {
            for secure in [false, true] {
                let ids = SwitcherSupport.nativeHotkeyIDs(takeOverSystemShortcuts: takeOver,
                                                          secureInputEnabled: secure,
                                                          appsShortcut: custom, windowShortcut: custom,
                                                          allWindowsShortcut: .switcherDefault, liveEntries: native)
                suite.expect(ids == (takeOver && !secure ? [1, 2] : []),
                             "all windows suppresses native keys only with takeover enabled and secure input off")
            }
        }
        suite.expect(SwitcherSupport.nativeHotkeyIDs(takeOverSystemShortcuts: true, secureInputEnabled: false,
                                                      appsShortcut: custom, windowShortcut: custom,
                                                      liveEntries: native).isEmpty,
                     "disabling all windows releases the native combination it used")
    }

    private static func preferenceChecks(_ suite: TestSuite) {
        let role = GlobalShortcutRole.switcherAllWindows
        let defaults = Defaults.registeredDefaults
        suite.expect(defaults[DefaultsKey.switcherAllWindowsShortcutEnabled] as? Bool == false
                     && defaults[role.storageKey] as? String == role.defaultShortcut.storageValue,
                     "all windows is opt-in and has a registered configurable default")
        for disabled in role.requiredEnableKeys {
            suite.expect(!GlobalShortcutRole.activeRoles(isOn: { $0 != disabled }, isAvailable: { _ in true }).contains(role),
                         "all windows releases its key when \(disabled) is off")
        }
        suite.expect(!GlobalShortcutRole.availableRoles(isAvailable: { $0 != .switcher }).contains(role),
                     "uninstalling the switcher also removes the new shortcut")
        suite.expect(SettingsBackupSupport.exportKeys().isSuperset(of: [role.storageKey, DefaultsKey.switcherAllWindowsShortcutEnabled]),
                     "the shortcut and opt-in travel in settings backups")
        let english = FeatureStrings.switcherShortcuts(.enUS)
        for language in AppLanguage.allCases {
            let text = FeatureStrings.switcherShortcuts(language)
            suite.expect(!text.allWindows.isEmpty && !text.allWindowsCaption.isEmpty,
                         "all windows has complete labels in \(language.rawValue)")
            if language != .enUS {
                suite.expect(text.allWindows != english.allWindows && text.allWindowsCaption != english.allWindowsCaption,
                             "all windows is translated in \(language.rawValue)")
            }
        }
    }

    /// Windowless app entries leave an all-windows list before the cap, so
    /// they cannot use up places a real window needs.
    private static func windowlessCapChecks(_ suite: TestSuite) {
        let windows = (1...40).map { id in
            SwitcherItem.window(id: CGWindowID(id), title: "Window \(id)", appName: "App", pid: 1,
                                isOnScreen: true, frame: CGRect(x: 0, y: 0, width: 600, height: 400))
        }
        let windowless = (2...41).map { SwitcherItem.appOnly(appName: "App \($0)", pid: pid_t($0)) }
        let regular = WindowEnumerator.shaped(windows + windowless,
                                              by: WindowEnumerator.Shaping(windowlessApps: .all, maximumCount: 48),
                                              orderByUse: { $0 })
        suite.expect(regular.items.count == 48 && regular.items.contains(where: \.isAppEntry),
                     "the existing shortcut still reserves slots for eligible windowless apps")
        let allWindows = WindowEnumerator.shaped(windows + windowless,
                                                 by: WindowEnumerator.Shaping(windowlessApps: .all, maximumCount: 48,
                                                                              windowsOnly: true),
                                                 orderByUse: { $0 })
        suite.expect(allWindows.items.compactMap(\.windowID) == (1...40).map(CGWindowID.init),
                     "all windows excludes windowless apps before capping so they cannot displace real windows")
    }
}
