// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import AppKit
import Carbon.HIToolbox
import SwiftUI
import VitruvianCore
import VitruvianDesign

/// Drives the QR button, which appears after the capture is scanned so the
/// preview never waits on detection to show, and the buttons grayed out
/// because the after-capture action already did their work.
@MainActor
package final class ScreenshotQuickPreviewModel: ObservableObject {
    @Published package var qr: BarcodeDetector.Reading?
    @Published package var disabledActions: Set<ScreenshotQuickPreviewController.Action> = []
    @Published package var sharing = false
    @Published package var sharedRecord: ScreenshotShareRecord?
    @Published package var deletingShare = false
}

/// A transient capture preview that stays outside Command Tab and reflects
/// automatic Save or Copy work that may already have completed.
@MainActor
package final class ScreenshotQuickPreviewController {
    package enum Action {
        case edit
        case pin
        case copy
        case save
        case saveAndCopy
        case discard
    }

    /// Where the preview's deferred work runs. `main` is the main queue;
    /// tests pass a clock of their own.
    package struct Scheduler {
        package var async: (@escaping @MainActor () -> Void) -> Void
        package var after: (_ delay: TimeInterval, _ work: DispatchWorkItem) -> Void

        package init(async: @escaping (@escaping @MainActor () -> Void) -> Void,
                     after: @escaping (TimeInterval, DispatchWorkItem) -> Void) {
            self.async = async
            self.after = after
        }

        package static var main: Scheduler {
            Scheduler(async: { work in
                DispatchQueue.main.async { MainActor.assumeIsolated { work() } }
            }, after: { DispatchQueue.main.asyncAfter(deadline: .now() + $0, execute: $1) })
        }
    }

    /// Where the preview appears and the settings it reads to decide how.
    /// `live` is the app's: its preferences, its island, and a floating panel
    /// put on screen without activating the app. Tests swap in their own.
    package struct Presentation {
        package var defaults: UserDefaults
        package var island: @MainActor () -> NotchService
        /// The floating panel, before its content, for content of `size`.
        package var makePanel: @MainActor (_ size: CGSize) -> NSPanel
        /// Puts the floating panel on screen, handing it the keyboard only
        /// when asked, and only once it is up.
        package var present: @MainActor (_ panel: NSPanel, _ takesFocus: Bool) -> Void

        package init(defaults: UserDefaults,
                     island: @escaping @MainActor () -> NotchService,
                     makePanel: @escaping @MainActor (_ size: CGSize) -> NSPanel,
                     present: @escaping @MainActor (_ panel: NSPanel, _ takesFocus: Bool) -> Void) {
            self.defaults = defaults
            self.island = island
            self.makePanel = makePanel
            self.present = present
        }

        package static var live: Presentation {
            Presentation(
                defaults: .standard,
                island: { NotchService.shared },
                makePanel: { size in ScreenshotQuickPreviewController.makePanel(size: size) },
                present: { panel, takesFocus in
                    panel.orderFrontRegardless()
                    // On by default: leaving the keyboard behind after a capture is what
                    // #1463 reported, since Command-C and Command-S did nothing until a
                    // click. Taking it costs the caret in the app being typed into
                    // (#1089), so persistent previews always leave focus where it was;
                    // a click can still hand focus to the preview explicitly.
                    if takesFocus {
                        panel.makeKey()
                    }
                })
        }
    }

    /// What a click on the link button does. The island hides the menu
    /// arrow, so a primary action there would leave the durations behind a
    /// press and hold that nothing hints at: a click opens them, as it always
    /// has. The floating preview shows its arrow and keeps a split button
    /// whose click shares at once.
    package enum ShareLinkClick {
        case opensDurations
        case sharesSavedLink
    }

    package static func shareLinkClick(embedded: Bool) -> ShareLinkClick {
        embedded ? .opensDurations : .sharesSavedLink
    }

    /// A press on the floating preview while it is not key hands it the
    /// keyboard, so its shortcuts start working; the press itself still
    /// reaches the button under it.
    package static func previewPanelTakesKeyboard(on type: NSEvent.EventType, isKeyWindow: Bool) -> Bool {
        type == .leftMouseDown && !isKeyWindow
    }

    private let capture: ScreenshotSelectionController.Capture
    private let strings: ScreenshotFeatureStrings
    private let defaultAction: ScreenshotDefaultAction
    /// Runs one action and reports which sub-actions actually happened —
    /// save-and-copy can succeed by halves, and only the done halves gray
    /// their buttons out. Empty means the action failed entirely.
    private let action: (Action) -> Set<Action>
    private let share: (ScreenshotShareDuration,
                        @escaping @MainActor (ScreenshotShareRecord?) -> Void) -> Void
    /// Writes the capture as it would be saved into a temporary file for the
    /// system share sheet.
    private let shareFile: () -> URL?
    private let shareAnchor = ShelfSharePickerAnchor.Anchor()
    /// The system share sheet is open, outside the preview.
    package var systemSharing = false
    private let onClose: () -> Void
    /// What the preview shows: sharing, the shared link, and the buttons
    /// already done.
    package let model = ScreenshotQuickPreviewModel()
    private var panel: NSPanel?
    private var keyMonitor: Any?
    private var dismissWork: DispatchWorkItem?
    private let baseDismissDuration: TimeInterval?
    private var autoDismissDuration: TimeInterval?
    private var closed = false
    private let presentationID = UUID()
    private var shownInNotch = false
    private var didStartPreview = false
    package private(set) var pointerInside = false
    private let scheduler: Scheduler
    private let links: ScreenshotLinkActions
    private let presentation: Presentation

    package var protectedWindowIDs: Set<CGWindowID> {
        guard let panel, panel.isVisible, panel.windowNumber > 0 else { return [] }
        return [CGWindowID(panel.windowNumber)]
    }

    package init(capture: ScreenshotSelectionController.Capture,
         strings: ScreenshotFeatureStrings,
         defaultAction: ScreenshotDefaultAction,
         completedActions: Set<Action>,
         dismissInterval: TimeInterval?,
         action: @escaping (Action) -> Set<Action>,
         share: @escaping (ScreenshotShareDuration,
                           @escaping @MainActor (ScreenshotShareRecord?) -> Void) -> Void,
         shareFile: @escaping () -> URL?,
         onClose: @escaping () -> Void,
         scheduler: Scheduler = .main,
         links: ScreenshotLinkActions = .live,
         presentation: Presentation = .live) {
        self.capture = capture
        self.strings = strings
        self.defaultAction = defaultAction
        self.baseDismissDuration = dismissInterval
        self.autoDismissDuration = dismissInterval
        self.action = action
        self.share = share
        self.shareFile = shareFile
        self.onClose = onClose
        self.scheduler = scheduler
        self.links = links
        self.presentation = presentation
        model.disabledActions = completedActions.intersection([.save, .copy])
    }

    package func show(inNotch: Bool = true) {
        guard panel == nil, !shownInNotch, !closed else { return }
        let wantsNotch = inNotch && NotchSupport.routes(.capture, in: presentation.defaults)
            && presentation.island().acceptsSystemFeedback
        let presentationPolicy = ScreenshotSupport.confirmationPreviewPresentationPolicy(
            dismissInterval: baseDismissDuration,
            defaults: presentation.defaults)
        let content = ScreenshotQuickPreviewView(
            image: Self.thumbnail(for: capture.image),
            strings: strings,
            model: model,
            perform: { [weak self] action in self?.perform(action) },
            dragItem: { [weak self] in
                guard let self else { return NSItemProvider() }
                return ScreenshotService.dragItemProvider(image: self.capture.image,
                                                          scale: self.capture.scale,
                                                          strings: self.strings)
                    ?? NSItemProvider()
            },
            share: { [weak self] duration in self?.performShare(duration) },
            systemShare: { [weak self] in self?.performSystemShare() },
            shareAnchor: shareAnchor,
            copySharedLink: { [weak self] in self?.copySharedLink() },
            deleteSharedLink: { [weak self] in self?.deleteSharedLink() },
            showQR: { [weak self] in self?.showQRResult() },
            dismiss: { [weak self] in self?.close() },
            hoverChanged: { [weak self] inside in self?.hoverChanged(inside) },
            showsDismissButton: presentationPolicy.showsDismissButton,
            embedded: wantsNotch)
        if wantsNotch, presentation.island().presentCapture(
            id: presentationID, content: AnyView(content), actions: AnyView(content.toolbar), height: Self.size(showingLink: model.sharedRecord != nil).height,
            takeFocus: presentationPolicy.takesFocus,
            closeOnCollapse: presentationPolicy.closesOnCollapse,
            fallback: { [weak self] in
                guard let self else { return }
                self.shownInNotch = false
                self.pointerInside = false
                if let keyMonitor = self.keyMonitor { NSEvent.removeMonitor(keyMonitor) }
                self.keyMonitor = nil
                self.show(inNotch: false)
            },
            close: { [weak self] in self?.close() },
            hover: { [weak self] inside in self?.hoverChanged(inside) }) {
            shownInNotch = true
            if let window = presentation.island().presentationWindow { installKeyMonitor(for: window) }
            finishShowing()
            return
        }
        let host = NSHostingController(rootView: content)
        let size = Self.size(showingLink: model.sharedRecord != nil)
        let panel = presentation.makePanel(size)
        panel.contentViewController = host
        panel.isReleasedWhenClosed = false
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.hidesOnDeactivate = false
        panel.level = .statusBar
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary,
                                    .transient, .ignoresCycle]

        let frame = previewFrame(for: size)
        panel.setFrame(frame, display: false)
        self.panel = panel
        installKeyMonitor(for: panel)
        presentation.present(panel, presentationPolicy.takesFocus)
        finishShowing()
    }

    /// The preview's panel, before its content: a floating overlay, which
    /// window managers do not list, that a click makes key.
    package static func makePanel(size: CGSize) -> NSPanel {
        ScreenshotQuickPreviewPanel(
            contentRect: CGRect(origin: .zero, size: size),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false)
    }

    private func finishShowing() {
        if !didStartPreview {
            didStartPreview = true
            scanForQR()
        }
        scheduleAutoDismiss()
    }

    /// The island tracks the image and header together. Leaving just the
    /// image must not restart dismissal while its actions are still hovered.
    package static func forwardImageHover(_ inside: Bool, embedded: Bool, to hoverChanged: (Bool) -> Void) {
        guard !embedded else { return }
        hoverChanged(inside)
    }

    package func hoverChanged(_ inside: Bool) {
        pointerInside = inside
        dismissWork?.cancel()
        dismissWork = nil
        if !inside { scheduleAutoDismiss() }
    }

    /// Scans the full resolution capture off the main thread and reveals the
    /// QR button if a code is found. Silent when there is none, so a plain
    /// screenshot preview is untouched.
    private func scanForQR() {
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let image = self?.capture.image, let reading = BarcodeDetector.read(image) else { return }
            DispatchQueue.main.async {
                guard let self, !self.closed else { return }
                withAnimation(.spring(response: 0.3, dampingFraction: 0.82)) {
                    self.model.qr = reading
                }
            }
        }
    }

    /// Hands the code to the shared result panel, which spells out the
    /// content before anything is copied. The preview steps aside.
    private func showQRResult() {
        guard let reading = model.qr else { return }
        close()
        QRResultController.shared.show(reading: reading)
    }

    private static func thumbnail(for image: CGImage) -> CGImage {
        let maximumDimension: CGFloat = 1_200
        let longest = CGFloat(max(image.width, image.height))
        guard longest > maximumDimension else { return image }
        let factor = maximumDimension / longest
        let width = max(1, Int((CGFloat(image.width) * factor).rounded()))
        let height = max(1, Int((CGFloat(image.height) * factor).rounded()))
        guard let colorSpace = CGColorSpace(name: CGColorSpace.sRGB),
              let context = CGContext(data: nil,
                                      width: width,
                                      height: height,
                                      bitsPerComponent: 8,
                                      bytesPerRow: 0,
                                      space: colorSpace,
                                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
        else { return image }
        context.interpolationQuality = .high
        context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        return context.makeImage() ?? image
    }

    package func close() {
        guard !closed else { return }
        closed = true
        dismissWork?.cancel()
        dismissWork = nil
        if let keyMonitor {
            NSEvent.removeMonitor(keyMonitor)
            self.keyMonitor = nil
        }
        panel?.orderOut(nil)
        panel = nil
        if shownInNotch {
            shownInNotch = false
            presentation.island().removeCapture(id: presentationID)
        }
        onClose()
    }

    package func perform(_ requested: Action) {
        guard !closed else { return }
        // Keyboard shortcuts honor the grayed-out buttons: what the
        // after-capture action already did is not done twice.
        guard !model.disabledActions.contains(requested) else { return }
        dismissWork?.cancel()
        dismissWork = nil
        if requested == .edit {
            // Release the island's non-activating key panel before promoting
            // the app and constructing another SwiftUI window. Defer past the
            // button's current update rather than nesting editor layout in it.
            let action = action
            close()
            scheduler.async { _ = action(requested) }
            return
        }
        guard !action(requested).isEmpty else {
            scheduleAutoDismiss()
            return
        }
        close()
    }

    package func shareLink() {
        guard !closed, !model.deletingShare else { return }
        if model.sharedRecord != nil {
            copySharedLink()
        } else {
            performShare(.saved())
        }
    }

    /// The system share sheet: AirDrop, messages and every other target the
    /// Mac offers. The preview waits while the sheet is up, and a chosen
    /// target finishes it the way Copy does.
    private func performSystemShare() {
        guard !closed, !systemSharing else { return }
        dismissWork?.cancel()
        dismissWork = nil
        guard let url = shareFile() else {
            NSSound.beep()
            scheduleAutoDismiss()
            return
        }
        systemSharing = true
        let shown = shareAnchor.present([url]) { [weak self] chosen in
            guard let self else { return }
            self.systemSharing = false
            if chosen { self.close() } else { self.scheduleAutoDismiss() }
        }
        if !shown {
            systemSharing = false
            scheduleAutoDismiss()
        }
    }

    private func performShare(_ duration: ScreenshotShareDuration) {
        guard !closed, !model.sharing else { return }
        dismissWork?.cancel()
        dismissWork = nil
        model.sharing = true
        let delete = links.delete
        share(duration) { [weak self] record in
            guard let self, !self.closed else {
                if let record {
                    Task { @MainActor in try? await delete(record) }
                }
                return
            }
            self.model.sharing = false
            guard let record else {
                self.scheduleAutoDismiss()
                return
            }
            if self.copyLinkAndClose(record) { return }
            withAnimation(.spring(response: 0.3, dampingFraction: 0.86)) {
                self.model.sharedRecord = record
            }
            self.autoDismissDuration = ScreenshotSupport.sharedPreviewDismissInterval(
                base: self.baseDismissDuration)
            self.resizePanel(showingLink: true)
            self.scheduleAutoDismiss()
        }
    }

    private func copySharedLink() {
        guard let record = model.sharedRecord else { return }
        dismissWork?.cancel()
        dismissWork = nil
        Task { @MainActor [weak self] in
            guard let self, !self.closed else { return }
            if !self.copyLinkAndClose(record) { self.scheduleAutoDismiss() }
        }
    }

    @MainActor
    private func copyLinkAndClose(_ record: ScreenshotShareRecord) -> Bool {
        let copied = ScreenshotSharingSupport.copyLink(
            record, using: links.copy,
            dismiss: { self.close() })
        if copied {
            links.announce("link", strings.sharedHUD)
        } else {
            links.announce("link", strings.linkCopyFailedHUD)
            links.beep()
        }
        return copied
    }

    private func deleteSharedLink() {
        guard let record = model.sharedRecord, !model.deletingShare else { return }
        dismissWork?.cancel()
        dismissWork = nil
        model.deletingShare = true
        Task { @MainActor [weak self] in
            guard let self else { return }
            do {
                try await self.links.delete(record)
                guard !self.closed else { return }
                withAnimation(.easeOut(duration: 0.2)) {
                    self.model.sharedRecord = nil
                    self.model.deletingShare = false
                }
                self.links.announce("link", self.strings.linkDeletedHUD)
                self.autoDismissDuration = self.baseDismissDuration
                self.resizePanel(showingLink: false)
            } catch {
                guard !self.closed else { return }
                self.model.deletingShare = false
                self.links.announce("link", self.strings.deleteFailedHUD)
                self.links.beep()
            }
            self.scheduleAutoDismiss()
        }
    }

    fileprivate static func size(showingLink: Bool) -> CGSize {
        CGSize(width: 350, height: showingLink ? 268 : 210)
    }

    private func previewFrame(for size: CGSize) -> CGRect {
        let pointer = NSEvent.mouseLocation
        let screens = NSScreen.screens.map { (frame: $0.frame, visibleFrame: $0.visibleFrame) }
        let visibleFrame = ScreenshotSupport.quickPreviewVisibleFrame(
            anchor: capture.anchorRect,
            pointer: pointer,
            screens: screens,
            fallback: NSScreen.pointerVisibleFrame)
        let storedPosition = UserDefaults.standard[Preferences.screenshotPreviewPosition]
        let position = ScreenshotSupport.QuickPreviewPosition(rawValue: storedPosition)
            ?? .automatic
        // With an after-capture action the preview is just a confirmation,
        // so it sits quietly in the corner and leaves sooner, instead of
        // popping up next to the selection and waiting.
        let effectivePosition: ScreenshotSupport.QuickPreviewPosition =
            position == .automatic && defaultAction != .none
                ? .bottomRight
                : position
        return ScreenshotSupport.quickPreviewFrame(
            size: size,
            anchor: capture.anchorRect,
            pointer: pointer,
            visibleFrame: visibleFrame,
            position: effectivePosition)
    }

    private func resizePanel(showingLink: Bool) {
        if shownInNotch {
            presentation.island().updateCaptureHeight(id: presentationID, height: Self.size(showingLink: showingLink).height)
            return
        }
        panel?.setFrame(previewFrame(for: Self.size(showingLink: showingLink)),
                        display: true,
                        animate: true)
    }

    package func scheduleAutoDismiss() {
        guard !closed, !pointerInside, !systemSharing, !model.sharing, !model.deletingShare,
              let dismissDuration = autoDismissDuration
        else { return }
        dismissWork?.cancel()
        let work = DispatchWorkItem { [weak self] in self?.close() }
        dismissWork = work
        scheduler.after(dismissDuration, work)
    }

    private func installKeyMonitor(for panel: NSPanel) {
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self, weak panel] event in
            guard let self, let panel,
                  ScreenshotPreviewKeys.ownsKeys(
                    closed: self.closed, panelVisible: panel.isVisible, inPanel: event.window === panel,
                    shownByIsland: !self.shownInNotch || self.presentation.island().isCaptureVisible(id: self.presentationID),
                    hasSheet: panel.attachedSheet != nil, editingText: panel.firstResponder is NSText,
                    recordingShortcut: ShortcutCapture.isCapturing),
                  let command = ScreenshotPreviewKeys.command(keyCode: Int(event.keyCode), flags: event.modifierFlags,
                                                              characters: event.charactersIgnoringModifiers)
            else { return event }
            switch command {
            case .close: self.close()
            case .perform(let action): self.perform(action)
            }
            return nil
        }
    }
}

