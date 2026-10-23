// Copyright (c) 2026 VitruvianSoftware
//
// Permission is hereby granted, free of charge, to any person obtaining a copy
// of this software and associated documentation files (the "Software"), to deal
// in the Software without restriction, including without limitation the rights
// to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
// copies of the Software, and to permit persons to whom the Software is
// furnished to do so, subject to the following conditions:
//
// The above copyright notice and this permission notice shall be included in
// all copies or substantial portions of the Software.
//
// THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
// IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
// FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
// AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
// LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
// OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
// SOFTWARE.
//
// The control room for Wave C: orchestration runs, scheduled automations, and
// remote hosts, the mobile companion and sleeping sessions. The app hands it
// the state objects and what to do when the user exports, wakes or edits.

import AppKit
import NexusAgentCore
import SwiftUI

@MainActor
public struct NexusAgentAutomationAndOrchestrationView: View {
    public enum Tab: String, Hashable, CaseIterable, Sendable {
        case runs, automations, remote
    }

    @ObservedObject private var coordinator: NexusAgentOrchestrationCoordinator
    @ObservedObject private var automations: NexusAgentAutomationManager
    @ObservedObject private var hibernation: NexusAgentHibernationManager
    private let mobileSnapshots: [NexusAgentMobileSessionSnapshot]
    private let defaultProviderID: UUID
    private let executablePath: String
    private let onRemoteHostsChange: ([NexusAgentRemoteHost]) -> Void
    private let onWake: (NexusAgentHibernatedSessionRecord) -> Void
    private let onExportLaunchAgent: (NexusAgentScheduledTask, String) -> Void

    @State var tab: Tab
    @State var hosts: [NexusAgentRemoteHost]

    public init(coordinator: NexusAgentOrchestrationCoordinator,
                automations: NexusAgentAutomationManager,
                hibernation: NexusAgentHibernationManager,
                remoteHosts: [NexusAgentRemoteHost] = [],
                mobileSnapshots: [NexusAgentMobileSessionSnapshot] = [],
                defaultProviderID: UUID,
                executablePath: String,
                initialTab: Tab = .runs,
                onRemoteHostsChange: @escaping ([NexusAgentRemoteHost]) -> Void = { _ in },
                onWake: @escaping (NexusAgentHibernatedSessionRecord) -> Void = { _ in },
                onExportLaunchAgent: @escaping (NexusAgentScheduledTask, String) -> Void = { _, _ in }) {
        self.coordinator = coordinator
        self.automations = automations
        self.hibernation = hibernation
        self.mobileSnapshots = mobileSnapshots
        self.defaultProviderID = defaultProviderID
        self.executablePath = executablePath
        self.onRemoteHostsChange = onRemoteHostsChange
        self.onWake = onWake
        self.onExportLaunchAgent = onExportLaunchAgent
        _tab = State(initialValue: initialTab)
        _hosts = State(initialValue: remoteHosts)
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Picker("", selection: $tab) {
                Label("Orchestration", systemImage: "cpu").tag(Tab.runs)
                Label("Automations", systemImage: "calendar.badge.clock").tag(Tab.automations)
                Label("Remote & Mobile", systemImage: "network").tag(Tab.remote)
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .padding(12)
            Divider()
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    switch tab {
                    case .runs:
                        NexusAgentOrchestrationRunsPane(coordinator: coordinator)
                    case .automations:
                        NexusAgentAutomationsPane(automations: automations,
                                                  defaultProviderID: defaultProviderID,
                                                  executablePath: executablePath,
                                                  onExportLaunchAgent: onExportLaunchAgent)
                    case .remote:
                        NexusAgentRemoteAndMobilePane(hosts: $hosts,
                                                      hibernation: hibernation,
                                                      mobileSnapshots: mobileSnapshots,
                                                      onRemoteHostsChange: onRemoteHostsChange,
                                                      onWake: onWake)
                    }
                }
                .padding(14)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .frame(minWidth: 520, minHeight: 420)
    }
}

// MARK: - Shared pieces

/// A rounded card around a section.
private struct NexusAgentControlRoomCard<Content: View>: View {
    let title: String
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title).font(.headline)
            content
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 10).fill(Color(nsColor: .controlBackgroundColor)))
        .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(Color.secondary.opacity(0.15)))
    }
}

