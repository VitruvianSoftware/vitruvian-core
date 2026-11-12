# Ai

## Overview
Component package providing implementation for `apps/desktop/vitruvian-courier/app/Sources/VitruvianCourierCore/AI`.

## Interface
- `[AIChatTurn.swift:AIChatTurn]`
- `[AIChatTurn.swift:AIChatContext]`
- `[AIKeyStore.swift:AIKeyStoreError]`
- `[AIKeyStore.swift:AIKeyStore]`
- `[AIOutputFormatter.swift:AIOutputFormatter]`
- `[AIPrompts.swift:AIPrompts]`
- `[AIProviderKind.swift:AIProviderKind]`
- `[AIProviderStore.swift:AIProviderStore]`
- `[AnthropicClient.swift:AnthropicClient]`
- `[AppleOnDeviceClient.swift:AppleOnDeviceClient]`
- `[ChatModelClient.swift:ChatModelClient]`
- `[ChatModelClient.swift:AIClientError]`
- `[ChatModelClient.swift:AIClientHTTP]`
- `[ConfiguredAIProvider.swift:ConfiguredAIProvider]`
- `[GeminiClient.swift:GeminiClient]`
- `[HTTPTransport.swift:HTTPTransport]`
- `[HTTPTransport.swift:URLSessionHTTPTransport]`
- `[HTTPTransport.swift:StubHTTPTransport]`
- `[LocalProviderDetector.swift:LocalDetection]`
- `[LocalProviderDetector.swift:LocalProviderDetector]`
- Subdirectory: [Speech](./Speech/README.md)

## Invariants
- [AIProviderKind.swift:62]: `/// Cloud providers and Unsloth Studio require an API key (`true`);`

## Side Effects
- [AIProviderKind.swift:166]: `URL(string: "http://127.0.0.1:11434/v1")`
- [AIProviderKind.swift:168]: `URL(string: "http://127.0.0.1:1234/v1")`
- [ChatModelClient.swift:31]: `? String(localized: "The AI provider returned an error (HTTP \(status)).")`
- [HTTPTransport.swift:13]: `private let session: URLSession`
- [HTTPTransport.swift:15]: `public init(session: URLSession = .shared) {`
- [HTTPTransport.swift:21]: `guard let http = response as? HTTPURLResponse else {`
- [LocalProviderDetector.swift:15]: `public static let ollamaTagsURL = URL(string: "http://127.0.0.1:11434/api/tag...`
- [LocalProviderDetector.swift:16]: `public static let lmStudioModelsURL = URL(string: "http://127.0.0.1:1234/v1/m...`
- [LocalProviderDetector.swift:103]: `return URL(string: "http://127.0.0.1:\(port)/v1")`

## Verification
- Run: `bazel test //apps/desktop/vitruvian-courier/app/Sources/VitruvianCourierCore/AI/...`
