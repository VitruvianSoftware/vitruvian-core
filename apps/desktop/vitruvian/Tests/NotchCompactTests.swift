// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import AppKit
import SwiftUI
import VitruvianCore
import VitruvianDesign
import VitruvianServices
import VitruvianUI

/// The compact pages' real views and rules: the camera page, calendar rows,
/// the rail, the scratchpad's editor and focus, and page sizing. Windows stay
/// hidden; these contracts neither capture pixels nor send input events.
enum NotchCompactTests {
    /// A camera that records what the camera page asks of it.
    final class Camera: NotchEmbeddedCamera {
        @Published var isEmbeddedPresented = false
        var stops = 0
        /// What the preview's stop button calls, as the page handed it over.
        var previewStop: (() -> Void)?
        func showEmbedded() { isEmbeddedPresented = true }
        func hideEmbedded() {
            guard isEmbeddedPresented else { return }
            stops += 1
            isEmbeddedPresented = false
        }
    }
    /// A window as the scratchpad's focus sees it, key when the test says so.
    final class Window: ScratchpadFocusWindow {
        static var key: Window?
        var isVisible = true
        var isKeyWindow: Bool { Self.key === self }
        var responderChanges = 0
        func makeKey() { Self.key = self }
        func makeFirstResponder(_ responder: NSResponder?) -> Bool {
            responderChanges += 1
            return true
        }
    }
    struct Entry: Identifiable { let id: Int }
    final class RailState: ObservableObject {
        @Published var selected: Int?
        @Published var rows = 2
        @Published var count = 1000
        var realized = Set<Int>()
    }
    struct Marker: NSViewRepresentable {
        let id: Int
        func makeNSView(context: Context) -> NSView {
            let view = NSView()
            view.identifier = NSUserInterfaceItemIdentifier("rail-\(id)")
            return view
        }
        func updateNSView(_ nsView: NSView, context: Context) {}
    }
    struct Rail: View {
        @ObservedObject var state: RailState
        var body: some View {
            let entries = (0..<state.count).map { NotchCompactTests.Entry(id: $0) }
            return NotchRail(items: entries, rows: state.rows, itemWidth: 76, width: 424,
                             scrollTarget: state.selected) { marker($0) }
                .frame(width: 424, height: 152)
        }
        private func marker(_ item: NotchCompactTests.Entry) -> some View {
            state.realized.insert(item.id)
            return NotchCompactTests.Marker(id: item.id).frame(height: 72)
        }
    }

