// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import CoreGraphics
import Foundation
import VitruvianCore
import VitruvianDesign
import VitruvianServices
import VitruvianUI

/// Runs the real quick preview and the real latest capture with controlled
/// uploads, links and clock. No network request, panel or clipboard write
/// happens.
enum ScreenshotShareCompletionTests {
    /// The sharing service, the HUD and the beep, recorded.
    final class Links {
        var records: [ScreenshotShareRecord] = []
        /// Every copy attempted, whether or not it landed.
        var copies: [URL] = []
        var clipboard = "new capture"
        var copySucceeds = true
        var revoked: [ScreenshotShareRecord] = []
        var announcements: [String] = []
        var beeps = 0

        var actions: ScreenshotLinkActions {
            ScreenshotLinkActions(
                records: { [unowned self] in records },
                copy: { [unowned self] url in
                    copies.append(url)
                    if copySucceeds { clipboard = url.absoluteString }
                    return copySucceeds
                },
                delete: { [unowned self] in revoked.append($0) },
                announce: { [unowned self] _, message in announcements.append(message) },
                beep: { [unowned self] in beeps += 1 })
        }
    }

    /// The preview's deferred work, run by hand.
    final class Clock {
        private var now: TimeInterval = 0
        private var pending: [(at: TimeInterval, work: DispatchWorkItem)] = []
        var delays: [TimeInterval] = []

        var scheduler: ScreenshotQuickPreviewController.Scheduler {
            .init(async: { work in work() },
                  after: { [unowned self] delay, work in
                      delays.append(delay)
                      pending.append((now + delay, work))
                  })
        }

        func advance(_ seconds: TimeInterval) {
            now += seconds
            let due = pending.filter { $0.at <= now }
            pending.removeAll { $0.at <= now }
            for item in due where !item.work.isCancelled { item.work.perform() }
        }
    }

    final class Editor {}

