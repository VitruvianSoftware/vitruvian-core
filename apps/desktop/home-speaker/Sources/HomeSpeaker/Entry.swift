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

import Foundation
import HomeSpeakerCore

// The same binary is both the menu bar app and the Claude Code Stop hook.
// Claude Code runs `HomeSpeaker --claude-stop-hook` with JSON on stdin; that
// path must never bring up a UI, so it is decided before SwiftUI starts.
// (An explicit @main type rather than top-level code in main.swift, because
// Bazel's swift_library compiles with -parse-as-library.)
@main
enum Entry {
    static func main() {
        let arguments = CommandLine.arguments.dropFirst()

        if arguments.contains(ClaudeStopHook.argument) {
            let input = FileHandle.standardInput.readDataToEndOfFile()
            // Claude Code enforces its own hook timeout; this backstop means a
            // hung network call can never wedge the agent. Output is always
            // "{}" so Claude Code sees a well-formed, no-op hook result.
            runHeadless(timeout: 8, onTimeout: { print("{}") }) {
                await ClaudeStopHook.run(input: input)
                print("{}")
            }
        }

        // Support/diagnostic mode: prints the homes and broadcast targets the
        // signed-in account can see, without touching the saved config.
        if arguments.contains("--discover") {
            runHeadless(timeout: 60, onTimeout: { print("error: timed out") }) {
                do {
                    let homes = try await GoogleHomeClient.shared.listHomes()
                    for home in homes {
                        print("home: \(home.name) (\(home.id))")
                        let targets = try await GoogleHomeClient.shared.discoverBroadcastTargets(structureId: home.id)
                        for (alias, d) in targets.sorted(by: { $0.key < $1.key }) {
                            print("  \(alias)\t\(d.type)\t\(d.displayLine)\t\(d.id)")
                        }
                    }
                    if homes.isEmpty { print("no homes visible to this account") }
                } catch {
                    FileHandle.standardError.write(Data("error: \(error.localizedDescription)\n".utf8))
                }
            }
        }

        // Scriptable announcement: `HomeSpeaker --say "dinner is ready"`.
        // Deliberate, like Quick Announce, so it overrides quiet hours but
        // still honours the master switch. Exit 1 on failure so scripts can tell.
        if let i = arguments.firstIndex(of: "--say") {
            let text = arguments[arguments.index(after: i)...].joined(separator: " ")
            runHeadless(timeout: 20, onTimeout: { FileHandle.standardError.write(Data("error: timed out\n".utf8)); exit(1) }) {
                let config = await MainActor.run { ConfigManager.shared.config }
                guard config.enabled else {
                    FileHandle.standardError.write(Data("broadcasting is switched off\n".utf8)); exit(1)
                }
                guard let target = config.defaultDevice else {
                    FileHandle.standardError.write(Data("no default speaker; open HomeSpeaker and pick one\n".utf8)); exit(1)
                }
                do {
                    _ = try await GoogleHomeClient.shared.broadcast(
                        text: text, target: target, structureId: config.structureId, config: config, force: true)
                    print("sent to \(target.name)")
                } catch {
                    FileHandle.standardError.write(Data("error: \(error.localizedDescription)\n".utf8)); exit(1)
                }
            }
        }

        if arguments.contains("--version") {
            print("HomeSpeaker \(HomeSpeakerVersion.current)")
            exit(0)
        }

        HomeSpeakerApp.main()
    }

    /// Runs `body` off the main actor while the main queue is serviced, then
    /// exits. `@main`'s `main()` is MainActor-isolated, so a plain `Task {}`
    /// here would inherit that and deadlock against a blocking wait; the
    /// config store is MainActor-bound too, so the main queue must keep
    /// running (`dispatchMain`) rather than block on a semaphore.
    private static func runHeadless(
        timeout: TimeInterval,
        onTimeout: @escaping @Sendable () -> Void,
        _ body: @escaping @Sendable () async -> Void
    ) -> Never {
        Task.detached {
            await body()
            exit(0)
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + timeout) {
            onTimeout()
            exit(0)
        }
        dispatchMain()
    }
}
