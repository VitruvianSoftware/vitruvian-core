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

/// The result of running one command. stdout is kept only for the caller to
/// discard or show deliberately: `token --rotate` prints the new token there,
/// and nothing in this app may display it.
public struct RunResult: Sendable {
    public var exitCode: Int32
    public var stdout: String
    public var stderr: String

    public var succeeded: Bool { exitCode == 0 }

    /// The first non-empty line of stderr, for an error dialog.
    public var firstErrorLine: String? {
        stderr.split(separator: "\n").map { $0.trimmingCharacters(in: .whitespaces) }.first { !$0.isEmpty }
    }
}

public enum Runner {
    /// Run a program directly (no shell), off the main thread, bounded.
    public static func run(_ executable: URL, _ arguments: [String], timeout: TimeInterval = 15) async -> RunResult {
        await Task.detached {
            let p = Process()
            p.executableURL = executable
            p.arguments = arguments
            let out = Pipe(), err = Pipe()
            p.standardOutput = out
            p.standardError = err
            do {
                try p.run()
            } catch {
                return RunResult(exitCode: -1, stdout: "", stderr: error.localizedDescription)
            }
            let deadline = Date().addingTimeInterval(timeout)
            while p.isRunning, Date() < deadline {
                try? await Task.sleep(nanoseconds: 50_000_000)
            }
            if p.isRunning {
                p.terminate()
                return RunResult(exitCode: -1, stdout: "", stderr: "timed out after \(Int(timeout))s")
            }
            let o = String(data: out.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
            let e = String(data: err.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
            return RunResult(exitCode: p.terminationStatus, stdout: o, stderr: e)
        }.value
    }
}
