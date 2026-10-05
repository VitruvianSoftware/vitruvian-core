// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Foundation
import VitruvianCore
import VitruvianDesign
import VitruvianServices
import VitruvianUI

/// Runs the production clear and uninstall flows with the password request,
/// tccutil and every removal step replaced by doubles that log what ran.
enum SelfUninstallContract {
    /// What ran, what each step answers, and the queue every hop waits on.
    /// Only the test's own thread touches it.
    nonisolated final class Record: @unchecked Sendable {
        var events: [String] = []
        var suspensionAllowed = true
        var sleepRestoreAllowed = true
        var detachAllowed = true
        var ruleRemovalAllowed = true
        var tccResetAllowed = true
        var fanHelperWasRegistered = true
        var fanRegistrationRestored = true
        var pending: [() -> Void] = []
        func flush() {
            while !pending.isEmpty { pending.removeFirst()() }
        }
    }

    static func steps(_ record: Record) -> SelfUninstall.Steps {
        .init(suspendInputInterceptors: { record.events.append("suspend"); return record.suspensionAllowed },
              restoreSleepBeforeRemoval: { record.events.append("sleep"); return record.sleepRestoreAllowed },
              detachFanControl: { record.events.append("fan"); return record.detachAllowed },
              detachLoginItem: { record.events.append("login") },
              removeSudoersRule: { then in
                  record.events.append("rule")
                  record.pending.append { then(record.ruleRemovalAllowed) }
              },
              resetTCC: { record.events.append("tccutil"); return record.tccResetAllowed },
              removePreferences: { record.events.append("preferences") },
              trashOwnBundleAndQuit: { record.events.append("trash") },
              fanHelperIsRegistered: {
                  record.events.append("fan registration")
                  return record.fanHelperWasRegistered
              },
              restoreFanRegistration: {
                  record.events.append("restore fan registration")
                  return record.fanRegistrationRestored
              },
              refreshPermissions: { record.events.append("refresh permissions") },
              resumeKeepAwake: { record.events.append("restore keep awake") },
              resumeFeatures: { record.events.append("resume features") },
              resumeBrightness: { record.events.append("resume brightness") },
              main: { work in record.pending.append { MainActor.assumeIsolated { work() } } },
              background: { work in record.pending.append(work) })
    }

