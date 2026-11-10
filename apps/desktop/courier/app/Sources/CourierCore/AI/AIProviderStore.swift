// Copyright 2026 VitruvianSoftware
// SPDX-License-Identifier: AGPL-3.0-or-later

import AppKit
import Combine
import Foundation

@MainActor
public final class AIProviderStore: ObservableObject {
    public enum LocalRowAction: Equatable, Sendable {
        case none
        case openApp(title: String)
        case getApp(title: String, url: URL)
    }

    public enum TestResult: Equatable, Sendable {
        case connected(modelCount: Int)
        case failure(String)

        public var displayText: String {
            switch self {
            case let .connected(count):
                count == 1
                    ? String(localized: "Connected, 1 model")
                    : String(localized: "Connected, \(count) models")
            case let .failure(message):
                message
            }
        }

        public var isConnected: Bool {
            if case .connected = self { return true }
            return false
        }
    }

    public let preferences: AIPreferences
    public let keyStore: AIKeyStore
    public let transport: any HTTPTransport
    public let detector: LocalProviderDetector

    @Published public private(set) var provider: any AIProvider = UnavailableAIProvider()
    @Published public private(set) var detections: [AIProviderKind: LocalDetection] = [:]
    @Published public private(set) var availableModels: [String] = []
    @Published public private(set) var isDetecting: Bool = false
    @Published public private(set) var isLoadingModels: Bool = false
    @Published public private(set) var isTesting: Bool = false
    @Published public private(set) var lastTestResult: TestResult?
    @Published public private(set) var keyError: String?
    @Published public private(set) var isSettingsDetectionActive: Bool = false

    public let settingsDetectionInterval: Duration
    public var isAppInstalled: @Sendable (AIProviderKind) -> Bool
    public var openLocalApp: @MainActor (AIProviderKind) -> Void
    private var settingsDetectionTask: Task<Void, Never>?
    private var modelLoadTask: Task<Void, Never>?
    private var modelLoadToken: UInt64 = 0
    private var currentEngineForModels: AIProviderKind?
    private var wasEnabled: Bool = false
    private var isApplyingInternalPreferenceUpdate: Bool = false
    private var cancellables: Set<AnyCancellable> = []
    private let appleClientFactory: @Sendable () -> AppleOnDeviceClient

    public init(
        preferences: AIPreferences,
        keyStore: AIKeyStore = AIKeyStore(),
        transport: any HTTPTransport = URLSessionHTTPTransport.shared,
        detector: LocalProviderDetector? = nil,
        settingsDetectionInterval: Duration = .seconds(30),
        isAppInstalled: @escaping @Sendable (AIProviderKind) -> Bool = { kind in
            guard let url = kind.localAppURL else { return false }
            return FileManager.default.fileExists(atPath: url.path)
        },
        openLocalApp: @escaping @MainActor (AIProviderKind) -> Void = { kind in
            guard let url = kind.localAppURL else { return }
            NSWorkspace.shared.open(url)
        },
        appleClientFactory: @escaping @Sendable () -> AppleOnDeviceClient = { AppleOnDeviceClient() }
    ) {
        self.preferences = preferences
        self.keyStore = keyStore
        self.transport = transport
        self.detector = detector ?? LocalProviderDetector(transport: transport)
        self.settingsDetectionInterval = settingsDetectionInterval
        self.isAppInstalled = isAppInstalled
        self.openLocalApp = openLocalApp
        self.appleClientFactory = appleClientFactory

        self.wasEnabled = preferences.enableContextualAI
        self.currentEngineForModels = preferences.enableContextualAI ? preferences.selectedEngine : nil
        observePreferences()
        rebuildProvider()
    }

    deinit {
        settingsDetectionTask?.cancel()
        modelLoadTask?.cancel()
    }

    private func observePreferences() {
        preferences.didChange
            .sink { [weak self] _ in
                guard let self, !self.isApplyingInternalPreferenceUpdate else { return }
                self.handlePreferencesChanged()
            }
            .store(in: &cancellables)
    }

