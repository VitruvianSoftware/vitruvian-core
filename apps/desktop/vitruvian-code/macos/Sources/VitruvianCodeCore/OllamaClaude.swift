// Copyright (c) 2026 VitruvianSoftware
//
// Permission is hereby granted, free of charge, to any person obtaining a copy
// of this software and associated documentation files (the "Software"), to deal
// in the Software without restriction, including without limitation the rights
// to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
// copies of the Software, and to permit persons to whom the Software is
// furnished to do so, subject to the following conditions:
//
// The above copyright notice and this permission notice shall be included in
// all copies or substantial portions of the Software.
//
// THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
// IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
// FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
// AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
// LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
// OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
// SOFTWARE.
//
// Shared by the standalone Vitruvian Code app and the Code feature of the
// Vitruvian desktop app. Written for Vitruvian and released under MIT by its
// copyright holder on 2026-10-09 (apps/desktop/vitruvian-atrium/UPSTREAM.md).

import Foundation

/// Ollama (claude) on the Agent SDK connection: Claude Code, run by the bundled helper as for
/// Claude, pointed at the user's Ollama server (design section 9, "Ollama (claude): Agent SDK,
/// with Ollama's endpoint").
///
/// The variables are the ones `ollama launch claude` sets itself (Ollama's
/// `cmd/launch/claude.go`), so a chat on the SDK reaches the same server, with the same model,
/// as one on the command line. The model is also passed as the SDK's own `model`
/// (the `model` field of the session's `_meta` on `session/new` and `session/resume`).
///
/// None of these values is a secret. `ANTHROPIC_AUTH_TOKEN` is Ollama's fixed placeholder:
/// Ollama's docs call it "required but ignored", and its local server does not check keys.
/// So it goes in the helper's environment like `CLAUDE_CONFIG_DIR`. A real token (for a
/// server that checks one) is a value the user marks sensitive: it travels in
/// `_vitruvian/secrets` as every stored secret does, and the helper applies those last, so it
/// replaces the placeholder.
public enum OllamaClaude {
    /// The program the helper drives. `ollama launch claude` runs this same `claude`.
    public static let claudeProgramName = "claude"

    /// What Ollama's launcher sets `ANTHROPIC_AUTH_TOKEN` to: Claude Code needs one, Ollama
    /// ignores it.
    public static let authTokenPlaceholder = "ollama"

    /// Where the `ollama` program and server read the server's address from.
    public static let hostVariable = "OLLAMA_HOST"

    /// Ollama's own port, used when the address names none.
    public static let defaultPort = "11434"

    /// The model a chat runs with: the one chosen in the app, or, with none chosen, the one
    /// the chat found with `ollama list` (`VitruvianCodeSupport.ollamaDefaultModel(fromList:)`),
    /// as the command-line connection decides it (`VitruvianCodeSupport.agentArguments`).
    public static func model(configured: String, ollamaDefaultModel: String) -> String {
        let chosen = configured.trimmingCharacters(in: .whitespaces)
        return chosen.isEmpty ? ollamaDefaultModel : chosen
    }

    /// The server's address as a client connects to it, from `OLLAMA_HOST` as the `ollama`
    /// program reads it: Ollama's `envconfig.Host()` (scheme, host, port and path, default
    /// `http://127.0.0.1:11434`), with a listen-everywhere address (`0.0.0.0`, `::`) turned
    /// into this Mac's own, as its `envconfig.ConnectableHost()` does.
    public static func serverURL(ollamaHost raw: String?) -> String {
        let quotes = CharacterSet(charactersIn: "\"'")
        let value = (raw ?? "").trimmingCharacters(in: .whitespacesAndNewlines).trimmingCharacters(in: quotes)
        var scheme = "http"
        var hostPort = value
        var portWhenMissing = defaultPort
        if let separator = value.range(of: "://") {
            scheme = String(value[..<separator.lowerBound])
            hostPort = String(value[separator.upperBound...])
            if scheme == "http" { portWhenMissing = "80" }
            if scheme == "https" { portWhenMissing = "443" }
        } else if value == "ollama.com" {
            scheme = "https"
            hostPort = "ollama.com:443"
        }
        var path = ""
        if let slash = hostPort.firstIndex(of: "/") {
            path = String(hostPort[hostPort.index(after: slash)...])
            hostPort = String(hostPort[..<slash])
        }
        var host: String
        var port: String
        if let split = splitHostPort(hostPort) {
            (host, port) = split
        } else {
            host = "127.0.0.1"
            port = portWhenMissing
            let bare = hostPort.trimmingCharacters(in: CharacterSet(charactersIn: "[]"))
            if isIPAddress(bare) {
                host = bare
            } else if !hostPort.isEmpty {
                host = hostPort
            }
        }
        if let number = Int(port), (0...65535).contains(number) {
            port = String(number)
        } else {
            port = portWhenMissing
        }
        if host == "0.0.0.0" { host = "127.0.0.1" }
        if host == "::" { host = "::1" }
        let joined = host.contains(":") ? "[\(host)]:\(port)" : "\(host):\(port)"
        return "\(scheme)://\(joined)" + (path.isEmpty ? "" : "/\(path)")
    }

