// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Foundation
import VitruvianCore
import VitruvianDesign
import VitruvianServices
import VitruvianUI

/// Sessions, restores, rule setup and their retries, through the real
/// manager and the real `SleepOverride` over the contract's machine.
enum KeepAwakeClamshellTests {
    private typealias C = KeepAwakeLidSleepContract

    static func run(expect: (Bool, String) -> Void) {
        let started = C.active()
        expect(started.manager.isActive && started.manager.clamshellActive && started.manager.passwordlessClamshell
               && started.machine.disabled && started.marker && started.machine.held.count == 2,
               "a session with closed-lid mode preferred turns sleep off through the rule and records it")

        let switching = C.make()
        switching.manager.activate(minutes: 15)
        switching.manager.activate(until: Date().addingTimeInterval(3600))
        expect(switching.manager.isActive && switching.manager.sessionMinutes == nil && switching.manager.endDate != nil,
               "an end time replacing a preset session leaves no duration chip selected")
        switching.manager.activate(minutes: 30)
        expect(switching.manager.sessionMinutes == 30,
               "a preset replacing an end-time session selects that preset")
        expect(switching.machine.held.count == 2, "switching picks keeps one assertion of each kind")
        switching.manager.deactivate(reason: .manual)
        switching.machine.drain()

        let lastPick = C.make()
        let end = Date().addingTimeInterval(3600)
        lastPick.manager.activate(until: end)
        lastPick.manager.deactivate(reason: .manual)
        lastPick.machine.drain()
        lastPick.manager.startLastPick()
        expect(lastPick.manager.endDate == end && lastPick.manager.sessionMinutes == nil,
               "the switch restarts a started end time unchanged")
        lastPick.manager.activate(minutes: 30)
        lastPick.manager.deactivate(reason: .manual)
        lastPick.machine.drain()
        lastPick.manager.startLastPick()
        expect(lastPick.manager.sessionMinutes == 30,
               "a preset started from any entry point is what the switch restarts")
        lastPick.manager.deactivate(reason: .manual)
        lastPick.machine.drain()
        lastPick.defaults.set(true, forKey: DefaultsKey.keepAwakeSwitchUsesUntil)
        lastPick.defaults.set(Date().addingTimeInterval(-60).timeIntervalSinceReferenceDate,
                              forKey: DefaultsKey.keepAwakeUntilTime)
        lastPick.manager.startLastPick()
        expect(lastPick.manager.sessionMinutes == 30,
               "an end time that already passed restarts the saved duration, not a session into tomorrow")
        lastPick.manager.resumeAfterSystemTeardown()
        lastPick.machine.drain()
        expect(lastPick.manager.isActive && lastPick.manager.sessionMinutes == 30,
               "clearing permissions keeps the running preset selected")
        lastPick.manager.deactivate(reason: .manual)
        lastPick.machine.drain()

        // A status probe queued before an enable answers after it.
        let staleStatus = C.make()
        staleStatus.manager.refreshPasswordlessStatus()
        staleStatus.manager.activate(minutes: 0)
        staleStatus.machine.runLane()
        staleStatus.machine.runMain()
        staleStatus.machine.configured = false
        staleStatus.machine.runBackground()
        staleStatus.machine.runLane()
        staleStatus.machine.runMain()
        expect(staleStatus.manager.passwordlessClamshell && staleStatus.manager.clamshellActive,
               "a status request from before a newer enable cannot overwrite that operation's verified result")

        let retainedRule = C.active()
        retainedRule.machine.disabled = false
        retainedRule.manager.resumeAfterSystemTeardown()
        retainedRule.machine.drain()
        expect(retainedRule.manager.clamshellActive && retainedRule.machine.disabled
               && retainedRule.machine.writes.last == true && retainedRule.machine.installs.isEmpty
               && retainedRule.marker,
               "a teardown that stopped rearms the active session through a rule that remained installed")

        // An enable still on the lane when the rule goes answers for a
        // session the teardown already discarded.
        let inFlight = C.make()
        inFlight.manager.activate(minutes: 0)
        inFlight.machine.configured = false
        inFlight.manager.resumeAfterSystemTeardown()
        inFlight.machine.drain()
        expect(!inFlight.manager.clamshellActive && inFlight.machine.installs.isEmpty && !inFlight.marker,
               "an enable still in flight at a teardown cannot ask for the rule again")

        let removedRule = C.active()
        removedRule.machine.disabled = false
        removedRule.machine.configured = false
        removedRule.manager.resumeAfterSystemTeardown()
        expect(!removedRule.manager.clamshellActive && !removedRule.manager.passwordlessClamshell,
               "a teardown discards the stale closed-lid session at once")
        removedRule.machine.drain()
        expect(removedRule.machine.installs.isEmpty && !removedRule.machine.disabled && removedRule.machine.prompts == 0
               && !removedRule.marker && removedRule.manager.clamshellPreferred
               && !removedRule.manager.clamshellSetupFailed,
               "a removed rule is not requested again right after the teardown, and a confirmed restore clears the marker")
        let attempted = removedRule.machine.writes.count
        removedRule.manager.deactivate(reason: .manual)
        removedRule.machine.drain()
        expect(removedRule.machine.writes.count == attempted && removedRule.machine.prompts == 0,
               "ending that session asks for nothing, since sleep is already back on")
        removedRule.manager.activate(minutes: 0)
        removedRule.machine.drain()
        expect(removedRule.machine.installs.count == 1,
               "the next session requests the removed rule the usual way")
        removedRule.machine.answerInstall(true)
        removedRule.machine.drain()
        expect(removedRule.manager.clamshellActive && removedRule.machine.disabled,
               "successful rule setup enables closed-lid mode for that session")

        let rearmed = C.active()
        rearmed.machine.configured = false
        rearmed.manager.resumeAfterSystemTeardown()
        rearmed.machine.drain()
        expect(!rearmed.manager.clamshellActive && rearmed.machine.installs.isEmpty && rearmed.marker,
               "sleep turned off again while the rule was being removed keeps its recovery marker")
        rearmed.manager.deactivate(reason: .manual)
        rearmed.machine.drain()
        expect(rearmed.machine.prompts == 1 && rearmed.marker,
               "with the rule gone, ending the session asks for the administrator password")
        rearmed.machine.answer(true)
        rearmed.machine.drain()
        expect(!rearmed.machine.disabled && !rearmed.marker,
               "ending the session still restores sleep that remained off")

        let unreadableReport = C.active()
        unreadableReport.machine.disabled = false
        unreadableReport.machine.configured = false
        unreadableReport.machine.reportStatus = 1
        unreadableReport.manager.resumeAfterSystemTeardown()
        unreadableReport.machine.drain()
        expect(unreadableReport.marker, "an unreadable sleep report does not drop the recovery marker")

        // The launch probe could not read `pmset`; the rule works by the time
        // the session starts.
        let recheck = C.make { machine, _ in machine.reportStatus = 1 }
        recheck.machine.reportStatus = 0
        recheck.manager.activate(minutes: 0)
        recheck.machine.drain()
        expect(recheck.machine.installs.isEmpty && recheck.manager.clamshellActive && recheck.machine.disabled,
               "a rule that proves itself at setup needs no install prompt")

        let pendingSetup = C.make { machine, _ in machine.configured = false }
        pendingSetup.manager.activate(minutes: 0)
        pendingSetup.machine.drain()
        pendingSetup.manager.resumeAfterSystemTeardown()
        pendingSetup.machine.drain()
        expect(pendingSetup.machine.installs.count == 1,
               "a teardown keeps one pending rule authorization instead of asking twice")
        pendingSetup.machine.answerInstall(true)
        pendingSetup.machine.drain()
        expect(pendingSetup.manager.clamshellActive && pendingSetup.machine.disabled,
               "the pending authorization can restore the closed-lid session")

        let pendingRestore = C.active()
        pendingRestore.machine.refusals = 1
        pendingRestore.manager.deactivate(reason: .manual)
        pendingRestore.machine.drain()
        pendingRestore.manager.activate(minutes: 0)
        pendingRestore.machine.drain()
        pendingRestore.machine.disabled = false
        pendingRestore.manager.resumeAfterSystemTeardown()
        pendingRestore.machine.drain()
        expect(!pendingRestore.manager.clamshellActive && pendingRestore.machine.prompts == 1
               && pendingRestore.machine.writes == [false] && !pendingRestore.marker,
               "a teardown waits for an older authorized restore before rearming")
        pendingRestore.machine.answer(true)
        pendingRestore.machine.drain()
        expect(pendingRestore.manager.clamshellActive && pendingRestore.machine.disabled
               && pendingRestore.machine.writes == [false, true],
               "the older restore cannot silently turn off a session that has already rearmed")

        let quitting = C.active()
        quitting.machine.sleepCheck = { [manager = quitting.manager, machine = quitting.machine] in
            !manager.isActive && machine.held.isEmpty && !machine.disabled
        }
        quitting.manager.deactivate(reason: .quit)
        expect(quitting.machine.sleeps == 1 && quitting.machine.sleepChecks == [true] && quitting.machine.waits == 0,
               "quit restores the system and ends the session before requesting lid sleep synchronously")
        expect(!quitting.marker && quitting.machine.prompts == 0,
               "successful quit clears recovery before returning and never asks for a password")

        for lid in [false, nil] as [Bool?] {
            let rig = C.active()
            rig.machine.lid = lid
            rig.manager.deactivate(reason: .quit)
            expect(rig.machine.sleeps == 0 && rig.machine.waits == 0 && !rig.machine.disabled,
                   "quit with an open or unknown lid restores normally without sleep or retry waits")
        }
        let plain = C.make()
        plain.manager.deactivate(reason: .quit)
        expect(plain.machine.sleeps == 0 && plain.machine.writes.isEmpty && plain.machine.waits == 0,
               "quit without an owned override or pending lid sleep changes no system power state")

        let refusedQuit = C.active()
        refusedQuit.machine.results = [1]
        refusedQuit.manager.deactivate(reason: .quit)
        expect(refusedQuit.machine.sleeps == 10 && refusedQuit.machine.waits == 9 && refusedQuit.machine.later.isEmpty,
               "quit completes at most ten refused sleep attempts before returning, without a lost async retry")
        let transient = C.active()
        transient.machine.results = [1, 1, 0]
        transient.manager.deactivate(reason: .quit)
        expect(transient.machine.sleeps == 3 && transient.machine.waits == 2,
               "quit stops waiting as soon as a transiently refused request succeeds")

        for change in 0..<4 {
            let rig = C.active()
            rig.machine.results = [1]
            rig.machine.onWait = { [machine = rig.machine] in
                switch change {
                case 0: machine.lid = false
                case 1: machine.policy = false
                case 2: machine.assertions = [["AssertType": "PreventSystemSleep", "AssertLevel": 1,
                                               "AppliesOnLidClose": true]]
                default: machine.assertions = nil
                }
            }
            rig.manager.deactivate(reason: .quit)
            expect(rig.machine.sleeps == 1 && rig.machine.waits == 1,
                   "every synchronous retry observes newly opened lids and external protections")
        }

        let failed = C.active()
        failed.machine.refusals = 1
        failed.manager.deactivate(reason: .quit)
        expect(failed.marker && failed.machine.sleeps == 0 && failed.machine.prompts == 0,
               "failed silent quit keeps recovery evidence and does not bypass native sleep protection")

        let enabling = C.make()
        enabling.manager.activate(minutes: 0)
        expect(enabling.marker,
               "an in-flight enable is recorded before its native command or main reply finishes")
        enabling.manager.deactivate(reason: .quit)
        enabling.machine.runMain()
        expect(enabling.machine.writes == [true, false] && !enabling.machine.disabled
               && !enabling.manager.clamshellActive && !enabling.marker,
               "quit drains a pending enable and an obsolete reply cannot resurrect its override or marker")

        let between = C.active()
        between.machine.results = [1, 0]
        between.manager.deactivate(reason: .timer)
        between.machine.drain()
        expect(between.machine.sleeps == 1 && !between.marker,
               "a timer can restore the override while its first lid-sleep request is refused")
        between.manager.deactivate(reason: .quit)
        expect(between.machine.sleeps == 2,
               "quit finishes already pending lid sleep even after the override marker was cleared")
        between.machine.advance()
        expect(between.machine.sleeps == 2, "a queued retry cannot repeat sleep after quit consumed it")

        let renewed = C.active()
        renewed.machine.results = [1]
        renewed.manager.deactivate(reason: .timer)
        renewed.machine.drain()
        renewed.manager.clamshellPreferred = false
        renewed.manager.activate(minutes: 0)
        renewed.manager.deactivate(reason: .manual)
        renewed.machine.advance()
        expect(renewed.machine.sleeps == 1,
               "an old retry cannot sleep a later session even if that session ended before the retry")

        let restoring = C.active()
        restoring.machine.refusals = 1
        restoring.manager.deactivate(reason: .manual)
        restoring.machine.drain()
        restoring.manager.activate(minutes: 0)
        restoring.machine.drain()
        expect(restoring.machine.writes == [false] && restoring.machine.prompts == 1
               && !restoring.manager.clamshellActive,
               "a new session waits while the older restore authorization is pending")
        restoring.machine.answer(true)
        restoring.machine.drain()
        expect(restoring.machine.writes == [false, true] && restoring.machine.disabled
               && restoring.manager.clamshellActive && restoring.machine.sleeps == 0,
               "successful delayed restore enables the current session without sleeping or overwriting it")

        let distrusted = C.active()
        distrusted.machine.refusals = 1
        distrusted.manager.deactivate(reason: .manual)
        distrusted.machine.drain()
        distrusted.machine.answer(true)
        distrusted.machine.drain()
        expect(!distrusted.manager.passwordlessClamshell && !distrusted.machine.disabled,
               "a restore that needed the password stops trusting the rule")
        distrusted.manager.activate(minutes: 0)
        distrusted.machine.drain()
        expect(distrusted.manager.clamshellActive && distrusted.manager.passwordlessClamshell
               && distrusted.machine.installs.isEmpty,
               "the next session proves the rule again before relying on it")

        let optedOut = C.active()
        optedOut.manager.clamshellPreferred = false
        optedOut.machine.drain()
        expect(optedOut.manager.isActive && !optedOut.machine.disabled && optedOut.machine.sleeps == 0
               && !optedOut.marker,
               "turning closed-lid mode off during a session restores sleep without sleeping the Mac")

        let waitingRestore = C.active()
        waitingRestore.machine.refusals = 1
        waitingRestore.manager.deactivate(reason: .manual)
        waitingRestore.machine.drain()
        waitingRestore.manager.activate(minutes: 0)
        waitingRestore.manager.deactivate(reason: .manual)
        waitingRestore.machine.drain()
        expect(waitingRestore.machine.writes == [false] && waitingRestore.machine.prompts == 1,
               "ending a session again while a restore waits for its password adds no second restore")

        // The prompt is checked again on the main thread after the lane
        // found sleep still off; quitting in between cancels it.
        let queuedPrompt = C.active()
        queuedPrompt.machine.refusals = 1
        queuedPrompt.manager.deactivate(reason: .manual)
        queuedPrompt.machine.runLane()
        queuedPrompt.machine.runMain()
        queuedPrompt.machine.runLane()
        queuedPrompt.manager.deactivate(reason: .quit)
        queuedPrompt.machine.drain()
        expect(queuedPrompt.machine.prompts == 0 && !queuedPrompt.machine.disabled,
               "a restore prompt queued before quit never opens")

        let latePrompt = C.active()
        latePrompt.machine.refusals = 1
        latePrompt.manager.deactivate(reason: .manual)
        latePrompt.machine.drain()
        latePrompt.manager.deactivate(reason: .quit)
        latePrompt.machine.answer(true)
        latePrompt.machine.drain()
        expect(latePrompt.machine.prompts == 1 && latePrompt.machine.writes == [false, false]
               && !latePrompt.machine.disabled,
               "quit never waits for or repeats an existing authorization; its late reply cannot re-enable")

        let setup = C.make { machine, _ in machine.configured = false }
        setup.manager.activate(minutes: 0)
        setup.machine.drain()
        setup.manager.deactivate(reason: .quit)
        setup.machine.answerInstall(true)
        setup.machine.drain()
        expect(!setup.machine.writes.contains(true) && !setup.machine.disabled,
               "successful setup arriving after quit cannot submit an enable")
        let setupProbe = C.make { machine, _ in machine.configured = false }
        setupProbe.manager.activate(minutes: 0)
        setupProbe.manager.deactivate(reason: .quit)
        setupProbe.machine.drain()
        expect(setupProbe.machine.installs.isEmpty,
               "a setup probe returning after quit cannot open an authorization prompt")

        let recovering = C.make { machine, defaults in
            machine.configured = false
            machine.disabled = true
            defaults.set(true, forKey: DefaultsKey.sleepDisabledFlag)
        }
        recovering.manager.recoverIfNeeded()
        recovering.machine.drain()
        recovering.manager.activate(minutes: 0)
        recovering.machine.drain()
        expect(recovering.machine.prompts == 1 && recovering.machine.installs.isEmpty
               && !recovering.machine.writes.contains(true),
               "launch recovery holds both enable and setup for a new manual session behind its pending off")
        recovering.machine.configured = true
        recovering.machine.answer(true)
        recovering.machine.drain()
        expect(recovering.machine.writes.last == true && recovering.machine.disabled
               && recovering.manager.clamshellActive && recovering.marker,
               "delayed launch recovery completes before the new manual session enables closed-lid mode")

        let unreadable = C.make { machine, defaults in
            machine.configured = false
            machine.reportStatus = -1
            machine.reportOutput = ""
            defaults.set(true, forKey: DefaultsKey.sleepDisabledFlag)
        }
        unreadable.manager.recoverIfNeeded()
        unreadable.machine.drain()
        unreadable.machine.answer(false)
        unreadable.machine.drain()
        expect(unreadable.marker,
               "failed power-state reads and refused recovery never erase evidence of an owned override")

        let deniedSetup = C.make()
        deniedSetup.machine.configured = false
        deniedSetup.manager.activate(minutes: 0)
        deniedSetup.machine.drain()
        expect(deniedSetup.machine.installs.count == 1,
               "a failed enable offers its one passwordless setup repair")
        deniedSetup.machine.answerInstall(false)
        deniedSetup.machine.drain()
        expect(!deniedSetup.manager.clamshellPreferred && deniedSetup.manager.clamshellSetupFailed
               && deniedSetup.machine.prompts == 0 && !deniedSetup.machine.disabled && !deniedSetup.marker,
               "denying repair does not ask for another password when the failed enable left sleep enabled")

        // A session restarted without the rule asks for it while the old
        // override is still recorded; ending that session needs a password.
        let staleSetup = C.active()
        staleSetup.machine.configured = false
        staleSetup.manager.resumeAfterSystemTeardown()
        staleSetup.machine.drain()
        staleSetup.manager.activate(minutes: 0)
        staleSetup.machine.drain()
        staleSetup.manager.deactivate(reason: .manual)
        staleSetup.machine.drain()
        staleSetup.machine.answerInstall(true)
        staleSetup.machine.drain()
        expect(staleSetup.manager.clamshellPreferred && staleSetup.machine.prompts == 1
               && staleSetup.machine.installs.isEmpty,
               "a setup reply invalidated by restore cannot open another prompt or turn off the saved preference")
        staleSetup.machine.lid = false
        staleSetup.machine.answer(true)
        staleSetup.machine.drain()
        expect(!staleSetup.machine.disabled && !staleSetup.marker,
               "late setup probes cannot resurrect the override cleared by authorized restore")

        sleepOverride(expect: expect)
    }

