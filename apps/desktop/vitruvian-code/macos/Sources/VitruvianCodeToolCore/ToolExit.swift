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
import VitruvianCodeCore

/// How the program ends once the app says `shutdown`.
///
/// The protocol gives a tool two seconds from `shutdown` to exit
/// (packages/vitruvian-sdk/docs/writing-a-tool.md); the app then asks it to
/// end, and kills it a second later. Two things used to spend that time on a
/// loaded machine:
///
/// - The program ended from the main thread, after the engine stopped the
///   chat's programs. A main thread busy with the chat window waited as long
///   as it was busy, and the engine was given five seconds.
/// - It ended with `exit`, which runs the atexit handlers first. CoreAnalytics,
///   which AppKit loads, registers one that waits for analyticsd over XPC
///   (`sendExitBarrierWithTimeoutSync`): about 300 ms under load, measured,
///   where an idle machine takes 5.
///
/// So the stop gets a budget, the wait for the main thread a deadline, and
/// the process ends with `_exit`. Nothing is lost by skipping the handlers:
/// the kit writes to the app with `write(2)`, which has no buffer to flush.
/// A stop cut short by the deadline would leave the chat's programs running
/// (agy, the Claude helper and its `claude`, what they started), so those
/// still in `ChildProcesses` are killed, groups and all, before the end.
public enum ToolExit {
    /// From the end of the kit's loop to the end of the process, whatever
    /// the main thread is doing: well inside the protocol's two seconds.
    public static let deadline: TimeInterval = 1.5

    /// What the engine gets to stop the chat's programs, inside `deadline`.
    public static let stopBudget: TimeInterval = 1.0

    /// Ends the process now with `status`, without the atexit handlers.
    public static func endProcess(_ status: Int32) -> Never {
        _exit(status)
    }

    /// Runs `stop` on the main actor and calls `end` once it has finished,
    /// or once `deadline` has passed, whichever is first. At the deadline,
    /// the programs still in `children` are killed first, from this thread.
    /// The program passes `ChildProcesses.shared`; a test passes its own,
    /// since killing the shared one kills every child of the test process.
    /// Called on the kit's thread when its loop returns; it blocks that
    /// thread, never the main one. It returns only if `end` does, as in the
    /// tests.
    public static func leave(
        status: Int32,
        deadline: TimeInterval = deadline,
        children: ChildProcesses,
        stop: @escaping @Sendable @MainActor () async -> Void,
        end: @Sendable (Int32) -> Void
    ) {
        ToolTrace.mark("loop returned")
        ToolTrace.heartbeat("leaving")
        let stopped = DispatchSemaphore(value: 0)
        Task { @MainActor in
            ToolTrace.mark("stop began on the main thread")
            await stop()
            ToolTrace.mark("stop finished")
            stopped.signal()
        }
        if stopped.wait(timeout: .now() + max(0, deadline)) == .timedOut {
            let killed = children.killAll()
            ToolTrace.mark("deadline hit; killed \(killed)")
        }
        ToolTrace.mark("ending with \(status)")
        end(status)
    }
}
