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

import XCTest

import VitruvianToolCLI
import VitruvianToolProtocol

/// `vitruvian-tool run` against real processes: small shell scripts that
/// speak the protocol, each behaving one way a tool can.
///
/// None can hang the test. Every wait in `run` has a limit, and the tests
/// make the limits short. A script starts a program of its own only when a
/// test asks for one, a `sleep` that ends by itself after a minute, and
/// that test sees it gone, or ends it. Each test that makes a tool stay
/// checks that its process is gone when `run` returns.
final class RunTests: XCTestCase {
    /// A tool in `/bin/sh`. `n` counts what the app has asked, which is the
    /// id the app gave it: 1 for `initialize`, 2 for the first command.
    private static let script = #"""
        #!/bin/sh
        n=0
        say() { printf '%s\n' "$1"; }
        done_() { say "{\"jsonrpc\":\"2.0\",\"id\":$n,\"result\":{}}"; }
        refused() { say "{\"jsonrpc\":\"2.0\",\"id\":$n,\"error\":{\"code\":-32010,\"message\":\"command refused\"}}"; }
        ask() {
          say "{\"jsonrpc\":\"2.0\",\"id\":\"a\",\"method\":\"$1\",\"params\":$2}"
          IFS= read -r answer
          case "$answer" in *'"error"'*) return 1 ;; esac
        }
        [ -n "$PIDFILE" ] && echo $$ > "$PIDFILE"
        if [ -n "$HELPERFILE" ]; then
          /bin/sleep 60 < /dev/null > /dev/null 2>&1 &
          echo $! > "$HELPERFILE"
        fi
        [ "$HOW" = gone ] && exit 0
        while IFS= read -r line; do
          case "$line" in
            *'"method":"initialize"'*)
              n=1
              hello="$line"
              [ "$HOW" = chatty ] && say "starting up"
              [ "$HOW" = mute ] && continue
              version=1
              [ "$HOW" = newer ] && version=3
              say "{\"jsonrpc\":\"2.0\",\"id\":1,\"result\":{\"protocolVersion\":\"$version\",\"toolVersion\":\"7\"}}"
              say '{"jsonrpc":"2.0","method":"commands/state","params":{"runnable":["hello","where"]}}'
              if [ "$HOW" = flood ]; then
                while :; do say '{"jsonrpc":"2.0","method":"log","params":{"message":"again"}}'; done
              fi
              ;;
            *'"command":"hello"'*)
              n=$((n + 1))
              if ask notify/hud '{"icon":"hand.wave","message":"Hi"}'; then done_; else refused; fi
              ;;
            *'"command":"where"'*)
              n=$((n + 1))
              say "{\"jsonrpc\":\"2.0\",\"method\":\"log\",\"params\":{\"message\":\"cwd=$PWD path=$PATH\"}}"
              done_
              ;;
            *'"command":"save"'*)
              n=$((n + 1))
              ask storage/set '{"key":"count","value":"three"}' || say '{"jsonrpc":"2.0","method":"log","params":{"message":"not saved"}}'
              ask storage/set '{"key":"count","value":3}'
              ask storage/get '{"key":"count"}'
              ask clipboard/writeText '{"text":"copied"}'
              done_
              ;;
            *'"command":"status"'*)
              n=$((n + 1))
              case "$hello" in
                *'"features":["ui.status","ui.choice","preferences.options","ui.status.activity","ui.open.settings","ui.chips","ui.sections","notify.notice","ui.slot","preferences.folder"]'*)
                  say '{"jsonrpc":"2.0","method":"log","params":{"message":"the app has a status"}}' ;;
              esac
              ask ui/status '{"state":"busy","text":"Working"}' || say '{"jsonrpc":"2.0","method":"log","params":{"message":"no status"}}'
              done_
              ;;
            *'"command":"hang"'*)
              n=$((n + 1))
              ;;
            *'"command":"crash"'*)
              exit 3
              ;;
            *'"method":"shutdown"'*)
              if [ "$HOW" = stubborn ]; then
                trap '' TERM
                while :; do :; done
              fi
              exit 0
              ;;
          esac
        done
        """#

    private static let manifest = #"""
        {"id":"com.example.run","name":{"en":"Run"},"version":"7","protocol":"1","publisher":"Example",
         "uses":["notify","storage"],
         "contributes":{"commands":[{"id":"hello","title":{"en":"Hello"}},{"id":"where","title":{"en":"Where"}},
           {"id":"save","title":{"en":"Save"}},{"id":"hang","title":{"en":"Hang"}},
           {"id":"crash","title":{"en":"Crash"}}]},
         "preferences":[{"id":"count","type":"integer","default":0}],
         "runtime":{"kind":"external","exec":"bin/tool"}}
        """#

    /// A tool of protocol 2 with the one command `status`, which declares a
    /// status when `declared`.
    private static func statusManifest(declared: Bool) -> String {
        #"""
        {"id":"com.example.run","name":{"en":"Run"},"version":"7","protocol":"2","publisher":"Example",
         "contributes":{"commands":[{"id":"status","title":{"en":"Status"}}]\#(declared ? #","status":{"placement":"island"}"# : "")},
         "runtime":{"kind":"external","exec":"bin/tool"}}
        """#
    }

    /// The manifest the next run's tool has.
    private var manifest = RunTests.manifest
    private var scratch = Scratch()

    override func setUp() {
        scratch = Scratch()
    }

    override func tearDown() {
        scratch.remove()
    }

    private func toolFolder() -> URL {
        let folder = scratch.folder("tool")
        Scratch.write(manifest, to: folder.appendingPathComponent("vitruvian-tool.json"))
        // The listing's indentation is not part of the script.
        let script = Self.script.split(separator: "\n", omittingEmptySubsequences: false).joined(separator: "\n")
        Scratch.write(script + "\n", to: folder.appendingPathComponent("bin/tool"), mode: 0o755)
        return folder
    }

    /// The process id a script wrote into `file`, or 0.
    private static func pid(in file: String) -> pid_t {
        pid_t((try? String(contentsOfFile: file, encoding: .utf8))?.trimmingCharacters(in: .whitespacesAndNewlines) ?? "") ?? 0
    }

    /// Waits a moment for the `sleep` a script started to be gone, and says
    /// whether it is. One that is still there is ended here, when it is
    /// still that `sleep` and not a process that took its id since.
    private static func helperIsGone(_ helper: pid_t) -> Bool {
        let limit = Date().addingTimeInterval(5)
        func gone() -> Bool { kill(helper, 0) == -1 && errno == ESRCH }
        while !gone(), Date() < limit { usleep(10000) }
        if gone() { return true }
        var path = [CChar](repeating: 0, count: 4 * Int(MAXPATHLEN))
        if proc_pidpath(helper, &path, UInt32(path.count)) > 0, String(cString: path) == "/bin/sleep" {
            kill(helper, SIGKILL)
        }
        return false
    }

    /// Runs the tool, and gives back what was printed and the status. With
    /// `helper`, the tool starts a program of its own first, and that
    /// program too must be gone by the time `run` returns.
    private func run(_ commands: [String] = [], how: String = "", typing: String? = nil, helper: Bool = false,
                     change: (inout RunOptions) -> Void = { _ in }) throws -> (said: [String], status: Int32) {
        var options = RunOptions()
        options.commands = commands
        options.firstAnswerSeconds = 2
        options.answerSeconds = 0.3
        options.exitSeconds = 0.3
        options.endSeconds = 0.3
        change(&options)
        let typed = scratch.url.appendingPathComponent("typed")
        try Data((typing ?? "").utf8).write(to: typed)
        let handle = try FileHandle(forReadingFrom: typed)
        defer { try? handle.close() }
        var said: [String] = []
        let pidFile = scratch.url.appendingPathComponent("pid").path
        let helperFile = scratch.url.appendingPathComponent("helper-\(UUID().uuidString)").path
        var environment = ["HOW": how, "PIDFILE": pidFile, "PATH": "/usr/bin:/bin:/opt/extra"]
        if helper { environment["HELPERFILE"] = helperFile }
        let started = Date()
        let status = VitruvianToolCommand.run(folder: toolFolder(), options: options,
                                              environment: environment,
                                              typing: handle.fileDescriptor, say: { said.append($0) })
        XCTAssertLessThan(Date().timeIntervalSince(started), 10, "no run waits for long")
        // The tool's process is gone by the time `run` returns.
        let pid = pid_t((try? String(contentsOfFile: pidFile, encoding: .utf8))?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? "") ?? 0
        XCTAssertTrue(pid > 0 && kill(pid, 0) == -1 && errno == ESRCH, "process \(pid) is still there")
        if helper {
            let started = Self.pid(in: helperFile)
            XCTAssertGreaterThan(started, 1, "the tool started a program of its own")
            XCTAssertTrue(started > 1 && Self.helperIsGone(started),
                          "the program the tool started, process \(started), is still there (\(how))")
        }
        return (said, status)
    }

    /// `run` plays the app's side here too: a program the tool started is
    /// ended with the tool, however the tool ends.
    func testTheProgramsAToolStartedEndWithIt() throws {
        let (left, status) = try run(["hello"], helper: true)
        XCTAssertEqual(status, 0, "a tool that leaves when told goodbye: \(left)")
        XCTAssertTrue(left.contains("stopped  exited with 0"), "\(left)")

        let (killed, failed) = try run(["hello"], how: "stubborn", helper: true)
        XCTAssertEqual(failed, 1)
        XCTAssertTrue(killed.contains { $0.hasPrefix("NOT OK   still running 0.3 seconds after shutdown") }, "\(killed)")

        let (crashed, crash) = try run(["crash"], helper: true)
        XCTAssertEqual(crash, 1)
        XCTAssertTrue(crashed.contains { $0.hasPrefix("NOT OK   the tool exited while `crash` ran, with status 3") },
                      "\(crashed)")
    }

    func testACommandRunsAndTheToolIsToldGoodbye() throws {
        let (all, status) = try run(["hello", "where"])
        XCTAssertEqual(status, 0, "\(all)")
        XCTAssertEqual(all.first, "note     This is not the app. Every service the manifest lists is granted, and "
            + "nothing real is done. There is no idle stop, no restart after a crash and no flood count.",
                       "where a run is not the app is said once, first")
        XCTAssertEqual(all.filter { $0.hasPrefix("note") }.count, 1)
        let said = Array(all.dropFirst())
        XCTAssertTrue(said[0].hasPrefix("started  bin/tool, in "))
        let folder = String(said[0].dropFirst("started  bin/tool, in ".count))
        XCTAssertTrue(folder.contains("vitruvian-tool-run-"))
        XCTAssertFalse(FileManager.default.fileExists(atPath: folder), "the folder made for the run is deleted")
        XCTAssertEqual(Array(said[1...4]), [
            "hello    protocol 1, tool version 7",
            "state    can run now: hello, where",
            "asked    notify/hud: the app would show \"Hi\" with the symbol hand.wave",
            "ran      hello",
        ])
        XCTAssertTrue(said[5].hasPrefix("log      cwd=") && said[5].contains(folder.split(separator: "/").last ?? "?"),
                      "the tool runs in the folder it was told is its own: \(said[5])")
        XCTAssertTrue(said[5].hasSuffix("path=/usr/bin:/bin:/opt/extra"), "with the environment it was started in")
        XCTAssertEqual(Array(said[6...]), ["ran      where", "stopped  exited with 0", "", "run: OK"])
    }

    func testTheShortPathOfTheApp() throws {
        let (said, status) = try run(["where"]) { $0.appPath = true }
        XCTAssertEqual(status, 0)
        XCTAssertTrue(said.contains { $0.hasSuffix("path=/usr/bin:/bin:/usr/sbin:/sbin") }, "\(said)")
    }

    func testTheHelloSaysWhatTheAppHasAndAStatusIsSaid() throws {
        manifest = Self.statusManifest(declared: true)
        let (said, status) = try run(["status"])
        XCTAssertEqual(status, 0, "\(said)")
        XCTAssertEqual(said.filter { $0.hasPrefix("asked") || $0.hasPrefix("log") || $0.hasPrefix("ran") }, [
            "log      the app has a status",
            "asked    ui/status: the app would show busy on the closed island, saying \"Working\"",
            "ran      status",
        ], "run says hello as an app that has all four, and needs nothing in `uses` for a status")

        manifest = Self.statusManifest(declared: false)
        let (refused, again) = try run(["status"])
        XCTAssertEqual(again, 0, "a tool that copes with the refusal passes: \(refused)")
        XCTAssertEqual(refused.filter { $0.hasPrefix("asked") || $0.hasPrefix("log") }, [
            "log      the app has a status",
            "asked    ui/status: refused: the manifest declares no status. Add `contributes.status`",
            "log      no status",
        ], "a status the manifest does not declare is refused, as the app refuses it")
    }

    func testEveryRequestRefused() throws {
        let (said, status) = try run(["hello"]) { $0.refuse = true }
        XCTAssertEqual(status, 0, "a tool that copes with a refusal passes")
        XCTAssertTrue(said.contains("asked    notify/hud: refused, as --refuse asks"))
        XCTAssertTrue(said.contains("refused  hello: command refused (-32010)"))
    }

    func testWhatTheToolSavesStaysInTheRun() throws {
        let (said, status) = try run(["save"])
        XCTAssertEqual(status, 0, "\(said)")
        XCTAssertEqual(said.filter { $0.hasPrefix("asked") || $0.hasPrefix("log") }, [
            "asked    storage/set: refused: `count` holds integer, not \"three\"",
            "log      not saved",
            "asked    storage/set: `count` is now 3, for this run only",
            "asked    storage/get: `count` is 3",
            "asked    clipboard/writeText: refused: `clipboard.write` is not in the manifest's `uses`",
        ])
    }

    func testTypedCommands() throws {
        let (said, status) = try run(typing: "hello\n\nwhere\nquit\nhello\n")
        XCTAssertEqual(status, 0, "\(said)")
        XCTAssertTrue(said.contains("Type a command's id and Return to run it: hello, where, save, hang, crash. "
                + "`quit` ends."))
        XCTAssertEqual(said.filter { $0.hasPrefix("ran") }, ["ran      hello", "ran      where"], "nothing after quit")
        let (more, again) = try run(typing: "hello")
        XCTAssertEqual(again, 0, "the end of what is typed ends the run: \(more)")
        XCTAssertFalse(more.contains("ran      hello"), "a line with no Return is not a command")
    }

    func testACommandTheManifestDoesNotHave() throws {
        let (said, status) = try run(["nope"])
        XCTAssertEqual(status, 1)
        XCTAssertTrue(said.contains("NOT OK   the manifest has no command `nope`"))
        XCTAssertEqual(said.last, "run: FAILED")
    }

    func testAToolThatDoesNotAnswer() throws {
        let (said, status) = try run(["hang", "hello"])
        XCTAssertEqual(status, 1)
        XCTAssertTrue(said.contains { $0.hasPrefix("NOT OK   no answer to `hang` within 0.3 seconds") }, "\(said)")
        XCTAssertTrue(said.contains("ran      hello"), "the run goes on, as the app does")
        XCTAssertTrue(said.contains("stopped  exited with 0"))
    }

    func testAToolThatSaysNothingAtAll() throws {
        let (said, status) = try run(["hello"], how: "mute") { $0.firstAnswerSeconds = 0.3 }
        XCTAssertEqual(status, 1)
        XCTAssertTrue(said.contains("NOT OK   no answer to initialize within 0.3 seconds"), "\(said)")
        XCTAssertFalse(said.contains { $0.hasPrefix("ran") }, "no command is sent to a tool that did not say hello")
    }

    func testAToolThatWillNotLeaveIsKilled() throws {
        let (said, status) = try run(["hello"], how: "stubborn")
        XCTAssertEqual(status, 1)
        XCTAssertTrue(said.contains { $0.hasPrefix("NOT OK   still running 0.3 seconds after shutdown") }, "\(said)")
    }

    func testAToolThatDiesMidCommand() throws {
        let (said, status) = try run(["crash", "hello"])
        XCTAssertEqual(status, 1)
        XCTAssertTrue(said.contains { $0.hasPrefix("NOT OK   the tool exited while `crash` ran, with status 3") },
                      "\(said)")
        XCTAssertFalse(said.contains { $0.hasPrefix("ran") }, "nothing more is asked of a tool that has gone")
    }

    func testAToolThatExitsAtOnce() throws {
        let (said, status) = try run(["hello"], how: "gone")
        XCTAssertEqual(status, 1)
        // Which of the two is said depends on whether the tool had gone
        // before `initialize` was written to it, or only before it answered.
        XCTAssertTrue(said.contains { $0 == "NOT OK   the tool exited before it answered initialize"
                              || $0 == "NOT OK   the tool closed its input" }, "\(said)")
        XCTAssertFalse(said.contains { $0.hasPrefix("ran") }, "no command is sent to a tool that has gone")
        XCTAssertTrue(said.contains("stopped  exited with 0"), "\(said)")
        XCTAssertEqual(said.last, "run: FAILED")
    }

    /// The app counts a tool's lines a second and stops one that floods.
    /// `run` does not count them: it prints each line, and its own limits
    /// still end the run, so a flood cannot hold it.
    func testAToolThatFloodsDoesNotHoldTheRun() throws {
        let (said, status) = try run(["hello"], how: "flood")
        XCTAssertEqual(status, 1)
        XCTAssertGreaterThan(said.filter { $0 == "log      again" }.count, 200, "each line is printed")
        XCTAssertTrue(said.contains { $0.hasPrefix("NOT OK   no answer to `hello` within 0.3 seconds") })
        XCTAssertTrue(said.contains { $0.hasPrefix("NOT OK   still running 0.3 seconds after shutdown") })
        XCTAssertEqual(said.last, "run: FAILED")
    }

    /// Control-C, or a request to end, while a tool runs: the tool's program
    /// is killed, the folder made for the run is deleted, and the command
    /// exits with 130. The command is started as a program of its own here,
    /// because the signal ends the process that gets it.
    func testAnInterruptKillsTheToolAndDeletesItsFolder() throws {
        let environment = ProcessInfo.processInfo.environment
        guard let path = environment["VITRUVIAN_TOOL_BINARY"] else {
            throw XCTSkip("the built command is handed to the tests by Bazel, in VITRUVIAN_TOOL_BINARY")
        }
        var binary = URL(fileURLWithPath: path)
        if let runfiles = environment["TEST_SRCDIR"], !path.hasPrefix("/") {
            binary = URL(fileURLWithPath: "\(runfiles)/\(environment["TEST_WORKSPACE"] ?? "_main")/\(path)")
        }
        let folder = toolFolder()
        for (name, number) in [("interrupt", SIGINT), ("terminate", SIGTERM)] {
            let pidFile = scratch.url.appendingPathComponent("pid-\(name)").path
            let helperFile = scratch.url.appendingPathComponent("helper-\(name)").path
            let command = Process()
            command.executableURL = binary
            command.arguments = ["run", folder.path]
            command.environment = environment.merging(["PIDFILE": pidFile, "HELPERFILE": helperFile, "HOW": ""]) { $1 }
            // Nothing is typed, and the typing does not end: the run waits.
            let typing = Pipe()
            let printed = Pipe()
            command.standardInput = typing
            command.standardOutput = printed
            try command.run()
            // Only the command holds the end it writes to, so that reading
            // what it printed ends when it does.
            try printed.fileHandleForWriting.close()

            func wait(_ seconds: TimeInterval, until done: () -> Bool) -> Bool {
                let limit = Date().addingTimeInterval(seconds)
                while !done(), Date() < limit { usleep(10000) }
                return done()
            }
            var tool: pid_t = 0
            let started = wait(10) {
                tool = pid_t((try? String(contentsOfFile: pidFile, encoding: .utf8))?
                    .trimmingCharacters(in: .whitespacesAndNewlines) ?? "") ?? 0
                return tool > 0
            }
            XCTAssertTrue(started, "\(name): the tool was started")
            // Time for the tool to say hello, so that the run is waiting for
            // a command to be typed.
            usleep(300_000)
            XCTAssertTrue(command.isRunning, "\(name): the run waits for a command")
            XCTAssertEqual(kill(tool, 0), 0, "\(name): the tool is running")

            kill(command.processIdentifier, number)
            let ended = wait(5) { !command.isRunning }
            if !ended { kill(command.processIdentifier, SIGKILL) }
            command.waitUntilExit()
            XCTAssertTrue(ended, "\(name): the command ends")
            XCTAssertEqual(command.terminationReason, .exit, name)
            XCTAssertEqual(command.terminationStatus, 130, name)
            // The command kills the tool and exits; macOS then clears the
            // dead process away, which can take a moment.
            let gone = wait(5) { kill(tool, 0) == -1 && errno == ESRCH }
            if !gone, started { kill(tool, SIGKILL) }
            XCTAssertTrue(gone, "\(name): process \(tool) is still there")
            let helper = Self.pid(in: helperFile)
            XCTAssertTrue(helper > 1 && Self.helperIsGone(helper),
                          "\(name): the program the tool started, process \(helper), is still there")

            let said = String(decoding: printed.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
                .split(separator: "\n").map(String.init)
            let prefix = "started  bin/tool, in "
            let made = said.first { $0.hasPrefix(prefix) }.map { String($0.dropFirst(prefix.count)) } ?? ""
            XCTAssertTrue(made.contains("vitruvian-tool-run-"), "\(name): \(said)")
            XCTAssertFalse(FileManager.default.fileExists(atPath: made), "\(name): the folder made for the run is deleted")
            try? typing.fileHandleForWriting.close()
        }
    }

    func testAToolThatSpeaksOutOfTurnOrPicksAnotherVersion() throws {
        var (said, status) = try run(["hello"], how: "chatty")
        XCTAssertEqual(status, 1)
        XCTAssertTrue(said.contains { $0.hasPrefix("NOT OK   a line that is not a message: starting up") }, "\(said)")
        (said, status) = try run(["hello"], how: "newer")
        XCTAssertEqual(status, 1)
        XCTAssertTrue(said.contains { $0.hasPrefix("NOT OK   the tool picked protocol 3") }, "\(said)")
    }

    func testAFolderTheAppWouldRefuseIsNotStarted() throws {
        let folder = toolFolder()
        chmod(folder.appendingPathComponent("bin/tool").path, 0o644)
        var said: [String] = []
        XCTAssertEqual(VitruvianToolCommand.main(["run", folder.path, "--command", "hello"],
                                                 say: { said.append($0) }), 1)
        XCTAssertTrue(said[0].hasPrefix("NOT OK   the program `bin/tool` is not a file macOS will run"))
        XCTAssertTrue(said.last?.hasPrefix("Nothing was started") == true)
    }

    func testTheArgumentsOfRun() {
        var options = RunOptions()
        options.commands = ["a", "b"]
        options.refuse = true
        options.appPath = true
        options.answerSeconds = 5
        XCTAssertEqual(VitruvianToolCommand.runArguments(["tool", "--command", "a", "--refuse", "--command", "b",
                                                          "--app-path", "--wait", "5"])?.options, options)
        XCTAssertEqual(VitruvianToolCommand.runArguments(["tool"])?.folder, "tool")
        for bad in [[], ["--refuse"], ["a", "b"], ["a", "--command"], ["a", "--wait", "soon"], ["a", "--wait", "0"],
                    ["a", "--real-clipboard"]] {
            XCTAssertNil(VitruvianToolCommand.runArguments(bad[...]), "\(bad)")
        }
    }

    /// A tool written with the kit, built by Bazel, under `run`.
    func testTheSwiftSampleRuns() throws {
        guard let manifest = ProcessInfo.processInfo.environment["VITRUVIAN_HELLO_SWIFT"] else {
            throw XCTSkip("the built sample is handed to the tests by Bazel, in VITRUVIAN_HELLO_SWIFT")
        }
        var built = URL(fileURLWithPath: manifest).deletingLastPathComponent()
        if let runfiles = ProcessInfo.processInfo.environment["TEST_SRCDIR"], !manifest.hasPrefix("/") {
            let workspace = ProcessInfo.processInfo.environment["TEST_WORKSPACE"] ?? "_main"
            built = URL(fileURLWithPath: "\(runfiles)/\(workspace)/\(manifest)").deletingLastPathComponent()
        }
        // Among a test's runfiles each file is a link to where Bazel built
        // it, which is outside the folder: `run` would rightly refuse it. A
        // copy with the links followed is a folder a person could add.
        let folder = scratch.folder("hello-swift")
        for (file, mode) in [("vitruvian-tool.json", 0o644), ("bin/tool", 0o755)] {
            let bytes = try Data(contentsOf: built.appendingPathComponent(file))
            try FileManager.default.createDirectory(at: folder.appendingPathComponent(file).deletingLastPathComponent(),
                                                    withIntermediateDirectories: true)
            try bytes.write(to: folder.appendingPathComponent(file))
            chmod(folder.appendingPathComponent(file).path, mode_t(mode))
        }
        var said: [String] = []
        let status = VitruvianToolCommand.main(["run", folder.path, "--command", "hello", "--command", "count",
                                                "--command", "count"], say: { said.append($0) })
        XCTAssertEqual(status, 0, "\(said)")
        XCTAssertEqual(said.filter { $0.hasPrefix("asked    notify/hud") }, [
            "asked    notify/hud: the app would show \"Hello from a Swift tool\" with the symbol hand.wave",
            "asked    notify/hud: the app would show \"Counted to 1\" with the symbol number",
            "asked    notify/hud: the app would show \"Counted to 2\" with the symbol number",
        ])
        XCTAssertEqual(Array(said.suffix(3)), ["stopped  exited with 0", "", "run: OK"])
    }

    /// `run` touches nothing of the person's. That is a property of what
    /// its code can reach, so it is held here: the command's sources import
    /// Foundation and the protocol, and name nothing that reaches the
    /// clipboard, the screen or another app.
    func testTheCommandCanReachNothingOfThePersons() throws {
        let sources = PackageFiles.url("Sources/VitruvianToolCLI/Command.swift").deletingLastPathComponent()
        let files = try FileManager.default.contentsOfDirectory(at: sources, includingPropertiesForKeys: nil)
            // Templates.swift is the samples as text, not code of the command.
            .filter { $0.pathExtension == "swift" && $0.lastPathComponent != "Templates.swift" }
        XCTAssertGreaterThanOrEqual(files.count, 5)
        for file in files {
            let text = try String(contentsOf: file, encoding: .utf8)
            let imports = text.split(separator: "\n").filter { $0.hasPrefix("import ") }.map(String.init)
            XCTAssertEqual(Set(imports).subtracting(["import Foundation", "import VitruvianToolProtocol"]), [],
                           file.lastPathComponent)
            for name in ["NSPasteboard", "NSWorkspace", "NSSound", "NSAppleScript", "CGEvent", "AXUIElement",
                         "/usr/bin/open", "osascript", "pbcopy"] {
                XCTAssertFalse(text.contains(name), "\(file.lastPathComponent) names \(name)")
            }
            // The one process this command may signal is the one it started,
            // and the one process group, the group that process leads.
            let kills = text.split(separator: "\n").filter { $0.contains("kill(") || $0.contains("killpg(") }
            XCTAssertTrue(kills.allSatisfy {
                $0.contains("kill(process.processIdentifier,") || $0.contains("kill(tool,") || $0.contains("killpg(group,")
            }, "\(file.lastPathComponent): \(kills)")
        }
    }
}
