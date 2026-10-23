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
// Shared by the standalone Nexus Agent app and the Nexus Agent feature of the
// Vitruvian desktop app. Written for Vitruvian and released under MIT by its
// copyright holder on 2026-10-09 (apps/desktop/vitruvian/UPSTREAM.md).

import NexusAgentCore
import SwiftUI

// MARK: - Multi-Agent Race Mode View

/// Side-by-side Multi-Agent Race Mode view allowing 2–4 contenders to race in isolated worktrees.
public struct NexusAgentRaceModeView: View {
    @ObservedObject private var raceSession: NexusAgentRaceSession
    private let availableProviders: [NexusAgentCLIProvider]
    private let onPickWinner: (UUID) -> Void
    private let onStartRace: ([(provider: NexusAgentCLIProvider, model: String)]) -> Void

    @State private var selectedSpecs: [(provider: NexusAgentCLIProvider, model: String)]

    public init(
        raceSession: NexusAgentRaceSession,
        availableProviders: [NexusAgentCLIProvider] = NexusAgentCLIProvider.builtIns,
        initialSpecs: [(provider: NexusAgentCLIProvider, model: String)] = [],
        onStartRace: @escaping ([(provider: NexusAgentCLIProvider, model: String)]) -> Void = { _ in },
        onPickWinner: @escaping (UUID) -> Void = { _ in }
    ) {
        self.raceSession = raceSession
        self.availableProviders = availableProviders
        self.onStartRace = onStartRace
        self.onPickWinner = onPickWinner
        if initialSpecs.count >= 2 {
            _selectedSpecs = State(initialValue: Array(initialSpecs.prefix(4)))
        } else {
            let defaults = Array(availableProviders.prefix(2)).map { ($0, "") }
            _selectedSpecs = State(initialValue: defaults)
        }
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            headerBar
            if raceSession.contenders.isEmpty {
                slotSelectorBar
            } else {
                contendersGrid
            }
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(NexusAgentTheme.cardFill)
                .overlay(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .strokeBorder(NexusAgentTheme.cardBorder, lineWidth: 1)
                )
        )
    }

    private var headerBar: some View {
        HStack(spacing: 8) {
            Image(systemName: "flag.checkered")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(NexusAgentTheme.warmCoral)
            Text("Multi-Agent Race Mode")
                .font(.system(size: 13, weight: .semibold))
            Spacer()
            if raceSession.isRunning {
                HStack(spacing: 4) {
                    ProgressView()
                        .controlSize(.small)
                    Text("Racing…")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    private var slotSelectorBar: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                ForEach(Array(selectedSpecs.enumerated()), id: \.offset) { index, spec in
                    HStack(spacing: 6) {
                        Image(systemName: "arrow.triangle.branch")
                            .font(.system(size: 10))
                            .foregroundStyle(NexusAgentTheme.warmCoral)
                        Text(spec.provider.name)
                            .font(.system(size: 11, weight: .medium))
                            .lineLimit(1)
                        if selectedSpecs.count > 2 {
                            Button {
                                selectedSpecs.remove(at: index)
                            } label: {
                                Image(systemName: "xmark.circle")
                                    .font(.system(size: 11))
                                    .foregroundStyle(.secondary)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 5)
                    .background(
                        Capsule()
                            .fill(Color.primary.opacity(0.06))
                    )
                }

                if selectedSpecs.count < 4, let nextProvider = availableProviders.first {
                    Button {
                        selectedSpecs.append((nextProvider, ""))
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: "plus")
                                .font(.system(size: 10, weight: .bold))
                            Text("Add Contender")
                                .font(.system(size: 11, weight: .medium))
                        }
                        .padding(.horizontal, 8)
                        .padding(.vertical, 5)
                        .background(
                            Capsule()
                                .strokeBorder(NexusAgentTheme.cardBorder, lineWidth: 1)
                        )
                    }
                    .buttonStyle(.plain)
                }

                Spacer()

                Button {
                    onStartRace(selectedSpecs)
                } label: {
                    HStack(spacing: 5) {
                        Image(systemName: "play.fill")
                            .font(.system(size: 10))
                        Text("Start Race")
                            .font(.system(size: 11, weight: .semibold))
                    }
                    .foregroundStyle(.white)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(
                        Capsule()
                            .fill(NexusAgentTheme.gradient)
                    )
                }
                .buttonStyle(.plain)
                .disabled(selectedSpecs.count < 2)
            }
        }
    }

    private var contendersGrid: some View {
        HStack(alignment: .top, spacing: 10) {
            ForEach(raceSession.contenders) { contender in
                contenderCard(contender)
            }
        }
    }

    private func contenderCard(_ contender: NexusAgentRaceContender) -> some View {
        let isWinner = contender.status == .winner
        return VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                statusIcon(for: contender.status)
                VStack(alignment: .leading, spacing: 1) {
                    Text(contender.provider.name)
                        .font(.system(size: 12, weight: .semibold))
                        .lineLimit(1)
                    Text(contender.model.isEmpty ? "default" : contender.model)
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                Spacer()
                if let durationMs = contender.durationMs {
                    HStack(spacing: 3) {
                        Image(systemName: "clock")
                            .font(.system(size: 9))
                        Text(String(format: "%.1fs", Double(durationMs) / 1000.0))
                            .font(.system(size: 10, design: .monospaced))
                    }
                    .foregroundStyle(.secondary)
                }
            }

            HStack(spacing: 8) {
                HStack(spacing: 3) {
                    Image(systemName: "arrow.triangle.branch")
                        .font(.system(size: 9))
                    Text(contender.worktree.branchName)
                        .font(.system(size: 10, design: .monospaced))
                        .lineLimit(1)
                }
                .foregroundStyle(.secondary)

                Spacer()

                HStack(spacing: 4) {
                    Text("+\(contender.addedLines)")
                        .font(.system(size: 10, weight: .semibold, design: .monospaced))
                        .foregroundStyle(.green)
                    Text("-\(contender.removedLines)")
                        .font(.system(size: 10, weight: .semibold, design: .monospaced))
                        .foregroundStyle(.red)
                }
            }

            Text(contender.responseText.isEmpty ? "Waiting for output…" : contender.responseText)
                .font(.system(size: 11))
                .foregroundStyle(contender.responseText.isEmpty ? .secondary : .primary)
                .lineLimit(4)
                .frame(maxWidth: .infinity, minHeight: 54, alignment: .topLeading)
                .padding(8)
                .background(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(Color.black.opacity(0.15))
                )

            if raceSession.winnerID == nil {
                Button {
                    onPickWinner(contender.id)
                } label: {
                    HStack(spacing: 5) {
                        Image(systemName: "flag.checkered")
                            .font(.system(size: 10, weight: .semibold))
                        Text("Pick Winner")
                            .font(.system(size: 11, weight: .semibold))
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 5)
                    .foregroundStyle(.white)
                    .background(
                        RoundedRectangle(cornerRadius: 7, style: .continuous)
                            .fill(NexusAgentTheme.gradient)
                    )
                }
                .buttonStyle(.plain)
            } else if isWinner {
                HStack(spacing: 5) {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 11))
                        .foregroundStyle(.green)
                    Text("Selected Winner")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(.green)
                }
            }
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(NexusAgentTheme.cardFill)
                .overlay(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .strokeBorder(
                            isWinner ? NexusAgentTheme.warmCoral : NexusAgentTheme.cardBorder,
                            lineWidth: isWinner ? 1.5 : 1
                        )
                )
        )
    }

    @ViewBuilder
    private func statusIcon(for status: NexusAgentRaceContender.Status) -> some View {
        switch status {
        case .queued, .running:
            Image(systemName: "clock.arrow.circlepath")
                .font(.system(size: 12))
                .foregroundStyle(NexusAgentTheme.warmCoral)
        case .completed, .winner:
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 12))
                .foregroundStyle(.green)
        case .failed, .discarded:
            Image(systemName: "xmark.circle")
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
        }
    }
}

