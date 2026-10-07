// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import AppKit
import Foundation
import VitruvianCore
import VitruvianDesign
import VitruvianServices
import VitruvianUI

/// The production chooser over a scripted desk: two 100-point displays side by
/// side, one window of this app across both, and captures that wait until a
/// check answers them. Its panels are built but never shown, and each picture
/// is a flat bitmap that remembers which windows it left out. No desktop
/// pixels or input events are used.
enum ScreenshotSelectionRefreshContract {
    typealias Controller = ScreenshotSelectionController

    @MainActor final class Desk {
        struct Request {
            let excluded: Set<CGWindowID>
            let continuation: CheckedContinuation<[CGDirectDisplayID: CGImage], Never>
        }

        /// This app's windows: the content window that can be picked, then
        /// the workflow window and another content window.
        static let window: CGWindowID = 900_011
        static let ownWindows: Set<CGWindowID> = [900_011, 900_012, 900_013]

        var requests: [Request] = []
        /// The scale a window capture reports, like a composite recaptured
        /// on a 2x display; `nil` echoes the scale asked for.
        var windowCaptureScale: CGFloat?
        private var answered: Set<Int> = []
        var pointer = CGPoint(x: 50, y: 50)
        let defaults: UserDefaults
        private let suiteName: String
        /// Which windows each picture left out, by picture. The pictures are
        /// kept so an identifier is never reused.
        private var exclusions: [ObjectIdentifier: Set<CGWindowID>] = [:]
        private var pictures: [CGImage] = []
        private var sessions: [Session] = []

        init() {
            let suiteName = "vitru.tests.screenshot-selection-\(UUID().uuidString)"
            self.suiteName = suiteName
            defaults = UserDefaults(suiteName: suiteName)!
            defaults.set(true, forKey: DefaultsKey.screenshotFreeze)
            defaults.set(false, forKey: DefaultsKey.screenshotIncludePointer)
            defaults.set(false, forKey: DefaultsKey.screenshotHideVitruvianWindows)
        }

        func tearDown() {
            sessions.forEach { $0.controller.cancel() }
            for index in requests.indices where !answered.contains(index) {
                complete(index, displays: [])
            }
            defaults.removePersistentDomain(forName: suiteName)
        }

        var environment: Controller.Environment {
            Controller.Environment(
                defaults: defaults,
                displays: {
                    [1, 2].map { (id: CGDirectDisplayID) in
                        let frame = CGRect(x: CGFloat(id - 1) * 100, y: 0, width: 100, height: 100)
                        return Controller.Environment.Display(
                            geometry: ScreenGeometry(displayID: id, frame: frame, visibleFrame: frame, scale: 1),
                            topChromeHeight: 0)
                    }
                },
                pointer: { [unowned self] in self.pointer },
                captureAllDisplays: { [unowned self] _, hide, protected in
                    let excluded = ScreenshotCapturePolicy.excludedWindowIDs(
                        hideVitruvianWindows: hide, ownWindowIDs: Self.ownWindows,
                        protectedWindowIDs: protected)
                    return await withCheckedContinuation {
                        self.requests.append(Request(excluded: excluded, continuation: $0))
                    }
                },
                pickableWindows: { hide, protected in
                    ScreenshotCapturePolicy.canPickWindow(
                        Self.window, isOwnWindow: true, hideVitruvianWindows: hide,
                        protectedWindowIDs: protected)
                        ? [(Self.window, CGRect(x: 0, y: 0, width: 200, height: 100))] : []
                },
                captureWindow: { [unowned self] _, scale in
                    (self.picture(excluding: []), self.windowCaptureScale ?? scale)
                },
                captureDisplay: { [unowned self] _, _, _, _ in self.picture(excluding: []) },
                show: { _, _ in })
        }

