// Copyright 2026 VitruvianSoftware
// SPDX-License-Identifier: AGPL-3.0-or-later

import AppKit
import SwiftUI
import VitruvianCourierCore

extension MotionCurve {
    func swiftUIAnimation(duration: TimeInterval) -> Animation {
        switch self {
        case .linear:
            return .linear(duration: duration)
        case .easeIn:
            return .easeIn(duration: duration)
        case .easeOut:
            return .easeOut(duration: duration)
        case .easeInOut:
            return .easeInOut(duration: duration)
        case let .cubicBezier(x1, y1, x2, y2):
            return .timingCurve(x1, y1, x2, y2, duration: duration)
        }
    }
}

// MARK: - Reduce Motion

private struct CourierReduceMotionOverrideKey: EnvironmentKey {
    static let defaultValue: Bool? = nil
}

extension EnvironmentValues {
    /// Forces Reduce Motion on or off for a view tree (tests set it: the system's own flag cannot be set from one).
    /// Nil, the default, follows the system.
    var courierReduceMotionOverride: Bool? {
        get { self[CourierReduceMotionOverrideKey.self] }
        set { self[CourierReduceMotionOverrideKey.self] = newValue }
    }
}

private struct TypingLineForTestingKey: EnvironmentKey {
    static let defaultValue: String? = nil
}

extension EnvironmentValues {
    /// Who is typing, as a test says it (the model's typing line comes from the engine, which view tests do not
    /// run). Nil, the default, uses the conversation's own.
    var typingLineForTesting: String? {
        get { self[TypingLineForTestingKey.self] }
        set { self[TypingLineForTestingKey.self] = newValue }
    }
}

/// The app's Reduce Motion check: the environment's value or the system's, unless a test forces it.
@MainActor
func courierReduceMotion(override: Bool?, accessibility: Bool) -> Bool {
    override ?? (accessibility || NSWorkspace.shared.accessibilityDisplayShouldReduceMotion)
}

// MARK: - Side Pane Entrance (Item 11)

extension View {
    /// The fade-and-rise entrance of a thread or Chat Info pane inside `HSplitView`. It plays once when `plays` is
    /// true at the pane's first appearance, then calls `didPlay`; a pane that comes back while it stays open (its
    /// content rebuilt after a chat switch) is passed `plays: false` and shows at once. It changes only the pane's
    /// own opacity and offset, never its layout, so split widths and the timeline's scroll position are untouched.
    func courierSidePaneEntrance(plays: Bool = true, didPlay: @escaping () -> Void = {}) -> some View {
        modifier(SidePaneEntranceModifier(plays: plays, didPlay: didPlay))
    }
}

private struct SidePaneEntranceModifier: ViewModifier {
    let plays: Bool
    let didPlay: () -> Void
    @Environment(\.accessibilityReduceMotion) private var accessibilityReduceMotion
    @Environment(\.courierReduceMotionOverride) private var reduceMotionOverride
    @State private var isRevealed: Bool

    init(plays: Bool, didPlay: @escaping () -> Void) {
        self.plays = plays
        self.didPlay = didPlay
        _isRevealed = State(initialValue: !plays)
    }

    private var reduceMotionEnabled: Bool {
        courierReduceMotion(override: reduceMotionOverride, accessibility: accessibilityReduceMotion)
    }

    func body(content: Content) -> some View {
        // The clip is on the container, which does not move: clipped after the offset it would travel with the
        // content and clip nothing, so the rising pane would spill past its own bottom edge.
        ZStack {
            content
                .opacity(SidePaneMotion.opacity(isRevealed: isRevealed))
                .offset(y: SidePaneMotion.yOffset(isRevealed: isRevealed, reduceMotion: reduceMotionEnabled))
        }
        .clipped()
        .onAppear {
            guard !isRevealed else { return }
            didPlay()
            let animation = SidePaneMotion.effectiveCurve(reduceMotion: reduceMotionEnabled)
                .swiftUIAnimation(duration: SidePaneMotion.effectiveDuration(reduceMotion: reduceMotionEnabled))
            withAnimation(animation) {
                isRevealed = true
            }
        }
    }
}

// MARK: - Command Bar Overlay Host (Item 12)

