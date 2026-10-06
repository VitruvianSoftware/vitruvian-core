// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import AppKit
import Combine
import VitruvianCore
import VitruvianDesign

/// The area a watch reads: a part of one window, followed wherever the
/// window goes, even covered or on another Space, or a fixed part of a
/// display when no window was under it.
package struct NotchWatchTarget: Equatable {
    package let windowID: CGWindowID?
    package let displayID: CGDirectDisplayID
    /// In points from the window's top-left corner; for a display, its
    /// pixels from the display's top-left corner.
    package let crop: CGRect
    package let appName: String
    package let processID: pid_t?
    package let windowTitle: String?

    package var appIcon: NSImage? {
        processID.flatMap { NSRunningApplication(processIdentifier: $0)?.icon }
    }

    // Spelled out because a memberwise initializer never leaves its module.
    package init(windowID: CGWindowID?, displayID: CGDirectDisplayID, crop: CGRect, appName: String, processID: pid_t?, windowTitle: String?) {
        self.windowID = windowID
        self.displayID = displayID
        self.crop = crop
        self.appName = appName
        self.processID = processID
        self.windowTitle = windowTitle
    }
}

package enum NotchWatchState: Equatable {
    case idle
    case watching
    /// The window is there but cannot be read now, as when it is minimized
    /// or the screen is locked. Watching continues when it can.
    case hidden
    case finished(NotchWatchOutcome)
}

