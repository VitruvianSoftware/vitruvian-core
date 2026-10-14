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
import VitruvianToolProtocol

/// How `vitruvian-tool run` is to play the app's side.
public struct RunOptions: Equatable, Sendable {
    /// The commands to run, in order. With none, the person types them.
    public var commands: [String] = []
    /// Refuse every request the tool makes.
    public var refuse = false
    /// Start the tool with the short `PATH` the app has.
    public var appPath = false
    /// How long the tool has to answer `initialize`. The app's is 10.
    public var firstAnswerSeconds: TimeInterval = 10
    /// How long it has to answer a command. The app's is 2.
    public var answerSeconds: TimeInterval = 2
    /// How long it has to exit after the goodbye. The app's is 2, and then
    /// 1 more after it is asked to end.
    public var exitSeconds: TimeInterval = 2
    public var endSeconds: TimeInterval = 1

    public init() {}
}

/// The tool's program as this command ends it, the way the app does: with
/// the programs it started. macOS starts a `Process` in a process group of
/// its own, which the programs it starts share unless they leave it. When
/// this command sees that the tool leads such a group, it signals the group;
/// when it does not, it signals the tool's process alone.
struct ToolFamily: Sendable {
    let tool: pid_t
    /// The process group the tool leads; nil when it was not seen to lead
    /// one, when the group is this command's own, or when its id is one no
    /// tool's group can have.
    let group: pid_t?

    init(tool: pid_t) {
        self.tool = tool
        let own = getpgid(tool)
        group = tool > 1 && own == tool && own != getpgrp() && own != getpid() ? own : nil
    }

    /// Sends a signal to the tool and to what it started. Only for a tool
    /// that has not been waited for yet.
    func signal(_ number: Int32) {
        if let group {
            _ = killpg(group, number)
        } else {
            _ = kill(tool, number)
        }
    }

    /// Ends what the tool left running, once the tool itself has exited and
    /// been waited for. A process that has the tool's id by then is another
    /// program, and its group is left alone.
    func endWhatIsLeft() {
        guard let group, kill(tool, 0) == -1, errno == ESRCH else { return }
        _ = killpg(group, SIGKILL)
    }
}

/// One run of a tool's program with this command in the app's place.
///
/// It works on one thread. Every wait is a `poll` with a time limit, but
/// one: the wait for the person to type the next command, which also ends
/// when the tool exits or the person's input does. However a run ends, the
/// tool's program is killed if it is still there and waited for, with the
/// programs it started, and the folder made for it is deleted.
final class Session {
    private enum Event {
        case message(RPCMessage)
        /// A line that is not a message, or one over 1 MB.
        case junk(String)
        case toolEnded
        case typed(String)
        case typingEnded
        case late
    }

    private let manifest: ToolManifestFile
    private let options: RunOptions
    private let say: (String) -> Void
    private let process = Process()
    private let toTool = Pipe()
    private let fromTool = Pipe()
    private let dataFolder: URL
    /// What the person types is read from here; nil when `--command` gave
    /// the commands.
    private let typing: Int32?

    private var desk: Desk
    private var splitter = LineSplitter()
    /// What the tool has sent that has not been looked at yet.
    private var events: [Event] = []
    /// The lines the person has typed that have not been acted on yet. They
    /// wait here while a command runs.
    private var lines: [String] = []
    private var typed = Data()
    private var toolEnded = false
    private var typingEnded = false
    private var lastID = 0
    private var runnable: Set<String>?
    private var failed = false
    /// The tool's program and what it started, once it runs.
    private var family: ToolFamily?

    init(manifest: ToolManifestFile, options: RunOptions, typing: Int32?, say: @escaping (String) -> Void) {
        self.manifest = manifest
        self.options = options
        self.typing = options.commands.isEmpty ? typing : nil
        self.say = say
        desk = Desk(manifest: manifest)
        desk.refuseAll = options.refuse
        dataFolder = FileManager.default.temporaryDirectory
            .appendingPathComponent("vitruvian-tool-run-\(UUID().uuidString)", isDirectory: true)
    }

    private static var now: TimeInterval { ProcessInfo.processInfo.systemUptime }

    private func line(_ word: String, _ text: String) {
        say(word.padding(toLength: 9, withPad: " ", startingAt: 0) + text)
    }

    private func notOK(_ text: String) {
        failed = true
        line("NOT OK", text)
    }

