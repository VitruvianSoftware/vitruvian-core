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

import CompXProtocol
import Foundation
import StatusSignals

/// `gravastar-mouse mcp`: the same commands as the command line, offered to an
/// AI agent as Model Context Protocol tools over stdio (newline-delimited
/// JSON-RPC 2.0, https://modelcontextprotocol.io). No SDK: the protocol
/// surface a tools-only server needs is four methods.
///
/// Each tool call becomes a command line, parsed by `CLI.parse` (so the tools
/// and the CLI accept exactly the same values) and run by `CLIRunner` with its
/// output captured. Nothing but protocol messages reaches stdout.
public struct MCPServer {
    public static let name = "gravastar-mouse"
    /// What `initialize` answers when the client asks for a version this
    /// server does not know: the newest one it does.
    public static let protocolVersions = ["2025-06-18", "2025-03-26", "2024-11-05"]

    public var runner: CLIRunner
    /// The global `--baseline` the server was started with, if any.
    public var baselinePath: String?

    public init(runner: CLIRunner, baselinePath: String? = nil) {
        self.runner = runner
        self.baselinePath = baselinePath
    }

    // MARK: - Transport

    /// Reads messages until `readLine` returns nil (stdin closed), answering
    /// each request on `write`. Notifications get no answer.
    public func serve(readLine: () -> String?, write: (String) -> Void) {
        while let line = readLine() {
            guard !line.trimmingCharacters(in: .whitespaces).isEmpty else { continue }
            if let reply = handle(line) { write(reply) }
        }
    }

    // MARK: - Messages

    /// Answers one JSON-RPC message, or nil when it needs no answer.
    public func handle(_ line: String) -> String? {
        guard let object = try? JSONSerialization.jsonObject(with: Data(line.utf8)),
              let message = object as? [String: Any] else {
            return Self.encode(["jsonrpc": "2.0", "id": NSNull(),
                                "error": ["code": -32700, "message": "parse error"] as [String: Any]])
        }
        // A message without an id is a notification (`notifications/initialized`,
        // `notifications/cancelled`): nothing to answer, whatever its method.
        guard let id = message["id"], let method = message["method"] as? String else { return nil }
        let params = message["params"] as? [String: Any] ?? [:]

        let result: [String: Any]
        switch method {
        case "initialize":
            var version = Self.protocolVersions[0]
            if let asked = params["protocolVersion"] as? String, Self.protocolVersions.contains(asked) {
                version = asked
            }
            result = [
                "protocolVersion": version,
                "capabilities": ["tools": [String: Any]()],
                "serverInfo": ["name": Self.name, "version": CLI.version],
                "instructions": Self.instructions,
            ]
        case "ping":
            result = [:]
        case "tools/list":
            result = ["tools": Self.tools]
        case "tools/call":
            guard let name = params["name"] as? String else {
                return Self.error(id, -32602, "tools/call needs a tool name")
            }
            guard Self.tools.contains(where: { $0["name"] as? String == name }) else {
                return Self.error(id, -32602, "unknown tool '\(name)'")
            }
            result = call(name, params["arguments"] as? [String: Any] ?? [:])
        default:
            return Self.error(id, -32601, "method '\(method)' not found")
        }
        return Self.encode(["jsonrpc": "2.0", "id": id, "result": result])
    }

    // MARK: - Tools

    /// Runs one tool. A bad argument or a missing mouse is a tool error the
    /// agent can read and act on, not a protocol error.
    func call(_ name: String, _ arguments: [String: Any]) -> [String: Any] {
        let line: [String]
        do {
            line = try Self.commandLine(for: name, arguments)
        } catch {
            return Self.toolResult("\(error)", isError: true)
        }
        let invocation: Invocation
        do {
            invocation = try CLI.parse(line)
        } catch {
            return Self.toolResult("\(error)", isError: true)
        }
        let captured = Captured()
        var quiet = runner
        quiet.out = { captured.out.append($0) }
        quiet.err = { captured.err.append($0) }
        let code = quiet.run(Invocation(command: invocation.command, trace: false,
                                        baselinePath: baselinePath ?? invocation.baselinePath))
        let text = (code == 0 ? captured.out : captured.err + captured.out).joined(separator: "\n")
        return Self.toolResult(text.isEmpty ? (code == 0 ? "ok" : "failed") : text, isError: code != 0)
    }