/// Turns any part of any window into a live activity: reads it every second
/// or two on the Mac itself, shows the reading in the closed island and
/// speaks up once the rule the person chose is met.
@MainActor
package final class NotchWatchService: ObservableObject {
    package static let shared = NotchWatchService()

    @Published package private(set) var target: NotchWatchTarget?
    @Published package private(set) var state: NotchWatchState = .idle
    @Published package private(set) var preview: CGImage?
    @Published package private(set) var text = ""
    @Published package private(set) var headline = ""
    /// The line chosen to show in the island; nil picks one automatically.
    @Published package private(set) var headlineLine: Int?
    @Published package private(set) var startedAt: Date?
    @Published package private(set) var condition: NotchWatchCondition = NotchWatchCondition.saved()
    @Published package private(set) var matchText = ""
    @Published package private(set) var matchNumber: Double?
    /// Screen Recording was turned off while watching: the area stays
    /// hidden until it is allowed again.
    @Published package private(set) var permissionMissing = false

    /// The page is on screen: read more often so the preview feels live.
    package var pageVisible = false {
        didSet { if pageVisible, !oldValue, isActive { restartLoop() } }
    }

    package var isActive: Bool { target != nil && (state == .watching || state == .hidden) }
    /// An area without text shows itself in the closed island instead.
    package var showsThumbnail: Bool { headline.isEmpty && preview != nil }
    package var isSelecting: Bool { selection != nil }

    private var tracker = NotchWatchTracker(condition: .changes)
    private var loop: Task<Void, Never>?
    private var generation = UUID()
    private var lastReading = NotchWatchLastReading()
    private var regionCapture: ScreenshotCaptureEngine.RegionCapture?
    private var selection: ScreenshotSelectionController?
    private lazy var tone = NSSound(contentsOfFile: "/System/Library/Sounds/Glass.aiff", byReference: false)

    private init() {}

    package func syncWithPreferences() {
        guard NotchWatchSupport.isEnabled() else { stop(); return }
        if isActive, loop == nil { restartLoop() }
    }

    // MARK: Choosing

    package func chooseArea() {
        guard NotchWatchSupport.isEnabled(), selection == nil, !ScreenshotSelectionController.isSessionOnScreen else { return }
        // Asked of the system: nothing keeps the shared state current for Watch.
        guard CGPreflightScreenCaptureAccess() else {
            Permissions.shared.requestScreenRecording()
            return
        }
        let notch = NotchService.shared
        let controller = ScreenshotSelectionController(
            freeze: false, includePointer: false, showLastRegion: false, hideVitruvianWindows: true,
            protectedWindowIDs: { notch.protectedWindowIDs.union(notch.captureChromeWindowIDs) },
            purpose: FeatureStrings.notchWatch(L10n.shared.language).purpose, mode: .geometry)
        selection = controller
        controller.begin { [weak self] outcome in
            guard let self else { return }
            self.selection = nil
            guard case .region(let region) = outcome else { return }
            Task { @MainActor [weak self] in await self?.watch(region) }
        }
    }

    @MainActor
    private func watch(_ region: RecorderSupport.Region) async {
        let notch = NotchService.shared
        let protected = notch.protectedWindowIDs.union(notch.captureChromeWindowIDs)
        let picked: (id: CGWindowID, crop: CGRect)?
        if let windowID = region.windowID, let bounds = Self.windowInfo(windowID)?.bounds {
            picked = (windowID, CGRect(origin: .zero, size: bounds.size))
        } else {
            // The area in the window server's top-left coordinates, as the
            // window list gives each window's frame.
            let mainHeight = NSScreen.screens.first?.frame.height ?? 0
            let area = CGRect(x: region.anchorRect.minX, y: mainHeight - region.anchorRect.maxY,
                              width: region.anchorRect.width, height: region.anchorRect.height)
            let windows = ScreenshotCaptureEngine.pickableWindows(hideVitruvianWindows: true,
                                                                  protectedWindowIDs: protected)
            picked = NotchWatchSupport.windowCrop(for: area, windows: windows)
        }
        let target: NotchWatchTarget
        if let picked, let info = Self.windowInfo(picked.id) {
            regionCapture = nil
            target = NotchWatchTarget(windowID: picked.id, displayID: region.displayID, crop: picked.crop,
                                      appName: info.appName, processID: info.processID, windowTitle: info.title)
        } else {
            // Nothing but the desktop or the menu bar under it: read that
            // part of the display as it is.
            guard let capture = await ScreenshotCaptureEngine.prepareDisplayRegion(
                displayID: region.displayID, pixelRect: region.pixelRect, includePointer: false,
                hideVitruvianWindows: true, protectedWindowIDs: protected) else { return }
            regionCapture = capture
            target = NotchWatchTarget(windowID: nil, displayID: region.displayID, crop: region.pixelRect,
                                      appName: FeatureStrings.notchWatch(L10n.shared.language).title,
                                      processID: nil, windowTitle: nil)
        }
        // Another area has other lines: its reading starts automatic again.
        headlineLine = nil
        begin(target)
        notch.open(.watch, feedback: false)
    }

    // MARK: Watching

    package func watchAgain() {
        guard let target, NotchWatchSupport.isEnabled() else { return }
        if let windowID = target.windowID, Self.windowInfo(windowID) == nil { return }
        begin(target)
    }

    package var canWatchAgain: Bool {
        guard let target, case .finished = state else { return false }
        return target.windowID.map { Self.windowInfo($0) != nil } ?? (regionCapture != nil)
    }

    package func stop() {
        cancelLoop()
        target = nil
        state = .idle
        preview = nil
        text = ""
        headline = ""
        startedAt = nil
        headlineLine = nil
        regionCapture = nil
        lastReading = NotchWatchLastReading()
        permissionMissing = false
    }

    package func setHeadlineLine(_ line: Int?) {
        guard line != headlineLine else { return }
        headlineLine = line
        headline = NotchWatchSupport.headline(from: text, line: line)
    }

    package func setCondition(_ condition: NotchWatchCondition) {
        guard condition != self.condition else { return }
        self.condition = condition
        UserDefaults.standard[Preferences.notchWatchCondition] = condition.rawValue
        resetTracker()
    }

    /// Typed words and numbers apply once confirmed, so a half-typed "1" on
    /// the way to 100 cannot end the watch early.
    package func setMatchText(_ text: String) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed != matchText else { return }
        matchText = trimmed
        if condition == .contains { resetTracker() }
    }

    /// Read as the page writes numbers, so 1.000 is a thousand where a
    /// comma starts the decimals.
    package func setMatchNumber(_ text: String) {
        let value = NotchWatchSupport.typedNumber(text, locale: L10n.shared.language.formattingLocale())
        guard value != matchNumber else { return }
        matchNumber = value
        if condition == .reaches { resetTracker() }
    }

    private func begin(_ target: NotchWatchTarget) {
        // Another area must not show the last one's picture while it is first read.
        if target != self.target { preview = nil }
        self.target = target
        state = .watching
        startedAt = Date()
        lastReading = NotchWatchLastReading()
        permissionMissing = false
        text = ""
        headline = ""
        tracker = makeTracker()
        // The alert falls back to a notification where the island cannot
        // show itself; the system asks once, and only before the first watch.
        Notifier.requestPermission()
        restartLoop()
    }

    /// A new rule starts from what the area shows now.
    private func resetTracker() {
        tracker = makeTracker()
        guard isActive, state == .watching, lastReading.signature != nil else { return }
        if let outcome = tracker.observe(signature: lastReading.signature, reading: text, at: Date()) { finish(outcome) }
    }

    private func makeTracker() -> NotchWatchTracker {
        NotchWatchTracker(condition: condition, text: matchText, target: matchNumber, locale: .autoupdatingCurrent)
    }

    private func restartLoop() {
        cancelLoop()
        let generation = UUID()
        self.generation = generation
        loop = Task { @MainActor [weak self] in
            while !Task.isCancelled {
                guard let self, self.generation == generation, self.isActive else { return }
                await self.read()
                guard self.generation == generation, self.isActive else { return }
                let interval = self.pageVisible && NotchService.shared.expanded
                    ? NotchWatchSupport.visibleInterval : NotchWatchSupport.backgroundInterval
                do { try await Task.sleep(for: .seconds(interval)) } catch { return }
            }
        }
    }

    private func cancelLoop() {
        loop?.cancel()
        loop = nil
        generation = UUID()
    }

    @MainActor
    private func read() async {
        guard let target else { return }
        let generation = self.generation
        var window: WindowInfo?
        if let windowID = target.windowID {
            guard let info = Self.windowInfo(windowID) else { finish(.closed); return }
            window = info
        }
        let attempt = await Self.areaPicture(allowed: { CGPreflightScreenCaptureAccess() }) { () async -> CGImage? in
            if permissionMissing { permissionMissing = false }
            guard let windowID = target.windowID, let info = window else { return await regionCapture?.image() }
            var captured = await WindowPreviewProvider.captureViaWindowServer(windowID)
            if captured == nil, info.onScreen {
                captured = await ScreenshotCaptureEngine.captureWindow(windowID, scale: 2)
            }
            return captured.flatMap { full in
                NotchWatchSupport.pixelCrop(target.crop, windowSize: info.bounds.size,
                                            imageSize: CGSize(width: full.width, height: full.height))
                    .flatMap { full.cropping(to: $0) }
            }
        }
        // Turned off in System Settings: nothing can be read.
        guard case .taken(let taken) = attempt else {
            if state != .hidden { state = .hidden }
            if !permissionMissing { permissionMissing = true }
            return
        }
        guard self.generation == generation, isActive else { return }
        guard let image = taken else {
            if state != .hidden { state = .hidden }
            return
        }
        if state != .watching { state = .watching }
        // A whole window can be large: its picture is summed up off the main thread.
        let picture = await Task.detached(priority: .utility) { NotchWatchSupport.fingerprint(image) }.value
        guard self.generation == generation, isActive else { return }
        if let still = lastReading.stillSignature(of: picture, at: Date()) {
            // The area looks as it did: no need to read it again, but it
            // confirms a change and lets time settle it.
            if let outcome = tracker.observe(signature: still, reading: text, at: Date()) { finish(outcome) }
            return
        }
        let languages = MediaSupport.recognitionLanguages(for: L10n.shared.language.rawValue)
        let (area, recognized) = await Task.detached(priority: .utility) { () -> (CGImage, String) in
            let area = NotchWatchSupport.standalone(image)
            let source = Self.scaledForRecognition(area) ?? area
            switch ScreenTextService.outcome(for: source, detectQRCodes: false, removeLineBreaks: false,
                                             fallbackLanguages: languages) {
            case .text(let text): return (area, text)
            case .qr, .empty: return (area, "")
            }
        }.value
        // Kept only once read: a reading dropped halfway must not leave the
        // area marked as read, or a still area would never be read again.
        guard self.generation == generation, isActive else { return }
        let signature = lastReading.keep(recognized, of: picture, at: Date())
        preview = area
        text = recognized
        let headline = NotchWatchSupport.headline(from: recognized, line: headlineLine)
        if headline != self.headline { self.headline = headline }
        if let outcome = tracker.observe(signature: signature, reading: recognized, at: Date()) { finish(outcome) }
    }

    private func finish(_ outcome: NotchWatchOutcome) {
        guard let target, isActive else { return }
        cancelLoop()
        state = .finished(outcome)
        let strings = FeatureStrings.notchWatch(L10n.shared.language)
        let title = strings.outcome(outcome)
        if UserDefaults.standard[Preferences.notchWatchSound] {
            if let tone { tone.stop(); tone.play() } else { NSSound.beep() }
        }
        let notch = NotchService.shared
        let onPage = notch.expanded && notch.selected == .watch
        let shown = onPage || notch.show(NotchNotice(event: .watch, title: title, detail: target.appName,
                                                     symbol: NotchModule.watch.symbol))
        // Hidden in a full-screen app or while the Mac is locked, the island
        // cannot speak up, and the person is counting on hearing about it.
        if !shown { Notifier.post(title: title, body: target.windowTitle ?? target.appName) }
    }

    /// What a read took of its area.
    package enum AreaPicture {
        /// Screen Recording is off, so nothing was captured.
        case notAllowed
        /// The capture's picture, nil when the area cannot be read now.
        case taken(CGImage?)
    }

    /// Takes the area's picture through `capture`, once `allowed` says Screen
    /// Recording is on. Turned off in System Settings, nothing can be read,
    /// and asking the capture again would only raise the system's prompt.
    package static func areaPicture(allowed: () -> Bool, capture: () async -> CGImage?) async -> AreaPicture {
        guard allowed() else { return .notAllowed }
        return .taken(await capture())
    }

    // MARK: Helpers

    private struct WindowInfo {
        let bounds: CGRect
        let appName: String
        let processID: pid_t?
        let title: String?
        let onScreen: Bool
    }

    private static func windowInfo(_ windowID: CGWindowID) -> WindowInfo? {
        guard let list = CGWindowListCopyWindowInfo([.optionIncludingWindow], windowID) as? [[String: Any]],
              let entry = list.first(where: {
                  ($0[kCGWindowNumber as String] as? NSNumber)?.uint32Value == windowID
              }),
              let boundsDict = entry[kCGWindowBounds as String] as? NSDictionary,
              let bounds = CGRect(dictionaryRepresentation: boundsDict),
              bounds.width > 0, bounds.height > 0 else { return nil }
        let pid = entry[kCGWindowOwnerPID as String] as? pid_t
        let app = pid.flatMap { NSRunningApplication(processIdentifier: $0)?.localizedName }
            ?? entry[kCGWindowOwnerName as String] as? String ?? ""
        let title = (entry[kCGWindowName as String] as? String).flatMap { $0.isEmpty ? nil : $0 }
        return WindowInfo(bounds: bounds, appName: app, processID: pid, title: title,
                          onScreen: entry[kCGWindowIsOnscreen as String] as? Bool ?? false)
    }

    /// Recognition is slower on big areas and no more accurate past a few
    /// hundred pixels, so a large area is read at a smaller size.
    nonisolated private static func scaledForRecognition(_ image: CGImage) -> CGImage? {
        let longest = max(image.width, image.height)
        guard longest > NotchWatchSupport.maximumRecognitionSide else { return nil }
        let scale = CGFloat(NotchWatchSupport.maximumRecognitionSide) / CGFloat(longest)
        let width = max(1, Int(CGFloat(image.width) * scale))
        let height = max(1, Int(CGFloat(image.height) * scale))
        guard let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
                                      space: CGColorSpace(name: CGColorSpace.sRGB) ?? CGColorSpaceCreateDeviceRGB(),
                                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
        context.interpolationQuality = .high
        context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        return context.makeImage()
    }
}