    /// Starts the program in `folder`, plays the app, and returns the status
    /// to exit with: 0 when the tool did everything the app would accept.
    func run(folder: URL, environment: [String: String]) -> Int32 {
        // A link that has gone is seen as a failed write, not as a signal.
        signal(SIGPIPE, SIG_IGN)
        do {
            try FileManager.default.createDirectory(at: dataFolder, withIntermediateDirectories: true,
                                                    attributes: [.posixPermissions: 0o700])
        } catch {
            notOK("no folder could be made for the tool to run in: \(error.localizedDescription)")
            return 1
        }
        defer { try? FileManager.default.removeItem(at: dataFolder) }

        var environment = environment
        if options.appPath { environment["PATH"] = FolderCheck.shortPath }
        process.executableURL = folder.appendingPathComponent(manifest.runtime.exec)
        process.currentDirectoryURL = dataFolder
        process.environment = environment
        process.standardInput = toTool
        process.standardOutput = fromTool
        do {
            try process.run()
        } catch {
            notOK("macOS would not start `\(manifest.runtime.exec)`: \(error.localizedDescription)")
            return 1
        }
        let family = ToolFamily(tool: process.processIdentifier)
        self.family = family
        // Whatever happens from here on, the program is ended and waited
        // for, and so is what it started.
        defer {
            if process.isRunning { family.signal(SIGKILL) }
            process.waitUntilExit()
            family.endWhatIsLeft()
        }
        let interrupt = Self.endOnInterrupt(family, dataFolder.path)
        defer {
            interrupt.forEach { $0.cancel() }
            signal(SIGINT, SIG_DFL)
            signal(SIGTERM, SIG_DFL)
        }
        // Never wait on a tool that has stopped reading.
        let writing = toTool.fileHandleForWriting.fileDescriptor
        _ = fcntl(writing, F_SETFL, fcntl(writing, F_GETFL) | O_NONBLOCK)

        line("started", "\(manifest.runtime.exec), in \(dataFolder.path)")
        guard greet() else {
            stop()
            return 1
        }
        if options.commands.isEmpty {
            converse()
        } else {
            for command in options.commands where !toolEnded { runCommand(command) }
        }
        stop()
        return failed ? 1 : 0
    }

    /// Control-C, or being asked to end: the tool's program is killed, with
    /// the programs it started, its folder deleted, and this command exits.
    /// The handler runs on a queue of its own, because the main thread is
    /// waiting in `poll`.
    private static func endOnInterrupt(_ family: ToolFamily, _ folder: String) -> [any DispatchSourceSignal] {
        [SIGINT, SIGTERM].map { number in
            signal(number, SIG_IGN)
            let source = DispatchSource.makeSignalSource(signal: number, queue: .global())
            source.setEventHandler {
                family.signal(SIGKILL)
                try? FileManager.default.removeItem(atPath: folder)
                exit(130)
            }
            source.resume()
            return source
        }
    }

    // MARK: - The link

    private func send(_ message: RPCMessage) -> Bool {
        guard !toolEnded, let bytes = try? LineFraming.line(for: message) else { return false }
        let written = bytes.withUnsafeBytes { write(toTool.fileHandleForWriting.fileDescriptor, $0.baseAddress, $0.count) }
        if written == bytes.count { return true }
        notOK(written < 0 && errno == EPIPE ? "the tool closed its input"
            : "the tool is not reading its input: \(method(of: message)) could not be written")
        return false
    }

    private func method(of message: RPCMessage) -> String {
        switch message {
        case .request(_, let method, _), .notice(let method, _): return method
        case .result, .failure: return "an answer"
        }
    }

    /// What happens next: a message from the tool, a line the person typed
    /// when `listening`, the end of either, or `deadline` passing. With no
    /// deadline it waits for as long as something can still happen.
    private func next(before deadline: TimeInterval?, listening: Bool = false) -> Event {
        while true {
            if !events.isEmpty { return events.removeFirst() }
            if listening {
                if !lines.isEmpty { return .typed(lines.removeFirst()) }
                if typingEnded { return .typingEnded }
            }
            let hear = listening && typing != nil
            if toolEnded, !hear { return .toolEnded }
            var wait: Int32 = -1
            if let deadline {
                let left = deadline - Self.now
                if left <= 0 { return .late }
                wait = Int32(min((left * 1000).rounded(.up), 3_600_000))
            }
            var waiting = [pollfd(fd: toolEnded ? -1 : fromTool.fileHandleForReading.fileDescriptor,
                                  events: Int16(POLLIN), revents: 0),
                           pollfd(fd: hear ? typing ?? -1 : -1, events: Int16(POLLIN), revents: 0)]
            let ready = poll(&waiting, 2, wait)
            if ready == 0 { continue }
            if ready < 0 {
                if errno != EINTR { return .toolEnded }
                continue
            }
            if waiting[0].revents != 0 { readTool() }
            if waiting[1].revents != 0 { readTyping() }
        }
    }

