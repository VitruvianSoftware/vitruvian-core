// Copyright 2026 VitruvianSoftware
// SPDX-License-Identifier: AGPL-3.0-or-later

import Foundation
import XCTest

@testable import CourierCore

@MainActor
final class AIProvidersTests: XCTestCase {
    override func tearDown() async throws {
        AppLockGate.shared.resetForTesting()
    }

    // MARK: - AIProviderKind & AIEngineChoice

    func testAIProviderKindCasesRawValuesAndMetadata() {
        // Keep the three existing raw values for UserDefaults compatibility
        XCTAssertEqual(AIEngineChoice.appleIntelligence.rawValue, "appleIntelligence")
        XCTAssertEqual(AIEngineChoice.openAI.rawValue, "openAI")
        XCTAssertEqual(AIEngineChoice.customOpenAICompatible.rawValue, "customOpenAICompatible")

        XCTAssertEqual(
            AIProviderKind.allCases,
            [
                .appleIntelligence,
                .ollama,
                .lmStudio,
                .unslothStudio,
                .anthropic,
                .googleAIStudio,
                .openAI,
                .customOpenAICompatible,
            ]
        )

        for kind in AIProviderKind.localProviders {
            XCTAssertTrue(kind.isLocal, "\(kind) must be local")
            XCTAssertEqual(kind.privacyNotice, "Stays on this Mac.")
        }
        for kind in AIProviderKind.cloudProviders {
            XCTAssertFalse(kind.isLocal, "\(kind) must be cloud")
            XCTAssertTrue(kind.privacyNotice.contains(kind.label))
        }

        XCTAssertTrue(AIProviderKind.anthropic.needsKey)
        XCTAssertTrue(AIProviderKind.googleAIStudio.needsKey)
        XCTAssertTrue(AIProviderKind.openAI.needsKey)
        XCTAssertTrue(AIProviderKind.unslothStudio.needsKey)
        XCTAssertFalse(AIProviderKind.appleIntelligence.needsKey)
        XCTAssertFalse(AIProviderKind.ollama.needsKey)
        XCTAssertFalse(AIProviderKind.lmStudio.needsKey)
        XCTAssertFalse(AIProviderKind.customOpenAICompatible.needsKey)
        XCTAssertTrue(AIProviderKind.unslothStudio.acceptsKey)
        XCTAssertTrue(AIProviderKind.customOpenAICompatible.acceptsKey)

        XCTAssertEqual(AIProviderKind.ollama.defaultBaseURL?.absoluteString, "http://127.0.0.1:11434/v1")
        XCTAssertEqual(AIProviderKind.lmStudio.defaultBaseURL?.absoluteString, "http://127.0.0.1:1234/v1")
        XCTAssertEqual(AIProviderKind.openAI.defaultBaseURL?.absoluteString, "https://api.openai.com/v1")
        XCTAssertNil(AIProviderKind.appleIntelligence.defaultBaseURL)
        XCTAssertNil(AIProviderKind.customOpenAICompatible.defaultBaseURL)
    }

    // MARK: - AnthropicClient

