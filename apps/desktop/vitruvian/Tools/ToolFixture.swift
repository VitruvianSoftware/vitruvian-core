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
//   hang      never answers
//   stubborn  never answers, stops reading, and ignores being asked to end
//   flood     writes log lines for as long as it lives
//   crash     exits with status 3
//
// It is a script: top-level code that reads lines until its input ends.
// Nothing here starts a task. A `Task` in top-level code inherits the main
// actor, and a program that then waits for it on the main thread never ends.

import Foundation

// A test run that died must not leave this behind.
alarm(120)

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

let commands = ["hello", "quick", "where", "mutter", "hang", "stubborn", "flood", "crash"]
var greeting: [String: Any] = [:]
/// The `command/run` that waits for the app to answer `notify/hud`.
var waitingRun: Any?

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
            break
        case "stubborn"?:
            signal(SIGTERM, SIG_IGN)
            log("stubborn")
            while true { sleep(1) }
        case "flood"?:
            while true { log("flood") }
        case "crash"?:
            exit(3)
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
