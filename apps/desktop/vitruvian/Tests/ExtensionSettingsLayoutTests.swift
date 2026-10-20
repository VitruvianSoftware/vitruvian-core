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
        aLongChoiceTitleLeavesTheMenuRoom(suite)
        theIslandPaneKeepsItsPreviewInItsCard(suite)
        theSheetLinesUpItsSwitches(suite)
        theSheetTakesTheRoomItHas(suite)
        theSheetFollowsItsWindow(suite)
        theLogKeepsTheSheetInItsWindow(suite)
        theRemoteSheetLightsEachLink(suite)
        aRefusedPageSaysWhy(suite)
        theRefusedSentenceIsWhatIsDrawn(suite)
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
    static func manifest(name: String, icon: String, setting: Bool, version: String, description: String) -> Data {
        let preferences = setting
            ? #"[{"id": "chime", "title": {"en": "Chime before speaking"}, "type": "boolean", "default": true}]"#
            : "null"
        return ExternalToolManifestTests.file(#"""
            {"name": {"en": "\#(name)"}, "publisher": "VitruvianSoftware", "version": "\#(version)", "icon": "\#(icon)",
             "description": {"en": "\#(description)"},
             "protocol": "2", "uses": ["notify", "storage"],
             "contributes": {
               "commands": [{"id": "speak", "title": {"en": "Speak the clipboard"}, "surfaces": ["commandBar"]}],
               "panels": [{"id": "deploys", "title": {"en": "\#(name)"}, "placement": "island"},
                          {"id": "settings", "title": {"en": "\#(name)"}, "placement": "settings"}],
               "status": {"placement": "island"}},
             "preferences": \#(preferences)}
            """#)
    }

    /// The two extensions as their sheets name them.
    struct Extension {
        let name: String
        let icon: String
        let version: String
        let description: String
        let settings: String
        /// Whether its manifest declares a setting of its own.
        let setting: Bool

        var manifest: Data {
            ExtensionSettingsLayoutTests.manifest(name: name, icon: icon, setting: setting, version: version,
                                                  description: description)
        }
    }

    static let homeSpeaker = Extension(
        name: "HomeSpeaker", icon: "hifispeaker.2", version: "1.26.0",
        description: "Speaks what you type, or the clipboard, on your Google Home speakers, and keeps broadcasting, "
            + "quiet hours and the volume at hand.",
        settings: homeSpeakerSettings, setting: true)
    static let remote = Extension(
        name: "Vitruvian Remote", icon: "iphone.radiowaves.left.and.right", version: "0.1.8",
        description: "Pairs your Android phone with this Mac's Vitruvian Remote agent over Tailscale, manages push "
            + "notifications and Claude Code permission prompts, and exposes the phone's MCP bridge.",
        settings: remoteSettings, setting: false)

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
        /// Stays off screen, titled or not.
        override func constrainFrameRect(_ frameRect: NSRect, to screen: NSScreen?) -> NSRect { frameRect }
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

    /// A window as Settings is, with a title bar and a toolbar, `height`
    /// points high in all, off screen, drawing `root`.
    static func titledWindow(_ root: some View, height: CGFloat, dark: Bool = false) -> NSWindow {
        _ = NSApplication.shared
        let window = KeyWindow(contentRect: NSRect(x: -12_000, y: -12_000, width: 780, height: height),
                               styleMask: [.titled, .closable, .miniaturizable, .resizable], backing: .buffered,
                               defer: false)
        window.isReleasedWhenClosed = false
        window.appearance = NSAppearance(named: dark ? .darkAqua : .aqua)
        window.toolbar = NSToolbar(identifier: "layout-tests")
        window.toolbarStyle = .unified
        window.contentView = NSHostingView(rootView: root.frame(maxWidth: .infinity, maxHeight: .infinity))
        window.setFrame(NSRect(x: -12_000, y: -12_000, width: 780, height: height), display: false)
        window.orderFrontRegardless()
        window.makeKey()
        settle()
        return window
    }

    /// A sheet as shown: the window it hangs from, its own window and view,
    /// and its height at each turn of the run loop from when it first
    /// appeared.
    struct Shown {
        let parent: NSWindow
        let sheet: NSWindow
        let view: NSView
        let heights: [CGFloat]

        /// How tall the parent is inside, under its toolbar.
        var room: CGFloat { parent.contentLayoutRect.height }
    }

    /// `content` as a SwiftUI sheet on a window `parentHeight` points high
    /// with a toolbar, as the Extensions page shows it: the page reads its
    /// window's room and hands it to the sheet (`SheetRoomReader(own:)`).
    static func sheet(_ content: @escaping (CGFloat?) -> some View, parentHeight: CGFloat, dark: Bool = false)
        -> Shown? {
        let parent = titledWindow(SheetPresenter(content: content), height: parentHeight, dark: dark)
        let deadline = Date(timeIntervalSinceNow: 5)
        while parent.attachedSheet?.contentView == nil, Date() < deadline {
            RunLoop.main.run(mode: .default, before: Date(timeIntervalSinceNow: 0.002))
        }
        guard let sheet = parent.attachedSheet, let view = sheet.contentView else {
            takeDown(parent)
            return nil
        }
        sheet.appearance = parent.appearance
        var heights: [CGFloat] = []
        let watched = Date(timeIntervalSinceNow: 0.8)
        while Date() < watched {
            heights.append(sheet.frame.height)
            RunLoop.main.run(mode: .default, before: Date(timeIntervalSinceNow: 0.005))
        }
        view.layoutSubtreeIfNeeded()
        settle(0.1)
        heights.append(sheet.frame.height)
        return Shown(parent: parent, sheet: sheet, view: view, heights: heights)
    }

    /// The Extensions page's part: it reads its window's room, then shows
    /// the sheet with it, as `ExtensionsSettings` does.
    private struct SheetPresenter<Content: View>: View {
        let content: (CGFloat?) -> Content
        @State private var shown = false
        @State private var room: CGFloat?

        var body: some View {
            Color.clear
                .background(SheetRoomReader(own: true) { room = $0 })
                .sheet(isPresented: $shown) { content(room).background(Color(nsColor: .windowBackgroundColor)) }
                .onChange(of: room) { _, known in if known != nil { shown = true } }
        }
    }

    /// What was drawn, as the pixels of a picture of it.
    struct Picture {
        let rep: NSBitmapImageRep
        /// The drawing's size, in points.
        let points: CGSize

        private var scale: CGFloat { CGFloat(rep.pixelsWide) / max(points.width, 1) }

        /// How light the pixel at `point` (in points from the top left) is,
        /// 0 for black to 1 for white, as a greyscale display shows it.
        func luminance(at point: CGPoint) -> CGFloat {
            guard let data = rep.bitmapData else { return -1 }
            let x = min(rep.pixelsWide - 1, max(0, Int(point.x * scale)))
            let y = min(rep.pixelsHigh - 1, max(0, Int(point.y * scale)))
            let pixel = data + y * rep.bytesPerRow + x * (rep.bitsPerPixel / 8)
            return (0.2126 * CGFloat(pixel[0]) + 0.7152 * CGFloat(pixel[1]) + 0.0722 * CGFloat(pixel[2])) / 255
        }

        /// The bounds, in points, of the pixels in `rect` whose lightness is
        /// more than `by` from `background`'s: what is drawn there.
        func drawn(in rect: CGRect, background: CGFloat, by: CGFloat = 0.3) -> CGRect? {
            var found: CGRect?
            let step = 1 / scale
            var y = rect.minY
            while y < rect.maxY {
                var x = rect.minX
                while x < rect.maxX {
                    if abs(luminance(at: CGPoint(x: x, y: y)) - background) > by {
                        let dot = CGRect(x: x, y: y, width: step, height: step)
                        found = found.map { $0.union(dot) } ?? dot
                    }
                    x += step
                }
                y += step
            }
            return found
        }

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

    /// Lighting a link changes only how it is painted: every link keeps its
    /// place whichever is lit, so none jumps to another row as the sheet
    /// scrolls or a link is used.
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
        // That every link, lit or not, has a pill to see is checked on the
        // drawn sheet (`theRemoteSheetLightsEachLink`).
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
        // A row is its title, a gap of at least `choiceGap` and the menu;
        // the page starts 14 in.
        let titles = ["Announce", "Speaker", "Volume"]
        suite.expect(menus.count == titles.count, "the island page draws its three menus: \(menus.count)")
        for (title, menu) in zip(titles, menus) {
            let whole = ceil((title as NSString).size(withAttributes: [.font: font]).width)
            let room = menu.minX - 14 - BlockTreeContent.choiceGap
            suite.expect(room >= whole - 0.5,
                         "\(title)'s title is drawn whole at the island's width: \(Int(room)) points for its "
                             + "\(Int(whole)), the menu from \(Int(menu.minX)) to \(Int(menu.maxX))")
            suite.expect(menu.maxX <= islandWidth + 14 + 1 && menu.width >= 44,
                         "\(title)'s menu stays within the island, at the trailing edge, and keeps a usable width: "
                             + "\(Int(menu.minX))–\(Int(menu.maxX)) of \(Int(islandWidth + 14))")
        }
    }

    /// A choice whose title and option are both long, on a page in each
    /// place it is drawn: the island (at the preview's width and at the
    /// island's own), the menu bar panel and the Extensions sheet. The
    /// title takes at most `choiceTitleShare` of the row and wraps onto two
    /// lines; the menu keeps the rest, enough to show its value; nothing
    /// runs past the edge.
    static func aLongChoiceTitleLeavesTheMenuRoom(_ suite: TestSuite) {
        let long = #"""
            {"blocks": [{"type": "choice", "id": "announce", "title": "Announce messages from every chat as they arrive",
             "value": "direct", "options": [{"value": "every", "title": "Every message"},
                                             {"value": "direct", "title": "Direct messages and mentions only"}]}]}
            """#
        let places: [(name: String, size: BlockTreeContent.Size, width: CGFloat)] = [
            ("island-preview", .island, islandWidth), ("island", .island, 300), ("menu-panel", .standard, 280),
            ("sheet", .standard, ExternalToolDetailHeightTests.listsWidth),
        ]
        for place in places {
            guard let content = ToolPanelScreensTests.content(long, size: place.size) else {
                suite.expect(false, "the page reads")
                return
            }
            let island = place.size == .island
            let page = BlockTreeView(content: content, size: place.size, act: { _, _, _ in }, follow: { _ in })
                .padding(14)
                .background(island ? Color.black : Color(nsColor: .windowBackgroundColor))
                .environment(\.colorScheme, island ? .dark : .light)
            let (window, view) = offScreen(page, size: CGSize(width: place.width + 28, height: 90), dark: island)
            defer { takeDown(window) }
            guard let drawn = picture(view, "choice-long-title-\(place.name).png"),
                  let menu = menus(in: view).first.map({ frame(of: $0, in: view) }) else {
                suite.expect(false, "\(place.name): the page draws its menu")
                continue
            }
            let row = place.width - BlockTreeContent.choiceGap
            let background = drawn.luminance(at: CGPoint(x: 4, y: 4))
            // What is drawn of the title: left of the menu, less the gap.
            let title = drawn.drawn(in: CGRect(x: 14, y: 0, width: max(1, menu.minX - 14 - 4), height: 90),
                                    background: background)
            let line = island ? 12 * 1.2 : NSFont.preferredFont(forTextStyle: .callout).pointSize * 1.2
            suite.expect(menu.maxX <= place.width + 14 + 1 && (title?.maxX ?? .infinity) <= menu.minX,
                         "\(place.name): nothing runs past the edge or into the menu: title to "
                             + "\(title.map { "\(Int($0.maxX))" } ?? "none"), menu \(Int(menu.minX))–\(Int(menu.maxX)) "
                             + "of \(Int(place.width + 14))")
            suite.expect(menu.width >= row * (1 - BlockTreeContent.choiceTitleShare) - 1,
                         "\(place.name): the menu keeps room to show its value: \(Int(menu.width)) of a row of "
                             + "\(Int(row))")
            suite.expect((title?.height ?? 0) >= line * 1.5,
                         "\(place.name): the title is readable, wrapped onto two lines: drawn "
                             + "\(title.map { "\(Int($0.width))×\(Int($0.height))" } ?? "nothing"), a line is "
                             + "\(Int(line))")
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
            guard let described = ExternalToolManifestTests.tool(String(data: homeSpeaker.manifest,
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
                    // The card keeps 16 points clear above the island and 32
                    // below it, for its caption: a page drawn centred and cut
                    // at the card's edges fills those too.
                    let inside = previewHeight - 16 - 32
                    suite.expect(island.height <= inside + 1,
                                 "the preview's island is cut to its card, inside its margins: at most "
                                     + "\(Int(inside)) of the card's \(Int(previewHeight)) points, drawn "
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

    /// An extension's detail, its settings page shown by `bench`, for the
    /// room the page hands it.
    static func detail(_ bench: PanelBench, _ tool: Extension, log: String = "", logExpanded: Bool = false)
        -> ((CGFloat?) -> ExternalToolDetailView)? {
        let store = ExternalToolStoreTests.Bench()
        defer { store.close() }
        guard case .success = store.add(store.folder(manifest: tool.manifest)),
              let listed = store.store.listed.first else { return nil }
        bench.host.open(ToolPanelHostTests.key("settings"), in: .settings)
        answer(bench, ["settings": tool.settings])
        let detail = ExternalToolDetail(listed, files: store.store.folder(of: listed.id), language: .enUS,
                                        strings: english, settings: store.store.settings(of: listed.id),
                                        settingsTitle: "Settings", updateAvailable: false, showsInIsland: true,
                                        showsStatus: true)
        let host = bench.host!
        return { room in
            ExternalToolDetailView(
                detail: detail, log: log, removal: ToolRemovalContent(name: tool.name, strings: english, cancel: "Cancel"),
                text: english, startAgain: {}, saveSetting: { _, _ in true }, setShowsInIsland: { _ in },
                setShowsStatus: { _ in }, panel: { _, _ in }, openWindow: { _ in }, reveal: {}, openShortcuts: {},
                update: {}, updateNow: {}, remove: { _ in }, close: {}, logExpanded: logExpanded, room: room,
                host: host)
        }
    }

    /// The settings region's height in a shown sheet: its first scroll view.
    static func region(_ shown: Shown) -> CGFloat {
        outermostScrollViews(in: shown.view).first.map { frame(of: $0, in: shown.view).height } ?? 0
    }

    /// The tallest a sheet may be in `shown`'s window: a 13-inch display's
    /// 800 points, or the window's room less the sheet's margin.
    static func cap(_ shown: Shown) -> CGFloat {
        min(ExternalToolDetailHeightTests.room, shown.room - ToolAgreementContent.sheetMargin)
    }

    /// Vitruvian's own switches, the manifest's setting and the extension's
    /// switches all end at one trailing edge, as the extension's do among
    /// themselves.
    static func theSheetLinesUpItsSwitches(_ suite: TestSuite) {
        for dark in [false, true] {
            let bench = PanelBench()
            guard let view = detail(bench, homeSpeaker), let shown = sheet(view, parentHeight: 1009, dark: dark) else {
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
    /// and never shorter than a usable minimum; and the sheet opens at that
    /// height, not at a smaller one that grows a moment later.
    static func theSheetTakesTheRoomItHas(_ suite: TestSuite) {
        var regions: [CGFloat: (region: CGFloat, sheet: CGFloat, cap: CGFloat)] = [:]
        for height in [640, 1009] as [CGFloat] {
            let bench = PanelBench()
            guard let view = detail(bench, homeSpeaker), let shown = sheet(view, parentHeight: height) else {
                suite.expect(false, "the HomeSpeaker sheet is shown on a window \(Int(height)) points high")
                return
            }
            regions[height] = (region(shown), shown.sheet.frame.height, cap(shown))
            let first = shown.heights.first ?? 0, last = shown.heights.last ?? 0
            let spread = (shown.heights.max() ?? 0) - (shown.heights.min() ?? 0)
            suite.expect(abs(first - last) <= 4 && spread <= 4,
                         "window \(Int(height)): the sheet opens at its height: \(Int(first)) when first shown, "
                             + "\(Int(last)) settled, \(Int(spread)) between least and most over "
                             + "\(shown.heights.count) looks")
            picture(shown.view, "sheet-homespeaker-window-\(Int(height)).png")
            takeDown(shown.parent)
        }
        let small = regions[640], large = regions[1009]
        let words = regions.sorted { $0.key < $1.key }
            .map { "window \(Int($0.key)): region \(Int($0.value.region)), sheet \(Int($0.value.sheet)) "
                + "of \(Int($0.value.cap))" }
            .joined(separator: "; ")
        suite.expect(large.map { $0.region >= ExtensionSettingsLayoutTests.smallest - 0.5 } == true
                         && small.map { $0.region >= ToolAgreementContent.pageListsTightHeight - 0.5 } == true,
                     "the region is at least \(Int(smallest)) points in a window with room, and gives way down to "
                         + "\(Int(ToolAgreementContent.pageListsTightHeight)) at most in a short one: \(words)")
        suite.expect(small.flatMap { small in large.map { $0.region >= small.region + 100 } } == true,
                     "the region grows with the room the window has: \(words)")
        suite.expect(regions.values.allSatisfy { $0.sheet <= ExternalToolDetailHeightTests.room },
                     "the sheet stays under \(Int(ExternalToolDetailHeightTests.room)) points, a 13-inch display's "
                         + "room: \(words)")
        suite.expect(small.map { $0.sheet <= $0.cap + 1 } == true,
                     "on a window shorter than that, the sheet fits the window less its margin: \(words)")
    }

    /// The window resized while the sheet is open: the sheet follows it,
    /// its region shrinking and growing again, never past its cap.
    static func theSheetFollowsItsWindow(_ suite: TestSuite) {
        let bench = PanelBench()
        guard let view = detail(bench, homeSpeaker), let shown = sheet(view, parentHeight: 1009) else {
            suite.expect(false, "the HomeSpeaker sheet is shown")
            return
        }
        defer { takeDown(shown.parent) }
        var seen: [(window: CGFloat, region: CGFloat, sheet: CGFloat, cap: CGFloat)] = []
        for height in [1009, 700, 1009] as [CGFloat] {
            var frame = shown.parent.frame
            frame.size.height = height
            shown.parent.setFrame(frame, display: true)
            settle(0.6)
            shown.view.layoutSubtreeIfNeeded()
            seen.append((height, region(shown), shown.sheet.frame.height, cap(shown)))
            picture(shown.view, "sheet-homespeaker-resized-\(seen.count)-\(Int(height)).png")
        }
        let words = seen.map { "window \(Int($0.window)): region \(Int($0.region)), sheet \(Int($0.sheet)) of "
            + "\(Int($0.cap))" }.joined(separator: "; ")
        suite.expect(seen.count == 3 && seen[1].region <= seen[0].region - 100 && abs(seen[2].region - seen[0].region) <= 1,
                     "the region shrinks with the window and grows back: \(words)")
        suite.expect(seen.allSatisfy { $0.sheet <= $0.cap + 1 && $0.region >= smallest - 0.5 },
                     "the sheet follows the window, never past its cap, its region never under "
                         + "\(Int(smallest)): \(words)")
    }

    /// The log open, in a window with real room: the sheet stays within the
    /// window less its margin and under its cap, the region giving way. A
    /// log opened while the sheet is shown does the same.
    static func theLogKeepsTheSheetInItsWindow(_ suite: TestSuite) {
        let log = (1...200).map { "line \($0)" }.joined(separator: "\n")
        for height in [770, 1009] as [CGFloat] {
            for opensLater in [false, true] {
                let bench = PanelBench()
                guard let view = detail(bench, homeSpeaker, log: log, logExpanded: !opensLater),
                      let shown = sheet(view, parentHeight: height) else {
                    suite.expect(false, "the HomeSpeaker sheet with its log is shown")
                    return
                }
                let name = "window \(Int(height)), log opened \(opensLater ? "while shown" : "before")"
                if opensLater {
                    // The disclosure and the buttons are drawn by SwiftUI, not
                    // AppKit: the disclosure's arrow is clicked where it is,
                    // in the middle of the row 16 points over the sheet's row
                    // of buttons (about 24 high), at its 22-point margin.
                    let bottom = shown.view.bounds.height - 22 - 24 - 16
                    click(at: CGPoint(x: 22 + 3, y: bottom - 10), in: shown.view)
                    settle(0.8)
                    shown.view.layoutSubtreeIfNeeded()
                }
                let scrolls = outermostScrollViews(in: shown.view)
                let words = "sheet \(Int(shown.sheet.frame.height)) of \(Int(cap(shown))), region "
                    + "\(Int(region(shown))), \(scrolls.count) scrolling views"
                let tight = ToolAgreementContent.pageListsTightHeight
                suite.expect(scrolls.count == 2 && shown.sheet.frame.height <= cap(shown) + 1
                                 && region(shown) >= tight - 0.5,
                             "\(name): with the log open the sheet stays within the window and under its cap, the "
                                 + "region giving way down to \(Int(tight)) at least: \(words)")
                picture(shown.view, "sheet-homespeaker-log-\(Int(height))\(opensLater ? "-opened" : "").png")
                takeDown(shown.parent)
            }
        }
    }

    /// The least height of the region.
    static let smallest: CGFloat = 250

    /// A Remote-shaped sheet, each of its links clicked in turn and drawn.
    /// In each picture the lit link is outlined, so it stands out by more
    /// than its colour (seen as a greyscale display shows it), and every
    /// other link has a pill to see, so each row starts at a visible edge.
    static func theRemoteSheetLightsEachLink(_ suite: TestSuite) {
        for dark in [false, true] {
            let bench = PanelBench()
            guard let view = detail(bench, remote), let shown = sheet(view, parentHeight: 1009, dark: dark) else {
                suite.expect(false, "the Remote sheet is shown")
                return
            }
            defer { takeDown(shown.parent) }
            guard let field = searchField(in: shown.view) else {
                suite.expect(false, "the Remote sheet has its search field")
                return
            }
            let mode = dark ? "dark" : "light"
            let origin = frame(of: field, in: shown.view)
            let names = [english.vitruvianSection, "General", "Pairing & Bridge", "Notifications", "Integrations"]
            let frames = linkFrames(remoteLinks, current: nil).map {
                // The row of links is 8 points under the search field.
                $0.offsetBy(dx: origin.minX, dy: origin.maxY + 8)
            }
            let region = outermostScrollViews(in: shown.view).first
            var offsets: [CGFloat] = []
            for (position, name) in names.enumerated() where frames.indices.contains(position) {
                click(at: CGPoint(x: frames[position].midX, y: frames[position].midY), in: shown.view)
                settle(0.5)
                offsets.append(region?.documentVisibleRect.minY ?? -1)
                let file = name.replacingOccurrences(of: " & ", with: "-")
                guard let drawn = picture(shown.view, "sheet-remote-lit-\(position + 1)-\(file)"
                                              + (dark ? "-dark" : "") + ".png") else { continue }
                // Inside a pill, clear of its words (9 points of padding), and
                // its edge; and the sheet's margin, left of the row.
                func inside(_ link: CGRect) -> CGFloat { drawn.luminance(at: CGPoint(x: link.minX + 4.5, y: link.midY)) }
                func edge(_ link: CGRect) -> CGFloat { drawn.luminance(at: CGPoint(x: link.minX + 0.75, y: link.midY)) }
                let lit = frames[position]
                let outline = abs(edge(lit) - inside(lit))
                suite.expect(outline >= (dark ? 0.12 : 0.25),
                             "\(mode), \(name) lit: its outline is plain in greyscale, \(String(format: "%.2f", outline)) "
                                 + "from the pill inside it")
                let unlit = frames.indices.filter { $0 != position }.map { frames[$0] }
                let pills = unlit.map { abs(inside($0) - drawn.luminance(at: CGPoint(x: origin.minX - 6, y: $0.midY))) }
                suite.expect(pills.allSatisfy { $0 >= 0.02 },
                             "\(mode), \(name) lit: every other link has a pill to see, so each row starts at a "
                                 + "visible edge: " + pills.map { String(format: "%.3f", $0) }.joined(separator: ", "))
                let outlines = unlit.map { abs(edge($0) - inside($0)) }
                suite.expect(outlines.allSatisfy { $0 < outline / 2 },
                             "\(mode), \(name) lit: only the lit link is outlined: "
                                 + outlines.map { String(format: "%.2f", $0) }.joined(separator: ", "))
            }
            // The last sections may be too short to reach the region's top:
            // the region then stops at its end.
            suite.expect(offsets.count == names.count && zip(offsets, offsets.dropFirst()).allSatisfy { $0 <= $1 }
                             && (offsets.last ?? 0) > (offsets.first ?? 0),
                         "\(mode): each link scrolls the region down to its section, as far as it goes: "
                             + offsets.map { "\(Int($0))" }.joined(separator: ", "))
        }
    }

    // MARK: A refused page

    /// The pixels of `content` drawn at the island's size in the island's
    /// black, kept as `name`.
    static func islandPixels(_ content: some View, _ name: String) -> Data? {
        let (window, view) = offScreen(content.frame(width: 420, height: 120, alignment: .top)
                                           .background(.black).environment(\.colorScheme, .dark),
                                       size: CGSize(width: 420, height: 120))
        defer { takeDown(window) }
        guard let drawn = picture(view, name), let bytes = drawn.rep.bitmapData else { return nil }
        return Data(bytes: bytes, count: drawn.rep.bytesPerRow * drawn.rep.pixelsHigh)
    }

    /// What a refused panel draws is the sentence that names the tool and
    /// the reason, in the app's language: the panel is drawn, and so is the
    /// one sentence it should say, and the pixels are the same. The
    /// sentence that points to the log, and the same sentence naming the
    /// tool by its id, are drawn too, and differ.
    static func theRefusedSentenceIsWhatIsDrawn(_ suite: TestSuite) {
        let original = L10n.shared.language
        defer { L10n.shared.language = original }
        let problem = ToolPanelProblem.notWellFormed("blocks[76].id")
        for language in [AppLanguage.enUS, .de] {
            L10n.shared.language = language
            let strings = FeatureStrings.externalTools(language)
            let bench = PanelBench(name: "HomeSpeaker")
            bench.host.open(ToolPanelHostTests.key("deploys"), in: .island)
            answer(bench, ["deploys": refusedSettings])
            let tag = language.rawValue
            let panel = islandPixels(ToolPanelView(key: ToolPanelHostTests.key("deploys"), size: .island, host: bench.host),
                                     "refused-sentence-\(tag)-panel.png")
            let said = strings.panelRefused("HomeSpeaker", problem)
            let meant = islandPixels(ToolPanelNotShown(size: .island, why: said), "refused-sentence-\(tag)-meant.png")
            let log = islandPixels(ToolPanelNotShown(size: .island), "refused-sentence-\(tag)-log.png")
            let byID = islandPixels(ToolPanelNotShown(size: .island, why: strings.panelRefused("com.acme.deploys", problem)),
                                    "refused-sentence-\(tag)-id.png")
            suite.expect(panel != nil && panel == meant && panel != log && panel != byID,
                         "\(tag): the refused panel draws \"\(said)\", not the log's sentence nor the tool's id")
        }
    }

    /// A settings page shaped as HomeSpeaker's was in 3.64.0, which the app
    /// refused: its 77th block, a button, has no id.
    static let refusedSettings = #"{"blocks": ["#
        + Array(repeating: #"{"type": "text", "text": "Speaks on your Google Home speakers.", "style": "caption"}"#,
                count: 76).joined(separator: ", ")
        + #", {"type": "button", "title": "Sign Out"}]}"#

    /// An island page over the 256 KB a page may weigh.
    static let tooLargeIsland = #"{"blocks": [{"type": "text", "text": ""#
        + String(repeating: "x", count: UILimits.maxTreeBytes) + #""}]}"#

    /// The island's page as the open island draws it: the black island with
    /// its title, and the page under it at the island's size.
    private struct RefusedIsland: View {
        let host: ToolPanelHost

        var body: some View {
            VStack(alignment: .leading, spacing: NotchLayout.spacing) {
                Text(verbatim: "HomeSpeaker")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(height: NotchLayout.headerHeight)
                ToolPanelView(key: ToolPanelHostTests.key("deploys"), size: .island, host: host)
                    .frame(maxWidth: .infinity, alignment: .topLeading)
            }
            .padding(.horizontal, NotchLayout.horizontalInset)
            .padding(.bottom, NotchLayout.bottomInset)
            .frame(width: 480, height: 300, alignment: .top)
            .background(.black, in: UnevenRoundedRectangle(bottomLeadingRadius: 28, bottomTrailingRadius: 28))
            .environment(\.colorScheme, .dark)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        }
    }

    /// A page the app refuses, before any page of the panel is drawn: in
    /// the Extensions sheet and on the island the panel says why, in place
    /// of a spinner that never ends. Each is kept as a picture.
    static func aRefusedPageSaysWhy(_ suite: TestSuite) {
        for dark in [false, true] {
            let name = dark ? "dark" : "light"
            let bench = PanelBench(name: "HomeSpeaker")
            let refused = Extension(name: homeSpeaker.name, icon: homeSpeaker.icon, version: homeSpeaker.version,
                                    description: homeSpeaker.description, settings: refusedSettings, setting: true)
            guard let view = detail(bench, refused), let shown = sheet(view, parentHeight: 1009, dark: dark) else {
                suite.expect(false, "\(name): the HomeSpeaker sheet is shown")
                return
            }
            picture(shown.view, "refused-page-sheet-\(name).png")
            let held = bench.host.shown[ToolPanelHostTests.key("settings")]
            suite.expect(held == .notShown(.notWellFormed("blocks[76].id"))
                             && views(in: shown.view, of: NSProgressIndicator.self).isEmpty,
                         "\(name): the sheet's settings page is not shown, saying where it was refused, and nothing "
                             + "spins: \(String(describing: held))")
            takeDown(shown.parent)
        }
        for (page, problem) in [("malformed", refusedSettings), ("too-large", tooLargeIsland)] {
            for dark in [false, true] {
                let name = dark ? "dark" : "light"
                let bench = PanelBench(name: "HomeSpeaker")
                bench.host.open(ToolPanelHostTests.key("deploys"), in: .island)
                let (window, view) = offScreen(RefusedIsland(host: bench.host), size: CGSize(width: 520, height: 320),
                                               dark: dark)
                // The spinner is there while the page is coming, so its
                // absence later is the panel's doing.
                let spun = !views(in: view, of: NSProgressIndicator.self).isEmpty
                answer(bench, ["deploys": problem])
                settle(0.2)
                guard let drawn = picture(view, "refused-page-island-\(page)-\(name).png") else {
                    suite.expect(false, "\(name): the island can be drawn")
                    takeDown(window)
                    return
                }
                // The island's page, under its title: a sentence drawn
                // across it, not a spinner's few points.
                let words = drawn.drawn(in: CGRect(x: 40, y: 50, width: 440, height: 200), background: 0)
                suite.expect(spun && views(in: view, of: NSProgressIndicator.self).isEmpty
                                 && (words?.width ?? 0) > 300 && (words?.height ?? 0) > 20,
                             "\(name): the island says why HomeSpeaker's \(page) page was refused, across the page, "
                                 + "and stops spinning: spun first \(spun), words \(words.map { "\($0)" } ?? "none")")
                if case .notShown(let refused?)? = bench.host.shown[ToolPanelHostTests.key("deploys")] {
                    print("ExtensionSettingsLayoutTests: the island says "
                              + english.panelRefused("HomeSpeaker", refused))
                }
                takeDown(window)
            }
        }
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
