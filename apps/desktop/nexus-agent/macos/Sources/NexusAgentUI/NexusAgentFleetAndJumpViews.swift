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

import NexusAgentCore
import SwiftUI

// MARK: - ⌘K Spotlight Jump Palette

/// Spotlight-style `⌘K` Omnibar modal with keyboard navigation across sessions,
/// worktrees, slash commands, agents, accounts, and GitHub/Linear tasks.
@MainActor
public struct NexusAgentJumpPaletteView: View {
    public let targets: [NexusAgentJumpTarget]
    public let onSelect: (NexusAgentJumpTarget) -> Void
    public let onDismiss: () -> Void

    @State private var query = ""
    @State private var selectedIndex = 0

    public init(
        targets: [NexusAgentJumpTarget],
        onSelect: @escaping (NexusAgentJumpTarget) -> Void,
        onDismiss: @escaping () -> Void = {}
    ) {
        self.targets = targets
        self.onSelect = onSelect
        self.onDismiss = onDismiss
    }

    private var matches: [NexusAgentJumpTarget] {
        NexusAgentJumpSearch.filter(query: query, targets: targets, limit: 15)
    }

    public var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 10) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(NexusAgentTheme.warmCoral)

                TextField("Jump to session, worktree, command, agent, or task…", text: $query)
                    .textFieldStyle(.plain)
                    .font(.system(size: 14))
                    .onSubmit {
                        confirmSelection()
                    }
                    .onChange(of: query) { _, _ in
                        selectedIndex = 0
                    }

                Button(action: onDismiss) {
                    Text("ESC")
                        .font(.system(size: 10, weight: .semibold, design: .monospaced))
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 3)
                        .background(Capsule().fill(Color.primary.opacity(0.08)))
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)

            Divider()

            if matches.isEmpty {
                VStack(spacing: 6) {
                    Image(systemName: "magnifyingglass")
                        .font(.system(size: 20))
                        .foregroundStyle(.secondary)
                    Text("No matching jump targets")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 28)
            } else {
                ScrollView {
                    LazyVStack(spacing: 4) {
                        ForEach(Array(matches.enumerated()), id: \.element.id) { index, target in
                            jumpRow(target: target, isSelected: index == selectedIndex)
                                .onTapGesture {
                                    selectedIndex = index
                                    onSelect(target)
                                }
                        }
                    }
                    .padding(8)
                }
                .frame(maxHeight: 340)
            }
        }
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(.ultraThinMaterial)
                .overlay(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .strokeBorder(NexusAgentTheme.cardBorder, lineWidth: 1)
                )
        )
        .onKeyPress(.upArrow) {
            moveSelection(by: -1)
            return .handled
        }
        .onKeyPress(.downArrow) {
            moveSelection(by: 1)
            return .handled
        }
        .onKeyPress(.return) {
            confirmSelection()
            return .handled
        }
        .onKeyPress(.escape) {
            onDismiss()
            return .handled
        }
    }

    @ViewBuilder
    private func jumpRow(target: NexusAgentJumpTarget, isSelected: Bool) -> some View {
        HStack(spacing: 10) {
            kindSymbol(for: target.kind)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(isSelected ? NexusAgentTheme.warmCoral : .secondary)
                .frame(width: 24, height: 24)

            VStack(alignment: .leading, spacing: 2) {
                Text(target.title)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                if !target.subtitle.isEmpty {
                    Text(target.subtitle)
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }

            Spacer()

            if let badge = target.badge, !badge.isEmpty {
                Text(badge)
                    .font(.system(size: 10, weight: .semibold, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Capsule().fill(Color.primary.opacity(0.08)))
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(isSelected ? NexusAgentTheme.warmCoral.opacity(0.16) : Color.clear)
        )
    }

    @ViewBuilder
    private func kindSymbol(for kind: NexusAgentJumpTarget.Kind) -> some View {
        switch kind {
        case .session:
            Image(systemName: "clock")
        case .worktree:
            Image(systemName: "arrow.triangle.branch")
        case .slashCommand:
            Image(systemName: "bolt.fill")
        case .agentPreset:
            Image(systemName: "terminal")
        case .account:
            Image(systemName: "person.crop.circle.badge.checkmark")
        case .task:
            Image(systemName: "checklist")
        case .file:
            Image(systemName: "doc.text")
        }
    }

    private func moveSelection(by delta: Int) {
        guard !matches.isEmpty else { return }
        let next = (selectedIndex + delta + matches.count) % matches.count
        selectedIndex = next
    }

    private func confirmSelection() {
        guard matches.indices.contains(selectedIndex) else { return }
        onSelect(matches[selectedIndex])
    }
}

// MARK: - Unified Agent Inbox & Fleet Telemetry View

/// Displays the Fleet Telemetry header and filterable Unified Agent Inbox rows.
@MainActor
public struct NexusAgentUnifiedInboxView: View {
    public enum Filter: String, CaseIterable, Identifiable, Sendable {
        case all = "All"
        case approvals = "Approvals"
        case completed = "Completed"
        case failed = "Failed"

        public var id: String { rawValue }
    }

    @ObservedObject private var inbox: NexusAgentInboxCenter
    public let onJumpToSession: (NexusAgentInboxEntry) -> Void
    @State private var activeFilter: Filter = .all

    public init(
        inbox: NexusAgentInboxCenter,
        onJumpToSession: @escaping (NexusAgentInboxEntry) -> Void = { _ in }
    ) {
        self.inbox = inbox
        self.onJumpToSession = onJumpToSession
    }

    private var filteredEntries: [NexusAgentInboxEntry] {
        inbox.entries.filter { entry in
            switch activeFilter {
            case .all:
                return true
            case .approvals:
                return entry.category == .needsApproval || entry.category == .waitingForInput
            case .completed:
                return entry.category == .completed
            case .failed:
                return entry.category == .failed
            }
        }
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            telemetryHeader

            HStack(spacing: 6) {
                ForEach(Filter.allCases) { filter in
                    Button {
                        activeFilter = filter
                    } label: {
                        Text(filter.rawValue)
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(activeFilter == filter ? Color.white : Color.secondary)
                            .padding(.horizontal, 9)
                            .padding(.vertical, 4)
                            .background(
                                Capsule().fill(
                                    activeFilter == filter
                                        ? NexusAgentTheme.warmCoral
                                        : Color.primary.opacity(0.07)
                                )
                            )
                    }
                    .buttonStyle(.plain)
                }

                Spacer()

                if inbox.unreadCount > 0 {
                    Button {
                        inbox.markAllRead()
                    } label: {
                        Label("Mark Read", systemImage: "envelope.open")
                            .font(.system(size: 11, weight: .medium))
                    }
                    .buttonStyle(.plain)
                }

                if !inbox.entries.isEmpty {
                    Button {
                        inbox.clearResolved()
                    } label: {
                        Label("Clear", systemImage: "trash")
                            .font(.system(size: 11, weight: .medium))
                    }
                    .buttonStyle(.plain)
                }
            }

            if filteredEntries.isEmpty {
                HStack(spacing: 8) {
                    Image(systemName: "tray.full")
                        .foregroundStyle(.secondary)
                    Text("Inbox is clear")
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, alignment: .center)
                .padding(.vertical, 20)
            } else {
                ScrollView {
                    LazyVStack(spacing: 6) {
                        ForEach(filteredEntries) { entry in
                            inboxRow(entry)
                        }
                    }
                }
            }
        }
        .padding(12)
    }

    private var telemetryHeader: some View {
        HStack(spacing: 10) {
            statCard(title: "Agents Spawned", value: "\(inbox.stats.agentsSpawned)") {
                Image(systemName: "terminal")
            }
            statCard(title: "Agent Time", value: inbox.stats.formattedAgentTime) {
                Image(systemName: "clock")
            }
            statCard(title: "PRs Created", value: "\(inbox.stats.prsCreated)") {
                Image(systemName: "arrow.triangle.branch")
            }
        }
    }

    private func statCard<Icon: View>(
        title: String,
        value: String,
        @ViewBuilder symbol: () -> Icon
    ) -> some View {
        HStack(spacing: 8) {
            symbol()
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(NexusAgentTheme.warmCoral)
            VStack(alignment: .leading, spacing: 1) {
                Text(value)
                    .font(.system(size: 13, weight: .bold, design: .rounded))
                Text(title)
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
        }
        .padding(8)
        .frame(maxWidth: .infinity)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(NexusAgentTheme.cardFill)
                .overlay(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .strokeBorder(NexusAgentTheme.cardBorder, lineWidth: 0.5)
                )
        )
    }

    @ViewBuilder
    private func inboxRow(_ entry: NexusAgentInboxEntry) -> some View {
        Button {
            inbox.markRead(id: entry.id)
            onJumpToSession(entry)
        } label: {
            HStack(alignment: .top, spacing: 10) {
                categorySymbol(entry.category)
                    .font(.system(size: 13, weight: .semibold))
                    .padding(.top, 2)

                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 6) {
                        Text(entry.title)
                            .font(.system(size: 12, weight: entry.isRead ? .medium : .bold))
                            .foregroundStyle(.primary)
                        if let worktree = entry.worktreeName, !worktree.isEmpty {
                            Text(worktree)
                                .font(.system(size: 10, design: .monospaced))
                                .foregroundStyle(.secondary)
                                .padding(.horizontal, 5)
                                .padding(.vertical, 1)
                                .background(Capsule().fill(Color.primary.opacity(0.08)))
                        }
                    }
                    Text(entry.summary)
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }

                Spacer()

                Image(systemName: "arrow.up.right.square")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }
            .padding(9)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(entry.isRead ? Color.clear : NexusAgentTheme.warmCoral.opacity(0.09))
                    .overlay(
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .strokeBorder(NexusAgentTheme.cardBorder, lineWidth: 0.5)
                    )
            )
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private func categorySymbol(_ category: NexusAgentInboxEntry.Category) -> some View {
        switch category {
        case .needsApproval, .waitingForInput:
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.orange)
        case .completed:
            Image(systemName: "checkmark.circle.fill")
                .foregroundStyle(.green)
        case .failed:
            Image(systemName: "xmark.circle.fill")
                .foregroundStyle(.red)
        }
    }
}

