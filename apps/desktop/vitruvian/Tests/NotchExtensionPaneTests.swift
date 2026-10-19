// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 VitruvianSoftware

import AppKit
import Foundation
import SwiftUI
import VitruvianCore
import VitruvianServices
import VitruvianToolProtocol
import VitruvianUI

/// The Dynamic Island page's pane for an extension, drawn in a window of its
/// own: its live preview and its settings card each ask for their page once
/// as they appear, keep it while what they draw changes, and let go when
/// they go; and the preview is only a picture, which a click never reaches.
enum NotchExtensionPaneTests {
    static func run(_ suite: TestSuite) {
        thePreviewKeepsItsPageWhileItIsDrawn(suite)
        theSettingsCardKeepsItsPageWhileItIsDrawn(suite)
        aClickOnThePreviewNeverReachesTheTool(suite)
    }

    typealias Bench = ToolPanelHostTests.Bench

    static func key(_ panel: String) -> ToolPanelHost.Key { ToolPanelHostTests.key(panel) }

    /// Whether the view is in the window.
    private final class State: ObservableObject {
        @Published var present = true
    }

    private struct Frame<Content: View>: View {
        @ObservedObject var state: State
        let content: () -> Content

        var body: some View {
            VStack {
                if state.present { content() }
            }
            .frame(width: Pane.width, height: Pane.height, alignment: .top)
        }
    }

    private enum Pane {
        static let width: CGFloat = 440
        static let height: CGFloat = 420
    }

    static func settle() { RunLoop.current.run(until: Date().addingTimeInterval(0.05)) }

