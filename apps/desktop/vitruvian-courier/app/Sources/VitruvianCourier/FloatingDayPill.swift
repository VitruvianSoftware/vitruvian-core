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
///
/// It is called on every scroll event, so each call is cheap: the words are made once per day (not per call), nothing is
/// published when it would not change, and the fade-out is one timer that a scroll pushes back, not a new one per call.
@MainActor
final class FloatingDayController {
    let model = FloatingDayModel()
    let hostingView: FloatingDayHostingView
    /// Makes the words for a day: `FloatingDay.text`, or a stand-in in a test that counts how often it is asked.
    private let words: (Date, Date) -> String
    /// How long the words made for a day are kept: a day's words read differently after midnight ("Today").
    private let wordsLifetime: TimeInterval = 60

    private var cachedDay: Date?
    private var cachedWords = ""
    private var cachedAt = Date.distantPast
    private var hideAt = Date.distantPast
    private var hideTask: Task<Void, Never>?
    /// How many times the fade-out timer was started, for the test that a run of scroll events starts one.
    private(set) var hideTimerStarts = 0

    init(words: @escaping (Date, Date) -> String = { FloatingDay.text(day: $0, now: $1) }) {
        self.words = words
        hostingView = FloatingDayHostingView(rootView: FloatingDayPillView(model: model))
        hostingView.sizingOptions = []
        hostingView.translatesAutoresizingMaskIntoConstraints = true
    }

    deinit { hideTask?.cancel() }

    /// The person scrolled: `day` is the day at the top (nil when the top row is a date divider: the capsule goes,
    /// as the day is already on screen).
    func userScrolled(day: Date?, now: Date = Date()) {
        guard let day else {
            hideTask?.cancel()
            hideTask = nil
            setVisible(false)
            return
        }
        if cachedDay != day || now.timeIntervalSince(cachedAt) > wordsLifetime {
            cachedDay = day
            cachedWords = words(day, now)
            cachedAt = now
        }
        if model.text != cachedWords { model.text = cachedWords }
        setVisible(true)
        hideAt = now.addingTimeInterval(FloatingDay.fadeOutDelay)
        if hideTask == nil { startHideTimer() }
    }

    /// The chat changed or the table went away: nothing to show.
    func reset() {
        hideTask?.cancel()
        hideTask = nil
        cachedDay = nil
        setVisible(false)
    }

    /// Published only when it changes: every write wakes the capsule's view, and scrolling calls this every frame.
    private func setVisible(_ visible: Bool) {
        if model.isVisible != visible { model.isVisible = visible }
    }

    /// One timer for a run of scroll events: it sleeps until `hideAt`, which each scroll moves later, and hides the
    /// capsule only once that time has passed.
    private func startHideTimer() {
        hideTimerStarts += 1
        hideTask = Task { @MainActor [weak self] in
            while let self, !Task.isCancelled {
                let wait = self.hideAt.timeIntervalSinceNow
                if wait <= 0 { break }
                try? await Task.sleep(for: .seconds(wait))
            }
            guard let self, !Task.isCancelled else { return }
            self.setVisible(false)
            self.hideTask = nil
        }
    }
}