    private func withInternalPreferenceUpdate(_ body: () -> Void) {
        let previous = isApplyingInternalPreferenceUpdate
        isApplyingInternalPreferenceUpdate = true
        defer { isApplyingInternalPreferenceUpdate = previous }
        body()
    }

    private func cancelModelLoad() {
        modelLoadToken &+= 1
        modelLoadTask?.cancel()
        modelLoadTask = nil
        isLoadingModels = false
    }

    private func startModelLoadTask(for kind: AIProviderKind) -> Task<Void, Never>? {
        cancelModelLoad()
        guard preferences.enableContextualAI,
              preferences.selectedEngine == kind,
              kind != .appleIntelligence,
              let client = makeClient(for: kind)
        else {
            return nil
        }
        modelLoadToken &+= 1
        let token = modelLoadToken
        isLoadingModels = true
        let task = Task { @MainActor [weak self] in
            guard let self, !Task.isCancelled else { return }
            defer {
                if self.modelLoadToken == token {
                    self.isLoadingModels = false
                    self.modelLoadTask = nil
                }
            }
            let fetchedModels: [String]?
            do {
                fetchedModels = try await client.listModels()
            } catch {
                fetchedModels = nil
            }
            guard !Task.isCancelled,
                  self.modelLoadToken == token,
                  self.preferences.enableContextualAI,
                  self.preferences.selectedEngine == kind
            else {
                return
            }
            if let models = fetchedModels {
                self.applyDiscoveredModels(models, for: kind)
                if kind.isLocal, kind != .appleIntelligence {
                    self.detections[kind] = .running(models: models)
                }
            } else {
                self.availableModels = []
            }
            self.rebuildProvider()
        }
        modelLoadTask = task
        return task
    }

    /// Selects `kind`, turns AI on, clears any stale models from a previous provider, and loads `kind`'s model list at once.
    public func selectProvider(_ kind: AIProviderKind) {
        let changedProvider = preferences.selectedEngine != kind || !preferences.enableContextualAI
        withInternalPreferenceUpdate {
            preferences.selectedEngine = kind
            preferences.enableContextualAI = true
        }
        if changedProvider {
            availableModels = []
        }
        currentEngineForModels = kind
        wasEnabled = true
        lastTestResult = nil
        keyError = nil
        syncAvailableModelsForCurrentSelection()
        rebuildProvider()
        if availableModels.isEmpty {
            _ = startModelLoadTask(for: kind)
        } else {
            cancelModelLoad()
        }
    }

    private func handlePreferencesChanged() {
        lastTestResult = nil
        guard preferences.enableContextualAI else {
            cancelModelLoad()
            availableModels = []
            currentEngineForModels = nil
            wasEnabled = false
            rebuildProvider()
            return
        }
        let kind = preferences.selectedEngine
        let providerChanged = currentEngineForModels != kind || !wasEnabled
        currentEngineForModels = kind
        wasEnabled = true
        if providerChanged {
            cancelModelLoad()
            availableModels = []
            keyError = nil
        }
        syncAvailableModelsForCurrentSelection()
        rebuildProvider()
        if providerChanged, availableModels.isEmpty {
            _ = startModelLoadTask(for: kind)
        }
    }

    // MARK: - Keys

    public func hasKey(for kind: AIProviderKind) -> Bool {
        keyStore.hasKey(for: kind)
    }

    public func clearKeyError() {
        keyError = nil
    }

    @discardableResult
    public func saveKey(_ key: String, for kind: AIProviderKind) -> Result<Void, AIKeyStoreError> {
        let result = keyStore.saveKey(key, for: kind)
        switch result {
        case .success:
            keyError = nil
            lastTestResult = nil
            rebuildProvider()
        case let .failure(error):
            keyError = error.message
        }
        return result
    }

    @discardableResult
    public func removeKey(for kind: AIProviderKind) -> Result<Void, AIKeyStoreError> {
        let result = keyStore.removeKey(for: kind)
        switch result {
        case .success:
            keyError = nil
            lastTestResult = nil
            rebuildProvider()
        case let .failure(error):
            keyError = error.message
        }
        return result
    }

    // MARK: - Detection & Models