// MARK: - GitHub & Linear Tasks Drawer View

/// Lists GitHub PRs, GitHub Issues, and Linear tasks with CI status pills and one-click worktree agent spawn.
@MainActor
public struct NexusAgentTasksDrawerView: View {
    public let tasks: [NexusAgentTaskItem]
    public let onStartWorktreeAgent: (NexusAgentTaskItem) -> Void
    public let onRefresh: (() -> Void)?

    public init(
        tasks: [NexusAgentTaskItem],
        onStartWorktreeAgent: @escaping (NexusAgentTaskItem) -> Void,
        onRefresh: (() -> Void)? = nil
    ) {
        self.tasks = tasks
        self.onStartWorktreeAgent = onStartWorktreeAgent
        self.onRefresh = onRefresh
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Label("GitHub & Linear Tasks", systemImage: "checklist")
                    .font(.system(size: 13, weight: .semibold))
                Spacer()
                if let onRefresh {
                    Button {
                        onRefresh()
                    } label: {
                        Image(systemName: "arrow.clockwise")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                    .help("Refresh tasks")
                }
                Text("\(tasks.count)")
                    .font(.system(size: 11, weight: .semibold, design: .monospaced))
                    .foregroundStyle(.secondary)
            }

            if tasks.isEmpty {
                Text("No open pull requests or issues found.")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                    .padding(.vertical, 16)
            } else {
                ScrollView {
                    LazyVStack(spacing: 6) {
                        ForEach(tasks) { item in
                            taskRow(item)
                        }
                    }
                }
            }
        }
        .padding(12)
    }

    private func taskRow(_ item: NexusAgentTaskItem) -> some View {
        HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text(item.numberOrKey)
                        .font(.system(size: 11, weight: .bold, design: .monospaced))
                        .foregroundStyle(NexusAgentTheme.warmCoral)
                    Text(item.title)
                        .font(.system(size: 12, weight: .medium))
                        .lineLimit(1)
                }

                HStack(spacing: 6) {
                    Text(item.statusLabel)
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(.secondary)

                    if let ciPassing = item.ciPassing {
                        HStack(spacing: 3) {
                            if ciPassing {
                                Image(systemName: "checkmark.circle.fill")
                                    .foregroundStyle(.green)
                                Text("CI Passing")
                            } else {
                                Image(systemName: "xmark.circle.fill")
                                    .foregroundStyle(.red)
                                Text("CI Failing")
                            }
                        }
                        .font(.system(size: 10, weight: .medium))
                    }

                    Text(NexusAgentTaskService.suggestedBranchName(for: item))
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }

            Spacer()

            Button {
                onStartWorktreeAgent(item)
            } label: {
                Label("Start Worktree Agent", systemImage: "arrow.triangle.branch")
                    .font(.system(size: 11, weight: .semibold))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 5)
                    .background(
                        Capsule()
                            .fill(NexusAgentTheme.warmCoral.opacity(0.15))
                    )
            }
            .buttonStyle(.plain)
        }
        .padding(9)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(NexusAgentTheme.cardFill)
                .overlay(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .strokeBorder(NexusAgentTheme.cardBorder, lineWidth: 0.5)
                )
        )
    }
}