    static func run(_ suite: TestSuite) {
        var record = Record()
        func reset(allowRule: Bool) {
            record = Record()
            record.ruleRemovalAllowed = allowRule
        }
        let stopped = L10n.shared.s.advancedUninstallFailedBody
        let ruleKept = L10n.shared.s.advancedClearFailed
        let fanUnavailable = FeatureStrings.fanControl(L10n.shared.language).helperUnavailable

        reset(allowRule: true)
        record.suspensionAllowed = false
        var cleared: Bool?
        SelfUninstall.clearPermissions(steps: steps(record)) { cleared = $0 }
        record.flush()
        suite.expect(cleared == true
                        && record.events == ["suspend", "sleep", "fan", "login", "rule", "tccutil", "refresh permissions", "restore keep awake", "resume brightness"],
                     "a mouse journal kept for a disconnected device does not block clearing permissions, found \(record.events)")

        reset(allowRule: true)
        record.sleepRestoreAllowed = false
        SelfUninstall.clearPermissions(steps: steps(record)) { cleared = $0 }
        record.flush()
        suite.expect(cleared == false
                        && record.events == ["suspend", "sleep", "refresh permissions", "resume features", "resume brightness"],
                     "failed sleep restoration keeps the recovery rule and permissions, found \(record.events)")

        reset(allowRule: true)
        record.detachAllowed = false
        SelfUninstall.clearPermissions(steps: steps(record)) { cleared = $0 }
        record.flush()
        suite.expect(cleared == false
                        && record.events == ["suspend", "sleep", "fan", "restore keep awake", "refresh permissions", "resume features", "resume brightness"],
                     "failed system detach keeps the recovery rule and rearms closed-lid mode, found \(record.events)")

        reset(allowRule: false)
        SelfUninstall.clearPermissions(steps: steps(record)) { cleared = $0 }
        record.flush()
        suite.expect(cleared == false
                        && record.events == ["suspend", "sleep", "fan", "login", "rule", "tccutil", "refresh permissions", "restore keep awake", "resume features", "resume brightness"],
                     "a refused password request reports partial clear and restores closed-lid mode, found \(record.events)")

        reset(allowRule: true)
        record.tccResetAllowed = false
        SelfUninstall.clearPermissions(steps: steps(record)) { cleared = $0 }
        record.flush()
        suite.expect(cleared == false
                        && record.events == ["suspend", "sleep", "fan", "login", "rule", "tccutil", "refresh permissions", "restore keep awake", "resume features", "resume brightness"],
                     "a failed TCC reset reports partial clear and restores closed-lid mode, found \(record.events)")

        reset(allowRule: true)
        SelfUninstall.clearPermissions(steps: steps(record)) { cleared = $0 }
        record.flush()
        suite.expect(cleared == true
                        && record.events == ["suspend", "sleep", "fan", "login", "rule", "tccutil", "refresh permissions", "restore keep awake", "resume brightness"],
                     "clear permissions succeeds when the rule and permissions are removed, found \(record.events)")

        reset(allowRule: false)
        var failure: String?
        SelfUninstall.uninstallCompletely(steps: steps(record)) { failure = $0 }
        record.flush()
        suite.expect(failure == ruleKept
                        && record.events == ["suspend", "sleep", "rule", "restore keep awake", "refresh permissions", "resume features", "resume brightness"],
                     "a refused password request stops a full uninstall before anything is removed, found \(record.events)")

        reset(allowRule: true)
        record.sleepRestoreAllowed = false
        failure = nil
        SelfUninstall.uninstallCompletely(steps: steps(record)) { failure = $0 }
        record.flush()
        suite.expect(failure == stopped
                        && record.events == ["suspend", "sleep", "refresh permissions", "resume features", "resume brightness"],
                     "failed sleep restoration does not reset the closed-lid session, found \(record.events)")

        reset(allowRule: true)
        record.tccResetAllowed = false
        failure = nil
        SelfUninstall.uninstallCompletely(steps: steps(record)) { failure = $0 }
        record.flush()
        suite.expect(failure == ruleKept
                        && record.events == ["suspend", "sleep", "rule", "fan registration", "fan", "tccutil", "restore fan registration", "restore keep awake", "refresh permissions", "resume features", "resume brightness"],
                     "a failed permission reset restores the prior fan helper and keeps login, found \(record.events)")

        reset(allowRule: true)
        record.tccResetAllowed = false
        record.fanRegistrationRestored = false
        failure = nil
        SelfUninstall.uninstallCompletely(steps: steps(record)) { failure = $0 }
        record.flush()
        suite.expect(failure == "\(ruleKept)\n\(fanUnavailable)"
                        && record.events == ["suspend", "sleep", "rule", "fan registration", "fan", "tccutil", "restore fan registration", "restore keep awake", "refresh permissions", "resume features", "resume brightness"],
                     "failed fan registration tells the user the helper is unavailable, found \(record.events)")

        reset(allowRule: true)
        record.tccResetAllowed = false
        record.fanHelperWasRegistered = false
        failure = nil
        SelfUninstall.uninstallCompletely(steps: steps(record)) { failure = $0 }
        record.flush()
        suite.expect(failure == ruleKept
                        && record.events == ["suspend", "sleep", "rule", "fan registration", "fan", "tccutil", "restore keep awake", "refresh permissions", "resume features", "resume brightness"],
                     "a failed reset does not register a helper the user never had, found \(record.events)")

        reset(allowRule: true)
        record.detachAllowed = false
        failure = nil
        SelfUninstall.uninstallCompletely(steps: steps(record)) { failure = $0 }
        record.flush()
        suite.expect(failure == stopped
                        && record.events == ["suspend", "sleep", "rule", "fan registration", "fan", "restore keep awake", "refresh permissions", "resume features", "resume brightness"],
                     "a failed fan-helper detach keeps permissions and login intact, found \(record.events)")

        reset(allowRule: true)
        failure = nil
        SelfUninstall.uninstallCompletely(steps: steps(record)) { failure = $0 }
        record.flush()
        suite.expect(failure == nil
                        && record.events == ["suspend", "sleep", "rule", "fan registration", "fan", "tccutil", "login", "preferences", "trash"],
                     "a full uninstall detaches the fan helper before permission reset and login afterward, found \(record.events)")

        reset(allowRule: true)
        record.suspensionAllowed = false
        failure = nil
        SelfUninstall.uninstallCompletely(steps: steps(record)) { failure = $0 }
        record.flush()
        suite.expect(failure == stopped
                        && record.events == ["suspend", "refresh permissions", "resume features", "resume brightness"],
                     "a full uninstall still waits for mouse acceleration before deleting its journal, found \(record.events)")
    }
}