/// A small capsule of text.
private struct NexusAgentControlRoomBadge: View {
    let text: String
    var tint: Color = .accentColor

    var body: some View {
        Text(text)
            .font(.caption.weight(.medium))
            .padding(.horizontal, 7)
            .padding(.vertical, 2)
            .background(Capsule().fill(tint.opacity(0.15)))
            .foregroundStyle(tint)
    }
}

// MARK: - Orchestration runs

private struct NexusAgentOrchestrationRunsPane: View {
    @ObservedObject var coordinator: NexusAgentOrchestrationCoordinator
    @State var runName = ""
    @State var plan = "writer: Implement the change\nreviewer: Review the change"
    @State var error: String?

    var body: some View {
        NexusAgentControlRoomCard(title: "New run") {
            TextField("Run name", text: $runName)
                .textFieldStyle(.roundedBorder)
            Text("One task per line, starting with writer: or reviewer:. Each reviewer waits on every writer above it; each writer waits on the task before it.")
                .font(.caption)
                .foregroundStyle(.secondary)
            TextEditor(text: $plan)
                .font(.system(.body, design: .monospaced))
                .frame(minHeight: 70)
                .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(Color.secondary.opacity(0.2)))
            HStack {
                if let error {
                    Label(error, systemImage: "exclamationmark.triangle.fill")
                        .font(.caption)
                        .foregroundStyle(.orange)
                }
                Spacer()
                Button {
                    startRun()
                } label: {
                    Label("Create & dispatch", systemImage: "play.fill")
                }
                .disabled(Self.tasks(from: plan).isEmpty)
            }
        }
        if coordinator.runs.isEmpty {
            Text("No orchestration runs yet.")
                .foregroundStyle(.secondary)
        }
        ForEach(coordinator.runs.reversed()) { run in
            NexusAgentRunCard(run: run, coordinator: coordinator)
        }
    }

    private func startRun() {
        let name = runName.trimmingCharacters(in: .whitespaces)
        switch coordinator.startRun(name: name.isEmpty ? "Run" : name, tasks: Self.tasks(from: plan)) {
        case .success(let run):
            coordinator.dispatchReady(runID: run.id)
            error = nil
            runName = ""
        case .failure(let failure):
            error = failure.message
        }
    }

    /// Turns the plan text into tasks with their dependencies.
    static func tasks(from plan: String) -> [NexusAgentWorkerTask] {
        var tasks: [NexusAgentWorkerTask] = []
        var writers: [UUID] = []
        for raw in plan.split(separator: "\n") {
            let line = raw.trimmingCharacters(in: .whitespaces)
            guard !line.isEmpty else { continue }
            let lowered = line.lowercased()
            let isReviewer = lowered.hasPrefix("reviewer:")
            var title = line
            if let colon = line.firstIndex(of: ":"), isReviewer || lowered.hasPrefix("writer:") {
                title = line[line.index(after: colon)...].trimmingCharacters(in: .whitespaces)
            }
            guard !title.isEmpty else { continue }
            let dependsOn = isReviewer ? writers : (tasks.last.map { [$0.id] } ?? [])
            let task = NexusAgentWorkerTask(title: title, promptSpec: title,
                                            role: isReviewer ? .reviewerReadOnly : .writerWorktree,
                                            dependsOnTaskIDs: dependsOn)
            if !isReviewer { writers.append(task.id) }
            tasks.append(task)
        }
        return tasks
    }
}

private struct NexusAgentRunCard: View {
    let run: NexusAgentOrchestrationRun
    @ObservedObject var coordinator: NexusAgentOrchestrationCoordinator

