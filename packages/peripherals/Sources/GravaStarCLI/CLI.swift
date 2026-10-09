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
import StatusSignals

/// One parsed subcommand.
public enum CLICommand: Equatable, Sendable {
    case status(json: Bool)
    case off
    /// Fixed colour. Speed is kept from the device, as the prototype did.
    case color(RGB, brightness: Level)
    case breathe(RGB, speed: Level, brightness: Level)
    case rainbow(speed: Level, brightness: Level)
    case set(LightingConfig)
    case signal(StatusSignal, restoreAfter: Duration?)
    case restore
    /// Serve the commands as MCP tools on stdin/stdout (`MCPServer`).
    case mcp
    case version
    case help
}

/// A whole command line: the subcommand plus the global flags.
public struct Invocation: Equatable, Sendable {
    public var command: CLICommand
    /// Hex-dump every frame to stderr.
    public var trace: Bool
    /// Overrides where the baseline lives (tests, experiments).
    public var baselinePath: String?

    public init(command: CLICommand, trace: Bool = false, baselinePath: String? = nil) {
        self.command = command
        self.trace = trace
        self.baselinePath = baselinePath
    }
}

/// A bad command line. Exit code 2.
public struct UsageError: Error, Equatable, CustomStringConvertible {
    public let message: String
    public init(_ message: String) { self.message = message }
    public var description: String { message }
}

public enum CLI {
    /// The tool's version, reported by `--version` and to MCP clients.
    /// release-please bumps it (packages/peripherals in release-please-config.json).
    public static let version = "0.1.1" // x-release-please-version

    public static let usage = """
    usage: gravastar-mouse [--trace] [--baseline PATH] <command> [options]

    commands:
      status [--json]                                show the current lighting (default)
      off                                            turn the LED off
      color <color> [--brightness N]                 fixed colour
      breathe <color> [--speed N] [--brightness N]   single-colour breathe
      rainbow [--speed N] [--brightness N]           rainbow cycle
      set --mode M [--color C] [--speed N] [--brightness N]
      signal <working|success|failure|warning|attention|off> [--restore-after SECONDS]
      restore                                        put back the lighting saved before the last signal
      mcp                                            serve these commands as MCP tools over stdio
      version                                        print the version (also --version)

    <color> is a name (red green blue cyan magenta purple yellow orange white pink)
    or hex (#00ffcc). N is 0-9. Modes: off rainbow breathe fixed neon
    rainbow-breathe fixed-rainbow.
    exit codes: 0 ok, 1 mouse/protocol error (incl. "mouse not found"), 2 usage error
    """

