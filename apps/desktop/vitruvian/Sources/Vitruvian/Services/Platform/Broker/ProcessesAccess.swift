// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 VitruvianSoftware

import Darwin
import Foundation
import VitruvianCore

/// What a tool scans processes with, off the main thread. It is handed out
/// after the broker's checks pass, and holds no way to change what it runs.
package struct ProcessScanner: Sendable {
    /// When a process started, as the kernel records it. With the PID it
    /// identifies one process even after the PID is used again.
    package let startTime: @Sendable (pid_t) -> UInt64?
    /// `lsof`'s field report of every listening TCP socket. A negative
    /// status means it ran out of time.
    package let listeningSocketsReport: @Sendable () -> (status: Int32, output: String)
}

/// The `processes` capability: see what is listening, and end a process.
@MainActor
package struct ProcessesAccess {
    package struct Backing {
        package var startTime: @Sendable (pid_t) -> UInt64?
        package var listeningSocketsReport: @Sendable () -> (status: Int32, output: String)
        /// Whether ending a process is offered at all. It is the Kill
        /// process feature's work, so it follows that feature.
        package var terminationAvailable: () -> Bool
        package var isProtected: (_ pid: pid_t, _ name: String) -> Bool
        package var terminate: (_ pid: pid_t, _ name: String, _ startedAt: UInt64, _ force: Bool,
                                _ completion: @escaping @MainActor @Sendable () -> Void) -> Void

        package init(startTime: @escaping @Sendable (pid_t) -> UInt64?,
                     listeningSocketsReport: @escaping @Sendable () -> (status: Int32, output: String),
                     terminationAvailable: @escaping () -> Bool,
                     isProtected: @escaping (pid_t, String) -> Bool,
                     terminate: @escaping (pid_t, String, UInt64, Bool, @escaping @MainActor @Sendable () -> Void) -> Void) {
            self.startTime = startTime
            self.listeningSocketsReport = listeningSocketsReport
            self.terminationAvailable = terminationAvailable
            self.isProtected = isProtected
            self.terminate = terminate
        }

        @MainActor package static let live = Backing(
            startTime: { KillProcessService.startTime(for: $0) },
            listeningSocketsReport: {
                Shell.run("/usr/sbin/lsof", ["-nP", "+c0", "-iTCP", "-sTCP:LISTEN", "-F", "pcnPT"])
            },
            terminationAvailable: { AppFeature.killProcess.isAvailable },
            isProtected: { KillProcessService.isProtected(pid: $0, name: $1) },
            terminate: { pid, name, startedAt, force, completion in
                KillProcessService.shared.kill(pid: pid, name: name, startedAt: startedAt, force: force,
                                               completion: completion)
            })

        /// Sees nothing and ends nothing. For tests of other capabilities.
        @MainActor package static let inert = Backing(startTime: { _ in nil }, listeningSocketsReport: { (0, "") },
                                                      terminationAvailable: { false }, isProtected: { _, _ in true },
                                                      terminate: { _, _, _, _, _ in })
    }

    let gate: () -> BrokerRefusal?
    let backing: Backing

    /// A scanner, once the checks pass. Ask each time a scan starts.
    package func scanner() -> Result<ProcessScanner, BrokerRefusal> {
        if let refusal = gate() { return .failure(refusal) }
        return .success(ProcessScanner(startTime: backing.startTime,
                                       listeningSocketsReport: backing.listeningSocketsReport))
    }

    /// Whether ending a process is offered to this tool right now.
    package var canTerminate: Bool {
        gate() == nil && backing.terminationAvailable()
    }

    /// Whether the host refuses to end this process. A tool that may not
    /// ask is told yes: the safe answer.
    package func isProtected(pid: pid_t, name: String) -> Bool {
        guard gate() == nil else { return true }
        return backing.isProtected(pid, name)
    }

    /// Ends the process that has this PID and started at `startedAt`.
    /// `completion` is not called when the call is refused.
    @discardableResult
    package func terminate(pid: pid_t, name: String, startedAt: UInt64, force: Bool,
                           completion: @escaping @MainActor @Sendable () -> Void) -> BrokerRefusal? {
        if let refusal = gate() { return refusal }
        guard backing.terminationAvailable() else { return .unavailable }
        backing.terminate(pid, name, startedAt, force, completion)
        return nil
    }
}
