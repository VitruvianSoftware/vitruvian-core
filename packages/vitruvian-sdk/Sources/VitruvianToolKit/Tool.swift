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

/// A command that will not run, and a few English words for the log saying
/// why. Throw it from a command's handler; the app is answered with -32010.
public struct CommandRefused: Error, Equatable, Sendable {
    public let message: String

    public init(_ message: String) {
        self.message = message
    }
}

/// A call to the app that got no answer.
public enum AppUnreachable: Error, Equatable, Sendable {
    /// The app said goodbye or closed the link, or has not said hello yet.
    case linkClosed
    /// No answer came within `Tool.answerSeconds`.
    case noAnswer(seconds: TimeInterval)
}

/// A tool that runs as its own program: its commands, and the loop that
/// reads what the app sends and answers it.
///
///     let tool = Tool(version: "0.1.0")
///     tool.command("hello") { app in
///         try app.showMessage("Hello")
///     }
///     tool.run()
///
/// It works on one thread, the one that calls `run()`. A handler runs on
/// that thread, and a call to the app made inside a handler reads the link
/// until the answer has come. Nothing here starts a thread or a task, so
/// there is nothing for a handler to wait on that could be waiting on it.
/// What the app sends while a handler waits is kept and handled after the
/// handler returns. Do not use a `Tool` or an `App` from another thread.
public final class Tool {
    public typealias Handler = (App) throws -> Void

    /// The tool's own version, as its manifest gives it.
    public let version: String
    /// How long a call to the app waits for its answer, in seconds.
    public var answerSeconds: TimeInterval = 10
    /// Called once, after the app has said hello and been answered.
    public var onStart: ((App) -> Void)?
    /// Called when the person changed a preference: each one's id and value.
    public var onPreferencesChanged: ((App, [String: JSONValue]) -> Void)?
    /// Called when the person changed the app's language.
    public var onLanguageChanged: ((App) -> Void)?

    /// The language the app is in, as a tag such as `en-US`.
    public private(set) var language = "en"
    /// The folder the tool may keep its own files in. It is also the folder
    /// the app starts the tool in.
    public private(set) var dataFolder = URL(fileURLWithPath: FileManager.default.currentDirectoryPath,
                                             isDirectory: true)

    private var handlers: [String: Handler] = [:]
    /// The tool's panels, by id, as `panel(_:onOpen:onEvent:)` made them.
    var panels: [String: Panel] = [:]
    /// What `every(seconds:_:)` set up: each with when it next runs, by the
    /// clock `Wire.now` reads. Nil until the app has said hello.
    private var timers: [(seconds: TimeInterval, handler: Handler, nextAt: TimeInterval?)] = []
    /// Held so that the two ends stay open for as long as the tool lives:
    /// a file handle closes its descriptor when it is let go.
    private let ends: [FileHandle]
    private var wire: Wire
    private var lastID = 0
    /// What came while a handler waited for an answer, in the order it came.
    private var kept: [RPCMessage] = []
    private var greeted = false
    private var stopping = false

    /// `input` and `output` are the link. Leave them alone outside a test.
    public init(version: String, input: FileHandle = .standardInput, output: FileHandle = .standardOutput) {
        self.version = version
        ends = [input, output]
        wire = Wire(input: input.fileDescriptor, output: output.fileDescriptor)
    }

    /// Says what a command does. `id` is the one the manifest gives it.
    public func command(_ id: String, _ handler: @escaping Handler) {
        handlers[id] = handler
    }

    /// Runs `handler` every `seconds`, on the thread that runs the tool,
    /// between messages: never while a command or a panel's handler is
    /// running or waiting for the app's answer, and not before the app has
    /// said hello. A handler that runs late is not run twice to catch up.
    /// An error it throws is written to the tool's log and the timer goes
    /// on. For a tool that polls, as one that watches a service does; ask
    /// for a few seconds at least, so the tool is not the app's busiest
    /// part.
    public func every(seconds: TimeInterval, _ handler: @escaping Handler) {
        timers.append((max(0, seconds), handler, nil))
    }

    /// Reads and answers until the app says goodbye, then exits with 0.
    public func run() -> Never {
        exit(serve())
    }

    /// Reads and answers until the app says goodbye or the link ends.
    /// Returns the status to exit with, which is 0.
    public func serve() -> Int32 {
        // A link that has gone is seen as a failed write, not as a signal.
        signal(SIGPIPE, SIG_IGN)
        while !stopping {
            if !kept.isEmpty {
                handle(kept.removeFirst())
                continue
            }
            switch wire.next(before: nextTimer) {
            case .message(let message): handle(message)
            case .late: runTimers()
            case .ended: stopping = true
            }
        }
        return 0
    }

