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

/// Lines on standard error that say when the program reached each step of
/// its life, for a conformance run that fails on time. Written only when
/// `VITRUVIAN_TOOL_TRACE=1`, which the conformance test sets; the app never
/// sets it. Each line carries the wall clock, which the test's own lines
/// share, and the process's CPU time, which says whether it was running or
/// waiting for the CPU.
public enum ToolTrace {
    public static let enabled = ProcessInfo.processInfo.environment["VITRUVIAN_TOOL_TRACE"] == "1"

    /// Writes `step` with `write(2)`: no buffer, safe from any thread, and
    /// out before an `_exit`.
    public static func mark(_ step: String) {
        guard enabled else { return }
        write(line(step))
    }

    /// The line `mark` writes, for the tests.
    public static func line(_ step: String) -> String {
        var usage = rusage()
        getrusage(RUSAGE_SELF, &usage)
        let cpu = Double(usage.ru_utime.tv_sec + usage.ru_stime.tv_sec) * 1000
            + Double(usage.ru_utime.tv_usec + usage.ru_stime.tv_usec) / 1000
        let wall = Date().timeIntervalSince1970
        return "tool-trace wall=\(String(format: "%.3f", wall)) cpu_ms=\(Int(cpu)) pid=\(getpid()) \(step)\n"
    }

    private static func write(_ text: String) {
        var bytes = Array(text.utf8)
        _ = bytes.withUnsafeMutableBytes { Darwin.write(STDERR_FILENO, $0.baseAddress, $0.count) }
    }

    /// While tracing, marks `step` every `interval` from a thread of its own
    /// until the process ends: a gap in these lines is time the process did
    /// not run.
    public static func heartbeat(_ step: String, every interval: TimeInterval = 0.1) {
        guard enabled else { return }
        Thread.detachNewThread {
            var beat = 0
            while true {
                usleep(useconds_t(interval * 1_000_000))
                beat += 1
                mark("\(step) \(beat)")
            }
        }
    }
}
