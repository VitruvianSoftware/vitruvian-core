// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 VitruvianSoftware

import AppKit
import SwiftUI
import VitruvianCore
import VitruvianDesign
import VitruvianServices

/// The GitHub Notch Quick Access drawer: displaying live repository pipeline metrics
/// (CI workflow runs, merge queue, and PR health) directly in the Notch drawer.
package struct NotchGitHubView: View {
    package let size: CGSize

    @ObservedObject private var gitHub = GitHubService.shared
    @ObservedObject private var auth = GitHubAuthService.shared
    @ObservedObject private var l10n = L10n.shared
    @State private var selectedRepoKey: RepoKey? = nil
    @State private var isRerunning = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var text: NotchGitHubStrings { FeatureStrings.notchGitHub(l10n.language) }

    private var currentRepo: RepoKey {
        if let selected = selectedRepoKey, gitHub.watchedRepositories.contains(selected) {
            return selected
        }
        return gitHub.watchedRepositories.first ?? RepoKey(owner: "VitruvianSoftware", name: "vitruvian-core")
    }

    private var repoState: RepoState? {
        gitHub.states[currentRepo]
    }

    package var body: some View {
        VStack(spacing: 10) {
            headerBar

            if !auth.isSignedIn {
                signedOutView
            } else if let state = repoState {
                contentGrid(state: state)
            } else if gitHub.isRefreshing {
                loadingView
            } else {
                emptyRepoView
            }
        }
        .padding(.horizontal, 16)
        .padding(.top, 8)
        .padding(.bottom, 12)
        .frame(width: size.width, height: size.height, alignment: .top)
    }

    // MARK: - Header Bar

    private var headerBar: some View {
        HStack(spacing: 8) {
            // Repo Selector Badge
            Menu {
                ForEach(gitHub.watchedRepositories, id: \.self) { repo in
                    Button {
                        selectedRepoKey = repo
                    } label: {
                        HStack {
                            Text(repo.fullName)
                            if repo == currentRepo {
                                Image(systemName: "checkmark")
                            }
                        }
                    }
                }
            } label: {
                HStack(spacing: 5) {
                    Image(systemName: "folder.fill")
                        .font(.system(size: 11))
                        .foregroundStyle(Color.accentColor)
                    Text(currentRepo.fullName)
                        .font(.system(size: 12, weight: .semibold))
                        .lineLimit(1)
                    if gitHub.watchedRepositories.count > 1 {
                        Image(systemName: "chevron.down")
                            .font(.system(size: 9, weight: .bold))
                            .foregroundStyle(.secondary)
                    }
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(Color.white.opacity(0.08), in: Capsule())
            }
            .menuStyle(.borderlessButton)
            .fixedSize()

            // Branch Pill with Commit SHA
            if let state = repoState {
                HStack(spacing: 4) {
                    Image(systemName: "arrow.triangle.branch")
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)
                    Text(state.defaultBranch)
                        .font(.system(size: 11, weight: .medium))
                        .lineLimit(1)
                    if let sha = state.headSHA {
                        Text("@ \(String(sha.prefix(7)))")
                            .font(.system(size: 10, weight: .regular, design: .monospaced))
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(Color.white.opacity(0.06), in: Capsule())
            }

            Spacer()

            // Refresh Button
            Button {
                gitHub.refresh()
            } label: {
                Image(systemName: "arrow.clockwise")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.secondary)
                    .rotationEffect(gitHub.isRefreshing ? .degrees(360) : .zero)
                    .animation(gitHub.isRefreshing && !reduceMotion ? .linear(duration: 1).repeatForever(autoreverses: false) : .default, value: gitHub.isRefreshing)
            }
            .buttonStyle(.plain)
            .help("Refresh GitHub Pipeline")

            // External Link to Repo
            Button {
                if let url = URL(string: "https://github.com/\(currentRepo.fullName)") {
                    NSWorkspace.shared.open(url)
                }
            } label: {
                Image(systemName: "arrow.up.forward.app")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
            .help("Open in GitHub")
        }
    }

    // MARK: - Metrics Grid

    private func contentGrid(state: RepoState) -> some View {
        ScrollView(.vertical, showsIndicators: false) {
            VStack(spacing: 10) {
                HStack(alignment: .top, spacing: 10) {
                    workflowRunsCard(state: state)
                        .frame(maxWidth: .infinity)

                    mergeQueueCard(state: state)
                        .frame(maxWidth: .infinity)
                }

                openPRsCard(state: state)
            }
            .padding(.bottom, 6)
        }
    }

    // MARK: - Card 1: Workflow Runs Card

    private func workflowRunsCard(state: RepoState) -> some View {
        let checks = Array(state.checks.values)
        let passing = checks.filter { $0.status == .completed && $0.conclusion?.isPassing == true }.count
        let running = checks.filter { $0.status.isRunning && $0.conclusion?.isFailing != true }.count
        let failing = checks.filter { $0.conclusion?.isFailing == true }.count

        return VStack(alignment: .leading, spacing: 8) {
            HStack {
                Label("Workflow Runs", systemImage: "play.circle.fill")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.secondary)
                Spacer()

                if failing > 0 {
                    Button {
                        rerunFailedChecks(state: state)
                    } label: {
                        HStack(spacing: 3) {
                            Image(systemName: "arrow.clockwise")
                            Text("Rerun")
                        }
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(.red)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Color.red.opacity(0.12), in: Capsule())
                    }
                    .buttonStyle(.plain)
                    .help("Rerun failed checks")
                }
            }

            // Summary Pills
            HStack(spacing: 6) {
                statusBadge(count: passing, label: "passing", systemImage: "checkmark.circle.fill", color: .green)
                if running > 0 {
                    statusBadge(count: running, label: "running", systemImage: "arrow.triangle.2.circlepath", color: .orange)
                }
                if failing > 0 {
                    statusBadge(count: failing, label: "failing", systemImage: "xmark.circle.fill", color: .red)
                }
            }

            // Recent Checks List
            if checks.isEmpty {
                Text("No check runs reported")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .padding(.vertical, 4)
            } else {
                VStack(spacing: 4) {
                    ForEach(checks.prefix(4), id: \.key) { run in
                        checkRow(run: run)
                    }
                }
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .modifier(NotchControlSurface(cornerRadius: 14))
    }

    private func checkRow(run: CheckRun) -> some View {
        Button {
            if let url = run.htmlURL {
                NSWorkspace.shared.open(url)
            }
        } label: {
            HStack(spacing: 6) {
                if run.conclusion?.isFailing == true {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.red)
                } else if run.status.isRunning {
                    Image(systemName: "arrow.triangle.2.circlepath")
                        .foregroundStyle(.orange)
                } else if run.conclusion?.isPassing == true {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                } else {
                    Image(systemName: "circle.dashed")
                        .foregroundStyle(.secondary)
                }

                Text(run.name)
                    .font(.system(size: 11, weight: .medium))
                    .lineLimit(1)
                    .foregroundStyle(.primary)

                Spacer()

                Image(systemName: "chevron.right")
                    .font(.system(size: 8, weight: .semibold))
                    .foregroundStyle(.tertiary)
            }
            .padding(.vertical, 3)
            .padding(.horizontal, 4)
            .background(Color.white.opacity(0.03), in: RoundedRectangle(cornerRadius: 6))
        }
        .buttonStyle(.plain)
    }

    // MARK: - Card 2: Merge Queue Card

    private func mergeQueueCard(state: RepoState) -> some View {
        // Find checks or branches associated with merge queue
        let queueChecks = state.checks.values.filter {
            $0.name.localizedCaseInsensitiveContains("queue") ||
            $0.key.localizedCaseInsensitiveContains("gh-readonly-queue")
        }

        return VStack(alignment: .leading, spacing: 8) {
            HStack {
                Label("Merge Queue", systemImage: "tray.full.fill")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.secondary)
                Spacer()

                if queueChecks.isEmpty {
                    Text("Clean")
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundStyle(.green)
                        .padding(.horizontal, 5)
                        .padding(.vertical, 2)
                        .background(Color.green.opacity(0.12), in: Capsule())
                }
            }

            if queueChecks.isEmpty {
                VStack(spacing: 6) {
                    Spacer().frame(height: 4)
                    Image(systemName: "checkmark.seal.fill")
                        .font(.system(size: 24))
                        .foregroundStyle(.green.opacity(0.8))
                    Text("Queue Empty")
                        .font(.system(size: 12, weight: .medium))
                    Text("Ready for landing")
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)
                    Spacer().frame(height: 4)
                }
                .frame(maxWidth: .infinity)
            } else {
                VStack(spacing: 5) {
                    ForEach(Array(queueChecks.enumerated()), id: \.element.key) { index, item in
                        HStack(spacing: 6) {
                            Text("#\(index + 1)")
                                .font(.system(size: 10, weight: .bold, design: .monospaced))
                                .foregroundStyle(Color.accentColor)

                            Text(item.name)
                                .font(.system(size: 11, weight: .medium))
                                .lineLimit(1)

                            Spacer()

                            if item.status.isRunning {
                                Text("testing")
                                    .font(.system(size: 9, weight: .medium))
                                    .foregroundStyle(.orange)
                            } else if item.conclusion?.isPassing == true {
                                Text("ready")
                                    .font(.system(size: 9, weight: .medium))
                                    .foregroundStyle(.green)
                            }
                        }
                        .padding(.vertical, 3)
                        .padding(.horizontal, 4)
                        .background(Color.white.opacity(0.03), in: RoundedRectangle(cornerRadius: 6))
                    }
                }
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .modifier(NotchControlSurface(cornerRadius: 14))
    }

    // MARK: - Card 3: Open Pull Requests Card

    private func openPRsCard(state: RepoState) -> some View {
        let prs = state.pullRequests.values.sorted { $0.number > $1.number }

        return VStack(alignment: .leading, spacing: 8) {
            HStack {
                Label("Open Pull Requests", systemImage: "arrow.triangle.branch")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.secondary)
                Spacer()

                Text("\(prs.count) open")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(.secondary)
            }

            if prs.isEmpty {
                HStack {
                    Image(systemName: "tray")
                        .font(.system(size: 13))
                        .foregroundStyle(.secondary)
                    Text("No pull requests requiring attention")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                }
                .padding(.vertical, 6)
            } else {
                VStack(spacing: 6) {
                    ForEach(prs, id: \.number) { pr in
                        pullRequestRow(pr: pr)
                    }
                }
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .modifier(NotchControlSurface(cornerRadius: 14))
    }

    private func pullRequestRow(pr: PullRequest) -> some View {
        let checks = Array(pr.checks.values)
        let passing = checks.filter { $0.status == .completed && $0.conclusion?.isPassing == true }.count
        let total = checks.count

        return Button {
            if let url = pr.htmlURL {
                NSWorkspace.shared.open(url)
            }
        } label: {
            HStack(spacing: 8) {
                // PR Number & Title
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 4) {
                        Text("#\(pr.number)")
                            .font(.system(size: 11, weight: .bold, design: .monospaced))
                            .foregroundStyle(Color.accentColor)

                        if pr.isDraft {
                            Text("Draft")
                                .font(.system(size: 9, weight: .medium))
                                .foregroundStyle(.secondary)
                                .padding(.horizontal, 4)
                                .padding(.vertical, 1)
                                .background(Color.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 4))
                        }

                        Text(pr.title)
                            .font(.system(size: 11, weight: .medium))
                            .lineLimit(1)
                            .foregroundStyle(.primary)
                    }

                    HStack(spacing: 6) {
                        // Check Rollup Progress
                        if total > 0 {
                            HStack(spacing: 3) {
                                Image(systemName: passing == total ? "checkmark.circle.fill" : "circle.dashed")
                                    .font(.system(size: 9))
                                    .foregroundStyle(passing == total ? .green : .orange)
                                Text("\(passing)/\(total) checks")
                                    .font(.system(size: 10, design: .monospaced))
                                    .foregroundStyle(.secondary)
                            }
                        }

                        // Review Status
                        reviewBadge(for: pr.reviewState)
                    }
                }

                Spacer()

                Image(systemName: "arrow.up.forward.app")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }
            .padding(.vertical, 4)
            .padding(.horizontal, 6)
            .background(Color.white.opacity(0.03), in: RoundedRectangle(cornerRadius: 8))
        }
        .buttonStyle(.plain)
    }

    // MARK: - Badges & Components

    private func statusBadge(count: Int, label: String, systemImage: String, color: Color) -> some View {
        HStack(spacing: 3) {
            Image(systemName: systemImage)
                .font(.system(size: 9))
            Text("\(count) \(label)")
                .font(.system(size: 10, weight: .medium))
        }
        .foregroundStyle(color)
        .padding(.horizontal, 6)
        .padding(.vertical, 3)
        .background(color.opacity(0.12), in: Capsule())
    }

    private func reviewBadge(for state: ReviewState) -> some View {
        Group {
            switch state {
            case .approved:
                HStack(spacing: 3) {
                    Image(systemName: "checkmark")
                        .font(.system(size: 8, weight: .bold))
                    Text("Approved")
                        .font(.system(size: 9, weight: .medium))
                }
                .foregroundStyle(.green)
            case .changesRequested:
                HStack(spacing: 3) {
                    Image(systemName: "exclamationmark.circle.fill")
                        .font(.system(size: 8, weight: .bold))
                    Text("Changes Requested")
                        .font(.system(size: 9, weight: .medium))
                }
                .foregroundStyle(.red)
            case .pending:
                HStack(spacing: 3) {
                    Image(systemName: "clock")
                        .font(.system(size: 8, weight: .bold))
                    Text("Review Pending")
                        .font(.system(size: 9, weight: .medium))
                }
                .foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, 4)
        .padding(.vertical, 1)
        .background(Color.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 4))
    }

    // MARK: - Actions

    private func rerunFailedChecks(state: RepoState) {
        let failingChecks = state.checks.values.filter { $0.conclusion?.isFailing == true }
        if let first = failingChecks.first, let url = first.htmlURL {
            NSWorkspace.shared.open(url)
        } else if let url = URL(string: "https://github.com/\(currentRepo.fullName)/actions") {
            NSWorkspace.shared.open(url)
        }
    }

    // MARK: - Empty States

    private var signedOutView: some View {
        VStack(spacing: 12) {
            Spacer().frame(height: 10)
            Image(systemName: "arrow.triangle.branch")
                .font(.system(size: 32))
                .foregroundStyle(.secondary)
            Text("GitHub Not Connected")
                .font(.system(size: 14, weight: .semibold))
            Text("Sign in with GitHub CLI (`gh auth login`) or Settings to view pipeline metrics.")
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 300)

            Button {
                NotchService.shared.openSettings(showing: .github)
            } label: {
                Text("Open Settings")
                    .font(.system(size: 11, weight: .medium))
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(Color.accentColor, in: RoundedRectangle(cornerRadius: 8))
                    .foregroundStyle(.white)
            }
            .buttonStyle(.plain)
            Spacer().frame(height: 10)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var loadingView: some View {
        VStack(spacing: 8) {
            ProgressView()
                .controlSize(.small)
            Text("Fetching pipeline status…")
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var emptyRepoView: some View {
        VStack(spacing: 8) {
            Image(systemName: "tray")
                .font(.system(size: 24))
                .foregroundStyle(.secondary)
            Text("No Data Available")
                .font(.system(size: 12, weight: .medium))
            Text("Watched repository pipeline status will appear here.")
                .font(.system(size: 10))
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