    /// Starts periodic local-only provider detection while Settings ▸ AI is open (re-detecting every 30 s).
    /// Runs even when AI is Off so the provider list can display what is installed/running on this Mac.
    public func startSettingsDetection() {
        isSettingsDetectionActive = true
        settingsDetectionTask?.cancel()
        let interval = settingsDetectionInterval
        settingsDetectionTask = Task { @MainActor [weak self] in
            guard let self, !Task.isCancelled, self.isSettingsDetectionActive else { return }
            await self.refresh()
            while !Task.isCancelled, self.isSettingsDetectionActive {
                try? await Task.sleep(for: interval)
                guard !Task.isCancelled, self.isSettingsDetectionActive else { break }
                await self.refreshLocalDetections()
            }
        }
    }

    /// Stops periodic Settings ▸ AI local provider detection.
    public func stopSettingsDetection() {
        isSettingsDetectionActive = false
        settingsDetectionTask?.cancel()
        settingsDetectionTask = nil
        cancelModelLoad()
        isDetecting = false
    }

    /// Probes local servers (`127.0.0.1` only). Safe to run while Settings ▸ AI is open even when AI is Off.
    public func refreshLocalDetections() async {
        guard !Task.isCancelled, preferences.enableContextualAI || isSettingsDetectionActive else {
            return
        }
        isDetecting = true
        let unslothKey = keyStore.key(for: .unslothStudio)
        let detected = await detector.detect(unslothKey: unslothKey)
        guard !Task.isCancelled, preferences.enableContextualAI || isSettingsDetectionActive else {
            isDetecting = false
            return
        }
        detections = detected
        isDetecting = false

        if preferences.enableContextualAI {
            let selected = preferences.selectedEngine
            if let localDetection = detected[selected],
               case let .running(models) = localDetection
            {
                applyDiscoveredModels(models, for: selected)
            }
            rebuildProvider()
        }
    }

    /// Re-runs local provider detection and refreshes models for the selected provider when AI is enabled.
    /// When AI is off (`enableContextualAI == false`) and Settings ▸ AI is closed, makes zero network requests.
    /// While Settings ▸ AI is open (`isSettingsDetectionActive == true`), probes localhost only.
    public func refresh() async {
        cancelModelLoad()
        guard !Task.isCancelled else { return }
        guard preferences.enableContextualAI else {
            if isSettingsDetectionActive {
                await refreshLocalDetections()
            }
            guard !Task.isCancelled else { return }
            availableModels = []
            lastTestResult = nil
            rebuildProvider()
            return
        }

        isDetecting = true
        let unslothKey = keyStore.key(for: .unslothStudio)
        let detected = await detector.detect(unslothKey: unslothKey)
        guard !Task.isCancelled else {
            isDetecting = false
            return
        }
        detections = detected
        isDetecting = false

        await refreshModelsForSelectedProvider()
        guard !Task.isCancelled else { return }
        rebuildProvider()
    }

    /// Refreshes the model list for the currently selected provider when AI is enabled.
    public func refreshModelsForSelectedProvider() async {
        cancelModelLoad()
        guard !Task.isCancelled else { return }
        guard preferences.enableContextualAI else {
            availableModels = []
            rebuildProvider()
            return
        }

        let kind = preferences.selectedEngine
        if kind == .appleIntelligence {
            syncAvailableModelsForCurrentSelection()
            rebuildProvider()
            return
        }

        if let localDetection = detections[kind] {
            switch localDetection {
            case let .running(models):
                applyDiscoveredModels(models, for: kind)
                rebuildProvider()
                return
            case .needsKey where !hasKey(for: kind):
                availableModels = []
                rebuildProvider()
                return
            case .notRunning:
                availableModels = []
                rebuildProvider()
                return
            default:
                break
            }
        }

        guard let task = startModelLoadTask(for: kind) else {
            if preferences.selectedEngine == kind {
                availableModels = []
                rebuildProvider()
            }
            return
        }
        await task.value
    }