/// Hosts `CommandBarOverlay`: the dimmer and the panel fade in over 0.12 s (ease-out) and out over 0.10 s (ease-in).
///
/// The overlay stays in the view tree through the fade-out, so what it shows is exactly what it showed (the model
/// clears its query and results only once the fade is done) and it can be told to stop taking keys and clicks the
/// moment the bar closes. Opening again during the fade reuses the same overlay: there is never a second one, its
/// content is already fresh (`open()` resets it) and the text field takes focus at once.
struct CommandBarOverlayHost: View {
    @ObservedObject var model: CommandBarModel
    @Environment(\.accessibilityReduceMotion) private var accessibilityReduceMotion
    @Environment(\.courierReduceMotionOverride) private var reduceMotionOverride
    @State private var isMounted = false
    @State private var isShown = false
    @State private var finishTask: Task<Void, Never>?

    private var reduceMotionEnabled: Bool {
        courierReduceMotion(override: reduceMotionOverride, accessibility: accessibilityReduceMotion)
    }

    private func animation(isPresented: Bool) -> Animation {
        CommandBarMotion.curve(isPresented: isPresented, reduceMotion: reduceMotionEnabled)
            .swiftUIAnimation(
                duration: CommandBarMotion.duration(isPresented: isPresented, reduceMotion: reduceMotionEnabled)
            )
    }

    var body: some View {
        ZStack {
            if isMounted {
                CommandBarOverlay(model: model, isInteractive: model.isPresented)
                    .opacity(isShown ? 1 : 0)
                    .onAppear {
                        guard model.isPresented else { return }
                        withAnimation(animation(isPresented: true)) { isShown = true }
                    }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        // Neither keys nor clicks reach the overlay once the bar has closed, however long the fade takes.
        .allowsHitTesting(model.isPresented)
        .onAppear { sync(presented: model.isPresented) }
        .onChange(of: model.isPresented) { _, presented in sync(presented: presented) }
        .onDisappear { finishTask?.cancel() }
    }

    private func sync(presented: Bool) {
        finishTask?.cancel()
        finishTask = nil
        if presented {
            if isMounted {
                // Opened again during the fade-out: the overlay is still here; bring it back.
                withAnimation(animation(isPresented: true)) { isShown = true }
            } else {
                isMounted = true // fades in from its `onAppear`
            }
        } else if isMounted {
            withAnimation(animation(isPresented: false)) { isShown = false }
            let fade = CommandBarMotion.duration(isPresented: false, reduceMotion: reduceMotionEnabled)
            finishTask = Task { @MainActor in
                try? await Task.sleep(nanoseconds: UInt64((fade + 0.03) * 1_000_000_000))
                guard !Task.isCancelled, !model.isPresented else { return }
                isMounted = false
                model.finishClosing()
            }
        }
    }
}

// MARK: - Eased inset (typing pill)

/// Calls `content` with `inset`, interpolated frame by frame while it animates. SwiftUI does not interpolate a plain
/// value handed to an AppKit view; this does, so the timeline's bottom inset eases instead of jumping.
struct EasedInsetHost<Content: View>: View, Animatable {
    var inset: CGFloat
    let content: (CGFloat) -> Content

    var animatableData: CGFloat {
        get { inset }
        set { inset = newValue }
    }

    var body: some View {
        content(inset)
    }
}

// MARK: - Window visibility (shimmer)

private struct WindowShowsContentProbeKey: EnvironmentKey {
    static let defaultValue: (@MainActor (NSWindow) -> Bool)? = nil
}

extension EnvironmentValues {
    /// Replaces the system's answer to "is this window showing its content?" (tests: a window in a test run is
    /// never reported as visible by the system). Nil, the default, asks the window.
    var windowShowsContentProbe: (@MainActor (NSWindow) -> Bool)? {
        get { self[WindowShowsContentProbeKey.self] }
        set { self[WindowShowsContentProbeKey.self] = newValue }
    }
}

/// Reports whether the window this view is in is showing its content: on screen, not minimised, not covered.
struct WindowShowsContentReader: NSViewRepresentable {
    let probe: (@MainActor (NSWindow) -> Bool)?
    let onChange: (Bool) -> Void

    func makeNSView(context _: Context) -> ReaderView {
        ReaderView(probe: probe, onChange: onChange)
    }

    func updateNSView(_ nsView: ReaderView, context _: Context) {
        nsView.probe = probe
        nsView.onChange = onChange
    }

    final class ReaderView: NSView {
        var probe: (@MainActor (NSWindow) -> Bool)?
        var onChange: (Bool) -> Void
        private var observers: [NSObjectProtocol] = []
        private var lastReported: Bool?

        init(probe: (@MainActor (NSWindow) -> Bool)?, onChange: @escaping (Bool) -> Void) {
            self.probe = probe
            self.onChange = onChange
            super.init(frame: .zero)
        }

        @available(*, unavailable)
        required init?(coder _: NSCoder) { nil }

        deinit {
            observers.forEach { NotificationCenter.default.removeObserver($0) }
        }

        override func hitTest(_: NSPoint) -> NSView? { nil }

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            observers.forEach { NotificationCenter.default.removeObserver($0) }
            observers = []
            lastReported = nil
            if let window {
                let names: [Notification.Name] = [
                    NSWindow.didChangeOcclusionStateNotification,
                    NSWindow.didMiniaturizeNotification,
                    NSWindow.didDeminiaturizeNotification,
                    NSWindow.didExposeNotification,
                    NSWindow.willCloseNotification,
                ]
                observers = names.map { name in
                    NotificationCenter.default.addObserver(forName: name, object: window, queue: .main) { [weak self] _ in
                        MainActor.assumeIsolated { self?.report() }
                    }
                }
            }
            report()
        }

        private func report() {
            let shows: Bool
            if let window {
                if let probe {
                    shows = probe(window)
                } else {
                    shows = SkeletonShimmerMotion.windowShowsContent(
                        isOnScreen: window.isVisible,
                        isMiniaturized: window.isMiniaturized,
                        occlusionVisible: window.occlusionState.contains(.visible)
                    )
                }
            } else {
                shows = false
            }
            guard shows != lastReported else { return }
            lastReported = shows
            onChange(shows)
        }
    }
}

// MARK: - Scroll-Edge Fade (Item 15)

extension View {
    /// Fades the scroller's rows out over about 10 pt at the top and bottom, only on a side that has more content
    /// beyond it, easing in over the first points scrolled. It is a SwiftUI mask driven by the scroll geometry the
    /// observer reads; the scroller's strip is left solid so its thumb is not faded, and the mask is a plain opaque
    /// fill (nothing fades) while nothing overflows. It never affects hit testing. `refreshToken` tells it to look
    /// again when the content changed; `onStateChange` reports the edge strengths (tests).
    ///
    /// Why a SwiftUI mask and not a Core Animation mask on the scroll view's layers: measured on a 600-row list a
    /// layer mask cost about 0.8 ms more per scroll step than no fade, this one about 0.15 ms
    /// (`PanelMotionViewTests.testEdgeFadeCostOnALongListIsMeasured`).
    func courierScrollEdgeFade(
        refreshToken: Int = 0,
        onStateChange: ((ScrollEdgeFadeState) -> Void)? = nil
    ) -> some View {
        modifier(ScrollEdgeFadeModifier(refreshToken: refreshToken, onStateChange: onStateChange))
    }
}

private struct ScrollEdgeFadeModifier: ViewModifier {
    let refreshToken: Int
    let onStateChange: ((ScrollEdgeFadeState) -> Void)?
    @State private var edgeState: ScrollEdgeFadeState = .none

