// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import AppKit
import VitruvianCore
import VitruvianDesign
import VitruvianServices
import VitruvianUI

/// The post-update icon check runs against a controlled queue and menu bar;
/// no real status items, windows, settings or session state are changed.
enum PostUpdateStatusItemRecoveryTests {
    final class Item {
        var frame: CGRect = .zero
        var hasMenu = false
        var isVisible = true
    }

    /// The app and the system as the check sees them.
    final class World {
        var item: Item? = Item()
        /// Items the menu bar still holds after the app let go of them.
        var retired: [Item] = []
        var recreations = 0
        var replacementFrame: CGRect = .zero
        var isTerminating = false
        var isReshowing = false
        var panelIsShown = false
        var logs: [String] = []
        var isDeveloperBuild = false
        var version = "3.4.0-beta.3"
        var now = Date(timeIntervalSince1970: 1_000_000)
        var jobs: [@MainActor () -> Void] = []
        var screens = [CGRect(x: 0, y: 0, width: 1470, height: 956)]
        var mouseIsPressed = false
        var hidesIcon = false
        var menuBarVisible = true
        var presentation: NSApplication.PresentationOptions = []
        var session: [String: Any]? = [kCGSessionOnConsoleKey as String: true]
        var manager: String?

        var check: StatusItemUpdateCheck<Item> {
            StatusItemUpdateCheck(
                host: .init(item: { [unowned self] in self.item },
                            isTerminating: { [unowned self] in self.isTerminating },
                            isReshowing: { [unowned self] in self.isReshowing },
                            panelIsShown: { [unowned self] in self.panelIsShown },
                            hasMenu: { $0.hasMenu },
                            isVisible: { $0.isVisible },
                            iconIsOnScreen: { [unowned self] in
                                guard let item = self.item, item.isVisible else { return false }
                                return StatusItemPlacementSupport.isPlacedStatusFrame(item.frame, screenFrames: self.screens)
                            },
                            recreate: { [unowned self] in
                                self.recreations += 1
                                let replacement = Item()
                                replacement.frame = self.replacementFrame
                                self.item = replacement
                            },
                            log: { [unowned self] in self.logs.append($0) }),
                system: .init(isDeveloperBuild: { [unowned self] in self.isDeveloperBuild },
                              version: { [unowned self] in self.version },
                              now: { [unowned self] in self.now },
                              after: { [unowned self] delay, work in
                                  self.jobs.append {
                                      self.now += delay
                                      work()
                                  }
                              },
                              screenFrames: { [unowned self] in self.screens },
                              mouseIsPressed: { [unowned self] in self.mouseIsPressed },
                              hidesIcon: { [unowned self] in self.hidesIcon },
                              menuBarVisible: { [unowned self] in self.menuBarVisible },
                              presentationHidesMenuBar: { [unowned self] in
                                  !self.presentation.intersection([.autoHideMenuBar, .hideMenuBar, .fullScreen]).isEmpty
                              },
                              session: { [unowned self] in self.session },
                              menuBarManager: { [unowned self] in self.manager }),
                interval: 0.8)
        }

        func next() {
            guard !jobs.isEmpty else { return }
            jobs.removeFirst()()
        }

        func drain() {
            // A regression that polls forever must fail rather than hang.
            for _ in 0..<100 where !jobs.isEmpty { next() }
        }
    }

    static let visibleFrame = CGRect(x: 1135, y: 926, width: 36, height: 30)