// MARK: - Checkpoint Timeline & Attribution View

/// Displays chronological turn checkpoints with AI vs human attribution pills and per-turn Rewind buttons.
public struct NexusAgentCheckpointTimelineView: View {
    @ObservedObject private var timeline: NexusAgentCheckpointTimeline
    private let onRewind: (UUID) -> Void

    public init(
        timeline: NexusAgentCheckpointTimeline,
        onRewind: @escaping (UUID) -> Void = { _ in }
    ) {
        self.timeline = timeline
        self.onRewind = onRewind
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            headerRow
            ForEach(timeline.entries) { entry in
                entryRow(entry)
            }
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(NexusAgentTheme.cardFill)
                .overlay(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .strokeBorder(NexusAgentTheme.cardBorder, lineWidth: 1)
                )
        )
    }

    private var headerRow: some View {
        let overall = timeline.overallAttribution
        return HStack(spacing: 8) {
            Image(systemName: "clock.arrow.circlepath")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(NexusAgentTheme.warmCoral)
            Text("Checkpoint Timeline")
                .font(.system(size: 12, weight: .semibold))
            Spacer()
            attributionPill(
                aiPercentage: overall.aiAttributionPercentage,
                aiLines: overall.totalAILines,
                humanLines: overall.totalHumanLines
            )
        }
    }

    private func entryRow(_ entry: NexusAgentCheckpointEntry) -> some View {
        HStack(spacing: 10) {
            Text("#\(entry.turnIndex)")
                .font(.system(size: 10, weight: .bold, design: .monospaced))
                .foregroundStyle(NexusAgentTheme.warmCoral)
                .frame(width: 26, alignment: .leading)

            VStack(alignment: .leading, spacing: 2) {
                Text(entry.promptPreview)
                    .font(.system(size: 11, weight: .medium))
                    .lineLimit(1)
                Text(entry.commitOrStashRef)
                    .font(.system(size: 9, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer()

            attributionPill(
                aiPercentage: entry.aiAttributionPercentage,
                aiLines: entry.aiAddedLines + entry.aiRemovedLines,
                humanLines: entry.humanAddedLines + entry.humanRemovedLines
            )

            Button {
                onRewind(entry.id)
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: "arrow.uturn.backward")
                        .font(.system(size: 9, weight: .semibold))
                    Text("Rewind")
                        .font(.system(size: 10, weight: .semibold))
                }
                .foregroundStyle(NexusAgentTheme.warmCoral)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(
                    Capsule()
                        .fill(NexusAgentTheme.warmCoral.opacity(0.14))
                )
            }
            .buttonStyle(.plain)
        }
        .padding(8)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(Color.primary.opacity(0.04))
        )
    }

    private func attributionPill(aiPercentage: Int, aiLines: Int, humanLines: Int) -> some View {
        HStack(spacing: 6) {
            HStack(spacing: 3) {
                Image(systemName: "sparkles")
                    .font(.system(size: 9))
                Text("\(aiPercentage)% AI (\(aiLines))")
                    .font(.system(size: 9, weight: .semibold))
            }
            .foregroundStyle(NexusAgentTheme.warmCoral)

            HStack(spacing: 3) {
                Image(systemName: "person.fill")
                    .font(.system(size: 9))
                Text("\(humanLines)")
                    .font(.system(size: 9, weight: .medium))
            }
            .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 7)
        .padding(.vertical, 3)
        .background(
            Capsule()
                .fill(Color.primary.opacity(0.06))
        )
    }
}

