// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 VitruvianSoftware
//
// Adapted from the standalone Nexus Agent app (apps/desktop/nexus-agent,
// MIT, Copyright (c) 2026 VitruvianSoftware): its status and settings
// windows, as one Settings page.

import AppKit
import SwiftUI
import VitruvianCore
import VitruvianDesign
import VitruvianServices

/// The bot's status and log, the part of its `.env` people change, the Quick
/// Prompt and where the bot lives. Status and log are read only while the
/// page is up.
package struct NexusAgentSettingsView: View {
    @ObservedObject private var l10n = L10n.shared
    @ObservedObject private var service = NexusAgentService.shared
    @AppStorage(Preferences.nexusAgentShortcutEnabled) private var shortcutEnabled: Bool
    @AppStorage(Preferences.nexusAgentAutoStart) private var autoStart: Bool
    @AppStorage(Preferences.nexusAgentBotDirectory) private var botDirectory: String
    @State private var draft = NexusAgentConfiguration()

    package init() {}

    private var strings: NexusAgentFeatureStrings { FeatureStrings.nexusAgent(l10n.language) }

    package var body: some View {
        Form {
            botSection
            configurationSection
            quickPromptSection
            botFolderSection
        }
        .formStyle(.grouped)
        .onAppear {
            service.startPolling()
            draft = service.configuration
        }
        .onDisappear { service.stopPolling() }
        .onChange(of: botDirectory) { _, _ in
            service.load()
            draft = service.configuration
        }
    }

    // MARK: - Bot

    private var botSection: some View {
        Section {
            HStack(spacing: 8) {
                Circle()
                    .fill(service.isRunning ? Color.green : Color.secondary.opacity(0.5))
                    .frame(width: 8, height: 8)
                Text(service.isRunning ? strings.statusRunning : strings.statusStopped)
                if let pid = service.pid {
                    Text("PID \(pid)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                }
                Spacer()
                if service.isRunning {
                    Button(strings.restart) { service.restart() }
                    Button(strings.stop) { service.stop() }
                } else {
                    Button(strings.start) { service.start() }
                }
            }
            if let message = problemMessage {
                Text(message)
                    .font(.caption)
                    .foregroundStyle(.orange)
            }
            if service.needsRestart {
                Text(strings.savedRestartHint)
                    .font(.caption)
                    .foregroundStyle(.orange)
            }
            Toggle(strings.autoStart, isOn: $autoStart)
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text(strings.recentLog)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Spacer()
                    Button(strings.openLog) { service.openLog() }
                        .controlSize(.small)
                }
                ScrollView {
                    Text(service.logLines.isEmpty ? strings.logEmpty : service.logLines.joined(separator: "\n"))
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundStyle(service.logLines.isEmpty ? .tertiary : .secondary)
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .frame(height: 140)
            }
        } header: {
            Text(strings.botSection)
        }
    }

    private var problemMessage: String? {
        switch service.problem {
        case .missingToken: return strings.missingToken
        case .missingBot: return strings.missingBot
        case .missingNode: return strings.missingNode
        case .startFailed: return strings.startFailed
        case .saveFailed: return strings.saveFailed
        case nil: return nil
        }
    }

    // MARK: - Configuration

    private var configurationSection: some View {
        Section {
            VStack(alignment: .leading, spacing: 4) {
                SecureField(strings.token, text: $draft.botToken)
                caption(strings.tokenCaption)
            }
            VStack(alignment: .leading, spacing: 4) {
                TextField(strings.allowedUsers, text: $draft.allowedUserIDs)
                caption(strings.allowedUsersCaption)
            }
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    TextField(strings.workingFolder, text: $draft.workingDirectory)
                    Button(strings.choose) {
                        if let path = chooseFolder() { draft.workingDirectory = path }
                    }
                }
                caption(strings.workingFolderCaption)
            }
            Picker(strings.approvalMode, selection: $draft.approvalMode) {
                ForEach(NexusAgentApprovalMode.allCases) { mode in
                    Text(strings.approvalModeName(mode)).tag(mode)
                }
            }
            TextField(strings.model, text: $draft.model, prompt: Text(strings.modelPlaceholder))
            Picker(strings.effort, selection: $draft.effort) {
                ForEach(NexusAgentEffort.allCases) { effort in
                    Text(strings.effortName(effort)).tag(effort)
                }
            }
            HStack {
                Spacer()
                Button(strings.save) { service.save(draft) }
                    .disabled(draft == service.configuration)
            }
        } header: {
            Text(strings.configurationSection)
        }
    }

    // MARK: - Quick Prompt

    private var quickPromptSection: some View {
        Section {
            Button {
                service.showQuickPrompt()
            } label: {
                Label(strings.quickPromptTitle, systemImage: "paperplane")
            }
            caption(strings.quickPromptCaption)
            if service.agentPath == nil {
                Text(strings.missingAgent)
                    .font(.caption)
                    .foregroundStyle(.orange)
            }
            Toggle(l10n.s.quickToolShortcutToggle, isOn: $shortcutEnabled)
                .onChange(of: shortcutEnabled) { _, _ in
                    service.syncWithPreferences()
                }
            ShortcutPreferenceRow(role: .nexusAgent, isEnabled: shortcutEnabled) {
                service.syncWithPreferences()
            }
            if shortcutEnabled, service.shortcutRegistrationFailed {
                Text(l10n.s.shortcutUnavailable)
                    .font(.caption)
                    .foregroundStyle(.orange)
            }
        } header: {
            Text(strings.quickPromptSection)
        }
    }

    // MARK: - Bot folder

    private var botFolderSection: some View {
        Section {
            HStack {
                TextField(strings.botFolder, text: $botDirectory,
                          prompt: Text(NexusAgentSupport.defaultBotDirectory(home: NSHomeDirectory())))
                Button(strings.choose) {
                    if let path = chooseFolder() { botDirectory = path }
                }
            }
            caption(strings.botFolderCaption)
            if !service.isBotInstalled {
                Text(strings.missingBot)
                    .font(.caption)
                    .foregroundStyle(.orange)
            }
        } header: {
            Text(strings.botFolder)
        }
    }

    // MARK: - Helpers

    private func caption(_ text: String) -> some View {
        Text(text)
            .font(.caption)
            .foregroundStyle(.secondary)
    }

    private func chooseFolder() -> String? {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.canCreateDirectories = true
        panel.allowsMultipleSelection = false
        return panel.runModal() == .OK ? panel.url?.path : nil
    }
}
