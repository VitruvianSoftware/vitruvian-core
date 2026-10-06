// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 VitruvianSoftware

import AppKit
import SwiftUI
import VitruvianCore
import VitruvianDesign
import VitruvianServices
import VitruvianUI

/// How two surfaces are drawn: a Clean URL field owns its whole row in a
/// grouped Form, and the panels' outlines answer raised contrast.
enum SettingsLayoutContract {
    static func run(_ suite: TestSuite) {
        // A grouped Form keeps a label column even for an empty label, which
        // left every field on the right half of its row. A field that keeps
        // that column is measured beside the page's own, so the measurement
        // is known to tell the two apart.
        let width: CGFloat = 480
        let owned = fieldWidth(AnyView(
            URLCleanerField(text: .constant(""), prompt: Text(verbatim: "example.com"),
                            accessibilityLabel: "Site") {}), width: width)
        let labelled = fieldWidth(AnyView(
            TextField("", text: .constant(""), prompt: Text(verbatim: "example.com"))
                .textFieldStyle(.roundedBorder)), width: width)
        if let owned, let labelled {
            suite.expect(owned > width * 0.6 && owned > labelled + 40,
                         "every Clean URL field hides its label so the field owns the row: "
                         + "\(Int(owned)) of \(Int(width)) points, \(Int(labelled)) beside an empty label")
        } else {
            suite.expect(false, "a grouped Form draws a Clean URL field and a labelled one "
                         + "(\(String(describing: owned)), \(String(describing: labelled)))")
        }

        // Raised contrast is asked for by someone who cannot see a hairline
        // at a tenth of an opacity: both outlines answer it, in either
        // appearance.
        for scheme in [ColorScheme.light, .dark] {
            let outline: Color = PanelSurface.border(for: scheme, increasedContrast: true)
            let raisedOutline: Color = PanelSurface.raisedBorder(for: scheme, increasedContrast: true)
            suite.expect(outline != PanelSurface.border(for: scheme, increasedContrast: false)
                         && raisedOutline != PanelSurface.raisedBorder(for: scheme, increasedContrast: false),
                         "both panel outlines answer raised contrast (\(scheme))")
        }
    }

    /// How wide the first editable text field in `row` is drawn, in a grouped
    /// Form `width` points wide, or nil when none was drawn.
    private static func fieldWidth(_ row: AnyView, width: CGFloat) -> CGFloat? {
        _ = NSApplication.shared
        let host = NSHostingView(rootView: Form { Section { row } }.formStyle(.grouped))
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: width, height: 240),
                              styleMask: [.borderless], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.contentView = host
        defer { window.close() }
        // The Form lays its rows out over a few passes; the width is read
        // once the field has been drawn and the layout has settled.
        var drawn: NSTextField?
        let deadline = Date().addingTimeInterval(3)
        repeat {
            host.layoutSubtreeIfNeeded()
            drawn = editableField(in: host)
            RunLoop.current.run(until: Date().addingTimeInterval(0.02))
        } while drawn == nil && Date() < deadline
        RunLoop.current.run(until: Date().addingTimeInterval(0.1))
        host.layoutSubtreeIfNeeded()
        guard let field = editableField(in: host) else { return nil }
        return field.convert(field.bounds, to: host).width
    }

    private static func editableField(in view: NSView) -> NSTextField? {
        if let field = view as? NSTextField, field.isEditable { return field }
        for subview in view.subviews {
            if let field = editableField(in: subview) { return field }
        }
        return nil
    }
}
