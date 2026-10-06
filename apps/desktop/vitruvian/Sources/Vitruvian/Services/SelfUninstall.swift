// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import AppKit
import ServiceManagement
import VitruvianCore
import VitruvianDesign

/// Clears the app's own footprint on the system, for a clean uninstall.
///
/// Security note: every operation here is scoped to THIS app and nothing else.
/// The bundle id is a constant identifier (never user input), so the `tccutil`
/// call cannot be steered elsewhere; the login item and sudoers rule are the
/// app's own; the preference and saved-state paths are built from the app's own
/// bundle id; and the only thing deleted is the app's own bundle, which is moved
/// to the Trash (reversible). Nothing leaves the machine.
package enum SelfUninstall {
    private static var bundleID: String { Bundle.main.bundleIdentifier ?? "com.vitruviansoftware.vitruvian" }

    /// What clearing and uninstalling do, step by step, and the queues they
    /// run on. `system` is the real teardown; tests pass doubles that log
    /// what ran.
    package struct Steps: Sendable {
        package var suspendInputInterceptors: @MainActor @Sendable () -> Bool
        package var restoreSleepBeforeRemoval: @Sendable () -> Bool
        package var detachFanControl: @Sendable () -> Bool
        package var detachLoginItem: @Sendable () -> Void
        /// Removes the closed-lid sudoers rule if present, which may ask for
        /// a password, then reports whether it is gone.
        package var removeSudoersRule: @Sendable (_ then: @escaping @Sendable (Bool) -> Void) -> Void
        package var resetTCC: @Sendable () -> Bool
        package var removePreferences: @Sendable () -> Void
        package var trashOwnBundleAndQuit: @MainActor @Sendable () -> Void
        package var fanHelperIsRegistered: @Sendable () -> Bool
        package var restoreFanRegistration: @Sendable () -> Bool
        package var refreshPermissions: @MainActor @Sendable () -> Void
        package var resumeKeepAwake: @MainActor @Sendable () -> Void
        package var resumeFeatures: @MainActor @Sendable () -> Void
        package var resumeBrightness: @MainActor @Sendable () -> Void
        package var main: @Sendable (@escaping @MainActor @Sendable () -> Void) -> Void
        package var background: @Sendable (@escaping @Sendable () -> Void) -> Void

        package init(suspendInputInterceptors: @escaping @MainActor @Sendable () -> Bool,
                     restoreSleepBeforeRemoval: @escaping @Sendable () -> Bool,
                     detachFanControl: @escaping @Sendable () -> Bool,
                     detachLoginItem: @escaping @Sendable () -> Void,
                     removeSudoersRule: @escaping @Sendable (@escaping @Sendable (Bool) -> Void) -> Void,
                     resetTCC: @escaping @Sendable () -> Bool,
                     removePreferences: @escaping @Sendable () -> Void,
                     trashOwnBundleAndQuit: @escaping @MainActor @Sendable () -> Void,
                     fanHelperIsRegistered: @escaping @Sendable () -> Bool,
                     restoreFanRegistration: @escaping @Sendable () -> Bool,
                     refreshPermissions: @escaping @MainActor @Sendable () -> Void,
                     resumeKeepAwake: @escaping @MainActor @Sendable () -> Void,
                     resumeFeatures: @escaping @MainActor @Sendable () -> Void,
                     resumeBrightness: @escaping @MainActor @Sendable () -> Void,
                     main: @escaping @Sendable (@escaping @MainActor @Sendable () -> Void) -> Void,
                     background: @escaping @Sendable (@escaping @Sendable () -> Void) -> Void) {
            self.suspendInputInterceptors = suspendInputInterceptors
            self.restoreSleepBeforeRemoval = restoreSleepBeforeRemoval
            self.detachFanControl = detachFanControl
            self.detachLoginItem = detachLoginItem
            self.removeSudoersRule = removeSudoersRule
            self.resetTCC = resetTCC
            self.removePreferences = removePreferences
            self.trashOwnBundleAndQuit = trashOwnBundleAndQuit
            self.fanHelperIsRegistered = fanHelperIsRegistered
            self.restoreFanRegistration = restoreFanRegistration
            self.refreshPermissions = refreshPermissions
            self.resumeKeepAwake = resumeKeepAwake
            self.resumeFeatures = resumeFeatures
            self.resumeBrightness = resumeBrightness
            self.main = main
            self.background = background
        }

        package static let system = Steps.wired(to: .live)

        /// The real steps over the system calls they make. `system` is them
        /// over the Mac's; tests pass recorders to check that the input
        /// teardown, the sleep restore and the fan detach are the real ones.
        package static func wired(to calls: SystemCalls) -> Steps {
            Steps(
                suspendInputInterceptors: { SelfUninstall.suspendInputInterceptors(calls) },
                restoreSleepBeforeRemoval: { SelfUninstall.restoreSleepBeforeRemoval(calls) },
                detachFanControl: { calls.detachFanHelper() },
                detachLoginItem: { SelfUninstall.detachLoginItem() },
                removeSudoersRule: { SelfUninstall.removeSudoersRuleIfPresent(then: $0) },
                resetTCC: { SelfUninstall.resetTCC() },
                removePreferences: { SelfUninstall.removePreferences() },
                trashOwnBundleAndQuit: { SelfUninstall.trashOwnBundleAndQuit() },
                fanHelperIsRegistered: { FanControlService.hasRegisteredHelperForRemoval },
                restoreFanRegistration: { FanControlService.restoreRegistrationAfterFailedRemoval() },
                refreshPermissions: { Permissions.shared.refresh() },
                resumeKeepAwake: { KeepAwakeManager.shared.resumeAfterSystemTeardown() },
                resumeFeatures: { FeatureRuntime.shared.sync(AppFeature.allCases) },
                resumeBrightness: { calls.resumeBrightnessKeys() },
                main: { work in DispatchQueue.main.async { work() } },
                background: { work in DispatchQueue.global(qos: .userInitiated).async { work() } })
        }
    }

    /// The Accessibility-backed input interceptors the teardown stops, in the
    /// order it stops them. Cleaning Mode goes first: deactivating it re-syncs
    /// the services it paused back to their preferences, so after the others
    /// it would re-arm the very taps this teardown just stopped.
    package enum InputInterceptor: CaseIterable, Sendable {
        case cleaningMode, scrollInverter, focusFollowsMouse, smoothScroll, mouseAcceleration
        case mouseNavigation, mouseButtonShortcuts, windowMaximizer, windowLayout, pointerDisplay
        case appSwitcher, dockPreview, brightnessKeys, autoQuit, finderCutPaste, finderRename
        case keyboardDebounce, mouseClickDebounce, superKey, dockClick, middleClick, quitProtection
        case pastePlain, snippetLibrary, textSnippets, screenCapture, recentCaptures, quickLauncher
        case screenText, cameraPreview, radialMenu, scratchpad, commandBar, preciseVolumeRoller, micMute
    }

    /// What the real steps ask of the Mac: the input teardown, the brightness
    /// keys, the closed-lid flag, `pmset`, the two ways sleep goes back and
    /// the fan helper. `live` is the Mac.
    package struct SystemCalls: Sendable {
        /// Stops one interceptor; false only when it cannot be let go yet.
        package var suspendInterceptor: @MainActor @Sendable (InputInterceptor) -> Bool
        package var resumeBrightnessKeys: @MainActor @Sendable () -> Void
        /// Whether a closed-lid session left sleep for the app to restore.
        package var sleepFlagged: @Sendable () -> Bool
        /// `pmset -g`.
        package var probeSleep: @Sendable () -> (status: Int32, output: String)
        /// Through the password-free rule, if it is installed.
        package var restoreSleepWithoutPassword: @Sendable () -> Bool
        /// Through the password dialog, which asks with `prompt`.
        package var restoreSleepAsAdministrator: @Sendable (_ prompt: String) -> Bool
        package var detachFanHelper: @Sendable () -> Bool

        package init(suspendInterceptor: @escaping @MainActor @Sendable (InputInterceptor) -> Bool,
                     resumeBrightnessKeys: @escaping @MainActor @Sendable () -> Void,
                     sleepFlagged: @escaping @Sendable () -> Bool,
                     probeSleep: @escaping @Sendable () -> (status: Int32, output: String),
                     restoreSleepWithoutPassword: @escaping @Sendable () -> Bool,
                     restoreSleepAsAdministrator: @escaping @Sendable (_ prompt: String) -> Bool,
                     detachFanHelper: @escaping @Sendable () -> Bool) {
            self.suspendInterceptor = suspendInterceptor
            self.resumeBrightnessKeys = resumeBrightnessKeys
            self.sleepFlagged = sleepFlagged
            self.probeSleep = probeSleep
            self.restoreSleepWithoutPassword = restoreSleepWithoutPassword
            self.restoreSleepAsAdministrator = restoreSleepAsAdministrator
            self.detachFanHelper = detachFanHelper
        }

        package static let live = SystemCalls(
            suspendInterceptor: { SelfUninstall.suspend($0) },
            resumeBrightnessKeys: { BrightnessService.shared.resumeInputTaps() },
            sleepFlagged: { UserDefaults.standard.bool(forKey: DefaultsKey.sleepDisabledFlag) },
            probeSleep: { Shell.run("/usr/bin/pmset", ["-g"]) },
            restoreSleepWithoutPassword: { Sudoers.pmsetDisableSleep(false) },
            restoreSleepAsAdministrator: { AdminShell.runSync("pmset disablesleep 0", prompt: $0) },
            detachFanHelper: { FanControlService.restoreAndUnregisterForRemoval() })
    }

    /// Resets every TCC permission the app holds, drops the login item and the
    /// optional closed-lid sudoers rule, and leaves the app in place. Calls back
    /// on the main queue with whether the rule and permissions were removed.
    /// Used by "Clear all permissions".
    package static func clearPermissions(steps: Steps = .system,
                                         completion: @escaping @MainActor @Sendable (Bool) -> Void) {
        @Sendable func stop(sleepRestored: Bool = false) {
            steps.main {
                if sleepRestored { steps.resumeKeepAwake() }
                steps.refreshPermissions()
                steps.resumeFeatures()
                steps.resumeBrightness()
                completion(false)
            }
        }
        // Stop every input interceptor FIRST (on the main thread), then revoke.
        // Revoking Accessibility while a tap is live makes the tap callback hang
        // on an AX call and freezes the whole machine's input — see the note on
        // `suspendInputInterceptors`.
        steps.main {
            // Mouse acceleration keeps its recovery journal and guard here.
            // Only a full uninstall deletes that journal, so only it must wait
            // for a disconnected device to be restored.
            _ = steps.suspendInputInterceptors()
            steps.background {
                guard steps.restoreSleepBeforeRemoval() else { stop(); return }
                guard detachFromSystem(steps) else {
                    stop(sleepRestored: true)
                    return
                }
                steps.removeSudoersRule { ruleRemoved in    // may show one admin prompt
                    let reset = steps.resetTCC()
                    steps.main {
                        // The published permissions still say granted. Read the
                        // reset state now, or a grant made before the next poll
                        // looks unchanged and the suspended taps never resume.
                        steps.refreshPermissions()
                        // Sleep was restored directly, so the closed-lid session
                        // state is stale whether or not the reset finished.
                        steps.resumeKeepAwake()
                        if !ruleRemoved || !reset {
                            steps.resumeFeatures()
                        }
                        steps.resumeBrightness()
                        completion(ruleRemoved && reset)
                    }
                }
            }
        }
    }

    /// Clears permissions, removes preferences and saved state, sends the app
    /// bundle to the Trash and quits. Used by "Uninstall Vitruvian completely".
    /// A failure passes the message explaining what stopped it.
    package static func uninstallCompletely(steps: Steps = .system,
                                            onFailure: @escaping @MainActor @Sendable (String) -> Void) {
        // A failed reset may have changed some grants. Recheck them before
        // rearming services in the app that remains installed.
        @Sendable func stop(_ body: String, sleepRestored: Bool = false) {
            steps.main {
                if sleepRestored { steps.resumeKeepAwake() }
                steps.refreshPermissions()
                steps.resumeFeatures()
                steps.resumeBrightness()
                onFailure(body)
            }
        }
        steps.main {
            guard steps.suspendInputInterceptors() else {
                stop(L10n.shared.s.advancedUninstallFailedBody)
                return
            }
            steps.background {
                // Sleep may still be restored through the rule, and a refused
                // rule removal must stop before anything else is removed.
                guard steps.restoreSleepBeforeRemoval() else {
                    stop(L10n.shared.s.advancedUninstallFailedBody)
                    return
                }
                steps.removeSudoersRule { ruleRemoved in
                    guard ruleRemoved else {
                        stop(L10n.shared.s.advancedClearFailed, sleepRestored: true)
                        return
                    }
                    // The helper must be safely removed before permissions go;
                    // a failure here keeps the app's existing grants intact.
                    let fanHelperWasRegistered = steps.fanHelperIsRegistered()
                    guard steps.detachFanControl() else {
                        stop(L10n.shared.s.advancedUninstallFailedBody, sleepRestored: true)
                        return
                    }
                    guard steps.resetTCC() else {
                        // The app stays installed, so restore a helper that was
                        // registered before the attempted uninstall.
                        let fanReady = !fanHelperWasRegistered || steps.restoreFanRegistration()
                        if fanReady {
                            stop(L10n.shared.s.advancedClearFailed, sleepRestored: true)
                        } else {
                            let warning = FeatureStrings.fanControl(L10n.shared.language).helperUnavailable
                            stop("\(L10n.shared.s.advancedClearFailed)\n\(warning)", sleepRestored: true)
                        }
                        return
                    }
                    // Do not clear the launch choice while a failed reset
                    // could still leave this app installed.
                    steps.detachLoginItem()
                    steps.removePreferences()
                    steps.main { steps.trashOwnBundleAndQuit() }
                }
            }
        }
    }

    // MARK: - Steps (each scoped to this app only)

    /// Tears down every Accessibility-backed input interceptor, all of them,
    /// in `InputInterceptor` order. MUST run on the main thread and BEFORE
    /// permissions are reset: otherwise revoking Accessibility while an event
    /// tap is still live makes the tap's callback block on an AX call, which
    /// stalls the OS input queue and freezes the keyboard and clicks (only
    /// the mouse cursor keeps moving). False when one could not be let go.
    // Both callers run it from the main queue.
    @MainActor
    private static func suspendInputInterceptors(_ calls: SystemCalls) -> Bool {
        var released = true
        for interceptor in InputInterceptor.allCases {
            if !calls.suspendInterceptor(interceptor) { released = false }
        }
        return released
    }

    /// Stops one interceptor, at once. Each `stop`/`suspend`/`deactivate` is
    /// idempotent, so calling it when a service is already off is a no-op.
    @MainActor
    private static func suspend(_ interceptor: InputInterceptor) -> Bool {
        switch interceptor {
        case .cleaningMode: CleaningModeManager.shared.deactivateForSystemTeardown()
        case .scrollInverter: ScrollInverter.shared.suspend()
        case .focusFollowsMouse: FocusFollowsMouseService.shared.stop()
        case .smoothScroll: SmoothScrollService.shared.suspend()
        // Its machine-local recovery journal is deleted by a full uninstall,
        // so the uninstall cannot continue until every HID value is restored.
        case .mouseAcceleration: return MouseAccelerationService.shared.stop()
        case .mouseNavigation: MouseNavigationService.shared.suspend()
        case .mouseButtonShortcuts: MouseButtonShortcutService.shared.suspend()
        case .windowMaximizer: WindowMaximizer.shared.stop()
        case .windowLayout: WindowLayoutService.shared.suspend()
        case .pointerDisplay: PointerDisplayService.shared.suspend()
        case .appSwitcher: AppSwitcher.shared.suspend()
        case .dockPreview: DockPreviewService.shared.stop()
        case .brightnessKeys: BrightnessService.shared.suspendInputTaps()
        case .autoQuit: AutoQuitService.shared.suspend()
        case .finderCutPaste: FinderCutPaste.shared.suspend()
        case .finderRename: FinderRenameService.shared.suspend()
        case .keyboardDebounce: KeyboardDebounceService.shared.suspend()
        case .mouseClickDebounce: MouseClickDebounceService.shared.suspend()
        // Also takes the Super key mapping back out, synchronously, so the
        // key is never left remapped behind a tap that is about to die.
        case .superKey: SuperKeyService.shared.suspend()
        case .dockClick: DockClickService.shared.suspend()
        case .middleClick: MiddleClickService.shared.suspend()
        case .quitProtection: QuitProtectionService.shared.suspend()
        case .pastePlain: PastePlainService.shared.suspend()
        case .snippetLibrary: SnippetLibraryService.shared.suspend()
        case .textSnippets: TextSnippetService.shared.suspend()
        case .screenCapture: ScreenCaptureService.shared.suspend()
        case .recentCaptures: RecentCaptureService.shared.suspend()
        case .quickLauncher: QuickLauncherService.shared.suspend()
        case .screenText: ScreenTextService.shared.suspend()
        case .cameraPreview: CameraPreviewService.shared.suspend()
        case .radialMenu: RadialMenuService.shared.suspend()
        case .scratchpad: ScratchpadService.shared.suspend()
        case .commandBar: CommandBarService.shared.suspend()
        case .preciseVolumeRoller: PreciseVolumeRollerService.shared.suspend()
        case .micMute:
            // Leaving the mic cut after the app is gone would strand the user
            // with a silent input and no indicator anywhere.
            MicMuteService.shared.unmuteForTeardown()
            MicMuteService.shared.suspend()
        }
        return true
    }

    @discardableResult
    private static func detachFromSystem(_ steps: Steps) -> Bool {
        guard steps.detachFanControl() else { return false }
        steps.detachLoginItem()
        return true
    }

    private static func detachLoginItem() {
        // Unregister the login item (scoped to our bundle id). The stored
        // intent goes with it, or the startup repair would quietly register
        // the item again after the user asked for a clean detach.
        UserDefaults.standard[Preferences.launchAtLoginWanted] = false
        try? SMAppService.mainApp.unregister()
    }

    /// Puts normal sleep back before the app goes.
    ///
    /// `KeepAwakeManager` is allowed to give up on a failed revert when the app
    /// is merely quitting, because "the next start repairs a revert that was
    /// missed". Removal is the one exit with no next start, and the flag that
    /// would trigger that repair is deleted with the rest of the preferences a
    /// moment later — so a reinstall does not fix it either, since recovery
    /// reads the flag before it reads the setting. This is the last chance
    /// anything has, which is why it may ask for the password the launch-time
    /// recovery would have asked for.
    private static func restoreSleepBeforeRemoval(_ calls: SystemCalls) -> Bool {
        restoreSleep(flagged: calls.sleepFlagged(),
                     probe: calls.probeSleep,
                     restoreWithoutPassword: calls.restoreSleepWithoutPassword,
                     restoreAsAdministrator: {
                         calls.restoreSleepAsAdministrator(L10n.shared.s.adminPromptRecover)
                     })
    }

    /// What `Vitruvian --uninstall` prints about sleep, or nil when no
    /// closed-lid session left it to restore. That path runs before the app
    /// has a password dialog, so only the password-free rule can put sleep
    /// back; a reading taken first, that answered and answered "on", counts as
    /// restored too. A probe that did not answer proves nothing. The script
    /// reads the setting back itself rather than trusting the line.
    package static func commandLineSleepReport(_ calls: SystemCalls) -> String? {
        guard calls.sleepFlagged() else { return nil }
        let probe = calls.probeSleep()
        let restored = calls.restoreSleepWithoutPassword()
            || (probe.status == 0
                && !SudoersSupport.sleepDisabled(inPmsetOutput: probe.output))
        return restored
            ? "UNINSTALL: normal sleep restored"
            : "UNINSTALL: sleep is still disabled"
    }

    /// `restoreSleepBeforeRemoval` with the system passed in: `flagged` is the
    /// closed-lid flag, `probe` reads `pmset -g`, and the two restores put
    /// sleep back through the password-free rule and through the password
    /// dialog. True only when sleep was never the app's to restore, or is
    /// known to be back.
    package static func restoreSleep(flagged: Bool,
                                     probe: () -> (status: Int32, output: String),
                                     restoreWithoutPassword: () -> Bool,
                                     restoreAsAdministrator: () -> Bool) -> Bool {
        guard flagged else { return true }
        // The flag can outlive the setting, so a stale one must not put a
        // password dialog in front of someone uninstalling. Only a reading that
        // answered, and answered "off", is allowed to skip the rest: a probe
        // that failed says nothing. Going on then costs a no-op call, and a
        // dialog only if that call fails too — the case where sleep really may
        // still be off with nothing else left to put it back.
        let reading = probe()
        if reading.status == 0, !SudoersSupport.sleepDisabled(inPmsetOutput: reading.output) {
            return true
        }
        if restoreWithoutPassword() { return true }
        guard restoreAsAdministrator() else { return false }
        let verification = probe()
        return verification.status == 0
            && !SudoersSupport.sleepDisabled(inPmsetOutput: verification.output)
    }

    private static func removeSudoersRuleIfPresent(then: @escaping (Bool) -> Void) {
        guard Sudoers.ruleFilesPresent || Sudoers.isConfigured() else { then(true); return }
        Sudoers.remove(completion: then)            // shows the admin password prompt
    }

    /// `tccutil reset All <bundle id>` clears Accessibility, Screen Recording,
    /// Full Disk Access, Automation and the rest, for this app only. The bundle
    /// id is a constant, so there is nothing to inject.
    @discardableResult
    private static func resetTCC() -> Bool {
        Shell.run("/usr/bin/tccutil", ["reset", "All", bundleID]).status == 0
    }

    private static func removePreferences() {
        let id = bundleID
        UserDefaults.standard.removePersistentDomain(forName: id)
        for path in ownedPaths(home: NSHomeDirectory(), bundleID: id) {
            try? FileManager.default.removeItem(atPath: path)
        }
    }

    /// The files and folders of the app's own under a home folder, which a
    /// full uninstall removes once its preferences domain is gone.
    /// `Tools/uninstall.sh` removes the same ones.
    package static func ownedPaths(home: String, bundleID id: String) -> [String] {
        [
            "\(home)/Library/Preferences/\(id).plist",
            "\(home)/Library/Saved Application State/\(id).savedState",
            // Clipboard images and any other app-owned data live here.
            "\(home)/Library/Application Support/\(id)",
            "\(home)/Library/Caches/\(id)",
            // URLSession writes these on our behalf whenever the app talks to the
            // network, so they exist without the app ever choosing the path.
            "\(home)/Library/HTTPStorages/\(id)",
            "\(home)/Library/HTTPStorages/\(id).binarycookies",
        ]
    }

    /// Moves the app's own bundle to the Trash after it quits, then quits. The
    /// path is the running app's own location, checked to be an `.app`, so this
    /// can only ever remove this app. A detached helper does the move so the
    /// bundle is not mutated while it is running.
    @MainActor
    private static func trashOwnBundleAndQuit() {
        let app = Bundle.main.bundlePath
        guard app.hasSuffix(".app"), app != "/" else { NSApp.terminate(nil); return }
        let pid = ProcessInfo.processInfo.processIdentifier
        let script = """
        #!/bin/sh
        APP="$1"; PID="$2"
        while kill -0 "$PID" 2>/dev/null; do sleep 0.3; done
        TRASH="$HOME/.Trash"
        /bin/mkdir -p "$TRASH" 2>/dev/null || true
        BASE="$(basename "$APP")"
        DEST="$TRASH/$BASE"
        n=2
        while [ -e "$DEST" ]; do DEST="$TRASH/${BASE%.app} $n.app"; n=$((n+1)); done
        # Reversible move to the Trash. If a direct move fails, ask Finder to do
        # the same Trash operation so it can present the standard admin prompt.
        if ! /bin/mv "$APP" "$DEST" 2>/dev/null; then
            /usr/bin/osascript - "$APP" <<'APPLESCRIPT'
        on run argv
            tell application "Finder" to delete POSIX file (item 1 of argv)
        end run
        APPLESCRIPT
        fi
        if [ -d "$APP" ]; then /usr/bin/open "$APP" 2>/dev/null; fi
        /bin/rm -f "$0"
        """
        let scriptURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("vitruvian-uninstall-\(pid)-\(UUID().uuidString).sh")
        do {
            try script.write(to: scriptURL, atomically: true, encoding: .utf8)
            // Its own session: the script's first act is to wait for this app
            // to exit, so a child left in our session would be torn down with
            // us before it ever gets to move the bundle.
            try DetachedProcess.spawn("/bin/sh", [scriptURL.path, app, "\(pid)"])
            NSApp.terminate(nil)
        } catch {
            try? FileManager.default.removeItem(at: scriptURL)
        }
    }
}
