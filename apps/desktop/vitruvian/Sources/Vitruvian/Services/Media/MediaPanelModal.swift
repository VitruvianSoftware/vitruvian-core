// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import AppKit
import VitruvianCore
import VitruvianDesign

/// The media workspace's file dialogs, run so they take clicks and keys from
/// the non-activating hosts it lives in.
package enum MediaPanelModal {
    /// The media workspace's hosts (menu popover, quick launcher) never activate
    /// the app, and a modal file dialog in an inactive app takes no clicks or
    /// keys (only Cancel reacts). Activate first and let the run loop turn so
    /// the activation lands before the modal session starts, then hand key
    /// focus back to the launcher.
    /// One dialog at a time: the modal now starts a run-loop turn after the
    /// click, so a double-click (or clicking both pickers quickly) would queue
    /// a second identical dialog behind the first without this guard.
    /// While it is set, the island keeps its working surface open.
    @MainActor
    package private(set) static var panelModalActive = false

    @MainActor
    package static func runPanelModal(_ panel: NSSavePanel,
                              completion: @escaping (NSApplication.ModalResponse) -> Void) {
        run(Dialog(panel), host: .system, completion: completion)
    }

    /// A file dialog as the host drives it.
    @MainActor
    package struct Dialog {
        /// Opens on its own at `level`, staying up while another app is
        /// active, and reports how it closed.
        package var begin: (_ level: NSWindow.Level, _ completion: @escaping (NSApplication.ModalResponse) -> Void) -> Void
        package var makeKeyAndOrderFront: () -> Void
        package var runModal: () -> NSApplication.ModalResponse

        package init(begin: @escaping (NSWindow.Level, @escaping (NSApplication.ModalResponse) -> Void) -> Void,
                     makeKeyAndOrderFront: @escaping () -> Void,
                     runModal: @escaping () -> NSApplication.ModalResponse) {
            self.begin = begin
            self.makeKeyAndOrderFront = makeKeyAndOrderFront
            self.runModal = runModal
        }

        init(_ panel: NSSavePanel) {
            self.init(begin: { level, completion in
                panel.level = level
                // Like the sheet it replaces, it stays up while another app is active.
                panel.hidesOnDeactivate = false
                panel.begin { completion($0) }
            }, makeKeyAndOrderFront: { panel.makeKeyAndOrderFront(nil) },
            runModal: { panel.runModal() })
        }
    }

    /// What a dialog is opened over. `system` is the island, the application
    /// and the quick launcher; tests pass doubles.
    @MainActor
    package struct Host {
        package var island: () -> (any IslandWindowing)?
        /// The window under the event being handled, and the key window.
        package var eventWindow: () -> AnyObject?
        package var keyWindow: () -> AnyObject?
        package var islandExpanded: () -> Bool
        package var activate: () -> Void
        package var main: (@escaping @MainActor () -> Void) -> Void
        package var refocusLauncher: () -> Void

        package init(island: @escaping () -> (any IslandWindowing)?,
                     eventWindow: @escaping () -> AnyObject?,
                     keyWindow: @escaping () -> AnyObject?,
                     islandExpanded: @escaping () -> Bool,
                     activate: @escaping () -> Void,
                     main: @escaping (@escaping @MainActor () -> Void) -> Void,
                     refocusLauncher: @escaping () -> Void) {
            self.island = island
            self.eventWindow = eventWindow
            self.keyWindow = keyWindow
            self.islandExpanded = islandExpanded
            self.activate = activate
            self.main = main
            self.refocusLauncher = refocusLauncher
        }

        package static var system: Host {
            Host(island: { NotchService.shared.presentationWindow },
                 eventWindow: { NSApp.currentEvent?.window },
                 keyWindow: { NSApp.keyWindow },
                 islandExpanded: { NotchService.shared.expanded },
                 activate: { NSApp.activate(ignoringOtherApps: true) },
                 main: { work in
                     // Handed to the main queue, which alone runs it.
                     nonisolated(unsafe) let work = work
                     DispatchQueue.main.async { work() }
                 },
                 refocusLauncher: { QuickLauncherService.shared.refocusAfterModal() })
        }
    }

    @MainActor
    package static func run(_ dialog: Dialog, host: Host,
                            completion: @escaping (NSApplication.ModalResponse) -> Void) {
        guard !panelModalActive else { return }
        panelModalActive = true
        if let island = host.island(), island.isVisible,
           host.eventWindow() === island || host.keyWindow() === island {
            // The island floats above the modal panel level, so an
            // application-modal dialog would open behind it, and a sheet
            // moves/reskins the borderless island. Open it on its own,
            // just above the island.
            dialog.begin(NSWindow.Level(rawValue: island.level.rawValue + 1)) { response in
                panelModalActive = false
                // Dismissal restores the previous key window after this callback.
                host.main { if host.islandExpanded() { island.makeKey() } }
                completion(response)
            }
            host.activate()
            // Activation alone can leave the nonactivating island holding focus.
            dialog.makeKeyAndOrderFront()
            return
        }
        host.activate()
        host.main {
            let response = dialog.runModal()
            panelModalActive = false
            host.refocusLauncher()
            completion(response)
        }
    }
}

/// The island's window as the dialogs opened over it see it.
@MainActor
package protocol IslandWindowing: AnyObject {
    var isVisible: Bool { get }
    var level: NSWindow.Level { get }
    func makeKey()
}

extension NSWindow: IslandWindowing {}
