// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 VitruvianSoftware

// A tool for the app's own tests to start as a real child process. It
// speaks the tool protocol with nothing but Foundation, so it checks what
// the app writes with code that shares none of the app's. Each of its
// commands behaves one way a tool can: well, or badly.
//
//   hello     asks the app to show a message, then answers, then logs
//             "hello answered", so a test can tell the answer has arrived
//   quick     answers at once
//   where     logs the folder it runs in and what the greeting told it
//   mutter    writes to standard error, then answers
//   hang      never answers, and stays when its input ends: a hung tool
//             reads nothing, so only a signal ends it
//   stubborn  never answers, stops reading, and ignores being asked to end
//   scribble  as stubborn, and for as long as it lives it makes its data
//             folder again and writes a file into it
//   flood     writes log lines for as long as it lives
//   crash     exits with status 3
//   helper    starts a program of its own, a helper, and logs its process
//             id and the file it writes; then answers
//   helper-deaf   the same, with a helper that ignores being asked to end
//   helper-away   the same, with a helper that leaves the tool's process
//                 group for one of its own
//
// A helper is this same program, started with `--helper <file>`. It keeps
// none of the tool's pipes, and for as long as it lives it writes a count
// into its file every two milliseconds, each time as a whole new file. It
// is started with `posix_spawn`
// and no attribute, as a script's `&` or Python's `subprocess` starts one,
// so it is in the tool's process group. (Foundation's `Process` would give
// it a group of its own.)
//
// It is a script: top-level code that reads lines until its input ends.
// Nothing here starts a task. A `Task` in top-level code inherits the main
// actor, and a program that then waits for it on the main thread never ends.

import Foundation

// A test run that died must not leave this behind, nor a helper of it.
alarm(120)

if CommandLine.arguments.count >= 3, CommandLine.arguments[1] == "--helper" {
    let file = URL(fileURLWithPath: CommandLine.arguments[2])
    let how = Set(CommandLine.arguments.dropFirst(3))
    if how.contains("deaf") { signal(SIGTERM, SIG_IGN) }
    if how.contains("away") { setpgid(0, 0) }
    var count = 0
    while true {
        count += 1
        // Whole or not at all: whoever reads the file never finds it empty
        // between two counts.
        try? Data("\(count)".utf8).write(to: file, options: .atomic)
        usleep(2_000)
    }
}

/// Starts a helper that writes into `file`, in this program's own process
/// group, with none of its pipes. Gives back the helper's process id.
func startHelper(writing file: String, _ how: [String]) -> pid_t? {
    guard let program = Bundle.main.executablePath else { return nil }
    var actions: posix_spawn_file_actions_t?
    guard posix_spawn_file_actions_init(&actions) == 0 else { return nil }
    defer { posix_spawn_file_actions_destroy(&actions) }
    for descriptor in [STDIN_FILENO, STDOUT_FILENO, STDERR_FILENO] {
        posix_spawn_file_actions_addopen(&actions, descriptor, "/dev/null", O_RDWR, 0)
    }
    var arguments: [UnsafeMutablePointer<CChar>?] = ([program, "--helper", file] + how).map { strdup($0) }
    arguments.append(nil)
    var environment: [UnsafeMutablePointer<CChar>?] = ProcessInfo.processInfo.environment.map { strdup($0 + "=" + $1) }
    environment.append(nil)
    defer { (arguments + environment).forEach { free($0) } }
    var pid: pid_t = 0
    guard posix_spawn(&pid, program, &actions, nil, &arguments, &environment) == 0 else { return nil }
    return pid
}

func send(_ message: [String: Any]) {
    guard var line = try? JSONSerialization.data(withJSONObject: message, options: [.withoutEscapingSlashes])
    else { return }
    line.append(0x0A)
    FileHandle.standardOutput.write(line)
}

func answer(_ id: Any, _ result: [String: Any] = [:]) {
    send(["jsonrpc": "2.0", "id": id, "result": result])
}

