// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 VitruvianSoftware

import AppKit
import SwiftUI
import VitruvianCore
import VitruvianServices
import VitruvianUI

/// A tool's page drawn as the island draws it, read back from the AppKit
/// controls SwiftUI draws: each switch sits at the trailing edge, where a
/// menu does, however long its title, so a page's switches and menus line
/// up in one column; and each switch is still named by its title. Chips
/// wrap onto more rows rather than run past the island's width.
enum BlockTreeLayoutTests {
    static func run(_ suite: TestSuite) {
        switchesLineUp(suite)
        chipsWrapWithinTheIslandWidth(suite)
    }

    static func switchesLineUp(_ suite: TestSuite) {
        let long = "Read every announcement aloud on the home speakers, even the quiet ones"
        guard let content = ToolPanelScreensTests.content(#"""
            {"blocks": [
              {"type": "toggle", "id": "broadcast", "title": "Broadcasting", "value": true},
              {"type": "toggle", "id": "quiet", "title": "Quiet hours", "value": false},
              {"type": "toggle", "id": "long", "title": "\#(long)", "value": true, "enabled": false},
              {"type": "choice", "id": "room", "title": "Home speakers", "value": "all",
               "options": [{"value": "all", "title": "All"}, {"value": "kitchen", "title": "Kitchen"}]}
            ]}
            """#, size: .island) else {
            suite.expect(false, "the page reads")
            return
        }
        for (size, width) in [(BlockTreeContent.Size.island, CGFloat(300)), (.standard, 420)] {
            let host = NSHostingView(rootView: BlockTreeView(content: content, size: size,
                                                              act: { _, _, _ in }, follow: { _ in }))
            host.frame = NSRect(x: 0, y: 0, width: width, height: 600)
            host.layoutSubtreeIfNeeded()
            let switches = views(in: host, of: NSSwitch.self)
            let menus = menus(in: host)
            let edges = switches.map { alignmentFrame(of: $0, in: host) }
            let menuEdge = menus.first.map { alignmentFrame(of: $0, in: host).maxX }
            let name = size == .island ? "island" : "standard"
            suite.expect(switches.count == 3 && menus.count == 1, "\(name): a page draws its three switches and its menu")
            suite.expect(!edges.isEmpty && edges.allSatisfy { abs($0.minX - edges[0].minX) <= 0.5 },
                         "\(name): every switch starts at the same place, whatever its title: "
                             + edges.map { "\(Int($0.minX))" }.joined(separator: ", "))
            suite.expect(menuEdge.map { edge in edges.allSatisfy { abs($0.maxX - edge) <= 1 } } == true
                             && menuEdge.map { abs($0 - width) <= 1 } == true,
                         "\(name): every switch ends at the trailing edge, where the menu does: switches at "
                             + edges.map { "\(Int($0.maxX))" }.joined(separator: ", ")
                             + ", menu at \(menuEdge.map { "\(Int($0))" } ?? "none") of \(Int(width))")
            // Each switch's name (its title, via `controlNamed`) is not checked
            // here: SwiftUI vends no accessibility children to the test
            // process, only the hosting view itself.
            suite.expect(switches.map(\.isEnabled) == [true, true, false],
                         "\(name): a switch that is not enabled cannot be switched")
        }
    }

    /// Twelve chips, one with a title longer than the island is wide, drawn
    /// at the island's width and at a width that holds them all in a row.
    /// SwiftUI draws a chip as no AppKit view, so the drawn page's size is
    /// read back, and the rows the chips make are checked where they are
    /// laid out.
    static func chipsWrapWithinTheIslandWidth(_ suite: TestSuite) {
        let island: CGFloat = 300
        let long = "A network whose name runs far past the width of the island, and on"
        let names = ["WhatsApp", "Signal", "Telegram", "Messenger", "Instagram", "Discord", "Slack", "Google Chat",
                     "LinkedIn", "X", "Messages", long]
        let options = names.enumerated().map { index, name in
            #"{"value": "n\#(index)", "title": "\#(name)", "on": \#(index % 3 == 0)}"#
        }
        func drawn(_ chips: [String], width: CGFloat, size: BlockTreeContent.Size) -> CGSize {
            guard let content = ToolPanelScreensTests.content(
                #"{"blocks": [{"type": "chips", "id": "muted", "options": [\#(chips.joined(separator: ", "))]}]}"#,
                size: size) else { return .zero }
            let host = NSHostingController(rootView: BlockTreeView(content: content, size: size,
                                                                   act: { _, _, _ in }, follow: { _ in }))
            return host.sizeThatFits(in: CGSize(width: width, height: 10_000))
        }
        for size in [BlockTreeContent.Size.island, .standard] {
            let name = size == .island ? "island" : "standard"
            let one = drawn(Array(options.prefix(1)), width: island, size: size)
            let many = drawn(options, width: island, size: size)
            let roomy = drawn(Array(options.dropLast()), width: 4_000, size: size)
            let lone = drawn([options.last ?? ""], width: island, size: size)
            suite.expect(one.height > 0 && abs(roomy.height - one.height) <= 0.5,
                         "\(name): with room, chips take one row: \(roomy) against one chip's \(one)")
            suite.expect(many.width <= island && many.height >= one.height * 2.5,
                         "\(name): at the island's width twelve chips wrap onto more rows and none runs past it: "
                             + "\(many), one row \(one)")
            suite.expect(lone.width <= island && abs(lone.height - one.height) <= 0.5,
                         "\(name): a chip whose title is wider than the island is cut to one line within it: \(lone)")
        }
        let sizes = [CGSize(width: 80, height: 22), CGSize(width: 500, height: 22), CGSize(width: 120, height: 22),
                     CGSize(width: 150, height: 22), CGSize(width: 40, height: 22)]
        let frames = BlockTreeContent.chipFrames(sizes, width: island, spacing: 6)
        suite.expect(frames.count == sizes.count && frames.allSatisfy { $0.minX >= 0 && $0.maxX <= island }
                         && frames.map(\.minY) == [0, 28, 56, 56, 84] && frames[1].width == island,
                     "chips are laid out in rows, each starting where the last ends, none past the width, a chip "
                         + "wider than the width cut to it: \(frames)")
    }

    /// The page's menus: pop-up buttons, or the focus ring macOS 26 and
    /// later leaves at a menu drawn by SwiftUI (as NotchSettingsChoiceTests
    /// finds them).
    private static func menus(in view: NSView) -> [NSView] {
        view.subviews.flatMap { subview -> [NSView] in
            if subview is NSPopUpButton || String(describing: type(of: subview)).contains("FocusRing") { return [subview] }
            return menus(in: subview)
        }
    }

    private static func views<V: NSView>(in view: NSView, of type: V.Type) -> [V] {
        view.subviews.flatMap { subview -> [V] in
            if let match = subview as? V { return [match] }
            return views(in: subview, of: type)
        }.sorted { $0.convert($0.bounds, to: nil).maxY > $1.convert($1.bounds, to: nil).maxY }
    }

    /// A control's frame in the host without the bezel some versions draw
    /// past the rect SwiftUI lines up.
    private static func alignmentFrame(of control: NSView, in host: NSView) -> CGRect {
        guard let superview = control.superview else { return .zero }
        return superview.convert(control.alignmentRect(forFrame: control.frame), to: host)
    }
}