    func body(content: Content) -> some View {
        content
            .background(
                ScrollEdgeFadeObserver(refreshToken: refreshToken) { newState in
                    if edgeState != newState {
                        edgeState = newState
                    }
                    onStateChange?(newState)
                }
                .allowsHitTesting(false)
            )
            .mask(ScrollEdgeFadeMask(state: edgeState))
    }
}

struct ScrollEdgeFadeMask: View {
    let state: ScrollEdgeFadeState
    /// The scroller's strip stays solid: its thumb must not fade with the rows.
    let scrollerStrip = NSScroller.scrollerWidth(for: .regular, scrollerStyle: NSScroller.preferredScrollerStyle)

    var body: some View {
        GeometryReader { geo in
            let edge = ScrollEdgeFadeMotion.effectiveFadeHeight(containerHeight: geo.size.height)
            HStack(spacing: 0) {
                if state.isActive {
                    VStack(spacing: 0) {
                        LinearGradient(
                            colors: [Color.black.opacity(1 - state.top), .black], startPoint: .top, endPoint: .bottom
                        )
                        .frame(height: edge)
                        Color.black
                        LinearGradient(
                            colors: [.black, Color.black.opacity(1 - state.bottom)], startPoint: .top, endPoint: .bottom
                        )
                        .frame(height: edge)
                    }
                    .frame(width: max(0, geo.size.width - scrollerStrip))
                    Color.black.frame(width: min(geo.size.width, scrollerStrip))
                } else {
                    Color.black
                }
            }
        }
    }
}

private struct ScrollEdgeFadeObserver: NSViewRepresentable {
    let refreshToken: Int
    let onChange: (ScrollEdgeFadeState) -> Void

