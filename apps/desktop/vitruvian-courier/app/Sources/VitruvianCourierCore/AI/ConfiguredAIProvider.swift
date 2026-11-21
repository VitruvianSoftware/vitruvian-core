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

    public func summarizeArticle(title: String, site: String, text: String) async -> AIProviderDisposition {
        guard isAvailable else {
            return .unavailable(reason: AIClientError.notConfigured.message)
        }
        let turns = AIPrompts.summarizeArticle(
            title: title,
            site: site,
            text: text,
            characterLimit: kind.articleCharacterBudget,
            responseLanguage: responseLanguage,
            customInstructions: customInstructions
        )
        return await complete(turns)
    }

    /// True when this provider's service can search the web itself (Google AI Studio, OpenAI, Anthropic).
    public var supportsWebSearch: Bool {
        (client as? any WebSearchingClient)?.supportsWebSearch == true
    }

    public func findUnpaywalledSource(headline: String, site: String, description _: String) async -> AISourceSearchDisposition {
        guard isAvailable else {
            return .unavailable(reason: AIClientError.notConfigured.message)
        }
        guard let searcher = client as? any WebSearchingClient, searcher.supportsWebSearch else {
            return .unsupported
        }
        do {
            let sources = try await searcher.searchWeb(
                prompt: AIPrompts.findSourcePrompt(headline: headline, site: site),
                excludingDomain: site,
                model: model
            )
            return .sources(sources)
        } catch let error as AIClientError {
            return .unavailable(reason: error.message)
        } catch {
            return .unavailable(reason: AIClientError.unreachable.message)
        }
    }

    public func isSameStory(
        headline: String,
        description: String,
        candidateTitle: String,
        candidateText: String
    ) async -> AISameStoryDisposition {
        guard isAvailable else {
            return .unavailable(reason: AIClientError.notConfigured.message)
        }
        let turns = AIPrompts.sameStory(
            headline: headline,
            description: description,
            candidateTitle: candidateTitle,
            candidateText: candidateText
        )
        switch await complete(turns) {
        case let .unavailable(reason):
            return .unavailable(reason: reason)
        case let .text(answer):
            return AIPrompts.parseYesNo(answer) == true ? .same : .different
        }
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