    func testAnthropicClientListModelsAndCompleteAndErrors() async throws {
        let transport = StubHTTPTransport()
        let secretKey = "test-anthropic-token"
        let client = AnthropicClient(apiKey: secretKey, transport: transport)

        // 1. listModels success
        transport.enqueue(
            status: 200,
            json: #"{"data":[{"id":"claude-sonnet-4-20250514"},{"id":"claude-3-5-haiku-latest"}]}"#
        )
        let models = try await client.listModels()
        XCTAssertEqual(models, ["claude-sonnet-4-20250514", "claude-3-5-haiku-latest"])

        let listReq = try XCTUnwrap(transport.requests.first)
        XCTAssertEqual(listReq.httpMethod, "GET")
        XCTAssertEqual(listReq.url?.absoluteString, "https://api.anthropic.com/v1/models")
        XCTAssertFalse(listReq.url?.absoluteString.contains(secretKey) ?? true, "API key must never appear in URL")
        XCTAssertEqual(listReq.value(forHTTPHeaderField: "x-api-key"), secretKey)
        XCTAssertEqual(listReq.value(forHTTPHeaderField: "anthropic-version"), "2023-06-01")
        XCTAssertEqual(listReq.timeoutInterval, 2.0, accuracy: 0.01)

        // 2. complete success
        transport.reset()
        transport.enqueue(
            status: 200,
            json: #"{"id":"msg_1","type":"message","content":[{"type":"text","text":"Sounds good, see you at 9!"}]}"#
        )
        let turns = [
            AIChatTurn(role: .system, text: "Be brief."),
            AIChatTurn(role: .user, text: "Alice: Are we meeting at 9?"),
        ]
        let reply = try await client.complete(turns, model: "claude-sonnet-4-20250514")
        XCTAssertEqual(reply, "Sounds good, see you at 9!")

        let completeReq = try XCTUnwrap(transport.requests.first)
        XCTAssertEqual(completeReq.httpMethod, "POST")
        XCTAssertEqual(completeReq.url?.absoluteString, "https://api.anthropic.com/v1/messages")
        XCTAssertFalse(completeReq.url?.absoluteString.contains(secretKey) ?? true, "API key must never appear in URL")
        XCTAssertEqual(completeReq.value(forHTTPHeaderField: "x-api-key"), secretKey)
        XCTAssertEqual(completeReq.value(forHTTPHeaderField: "anthropic-version"), "2023-06-01")
        XCTAssertEqual(completeReq.value(forHTTPHeaderField: "Content-Type"), "application/json")
        XCTAssertEqual(completeReq.timeoutInterval, 60.0, accuracy: 0.01)

        let bodyData = try XCTUnwrap(StubHTTPTransport.bodyData(of: completeReq))
        let bodyJSON = try XCTUnwrap(JSONSerialization.jsonObject(with: bodyData) as? [String: Any])
        XCTAssertEqual(bodyJSON["model"] as? String, "claude-sonnet-4-20250514")
        XCTAssertEqual(bodyJSON["max_tokens"] as? Int, 1024)
        XCTAssertEqual(bodyJSON["system"] as? String, "Be brief.")
        let sentMessages = try XCTUnwrap(bodyJSON["messages"] as? [[String: String]])
        XCTAssertEqual(sentMessages, [["role": "user", "content": "Alice: Are we meeting at 9?"]])

        // 3. 401 -> .badKey
        transport.enqueue(status: 401, json: #"{"error":{"message":"invalid x-api-key"}}"#)
        await assertThrowsClientError(try await client.complete(turns, model: "claude-sonnet-4-20250514"), expected: .badKey)

        // 4. 429 -> .rateLimited
        transport.enqueue(status: 429, json: #"{"error":{"message":"rate limit exceeded"}}"#)
        await assertThrowsClientError(try await client.complete(turns, model: "claude-sonnet-4-20250514"), expected: .rateLimited)

        // 5. Provider error body (400)
        transport.enqueue(status: 400, json: #"{"error":{"type":"invalid_request_error","message":"Credit balance is too low"}}"#)
        await assertThrowsClientError(
            try await client.complete(turns, model: "claude-sonnet-4-20250514"),
            expected: .server(status: 400, message: "Credit balance is too low")
        )
    }

    // MARK: - GeminiClient

    func testGeminiClientListModelsAndCompleteAndErrors() async throws {
        let transport = StubHTTPTransport()
        let secretKey = "test-gemini-token"
        let client = GeminiClient(apiKey: secretKey, transport: transport)

        // 1. listModels filters by generateContent and strips models/ prefix
        transport.enqueue(
            status: 200,
            json: #"""
            {
              "models": [
                {"name": "models/gemini-2.5-flash", "supportedGenerationMethods": ["generateContent", "countTokens"]},
                {"name": "models/text-embedding-004", "supportedGenerationMethods": ["embedContent"]},
                {"name": "models/gemini-2.5-pro", "supportedGenerationMethods": ["generateContent"]}
              ]
            }
            """#
        )
        let models = try await client.listModels()
        XCTAssertEqual(models, ["gemini-2.5-flash", "gemini-2.5-pro"])

        let listReq = try XCTUnwrap(transport.requests.first)
        XCTAssertEqual(listReq.httpMethod, "GET")
        XCTAssertEqual(listReq.url?.absoluteString, "https://generativelanguage.googleapis.com/v1beta/models")
        XCTAssertFalse(listReq.url?.absoluteString.contains(secretKey) ?? true, "Gemini key must never be in the URL")
        XCTAssertNil(listReq.url?.query, "Gemini URL must have no query parameters")
        XCTAssertEqual(listReq.value(forHTTPHeaderField: "x-goog-api-key"), secretKey)

        // 2. complete success
        transport.reset()
        transport.enqueue(
            status: 200,
            json: #"{"candidates":[{"content":{"parts":[{"text":"Hola, ¿cómo estás?"}]}}]}"#
        )
        let turns = [
            AIChatTurn(role: .system, text: "Translate accurately."),
            AIChatTurn(role: .user, text: "Hello, how are you?"),
        ]
        let output = try await client.complete(turns, model: "gemini-2.5-flash")
        XCTAssertEqual(output, "Hola, ¿cómo estás?")

        let completeReq = try XCTUnwrap(transport.requests.first)
        XCTAssertEqual(completeReq.httpMethod, "POST")
        XCTAssertEqual(
            completeReq.url?.absoluteString,
            "https://generativelanguage.googleapis.com/v1beta/models/gemini-2.5-flash:generateContent"
        )
        XCTAssertFalse(completeReq.url?.absoluteString.contains(secretKey) ?? true, "Gemini key must never be in the URL")
        XCTAssertEqual(completeReq.value(forHTTPHeaderField: "x-goog-api-key"), secretKey)
        XCTAssertEqual(completeReq.value(forHTTPHeaderField: "Content-Type"), "application/json")

        let bodyData = try XCTUnwrap(StubHTTPTransport.bodyData(of: completeReq))
        let bodyJSON = try XCTUnwrap(JSONSerialization.jsonObject(with: bodyData) as? [String: Any])
        let sysInst = try XCTUnwrap(bodyJSON["systemInstruction"] as? [String: Any])
        let sysParts = try XCTUnwrap(sysInst["parts"] as? [[String: String]])
        XCTAssertEqual(sysParts, [["text": "Translate accurately."]])
        let contents = try XCTUnwrap(bodyJSON["contents"] as? [[String: Any]])
        XCTAssertEqual(contents.count, 1)
        XCTAssertEqual(contents.first?["role"] as? String, "user")

        // 3. 401, 429, and error body
        transport.enqueue(status: 401, json: #"{"error":{"message":"API key not valid"}}"#)
        await assertThrowsClientError(try await client.complete(turns, model: "gemini-2.5-flash"), expected: .badKey)

        transport.enqueue(status: 429, json: #"{"error":{"message":"Resource has been exhausted"}}"#)
        await assertThrowsClientError(try await client.complete(turns, model: "gemini-2.5-flash"), expected: .rateLimited)

        transport.enqueue(status: 400, json: #"{"error":{"code":400,"message":"Model gemini-unknown not found"}}"#)
        await assertThrowsClientError(
            try await client.complete(turns, model: "gemini-unknown"),
            expected: .server(status: 400, message: "Model gemini-unknown not found")
        )
    }

    // MARK: - OpenAICompatibleClient

    func testOpenAICompatibleClientWithAndWithoutKeyAndErrors() async throws {
        let transport = StubHTTPTransport()
        let secretKey = "test-openai-token"
        let cloudClient = OpenAICompatibleClient(
            baseURL: URL(string: "https://api.openai.com/v1")!,
            key: secretKey,
            transport: transport
        )

        // 1. Cloud listModels + complete with Authorization header
        transport.enqueue(status: 200, json: #"{"data":[{"id":"gpt-4o-mini"},{"id":"gpt-4o"}]}"#)
        let models = try await cloudClient.listModels()
        XCTAssertEqual(models, ["gpt-4o-mini", "gpt-4o"])

        let listReq = try XCTUnwrap(transport.requests.first)
        XCTAssertEqual(listReq.httpMethod, "GET")
        XCTAssertEqual(listReq.url?.absoluteString, "https://api.openai.com/v1/models")
        XCTAssertFalse(listReq.url?.absoluteString.contains(secretKey) ?? true)
        XCTAssertEqual(listReq.value(forHTTPHeaderField: "Authorization"), "Bearer \(secretKey)")

        transport.reset()
        transport.enqueue(
            status: 200,
            json: #"{"choices":[{"message":{"role":"assistant","content":"On my way!"}}]}"#
        )
        let turns = [
            AIChatTurn(role: .system, text: "You are helpful."),
            AIChatTurn(role: .user, text: "Draft a reply"),
        ]
        let reply = try await cloudClient.complete(turns, model: "gpt-4o-mini")
        XCTAssertEqual(reply, "On my way!")

        let completeReq = try XCTUnwrap(transport.requests.first)
        XCTAssertEqual(completeReq.httpMethod, "POST")
        XCTAssertEqual(completeReq.url?.absoluteString, "https://api.openai.com/v1/chat/completions")
        XCTAssertFalse(completeReq.url?.absoluteString.contains(secretKey) ?? true)
        XCTAssertEqual(completeReq.value(forHTTPHeaderField: "Authorization"), "Bearer \(secretKey)")
        XCTAssertEqual(completeReq.timeoutInterval, 60.0, accuracy: 0.01)

        let bodyData = try XCTUnwrap(StubHTTPTransport.bodyData(of: completeReq))
        let bodyJSON = try XCTUnwrap(JSONSerialization.jsonObject(with: bodyData) as? [String: Any])
        XCTAssertEqual(bodyJSON["model"] as? String, "gpt-4o-mini")
        let messages = try XCTUnwrap(bodyJSON["messages"] as? [[String: String]])
        XCTAssertEqual(
            messages,
            [
                ["role": "system", "content": "You are helpful."],
                ["role": "user", "content": "Draft a reply"],
            ]
        )

        // 2. Local client without key omits Authorization header and uses 180s timeout
        transport.reset()
        let localClient = OpenAICompatibleClient(
            baseURL: URL(string: "http://127.0.0.1:11434/v1")!,
            key: nil,
            transport: transport
        )
        transport.enqueue(
            status: 200,
            json: #"{"choices":[{"message":{"role":"assistant","content":"Local response"}}]}"#
        )
        let localReply = try await localClient.complete(turns, model: "llama3.2")
        XCTAssertEqual(localReply, "Local response")
        let localReq = try XCTUnwrap(transport.requests.first)
        XCTAssertNil(localReq.value(forHTTPHeaderField: "Authorization"))
        XCTAssertEqual(localReq.timeoutInterval, 180.0, accuracy: 0.01)

        // 3. 401, 429, provider error body, and network unreachable
        transport.enqueue(status: 401, json: #"{"error":{"message":"Incorrect API key provided"}}"#)
        await assertThrowsClientError(try await cloudClient.complete(turns, model: "gpt-4o-mini"), expected: .badKey)

        transport.enqueue(status: 429, json: #"{"error":{"message":"You exceeded your current quota"}}"#)
        await assertThrowsClientError(try await cloudClient.complete(turns, model: "gpt-4o-mini"), expected: .rateLimited)

        transport.enqueue(status: 404, json: #"{"error":{"message":"The model `gpt-99` does not exist"}}"#)
        await assertThrowsClientError(
            try await cloudClient.complete(turns, model: "gpt-99"),
            expected: .server(status: 404, message: "The model `gpt-99` does not exist")
        )

        transport.enqueue(error: URLError(.cannotConnectToHost))
        await assertThrowsClientError(try await localClient.complete(turns, model: "llama3.2"), expected: .unreachable)
    }

    // MARK: - LocalProviderDetector

    func testLocalProviderDetectorRunningNeedsKeyNotRunningAndNon8888UnslothPort() async {
        let transport = StubHTTPTransport { request in
            guard let url = request.url else { throw URLError(.badURL) }
            switch url.absoluteString {
            case "http://127.0.0.1:11434/api/tags":
                let body = Data(#"{"models":[{"name":"llama3.2:latest"},{"name":"qwen2.5:7b"}]}"#.utf8)
                return (body, StubHTTPTransport.makeResponse(url: url, status: 200))
            case "http://127.0.0.1:8891/v1/models":
                if request.value(forHTTPHeaderField: "Authorization") == "Bearer unsloth-token" {
                    let body = Data(#"{"data":[{"id":"unsloth/Qwen2.5-7B-Instruct"}]}"#.utf8)
                    return (body, StubHTTPTransport.makeResponse(url: url, status: 200))
                }
                return (Data(), StubHTTPTransport.makeResponse(url: url, status: 401))
            default:
                throw URLError(.cannotConnectToHost)
            }
        }

        let detector = LocalProviderDetector(transport: transport)

        // First probe without an Unsloth key: Ollama is running, LM Studio is not running, Unsloth on 8891 needs key
        let firstResults = await detector.detect()
        XCTAssertEqual(firstResults[.ollama], .running(models: ["llama3.2:latest", "qwen2.5:7b"]))
        XCTAssertEqual(firstResults[.lmStudio], .notRunning)
        XCTAssertEqual(firstResults[.unslothStudio], .needsKey)
        XCTAssertEqual(detector.detectedUnslothPort, 8891)
        XCTAssertEqual(detector.unslothBaseURL.absoluteString, "http://127.0.0.1:8891/v1")

        // Every request probed only 127.0.0.1 with 0.4s timeout
        XCTAssertFalse(transport.requests.isEmpty)
        for req in transport.requests {
            XCTAssertEqual(req.url?.host, "127.0.0.1", "Detector must only ever probe localhost")
            XCTAssertEqual(req.timeoutInterval, 0.4, accuracy: 0.01)
        }

        // Probe again with the Unsloth key: Unsloth on port 8891 now reports .running
        let secondResults = await detector.detect(unslothKey: "unsloth-token")
        XCTAssertEqual(secondResults[.unslothStudio], .running(models: ["unsloth/Qwen2.5-7B-Instruct"]))
        XCTAssertEqual(detector.detectedUnslothPort, 8891)
    }

    func testLocalProviderDetectorIgnores403AndSendsUnslothKeyOnlyToChosen401Port() async {
        let secretKey = "unsloth-secret-key"
        let transport = StubHTTPTransport { request in
            guard let url = request.url else { throw URLError(.badURL) }
            switch url.absoluteString {
            case "http://127.0.0.1:8888/v1/models":
                // 403 (e.g. another local server) must NOT be treated as an Unsloth candidate
                return (Data(), StubHTTPTransport.makeResponse(url: url, status: 403))
            case "http://127.0.0.1:8890/v1/models":
                if request.value(forHTTPHeaderField: "Authorization") == "Bearer \(secretKey)" {
                    let body = Data(#"{"data":[{"id":"unsloth/Llama-3.2-3B"}]}"#.utf8)
                    return (body, StubHTTPTransport.makeResponse(url: url, status: 200))
                }
                return (Data(), StubHTTPTransport.makeResponse(url: url, status: 401))
            default:
                throw URLError(.cannotConnectToHost)
            }
        }

        let detector = LocalProviderDetector(transport: transport)
        let results = await detector.detect(unslothKey: secretKey)

        XCTAssertEqual(detector.detectedUnslothPort, 8890)
        XCTAssertEqual(detector.unslothBaseURL.absoluteString, "http://127.0.0.1:8890/v1")
        XCTAssertEqual(results[.unslothStudio], .running(models: ["unsloth/Llama-3.2-3B"]))

        let keyedRequests = transport.requests.filter {
            $0.value(forHTTPHeaderField: "Authorization") != nil
        }
        XCTAssertEqual(keyedRequests.count, 1, "Saved Unsloth key must only be sent once, to the chosen 401 port")
        XCTAssertEqual(keyedRequests.first?.url?.absoluteString, "http://127.0.0.1:8890/v1/models")
        XCTAssertEqual(keyedRequests.first?.value(forHTTPHeaderField: "Authorization"), "Bearer \(secretKey)")
    }

    // MARK: - AIKeyStore

    func testAIKeyStoreInMemoryAndServiceSeparationAndRedaction() throws {
        let memory = InMemoryCredentialStore()
        let keyStore = AIKeyStore(store: memory)

        XCTAssertFalse(keyStore.hasKey(for: .anthropic))
        XCTAssertNil(keyStore.key(for: .anthropic))

        try keyStore.saveKey("  test-stored-token-1234  ", for: .anthropic)
        XCTAssertTrue(keyStore.hasKey(for: .anthropic))
        XCTAssertEqual(keyStore.key(for: .anthropic), "test-stored-token-1234")
        XCTAssertEqual(keyStore.keyLastFour(for: .anthropic), "1234")
        XCTAssertEqual(try memory.read(account: "anthropic"), "test-stored-token-1234")

        // Never appears in description or debugDescription
        XCTAssertFalse(String(describing: keyStore).contains("test-stored-token-1234"))
        XCTAssertFalse(String(reflecting: keyStore).contains("test-stored-token-1234"))

        try keyStore.removeKey(for: .anthropic)
        XCTAssertFalse(keyStore.hasKey(for: .anthropic))
        XCTAssertNil(keyStore.key(for: .anthropic))

        // Test copy uses its own service name, separate from the installed app
        XCTAssertEqual(
            AIKeyStore.service(for: "com.vitruviansoftware.courier"),
            "com.vitruviansoftware.courier.ai"
        )
        XCTAssertEqual(
            AIKeyStore.service(for: TestCopy.bundleIdentifier),
            "com.vitruviansoftware.courier.dev.ai"
        )
    }

    // MARK: - AIPrompts & AIChatContext

    func testAIPromptsDraftSummarizeTranslateFilterAttachmentsAndEnforceCaps() {
        // Build 35 timeline messages plus an image attachment and an empty message
        var timelineMessages: [TimelineMessage] = []
        for idx in 1 ... 35 {
            timelineMessages.append(
                makeTimelineMessage(
                    id: "$m\(idx)",
                    senderName: idx.isMultiple(of: 2) ? "MeUser" : "Alice",
                    mine: idx.isMultiple(of: 2),
                    kind: .text,
                    body: "Message \(idx)"
                )
            )
        }
        // Add media/attachment messages that must be excluded even when they carry a caption/body
        timelineMessages.append(
            makeTimelineMessage(
                id: "$img",
                senderName: "Alice",
                mine: false,
                kind: .image,
                body: "Secret photo caption",
                fileName: "photo.jpg",
                mediaPath: "/tmp/photo.jpg"
            )
        )
        timelineMessages.append(
            makeTimelineMessage(
                id: "$file",
                senderName: "Alice",
                mine: false,
                kind: .file,
                body: "budget.pdf",
                fileName: "budget.pdf",
                mediaPath: "/tmp/budget.pdf"
            )
        )
        timelineMessages.append(
            makeTimelineMessage(
                id: "$empty",
                senderName: "Alice",
                mine: false,
                kind: .text,
                body: "   "
            )
        )

        let context = AIChatContext(title: "Project Room", timelineMessages: timelineMessages)
        XCTAssertEqual(context.messages.count, 35, "Attachments and blank messages must be excluded")
        XCTAssertFalse(context.messages.contains { $0.text.contains("Secret photo caption") || $0.text.contains("budget.pdf") })

        // Draft cap is last 30 text messages (messages 6...35), oldest first
        let draftTurns = AIPrompts.draft(
            context: context,
            draft: "",
            tone: nil,
            responseLanguage: "Spanish",
            customInstructions: "Always use metric units."
        )
        XCTAssertEqual(draftTurns.count, 2)
        XCTAssertEqual(draftTurns[0].role, .system)
        XCTAssertTrue(draftTurns[0].text.contains("Spanish"))
        XCTAssertTrue(draftTurns[0].text.contains("Always use metric units."))

        let userText = draftTurns[1].text
        XCTAssertFalse(userText.contains("Message 5\n"), "Messages older than the last 30 must be dropped")
        XCTAssertTrue(userText.contains("Me: Message 6"))
        XCTAssertTrue(userText.contains("Alice: Message 35"))
        XCTAssertTrue(userText.contains("Write my next reply. Reply with only the message text."))

        // Summarize cap is last 100 text messages
        var manyEntries: [AIChatContext.Entry] = []
        for idx in 1 ... 120 {
            manyEntries.append((senderName: "Bob", mine: false, text: "Line \(idx)"))
        }
        let largeContext = AIChatContext(title: "Big Chat", messages: manyEntries)
        let summaryTurns = AIPrompts.summarize(
            context: largeContext,
            responseLanguage: "French",
            customInstructions: "Focus on deadlines."
        )
        XCTAssertTrue(summaryTurns[0].text.contains("French"))
        XCTAssertTrue(summaryTurns[0].text.contains("Focus on deadlines."))
        XCTAssertFalse(summaryTurns[1].text.contains("Bob: Line 20\n"))
        XCTAssertTrue(summaryTurns[1].text.contains("Bob: Line 21"))
        XCTAssertTrue(summaryTurns[1].text.contains("Bob: Line 120"))
        XCTAssertTrue(summaryTurns[1].text.contains("Summarize in at most 5 short bullet points."))

        // Translate prompt
        let translateTurns = AIPrompts.translate(
            text: "Good morning",
            targetLanguage: "Japanese",
            responseLanguage: "English",
            customInstructions: "Use polite form."
        )
        XCTAssertTrue(translateTurns[0].text.contains("Use polite form."))
        XCTAssertTrue(translateTurns[1].text.contains("Translate into Japanese. Reply with only the translation."))
        XCTAssertTrue(translateTurns[1].text.contains("Good morning"))
    }

    // MARK: - ConfiguredAIProvider Error Mapping

    func testConfiguredAIProviderMapsErrorsToUnavailableWithPlainMessage() async {
        let transport = StubHTTPTransport()
        let client = OpenAICompatibleClient(
            baseURL: URL(string: "https://api.openai.com/v1")!,
            key: "sk-test",
            transport: transport
        )
        let provider = ConfiguredAIProvider(
            kind: .openAI,
            client: client,
            model: "gpt-4o-mini"
        )

        let context = AIChatContext(title: "Test", messages: [("Alice", false, "Hi")])

        // 401 -> badKey plain message
        transport.enqueue(status: 401, json: #"{"error":{"message":"bad key"}}"#)
        let draftDisp = await provider.draftResponse(context: context, draft: "", tone: nil)
        XCTAssertEqual(draftDisp, .unavailable(reason: AIClientError.badKey.message))

        // 429 -> rateLimited plain message
        transport.enqueue(status: 429, json: #"{"error":{"message":"slow down"}}"#)
        let translateDisp = await provider.translate(text: "Hello", targetLanguage: "Spanish")
        XCTAssertEqual(translateDisp, .unavailable(reason: AIClientError.rateLimited.message))

        // Network error -> unreachable plain message
        transport.enqueue(error: URLError(.notConnectedToInternet))
        let summarizeDisp = await provider.summarize(context: context)
        XCTAssertEqual(summarizeDisp, .unavailable(reason: AIClientError.unreachable.message))

        // Out-of-scope voice transcription & Talk to Type stay unavailable
        let voiceDisp = await provider.transcribeVoiceNote(roomID: "!r:local", eventID: "$1")
        let talkDisp = await provider.startTalkToType()
        if case .text = voiceDisp { XCTFail("Expected unavailable") }
        if case .text = talkDisp { XCTFail("Expected unavailable") }
    }

    // MARK: - AI Off Makes Zero Requests

    func testAIProviderStoreWhenAIOffHandsOutUnavailableProviderAndMakesZeroRequests() async {
        let suiteName = "test.courier.ai.store.off.\(UUID().uuidString)"
        let defaults = ScratchDefaults.suite(named: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let prefs = AIPreferences(defaults: defaults)
        XCTAssertFalse(prefs.enableContextualAI)

        let transport = StubHTTPTransport()
        let keyStore = AIKeyStore(store: InMemoryCredentialStore(["openAI": "test-openai-key"]))
        let store = AIProviderStore(preferences: prefs, keyStore: keyStore, transport: transport)

        XCTAssertFalse(store.provider.isAvailable)
        XCTAssertTrue(store.provider is UnavailableAIProvider)
        XCTAssertEqual(store.statusBannerText, "AI is off")

        await store.refresh()
        let context = AIChatContext(title: "Crew", messages: [("Alice", false, "Hello")])
        _ = await store.provider.draftResponse(context: context, draft: "", tone: nil)
        _ = await store.provider.translate(text: "Hello", targetLanguage: "French")
        _ = await store.provider.summarize(context: context)

        XCTAssertTrue(transport.requests.isEmpty, "With AI off, Courier must make zero network requests")
    }

    func testAIProviderStoreSettingsDetectionRunsLocalhostWhenAIOffAndStopsWhenClosed() async throws {
        let suiteName = "test.courier.ai.store.settings.\(UUID().uuidString)"
        let defaults = ScratchDefaults.suite(named: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let prefs = AIPreferences(defaults: defaults)
        prefs.selectedEngine = .openAI
        XCTAssertFalse(prefs.enableContextualAI)

        let transport = StubHTTPTransport { request in
            guard let url = request.url else { throw URLError(.badURL) }
            if url.absoluteString == "http://127.0.0.1:11434/api/tags" {
                let body = Data(#"{"models":[{"name":"llama3.2:latest"}]}"#.utf8)
                return (body, StubHTTPTransport.makeResponse(url: url, status: 200))
            }
            throw URLError(.cannotConnectToHost)
        }
        let keyStore = AIKeyStore(store: InMemoryCredentialStore(["openAI": "test-openai-key"]))
        let store = AIProviderStore(
            preferences: prefs,
            keyStore: keyStore,
            transport: transport,
            settingsDetectionInterval: .milliseconds(40)
        )

        // While Settings is closed and AI is off: zero requests
        await store.refresh()
        XCTAssertTrue(transport.requests.isEmpty)

        // Opening Settings ▸ AI starts local-only detection even while AI is Off
        store.startSettingsDetection()
        XCTAssertTrue(store.isSettingsDetectionActive)
        try await Task.sleep(for: .milliseconds(100))

        XCTAssertEqual(store.detections[.ollama], .running(models: ["llama3.2:latest"]))
        XCTAssertFalse(store.provider.isAvailable, "Provider stays unavailable while AI is Off")
        XCTAssertFalse(transport.requests.isEmpty)
        for req in transport.requests {
            XCTAssertEqual(req.url?.host, "127.0.0.1", "Settings detection when AI is off must only hit localhost")
        }

        // Closing Settings stops periodic detection; subsequent refresh while AI is off makes zero new requests
        store.stopSettingsDetection()
        XCTAssertFalse(store.isSettingsDetectionActive)
        transport.reset()
        try await Task.sleep(for: .milliseconds(100))
        await store.refresh()
        XCTAssertTrue(transport.requests.isEmpty, "With Settings closed and AI off, zero requests must be made")
    }

    func testAIProviderStoreRebuildsWhenEnabledAndTestConnects() async throws {
        let suiteName = "test.courier.ai.store.on.\(UUID().uuidString)"
        let defaults = ScratchDefaults.suite(named: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let prefs = AIPreferences(defaults: defaults)
        let transport = StubHTTPTransport()
        let keyStore = AIKeyStore(store: InMemoryCredentialStore())
        let store = AIProviderStore(preferences: prefs, keyStore: keyStore, transport: transport)

        prefs.enableContextualAI = true
        prefs.selectedEngine = .anthropic
        store.rebuildProvider()
        XCTAssertFalse(store.provider.isAvailable, "Anthropic without a key is not available")
        XCTAssertEqual(store.stateText(for: .anthropic), "Needs key")

        try store.saveKey("test-anthropic-valid", for: .anthropic)
        XCTAssertEqual(store.stateText(for: .anthropic), "Key saved")

        transport.enqueue(
            status: 200,
            json: #"{"data":[{"id":"claude-sonnet-4-20250514"},{"id":"claude-3-5-haiku-latest"}]}"#
        )
        let testResult = await store.test()
        XCTAssertEqual(testResult, .connected(modelCount: 2))
        XCTAssertTrue(store.provider.isAvailable)
        XCTAssertEqual(store.availableModels, ["claude-sonnet-4-20250514", "claude-3-5-haiku-latest"])
        XCTAssertEqual(prefs.model(for: .anthropic), "claude-sonnet-4-20250514")
        XCTAssertEqual(store.statusBannerText, "Anthropic · claude-sonnet-4-20250514")
    }

    // MARK: - Helpers

    private func assertThrowsClientError<T>(
        _ expression: @autoclosure () async throws -> T,
        expected: AIClientError,
        file: StaticString = #filePath,
        line: UInt = #line
    ) async {
        do {
            _ = try await expression()
            XCTFail("Expected \(expected), but call succeeded", file: file, line: line)
        } catch let error as AIClientError {
            XCTAssertEqual(error, expected, file: file, line: line)
        } catch {
            XCTFail("Expected AIClientError.\(expected), got \(error)", file: file, line: line)
        }
    }

    private func makeTimelineMessage(
        id: String,
        senderName: String,
        mine: Bool,
        kind: MessageKind,
        body: String,
        fileName: String = "",
        mediaPath: String = ""
    ) -> TimelineMessage {
        TimelineMessage(
            id: id,
            roomID: "!room:courier.local",
            sender: mine ? "@me:courier.local" : "@alice:courier.local",
            senderName: senderName,
            senderAvatarPath: "",
            mine: mine,
            ts: 1_760_600_000_000,
            kind: kind,
            body: body,
            rich: RichText(text: body),
            isEdited: false,
            editCount: 0,
            editFailed: nil,
            failedEditID: nil,
            fileName: fileName,
            mimeType: "",
            byteSize: nil,
            width: nil,
            height: nil,
            mediaPath: mediaPath,
            statusLine: .sent,
            countsAsUnread: !mine,
            poll: nil,
            thread: nil,
            bookmarked: false,
            expiresAt: nil,
            timerChange: nil,
            call: nil,
            reply: nil,
            reactions: [],
            startsGroup: true
        )
    }
}
