// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import AppKit
import VitruvianCore
import VitruvianDesign

/// The media workspace's file dialogs, run so they take clicks and keys from
/// the non-activating hosts it lives in.
enum MediaPanelModal {
    /// The media workspace's hosts (menu popover, quick launcher) never activate
    /// the app, and a modal file dialog in an inactive app takes no clicks or
    /// keys (only Cancel reacts). Activate first and let the run loop turn so
    /// the activation lands before the modal session starts, then hand key
    /// focus back to the launcher.
    /// One dialog at a time: the modal now starts a run-loop turn after the
    /// click, so a double-click (or clicking both pickers quickly) would queue
    /// a second identical dialog behind the first without this guard.
    /// While it is set, the island keeps its working surface open.
    private(set) static var panelModalActive = false

    static func runPanelModal(_ panel: NSSavePanel,
                              completion: @escaping (NSApplication.ModalResponse) -> Void) {
        guard !panelModalActive else { return }
        panelModalActive = true
        if let island = NotchService.shared.presentationWindow, island.isVisible,
           NSApp.currentEvent?.window === island || NSApp.keyWindow === island {
            // The island floats above the modal panel level, so an
            // application-modal dialog would open behind it, and a sheet
            // moves/reskins the borderless island. Open it on its own,
            // just above the island.
            panel.level = NSWindow.Level(rawValue: island.level.rawValue + 1)
            // Like the sheet it replaces, it stays up while another app is active.
            panel.hidesOnDeactivate = false
            panel.begin { response in
                panelModalActive = false
                // Dismissal restores the previous key window after this callback.
                DispatchQueue.main.async { if NotchService.shared.expanded { island.makeKey() } }
                completion(response)
            }
            NSApp.activate(ignoringOtherApps: true)
            // Activation alone can leave the nonactivating island holding focus.
            panel.makeKeyAndOrderFront(nil)
            return
        }
        NSApp.activate(ignoringOtherApps: true)
        DispatchQueue.main.async {
            let response = panel.runModal()
            panelModalActive = false
            QuickLauncherService.shared.refocusAfterModal()
            completion(response)
        }
    }
}