    private func readTool() {
        var buffer = [UInt8](repeating: 0, count: 65_536)
        let count = read(fromTool.fileHandleForReading.fileDescriptor, &buffer, buffer.count)
        if count < 0, errno == EINTR { return }
        guard count > 0 else {
            toolEnded = true
            events.append(.toolEnded)
            return
        }
        for piece in splitter.append(Data(buffer[0..<count])) {
            switch piece {
            case .oversized:
                events.append(.junk("a line over 1 MB. The app stops a tool for one"))
            case .line(let line):
                if let message = try? LineFraming.message(from: line) {
                    events.append(.message(message))
                } else {
                    events.append(.junk("a line that is not a message: "
                            + String(decoding: line.prefix(80), as: UTF8.self)
                            + ". The app drops it, and stops a tool after twenty in a minute"))
                }
            }
        }
    }

    private func readTyping() {
        guard let typing else { return }
        var buffer = [UInt8](repeating: 0, count: 4096)
        let count = read(typing, &buffer, buffer.count)
        if count < 0, errno == EINTR { return }
        guard count > 0 else {
            typingEnded = true
            return
        }
        typed.append(contentsOf: buffer[0..<count])
        while let lineBreak = typed.firstIndex(of: 0x0A) {
            let text = String(decoding: typed[typed.startIndex..<lineBreak], as: UTF8.self)
            typed = Data(typed[typed.index(after: lineBreak)...])
            lines.append(text.trimmingCharacters(in: .whitespaces))
        }
    }

    // MARK: - The app's side

    /// Says hello, and reads the answer. False when the tool is not one the
    /// app would go on with.
    private func greet() -> Bool {
        lastID += 1
        // As the newest app says it: with everything it has beyond the first
        // release of the protocol version. The conformance script's "an
        // older app" step is where a tool meets an app that has none.
        let hello = InitializeParams(protocolVersions: ProtocolVersion.supported,
                                     language: Locale.preferredLanguages.first ?? "en",
                                     dataFolder: dataFolder.path,
                                     features: ProtocolFeature.allCases.map(\.rawValue))
        guard let params = try? JSONValue(encoding: hello),
              send(.request(id: .number(lastID), method: ToolMethod.initialize.rawValue, params: params))
        else { return false }
        let seconds = options.firstAnswerSeconds
        switch next(before: Self.now + seconds) {
        case .message(.result(.number(lastID), let value)):
            guard let answer = try? value.decode(InitializeResult.self) else {
                notOK("an answer to initialize that does not say a protocol version and the tool's own")
                return false
            }
            guard ProtocolVersion.supported.contains(answer.protocolVersion) else {
                notOK("the tool picked protocol \(answer.protocolVersion), which the app did not offer. "
                    + "The app stops such a tool")
                return false
            }
            line("hello", "protocol \(answer.protocolVersion), tool version \(answer.toolVersion)")
            return true
        case .late:
            notOK("no answer to initialize within \(Self.seconds(seconds))")
        case .toolEnded:
            notOK("the tool exited before it answered initialize")
        case .junk(let what):
            notOK(what)
        case .message, .typed, .typingEnded:
            notOK("something other than the answer to initialize came first. Nothing may be sent before it")
        }
        return false
    }

    /// Runs one command and plays the app until it is answered.
    private func runCommand(_ command: String) {
        guard (manifest.contributes?.commands ?? []).contains(where: { $0.id == command }) else {
            return notOK("the manifest has no command `\(command)`")
        }
        if let runnable, !runnable.contains(command) {
            line("note", "the tool said `\(command)` cannot run now. The app would grey it out; run here anyway")
        }
        lastID += 1
        let id = RPCID.number(lastID)
        guard let params = try? JSONValue(encoding: CommandRunParams(command: command)),
              send(.request(id: id, method: ToolMethod.commandRun.rawValue, params: params)) else { return }
        let deadline = Self.now + options.answerSeconds
        while true {
            switch next(before: deadline) {
            case .message(.result(id, _)):
                return line("ran", command)
            case .message(.failure(id, let error)):
                return line("refused", "\(command): \(error.message) (\(error.code))")
            case .late:
                return notOK("no answer to `\(command)` within \(Self.seconds(options.answerSeconds)). The app "
                    + "fails the command, and stops a tool after three in a row")
            case .toolEnded:
                return notOK("the tool exited while `\(command)` ran, with status \(exitStatus()). The app "
                    + "treats that as a crash")
            case .typed, .typingEnded:
                continue
            case let other:
                heard(other)
            }
        }
    }

