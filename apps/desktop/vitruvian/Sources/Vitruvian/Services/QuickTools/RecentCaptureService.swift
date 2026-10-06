// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import AppKit
import AVFoundation
import Carbon.HIToolbox
import ImageIO
import SwiftUI
import VitruvianCore
import VitruvianDesign

/// A bounded, on-demand list of captures. Screenshots live in this cache so
/// copy-only captures can return after their preview closes. Recordings keep
/// only their file path and a small thumbnail, never a second video copy.
@MainActor
package final class RecentCaptureService: ObservableObject {
    package static let shared = RecentCaptureService()

    @Published package private(set) var entries: [RecentCaptureEntry] = []
    @Published package private(set) var shortcutRegistrationFailed = false

    // The default manager is safe from any thread; the SDK does not mark it Sendable.
    nonisolated(unsafe) private let manager = FileManager.default
    private lazy var hotkey: QuickToolHotkey = RecentCaptureService.historyShortcut(opening: { [weak self] in
        self?.showHistoryWindow()
    })
    private let queue = DispatchQueue(label: "com.vitruviansoftware.vitruvian.recent-captures",
                                      qos: .utility)
    private let generationLock = NSLock()
    /// Thread-safe; the queue empties it on a clear.
    nonisolated(unsafe) private let thumbnailCache = NSCache<NSString, NSImage>()
    /// Where the captures live, found once; nil without a caches folder.
    private let root: URL?
    /// Touched only on `queue`.
    nonisolated(unsafe) private let store: RecentCaptureStore
    /// Guarded by `generationLock`.
    nonisolated(unsafe) private var clearGeneration = 0
    private var panel: NSPanel?
    private var panelKeyMonitor: Any?
    private var panelLocalClickMonitor: Any?
    private var panelGlobalClickMonitor: Any?
    private var panelActivationObserver: NSObjectProtocol?

    private init() {
        root = Self.cachesRoot(in: FileManager.default)
        store = RecentCaptureStore(directoryURL: root)
        thumbnailCache.countLimit = ScreenshotSupport.recentCaptureLimit
        reload()
    }

    /// The history shortcut, wired to open the palette. Its id is the one
    /// the hand-assigned quick tool range keeps for it.
    package static func historyShortcut(opening open: @escaping () -> Void) -> QuickToolHotkey {
        let hotkey = QuickToolHotkey(id: 21)
        hotkey.onPress = open
        return hotkey
    }

    package func syncWithPreferences() {
        let available = AppFeature.screenshot.isAvailable || AppFeature.screenRecorder.isAvailable
        let enabled = available
            && UserDefaults.standard.bool(forKey: DefaultsKey.recentCapturesShortcutEnabled)
        let shortcut = GlobalShortcut.saved(for: DefaultsKey.recentCapturesShortcut,
                                            fallback: .recentCapturesDefault)
        shortcutRegistrationFailed = !hotkey.sync(enabled: enabled, shortcut: shortcut,
                                                  storageKey: DefaultsKey.recentCapturesShortcut)
        if !available { hideHistoryWindow() }
    }

    package func suspend() {
        hotkey.unregister()
        hideHistoryWindow()
    }

    // MARK: - History palette

    package func showHistoryWindow() {
        guard Thread.isMainThread else {
            DispatchQueue.main.async { [weak self] in self?.showHistoryWindow() }
            return
        }
        guard AppFeature.screenshot.isAvailable || AppFeature.screenRecorder.isAvailable else {
            return
        }
        let anchor = NSApp.keyWindow?.isVisible == true ? NSApp.keyWindow : nil
        let panel = ensurePanel()
        reload()
        position(panel, over: anchor)
        installPanelMonitors(for: panel)
        panel.alphaValue = 0
        panel.orderFrontRegardless()
        panel.makeKey()
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.12
            panel.animator().alphaValue = 1
        }
    }

    package func hideHistoryWindow() {
        guard Thread.isMainThread else {
            DispatchQueue.main.async { [weak self] in self?.hideHistoryWindow() }
            return
        }
        removePanelMonitors()
        panel?.orderOut(nil)
    }

    private final class KeyableHistoryPanel: OverlayPanel {
        override var canBecomeKey: Bool { true }
    }

    /// The palette's panel, before its content.
    package static func makeHistoryPanel() -> NSPanel {
        let panel = KeyableHistoryPanel(
            contentRect: NSRect(x: 0, y: 0, width: 468, height: 360),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false)
        panel.title = FeatureStrings.recentCaptures(L10n.shared.language).title
        panel.isReleasedWhenClosed = false
        panel.isMovableByWindowBackground = true
        // The palette is summoned from other apps. A panel that hides on deactivate
        // stays off screen until this app activates, so it would appear late.
        panel.hidesOnDeactivate = false
        panel.isFloatingPanel = true
        panel.level = .floating
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = false
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .ignoresCycle]
        return panel
    }

    private func ensurePanel() -> NSPanel {
        if let panel { return panel }
        let panel = Self.makeHistoryPanel()
        let host = NSHostingController(rootView: ServiceViews.factory.recentCaptures(
            onClose: { [weak self] in self?.hideHistoryWindow() }))
        host.sizingOptions = .preferredContentSize
        panel.contentViewController = host
        self.panel = panel
        return panel
    }

    private func position(_ panel: NSPanel, over anchor: NSWindow?) {
        panel.contentViewController?.view.layoutSubtreeIfNeeded()
        let size = panel.contentViewController?.view.fittingSize
            ?? NSSize(width: 468, height: 360)
        let screen = anchor?.screen?.visibleFrame ?? NSScreen.pointerVisibleFrame
        let center = anchor.map { CGPoint(x: $0.frame.midX, y: $0.frame.midY) }
            ?? CGPoint(x: screen.midX, y: screen.midY)
        let x = min(max(center.x - size.width / 2, screen.minX + 16),
                    screen.maxX - size.width - 16)
        let y = min(max(center.y - size.height / 2, screen.minY + 16),
                    screen.maxY - size.height - 16)
        panel.setFrame(NSRect(origin: CGPoint(x: x, y: y), size: size),
                       display: true,
                       animate: false)
    }

    private func refreshPanelLayout() {
        guard let panel, panel.isVisible else { return }
        panel.contentViewController?.view.layoutSubtreeIfNeeded()
        let size = panel.contentViewController?.view.fittingSize ?? panel.frame.size
        let screen = panel.screen?.visibleFrame ?? NSScreen.pointerVisibleFrame
        var frame = panel.frame
        frame.origin.y = min(max(frame.maxY - size.height, screen.minY + 16),
                             screen.maxY - size.height - 16)
        frame.origin.x = min(max(frame.origin.x, screen.minX + 16),
                             screen.maxX - size.width - 16)
        frame.size = size
        panel.setFrame(frame, display: true, animate: false)
    }

    private func installPanelMonitors(for panel: NSPanel) {
        removePanelMonitors()
        panelKeyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) {
            [weak self, weak panel] event in
            guard event.window === panel else { return event }
            if Int(event.keyCode) == kVK_Escape {
                self?.hideHistoryWindow()
                return nil
            }
            return event
        }
        panelLocalClickMonitor = NSEvent.addLocalMonitorForEvents(
            matching: [.leftMouseDown, .rightMouseDown]) { [weak self, weak panel] event in
                if event.window !== panel { self?.hideHistoryWindow() }
                return event
            }
        panelGlobalClickMonitor = NSEvent.addGlobalMonitorForEvents(
            matching: [.leftMouseDown, .rightMouseDown]) { [weak self] _ in
                self?.hideHistoryWindow()
            }
        panelActivationObserver = Self.observeOtherAppActivation { [weak self] in
            self?.hideHistoryWindow()
        }
    }

    /// Runs `handler` when another app comes forward, which is when the
    /// palette leaves. It never hides on deactivation, so it reads the
    /// workspace's activations rather than this app resigning active; this
    /// app, and the accessibility keyboard typing into it, do not count.
    package static func observeOtherAppActivation(
        in center: NotificationCenter = NSWorkspace.shared.notificationCenter,
        ownBundleIdentifiers: [String?] = [Bundle.main.bundleIdentifier, AssistiveKeyboard.bundleID],
        _ handler: @escaping @MainActor @Sendable () -> Void
    ) -> NSObjectProtocol {
        center.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification,
            object: nil,
            queue: .main) { notification in
                // Read here: the notification itself never crosses to the main actor.
                let app = notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication
                // Delivered on the main queue.
                MainActor.assumeIsolated {
                    guard let app, !ownBundleIdentifiers.contains(app.bundleIdentifier) else { return }
                    handler()
                }
            }
    }

    private func removePanelMonitors() {
        if let panelKeyMonitor { NSEvent.removeMonitor(panelKeyMonitor) }
        if let panelLocalClickMonitor { NSEvent.removeMonitor(panelLocalClickMonitor) }
        if let panelGlobalClickMonitor { NSEvent.removeMonitor(panelGlobalClickMonitor) }
        if let panelActivationObserver {
            NSWorkspace.shared.notificationCenter.removeObserver(panelActivationObserver)
        }
        panelKeyMonitor = nil
        panelLocalClickMonitor = nil
        panelGlobalClickMonitor = nil
        panelActivationObserver = nil
    }

    nonisolated private static func cachesRoot(in manager: FileManager) -> URL? {
        guard let base = manager.urls(for: .cachesDirectory, in: .userDomainMask).first,
              let bundleID = Bundle.main.bundleIdentifier
        else { return nil }
        return base
            .appendingPathComponent(bundleID, isDirectory: true)
            .appendingPathComponent("RecentCaptures", isDirectory: true)
    }

    package func reload() {
        queue.async { [weak self] in
            guard let self else { return }
            guard self.store.loadIfNeeded() else { return }
            self.pruneMissingEntries()
            self.store.persist()
            self.publish()
        }
    }

    package func recordScreenshot(_ capture: ScreenshotSelectionController.Capture) {
        let id = UUID()
        let screenshotName = "\(id.uuidString).png"
        let thumbnailName = "\(id.uuidString)-thumbnail.png"
        let entry = RecentCaptureEntry(
            id: id,
            kind: .screenshot,
            createdAt: Date(),
            screenshotName: screenshotName,
            recordingPath: nil,
            thumbnailName: thumbnailName,
            scale: Double(capture.scale),
            anchorX: Double(capture.anchorRect.origin.x),
            anchorY: Double(capture.anchorRect.origin.y),
            anchorWidth: Double(capture.anchorRect.width),
            anchorHeight: Double(capture.anchorRect.height))
        let image = capture.image
        let scale = capture.scale

        queue.async { [weak self] in
            guard let self, let root = self.root else { return }
            guard self.store.loadIfNeeded() else { return }
            do {
                guard let full = ScreenshotRenderer.pngData(from: image, scale: scale),
                      let smallImage = Self.thumbnail(from: image),
                      let small = ScreenshotRenderer.pngData(from: smallImage, scale: 1)
                else { return }
                try RecentCaptureStore.write(full, to: root.appendingPathComponent(screenshotName))
                do {
                    try RecentCaptureStore.write(small, to: root.appendingPathComponent(thumbnailName))
                } catch {
                    try? self.manager.removeItem(at: root.appendingPathComponent(screenshotName))
                    try? self.manager.removeItem(at: root.appendingPathComponent(thumbnailName))
                    throw error
                }
                self.prepend(entry)
            } catch {
                return
            }
        }
    }

    package func recordRecording(at url: URL) {
        guard RecentCaptureStore.isRegularFile(url) else { return }
        let id = UUID()
        let thumbnailName = "\(id.uuidString)-thumbnail.png"
        let createdAt = Date()
        let generation = currentClearGeneration()

        Task { @MainActor [weak self] in
            let thumbnail = await Self.recordingThumbnail(at: url)
            self?.storeRecording(at: url, id: id, createdAt: createdAt,
                                 thumbnailName: thumbnailName, thumbnail: thumbnail,
                                 generation: generation)
        }
    }

    private func storeRecording(at url: URL,
                                id: UUID,
                                createdAt: Date,
                                thumbnailName: String,
                                thumbnail: CGImage?,
                                generation: Int) {
        queue.async { [weak self] in
            guard let self, self.currentClearGeneration() == generation,
                  let root = self.root, RecentCaptureStore.isRegularFile(url) else { return }
            guard self.store.loadIfNeeded() else { return }
            var storedThumbnail: String?
            if let thumbnail,
               let data = ScreenshotRenderer.pngData(from: thumbnail, scale: 1),
               (try? RecentCaptureStore.write(data, to: root.appendingPathComponent(thumbnailName))) != nil {
                storedThumbnail = thumbnailName
            }
            guard self.currentClearGeneration() == generation else {
                if let storedThumbnail {
                    try? self.manager.removeItem(
                        at: root.appendingPathComponent(storedThumbnail))
                }
                return
            }
            let entry = RecentCaptureEntry(
                id: id,
                kind: .recording,
                createdAt: createdAt,
                screenshotName: nil,
                recordingPath: url.standardizedFileURL.path,
                thumbnailName: storedThumbnail,
                scale: nil,
                anchorX: nil,
                anchorY: nil,
                anchorWidth: nil,
                anchorHeight: nil)
            self.prepend(entry)
        }
    }

    package func remove(_ entry: RecentCaptureEntry) {
        queue.async { [weak self] in
            guard let self else { return }
            guard self.store.loadIfNeeded() else { return }
            guard self.store.entries.contains(where: { $0.id == entry.id }) else { return }
            self.store.entries.removeAll { $0.id == entry.id }
            self.store.persist()
            self.publish()
        }
    }

    package func clear() {
        generationLock.lock()
        clearGeneration &+= 1
        generationLock.unlock()
        queue.async { [weak self] in
            guard let self else { return }
            guard self.store.loadIfNeeded() else { return }
            self.store.entries.removeAll()
            self.store.persist()
            self.thumbnailCache.removeAllObjects()
            self.publish()
        }
    }

    package func thumbnail(for entry: RecentCaptureEntry) -> NSImage? {
        guard let name = entry.thumbnailName, Self.isSafeName(name), let root else { return nil }
        let key = name as NSString
        if let cached = thumbnailCache.object(forKey: key) { return cached }
        guard let image = NSImage(contentsOf: root.appendingPathComponent(name)) else { return nil }
        thumbnailCache.setObject(image, forKey: key)
        return image
    }

    package func open(_ entry: RecentCaptureEntry) {
        hideHistoryWindow()
        switch entry.kind {
        case .screenshot:
            restoreScreenshot(entry)
        case .recording:
            guard let url = entry.recordingURL, RecentCaptureStore.isRegularFile(url) else {
                remove(entry)
                NSSound.beep()
                return
            }
            appShell()?.closePopover()
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.12) {
                NSWorkspace.shared.open(url)
            }
        }
    }

    private func restoreScreenshot(_ entry: RecentCaptureEntry) {
        queue.async { [weak self] in
            guard let self, let capture = self.loadScreenshot(entry) else {
                DispatchQueue.main.async { [weak self] in
                    self?.remove(entry)
                    NSSound.beep()
                }
                return
            }
            DispatchQueue.main.async {
                appShell()?.closePopover()
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.12) {
                    ScreenshotService.shared.restorePreview(capture)
                }
            }
        }
    }

    nonisolated private func loadScreenshot(_ entry: RecentCaptureEntry)
        -> ScreenshotSelectionController.Capture? {
        guard entry.kind == .screenshot,
              let name = entry.screenshotName,
              Self.isSafeName(name),
              let root,
              let scale = entry.scale,
              scale.isFinite, scale > 0,
              let source = CGImageSourceCreateWithURL(
                root.appendingPathComponent(name) as CFURL,
                [kCGImageSourceShouldCache: false] as CFDictionary),
              let image = CGImageSourceCreateImageAtIndex(
                source, 0,
                [kCGImageSourceShouldCacheImmediately: true] as CFDictionary)
        else { return nil }
        let anchor = CGRect(
            x: entry.anchorX ?? 0,
            y: entry.anchorY ?? 0,
            width: entry.anchorWidth ?? 0,
            height: entry.anchorHeight ?? 0)
        return ScreenshotSelectionController.Capture(
            image: image, scale: CGFloat(scale), anchorRect: anchor)
    }

    nonisolated private func pruneMissingEntries() {
        var kept: [RecentCaptureEntry] = []
        for entry in store.entries where entryExists(entry) {
            kept.append(entry)
        }
        let keepIDs = cappedIDs(for: kept)
        store.entries = kept.filter { keepIDs.contains($0.id) }
    }

    nonisolated private func prepend(_ entry: RecentCaptureEntry) {
        if let path = entry.recordingPath,
           let previous = store.entries.first(where: { $0.recordingPath == path }) {
            store.entries.removeAll { $0.id == previous.id }
        }
        store.entries.append(entry)
        store.entries.sort { $0.createdAt > $1.createdAt }
        let keepIDs = cappedIDs(for: store.entries)
        store.entries.removeAll { !keepIDs.contains($0.id) }
        store.persist()
        publish()
    }

    nonisolated private func entryExists(_ entry: RecentCaptureEntry) -> Bool {
        switch entry.kind {
        case .screenshot:
            guard let name = entry.screenshotName, Self.isSafeName(name), let root else { return false }
            return RecentCaptureStore.isRegularFile(root.appendingPathComponent(name))
        case .recording:
            guard let url = entry.recordingURL else { return false }
            return RecentCaptureStore.isRegularFile(url)
        }
    }

    nonisolated private func cappedIDs(for entries: [RecentCaptureEntry]) -> Set<UUID> {
        var screenshotBytes: [UUID: Int64] = [:]
        if let root {
            for entry in entries where entry.kind == .screenshot {
                guard let name = entry.screenshotName, Self.isSafeName(name),
                      let size = try? root.appendingPathComponent(name).resourceValues(
                        forKeys: [.fileSizeKey]).fileSize
                else { continue }
                screenshotBytes[entry.id] = Int64(size)
            }
        }
        return Set(ScreenshotSupport.cappedRecentCaptureIDs(
            entries.map(\.id), screenshotBytes: screenshotBytes))
    }

    nonisolated private func publish() {
        let value = store.entries
        DispatchQueue.main.async { [weak self] in
            self?.entries = value
            DispatchQueue.main.async { [weak self] in self?.refreshPanelLayout() }
        }
    }

    nonisolated private func currentClearGeneration() -> Int {
        generationLock.lock()
        defer { generationLock.unlock() }
        return clearGeneration
    }

    nonisolated private static func isSafeName(_ name: String) -> Bool {
        !name.isEmpty && name == URL(fileURLWithPath: name).lastPathComponent
    }

    nonisolated private static func thumbnail(from image: CGImage) -> CGImage? {
        let maximum = CGFloat(360)
        let longest = CGFloat(max(image.width, image.height))
        let factor = min(1, maximum / max(1, longest))
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
        else { return nil }
        context.interpolationQuality = .high
        context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        return context.makeImage()
    }

    nonisolated private static func recordingThumbnail(at url: URL) async -> CGImage? {
        if url.pathExtension.lowercased() == "gif" {
            guard let source = CGImageSourceCreateWithURL(url as CFURL, nil) else { return nil }
            let options: [CFString: Any] = [
                kCGImageSourceCreateThumbnailFromImageAlways: true,
                kCGImageSourceCreateThumbnailWithTransform: true,
                kCGImageSourceThumbnailMaxPixelSize: 360,
            ]
            return CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary)
        }
        let generator = AVAssetImageGenerator(asset: AVURLAsset(url: url))
        generator.appliesPreferredTrackTransform = true
        generator.maximumSize = CGSize(width: 360, height: 360)
        return try? await generator.image(at: .zero).image
    }
}
