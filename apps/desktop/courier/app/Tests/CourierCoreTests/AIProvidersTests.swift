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
            XCTAssertEqual(
                kind.privacyNotice,
                "Messages you use with AI, and your draft, are sent to \(kind.label). Never your keys or other chats."
            )
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

    func testHTTP403MapsToBadKeyForEveryCloudClient() async throws {
        let transport = StubHTTPTransport()
        let turns = [
            AIChatTurn(role: .system, text: "You are helpful."),
            AIChatTurn(role: .user, text: "Hello"),
        ]

        let anthropic = AnthropicClient(apiKey: "test-anthropic-token", transport: transport)
        transport.enqueue(status: 403, json: #"{"error":{"message":"forbidden"}}"#)
        await assertThrowsClientError(
            try await anthropic.complete(turns, model: "claude-sonnet-4-20250514"),
            expected: .badKey
        )

        let gemini = GeminiClient(apiKey: "test-gemini-token", transport: transport)
        transport.enqueue(status: 403, json: #"{"error":{"message":"permission denied"}}"#)
        await assertThrowsClientError(
            try await gemini.complete(turns, model: "gemini-2.5-flash"),
            expected: .badKey
        )

        let openAI = OpenAICompatibleClient(
            baseURL: URL(string: "https://api.openai.com/v1")!,
            key: "test-openai-token",
            transport: transport
        )
        transport.enqueue(status: 403, json: #"{"error":{"message":"forbidden"}}"#)
        await assertThrowsClientError(
            try await openAI.complete(turns, model: "gpt-4o-mini"),
            expected: .badKey
        )
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
        XCTAssertEqual(detector.unslothBaseURL?.absoluteString, "http://127.0.0.1:8891/v1")

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
        XCTAssertEqual(detector.unslothBaseURL?.absoluteString, "http://127.0.0.1:8890/v1")
        XCTAssertEqual(results[.unslothStudio], .running(models: ["unsloth/Llama-3.2-3B"]))

        let keyedRequests = transport.requests.filter {
            $0.value(forHTTPHeaderField: "Authorization") != nil
        }
        XCTAssertEqual(keyedRequests.count, 1, "Saved Unsloth key must only be sent once, to the chosen 401 port")
        XCTAssertEqual(keyedRequests.first?.url?.absoluteString, "http://127.0.0.1:8890/v1/models")
        XCTAssertEqual(keyedRequests.first?.value(forHTTPHeaderField: "Authorization"), "Bearer \(secretKey)")
    }

    func testUnslothKeyNeverSentWhenNoPortDetectedEvenWithStubOn8888() async {
        let suiteName = "test.courier.ai.unsloth.noleak.\(UUID().uuidString)"
        let defaults = ScratchDefaults.suite(named: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let secretKey = "unsloth-top-secret-key"
        let transport = StubHTTPTransport { request in
            guard let url = request.url else { throw URLError(.badURL) }
            // Stub a non-Unsloth service on port 8888 (e.g. Jupyter / local dev server returning 404 or 200 HTML)
            if url.host == "127.0.0.1", url.port == 8888 {
                let body = Data(#"{"error":"not unsloth"}"#.utf8)
                return (body, StubHTTPTransport.makeResponse(url: url, status: 404))
            }
            throw URLError(.cannotConnectToHost)
        }

        let detector = LocalProviderDetector(transport: transport)
        XCTAssertNil(detector.detectedUnslothPort)
        XCTAssertNil(detector.unslothBaseURL)

        let prefs = AIPreferences(defaults: defaults)
        prefs.selectedEngine = .unslothStudio
        prefs.enableContextualAI = true

        let keyStore = AIKeyStore(store: InMemoryCredentialStore(["unslothStudio": secretKey]))
        let store = AIProviderStore(
            preferences: prefs,
            keyStore: keyStore,
            transport: transport,
            detector: detector
        )

        // 1. Before any detection: no port detected -> no client built, provider unavailable with "Unsloth Studio is not running"
        XCTAssertNil(store.makeClient(for: .unslothStudio))
        XCTAssertFalse(store.provider.isAvailable)
        XCTAssertTrue(store.provider.unavailableReason.contains("Unsloth Studio is not running"))

        await store.refreshModelsForSelectedProvider()
        let testResult = await store.test()
        XCTAssertFalse(testResult.isConnected)
        XCTAssertTrue(testResult.displayText.contains("Unsloth Studio is not running"))

        let context = AIChatContext(title: "Test", messages: [("Alice", false, "Hi")])
        let draftDisp = await store.provider.draftResponse(context: context, draft: "", tone: nil)
        if case let .unavailable(reason) = draftDisp {
            XCTAssertTrue(reason.contains("Unsloth Studio is not running"))
        } else {
            XCTFail("Expected unavailable disposition")
        }

        // 2. Run refresh/detection where port 8888 is a non-Unsloth server (404)
        await store.refresh()
        XCTAssertNil(detector.detectedUnslothPort)
        XCTAssertNil(detector.unslothBaseURL)
        XCTAssertNil(store.makeClient(for: .unslothStudio))
        XCTAssertFalse(store.provider.isAvailable)
        XCTAssertTrue(store.provider.unavailableReason.contains("Unsloth Studio is not running"))

        // Zero requests across the entire session may carry the saved Unsloth key
        let requestsCarryingKey = transport.requests.filter { req in
            let auth = req.value(forHTTPHeaderField: "Authorization") ?? ""
            let urlString = req.url?.absoluteString ?? ""
            return auth.contains(secretKey) || urlString.contains(secretKey) || !auth.isEmpty
        }
        XCTAssertTrue(requestsCarryingKey.isEmpty, "Zero requests may carry the Unsloth key when no Unsloth port was detected")
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

    func testChoosingProviderLoadsModelsAtOnceSelectsRememberedOrFirstAndNeverShowsUnlistedModel() async throws {
        let suiteName = "test.courier.ai.store.select.\(UUID().uuidString)"
        let defaults = ScratchDefaults.suite(named: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let prefs = AIPreferences(defaults: defaults)
        // Default selectedModel is unset ("") and never the stale "On-Device (Not available yet)" string
        XCTAssertEqual(prefs.selectedModel, "")

        // Pre-populate a remembered model for OpenAI (listed) and an unlisted stale model for Ollama
        prefs.setModel("gpt-4.1-mini", for: .openAI)
        prefs.setModel("unlisted-stale-model", for: .ollama)

        let transport = StubHTTPTransport { request in
            guard let url = request.url else { throw URLError(.badURL) }
            switch url.absoluteString {
            case "http://127.0.0.1:11434/v1/models":
                let body = Data(#"{"data":[{"id":"llama3.2:latest"},{"id":"qwen2.5:7b"}]}"#.utf8)
                return (body, StubHTTPTransport.makeResponse(url: url, status: 200))
            case "https://api.openai.com/v1/models":
                let body = Data(#"{"data":[{"id":"gpt-4o"},{"id":"gpt-4.1-mini"}]}"#.utf8)
                return (body, StubHTTPTransport.makeResponse(url: url, status: 200))
            default:
                throw URLError(.cannotConnectToHost)
            }
        }
        let keyStore = AIKeyStore(store: InMemoryCredentialStore(["openAI": "test-openai-key"]))
        let store = AIProviderStore(preferences: prefs, keyStore: keyStore, transport: transport)

        // 1. Choosing Ollama loads its model list at once; because "unlisted-stale-model" is not listed, selects the first listed model
        store.selectProvider(.ollama)
        try await waitUntil { store.availableModels == ["llama3.2:latest", "qwen2.5:7b"] }
        XCTAssertEqual(store.availableModels, ["llama3.2:latest", "qwen2.5:7b"])
        XCTAssertFalse(store.availableModels.contains("unlisted-stale-model"))
        XCTAssertEqual(prefs.model(for: .ollama), "llama3.2:latest")
        XCTAssertEqual(prefs.selectedModel, "llama3.2:latest")
        XCTAssertEqual((store.provider as? ConfiguredAIProvider)?.model, "llama3.2:latest")

        // 2. Choosing OpenAI clears Ollama's models immediately, loads OpenAI's models at once, and selects the remembered "gpt-4.1-mini"
        store.selectProvider(.openAI)
        try await waitUntil { store.availableModels == ["gpt-4o", "gpt-4.1-mini"] }
        XCTAssertEqual(store.availableModels, ["gpt-4o", "gpt-4.1-mini"])
        XCTAssertFalse(store.availableModels.contains("llama3.2:latest"))
        XCTAssertEqual(prefs.model(for: .openAI), "gpt-4.1-mini")
        XCTAssertEqual(prefs.selectedModel, "gpt-4.1-mini")
        XCTAssertEqual((store.provider as? ConfiguredAIProvider)?.model, "gpt-4.1-mini")
    }

    func testSwitchingProviderMidLoadNeverWritesOldProvidersModelsAndTestIsDeterministic() async throws {
        let suiteName = "test.courier.ai.store.midload.\(UUID().uuidString)"
        let defaults = ScratchDefaults.suite(named: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let prefs = AIPreferences(defaults: defaults)
        let transport = StubHTTPTransport { request in
            guard let url = request.url else { throw URLError(.badURL) }
            switch url.absoluteString {
            case "http://127.0.0.1:11434/v1/models":
                try await Task.sleep(for: .milliseconds(70))
                let body = Data(#"{"data":[{"id":"ollama-slow-model"}]}"#.utf8)
                return (body, StubHTTPTransport.makeResponse(url: url, status: 200))
            case "https://api.openai.com/v1/models":
                let body = Data(#"{"data":[{"id":"gpt-4o"},{"id":"gpt-4.1-mini"}]}"#.utf8)
                return (body, StubHTTPTransport.makeResponse(url: url, status: 200))
            case "https://api.anthropic.com/v1/models":
                let body = Data(#"{"data":[{"id":"claude-sonnet-4-20250514"}]}"#.utf8)
                return (body, StubHTTPTransport.makeResponse(url: url, status: 200))
            default:
                throw URLError(.cannotConnectToHost)
            }
        }
        let keyStore = AIKeyStore(
            store: InMemoryCredentialStore([
                "openAI": "test-openai-key",
                "anthropic": "test-anthropic-key",
            ])
        )
        let store = AIProviderStore(preferences: prefs, keyStore: keyStore, transport: transport)

        // Start loading Ollama (slow), then immediately switch to OpenAI (fast) before Ollama finishes
        store.selectProvider(.ollama)
        store.selectProvider(.openAI)

        try await waitUntil { store.availableModels == ["gpt-4o", "gpt-4.1-mini"] }
        // Wait past Ollama's slow response time and verify Ollama's models never overwrite OpenAI's
        try await Task.sleep(for: .milliseconds(110))
        XCTAssertEqual(prefs.selectedEngine, .openAI)
        XCTAssertEqual(store.availableModels, ["gpt-4o", "gpt-4.1-mini"])
        XCTAssertFalse(store.availableModels.contains("ollama-slow-model"))
        XCTAssertEqual(prefs.selectedModel, "gpt-4o")
        XCTAssertEqual((store.provider as? ConfiguredAIProvider)?.kind, .openAI)
        XCTAssertEqual((store.provider as? ConfiguredAIProvider)?.model, "gpt-4o")

        // Selecting a provider and immediately calling test() cancels the background model load rather than racing it
        transport.reset()
        transport.enqueue(
            status: 200,
            json: #"{"data":[{"id":"claude-sonnet-4-20250514"},{"id":"claude-3-5-haiku-latest"}]}"#
        )
        store.selectProvider(.anthropic)
        let result = await store.test()
        XCTAssertEqual(result, .connected(modelCount: 2))
        XCTAssertEqual(store.lastTestResult, .connected(modelCount: 2))
        XCTAssertEqual(store.availableModels, ["claude-sonnet-4-20250514", "claude-3-5-haiku-latest"])
        XCTAssertEqual(transport.requests.count, 1, "test() must cancel any pending automatic model load rather than racing it")
    }

    func testStartAndImmediatelyStopSettingsDetectionMakesZeroRequests() async throws {
        let suiteName = "test.courier.ai.store.stopimmediate.\(UUID().uuidString)"
        let defaults = ScratchDefaults.suite(named: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let prefs = AIPreferences(defaults: defaults)
        let transport = StubHTTPTransport { request in
            guard let url = request.url else { throw URLError(.badURL) }
            let body = Data(#"{"data":[{"id":"llama3.2:latest"}]}"#.utf8)
            return (body, StubHTTPTransport.makeResponse(url: url, status: 200))
        }
        let store = AIProviderStore(
            preferences: prefs,
            keyStore: AIKeyStore(store: InMemoryCredentialStore(["openAI": "test-openai-key"])),
            transport: transport,
            settingsDetectionInterval: .milliseconds(20)
        )

        // 1. AI off: start then immediately stop -> zero requests
        store.startSettingsDetection()
        store.stopSettingsDetection()
        XCTAssertFalse(store.isSettingsDetectionActive)
        try await Task.sleep(for: .milliseconds(60))
        XCTAssertTrue(transport.requests.isEmpty, "Starting then immediately stopping settings detection must make zero requests")

        // 2. AI on: start then immediately stop -> zero requests
        prefs.selectedEngine = .appleIntelligence
        prefs.enableContextualAI = true
        transport.reset()
        store.startSettingsDetection()
        store.stopSettingsDetection()
        XCTAssertFalse(store.isSettingsDetectionActive)
        try await Task.sleep(for: .milliseconds(60))
        XCTAssertTrue(transport.requests.isEmpty, "Starting then immediately stopping settings detection with AI enabled must make zero requests")
    }

    // MARK: - UI Model Wiring Tests (Translation, Result Strip, Chat Switch Cancellation, Last Language Rule)

    func testDisabledLastTranslationLanguageRule() {
        let suiteName = "test.courier.ai.lastlang.\(UUID().uuidString)"
        let defaults = ScratchDefaults.suite(named: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let prefs = AIPreferences(defaults: defaults)
        prefs.translationLanguages = ["Spanish", "French"]
        XCTAssertEqual(AIPreferences.lastTranslationLanguageHelp, "At least one language stays on")
        XCTAssertFalse(prefs.isLastEnabledTranslationLanguage("Spanish"))
        XCTAssertFalse(prefs.isLastEnabledTranslationLanguage("French"))

        // Disabling Spanish leaves French as the sole enabled language
        prefs.setTranslationLanguage("Spanish", enabled: false)
        XCTAssertEqual(prefs.translationLanguages, ["French"])
        XCTAssertTrue(prefs.isLastEnabledTranslationLanguage("French"))
        XCTAssertFalse(prefs.isLastEnabledTranslationLanguage("Spanish"))

        // Attempting to disable the last remaining language is refused
        prefs.setTranslationLanguage("French", enabled: false)
        XCTAssertEqual(prefs.translationLanguages, ["French"])
    }

    func testTranslateLanguageChoiceAndMessageMenuSubmenu() async throws {
        let suiteName = "test.courier.ai.translatelang.\(UUID().uuidString)"
        let defaults = ScratchDefaults.suite(named: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let prefs = AIPreferences(defaults: defaults)
        prefs.translationLanguages = ["Spanish", "French", "Japanese"]
        prefs.responseLanguage = "French"
        prefs.enableContextualAI = true
        prefs.selectedEngine = .ollama
        prefs.selectedModel = "llama3.2"

        let msg = makeTimelineMessage(
            id: "$msg1",
            senderName: "Alice",
            mine: false,
            kind: .text,
            body: "Bonjour tout le monde"
        )

        // 1. MessageMenu when AI is unavailable: Translate is disabled with "Set up AI in Settings"
        let unavailableSections = MessageMenu.sections(
            for: msg,
            available: (actions: [.reply, .copy], unavailable: []),
            features: ChatFeatures(source: .stored),
            disappearsIn: nil,
            time: { _ in "12:00 PM" },
            includeDiagnostics: true,
            isAIAvailable: false,
            responseLanguage: prefs.responseLanguage,
            translationLanguages: prefs.translationLanguages
        )
        let unavailableTranslate = unavailableSections.flatMap { $0 }.first { $0.title == "Translate" }
        XCTAssertNotNil(unavailableTranslate)
        XCTAssertEqual(unavailableTranslate?.isEnabled, false)
        XCTAssertEqual(unavailableTranslate?.help, "Set up AI in Settings")
        XCTAssertTrue(unavailableTranslate?.children.isEmpty ?? false)

        // 2. MessageMenu when AI is available: primary Translate + "Translate Into…" submenu for other enabled languages
        let availableSections = MessageMenu.sections(
            for: msg,
            available: (actions: [.reply, .copy], unavailable: []),
            features: ChatFeatures(source: .stored),
            disappearsIn: nil,
            time: { _ in "12:00 PM" },
            includeDiagnostics: true,
            isAIAvailable: true,
            responseLanguage: prefs.responseLanguage,
            translationLanguages: prefs.translationLanguages
        )
        let availableItems = availableSections.flatMap { $0 }
        let primaryTranslate = availableItems.first { $0.title == "Translate" }
        let submenu = availableItems.first { $0.title == "Translate Into…" }
        XCTAssertEqual(primaryTranslate?.isEnabled, true)
        XCTAssertEqual(primaryTranslate?.command, MessageMenuItem.Command.translate)
        XCTAssertNotNil(submenu)
        XCTAssertEqual(
            submenu?.children.map { $0.command },
            [MessageMenuItem.Command.translateTo("Spanish"), MessageMenuItem.Command.translateTo("Japanese")]
        )

        // 3. MessageActionsModel.translateMessage defaults to preferences.responseLanguage (not translationLanguages.first)
        let h = try await startConversation(
            ["!a": [textEvent(id: "$msg1", room: "!a", at: 1, body: "Bonjour tout le monde")]],
            rows: ["!a": chatRow("!a", name: "Alice", network: "whatsapp")]
        )
        try await h.open("!a")
        let actions = MessageActionsModel(
            conversation: h.conversation,
            appModel: h.app,
            preferences: h.preferences,
            pasteboard: FakePasteboard()
        )
        let mockProvider = MockTestAIProvider(result: .text("Hello everyone"))
        actions.aiPreferences = prefs
        actions.aiProvider = mockProvider

        actions.translateMessage(eventID: "$msg1")
        await actions.waitForTranslation(eventID: "$msg1")

        XCTAssertEqual(actions.translationTargetLanguages["$msg1"], "French")
        XCTAssertEqual(mockProvider.lastTranslateTargetLanguage, "French")
        XCTAssertEqual(actions.translations["$msg1"], AIProviderDisposition.text("Hello everyone"))
        XCTAssertEqual(actions.translationProvenance["$msg1"], "via llama3.2 · on this Mac")
        await h.stop()
    }

    func testTranslateMessageWithEmptyTextSkipsRequestAndShowsNothing() async throws {
        let suiteName = "test.courier.ai.translate.empty.\(UUID().uuidString)"
        let defaults = ScratchDefaults.suite(named: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let prefs = AIPreferences(defaults: defaults)
        prefs.enableContextualAI = true
        prefs.selectedEngine = .ollama
        prefs.selectedModel = "llama3.2"
        prefs.responseLanguage = "Spanish"

        let h = try await startConversation(
            ["!a": [
                textEvent(id: "$empty", room: "!a", at: 1, body: ""),
                textEvent(id: "$whitespace", room: "!a", at: 2, body: "   \n  "),
            ]],
            rows: ["!a": chatRow("!a", name: "Alice", network: "whatsapp")]
        )
        try await h.open("!a")
        let actions = MessageActionsModel(
            conversation: h.conversation,
            appModel: h.app,
            preferences: h.preferences,
            pasteboard: FakePasteboard()
        )
        let mockProvider = MockTestAIProvider(result: .text("Should never be called"))
        actions.aiPreferences = prefs
        actions.aiProvider = mockProvider

        actions.translateMessage(eventID: "$empty")
        actions.translateMessage(eventID: "$whitespace")
        await actions.waitForTranslation(eventID: "$empty")
        await actions.waitForTranslation(eventID: "$whitespace")

        XCTAssertNil(mockProvider.lastTranslateTargetLanguage, "Empty or whitespace message must not trigger a translate request")
        XCTAssertNil(actions.translations["$empty"])
        XCTAssertNil(actions.translations["$whitespace"])
        XCTAssertNil(actions.translationTargetLanguages["$empty"])
        XCTAssertNil(actions.translationTargetLanguages["$whitespace"])
        XCTAssertFalse(actions.translatingEventIDs.contains("$empty"))
        XCTAssertFalse(actions.translatingEventIDs.contains("$whitespace"))
        await h.stop()
    }

    func testComposerAIResultStripReplaceInsertDiscardAndNeverChangesTextOnError() async {
        let suiteName = "test.courier.ai.composer.strip.\(UUID().uuidString)"
        let defaults = ScratchDefaults.suite(named: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let prefs = AIPreferences(defaults: defaults)
        prefs.enableContextualAI = true
        prefs.selectedEngine = .anthropic
        prefs.selectedModel = "claude-sonnet-4-20250514"

        let composer = ComposerModel()
        composer.aiPreferences = prefs
        composer.open("!room1:courier.local")

        let mockProvider = MockTestAIProvider(result: .text("Polished reply"))
        composer.aiProvider = mockProvider

        // 1. Replace: result lands in aiResult first without touching composer.text; replaceWithAIResult replaces text
        composer.text = "rough draft"
        composer.draftWithAI(tone: .moreConcise)
        await composer.waitForAI()

        XCTAssertEqual(composer.text, "rough draft", "Drafting must not overwrite composer.text before Replace is chosen")
        XCTAssertEqual(composer.aiResult?.text, "Polished reply")
        XCTAssertEqual(composer.aiResult?.provenance, "via claude-sonnet-4-20250514 · sent to Anthropic")
        composer.replaceWithAIResult()
        XCTAssertEqual(composer.text, "Polished reply")
        XCTAssertNil(composer.aiResult)

        // 2. Insert: appends/inserts into existing composer.text
        composer.text = "Hey team,"
        composer.draftWithAI(tone: nil)
        await composer.waitForAI()
        XCTAssertEqual(composer.aiResult?.text, "Polished reply")
        composer.insertAIResult()
        XCTAssertEqual(composer.text, "Hey team,\n\nPolished reply")
        XCTAssertNil(composer.aiResult)

        // 3. Discard: clears aiResult without changing composer.text
        composer.text = "Keep my words"
        composer.draftWithAI(tone: nil)
        await composer.waitForAI()
        XCTAssertNotNil(composer.aiResult)
        composer.discardAIResult()
        XCTAssertNil(composer.aiResult)
        XCTAssertEqual(composer.text, "Keep my words")

        // 4. Error: sets aiError and NEVER changes composer.text
        mockProvider.result = .unavailable(reason: AIClientError.badKey.message)
        composer.text = "Never lose this draft"
        composer.draftWithAI(tone: .moreProfessional)
        await composer.waitForAI()

        XCTAssertEqual(composer.text, "Never lose this draft")
        XCTAssertNil(composer.aiResult)
        XCTAssertEqual(composer.aiError, AIClientError.badKey.message)
    }

    func testComposerCancelsInFlightAIRequestOnChatSwitchAndNeverLandsInOtherChat() async throws {
        let suiteName = "test.courier.ai.composer.cancel.\(UUID().uuidString)"
        let defaults = ScratchDefaults.suite(named: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let prefs = AIPreferences(defaults: defaults)
        prefs.enableContextualAI = true
        prefs.selectedEngine = .ollama
        prefs.selectedModel = "llama3.2"

        let composer = ComposerModel()
        composer.aiPreferences = prefs
        let slowProvider = MockTestAIProvider(
            result: .text("Reply for Room A"),
            delay: .milliseconds(80)
        )
        composer.aiProvider = slowProvider

        composer.open("!roomA:courier.local")
        composer.text = "Draft in Room A"
        composer.draftWithAI(tone: nil)
        XCTAssertTrue(composer.isAIWriting)

        // Switch chats while the request is in flight
        composer.open("!roomB:courier.local")
        XCTAssertEqual(composer.roomID, "!roomB:courier.local")
        XCTAssertFalse(composer.isAIWriting)
        XCTAssertNil(composer.aiResult)

        // Wait longer than the provider's delay and verify the result never lands in Room B
        try await Task.sleep(for: .milliseconds(140))
        XCTAssertEqual(composer.roomID, "!roomB:courier.local")
        XCTAssertNil(composer.aiResult, "In-flight AI result from previous chat must never land in the new chat")
        XCTAssertNil(composer.aiError)
        XCTAssertEqual(composer.text, "")
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

private final class MockTestAIProvider: AIProvider, @unchecked Sendable {
    private let lock = NSLock()
    let isAvailable: Bool = true
    let unavailableReason: String = ""
    let availableModels: [String] = ["test-model"]
    private var _result: AIProviderDisposition
    let delay: Duration?
    private var _lastTranslateTargetLanguage: String?

    var result: AIProviderDisposition {
        get { lock.withLock { _result } }
        set { lock.withLock { _result = newValue } }
    }

    var lastTranslateTargetLanguage: String? {
        lock.withLock { _lastTranslateTargetLanguage }
    }

    init(result: AIProviderDisposition, delay: Duration? = nil) {
        self._result = result
        self.delay = delay
    }

    func summarize(context: AIChatContext) async -> AIProviderDisposition {
        if let delay {
            try? await Task.sleep(for: delay)
        }
        return result
    }

    func draftResponse(context: AIChatContext, draft: String, tone: AIRewriteTone?) async -> AIProviderDisposition {
        if let delay {
            try? await Task.sleep(for: delay)
        }
        return result
    }

    func translate(text: String, targetLanguage: String) async -> AIProviderDisposition {
        lock.withLock { _lastTranslateTargetLanguage = targetLanguage }
        if let delay {
            try? await Task.sleep(for: delay)
        }
        return result
    }

    func ask(prompt: String, context: AIChatContext) async -> AIProviderDisposition {
        if let delay {
            try? await Task.sleep(for: delay)
        }
        return result
    }

    func transcribeVoiceNote(roomID: String, eventID: String) async -> AIProviderDisposition {
        .unavailable(reason: "Not available")
    }

    func startTalkToType() async -> AIProviderDisposition {
        .unavailable(reason: "Not available")
    }
}