    static func capture() -> ScreenshotSelectionController.Capture {
        let context = CGContext(data: nil, width: 1, height: 1, bitsPerComponent: 8, bytesPerRow: 0,
                                space: CGColorSpaceCreateDeviceRGB(),
                                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        return .init(image: context.makeImage()!, scale: 1, anchorRect: .zero)
    }

    /// A preview that shares through `share` and reports its close.
    static func preview(links: Links, clock: Clock, dismissInterval: TimeInterval? = 12,
                        share: @escaping (ScreenshotShareDuration,
                                          @escaping @MainActor (ScreenshotShareRecord?) -> Void) -> Void,
                        onClose: @escaping () -> Void) -> ScreenshotQuickPreviewController {
        ScreenshotQuickPreviewController(capture: capture(), strings: .enUS, defaultAction: .none,
                                         completedActions: [], dismissInterval: dismissInterval,
                                         action: { _ in [] }, share: share, shareFile: { nil },
                                         onClose: onClose, scheduler: clock.scheduler, links: links.actions)
    }

    /// One preview and the upload it started, for the preview's own checks.
    final class Sharing {
        let clock = Clock()
        var completion: (@MainActor (ScreenshotShareRecord?) -> Void)?
        var closes = 0
        var closed: Bool { closes > 0 }
        var preview: ScreenshotQuickPreviewController?

        init(_ links: Links) {
            preview = ScreenshotShareCompletionTests.preview(
                links: links, clock: clock,
                share: { [weak self] _, completion in self?.completion = completion },
                onClose: { [weak self] in self?.closes += 1 })
        }
    }

    /// The screenshot service's side of the latest capture: the kept capture
    /// is a number, editors are plain objects and uploads are recorded.
    final class Uploader {
        let links: Links
        let clock = Clock()
        let defaultsName = "vitru.tests.screenshot-shortcut.\(UUID().uuidString)"
        let defaults: UserDefaults
        var stored: Int? = 1
        var preview: ScreenshotQuickPreviewController?
        var completion: (@MainActor (ScreenshotShareRecord?) -> Void)?
        var uploads = 0
        var uploadedCaptures: [Int] = []
        lazy var latest: ScreenshotLatestCapture<Int, Editor> = ScreenshotLatestCapture(host: .init(
            defaults: defaults,
            isAvailable: { true },
            sharePreview: { [unowned self] in
                guard let preview else { return false }
                preview.shareLink()
                return true
            },
            stored: { [unowned self] in stored },
            store: { [unowned self] in stored = $0 },
            forget: { [unowned self] in stored = nil },
            share: { [unowned self] capture, _, completion in shareDirect(capture, completion: completion) },
            links: links.actions,
            strings: { .enUS }))

        init(_ links: Links) {
            self.links = links
            defaults = UserDefaults(suiteName: defaultsName)!
            defaults.set(true, forKey: DefaultsKey.screenshotUploadShortcutEnabled)
            defaults.set(true, forKey: DefaultsKey.screenshotSharingEnabled)
        }
        deinit {
            UserDefaults(suiteName: defaultsName)?.removePersistentDomain(forName: defaultsName)
        }

        func shareDirect(_ capture: Int, completion: @escaping @MainActor (ScreenshotShareRecord?) -> Void) {
            uploads += 1
            uploadedCaptures.append(capture)
            self.completion = completion
        }

        /// A preview of `capture` that shares it through this uploader.
        @discardableResult
        func showPreview(capture: Int = 1, dismissInterval: TimeInterval? = 12) -> ScreenshotQuickPreviewController {
            let controller = ScreenshotShareCompletionTests.preview(
                links: links, clock: clock, dismissInterval: dismissInterval,
                share: { [weak self] _, completion in self?.shareDirect(capture, completion: completion) },
                onClose: { [weak self] in self?.preview = nil })
            preview = controller
            return controller
        }

        func openEditor() -> Editor {
            let editor = Editor()
            latest.editorOpened(editor)
            return editor
        }
    }

    static func run(_ suite: TestSuite) {
        var finished = false
        Task { @MainActor in
            await checks(suite)
            finished = true
        }
        let deadline = Date().addingTimeInterval(10)
        while !finished && Date() < deadline {
            RunLoop.main.run(until: Date().addingTimeInterval(0.005))
        }
        suite.expect(finished, "screenshot upload completion tests finish")
    }

    static func settle() async {
        for _ in 0..<20 { await Task.yield() }
    }

    static let record = ScreenshotShareRecord(id: "test", endpoint: URL(string: "https://example.com")!,
                                              expiresAt: Date().addingTimeInterval(3_600), deleteToken: "test")

    static func checks(_ suite: TestSuite) async {
        await previewCompletion(suite)
        await shortcutCompletion(suite)
        await retries(suite)
        dismissal(suite)
        editorsAndDiscards(suite)
        retention(suite)
    }

    private static func previewCompletion(_ suite: TestSuite) async {
        let links = Links()
        let open = Sharing(links)
        open.preview?.shareLink()
        suite.expect(open.preview?.model.sharing == true, "sharing shows progress until the upload answers")
        open.completion?(record)
        suite.expect(links.copies == [record.url] && open.closed && open.preview?.model.sharing == false,
                     "upload completion copies and closes before returning, without a deferred handoff")
        suite.expect(links.announcements == [ScreenshotFeatureStrings.enUS.sharedHUD],
                     "a copied link is announced")
        await settle()
        suite.expect(links.revoked.isEmpty, "a delivered link stays active")

        let closingAfterCallback = Sharing(links)
        links.copies = []
        closingAfterCallback.preview?.shareLink()
        closingAfterCallback.completion?(record)
        closingAfterCallback.preview?.close()
        await settle()
        suite.expect(links.copies == [record.url] || links.revoked == [record],
                     "closing immediately after the callback cannot leave a link neither delivered nor revoked")
        suite.expect(closingAfterCallback.closes == 1, "closing a closed preview does nothing")

        links.copies = []
        links.revoked = []
        let closed = Sharing(links)
        closed.preview?.shareLink()
        closed.preview?.close()
        closed.completion?(record)
        await settle()
        suite.expect(links.revoked == [record] && links.copies.isEmpty,
                     "closing before upload completion revokes the link without copying it")

        links.revoked = []
        let released = Sharing(links)
        released.preview?.shareLink()
        let completion = released.completion
        released.preview = nil
        completion?(record)
        await settle()
        suite.expect(links.revoked == [record], "releasing the preview also revokes an undelivered link")

        links.revoked = []
        links.copySucceeds = false
        let failedCopy = Sharing(links)
        failedCopy.preview?.shareLink()
        failedCopy.completion?(record)
        suite.expect(!failedCopy.closed && failedCopy.preview?.model.sharedRecord == record
                     && links.beeps == 1,
                     "clipboard failure retains the existing link and copy controls in the preview")
        suite.expect(failedCopy.clock.delays.last == ScreenshotSupport.sharedPreviewDismissInterval(base: 12),
                     "a preview showing its link waits the longer shared-link time")
        let scheduled = failedCopy.clock.delays.count
        failedCopy.preview?.shareLink()
        await settle()
        suite.expect(!failedCopy.closed && failedCopy.clock.delays.count == scheduled + 1,
                     "a copy that fails again keeps the preview and its dismissal")
        links.copySucceeds = true
        failedCopy.preview?.shareLink()
        await settle()
        suite.expect(failedCopy.closed && links.copies == [record.url, record.url, record.url],
                     "pressing share again copies the link already made instead of uploading again")

        let waiting = Sharing(links)
        waiting.preview?.shareLink()
        waiting.preview?.scheduleAutoDismiss()
        waiting.clock.advance(60)
        suite.expect(!waiting.closed && waiting.clock.delays.isEmpty,
                     "a pointer leaving a sharing preview cannot dismiss it before the link arrives")

        let failedUpload = Sharing(links)
        failedUpload.preview?.shareLink()
        failedUpload.completion?(nil)
        suite.expect(!failedUpload.closed && failedUpload.preview?.model.sharing == false
                     && failedUpload.clock.delays == [12],
                     "a failed upload leaves the preview open and dismisses it on its usual clock")
    }

    private static func shortcutCompletion(_ suite: TestSuite) async {
        let links = Links()
        for scenario in ["open", "closed", "released", "replaced", "standalone", "standalone replaced",
                         "history opened", "owner released", "feature off", "links off"] {
            links.revoked = []
            links.copies = []
            links.clipboard = "new capture"
            var uploader: Uploader? = Uploader(links)
            var preview: ScreenshotQuickPreviewController? = ["standalone", "standalone replaced", "history opened",
                                                              "feature off", "links off"].contains(scenario)
                ? nil : uploader!.showPreview()
            uploader!.latest.upload()
            uploader!.latest.upload()
            suite.expect(uploader!.uploads == 1, "pending shortcut upload ignores duplicate presses")
            let completion = uploader!.completion
            if ["closed", "released", "replaced"].contains(scenario) { preview?.close() }
            if scenario == "released" { preview = nil }
            if scenario == "replaced" || scenario == "standalone replaced" {
                uploader!.latest.begin(2)
                uploader!.showPreview()
            }
            if scenario == "history opened" { uploader!.showPreview(capture: 2) }
            if scenario == "feature off" { uploader!.latest.invalidate() }
            if scenario == "links off" {
                uploader!.defaults.set(false, forKey: DefaultsKey.screenshotSharingEnabled)
                uploader!.latest.sync()
            }
            if scenario == "owner released" { preview = nil; uploader = nil }
            completion?(record)
            await settle()
            if ["open", "standalone", "history opened"].contains(scenario) {
                suite.expect(links.copies == [record.url] && links.revoked.isEmpty,
                             "\(scenario) shortcut upload delivers its link")
                if scenario == "open" {
                    suite.expect(uploader?.preview == nil, "successful shortcut copy closes its preview")
                }
            } else {
                suite.expect(links.copies.isEmpty && links.clipboard == "new capture"
                             && links.revoked == [record],
                             "\(scenario) shortcut upload should revoke and preserve clipboard; "
                             + "copies=\(links.copies.count), revoked=\(links.revoked.count), "
                             + "clipboard=\(links.clipboard)")
            }
            if scenario == "history opened" {
                suite.expect(uploader?.preview != nil, "standalone upload leaves a later history preview open")
            }
            if let uploader {
                suite.expect(uploader.latest.uploadingID == nil, "completion clears pending shortcut upload")
            }
        }

        let announced = Uploader(links)
        announced.latest.upload()
        suite.expect(links.announcements.last == ScreenshotFeatureStrings.enUS.sharingHUD,
                     "a shortcut upload says it started")
        let missing = Uploader(links)
        missing.stored = nil
        missing.latest.upload()
        suite.expect(missing.uploads == 0
                     && links.announcements.last == ScreenshotFeatureStrings.enUS.lastCaptureMissing,
                     "a press with no kept capture says so instead of uploading")
        let off = Uploader(links)
        off.defaults.set(false, forKey: DefaultsKey.screenshotUploadShortcutEnabled)
        off.showPreview()
        off.latest.upload()
        suite.expect(off.uploads == 0 && off.preview?.model.sharing == false,
                     "with the upload shortcut off a press does nothing, even over a preview")

        let failedUpload = Uploader(links)
        failedUpload.latest.upload()
        failedUpload.completion?(nil)
        suite.expect(failedUpload.latest.uploadingID == nil, "failed upload clears pending shortcut state")

        let deleting = Uploader(links)
        let deletingPreview = deleting.showPreview()
        deletingPreview.model.sharedRecord = record
        deletingPreview.model.deletingShare = true
        links.copies = []
        deleting.latest.upload()
        await settle()
        suite.expect(links.copies.isEmpty && deleting.uploads == 0,
                     "shortcut cannot copy or upload while the preview deletes its link")

        let stale = Uploader(links)
        stale.latest.upload()
        stale.latest.begin(11)
        stale.latest.upload()
        suite.expect(stale.uploads == 2 && stale.uploadedCaptures == [1, 11],
                     "a press for a newer capture starts its own upload while an older one is still pending")
    }

    private static func retries(_ suite: TestSuite) async {
        let links = Links()
        links.records = [record]
        links.copySucceeds = false
        let retry = Uploader(links)
        let retryPreview = retry.showPreview()
        retry.latest.upload()
        retry.completion?(record)
        suite.expect(retry.preview === retryPreview, "failed shortcut copy keeps its preview open")
        links.copySucceeds = true
        retry.latest.upload()
        await settle()
        suite.expect(retry.uploads == 1 && links.copies == [record.url, record.url] && retry.preview == nil,
                     "shortcut retries a failed copy without another upload")

        links.copies = []
        links.copySucceeds = false
        let teardownRetry = Uploader(links)
        teardownRetry.latest.upload()
        teardownRetry.completion?(record)
        suite.expect(links.announcements.last == ScreenshotFeatureStrings.enUS.linkCopyFailedHUD,
                     "a failed copy says so")
        teardownRetry.latest.invalidate()
        links.copySucceeds = true
        teardownRetry.latest.upload()
        suite.expect(teardownRetry.uploads == 2 && links.copies == [record.url],
                     "feature teardown drops a pending copy retry instead of copying the old link")

        links.copies = []
        links.copySucceeds = false
        let standaloneRetry = Uploader(links)
        standaloneRetry.latest.upload()
        standaloneRetry.completion?(record)
        links.copySucceeds = true
        standaloneRetry.latest.upload()
        suite.expect(standaloneRetry.uploads == 1 && links.copies == [record.url, record.url],
                     "standalone shortcut retries copying its existing link without uploading again")
        standaloneRetry.latest.upload()
        suite.expect(standaloneRetry.uploads == 2,
                     "a link copied at last is not copied again; the next press uploads afresh")

        links.copies = []
        links.copySucceeds = false
        let expired = Uploader(links)
        expired.latest.upload()
        expired.completion?(record)
        links.records = []
        links.copySucceeds = true
        expired.latest.upload()
        suite.expect(expired.uploads == 2 && links.copies == [record.url],
                     "a link the service no longer lists is uploaded again instead of copied")
    }

    private static func dismissal(_ suite: TestSuite) {
        let links = Links()
        for duration in [3.0, 12.0] {
            let history = Uploader(links)
            let historyPreview = history.showPreview(capture: 2, dismissInterval: duration)
            historyPreview.scheduleAutoDismiss()
            history.latest.upload()
            history.clock.advance(duration + 1)
            suite.expect(history.preview != nil && historyPreview.model.sharing,
                         "shortcut upload keeps preview open past its dismissal deadline")
            suite.expect(history.uploadedCaptures == [2], "shortcut uploads the visible history capture")
            history.completion?(record)
            suite.expect(history.preview == nil, "history upload copies and closes its own preview")
        }
        let idle = Uploader(links)
        idle.showPreview(dismissInterval: 3)
        idle.preview?.scheduleAutoDismiss()
        idle.clock.advance(4)
        suite.expect(idle.preview == nil, "an untouched preview dismisses itself on time")

        let editingWithHistory = Uploader(links)
        _ = editingWithHistory.openEditor()
        editingWithHistory.showPreview(capture: 2)
        editingWithHistory.latest.upload()
        suite.expect(editingWithHistory.uploadedCaptures == [2],
                     "an open history preview still uploads its own visible capture")
    }

    private static func editorsAndDiscards(_ suite: TestSuite) {
        let links = Links()
        links.records = [record]
        let editing = Uploader(links)
        links.copySucceeds = false
        editing.latest.upload()
        editing.completion?(record)
        links.copySucceeds = true
        links.copies = []
        let first = editing.openEditor()
        _ = editing.openEditor()
        suite.expect(editing.latest.editors.count == 2, "editors are tracked when shown")
        editing.latest.upload()
        suite.expect(editing.uploads == 1 && links.copies.isEmpty,
                     "shortcut never uploads or copies the stored original while its editor is open")
        suite.expect(links.beeps == 1, "blocked cached-link press beeps")
        suite.expect(editing.latest.editorClosed(first) && !editing.latest.editorClosed(first)
                     && editing.latest.editors.count == 1,
                     "duplicate close preserves the remaining editor")
        editing.latest.begin(3)
        editing.latest.upload()
        suite.expect(editing.uploads == 1 && links.beeps == 2,
                     "remaining editor blocks upload even after a newer capture")
        editing.latest.editorClosed(editing.latest.editors[0])
        editing.latest.upload()
        suite.expect(editing.uploads == 2 && editing.uploadedCaptures == [1, 3] && links.beeps == 2,
                     "a capture taken after those editors opened uploads once the last one closes")

        // What an editor exported is no longer the stored original, so that
        // original stays back after the editor closes, and so does a
        // discarded capture, until a newer capture arrives.
        let edited = Uploader(links)
        edited.latest.begin(4)
        edited.latest.editorClosed(edited.openEditor())
        edited.latest.upload()
        suite.expect(edited.uploads == 0 && links.beeps == 3,
                     "a capture that went through an editor is not published as its stored original after the editor closes")
        edited.latest.begin(5)
        edited.latest.upload()
        suite.expect(edited.uploads == 1 && edited.uploadedCaptures == [5],
                     "a newer capture can be uploaded again")
        let discarded = Uploader(links)
        discarded.latest.begin(6)
        discarded.latest.discard(UUID())
        discarded.latest.discard(nil)
        discarded.latest.upload()
        suite.expect(discarded.uploads == 1,
                     "discarding an older capture or one reopened from history leaves the latest one shareable")
        let discardedLatest = Uploader(links)
        discardedLatest.latest.begin(7)
        discardedLatest.latest.discard(discardedLatest.latest.id)
        discardedLatest.latest.upload()
        suite.expect(discardedLatest.uploads == 0 && links.beeps == 4,
                     "a discarded latest capture is not published")
        let emptied = Uploader(links)
        _ = emptied.openEditor()
        emptied.latest.removeAllEditors()
        emptied.latest.begin(8)
        emptied.latest.upload()
        suite.expect(emptied.latest.editors.isEmpty && emptied.uploads == 1,
                     "closing every editor at teardown leaves none to block the shortcut")
    }

    /// The capture is kept for whichever shortcut uses it, and only then.
    private static func retention(_ suite: TestSuite) {
        let retention = Uploader(Links())
        retention.stored = nil
        retention.latest.begin(8)
        retention.latest.sync()
        suite.expect(retention.stored == 8, "the upload shortcut alone keeps the latest capture for itself")
        retention.defaults.set(false, forKey: DefaultsKey.screenshotUploadShortcutEnabled)
        retention.latest.sync()
        retention.latest.begin(9)
        suite.expect(retention.stored == nil,
                     "with neither shortcut on the latest capture is cleared and no longer kept")
        retention.defaults.set(true, forKey: DefaultsKey.screenshotLastCaptureShortcutEnabled)
        retention.latest.begin(10)
        retention.latest.sync()
        suite.expect(retention.stored == 10, "edit latest screenshot alone still keeps the latest capture")
    }
}