private final class ScreenshotQuickPreviewPanel: OverlayPanel {
    override var canBecomeKey: Bool { true }

    /// The preview shows up unasked for, so presenting it leaves the keyboard
    /// where it was unless the person opted in, and a click is what hands it
    /// over. Its shortcuts read a local monitor, and that monitor is delivered
    /// nothing until this panel is key. The hand-off sits in `sendEvent`
    /// rather than `mouseDown` because the hosted SwiftUI content answers a
    /// press on a button itself, and a window's `mouseDown` never runs for the
    /// clicks a view has taken.
    override func sendEvent(_ event: NSEvent) {
        if ScreenshotQuickPreviewController.previewPanelTakesKeyboard(on: event.type, isKeyWindow: isKeyWindow) {
            makeKey()
        }
        super.sendEvent(event)
    }
}

private struct ScreenshotQuickPreviewView: View {
    let image: CGImage
    let strings: ScreenshotFeatureStrings
    @ObservedObject var model: ScreenshotQuickPreviewModel
    let perform: (ScreenshotQuickPreviewController.Action) -> Void
    let dragItem: () -> NSItemProvider
    let share: (ScreenshotShareDuration) -> Void
    let systemShare: () -> Void
    let shareAnchor: ShelfSharePickerAnchor.Anchor
    let copySharedLink: () -> Void
    let deleteSharedLink: () -> Void
    let showQR: () -> Void
    let dismiss: () -> Void
    let hoverChanged: (Bool) -> Void
    let showsDismissButton: Bool
    var embedded = false
    var actionsOnly = false
    var toolbar: Self {
        var view = self
        view.actionsOnly = true
        return view
    }
    @AppStorage(Preferences.screenshotSharingEnabled) private var sharingEnabled: Bool

