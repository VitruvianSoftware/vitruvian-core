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

import CompXHID
import CompXProtocol
import Foundation
import StatusSignals

/// Executes an `Invocation` against a mouse. Every side effect is injected,
/// so tests drive it with a mock transport and capture output.
public struct CLIRunner {
    public var open: (_ trace: Bool) throws -> GravaStarMouse
    public var out: (String) -> Void
    public var err: (String) -> Void
    public var sleep: (Duration) -> Void

    public init(
        open: @escaping (_ trace: Bool) throws -> GravaStarMouse,
        out: @escaping (String) -> Void,
        err: @escaping (String) -> Void,
        sleep: @escaping (Duration) -> Void
    ) {
        self.open = open
        self.out = out
        self.err = err
        self.sleep = sleep
    }

    /// The real thing: IOKit, stdout/stderr, wall-clock sleep.
    public static let live = CLIRunner(
        open: { trace in
            try GravaStarMouse.open(trace: trace ? { line in FileHandle.standardError.write(Data("trace \(line)\n".utf8)) } : nil)
        },
        out: { print($0) },
        err: { FileHandle.standardError.write(Data(($0 + "\n").utf8)) },
        sleep: { Thread.sleep(forTimeInterval: Double($0.components.seconds) + Double($0.components.attoseconds) / 1e18) }
    )

    /// Parses and runs. Returns the process exit code.
    public func main(_ arguments: [String]) -> Int32 {
        let invocation: Invocation
        do {
            invocation = try CLI.parse(arguments)
        } catch {
            err("gravastar-mouse: \(error)")
            err("run 'gravastar-mouse --help' for usage")
            return 2
        }
        return run(invocation)
    }

    public func run(_ invocation: Invocation) -> Int32 {
        if invocation.command == .help {
            out(CLI.usage)
            return 0
        }
        if invocation.command == .version {
            out(CLI.version)
            return 0
        }
        if invocation.command == .mcp {
            // stdout carries the protocol now; the server captures what each
            // tool call prints instead.
            MCPServer(runner: self, baselinePath: invocation.baselinePath)
                .serve(readLine: { Swift.readLine(strippingNewline: true) },
                       write: { FileHandle.standardOutput.write(Data(($0 + "\n").utf8)) })
            return 0
        }
        let store = invocation.baselinePath.map { BaselineStore(url: URL(fileURLWithPath: $0)) } ?? BaselineStore()
        do {
            try execute(invocation, store: store)
            return 0
        } catch {
            err("gravastar-mouse: \(error)")
            return 1
        }
    }

    private func execute(_ invocation: Invocation, store: BaselineStore) throws {
        let mouse = try open(invocation.trace)
        defer { mouse.close() }
        let indicator = MouseStatusIndicator(mouse: mouse, store: store)

        switch invocation.command {
        case .help, .mcp, .version:
            out(CLI.usage)
        case let .status(json):
            let config = try mouse.readLighting()
            out(json ? try Self.json(config) : Self.describe(config))
        case .off:
            try mouse.writeLighting(StatusPresets.lighting(for: .off))
            out("Mouse LEDs turned OFF.")
        case let .color(rgb, brightness):
            let current = try mouse.readLighting()
            try mouse.writeLighting(LightingConfig(mode: .fixed, color: rgb, speed: current.speed, brightness: brightness))
            out("Mouse set to Fixed Color \(rgb.hexString) (Brightness: \(brightness)).")
        case let .breathe(rgb, speed, brightness):
            try mouse.writeLighting(LightingConfig(mode: .breathe, color: rgb, speed: speed, brightness: brightness))
            out("Mouse set to Breathe \(rgb.hexString) (Speed: \(speed), Brightness: \(brightness)).")
        case let .rainbow(speed, brightness):
            try mouse.writeLighting(LightingConfig(mode: .rainbow, color: RGB(r: 255, g: 0, b: 0), speed: speed, brightness: brightness))
            out("Mouse set to Rainbow mode (Speed: \(speed), Brightness: \(brightness)).")
        case let .set(config):
            try mouse.writeLighting(config)
            out("Mouse set to \(config.mode) \(config.color.hexString) (Speed: \(config.speed), Brightness: \(config.brightness)).")
        case let .signal(signal, restoreAfter):
            try indicator.signal(signal)
            out("Signal \(signal.rawValue): \(Self.summary(StatusPresets.lighting(for: signal))). Baseline: \(store.url.path)")
            if let restoreAfter {
                // Release the device while waiting; reopen it for the restore.
                mouse.close()
                sleep(restoreAfter)
                let later = try open(invocation.trace)
                defer { later.close() }
                report(try MouseStatusIndicator(mouse: later, store: store).restore(ifShowing: signal))
            }
        case .restore:
            report(try indicator.restore())
        }
    }

    private func report(_ result: RestoreResult) {
        switch result {
        case let .restored(config): out("Restored \(Self.summary(config)).")
        case .noBaseline: out("No baseline saved; nothing to restore.")
        case let .skipped(current): out("Light changed since the signal (now \(Self.summary(current))); left as is.")
        }
    }

    static func describe(_ config: LightingConfig) -> String {
        """
        GravaStar Mouse Lighting Status:
          Mode:       \(config.mode) (ID \(config.mode.rawValue))
          Color:      \(config.color.hexString) RGB(\(config.color.r), \(config.color.g), \(config.color.b))
          Brightness: \(config.brightness) / 9
          Speed:      \(config.speed) / 9
        """
    }

    static func summary(_ config: LightingConfig) -> String {
        "\(config.mode.name) \(config.color.hexString) speed \(config.speed) brightness \(config.brightness)"
    }

    static func json(_ config: LightingConfig) throws -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        return String(decoding: try encoder.encode(config), as: UTF8.self)
    }
}
