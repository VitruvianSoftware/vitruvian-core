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
import XCTest

import NexusAgentToolCore

/// The app fails a request not answered within two seconds. These hold the
/// main thread busy, as a slow first window or a start-up still running
/// does, and time how long the kit's thread waits for each answer.
final class CommandAnswerTests: XCTestCase {
    /// What a background call to `handle` saw.
    private final class Outcome: @unchecked Sendable {
        let lock = NSLock()
        var answeredAfter: TimeInterval?
        var ran: [String] = []
        func record(_ seconds: TimeInterval) { lock.lock(); answeredAfter = seconds; lock.unlock() }
        func ran(_ command: String) { lock.lock(); ran.append(command); lock.unlock() }
        var snapshot: (TimeInterval?, [String]) { lock.lock(); defer { lock.unlock() }; return (answeredAfter, ran) }
    }

    /// Calls `handle` from another thread while the main thread is busy for
    /// `busy` seconds, then lets the main thread run what was left for it.
    private func answer(_ command: String, mainBusyFor busy: TimeInterval) -> Outcome {
        XCTAssertTrue(Thread.isMainThread, "the test holds the main thread itself")
        let outcome = Outcome()
        let started = Date()
        Thread.detachNewThread {
            try? CommandAnswer.handle(command) { outcome.ran($0) }
            outcome.record(Date().timeIntervalSince(started))
        }
        Thread.sleep(forTimeInterval: busy)
        RunLoop.main.run(until: Date().addingTimeInterval(0.3))
        return outcome
    }

    func testAWindowCommandIsAnsweredWhileTheMainThreadIsBusy() {
        for command in [NexusAgentTool.Command.quickPrompt, NexusAgentTool.Command.newChat,
                        NexusAgentTool.Command.quickJump] {
            let (after, ran) = answer(command, mainBusyFor: 1.5).snapshot
            let seconds = try? XCTUnwrap(after, "\(command) was never answered")
            XCTAssertLessThan(seconds ?? .infinity, 0.5,
                              "\(command) waited for the busy main thread before answering")
            XCTAssertEqual(ran, [command], "\(command) still runs, once the main thread is free")
        }
    }

    func testACommandThatCanBeRefusedRunsBeforeItIsAnswered() {
        let (after, ran) = answer(NexusAgentTool.Command.startBot, mainBusyFor: 0.8).snapshot
        XCTAssertGreaterThanOrEqual(after ?? 0, 0.8,
                                    "startBot must run, and maybe refuse, before the app is answered")
        XCTAssertEqual(ran, [NexusAgentTool.Command.startBot])
    }

    func testARefusalReachesTheApp() {
        struct Refused: Error {}
        XCTAssertThrowsError(try {
            let done = DispatchSemaphore(value: 0)
            var thrown: Error?
            Thread.detachNewThread {
                do { try CommandAnswer.handle(NexusAgentTool.Command.stopBot) { _ in throw Refused() } } catch {
                    thrown = error
                }
                done.signal()
            }
            while done.wait(timeout: .now()) == .timedOut { RunLoop.main.run(until: Date().addingTimeInterval(0.01)) }
            if let thrown { throw thrown }
        }())
    }

    func testEveryWindowCommandIsOneTheToolHas() {
        let known = Set(NexusAgentTool.Command.all + NexusAgentTool.Command.ade)
        XCTAssertTrue(CommandAnswer.answeredFirst.isSubset(of: known))
        XCTAssertFalse(CommandAnswer.answeredFirst.contains(NexusAgentTool.Command.startBot))
        XCTAssertFalse(CommandAnswer.answeredFirst.contains(NexusAgentTool.Command.stopBot))
    }
}
