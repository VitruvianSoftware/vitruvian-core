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
import Testing
@testable import VitruvianSpeakerCore

// A second extension process that started while the old one was still
// exiting tries the live lock again on each role tick (#3357), and the
// app's choice window opens when the app starts asking mid-run (#3356).

private func lockURL() throws -> URL {
    let dir = FileManager.default.temporaryDirectory
        .appendingPathComponent("vitruvian-speaker-keeper-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    return dir.appendingPathComponent("running.lock")
}

/// A `flock` belongs to an open file description, so another holder in
/// this process refuses the keeper just as another process would.
@Suite struct LiveLockKeeperTests {
    @Test func aRefusedProcessTakesTheLockOnceTheOldOneHasGone() throws {
        let url = try lockURL()
        let old = try LiveLock.hold(at: url)
        var taken = 0
        let keeper = LiveLockKeeper(
            url: url, first: { try? LiveLock.hold(at: url, retries: 0, wait: 0, onBusy: { _ in }) },
            onTaken: { taken += 1 })
        #expect(taken == 0, "refused at start")
        #expect(!keeper.holds(), "still refused while the old process holds it")
        #expect(taken == 0)

        old.release()
        #expect(keeper.holds(), "taken on the next tick once the old one has gone")
        #expect(taken == 1, "what only the live process does starts then")
        #expect(LiveLock.isHeld(at: url))
        #expect(keeper.holds())
        #expect(taken == 1, "and starts once")
    }

    @Test func aProcessThatTakesItAtStartKeepsIt() throws {
        let url = try lockURL()
        var taken = 0
        let keeper = LiveLockKeeper(url: url, onTaken: { taken += 1 })
        #expect(taken == 1, "taken at start")
        #expect(keeper.holds())
        #expect(taken == 1)
        #expect(throws: (any Error).self, "nobody else takes it meanwhile") {
            try LiveLock.hold(at: url, retries: 0, wait: 0, onBusy: { _ in })
        }
    }
}

@Suite struct ChoiceWindowTests {
    private let asking = AppStartup.plan(role: .activeAsking, inTrash: false)
    private let active = AppStartup.plan(role: .active, inTrash: false)
    private let quiet = AppStartup.plan(role: .quiet(other: .extension), inTrash: false)
    private let trash = AppStartup.plan(role: .active, inTrash: true)

    @Test func startingToAskMidRunOpensTheWindow() {
        #expect(asking.opensWindow(after: active), "the extension appeared while the app ran")
        #expect(asking.opensWindow(after: trash))
    }

    @Test func goingQuietOpensTheWindow() {
        #expect(quiet.opensWindow(after: active))
        #expect(quiet.opensWindow(after: asking))
    }

    @Test func nothingElseOpensIt() {
        #expect(!active.opensWindow(after: asking), "a choice made: nothing more to ask")
        #expect(!active.opensWindow(after: quiet))
        #expect(!trash.opensWindow(after: active))
    }
}
