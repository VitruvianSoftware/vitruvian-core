// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Foundation
import VitruvianCore
import VitruvianDesign
import VitruvianServices
import VitruvianUI

/// Drives the real `KeepAwakeManager` over a machine the test runs by hand:
/// its queues, the `pmset` override and its rule, the power manager, the lid
/// and the panel. Nothing reaches the Mac running the tests.
enum KeepAwakeLidSleepContract {
    /// A value closures can share with the test.
    nonisolated final class Box<Value>: @unchecked Sendable {
        var value: Value
        init(_ value: Value) { self.value = value }
    }

    /// The machine's state and every queue, all run on the main thread.
    nonisolated final class Machine: @unchecked Sendable {
        // `pmset` and the sudoers rule.
        /// SleepDisabled, as `pmset -g` reports it.
        var disabled = false
        /// Whether `sudo -n` gets through.
        var configured = true
        /// Passwordless writes still to refuse while the rule otherwise works.
        var refusals = 0
        /// Every passwordless write asked for, the rule's probes included.
        var writes: [Bool] = []
        var reportStatus: Int32 = 0
        /// Nil reports `disabled`.
        var reportOutput: String?
        var installs: [@Sendable (Bool) -> Void] = []
        var restores: [@Sendable (Bool) -> Void] = []
        var commands: [String] = []
        /// Restore prompts opened.
        var prompts = 0

        // The queues.
        var lane: [@Sendable () -> Void] = []
        var background: [@Sendable () -> Void] = []
        var main: [@MainActor @Sendable () -> Void] = []
        var later: [@MainActor @Sendable () -> Void] = []
        var timers: [Timer] = []

        // The power manager.
        var lid: Bool? = true
        var policy: Bool? = true
        var assertions: [[String: Any]]? = []
        /// Whether there is a power manager to ask.
        var available = true
        /// What each sleep request answers; the last one repeats.
        var results: [Int32] = [0]
        var sleeps = 0
        /// Read at each sleep request, into `sleepChecks`.
        var sleepCheck: (@MainActor () -> Bool)?
        var sleepChecks: [Bool] = []
        var waits = 0
        var onWait: (@MainActor () -> Void)?
        var held: Set<UInt32> = []
        private var nextAssertion: UInt32 = 1

        // The screen lock, the lid watch and the panel.
        var lockChanged: (@MainActor @Sendable (Bool) -> Void)?
        /// The login session's state when lock monitoring starts.
        var sessionInfo: [String: Any]?
        var lidChanged: (@MainActor @Sendable () -> Void)?
        var lidWatches = 0
        var lidWatchesEnded = 0
        var reading: Double?
        var writeSucceeds = true
        var written: [Double] = []

        var transport: SleepOverride.Transport {
            SleepOverride.Transport(
                async: { [self] work in lane.append(work) },
                sync: { [self] body in
                    runLane()
                    return body()
                },
                report: { [self] in report() },
                write: { [self] on in
                    writes.append(on)
                    guard configured else { return false }
                    if refusals > 0 {
                        refusals -= 1
                        return false
                    }
                    disabled = on
                    return true
                },
                authorize: { [self] command, _, completion in
                    commands.append(command)
                    if command == Sudoers.installCommand {
                        installs.append(completion)
                    } else {
                        prompts += 1
                        restores.append(completion)
                    }
                },
                main: { [self] work in main.append(work) })
        }

        func report() -> (status: Int32, output: String) {
            (reportStatus, reportOutput ?? "SleepDisabled \(disabled ? 1 : 0)")
        }

        @MainActor func system(defaults: UserDefaults) -> KeepAwakeManager.System {
            KeepAwakeManager.System(
                defaults: defaults,
                notificationCenter: NotificationCenter(),
                sleep: SleepOverride(transport: transport),
                pmsetReport: { [self] in report() },
                background: { [self] _, work in background.append(work) },
                main: { [self] work in main.append(work) },
                after: { [self] _, work in later.append(work) },
                wait: { [self] _ in
                    waits += 1
                    onWait?()
                },
                schedule: { [self] in timers.append($0) },
                assert: { [self] _, _ in
                    let id = nextAssertion
                    nextAssertion += 1
                    held.insert(id)
                    return id
                },
                releaseAssertion: { [self] in _ = held.remove($0) },
                battery: { nil },
                watchLock: { [self] changed in
                    lockChanged = changed
                    return { [self] in lockChanged = nil }
                },
                session: { [self] in sessionInfo },
                lidClosed: { [self] in lid },
                clamshellCausesSleep: { [self] in policy },
                powerAssertions: { [self] in assertions },
                sleepSystem: { [self] in
                    guard available else { return nil }
                    sleeps += 1
                    if let sleepCheck { sleepChecks.append(sleepCheck()) }
                    return results.count > 1 ? results.removeFirst() : results[0]
                },
                watchLid: { [self] changed in
                    lidWatches += 1
                    lidChanged = changed
                    return { [self] in
                        lidWatchesEnded += 1
                        lidChanged = nil
                    }
                },
                panelBrightness: { [self] in reading },
                setPanelBrightness: { [self] value in
                    guard writeSucceeds else { return false }
                    written.append(value)
                    reading = value
                    return true
                })
        }

        func runLane() {
            while !lane.isEmpty { lane.removeFirst()() }
        }

        func runBackground() {
            while !background.isEmpty { background.removeFirst()() }
        }

        @MainActor func runMain() {
            while !main.isEmpty { main.removeFirst()() }
        }

        /// Runs every queue until all of them are idle.
        @MainActor func drain() {
            for _ in 0..<50 {
                if lane.isEmpty, background.isEmpty, main.isEmpty { return }
                runBackground()
                runLane()
                runMain()
            }
        }

        /// Runs the delayed work due now; what it schedules waits for the next call.
        @MainActor func advance() {
            let due = later
            later.removeAll()
            due.forEach { $0() }
        }

        /// Answers every open restore prompt.
        @MainActor func answer(_ ok: Bool) {
            if ok { disabled = false }
            let waiting = restores
            restores.removeAll()
            waiting.forEach { $0(ok) }
        }

        /// Answers the oldest rule install; an approved one installs a rule
        /// that works unless `works` says otherwise.
        @MainActor func answerInstall(_ ok: Bool, works: Bool? = nil) {
            if ok { configured = works ?? true }
            installs.removeFirst()(ok)
        }

        /// The power manager's general interest, as the lid opens or closes.
        @MainActor func lidEvent() {
            if let lidChanged { main.append(lidChanged) }
            drain()
        }
    }