// MARK: - Multi-Account Switcher & 27-Agent Catalog View

/// Shows the active account switcher with 5h and 7d usage bars plus the searchable 27-Agent CLI Catalog.
@MainActor
public struct NexusAgentAccountAndCatalogView: View {
    @ObservedObject private var accountManager: NexusAgentAccountManager
    public let installedPresetIDs: Set<String>
    public let onEnablePreset: (NexusAgentCatalogPreset) -> Void
    @State private var searchQuery = ""

    public init(
        accountManager: NexusAgentAccountManager,
        installedPresetIDs: Set<String> = [],
        onEnablePreset: @escaping (NexusAgentCatalogPreset) -> Void = { _ in }
    ) {
        self.accountManager = accountManager
        self.installedPresetIDs = installedPresetIDs
        self.onEnablePreset = onEnablePreset
    }

    private var filteredPresets: [NexusAgentCatalogPreset] {
        let q = searchQuery.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !q.isEmpty else { return NexusAgentCatalog.allPresets }
        return NexusAgentCatalog.allPresets.filter {
            $0.name.lowercased().contains(q)
                || $0.executableName.lowercased().contains(q)
                || $0.id.lowercased().contains(q)
        }
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            accountsSection
            Divider()
            catalogSection
        }
        .padding(12)
    }

    private var accountsSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("Accounts & 5h / 7d Usage", systemImage: "person.crop.circle.badge.checkmark")
                .font(.system(size: 13, weight: .semibold))

            if accountManager.profiles.isEmpty {
                Text("No saved account profiles yet.")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            } else {
                ForEach(accountManager.profiles) { profile in
                    accountRow(profile)
                }
            }
        }
    }

    private func accountRow(_ profile: NexusAgentAccountProfile) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                VStack(alignment: .leading, spacing: 1) {
                    HStack(spacing: 6) {
                        Text(profile.accountLabel)
                            .font(.system(size: 12, weight: .semibold))
                        Text(profile.providerName)
                            .font(.system(size: 10, weight: .medium))
                            .foregroundStyle(.secondary)
                        if let tier = profile.quota?.planTier, !tier.isEmpty {
                            Text(tier)
                                .font(.system(size: 9, weight: .bold))
                                .padding(.horizontal, 5)
                                .padding(.vertical, 1)
                                .background(Capsule().fill(Color.primary.opacity(0.08)))
                        }
                    }
                    Text(profile.emailOrHandle)
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)
                }

                Spacer()

                if profile.isActive {
                    Label("Active", systemImage: "checkmark")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(.green)
                } else {
                    Button("Switch") {
                        _ = accountManager.switchAccount(id: profile.id)
                    }
                    .buttonStyle(.plain)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(NexusAgentTheme.warmCoral)
                }
            }

            if let quota = profile.quota {
                HStack(spacing: 12) {
                    quotaMeter(
                        label: "5h",
                        percent: quota.fiveHourUsedPercent,
                        resetText: quota.fiveHourResetCountdown()
                    )
                    quotaMeter(
                        label: "7d",
                        percent: quota.sevenDayUsedPercent,
                        resetText: quota.sevenDayResetCountdown()
                    )
                }
            }
        }
        .padding(9)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(NexusAgentTheme.cardFill)
                .overlay(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .strokeBorder(NexusAgentTheme.cardBorder, lineWidth: 0.5)
                )
        )
    }

    private func quotaMeter(label: String, percent: Double, resetText: String) -> some View {
        HStack(spacing: 5) {
            Image(systemName: "gauge.with.dots.needle.67percent")
                .font(.system(size: 10))
                .foregroundStyle(percent >= 80 ? .orange : .secondary)
            Text("\(label): \(Int(percent.rounded()))%")
                .font(.system(size: 10, weight: .semibold, design: .monospaced))
            Text("(\(resetText))")
                .font(.system(size: 10))
                .foregroundStyle(.secondary)
        }
    }

    private var catalogSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Label("CLI Agent Catalog (\(NexusAgentCatalog.allPresets.count))", systemImage: "terminal")
                    .font(.system(size: 13, weight: .semibold))
                Spacer()
            }

            HStack(spacing: 6) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                TextField("Filter 27+ CLI agents…", text: $searchQuery)
                    .textFieldStyle(.plain)
                    .font(.system(size: 12))
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 5)
            .background(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(Color.primary.opacity(0.06))
            )

            ScrollView {
                LazyVStack(spacing: 5) {
                    ForEach(filteredPresets) { preset in
                        HStack(spacing: 8) {
                            VStack(alignment: .leading, spacing: 2) {
                                HStack(spacing: 6) {
                                    Text(preset.name)
                                        .font(.system(size: 12, weight: .medium))
                                    Text(preset.executableName)
                                        .font(.system(size: 10, design: .monospaced))
                                        .foregroundStyle(.secondary)
                                    if installedPresetIDs.contains(preset.id) {
                                        Text("Installed")
                                            .font(.system(size: 9, weight: .semibold))
                                            .foregroundStyle(.green)
                                    }
                                }
                                Text(preset.commandTemplate)
                                    .font(.system(size: 10, design: .monospaced))
                                    .foregroundStyle(.secondary)
                                    .lineLimit(1)
                            }

                            Spacer()

                            Button {
                                onEnablePreset(preset)
                            } label: {
                                Label("Enable in Nexus", systemImage: "plus.circle")
                                    .font(.system(size: 11, weight: .semibold))
                                    .foregroundStyle(NexusAgentTheme.warmCoral)
                            }
                            .buttonStyle(.plain)
                        }
                        .padding(.horizontal, 8)
                        .padding(.vertical, 6)
                        .background(
                            RoundedRectangle(cornerRadius: 7, style: .continuous)
                                .fill(NexusAgentTheme.cardFill)
                        )
                    }
                }
            }
            .frame(maxHeight: 260)
        }
    }
}
