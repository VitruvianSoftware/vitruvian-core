// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 VitruvianSoftware

import AppKit
import SwiftUI
import VitruvianCore
import VitruvianDesign
import VitruvianServices

/// Top-level GitHub Settings page in the sidebar under Utilities / Developer Tools.
package struct GitHubSettingsView: View {
    @ObservedObject private var auth = GitHubAuthService.shared
    @ObservedObject private var service = GitHubService.shared
    @ObservedObject private var l10n = L10n.shared
    @ObservedObject private var features = FeatureRuntime.shared

    @AppStorage(Preferences.notchGitHubEnabled) private var enabled: Bool
    @AppStorage(Preferences.githubMouseIndicator) private var mouseIndicator: Bool
    @AppStorage(Preferences.githubWatchedRepositories) private var watched: String
    @AppStorage(Preferences.githubPollInterval) private var pollInterval: Int
    @AppStorage(Preferences.githubPollActiveInterval) private var pollActiveInterval: Int
    @AppStorage(Preferences.githubMouseSuccessColor) private var successColor: String
    @AppStorage(Preferences.githubMouseSuccessMode) private var successMode: String
    @AppStorage(Preferences.githubMouseRunningColor) private var runningColor: String
    @AppStorage(Preferences.githubMouseRunningMode) private var runningMode: String
    @AppStorage(Preferences.githubMouseFailureColor) private var failureColor: String
    @AppStorage(Preferences.githubMouseFailureMode) private var failureMode: String
    @AppStorage(Preferences.githubMouseIdleBehavior) private var idleBehavior: String
    @AppStorage(Preferences.githubMouseApprovalColor) private var approvalColor: String
    @AppStorage(Preferences.githubMouseApprovalMode) private var approvalMode: String
    @AppStorage(Preferences.githubMouseApprovalSpeed) private var approvalSpeed: Int
    @AppStorage(Preferences.githubMouseBinaryPath) private var mouseBinaryPath: String

    private let colorOptions = ["green", "cyan", "blue", "purple", "magenta", "yellow", "orange", "red", "white", "pink"]

    @State private var patInput: String = ""
    @State private var showsPATSheet: Bool = false
    @State private var showsAdvanced: Bool = false

    package init() {}

    private var text: NotchGitHubStrings { FeatureStrings.notchGitHub(l10n.language) }

    package var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                // Header & Feature Enablement
                SettingsCard {
                    Toggle("GitHub Status & Actions", isOn: $enabled)
                        .toggleStyle(TrailingSwitchToggleStyle())
                    Text("Monitor CI workflows, check runs, and pull requests directly in the Dynamic Island and on your GravaStar mouse.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                if enabled {
                    // Account Authentication Card
                    SettingsCard(title: "GitHub Account") {
                        accountSection
                    }

                    // Live Status Card (When Signed In)
                    if auth.isSignedIn {
                        SettingsCard(title: "Watched Repositories") {
                            watchlistSection
                        }

                        SettingsCard(title: "Sync & Polling Cadence") {
                            VStack(alignment: .leading, spacing: 14) {
                                HStack {
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text("Standard Refresh Interval")
                                            .font(.subheadline)
                                        Text("Frequency to check workflow runs and open PRs at rest.")
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                    }
                                    Spacer()
                                    Picker("", selection: $pollInterval) {
                                        Text("15 seconds").tag(15)
                                        Text("30 seconds (Default)").tag(30)
                                        Text("1 minute").tag(60)
                                        Text("2 minutes").tag(120)
                                        Text("5 minutes").tag(300)
                                    }
                                    .frame(width: 175)
                                    .labelsHidden()
                                }

                                Divider()

                                HStack {
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text("Active Run Refresh Interval")
                                            .font(.subheadline)
                                        Text("Accelerated frequency when a check run or build is active.")
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                    }
                                    Spacer()
                                    Picker("", selection: $pollActiveInterval) {
                                        Text("5 seconds").tag(5)
                                        Text("10 seconds (Default)").tag(10)
                                        Text("15 seconds").tag(15)
                                        Text("30 seconds").tag(30)
                                    }
                                    .frame(width: 175)
                                    .labelsHidden()
                                }
                            }
                        }

                        SettingsCard(title: "Hardware & Mouse Lighting") {
                            VStack(alignment: .leading, spacing: 14) {
                                Toggle("Show status on GravaStar mouse LED", isOn: $mouseIndicator)
                                    .toggleStyle(TrailingSwitchToggleStyle())
                                    .onChange(of: mouseIndicator) { _, isEnabled in
                                        if isEnabled {
                                            GitHubPeripheralSink.shared.update(summary: service.summary)
                                        } else {
                                            GitHubPeripheralSink.shared.restore()
                                        }
                                    }

                                if mouseIndicator {
                                    Divider()

                                    mouseCommandSection

                                    Divider()

                                    // Awaiting approval: outranks the rows below
                                    HStack {
                                        Label("Awaiting Approval", systemImage: "hand.raised.fill")
                                            .foregroundStyle(.blue)
                                            .frame(width: 140, alignment: .leading)
                                        Spacer()
                                        Picker("Color", selection: $approvalColor) {
                                            ForEach(colorOptions, id: \.self) { c in
                                                Text(c.capitalized).tag(c)
                                            }
                                        }
                                        .frame(width: 105)
                                        .labelsHidden()
                                        Picker("Style", selection: $approvalMode) {
                                            Text("Solid").tag("fixed")
                                            Text("Pulsing").tag("breathe")
                                        }
                                        .frame(width: 95)
                                        .labelsHidden()
                                        Button("Test") {
                                            GitHubPeripheralSink.shared.signal(color: approvalColor, mode: approvalMode,
                                                                               speed: approvalSpeed)
                                        }
                                        .buttonStyle(.bordered)
                                        .controlSize(.small)
                                    }

                                    // Success
                                    HStack {
                                        Label("All Passing", systemImage: "checkmark.circle.fill")
                                            .foregroundStyle(.green)
                                            .frame(width: 140, alignment: .leading)
                                        Spacer()
                                        Picker("Color", selection: $successColor) {
                                            ForEach(colorOptions, id: \.self) { c in
                                                Text(c.capitalized).tag(c)
                                            }
                                        }
                                        .frame(width: 105)
                                        .labelsHidden()
                                        Picker("Style", selection: $successMode) {
                                            Text("Solid").tag("fixed")
                                            Text("Pulsing").tag("breathe")
                                        }
                                        .frame(width: 95)
                                        .labelsHidden()
                                        Button("Test") {
                                            GitHubPeripheralSink.shared.signal(color: successColor, mode: successMode)
                                        }
                                        .buttonStyle(.bordered)
                                        .controlSize(.small)
                                    }

                                    // Running / Warning
                                    HStack {
                                        Label("Active / Building", systemImage: "clock.fill")
                                            .foregroundStyle(.orange)
                                            .frame(width: 140, alignment: .leading)
                                        Spacer()
                                        Picker("Color", selection: $runningColor) {
                                            ForEach(colorOptions, id: \.self) { c in
                                                Text(c.capitalized).tag(c)
                                            }
                                        }
                                        .frame(width: 105)
                                        .labelsHidden()
                                        Picker("Style", selection: $runningMode) {
                                            Text("Solid").tag("fixed")
                                            Text("Pulsing").tag("breathe")
                                        }
                                        .frame(width: 95)
                                        .labelsHidden()
                                        Button("Test") {
                                            GitHubPeripheralSink.shared.signal(color: runningColor, mode: runningMode)
                                        }
                                        .buttonStyle(.bordered)
                                        .controlSize(.small)
                                    }

                                    // Failure
                                    HStack {
                                        Label("Build Failure", systemImage: "xmark.circle.fill")
                                            .foregroundStyle(.red)
                                            .frame(width: 140, alignment: .leading)
                                        Spacer()
                                        Picker("Color", selection: $failureColor) {
                                            ForEach(colorOptions, id: \.self) { c in
                                                Text(c.capitalized).tag(c)
                                            }
                                        }
                                        .frame(width: 105)
                                        .labelsHidden()
                                        Picker("Style", selection: $failureMode) {
                                            Text("Solid").tag("fixed")
                                            Text("Pulsing").tag("breathe")
                                        }
                                        .frame(width: 95)
                                        .labelsHidden()
                                        Button("Test") {
                                            GitHubPeripheralSink.shared.signal(color: failureColor, mode: failureMode)
                                        }
                                        .buttonStyle(.bordered)
                                        .controlSize(.small)
                                    }

                                    // Idle / Rest
                                    HStack {
                                        Label("Idle / Rest", systemImage: "moon.fill")
                                            .foregroundStyle(.secondary)
                                            .frame(width: 140, alignment: .leading)
                                        Spacer()
                                        Picker("Behavior", selection: $idleBehavior) {
                                            Text("Restore Baseline").tag("restore")
                                            Text("Turn Off LED").tag("off")
                                        }
                                        .frame(width: 205)
                                        .labelsHidden()
                                        Button("Reset") {
                                            GitHubPeripheralSink.shared.restore()
                                        }
                                        .buttonStyle(.bordered)
                                        .controlSize(.small)
                                    }
                                }
                            }
                        }
                    }
                }
            }
            .padding(20)
        }
        .onAppear {
            auth.syncWithPreferences()
            if auth.isSignedIn { service.refresh() }
        }
    }

    // MARK: - Mouse Command

    /// Where `gravastar-mouse` is, and whether one was found. Empty searches.
    @ViewBuilder
    private var mouseCommandSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(text.mouseCommand)
                    .font(.subheadline)
                Spacer()
                TextField(GitHubMouseBinary.name, text: $mouseBinaryPath)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 260)
                Button(text.choose) { chooseMouseBinary() }
                    .controlSize(.small)
            }
            Text(text.mouseCommandHint)
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            // A change to mouseBinaryPath redraws the view, so this line
            // follows the field as the path is typed or chosen.
            if let found = GitHubPeripheralSink.shared.locateBinary() {
                HStack {
                    Text(text.mouseCommandFound(found))
                        .font(.caption.monospaced())
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                    Spacer()
                    // For an AI agent: the same command as an MCP server.
                    Button(text.copyMCPConfig) {
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString(GitHubMouseBinary.mcpConfig(binary: found), forType: .string)
                    }
                    .buttonStyle(.link)
                    .font(.caption)
                }
            } else {
                Text(text.mouseCommandMissing)
                    .font(.caption)
                    .foregroundStyle(.orange)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private func chooseMouseBinary() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.showsHiddenFiles = true
        panel.directoryURL = URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent(".local/bin")
        NSApp.activate(ignoringOtherApps: true)
        guard panel.runModal() == .OK, let url = panel.url else { return }
        mouseBinaryPath = url.path
    }

    // MARK: - Account Section

    @ViewBuilder
    private var accountSection: some View {
        switch auth.state {
        case .signedIn(let login):
            HStack(spacing: 12) {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(Color.green)
                    .font(.title2)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Connected as @\(login)")
                        .font(.headline)
                    if let refreshed = service.lastRefreshedAt {
                        Text("Last updated: \(refreshed.formatted(date: .omitted, time: .standard))")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                Spacer()
                Button(action: { service.refresh() }) {
                    Label(service.isRefreshing ? "Refreshing..." : "Refresh", systemImage: "arrow.clockwise")
                }
                .disabled(service.isRefreshing)
                Button("Disconnect") {
                    auth.disconnect()
                }
                .buttonStyle(.bordered)
            }

        case .authorizing, .exchanging:
            HStack(spacing: 12) {
                ProgressView().controlSize(.small)
                Text("Connecting to GitHub...")
                    .font(.callout)
                Spacer()
                Button("Cancel") { auth.cancel() }
            }

        case .deviceFlow(let userCode, let verificationURL):
            VStack(alignment: .leading, spacing: 10) {
                Text("Enter this code to authorize:")
                    .font(.subheadline)
                Text(userCode)
                    .font(.title2.monospaced().weight(.bold))
                    .textSelection(.enabled)
                HStack(spacing: 10) {
                    Button("Copy Code") {
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString(userCode, forType: .string)
                    }
                    Button("Open GitHub Verification") {
                        NSWorkspace.shared.open(verificationURL)
                    }
                    .buttonStyle(.borderedProminent)
                    Button("Cancel") { auth.cancel() }
                }
            }

        case .signedOut, .failed:
            VStack(alignment: .leading, spacing: 14) {
                if case .failed(let err) = auth.state {
                    Text(text.message(for: err))
                        .font(.caption)
                        .foregroundStyle(.red)
                }

                // Path 1: 1-Click GitHub CLI Auto-Detection (Frictionless)
                if let cli = auth.detectedCLIAccount {
                    VStack(alignment: .leading, spacing: 6) {
                        Button(action: { auth.connectWithGitHubCLI() }) {
                            HStack {
                                Image(systemName: "terminal")
                                Text("Connect with GitHub CLI (@\(cli.login))")
                                    .fontWeight(.medium)
                            }
                            .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.borderedProminent)
                        .controlSize(.large)
                        Text("Detected authenticated GitHub CLI session on your Mac. Instant 1-click connect.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Divider()
                }

                // Path 2: Personal Access Token
                VStack(alignment: .leading, spacing: 8) {
                    Text("Or connect with a Personal Access Token:")
                        .font(.caption.weight(.medium))
                    HStack {
                        SecureField("ghp_... or gho_...", text: $patInput)
                            .textFieldStyle(.roundedBorder)
                        Button("Save Token") {
                            auth.connectWithToken(patInput)
                        }
                        .disabled(patInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    }
                    HStack {
                        Button("Generate token on GitHub.com") {
                            if let url = URL(string: "https://github.com/settings/tokens/new?description=Vitruvian%20Desktop&scopes=repo,workflow") {
                                NSWorkspace.shared.open(url)
                            }
                        }
                        .buttonStyle(.link)
                        .font(.caption)
                        Spacer()
                        Button("Use Device Code") {
                            auth.connectWithCode()
                        }
                        .buttonStyle(.link)
                        .font(.caption)
                    }
                }
            }
        }
    }

    // MARK: - Watchlist Section

    private var repositoryText: Binding<String> {
        Binding(
            get: {
                let repos = GitHubWatchlist.decode(watched)
                return repos.map(\.fullName).joined(separator: ", ")
            },
            set: { newValue in
                let parts = newValue.split(separator: ",").map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                let valid = parts.compactMap(RepoKey.init(fullName:))
                watched = GitHubWatchlist.encode(valid.isEmpty ? GitHubWatchlist.defaultRepositories : valid)
            }
        )
    }

    @ViewBuilder
    private var watchlistSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            TextField("Watched Repositories (owner/repo, comma-separated)", text: repositoryText)
                .textFieldStyle(.roundedBorder)
                .onSubmit { service.refresh() }

            if service.summary.repositories.isEmpty {
                Text("No repository data yet. Hit Refresh or enter a valid repository (e.g. VitruvianSoftware/vitruvian-core).")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                ForEach(service.summary.repositories, id: \.repo) { repo in
                    HStack(spacing: 10) {
                        Circle()
                            .fill(color(for: repo.verdict))
                            .frame(width: 10, height: 10)
                        Text(repo.repo.fullName)
                            .font(.subheadline.weight(.semibold))
                        Spacer()
                        HStack(spacing: 12) {
                            if repo.passed > 0 {
                                Label("\(repo.passed)", systemImage: "checkmark")
                                    .foregroundStyle(.green)
                            }
                            if repo.running > 0 {
                                Label("\(repo.running)", systemImage: "clock")
                                    .foregroundStyle(.orange)
                            }
                            if repo.failed > 0 {
                                Label("\(repo.failed)", systemImage: "xmark")
                                    .foregroundStyle(.red)
                            }
                        }
                        .font(.caption.monospacedDigit())
                    }
                    .padding(.vertical, 4)
                }
            }

            if !service.summary.pullRequests.isEmpty {
                Divider()
                Text("Open Pull Requests")
                    .font(.subheadline.weight(.semibold))
                ForEach(service.summary.pullRequests, id: \.pullRequest.number) { row in
                    HStack {
                        Text("#\(row.pullRequest.number)")
                            .font(.caption.monospaced())
                            .foregroundStyle(.secondary)
                        Text(row.pullRequest.title)
                            .font(.subheadline)
                            .lineLimit(1)
                        Spacer()
                        if let url = row.pullRequest.htmlURL {
                            Link("View", destination: url)
                                .font(.caption)
                        }
                    }
                }
            }
        }
    }

    private func color(for verdict: Verdict) -> Color {
        switch verdict {
        case .green: return .green
        case .amber: return .orange
        case .red:   return .red
        case .grey:  return .secondary
        }
    }
}