    static func settle(_ view: NSView? = nil) {
        for _ in 0..<30 {
            view?.layoutSubtreeIfNeeded()
            RunLoop.current.run(until: Date().addingTimeInterval(0.01))
        }
    }
    static func descendants(_ view: NSView) -> [NSView] {
        [view] + view.subviews.flatMap(descendants)
    }
    static func run(_ suite: TestSuite) {
        camera(suite)
        calendarRows(suite)
        rail(suite)
        scratchpad(suite)
        focus(suite)
        sizing(suite)
        musicControls(suite)
        controlGroups(suite)
    }
    private static func calendarRows(_ suite: TestSuite) {
        let day = Date(timeIntervalSince1970: 1_780_000_000)
        for language in AppLanguage.allCases {
            for width: CGFloat in [192, 304, 424] {
                func height(title: String, chosen: Bool? = nil) -> CGFloat {
                    let event = NotchCalendarEvent(id: "layout", title: title, calendar: "Calendar",
                                                   start: day, end: day.addingTimeInterval(3600),
                                                   allDay: false, location: "Meeting room")
                    let host = NSHostingView(rootView: NotchCalendarEventRow(event: event, day: day, now: day,
                                                                           isNext: true,
                                                                           text: FeatureStrings.notchCalendar(language),
                                                                           countdown: chosen, choose: { _ in }, open: {})
                        .environment(\.locale, Locale(identifier: language.rawValue))
                        .frame(width: width))
                    host.layoutSubtreeIfNeeded()
                    suite.expect(host.fittingSize.width == width && host.fittingSize.height.isFinite,
                                 "agenda rows stay inside the available width in \(language.rawValue)")
                    return host.fittingSize.height
                }
                let short = height(title: "Meeting")
                let long = height(title: Array(repeating: "A long appointment title", count: 10).joined(separator: " "))
                suite.expect(long > short + 40,
                             "long agenda titles grow vertically instead of clipping into a fixed-height card")
                suite.expect(height(title: "Meeting", chosen: true) == short,
                             "the mark of an event chosen to count down fits its time line without growing the card")
            }
        }
    }
    private static func camera(_ suite: TestSuite) {
        let service = Camera()
        let host = NSHostingView(rootView: AnyView(VStack {
            NotchCameraView(size: CGSize(width: 424, height: 180), camera: service) { size, stop in
                Color.black.frame(width: size.width, height: size.height)
                    .onAppear { service.previewStop = stop }
            }
        }))
        let window = NSWindow(contentRect: NSRect(x: -10000, y: -10000, width: 424, height: 180),
                              styleMask: [.borderless], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.contentView = host
        defer { window.contentView = nil }
        host.frame = NSRect(x: 0, y: 0, width: 424, height: 180)
        settle(host)
        service.showEmbedded()
        settle(host)
        suite.expect(service.isEmbeddedPresented && service.stops == 0,
                     "starting the embedded camera does not dismiss it when the start card disappears")
        service.previewStop?()
        settle(host)
        service.showEmbedded()
        settle(host)
        suite.expect(service.isEmbeddedPresented && service.stops == 1,
                     "the stop button over the preview stops the camera, and it starts again within the same page")
        host.rootView = AnyView(EmptyView())
        settle(host)
        suite.expect(!service.isEmbeddedPresented && service.stops == 2,
                     "leaving the camera page still stops capture")
    }
    private static func rail(_ suite: TestSuite) {
        let state = RailState()
        let host = NSHostingView(rootView: Rail(state: state))
        let window = NSWindow(contentRect: NSRect(x: -10000, y: -10000, width: 424, height: 152),
                              styleMask: [.borderless], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.contentView = host
        defer { window.contentView = nil }
        host.frame = NSRect(x: 0, y: 0, width: 424, height: 152)
        settle(host)
        suite.expect(state.realized.count > 0 && state.realized.count < 40,
                     "a thousand history entries create only the visible rail neighborhood")
        let firstTiles = (0..<3).compactMap { id in
            descendants(host).first { $0.identifier?.rawValue == "rail-\(id)" }.map { $0.convert($0.bounds, to: host) }
        }
        if firstTiles.count == 3 {
            let gap = CGPoint(x: (firstTiles[0].maxX + firstTiles[2].minX) / 2, y: firstTiles[0].midY)
            var target = host.hitTest(gap)
            while let view = target, !(view is NSScrollView) { target = view.superview }
            suite.expect(target is NSScrollView,
                         "empty space between rail columns routes wheel events through the scroll view")
        } else {
            suite.expect(false, "the visible rail has enough columns to exercise its empty gap")
        }
        for (target, rows) in [(12, 2), (900, 2), (901, 2), (901, 1), (0, 1)] {
            state.rows = rows
            state.selected = target
            settle(host)
            let marker = descendants(host).first { $0.identifier?.rawValue == "rail-\(target)" }
            suite.expect(marker.map { host.bounds.intersects($0.convert($0.bounds, to: host)) } == true,
                         "selection \(target) remains visible after navigating or changing to \(rows) rail rows")
        }
        suite.expect(state.realized.count < 500,
                     "jumping to distant selections does not realize the intervening history")
        // Five tiles over two rows fit three columns wide: they read across
        // the rows, and the two on the last row sit centered under the three.
        state.count = 5
        state.rows = 2
        state.selected = nil
        settle(host)
        let frames = (0..<5).compactMap { id in
            descendants(host).first { $0.identifier?.rawValue == "rail-\(id)" }.map { $0.convert($0.bounds, to: host) }
        }
        suite.expect(frames.count == 5
               && frames[0].minY == frames[1].minY && frames[1].minY == frames[2].minY
               && frames[0].minX < frames[1].minX && frames[1].minX < frames[2].minX
               && frames[3].minY == frames[4].minY && frames[3].minY != frames[0].minY,
               "a rail that fits reads left to right along its rows")
        suite.expect(frames.count == 5
               && abs(frames[3].width - frames[0].width) < 0.5
               && abs(frames[3].midX - (frames[0].midX + frames[1].midX) / 2) < 0.5
               && abs((frames[3].minX + frames[4].maxX) / 2 - host.bounds.midX) < 0.5,
               "a short last row keeps the cell width and sits centered under the row above")
    }
    private static func scratchpad(_ suite: TestSuite) {
        let manager = FileManager.default
        let root = manager.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let domain = "com.vitruviansoftware.vitruvian.tests.notch-compact"
        let defaults = UserDefaults(suiteName: domain)!
        // A real pad over a directory of its own, on a real island's page.
        let harness = ScratchpadHarness(root: root)
        let fixture = NotchIslandFixture(defaults: defaults)
        defer {
            withExtendedLifetime(fixture) {}
            harness.cleanUp()
            try? manager.removeItem(at: root)
            defaults.removePersistentDomain(forName: domain)
        }
        harness.defaults.set(true, forKey: AppFeature.scratchpad.availabilityKey)
        let pad: ScratchpadService = harness.service
        let window = NSWindow(contentRect: NSRect(x: -10000, y: -10000, width: 424, height: 180),
                              styleMask: [.borderless], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        let host = NSHostingView(rootView: NotchScratchpadView(service: fixture.island, pad: pad))
        window.contentView = host
        // The page saves as it leaves, while the pad's harness is still there.
        defer {
            window.contentView = nil
            settle()
        }
        host.frame = NSRect(x: 0, y: 0, width: 424, height: 180)
        settle(host)
        pad.text = "original note"
        settle(host)
        guard let editor = descendants(host).compactMap({ $0 as? NSTextView }).first else {
            suite.expect(false, "the embedded scratchpad creates its native editor")
            return
        }
        /// Preview on or off, as its button turns it.
        func preview(_ on: Bool) {
            if pad.isPreviewing != on { pad.togglePreview() }
            settle(host)
        }
        for previewing in [true, false] {
            preview(previewing)
            suite.expect(descendants(host).contains { $0 === editor },
                         "preview preserves the same editor and undo history")
            pad.clear(through: editor)
            settle(host)
            suite.expect(pad.text.isEmpty && editor.undoManager?.canUndo == true,
                         "clearing from preview or editing records an undoable text edit")
            window.makeFirstResponder(editor)
            editor.undoManager?.undo()
            suite.expect(editor.string == "original note", "one native undo restores the complete note")
            // This window never becomes key. Commit the restored text explicitly
            // to exercise the editor's delegate independently of AppKit's event loop.
            editor.didChangeText()
            settle(host)
            suite.expect(pad.text == "original note", "committing the restored text updates the shared document")
        }
        preview(true)
        pad.text = "another pad"
        settle(host)
        preview(false)
        suite.expect(editor.string == "another pad" && editor.undoManager?.canUndo != true,
                     "switching documents while previewing cannot undo into the previous document")
    }
    private static func focus(_ suite: TestSuite) {
        let floating = Window()
        let island = Window()
        let floatingEditor = NSTextView()
        let islandEditor = NSTextView()
        var queued: [@MainActor () -> Void] = []
        /// What the floating pad does for a document action, or for an explicit show.
        func focusFloating(requiresKeyWindow: Bool = true) {
            ScratchpadFocus.bringForward(floating, requiresKeyWindow: requiresKeyWindow,
                                         later: { queued.append($0) }) { (window: floating, editor: floatingEditor) }
        }
        /// What the island's page does when its pad changes.
        func focusEmbedded() {
            ScratchpadFocus.placeCaret(in: islandEditor, window: island)
        }
        /// The main queue runs what was queued for it.
        func runQueued() {
            let work = queued
            queued.removeAll()
            work.forEach { $0() }
        }
        defer { Window.key = nil }
        for visible in [true, false] {
            floating.isVisible = visible
            Window.key = island
            focusFloating()
            focusEmbedded()
            runQueued()
            suite.expect(Window.key === island && floating.responderChanges == 0,
                         "document actions preserve island focus with the floating host visible or hidden")
        }
        floating.isVisible = true
        focusFloating(requiresKeyWindow: false)
        runQueued()
        suite.expect(Window.key === floating && floating.responderChanges == 1,
                     "explicitly opening the floating pad still gives its editor the keyboard")
        let before = island.responderChanges
        focusEmbedded()
        suite.expect(island.responderChanges == before, "an island observer cannot change the nonkey editor selection")
        focusFloating()
        Window.key = island
        runQueued()
        suite.expect(floating.responderChanges == 1,
                     "a queued floating focus request is discarded after the user changes hosts")
    }
    /// The music page's row of controls, which its size and its drawing
    /// both read from `NotchMusicControls`.
    private static func musicControls(_ suite: TestSuite) {
        let domain = "com.vitruviansoftware.vitruvian.tests.notch-music-controls"
        let defaults = UserDefaults(suiteName: domain)!
        defaults.removePersistentDomain(forName: domain)
        defer { defaults.removePersistentDomain(forName: domain) }
        suite.expect(!NotchMusicControls(in: defaults).hasRow, "with nothing to offer, the music page draws no row of controls")
        defaults.set(true, forKey: DefaultsKey.notchLyricsEnabled)
        suite.expect(!NotchMusicControls(in: defaults).hasRow, "lyrics switched on count only once the feature is available")
        defaults.set(true, forKey: AppFeature.notchLyrics.availabilityKey)
        // The Settings preview draws the page with the island off and Music
        // hidden; the row the page draws is the row its size counts.
        defaults.set(false, forKey: DefaultsKey.notchEnabled)
        let lyrics = NotchMusicControls(in: defaults)
        suite.expect(lyrics.hasRow && lyrics.lyrics && !lyrics.queue && !lyrics.mixer,
                     "available lyrics give the page its row whether or not the island shows Music")
        suite.expect(NotchMusicControls(lyricsEnabled: false, queueEnabled: false, in: defaults)
                        == NotchMusicControls(mixer: false, lyrics: false, queue: false),
                     "the page's own switches decide, not the stored ones")
        defaults.set(true, forKey: AppFeature.mixer.availabilityKey)
        suite.expect(NotchMusicControls(lyricsEnabled: false, queueEnabled: false, in: defaults).hasRow,
                     "the mixer alone gives the page its row")
        // A page too short for anything grows to hold what it draws.
        func height(_ row: Bool) -> CGFloat {
            NotchLayout.pageSize(content: CGSize(width: 300, height: 10), module: .music, detail: false, controls: [],
                                 timerMode: .timer, timerHasSession: false, hasPlayback: false,
                                 musicControlsRow: row, layout: .custom).height
        }
        suite.expect(height(true) - height(false) == NotchLayout.musicControlsRowHeight + NotchLayout.rowSpacing,
                     "the music page's size holds exactly the row it draws")
    }

    /// The home page's split into cards and shortcuts, which its size, its
    /// drawing and the Settings preview all read from `NotchControlGroups`.
    private static func controlGroups(_ suite: TestSuite) {
        let groups = NotchControlGroups([.timer, .volume, .music, .keepAwake, .brightness])
        suite.expect(groups.levels == [.volume, .brightness] && groups.music
                     && groups.shortcuts == [.timer, .keepAwake] && groups.hasCards,
                     "the levels and music share the card row and the rest are shortcuts, in their order")
        suite.expect(!NotchControlGroups([.timer, .calendar]).hasCards && NotchControlGroups([.music]).hasCards
                     && NotchControlGroups([.brightness]).hasCards,
                     "the card row appears for music or any level, and only then")
        let short = CGSize(width: 300, height: 10)
        for items: [NotchControlItem] in [[.timer, .volume, .music], [.timer, .calendar, .keepAwake], [.brightness]] {
            let groups = NotchControlGroups(items)
            let page = NotchLayout.pageSize(content: short, module: .controls, detail: false, controls: items,
                                            timerMode: .timer, timerHasSession: false, hasPlayback: true,
                                            musicControlsRow: true, layout: .custom)
            let drawn = NotchLayout.controls(hasCards: groups.hasCards, shortcutCount: groups.shortcuts.count,
                                             width: short.width, height: short.height)
            suite.expect(page.height == max(short.height, drawn.height),
                         "the home page's size holds the rows it draws for \(items)")
        }
    }

    private static func sizing(_ suite: TestSuite) {
        /// A page's size with the home page's usual cards, a song playing and
        /// no timer under way.
        func pageSize(_ content: CGSize, _ module: NotchModule, detail: Bool = false,
                      controls: [NotchControlItem] = [.music, .volume, .brightness, .timer]) -> CGSize {
            NotchLayout.pageSize(content: content, module: module, detail: detail, controls: controls,
                                 timerMode: .timer, timerHasSession: false, hasPlayback: true,
                                 musicControlsRow: true, layout: .custom)
        }
        let screen = CGRect(x: 0, y: 0, width: 1440, height: 900)
        for bar: CGFloat in [24, 32, 40, 48, 64] {
            let geometry = NotchGeometry(screen: screen, safeAreaTop: 0, cameraWidth: 0, layout: .custom,
                                         menuBarHeight: bar, customWidth: 360, customHeight: 260)
            for module in [NotchModule.controls, .timer, .calendar, .files, .music, .clipboard, .camera, .mixer] {
                let content = geometry.contentSize(for: geometry.expandedSize(module: module))
                let layout = pageSize(content, module)
                suite.expect(layout.width == content.width && layout.height >= content.height,
                             "\(module) keeps the chosen width and exposes any vertically overflowing content")
                if module == .controls {
                    let required = NotchLayout.controls(hasCards: true, shortcutCount: 1, width: layout.width, height: layout.height)
                    suite.expect(required.height <= layout.height, "home buttons fit their scrollable layout at menu height \(bar)")
                } else if module == .timer {
                    for mode in NotchTimerMode.allCases {
                        let required = NotchLayout.timer(mode: mode, hasSession: false, width: layout.width, height: layout.height)
                        suite.expect(required <= layout.height, "timer controls remain reachable at menu height \(bar)")
                    }
                } else if module == .calendar {
                    let required = NotchLayout.calendarMonthHeaderHeight + NotchLayout.calendarMonthWeekdayHeight
                        + NotchLayout.calendarMonthSpacing * 2 + 6 * NotchLayout.calendarMonthRowHeight(height: layout.height)
                    suite.expect(required <= layout.height, "all six month rows remain reachable at menu height \(bar)")
                } else if module == .clipboard {
                    suite.expect(layout.height >= NotchLayout.clipboardSearchHeight + NotchLayout.rowSpacing
                                 + NotchLayout.clipboardCardHeight,
                                 "a short clipboard page keeps the search field and a complete card reachable")
                } else if module == .camera || module == .mixer {
                    suite.expect(layout.height >= 144, "camera and mixer controls keep a usable height in a short island")
                    if content.height >= 144 {
                        suite.expect(layout.height == content.height,
                                     "camera and mixer actions fit without outer scrolling in a short island")
                    }
                }
            }
        }
        let card = CGSize(width: 424, height: 96)
        suite.expect(pageSize(card, .controls, controls: [.volume]) == card,
                     "a single home card does not introduce unnecessary scrolling")
        suite.expect(pageSize(card, .calendar) != card && pageSize(card, .calendar, detail: true) == card,
                     "vertical detail pages preserve their existing layout")
    }
}
