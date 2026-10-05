// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 VitruvianSoftware

import AppKit
import Foundation
import VitruvianCore
import VitruvianDesign
import VitruvianServices
import VitruvianUI

/// The Command Bar's own rows, built by the catalog with recording actions:
/// what each one is called, what it asks first, and what it runs.
enum CommandBarCatalogRowContract {
    /// What the rows' actions did.
    private final class Log {
        var calls: [String] = []
    }

    static func run(_ suite: TestSuite) {
        let language = L10n.shared.language
        let s = L10n.shared.s
        let bar = FeatureStrings.commandBar(language)
        let domain = "com.vitruviansoftware.vitruvian.tests.command-bar-catalog"
        let defaults = UserDefaults(suiteName: domain)!
        defaults.removePersistentDomain(forName: domain)
        defer { defaults.removePersistentDomain(forName: domain) }
        let log = Log()

        // Clearing the clipboard history asks first.
        let clipboard = FeatureStrings.clipboard(language)
        let clear = CommandBarCatalog.clipboardClearEntry(clipboard, subtitle: clipboard.title, trouble: nil,
                                                          clear: { log.calls.append("clear") })
        suite.expect(clear.id == "action.clipboardClearRecent" && clear.title == clipboard.clearRecent
                     && clear.confirmationPrompt == clipboard.clearRecent && clear.needsPrompt,
                     "the Command Bar clears the clipboard history only after confirmation")
        clear.run(nil)
        suite.expect(log.calls == ["clear"], "the confirmed row clears the history once")

        // Volume confirms in Dynamic Island when it can.
        log.calls = []
        var floated: [(icon: String, message: String)] = []
        CommandBarCatalog.confirmVolume(0.4, percent: 40, island: { log.calls.append("island \($0)"); return true },
                                        float: { floated.append((icon: $0, message: $1)) })
        suite.expect(log.calls == ["island 0.4"] && floated.isEmpty,
                     "volume from the bar reports in Dynamic Island when it can")
        CommandBarCatalog.confirmVolume(0.4, percent: 40, island: { _ in false },
                                        float: { floated.append((icon: $0, message: $1)) })
        suite.expect(floated.map(\.icon) == ["speaker.wave.2"] && floated.map(\.message) == ["\(bar.volumeTitle) 40%"],
                     "and floats its confirmation only otherwise")

        // Relaunching.
        log.calls = []
        let restart = CommandBarCatalog.restartAppEntry(bar: bar, relaunch: { log.calls.append("relaunch") })
        suite.expect(restart.id == "action.restartApp"
                     && restart.title == String(format: bar.restartAppFormat, AppInfo.name),
                     "the Command Bar names its own relaunch action in the person's language")
        restart.run(nil)
        suite.expect(log.calls == ["relaunch"], "the relaunch row relaunches")

        // Keep awake turns any duration outside its presets into an
        // indefinite session, so no row may hand it a typed number.
        log.calls = []
        let awake = CommandBarCatalog.keepAwakeEntries(s, bar: bar, subtitle: s.keepAwakeTitle, shortcut: nil,
                                                       isActive: false, toggle: { log.calls.append("toggle") },
                                                       activate: { log.calls.append("\($0)") })
        let plain = awake.first { $0.id == "action.keepAwake" }
        suite.expect(plain != nil && plain?.numericRange == nil,
                     "the plain keep awake row takes no number that could become indefinite")
        plain?.run(nil)
        suite.expect(log.calls == ["toggle"], "the plain keep awake row turns keep awake on or off")
        for minutes in Defaults.allowedDurations where minutes > 0 {
            log.calls = []
            let preset = awake.first { $0.id == "action.keepAwake.\(minutes)" }
            preset?.run(nil)
            suite.expect(preset?.numericRange == nil && log.calls == ["\(minutes)"],
                         "keep awake for \(minutes) minutes has its own Command Bar row")
        }
        suite.expect(awake.count == Defaults.allowedDurations.filter { $0 > 0 }.count + 1,
                     "keep awake offers its presets and nothing else")

        // The mouse button switches.
        defaults.set(true, forKey: AppFeature.mouseButtonShortcuts.availabilityKey)
        func toggles() -> [String: CommandBarEntry] {
            Dictionary(CommandBarCatalog.toggleEntries(s, language: language, bar: bar, defaults: defaults,
                                                       accessible: true).map { ($0.id, $0) },
                       uniquingKeysWith: { first, _ in first })
        }
        let mouseName = AppFeature.mouseButtonShortcuts.hubTitle(s, hub: FeatureStrings.hub(language))
        let spacesName = FeatureStrings.mouseButtons(language).spacesEnableLabel
        defaults.set(true, forKey: DefaultsKey.mouseButtonShortcutsEnabled)
        defaults.set(false, forKey: DefaultsKey.mouseSpacesGestureEnabled)
        var rows = toggles()
        suite.expect(rows["toggle.mouseButtonShortcuts"]?.title == String(format: bar.turnOffFormat, mouseName)
                     && rows["toggle.mouseButtonShortcuts"]?.isActive == true,
                     "the Command Bar keeps the mouse-button shortcut row's key, title and stable id")
        suite.expect(rows["toggle.mouseButtonShortcuts.spacesGesture"]?.title
                        == String(format: bar.turnOnFormat, spacesName)
                     && rows["toggle.mouseButtonShortcuts.spacesGesture"]?.isActive == false,
                     "the Command Bar exposes the Spaces gesture as its own localized toggle row")
        defaults.set(false, forKey: DefaultsKey.mouseButtonShortcutsEnabled)
        defaults.set(true, forKey: DefaultsKey.mouseSpacesGestureEnabled)
        rows = toggles()
        suite.expect(rows["toggle.mouseButtonShortcuts"]?.isActive == false
                     && rows["toggle.mouseButtonShortcuts.spacesGesture"]?.isActive == true,
                     "each mouse-button row follows its own switch")
        defaults.set(false, forKey: AppFeature.mouseButtonShortcuts.availabilityKey)
        suite.expect(toggles()["toggle.mouseButtonShortcuts"] == nil,
                     "a feature that is not available offers no switch")

        // The uninstaller's rows.
        defaults.set(true, forKey: AppFeature.uninstaller.availabilityKey)
        defaults.set(true, forKey: DefaultsKey.uninstallerCommandBarEnabled)
        let taken = URL(fileURLWithPath: "/Applications/Taken.app")
        let refused = URL(fileURLWithPath: "/Applications/Refused.app")
        let apps = [taken, refused].map {
            InstalledApps.InstalledApp(id: $0.path, name: $0.deletingPathExtension().lastPathComponent,
                                       bundleID: "com.example." + $0.deletingPathExtension().lastPathComponent,
                                       url: $0, isSystem: false)
        }
        let browse = CommandBarCatalog.uninstallEntries(apps, uninstallable: [taken.path], bar: bar, defaults: defaults)
        suite.expect(browse.map(\.uninstallAppURL) == [taken],
                     "the uninstall browse offers only apps the uninstaller accepted")
        func selection(_ url: URL, takes: Bool) -> [CommandBarEntry] {
            CommandBarCatalog.uninstallSelectionEntries(urls: [url], automationDenied: false, defaults: defaults,
                                                        isInApplications: { _ in true },
                                                        uninstallerTakes: { _ in takes })
        }
        suite.expect(selection(taken, takes: true).map(\.uninstallAppURL) == [taken]
                     && selection(refused, takes: false).isEmpty,
                     "the Finder selection row offers only an app the uninstaller will take")
        defaults.set(false, forKey: DefaultsKey.uninstallerCommandBarEnabled)
        suite.expect(CommandBarCatalog.uninstallEntries(apps, uninstallable: [taken.path], bar: bar,
                                                        defaults: defaults).isEmpty
                     && selection(taken, takes: true).isEmpty,
                     "turning the Command Bar's uninstall rows off removes both")

        // Rows for things whose ids the system reuses never learn habits.
        let processes = [false, true].map { protected in
            KillProcessEntry(pid: protected ? 2 : 1, ppid: 1, name: protected ? "kernel" : "worker",
                             path: "/usr/bin/worker", cpuPercent: 0, memoryBytes: 0, isRegularApp: false,
                             bundleURL: nil, groupedCount: 1, isProtected: protected, startedAt: nil)
        }
        let kills = CommandBarCatalog.killProcessEntries(processes, killStrings: FeatureStrings.killProcess(language))
        suite.expect(kills.map(\.id) == ["kill.1"] && kills.allSatisfy { !$0.countsUsage },
                     "killProcessEntries excludes recycled process IDs from learning")
        let quits = CommandBarCatalog.quitEntries(NSWorkspace.shared.runningApplications, bar: bar)
        suite.expect(!quits.isEmpty && quits.allSatisfy { row in
            let pidID = NSWorkspace.shared.runningApplications.contains { "quit.\($0.processIdentifier)" == row.id }
            return row.countsUsage != pidID
        }, "quitEntries learns from apps with a bundle id and never from a recycled process ID")

        // A window row hands focus back to the app that was in front when
        // it ran, not to whatever came forward during the beat.
        final class Front {
            var pid: pid_t? = 100
            var pending: [@MainActor () -> Void] = []
            var activated: [(pid: pid_t, window: CGWindowID?, app: String, source: pid_t?)] = []
        }
        let front = Front()
        let window = SwitcherItem(id: "editor.notes", title: "Notes", appName: "Editor", pid: 10, windowOwnerPID: 10,
                                  windowID: 12, isOnScreen: true, isAppHidden: false, isMinimized: false,
                                  isFullscreen: false, isOnHiddenSpace: false, frame: .zero)
        let untitled = SwitcherItem(id: "editor.app", title: "Editor", appName: "Editor", pid: 10, windowOwnerPID: 10,
                                    windowID: 13, isOnScreen: true, isAppHidden: false, isMinimized: false,
                                    isFullscreen: false, isOnHiddenSpace: false, frame: .zero)
        let windows = CommandBarCatalog.windowEntries(
            [window, untitled], bar: bar, frontmost: { front.pid },
            later: { _, work in front.pending.append(work) },
            activate: { front.activated.append((pid: $0, window: $1, app: $2, source: $3)) })
        suite.expect(windows.map(\.id) == ["window.editor.notes"] && windows.allSatisfy { !$0.countsUsage },
                     "windowEntries skips a window named only for its app and excludes recycled window IDs from learning")
        windows.first?.run(nil)
        suite.expect(front.activated.isEmpty && front.pending.count == 1,
                     "a window row waits a beat for the bar to leave before it activates")
        front.pid = 200
        front.pending.forEach { $0() }
        suite.expect(front.activated.map(\.pid) == [10] && front.activated.map(\.window) == [12]
                     && front.activated.map(\.source) == [100],
                     "Command Bar captures its handoff source before the activation beat")
    }
}
