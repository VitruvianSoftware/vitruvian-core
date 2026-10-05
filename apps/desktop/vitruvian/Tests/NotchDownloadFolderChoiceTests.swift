// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import AppKit
import Foundation
import VitruvianCore
import VitruvianDesign
import VitruvianServices
import VitruvianUI

/// The production folder choice runs on a session of doubles that model
/// native dismissal order without creating windows or reading UI.
enum NotchDownloadFolderChoiceContract {
    final class Window: IslandWindowing {
        var level = NSWindow.Level(rawValue: 26)
        var isVisible = true
        var focusReturns = 0
        func makeKey() {}
    }

    final class Panel {
        static weak var current: Panel?
        /// Set when begun on its own above the island.
        var level: NSWindow.Level?
        /// Begun as an ordinary window, as from Settings.
        var ordinary = false
        var focused = false
        var cancelled = false
        var url: URL? = URL(fileURLWithPath: "/Users/example/Downloads", isDirectory: true)
        var dismissed: () -> Void = {}
        private var completed: ((NSApplication.ModalResponse, URL?) -> Void)?
        var chooser: NotchDownloadFolderChoice.Chooser {
            .init(beginAbove: { level, completion in
                Self.current = self
                self.level = level
                self.completed = completion
            }, begin: { completion in
                Self.current = self
                self.ordinary = true
                self.completed = completion
            }, makeKeyAndOrderFront: { self.focused = true },
            cancel: { self.cancelled = true; self.finish(.cancel) })
        }
        func finish(_ response: NSApplication.ModalResponse) {
            if Self.current === self { Self.current = nil }
            completed?(response, url)
            // Reproduce AppKit restoring a key window after calling completion.
            dismissed()
        }
    }

    final class Session {
        let settingsWindow = Window()
        var window: Window? = Window()
        var acceptsUserInteraction = true
        var expanded = true
        var selected: NotchModule = .downloads
        var pinned = false
        var available = true
        var downloadsShown = true
        var eventWindow: Window?
        var keyWindow: Window?
        var activatedWithChooser = false
        var panels: [Panel] = []
        var bookmarkFails = false
        var adopted: [Data] = []
        var unavailable = false
        var main: [() -> Void] = []
        private(set) lazy var choice: NotchDownloadFolderChoice = NotchDownloadFolderChoice(environment: .init(
            isAvailable: { self.available },
            downloadsShown: { self.downloadsShown },
            island: {
                NotchIslandSurface(window: self.window, acceptsUserInteraction: self.acceptsUserInteraction,
                                   expanded: self.expanded, selected: self.selected)
            },
            eventWindow: { self.eventWindow },
            keyWindow: { self.keyWindow },
            makeChooser: {
                let panel = Panel()
                panel.dismissed = { self.keyWindow = self.settingsWindow }
                self.panels.append(panel)
                return panel.chooser
            },
            activate: {
                // A pending chooser keeps the island's working surface.
                self.activatedWithChooser = Panel.current != nil
                if self.eventWindow === self.window, !self.activatedWithChooser, !self.pinned { self.expanded = false }
                self.keyWindow = self.settingsWindow
            },
            reopenDownloads: {
                self.selected = .downloads
                self.expanded = true
                self.window?.focusReturns += 1
                self.keyWindow = self.window
            },
            main: { work in self.main.append { work() } },
            bookmark: { _ in
                if self.bookmarkFails { throw CocoaError(.fileReadNoPermission) }
                return Data([1, 2, 3])
            },
            adopt: { bookmark in
                // The service stops watching, which ends any chooser, first.
                self.choice.cancel()
                self.adopted.append(bookmark)
            },
            markUnavailable: { self.unavailable = true }))

        init(fromNotch: Bool = true, pinned: Bool = false, menuAction: Bool = false) {
            self.pinned = pinned
            let origin = fromNotch ? window : settingsWindow
            keyWindow = origin
            eventWindow = menuAction ? nil : origin
        }

        func drain() { while !main.isEmpty { main.removeFirst()() } }
    }
}

enum NotchDownloadFolderChoiceTests {
    private typealias Context = NotchDownloadFolderChoiceContract