    /// Anything the tool sends that is not the answer being waited for.
    private func heard(_ event: Event) {
        switch event {
        case .junk(let what):
            notOK(what)
        case .message(.request(let id, let method, let params)):
            let (answer, said) = desk.serve(method, params)
            line("asked", "\(method): \(said)")
            switch answer {
            case .success(let value): _ = send(.result(id: id, value: value))
            case .failure(let error): _ = send(.failure(id: id, error: error))
            }
        case .message(.notice(let method, let params)):
            switch ToolMethod(rawValue: method) {
            case .commandsState?:
                guard let state = try? params?.decode(CommandsStateParams.self) else {
                    return notOK("commands/state with params that are not its own")
                }
                runnable = Set(state.runnable)
                line("state", state.runnable.isEmpty ? "no command can run now"
                    : "can run now: " + state.runnable.joined(separator: ", "))
            case .log?:
                guard let entry = try? params?.decode(LogParams.self) else {
                    return notOK("log with params that are not its own")
                }
                line("log", entry.message)
            case .uiRender?:
                guard let page = try? params?.decode(UIRenderParams.self) else {
                    return notOK("ui/render with params that are not its own")
                }
                line("page", "for the panel \(page.panel), \(page.tree.blocks.count) blocks, which the app would draw")
            default:
                line("notice", "\(method). The app ignores a notice it does not know")
            }
        case .message(.result), .message(.failure):
            notOK("an answer to a request that was not waiting")
        case .toolEnded, .typed, .typingEnded, .late:
            break
        }
    }

    /// The person types commands until they type `quit`, their input ends,
    /// or the tool exits.
    private func converse() {
        let commands = (manifest.contributes?.commands ?? []).map(\.id)
        say("Type a command's id and Return to run it: " + (commands.isEmpty ? "(none)" : commands.joined(separator: ", "))
            + ". `quit` ends.")
        while true {
            switch next(before: nil, listening: true) {
            case .typed("quit"), .typed("exit"), .typingEnded:
                return
            case .typed(""):
                continue
            case .typed(let command):
                runCommand(command)
                if toolEnded { return }
            case .toolEnded:
                return notOK("the tool exited before it was told to, with status \(exitStatus()). The app "
                    + "treats that as a crash")
            case let other:
                heard(other)
            }
        }
    }

    /// The goodbye: `shutdown`, the end of the tool's input, a wait, a
    /// request to end, a shorter wait, and then a kill.
    private func stop() {
        if !toolEnded {
            _ = send(.notice(method: ToolMethod.shutdown.rawValue, params: nil))
        }
        try? toTool.fileHandleForWriting.close()
        if gone(within: options.exitSeconds) {
            let status = exitStatus()
            return status == "0" ? line("stopped", "exited with 0") : notOK("the tool exited with \(status)")
        }
        notOK("still running \(Self.seconds(options.exitSeconds)) after shutdown. The app then asks it to end, "
            + "and kills it a second later")
        family?.signal(SIGTERM)
        if !gone(within: options.endSeconds) { family?.signal(SIGKILL) }
    }

    /// Reads what the tool still writes until its program has exited, for
    /// `seconds` at most. True when it exited.
    private func gone(within seconds: TimeInterval) -> Bool {
        let deadline = Self.now + seconds
        while process.isRunning, Self.now < deadline {
            switch next(before: min(deadline, Self.now + 0.02)) {
            case .late, .typed, .typingEnded: continue
            case .toolEnded: usleep(2000)
            case let other: heard(other)
            }
        }
        return !process.isRunning
    }

    private func exitStatus() -> String {
        // The program has closed its output; give it a moment to be gone.
        let deadline = Self.now + 1
        while process.isRunning, Self.now < deadline { usleep(2000) }
        guard !process.isRunning else { return "none yet" }
        return process.terminationReason == .exit ? "\(process.terminationStatus)"
            : "signal \(process.terminationStatus)"
    }

    private static func seconds(_ seconds: TimeInterval) -> String {
        seconds == seconds.rounded() ? "\(Int(seconds)) second\(seconds == 1 ? "" : "s")" : "\(seconds) seconds"
    }
}