    /// Tests connectivity and model listing for the currently selected provider.
    @discardableResult
    public func test() async -> TestResult {
        cancelModelLoad()
        guard preferences.enableContextualAI else {
            let result = TestResult.failure(AIClientError.notConfigured.message)
            lastTestResult = result
            return result
        }

        let kind = preferences.selectedEngine
        if kind == .unslothStudio, detector.unslothBaseURL == nil {
            let result = TestResult.failure(
                String(localized: "Unsloth Studio is not running on this Mac. Start it and click Refresh in Settings ▸ AI.")
            )
            lastTestResult = result
            return result
        }
        guard let client = makeClient(for: kind) else {
            let result = TestResult.failure(AIClientError.notConfigured.message)
            lastTestResult = result
            return result
        }

        isTesting = true
        defer { isTesting = false }

        do {
            let models = try await client.listModels()
            let result = TestResult.connected(modelCount: models.count)
            guard !Task.isCancelled,
                  preferences.enableContextualAI,
                  preferences.selectedEngine == kind
            else {
                return result
            }
            applyDiscoveredModels(models, for: kind)
            if kind.isLocal, kind != .appleIntelligence {
                detections[kind] = .running(models: models)
            }
            rebuildProvider()
            lastTestResult = result
            return result
        } catch let error as AIClientError {
            let result = TestResult.failure(error.message)
            guard !Task.isCancelled,
                  preferences.enableContextualAI,
                  preferences.selectedEngine == kind
            else {
                return result
            }
            if kind == .unslothStudio, error == .badKey {
                detections[.unslothStudio] = .needsKey
            }
            rebuildProvider()
            lastTestResult = result
            return result
        } catch {
            let result = TestResult.failure(AIClientError.unreachable.message)
            guard !Task.isCancelled,
                  preferences.enableContextualAI,
                  preferences.selectedEngine == kind
            else {
                return result
            }
            rebuildProvider()
            lastTestResult = result
            return result
        }
    }

    // MARK: - UI State Helpers

    public var statusBannerText: String {
        guard preferences.enableContextualAI else {
            return String(localized: "AI is off")
        }
        if let configured = provider as? ConfiguredAIProvider, configured.isAvailable {
            return "\(configured.kind.label) · \(configured.model)"
        }
        return String(localized: "Set up a provider")
    }

    public func stateText(for kind: AIProviderKind) -> String {
        switch kind {
        case .appleIntelligence:
            let status = appleClientFactory().availability
            return status.isAvailable ? String(localized: "1 model") : String(localized: "Not running")
        case .ollama, .lmStudio:
            switch detections[kind] {
            case let .running(models):
                return models.count == 1
                    ? String(localized: "1 model")
                    : String(localized: "\(models.count) models")
            case .needsKey:
                return String(localized: "Needs key")
            case .notRunning, nil:
                return String(localized: "Not running")
            }
        case .unslothStudio:
            switch detections[.unslothStudio] {
            case let .running(models):
                return models.count == 1
                    ? String(localized: "1 model")
                    : String(localized: "\(models.count) models")
            case .needsKey:
                return hasKey(for: .unslothStudio)
                    ? String(localized: "Key saved")
                    : String(localized: "Needs key")
            case .notRunning, nil:
                return String(localized: "Not running")
            }
        case .anthropic, .googleAIStudio, .openAI:
            return hasKey(for: kind)
                ? String(localized: "Key saved")
                : String(localized: "Needs key")
        case .customOpenAICompatible:
            let hasURL = Self.normalizedBaseURL(from: preferences.customBaseURL) != nil
            guard hasURL else { return String(localized: "Not set up") }
            return hasKey(for: .customOpenAICompatible)
                ? String(localized: "Key saved")
                : String(localized: "Set up")
        }
    }

