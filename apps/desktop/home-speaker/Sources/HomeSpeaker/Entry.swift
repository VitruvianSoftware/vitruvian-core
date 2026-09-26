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

import AppKit
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

        // The Stop hook's detached announcement (ClaudeStopHook.run): exactly
        // `--announce <text>`, so a reply that happens to contain a flag name
        // is never mistaken for one. Automated, so quiet hours hold.
        if arguments.first == ClaudeStopHook.announceArgument, arguments.count == 2, let text = arguments.last {
            announce(text, force: false)
        }

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
            announce(arguments[arguments.index(after: i)...].joined(separator: " "), force: true)
        }

        // The default speaker's volume, as JSON on stdout -- the contract the
        // Mac agent (android-remote) relies on. `--set-volume N`, `--mute` and
        // `--unmute` change it and answer with the level read back afterwards.
        // Failures are still JSON (available:false + reason) and exit 1.
        let volumeFlags = ["--volume", "--set-volume", "--mute", "--unmute"]
        if let flag = volumeFlags.first(where: { arguments.contains($0) }) {
            // A constant, not a var: the headless task below runs concurrently.
            let level: Int? = flag == "--set-volume" ? {
                guard let i = arguments.firstIndex(of: "--set-volume"), arguments.index(after: i) < arguments.endIndex,
                      let n = Int(arguments[arguments.index(after: i)]), (0...100).contains(n) else {
                    printVolumeJSON(["available": false, "reason": "--set-volume needs a whole number from 0 to 100"]); exit(1)
                }
                return n
            }() : nil
            // Two 6 s confirm windows plus retries: 40 s, not --say's 20.
            runHeadless(timeout: 40, onTimeout: { printVolumeJSON(["available": false, "reason": "timed out"]); exit(1) }) {
                let config = await MainActor.run { ConfigManager.shared.config }
                guard let target = config.defaultDevice else {
                    printVolumeJSON(["available": false, "reason": "no default speaker; open HomeSpeaker and pick one"]); exit(1)
                }
                let client = GoogleHomeClient.shared
                do {
                    var confirmed: SpeakerVolume?
                    switch flag {
                    case "--set-volume":
                        confirmed = try await client.setVolumeConfirmed(level ?? 0, on: target, structureId: config.structureId)
                    case "--mute": try await client.setMuted(true, on: target, structureId: config.structureId)
                    case "--unmute": try await client.setMuted(false, on: target, structureId: config.structureId)
                    default: break
                    }
                    // After a set, the level Google finally reports (it lags
                    // ~3 s); otherwise --set-volume 41 answers with the old 40.
                    let v: SpeakerVolume
                    if let confirmed { v = confirmed } else { v = try await client.volume(of: target, structureId: config.structureId) }
                    printVolumeJSON([
                        "available": true, "speaker": target.name,
                        "percent": v.percent, "muted": v.muted, "online": v.online,
                    ])
                } catch {
                    printVolumeJSON(["available": false, "speaker": target.name, "reason": error.localizedDescription]); exit(1)
                }
            }
        }

        // Browser sign-in from the terminal. `--chat` signs in for Google Chat
        // instead of Home (Google refuses both scopes in one grant, so they
        // are separate logins). Same flow the Settings buttons run.
        if arguments.contains("--sign-in") {
            let purpose: GoogleAuth.Purpose = arguments.contains("--chat") ? .chat : .home
            runHeadless(timeout: 300, onTimeout: { FileHandle.standardError.write(Data("error: timed out\n".utf8)); exit(1) }) {
                do {
                    let creds = try await GoogleAuth.shared.signIn(purpose: purpose) { url in
                        print("opening browser: \(url.host ?? "")")
                        _ = NSWorkspace.shared.open(url)
                    }
                    print("signed in as \(creds.email ?? "unknown"); scopes: \(creds.scopes.joined(separator: " "))")
                } catch {
                    FileHandle.standardError.write(Data("error: \(error.localizedDescription)\n".utf8)); exit(1)
                }
            }
        }

        // Without this, `--help` fell through to HomeSpeakerApp.main() and
        // hung a terminal on a second copy of the menu bar app.
        if arguments.contains("--help") || arguments.contains("-h") {
            print("""
            HomeSpeaker \(HomeSpeakerVersion.current) — speaks your coding agent's replies on a Google speaker.

            usage: HomeSpeaker [flag]
              (no flag)            run the menu bar app
              --say <text>         announce text on the default speaker and/or this Mac
              --volume             the default speaker's volume, as JSON
              --set-volume <0-100> set it; --mute / --unmute likewise
              --discover           list homes and broadcast targets
              --sign-in [--chat]   sign in for Home (or Google Chat)
              --claude-stop-hook   Claude Code Stop hook; reads hook JSON on stdin
              --version            print the version
              --help               print this
            """)
            exit(0)
        }

        if arguments.contains("--version") {
            print("HomeSpeaker \(HomeSpeakerVersion.current)")
            exit(0)
        }

        HomeSpeakerApp.main()
    }

    /// Speaks `text` on the home speakers and/or this Mac, as the settings
    /// say, and exits. Does not exit before this Mac has finished speaking
    /// (docs/local-speech.md rule 9). Exit 0 when anything was heard, or
    /// nothing was meant to be (quiet hours, no outputs); 1 when it failed.
    private static func announce(_ text: String, force: Bool) -> Never {
        let initial = MainActor.assumeIsolated { ConfigManager.shared.config }
        // 20 s covered a home broadcast; the Mac speaking adds its own time.
        var timeout: TimeInterval = 20
        if initial.effectiveSpeakLocal {
            timeout += LocalSpeaker.timeLimit(
                for: GoogleHomeClient.cleanForSpeech(text, length: initial.effectiveSpeechLength))
        }
        runHeadless(timeout: timeout, onTimeout: { FileHandle.standardError.write(Data("error: timed out\n".utf8)); exit(1) }) {
            let config = await MainActor.run { ConfigManager.shared.config }
            guard config.enabled else {
                FileHandle.standardError.write(Data("broadcasting is switched off\n".utf8)); exit(1)
            }
            // Home only with no speaker picked: the same message as before.
            if config.effectiveSpeakHome && !config.effectiveSpeakLocal && config.defaultDevice == nil {
                FileHandle.standardError.write(Data("no default speaker; open HomeSpeaker and pick one\n".utf8)); exit(1)
            }
            let outcome = await Announcer.shared.announce(text, config: config, force: force)
            switch outcome {
            case .disabled:
                FileHandle.standardError.write(Data("broadcasting is switched off\n".utf8)); exit(1)
            case .quietHours(let until):
                FileHandle.standardError.write(Data("Quiet hours active until \(until). Nothing spoken.\n".utf8))
            case .noOutputs:
                print(AnnounceOutcome.noOutputsMessage)
            case .nothingToSay:
                FileHandle.standardError.write(Data("nothing to say after cleaning up the text\n".utf8))
            case .announced(let home, let local):
                if home.didSpeak { print("sent to \(config.defaultDevice?.name ?? "the home speakers")") }
                if local.didSpeak { print("spoke on this Mac") }
                for failure in outcome.failureMessages {
                    FileHandle.standardError.write(Data("error: \(failure)\n".utf8))
                }
                if !outcome.anySpoke { exit(1) }
            }
        }
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

/// One JSON object on stdout, for the Mac agent to parse.
private func printVolumeJSON(_ object: [String: Any]) {
    if let data = try? JSONSerialization.data(withJSONObject: object, options: [.sortedKeys]),
       let line = String(data: data, encoding: .utf8) {
        print(line)
    }
}
