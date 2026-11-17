// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 VitruvianSoftware

import AppKit
import CoreGraphics
import VitruvianAtriumCore
import VitruvianAtriumServices

/// What the quick-switch latency work promises, checked on the shipped types:
/// a window-server snapshot that a current ID list can validate, the source
/// staging that is not repeated once confirmed, and the activation whose writes
/// to another app wait on a lane and are dropped once a newer activation has
/// overtaken them. Nothing here activates an app or posts input.
enum SwitcherLatencyTests {
    static func run(_ suite: TestSuite) {
        snapshotChecks(suite)
        stagingChecks(suite)
        retryChecks(suite)
        activationChecks(suite)
    }

    private static func info(_ id: CGWindowID, owner: pid_t, layer: Int = 0) -> [String: Any] {
        [kCGWindowNumber as String: NSNumber(value: id),
         kCGWindowOwnerPID as String: NSNumber(value: owner),
         kCGWindowLayer as String: NSNumber(value: layer)]
    }

    private static func snapshotChecks(_ suite: TestSuite) {
        let raw = [info(1, owner: 10), info(2, owner: 10), info(3, owner: 20), info(4, owner: 20, layer: 25)]
        let snapshot = SwitcherWindowServerSnapshot(windowInfo: raw, capturesActivationBaseline: true)
        suite.expect(snapshot.windowIDs == [1, 2, 3, 4]
                        && snapshot.normalLevelWindowIDs == [1, 2, 3]
                        && snapshot.normalLevelOwnerPIDs.sorted() == [10, 10, 20],
                     "the snapshot keeps every window and the normal-level ones apart")
        suite.expect(snapshot.activationWindowIDs(ownerPID: 10, targetWindowID: 1,
                                                  currentWindowIDs: [1, 2, 3, 4]) == [1, 2],
                     "an unchanged window set validates the owner's windows without another read")
        suite.expect(snapshot.activationWindowIDs(ownerPID: 10, targetWindowID: 1,
                                                  currentWindowIDs: [1, 3, 4]) == [1],
                     "a window that closed since is left out of the validated set")
        suite.expect(snapshot.activationWindowIDs(ownerPID: 10, targetWindowID: 1,
                                                  currentWindowIDs: [1, 2, 3, 4, 5]) == nil,
                     "a window that appeared since needs a fresh read")
        suite.expect(snapshot.activationWindowIDs(ownerPID: 10, targetWindowID: 3,
                                                  currentWindowIDs: [1, 2, 3, 4]) == nil,
                     "a target the owner never held needs a fresh read")
        suite.expect(snapshot.activationWindowIDs(ownerPID: 10, targetWindowID: 2,
                                                  currentWindowIDs: [1, 3, 4]) == nil,
                     "a target that is gone needs a fresh read")
        let withoutBaseline = SwitcherWindowServerSnapshot(windowInfo: raw, capturesActivationBaseline: false)
        suite.expect(withoutBaseline.activationWindowIDs(ownerPID: 10, targetWindowID: 1,
                                                         currentWindowIDs: [1, 2, 3, 4]) == nil,
                     "a snapshot taken without the owner map never validates")
        let incomplete = SwitcherWindowServerSnapshot(
            windowInfo: raw + [[kCGWindowNumber as String: NSNumber(value: 9)]],
            capturesActivationBaseline: true)
        suite.expect(incomplete.activationWindowIDs(ownerPID: 10, targetWindowID: 1,
                                                    currentWindowIDs: [1, 2, 3, 4, 9]) == nil,
                     "a window without an owner makes the baseline incomplete")
    }

    private static func stagingChecks(_ suite: TestSuite) {
        let state = SwitcherSourceStagingState(generation: 5)
        suite.expect(state.lastOutcome == .notApplicable, "a new activation starts with an unstaged source")
        state.record(.staged, generation: 4)
        suite.expect(state.lastOutcome == .notApplicable, "a pass of another activation is not recorded")
        state.record(.staged, generation: 5)
        suite.expect(state.lastOutcome == .staged, "a confirmed staging is remembered")
        state.record(.unresolved, generation: 5)
        suite.expect(state.lastOutcome == .unresolved, "a failed pass leaves the source unstaged for the next one")
        suite.expect(SwitcherSupport.shouldSkipSourceStaging(outcome: .staged, frontmostPID: 30, sourcePID: 20),
                     "a source that is not back in front stays staged")
        suite.expect(!SwitcherSupport.shouldSkipSourceStaging(outcome: .staged, frontmostPID: 20, sourcePID: 20),
                     "a source that came back to the front is staged again")
        suite.expect(!SwitcherSupport.shouldSkipSourceStaging(outcome: .unresolved, frontmostPID: 30, sourcePID: 20),
                     "an unconfirmed staging is tried again")
        suite.expect(!SwitcherSupport.shouldSkipSourceStaging(outcome: .staged, frontmostPID: nil, sourcePID: 20),
                     "a staging with no foreground reading is not skipped")
    }

