// Copyright 2026 VitruvianSoftware
// SPDX-License-Identifier: AGPL-3.0-or-later

import Combine
import Foundation

@MainActor
public final class AIProviderStore: ObservableObject {
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

    private var cancellables: Set<AnyCancellable> = []
    private let appleClientFactory: @Sendable () -> AppleOnDeviceClient

    public init(
        preferences: AIPreferences,
        keyStore: AIKeyStore = AIKeyStore(),
        transport: any HTTPTransport = URLSessionHTTPTransport.shared,
        detector: LocalProviderDetector? = nil,
        appleClientFactory: @escaping @Sendable () -> AppleOnDeviceClient = { AppleOnDeviceClient() }
    ) {
        self.preferences = preferences
        self.keyStore = keyStore
        self.transport = transport
        self.detector = detector ?? LocalProviderDetector(transport: transport)
        self.appleClientFactory = appleClientFactory

        observePreferences()
        rebuildProvider()
    }

    private func observePreferences() {
        preferences.objectWillChange
            .sink { [weak self] _ in
                Task { @MainActor [weak self] in
                    self?.handlePreferencesChanged()
                }
            }
            .store(in: &cancellables)
    }

    private func handlePreferencesChanged() {
        lastTestResult = nil
        syncAvailableModelsForCurrentSelection()
        rebuildProvider()
    }

    // MARK: - Keys

    public func hasKey(for kind: AIProviderKind) -> Bool {
        keyStore.hasKey(for: kind)
    }

    public func saveKey(_ key: String, for kind: AIProviderKind) throws {
        try keyStore.saveKey(key, for: kind)
        lastTestResult = nil
        rebuildProvider()
    }

    public func removeKey(for kind: AIProviderKind) throws {
        try keyStore.removeKey(for: kind)
        lastTestResult = nil
        rebuildProvider()
    }

    // MARK: - Detection & Models

    /// Re-runs local provider detection and refreshes models for the selected provider when AI is enabled.
    /// When AI is off (`enableContextualAI == false`), makes zero network requests.
    public func refresh() async {
        guard preferences.enableContextualAI else {
            availableModels = []
            lastTestResult = nil
            rebuildProvider()
            return
        }

        isDetecting = true
        let unslothKey = keyStore.key(for: .unslothStudio)
        let detected = await detector.detect(unslothKey: unslothKey)
        detections = detected
        isDetecting = false

        await refreshModelsForSelectedProvider()
        rebuildProvider()
    }

    /// Refreshes the model list for the currently selected provider when AI is enabled.
    public func refreshModelsForSelectedProvider() async {
        guard preferences.enableContextualAI else {
            availableModels = []
            rebuildProvider()
            return
        }

        let kind = preferences.selectedEngine
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

        guard let client = makeClient(for: kind) else {
            availableModels = []
            rebuildProvider()
            return
        }

        isLoadingModels = true
        defer { isLoadingModels = false }
        if let models = try? await client.listModels() {
            applyDiscoveredModels(models, for: kind)
            if kind.isLocal, kind != .appleIntelligence {
                detections[kind] = .running(models: models)
            }
        } else {
            availableModels = []
        }
        rebuildProvider()
    }

    /// Tests connectivity and model listing for the currently selected provider.
    @discardableResult
    public func test() async -> TestResult {
        guard preferences.enableContextualAI else {
            let result = TestResult.failure(AIClientError.notConfigured.message)
            lastTestResult = result
            return result
        }

        let kind = preferences.selectedEngine
        guard let client = makeClient(for: kind) else {
            let result = TestResult.failure(AIClientError.notConfigured.message)
            lastTestResult = result
            return result
        }

        isTesting = true
        defer { isTesting = false }

        do {
            let models = try await client.listModels()
            applyDiscoveredModels(models, for: kind)
            if kind.isLocal, kind != .appleIntelligence {
                detections[kind] = .running(models: models)
            }
            rebuildProvider()
            let result = TestResult.connected(modelCount: models.count)
            lastTestResult = result
            return result
        } catch let error as AIClientError {
            if kind == .unslothStudio, error == .badKey {
                detections[.unslothStudio] = .needsKey
            }
            rebuildProvider()
            let result = TestResult.failure(error.message)
            lastTestResult = result
            return result
        } catch {
            rebuildProvider()
            let result = TestResult.failure(AIClientError.unreachable.message)
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
            guard let key = keyStore.key(for: .unslothStudio) else { return nil }
            return OpenAICompatibleClient(
                baseURL: detector.unslothBaseURL,
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
            availableModels = status.isAvailable ? [AppleOnDeviceClient.modelName] : []
            return
        }
        if case let .running(models) = detections[kind] {
            availableModels = models
        }
    }

    private func applyDiscoveredModels(_ models: [String], for kind: AIProviderKind) {
        availableModels = models
        guard !models.isEmpty else { return }
        if let existing = preferences.model(for: kind), models.contains(existing) {
            if preferences.selectedEngine == kind, preferences.selectedModel != existing {
                preferences.selectedModel = existing
            }
        } else if let first = models.first {
            preferences.setModel(first, for: kind)
        }
    }

    public func rebuildProvider() {
        guard preferences.enableContextualAI else {
            provider = UnavailableAIProvider(
                reason: String(localized: "Turn on AI in Settings ▸ AI to use Courier AI features. Everything you write stays on this Mac.")
            )
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

        guard let client = makeClient(for: kind) else {
            provider = UnavailableAIProvider(reason: AIClientError.notConfigured.message)
            return
        }

        let resolvedModel = resolveModel(for: kind)
        guard !resolvedModel.isEmpty else {
            provider = UnavailableAIProvider(reason: AIClientError.notConfigured.message)
            return
        }

        let modelsList = availableModels.isEmpty ? [resolvedModel] : availableModels
        provider = ConfiguredAIProvider(
            kind: kind,
            client: client,
            model: resolvedModel,
            availableModels: modelsList,
            responseLanguage: preferences.responseLanguage,
            customInstructions: preferences.aiMentionsSystemPrompt
        )
    }

    private func resolveModel(for kind: AIProviderKind) -> String {
        if let perProvider = preferences.model(for: kind) {
            return perProvider
        }
        if let firstAvailable = availableModels.first, !firstAvailable.isEmpty {
            return firstAvailable
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
