// Copyright 2026 VitruvianSoftware
// SPDX-License-Identifier: AGPL-3.0-or-later

import CourierCore
import SwiftUI

/// `Settings ▸ AI` (`01` §13, `02` §1.3): covers `setting:ai Translation Languages`, `setting:ai Arabic`,
/// `setting:ai Use OpenAI's Whisper model for Talk to Type and transcribing`, `setting:ai Mention an AI to get answers and help in chat`,
/// and `createSlashCommandTriggerSettings.tsx`, backed by `AIPreferences` and `AIProvider`.
public struct AISettingsPane: View {
    @ObservedObject public var preferences: AIPreferences
    public let provider: any AIProvider
    @ObservedObject public var lifecycle: SystemLifecycleModel
    public var highlightedSettingID: String? = nil

    @MainActor
    public init(
        preferences: AIPreferences,
        provider: any AIProvider = UnavailableAIProvider(),
        lifecycle: SystemLifecycleModel? = nil,
        highlightedSettingID: String? = nil
    ) {
        self.preferences = preferences
        self.provider = provider
        self.lifecycle = lifecycle ?? AppLockGate.shared.lifecycle
        self.highlightedSettingID = highlightedSettingID
    }

    public var body: some View {
        ScrollViewReader { proxy in
            Form {
                statusBannerSection
                contextualAISection
                translationLanguagesSection
                talkToTypeSection
                slashCommandsSection
            }
            .formStyle(.grouped)
            .disabled(lifecycle.isLocked)
            .onChange(of: highlightedSettingID, initial: true) { _, targetID in
                if let targetID {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        proxy.scrollTo(targetID, anchor: .center)
                    }
                }
            }
        }
    }

    private var statusBannerSection: some View {
        Section {
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: "sparkles")
                    .font(.title3)
                    .foregroundStyle(Color.accentColor)
                    .padding(.top, 2)
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 8) {
                        Text(String(localized: "On-Device & Cloud AI"))
                            .font(.subheadline.weight(.semibold))
                        Text(provider.isAvailable ? String(localized: "Active") : String(localized: "Not available yet"))
                            .font(.caption2.weight(.semibold))
                            .padding(.horizontal, 7)
                            .padding(.vertical, 2)
                            .background(Capsule().fill(Color.secondary.opacity(0.16)))
                            .foregroundStyle(.secondary)
                    }
                    Text(provider.unavailableReason)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer(minLength: 0)
            }
            .padding(.vertical, 4)
        }
    }

    private var contextualAISection: some View {
        Section(String(localized: "Contextual AI & Chat Assistant")) {
            VStack(alignment: .leading, spacing: 10) {
                Toggle(
                    String(localized: "Enable contextual AI assistant"),
                    isOn: $preferences.enableContextualAI
                )
                Picker(String(localized: "AI Engine"), selection: $preferences.selectedEngine) {
                    ForEach(AIEngineChoice.allCases, id: \.self) { choice in
                        Text(choice.label).tag(choice)
                    }
                }
                Picker(String(localized: "Model"), selection: $preferences.selectedModel) {
                    ForEach(provider.availableModels, id: \.self) { modelName in
                        Text(modelName).tag(modelName)
                    }
                }
                Toggle(
                    String(localized: "Mention an AI to get answers and help in chat"),
                    isOn: $preferences.mentionAIInChats
                )
                VStack(alignment: .leading, spacing: 4) {
                    Text(String(localized: "Custom instructions for AI mentions"))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    TextField(
                        String(localized: "Keep answers brief and factual…"),
                        text: $preferences.aiMentionsSystemPrompt
                    )
                    .textFieldStyle(.roundedBorder)
                }
            }
            .settingAnchor("ai.contextual", highlighted: highlightedSettingID)
        }
    }

    private var translationLanguagesSection: some View {
        Section(String(localized: "Translation Languages")) {
            VStack(alignment: .leading, spacing: 10) {
                Picker(
                    String(localized: "Preferred response language"),
                    selection: $preferences.responseLanguage
                ) {
                    ForEach(AIPreferences.supportedTranslationLanguages, id: \.self) { language in
                        Text(language).tag(language)
                    }
                }

                Text(String(localized: "Enabled translation languages"))
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)

                LazyVGrid(
                    columns: [GridItem(.adaptive(minimum: 150), spacing: 8)],
                    alignment: .leading,
                    spacing: 6
                ) {
                    ForEach(AIPreferences.supportedTranslationLanguages, id: \.self) { language in
                        Toggle(
                            language,
                            isOn: Binding(
                                get: { preferences.translationLanguages.contains(language) },
                                set: { enabled in
                                    var updated = preferences.translationLanguages
                                    if enabled {
                                        if !updated.contains(language) {
                                            updated.append(language)
                                        }
                                    } else if updated.count > 1 {
                                        updated.removeAll { $0 == language }
                                    }
                                    preferences.translationLanguages = updated
                                }
                            )
                        )
                        .toggleStyle(.checkbox)
                        .font(.caption)
                    }
                }
            }
            .settingAnchor("ai.translation", highlighted: highlightedSettingID)
        }
    }

    private var talkToTypeSection: some View {
        Section(String(localized: "Talk to Type & Voice Transcription")) {
            VStack(alignment: .leading, spacing: 10) {
                Toggle(
                    String(localized: "Use OpenAI's Whisper model for Talk to Type and transcribing"),
                    isOn: $preferences.useWhisperForTalkToType
                )
                Toggle(
                    String(localized: "Automatically transcribe incoming voice notes"),
                    isOn: $preferences.autoTranscribeVoiceNotes
                )
                Picker(
                    String(localized: "Transcription language"),
                    selection: $preferences.transcriptionLanguage
                ) {
                    Text(String(localized: "Auto-Detect")).tag("Auto-Detect")
                    ForEach(AIPreferences.supportedTranslationLanguages, id: \.self) { language in
                        Text(language).tag(language)
                    }
                }
            }
            .settingAnchor("ai.talkToType", highlighted: highlightedSettingID)
        }
    }

    private var slashCommandsSection: some View {
        Section(String(localized: "Slash Command Triggers")) {
            VStack(alignment: .leading, spacing: 10) {
                Toggle(
                    String(localized: "Enable / slash command triggers in the message box"),
                    isOn: $preferences.enableSlashCommands
                )

                VStack(alignment: .leading, spacing: 6) {
                    ForEach(ComposerSlashCommand.allCommands) { cmd in
                        HStack(spacing: 10) {
                            Text(cmd.trigger)
                                .font(.system(.caption, design: .monospaced).weight(.semibold))
                                .padding(.horizontal, 7)
                                .padding(.vertical, 2)
                                .background(
                                    RoundedRectangle(cornerRadius: 5, style: .continuous)
                                        .fill(Color.accentColor.opacity(0.14))
                                )
                            VStack(alignment: .leading, spacing: 1) {
                                Text(cmd.title)
                                    .font(.caption.weight(.medium))
                                Text(cmd.summary)
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer(minLength: 0)
                        }
                    }
                }
            }
            .settingAnchor("ai.slashCommands", highlighted: highlightedSettingID)
        }
    }
}