    /// Detailed row state text for the "On this Mac" list in Settings ▸ AI, distinguishing running, installed-not-running, and not found.
    public func localRowStateText(for kind: AIProviderKind) -> String {
        switch kind {
        case .appleIntelligence:
            let status = appleClientFactory().availability
            return status.isAvailable
                ? String(localized: "Found · 1 model · Stays on this Mac")
                : status.reason
        case .ollama, .lmStudio:
            switch detections[kind] {
            case let .running(models):
                let countText = models.count == 1
                    ? String(localized: "1 model")
                    : String(localized: "\(models.count) models")
                return String(localized: "Found · \(countText) · Stays on this Mac")
            case .needsKey:
                return String(localized: "Found · Needs key")
            case .notRunning, nil:
                return isAppInstalled(kind)
                    ? String(localized: "Installed · not running")
                    : String(localized: "Not found")
            }
        case .unslothStudio:
            switch detections[.unslothStudio] {
            case let .running(models):
                let countText = models.count == 1
                    ? String(localized: "1 model")
                    : String(localized: "\(models.count) models")
                return String(localized: "Found · \(countText) · Stays on this Mac")
            case .needsKey:
                return hasKey(for: .unslothStudio)
                    ? String(localized: "Found · Key saved")
                    : String(localized: "Found · Needs key")
            case .notRunning, nil:
                return isAppInstalled(.unslothStudio)
                    ? String(localized: "Installed · not running")
                    : String(localized: "Not found")
            }
        default:
            return stateText(for: kind)
        }
    }

    /// Trailing row action for an "On this Mac" provider row (`Open <app>` when installed-not-running, `Get <app>` when not installed).
    public func localRowAction(for kind: AIProviderKind) -> LocalRowAction {
        guard kind.isLocal, kind != .appleIntelligence else { return .none }
        switch detections[kind] {
        case .running, .needsKey:
            return .none
        case .notRunning, nil:
            if isAppInstalled(kind) {
                return .openApp(title: String(localized: "Open \(kind.shortAppName)"))
            }
            if let url = kind.downloadURL {
                return .getApp(title: String(localized: "Get \(kind.shortAppName)"), url: url)
            }
            return .none
        }
    }

    // MARK: - Provider Construction

    public func makeClient(for kind: AIProviderKind) -> (any ChatModelClient)? {
        switch kind {
        case .appleIntelligence:
            return appleClientFactory()
        case .ollama:
            guard let baseURL = kind.defaultBaseURL else { return nil }
            return OpenAICompatibleClient(baseURL: baseURL, key: nil, isLocal: true, transport: transport)
        case .lmStudio:
            guard let baseURL = kind.defaultBaseURL else { return nil }
            return OpenAICompatibleClient(baseURL: baseURL, key: nil, isLocal: true, transport: transport)
        case .unslothStudio:
            guard let key = keyStore.key(for: .unslothStudio),
                  let baseURL = detector.unslothBaseURL
            else { return nil }
            return OpenAICompatibleClient(
                baseURL: baseURL,
                key: key,
                isLocal: true,
                transport: transport
            )
        case .anthropic:
            guard let key = keyStore.key(for: .anthropic) else { return nil }
            return AnthropicClient(apiKey: key, transport: transport)
        case .googleAIStudio:
            guard let key = keyStore.key(for: .googleAIStudio) else { return nil }
            return GeminiClient(apiKey: key, transport: transport)
        case .openAI:
            guard let key = keyStore.key(for: .openAI),
                  let baseURL = kind.defaultBaseURL
            else { return nil }
            return OpenAICompatibleClient(baseURL: baseURL, key: key, isLocal: false, transport: transport)
        case .customOpenAICompatible:
            guard let baseURL = Self.normalizedBaseURL(from: preferences.customBaseURL) else { return nil }
            let key = keyStore.key(for: .customOpenAICompatible)
            return OpenAICompatibleClient(baseURL: baseURL, key: key, transport: transport)
        }
    }

    private func syncAvailableModelsForCurrentSelection() {
        guard preferences.enableContextualAI else {
            availableModels = []
            return
        }
        let kind = preferences.selectedEngine
        if kind == .appleIntelligence {
            let status = appleClientFactory().availability
            let models = status.isAvailable ? [AppleOnDeviceClient.modelName] : []
            applyDiscoveredModels(models, for: .appleIntelligence)
            return
        }
        if case let .running(models) = detections[kind] {
            applyDiscoveredModels(models, for: kind)
        } else if kind.isLocal {
            availableModels = []
        }
    }

