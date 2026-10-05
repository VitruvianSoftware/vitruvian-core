// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import CoreGraphics
import Foundation
import VitruvianCore
import VitruvianDesign
import VitruvianServices
import VitruvianUI

enum DockAutohideHoldTests {
    /// The preview service's side of a held session, recorded. No event tap
    /// is installed and the workspace notifications go to a private center.
    final class Preview {
        var events: [String] = []
        var acceptsInputTap = true
        var inputTapActive = false
        var stoppedWhileHolding = false
        var mayActivate = true
        var isRunning = true
        var captures = 0
        /// Whether each restore handed out would still run, asked later.
        var restores: [@MainActor @Sendable () -> Bool] = []
        let center = NotificationCenter()
        var session: DockHoldSession<Int>!

        init(_ hold: DockAutohideHold) {
            session = DockHoldSession(hold: hold, host: .init(
                startInputTap: { [unowned self] in
                    inputTapActive = acceptsInputTap
                    return acceptsInputTap
                },
                stopInputTap: { [unowned self] in
                    stoppedWhileHolding = stoppedWhileHolding || session.hold.isHolding
                    inputTapActive = false
                },
                captureFrames: { [unowned self] in
                    captures += 1
                    return { [unowned self] _, isCurrent in
                        events.append("capture")
                        return { [unowned self] in
                            events.append("restore")
                            restores.append(isCurrent)
                        }
                    }
                },
                isRunning: { [unowned self] in isRunning },
                dropQueuedPointer: { [unowned self] in events.append("drop") },
                endSession: { [unowned self] in
                    events.append("end")
                    session.release()
                },
                mayActivate: { [unowned self] _ in mayActivate },
                activate: { [unowned self] _ in events.append("activate") },
                notificationCenter: center))
        }

        /// Whether the session's key tap and workspace observers are live.
        func watches() -> Bool {
            let before = events.count
            center.post(name: DockHoldSession<Int>.endingNotifications[0], object: nil)
            let watched = events.count > before
            return watched
        }
    }