    var body: some View {
        if actionsOnly { actionBar }
        else { preview }
    }

    private var actionBar: some View {
        HStack(spacing: embedded ? 2 : 5) {
            Button {
                perform(.discard)
            } label: {
                Image(systemName: "trash")
                    .frame(width: embedded ? 28 : 22, height: embedded ? 28 : 18)
            }
            .modifier(ScreenshotPreviewActionStyle(embedded: embedded))
            .controlSize(.small)
            .screenshotSafeHelp("\(strings.discardConfirm)  (⌫)")
            .accessibilityLabel(strings.discardConfirm)
            if model.qr != nil {
                qrControl
                    .transition(.scale.combined(with: .opacity))
            }
            actionButton(symbol: "square.and.arrow.down",
                         title: strings.saveButton,
                         shortcut: "⌘S",
                         disabled: model.disabledActions.contains(.save)) {
                perform(.save)
            }
            actionButton(symbol: "doc.on.doc",
                         title: strings.copyButton,
                         shortcut: "⌘C",
                         disabled: model.disabledActions.contains(.copy)) {
                perform(.copy)
            }
            if embedded {
                Button(action: systemShare) {
                    Image(systemName: "square.and.arrow.up").frame(width: 28, height: 28)
                }
                .modifier(ScreenshotPreviewActionStyle(embedded: true))
                .controlSize(.small)
                .background(ShelfSharePickerAnchor(anchor: shareAnchor))
                .screenshotSafeHelp(strings.shareButton)
                .accessibilityLabel(strings.shareButton)
            }
            if sharingEnabled, model.sharedRecord == nil {
                shareMenu
            }
            if !embedded { Spacer(minLength: 4) }
            if embedded {
                Button {
                    perform(.pin)
                } label: {
                    Image(systemName: "pin").frame(width: 28, height: 28)
                }
                .modifier(ScreenshotPreviewActionStyle(embedded: true))
                .controlSize(.small)
                .screenshotSafeHelp(strings.pinButton)
                .accessibilityLabel(strings.pinButton)
            }
            Button { perform(.edit) } label: {
                if embedded { Image(systemName: "pencil").frame(width: 28, height: 28) }
                else { Text(strings.editButton) }
            }
            .accessibilityLabel(strings.editButton)
            .modifier(ScreenshotPreviewActionStyle(embedded: embedded, prominent: true))
            .controlSize(.small)
            .screenshotSafeHelp("\(strings.editButton)  (⏎)")
        }
    }

