// Copyright 2026 VitruvianSoftware
// SPDX-License-Identifier: AGPL-3.0-or-later

import Foundation

public struct ConfiguredAIProvider: AIProvider, Sendable {
    public let kind: AIProviderKind
    public let client: any ChatModelClient
    public let model: String
    public let availableModels: [String]
    public let responseLanguage: String
    public let customInstructions: String

    public init(
        kind: AIProviderKind = .openAI,
        client: any ChatModelClient,
        model: String,
        availableModels: [String]? = nil,
        responseLanguage: String = "English",
        customInstructions: String = ""
    ) {
        self.kind = kind
        self.client = client
        self.model = model.trimmingCharacters(in: .whitespacesAndNewlines)
        if let availableModels, !availableModels.isEmpty {
            self.availableModels = availableModels
        } else {
            self.availableModels = self.model.isEmpty ? [] : [self.model]
        }
        self.responseLanguage = responseLanguage
        self.customInstructions = customInstructions
    }

    public var isAvailable: Bool {
        !model.isEmpty
    }

    public var unavailableReason: String {
        isAvailable ? "" : AIClientError.notConfigured.message
    }

    public func draftResponse(
        context: AIChatContext,
        draft: String,
        tone: AIRewriteTone?
    ) async -> AIProviderDisposition {
        guard isAvailable else {
            return .unavailable(reason: AIClientError.notConfigured.message)
        }
        let turns = AIPrompts.draft(
            context: context,
            draft: draft,
            tone: tone,
            responseLanguage: responseLanguage,
            customInstructions: customInstructions
        )
        return await complete(turns)
    }

    public func translate(
        text: String,
        targetLanguage: String
    ) async -> AIProviderDisposition {
        guard isAvailable else {
            return .unavailable(reason: AIClientError.notConfigured.message)
        }
        let turns = AIPrompts.translate(
            text: text,
            targetLanguage: targetLanguage,
            responseLanguage: responseLanguage,
            customInstructions: customInstructions
        )
        return await complete(turns)
    }

    public func summarize(context: AIChatContext) async -> AIProviderDisposition {
        guard isAvailable else {
            return .unavailable(reason: AIClientError.notConfigured.message)
        }
        let turns = AIPrompts.summarize(
            context: context,
            responseLanguage: responseLanguage,
            customInstructions: customInstructions
        )
        return await complete(turns)
    }

    public func transcribeVoiceNote(roomID _: String, eventID _: String) async -> AIProviderDisposition {
        .unavailable(reason: String(localized: "Voice-note transcription isn’t available yet in Courier."))
    }

    public func startTalkToType() async -> AIProviderDisposition {
        .unavailable(reason: String(localized: "Talk to Type isn’t available yet in Courier."))
    }

    private func complete(_ turns: [AIChatTurn]) async -> AIProviderDisposition {
        do {
            let output = try await client.complete(turns, model: model)
            return .text(output)
        } catch let error as AIClientError {
            return .unavailable(reason: error.message)
        } catch {
            return .unavailable(reason: AIClientError.unreachable.message)
        }
    }
}
