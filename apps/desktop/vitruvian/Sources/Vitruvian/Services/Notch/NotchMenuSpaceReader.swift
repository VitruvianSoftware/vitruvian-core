// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 VitruvianSoftware

import AppKit
import VitruvianCore
import VitruvianDesign

/// Reads how much of the menu bar beside the camera the menus leave free:
/// at once when started, then about once a second until stopped, and again
/// whenever the island asks.
///
/// Each read measures off the main thread, through the accessibility API, and
/// hands its answer back on the main thread. One read runs at a time. An
/// answer that arrives after the island invalidated the reader (it moved to
/// another display or changed its layout), or after the menu bar changed
/// owner, is dropped and read again. A stopped reader drops whatever is still
/// in flight.
///
/// It only measures. Whether to read at all, and what an answer does to the
/// island, stay with `NotchService`.
package final class NotchMenuSpaceReader {
    /// What one read measures against, taken on the main thread as it starts.
    package struct Subject {
        package let geometry: NotchGeometry
        /// The top of the display that holds the menu bar, which
        /// accessibility frames are flipped against.
        package let primaryTop: CGFloat
        /// The island's own window, which is not a status item.
        package let ownWindow: Int

        package init(geometry: NotchGeometry, primaryTop: CGFloat, ownWindow: Int) {
            self.geometry = geometry
            self.primaryTop = primaryTop
            self.ownWindow = ownWindow
        }
    }

    /// What the reader needs from the system. The app uses `system`; a test
    /// runs each step by hand.
    package struct Environment {
        /// The process whose menus are on show.
        package var menuBarOwner: () -> pid_t?
        package var measure: (pid_t, Subject) -> CGFloat?
        /// Runs a read off the main thread.
        package var background: (@escaping () -> Void) -> Void
        /// Brings an answer back to the main thread.
        package var main: (@escaping () -> Void) -> Void
        /// Calls its closure about once a second until the returned closure
        /// cancels it.
        package var ticks: (@escaping () -> Void) -> () -> Void

        package init(menuBarOwner: @escaping () -> pid_t?,
                     measure: @escaping (pid_t, Subject) -> CGFloat?,
                     background: @escaping (@escaping () -> Void) -> Void,
                     main: @escaping (@escaping () -> Void) -> Void,
                     ticks: @escaping (@escaping () -> Void) -> () -> Void) {
            self.menuBarOwner = menuBarOwner
            self.measure = measure
            self.background = background
            self.main = main
            self.ticks = ticks
        }

        package static var system: Environment {
            let queue = DispatchQueue(label: "com.vitruviansoftware.vitruvian.notch-menu-space", qos: .utility)
            return Environment(
                menuBarOwner: {
                    // The displayed menus belong to the menu bar's owner, which is not the
                    // frontmost application while an accessory app such as a launcher has
                    // focus; that app's own menu geometry was never laid out. When our own
                    // Settings has focus, the menu owner can briefly be nil.
                    // The reader asks on the main thread, from its ticks and its answers.
                    NSWorkspace.shared.menuBarOwningApplication?.processIdentifier
                        ?? (MainActor.assumeIsolated { NSApp.isActive } ? getpid() : nil)
                },
                measure: { pid, subject in
                    NotchMenuBarSpace.measure(pid: pid, geometry: subject.geometry,
                                              primaryTop: subject.primaryTop, ownWindow: subject.ownWindow)
                },
                background: { work in queue.async { work() } },
                main: { work in DispatchQueue.main.async { work() } },
                ticks: { tick in
                    let timer = Timer(timeInterval: 1, repeats: true) { _ in tick() }
                    timer.tolerance = 0.2
                    RunLoop.main.add(timer, forMode: .common)
                    return { timer.invalidate() }
                })
        }
    }

    private let environment: Environment
    private let subject: () -> Subject?
    private let apply: (CGFloat?) -> Void
    private var cancelTicks: (() -> Void)?
    private var reading = false
    private var generation = 0

    /// `subject` describes the island when a read starts, or nil to skip it;
    /// `apply` receives each answer that is still current.
    package init(environment: Environment = .system,
                 subject: @escaping () -> Subject?,
                 apply: @escaping (CGFloat?) -> Void) {
        self.environment = environment
        self.subject = subject
        self.apply = apply
    }

    deinit { cancelTicks?() }

    package var isRunning: Bool { cancelTicks != nil }

    /// Reads now, then about once a second until `stop()`. A running reader
    /// keeps its schedule.
    package func start() {
        guard cancelTicks == nil else { return }
        cancelTicks = environment.ticks { [weak self] in self?.read() }
        read()
    }

    /// Stops the schedule and drops the answer in flight.
    package func stop() {
        cancelTicks?()
        cancelTicks = nil
        generation += 1
    }

    /// The island moved or changed shape: the answer in flight, if any,
    /// measured something else, so it is read again when it arrives.
    package func invalidate() {
        generation += 1
    }

    /// Reads now, unless the reader is stopped or a read is still running.
    package func read() {
        guard cancelTicks != nil, !reading,
              let pid = environment.menuBarOwner(), let subject = subject() else { return }
        reading = true
        let generation = generation
        let environment = environment
        environment.background { [weak self] in
            let room = environment.measure(pid, subject)
            environment.main {
                guard let self else { return }
                self.reading = false
                // A stop moves the generation on as well, and a stopped
                // reader does not read again.
                guard self.generation == generation, environment.menuBarOwner() == pid else {
                    self.read(); return
                }
                self.apply(room)
            }
        }
    }
}