    static func run(_ suite: TestSuite) {
        for previous in [nil, "", "dev", "3.4.0-beta.3", "3.4.0", "3.5.0"] as [String?] {
            let world = World()
            world.check.start(previousVersion: previous)
            suite.expect(world.jobs.isEmpty,
                         "first installs, unchanged versions and downgrades never schedule recovery: \(previous ?? "nil")")
        }
        for previous in ["3.3.5", "3.4.0-beta.2.1"] {
            let world = World()
            world.item?.frame = visibleFrame
            let original = world.item
            world.check.start(previousVersion: previous)
            world.drain()
            suite.expect(world.item === original && world.recreations == 0,
                         "a healthy item keeps its exact instance after an update from \(previous)")
            suite.expect(world.logs == ["post-update appeared"] && world.jobs.isEmpty,
                         "successful placement ends the check without future polling")
        }
        do {
            let world = World()
            world.item?.frame = CGRect(x: 0, y: 0, width: 36, height: 0)
            world.check.start(previousVersion: "3.3.5")
            for _ in 0..<8 { world.next() }
            suite.expect(world.recreations == 0, "a newborn item gets several seconds to settle without being replaced")
            world.item?.frame = visibleFrame
            world.drain()
            suite.expect(world.recreations == 0 && world.jobs.isEmpty,
                         "late placement cancels recovery without losing the arranged position")
        }
        for succeeds in [true, false] {
            let world = World()
            world.replacementFrame = succeeds ? visibleFrame : CGRect(x: -200, y: 926, width: 36, height: 30)
            world.check.start(previousVersion: "3.3.5")
            for _ in 0..<11 { world.next() }
            suite.expect(world.recreations == 0, "the full initial placement grace is preserved")
            world.next()
            suite.expect(world.recreations == 1 && world.logs.last == "post-update recreating",
                         "a missing icon gets one recovery attempt")
            world.drain()
            suite.expect(world.recreations == 1 && world.jobs.isEmpty,
                         "verification never escalates to another rebuild or identity reset")
            suite.expect(world.logs.last == (succeeds ? "post-update appeared" : "post-update still hidden"),
                         "the replacement's real placement result is recorded")
        }

        let cancellations: [(String, (World) -> Void)] = [
            ("user hides the icon", { $0.hidesIcon = true }),
            ("system hides the item", { $0.item?.isVisible = false }),
            ("panel is open", { $0.panelIsShown = true }),
            ("context menu is open", { $0.item?.hasMenu = true }),
            ("person is dragging an item", { $0.mouseIsPressed = true }),
            ("app is quitting", { $0.isTerminating = true }),
            ("manual recovery owns the item", { $0.isReshowing = true }),
            ("reopen replaced the item", { world in
                // The old item may outlive the swap, so identity, not its
                // release, is what stops the check.
                if let old = world.item { world.retired.append(old) }
                world.item = Item()
            }),
            ("controller went away", { $0.item = nil }),
            ("menu bar hides", { $0.menuBarVisible = false }),
            ("auto-hidden bar", { $0.presentation = [.autoHideMenuBar] }),
            ("hidden presentation", { $0.presentation = [.hideMenuBar] }),
            ("fullscreen presentation", { $0.presentation = [.fullScreen] }),
            ("display layout changes", { $0.screens[0].origin.x = -1470 }),
            ("all displays disconnect", { $0.screens = [] }),
            ("session state is unavailable", { $0.session = nil }),
            ("user switches away", { $0.session = [kCGSessionOnConsoleKey as String: false] }),
            ("screen locks", { $0.session?["CGSSessionScreenIsLocked"] = true }),
            ("menu bar organizer is running", { $0.manager = "organizer" }),
        ]
        for (name, cancel) in cancellations {
            // Cancellation must hold both before a rebuild and while verifying
            // its result, not just when the launch first schedules the check.
            for afterRebuild in [false, true] {
                let world = World()
                world.check.start(previousVersion: "3.3.5")
                for _ in 0..<(afterRebuild ? 12 : 1) { world.next() }
                let count = world.recreations
                cancel(world)
                world.drain()
                suite.expect(world.recreations == count && world.jobs.isEmpty,
                             "recovery stops when \(name), after rebuild: \(afterRebuild)")
            }
        }
        do {
            let world = World()
            world.check.start(previousVersion: "3.3.5")
            world.now += 31
            world.drain()
            suite.expect(world.recreations == 0 && world.jobs.isEmpty,
                         "a callback delayed beyond the startup window cannot recover after sleep")
        }
        for developer in [false, true] {
            let world = World()
            world.isDeveloperBuild = developer
            if !developer { world.screens = [] }
            world.check.start(previousVersion: "3.3.5")
            suite.expect(world.jobs.isEmpty,
                         "developer builds and launches without displays leave the menu bar alone")
        }
    }
}