    static func run(_ suite: TestSuite) {
        let name = "com.vitruviansoftware.vitruvian.tests.dock-hold.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: name)!
        defer { defaults.removePersistentDomain(forName: name) }
        let marker = DefaultsKey.dockPreviewRestoreAutohide
        var autohide: Bool? = true
        var writes: [Bool] = []
        var acceptsWrites = true
        let makeHold = {
            DockAutohideHold(defaults: defaults, readAutohide: { autohide }, writeAutohide: {
                writes.append($0)
                guard acceptsWrites else { return false }
                autohide = $0
                return true
            })
        }
        let hold = makeHold()
        suite.expect(writes.isEmpty, "starting without a recovery marker never changes the Dock")
        suite.expect(hold.begin() && autohide == false && hold.isHolding,
                     "an auto-hidden Dock stays visible for the preview session")
        suite.expect(defaults.bool(forKey: marker), "the original auto-hide is recoverable while held")
        suite.expect(hold.begin() && writes == [false], "switching preview apps reuses the hold")
        hold.end()
        hold.end()
        suite.expect(autohide == true && !hold.isHolding && writes == [false, true],
                     "ending or disabling a session restores auto-hide exactly once")
        suite.expect(defaults.object(forKey: marker) == nil, "successful restoration clears recovery")

        writes = []
        autohide = false
        suite.expect(!hold.begin(), "a Dock already permanently visible is never changed")
        autohide = nil
        suite.expect(!hold.begin() && writes.isEmpty, "a missing private API leaves normal preview available")

        autohide = true
        acceptsWrites = false
        suite.expect(!hold.begin() && !hold.isHolding, "a rejected hold cannot masquerade as active")
        suite.expect(defaults.bool(forKey: marker), "failed restoration remains recoverable")
        acceptsWrites = true
        let recovered = makeHold()
        suite.expect(autohide == true && !recovered.isHolding && !defaults.bool(forKey: marker),
                     "the next startup retries an interrupted restoration even with the toggle off")

        autohide = true
        _ = hold.begin()
        acceptsWrites = false
        hold.end()
        suite.expect(!hold.isHolding && autohide == false && defaults.bool(forKey: marker),
                     "a failed release retains recovery instead of forgetting the system change")
        suite.expect(!hold.begin(), "a pending restoration cannot be overwritten by another session")
        acceptsWrites = true
        hold.end()
        suite.expect(autohide == true && !defaults.bool(forKey: marker),
                     "a subsequent release can finish restoring auto-hide")

        autohide = true
        _ = hold.begin()
        autohide = true // User re-enables auto-hide while the preview is open.
        hold.end()
        suite.expect(autohide == true && !hold.isHolding, "restoration preserves re-enabled auto-hide")

        autohide = true
        _ = hold.begin()
        let restarted = makeHold() // Simulate interruption without calling end().
        suite.expect(autohide == true && !restarted.isHolding && !defaults.bool(forKey: marker),
                     "a new process restores the pending preference after an interrupted preview")
        autohide = true
        let interrupted = makeHold()
        _ = interrupted.begin()
        writes = []
        DockAutohideHold.recoverIfNeeded(defaults: defaults, writeAutohide: {
            writes.append($0)
            autohide = $0
            return true
        })
        suite.expect(autohide == true && writes == [true] && !defaults.bool(forKey: marker),
                     "launch restores an interrupted hold without any Dock preview service")
        DockAutohideHold.recoverIfNeeded(defaults: defaults, writeAutohide: {
            writes.append($0)
            return true
        })
        suite.expect(writes == [true], "launch recovery without a marker never changes the Dock")

        let preview = Preview(makeHold())
        let session = preview.session!
        autohide = true
        preview.acceptsInputTap = false
        let beforeRejectedTap = writes.count
        session.begin()
        suite.expect(autohide == true && writes.count == beforeRejectedTap && !preview.watches(),
                     "without input protection the normal preview never changes auto-hide")
        preview.acceptsInputTap = true
        autohide = false
        session.begin()
        suite.expect(!preview.inputTapActive && !preview.watches(),
                     "a Dock already visible leaves no input tap or observers")
        autohide = true
        let captured = preview.captures
        session.begin()
        session.begin()
        suite.expect(preview.inputTapActive && preview.captures == captured + 1,
                     "switching Dock icons keeps the hold and the window geometry from before it")
        preview.events = []
        session.handleInput(type: .mouseMoved)
        suite.expect(autohide == false && preview.events.isEmpty,
                     "moving through previews keeps the Dock held")
        session.handleInput(type: .keyDown)
        suite.expect(preview.events == ["drop", "end"],
                     "a key drops the queued pointer move before it ends the preview")
        suite.expect(!preview.stoppedWhileHolding,
                     "auto-hide is restored before the input tap can release its pending key")
        suite.expect(autohide == true && !preview.inputTapActive && !preview.watches(),
                     "keyboard input restores the Dock and stops watching")
        preview.events = []
        session.commit(1)
        suite.expect(preview.events == ["end", "activate"], "ending a hold discards its saved window geometry")
        autohide?.toggle() // Native shortcut chooses a permanently visible Dock.
        session.release() // A later close or preference sync.
        suite.expect(autohide == false && !defaults.bool(forKey: marker),
                     "later session cleanup cannot undo the user's shortcut choice")
        autohide?.toggle()
        autohide?.toggle()
        session.release()
        suite.expect(autohide == false,
                     "further Dock changes after keyboard dismissal remain untouched")
        preview.events = []
        session.handleInput(type: .keyDown)
        suite.expect(preview.events.isEmpty,
                     "input outside a hold does not dismiss the normal preview")
        for event in [CGEventType.tapDisabledByTimeout, .tapDisabledByUserInput] {
            autohide = true
            session.begin()
            session.handleInput(type: event)
            suite.expect(autohide == true && !preview.inputTapActive,
                         "losing input protection immediately releases the hold")
        }
        for name in DockHoldSession<Int>.endingNotifications {
            autohide = true
            session.begin()
            preview.events = []
            preview.center.post(name: name, object: nil)
            preview.center.post(name: name, object: nil)
            suite.expect(autohide == true && !preview.inputTapActive && preview.events == ["end"],
                         "leaving the workspace releases both the Dock and input protection, once")
        }
        autohide = true
        acceptsWrites = false
        session.begin()
        suite.expect(!preview.inputTapActive && !preview.watches(),
                     "a rejected system write removes input protection immediately")
        acceptsWrites = true
        session.release()

        autohide = true
        session.begin()
        preview.events = []
        session.commit(1)
        suite.expect(preview.events == ["capture", "end", "activate", "restore"],
                     "selection captures geometry before release and repairs only after activating the window")
        suite.expect(preview.restores.last?() == true, "the repair stays current after the preview closes")
        autohide = true
        session.begin()
        suite.expect(preview.restores.last?() == false, "a newer hold makes an older repair stale")
        preview.events = []
        preview.mayActivate = false
        session.commit(1)
        suite.expect(preview.events == ["capture", "end"],
                     "a selection rejected by the Space policy never restores a window")
        preview.mayActivate = true
        preview.events = []
        session.commit(1)
        suite.expect(preview.events == ["end", "activate"],
                     "normal previews never schedule a frame restoration")
        autohide = true
        session.begin()
        session.commit(1)
        preview.isRunning = false
        suite.expect(preview.restores.last?() == false, "a stopped Dock preview repairs nothing")

        suite.expect(Defaults.registeredDefaults[DefaultsKey.dockPreviewKeepDockVisible] as? Bool == false,
                     "the experiment is disabled by default")
        suite.expect(SettingsBackupSupport.exportKeys().contains(DefaultsKey.dockPreviewKeepDockVisible)
                     && !SettingsBackupSupport.exportKeys().contains(marker),
                     "backups carry the toggle but never another session's recovery state")
    }
}