    private func applyDiscoveredModels(_ models: [String], for kind: AIProviderKind) {
        guard !Task.isCancelled,
              preferences.enableContextualAI,
              preferences.selectedEngine == kind
        else {
            return
        }
        availableModels = models
        withInternalPreferenceUpdate {
            guard !models.isEmpty else {
                if preferences.selectedEngine == kind, !preferences.selectedModel.isEmpty {
                    preferences.selectedModel = ""
                }
                return
            }
            if let existing = preferences.model(for: kind), models.contains(existing) {
                if preferences.selectedEngine == kind, preferences.selectedModel != existing {
                    preferences.selectedModel = existing
                }
            } else if let first = models.first {
                preferences.setModel(first, for: kind)
                if preferences.selectedEngine == kind, preferences.selectedModel != first {
                    preferences.selectedModel = first
                }
            }
        }
    }

    public func rebuildProvider() {
        guard preferences.enableContextualAI else {
            provider = UnavailableAIProvider()
            return
        }

        let kind = preferences.selectedEngine
        if kind == .appleIntelligence {
            let apple = appleClientFactory()
            let status = apple.availability
            guard status.isAvailable else {
                provider = UnavailableAIProvider(reason: status.reason)
                return
            }
            let model = AppleOnDeviceClient.modelName
            availableModels = [model]
            provider = ConfiguredAIProvider(
                kind: .appleIntelligence,
                client: apple,
                model: model,
                availableModels: [model],
                responseLanguage: preferences.responseLanguage,
                customInstructions: preferences.aiMentionsSystemPrompt
            )
            return
        }

        if kind.isLocal {
            if kind == .unslothStudio, detector.unslothBaseURL == nil {
                provider = UnavailableAIProvider(
                    reason: String(localized: "Unsloth Studio is not running on this Mac. Start it and click Refresh in Settings ▸ AI.")
                )
                return
            }
            switch detections[kind] {
            case .notRunning:
                provider = UnavailableAIProvider(
                    reason: String(localized: "\(kind.label) is not running on this Mac. Start it and click Refresh in Settings ▸ AI.")
                )
                return
            case .needsKey where !hasKey(for: kind):
                provider = UnavailableAIProvider(
                    reason: String(localized: "Enter your \(kind.label) API key in Settings ▸ AI.")
                )
                return
            default:
                break
            }
        }

        if kind.needsKey, !hasKey(for: kind) {
            provider = UnavailableAIProvider(
                reason: String(localized: "Enter your \(kind.label) API key in Settings ▸ AI.")
            )
            return
        }

        guard let client = makeClient(for: kind) else {
            provider = UnavailableAIProvider(reason: AIClientError.notConfigured.message)
            return
        }

        let resolvedModel = resolveModel(for: kind)
        guard !resolvedModel.isEmpty else {
            if kind.isLocal, kind != .appleIntelligence {
                provider = UnavailableAIProvider(
                    reason: String(localized: "\(kind.label) is not running on this Mac. Start it and click Refresh in Settings ▸ AI.")
                )
            } else {
                provider = UnavailableAIProvider(reason: AIClientError.notConfigured.message)
            }
            return
        }

        provider = ConfiguredAIProvider(
            kind: kind,
            client: client,
            model: resolvedModel,
            availableModels: availableModels,
            responseLanguage: preferences.responseLanguage,
            customInstructions: preferences.aiMentionsSystemPrompt
        )
    }

    private func resolveModel(for kind: AIProviderKind) -> String {
        if !availableModels.isEmpty {
            if let perProvider = preferences.model(for: kind), availableModels.contains(perProvider) {
                return perProvider
            }
            if let firstAvailable = availableModels.first {
                return firstAvailable
            }
        }
        if let perProvider = preferences.model(for: kind), !perProvider.isEmpty {
            return perProvider
        }
        let legacyPlaceholder = String(localized: "On-Device (Not available yet)")
        let trimmedSelected = preferences.selectedModel.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmedSelected.isEmpty, trimmedSelected != legacyPlaceholder {
            return trimmedSelected
        }
        return ""
    }

    private static func normalizedBaseURL(from raw: String) -> URL? {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty,
              let url = URL(string: trimmed),
              let scheme = url.scheme?.lowercased(),
              scheme == "http" || scheme == "https",
              let host = url.host,
              !host.isEmpty
        else {
            return nil
        }
        return url
    }
}