    /// The override's own lane: probes, writes, authorized restores and the
    /// rule install, over the same machine.
    private static func sleepOverride(expect: (Bool, String) -> Void) {
        let probing = C.Machine()
        probing.disabled = true
        let suspended = SleepOverride(transport: probing.transport)
        expect(suspended.isConfigured() && probing.writes == [true],
               "a probe before authorization verifies the current state by writing it back")
        suspended.restoreWithAuthorization(prompt: "restore", shouldProceed: { true }) { _ in }
        probing.drain()
        expect(probing.prompts == 1 && probing.commands == ["pmset disablesleep 0"]
               && !suspended.isConfigured() && probing.writes == [true],
               "a pending authorization blocks late probes from reapplying stale disabled-sleep state")
        expect(suspended.disableSleep(false) && !probing.disabled,
               "a silent quit restore can drain the lane while authorization remains unanswered")
        probing.answer(true)
        probing.drain()
        expect(suspended.isConfigured() && probing.writes.last == false && !probing.disabled,
               "probes resume only after authorization finishes and then observe the restored state")

        let canceled = C.Machine()
        canceled.disabled = true
        let cancelable = SleepOverride(transport: canceled.transport)
        let mayPrompt = C.Box(true)
        cancelable.restoreWithAuthorization(prompt: "restore", shouldProceed: { mayPrompt.value }) { _ in }
        canceled.runLane()
        mayPrompt.value = false
        canceled.drain()
        expect(canceled.prompts == 0 && cancelable.isConfigured(),
               "authorization revalidates on the main thread and releases probe suspension after cancellation")

        let alreadyOn = C.Machine()
        let confirmed = SleepOverride(transport: alreadyOn.transport)
        let restored = C.Box(false)
        confirmed.restoreWithAuthorization(prompt: "restore", shouldProceed: { true }) { restored.value = $0 }
        alreadyOn.drain()
        expect(restored.value && alreadyOn.prompts == 0 && confirmed.isConfigured(),
               "a confirmed already-restored override succeeds without authorization and releases probes")

        let blind = C.Machine()
        blind.reportStatus = 1
        expect(!SleepOverride(transport: blind.transport).isConfigured() && blind.writes.isEmpty,
               "a probe that cannot read pmset proves nothing and writes nothing")

        let unreadable = C.Machine()
        unreadable.reportStatus = -1
        unreadable.reportOutput = ""
        let unconfirmed = SleepOverride(transport: unreadable.transport)
        unconfirmed.restoreWithAuthorization(prompt: "restore", shouldProceed: { true }) { _ in }
        unreadable.drain()
        unreadable.reportStatus = 0
        unreadable.reportOutput = nil
        expect(unreadable.prompts == 1 && !unconfirmed.isConfigured(),
               "an unreadable power report cannot bypass the normal restore authorization")
        unreadable.answer(false)
        unreadable.drain()
        expect(unconfirmed.isConfigured(), "a refused authorization still releases the probes")

        let installing = C.Machine()
        installing.configured = false
        let rule = SleepOverride(transport: installing.transport)
        let installed = C.Box<[Bool]>([])
        rule.install { installed.value.append($0) }
        rule.install { installed.value.append($0) }
        installing.answerInstall(true, works: false)
        installing.answerInstall(true)
        expect(installing.commands == [Sudoers.installCommand, Sudoers.installCommand]
               && installed.value == [false, true],
               "an installed rule counts only once its passwordless path proves itself")
    }
}