    func makeNSView(context _: Context) -> ObserverNSView {
        ObserverNSView(onChange: onChange)
    }

    func updateNSView(_ nsView: ObserverNSView, context _: Context) {
        nsView.onChange = onChange
        nsView.scheduleRefreshIfNeeded(refreshToken: refreshToken)
    }

    final class ObserverNSView: NSView {
        var onChange: (ScrollEdgeFadeState) -> Void
        private weak var observedScrollView: NSScrollView?
        private var boundsObserver: NSObjectProtocol?
        private var clipFrameObserver: NSObjectProtocol?
        private var docFrameObserver: NSObjectProtocol?
        private var docObservation: NSKeyValueObservation?
        private var lastReportedState: ScrollEdgeFadeState?
        private var lastRefreshToken: Int?
        private var pendingRefresh = false
        private var retryCount = 0
        private let maxRetries = 8

        init(onChange: @escaping (ScrollEdgeFadeState) -> Void) {
            self.onChange = onChange
            super.init(frame: .zero)
        }

        @available(*, unavailable)
        required init?(coder _: NSCoder) { nil }

        deinit {
            detach()
        }

        override func hitTest(_: NSPoint) -> NSView? {
            nil
        }

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            // A new window (or none) means the scroll view found before is not this one's any more.
            if let observed = observedScrollView, observed.window == nil || observed.window !== window {
                detach()
            }
            retryCount = 0
            scheduleCoalescedRefresh()
        }

        override func layout() {
            super.layout()
            refreshNow()
        }

        func scheduleRefreshIfNeeded(refreshToken: Int) {
            if lastRefreshToken != refreshToken || observedScrollView == nil {
                lastRefreshToken = refreshToken
                retryCount = 0
                scheduleCoalescedRefresh()
            }
        }

        private func refreshNow() {
            if let observed = observedScrollView, observed.window == nil || observed.window !== window {
                detach()
            }
            if observedScrollView == nil {
                attachIfPossible()
            } else {
                evaluate()
            }
        }

        private func scheduleCoalescedRefresh(after delay: TimeInterval = 0) {
            guard !pendingRefresh else { return }
            pendingRefresh = true
            let work = { [weak self] in
                guard let self else { return }
                self.pendingRefresh = false
                self.refreshNow()
                // The scroll view can show up a few ticks after this view does (a list sizing late): look again,
                // a bounded number of times, rather than only when something happens to lay out.
                if self.observedScrollView == nil, self.window != nil, self.retryCount < self.maxRetries {
                    self.retryCount += 1
                    self.scheduleCoalescedRefresh(after: min(0.5, 0.05 * pow(2, Double(self.retryCount - 1))))
                }
            }
            if delay <= 0 {
                DispatchQueue.main.async(execute: work)
            } else {
                DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: work)
            }
        }

        private func attachIfPossible() {
            guard let scrollView = resolveScrollView() else { return }
            if observedScrollView === scrollView {
                evaluate()
                return
            }
            attach(to: scrollView)
        }

        private func resolveScrollView() -> NSScrollView? {
            if let start = superview,
               let ancestor = sequence(first: start, next: \.superview)
                .compactMap({ $0 as? NSScrollView })
                .first {
                return ancestor
            }
            guard !bounds.isEmpty, window != nil else { return nil }
            let root = resolutionRootView()
            let selfRect = convert(bounds, to: root)
            let selfArea = selfRect.width * selfRect.height
            guard selfArea > 0 else { return nil }

            var candidates: [(scrollView: NSScrollView, iou: CGFloat, sizeDelta: CGFloat)] = []
            collectScrollViews(in: root) { scrollView in
                let svRect = scrollView.convert(scrollView.bounds, to: root)
                let svArea = svRect.width * svRect.height
                guard svArea > 0 else { return }
                let intersection = selfRect.intersection(svRect)
                guard !intersection.isNull else { return }
                let intersectionArea = intersection.width * intersection.height
                let overlapWithSelf = intersectionArea / selfArea
                let overlapWithScrollView = intersectionArea / svArea
                guard overlapWithSelf >= 0.5 || overlapWithScrollView >= 0.8 else { return }
                let unionArea = selfArea + svArea - intersectionArea
                let iou = unionArea > 0 ? intersectionArea / unionArea : 0
                let sizeDelta = abs(svRect.width - selfRect.width) + abs(svRect.height - selfRect.height)
                candidates.append((scrollView, iou, sizeDelta))
            }

            return candidates.max { lhs, rhs in
                if abs(lhs.iou - rhs.iou) > 0.01 {
                    return lhs.iou < rhs.iou
                }
                return lhs.sizeDelta > rhs.sizeDelta
            }?.scrollView
        }