    /// When the first timer is due, or nil with none set up or none started.
    private var nextTimer: TimeInterval? {
        timers.compactMap(\.nextAt).min()
    }

    /// Runs each timer that is due, once, and sets its next time from now,
    /// not from when it was due.
    private func runTimers() {
        for index in timers.indices {
            guard let due = timers[index].nextAt, due <= Wire.now else { continue }
            timers[index].nextAt = Wire.now + timers[index].seconds
            do {
                try timers[index].handler(App(tool: self))
            } catch {
                App(tool: self).log("a timer's handler failed: \(error)")
            }
            if stopping { return }
        }
    }

    private func handle(_ message: RPCMessage) {
        switch message {
        case .request(let id, let method, let params):
            switch ToolMethod(rawValue: method) {
            case .initialize?: greet(id, params)
            case .commandRun?: runCommand(id, params)
            case .uiOpen?: openPanel(id, params)
            case .uiEvent?: panelEvent(id, params)
            default: refuse(id, RPCErrorCode.methodNotFound, "method not found")
            }
        case .notice(let method, let params):
            switch ToolMethod(rawValue: method) {
            case .shutdown?:
                stopping = true
            case .preferencesChanged?:
                if let changed = try? params?.decode(PreferencesChangedParams.self) {
                    onPreferencesChanged?(App(tool: self), changed.values)
                }
            case .languageChanged?:
                if let changed = try? params?.decode(LanguageChangedParams.self) {
                    language = changed.language
                    onLanguageChanged?(App(tool: self))
                }
            case .uiClose?:
                if let closed = try? params?.decode(UICloseParams.self) { panels[closed.panel]?.isOpen = false }
            default:
                break
            }
        case .result, .failure:
            // An answer nobody waits for: it came after its call gave up.
            break
        }
    }

    private func greet(_ id: RPCID, _ params: JSONValue?) {
        guard let hello = try? params?.decode(InitializeParams.self) else {
            return refuse(id, RPCErrorCode.invalidParams, "invalid params")
        }
        // The newest version both speak. Version 2 only adds to version 1,
        // so a tool of either is answered by an app of either.
        guard let picked = ProtocolVersion.supported.last(where: hello.protocolVersions.contains) else {
            let spoken = ProtocolVersion.supported.joined(separator: " and ")
            return refuse(id, RPCErrorCode.invalidParams, "this tool speaks protocols \(spoken) only")
        }
        language = hello.language
        dataFolder = URL(fileURLWithPath: hello.dataFolder, isDirectory: true)
        greeted = true
        answer(id, InitializeResult(protocolVersion: picked, toolVersion: version))
        // The timers count from the hello, so a handler may call the app.
        for index in timers.indices { timers[index].nextAt = Wire.now + timers[index].seconds }
        onStart?(App(tool: self))
    }

    func runCommand(_ id: RPCID, _ params: JSONValue?) {
        guard greeted else { return refuse(id, RPCErrorCode.invalidRequest, "initialize comes first") }
        guard let asked = try? params?.decode(CommandRunParams.self) else {
            return refuse(id, RPCErrorCode.invalidParams, "invalid params")
        }
        guard let handler = handlers[asked.command] else {
            return refuse(id, RPCErrorCode.invalidParams, "no such command")
        }
        do {
            try handler(App(tool: self))
            answer(id, EmptyObject())
        } catch let refused as CommandRefused {
            refuse(id, RefusalCode.commandRefused.rawValue, refused.message)
        } catch let refusal as RPCErrorObject {
            // The app refused something the command needed. Its reason goes
            // with ours, for the log.
            refuse(id, RefusalCode.commandRefused.rawValue, RefusalCode.commandRefused.message,
                   data: try? JSONValue(encoding: refusal))
        } catch {
            refuse(id, RefusalCode.commandRefused.rawValue, "\(error)")
        }
    }

    func answer<Value: Encodable>(_ id: RPCID, _ value: Value) {
        guard let result = try? JSONValue(encoding: value) else {
            return refuse(id, RPCErrorCode.internalError, "the answer could not be written")
        }
        wire.send(.result(id: id, value: result))
    }

    func refuse(_ id: RPCID, _ code: Int, _ message: String, data: JSONValue? = nil) {
        wire.send(.failure(id: id, error: RPCErrorObject(code: code, message: message, data: data)))
    }

    // MARK: - What `App` is made of

