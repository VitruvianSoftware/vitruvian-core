// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 VitruvianSoftware

import AppKit
import SwiftUI
import VitruvianCore
import VitruvianServices
import VitruvianToolProtocol
import VitruvianUI

/// Text typed in a tool's field reaches the tool before the click that
/// uses it. On macOS a click on a button leaves the field focused, so a
/// field that sent its text only when left never sent it: HomeSpeaker's
/// "Save Token" then saw no token and said "Paste the Beeper token first".
@MainActor
enum BlockFieldPendingTests {
    static func run(_ suite: TestSuite) {
        theQueue(suite)
        aDrawnPage(suite)
    }

    /// `PendingFields` on its own: what is held is sent once, in the order
    /// typed, before the click's own event.
    static func theQueue(_ suite: TestSuite) {
        var log: [String] = []
        let pending = PendingFields()
        let send = pending.flushing(into: { id, kind, _ in log.append("\(id) \(kind.rawValue)") })
        pending.hold("clientId") { log.append("clientId change 1") }
        pending.hold("secret") { log.append("secret change") }
        pending.hold("clientId") { log.append("clientId change 2") }
        suite.expect(!pending.isEmpty, "a field with unsent text is held")
        send("save", .tap, nil)
        suite.expect(log == ["clientId change 2", "secret change", "save tap"],
                     "a click sends each field's latest text first, in the order typed, then its own event: \(log)")
        log = []
        send("save", .tap, nil)
        suite.expect(log == ["save tap"] && pending.isEmpty, "text is sent once")
        log = []
        pending.hold("quiet") { log.append("quiet change") }
        pending.drop("quiet")
        send("toggle", .toggle, .bool(true))
        suite.expect(log == ["toggle toggle"], "a field that has sent its text is not sent again")
    }

    /// The real page: a secret field and a text field typed in, then the
    /// button clicked while the field still has the focus.
    static func aDrawnPage(_ suite: TestSuite) {
        _ = NSApplication.shared
        func settle() { RunLoop.current.run(until: Date().addingTimeInterval(0.05)) }
        guard let content = ToolPanelScreensTests.content(#"""
            {"blocks": [
              {"type": "field", "id": "token", "title": "Access token", "kind": "secret"},
              {"type": "field", "id": "clientId", "title": "Client ID", "value": ""},
              {"type": "button", "id": "save", "title": "Save Token"}
            ]}
            """#, size: .island) else {
            suite.expect(false, "the page reads")
            return
        }
        var log: [String] = []
        let view = NSHostingView(rootView: BlockTreeView(content: content, size: .island, act: { id, kind, value in
            if case .string(let text)? = value {
                log.append("\(id) \(kind.rawValue) \(text)")
            } else {
                log.append("\(id) \(kind.rawValue)")
            }
        }, follow: { _ in }))
        let window = NSWindow(contentRect: NSRect(x: -10000, y: -10000, width: 320, height: 300),
                              styleMask: [.titled], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.contentView = view
        window.orderFrontRegardless()
        defer {
            window.orderOut(nil)
            window.contentView = nil
            window.close()
        }
        view.layoutSubtreeIfNeeded()
        settle()

        let fields = views(in: view, of: NSTextField.self).filter(\.isEditable)
        let secret = fields.first { $0 is NSSecureTextField }
        let plain = fields.first { !($0 is NSSecureTextField) }
        guard let secret, let plain else {
            suite.expect(false, "the page draws a secret field and a text field (\(fields.count) fields)")
            return
        }

        type("sk-pasted", into: secret, window: window)
        settle()
        suite.expect(log == ["token change sk-pasted"],
                     "a secret field sends what is pasted at once, while it keeps the focus: \(log)")

        log = []
        type("client-123", into: plain, window: window)
        settle()
        suite.expect(log.isEmpty, "a text field holds what is typed while it keeps the focus: \(log)")
        // SwiftUI draws the button itself, not as an NSButton: it is
        // clicked where it is drawn, the page's last row, under the field.
        let below = plain.convert(plain.bounds, to: nil)
        click(at: NSPoint(x: below.minX + 12, y: below.minY - 14), in: window)
        settle()
        suite.expect(window.firstResponder === plain.currentEditor() || window.firstResponder === plain,
                     "clicking the button leaves the field focused, as on screen")
        suite.expect(log == ["clientId change client-123", "save tap"],
                     "clicking a button with the field still focused sends the field's text first: \(log)")
    }

    /// Types `text` into `field` as the person does: focused, its editor's
    /// text replaced, and its delegate told.
    private static func type(_ text: String, into field: NSTextField, window: NSWindow) {
        window.makeFirstResponder(field)
        if let editor = field.currentEditor() {
            editor.string = text
        }
        field.stringValue = text
        NotificationCenter.default.post(name: NSControl.textDidChangeNotification, object: field)
        field.delegate?.controlTextDidChange?(Notification(name: NSControl.textDidChangeNotification, object: field))
    }

    /// A click of the mouse at `point`, in the window's coordinates.
    private static func click(at point: NSPoint, in window: NSWindow) {
        for type in [NSEvent.EventType.leftMouseDown, .leftMouseUp] {
            guard let event = NSEvent.mouseEvent(with: type, location: point, modifierFlags: [], timestamp: 0,
                                                 windowNumber: window.windowNumber, context: nil, eventNumber: 0,
                                                 clickCount: 1, pressure: type == .leftMouseDown ? 1 : 0) else { continue }
            window.sendEvent(event)
        }
    }

    private static func views<V: NSView>(in view: NSView, of type: V.Type) -> [V] {
        view.subviews.flatMap { subview -> [V] in
            if let match = subview as? V { return [match] }
            return views(in: subview, of: type)
        }.sorted { $0.convert($0.bounds, to: nil).maxY > $1.convert($1.bounds, to: nil).maxY }
    }
}
