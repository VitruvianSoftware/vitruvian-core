// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 VitruvianSoftware

import AppKit
import SwiftUI
import VitruvianCore
import VitruvianServices
import VitruvianToolProtocol
import VitruvianUI

/// An extension's settings as they are drawn, in the Extensions sheet and
/// on the Dynamic Island page, read back from the drawing itself: the
/// pixels, and the AppKit controls SwiftUI draws. Each check is of
/// something a person saw wrong in 3.63.0 while every test of the plain
/// values passed:
///
/// - the island page's live preview stays in its card, and draws over
///   neither the pane's header nor the search field under it;
/// - the pane opens at its top, and a search in it scrolls only its own
///   region;
/// - the section links stay where they are whichever one is lit;
/// - Vitruvian's own switches end where the extension's do;
/// - the sheet's scrolling region takes the room the window has;
/// - a menu on the island never cuts its title short.
///
/// Each drawing is also kept as a PNG, for a person to look at: in the
/// test's outputs under Bazel, or in a folder the run prints.
enum ExtensionSettingsLayoutTests {
    static func run(_ suite: TestSuite) {
        theLinksKeepTheirPlaces(suite)
        aChoiceTitleIsNeverCutOnTheIsland(suite)
        theIslandPaneKeepsItsPreviewInItsCard(suite)
        theSheetLinesUpItsSwitches(suite)
        theSheetTakesTheRoomItHas(suite)
        theRemoteSheetLightsEachLink(suite)
    }

    // MARK: Pages shaped as the extensions' own

    typealias PanelBench = ToolPanelHostTests.Bench

    static let english = FeatureStrings.externalTools(.enUS)