    private static func retryChecks(_ suite: TestSuite) {
        func shouldContinue(afterQuery frontmost: pid_t) -> Bool {
            let state = SwitcherWindowFocusRetryState(targetWindowID: 1, targetStartedMinimized: false,
                                                      knownWindowIDs: [1])
            return state.shouldContinue(targetPID: 10, sourcePID: 20, frontmostPID: 10,
                                        frontmostAfterFocusQueryPID: { frontmost },
                                        targetMinimizedState: false,
                                        targetAppWindowIDs: [1, 2],
                                        targetAppFocusedWindowID: 1)
        }
        suite.expect(shouldContinue(afterQuery: 10),
                     "a pass goes on while the target is still in front after its focus query")
        suite.expect(!shouldContinue(afterQuery: 30),
                     "a slow focus query cannot reclaim an app the user left while it ran")
        let restored = SwitcherWindowFocusRetryState(targetWindowID: 1, targetStartedMinimized: true,
                                                     targetWasObservedRestored: true, knownWindowIDs: [1])
        var asked = 0
        restored.observeInitialMinimizedState { asked += 1; return nil }
        suite.expect(asked == 1, "a window that started minimized is read once for its initial state")
        let ordinary = SwitcherWindowFocusRetryState(targetWindowID: 1, targetStartedMinimized: false,
                                                     targetWasObservedRestored: true, knownWindowIDs: [1])
        ordinary.observeInitialMinimizedState { asked += 1; return nil }
        suite.expect(asked == 1, "a window that started restored is not read for its initial state")
    }

    private static func activationChecks(_ suite: TestSuite) {
        typealias Steps = WindowActivator.ActivationSteps<SwitcherActivationTests.App>
        var writes: [() -> Void] = []
        var prepares = 0
        var snapshotReads = 0
        var minimized = false
        func makeSteps() -> Steps {
            var calls = SwitcherActivationTests.calls
            calls.writeLane = { writes.append($0) }
            calls.prepareWindow = { _, _ in prepares += 1; return true }
            return Steps(calls: calls,
                         openApplication: { _ in },
                         watchAppActivation: { _ in { _, _, _ in } },
                         minimizedState: { _, _ in minimized },
                         beginSpaceHop: { _, _, _, _, _ in false },
                         snapshot: { _ in snapshotReads += 1; return [77, 78] },
                         watchTargetMinimize: { _ in },
                         stageSourceBehindTarget: { _ in },
                         shouldContinueFocusRetry: { _ in true },
                         after: { _, _ in })
        }
        func drain() {
            while !writes.isEmpty {
                let work = writes.removeFirst()
                work()
            }
        }
        let target = SwitcherItem.window(id: 77, title: "Target", appName: "Target", pid: 10,
                                         isOnScreen: true, frame: .zero)
        let other = SwitcherItem.window(id: 88, title: "Other", appName: "Other", pid: 11,
                                        isOnScreen: true, frame: .zero)

        SwitcherActivationTests.reset()
        WindowActivator.activate(target, retry: false, sources: SwitcherActivationSources(), steps: makeSteps())
        let raisedBeforeDrain = SwitcherActivationTests.events.contains { $0.hasPrefix("raise:") }
        suite.expect(!raisedBeforeDrain && !writes.isEmpty,
                     "the exact-window focus waits for the write lane instead of running in the key callback")
        drain()
        suite.expect(SwitcherActivationTests.events.contains("raise:77:10:false"),
                     "the queued focus write raises the selected window when its lane runs")

        SwitcherActivationTests.reset()
        writes = []
        WindowActivator.activate(target, retry: false, sources: SwitcherActivationSources(), steps: makeSteps())
        let stale = writes
        writes = []
        WindowActivator.activate(other, retry: false, sources: SwitcherActivationSources(), steps: makeSteps())
        SwitcherActivationTests.events = []
        stale.forEach { $0() }
        suite.expect(!SwitcherActivationTests.events.contains { $0.hasPrefix("raise:77") },
                     "a newer activation drops the focus write an earlier one left queued")
        writes = []

        SwitcherActivationTests.reset()
        prepares = 0
        minimized = true
        WindowActivator.activate(target, retry: false, sources: SwitcherActivationSources(), steps: makeSteps())
        suite.expect(prepares == 0,
                     "a minimized target is not restored before its app is in front, which flashed it")
        minimized = false
        WindowActivator.activate(target, retry: false, sources: SwitcherActivationSources(), steps: makeSteps())
        suite.expect(prepares == 1, "a restored target is prepared before it is fronted")
        writes = []

        let snapshot = SwitcherWindowServerSnapshot(windowInfo: [info(77, owner: 10), info(78, owner: 10)],
                                                    capturesActivationBaseline: true)
        for (current, expectedReads) in [(Set<CGWindowID>([77, 78]), 0), (Set<CGWindowID>([77, 78, 79]), 1)] {
            SwitcherActivationTests.reset()
            snapshotReads = 0
            var steps = makeSteps()
            steps.currentWindowIDs = { current }
            WindowActivator.activate(target, retry: true, sources: SwitcherActivationSources(),
                                     windowServerSnapshot: snapshot, steps: steps)
            suite.expect(snapshotReads == expectedReads,
                         "the session's window-server snapshot is reused only while the window set is unchanged")
            writes = []
        }
    }
}
