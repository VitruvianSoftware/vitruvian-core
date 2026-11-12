// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import AppKit
import VitruvianCore
import VitruvianDesign
import VitruvianServices
import VitruvianUI

/// The production dialog host runs with doubles for the dialog, the island and
/// the application: no dialog opens and nothing activates.
enum MediaDialogHostContract {
    final class Island: IslandWindowing {
        var isVisible = true
        var level = NSWindow.Level(rawValue: 26)
        var keyRequests = 0
        func makeKey() { keyRequests += 1 }
    }

    /// A dialog that records how it was opened and closes when told.
    final class Panel {
        static weak var current: Panel?
        var level: NSWindow.Level?
        var focused = false
        var modalRuns = 0
        private var completed: ((NSApplication.ModalResponse) -> Void)?
        var dialog: MediaPanelModal.Dialog {
            .init(begin: { level, completion in
                Self.current = self
                self.level = level
                self.completed = completion
            }, makeKeyAndOrderFront: { self.focused = true },
            runModal: { self.modalRuns += 1; return .OK })
        }
        func finish(_ response: NSApplication.ModalResponse) {
            if Self.current === self { Self.current = nil }
            completed?(response)
        }
    }

    /// The island, the application and the launcher a dialog opens over.
    final class Session {
        var island: Island? = Island()
        var eventWindow: Island?
        var keyWindow: Island?
        var expanded = true
        /// Whether the island's own dialog was already up at each activation.
        var activations: [Bool] = []
        var main: [() -> Void] = []
        var refocuses = 0
        var host: MediaPanelModal.Host {
            .init(island: { self.island }, eventWindow: { self.eventWindow }, keyWindow: { self.keyWindow },
                  islandExpanded: { self.expanded },
                  activate: { self.activations.append(Panel.current != nil) },
                  main: { work in self.main.append { work() } },
                  refocusLauncher: { self.refocuses += 1 })
        }
        func drain() { while !main.isEmpty { main.removeFirst()() } }
    }
}

enum MediaDialogHostTests {
    private typealias Context = MediaDialogHostContract

    static func run(expect: (Bool, String) -> Void) {
        for viaEvent in [true, false] {
            let session = Context.Session()
            let island = session.island!
            if viaEvent { session.eventWindow = island } else { session.keyWindow = island }
            let panel = Context.Panel()
            var responses: [NSApplication.ModalResponse] = []
            MediaPanelModal.run(panel.dialog, host: session.host) { responses.append($0) }
            expect(panel.focused && panel.modalRuns == 0
                   && (panel.level?.rawValue ?? 0) > island.level.rawValue && session.activations == [true],
                   "a dialog begun from the island opens above it on its own before activation, never as an "
                   + "application-modal window that opens behind it")
            let second = Context.Panel()
            MediaPanelModal.run(second.dialog, host: session.host) { _ in }
            expect(second.level == nil && !second.focused && second.modalRuns == 0 && MediaPanelModal.panelModalActive,
                   "a second request while the dialog is up is ignored")
            panel.finish(.OK)
            expect(responses == [.OK] && !MediaPanelModal.panelModalActive && island.keyRequests == 0,
                   "the completion runs before focus returns, while native dismissal is still restoring key windows")
            session.drain()
            expect(island.keyRequests == 1 && session.refocuses == 0,
                   "focus returns to the still-open island on the next turn")
        }

        let collapsing = Context.Session()
        collapsing.eventWindow = collapsing.island
        let cancelled = Context.Panel()
        MediaPanelModal.run(cancelled.dialog, host: collapsing.host) { _ in }
        collapsing.expanded = false
        cancelled.finish(.cancel)
        collapsing.drain()
        expect(collapsing.island?.keyRequests == 0 && !MediaPanelModal.panelModalActive,
               "an island that collapsed meanwhile is not made key again")

        for hidden in [false, true] {
            let session = Context.Session()
            let island = session.island!
            island.isVisible = !hidden
            session.eventWindow = hidden ? island : nil
            let panel = Context.Panel()
            var responses: [NSApplication.ModalResponse] = []
            MediaPanelModal.run(panel.dialog, host: session.host) { responses.append($0) }
            expect(panel.level == nil && panel.modalRuns == 0 && session.activations == [false]
                   && MediaPanelModal.panelModalActive,
                   "a dialog begun from a popover, the launcher or an ordered-out island activates first and "
                   + "runs modal on the next turn")
            session.drain()
            expect(panel.modalRuns == 1 && responses == [.OK] && !MediaPanelModal.panelModalActive
                   && session.refocuses == 1 && island.keyRequests == 0,
                   "the modal path still hands focus back through the launcher")
        }
    }
}
