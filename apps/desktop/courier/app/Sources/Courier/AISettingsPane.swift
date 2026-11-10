// Copyright 2026 VitruvianSoftware
// SPDX-License-Identifier: AGPL-3.0-or-later

import AppKit
import CourierCore
import SwiftUI

private final class EphemeralCredentialStore: CredentialStore, @unchecked Sendable {
    private let lock = NSLock()
    private var values: [String: String] = [:]

    func read(account: String) throws -> String? {
        lock.withLock { values[account] }
    }

    func write(_ value: String, account: String) throws {
        lock.withLock { values[account] = value }
    }

    func delete(account: String) throws {
        _ = lock.withLock { values.removeValue(forKey: account) }
    }
}

/// Observes `NSWindow.willCloseNotification` (and `didBecomeKeyNotification`) for the hosting Settings window so
/// periodic local AI detection stops immediately when the Settings window closes, even when SwiftUI keeps the
/// `Settings` scene view hierarchy alive.
struct SettingsWindowDetectionObserver: NSViewRepresentable {
    var onWindowClose: @MainActor () -> Void
    var onWindowBecomeKey: (@MainActor () -> Void)? = nil

    final class ObserverView: NSView {
        var onWindowClose: @MainActor () -> Void = {}
        var onWindowBecomeKey: (@MainActor () -> Void)?
        private var observers: [NSObjectProtocol] = []

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            removeObservers()
            guard let window else {
                MainActor.assumeIsolated {
                    onWindowClose()
                }
                return
            }
            observers.append(
                NotificationCenter.default.addObserver(
                    forName: NSWindow.willCloseNotification,
                    object: window,
                    queue: .main
                ) { [weak self] _ in
                    MainActor.assumeIsolated {
                        self?.onWindowClose()
                    }
                }
            )
            if onWindowBecomeKey != nil {
                observers.append(
                    NotificationCenter.default.addObserver(
                        forName: NSWindow.didBecomeKeyNotification,
                        object: window,
                        queue: .main
                    ) { [weak self] _ in
                        MainActor.assumeIsolated {
                            self?.onWindowBecomeKey?()
                        }
                    }
                )
            }
        }

        func removeObservers() {
            for observer in observers {
                NotificationCenter.default.removeObserver(observer)
            }
            observers = []
        }

        deinit {
            for observer in observers {
                NotificationCenter.default.removeObserver(observer)
            }
        }
    }

    func makeNSView(context _: Context) -> ObserverView {
        let view = ObserverView(frame: .zero)
        view.onWindowClose = onWindowClose
        view.onWindowBecomeKey = onWindowBecomeKey
        return view
    }

    func updateNSView(_ nsView: ObserverView, context _: Context) {
        nsView.onWindowClose = onWindowClose
        nsView.onWindowBecomeKey = onWindowBecomeKey
    }

    static func dismantleNSView(_ nsView: ObserverView, coordinator _: ()) {
        nsView.removeObservers()
    }
}

/// `Settings ▸ AI` (`01` §13, `02` §1.3, `docs/ai-providers.md`): provider list with `Off`, `On this Mac`, and `Cloud`
/// groups, selected-provider key/URL/model/test controls, custom instructions, translation languages, Talk to Type,
/// and slash command triggers, backed by `AIPreferences` and `AIProviderStore`.
public struct AISettingsPane: View {
    @ObservedObject public var preferences: AIPreferences
    @ObservedObject public var store: AIProviderStore
    private let explicitProvider: (any AIProvider)?
    private let ownsFallbackStore: Bool
    @ObservedObject public var lifecycle: SystemLifecycleModel
    public var highlightedSettingID: String? = nil

    @State private var apiKeyInput: String = ""

    @MainActor
    public init(
        preferences: AIPreferences,
        store: AIProviderStore? = nil,
        provider: (any AIProvider)? = nil,
        lifecycle: SystemLifecycleModel? = nil,
        highlightedSettingID: String? = nil
    ) {
        self.preferences = preferences
        if let store {
            self.store = store
            self.ownsFallbackStore = false
        } else {
            let quietTransport = StubHTTPTransport()
            self.store = AIProviderStore(
                preferences: preferences,
                keyStore: AIKeyStore(store: EphemeralCredentialStore()),
                transport: quietTransport,
                isAppInstalled: { _ in false }
            )
            self.ownsFallbackStore = true
        }
        self.explicitProvider = provider
        self.lifecycle = lifecycle ?? AppLockGate.shared.lifecycle
        self.highlightedSettingID = highlightedSettingID
    }

