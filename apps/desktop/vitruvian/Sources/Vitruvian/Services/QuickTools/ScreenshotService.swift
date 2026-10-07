// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import AppKit
import ImageIO
import UniformTypeIdentifiers
import VitruvianCore
import VitruvianDesign

/// The screenshot tool: freeze-first area, window and full screen capture
/// with an annotation editor, pinned floating captures and direct clipboard
/// or file output. Purely on demand and needs Screen Recording, requested
/// contextually on first use. The shared screen-capture service owns the
/// general shortcut and hands completed pictures back here.
@MainActor
package final class ScreenshotService: ObservableObject {
    package static let shared = ScreenshotService()

    @Published package private(set) var fullScreenShortcutRegistrationFailed = false
    @Published package private(set) var lastCaptureShortcutRegistrationFailed = false
    @Published package private(set) var clipboardShortcutRegistrationFailed = false

    @Published package private(set) var uploadShortcutRegistrationFailed = false
    private let uploadHotkey = QuickToolHotkey(id: 61)
    private lazy var latest: ScreenshotLatestCapture<ScreenshotSelectionController.Capture,
                                                     ScreenshotEditorController> = ScreenshotLatestCapture(host: .init(
        defaults: .standard,
        isAvailable: { AppFeature.screenshot.isAvailable },
        sharePreview: { [weak self] in
            guard let preview = self?.preview else { return false }
            preview.shareLink()
            return true
        },
        stored: { ScreenshotLastCaptureStore.load() },
        store: { ScreenshotLastCaptureStore.save($0) },
        forget: { ScreenshotLastCaptureStore.clear() },
        storedWithheld: { ScreenshotLastCaptureStore.isWithheld },
        withholdStored: { ScreenshotLastCaptureStore.withhold() },
        share: { [weak self] capture, duration, completion in
            self?.shareDirect(capture, duration: duration, completion: completion)
        },
        links: .live,
        strings: { FeatureStrings.screenshot(L10n.shared.language) }))

    private let lastCaptureHotkey = QuickToolHotkey(id: 22)
    private let fullScreenHotkey = QuickToolHotkey(id: 23)
    private let clipboardHotkey = QuickToolHotkey(id: 24)
    private var session: ScreenshotSelectionController?
    private var preview: ScreenshotQuickPreviewController?
    private var countdown: DispatchWorkItem?
    private var countdownRemaining = 0
    private var countdownMode: CaptureMode = .standard
    private var directCaptureTask: Task<Void, Never>?
    private var autoCopyTask: Task<Void, Never>?
    private var autoCopyGeneration = 0
    private var scrollingTask: Task<Void, Never>?
    private var scrollingCaptureID: UUID?
    private var scrollingFinishSignal: ScreenshotScrollingCapture.FinishSignal?

    private enum CaptureMode {
        case standard
        case fullScreen
        case scrolling
    }

    private var hideVitruvianWindows: Bool {
        UserDefaults.standard[Preferences.screenshotHideVitruvianWindows]
    }

    /// The surfaces that make up the act of capturing. The quick preview is
    /// here rather than with the content windows because it dismisses itself
    /// after a few seconds: back-to-back captures would otherwise photograph
    /// the previous capture's toast.
    private var workflowWindowIDs: Set<CGWindowID> {
        var ids = session?.protectedWindowIDs ?? []
        if NotchSupport.isEnabled() { ids.formUnion(NotchService.shared.protectedWindowIDs) }
        ids.formUnion(preview?.protectedWindowIDs ?? [])
        ids.formUnion(ScreenCaptureService.shared.protectedWindowIDs)
        if let number = QuickToolHUD.currentWindowNumber, number > 0 {
            ids.insert(CGWindowID(number))
        }
        if let number = QuickToolHUD.currentScrollingWindowNumber, number > 0 {
            ids.insert(CGWindowID(number))
        }
        return ids
    }

    /// Ordinary windows somebody left on screen, which the "Hide Vitruvian
    /// windows" preference owns.
    private var contentWindowIDs: Set<CGWindowID> {
        var ids: Set<CGWindowID> = []
        for editor in latest.editors {
            ids.formUnion(editor.protectedWindowIDs)
        }
        ids.formUnion(ScreenshotPinController.shared.protectedWindowIDs)
        return ids
    }

    private var protectedWindowIDs: Set<CGWindowID> {
        protectedWindowIDsForCapture(honoursVisibilityPreference: true)
    }

    package func protectedWindowIDsForCapture(honoursVisibilityPreference: Bool) -> Set<CGWindowID> {
        ScreenshotCapturePolicy.protectedWindowIDs(
            workflowWindowIDs: workflowWindowIDs,
            contentWindowIDs: contentWindowIDs,
            honoursVisibilityPreference: honoursVisibilityPreference)
    }

    private var strings: ScreenshotFeatureStrings {
        FeatureStrings.screenshot(L10n.shared.language)
    }

    private init() {
        DispatchQueue.global(qos: .utility).async {
            ScreenshotSupport.removeTemporaryDragDirectories()
        }
        fullScreenHotkey.onPress = { [weak self] in self?.captureFullScreen() }
        lastCaptureHotkey.onPress = { [weak self] in self?.openLastCapture() }
        uploadHotkey.onPress = { [weak self] in
            Task { @MainActor [weak self] in self?.latest.upload() }
        }
        clipboardHotkey.onPress = { [weak self] in self?.openClipboardImage() }
    }

    package func syncWithPreferences() {
        guard AppFeature.screenshot.isAvailable else {
            fullScreenShortcutRegistrationFailed = false
            lastCaptureShortcutRegistrationFailed = false
            clipboardShortcutRegistrationFailed = false
            uploadShortcutRegistrationFailed = false
            fullScreenHotkey.unregister()
            lastCaptureHotkey.unregister()
            clipboardHotkey.unregister()
            uploadHotkey.unregister()
            ScreenshotLastCaptureStore.clear()
            teardownSurfaces()
            return
        }
        let defaults = UserDefaults.standard
        let fullScreenEnabled = defaults[Preferences.screenshotFullScreenShortcutEnabled]
        let fullScreenShortcut = GlobalShortcut.saved(
            for: DefaultsKey.screenshotFullScreenShortcut,
            fallback: .screenshotFullScreenDefault)
        fullScreenShortcutRegistrationFailed = !fullScreenHotkey.sync(
            enabled: fullScreenEnabled,
            shortcut: fullScreenShortcut,
            storageKey: DefaultsKey.screenshotFullScreenShortcut)
        let lastCaptureEnabled = defaults[Preferences.screenshotLastCaptureShortcutEnabled]
        let lastCaptureShortcut = GlobalShortcut.saved(
            for: DefaultsKey.screenshotLastCaptureShortcut,
            fallback: .screenshotLastCaptureDefault)
        lastCaptureShortcutRegistrationFailed = !lastCaptureHotkey.sync(
            enabled: lastCaptureEnabled,
            shortcut: lastCaptureShortcut,
            storageKey: DefaultsKey.screenshotLastCaptureShortcut)
        let clipboardEnabled = defaults[Preferences.screenshotClipboardShortcutEnabled]
        let clipboardShortcut = GlobalShortcut.saved(
            for: DefaultsKey.screenshotClipboardShortcut,
            fallback: .screenshotClipboardDefault)
        clipboardShortcutRegistrationFailed = !clipboardHotkey.sync(
            enabled: clipboardEnabled,
            shortcut: clipboardShortcut,
            storageKey: DefaultsKey.screenshotClipboardShortcut)
        uploadShortcutRegistrationFailed = !latest.registerShortcut { enabled in
            uploadHotkey.sync(
                enabled: enabled,
                shortcut: GlobalShortcut.saved(for: DefaultsKey.screenshotUploadShortcut,
                                               fallback: .screenshotUploadDefault),
                storageKey: DefaultsKey.screenshotUploadShortcut)
        }
        latest.sync()
    }

    package func suspend() {
        fullScreenHotkey.unregister()
        lastCaptureHotkey.unregister()
        clipboardHotkey.unregister()
        uploadHotkey.unregister()
    }

    /// Hub-off means gone: open editors, pins and a selection in progress
    /// all leave the screen.
    private func teardownSurfaces() {
        countdown?.cancel()
        countdown = nil
        directCaptureTask?.cancel()
        directCaptureTask = nil
        autoCopyTask?.cancel()
        autoCopyTask = nil
        autoCopyGeneration += 1
        scrollingTask?.cancel()
        scrollingTask = nil
        scrollingCaptureID = nil
        scrollingFinishSignal = nil
        QuickToolHUD.dismissScrollingCapture()
        session?.cancel()
        session = nil
        latest.end(closingPreview: {
            preview?.close()
            preview = nil
        }, closingEditor: { $0.close() })
        ScreenshotPinController.shared.closeAll()
    }

    // MARK: - Entry

    /// Starts a capture; pressing the shortcut again while a countdown runs
    /// cancels it, and a session in progress is left alone.
    package func capture() {
        ScreenCaptureService.shared.capture(initial: .screenshot)
    }

    package func captureScrolling() {
        startCapture(.scrolling)
    }

    package func captureFullScreen() {
        startCapture(.fullScreen)
    }

    private func startCapture(_ mode: CaptureMode) {
        // Repeating the same action finishes a long capture at the current
        // point. It can never open a second selection or capture task.
        if scrollingTask != nil {
            QuickToolHUD.markScrollingCaptureFinishing()
            scrollingFinishSignal?.request()
            return
        }
        // Another feature may already own the capture surface (copying text
        // off the screen picks an area the same way).
        guard session == nil, directCaptureTask == nil,
              !ScreenshotSelectionController.isSessionOnScreen else { return }
        if countdown != nil {
            countdown?.cancel()
            countdown = nil
            return
        }
        guard Permissions.shared.screenRecording else {
            Permissions.shared.requestScreenRecording()
            return
        }
        let delay = ScreenshotSupport.sanitizedDelay(
            UserDefaults.standard[Preferences.screenshotDelay])
        if delay > 0 {
            countdownMode = mode
            countdownRemaining = delay
            tickCountdown()
        } else {
            beginCapture(mode)
        }
    }

    private func tickCountdown() {
        guard countdownRemaining > 0 else {
            let mode = countdownMode
            countdown = nil
            beginCapture(mode)
            return
        }
        QuickToolHUD.showCountdown(countdownRemaining)
        let work = DispatchWorkItem { [weak self] in
            guard let self else { return }
            self.countdownRemaining -= 1
            self.tickCountdown()
        }
        countdown = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 1, execute: work)
    }

    private func beginCapture(_ mode: CaptureMode) {
        if mode == .fullScreen {
            beginFullScreenCapture()
        } else {
            beginSelection(mode)
        }
    }

    private func beginSelection(_ mode: CaptureMode) {
        guard session == nil, !ScreenshotSelectionController.isSessionOnScreen else { return }
        preview?.close()
        preview = nil
        let defaults = UserDefaults.standard
        let controller = ScreenshotSelectionController(
            freeze: mode == .scrolling
                ? false
                : defaults[Preferences.screenshotFreeze],
            includePointer: defaults[Preferences.screenshotIncludePointer],
            showLastRegion: defaults[Preferences.screenshotShowLastRegion],
            hideVitruvianWindows: hideVitruvianWindows,
            protectedWindowIDs: { [weak self] in self?.protectedWindowIDs ?? [] },
            purpose: mode == .scrolling ? strings.scrollingCaptureTitle : nil,
            mode: mode == .scrolling ? .geometry : .image,
            supportsScrollingCapture: mode == .standard)
        session = controller
        controller.begin { [weak self] outcome in
            guard let self else { return }
            self.session = nil
            switch outcome {
            case .captured(let capture):
                self.route(capture)
            case .region(let region):
                guard mode == .scrolling else { break }
                self.captureScrolling(region)
            case .scrollingRegion(let region):
                self.captureScrolling(region)
            case .color:
                break
            case .cancelled:
                break
            case .failed:
                QuickToolHUD.show(icon: "camera.viewfinder", message: self.strings.captureFailed)
            }
        }
    }

    package func receiveUnifiedCapture(_ capture: ScreenshotSelectionController.Capture) {
        route(capture)
    }

    package func receiveUnifiedScrollingRegion(_ region: RecorderSupport.Region) {
        captureScrolling(region)
    }

    private func beginFullScreenCapture() {
        guard directCaptureTask == nil, !ScreenshotSelectionController.isSessionOnScreen else {
            return
        }
        preview?.close()
        preview = nil
        guard let screen = ScreenGeometry.under(NSEvent.mouseLocation, among: NSScreen.geometries,
                                                fallback: NSScreen.main?.geometry),
              screen.displayID != 0 else {
            QuickToolHUD.show(icon: "camera.viewfinder", message: strings.captureFailed)
            return
        }
        let displayID = screen.displayID
        let scale = screen.scale
        let frame = screen.frame
        let includePointer = UserDefaults.standard[Preferences.screenshotIncludePointer]
        let hideWindows = hideVitruvianWindows
        let protectedIDs = protectedWindowIDs
        directCaptureTask = Task { @MainActor [weak self] in
            let image = await ScreenshotCaptureEngine.captureDisplay(
                displayID,
                includePointer: includePointer,
                hideVitruvianWindows: hideWindows,
                protectedWindowIDs: protectedIDs)
            guard let self, !Task.isCancelled else { return }
            self.directCaptureTask = nil
            guard let image else {
                QuickToolHUD.show(icon: "camera.viewfinder", message: self.strings.captureFailed)
                return
            }
            self.route(ScreenshotSelectionController.Capture(
                image: image,
                scale: scale,
                anchorRect: frame))
        }
    }

    private func captureScrolling(_ region: RecorderSupport.Region) {
        guard scrollingTask == nil else { return }
        let finishSignal = ScreenshotScrollingCapture.FinishSignal()
        scrollingFinishSignal = finishSignal
        QuickToolHUD.showScrollingCapture(
            message: strings.scrollingCaptureProgressHUD,
            finishTitle: strings.done,
            cancelTitle: strings.cancel,
            onFinish: { finishSignal.request() },
            onCancel: { [weak self] in self?.scrollingTask?.cancel() })
        // Read after the controls are on screen so their window is protected,
        // and once for the whole run: the picture must not change halfway.
        let hideWindows = hideVitruvianWindows
        let protectedIDs = protectedWindowIDs
        let captureID = UUID()
        scrollingCaptureID = captureID
        scrollingTask = Task { @MainActor [weak self] in
            guard let self else { return }
            let result = await ScreenshotScrollingCapture.capture(
                region: region,
                includePointer: false,
                hideVitruvianWindows: hideWindows,
                protectedWindowIDs: protectedIDs,
                finishSignal: finishSignal,
                onProgress: { height in
                    QuickToolHUD.updateScrollingCapture(height: height)
                })
            guard self.scrollingCaptureID == captureID else { return }
            self.scrollingCaptureID = nil
            self.scrollingTask = nil
            self.scrollingFinishSignal = nil
            QuickToolHUD.dismissScrollingCapture()
            switch result {
            case .success(let capture):
                self.route(capture)
            case .partial(let capture):
                self.route(capture)
                QuickToolHUD.show(icon: "rectangle.stack",
                                  message: self.strings.scrollingCapturePartialHUD)
            case .limited(let capture):
                self.route(capture)
                QuickToolHUD.show(icon: "rectangle.stack",
                                  message: self.strings.scrollingCaptureTooLongHUD)
            case .cancelled:
                QuickToolHUD.show(icon: "xmark", message: L10n.shared.s.mediaCancelled)
            case .failed:
                QuickToolHUD.show(icon: "camera.viewfinder", message: self.strings.captureFailed)
            }
        }
    }

    // MARK: - Routing

    /// Where a direct save landed, and which "%#" number it consumed — so a
    /// later Trash can remove the file and, if applicable, give exactly that
    /// number back.
    private struct SaveOutcome {
        let url: URL
        let consumedNumber: Int?
    }

    private struct AutomaticActionResult {
        let performed: Set<ScreenshotQuickPreviewController.Action>
        let saved: SaveOutcome?
    }

    private func route(_ capture: ScreenshotSelectionController.Capture) {
        Self.route(capture, defaults: .standard, steps: previewRoute)
    }

    /// The steps a finished or restored capture takes toward its preview,
    /// passed in so their order and what the preview is handed can be
    /// checked. `Saved` is what the after-capture action saved.
    package struct PreviewRoute<Capture, Saved> {
        /// Makes a capture the latest one, and names the latest capture.
        package var beginLatest: (Capture) -> Void
        package var latestID: () -> UUID
        package var closePreview: () -> Void
        package var record: (Capture) -> Void
        package var autoCopy: (Capture) -> Void
        package var defaultAction: () -> ScreenshotDefaultAction
        package var openEditor: (Capture) -> Void
        package var runDefaultAction: (ScreenshotDefaultAction, Capture)
            -> (performed: Set<ScreenshotQuickPreviewController.Action>, saved: Saved?)
        /// Shows the preview. `latestCapture` names the latest capture its
        /// discard withholds from the upload shortcut; nil withholds nothing.
        package var presentPreview: (_ capture: Capture, _ defaultAction: ScreenshotDefaultAction,
                                     _ saved: Saved?, _ performed: Set<ScreenshotQuickPreviewController.Action>,
                                     _ dismissInterval: TimeInterval?, _ latestCapture: UUID?) -> Void

        // Spelled out because a memberwise initializer never leaves its module.
        package init(beginLatest: @escaping (Capture) -> Void, latestID: @escaping () -> UUID,
                     closePreview: @escaping () -> Void, record: @escaping (Capture) -> Void,
                     autoCopy: @escaping (Capture) -> Void,
                     defaultAction: @escaping () -> ScreenshotDefaultAction,
                     openEditor: @escaping (Capture) -> Void,
                     runDefaultAction: @escaping (ScreenshotDefaultAction, Capture)
                         -> (performed: Set<ScreenshotQuickPreviewController.Action>, saved: Saved?),
                     presentPreview: @escaping (_ capture: Capture, _ defaultAction: ScreenshotDefaultAction,
                                                _ saved: Saved?,
                                                _ performed: Set<ScreenshotQuickPreviewController.Action>,
                                                _ dismissInterval: TimeInterval?, _ latestCapture: UUID?) -> Void) {
            self.beginLatest = beginLatest
            self.latestID = latestID
            self.closePreview = closePreview
            self.record = record
            self.autoCopy = autoCopy
            self.defaultAction = defaultAction
            self.openEditor = openEditor
            self.runDefaultAction = runDefaultAction
            self.presentPreview = presentPreview
        }
    }

    private var previewRoute: PreviewRoute<ScreenshotSelectionController.Capture, SaveOutcome> {
        PreviewRoute(
            beginLatest: { self.latest.begin($0) },
            latestID: { self.latest.token },
            closePreview: { self.preview?.close() },
            record: { RecentCaptureService.shared.recordScreenshot($0) },
            autoCopy: { self.autoCopy($0) },
            defaultAction: { ScreenshotDefaultAction.current },
            openEditor: { self.openEditor(with: $0) },
            runDefaultAction: { action, capture in
                let result = self.runDefaultAction(action, capture: capture)
                return (result.performed, result.saved)
            },
            presentPreview: { capture, defaultAction, saved, performed, dismissInterval, latestCapture in
                self.presentPreview(capture,
                                    defaultAction: defaultAction,
                                    initialSaved: saved,
                                    completedActions: performed,
                                    dismissInterval: dismissInterval,
                                    latestCapture: latestCapture)
            })
    }

    /// A finished capture runs its configured after-capture action first, then
    /// either stays quiet, shows a confirmation/recovery preview, or opens the
    /// editor directly. It becomes the latest capture before anything else:
    /// an editor it opens withholds it from the upload shortcut, and the
    /// preview it shows names it, so discarding that preview withholds this
    /// capture rather than the one before.
    ///
    /// The clipboard copy happens first and independently, so it also reaches
    /// the captures that open straight in the editor, where no preview button
    /// exists to reach for.
    package static func route<Capture, Saved>(_ capture: Capture, defaults: UserDefaults,
                                              steps: PreviewRoute<Capture, Saved>) {
        steps.beginLatest(capture)
        steps.closePreview()
        steps.record(capture)
        if defaults[Preferences.screenshotCopyToClipboard] {
            steps.autoCopy(capture)
        }
        let defaultAction = steps.defaultAction()
        if defaultAction == .edit {
            steps.openEditor(capture)
            return
        }
        let result = steps.runDefaultAction(defaultAction, capture)
        presentRoutedPreview(after: defaultAction,
                             saved: result.saved != nil,
                             performed: result.performed,
                             defaults: defaults) { dismissInterval in
            steps.presentPreview(capture, defaultAction, result.saved, result.performed,
                                 dismissInterval, steps.latestID())
        }
    }

    /// The preview `route` shows once the default action ran: exactly the
    /// one the shared decision asks for, given what the action did, presented
    /// once with the decision's interval, or nothing when it is hidden.
    package static func presentRoutedPreview(
        after defaultAction: ScreenshotDefaultAction,
        saved: Bool,
        performed: Set<ScreenshotQuickPreviewController.Action>,
        defaults: UserDefaults,
        present: (_ dismissInterval: TimeInterval?) -> Void
    ) {
        guard case .shown(let dismissInterval) = ScreenshotSupport.quickPreviewPresentation(
            defaultAction: defaultAction,
            saved: saved,
            copied: performed.contains(.copy),
            defaults: defaults)
        else { return }
        present(dismissInterval)
    }

    package func restorePreview(_ capture: ScreenshotSelectionController.Capture) {
        Self.restore(capture, steps: previewRoute)
    }

    /// A history item returns to the same floating preview without repeating
    /// automatic copy or save actions that already ran when it was captured,
    /// and without any claim on the latest capture: discarding it withholds
    /// nothing from the upload shortcut.
    package static func restore<Capture, Saved>(_ capture: Capture, steps: PreviewRoute<Capture, Saved>) {
        steps.closePreview()
        steps.presentPreview(capture, .none, nil, [], ScreenshotSupport.recoveryPreviewDismissInterval, nil)
    }

    /// What the quick preview's buttons call on the service, passed in so
    /// the preview's own bookkeeping can be checked. `Saved` is what a save
    /// wrote.
    package struct PreviewActions<Capture, Saved> {
        package var edit: (Capture) -> Void
        package var pin: (Capture) -> Void
        package var copy: (Capture) -> Bool
        package var save: (Capture) -> Saved?
        package var saveAndCopy: (Capture) -> (outcome: Saved, copied: Bool)?
        /// Takes back a file a save wrote.
        package var trash: (Saved) -> Void
        /// Withholds the latest capture from the upload shortcut while
        /// `latestCapture` still names it; nil names nothing.
        package var withholdLatest: (_ latestCapture: UUID?) -> Void

        // Spelled out because a memberwise initializer never leaves its module.
        package init(edit: @escaping (Capture) -> Void, pin: @escaping (Capture) -> Void,
                     copy: @escaping (Capture) -> Bool, save: @escaping (Capture) -> Saved?,
                     saveAndCopy: @escaping (Capture) -> (outcome: Saved, copied: Bool)?,
                     trash: @escaping (Saved) -> Void,
                     withholdLatest: @escaping (_ latestCapture: UUID?) -> Void) {
            self.edit = edit
            self.pin = pin
            self.copy = copy
            self.save = save
            self.saveAndCopy = saveAndCopy
            self.trash = trash
            self.withholdLatest = withholdLatest
        }
    }

    private var previewActions: PreviewActions<ScreenshotSelectionController.Capture, SaveOutcome> {
        PreviewActions(
            edit: { [weak self] in self?.openEditor(with: $0) },
            pin: { ScreenshotPinController.shared.pin(image: $0.image, scale: $0.scale) },
            copy: { [weak self] in self?.copyDirect($0) ?? false },
            save: { [weak self] in self?.saveDirect($0) },
            saveAndCopy: { [weak self] in self?.saveAndCopyDirect($0) },
            trash: { saved in
                // Into the actual Trash: the person may be discarding a
                // file the HUD just announced as saved.
                try? FileManager.default.trashItem(at: saved.url, resultingItemURL: nil)
                if let consumed = saved.consumedNumber {
                    Self.rewindNumberSequence(toReuse: consumed)
                }
            },
            withholdLatest: { [weak self] in self?.latest.discard($0) })
    }

    /// The preview's button handler. What a save wrote is remembered, so a
    /// discard can take it back, and a discard withholds the latest capture
    /// only when the preview was made from it.
    package static func previewAction<Capture, Saved>(for capture: Capture,
                                                      initialSaved: Saved?,
                                                      latestCapture: UUID?,
                                                      actions: PreviewActions<Capture, Saved>)
        -> (ScreenshotQuickPreviewController.Action) -> Set<ScreenshotQuickPreviewController.Action> {
        var saved = initialSaved
        return { action in
            switch action {
            case .edit:
                actions.edit(capture)
                return [.edit]
            case .pin:
                actions.pin(capture)
                return [.pin]
            case .copy:
                return actions.copy(capture) ? [.copy] : []
            case .save:
                guard let outcome = actions.save(capture) else { return [] }
                saved = outcome
                return [.save]
            case .saveAndCopy:
                guard let result = actions.saveAndCopy(capture) else { return [] }
                saved = result.outcome
                return result.copied ? [.save, .copy] : [.save]
            case .discard:
                // If this capture was already written to disk — whether
                // by the default action or a manual Save — Trash should
                // undo that rather than leave an orphaned file behind.
                if let saved {
                    actions.trash(saved)
                }
                actions.withholdLatest(latestCapture)
                return [.discard]
            }
        }
    }

    private func presentPreview(_ capture: ScreenshotSelectionController.Capture,
                                defaultAction: ScreenshotDefaultAction,
                                initialSaved: SaveOutcome?,
                                completedActions: Set<ScreenshotQuickPreviewController.Action>,
                                dismissInterval: TimeInterval?,
                                latestCapture: UUID?) {
        let handle = Self.previewAction(for: capture, initialSaved: initialSaved,
                                        latestCapture: latestCapture, actions: previewActions)
        let controller = ScreenshotQuickPreviewController(
            capture: capture,
            strings: strings,
            defaultAction: defaultAction,
            completedActions: completedActions,
            dismissInterval: dismissInterval,
            action: { [weak self] action in
                guard self != nil else { return [] }
                return handle(action)
            },
            share: { [weak self] duration, completion in
                guard let self else {
                    Task { @MainActor in completion(nil) }
                    return
                }
                self.shareDirect(capture, duration: duration, completion: completion)
            },
            shareFile: { [weak self] in
                guard let self, let export = self.flatten(capture) else { return nil }
                return Self.temporaryExportFile(image: export.image, scale: export.scale,
                                                strings: self.strings)
            },
            onClose: { [weak self] in self?.preview = nil })
        preview = controller
        controller.show()
    }

    private func runDefaultAction(_ defaultAction: ScreenshotDefaultAction,
                                  capture: ScreenshotSelectionController.Capture)
        -> AutomaticActionResult {
        switch defaultAction {
        case .none, .edit:
            return AutomaticActionResult(performed: [], saved: nil)
        case .copy:
            return AutomaticActionResult(
                performed: copyDirect(capture) ? [.copy] : [],
                saved: nil)
        case .save:
            guard let outcome = saveDirect(capture) else {
                return AutomaticActionResult(performed: [], saved: nil)
            }
            return AutomaticActionResult(performed: [.save], saved: outcome)
        case .saveAndCopy:
            guard let result = saveAndCopyDirect(capture) else {
                return AutomaticActionResult(performed: [], saved: nil)
            }
            return AutomaticActionResult(
                performed: result.copied ? [.save, .copy] : [.save],
                saved: result.outcome)
        }
    }

    package func openEditor(with capture: ScreenshotSelectionController.Capture) {
        WindowActivationPolicy.retain()
        let editor = ScreenshotEditorController(capture: capture)
        latest.editorOpened(editor)
        editor.show()
    }

    private func openLastCapture() {
        guard let capture = ScreenshotLastCaptureStore.load() else {
            QuickToolHUD.show(icon: "camera.viewfinder", message: strings.lastCaptureMissing)
            return
        }
        preview?.close()
        preview = nil
        openEditor(with: capture)
    }

    private func openClipboardImage() {
        GeneralPasteboardAccess.shared.async { [weak self] in
            let capture = autoreleasepool {
                Self.clipboardCapture(from: NSPasteboard.general)
            }
            DispatchQueue.main.async { [weak self] in
                guard let self, AppFeature.screenshot.isAvailable else { return }
                guard let capture else {
                    QuickToolHUD.show(icon: "photo", message: self.strings.clipboardImageMissing)
                    return
                }
                self.openEditor(with: capture)
            }
        }
    }

    nonisolated private static func clipboardCapture(
        from pasteboard: NSPasteboard
    ) -> ScreenshotSelectionController.Capture? {
        guard let image = clipboardImage(from: pasteboard) else { return nil }
        return imageCapture(from: image)
    }

    nonisolated
    package static func imageCapture(from image: NSImage) -> ScreenshotSelectionController.Capture? {
        guard image.size.width > 0, image.size.height > 0
        else { return nil }
        var rect = CGRect(origin: .zero, size: image.size)
        guard let cgImage = image.cgImage(forProposedRect: &rect, context: nil, hints: nil),
              cgImage.width > 0, cgImage.height > 0,
              cgImage.width <= ScreenshotSupport.scrollingCaptureMaximumPixels / cgImage.height
        else { return nil }
        let pixelSize = CGSize(width: cgImage.width, height: cgImage.height)
        let scale = ScreenshotSupport.clipboardImageScale(pixelSize: pixelSize,
                                                          pointSize: image.size)
        return ScreenshotSelectionController.Capture(image: cgImage,
                                                     scale: scale,
                                                     anchorRect: .zero)
    }

    /// Copying a file in Finder leaves both its URL and a small icon preview on
    /// the pasteboard, so the file on disk wins whenever it is a readable image.
    nonisolated private static func clipboardImage(from pasteboard: NSPasteboard) -> NSImage? {
        let options: [NSPasteboard.ReadingOptionKey: Any] = [
            .urlReadingFileURLsOnly: true,
            .urlReadingContentsConformToTypes: [UTType.image.identifier]
        ]
        if let url = (pasteboard.readObjects(forClasses: [NSURL.self],
                                             options: options) as? [NSURL])?.first as URL?,
           let image = NSImage(contentsOf: url),
           image.size.width > 0, image.size.height > 0 {
            return image
        }
        return NSImage(pasteboard: pasteboard)
    }

    package func editorDidClose(_ editor: ScreenshotEditorController) {
        guard latest.editorClosed(editor) else { return }
        WindowActivationPolicy.release()
    }

    /// Automatic copy stays quiet on success: the preview or the editor is
    /// already appearing and says the capture happened, so a HUD on top of it
    /// would only repeat that. A failure still beeps, since nothing else
    /// would reveal an empty clipboard before the paste.
    private func autoCopy(_ capture: ScreenshotSelectionController.Capture) {
        let downscale = UserDefaults.standard[Preferences.screenshotDownscale]
        guard let folder = ScreenshotSupport.copiedFilesDirectory() else {
            NSSound.beep()
            return
        }
        let name = ScreenshotSupport.fileName(prefix: strings.fileNamePrefix, date: Date())
        autoCopyTask?.cancel()
        autoCopyGeneration += 1
        let generation = autoCopyGeneration
        let pasteboardChangeCount = NSPasteboard.general.changeCount
        autoCopyTask = Task { @MainActor [weak self] in
            let output = await Task.detached(priority: .userInitiated) {
                guard let export = Self.flatten(capture, downscaleTo1x: downscale) else {
                    return nil as (URL, ScreenshotEditorController.ClipboardPayload)?
                }
                let payload = ScreenshotEditorController.clipboardPayload(from: export)
                guard let png = payload.png,
                      let url = try? ScreenshotSupport.copiedFile(
                        data: png, name: name, directory: folder) else { return nil }
                return (url, payload)
            }.value
            guard let output else {
                if !Task.isCancelled { NSSound.beep() }
                return
            }
            guard let self, !Task.isCancelled,
                  generation == self.autoCopyGeneration,
                  pasteboardChangeCount == NSPasteboard.general.changeCount,
                  AppFeature.screenshot.isAvailable
            else {
                try? FileManager.default.removeItem(at: output.0)
                return
            }
            guard ScreenshotEditorController.copyFile(output.0, payload: output.1)
            else {
                try? FileManager.default.removeItem(at: output.0)
                NSSound.beep()
                return
            }
            ScreenshotSupport.pruneCopiedFiles(in: folder, preserving: output.0)
            self.autoCopyTask = nil
        }
    }

    private func shareDirect(_ capture: ScreenshotSelectionController.Capture,
                             duration: ScreenshotShareDuration,
                             completion: @escaping @MainActor (ScreenshotShareRecord?) -> Void) {
        let downscale = UserDefaults.standard[Preferences.screenshotDownscale]
        Task { @MainActor [weak self] in
            guard let self else {
                completion(nil)
                return
            }
            let data = await Task.detached(priority: .userInitiated) {
                guard let export = Self.flatten(capture, downscaleTo1x: downscale) else {
                    return nil as Data?
                }
                return ScreenshotRenderer.pngData(from: export.image, scale: export.scale)
            }.value
            guard let data else {
                QuickToolHUD.show(icon: "link", message: self.strings.shareFailedHUD)
                completion(nil)
                return
            }
            do {
                let record = try await ScreenshotShareService.shared.createLink(
                    pngData: data, duration: duration)
                completion(record)
            } catch {
                QuickToolHUD.show(icon: "link", message: self.strings.shareFailedHUD)
                NSSound.beep()
                completion(nil)
            }
        }
    }

    @discardableResult
    private func copyDirect(_ capture: ScreenshotSelectionController.Capture) -> Bool {
        guard let export = flatten(capture) else { return false }
        guard ScreenshotEditorController.copyImage(
            export, fileNamePrefix: strings.fileNamePrefix) else {
            NSSound.beep()
            return false
        }
        QuickToolHUD.show(icon: "camera.viewfinder", message: strings.copiedHUD)
        return true
    }

    private func saveDirect(_ capture: ScreenshotSelectionController.Capture) -> SaveOutcome? {
        guard let export = flatten(capture),
              let data = ScreenshotRenderer.pngData(from: export.image, scale: export.scale)
        else { return nil }
        let (url, consumedNumber) = Self.saveDestination(strings: strings)
        do {
            try data.write(to: url, options: .atomic)
            ScreenshotSupport.markAsScreenCapture(url)
            QuickToolHUD.show(icon: "camera.viewfinder",
                              message: String(format: strings.savedHUDFormat,
                                              url.deletingLastPathComponent().lastPathComponent))
            return SaveOutcome(url: url, consumedNumber: consumedNumber)
        } catch {
            if let consumedNumber {
                Self.rewindNumberSequence(toReuse: consumedNumber)
            }
            NSSound.beep()
            return nil
        }
    }

    /// The copy half is reported honestly: when the pasteboard write fails
    /// the HUD keeps the plain saved message, so the caller leaves the Copy
    /// button available instead of claiming work that never happened.
    private func saveAndCopyDirect(_ capture: ScreenshotSelectionController.Capture)
        -> (outcome: SaveOutcome, copied: Bool)? {
        guard let export = flatten(capture),
              let data = ScreenshotRenderer.pngData(from: export.image, scale: export.scale)
        else { return nil }
        let (url, consumedNumber) = Self.saveDestination(strings: strings)
        do {
            try data.write(to: url, options: .atomic)
            ScreenshotSupport.markAsScreenCapture(url)
        } catch {
            if let consumedNumber {
                Self.rewindNumberSequence(toReuse: consumedNumber)
            }
            NSSound.beep()
            return nil
        }

        let copied = ScreenshotEditorController.copyFile(
            url, payload: ScreenshotEditorController.clipboardPayload(from: export, png: data))
        let format = copied ? strings.savedAndCopiedHUDFormat : strings.savedHUDFormat
        QuickToolHUD.show(icon: "camera.viewfinder",
                          message: String(format: format,
                                          url.deletingLastPathComponent().lastPathComponent))
        return (SaveOutcome(url: url, consumedNumber: consumedNumber), copied)
    }

    /// Direct outputs go through the same pipeline as the editor so the 1x
    /// downscale preference applies everywhere; no backdrop, no rounding and
    /// no watermark, a direct capture is the raw pixels.
    private func flatten(_ capture: ScreenshotSelectionController.Capture)
        -> ScreenshotRenderer.Export? {
        Self.flatten(
            capture,
            downscaleTo1x: UserDefaults.standard[Preferences.screenshotDownscale])
    }

    nonisolated private static func flatten(_ capture: ScreenshotSelectionController.Capture,
                                downscaleTo1x: Bool) -> ScreenshotRenderer.Export? {
        ScreenshotRenderer.renderExport(
            baseImage: capture.image,
            annotations: [],
            pixelated: [:],
            scale: capture.scale,
            annotationShadowsEnabled: false,
            watermark: ScreenshotSupport.WatermarkStyle(),
            watermarkImage: nil,
            style: ScreenshotSupport.BackdropStyle(kind: .none, cornerRadius: 0),
            fill: .none,
            downscaleTo1x: downscaleTo1x)
    }

    /// Vends a full-resolution PNG for dragging into a folder or another app.
    /// The temporary write begins only when the person starts the drag.
    nonisolated package static func dragItemProvider(image: CGImage,
                                 scale: CGFloat,
                                 strings: ScreenshotFeatureStrings) -> NSItemProvider? {
        guard let url = temporaryExportFile(image: image, scale: scale, strings: strings) else {
            return nil
        }
        guard let provider = NSItemProvider(contentsOf: url) else {
            try? FileManager.default.removeItem(at: url.deletingLastPathComponent())
            return nil
        }
        return provider
    }

    /// A dated PNG in its own temporary folder, for a drag or the system
    /// share sheet. The receiving side reads the file after the gesture ends,
    /// so the folder stays for an hour before it is removed.
    nonisolated package static func temporaryExportFile(image: CGImage,
                                    scale: CGFloat,
                                    strings: ScreenshotFeatureStrings) -> URL? {
        guard let data = ScreenshotRenderer.pngData(from: image, scale: scale) else {
            return nil
        }
        let name = ScreenshotSupport.fileName(prefix: strings.fileNamePrefix, date: Date())
        guard let url = try? ScreenshotSupport.temporaryDragFile(data: data, name: name) else {
            return nil
        }
        let folder = url.deletingLastPathComponent()
        DispatchQueue.global(qos: .utility).asyncAfter(deadline: .now() + 60 * 60) {
            try? FileManager.default.removeItem(at: folder)
        }
        return url
    }

    // MARK: - Save location

    /// The configured folder when it still exists, otherwise the Desktop,
    /// with a unique dated file name.
    nonisolated package static func saveDestination(strings: ScreenshotFeatureStrings) -> (url: URL, consumedNumber: Int?) {
        let manager = FileManager.default
        var folder: URL?
        let stored = UserDefaults.standard[Preferences.screenshotSaveFolder]
        if !stored.isEmpty {
            let expanded = (stored as NSString).expandingTildeInPath
            var isDirectory: ObjCBool = false
            if manager.fileExists(atPath: expanded, isDirectory: &isDirectory),
               isDirectory.boolValue {
                folder = URL(fileURLWithPath: expanded)
            }
        }
        var destination = folder
            ?? manager.urls(for: .desktopDirectory, in: .userDomainMask).first
            ?? manager.homeDirectoryForCurrentUser
        let subfolderPattern = UserDefaults.standard[Preferences.screenshotSaveSubfolder]
        let subfolder = ScreenshotSupport.expandSaveSubfolder(subfolderPattern, date: Date())
        if !subfolder.isEmpty {
            let dated = destination.appendingPathComponent(subfolder, isDirectory: true)
            // Only descend into the dated subfolder if we can actually create
            // it; otherwise fall back to the base folder rather than losing
            // the screenshot.
            if (try? manager.createDirectory(at: dated, withIntermediateDirectories: true)) != nil {
                destination = dated
            }
        }
        let (name, consumedNumber) = Self.fileName(strings: strings)
        let unique = ScreenshotSupport.uniqueFileName(name) { candidate in
            manager.fileExists(atPath: destination.appendingPathComponent(candidate).path)
        }
        return (destination.appendingPathComponent(unique), consumedNumber)
    }

    /// The default localized "Screenshot yyyy-MM-dd at HH.mm.ss.png" name
    /// when no pattern is set, otherwise the pattern with date tokens and
    /// an optional "%#" number sequence expanded. Advances and persists the
    /// number sequence when the pattern actually uses it.
    nonisolated private static func fileName(strings: ScreenshotFeatureStrings) -> (name: String, consumedNumber: Int?) {
        let defaults = UserDefaults.standard
        let pattern = (defaults[Preferences.screenshotFileNamePattern])
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !pattern.isEmpty else {
            return (ScreenshotSupport.fileName(prefix: strings.fileNamePrefix, date: Date()), nil)
        }

        if ScreenshotSupport.fileNamePatternUsesNumber(pattern) {
            let number = defaults[Preferences.screenshotFileNumberNext]
            let expanded = ScreenshotSupport.expandFileNamePattern(pattern, date: Date(), number: number)
            defaults[Preferences.screenshotFileNumberNext] = number + 1
            return (expanded + ".png", number)
        } else {
            let expanded = ScreenshotSupport.expandFileNamePattern(pattern, date: Date(), number: 0)
            return (expanded + ".png", nil)
        }
    }

    /// Gives a consumed "%#" number back after its save failed or was
    /// deleted — but only while nothing else advanced the sequence since,
    /// so a rewind can never undo another capture's number.
    nonisolated package static func rewindNumberSequence(toReuse consumed: Int) {
        let defaults = UserDefaults.standard
        guard defaults[Preferences.screenshotFileNumberNext] == consumed + 1 else {
            return
        }
        defaults[Preferences.screenshotFileNumberNext] = consumed
    }
}