    var body: some View {
        NexusAgentControlRoomCard(title: run.name) {
            HStack(spacing: 8) {
                ProgressView(value: Double(run.completedCount), total: Double(max(run.tasks.count, 1)))
                Text("\(run.completedCount)/\(run.tasks.count)")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
                if run.isComplete {
                    NexusAgentControlRoomBadge(text: run.succeeded ? "Complete" : "Finished with failures",
                                    tint: run.succeeded ? .green : .orange)
                }
            }
            ForEach(run.tasks) { task in
                HStack(spacing: 8) {
                    NexusAgentTaskStatusIcon(status: task.status)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(task.title).lineLimit(1)
                        if let summary = task.resultSummary, !summary.isEmpty {
                            Text(summary).font(.caption).foregroundStyle(.secondary).lineLimit(2)
                        } else if let path = task.worktreePath {
                            Text(path).font(.caption.monospaced()).foregroundStyle(.secondary).lineLimit(1)
                        }
                    }
                    Spacer()
                    NexusAgentRoleBadge(role: task.role)
                    if task.status == .dispatched {
                        Button("Done") {
                            coordinator.workerDone(runID: run.id, taskID: task.id, succeeded: true,
                                                   summary: "Marked done by hand.")
                            coordinator.dispatchReady(runID: run.id)
                        }
                        .controlSize(.small)
                        Button("Failed") {
                            coordinator.workerDone(runID: run.id, taskID: task.id, succeeded: false,
                                                   summary: "Marked failed by hand.")
                            coordinator.dispatchReady(runID: run.id)
                        }
                        .controlSize(.small)
                    }
                }
            }
            HStack {
                Text(run.createdAt, style: .relative).font(.caption).foregroundStyle(.secondary)
                Spacer()
                if !run.readyTasks.isEmpty {
                    Button {
                        coordinator.dispatchReady(runID: run.id)
                    } label: {
                        Label("Dispatch ready", systemImage: "play.fill")
                    }
                    .controlSize(.small)
                }
                Button(role: .destructive) {
                    coordinator.removeRun(id: run.id)
                } label: {
                    Label("Remove", systemImage: "trash")
                }
                .controlSize(.small)
            }
        }
    }
}

private struct NexusAgentRoleBadge: View {
    let role: NexusAgentWorkerRole

    var body: some View {
        HStack(spacing: 3) {
            switch role {
            case .writerWorktree: Image(systemName: "arrow.triangle.branch")
            case .reviewerReadOnly: Image(systemName: "eye")
            }
            Text(role.displayName)
        }
        .font(.caption.weight(.medium))
        .padding(.horizontal, 7)
        .padding(.vertical, 2)
        .background(Capsule().fill((role == .writerWorktree ? Color.blue : Color.purple).opacity(0.15)))
        .foregroundStyle(role == .writerWorktree ? Color.blue : Color.purple)
        .help(role == .writerWorktree ? "Writes in a worktree of its own" : "Reads only; changes nothing")
    }
}

private struct NexusAgentTaskStatusIcon: View {
    let status: NexusAgentWorkerTask.Status

    var body: some View {
        Group {
            switch status {
            case .pending: Image(systemName: "hourglass").foregroundStyle(.secondary)
            case .ready: Image(systemName: "circle").foregroundStyle(.blue)
            case .dispatched: Image(systemName: "bolt.fill").foregroundStyle(.blue)
            case .completed: Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
            case .failed: Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.orange)
            case .circuitBroken: Image(systemName: "xmark.octagon.fill").foregroundStyle(.red)
            }
        }
        .frame(width: 16)
        .help(status.rawValue)
    }
}

// MARK: - Scheduled automations

private struct NexusAgentAutomationsPane: View {
    @ObservedObject var automations: NexusAgentAutomationManager
    let defaultProviderID: UUID
    let executablePath: String
    let onExportLaunchAgent: (NexusAgentScheduledTask, String) -> Void

    @State var name = ""
    @State var prompt = ""
    @State var workingDirectory = ""
    @State var scheduleText = "@weekdays9am"
    @State var useWorktree = false

    private var schedule: NexusAgentAutomationSchedule? {
        NexusAgentAutomationSchedule(text: scheduleText)
    }

