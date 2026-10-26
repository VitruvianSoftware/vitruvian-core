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
        @Published var width: CGFloat = 424
        @Published var leastSpacing: CGFloat?
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
            return NotchRail(items: entries, rows: state.rows, itemWidth: 76, width: state.width,
                             leastSpacing: state.leastSpacing, scrollTarget: state.selected) { marker($0) }
                .frame(width: state.width, height: 152)
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
        readingLayout(suite)
        readingLevels(suite)
        musicVolumeSizing(suite)
        focus(suite)
        sizing(suite)
        musicControls(suite)
        controlGroups(suite)
    }
    private static func calendarRows(_ suite: TestSuite) {
        // Local noon, so the one-hour event never crosses midnight in any time zone.
        let day = Calendar.current.date(bySettingHour: 12, minute: 0, second: 0,
                                        of: Date(timeIntervalSince1970: 1_780_000_000)) ?? Date(timeIntervalSince1970: 1_780_000_000)
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
            NotchCameraView(size: CGSize(width: 424, height: 180), camera: service) { size in
                Color.black.frame(width: size.width, height: size.height)
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
        // The top row's stop button, as a pill in a full row and a glyph
        // beside the camera, there only while the mirror runs.
        func stopButtonWidth(besideCamera: Bool) -> CGFloat {
            var band = NotchBand()
            band.besideCamera = besideCamera
            let stop = NSHostingView(rootView: NotchCameraStopButton(camera: service).environment(\.notchBand, band))
            stop.layoutSubtreeIfNeeded()
            return stop.fittingSize.width
        }
        let pill = stopButtonWidth(besideCamera: false), glyph = stopButtonWidth(besideCamera: true)
        suite.expect(pill > 0 && glyph > 0, "the top row offers Stop while the mirror runs: \(pill) \(glyph)")
        service.hideEmbedded()
        suite.expect(stopButtonWidth(besideCamera: false) == 0, "the top row's Stop leaves with the mirror")
        settle(host)
        service.showEmbedded()
        settle(host)
        suite.expect(service.isEmbeddedPresented && service.stops == 1,
                     "stopping from the top row brings back the start card, and the camera starts again within the same page")
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
        // Four tiles in one row just miss the narrowest page with their gaps.
        // A rail that may close them keeps every tile whole, side by side;
        // any other still scrolls its last column past the edge.
        state.count = 4
        state.rows = 1
        state.width = 304
        host.frame = NSRect(x: 0, y: 0, width: 304, height: 152)
        for least in [NotchLayout.shortcutLeastSpacing, nil] {
            state.leastSpacing = least
            settle(host)
            let tiles = (0..<4).compactMap { id in
                descendants(host).first { $0.identifier?.rawValue == "rail-\(id)" }.map { $0.convert($0.bounds, to: host) }
            }
            let whole = tiles.count == 4 && tiles.allSatisfy { (tile: CGRect) -> Bool in
                tile.minX >= -0.5 && tile.maxX <= 304.5 && abs(tile.width - 76) < 0.5
            }
            suite.expect(whole == (least != nil), least != nil
                         ? "a rail that closes its gaps keeps four tiles whole across the narrowest page"
                         : "a rail with no least gap still scrolls the column that misses its width")
        }
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
        // Option-Up trades two lines; undo and redo put the text and the
        // selection back exactly, not the caret at the end of the note.
        if let coordinator = editor.delegate as? PlainTextEditor.Coordinator {
            editor.string = "one\ntwo\nthree\nfour"
            editor.didChangeText()
            settle(host)
            editor.undoManager?.removeAllActions()
            editor.setSelectedRange(NSRange(location: 5, length: 2))
            let moved = coordinator.moveLine(.up, in: editor)
            settle(host)
            suite.expect(moved && editor.string == "two\none\nthree\nfour"
                         && editor.selectedRange() == NSRange(location: 1, length: 2),
                         "option-up moves the line with its selection")
            editor.undoManager?.undo()
            suite.expect(editor.string == "one\ntwo\nthree\nfour"
                         && editor.selectedRange() == NSRange(location: 5, length: 2),
                         "one undo after a line move restores the text and the selection")
            editor.undoManager?.redo()
            suite.expect(editor.string == "two\none\nthree\nfour"
                         && editor.selectedRange() == NSRange(location: 1, length: 2),
                         "redo moves the line again with the selection on it")
            editor.string = "a\na\nb"
            editor.didChangeText()
            settle(host)
            editor.undoManager?.removeAllActions()
            editor.setSelectedRange(NSRange(location: 2, length: 0))
            suite.expect(coordinator.moveLine(.up, in: editor) && editor.string == "a\na\nb"
                         && editor.selectedRange() == NSRange(location: 0, length: 0)
                         && editor.undoManager?.canUndo != true,
                         "trading two identical lines only moves the caret and leaves no empty undo step")
        } else {
            suite.expect(false, "the scratchpad editor's coordinator is its delegate")
        }
    }

    private static func readingLayout(_ suite: TestSuite) {
        // The most opaque pixel of an empty circle drawn in `appearance`; a
        // palette would lay tertiary label's alpha over the ring's, at ~7%.
        func ink(_ appearance: NSAppearance.Name) -> CGFloat {
            guard let image = TaskBoxAttachment(checked: false, size: 16, description: "").image,
                  let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 32, pixelsHigh: 32,
                                                bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                                                colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0),
                  let context = NSGraphicsContext(bitmapImageRep: bitmap) else { return 0 }
            NSGraphicsContext.saveGraphicsState()
            NSGraphicsContext.current = context
            NSAppearance(named: appearance)?.performAsCurrentDrawingAppearance {
                image.draw(in: NSRect(x: 0, y: 0, width: 32, height: 32))
            }
            NSGraphicsContext.restoreGraphicsState()
            var most: CGFloat = 0
            for x in 0..<32 { for y in 0..<32 { most = max(most, bitmap.colorAt(x: x, y: y)?.alphaComponent ?? 0) } }
            return most
        }
        suite.expect(ink(.aqua) > 0.18 && ink(.darkAqua) > 0.18,
                     "the empty task circle draws at tertiary label strength in light and dark, not faded twice")

        let note = "- [ ] Call the bank\n  - [ ] Ask about the fee\n  - spare key\n    - [ ] copy\n"
            + "- [ ] Book train tickets for Saturday morning and check whether the return can move to Sunday evening\n"
            + "- bread\n  - [ ] rye\n  - crust\n\n> Reminder\n"
            + "> - [ ] Bring the key and the parking pass for the guests who arrive near midnight\n>   - [ ] spare one"
        let view = TaskPreviewTextView(frame: NSRect(x: 0, y: 0, width: 240, height: 400))
        MarkdownPreview.Coordinator().show(ScratchpadSupport.markdownPreview(note), base: 13,
                                           taskStates: (done: "Done", notDone: "Not done"), in: view)
        guard let layout = view.layoutManager, let container = view.textContainer, let storage = view.textStorage else {
            suite.expect(false, "the reading lays its text out")
            return
        }
        layout.ensureLayout(for: container)
        let shown = storage.string as NSString
        guard ["Call the bank", "Ask about", "spare key", "copy", "Book train", "evening", "bread", "rye", "Reminder",
               "Bring the key", "midnight", "spare one"]
            .allSatisfy({ shown.range(of: $0).location != NSNotFound }) else {
            suite.expect(false, "the reading shows every line of the checklist")
            return
        }
        func x(glyph: Int) -> CGFloat {
            layout.boundingRect(forGlyphRange: NSRange(location: glyph, length: 1), in: container).minX
        }
        func x(_ character: Int) -> CGFloat { x(glyph: layout.glyphIndexForCharacter(at: character)) }
        func x(of text: String) -> CGFloat { x(shown.range(of: text).location) }
        /// Where the circle or bullet in front of `text`, and its space, starts.
        func marker(before text: String) -> CGFloat { x(shown.range(of: text).location - 2) }
        suite.expect(abs(marker(before: "Ask about") - x(of: "Call the bank")) < 0.5
                     && abs(marker(before: "spare key") - x(of: "Call the bank")) < 0.5
                     && abs(marker(before: "rye") - x(of: "bread")) < 0.5
                     && abs(marker(before: "copy") - x(of: "spare key")) < 0.5,
                     "a nested task or bullet starts under its parent's text, and a task under a bullet under the bullet's text")
        suite.expect(shown.range(of: "\n  • crust").location != NSNotFound,
                     "a bullet under a plain bullet keeps its leading spaces")
        /// Whether the line holding `last` wraps from the line that opens
        /// with `first` and starts where `first` does.
        func hangs(_ last: String, under first: String) -> Bool {
            var line = NSRange()
            _ = layout.lineFragmentRect(forGlyphAt: layout.glyphIndexForCharacter(at: shown.range(of: last).location),
                                        effectiveRange: &line)
            return line.location > layout.glyphIndexForCharacter(at: shown.range(of: first).location)
                && abs(x(glyph: line.location) - x(of: first)) < 0.5
        }
        suite.expect(hangs("evening", under: "Book train") && hangs("midnight", under: "Bring the key"),
                     "a wrapped task line hangs under the task's text, not under its circle, in a quote as well")
        let bring = shown.range(of: "Bring the key").location
        let quoted = shown.lineRange(for: NSRange(location: bring, length: 0)).location
        let reminder = shown.lineRange(for: shown.range(of: "Reminder")).location
        suite.expect(shown.substring(with: NSRange(location: quoted, length: 1)) == "▏"
                     && abs(x(quoted) - x(reminder)) < 0.5
                     && storage.attribute(.attachment, at: bring - 2, effectiveRange: nil) is TaskBoxAttachment
                     && abs(marker(before: "Bring the key") - x(of: "Reminder")) < 0.5
                     && abs(marker(before: "spare one") - x(of: "Bring the key")) < 0.5
                     && shown.substring(with: NSRange(location: shown.lineRange(for: shown.range(of: "spare one")).location,
                                                      length: 1)) == "▏"
                     && storage.attribute(.foregroundColor, at: bring, effectiveRange: nil) as? NSColor == .secondaryLabelColor,
                     "a task in a quote keeps the quote's bar and colour, with its circle where the quote's text starts and a nested one under its parent's text")
    }
    /// A list that opens below depth 1 lines its items up by their own
    /// depth, whatever list came before, and a task quoted inside a bullet
    /// starts after the quote's bar, which is wider than the bullet.
    private static func readingLevels(_ suite: TestSuite) {
        let note = "- [ ] Water the plants\n\nLater\n\n- - [ ] Feed the cat\n  - [ ] Lock the door\n\n"
            + "- Garden\n  > - [ ] Prune the roses\n  >   - [ ] Buy shears"
        let view = TaskPreviewTextView(frame: NSRect(x: 0, y: 0, width: 240, height: 300))
        MarkdownPreview.Coordinator().show(ScratchpadSupport.markdownPreview(note), base: 13,
                                           taskStates: (done: "Done", notDone: "Not done"), in: view)
        guard let layout = view.layoutManager, let container = view.textContainer, let storage = view.textStorage else {
            suite.expect(false, "the reading lays its text out")
            return
        }
        layout.ensureLayout(for: container)
        let shown = storage.string as NSString
        /// The circle in front of `text`, as a character offset.
        func circle(before text: String) -> Int? {
            let location = shown.range(of: text).location
            guard location != NSNotFound, location >= 2,
                  storage.attribute(.attachment, at: location - 2, effectiveRange: nil) is TaskBoxAttachment else { return nil }
            return location - 2
        }
        func x(_ character: Int) -> CGFloat {
            layout.boundingRect(forGlyphRange: NSRange(location: layout.glyphIndexForCharacter(at: character), length: 1),
                                in: container).minX
        }
        let circles = ["Water the plants", "Feed the cat", "Lock the door", "Prune the roses", "Buy shears"]
            .compactMap(circle(before:))
        guard circles.count == 5 else {
            suite.expect(false, "the reading shows every task of the deeper lists with its circle")
            return
        }
        let water = x(circles[0]), feed = x(circles[1])
        suite.expect(abs(feed - x(circles[2])) < 0.5 && feed > water + 1 && feed < x(circles[0] + 2) - 1,
                     "a list that opens below depth 1 keeps its tasks in line, indented, and not under an earlier list's text")
        suite.expect(abs(x(circles[4]) - x(circles[3] + 2)) < 0.5,
                     "a task quoted inside a bullet starts after the quote's bar, and a task under it sits under its text")
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
    /// What the music page offers beside its player, read from
    /// `NotchMusicControls`, and the player's size, which no longer holds a
    /// row of controls under it.
    private static func musicControls(_ suite: TestSuite) {
        let domain = "com.vitruviansoftware.vitruvian.tests.notch-music-controls"
        let defaults = UserDefaults(suiteName: domain)!
        defaults.removePersistentDomain(forName: domain)
        defer { defaults.removePersistentDomain(forName: domain) }
        // Written out, not left absent: a suite run earlier in the process
        // (features) registers the catalog's defaults, and an absent key
        // would read those.
        for feature in [AppFeature.notchLyrics, .notchQueue] {
            defaults.set(false, forKey: feature.availabilityKey)
        }
        suite.expect(NotchMusicControls(lyricsEnabled: true, queueEnabled: true, in: defaults)
                        == NotchMusicControls(lyrics: false, queue: false),
                     "lyrics and the queue switched on count only once their feature is available")
        defaults.set(true, forKey: AppFeature.notchLyrics.availabilityKey)
        // The Settings preview draws the page with the island off and Music
        // hidden; it offers what the island would.
        defaults.set(false, forKey: DefaultsKey.notchEnabled)
        let lyrics = NotchMusicControls(lyricsEnabled: true, queueEnabled: true, in: defaults)
        suite.expect(lyrics.lyrics && !lyrics.queue,
                     "available lyrics show whether or not the island shows Music")
        suite.expect(NotchMusicControls(lyricsEnabled: false, queueEnabled: false, in: defaults)
                        == NotchMusicControls(lyrics: false, queue: false),
                     "the page's own switches decide, not the stored ones")
        // A page too short for anything grows to hold the player, a
        // timeline taller while something plays.
        func height(playing: Bool, band: CGFloat = 0) -> CGFloat {
            NotchLayout.pageSize(content: CGSize(width: 300, height: 10), module: .music, detail: false, controls: [],
                                 band: NotchBand(), timerMode: .timer, timerHasSession: false, hasPlayback: playing,
                                 musicBand: band).height
        }
        suite.expect(height(playing: true) - height(playing: false)
                        == NotchLayout.musicTimelineHeight + NotchLayout.rowSpacing
                     && height(playing: true) == NotchLayout.musicPlayerHeight(band: 0),
                     "the music page's size holds exactly the player it draws")
        suite.expect(height(playing: true, band: 38) > height(playing: true),
                     "beside a camera row the song sits below the camera and the player grows to hold it")
    }

    /// The home page's split into levels, music and shortcuts, which its
    /// size, its drawing and the Settings preview all read from
    /// `NotchControlGroups`. The levels go to the top row; the player card
    /// is the only card.
    private static func controlGroups(_ suite: TestSuite) {
        let groups = NotchControlGroups([.timer, .volume, .music, .keepAwake, .brightness])
        suite.expect(groups.levels == [.volume, .brightness] && groups.music
                     && groups.shortcuts == [.timer, .keepAwake],
                     "the levels, music and the rest as shortcuts, in their order")
        var besideCamera = NotchBand()
        besideCamera.besideCamera = true
        let short = CGSize(width: 300, height: 10)
        for items: [NotchControlItem] in [[.timer, .volume, .music], [.timer, .calendar, .keepAwake], [.brightness],
                                          [.volume, .brightness, .keyboardLight, .music]] {
            for band in [NotchBand(), besideCamera] {
                let groups = NotchControlGroups(items)
                let page = NotchLayout.pageSize(content: short, module: .controls, detail: false, controls: items,
                                                band: band, timerMode: .timer, timerHasSession: false,
                                                hasPlayback: true, musicBand: 0)
                let levelRow = NotchLayout.bandLevelCount(groups.levels.count, band: band) < groups.levels.count
                let drawn = NotchLayout.controls(hasCards: groups.music, levelRow: levelRow,
                                                 shortcutCount: groups.shortcuts.count,
                                                 width: short.width, height: short.height)
                suite.expect(page.height == max(short.height, drawn.height),
                             "the home page's size holds the rows it draws for \(items), beside a camera: \(band.besideCamera)")
            }
        }
    }

    /// The music page holds the optional volume row beside the player it
    /// draws, and adds no scrolling when everything fits.
    private static func musicVolumeSizing(_ suite: TestSuite) {
        let screen = CGRect(x: 0, y: 0, width: 1440, height: 900)
        for notched in [false, true] {
            for layout: NotchSize in [.compact, .spacious, .custom] {
                var geometry = NotchGeometry(screen: screen, safeAreaTop: notched ? 32 : 0,
                                             cameraWidth: notched ? 210 : 0, layout: layout,
                                             customWidth: 480, customHeight: 260)
                geometry.pageTop = NotchModule.music.pageTop
                for playing in [false, true] {
                    for showVolume in [false, true] {
                        let minimum = NotchLayout.musicPlayerHeight(band: geometry.musicBandHeight,
                                                                    playing: playing, showVolume: showVolume)
                        for available: CGFloat in [100, minimum, 300] {
                            let size = NotchLayout.pageSize(
                                content: CGSize(width: 304, height: available), module: .music, detail: false,
                                controls: [], band: NotchBand(), timerMode: .timer, timerHasSession: false,
                                hasPlayback: playing, musicBand: geometry.musicBandHeight,
                                musicShowsVolume: showVolume)
                            suite.expect(size == CGSize(width: 304, height: max(available, minimum)),
                                         "the music page keeps all controls reachable in short islands and adds no scrolling when they fit: \(layout), notched \(notched), playing \(playing), volume \(showVolume)")
                        }
                    }
                }
            }
        }
    }

    private static func sizing(_ suite: TestSuite) {
        /// A page's size with the home page's usual items, a song playing and
        /// no timer under way, across a row without a camera.
        func pageSize(_ content: CGSize, _ module: NotchModule, detail: Bool = false,
                      controls: [NotchControlItem] = [.music, .volume, .brightness, .timer],
                      timerMode: NotchTimerMode = .timer) -> CGSize {
            NotchLayout.pageSize(content: content, module: module, detail: detail, controls: controls,
                                 band: NotchBand(), timerMode: timerMode, timerHasSession: false,
                                 hasPlayback: true, musicBand: 0)
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
                    // Playback keeps the card row; the levels sit in the top row.
                    let required = NotchLayout.controls(hasCards: true, shortcutCount: 1,
                                                        width: layout.width, height: layout.height)
                    suite.expect(required.height <= layout.height, "home buttons fit their scrollable layout at menu height \(bar)")
                } else if module == .timer {
                    // Each mode sizes the island for itself, the Pomodoro a line taller.
                    for mode in NotchTimerMode.allCases {
                        let content = geometry.contentSize(for: geometry.expandedSize(module: module, timerMode: mode))
                        let layout = pageSize(content, module, timerMode: mode)
                        let required = NotchLayout.timer(mode: mode, hasSession: false, height: layout.height)
                        suite.expect(required <= layout.height && layout.height >= content.height,
                                     "timer controls remain reachable at menu height \(bar): \(mode)")
                    }
                    // A page shorter than every mode needs scrolls to the
                    // mode it shows, which only the page's own mode decides.
                    let short = CGSize(width: content.width, height: 60)
                    let heights = NotchTimerMode.allCases.map { pageSize(short, module, timerMode: $0).height }
                    suite.expect(heights == NotchTimerMode.allCases.map { NotchLayout.timer(mode: $0, hasSession: false, height: 60) }
                                 && heights[1] > heights[0],
                                 "a short page scrolls to its own mode's controls at menu height \(bar): \(heights)")
                } else if module == .calendar {
                    let required = NotchLayout.calendarMonthWeekdayHeight
                        + 6 * NotchLayout.calendarMonthRowHeight(height: layout.height)
                    suite.expect(required <= layout.height, "all six month rows remain reachable at menu height \(bar)")
                } else if module == .clipboard {
                    suite.expect(layout.height >= NotchLayout.clipboardCardHeight,
                                 "a short clipboard page keeps a complete card reachable")
                } else if module == .camera || module == .mixer {
                    // The mixer's controls sit in the top row, so its faders take the whole page.
                    let minimum = module == .camera ? 144 : NotchLayout.mixerMinimumHeight
                    suite.expect(layout.height >= minimum, "camera and mixer controls keep a usable height in a short island")
                    if content.height >= minimum {
                        suite.expect(layout.height == content.height,
                                     "camera and mixer actions fit without outer scrolling in a short island")
                    }
                }
            }
        }
        let card = CGSize(width: 424, height: 96)
        suite.expect(pageSize(card, .controls, controls: [.volume]) == card,
                     "a single home level does not introduce unnecessary scrolling")
        suite.expect(pageSize(card, .calendar) != card && pageSize(card, .calendar, detail: true) == card,
                     "vertical detail pages preserve their existing layout")
    }
}
