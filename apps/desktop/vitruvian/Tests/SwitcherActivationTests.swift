// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import AppKit
import ApplicationServices
import VitruvianCore
import VitruvianDesign
import VitruvianServices
import VitruvianUI

/// The production activation and window fronting run against apps and
/// window-server calls that never activate an app or post input. Native
/// window ordering is validated separately.
enum SwitcherActivationTests {
    // Only the test's own thread touches these.
    nonisolated(unsafe) static var events: [String] = []
    nonisolated(unsafe) static var records: [[UInt8]] = []
    nonisolated(unsafe) static var canRaise = true
    static var fronting = SpaceWindowBridge.FrontingCalls(processForPID: nil, setFrontProcess: nil,
                                                          postEventRecord: nil)

    nonisolated final class App: SwitcherActivatableApp {
        let processIdentifier: pid_t
        var isTerminated = false
        init?(processIdentifier: pid_t) {
            guard processIdentifier > 0 else { return nil }
            self.processIdentifier = processIdentifier
        }
        func unhide() -> Bool { events.append("unhide"); return true }
        func activateFromCurrent(options: NSApplication.ActivationOptions) -> Bool {
            events.append("activate:\(processIdentifier):\(options.contains(.activateAllWindows))")
            return true
        }
        func activate(options: NSApplication.ActivationOptions) -> Bool { false }
    }
    static var calls: WindowActivator.ActivationCalls<App> {
        .init(running: { App(processIdentifier: $0) },
              yield: { events.append("yield:\($0.processIdentifier)") },
              frontWindow: { SpaceWindowBridge.frontWindow($0, ownerPID: $1, calls: fronting) },
              focusWindow: { windowID, pid, makeAppFrontmost in
                  events.append("raise:\(windowID):\(pid):\(makeAppFrontmost)")
                  return canRaise
              },
              prepareWindow: { _, _ in true })
    }
    static func reset(raise: Bool = true, front: CGError = .success, down: CGError = .success, up: CGError = .success) {
        events = []; records = []; canRaise = raise
        fronting = .init(
            processForPID: { pid, _ in events.append("owner:\(pid)"); return noErr },
            setFrontProcess: { _, id, _ in events.append("front:\(id)"); return front },
            postEventRecord: { _, bytes in
                events.append("event:\(bytes[8])")
                records.append(Array(UnsafeBufferPointer(start: bytes, count: 0x100)))
                return bytes[8] == 1 ? down : up
            })
    }
    static func run(_ suite: TestSuite) {
        let app = App(processIdentifier: 20)!
        let windowPlan = SwitcherSupport.activationPlan(targetsSpecificWindow: true)
        func select(owner: pid_t = 20) {
            WindowActivator.activateApp(app, plan: windowPlan, windowID: 77, windowOwnerPID: owner, calls: calls)
        }
        reset(); select()
        suite.expect(events == ["owner:20", "front:77", "event:1", "raise:77:20:false"],
                     "a delivered window selection raises the exact window without activating every sibling")
        // The press that makes the window key must name the window and aim far
        // past its bottom-right: a point near the frame's corner hits the resize
        // border, and some apps turn a NaN point into their top-left corner.
        // Without a release, no control can be activated wherever it lands.
        let windowIDBytes = withUnsafeBytes(of: CGWindowID(77).littleEndian, Array.init)
        let farPointBytes = withUnsafeBytes(of: CGPoint(x: 300_000, y: 300_000), Array.init)
        suite.expect(records.count == 1 && records.allSatisfy { record in
            record[0x04] == 0xf8 && record[0x3a] == 0x10
                && Array(record[0x3c..<0x40]) == windowIDBytes
                && Array(record[0x20..<0x30]) == farPointBytes
        }, "the key-making press names the window and points far past its bottom-right")
        suite.expect(records.map { $0[0x08] } == [1], "the key-making event is a lone press with no release")
        reset(raise: false); select()
        suite.expect(events.contains("activate:20:false"), "a window lost by Accessibility retains cooperative recovery")
        reset(front: .failure); select()
        suite.expect(!events.contains("event:1") && events.contains("activate:20:false"), "a refused front request uses the previous activation path")
        suite.expect(events == ["owner:20", "front:77", "yield:20", "activate:20:false", "raise:77:20:false"],
                     "cooperative recovery still raises the selected window after activating its app")
        for down in [CGError.success, .failure] {
            reset(down: down); select()
            suite.expect(events.contains("activate:20:false") == (down != .success),
                         "a refused press triggers recovery")
            suite.expect(!events.contains("event:2"), "no release is ever posted")
        }
        reset(); fronting.postEventRecord = nil; select()
        suite.expect(!events.contains("front:77") && events.contains("activate:20:false"), "missing event transport cannot claim success")
        reset(); fronting.setFrontProcess = nil; select()
        suite.expect(events.contains("activate:20:false"), "missing front transport recovers")
        reset(); fronting.processForPID = { _, _ in -1 }; select()
        suite.expect(events.contains("activate:20:false"), "missing process identity recovers")
        reset(); select(owner: 30)
        suite.expect(events.prefix(3) == ["yield:20", "activate:20:false", "owner:30"],
                     "host menus are activated before fronting an accessory owner's window")
        suite.expect(events.last == "raise:77:30:false", "helper window focusing does not replace host activation")
        reset(); _ = WindowActivator.activateSource(pid: 20, windowID: nil, windowOwnerPID: nil, calls: calls)
        suite.expect(events == ["unhide", "yield:20", "activate:20:false"], "returning without a saved window does not raise all source windows")
        reset(); _ = WindowActivator.activateSource(pid: 20, windowID: 77, windowOwnerPID: 20, calls: calls)
        suite.expect(!events.contains("activate:20:true") && events.contains("front:77"), "returning to an identified source still selects its window")
        reset(); WindowActivator.activateApp(app, plan: SwitcherSupport.activationPlan(targetsSpecificWindow: false),
                                             calls: calls)
        suite.expect(events == ["yield:20", "activate:20:true"], "explicit app selection still brings all its windows forward")
        reset(); let restored = WindowActivator.activateSource(pid: -1, windowID: nil, windowOwnerPID: nil, calls: calls)
        suite.expect(!restored && events.isEmpty, "an exited source cannot receive restoration")
        var terminated = calls
        terminated.running = { pid in
            let app = App(processIdentifier: pid)
            app?.isTerminated = true
            return app
        }
        reset(); let revived = WindowActivator.activateSource(pid: 20, windowID: 77, windowOwnerPID: 20, calls: terminated)
        suite.expect(!revived && events.isEmpty, "a source that is quitting cannot receive restoration")
    }
}