    static func run(_ suite: TestSuite) {
        for pinned in [false, true] {
            for menu in [false, true] {
                let session = Context.Session(pinned: pinned, menuAction: menu)
                let choice = session.choice
                let window = session.window!
                choice.choose()
                guard let panel = session.panels.last, choice.isChoosing else {
                    suite.expect(false, "the folder chooser was created"); continue
                }
                suite.expect(!panel.ordinary && panel.focused && (panel.level?.rawValue ?? 0) > window.level.rawValue
                       && session.activatedWithChooser,
                       "notch buttons and menus focus a standalone picker, begun before activation")
                suite.expect(session.expanded && session.pinned == pinned,
                       "opening the picker preserves the working surface and existing pin")
                panel.finish(.OK)
                suite.expect(session.keyWindow !== window && window.focusReturns == 0,
                       "focus is not restored before native dismissal finishes")
                session.drain()
                suite.expect(session.keyWindow === window && window.focusReturns == 1 && session.pinned == pinned,
                       "successful folder selection returns to the same Downloads surface without altering pin")
                suite.expect(session.adopted == [Data([1, 2, 3])] && !session.unavailable,
                       "only successful selection saves the folder authority and enables monitoring")
            }
        }
        let cancelled = Context.Session()
        cancelled.choice.choose()
        cancelled.panels.last?.finish(.cancel)
        cancelled.drain()
        suite.expect(cancelled.window?.focusReturns == 1 && cancelled.adopted.isEmpty,
               "Cancel returns to the still-open origin without saving a folder or enabling downloads")

        let settings = Context.Session(fromNotch: false, pinned: true)
        let backgroundNotch = settings.window!
        settings.choice.choose()
        suite.expect(settings.panels.last?.ordinary == true && settings.panels.last?.level == nil,
               "a Settings action never borrows a pinned notch as its parent or rises to its level")
        settings.panels.last?.finish(.OK)
        settings.drain()
        suite.expect(backgroundNotch.focusReturns == 0 && settings.keyWindow === settings.settingsWindow
               && settings.adopted.count == 1,
               "Settings selection stays in Settings and never opens or focuses the notch")

        let removed = Context.Session(fromNotch: false)
        removed.choice.choose()
        removed.available = false
        removed.panels.last?.finish(.OK)
        suite.expect(removed.adopted.isEmpty, "a Settings chooser answered after the feature was removed saves nothing")

        let clicked = Context.Session()
        clicked.keyWindow = clicked.settingsWindow
        clicked.choice.choose()
        suite.expect(clicked.panels.last?.level != nil && clicked.panels.last?.ordinary == false,
               "a click on the island opens the picker over it even while another window is key")

        for interruption in 0..<7 {
            let session = Context.Session()
            let window = session.window!
            session.choice.choose()
            let panel = session.panels.last!
            switch interruption {
            case 0: session.choice.cancel()
            case 1: session.available = false
            case 2: session.acceptsUserInteraction = false
            case 3: session.selected = .music
            case 4: session.expanded = false
            case 5: session.window = Context.Window()
            default: session.downloadsShown = false
            }
            panel.finish(.OK)
            session.drain()
            suite.expect(window.focusReturns == 0 && session.adopted.isEmpty,
                   "stop, disable, lock, section change, collapse, replacement or hide rejects the stale folder result")
        }
        for interruption in 0..<4 {
            let session = Context.Session()
            let window = session.window!
            session.choice.choose()
            session.panels.last?.finish(.OK)
            switch interruption {
            case 0: session.choice.cancel()
            case 1: session.selected = .music
            case 2: session.expanded = false
            default: session.available = false
            }
            session.drain()
            suite.expect(window.focusReturns == 0, "an interruption during native dismissal cancels the deferred focus return too")
        }
        let newer = Context.Session()
        let window = newer.window!
        newer.choice.choose()
        newer.panels.last?.finish(.OK)
        newer.eventWindow = newer.settingsWindow
        newer.keyWindow = newer.settingsWindow
        newer.choice.choose()
        newer.panels.last?.finish(.cancel)
        newer.drain()
        suite.expect(window.focusReturns == 0, "a newer Settings chooser supersedes the old pending notch return")

        let failed = Context.Session()
        failed.choice.choose()
        failed.bookmarkFails = true
        failed.panels.last?.finish(.OK)
        failed.drain()
        suite.expect(failed.unavailable && failed.window?.focusReturns == 1 && failed.adopted.isEmpty,
               "a failed folder grant returns to the existing error surface without saving or enabling anything")

        let leaving = Context.Session()
        leaving.choice.choose()
        let islandChooser = leaving.panels.last
        leaving.choice.cancelNotchChoice()
        leaving.drain()
        suite.expect(islandChooser?.cancelled == true && Context.Panel.current == nil && !leaving.choice.isChoosing,
               "leaving the island's Downloads page closes the chooser begun there")
        suite.expect(leaving.window?.focusReturns == 0 && leaving.adopted.isEmpty,
               "the closed island chooser neither saves a folder nor refocuses the island")

        let staying = Context.Session(fromNotch: false)
        staying.choice.choose()
        let settingsChooser = staying.panels.last
        staying.choice.cancelNotchChoice()
        suite.expect(settingsChooser?.cancelled == false && Context.Panel.current === settingsChooser
               && staying.choice.isChoosing,
               "leaving the island's Downloads page leaves a chooser begun in Settings open")
        settingsChooser?.finish(.OK)
        staying.drain()
        suite.expect(staying.adopted.count == 1,
               "the Settings chooser still saves the folder picked after the island's page went away")
    }
}