func refuse(_ id: Any, _ code: Int, _ message: String, data: Any? = nil) {
    var error: [String: Any] = ["code": code, "message": message]
    if let data { error["data"] = data }
    send(["jsonrpc": "2.0", "id": id, "error": error])
}

func log(_ message: String) {
    send(["jsonrpc": "2.0", "method": "log", "params": ["message": message]])
}

let commands = ["hello", "quick", "where", "mutter", "hang", "stubborn", "scribble", "flood", "crash",
                "helper", "helper-deaf", "helper-away"]
var greeting: [String: Any] = [:]
/// The `command/run` that waits for the app to answer `notify/hud`.
var waitingRun: Any?
/// Set by `hang`: the tool no longer ends when its input does.
var hung = false

while let line = readLine() {
    guard let message = (try? JSONSerialization.jsonObject(with: Data(line.utf8))) as? [String: Any] else { continue }
    let params = message["params"] as? [String: Any] ?? [:]
    let id = message["id"]
    switch message["method"] as? String {
    case "initialize"?:
        guard let id else { continue }
        guard (params["protocolVersions"] as? [String])?.contains("1") == true else {
            refuse(id, -32602, "this tool speaks protocol 1 only")
            continue
        }
        greeting = params
        answer(id, ["protocolVersion": "1", "toolVersion": "fixture"])
        send(["jsonrpc": "2.0", "method": "commands/state", "params": ["runnable": commands]])
    case "command/run"?:
        guard let id else { continue }
        switch params["command"] as? String {
        case "hello"?:
            waitingRun = id
            send(["jsonrpc": "2.0", "id": "hud", "method": "notify/hud",
                  "params": ["icon": "hand.wave", "message": "Hello from the fixture"]])
        case "quick"?:
            answer(id)
        case "where"?:
            let folder = FileManager.default.currentDirectoryPath
            log("cwd=\(folder) data=\(greeting["dataFolder"] ?? "") language=\(greeting["language"] ?? "")")
            answer(id)
        case "mutter"?:
            FileHandle.standardError.write(Data("fixture: on standard error\n".utf8))
            answer(id)
        case "hang"?:
            hung = true
        case "stubborn"?:
            signal(SIGTERM, SIG_IGN)
            log("stubborn")
            while true { sleep(1) }
        case "scribble"?:
            signal(SIGTERM, SIG_IGN)
            let folder = URL(fileURLWithPath: greeting["dataFolder"] as? String ?? ".", isDirectory: true)
            var written = false
            while true {
                try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
                let wrote = (try? Data("scribble".utf8).write(to: folder.appendingPathComponent("scribbled"))) != nil
                if wrote, !written {
                    written = true
                    log("scribbling")
                }
                usleep(500)
            }
        case "flood"?:
            while true { log("flood") }
        case "crash"?:
            exit(3)
        case let command? where command.hasPrefix("helper"):
            let how = command.split(separator: "-").dropFirst().map(String.init)
            let folder = greeting["dataFolder"] as? String ?? FileManager.default.currentDirectoryPath
            let file = folder + "/" + command
            if let pid = startHelper(writing: file, how) {
                log("helper pid=\(pid) file=\(file)")
                answer(id)
            } else {
                refuse(id, -32010, "no helper could be started")
            }
        default:
            refuse(id, -32602, "no such command")
        }
    case "shutdown"?:
        exit(0)
    case nil:
        // The app's answer to `notify/hud`: the command it was part of ran,
        // or was refused for the app's reason.
        guard message["id"] as? String == "hud", let run = waitingRun else { continue }
        waitingRun = nil
        if let error = message["error"] {
            refuse(run, -32010, "command refused", data: error)
        } else {
            answer(run)
            log("hello answered")
        }
    default:
        if let id { refuse(id, -32601, "method not found") }
    }
}
// A hung tool does not notice its input end: only a signal, or the alarm,
// ends it. Otherwise closing its input could end it before the app's
// signal does, and a test could not tell which did.
while hung { sleep(1) }