    /// Draws `content` in a window off screen, hands `check` the view's
    /// state, the window and the hosting view, then takes it all down.
    private static func drawn<Content: View>(_ content: @escaping () -> Content,
                                             _ check: (State, NSWindow, NSView) -> Void) {
        _ = NSApplication.shared
        let state = State()
        let view = NSHostingView(rootView: Frame(state: state, content: content))
        let window = NSWindow(contentRect: NSRect(x: -10000, y: -10000, width: Pane.width, height: Pane.height),
                              styleMask: [.borderless], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.contentView = view
        window.orderFrontRegardless()
        defer {
            state.present = false
            settle()
            window.orderOut(nil)
            window.contentView = nil
            window.close()
        }
        view.layoutSubtreeIfNeeded()
        settle()
        check(state, window, view)
    }

    /// How many times the tool was sent a tap, a change or any other event
    /// of a page.
    static func events(_ bench: Bench) -> Int {
        bench.runs.flatMap(\.sent).filter {
            if case .request(_, "ui/event", _) = $0 { return true }
            return false
        }.count
    }

    static func thePreviewKeepsItsPageWhileItIsDrawn(_ suite: TestSuite) {
        let bench = Bench()
        drawn({ NotchExtensionPreview(title: "Deploys", symbol: "bolt", hidden: false, page: key("deploys"),
                                      host: bench.host) }) { state, _, _ in
            suite.expect(bench.host.shown[key("deploys")] == .waiting && bench.host.viewers[key("deploys")]?.count == 1,
                         "a drawn preview asks for its island page as it appears")
            guard !bench.runs.isEmpty else { return }
            ToolPanelHostTests.answered(bench)
            settle()
            settle()
            suite.expect(ToolPanelHostTests.text(bench.host.shown[key("deploys")]) == "first"
                             && ToolPanelHostTests.opens(bench) == 1 && ToolPanelHostTests.closes(bench) == 0
                             && bench.host.viewers[key("deploys")]?.count == 1,
                         "once the page comes and takes the tile's place, the preview keeps it: the tool is asked "
                             + "once and never told it closed (asked \(ToolPanelHostTests.opens(bench)), "
                             + "closed \(ToolPanelHostTests.closes(bench)))")
            bench.clock.advance(by: 1)
            bench.render("deploys", "second")
            settle()
            suite.expect(ToolPanelHostTests.text(bench.host.shown[key("deploys")]) == "second"
                             && ToolPanelHostTests.opens(bench) == 1 && ToolPanelHostTests.closes(bench) == 0,
                         "a newer page is drawn in the preview, and nothing is asked again or closed")
            state.present = false
            settle()
            suite.expect(bench.host.shown[key("deploys")] == nil && bench.host.viewers.isEmpty
                             && ToolPanelHostTests.closes(bench) == 1,
                         "the preview going lets go of the page, and the tool is told once")
        }
    }

    static func theSettingsCardKeepsItsPageWhileItIsDrawn(_ suite: TestSuite) {
        let bench = Bench()
        drawn({ NotchExtensionSettings(key: key("settings"), host: bench.host) }) { state, _, _ in
            suite.expect(bench.host.shown[key("settings")] == .waiting && bench.host.viewers[key("settings")]?.count == 1,
                         "a drawn settings card asks for the extension's settings page as it appears")
            guard !bench.runs.isEmpty else { return }
            ToolPanelHostTests.answered(bench)
            settle()
            settle()
            suite.expect(ToolPanelHostTests.text(bench.host.shown[key("settings")]) == "first"
                             && ToolPanelHostTests.opens(bench, "settings") == 1
                             && ToolPanelHostTests.closes(bench, "settings") == 0
                             && bench.host.viewers[key("settings")]?.count == 1,
                         "once the page comes and takes the spinner's place, the card keeps it: the tool is asked "
                             + "once and never told it closed (asked \(ToolPanelHostTests.opens(bench, "settings")), "
                             + "closed \(ToolPanelHostTests.closes(bench, "settings")))")
            state.present = false
            settle()
            suite.expect(bench.host.shown[key("settings")] == nil && bench.host.viewers.isEmpty
                             && ToolPanelHostTests.closes(bench, "settings") == 1,
                         "the card going lets go of the page, and the tool is told once")
        }
    }

    /// A page of buttons that fill the island's width, as a speaker
    /// extension's island page has its Speak button.
    static let buttons = #"{"tree":{"blocks":["# + (0..<8).map { #"{"type":"button","id":"b\#($0)","title":"Speak now, on every speaker in the house"}"# }
        .joined(separator: ",") + "]}}"

    /// Clicks every 20 points over the whole window.
    private static func clickEverywhere(in window: NSWindow) {
        for x in stride(from: CGFloat(10), to: Pane.width, by: 20) {
            for y in stride(from: CGFloat(10), to: Pane.height, by: 20) {
                for type in [NSEvent.EventType.leftMouseDown, .leftMouseUp] {
                    guard let event = NSEvent.mouseEvent(with: type, location: NSPoint(x: x, y: y), modifierFlags: [],
                                                         timestamp: 0, windowNumber: window.windowNumber, context: nil,
                                                         eventNumber: 0, clickCount: 1,
                                                         pressure: type == .leftMouseDown ? 1 : 0) else { continue }
                    window.sendEvent(event)
                }
            }
        }
        settle()
    }

    static func aClickOnThePreviewNeverReachesTheTool(_ suite: TestSuite) {
        // The same page drawn as the island draws it, so the clicks are
        // known to land on its buttons.
        let plain = Bench()
        plain.host.open(key("deploys"), in: .island)
        plain.current.greets()
        if let asked = plain.current.lastRequest { plain.current.answers(asked, buttons) }
        drawn({ ToolPanelView(key: key("deploys"), size: .island, host: plain.host) }) { _, window, _ in
            clickEverywhere(in: window)
        }
        suite.expect(events(plain) > 0, "a click on the page as the island draws it reaches the tool (\(events(plain)))")

        let bench = Bench()
        drawn({ NotchExtensionPreview(title: "Deploys", symbol: "bolt", hidden: false, page: key("deploys"),
                                      host: bench.host) }) { _, window, _ in
            guard !bench.runs.isEmpty else { return suite.expect(false, "the drawn preview asks for its page") }
            bench.current.greets()
            if let asked = bench.current.lastRequest { bench.current.answers(asked, buttons) }
            settle()
            clickEverywhere(in: window)
            suite.expect(bench.host.shown[key("deploys")] != nil && events(bench) == 0,
                         "a click anywhere on the live preview never reaches the tool: it is only a picture "
                             + "(\(events(bench)) events sent)")
        }
    }
}