        private func resolutionRootView() -> NSView {
            var current: NSView = self
            var steps = 0
            while let parent = current.superview {
                current = parent
                steps += 1
                if String(describing: type(of: parent)).contains("NSHostingView") {
                    return parent
                }
                if steps >= 6 {
                    break
                }
            }
            return current
        }

        private func collectScrollViews(in view: NSView, visit: (NSScrollView) -> Void) {
            for child in view.subviews {
                if let scrollView = child as? NSScrollView {
                    visit(scrollView)
                    // Do not descend into nested subviews of a matched scroll view.
                    continue
                }
                collectScrollViews(in: child, visit: visit)
            }
        }

        private func attach(to scrollView: NSScrollView) {
            detach()
            observedScrollView = scrollView
            let clipView = scrollView.contentView
            clipView.postsBoundsChangedNotifications = true
            clipView.postsFrameChangedNotifications = true

            boundsObserver = NotificationCenter.default.addObserver(
                forName: NSView.boundsDidChangeNotification,
                object: clipView,
                queue: .main
            ) { [weak self] _ in
                MainActor.assumeIsolated {
                    self?.evaluate()
                }
            }

            clipFrameObserver = NotificationCenter.default.addObserver(
                forName: NSView.frameDidChangeNotification,
                object: clipView,
                queue: .main
            ) { [weak self] _ in
                MainActor.assumeIsolated {
                    self?.evaluate()
                }
            }

            observeDocumentView(scrollView.documentView)
            docObservation = scrollView.observe(\.documentView, options: [.new]) { [weak self] sv, _ in
                MainActor.assumeIsolated {
                    self?.observeDocumentView(sv.documentView)
                    self?.evaluate()
                }
            }
            evaluate()
        }

        private func observeDocumentView(_ docView: NSView?) {
            if let docFrameObserver {
                NotificationCenter.default.removeObserver(docFrameObserver)
                self.docFrameObserver = nil
            }
            guard let docView else { return }
            docView.postsFrameChangedNotifications = true
            docFrameObserver = NotificationCenter.default.addObserver(
                forName: NSView.frameDidChangeNotification,
                object: docView,
                queue: .main
            ) { [weak self] _ in
                MainActor.assumeIsolated {
                    self?.evaluate()
                }
            }
        }

        private func detach() {
            if let boundsObserver {
                NotificationCenter.default.removeObserver(boundsObserver)
                self.boundsObserver = nil
            }
            if let clipFrameObserver {
                NotificationCenter.default.removeObserver(clipFrameObserver)
                self.clipFrameObserver = nil
            }
            if let docFrameObserver {
                NotificationCenter.default.removeObserver(docFrameObserver)
                self.docFrameObserver = nil
            }
            docObservation?.invalidate()
            docObservation = nil
            observedScrollView = nil
            lastReportedState = nil
        }

        private func evaluate() {
            guard let scrollView = observedScrollView,
                  let docView = scrollView.documentView else { return }
            let clipView = scrollView.contentView
            let docBounds = docView.bounds
            let clipBounds = clipView.bounds
            let insets = clipView.contentInsets
            let newState = ScrollEdgeFadeMotion.state(
                documentMinY: docBounds.minY,
                documentMaxY: docBounds.maxY,
                clipMinY: clipBounds.minY,
                clipMaxY: clipBounds.maxY,
                topInset: insets.top,
                bottomInset: insets.bottom,
                isFlipped: docView.isFlipped
            )
            guard newState != lastReportedState else { return }
            lastReportedState = newState
            // Told on the next turn: this runs inside AppKit's scroll and layout callbacks, where SwiftUI state
            // must not be changed.
            DispatchQueue.main.async { [weak self] in
                guard let self, self.lastReportedState == newState else { return }
                self.onChange(newState)
            }
        }
    }
}
