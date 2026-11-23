// Copyright 2026 VitruvianSoftware
// SPDX-License-Identifier: AGPL-3.0-or-later

import AppKit
import SwiftUI
import XCTest

@testable import VitruvianCourier

/// The Settings window can be resized (James, 2026-11-22): a SwiftUI `Settings` scene opens it without the resizable
/// style, so `SettingsWindowResizer` adds it once the view is in the window.
@MainActor
final class SettingsWindowResizeTests: XCTestCase {
    func testTheSettingsViewMakesItsWindowResizableDownToThePanesMinimum() {
        _ = NSApplication.shared
        let window = NSWindow(contentRect: NSRect(x: -10_000, y: -10_000, width: 980, height: 600),
                              styleMask: [.titled, .closable, .miniaturizable], backing: .buffered, defer: false)
        defer { window.orderOut(nil) }
        XCTAssertFalse(window.styleMask.contains(.resizable), "a Settings window starts out fixed")
        window.contentView = NSHostingView(rootView: Color.clear
            .frame(minWidth: SettingsWindowResizer.minimumSize.width, minHeight: SettingsWindowResizer.minimumSize.height)
            .background(SettingsWindowResizer()))
        window.contentView?.layoutSubtreeIfNeeded()
        RunLoop.main.run(until: Date().addingTimeInterval(0.05))

        XCTAssertTrue(window.styleMask.contains(.resizable))
        XCTAssertGreaterThanOrEqual(window.contentMinSize.width, SettingsWindowResizer.minimumSize.width, "never narrower than the panes need")
        XCTAssertGreaterThanOrEqual(window.contentMinSize.height, SettingsWindowResizer.minimumSize.height)
    }

    /// SwiftUI sets the Settings window up after the view arrives and takes the style away again; the second apply,
    /// on the next turn of the main queue, puts it back.
    func testTheResizableStyleIsPutBackAfterTheWindowIsSetUpAgain() {
        _ = NSApplication.shared
        let window = NSWindow(contentRect: NSRect(x: -10_000, y: -10_000, width: 980, height: 600),
                              styleMask: [.titled, .closable], backing: .buffered, defer: false)
        defer { window.orderOut(nil) }
        window.contentView = NSHostingView(rootView: Color.clear.background(SettingsWindowResizer()))
        window.contentView?.layoutSubtreeIfNeeded()
        // What the scene does after the view is in the window.
        window.styleMask.remove(.resizable)
        window.contentMaxSize = NSSize(width: 980, height: 600)
        RunLoop.main.run(until: Date().addingTimeInterval(0.05))

        XCTAssertTrue(window.styleMask.contains(.resizable))
        XCTAssertGreaterThan(window.contentMaxSize.width, 10_000, "no largest size")
    }
}
