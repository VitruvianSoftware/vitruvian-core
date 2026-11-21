// Copyright 2026 VitruvianSoftware
// SPDX-License-Identifier: AGPL-3.0-or-later

import AppKit
import SwiftUI
import VitruvianCourierCore

/// What the floating date capsule says and whether it is showing.
@MainActor
final class FloatingDayModel: ObservableObject {
    @Published var text = ""
    @Published var isVisible = false
}

/// The capsule: the date divider's look (small, secondary, on a quiet capsule), over a material so it stays readable
/// above message bubbles. It fades in and out; with Reduce Motion on that is all it does (otherwise it also slides a
/// few points).
struct FloatingDayPillView: View {
    @ObservedObject var model: FloatingDayModel
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    static let slide: CGFloat = 4

    var body: some View {
        Text(model.text)
            .font(.caption.weight(.medium))
            .foregroundStyle(.secondary)
            .contentTransition(.opacity)
            .padding(.horizontal, 10)
            .padding(.vertical, 3)
            .background(Capsule().fill(.regularMaterial))
            .background(Capsule().fill(.quaternary))
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            .opacity(model.isVisible ? 1 : 0)
            .offset(y: reduceMotion || model.isVisible ? 0 : -Self.slide)
            .animation(.easeOut(duration: FloatingDay.fadeDuration), value: model.isVisible)
            .animation(.easeOut(duration: FloatingDay.fadeDuration), value: model.text)
            .accessibilityHidden(true)
    }
}

/// The capsule's view: it takes no clicks, so the messages under it work as they do without it.
final class FloatingDayHostingView: NSHostingView<FloatingDayPillView> {
    static let height: CGFloat = 26

    override func hitTest(_ point: NSPoint) -> NSView? { nil }
    override func isAccessibilityElement() -> Bool { false }
}

/// Owns the capsule on the timeline: shows it as the person scrolls, and fades it out `FloatingDay.fadeOutDelay`
/// after the last scroll.
@MainActor
final class FloatingDayController {
    let model = FloatingDayModel()
    let hostingView: FloatingDayHostingView
    private var hideTask: Task<Void, Never>?

    init() {
        hostingView = FloatingDayHostingView(rootView: FloatingDayPillView(model: model))
        hostingView.sizingOptions = []
        hostingView.translatesAutoresizingMaskIntoConstraints = true
        hostingView.isHidden = false
    }

    deinit { hideTask?.cancel() }

    /// The person scrolled: `day` is the day at the top (nil when the top row is a date divider: the capsule goes,
    /// as the day is already on screen).
    func userScrolled(day: Date?, now: Date = Date()) {
        hideTask?.cancel()
        guard let day else {
            model.isVisible = false
            return
        }
        let text = FloatingDay.text(day: day, now: now)
        if model.text != text { model.text = text }
        model.isVisible = true
        hideTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(FloatingDay.fadeOutDelay))
            guard !Task.isCancelled else { return }
            self?.model.isVisible = false
        }
    }

    /// The chat changed or the table went away: nothing to show.
    func reset() {
        hideTask?.cancel()
        hideTask = nil
        model.isVisible = false
    }
}