    private var effectiveProvider: any AIProvider {
        explicitProvider ?? store.provider
    }

    public var body: some View {
        ScrollViewReader { proxy in
            Form {
                statusBannerSection
                providerListSection
                selectedProviderSection
                customInstructionsSection
                translationLanguagesSection
                talkToTypeSection
                slashCommandsSection
            }
            .formStyle(.grouped)
            .disabled(lifecycle.isLocked)
            .background(
                SettingsWindowDetectionObserver(
                    onWindowClose: {
                        if !ownsFallbackStore {
                            store.stopSettingsDetection()
                        }
                    },
                    onWindowBecomeKey: {
                        if !ownsFallbackStore, !store.isSettingsDetectionActive {
                            store.startSettingsDetection()
                        }
                    }
                )
            )
            .onAppear {
                if !ownsFallbackStore {
                    store.startSettingsDetection()
                }
            }
            .onDisappear {
                if !ownsFallbackStore {
                    store.stopSettingsDetection()
                }
            }
            .onChange(of: preferences.selectedEngine) { _, _ in
                apiKeyInput = ""
            }
            .onChange(of: highlightedSettingID, initial: true) { _, targetID in
                if let targetID {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        proxy.scrollTo(targetID, anchor: .center)
                    }
                }
            }
        }
    }

    // MARK: - Status Banner

    private var statusBannerSection: some View {
        Section {
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: "sparkles")
                    .font(.title3)
                    .foregroundStyle(Color.accentColor)
                    .padding(.top, 2)
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 8) {
                        if effectiveProvider.isAvailable {
                            Circle()
                                .fill(Color.green)
                                .frame(width: 8, height: 8)
                                .accessibilityHidden(true)
                        }
                        Text(bannerHeadline)
                            .font(.subheadline.weight(.semibold))
                        Text(effectiveProvider.isAvailable ? String(localized: "Ready") : (preferences.enableContextualAI ? String(localized: "Needs setup") : String(localized: "Off")))
                            .font(.caption2.weight(.semibold))
                            .padding(.horizontal, 7)
                            .padding(.vertical, 2)
                            .background(Capsule().fill(Color.secondary.opacity(0.16)))
                            .foregroundStyle(.secondary)
                    }
                    Text(bannerSubtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer(minLength: 0)
            }
            .padding(.vertical, 4)
        }
    }

    private var bannerHeadline: String {
        if !preferences.enableContextualAI {
            return String(localized: "AI is off")
        }
        if effectiveProvider.isAvailable {
            let model = preferences.model(for: preferences.selectedEngine) ?? preferences.selectedModel
            return "\(preferences.selectedEngine.label) · \(model)"
        }
        return String(localized: "Set up a provider")
    }

    private var bannerSubtitle: String {
        if !preferences.enableContextualAI {
            return String(localized: "Choose a local or cloud provider below to draft replies, rewrite text, translate messages, or summarize chats.")
        }
        if effectiveProvider.isAvailable {
            return privacySentence(for: preferences.selectedEngine)
        }
        return effectiveProvider.unavailableReason
    }

    // MARK: - Provider List

    private var providerListSection: some View {
        Section(String(localized: "AI Provider")) {
            VStack(alignment: .leading, spacing: 10) {
                offProviderRow

                Divider()

                HStack(spacing: 8) {
                    Text(String(localized: "On this Mac"))
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                    if store.isDetecting {
                        ProgressView()
                            .controlSize(.small)
                        Text(String(localized: "Looking for local models…"))
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                    Spacer(minLength: 0)
                    Button {
                        Task { await store.refresh() }
                    } label: {
                        Label(String(localized: "Refresh"), systemImage: "arrow.clockwise")
                            .font(.caption)
                    }
                    .buttonStyle(.borderless)
                    .help(String(localized: "Re-scan local AI servers on this Mac"))
                }

                ForEach(AIProviderKind.localProviders, id: \.self) { kind in
                    localProviderRow(kind)
                }

                Divider()

                Text(String(localized: "Cloud"))
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)

                ForEach(AIProviderKind.cloudProviders, id: \.self) { kind in
                    cloudProviderRow(kind)
                }
            }
            .settingAnchor("ai.contextual", highlighted: highlightedSettingID)
        }
    }

    private var offProviderRow: some View {
        let isOff = !preferences.enableContextualAI
        return Button {
            preferences.enableContextualAI = false
        } label: {
            HStack(spacing: 10) {
                Image(systemName: isOff ? "checkmark.circle.fill" : "circle")
                    .foregroundStyle(isOff ? Color.accentColor : Color.secondary)
                Text(String(localized: "Off"))
                    .font(.callout.weight(isOff ? .semibold : .regular))
                Spacer(minLength: 0)
                Text(String(localized: "AI features turned off"))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func localProviderRow(_ kind: AIProviderKind) -> some View {
        let isSelected = preferences.enableContextualAI && preferences.selectedEngine == kind
        let rowAction = store.localRowAction(for: kind)
        return HStack(spacing: 10) {
            Button {
                preferences.selectedEngine = kind
                preferences.enableContextualAI = true
            } label: {
                HStack(spacing: 10) {
                    Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                        .foregroundStyle(isSelected ? Color.accentColor : Color.secondary)
                    Text(kind.label)
                        .font(.callout.weight(isSelected ? .semibold : .regular))
                    Spacer(minLength: 0)
                    Text(store.localRowStateText(for: kind))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            switch rowAction {
            case .none:
                EmptyView()
            case let .openApp(title):
                Button(title) {
                    store.openLocalApp(kind)
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            case let .getApp(title, url):
                Link(title, destination: url)
                    .font(.caption.weight(.medium))
            }
        }
    }

    private func cloudProviderRow(_ kind: AIProviderKind) -> some View {
        let isSelected = preferences.enableContextualAI && preferences.selectedEngine == kind
        return Button {
            preferences.selectedEngine = kind
            preferences.enableContextualAI = true
        } label: {
            HStack(spacing: 10) {
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .foregroundStyle(isSelected ? Color.accentColor : Color.secondary)
                Text(kind.label)
                    .font(.callout.weight(isSelected ? .semibold : .regular))
                Spacer(minLength: 0)
                Text(store.stateText(for: kind))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    // MARK: - Selected Provider Configuration

    private var selectedProviderSection: some View {
        let kind = preferences.selectedEngine
        return Section(kind.label) {
            VStack(alignment: .leading, spacing: 10) {
                if kind.acceptsKey {
                    apiKeyControls(for: kind)
                }

                if kind == .customOpenAICompatible {
                    TextField(
                        String(localized: "Base URL"),
                        text: $preferences.customBaseURL,
                        prompt: Text(verbatim: "https://api.example.com/v1")
                    )
                    .textFieldStyle(.roundedBorder)
                }

                HStack(spacing: 8) {
                    Picker(
                        String(localized: "Model"),
                        selection: Binding(
                            get: {
                                preferences.model(for: kind) ?? preferences.selectedModel
                            },
                            set: { newModel in
                                preferences.setModel(newModel, for: kind)
                                preferences.selectedModel = newModel
                            }
                        )
                    ) {
                        ForEach(modelChoices(for: kind), id: \.self) { modelName in
                            Text(modelName).tag(modelName)
                        }
                    }

                    Button {
                        Task { await store.refreshModelsForSelectedProvider() }
                    } label: {
                        Image(systemName: "arrow.clockwise")
                    }
                    .buttonStyle(.borderless)
                    .help(String(localized: "Refresh models from provider"))
                    .accessibilityLabel(String(localized: "Refresh models"))
                }

                HStack(spacing: 10) {
                    Button(String(localized: "Test")) {
                        preferences.enableContextualAI = true
                        Task { await store.test() }
                    }
                    .disabled(store.isTesting)

                    if store.isTesting {
                        ProgressView()
                            .controlSize(.small)
                        Text(String(localized: "Checking connection…"))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    } else if let result = store.lastTestResult {
                        Text(result.displayText)
                            .font(.caption)
                            .foregroundStyle(result.isConnected ? Color.green : Color.red)
                    }
                    Spacer(minLength: 0)
                }

                Text(privacySentence(for: kind))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    @ViewBuilder
    private func apiKeyControls(for kind: AIProviderKind) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                SecureField(
                    String(localized: "API Key"),
                    text: $apiKeyInput,
                    prompt: Text(String(localized: "Paste API key…"))
                )
                .textFieldStyle(.roundedBorder)

                Button(String(localized: "Check")) {
                    let trimmed = apiKeyInput.trimmingCharacters(in: .whitespacesAndNewlines)
                    preferences.enableContextualAI = true
                    if !trimmed.isEmpty {
                        try? store.saveKey(trimmed, for: kind)
                        apiKeyInput = ""
                    }
                    Task { await store.test() }
                }
                .disabled(apiKeyInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !store.hasKey(for: kind))

                Button(String(localized: "Save")) {
                    let trimmed = apiKeyInput.trimmingCharacters(in: .whitespacesAndNewlines)
                    guard !trimmed.isEmpty else { return }
                    preferences.enableContextualAI = true
                    try? store.saveKey(trimmed, for: kind)
                    apiKeyInput = ""
                }
                .disabled(apiKeyInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)

                if let portalURL = kind.keyPortalURL {
                    Link(String(localized: "Get a key"), destination: portalURL)
                        .font(.caption.weight(.medium))
                }
            }

            if store.hasKey(for: kind) {
                HStack(spacing: 8) {
                    let suffix = store.keyStore.keyLastFour(for: kind) ?? ""
                    Text(String(localized: "Stored in Keychain · …\(suffix)"))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Button(String(localized: "Remove")) {
                        try? store.removeKey(for: kind)
                        apiKeyInput = ""
                    }
                    .buttonStyle(.borderless)
                    .font(.caption)
                    Spacer(minLength: 0)
                }
            }
        }
    }

    private func modelChoices(for kind: AIProviderKind) -> [String] {
        var choices = store.availableModels
        if choices.isEmpty {
            choices = effectiveProvider.availableModels
        }
        let current = preferences.model(for: kind) ?? preferences.selectedModel
        if !current.isEmpty, !choices.contains(current) {
            choices.insert(current, at: 0)
        }
        if choices.isEmpty {
            choices = [String(localized: "Default")]
        }
        return choices
    }

    private func privacySentence(for kind: AIProviderKind) -> String {
        if kind.isLocal {
            return String(localized: "Stays on this Mac. Your messages are not sent anywhere. Only the messages you use with AI, and your draft. Never your keys or other chats.")
        }
        return String(localized: "Messages you use with AI are sent to \(kind.label). Only the messages you use with AI, and your draft. Never your keys or other chats.")
    }

    // MARK: - Custom Instructions

    private var customInstructionsSection: some View {
        Section(String(localized: "Contextual AI & Chat Assistant")) {
            VStack(alignment: .leading, spacing: 10) {
                Toggle(
                    String(localized: "Mention an AI to get answers and help in chat"),
                    isOn: $preferences.mentionAIInChats
                )
                TextField(
                    String(localized: "Custom instructions"),
                    text: $preferences.aiMentionsSystemPrompt,
                    prompt: Text(String(localized: "Keep answers brief and factual…"))
                )
                .textFieldStyle(.roundedBorder)
            }
        }
    }

    // MARK: - Translation Languages

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
                        let isLastEnabled = preferences.isLastEnabledTranslationLanguage(language)
                        Toggle(
                            language,
                            isOn: Binding(
                                get: { preferences.translationLanguages.contains(language) },
                                set: { enabled in
                                    preferences.setTranslationLanguage(language, enabled: enabled)
                                }
                            )
                        )
                        .toggleStyle(.checkbox)
                        .font(.caption)
                        .disabled(isLastEnabled)
                        .help(isLastEnabled ? AIPreferences.lastTranslationLanguageHelp : "")
                    }
                }
            }
            .settingAnchor("ai.translation", highlighted: highlightedSettingID)
        }
    }

    // MARK: - Talk to Type

    private var talkToTypeSection: some View {
        Section(String(localized: "Talk to Type & Voice Transcription")) {
            VStack(alignment: .leading, spacing: 10) {
                Text(String(localized: "Voice transcription isn’t wired up yet in Courier."))
                    .font(.caption)
                    .foregroundStyle(.secondary)
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

    // MARK: - Slash Commands

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
