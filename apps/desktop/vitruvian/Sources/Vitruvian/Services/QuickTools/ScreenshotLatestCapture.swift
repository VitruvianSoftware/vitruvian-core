// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 VitruvianSoftware

import Foundation
import VitruvianCore
import VitruvianDesign

/// The latest capture and what may publish it through the upload shortcut:
/// the editors open, the shortcut's pending upload and a link whose copy
/// failed. A newer capture, an editor or a discard takes the claim away.
/// `ScreenshotService` owns one; tests pass doubles through `Host`.
@MainActor
package final class ScreenshotLatestCapture<Capture, Editor: AnyObject> {
    /// What the latest capture asks of the screenshot service and the system.
    @MainActor
    package struct Host {
        /// The settings that turn the shortcut on and keep the capture.
        package var defaults: UserDefaults
        package var isAvailable: () -> Bool
        /// Asks the open preview to share its own capture; false without one.
        package var sharePreview: () -> Bool
        /// The capture kept for the shortcuts, and keeping or forgetting it.
        package var stored: () -> Capture?
        package var store: (Capture) -> Void
        package var forget: () -> Void
        /// Whether the kept capture was discarded or edited, which the store
        /// remembers for the next launch, and marking it so.
        package var storedWithheld: () -> Bool
        package var withholdStored: () -> Void
        package var share: (Capture, ScreenshotShareDuration,
                            @escaping @MainActor (ScreenshotShareRecord?) -> Void) -> Void
        package var links: ScreenshotLinkActions
        package var strings: () -> ScreenshotFeatureStrings

        // Spelled out because a memberwise initializer never leaves its module.
        package init(defaults: UserDefaults, isAvailable: @escaping () -> Bool,
                     sharePreview: @escaping () -> Bool, stored: @escaping () -> Capture?,
                     store: @escaping (Capture) -> Void, forget: @escaping () -> Void,
                     storedWithheld: @escaping () -> Bool, withholdStored: @escaping () -> Void,
                     share: @escaping (Capture, ScreenshotShareDuration,
                                       @escaping @MainActor (ScreenshotShareRecord?) -> Void) -> Void,
                     links: ScreenshotLinkActions, strings: @escaping () -> ScreenshotFeatureStrings) {
            self.defaults = defaults
            self.isAvailable = isAvailable
            self.sharePreview = sharePreview
            self.stored = stored
            self.store = store
            self.forget = forget
            self.storedWithheld = storedWithheld
            self.withholdStored = withholdStored
            self.share = share
            self.links = links
            self.strings = strings
        }
    }

    package private(set) var editors: [Editor] = []
    /// Names the latest capture's claim on the upload shortcut. A pending
    /// upload keeps the one it began for.
    package private(set) var id = UUID()
    /// Names the latest capture itself. Turning the shortcut off renews `id`
    /// but not this, so a later Discard still finds it.
    package private(set) var token = UUID()
    package private(set) var uploadingID: UUID?
    /// Set once the latest capture went through an editor or was discarded:
    /// the stored original is then no longer what the person kept. The store
    /// keeps the same answer for the next launch.
    private var withheld = false
    private var copyRetry = ScreenshotLinkCopyRetry()
    private let host: Host

    package init(host: Host) {
        self.host = host
    }

    /// A new capture becomes the latest one: a pending shortcut upload of the
    /// one before loses its claim, and the new one is kept, untouched so far,
    /// for the shortcuts that reopen or upload it.
    package func begin(_ capture: Capture) {
        invalidate()
        token = UUID()
        withheld = false
        if ScreenshotSharingSupport.retainsLatestCapture(in: host.defaults) {
            host.store(capture)
        }
    }

    /// Thrown away, the latest capture is no longer one the upload shortcut
    /// may publish. A capture reopened from history makes no such claim.
    package func discard(_ latestCapture: UUID?) {
        guard let latestCapture, latestCapture == token else { return }
        withhold()
    }

    private func withhold() {
        withheld = true
        host.withholdStored()
    }

    /// A newer capture or turning the feature off ends the claim a pending
    /// shortcut upload has on the latest capture: its link is revoked when
    /// it arrives instead of being copied, and a failed copy is not retried.
    package func invalidate() {
        id = UUID()
        copyRetry.clear()
    }

    /// A capture no shortcut needs is not kept, and an upload still pending
    /// when its shortcut or temporary links were turned off revokes its link
    /// when it arrives instead of copying it.
    package func sync() {
        if !ScreenshotSharingSupport.uploadShortcutEnabled(in: host.defaults) {
            invalidate()
        }
        if !ScreenshotSharingSupport.retainsLatestCapture(in: host.defaults) {
            host.forget()
        }
    }

    /// The upload shortcut is registered only while it and temporary links
    /// are both on. Returns what the registration answered.
    package func registerShortcut(_ register: (_ enabled: Bool) -> Bool) -> Bool {
        register(ScreenshotSharingSupport.uploadShortcutEnabled(in: host.defaults))
    }

    /// Turning screenshots off. A pending shortcut upload loses its claim
    /// first, so its link is revoked when it arrives instead of being copied;
    /// then the preview and every editor showing a capture close.
    package func end(closingPreview: () -> Void, closingEditor: (Editor) -> Void) {
        invalidate()
        closingPreview()
        for editor in editors {
            closingEditor(editor)
        }
        removeAllEditors()
    }

    /// Any editor may be showing the latest capture, and what it exports is
    /// no longer the stored original, so the shortcut keeps that original
    /// back until a newer capture arrives.
    package func editorOpened(_ editor: Editor) {
        withhold()
        editors.append(editor)
    }

    /// Whether the editor was still open; a repeated close changes nothing.
    @discardableResult
    package func editorClosed(_ editor: Editor) -> Bool {
        guard editors.contains(where: { $0 === editor }) else { return false }
        editors.removeAll { $0 === editor }
        return true
    }

    package func removeAllEditors() {
        editors.removeAll()
    }

    /// The upload shortcut: the open preview shares its own capture;
    /// otherwise the kept latest capture is uploaded once, or its link copied
    /// again after a failed copy.
    package func upload() {
        guard host.isAvailable(),
              ScreenshotSharingSupport.uploadShortcutEnabled(in: host.defaults) else { return }
        if host.sharePreview() { return }
        guard editors.isEmpty, !withheld, !host.storedWithheld() else {
            host.links.beep()
            return
        }
        guard uploadingID != id else { return }
        if let record = copyRetry.record(for: id, availableRecords: host.links.records()) {
            copy(record, captureID: id)
            return
        }
        guard let capture = host.stored() else {
            host.links.announce("camera.viewfinder", host.strings().lastCaptureMissing)
            return
        }
        let captureID = id
        uploadingID = captureID
        host.links.announce("link", host.strings().sharingHUD)
        let delete = host.links.delete
        host.share(capture, .saved()) { [weak self] record in
            if self?.uploadingID == captureID { self?.uploadingID = nil }
            guard let record else { return }
            guard let self, self.id == captureID else {
                Task { @MainActor in try? await delete(record) }
                return
            }
            self.copy(record, captureID: captureID)
        }
    }

    private func copy(_ record: ScreenshotShareRecord, captureID: UUID) {
        let copied = ScreenshotSharingSupport.copyLink(record, using: host.links.copy, dismiss: {})
        if captureID == id {
            if copied {
                copyRetry.clear()
            } else {
                copyRetry.remember(record, for: captureID)
            }
        }
        host.links.announce("link", copied ? host.strings().sharedHUD : host.strings().linkCopyFailedHUD)
    }
}