    /// HomeSpeaker's island page, taller than the preview's card.
    static let homeSpeakerIsland = #"""
        {"blocks": [
          {"type": "toggle", "id": "home", "title": "Home speakers", "value": true},
          {"type": "toggle", "id": "mac", "title": "This Mac", "value": false},
          {"type": "text", "text": "Speaking on Lake Office display", "style": "caption"},
          {"type": "divider"},
          {"type": "heading", "text": "Coding agents"},
          {"type": "toggle", "id": "claude", "title": "Claude Code", "value": true},
          {"type": "toggle", "id": "agy", "title": "Antigravity", "value": true},
          {"type": "heading", "text": "Chat apps"},
          {"type": "toggle", "id": "slack", "title": "Slack", "value": true},
          {"type": "toggle", "id": "gchat", "title": "Google Chat", "value": false},
          {"type": "toggle", "id": "beeper", "title": "Beeper", "value": true},
          \#(announce),
          {"type": "heading", "text": "Networks"},
          {"type": "toggle", "id": "n.beeper", "title": "Beeper", "value": true},
          {"type": "toggle", "id": "n.gchat", "title": "Google Chat", "value": true},
          {"type": "toggle", "id": "n.messages", "title": "Google Messages", "value": true},
          {"type": "toggle", "id": "n.signal", "title": "Signal", "value": true},
          {"type": "toggle", "id": "n.telegram", "title": "Telegram", "value": true},
          {"type": "toggle", "id": "n.whatsapp", "title": "WhatsApp", "value": true},
          {"type": "toggle", "id": "skip", "title": "Skip messages I sent", "value": true},
          \#(speaker),
          \#(volume)
        ]}
        """#

    /// HomeSpeaker's menus: Announce, whose options run long, Speaker and
    /// Volume.
    static let announce = #"""
        {"type": "choice", "id": "announce", "title": "Announce", "value": "every",
         "options": [{"value": "every", "title": "Every message"},
                     {"value": "direct", "title": "Direct messages and mentions only"}]}
        """#
    static let speaker = #"""
        {"type": "choice", "id": "speaker", "title": "Speaker", "value": "lake",
         "options": [{"value": "lake", "title": "Lake Office display"}, {"value": "kitchen", "title": "Kitchen"},
                     {"value": "all", "title": "All speakers"}]}
        """#
    static let volume = #"""
        {"type": "choice", "id": "volume", "title": "Volume", "value": "50",
         "options": [{"value": "25", "title": "25%"}, {"value": "50", "title": "50%"}, {"value": "75", "title": "75%"}]}
        """#

    /// HomeSpeaker's settings page: five sections.
    static let homeSpeakerSettings = #"""
        {"blocks": [
          {"type": "heading", "text": "General", "section": true},
          {"type": "heading", "text": "Which HomeSpeaker"},
          {"type": "text", "text": "This Mac uses the extension."},
          {"type": "button", "id": "app", "title": "Use the app instead"},
          {"type": "button", "id": "copy", "title": "Copy settings from the app"},
          {"type": "heading", "text": "Speakers", "section": true},
          \#(speaker),
          \#(volume),
          {"type": "toggle", "id": "home", "title": "Home speakers", "value": true},
          {"type": "toggle", "id": "mac", "title": "This Mac", "value": false},
          {"type": "heading", "text": "Chats", "section": true},
          {"type": "toggle", "id": "slack", "title": "Slack", "value": true},
          {"type": "toggle", "id": "gchat", "title": "Google Chat", "value": false},
          {"type": "toggle", "id": "beeper", "title": "Beeper", "value": true},
          \#(announce),
          {"type": "toggle", "id": "skip", "title": "Skip messages I sent", "value": true},
          {"type": "heading", "text": "AI Agents", "section": true},
          {"type": "toggle", "id": "claude", "title": "Claude Code", "value": true},
          {"type": "toggle", "id": "agy", "title": "Antigravity", "value": true},
          {"type": "heading", "text": "Google Cloud", "section": true},
          {"type": "heading", "text": "Google Home Account"},
          {"type": "button", "id": "signout", "title": "Sign Out"},
          {"type": "text", "text": "Sign Out also signs out of Google Chat and stops the Chat monitor.", "style": "caption"},
          {"type": "toggle", "id": "voice", "title": "Enable Voice Broadcasting", "value": true}
        ]}
        """#

    /// Vitruvian Remote's settings page: four sections.
    static let remoteSettings = #"""
        {"blocks": [
          {"type": "heading", "text": "General", "section": true},
          {"type": "heading", "text": "Which Vitruvian Remote"},
          {"type": "row", "id": "which", "title": "Using the Vitruvian extension",
           "subtitle": "The standalone setup is quiet so only one agent runs on port 7411.", "icon": "iphone"},
          {"type": "button", "id": "copy", "title": "Copy Settings & Pairing from Standalone Setup"},
          {"type": "button", "id": "standalone", "title": "Use the Standalone App Instead"},
          {"type": "heading", "text": "Agent & Network"},
          {"type": "row", "id": "agent", "title": "Agent running", "subtitle": "Tailscale, port 7411", "icon": "waveform.path.ecg"},
          {"type": "row", "id": "phone", "title": "Phone paired, not connected", "icon": "iphone"},
          {"type": "toggle", "id": "answer", "title": "Answer Claude Code prompts on phone", "value": true},
          {"type": "heading", "text": "Pairing & Bridge", "section": true},
          {"type": "heading", "text": "Pair a Phone"},
          {"type": "button", "id": "qr", "title": "Pair with QR Code"},
          {"type": "text", "text": "Or enter the 6-digit code shown on the phone", "style": "caption"},
          {"type": "field", "id": "code", "title": "Code", "value": "482917"},
          {"type": "button", "id": "pair", "title": "Pair with 6-Digit Code"},
          {"type": "button", "id": "unpair", "title": "Unpair All Phones…"},
          {"type": "heading", "text": "Notifications", "section": true},
          {"type": "heading", "text": "Push Notifications (ntfy)"},
          {"type": "toggle", "id": "push", "title": "Enable push notifications", "value": false,
           "help": "Publishes push notifications to your ntfy topic when an agent needs attention."},
          {"type": "field", "id": "url", "title": "ntfy server URL", "value": "https://ntfy.example.dev"},
          {"type": "field", "id": "topic", "title": "ntfy topic", "value": "vitruvian-remote"},
          {"type": "heading", "text": "Integrations", "section": true},
          {"type": "heading", "text": "Command Execution & GitHub"},
          {"type": "field", "id": "exec", "title": "Working directory for commands", "value": "~/code"},
          {"type": "field", "id": "repos", "title": "Extra GitHub repositories", "value": "",
           "placeholder": "owner/repo1,owner/repo2"},
          {"type": "divider"},
          {"type": "heading", "text": "Kubernetes & Prometheus"},
          {"type": "field", "id": "kube", "title": "Kubeconfig", "value": "~/.kube/config"},
          {"type": "field", "id": "prom", "title": "Prometheus URL", "value": "http://prometheus:9090"}
        ]}
        """#

    /// A manifest with an island page and a settings page, as both
    /// extensions have, under the panel bench's tool id.
    static func manifest(name: String, icon: String, setting: Bool) -> Data {
        let preferences = setting
            ? #"[{"id": "chime", "title": {"en": "Chime before speaking"}, "type": "boolean", "default": true}]"#
            : "null"
        return ExternalToolManifestTests.file(#"""
            {"name": {"en": "\#(name)"}, "publisher": "VitruvianSoftware", "version": "1.26.0", "icon": "\#(icon)",
             "description": {"en": "Speaks what you type, or the clipboard, on your Google Home speakers."},
             "protocol": "2", "uses": ["notify", "storage"],
             "contributes": {
               "commands": [{"id": "speak", "title": {"en": "Speak the clipboard"}, "surfaces": ["commandBar"]}],
               "panels": [{"id": "deploys", "title": {"en": "\#(name)"}, "placement": "island"},
                          {"id": "settings", "title": {"en": "\#(name)"}, "placement": "settings"}],
               "status": {"placement": "island"}},
             "preferences": \#(preferences)}
            """#)
    }

    /// Answers each page the tool was asked for with `pages`, by panel.
    static func answer(_ bench: PanelBench, _ pages: [String: String]) {
        guard !bench.runs.isEmpty else { return }
        bench.current.greets()
        var answered: Set<Int> = []
        for _ in 0..<3 {
            for message in bench.current.sent {
                guard case .request(.number(let id), "ui/open", .object(let params)) = message,
                      !answered.contains(id), case .string(let panel)? = params["panel"],
                      let page = pages[panel] else { continue }
                answered.insert(id)
                // One line, as the protocol frames a message.
                bench.current.answers(id, #"{"tree":\#(page.replacingOccurrences(of: "\n", with: " "))}"#)
            }
            settle()
        }
        if !bench.logged.isEmpty { print("ExtensionSettingsLayoutTests: the tool's log: \(bench.logged)") }
    }

    // MARK: Drawing

    /// A window off screen that can take the keyboard, as Settings can.
    final class KeyWindow: NSWindow {
        override var canBecomeKey: Bool { true }
        override var canBecomeMain: Bool { true }
    }

    static func settle(_ seconds: TimeInterval = 0.1) {
        RunLoop.current.run(until: Date().addingTimeInterval(seconds))
    }

    /// `root` in a window of `size` off screen, in the light or dark
    /// appearance.
    static func offScreen(_ root: some View, size: CGSize, dark: Bool = false) -> (NSWindow, NSView) {
        _ = NSApplication.shared
        // On the window's own background, so a picture of it has one in
        // either appearance.
        let view = NSHostingView(rootView: root.frame(width: size.width, height: size.height, alignment: .topLeading)
            .background(Color(nsColor: .windowBackgroundColor)))
        let window = KeyWindow(contentRect: NSRect(x: -12_000, y: -12_000, width: size.width, height: size.height),
                               styleMask: [.borderless], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.appearance = NSAppearance(named: dark ? .darkAqua : .aqua)
        window.contentView = view
        window.orderFrontRegardless()
        window.makeKey()
        view.layoutSubtreeIfNeeded()
        settle()
        return (window, view)
    }

    static func takeDown(_ window: NSWindow) {
        if let sheet = window.attachedSheet {
            window.endSheet(sheet)
            sheet.orderOut(nil)
        }
        settle()
        window.orderOut(nil)
        window.contentView = nil
        window.close()
    }

    /// `content` as a SwiftUI sheet on a window `height` points high, as
    /// the Extensions page shows it: the parent window, the sheet's window
    /// and the sheet's view, once it is shown.
    static func sheet(_ content: some View, parentHeight: CGFloat, dark: Bool = false)
        -> (parent: NSWindow, sheet: NSWindow, view: NSView)? {
        let (parent, _) = offScreen(SheetPresenter(content: content), size: CGSize(width: 780, height: parentHeight),
                                 dark: dark)
        guard ToolRuntimeSupport.wait(upTo: 5, until: { parent.attachedSheet?.contentView != nil }),
              let sheet = parent.attachedSheet, let view = sheet.contentView else {
            takeDown(parent)
            return nil
        }
        sheet.appearance = parent.appearance
        settle(0.4)
        view.layoutSubtreeIfNeeded()
        settle(0.2)
        return (parent, sheet, view)
    }

    private struct SheetPresenter<Content: View>: View {
        let content: Content
        @State private var shown = false

        var body: some View {
            Color.clear
                .sheet(isPresented: $shown) { content.background(Color(nsColor: .windowBackgroundColor)) }
                .onAppear { shown = true }
        }
    }

    /// What was drawn, as the pixels of a picture of it.
    struct Picture {
        let rep: NSBitmapImageRep
        /// The drawing's size, in points.
        let points: CGSize

        private var scale: CGFloat { CGFloat(rep.pixelsWide) / max(points.width, 1) }

        /// The bounds, in points from the top left, of the island's black:
        /// the pixels that are black in a drawing in the light appearance,
        /// where nothing else is. Within `rect` when it is given; nil for
        /// none.
        func black(in rect: CGRect? = nil) -> CGRect? {
            guard let data = rep.bitmapData else { return nil }
            let area = (rect ?? CGRect(origin: .zero, size: points)).intersection(CGRect(origin: .zero, size: points))
            guard !area.isNull, area.width > 0, area.height > 0 else { return nil }
            let row = rep.bytesPerRow, step = rep.bitsPerPixel / 8
            var found: (minX: Int, minY: Int, maxX: Int, maxY: Int)?
            for y in Int(area.minY * scale)..<min(rep.pixelsHigh, Int(area.maxY * scale)) {
                for x in Int(area.minX * scale)..<min(rep.pixelsWide, Int(area.maxX * scale)) {
                    let pixel = data + y * row + x * step
                    guard pixel[0] <= 6, pixel[1] <= 6, pixel[2] <= 6, pixel[3] >= 250 else { continue }
                    found = found.map { (min($0.minX, x), min($0.minY, y), max($0.maxX, x), max($0.maxY, y)) }
                        ?? (x, y, x, y)
                }
            }
            return found.map {
                CGRect(x: CGFloat($0.minX) / scale, y: CGFloat($0.minY) / scale,
                       width: CGFloat($0.maxX - $0.minX + 1) / scale, height: CGFloat($0.maxY - $0.minY + 1) / scale)
            }
        }
    }

    /// Where the pictures go: the test's outputs under Bazel, else a
    /// folder of their own, which the run prints.
    static let shots: URL = {
        if let outputs = ProcessInfo.processInfo.environment["TEST_UNDECLARED_OUTPUTS_DIR"] {
            return URL(fileURLWithPath: outputs, isDirectory: true).appendingPathComponent("layout-shots")
        }
        return FileManager.default.temporaryDirectory.appendingPathComponent("vitruvian-layout-shots", isDirectory: true)
    }()

    /// A picture of `view` as drawn, on its window's background, at the
    /// display's scale, kept as `name`.
    @discardableResult
    static func picture(_ view: NSView, _ name: String) -> Picture? {
        view.layoutSubtreeIfNeeded()
        guard let drawn = view.bitmapImageRepForCachingDisplay(in: view.bounds),
              let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: drawn.pixelsWide,
                                         pixelsHigh: drawn.pixelsHigh, bitsPerSample: 8, samplesPerPixel: 4,
                                         hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB,
                                         bytesPerRow: 0, bitsPerPixel: 0) else { return nil }
        view.cacheDisplay(in: view.bounds, to: drawn)
        let size = view.bounds.size
        rep.size = size
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
        // The window's background in the view's appearance, resolved there:
        // a picture has no window behind it.
        let dark = view.effectiveAppearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
        var background = CGColor(gray: dark ? 0.12 : 0.93, alpha: 1)
        NSAppearance(named: dark ? .darkAqua : .aqua)?.performAsCurrentDrawingAppearance {
            if let resolved = NSColor.windowBackgroundColor.usingColorSpace(.sRGB) { background = resolved.cgColor }
        }
        NSGraphicsContext.current?.cgContext.setFillColor(background)
        NSGraphicsContext.current?.cgContext.fill(CGRect(origin: .zero, size: size))
        drawn.draw(in: NSRect(origin: .zero, size: size))
        NSGraphicsContext.restoreGraphicsState()
        try? FileManager.default.createDirectory(at: shots, withIntermediateDirectories: true)
        try? rep.representation(using: .png, properties: [:])?.write(to: shots.appendingPathComponent(name))
        print("ExtensionSettingsLayoutTests: drew \(shots.appendingPathComponent(name).path)")
        return Picture(rep: rep, points: size)
    }

    // MARK: Reading the drawn controls

    static func views<V: NSView>(in view: NSView, of type: V.Type) -> [V] {
        view.subviews.flatMap { subview -> [V] in
            (subview as? V).map { [$0] + views(in: subview, of: type) } ?? views(in: subview, of: type)
        }
    }

    /// The menus: pop-up buttons, or the focus ring macOS 26 and later
    /// leaves at a menu SwiftUI draws (as `BlockTreeLayoutTests` finds them).
    static func menus(in view: NSView) -> [NSView] {
        view.subviews.flatMap { subview -> [NSView] in
            if subview is NSPopUpButton || String(describing: Swift.type(of: subview)).contains("FocusRing") {
                return [subview]
            }
            return menus(in: subview)
        }
    }

    /// A control's frame in `host`, without the bezel some versions draw
    /// past the rect SwiftUI lines up, from the top left.
    static func frame(of control: NSView, in host: NSView) -> CGRect {
        guard let superview = control.superview else { return .zero }
        let frame = superview.convert(control.alignmentRect(forFrame: control.frame), to: host)
        return host.isFlipped ? frame : CGRect(x: frame.minX, y: host.bounds.height - frame.maxY,
                                                width: frame.width, height: frame.height)
    }

    /// The search field of an extension's settings.
    static func searchField(in view: NSView) -> NSTextField? {
        views(in: view, of: NSTextField.self).first { $0.isEditable && $0.placeholderString == english.searchSettings }
            ?? views(in: view, of: NSTextField.self).first { $0.isEditable }
    }

    /// The scroll views that are in no other.
    static func outermostScrollViews(in view: NSView) -> [NSScrollView] {
        view.subviews.flatMap { subview -> [NSScrollView] in
            if let scroll = subview as? NSScrollView { return [scroll] }
            return outermostScrollViews(in: subview)
        }
    }

    /// Types `text` into `field`, as a person does.
    static func typeText(_ text: String, into field: NSTextField) {
        field.window?.makeFirstResponder(field)
        settle()
        (field.currentEditor() as? NSTextView)?.insertText(text,
                                                            replacementRange: NSRange(location: NSNotFound, length: 0))
        settle(0.3)
    }

    // MARK: The links

    /// Vitruvian Remote's links, as its sheet draws them.
    static let remoteLinks: [(title: String, anchor: SettingsSheetIndex.Anchor)] = [
        (english.vitruvianSection, .vitruvianHeading), ("General", .panelItem(0)), ("Pairing & Bridge", .panelItem(9)),
        ("Notifications", .panelItem(16)), ("Integrations", .panelItem(21)), (english.commandsTitle, .commands),
        (english.usesTitle, .uses),
    ]

    private final class Placed {
        var frames: [CGRect] = []
    }

    /// The links drawn at the sheet's width with `current` lit: where each
    /// was placed, from the row's top left.
    static func linkFrames(_ links: [(title: String, anchor: SettingsSheetIndex.Anchor)],
                           current: SettingsSheetIndex.Anchor?,
                           width: CGFloat = ExternalToolDetailHeightTests.listsWidth) -> [CGRect] {
        let placed = Placed()
        let row = SettingsSheetLinks(links: links, current: current, focus: nil, jump: { _ in },
                                     placed: { placed.frames = $0 })
        let (window, _) = offScreen(row, size: CGSize(width: width, height: 120))
        takeDown(window)
        return placed.frames
    }

    /// Lighting a link changes only its fill: every link keeps its place
    /// whichever is lit, so none jumps to another row as the sheet scrolls
    /// or a link is used, and each row starts at the same edge.
    static func theLinksKeepTheirPlaces(_ suite: TestSuite) {
        let unlit = linkFrames(remoteLinks, current: nil)
        for link in remoteLinks {
            let lit = linkFrames(remoteLinks, current: link.anchor)
            let moved = zip(unlit, lit).enumerated().filter { _, pair in
                abs(pair.0.minX - pair.1.minX) > 0.5 || abs(pair.0.minY - pair.1.minY) > 0.5
                    || abs(pair.0.width - pair.1.width) > 0.5
            }
            suite.expect(lit.count == remoteLinks.count && unlit.count == lit.count && moved.isEmpty,
                         "with \(link.title) lit, every link is where it is with none lit: "
                             + moved.map { "\(remoteLinks[$0.offset].title) at \(Int($0.element.1.minX)),"
                                 + "\(Int($0.element.1.minY)) w\(Int($0.element.1.width)) not \(Int($0.element.0.minX)),"
                                 + "\(Int($0.element.0.minY)) w\(Int($0.element.0.width))" }.joined(separator: "; "))
        }
        let rows = Dictionary(grouping: unlit, by: { Int($0.minY.rounded()) })
        let edge = unlit.first?.minX ?? 0
        suite.expect(rows.count >= 2 && rows.values.allSatisfy { abs(($0.map(\.minX).min() ?? -1) - edge) <= 0.5 },
                     "the links wrap onto \(rows.count) rows, each starting at the same edge: "
                         + rows.sorted { $0.key < $1.key }.map { "\(Int($0.value.map(\.minX).min() ?? -1))" }
                         .joined(separator: ", "))
    }

    // MARK: The island's menus

    /// The island's width for a page in the preview of the Dynamic Island
    /// page in a window as narrow as James's: 306 points of pane, less the
    /// preview's margins.
    static let islandWidth: CGFloat = 246

    /// A menu's title is the row's name: it is drawn whole, and the menu
    /// gives up its own width and cuts its option's words instead.
    static func aChoiceTitleIsNeverCutOnTheIsland(_ suite: TestSuite) {
        guard let content = ToolPanelScreensTests.content(#"{"blocks": [\#(announce), \#(speaker), \#(volume)]}"#,
                                                          size: .island) else {
            suite.expect(false, "the island page reads")
            return
        }
        let page = BlockTreeView(content: content, size: .island, act: { _, _, _ in }, follow: { _ in })
            .padding(14)
            .background(Color.black)
            .environment(\.colorScheme, .dark)
        let (window, view) = offScreen(page, size: CGSize(width: islandWidth + 28, height: 140), dark: true)
        defer { takeDown(window) }
        picture(view, "island-choice-announce.png")
        let menus = menus(in: view).map { frame(of: $0, in: view) }.sorted { $0.minY < $1.minY }
        let font = NSFont.systemFont(ofSize: 12)
        // A row is its title, a gap of 10, a spacer of at least 8, a gap of
        // 10 and the menu; the page starts 14 in.
        let titles = ["Announce", "Speaker", "Volume"]
        suite.expect(menus.count == titles.count, "the island page draws its three menus: \(menus.count)")
        for (title, menu) in zip(titles, menus) {
            let whole = ceil((title as NSString).size(withAttributes: [.font: font]).width)
            let room = menu.minX - 14 - 28
            suite.expect(room >= whole - 0.5,
                         "\(title)'s title is drawn whole at the island's width: \(Int(room)) points for its "
                             + "\(Int(whole)), the menu from \(Int(menu.minX)) to \(Int(menu.maxX))")
            suite.expect(menu.maxX <= islandWidth + 14 + 1 && menu.width >= 44,
                         "\(title)'s menu stays within the island, at the trailing edge, and keeps a usable width: "
                             + "\(Int(menu.minX))–\(Int(menu.maxX)) of \(Int(islandWidth + 14))")
        }
    }

    // MARK: The Dynamic Island page

    /// The pane of the Dynamic Island page for a HomeSpeaker-shaped
    /// extension, at the width of James's window (306 points), with a
    /// preview as tall as the built-in previews are there.
    static let paneWidth: CGFloat = 306
    static let previewHeight: CGFloat = 250

    static func theIslandPaneKeepsItsPreviewInItsCard(_ suite: TestSuite) {
        for dark in [false, true] {
            let bench = PanelBench()
            guard let described = ExternalToolManifestTests.tool(String(data: manifest(name: "HomeSpeaker",
                                                                                         icon: "hifispeaker.2",
                                                                                         setting: false),
                                                                          encoding: .utf8) ?? "") else {
                suite.expect(false, "the manifest reads")
                return
            }
            let pane = NotchExtensionPane(manifest: described, shown: true)
            let column = NotchSectionScroll {
                NotchExtensionDetail(pane: pane, title: "HomeSpeaker", symbol: "hifispeaker.2", shown: true,
                                     previewHeight: previewHeight, host: bench.host,
                                     window: NotchExtensionPaneTests.shown()) {}
            }
            let (window, view) = offScreen(column, size: CGSize(width: paneWidth, height: 810), dark: dark)
            answer(bench, ["deploys": homeSpeakerIsland, "settings": homeSpeakerSettings])
            settle(0.3)
            view.layoutSubtreeIfNeeded()
            let name = dark ? "dark" : "light"
            let outer = outermostScrollViews(in: view).first
            let opened = outer?.documentVisibleRect.minY
            guard let drawn = picture(view, "island-pane-homespeaker-\(name).png") else {
                suite.expect(false, "\(name): the pane can be drawn")
                takeDown(window)
                return
            }
            if !dark {
                suite.expect(opened == 0, "the pane opens at its top, its header in view: scrolled "
                                 + "\(opened.map { "\(Int($0))" } ?? "no scroll view") points")
                let field = searchField(in: view).map { frame(of: $0, in: view) }
                let island = drawn.black()
                suite.expect(field != nil && island != nil, "the pane draws the island's page and the search field")
                if let field, let island {
                    suite.expect(island.maxY <= field.minY,
                                 "the preview's island ends above the search field: island \(Int(island.minY))–"
                                     + "\(Int(island.maxY)), field at \(Int(field.minY))")
                    suite.expect(island.height <= previewHeight,
                                 "the preview's island is cut to its card, \(Int(previewHeight)) points: "
                                     + "\(Int(island.height))")
                }
                let header = drawn.black(in: CGRect(x: 0, y: 0, width: paneWidth, height: 38))
                suite.expect(header == nil,
                             "the pane's header is in view, not under the preview: island in the header at "
                                 + "\(header.map { "\($0)" } ?? "none")")
                if let field = searchField(in: view) {
                    // The pane scrolled to its end by hand, then the last of
                    // the page's links clicked, as a person does.
                    if let outer, let document = outer.documentView {
                        let end = max(0, document.frame.height - outer.contentView.bounds.height)
                        outer.contentView.scroll(to: NSPoint(x: 0, y: end))
                        outer.reflectScrolledClipView(outer.contentView)
                        settle()
                    }
                    let before = outer?.documentVisibleRect.minY
                    let row = frame(of: field, in: view)
                    let links = ["General", "Speakers", "Chats", "AI Agents", "Google Cloud"].enumerated()
                        .map { (title: $1, anchor: SettingsSheetIndex.Anchor.panelItem($0)) }
                    if let last = linkFrames(links, current: nil, width: row.width).last {
                        click(at: CGPoint(x: row.minX + last.midX, y: row.maxY + 8 + last.midY), in: view)
                        settle(0.5)
                    }
                    let inner = outer.flatMap { $0.documentView }.flatMap { views(in: $0, of: NSScrollView.self).first }
                    let linked = outer?.documentVisibleRect.minY
                    suite.expect((before ?? 0) > 0 && linked == before && (inner?.documentVisibleRect.minY ?? 0) > 0,
                                 "a link scrolls only the settings' own region, never the pane: the pane moved from "
                                     + "\(before.map { "\(Int($0))" } ?? "?") to \(linked.map { "\(Int($0))" } ?? "?"), "
                                     + "the region to \(inner.map { "\(Int($0.documentVisibleRect.minY))" } ?? "none")")
                    picture(view, "island-pane-homespeaker-linked.png")
                    typeText("speak", into: field)
                    let after = outer?.documentVisibleRect.minY
                    // A search keeps fewer links, so the pane may be shorter
                    // and end higher; it moves no further than that.
                    let end = outer.flatMap { outer in
                        outer.documentView.map { max(0, $0.frame.height - outer.contentView.bounds.height) }
                    }
                    suite.expect(after != nil && after == linked.flatMap { linked in end.map { min(linked, $0) } },
                                 "a search scrolls only the settings' own region, never the pane: the pane moved from "
                                     + "\(linked.map { "\(Int($0))" } ?? "?") to \(after.map { "\(Int($0))" } ?? "?"), "
                                     + "its end now at \(end.map { "\(Int($0))" } ?? "?")")
                    picture(view, "island-pane-homespeaker-searched.png")
                }
            }
            takeDown(window)
        }
    }

    // MARK: The Extensions sheet

    /// A HomeSpeaker-shaped detail, its settings page shown by `bench`.
    static func detail(_ bench: PanelBench, name: String, icon: String, settings page: String, setting: Bool)
        -> ExternalToolDetailView? {
        let store = ExternalToolStoreTests.Bench()
        defer { store.close() }
        guard case .success = store.add(store.folder(manifest: manifest(name: name, icon: icon, setting: setting))),
              let listed = store.store.listed.first else { return nil }
        bench.host.open(ToolPanelHostTests.key("settings"), in: .settings)
        answer(bench, ["settings": page])
        let detail = ExternalToolDetail(listed, files: store.store.folder(of: listed.id), language: .enUS,
                                        strings: english, settings: store.store.settings(of: listed.id),
                                        settingsTitle: "Settings", updateAvailable: false, showsInIsland: true,
                                        showsStatus: true)
        return ExternalToolDetailView(
            detail: detail, log: "", removal: ToolRemovalContent(name: name, strings: english, cancel: "Cancel"),
            text: english, startAgain: {}, saveSetting: { _, _ in true }, setShowsInIsland: { _ in },
            setShowsStatus: { _ in }, panel: { _, _ in }, openWindow: { _ in }, reveal: {}, openShortcuts: {},
            update: {}, updateNow: {}, remove: { _ in }, close: {}, host: bench.host)
    }

    /// Vitruvian's own switches, the manifest's setting and the extension's
    /// switches all end at one trailing edge, as the extension's do among
    /// themselves.
    static func theSheetLinesUpItsSwitches(_ suite: TestSuite) {
        for dark in [false, true] {
            let bench = PanelBench()
            guard let view = detail(bench, name: "HomeSpeaker", icon: "hifispeaker.2", settings: homeSpeakerSettings,
                                    setting: true),
                  let shown = sheet(view, parentHeight: 1009, dark: dark) else {
                suite.expect(false, "the HomeSpeaker sheet is shown")
                return
            }
            defer { takeDown(shown.parent) }
            let name = dark ? "dark" : "light"
            picture(shown.view, "sheet-homespeaker-\(name).png")
            let switches = views(in: shown.view, of: NSSwitch.self).map { frame(of: $0, in: shown.view) }
                .sorted { $0.minY < $1.minY }
            let edges = switches.map(\.maxX)
            suite.expect(switches.count >= 5 && edges.allSatisfy { abs($0 - edges[0]) <= 1 },
                         "\(name): every switch on the sheet, Vitruvian's own and the extension's, ends at one edge: "
                             + edges.map { "\(Int($0))" }.joined(separator: ", "))
        }
    }

    /// The scrolling region of a sheet with a settings page is as tall as
    /// the window lets it be, up to the 800 points of a 13-inch display,
    /// and never shorter than a usable minimum.
    static func theSheetTakesTheRoomItHas(_ suite: TestSuite) {
        var regions: [CGFloat: (region: CGFloat, sheet: CGFloat)] = [:]
        for height in [640, 1009] as [CGFloat] {
            let bench = PanelBench()
            guard let view = detail(bench, name: "HomeSpeaker", icon: "hifispeaker.2", settings: homeSpeakerSettings,
                                    setting: true),
                  let shown = sheet(view, parentHeight: height) else {
                suite.expect(false, "the HomeSpeaker sheet is shown on a window \(Int(height)) points high")
                return
            }
            let region = outermostScrollViews(in: shown.view).first.map { frame(of: $0, in: shown.view).height } ?? 0
            regions[height] = (region, shown.sheet.frame.height)
            picture(shown.view, "sheet-homespeaker-window-\(Int(height)).png")
            takeDown(shown.parent)
        }
        let small = regions[640], large = regions[1009]
        let words = regions.sorted { $0.key < $1.key }
            .map { "window \(Int($0.key)): region \(Int($0.value.region)), sheet \(Int($0.value.sheet))" }
            .joined(separator: "; ")
        suite.expect(small.map { $0.region >= ExtensionSettingsLayoutTests.smallest - 0.5 } == true,
                     "the region is never shorter than \(Int(smallest)) points: \(words)")
        suite.expect(small.flatMap { small in large.map { $0.region >= small.region + 100 } } == true,
                     "the region grows with the room the window has: \(words)")
        suite.expect(regions.values.allSatisfy { $0.sheet <= ExternalToolDetailHeightTests.room },
                     "the sheet stays under \(Int(ExternalToolDetailHeightTests.room)) points, a 13-inch display's "
                         + "room: \(words)")
        suite.expect(small.map { $0.sheet <= 640 } == true,
                     "on a window shorter than that, the sheet fits the window: \(words)")
    }

    /// The least height of the region.
    static let smallest: CGFloat = 250

    /// A Remote-shaped sheet, each of its links clicked in turn and drawn.
    static func theRemoteSheetLightsEachLink(_ suite: TestSuite) {
        let bench = PanelBench()
        guard let view = detail(bench, name: "Vitruvian Remote", icon: "iphone.radiowaves.left.and.right",
                                settings: remoteSettings, setting: false),
              let shown = sheet(view, parentHeight: 1009) else {
            suite.expect(false, "the Remote sheet is shown")
            return
        }
        defer { takeDown(shown.parent) }
        guard let field = searchField(in: shown.view) else {
            suite.expect(false, "the Remote sheet has its search field")
            return
        }
        let origin = frame(of: field, in: shown.view)
        let names = [english.vitruvianSection, "General", "Pairing & Bridge", "Notifications", "Integrations"]
        let frames = linkFrames(remoteLinks, current: nil)
        let region = outermostScrollViews(in: shown.view).first
        var offsets: [CGFloat] = []
        for (position, name) in names.enumerated() where frames.indices.contains(position) {
            let link = frames[position]
            // The row of links is 8 points under the search field.
            let point = CGPoint(x: origin.minX + link.midX, y: origin.maxY + 8 + link.midY)
            click(at: point, in: shown.view)
            settle(0.5)
            offsets.append(region?.documentVisibleRect.minY ?? -1)
            picture(shown.view, "sheet-remote-lit-\(position + 1)-\(name.replacingOccurrences(of: " & ", with: "-"))"
                        + ".png")
        }
        // The last sections may be too short to reach the region's top: the
        // region then stops at its end.
        suite.expect(offsets.count == names.count && zip(offsets, offsets.dropFirst()).allSatisfy { $0 <= $1 }
                         && (offsets.last ?? 0) > (offsets.first ?? 0),
                     "each link scrolls the region down to its section, as far as it goes: "
                         + offsets.map { "\(Int($0))" }.joined(separator: ", "))
    }

    /// A click at `point`, from the top left of `view`.
    static func click(at point: CGPoint, in view: NSView) {
        guard let window = view.window else { return }
        let inView = view.isFlipped ? point : CGPoint(x: point.x, y: view.bounds.height - point.y)
        let inWindow = view.convert(inView, to: nil)
        for kind in [NSEvent.EventType.leftMouseDown, .leftMouseUp] {
            if let event = NSEvent.mouseEvent(with: kind, location: inWindow, modifierFlags: [],
                                              timestamp: ProcessInfo.processInfo.systemUptime,
                                              windowNumber: window.windowNumber, context: nil, eventNumber: 0,
                                              clickCount: 1, pressure: 1) {
                window.sendEvent(event)
            }
        }
    }
}
