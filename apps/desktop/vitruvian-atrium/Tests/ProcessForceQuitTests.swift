// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Darwin
import Foundation
import VitruvianCore
import VitruvianServices

/// Run the real identity binding and eligibility guards; no process is signalled.
enum ProcessForceQuitTests {
    /// Stands in for the responsible-process lookup and the kernel's start
    /// times, so the guards see the owners and identities each case sets.
    nonisolated final class Identity: @unchecked Sendable {
        var owners: [pid_t: pid_t] = [:]
        var startTimes: [pid_t: UInt64] = [:]
        var lookups = 0

        var environment: ProcessUsageService.Environment {
            ProcessUsageService.Environment(
                owner: { self.owners[$0] ?? $0 },
                displayName: { _, fallback in fallback },
                startTime: {
                    self.lookups += 1
                    return self.startTimes[$0]
                })
        }
    }

    static func run(_ suite: TestSuite) {
        let defaults = UserDefaults.standard
        let featureKey = AppFeature.killProcess.availabilityKey
        let previous = defaults.object(forKey: featureKey)
        defer {
            if let previous { defaults.set(previous, forKey: featureKey) }
            else { defaults.removeObject(forKey: featureKey) }
        }

        let sampleStartedAt = mach_absolute_time()
        let victim = Process()
        victim.executableURL = URL(fileURLWithPath: "/bin/sleep")
        victim.arguments = ["60"]
        guard (try? victim.run()) != nil else {
            suite.expect(false, "an ordinary test process can launch")
            return
        }
        defer { victim.terminate(); victim.waitUntilExit() }
        let victimPID = victim.processIdentifier
        let identity = Identity()
        let service = ProcessUsageService(environment: identity.environment)
        identity.startTimes[victimPID] = 42

        defaults.set(false, forKey: featureKey)
        suite.expect(!service.canForceQuit(ProcessUsage(pid: victimPID, name: "sleep", value: 1, startedAt: 42))
                     && identity.lookups == 0,
                     "uninstalled Kill Process does not inspect or expose a process")

        defaults.set(true, forKey: featureKey)
        let row = ProcessUsage(pid: victimPID, name: "sleep", value: 1)
        let replaced = service.withForceQuitIdentity([row], sampleStartedAt: sampleStartedAt,
                                                     unsafeOwners: [])
        suite.expect(replaced.first?.startedAt == nil,
                     "a PID replaced during sampling cannot acquire the replacement's identity")
        let stable = service.withForceQuitIdentity([row], sampleStartedAt: mach_absolute_time(),
                                                   unsafeOwners: [])
        suite.expect(stable.first?.startedAt == 42,
                     "a process that existed before sampling retains its identity")
        let lookups = identity.lookups
        let untracked = service.groupedByApp([row], sampleStartedAt: nil)
        suite.expect(untracked.first?.startedAt == nil && identity.lookups == lookups,
                     "enabling Kill Process after sampling does not bind an untracked row")

        // A reused helper can resolve to an older, still-running owner. The
        // helper must also predate the sample, not just that owner.
        identity.startTimes[getpid()] = 42
        identity.owners[victimPID] = getpid()
        let helper = service.groupedByApp([row], sampleStartedAt: sampleStartedAt)
        suite.expect(helper.first?.pid == getpid() && helper.first?.startedAt == nil
                     && helper.first?.value == 1,
                     "a replacement helper cannot make a stable owner's row killable")
        let mixed = service.groupedByApp(
            [ProcessUsage(pid: getpid(), name: "owner", value: 2), row],
            sampleStartedAt: sampleStartedAt)
        suite.expect(mixed.first?.startedAt == nil && mixed.first?.value == 3,
                     "one unsafe contributor disables killing while preserving grouped usage")
        let networkSample = NetworkProcessSample(pid: victimPID, name: "sleep", bytesIn: 10, bytesOut: 20)
        let network = service.groupedNetworkByApp([networkSample], sampleStartedAt: sampleStartedAt)
        suite.expect(network.first?.startedAt == nil && network.first?.networkDownBytesPerSec == 10
                     && network.first?.networkUpBytesPerSec == 20,
                     "network rejects a replacement helper while preserving both rates")
        let stableNetwork = service.groupedNetworkByApp([networkSample], sampleStartedAt: mach_absolute_time())
        suite.expect(stableNetwork.first?.startedAt == 42,
                     "network binds a stable helper's responsible owner")

        identity.owners = [getpid(): victimPID]
        let owner = service.groupedByApp([ProcessUsage(pid: getpid(), name: "helper", value: 1)],
                                         sampleStartedAt: sampleStartedAt)
        suite.expect(owner.first?.pid == victimPID && owner.first?.startedAt == nil,
                     "a stable helper cannot bind an owner created during sampling")
        identity.owners = [:]

        defaults.set(false, forKey: featureKey)
        let disabledLookups = identity.lookups
        let disabled = service.groupedByApp([row], sampleStartedAt: mach_absolute_time())
        suite.expect(disabled.first?.startedAt == nil && identity.lookups == disabledLookups,
                     "uninstalled Kill Process skips identity binding during grouping")
        defaults.set(true, forKey: featureKey)
        suite.expect(!service.canForceQuit(ProcessUsage(pid: victimPID, name: "sleep", value: 1, startedAt: nil)),
                     "a row without a sampled identity cannot be killed")
        suite.expect(!service.canForceQuit(ProcessUsage(pid: victimPID, name: "sleep", value: 1, startedAt: 41)),
                     "a PID reused before menu selection cannot be killed")
        suite.expect(service.canForceQuit(ProcessUsage(pid: victimPID, name: "sleep", value: 1, startedAt: 42)),
                     "an ordinary process with a matching identity can be force killed")
        identity.startTimes[victimPID] = 43
        suite.expect(!service.canForceQuit(ProcessUsage(pid: victimPID, name: "sleep", value: 1, startedAt: 42)),
                     "a PID reused while confirmation is open cannot be killed")
        identity.startTimes[victimPID] = 42
        suite.expect(!service.canForceQuit(ProcessUsage(pid: victimPID, name: "WindowServer", value: 1, startedAt: 42)),
                     "a protected display name cannot be killed")

        identity.startTimes[getpid()] = 42
        suite.expect(!service.canForceQuit(ProcessUsage(pid: getpid(), name: "Whatever", value: 1, startedAt: 42)),
                     "the app's own process stays protected")
        identity.startTimes[1] = 42
        suite.expect(!service.canForceQuit(ProcessUsage(pid: 1, name: "pid 1", value: 1, startedAt: 42)),
                     "launchd stays protected")
        for name in ["WindowServer", "loginwindow", "kernel_task"] {
            guard let pid = pid(named: name) else { continue }
            identity.startTimes[pid] = 42
            suite.expect(!service.canForceQuit(ProcessUsage(pid: pid, name: "pid \(pid)", value: 1, startedAt: 42)),
                         "\(name) stays protected behind an unresolved display name")
            suite.expect(!service.canForceQuit(ProcessUsage(pid: pid, name: name, value: 1, startedAt: 42)),
                         "\(name) stays protected under its own name")
        }
    }

    /// `ps` rather than `proc_name`, which returns nothing for processes owned
    /// by root — exactly the ones these assertions have to reach.
    private static func pid(named target: String) -> pid_t? {
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/bin/ps")
        task.arguments = ["-Aceo", "pid,comm"]
        let pipe = Pipe()
        task.standardOutput = pipe
        guard (try? task.run()) != nil else { return nil }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        task.waitUntilExit()
        for line in String(decoding: data, as: UTF8.self).split(separator: "\n") {
            let columns = line.split(separator: " ", omittingEmptySubsequences: true)
            guard columns.count == 2, columns[1] == target else { continue }
            return pid_t(columns[0])
        }
        return nil
    }
}