    var body: some View {
        NexusAgentControlRoomCard(title: "New automation") {
            TextField("Name", text: $name).textFieldStyle(.roundedBorder)
            TextField("Prompt", text: $prompt, axis: .vertical)
                .lineLimit(2...5)
                .textFieldStyle(.roundedBorder)
            TextField("Working folder", text: $workingDirectory).textFieldStyle(.roundedBorder)
            HStack {
                TextField("Schedule", text: $scheduleText)
                    .textFieldStyle(.roundedBorder)
                    .font(.system(.body, design: .monospaced))
                Menu("Presets") {
                    Button("Hourly") { scheduleText = "@hourly" }
                    Button("Daily") { scheduleText = "@daily" }
                    Button("Weekdays 9:00") { scheduleText = "@weekdays9am" }
                    Button("Every 30 minutes") { scheduleText = "@every 30m" }
                    Button("Cron: 8:30 on Mondays") { scheduleText = "30 8 * * 1" }
                }
                .fixedSize()
            }
            HStack {
                if let schedule {
                    NexusAgentControlRoomBadge(text: schedule.displayName)
                } else {
                    Label("Not a schedule: use a preset, @every 15m, or five cron fields",
                          systemImage: "exclamationmark.triangle.fill")
                        .font(.caption)
                        .foregroundStyle(.orange)
                }
                Spacer()
                Toggle("Own worktree", isOn: $useWorktree).toggleStyle(.checkbox)
                Button {
                    add()
                } label: {
                    Label("Add", systemImage: "plus")
                }
                .disabled(schedule == nil || name.trimmingCharacters(in: .whitespaces).isEmpty
                          || prompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        if let error = automations.lastError {
            Label(error, systemImage: "exclamationmark.triangle.fill")
                .font(.caption)
                .foregroundStyle(.orange)
        }
        if automations.tasks.isEmpty {
            Text("No scheduled automations yet.").foregroundStyle(.secondary)
        }
        ForEach(automations.tasks) { task in
            NexusAgentControlRoomCard(title: task.name) {
                HStack(spacing: 8) {
                    Image(systemName: task.isEnabled ? "play.fill" : "pause.fill")
                        .foregroundStyle(task.isEnabled ? Color.green : Color.secondary)
                    NexusAgentControlRoomBadge(text: task.schedule.displayName)
                    if task.useWorktree {
                        NexusAgentControlRoomBadge(text: "Worktree", tint: .blue)
                    }
                    Spacer()
                    Toggle("Enabled", isOn: Binding(
                        get: { task.isEnabled },
                        set: { automations.setEnabled($0, id: task.id) }))
                        .toggleStyle(.switch)
                        .labelsHidden()
                }
                Text(task.prompt).font(.callout).lineLimit(3)
                HStack(spacing: 6) {
                    if let lastRun = task.lastRunAt {
                        Image(systemName: task.lastRunSucceeded == false
                              ? "exclamationmark.triangle.fill" : "checkmark.circle.fill")
                            .foregroundStyle(task.lastRunSucceeded == false ? Color.orange : Color.green)
                        Text("Last run \(lastRun, style: .relative) ago")
                    } else {
                        Image(systemName: "clock").foregroundStyle(.secondary)
                        Text("Not run yet")
                    }
                    if task.isEnabled, let next = task.nextRunDate(now: Date(), calendar: automations.calendar) {
                        Text("· next \(next, style: .relative)")
                    }
                    Spacer()
                    Button {
                        onExportLaunchAgent(task, automations.launchdPlistXML(for: task, executablePath: executablePath))
                    } label: {
                        Label("Export LaunchAgent", systemImage: "square.and.arrow.up")
                    }
                    .controlSize(.small)
                    Button(role: .destructive) {
                        automations.remove(id: task.id)
                    } label: {
                        Label("Delete", systemImage: "trash")
                    }
                    .controlSize(.small)
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }
        }
    }

    private func add() {
        guard let schedule else { return }
        automations.upsert(NexusAgentScheduledTask(
            name: name.trimmingCharacters(in: .whitespaces),
            prompt: prompt.trimmingCharacters(in: .whitespacesAndNewlines),
            workingDirectory: workingDirectory.trimmingCharacters(in: .whitespaces),
            providerID: defaultProviderID,
            useWorktree: useWorktree,
            schedule: schedule))
        name = ""
        prompt = ""
    }
}

// MARK: - Remote hosts, mobile companion, sleeping sessions

private struct NexusAgentRemoteAndMobilePane: View {
    @Binding var hosts: [NexusAgentRemoteHost]
    @ObservedObject var hibernation: NexusAgentHibernationManager
    let mobileSnapshots: [NexusAgentMobileSessionSnapshot]
    let onRemoteHostsChange: ([NexusAgentRemoteHost]) -> Void
    let onWake: (NexusAgentHibernatedSessionRecord) -> Void

    @State var label = ""
    @State var sshHost = ""
    @State var sshUser = ""
    @State var remotePath = ""
    @State var localPort = ""
    @State var remotePort = ""

    var body: some View {
        NexusAgentControlRoomCard(title: "SSH remote worktrees") {
            ForEach(hosts) { host in
                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 6) {
                        Image(systemName: "desktopcomputer")
                        Text(host.label).fontWeight(.medium)
                        Circle()
                            .fill(host.isConnected ? Color.green : Color.secondary.opacity(0.4))
                            .frame(width: 7, height: 7)
                        Text(host.isConnected ? "Connected" : "Not connected")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Spacer()
                        Button(role: .destructive) {
                            hosts.removeAll { $0.id == host.id }
                            onRemoteHostsChange(hosts)
                        } label: {
                            Image(systemName: "trash")
                        }
                        .buttonStyle(.borderless)
                        .help("Remove this host")
                    }
                    Text("ssh " + NexusAgentRemoteAndMobileBridge.sshArguments(for: host, remoteCommand: "")
                        .joined(separator: " "))
                        .font(.caption.monospaced())
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                        .lineLimit(2)
                }
                Divider()
            }
            HStack {
                TextField("Label", text: $label)
                TextField("Host", text: $sshHost)
                TextField("User", text: $sshUser)
            }
            .textFieldStyle(.roundedBorder)
            HStack {
                TextField("Remote workspace path", text: $remotePath)
                TextField("Local port", text: $localPort).frame(width: 80)
                TextField("Remote port", text: $remotePort).frame(width: 90)
                Button {
                    addHost()
                } label: {
                    Label("Add host", systemImage: "plus")
                }
                .disabled(sshHost.trimmingCharacters(in: .whitespaces).isEmpty)
            }
            .textFieldStyle(.roundedBorder)
        }
        NexusAgentControlRoomCard(title: "Mobile companion") {
            HStack(spacing: 6) {
                Image(systemName: "iphone")
                Text(mobileSnapshots.isEmpty
                     ? "No sessions shared with the phone."
                     : "\(mobileSnapshots.count) session(s) shared with the phone.")
                Spacer()
                if let latest = mobileSnapshots.map(\.updatedAt).max() {
                    Text("Synced \(latest, style: .relative) ago")
                }
            }
            .font(.callout)
            ForEach(mobileSnapshots) { snapshot in
                HStack(spacing: 6) {
                    VStack(alignment: .leading, spacing: 1) {
                        Text(snapshot.title).lineLimit(1)
                        Text("\(snapshot.providerName) · \(snapshot.status)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    if let branch = snapshot.worktreeBranch {
                        NexusAgentControlRoomBadge(text: branch, tint: .blue)
                    }
                    if snapshot.pendingApprovalSummary != nil {
                        NexusAgentControlRoomBadge(text: "Needs approval", tint: .orange)
                    }
                }
            }
        }
        NexusAgentControlRoomCard(title: "Hibernated sessions") {
            if hibernation.hibernated.isEmpty {
                Text("Nothing is asleep. Idle background sessions sleep after \(Int(hibernation.evaluator.idleThreshold / 60)) minutes.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
            ForEach(hibernation.hibernated) { record in
                HStack(spacing: 8) {
                    Image(systemName: "moon.zzz.fill").foregroundStyle(.indigo)
                    VStack(alignment: .leading, spacing: 1) {
                        Text(record.sessionID).font(.callout.monospaced()).lineLimit(1)
                        Text("\(record.workingDirectory) · asleep since \(record.hibernatedAt, style: .relative)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                    Spacer()
                    Button {
                        if let restored = hibernation.restore(sessionID: record.sessionID) {
                            onWake(restored)
                        }
                    } label: {
                        Label("Wake", systemImage: "sun.max.fill")
                    }
                    .controlSize(.small)
                }
            }
        }
    }

    private func addHost() {
        let host = sshHost.trimmingCharacters(in: .whitespaces)
        let name = label.trimmingCharacters(in: .whitespaces)
        hosts.append(NexusAgentRemoteHost(label: name.isEmpty ? host : name,
                                          sshHost: host,
                                          sshUser: sshUser.trimmingCharacters(in: .whitespaces),
                                          remoteWorkspacePath: remotePath.trimmingCharacters(in: .whitespaces),
                                          portForwardLocalPort: Int(localPort),
                                          portForwardRemotePort: Int(remotePort)))
        onRemoteHostsChange(hosts)
        label = ""
        sshHost = ""
        sshUser = ""
        remotePath = ""
        localPort = ""
        remotePort = ""
    }
}