    /// The command line a tool call stands for. Values are passed through as
    /// text, so `CLI.parse` is what validates them.
    static func commandLine(for name: String, _ arguments: [String: Any]) throws -> [String] {
        func text(_ key: String) -> String? {
            switch arguments[key] {
            case let value as String: return value
            case let value as NSNumber: return value.stringValue
            default: return nil
            }
        }
        func required(_ key: String) throws -> String {
            guard let value = text(key) else { throw UsageError("\(name) needs '\(key)'") }
            return value
        }
        func options(_ keys: String...) -> [String] {
            keys.flatMap { key in text(key).map { ["--\(key)", $0] } ?? [] }
        }
        switch name {
        case "mouse_status": return ["status", "--json"]
        case "mouse_signal": return ["signal", try required("signal")]
        case "mouse_restore": return ["restore"]
        case "mouse_color": return ["color", try required("color")] + options("brightness")
        case "mouse_breathe": return ["breathe", try required("color")] + options("speed", "brightness")
        case "mouse_rainbow": return ["rainbow"] + options("speed", "brightness")
        case "mouse_off": return ["off"]
        default: throw UsageError("unknown tool '\(name)'")
        }
    }

    static let instructions = """
    Controls the RGB light of a GravaStar mouse attached to this Mac. Use mouse_signal to show \
    status (working while you run something, then success or failure), and mouse_restore to put \
    back the person's own lighting afterwards. A missing mouse is normal (the laptop may be \
    undocked): the tool reports it and nothing else happens.
    """

    static var tools: [[String: Any]] {
        let level: [String: Any] = ["type": "integer", "minimum": 0, "maximum": 9]
        let color: [String: Any] = [
            "type": "string",
            "description": "A name (\(RGBNames.list)) or hex such as #00ffcc.",
        ]
        func tool(_ name: String, _ title: String, _ description: String,
                  _ properties: [String: Any] = [:], required: [String] = [],
                  readOnly: Bool = false) -> [String: Any] {
            var schema: [String: Any] = ["type": "object", "properties": properties,
                                         "additionalProperties": false]
            if !required.isEmpty { schema["required"] = required }
            return ["name": name, "title": title, "description": description, "inputSchema": schema,
                    "annotations": ["readOnlyHint": readOnly, "destructiveHint": false,
                                    "idempotentHint": true, "openWorldHint": false]]
        }
        return [
            tool("mouse_status", "Read mouse lighting",
                 "The mouse's current lighting as JSON: mode, color, speed and brightness.", readOnly: true),
            tool("mouse_signal", "Show a status signal",
                 "Shows a status: working (blue, breathing), success (green), failure (red, breathing), "
                     + "warning (amber), attention (magenta, breathing) or off. The person's own lighting "
                     + "is saved first, so mouse_restore can put it back.",
                 ["signal": ["type": "string", "enum": StatusSignal.allCases.map(\.rawValue)] as [String: Any]],
                 required: ["signal"]),
            tool("mouse_restore", "Restore the person's lighting",
                 "Puts back the lighting saved before the last signal. Harmless when nothing was saved."),
            tool("mouse_color", "Set a solid color", "A solid color, keeping the mouse's speed.",
                 ["color": color, "brightness": level], required: ["color"]),
            tool("mouse_breathe", "Set a breathing color", "One color fading in and out.",
                 ["color": color, "speed": level, "brightness": level], required: ["color"]),
            tool("mouse_rainbow", "Set rainbow", "A rainbow cycle.", ["speed": level, "brightness": level]),
            tool("mouse_off", "Turn the light off", "Turns the mouse's light off."),
        ]
    }

    static func toolResult(_ text: String, isError: Bool) -> [String: Any] {
        ["content": [["type": "text", "text": text]], "isError": isError]
    }

    static func error(_ id: Any, _ code: Int, _ message: String) -> String {
        encode(["jsonrpc": "2.0", "id": id, "error": ["code": code, "message": message] as [String: Any]])
    }

    /// One line of JSON. JSONSerialization never pretty-prints unless asked,
    /// so the message has no newline in it, as the stdio transport requires.
    static func encode(_ message: [String: Any]) -> String {
        guard let data = try? JSONSerialization.data(withJSONObject: message,
                                                     options: [.sortedKeys, .withoutEscapingSlashes]) else {
            return #"{"error":{"code":-32603,"message":"internal error"},"id":null,"jsonrpc":"2.0"}"#
        }
        return String(decoding: data, as: UTF8.self)
    }
}

/// What a tool call printed, collected instead of reaching stdout.
private final class Captured {
    var out: [String] = []
    var err: [String] = []
}

private enum RGBNames {
    static var list: String { RGB.named.keys.sorted().joined(separator: ", ") }
}