    /// A manager over its machine and a private settings suite.
    struct Rig {
        let manager: KeepAwakeManager
        let machine: Machine
        let defaults: UserDefaults

        /// The recovery marker for a sleep override this app set.
        var marker: Bool { defaults.bool(forKey: DefaultsKey.sleepDisabledFlag) }
        var savedBrightness: Double? {
            defaults.object(forKey: DefaultsKey.dimmedDisplaySavedBrightness) as? Double
        }
    }

    private static var suites: [String] = []

    /// A fresh manager with Keep Awake available and closed-lid mode preferred,
    /// after its launch-time rule probe. `prepare` runs before it starts.
    static func make(_ prepare: (Machine, UserDefaults) -> Void = { _, _ in }) -> Rig {
        let name = "vitru.tests.keep-awake.\(UUID().uuidString)"
        suites.append(name)
        let defaults = UserDefaults(suiteName: name)!
        defaults.set(true, forKey: AppFeature.keepAwake.availabilityKey)
        defaults.set(true, forKey: DefaultsKey.clamshellPreferred)
        let machine = Machine()
        prepare(machine, defaults)
        let manager = KeepAwakeManager(system: machine.system(defaults: defaults))
        machine.drain()
        machine.writes = []
        return Rig(manager: manager, machine: machine, defaults: defaults)
    }