        /// A chooser for `tool` the way the capture service starts one, with
        /// its first pictures in.
        func session(_ tool: ScreenCaptureTool) async -> Session {
            let options = ScreenCaptureSelectionOptions(availableTools: ScreenCaptureTool.allCases,
                                                        selectedTool: tool, showsCaptureMenu: true)
            let policy = ScreenshotSupport.unifiedCapturePolicy(
                for: tool,
                screenshotFreeze: defaults.bool(forKey: DefaultsKey.screenshotFreeze),
                screenshotIncludePointer: defaults.bool(forKey: DefaultsKey.screenshotIncludePointer),
                screenshotHideVitruvianWindows: defaults.bool(forKey: DefaultsKey.screenshotHideVitruvianWindows))
            let controller = Controller(
                freeze: policy.freeze,
                includePointer: policy.includePointer,
                showLastRegion: false,
                hideVitruvianWindows: policy.hideVitruvianWindows,
                protectedWindowIDs: { [weak options] in
                    let tool = options?.selectedTool
                    return ScreenshotCapturePolicy.protectedWindowIDs(
                        workflowWindowIDs: [900_012], contentWindowIDs: [900_011, 900_013],
                        honoursVisibilityPreference: tool != nil && tool != .recording)
                },
                mode: policy.usesGeometry ? .geometry : .image,
                supportsScrollingCapture: true,
                screenCaptureOptions: options,
                environment: environment)
            let session = Session(controller: controller, options: options)
            sessions.append(session)
            // A refresh another chooser queued must ask before this one does,
            // or this one's first picture would answer it.
            await drain()
            let first = requests.count
            controller.begin { [weak session] in session?.outcome = $0 }
            await drain()
            if requests.count > first {
                complete(first, displays: [1, 2])
                await drain()
            }
            session.start = "\(tool) freeze \(policy.freeze), \(requests.count - first) captures, "
                + "\(controller.panels.count) panels, over \(controller.isOver), outcome \(String(describing: session.outcome))"
            return session
        }

        /// Answers a capture with a picture of each of `displays`.
        func complete(_ index: Int, displays: [CGDirectDisplayID]) {
            guard requests.indices.contains(index), answered.insert(index).inserted else { return }
            let request = requests[index]
            request.continuation.resume(returning: Dictionary(uniqueKeysWithValues: displays.map {
                ($0, picture(excluding: request.excluded))
            }))
        }

        func excluded(_ picture: CGImage?) -> Set<CGWindowID>? {
            picture.flatMap { exclusions[ObjectIdentifier($0)] }
        }

        /// A flat 100-pixel square: red when this app's window was left out,
        /// green otherwise.
        private func picture(excluding excluded: Set<CGWindowID>) -> CGImage {
            let context = CGContext(data: nil, width: 100, height: 100, bitsPerComponent: 8, bytesPerRow: 0,
                                    space: CGColorSpaceCreateDeviceRGB(),
                                    bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
            context.setFillColor(excluded.contains(Self.window) ? NSColor.red.cgColor : NSColor.green.cgColor)
            context.fill(CGRect(x: 0, y: 0, width: 100, height: 100))
            let image = context.makeImage()!
            pictures.append(image)
            exclusions[ObjectIdentifier(image)] = excluded
            return image
        }
    }

    @MainActor final class Session {
        let controller: Controller
        let options: ScreenCaptureSelectionOptions
        var outcome: Controller.Outcome?
        /// How the chooser came up, for a check that finds it without panels.
        var start = ""
        var panels: [ScreenshotOverlayPanel] { controller.panels }

        init(controller: Controller, options: ScreenCaptureSelectionOptions) {
            self.controller = controller
            self.options = options
        }

        func select(_ tool: ScreenCaptureTool) { options.select(tool) }

        /// The display the outcome came from.
        var outcomeDisplay: CGDirectDisplayID? {
            switch outcome {
            case .captured(let capture)?: return capture.anchorRect.minX >= 100 ? 2 : 1
            case .region(let region)?, .scrollingRegion(let region)?: return region.displayID
            default: return nil
            }
        }
    }

    final class Box<Value> {
        var value: Value
        init(_ value: Value) { self.value = value }
    }

    static func run(_ suite: TestSuite) {
        var completed = false
        Task { @MainActor in
            await checks(suite)
            completed = true
        }
        let deadline = Date().addingTimeInterval(20)
        while !completed && Date() < deadline {
            RunLoop.main.run(until: Date().addingTimeInterval(0.005))
        }
        suite.expect(completed, "capture selection refresh contracts finish without UI")
    }

    @MainActor static func drain() async { for _ in 0..<20 { await Task.yield() } }

