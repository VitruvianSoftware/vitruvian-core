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
    // Snippet expansion asks for it from plain code, and is refused off the main thread.
    nonisolated package static let shared = TransientPaste()

    nonisolated private init() {}

    private static let restoreDelay: TimeInterval = 0.5

    private var pendingRestore: (snapshot: [NSPasteboardItem], changeCount: Int)?
    private var restoreWork: DispatchWorkItem?
    private var isPerforming = false

    /// Main thread only: a call from anywhere else is refused.
    @discardableResult
    nonisolated package func paste(_ text: String,
               willPostShortcut: (() -> Void)? = nil,
               didPostShortcut: (() -> Void)? = nil,
               didFail: (() -> Void)? = nil) -> Bool {
        guard Thread.isMainThread else { return false }
        // Checked just above.
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

        GeneralPasteboardAccess.shared.async {
            let pasteboard = NSPasteboard.general
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
                ClipboardHistoryService.shared.ignoreNextChange(upTo: changeCount)
                self.pendingRestore = (saved, changeCount)
                Self.postPasteWhenModifiersReleased(
                    attempt: 0,
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
        let work = DispatchWorkItem { [weak self] in
            // Run by the main queue below.
            MainActor.assumeIsolated {
                guard let self else { return }
                self.restoreWork = nil
                self.pendingRestore = nil
                GeneralPasteboardAccess.shared.async {
                    let pasteboard = NSPasteboard.general
                    guard pasteboard.changeCount == changeCount else { return }
                    pasteboard.clearContents()
                    if !snapshot.isEmpty { pasteboard.writeObjects(snapshot) }
                    let restoredCount = pasteboard.changeCount
                    DispatchQueue.main.async {
                        ClipboardHistoryService.shared.ignoreNextChange(upTo: restoredCount)
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

    private static func postPasteWhenModifiersReleased(attempt: Int,
                                                       willPost: (() -> Void)?,
                                                       didPost: (() -> Void)?,
                                                       didFail: (() -> Void)?,
                                                       completion: @escaping () -> Void) {
        let held = CGEventSource.flagsState(.combinedSessionState)
            .intersection([.maskCommand, .maskAlternate, .maskShift, .maskControl])
        if held.isEmpty || attempt >= 100 {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.06) {
                postPasteShortcut(willPost: willPost) { succeeded in
                    if succeeded {
                        didPost?()
                    } else {
                        didFail?()
                    }
                    completion()
                }
            }
            return
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.015) {
            postPasteWhenModifiersReleased(attempt: attempt + 1,
                                           willPost: willPost,
                                           didPost: didPost,
                                           didFail: didFail,
                                           completion: completion)
        }
    }

    private static func postPasteShortcut(willPost: (() -> Void)?,
                                          completion: @escaping (Bool) -> Void) {
        guard let keyDown = CGEvent(keyboardEventSource: nil,
                                    virtualKey: CGKeyCode(kVK_ANSI_V),
                                    keyDown: true),
              let keyUp = CGEvent(keyboardEventSource: nil,
                                  virtualKey: CGKeyCode(kVK_ANSI_V),
                                  keyDown: false)
        else {
            completion(false)
            return
        }
        keyDown.flags = .maskCommand
        keyUp.flags = .maskCommand
        willPost?()
        keyDown.post(tap: .cghidEventTap)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.04) {
            keyUp.post(tap: .cghidEventTap)
            completion(true)
        }
    }
}