    private var thumbnailDismissButton: some View {
        Button(action: dismiss) {
            Image(systemName: "xmark")
                .font(.system(size: 11, weight: .semibold))
                .frame(width: 24, height: 24)
                .background(.regularMaterial, in: Circle())
                .overlay(Circle().strokeBorder(Color.primary.opacity(0.12), lineWidth: 1))
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .padding(6)
        .screenshotSafeHelp("\(strings.done)  (⎋)")
        .accessibilityLabel(strings.done)
    }

    private var thumbnailButtons: some View {
        HStack(spacing: 5) {
            thumbnailButton(symbol: "square.and.arrow.up", title: strings.shareButton,
                            action: systemShare)
                .background(ShelfSharePickerAnchor(anchor: shareAnchor))
            thumbnailButton(symbol: "pin", title: strings.pinButton) { perform(.pin) }
        }
        .padding(6)
    }

    private func thumbnailButton(symbol: String,
                                 title: String,
                                 action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 11, weight: .semibold))
                .frame(width: 24, height: 24)
                .background(.regularMaterial, in: Circle())
                .overlay(Circle().strokeBorder(Color.primary.opacity(0.12), lineWidth: 1))
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .screenshotSafeHelp(title)
        .accessibilityLabel(title)
    }

    private var preview: some View {
        VStack(spacing: 10) {
            Button {
                perform(.edit)
            } label: {
                Image(decorative: image, scale: 1)
                    .resizable()
                    .interpolation(.high)
                    .scaledToFit()
                    .frame(maxWidth: 320, maxHeight: 138)
                    .frame(width: embedded ? nil : 320, height: 138)
                    .background(Color.black.opacity(0.12))
                    .clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 9, style: .continuous)
                            .strokeBorder(Color.primary.opacity(0.12), lineWidth: 1)
                    )
            }
            .buttonStyle(.plain)
            .onDrag(dragItem)
            .screenshotSafeHelp(strings.editButton)
            .accessibilityLabel(strings.editButton)
            .overlay(alignment: .topLeading) {
                if showsDismissButton { thumbnailDismissButton }
            }
            .overlay(alignment: .topTrailing) {
                // The floating action row already fills its fixed width in
                // longer languages, so share and pin ride on the thumbnail
                // there instead of squeezing Save, Copy and Edit.
                if !embedded { thumbnailButtons }
            }

            if let record = model.sharedRecord {
                sharedLinkRow(record)
                    .transition(.move(edge: .top).combined(with: .opacity))
            }

            if !embedded { actionBar }
        }
        .padding(10)
        .frame(width: embedded ? nil : ScreenshotQuickPreviewController.size(showingLink: false).width,
               height: embedded ? nil : ScreenshotQuickPreviewController.size(
                   showingLink: model.sharedRecord != nil).height)
        .background {
            if !embedded {
                RoundedRectangle(cornerRadius: 16, style: .continuous).fill(.regularMaterial)
            }
        }
        .overlay {
            if !embedded {
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .strokeBorder(Color.primary.opacity(0.10), lineWidth: 1)
            }
        }
        .onHover(perform: previewHoverChanged)
    }

    private func previewHoverChanged(_ inside: Bool) {
        ScreenshotQuickPreviewController.forwardImageHover(inside, embedded: embedded, to: hoverChanged)
    }

    private func sharedLinkRow(_ record: ScreenshotShareRecord) -> some View {
        HStack(spacing: 8) {
            Image(systemName: "link")
                .foregroundStyle(.secondary)
            VStack(alignment: .leading, spacing: 2) {
                Text(record.url.absoluteString)
                    .font(.system(size: 11, design: .rounded))
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .textSelection(.enabled)
                HStack(spacing: 3) {
                    Text(strings.expiresLabel)
                    Text(record.expiresAt, style: .relative)
                }
                .font(.caption2)
                .foregroundStyle(.secondary)
            }
            Spacer(minLength: 2)
            Button(action: copySharedLink) {
                Image(systemName: "doc.on.doc")
                    .frame(width: 18, height: 18)
            }
            .buttonStyle(.borderless)
            .disabled(model.deletingShare)
            .screenshotSafeHelp(strings.copyLink)
            .accessibilityLabel(strings.copyLink)
            Button(role: .destructive, action: deleteSharedLink) {
                Group {
                    if model.deletingShare {
                        ProgressView()
                            .controlSize(.mini)
                    } else {
                        Image(systemName: "trash")
                    }
                }
                .frame(width: 18, height: 18)
            }
            .buttonStyle(.borderless)
            .disabled(model.deletingShare)
            .screenshotSafeHelp(strings.deleteLink)
            .accessibilityLabel(strings.deleteLink)
        }
        .padding(.horizontal, 9)
        .frame(width: embedded ? nil : 320, height: 48)
        .background(Color.primary.opacity(0.055),
                    in: RoundedRectangle(cornerRadius: 9, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 9, style: .continuous)
                .strokeBorder(Color.primary.opacity(0.09), lineWidth: 1)
        )
    }

    /// A code was found: open the result panel that spells out its content.
    private var qrControl: some View {
        Button(action: showQR) {
            Image(systemName: "qrcode")
                .frame(width: embedded ? 28 : 22, height: embedded ? 28 : 18)
        }
        .modifier(ScreenshotPreviewActionStyle(embedded: embedded))
        .controlSize(.small)
        .tint(.accentColor)
        .screenshotSafeHelp(L10n.shared.s.qrResultTitle)
        .accessibilityLabel(L10n.shared.s.qrResultTitle)
    }

    @ViewBuilder private var shareMenu: some View {
        switch ScreenshotQuickPreviewController.shareLinkClick(embedded: embedded) {
        case .opensDurations:
            shareMenuChrome(Menu { shareDurations } label: { shareMenuLabel },
                            help: strings.shareSectionTitle)
                .menuStyle(.borderlessButton).menuIndicator(.hidden)
                .frame(width: 28, height: 28)
        case .sharesSavedLink:
            shareMenuChrome(Menu { shareDurations } label: { shareMenuLabel } primaryAction: {
                share(.saved())
            }, help: "\(strings.shareSectionTitle) · \(ScreenshotShareDuration.saved().title(strings))")
                .menuStyle(.button).buttonStyle(.bordered).controlSize(.small)
        }
    }

    private var shareDurations: some View {
        ForEach(ScreenshotShareDuration.allCases) { duration in
            Button(duration.title(strings)) { share(duration) }
        }
    }

    private var shareMenuLabel: some View {
        Group {
            if model.sharing {
                ProgressView()
                    .controlSize(.small)
            } else {
                Image(systemName: "link")
            }
        }
        .frame(width: embedded ? 28 : 22, height: embedded ? 28 : 18)
    }

    private func shareMenuChrome(_ menu: some View, help: String) -> some View {
        menu
            .disabled(model.sharing)
            .screenshotSafeHelp(model.sharing ? strings.sharingHUD : help)
            .accessibilityLabel(strings.shareSectionTitle)
    }

    private func actionButton(symbol: String,
                              title: String,
                              shortcut: String,
                              disabled: Bool = false,
                              action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Group {
                if embedded { Image(systemName: symbol).frame(width: 28, height: 28) }
                else { Label(title, systemImage: symbol) }
            }
                .font(.system(size: 11, weight: .medium))
                .lineLimit(1)
                .minimumScaleFactor(0.78)
        }
        .modifier(ScreenshotPreviewActionStyle(embedded: embedded))
        .controlSize(.small)
        .disabled(disabled)
        .opacity(disabled ? 0.4 : 1)
        .screenshotSafeHelp("\(title)  (\(shortcut))")
        .accessibilityLabel(title)
    }
}

/// The island header has its own surface; native button bezels waste the space
/// needed by its title at the minimum width. Keep 28-point targets in that host.
private struct ScreenshotPreviewActionStyle: ViewModifier {
    let embedded: Bool
    var prominent = false

    @ViewBuilder func body(content: Content) -> some View {
        if embedded {
            content.buttonStyle(NotchButtonStyle(cornerRadius: 8))
                .background(prominent ? Color.white.opacity(0.14) : .clear,
                            in: RoundedRectangle(cornerRadius: 8))
        } else if prominent {
            content.buttonStyle(.borderedProminent)
        } else {
            content.buttonStyle(.bordered)
        }
    }
}