    /// Turns `CommandLine.arguments.dropFirst()` into an `Invocation`.
    /// Pure: no device, no files, so it is unit-tested directly.
    public static func parse(_ arguments: [String]) throws -> Invocation {
        var positionals: [String] = []
        var options: [String: String] = [:]
        var flags: Set<String> = []
        let valued: Set<String> = ["--brightness", "--speed", "--mode", "--color", "--restore-after", "--baseline"]
        let boolean: Set<String> = ["--json", "--trace", "--help", "--version"]

        var index = 0
        while index < arguments.count {
            let arg = arguments[index]
            index += 1
            if arg == "-h" { flags.insert("--help"); continue }
            guard arg.hasPrefix("--") else { positionals.append(arg); continue }
            let parts = arg.split(separator: "=", maxSplits: 1).map(String.init)
            let name = parts[0]
            if boolean.contains(name) {
                guard parts.count == 1 else { throw UsageError("\(name) takes no value") }
                flags.insert(name)
            } else if valued.contains(name) {
                if parts.count == 2 {
                    options[name] = parts[1]
                } else {
                    guard index < arguments.count else { throw UsageError("\(name) needs a value") }
                    options[name] = arguments[index]
                    index += 1
                }
            } else {
                throw UsageError("unknown option \(name)")
            }
        }

        let trace = flags.contains("--trace")
        let baseline = options.removeValue(forKey: "--baseline")
        if flags.contains("--help") {
            return Invocation(command: .help, trace: trace, baselinePath: baseline)
        }
        if flags.contains("--version") {
            return Invocation(command: .version, trace: trace, baselinePath: baseline)
        }

        let name = positionals.first ?? "status"
        let args = Array(positionals.dropFirst())
        var allowedOptions: Set<String> = []
        var allowedFlags: Set<String> = ["--trace"]
        let command: CLICommand

        func expectArgs(_ count: Int, _ what: String) throws {
            guard args.count == count else {
                throw UsageError(count == 0
                    ? "\(name) takes no arguments" : "\(name) needs exactly one \(what)")
            }
        }

        switch name {
        case "status":
            try expectArgs(0, "")
            allowedFlags.insert("--json")
            command = .status(json: flags.contains("--json"))
        case "off":
            try expectArgs(0, "")
            command = .off
        case "color", "fixed":
            try expectArgs(1, "colour")
            allowedOptions = ["--brightness"]
            command = .color(try color(args[0]), brightness: try level(options["--brightness"], "--brightness", default: .seven))
        case "breathe":
            try expectArgs(1, "colour")
            allowedOptions = ["--speed", "--brightness"]
            command = .breathe(
                try color(args[0]),
                speed: try level(options["--speed"], "--speed", default: .five),
                brightness: try level(options["--brightness"], "--brightness", default: .seven))
        case "rainbow":
            try expectArgs(0, "")
            allowedOptions = ["--speed", "--brightness"]
            command = .rainbow(
                speed: try level(options["--speed"], "--speed", default: .five),
                brightness: try level(options["--brightness"], "--brightness", default: .seven))
        case "set":
            try expectArgs(0, "")
            allowedOptions = ["--mode", "--color", "--speed", "--brightness"]
            guard let modeName = options["--mode"] else { throw UsageError("set needs --mode") }
            guard let mode = LightingMode(name: modeName) else { throw UsageError("unknown mode '\(modeName)'") }
            command = .set(LightingConfig(
                mode: mode,
                color: try color(options["--color"] ?? "red"),
                speed: try level(options["--speed"], "--speed", default: .five),
                brightness: try level(options["--brightness"], "--brightness", default: .seven)))
        case "signal":
            try expectArgs(1, "signal name")
            allowedOptions = ["--restore-after"]
            guard let signal = StatusSignal(rawValue: args[0].lowercased()) else {
                let names = StatusSignal.allCases.map(\.rawValue).joined(separator: "|")
                throw UsageError("unknown signal '\(args[0])' (expected \(names))")
            }
            var after: Duration?
            if let text = options["--restore-after"] {
                guard let seconds = Double(text), seconds.isFinite, seconds > 0 else {
                    throw UsageError("--restore-after needs a positive number of seconds, got '\(text)'")
                }
                after = .milliseconds(Int64((seconds * 1000).rounded()))
            }
            command = .signal(signal, restoreAfter: after)
        case "restore":
            try expectArgs(0, "")
            command = .restore
        case "mcp":
            try expectArgs(0, "")
            command = .mcp
        case "version":
            try expectArgs(0, "")
            command = .version
        case "help":
            command = .help
        default:
            throw UsageError("unknown command '\(name)'")
        }

        if let stray = options.keys.sorted().first(where: { !allowedOptions.contains($0) }) {
            throw UsageError("\(name) does not take \(stray)")
        }
        if let stray = flags.sorted().first(where: { !allowedFlags.contains($0) }) {
            throw UsageError("\(name) does not take \(stray)")
        }
        return Invocation(command: command, trace: trace, baselinePath: baseline)
    }

    static func color(_ text: String) throws -> RGB {
        guard let rgb = RGB(text) else {
            throw UsageError("invalid colour '\(text)': use a name like cyan or hex like #00ffcc")
        }
        return rgb
    }

    static func level(_ text: String?, _ option: String, default fallback: Level) throws -> Level {
        guard let text else { return fallback }
        guard let number = Int(text), let level = Level(number) else {
            throw UsageError("\(option) must be 0-9, got '\(text)'")
        }
        return level
    }
}