    /// What the helper's environment gains for an Ollama chat: the routing variables of
    /// `ollama launch claude` and its model for every model tier, so Claude Code's own
    /// background and subagent calls go to Ollama too. `ANTHROPIC_API_KEY` is set empty, as
    /// Ollama's launcher sets it, so the user's own Anthropic key is never sent to the server.
    public static func environment(serverURL: String, model: String) -> [String: String] {
        [
            "ANTHROPIC_BASE_URL": serverURL,
            "ANTHROPIC_API_KEY": "",
            "ANTHROPIC_AUTH_TOKEN": authTokenPlaceholder,
            // Keeps the routing to this launch even when Claude's settings name another endpoint.
            "CLAUDE_CODE_PROVIDER_MANAGED_BY_HOST": "1",
            "CLAUDE_CODE_USE_BEDROCK": "",
            "CLAUDE_CODE_USE_VERTEX": "",
            "CLAUDE_CODE_USE_FOUNDRY": "",
            "CLAUDE_CODE_USE_ANTHROPIC_AWS": "",
            "CLAUDE_CODE_USE_ANTHROPIC_GOOGLE_CLOUD": "",
            "CLAUDE_CODE_USE_MANTLE": "",
            "CLAUDE_CODE_USE_GATEWAY": "",
            "ANTHROPIC_DEFAULT_OPUS_MODEL": model,
            "ANTHROPIC_DEFAULT_SONNET_MODEL": model,
            "ANTHROPIC_DEFAULT_HAIKU_MODEL": model,
            "CLAUDE_CODE_SUBAGENT_MODEL": model,
        ]
    }

    /// `base` (the helper's environment) with the Ollama variables for `model` on top, the
    /// server's address read from that same environment's `OLLAMA_HOST`.
    public static func helperEnvironment(_ base: [String: String], model: String) -> [String: String] {
        base.merging(environment(serverURL: serverURL(ollamaHost: base[hostVariable]), model: model)) { _, ollama in ollama }
    }

    /// Go's `net.SplitHostPort`: `host:port` or `[v6]:port`. Nil when there is no port, or
    /// when an unbracketed host has a colon of its own.
    private static func splitHostPort(_ text: String) -> (String, String)? {
        if text.hasPrefix("[") {
            guard let close = text.firstIndex(of: "]") else { return nil }
            let rest = text[text.index(after: close)...]
            guard rest.hasPrefix(":") else { return nil }
            return (String(text[text.index(after: text.startIndex)..<close]), String(rest.dropFirst()))
        }
        guard let colon = text.lastIndex(of: ":") else { return nil }
        let host = text[..<colon]
        guard !host.contains(":") else { return nil }
        return (String(host), String(text[text.index(after: colon)...]))
    }

    private static func isIPAddress(_ text: String) -> Bool {
        var v4 = in_addr()
        var v6 = in6_addr()
        return inet_pton(AF_INET, text, &v4) == 1 || inet_pton(AF_INET6, text, &v6) == 1
    }
}

extension VitruvianCodeCLIProvider {
    /// True when this provider's turns go to Claude Code through the bundled helper: Claude,
    /// or Ollama (claude), with the Agent SDK connection chosen.
    public var runsOnClaudeSDK: Bool {
        (route == .claude || route == .ollama) && connection == .claudeSDK
    }
}
