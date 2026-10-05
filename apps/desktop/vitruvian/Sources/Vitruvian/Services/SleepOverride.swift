// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 VitruvianSoftware

import Foundation
import VitruvianCore

/// The system-wide `pmset disablesleep` override that closed-lid mode sets,
/// through the passwordless sudoers rule or, failing that, an administrator
/// prompt.
///
/// Writes and the probes that prove the rule run in order on one serial lane.
/// An authorized restore runs beside that lane with probes suspended, so a
/// probe cannot put back a stale "1" after the restore cleared it and leave
/// lid sleep off without a recovery marker.
package final class SleepOverride: @unchecked Sendable {
    package struct Transport: Sendable {
        /// Queues work on the serial lane, behind everything already on it.
        package var async: @Sendable (@escaping @Sendable () -> Void) -> Void
        /// Runs work on the serial lane and waits for it.
        package var sync: @Sendable (() -> Bool) -> Bool
        /// `pmset -g`: its exit status and report.
        package var report: @Sendable () -> (status: Int32, output: String)
        /// `sudo -n pmset disablesleep`: whether the passwordless write succeeded.
        package var write: @Sendable (Bool) -> Bool
        /// Runs a command as administrator, behind the system's password prompt.
        package var authorize: @Sendable (_ command: String, _ prompt: String,
                                          _ completion: @escaping @Sendable (Bool) -> Void) -> Void
        /// The main queue, where a prompt is checked again before it opens.
        package var main: @Sendable (@escaping @MainActor @Sendable () -> Void) -> Void

        package init(async: @escaping @Sendable (@escaping @Sendable () -> Void) -> Void,
                     sync: @escaping @Sendable (() -> Bool) -> Bool,
                     report: @escaping @Sendable () -> (status: Int32, output: String),
                     write: @escaping @Sendable (Bool) -> Bool,
                     authorize: @escaping @Sendable (String, String, @escaping @Sendable (Bool) -> Void) -> Void,
                     main: @escaping @Sendable (@escaping @MainActor @Sendable () -> Void) -> Void) {
            self.async = async
            self.sync = sync
            self.report = report
            self.write = write
            self.authorize = authorize
            self.main = main
        }

        /// One serial queue, `pmset` through `Shell` and the prompt through `AdminShell`.
        package static var live: Transport {
            let queue = DispatchQueue(label: "com.vitruviansoftware.vitruvian.pmset-state")
            return Transport(
                async: { queue.async(execute: $0) },
                sync: { queue.sync(execute: $0) },
                report: { Shell.run("/usr/bin/pmset", ["-g"]) },
                write: { on in
                    Shell.run("/usr/bin/sudo", ["-n", "/usr/bin/pmset", "disablesleep", on ? "1" : "0"]).status == 0
                },
                authorize: { command, prompt, completion in
                    AdminShell.run(command, prompt: prompt, completion: completion)
                },
                main: { work in DispatchQueue.main.async { work() } })
        }
    }

    package static let live = SleepOverride(transport: .live)

    private let transport: Transport
    // Only the serial lane touches it.
    private var probeSuspensions = 0

    package init(transport: Transport) {
        self.transport = transport
    }

    /// Proves the passwordless path by running it: re-applying the current
    /// SleepDisabled state through `sudo -n` changes nothing on the system and
    /// exercises the exact call the feature makes. Listing checks (`sudo -l`)
    /// reported the rule as ready on Macs where the real call still asked for
    /// a password, which put every toggle behind a prompt (issue #269).
    package func isConfigured() -> Bool {
        transport.sync {
            guard self.probeSuspensions == 0 else { return false }
            let report = self.transport.report()
            guard report.status == 0 else { return false }
            return self.transport.write(SudoersSupport.sleepDisabled(inPmsetOutput: report.output))
        }
    }

    /// Installs the rule behind the administrator prompt; succeeds only once
    /// the rule then proves itself.
    package func install(completion: @escaping @Sendable (Bool) -> Void) {
        transport.authorize(Sudoers.installCommand, L10n.shared.s.adminPromptSudoersInstall) { ok in
            completion(ok && self.isConfigured())
        }
    }

    /// Toggles sleep through the password-free path, after every write already
    /// queued. Fails (returns false) when the rule is not installed.
    @discardableResult
    package func disableSleep(_ on: Bool) -> Bool {
        transport.sync { self.transport.write(on) }
    }

    /// Queues the write in request order. Completions must not wait for the
    /// main thread or for administrator authorization.
    package func disableSleep(_ on: Bool, completion: @escaping @Sendable (Bool) -> Void) {
        transport.async { completion(self.transport.write(on)) }
    }

    /// Completes earlier probes before authorization can restore sleep and
    /// suspends later probes until it finishes. The lane remains free for a
    /// silent restore during quit; the main-thread check cancels stale prompts.
    /// `shouldProceed` runs on the main thread; `completion` on the lane.
    package func restoreWithAuthorization(prompt: String,
                                          shouldProceed: @escaping @MainActor @Sendable () -> Bool,
                                          completion: @escaping @Sendable (Bool) -> Void) {
        transport.async {
            self.probeSuspensions += 1
            let finish: @Sendable (Bool) -> Void = { ok in
                self.transport.async {
                    self.probeSuspensions -= 1
                    completion(ok)
                }
            }
            // A failed enable may never have set the override. Once probes
            // are suspended, a confirmed off needs no further authorization.
            let report = self.transport.report()
            if report.status == 0, !SudoersSupport.sleepDisabled(inPmsetOutput: report.output) {
                finish(true)
                return
            }
            self.transport.main {
                guard shouldProceed() else {
                    finish(false)
                    return
                }
                self.transport.authorize("pmset disablesleep 0", prompt, finish)
            }
        }
    }
}
