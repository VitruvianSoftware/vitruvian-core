// Copyright 2026 VitruvianSoftware
// SPDX-License-Identifier: AGPL-3.0-or-later

import AppKit
import SwiftUI
import XCTest

/// Draws a view to a PNG, light or dark, through AppKit (an NSHostingView in a window that is never shown), so that
/// controls AppKit draws (pickers, toggles, text fields, the composer's text view) come out as they do in the app,
/// which ImageRenderer can't do. The PNGs go to the test's undeclared outputs, for a person to look at.
@MainActor
enum Snapshot {
    /// Where the PNGs go: Bazel's undeclared outputs for this test, or (outside Bazel) a folder under the temporary
    /// directory.
    static var directory: URL {
        let environment = ProcessInfo.processInfo.environment
        let base = environment["TEST_UNDECLARED_OUTPUTS_DIR"].map { URL(fileURLWithPath: $0) }
            ?? FileManager.default.temporaryDirectory.appendingPathComponent("CourierViewTests")
        try? FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
        return base
    }

    /// Renders `view` at `width` (its height is what it needs, unless `height` is given) as `name`-light.png and
    /// `name`-dark.png, and returns their sizes in pixels.
    @discardableResult
    static func render<V: View>(_ name: String, width: CGFloat, height: CGFloat? = nil,
                                prepare: (NSView) -> Void = { _ in },
                                @ViewBuilder _ view: () -> V) throws -> [NSSize] {
        _ = NSApplication.shared
        var sizes: [NSSize] = []
        for (suffix, appearance) in [("light", NSAppearance.Name.aqua), ("dark", .darkAqua)] {
            let content = view()
                .frame(width: width, height: height)
                .fixedSize(horizontal: false, vertical: height == nil)
                .background(Color(nsColor: .windowBackgroundColor))
            let host = NSHostingView(rootView: content)
            host.appearance = NSAppearance(named: appearance)
            let fitting = host.fittingSize
            let size = NSSize(width: width, height: height ?? max(fitting.height, 1))
            let window = NSWindow(contentRect: NSRect(origin: .zero, size: size), styleMask: [.borderless],
                                  backing: .buffered, defer: false)
            window.appearance = NSAppearance(named: appearance)
            window.contentView = host
            host.frame = NSRect(origin: .zero, size: size)
            host.layoutSubtreeIfNeeded()
            // A second pass for AppKit controls that size themselves in the first, and for what `prepare` did (a
            // selection made in a text view). The run loop handles what is already waiting; nothing waits for time.
            window.displayIfNeeded()
            prepare(host)
            for _ in 0 ..< 3 {
                RunLoop.main.run(mode: .default, before: Date.distantPast)
                host.layoutSubtreeIfNeeded()
            }
            window.displayIfNeeded()
            guard let bitmap = host.bitmapImageRepForCachingDisplay(in: host.bounds) else {
                throw SnapshotError.noBitmap(name)
            }
            host.cacheDisplay(in: host.bounds, to: bitmap)
            guard let png = bitmap.representation(using: .png, properties: [:]) else { throw SnapshotError.noBitmap(name) }
            let url = directory.appendingPathComponent("\(name)-\(suffix).png")
            try png.write(to: url)
            sizes.append(NSSize(width: bitmap.pixelsWide, height: bitmap.pixelsHigh))
            window.contentView = nil
        }
        return sizes
    }
}

enum SnapshotError: Error {
    case noBitmap(String)
}

extension NSView {
    /// The first view of type `T` in this view's tree, depth first.
    func first<T: NSView>(_ type: T.Type) -> T? {
        if let found = self as? T { return found }
        for child in subviews {
            if let found = child.first(type) { return found }
        }
        return nil
    }
}