    /// Sends a request and reads the link until its answer has come.
    func call(_ method: ToolMethod, _ params: JSONValue) throws -> JSONValue {
        guard greeted, !stopping else { throw AppUnreachable.linkClosed }
        lastID += 1
        let id = RPCID.number(lastID)
        guard wire.send(.request(id: id, method: method.rawValue, params: params)) else {
            stopping = true
            throw AppUnreachable.linkClosed
        }
        let deadline = Wire.now + answerSeconds
        while true {
            switch wire.next(before: deadline) {
            case .ended:
                stopping = true
                throw AppUnreachable.linkClosed
            case .late:
                throw AppUnreachable.noAnswer(seconds: answerSeconds)
            case .message(.result(let answered, let value)) where answered == id:
                return value
            case .message(.failure(let answered, let error)) where answered == id:
                throw error
            case .message(.notice(let name, _)) where name == ToolMethod.shutdown.rawValue:
                stopping = true
                throw AppUnreachable.linkClosed
            case .message(let other):
                kept.append(other)
            }
        }
    }

    /// Sends a notice. False when it could not be sent: the tool has not
    /// been greeted, or the link has closed.
    @discardableResult
    func note(_ method: ToolMethod, _ params: JSONValue) -> Bool {
        guard greeted, !stopping else { return false }
        return wire.send(.notice(method: method.rawValue, params: params))
    }
}

/// The app, as a handler sees it. Each method is one request of the
/// protocol. Any of them can be refused: the failure the app answered with
/// is thrown, as an `RPCErrorObject`, and `RefusalCode(error)` says which
/// refusal it is. A handler that lets it through has its command answered
/// as refused.
///
/// A tool may do any of this itself: it is a separate program with every
/// permission the app has. These are for what is better done through the
/// app.
public struct App {
    let tool: Tool

    public var language: String { tool.language }
    public var dataFolder: URL { tool.dataFolder }

    /// Sends any request of the protocol and reads its answer.
    @discardableResult
    public func send<Request: AppRequest>(_ request: Request) throws -> Request.Answer {
        try tool.call(Request.method, try JSONValue(encoding: request)).decode(Request.Answer.self)
    }

    /// The app's short on-screen message. `icon` is an SF Symbol name.
    /// Needs `notify` in the manifest's `uses`.
    public func showMessage(_ message: String, icon: String = "puzzlepiece.extension") throws {
        try send(NotifyHUDParams(icon: icon, message: message))
    }

    /// The alert sound. Needs `notify`.
    public func beep() throws {
        try send(NotifyBeepParams())
    }

    /// Opens a link. False when nothing could open it. Needs `open`.
    @discardableResult
    public func open(_ url: String) throws -> Bool {
        try send(OpenURLParams(url: url)).opened
    }

    /// The clipboard's text; nil when it holds none. Needs `clipboard.read`.
    public func clipboardText() throws -> String? {
        try send(ClipboardReadTextParams()).text
    }

    /// Replaces the clipboard with `text`. Needs `clipboard.write`.
    @discardableResult
    public func setClipboardText(_ text: String) throws -> Bool {
        try send(ClipboardWriteTextParams(text: text)).written
    }

    /// Pastes `text` into the app in front. Needs `keystrokes`.
    public func paste(_ text: String) throws {
        try send(KeystrokesPasteParams(text: text))
    }

    /// Presses the menu item with one of these key equivalents in the app in
    /// front. False when it has none. Needs `keystrokes`.
    @discardableResult
    public func pressMenuItem(_ equivalents: [KeyEquivalent]) throws -> Bool {
        try send(KeystrokesPressMenuItemParams(equivalents: equivalents)).pressed
    }

    /// Ends a process, with the app's checks. Needs `processes`.
    public func endProcess(pid: Int, name: String, force: Bool = false) throws {
        try send(ProcessesTerminateParams(pid: pid, name: name, force: force))
    }

    /// One of the preferences the manifest declares. Needs `storage`.
    public func value(_ key: String) throws -> JSONValue {
        try send(StorageGetParams(key: key)).value
    }

    /// Saves one of the preferences the manifest declares. Needs `storage`.
    public func setValue(_ value: JSONValue, for key: String) throws {
        try send(StorageSetParams(key: key, value: value))
    }

    /// Says which commands can run now. Until the first time, all of them
    /// can. It is a notice: the app does not answer it.
    public func setRunnable(_ commands: [String]) {
        guard let params = try? JSONValue(encoding: CommandsStateParams(runnable: commands)) else { return }
        tool.note(.commandsState, params)
    }

    /// A line for the tool's log in Settings. It is a notice.
    public func log(_ message: String) {
        guard let params = try? JSONValue(encoding: LogParams(message: message)) else { return }
        tool.note(.log, params)
    }
}
