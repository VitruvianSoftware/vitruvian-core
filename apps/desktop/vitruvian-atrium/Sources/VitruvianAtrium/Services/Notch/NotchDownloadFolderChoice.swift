// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import AppKit
import VitruvianCore
import VitruvianDesign

/// Choosing the folder the island watches for downloads, from its Downloads
/// page or from Settings, and returning to the page it was chosen from.
/// `NotchDownloadService` owns it and adopts what is chosen; tests pass
/// doubles for the chooser, the island and the application.
@MainActor
package final class NotchDownloadFolderChoice {
    /// A folder chooser, as the choice drives it.
    @MainActor
    package struct Chooser {
        /// Opens on its own at `level`, staying up while another app is
        /// active. Used over the island.
        package var beginAbove: (_ level: NSWindow.Level,
                                 _ completion: @escaping (NSApplication.ModalResponse, URL?) -> Void) -> Void
        /// Opens as an ordinary window, as from Settings.
        package var begin: (_ completion: @escaping (NSApplication.ModalResponse, URL?) -> Void) -> Void
        package var makeKeyAndOrderFront: () -> Void
        package var cancel: () -> Void

        package init(beginAbove: @escaping (NSWindow.Level, @escaping (NSApplication.ModalResponse, URL?) -> Void) -> Void,
                     begin: @escaping (@escaping (NSApplication.ModalResponse, URL?) -> Void) -> Void,
                     makeKeyAndOrderFront: @escaping () -> Void, cancel: @escaping () -> Void) {
            self.beginAbove = beginAbove
            self.begin = begin
            self.makeKeyAndOrderFront = makeKeyAndOrderFront
            self.cancel = cancel
        }

        init(_ panel: NSOpenPanel) {
            panel.canChooseFiles = false
            panel.canChooseDirectories = true
            panel.allowsMultipleSelection = false
            panel.directoryURL = FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask).first
            panel.message = FeatureStrings.notchFiles(L10n.shared.language).downloadsHint
            self.init(beginAbove: { level, completion in
                // An attached sheet moves/reskins a borderless island. Keep the
                // chooser independent and above its parent instead, without
                // changing the pin; isChoosingFolder keeps the surface alive.
                panel.level = level
                // Like the sheet it replaces, it stays up while another app is active.
                panel.hidesOnDeactivate = false
                panel.begin { [weak panel] response in completion(response, panel?.url) }
            }, begin: { completion in
                panel.begin { [weak panel] response in completion(response, panel?.url) }
            }, makeKeyAndOrderFront: { panel.makeKeyAndOrderFront(nil) },
            cancel: { panel.cancel(nil) })
        }
    }

    /// What the choice reads and drives. `system` is the feature and island
    /// settings, the island, the application, an open panel and the main
    /// queue; the service passes how a chosen folder is adopted.
    @MainActor
    package struct Environment {
        package var isAvailable: () -> Bool
        /// The island is on and lists the Downloads page.
        package var downloadsShown: () -> Bool
        package var island: () -> NotchIslandSurface
        /// The window under the event being handled, and the key window.
        package var eventWindow: () -> AnyObject?
        package var keyWindow: () -> AnyObject?
        package var makeChooser: () -> Chooser
        package var activate: () -> Void
        package var reopenDownloads: () -> Void
        package var main: (@escaping @MainActor () -> Void) -> Void
        /// The security-scoped bookmark that lets a later launch read the folder.
        package var bookmark: (URL) throws -> Data
        /// Watches the folder from now on.
        package var adopt: (_ bookmark: Data) -> Void
        package var markUnavailable: () -> Void

        package init(isAvailable: @escaping () -> Bool, downloadsShown: @escaping () -> Bool,
                     island: @escaping () -> NotchIslandSurface, eventWindow: @escaping () -> AnyObject?,
                     keyWindow: @escaping () -> AnyObject?, makeChooser: @escaping () -> Chooser,
                     activate: @escaping () -> Void, reopenDownloads: @escaping () -> Void,
                     main: @escaping (@escaping @MainActor () -> Void) -> Void,
                     bookmark: @escaping (URL) throws -> Data, adopt: @escaping (Data) -> Void,
                     markUnavailable: @escaping () -> Void) {
            self.isAvailable = isAvailable
            self.downloadsShown = downloadsShown
            self.island = island
            self.eventWindow = eventWindow
            self.keyWindow = keyWindow
            self.makeChooser = makeChooser
            self.activate = activate
            self.reopenDownloads = reopenDownloads
            self.main = main
            self.bookmark = bookmark
            self.adopt = adopt
            self.markUnavailable = markUnavailable
        }

        package static func system(adopt: @escaping (Data) -> Void,
                                   markUnavailable: @escaping () -> Void) -> Environment {
            Environment(
                isAvailable: { AppFeature.notchDownloads.isAvailable },
                downloadsShown: { NotchSupport.isEnabled() && NotchSupport.modules().contains(.downloads) },
                island: { NotchIslandSurface.current },
                eventWindow: { NSApp.currentEvent?.window },
                keyWindow: { NSApp.keyWindow },
                makeChooser: { Chooser(NSOpenPanel()) },
                activate: { NSApp.activate(ignoringOtherApps: true) },
                reopenDownloads: { NotchService.shared.open(.downloads, feedback: false) },
                main: { work in
                    // Handed to the main queue, which alone runs it.
                    nonisolated(unsafe) let work = work
                    DispatchQueue.main.async { work() }
                },
                bookmark: { try $0.bookmarkData(options: .withSecurityScope,
                                                includingResourceValuesForKeys: nil, relativeTo: nil) },
                adopt: adopt, markUnavailable: markUnavailable)
        }
    }

    private let environment: Environment
    private var chooser: Chooser?
    private var chooserID = UUID()
    /// The pending chooser was begun from the island's Downloads page.
    private var chooserInNotch = false

    package var isChoosing: Bool { chooser != nil }

    package init(environment: Environment) {
        self.environment = environment
    }

    package func choose() {
        guard chooser == nil, environment.isAvailable() else { return }
        let panel = environment.makeChooser()
        let parent = folderPickerParent()
        let beganInNotch = parent != nil
        let requested = UUID()
        chooserID = requested
        chooser = panel
        chooserInNotch = beganInNotch
        let completed: (NSApplication.ModalResponse, URL?) -> Void = { [weak self, weak parent] response, url in
            guard let self, self.chooser != nil, self.chooserID == requested else { return }
            self.chooser = nil
            self.chooserInNotch = false
            guard !beganInNotch || parent.map(self.canReturnToDownloads) == true else { return }
            if response == .OK, let url, self.environment.isAvailable() {
                do {
                    self.environment.adopt(try self.environment.bookmark(url))
                } catch { self.environment.markUnavailable() }
            }
            guard let parent else { return }
            let returnID = self.chooserID
            // Native panel dismissal restores its previous key window after the
            // completion callback. Return on the next turn without changing pin.
            self.environment.main { [weak self, weak parent] in
                guard let self, let parent, self.chooserID == returnID, self.chooser == nil,
                      self.canReturnToDownloads(parent) else { return }
                self.environment.reopenDownloads()
            }
        }
        if let parent {
            panel.beginAbove(NSWindow.Level(rawValue: parent.level.rawValue + 1), completed)
            environment.activate()
            // Activation alone can leave the nonactivating island holding focus.
            panel.makeKeyAndOrderFront()
        } else {
            environment.activate()
            panel.begin(completed)
        }
    }

    private func folderPickerParent() -> (any IslandWindowing)? {
        guard let window = environment.island().window, canReturnToDownloads(window),
              environment.eventWindow() === window || environment.keyWindow() === window else { return nil }
        return window
    }

    private func canReturnToDownloads(_ window: any IslandWindowing) -> Bool {
        environment.isAvailable() && environment.downloadsShown()
            && environment.island().shows(.downloads, in: window)
    }

    package func cancel() {
        chooserID = UUID()
        chooserInNotch = false
        chooser?.cancel()
        chooser = nil
    }

    /// The island's Downloads page went away: a folder chosen now could no
    /// longer return to it and would be dropped in silence, so its chooser
    /// ends with it. One begun in Settings stays up.
    package func cancelNotchChoice() {
        guard chooserInNotch, chooser != nil else { return }
        cancel()
    }
}
