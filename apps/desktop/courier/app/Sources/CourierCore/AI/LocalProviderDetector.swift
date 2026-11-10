// Copyright 2026 VitruvianSoftware
// SPDX-License-Identifier: AGPL-3.0-or-later

import Foundation

public enum LocalDetection: Equatable, Sendable {
    case running(models: [String])
    case needsKey
    case notRunning
}

/// Probes local model servers on `127.0.0.1` concurrently (`Ollama`, `LM Studio`, and `Unsloth Studio`).
/// Never contacts non-localhost hosts.
public final class LocalProviderDetector: @unchecked Sendable {
    public static let ollamaTagsURL = URL(string: "http://127.0.0.1:11434/api/tags")!
    public static let lmStudioModelsURL = URL(string: "http://127.0.0.1:1234/v1/models")!
    public static let unslothPorts: ClosedRange<Int> = 8888 ... 8908

    private let transport: any HTTPTransport
    private let lock = NSLock()
    private var _detectedUnslothPort: Int?

    public init(transport: any HTTPTransport = URLSessionHTTPTransport.shared) {
        self.transport = transport
    }

    public var detectedUnslothPort: Int? {
        lock.withLock { _detectedUnslothPort }
    }

    /// Base URL for Unsloth Studio when a running or key-protected instance was detected; `nil` when none was detected.
    public var unslothBaseURL: URL? {
        guard let port = detectedUnslothPort else { return nil }
        return URL(string: "http://127.0.0.1:\(port)/v1")
    }

    public func detect(unslothKey: String? = nil) async -> [AIProviderKind: LocalDetection] {
        let transport = self.transport
        let trimmedKey = unslothKey?.trimmingCharacters(in: .whitespacesAndNewlines)
        let activeKey = (trimmedKey?.isEmpty == false) ? trimmedKey : nil

        enum ProbeKind: Sendable {
            case ollama(LocalDetection)
            case lmStudio(LocalDetection)
            case unsloth(port: Int, detection: LocalDetection)
        }

        var ollamaResult: LocalDetection = .notRunning
        var lmStudioResult: LocalDetection = .notRunning
        var unslothByPort: [Int: LocalDetection] = [:]

        await withTaskGroup(of: ProbeKind.self) { group in
            group.addTask {
                let detection = await Self.probeOllama(using: transport)
                return .ollama(detection)
            }
            group.addTask {
                let detection = await Self.probeOpenAIModels(
                    url: Self.lmStudioModelsURL,
                    apiKey: nil,
                    using: transport
                )
                return .lmStudio(detection)
            }
            for port in Self.unslothPorts {
                group.addTask {
                    let url = URL(string: "http://127.0.0.1:\(port)/v1/models")!
                    let detection = await Self.probeOpenAIModels(
                        url: url,
                        apiKey: nil,
                        using: transport
                    )
                    return .unsloth(port: port, detection: detection)
                }
            }

            for await result in group {
                switch result {
                case let .ollama(detection):
                    ollamaResult = detection
                case let .lmStudio(detection):
                    lmStudioResult = detection
                case let .unsloth(port, detection):
                    unslothByPort[port] = detection
                }
            }
        }

        var unslothResult: LocalDetection = .notRunning
        var chosenPort: Int?
        for port in Self.unslothPorts {
            if case let .running(models) = unslothByPort[port] {
                unslothResult = .running(models: models)
                chosenPort = port
                break
            }
        }
        if chosenPort == nil {
            for port in Self.unslothPorts {
                if unslothByPort[port] == .needsKey {
                    unslothResult = .needsKey
                    chosenPort = port
                    break
                }
            }
            if let chosenPort, let activeKey {
                let url = URL(string: "http://127.0.0.1:\(chosenPort)/v1/models")!
                let keyedDetection = await Self.probeOpenAIModels(
                    url: url,
                    apiKey: activeKey,
                    using: transport
                )
                if case let .running(models) = keyedDetection {
                    unslothResult = .running(models: models)
                }
            }
        }

        lock.withLock {
            _detectedUnslothPort = chosenPort
        }

        return [
            .ollama: ollamaResult,
            .lmStudio: lmStudioResult,
            .unslothStudio: unslothResult,
        ]
    }

    private static func isLocalhost(_ url: URL) -> Bool {
        let host = url.host?.lowercased() ?? ""
        return host == "127.0.0.1" || host == "localhost" || host == "::1"
    }

    private static func probeOllama(using transport: any HTTPTransport) async -> LocalDetection {
        guard isLocalhost(ollamaTagsURL) else { return .notRunning }
        var request = URLRequest(url: ollamaTagsURL, timeoutInterval: AIClientHTTP.detectionProbeTimeout)
        request.httpMethod = "GET"
        guard let (data, response) = try? await transport.send(request) else {
            return .notRunning
        }
        switch response.statusCode {
        case 200 ..< 300:
            guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                return .notRunning
            }
            if let models = json["models"] as? [[String: Any]] {
                let names = models.compactMap { item -> String? in
                    let raw = (item["name"] as? String) ?? (item["model"] as? String) ?? (item["id"] as? String)
                    guard let raw else { return nil }
                    let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
                    return trimmed.isEmpty ? nil : trimmed
                }
                return .running(models: names)
            }
            if let dataItems = json["data"] as? [[String: Any]] {
                let ids = dataItems.compactMap { ($0["id"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines) }
                    .filter { !$0.isEmpty }
                return .running(models: ids)
            }
            return .notRunning
        case 401:
            return .needsKey
        default:
            return .notRunning
        }
    }

    private static func probeOpenAIModels(
        url: URL,
        apiKey: String?,
        using transport: any HTTPTransport
    ) async -> LocalDetection {
        guard isLocalhost(url) else { return .notRunning }
        var request = URLRequest(url: url, timeoutInterval: AIClientHTTP.detectionProbeTimeout)
        request.httpMethod = "GET"
        if let apiKey {
            request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        }
        guard let (data, response) = try? await transport.send(request) else {
            return .notRunning
        }
        switch response.statusCode {
        case 200 ..< 300:
            guard let models = try? OpenAICompatibleClient.parseModels(from: data) else {
                return .notRunning
            }
            return .running(models: models)
        case 401:
            return .needsKey
        default:
            return .notRunning
        }
    }
}