/// One discardable PNG on disk keeps this shortcut useful across launches
/// without holding a full-resolution screenshot in memory while the app rests.
package enum ScreenshotLastCaptureStore {
    private static let writeQueue = DispatchQueue(
        label: "com.vitruviansoftware.vitruvian.latest-screenshot",
        qos: .utility)
    private static let stateLock = NSLock()
    // Both guarded by stateLock.
    nonisolated(unsafe) private static var generation = 0
    nonisolated(unsafe) private static var pendingCapture: ScreenshotSelectionController.Capture?

    private static var fileURL: URL? {
        guard let base = FileManager.default.urls(for: .cachesDirectory,
                                                  in: .userDomainMask).first,
              let bundleID = Bundle.main.bundleIdentifier
        else { return nil }
        return base
            .appendingPathComponent(bundleID, isDirectory: true)
            .appendingPathComponent("LatestScreenshot.png")
    }

    /// Present while the stored capture was discarded or went through an
    /// editor, so the upload shortcut keeps it back after a relaunch too.
    private static var withheldURL: URL? {
        fileURL?.deletingLastPathComponent().appendingPathComponent("LatestScreenshot.withheld")
    }

    package static var isWithheld: Bool {
        guard let withheldURL else { return false }
        return FileManager.default.fileExists(atPath: withheldURL.path)
    }

    package static func withhold() {
        guard let withheldURL else { return }
        try? FileManager.default.createDirectory(at: withheldURL.deletingLastPathComponent(),
                                                 withIntermediateDirectories: true)
        FileManager.default.createFile(atPath: withheldURL.path, contents: nil)
    }

    package static func save(_ capture: ScreenshotSelectionController.Capture) {
        guard let fileURL else { return }
        // A new capture starts out as the one the person kept.
        if let withheldURL { try? FileManager.default.removeItem(at: withheldURL) }
        stateLock.lock()
        generation += 1
        let operation = generation
        pendingCapture = capture
        stateLock.unlock()

        writeQueue.async {
            guard let data = ScreenshotRenderer.pngData(
                from: capture.image, scale: capture.scale)
            else {
                finish(operation, fileURL: fileURL, removeFile: true)
                return
            }
            guard isCurrent(operation) else { return }
            do {
                try FileManager.default.createDirectory(
                    at: fileURL.deletingLastPathComponent(),
                    withIntermediateDirectories: true)
                try data.write(to: fileURL, options: .atomic)
                guard isCurrent(operation) else {
                    try? FileManager.default.removeItem(at: fileURL)
                    return
                }
                finish(operation, fileURL: fileURL, removeFile: false)
            } catch {
                finish(operation, fileURL: fileURL, removeFile: true)
            }
        }
    }

    package static func load() -> ScreenshotSelectionController.Capture? {
        stateLock.lock()
        let pending = pendingCapture
        stateLock.unlock()
        if let pending { return pending }

        guard let fileURL else { return nil }
        let sourceOptions = [kCGImageSourceShouldCache: false] as CFDictionary
        guard let source = CGImageSourceCreateWithURL(fileURL as CFURL, sourceOptions),
              let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as NSDictionary?,
              let dpi = properties[kCGImagePropertyDPIWidth] as? NSNumber,
              let scale = ScreenshotSupport.captureScale(fromDPI: dpi.doubleValue)
        else { return nil }
        let imageOptions = [kCGImageSourceShouldCacheImmediately: true] as CFDictionary
        guard let image = CGImageSourceCreateImageAtIndex(source, 0, imageOptions) else { return nil }
        return ScreenshotSelectionController.Capture(image: image, scale: scale, anchorRect: .zero)
    }

    package static func clear() {
        stateLock.lock()
        generation += 1
        pendingCapture = nil
        stateLock.unlock()
        if let withheldURL { try? FileManager.default.removeItem(at: withheldURL) }
        guard let fileURL else { return }
        try? FileManager.default.removeItem(at: fileURL)
    }

    private static func isCurrent(_ operation: Int) -> Bool {
        stateLock.lock()
        defer { stateLock.unlock() }
        return generation == operation
    }

    private static func finish(_ operation: Int, fileURL: URL, removeFile: Bool) {
        guard isCurrent(operation) else { return }
        if removeFile {
            try? FileManager.default.removeItem(at: fileURL)
        }
        stateLock.lock()
        if generation == operation {
            pendingCapture = nil
        }
        stateLock.unlock()
    }
}
