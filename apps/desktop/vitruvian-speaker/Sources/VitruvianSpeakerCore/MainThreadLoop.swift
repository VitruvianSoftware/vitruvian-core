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

/// Keeps a headless program's main thread at work: it runs the main run
/// loop, and so the main queue and the main actor's jobs, on the main
/// thread itself, until something calls `exit`.
///
/// Not `dispatchMain()`. That ends the main thread (`pthread_exit`) and
/// leaves the main queue to a worker thread, where
/// `MainActor.assumeIsolated` can trap ("Incorrect actor executor
/// assumption"), as HomeSpeaker extension 1.19.0 did on every start once
/// its chat monitor started, and where nothing services the main thread's
/// run loop (distributed notifications, timers on it).
public enum MainThreadLoop {
    /// Runs the main run loop forever. Call it on the main thread, last.
    public static func run() -> Never {
        precondition(Thread.isMainThread, "MainThreadLoop.run() must be called on the main thread")
        // A run loop with no source returns at once; a port that nothing
        // sends to keeps it waiting.
        RunLoop.main.add(NSMachPort(), forMode: .default)
        while true {
            _ = RunLoop.main.run(mode: .default, before: .distantFuture)
        }
    }
}