// MARK: - Multi-Repo Parent Workspace Header Badge

/// Compact header badge showing when a multi-repo parent workspace is active and listing child repositories in a popover.
public struct NexusAgentMultiRepoHeaderBadge: View {
    private let workspace: NexusAgentMultiRepoWorkspace
    @State private var isPopoverPresented = false

    public init(workspace: NexusAgentMultiRepoWorkspace) {
        self.workspace = workspace
    }

    public var body: some View {
        if workspace.isMultiRepoActive {
            Button {
                isPopoverPresented.toggle()
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: "folder.fill")
                        .font(.system(size: 9))
                    Text("\(workspace.childRepositories.count) repos")
                        .font(.system(size: 10, weight: .semibold))
                }
                .foregroundStyle(NexusAgentTheme.warmCoral)
                .padding(.horizontal, 7)
                .padding(.vertical, 3)
                .background(
                    Capsule()
                        .fill(NexusAgentTheme.warmCoral.opacity(0.14))
                )
            }
            .buttonStyle(.plain)
            .popover(isPresented: $isPopoverPresented, arrowEdge: .bottom) {
                VStack(alignment: .leading, spacing: 6) {
                    HStack(spacing: 5) {
                        Image(systemName: "folder.fill")
                            .font(.system(size: 11))
                            .foregroundStyle(NexusAgentTheme.warmCoral)
                        Text("Multi-Repo Workspace")
                            .font(.system(size: 12, weight: .semibold))
                    }
                    Divider()
                    ForEach(workspace.childRepositories, id: \.self) { repo in
                        HStack(spacing: 6) {
                            Image(systemName: "arrow.triangle.branch")
                                .font(.system(size: 10))
                                .foregroundStyle(.secondary)
                            Text((repo as NSString).lastPathComponent)
                                .font(.system(size: 11, weight: .medium))
                            Spacer()
                            Text(repo)
                                .font(.system(size: 10, design: .monospaced))
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                .padding(12)
                .frame(minWidth: 260)
            }
        }
    }
}