    @MainActor static func checks(_ suite: TestSuite) async {
        func expect(_ condition: Bool, _ message: String) { suite.expect(condition, message) }
        _ = NSApplication.shared
        let desk = Desk()
        /// A chooser with a panel on each display, or a failed check saying why not.
        func started(_ tool: ScreenCaptureTool) async -> Session? {
            let session = await desk.session(tool)
            guard session.panels.count == 2 else {
                expect(false, "a started chooser covers both displays: \(session.start)")
                return nil
            }
            return session
        }
        defer { desk.tearDown() }
        let previousRegion = Controller.lastRegion
        defer { Controller.lastRegion = previousRegion }

        for tool in ScreenCaptureTool.allCases {
            for display in [nil, 1, 2, 3] as [CGDirectDisplayID?] {
                guard let c = await started(tool) else { return }
                Controller.lastRegion = display.map { ($0, CGRect(x: 0, y: 0, width: 20, height: 20)) }
                let available = display == 1 || display == 2
                expect(c.controller.offersRepeatLastRegion == (available && tool != .color),
                       "repeat is offered only for a stored display and a tool that accepts regions")
                c.controller.repeatLastRegion()
                expect((c.outcome != nil) == (available && tool != .color),
                       "the repeat hint agrees with the production confirmation path")
                expect(c.outcome == nil || c.outcomeDisplay == display,
                       "repeat targets its stored display even when the pointer is on another display")
            }
        }

        guard let fullScreenScreenshot = await started(.screenshot) else { return }
        fullScreenScreenshot.controller.captureFullScreenFromControl(on: fullScreenScreenshot.panels[0])
        if case .captured? = fullScreenScreenshot.outcome {
            expect(true, "the full-screen control runs the screenshot capture path")
        } else {
            expect(false, "the full-screen control runs the screenshot capture path")
        }
        for tool in [ScreenCaptureTool.recording, .text, .color] {
            guard let other = await started(tool) else { return }
            other.controller.captureFullScreenFromControl(on: other.panels[0])
            expect(other.outcome == nil,
                   "the full-screen control stays unavailable outside screenshot mode")
        }
        guard let scrolling = await started(.screenshot) else { return }
        scrolling.controller.toggleScrollingCapture()
        scrolling.controller.captureFullScreenFromControl(on: scrolling.panels[0])
        expect(scrolling.outcome == nil,
               "scrolling capture keeps its region workflow instead of taking a full-screen capture")

        guard let placement = await started(.screenshot) else { return }
        placement.controller.placeFullScreenControlBelowNotch(
            screenFrame: placement.panels[1].screenFrame, surfaceHeight: 72)
        expect(placement.panels[0].overlayView.notchCaptureControlsHeight == nil
                && placement.panels[1].overlayView.notchCaptureControlsHeight == 72,
               "the island surface height applies only to the display that owns the notch")
        placement.controller.placeFullScreenControlBelowNotch(
            screenFrame: placement.panels[0].screenFrame, surfaceHeight: 40)
        expect(placement.panels[0].overlayView.notchCaptureControlsHeight == 40
                && placement.panels[1].overlayView.notchCaptureControlsHeight == nil,
               "moving capture controls to another display clears the old pill offset")

        guard let surface = await started(.screenshot) else { return }
        let current = Box(true)
        ScreenCaptureService.connectCaptureControlsSurface(surface.options, controller: surface.controller) { _, _ in
            current.value
        }
        surface.options.onCaptureControlsSurfaceChange?(surface.panels[1].screenFrame, 88)
        expect(surface.panels[1].overlayView.notchCaptureControlsHeight == 88
                && surface.panels[0].overlayView.notchCaptureControlsHeight == nil,
               "the capture service forwards live island geometry to its active selection")
        current.value = false
        surface.options.onCaptureControlsSurfaceChange?(surface.panels[0].screenFrame, 12)
        expect(surface.panels[1].overlayView.notchCaptureControlsHeight == 88
                && surface.panels[0].overlayView.notchCaptureControlsHeight == nil,
               "a stale island geometry callback cannot move a replacement selection")

        guard let visibility = await started(.screenshot) else { return }
        let progressChanges = Box<[Bool]>([])
        visibility.options.onSelectionProgressChange = { progressChanges.value.append($0) }
        visibility.controller.setSelectionInProgress(true)
        expect(visibility.panels.allSatisfy { !$0.overlayView.showsFullScreenControl },
               "a selection in progress hides the full-screen action on every display")
        visibility.controller.setSelectionInProgress(false)
        expect(visibility.panels[0].overlayView.showsFullScreenControl
                && !visibility.panels[1].overlayView.showsFullScreenControl
                && progressChanges.value == [true, false],
               "selection progress refreshes both chooser surfaces and notifies the island")

        guard let hover = await started(.screenshot) else { return }
        let hoverView = hover.panels[0].overlayView
        hoverView.layoutSubtreeIfNeeded()
        hoverView.refreshFullScreenControlVisibility()
        let control = hoverView.fullScreenControlFrame
        expect(hoverView.showsFullScreenControl && !control.isEmpty,
               "the full-screen action shows on the display under the pointer")
        hoverView.updatePointerHover(CGPoint(x: control.midX, y: control.midY))
        expect(hoverView.hoveredWindow == nil,
               "hovering the full-screen action suppresses the window capture highlight")
        hoverView.updatePointerHover(CGPoint(x: 5, y: 95))
        expect(hoverView.hoveredWindow?.windowID == Desk.window,
               "window highlighting resumes immediately outside the full-screen action")
        hoverView.setNotchCaptureControlsHeight(180)
        hoverView.fullScreenControlHoverChanged(true)
        hoverView.setNotchCaptureControlsHeight(40)
        expect(hoverView.notchCaptureControlsHeight == 180 && hoverView.hasDeferredNotchCaptureControlsHeight,
               "an island collapse cannot move the full-screen action while it is hovered")
        hoverView.fullScreenControlHoverChanged(false)
        expect(hoverView.notchCaptureControlsHeight == 40 && !hoverView.hasDeferredNotchCaptureControlsHeight,
               "the latest island geometry is applied as soon as the pointer leaves the action")

        guard let hiddenHover = await started(.screenshot) else { return }
        let hiddenHoverView = hiddenHover.panels[0].overlayView
        hiddenHoverView.refreshFullScreenControlVisibility()
        hiddenHoverView.fullScreenControlHoverChanged(true)
        hiddenHoverView.setNotchCaptureControlsHeight(180)
        hiddenHover.select(.recording)
        expect(!hiddenHoverView.showsFullScreenControl
                && !hiddenHoverView.fullScreenControlHovered
                && hiddenHoverView.notchCaptureControlsHeight == 180
                && !hiddenHoverView.hasDeferredNotchCaptureControlsHeight,
               "hiding a hovered full-screen action clears hover and applies deferred island geometry")

        for other in [ScreenCaptureTool.screenshot, .text, .color] {
            for (from, to) in [(ScreenCaptureTool.recording, other), (other, ScreenCaptureTool.recording)] {
                guard let c = await started(from) else { return }
                let request = desk.requests.count
                let panelsBefore = c.panels.map { ObjectIdentifier($0) }
                c.select(to)
                expect(c.panels.allSatisfy { !$0.overlayView.showsFullScreenControl },
                       "changing capture tool hides the full-screen action until the refreshed source is ready")
                expect(c.options.offersRepeatLastRegion == c.controller.offersRepeatLastRegion,
                       "changing capture tool updates the island hint from the same decision as the overlay")
                expect(!c.controller.acceptsCaptureInput,
                       "changing tool blocks capture before the refresh task starts")
                c.controller.confirmRegion(CGRect(x: 0, y: 0, width: 20, height: 20), on: c.panels[0])
                c.controller.confirmWindow(Desk.window, frame: .zero, on: c.panels[0])
                c.controller.captureFullDisplayUnderMouse()
                c.controller.captureFullScreenFromControl(on: c.panels[0])
                Controller.lastRegion = (1, CGRect(x: 0, y: 0, width: 20, height: 20))
                c.controller.repeatLastRegion()
                c.controller.confirmColor(at: .zero, on: c.panels[0])
                expect(c.outcome == nil,
                       "pending refresh rejects region, window, full-screen, repeat and color confirmations")
                await drain()
                expect(desk.requests.count == request + 1, "each changed visibility requests one fresh source")
                desk.complete(request, displays: [1, 2])
                await drain()
                expect(c.controller.acceptsCaptureInput, "successful refresh restores capture input")
                expect(c.panels[0].overlayView.showsFullScreenControl == (to == .screenshot)
                        && !c.panels[1].overlayView.showsFullScreenControl,
                       "a ready source restores the full-screen action only for screenshots on the pointer display")
                expect(c.panels.allSatisfy {
                    desk.excluded($0.frozenImage)?.contains(Desk.window) == (to == .recording)
                }, "both displays use the selected tool visibility")
                expect(c.panels.allSatisfy { $0.overlayView.windows.isEmpty == (to == .recording) },
                       "selectable windows follow the refreshed pixels")
                // A new mode never takes the chooser down to put another up: the
                // same session and its panels take the new pixels behind them.
                expect(!c.controller.isOver && c.panels.map { ObjectIdentifier($0) } == panelsBefore,
                       "changing modes keeps the selection controller and its panels on screen")
                if to == .color {
                    c.controller.confirmColor(at: .zero, on: c.panels[0])
                } else {
                    c.controller.captureFullDisplayUnderMouse()
                }
                expect(c.outcome != nil, "a ready source can be confirmed normally")
            }
        }

        for available: [CGDirectDisplayID] in [[], [1]] {
            guard let failed = await started(.recording) else { return }
            let panel = failed.panels[0]
            let r = desk.requests.count
            failed.select(.screenshot)
            await drain()
            desk.complete(r, displays: available)
            await drain()
            if case .failed? = failed.outcome {
                expect(true, "missing refreshed display closes selection safely")
            } else {
                expect(false, "missing refreshed display closes selection safely")
            }
            expect(!failed.controller.acceptsCaptureInput, "a failed refresh never resumes capture on old pixels")
            failed.controller.captureFullDisplayUnderMouse()
            failed.controller.captureFullScreenFromControl(on: panel)
            if case .failed? = failed.outcome {
                expect(true, "failed selection cannot subsequently save a stale screenshot")
            } else {
                expect(false, "failed selection cannot subsequently save a stale screenshot")
            }
        }

        // A 1x panel whose window came back as a 2x composite records 2x, so
        // the editor, pinned image and 1x export size it by its own pixels.
        for reported: CGFloat? in [nil, 2] {
            desk.windowCaptureScale = reported
            guard let window = await started(.screenshot) else { return }
            // A finished chooser closes its panels, so read the scale first.
            let panel = window.panels[0]
            let panelScale = panel.pixelScale
            window.controller.confirmWindow(11, frame: CGRect(x: 0, y: 0, width: 50, height: 50), on: panel)
            await drain()
            if case .captured(let capture)? = window.outcome {
                expect(capture.scale == (reported ?? panelScale),
                       "a window capture records the scale the engine captured it at")
            } else {
                expect(false, "a window capture records the scale the engine captured it at")
            }
        }
        desk.windowCaptureScale = nil

        guard let rapid = await started(.recording) else { return }
        let r3 = desk.requests.count
        rapid.select(.screenshot)
        await drain()
        rapid.select(.recording)
        await drain()
        desk.complete(r3, displays: [])
        await drain()
        expect(!rapid.controller.isOver && !rapid.controller.acceptsCaptureInput,
               "outdated failure cannot close or unlock the current refresh")
        desk.complete(r3 + 1, displays: [1, 2])
        await drain()
        expect(rapid.controller.acceptsCaptureInput && rapid.panels.allSatisfy {
            desk.excluded($0.frozenImage)?.contains(Desk.window) == true && $0.overlayView.windows.isEmpty
        }, "latest source restores input with current visibility")

        guard let reverse = await started(.recording) else { return }
        let rr = desk.requests.count
        reverse.select(.screenshot)
        await drain()
        reverse.select(.recording)
        await drain()
        desk.complete(rr + 1, displays: [1, 2])
        await drain()
        desk.complete(rr, displays: [1, 2])
        await drain()
        expect(reverse.panels.allSatisfy { desk.excluded($0.frozenImage)?.contains(Desk.window) == true },
               "old success arriving last cannot overwrite current pixels")

        guard let cancelled = await started(.recording) else { return }
        let cancelledPanel = cancelled.panels[0]
        let r4 = desk.requests.count
        cancelled.select(.screenshot)
        await drain()
        cancelled.controller.cancel()
        desk.complete(r4, displays: [1, 2])
        await drain()
        expect(!cancelled.controller.acceptsCaptureInput
                && desk.excluded(cancelledPanel.frozenImage)?.contains(Desk.window) == true,
               "cancelled selection ignores delayed refresh")

        guard let same = await started(.screenshot) else { return }
        let count = desk.requests.count
        same.select(.text)
        same.select(.color)
        await drain()
        expect(desk.requests.count == count && same.controller.acceptsCaptureInput,
               "equal source tools reuse pixels without pausing capture")

        guard let follow = await started(.screenshot) else { return }
        let rf = desk.requests.count
        follow.select(.recording)
        await drain()
        desk.defaults.set(true, forKey: DefaultsKey.screenshotHideVitruvianWindows)
        follow.select(.text)
        await drain()
        desk.complete(rf + 1, displays: [1, 2])
        await drain()
        desk.complete(rf, displays: [1, 2])
        await drain()
        expect(follow.panels.allSatisfy {
            desk.excluded($0.frozenImage)?.contains(Desk.window) == true && $0.overlayView.windows.isEmpty
        }, "later preference choice wins over old completion")
        desk.defaults.set(false, forKey: DefaultsKey.screenshotHideVitruvianWindows)
        let rshow = desk.requests.count
        follow.select(.screenshot)
        await drain()
        desk.complete(rshow, displays: [1, 2])
        await drain()
        expect(follow.panels.allSatisfy {
            desk.excluded($0.frozenImage)?.contains(Desk.window) == false && !$0.overlayView.windows.isEmpty
        }, "showing windows again restores editor visibility")

        guard let live = await started(.recording) else { return }
        let rl = desk.requests.count
        live.select(.text)
        await drain()
        desk.defaults.set(false, forKey: DefaultsKey.screenshotFreeze)
        live.select(.screenshot)
        expect(live.controller.acceptsCaptureInput
                && live.panels.allSatisfy { $0.frozenImage == nil && !$0.overlayView.windows.isEmpty },
               "switching to live capture resumes with current selectable windows")
        desk.complete(rl, displays: [1, 2])
        await drain()
        expect(live.panels.allSatisfy { $0.frozenImage == nil },
               "an old frozen result cannot replace live capture")
        desk.defaults.set(true, forKey: DefaultsKey.screenshotFreeze)

        guard let loupe = await started(.screenshot) else { return }
        let loupeRequest = desk.requests.count
        loupe.controller.loadLiveLoupeImages()
        await drain()
        loupe.select(.recording)
        await drain()
        desk.complete(loupeRequest + 1, displays: [1, 2])
        await drain()
        desk.complete(loupeRequest, displays: [1, 2])
        await drain()
        expect(loupe.panels.allSatisfy { $0.overlayView.loupeImage === $0.frozenImage },
               "a previous tool's delayed live loupe cannot replace the current source")

        // The surface itself, with the pointer on the first display.
        desk.pointer = CGPoint(x: 50, y: 50)
        guard let surfaceSession = await started(.screenshot) else { return }
        expect(surfaceSession.panels.allSatisfy { $0.overlayView.acceptsFirstMouse(for: nil) },
               "the capture surface claims the first click so a drag works while Dynamic Island holds key focus")
        // System chrome, such as the Dock or the menu bar, can report the
        // pointer leaving a surface it never left.
        let first = surfaceSession.panels[0].overlayView
        let second = surfaceSession.panels[1].overlayView
        if let crossing = NSEvent.mouseEvent(with: .mouseMoved, location: .zero, modifierFlags: [], timestamp: 0,
                                             windowNumber: 0, context: nil, eventNumber: 0, clickCount: 0,
                                             pressure: 0) {
            first.mouseExited(with: crossing)
            expect(first.showsCaptureGuide,
                   "system chrome cannot hide the capture chooser while the pointer remains on its display")
            desk.pointer = CGPoint(x: 150, y: 50)
            first.mouseExited(with: crossing)
            second.mouseEntered(with: crossing)
            expect(!first.showsCaptureGuide && second.showsCaptureGuide,
                   "the chooser leaves a display the pointer really left and follows it to the next")
            desk.pointer = CGPoint(x: 50, y: 50)
        } else {
            expect(false, "a pointer crossing can be made")
        }

        // Every mode lays the chooser out at one height, the recording
        // controls held in place but hidden, so switching never moves it.
        var guideFrameHeights: Set<CGFloat> = []
        var guideContentHeights: Set<CGFloat> = []
        for tool in ScreenCaptureTool.allCases {
            guard let mode = await started(tool) else { return }
            let view = mode.panels[0].overlayView
            view.layoutSubtreeIfNeeded()
            guideFrameHeights.insert(view.captureGuideFrame.height)
            guideContentHeights.insert(view.captureGuideFittingSize.height)
        }
        expect(guideFrameHeights.count == 1 && guideContentHeights.count == 1
                && (guideContentHeights.first ?? 0) > 0,
               "capture modes reserve the recording controls' height so the chooser never jumps")

        guard let picking = await started(.color) else { return }
        expect(picking.panels[0].overlayView.showsLoupe && !picking.panels[1].overlayView.showsLoupe,
               "the capture loupe draws on only the display that owns the current pointer")
    }
}