    /// A running session whose closed-lid mode is on: sleep is off through
    /// the rule and the recovery marker is written.
    static func active(_ prepare: (Machine, UserDefaults) -> Void = { _, _ in }) -> Rig {
        let rig = make(prepare)
        rig.manager.activate(minutes: 0)
        rig.machine.drain()
        rig.machine.writes = []
        return rig
    }

    static func removeSuites() {
        for name in suites { UserDefaults().removePersistentDomain(forName: name) }
        suites.removeAll()
    }
}

enum KeepAwakeLidSleepTests {
    private typealias C = KeepAwakeLidSleepContract

    static func run(expect: (Bool, String) -> Void) {
        func allowed(_ policy: Bool?, _ assertions: [[String: Any]]?) -> Bool {
            KeepAwakeAutomationSupport.lidSleepIsAllowed(systemAllowsSleep: policy, assertions: assertions)
        }
        let connection: [String: Any] = ["AssertType": "PreventSystemSleep", "AssertLevel": 1,
                                          "ProcessingHotPlug": true]
        expect(!allowed(true, [connection]),
               "a live monitor transition overrides a stale allowed lid policy")
        expect(!allowed(false, []) && !allowed(nil, []) && !allowed(true, nil),
               "closed-display mode and unavailable system facts never authorize forced sleep")
        expect(allowed(true, []) && allowed(true, [["AssertType": "PreventUserIdleSystemSleep", "AssertLevel": 1]]),
               "media idle assertions do not defeat the closed-lid battery cutoff")
        for type in ["UserIsActive", "DisplayWake", "PreventSystemSleep"] {
            for key in ["AppliesOnLidClose", "ProcessingHotPlug"] {
                expect(!allowed(true, [["AssertType": type, "AssertLevel": 1, key: true]]),
                       "active lid protection is preserved for \(type)")
                expect(allowed(true, [["AssertType": type, "AssertLevel": 0, key: true]]),
                       "released lid protection does not keep a finished session awake")
                expect(allowed(true, [["AssertType": type, "AssertLevel": 1, key: false]]),
                       "an assertion that does not apply to the lid does not block lid sleep")
            }
        }
        expect(!allowed(true, [["ProcessingHotPlug": true]]),
               "incomplete marked protection is not mistaken for an inactive assertion")
        expect(allowed(true, [["AssertType": "PreventUserIdleSystemSleep", "AssertLevel": 1,
                               "AppliesOnLidClose": true]]),
               "lid flags on unrelated assertion types do not change the system's policy")

        // Ending a closed-lid session restores sleep, then asks for the
        // sleep a lid that shut during the session would have caused.
        for lid in [true, false, nil] as [Bool?] {
            for policy in [true, false, nil] as [Bool?] {
                let rig = C.active()
                rig.machine.lid = lid
                rig.machine.policy = policy
                rig.manager.deactivate(reason: .manual)
                rig.machine.drain()
                expect(rig.machine.sleeps == (lid == true && policy == true ? 1 : 0),
                       "only a closed lid with an affirmative current policy can request sleep")
                expect(rig.machine.later.isEmpty, "successful or inapplicable requests do not poll")
            }
        }
        let blocked = C.active()
        blocked.machine.assertions = [connection]
        blocked.manager.deactivate(reason: .manual)
        blocked.machine.drain()
        expect(blocked.machine.sleeps == 0, "the production request respects an in-progress monitor connection")
        blocked.machine.assertions = []
        blocked.manager.activate(minutes: 0)
        blocked.machine.drain()
        blocked.manager.deactivate(reason: .manual)
        blocked.machine.drain()
        expect(blocked.machine.sleeps == 1, "sleep is allowed again once the temporary protection is released")

        let retry = C.active()
        retry.machine.results = [1, 1, 0]
        retry.manager.deactivate(reason: .manual)
        retry.machine.drain()
        for _ in 0..<12 { retry.machine.advance() }
        expect(retry.machine.sleeps == 3, "a refused lid sleep retries until the system accepts it")
        let refused = C.active()
        refused.machine.results = [1]
        refused.manager.deactivate(reason: .manual)
        refused.machine.drain()
        for _ in 0..<15 { refused.machine.advance() }
        expect(refused.machine.sleeps == 10 && refused.machine.later.isEmpty,
               "refused sleep is bounded to ten attempts with no permanent timer")

        for change in 0..<5 {
            let rig = C.active()
            rig.machine.results = [1]
            rig.manager.deactivate(reason: .manual)
            rig.machine.drain()
            switch change {
            case 0:
                rig.manager.activate(minutes: 0)
                rig.machine.drain()
            case 1: rig.machine.lid = false
            case 2: rig.machine.policy = false
            case 3: rig.machine.assertions = [connection]
            default: rig.machine.assertions = nil
            }
            rig.machine.advance()
            expect(rig.machine.sleeps == 1 && rig.machine.later.isEmpty,
                   "each retry rechecks the session, lid and current system protection")
            guard change > 0 else { continue }
            rig.machine.lid = true
            rig.machine.policy = true
            rig.machine.assertions = []
            rig.machine.advance()
            expect(rig.machine.sleeps == 1, "a canceled retry cannot resume after a later context change")
        }

        let paused = C.active { _, defaults in defaults.set(true, forKey: DefaultsKey.keepAwakePauseWhenLocked) }
        paused.machine.lockChanged?(true)
        paused.machine.drain()
        expect(paused.manager.isActive && !paused.manager.clamshellActive && paused.machine.held.isEmpty
               && !paused.machine.disabled && paused.machine.sleeps == 1,
               "a session paused for screen lock no longer asks to stay awake")
        paused.machine.lockChanged?(false)
        paused.machine.drain()
        expect(paused.manager.clamshellActive && paused.machine.disabled && paused.machine.held.count == 2,
               "unlocking resumes the session's assertions and closed-lid mode")

        let lockedStart = C.make { machine, defaults in
            machine.configured = false
            machine.sessionInfo = ["CGSSessionScreenIsLocked": true]
            defaults.set(true, forKey: DefaultsKey.keepAwakePauseWhenLocked)
        }
        lockedStart.manager.activate(minutes: 0)
        lockedStart.machine.drain()
        expect(lockedStart.manager.isActive && lockedStart.machine.installs.isEmpty && lockedStart.machine.held.isEmpty,
               "a session started behind a locked screen asks for nothing until it unlocks")
        lockedStart.machine.lockChanged?(false)
        lockedStart.machine.drain()
        expect(lockedStart.machine.installs.count == 1 && lockedStart.machine.held.count == 2,
               "unlocking starts that session and asks for the rule")

        let relocked = C.active { _, defaults in defaults.set(true, forKey: DefaultsKey.keepAwakePauseWhenLocked) }
        relocked.machine.results = [1]
        for locked in [true, false, true] {
            relocked.machine.lockChanged?(locked)
            relocked.machine.drain()
        }
        relocked.machine.advance()
        expect(relocked.machine.sleeps == 3,
               "a lid-sleep retry left over from an earlier lock is dropped by the next restore")

        let missing = C.active()
        missing.machine.available = false
        missing.machine.results = [1]
        missing.manager.deactivate(reason: .manual)
        missing.machine.drain()
        expect(missing.machine.sleeps == 0 && missing.machine.later.isEmpty,
               "a Mac without a power manager is neither asked to sleep nor polled")

        KeepAwakeClamshellTests.run(expect: expect)
        KeepAwakeDimmingTests.run(expect: expect)
        C.removeSuites()
    }
}
