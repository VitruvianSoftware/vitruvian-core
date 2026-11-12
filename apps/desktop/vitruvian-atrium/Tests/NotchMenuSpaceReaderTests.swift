// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 VitruvianSoftware

import CoreGraphics
import Foundation
import VitruvianCore
import VitruvianDesign
import VitruvianServices
import VitruvianUI

/// Drives the island's menu-space reader with every step run by hand: the
/// once-a-second tick, the read off the main thread and the answer's return
/// to it. The reader is the module's own type, not a copy.
enum NotchMenuSpaceReaderTests {
    final class System {
        var owner: pid_t? = 42
        var room: CGFloat? = 64
        var measured: [(pid: pid_t, width: CGFloat)] = []
        var background: [() -> Void] = []
        var main: [() -> Void] = []
        var tick: (() -> Void)?
        var schedules = 0
        var cancels = 0

        var environment: NotchMenuSpaceReader.Environment {
            NotchMenuSpaceReader.Environment(
                menuBarOwner: { [unowned self] in self.owner },
                measure: { [unowned self] pid, subject in
                    self.measured.append((pid, subject.geometry.screen.width))
                    return self.room
                },
                background: { [unowned self] in self.background.append($0) },
                main: { [unowned self] in self.main.append($0) },
                ticks: { [unowned self] tick in
                    self.schedules += 1
                    self.tick = tick
                    return { [unowned self] in
                        self.cancels += 1
                        self.tick = nil
                    }
                })
        }

        /// Runs the reads waiting off the main thread.
        func measure() {
            let work = background
            background.removeAll()
            work.forEach { $0() }
        }

        /// Runs the answers waiting for the main thread.
        func deliver() {
            let work = main
            main.removeAll()
            work.forEach { $0() }
        }
    }

    static func run(_ suite: TestSuite) {
        let system = System()
        var screenWidth: CGFloat = 1440
        var hasSubject = true
        var applied: [CGFloat?] = []
        let reader = NotchMenuSpaceReader(
            environment: system.environment,
            subject: {
                guard hasSubject else { return nil }
                let geometry = NotchGeometry(screen: CGRect(x: 0, y: 0, width: screenWidth, height: 900),
                                             safeAreaTop: 32, cameraWidth: 200)
                return NotchMenuSpaceReader.Subject(geometry: geometry, primaryTop: 900, ownWindow: 7)
            },
            apply: { applied.append($0) })

        reader.read()
        suite.expect(system.background.isEmpty && !reader.isRunning, "a reader that was never started reads nothing")

        reader.start()
        suite.expect(reader.isRunning && system.schedules == 1 && system.background.count == 1 && system.measured.isEmpty,
                     "starting schedules the ticks and queues one read, which measures off the main thread")
        reader.start()
        system.tick?()
        reader.read()
        suite.expect(system.schedules == 1 && system.background.count == 1,
                     "one read runs at a time: starting again, a tick or a request while it runs adds none")
        system.measure()
        suite.expect(applied.isEmpty && system.main.count == 1 && system.measured.map { $0.pid } == [42],
                     "the read measures the menu bar's owner and sends its answer back to the main thread")
        system.deliver()
        suite.expect(applied == [64], "a current answer reaches the island")

        system.tick?()
        suite.expect(system.background.count == 1, "each tick reads again")
        screenWidth = 1920
        system.measure()
        system.deliver()
        suite.expect(system.measured.last?.width == 1440 && applied == [64, 64],
                     "a read measures the island as it was when the read started")

        system.room = 80
        system.tick?()
        system.measure()
        reader.invalidate()
        system.deliver()
        suite.expect(applied == [64, 64] && system.background.count == 1,
                     "an answer measured before the island moved is dropped and read again")
        system.measure()
        system.deliver()
        suite.expect(applied == [64, 64, 80] && system.measured.last?.width == 1920,
                     "the second read measures the island where it is now")

        system.tick?()
        system.measure()
        system.owner = 99
        system.deliver()
        suite.expect(applied.count == 3 && system.background.count == 1,
                     "an answer for menus that are no longer on the bar is dropped and read again")
        system.measure()
        system.deliver()
        suite.expect(applied.count == 4 && system.measured.last?.pid == 99, "the new owner's menus are measured")

        system.tick?()
        reader.stop()
        system.measure()
        system.deliver()
        suite.expect(applied.count == 4 && system.background.isEmpty && !reader.isRunning
                     && system.cancels == 1 && system.tick == nil,
                     "stopping cancels the ticks and drops the answer in flight without reading again")
        reader.read()
        suite.expect(system.background.isEmpty, "a stopped reader ignores requests")

        reader.start()
        system.measure()
        system.deliver()
        suite.expect(system.schedules == 2 && applied.count == 5,
                     "a stopped reader starts again, and a read stopped mid-flight leaves none running")

        system.tick?()
        system.measure()
        reader.stop()
        reader.start()
        suite.expect(system.background.isEmpty, "a restart waits for the read still in flight")
        system.deliver()
        suite.expect(applied.count == 5 && system.background.count == 1,
                     "an answer measured before a stop is dropped after a restart, and read again")
        system.measure()
        system.deliver()
        suite.expect(applied.count == 6, "the fresh read reaches the island")

        system.owner = nil
        system.tick?()
        suite.expect(system.background.isEmpty, "with no menu bar owner there is nothing to read")
        system.owner = 42
        hasSubject = false
        system.tick?()
        suite.expect(system.background.isEmpty, "with no island to measure against there is nothing to read")
        hasSubject = true

        let released = System()
        var temporary: NotchMenuSpaceReader? = NotchMenuSpaceReader(
            environment: released.environment, subject: { nil }, apply: { _ in })
        temporary?.start()
        temporary = nil
        suite.expect(released.cancels == 1, "a released reader cancels its ticks")
    }
}
