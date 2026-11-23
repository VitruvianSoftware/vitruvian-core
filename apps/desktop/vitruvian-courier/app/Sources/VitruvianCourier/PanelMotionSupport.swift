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

// MARK: - Side Pane Entrance (Item 11)

extension View {
    /// Applies the Stream C fade-and-rise entrance inside an `HSplitView` side pane without disturbing split widths.
    func courierSidePaneEntrance() -> some View {
        modifier(SidePaneEntranceModifier())
    }
}

private struct SidePaneEntranceModifier: ViewModifier {
    @Environment(\.accessibilityReduceMotion) private var accessibilityReduceMotion
    @State private var isRevealed = false

    private var reduceMotionEnabled: Bool {
        accessibilityReduceMotion || NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
    }

    func body(content: Content) -> some View {
        content
            .opacity(SidePaneMotion.opacity(isRevealed: isRevealed))
            .offset(y: SidePaneMotion.yOffset(isRevealed: isRevealed, reduceMotion: reduceMotionEnabled))
            .clipped()
            .onAppear {
                guard !isRevealed else { return }
                let animation = SidePaneMotion.effectiveCurve(reduceMotion: reduceMotionEnabled)
                    .swiftUIAnimation(duration: SidePaneMotion.effectiveDuration(reduceMotion: reduceMotionEnabled))
                withAnimation(animation) {
                    isRevealed = true
                }
            }
    }
}

// MARK: - Command Bar Overlay Host (Item 12)

/// Hosts `CommandBarOverlay` so both dimmer and panel fade in (0.12 s ease-out) and out (0.10 s ease-in).
struct CommandBarOverlayHost: View {
    @ObservedObject var model: CommandBarModel
    @Environment(\.accessibilityReduceMotion) private var accessibilityReduceMotion

    private var reduceMotionEnabled: Bool {
        accessibilityReduceMotion || NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
    }

    var body: some View {
        ZStack {
            if model.isPresented {
                CommandBarOverlay(model: model)
                    .transition(.opacity)
                    .zIndex(1)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .allowsHitTesting(model.isPresented)
        .animation(
            CommandBarMotion.curve(isPresented: model.isPresented, reduceMotion: reduceMotionEnabled)
                .swiftUIAnimation(
                    duration: CommandBarMotion.duration(
                        isPresented: model.isPresented,
                        reduceMotion: reduceMotionEnabled
                    )
                ),
            value: model.isPresented
        )
    }
}

// MARK: - Scroll-Edge Fade Mask (Item 15)

extension View {
    /// Fades scrollable content out over ~10 pt at the top and/or bottom when more content exists beyond that edge.
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
    @Environment(\.accessibilityReduceMotion) private var accessibilityReduceMotion

    private var reduceMotionEnabled: Bool {
        accessibilityReduceMotion || NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
    }

    func body(content: Content) -> some View {
        let maskAnimation: Animation? = ScrollEdgeFadeMotion.animatesMaskChange(reduceMotion: reduceMotionEnabled)
            ? .easeOut(duration: ScrollEdgeFadeMotion.fadeTransitionDuration)
            : nil
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
            .mask(
                ScrollEdgeFadeMask(
                    state: edgeState,
                    fadeHeight: ScrollEdgeFadeMotion.fadeHeight,
                    animation: maskAnimation
                )
            )
    }
}

private struct ScrollEdgeFadeMask: View {
    let state: ScrollEdgeFadeState
    let fadeHeight: CGFloat
    let animation: Animation?

    var body: some View {
        GeometryReader { geo in
            let edge = min(fadeHeight, ScrollEdgeFadeMotion.effectiveFadeHeight(containerHeight: geo.size.height))
            VStack(spacing: 0) {
                LinearGradient(
                    colors: [Color.black.opacity(state.top ? 0 : 1), .black],
                    startPoint: .top,
                    endPoint: .bottom
                )
                .frame(height: edge)

                Color.black

                LinearGradient(
                    colors: [.black, Color.black.opacity(state.bottom ? 0 : 1)],
                    startPoint: .top,
                    endPoint: .bottom
                )
                .frame(height: edge)
            }
            .animation(animation, value: state)
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
            scheduleCoalescedRefresh()
        }

        override func layout() {
            super.layout()
            if observedScrollView == nil {
                attachIfPossible()
            } else {
                evaluate()
            }
        }

        func scheduleRefreshIfNeeded(refreshToken: Int) {
            if lastRefreshToken != refreshToken || observedScrollView == nil {
                lastRefreshToken = refreshToken
                scheduleCoalescedRefresh()
            }
        }

        private func scheduleCoalescedRefresh() {
            guard !pendingRefresh else { return }
            pendingRefresh = true
            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                self.pendingRefresh = false
                if self.observedScrollView == nil {
                    self.attachIfPossible()
                } else {
                    self.evaluate()
                }
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
            guard !bounds.isEmpty else { return nil }
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
                if parent is NSHostingView<AnyView> || String(describing: type(of: parent)).contains("NSHostingView") {
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
            DispatchQueue.main.async { [weak self] in
                guard let self, self.lastReportedState == newState else { return }
                self.onChange(newState)
            }
        }
    }
}
