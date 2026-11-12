// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import AppKit
import Carbon.HIToolbox
import CoreGraphics
import VitruvianCore
import VitruvianDesign

/// Temporarily places plain text on the general pasteboard, pastes it, then
/// restores the previous content if the user did not copy something else.
/// All pasteboard reads share the app's serial lane because promised data can
/// block while its owning process renders it.
@MainActor
package final class TransientPaste {
    /// What the paste reaches outside itself: the pasteboard and the lane
    /// that reads it, the modifier keys held, the posted Command-V and the
    /// clipboard history. `live` is the app's; tests pass their own.
    package struct Environment: @unchecked Sendable {
        package var pasteboard: @Sendable () -> NSPasteboard
        package var lane: GeneralPasteboardAccess
        package var heldModifiers: @MainActor () -> CGEventFlags
        /// Command-V's two key events, each posted when called, or nothing
        /// when they could not be made.
        package var commandV: @MainActor () -> (down: () -> Void, up: () -> Void)?
        package var ignoreHistory: @MainActor (_ upTo: Int) -> Void

        package init(pasteboard: @escaping @Sendable () -> NSPasteboard,
                     lane: GeneralPasteboardAccess,
                     heldModifiers: @escaping @MainActor () -> CGEventFlags,
                     commandV: @escaping @MainActor () -> (down: () -> Void, up: () -> Void)?,
                     ignoreHistory: @escaping @MainActor (_ upTo: Int) -> Void) {
            self.pasteboard = pasteboard
            self.lane = lane
            self.heldModifiers = heldModifiers
            self.commandV = commandV
            self.ignoreHistory = ignoreHistory
        }

        package static var live: Environment {
            Environment(pasteboard: { NSPasteboard.general },
                        lane: .shared,
                        heldModifiers: { CGEventSource.flagsState(.combinedSessionState) },
                        commandV: {
                            guard let keyDown = CGEvent(keyboardEventSource: nil,
                                                        virtualKey: CGKeyCode(kVK_ANSI_V),
                                                        keyDown: true),
                                  let keyUp = CGEvent(keyboardEventSource: nil,
                                                      virtualKey: CGKeyCode(kVK_ANSI_V),
                                                      keyDown: false)
                            else { return nil }
                            keyDown.flags = .maskCommand
                            keyUp.flags = .maskCommand
                            return ({ keyDown.post(tap: .cghidEventTap) }, { keyUp.post(tap: .cghidEventTap) })
                        },
                        ignoreHistory: { ClipboardHistoryService.shared.ignoreNextChange(upTo: $0) })
        }
    }

    // Snippet expansion asks for it from plain code, and is refused off the main thread.
    nonisolated package static let shared = TransientPaste(environment: .live)

    nonisolated private let environment: Environment

    package nonisolated init(environment: Environment) {
        self.environment = environment
    }

    private static let restoreDelay: TimeInterval = 0.5

    private var pendingRestore: (snapshot: [NSPasteboardItem], changeCount: Int)?
    private var restoreWork: DispatchWorkItem?
    private var isPerforming = false

    /// Forwards a paste of non-text content without reading promised data,
    /// taking a snapshot or changing the clipboard. It shares the modifier
    /// wait and shortcut handoff used by a temporary text paste.
    @discardableResult
    package func pasteCurrentContents(willPostShortcut: (() -> Void)? = nil,
                              didPostShortcut: (() -> Void)? = nil,
                              didFail: (() -> Void)? = nil) -> Bool {
        guard Thread.isMainThread, !isPerforming else { return false }
        isPerforming = true
        let pasteboard = environment.pasteboard
        environment.lane.async({ pasteboard().changeCount }) { changeCount in
            self.postPasteWhenModifiersReleased(attempt: 0,
                                                expectedChangeCount: changeCount,
                                                willPost: willPostShortcut,
                                                didPost: didPostShortcut,
                                                didFail: didFail) {
                self.isPerforming = false
            }
        }
        return true
    }

    /// Main thread only: a call from anywhere else is refused.
    @discardableResult
    nonisolated package func paste(_ text: String,
               willPostShortcut: (() -> Void)? = nil,
               didPostShortcut: (() -> Void)? = nil,
               didFail: (() -> Void)? = nil) -> Bool {
        guard Thread.isMainThread else { return false }
        // Checked just above, so the callbacks never leave the main thread.
        nonisolated(unsafe) let willPostShortcut = willPostShortcut
        nonisolated(unsafe) let didPostShortcut = didPostShortcut
        nonisolated(unsafe) let didFail = didFail
        return MainActor.assumeIsolated {
            pasteOnMain(text, willPostShortcut: willPostShortcut, didPostShortcut: didPostShortcut, didFail: didFail)
        }
    }

    private func pasteOnMain(_ text: String,
                             willPostShortcut: (() -> Void)?,
                             didPostShortcut: (() -> Void)?,
                             didFail: (() -> Void)?) -> Bool {
        guard !isPerforming else { return false }
        isPerforming = true

        // Handed to the pasteboard lane, which alone reads it.
        nonisolated(unsafe) let previous = pendingRestore
        // Carried through the lane and called back on the main thread only.
        nonisolated(unsafe) let willPostShortcut = willPostShortcut
        nonisolated(unsafe) let didPostShortcut = didPostShortcut
        nonisolated(unsafe) let didFail = didFail
        restoreWork?.cancel()
        restoreWork = nil

        let general = environment.pasteboard
        environment.lane.async {
            let pasteboard = general()
            let originalChangeCount = pasteboard.changeCount
            let snapshot: [NSPasteboardItem]?
            if let previous, pasteboard.changeCount == previous.changeCount {
                snapshot = previous.snapshot
            } else {
                snapshot = Self.snapshot(of: pasteboard)
            }
            guard let snapshot else {
                DispatchQueue.main.async {
                    self.isPerforming = false
                    didFail?()
                }
                return
            }
            guard pasteboard.changeCount == originalChangeCount else {
                DispatchQueue.main.async {
                    self.isPerforming = false
                    didFail?()
                }
                return
            }

            pasteboard.clearContents()
            guard pasteboard.setString(text, forType: .string) else {
                if !snapshot.isEmpty { pasteboard.writeObjects(snapshot) }
                DispatchQueue.main.async {
                    self.isPerforming = false
                    didFail?()
                }
                return
            }
            let changeCount = pasteboard.changeCount
            // Handed back to the main thread, which keeps it for the restore.
            nonisolated(unsafe) let saved = snapshot

            DispatchQueue.main.async {
                self.environment.ignoreHistory(changeCount)
                self.pendingRestore = (saved, changeCount)
                self.postPasteWhenModifiersReleased(
                    attempt: 0,
                    expectedChangeCount: changeCount,
                    willPost: willPostShortcut,
                    didPost: didPostShortcut,
                    didFail: didFail
                ) {
                    self.isPerforming = false
                    self.scheduleRestore(snapshot: saved, changeCount: changeCount)
                }
            }
        }
        return true
    }

    private func scheduleRestore(snapshot: [NSPasteboardItem], changeCount: Int) {
        // Handed to the pasteboard lane, which alone reads it.
        nonisolated(unsafe) let snapshot = snapshot
        let general = environment.pasteboard
        let work = DispatchWorkItem { [weak self] in
            // Run by the main queue below.
            MainActor.assumeIsolated {
                guard let self else { return }
                self.restoreWork = nil
                self.pendingRestore = nil
                self.environment.lane.async {
                    let pasteboard = general()
                    guard pasteboard.changeCount == changeCount else { return }
                    pasteboard.clearContents()
                    if !snapshot.isEmpty { pasteboard.writeObjects(snapshot) }
                    let restoredCount = pasteboard.changeCount
                    DispatchQueue.main.async {
                        self.environment.ignoreHistory(restoredCount)
                    }
                }
            }
        }
        restoreWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + Self.restoreDelay, execute: work)
    }

    /// Nil means at least one advertised flavor could not be preserved, so the
    /// transient paste fails open instead of clearing incomplete user data.
    nonisolated private static func snapshot(of pasteboard: NSPasteboard) -> [NSPasteboardItem]? {
        guard let items = pasteboard.pasteboardItems else {
            return pasteboard.types?.isEmpty == false ? nil : []
        }
        var snapshot: [NSPasteboardItem] = []
        for item in items {
            let copy = NSPasteboardItem()
            for type in item.types {
                guard let data = item.data(forType: type) else { return nil }
                copy.setData(data, forType: type)
            }
            snapshot.append(copy)
        }
        return snapshot
    }

    private func postPasteWhenModifiersReleased(attempt: Int,
                                                       expectedChangeCount: Int,
                                                       willPost: (() -> Void)?,
                                                       didPost: (() -> Void)?,
                                                       didFail: (() -> Void)?,
                                                       completion: @escaping () -> Void) {
        let held = environment.heldModifiers()
            .intersection([.maskCommand, .maskAlternate, .maskShift, .maskControl])
        if held.isEmpty || attempt >= 100 {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.06) {
                // A copy made while waiting belongs to the user, not this
                // operation. Do not paste it or delete a snippet's trigger.
                // Read on the shared lane: pboard can block even for its count.
                let pasteboard = self.environment.pasteboard
                self.environment.lane.async({
                    pasteboard().changeCount == expectedChangeCount
                }) { isCurrent in
                    guard isCurrent else {
                        didFail?()
                        completion()
                        return
                    }
                    self.postPasteShortcut(willPost: willPost) { succeeded in
                        if succeeded {
                            didPost?()
                        } else {
                            didFail?()
                        }
                        completion()
                    }
                }
            }
            return
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.015) {
            self.postPasteWhenModifiersReleased(attempt: attempt + 1,
                                           expectedChangeCount: expectedChangeCount,
                                           willPost: willPost,
                                           didPost: didPost,
                                           didFail: didFail,
                                           completion: completion)
        }
    }

    private func postPasteShortcut(willPost: (() -> Void)?,
                                   completion: @escaping (Bool) -> Void) {
        guard let keys = environment.commandV() else {
            completion(false)
            return
        }
        willPost?()
        keys.down()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.04) {
            keys.up()
            completion(true)
        }
    }
}
