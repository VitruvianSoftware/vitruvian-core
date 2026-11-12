// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 VitruvianSoftware

import AppKit
import Combine
import SwiftUI
import VitruvianCore
import VitruvianDesign
import VitruvianServices
import VitruvianToolProtocol

/// How a tool's window is sized and titled. Plain values, so the tests
/// check them without opening a window.
package struct ToolPanelWindowLook: Equatable, Sendable {
    /// A page of blocks: this wide, and as tall as its blocks between these
    /// two; past the taller its blocks scroll. It is not resized by hand.
    package static let blocksWidth: CGFloat = 380
    package static let blocksHeight: ClosedRange<CGFloat> = 120...560
    /// A web page: this size to start with, and no smaller; the person may
    /// resize it.
    package static let webSize = CGSize(width: 640, height: 480)
    package static let webSmallest = CGSize(width: 320, height: 240)

    /// The panel's title in the person's language, as the tool wrote it.
    package let title: String
    /// The tool's name, under the title.
    package let subtitle: String
    package let isWeb: Bool

    @MainActor package init?(key: ToolPanelHost.Key, store: ExternalToolStore, language: AppLanguage) {
        guard let tool = store.installed[key.tool]?.tool, let panel = tool.panel(key.panel),
              panel.placement == .window else { return nil }
        title = ToolOwnWords.oneLine(panel.title.text(for: language.rawValue) ?? key.panel)
        subtitle = ToolOwnWords.oneLine(tool.name.text(for: language.rawValue) ?? tool.manifest.tool.name)
        isWeb = panel.isWeb
    }
}

/// The windows of tools from outside: one for each window panel the host
/// has open, made when it opens and closed when it closes, when the tool
/// ends, or when the person closes it, which tells the tool.
@MainActor
package final class ToolPanelWindows: NSObject, NSWindowDelegate {
    package static let shared = ToolPanelWindows()

    private var windows: [ToolPanelHost.Key: NSPanel] = [:]
    private var watching: AnyCancellable?

    /// Starts following the host's open windows. Called once, at launch.
    package func start() {
        guard watching == nil else { return }
        watching = ToolPanelHost.shared.$windows.receive(on: DispatchQueue.main).sink { [weak self] keys in
            MainActor.assumeIsolated { self?.follow(keys) }
        }
    }

    private func follow(_ keys: [ToolPanelHost.Key]) {
        for (key, window) in windows where !keys.contains(key) {
            windows[key] = nil
            window.delegate = nil
            window.close()
        }
        for key in keys where windows[key] == nil {
            guard let look = ToolPanelWindowLook(key: key, store: .shared, language: L10n.shared.language) else { continue }
            let window = makeWindow(key, look)
            windows[key] = window
            window.center()
            window.makeKeyAndOrderFront(nil)
        }
    }

    private func makeWindow(_ key: ToolPanelHost.Key, _ look: ToolPanelWindowLook) -> NSPanel {
        // A full title bar: it carries the panel's title and, under it, the
        // tool's name.
        var style: NSWindow.StyleMask = [.titled, .closable]
        if look.isWeb { style.insert(.resizable) }
        let size = look.isWeb ? ToolPanelWindowLook.webSize
            : CGSize(width: ToolPanelWindowLook.blocksWidth, height: ToolPanelWindowLook.blocksHeight.lowerBound)
        let window = NSPanel(contentRect: NSRect(origin: .zero, size: size), styleMask: style, backing: .buffered,
                             defer: false)
        window.title = look.title
        window.subtitle = look.subtitle
        window.isReleasedWhenClosed = false
        window.hidesOnDeactivate = false
        window.delegate = self
        if look.isWeb {
            window.contentMinSize = ToolPanelWindowLook.webSmallest
            window.contentViewController = NSHostingController(rootView: ToolPanelView(key: key, size: .standard))
        } else {
            let hosting = NSHostingController(rootView: ToolPanelWindowContent(key: key))
            // The window follows the height its blocks ask for.
            hosting.sizingOptions = [.preferredContentSize]
            window.contentViewController = hosting
        }
        return window
    }

    /// The person closed a window: the panel closes, and its tool is told.
    package func windowWillClose(_ notification: Notification) {
        guard let window = notification.object as? NSPanel,
              let key = windows.first(where: { $0.value === window })?.key else { return }
        windows[key] = nil
        ToolPanelHost.shared.close(key)
    }
}

/// A window's page of blocks: as tall as it is, up to the most a window
/// shows; past that it scrolls.
private struct ToolPanelWindowContent: View {
    let key: ToolPanelHost.Key

    var body: some View {
        ViewThatFits(in: .vertical) {
            page
            ScrollView { page }
        }
        .frame(width: ToolPanelWindowLook.blocksWidth)
        .frame(minHeight: ToolPanelWindowLook.blocksHeight.lowerBound, maxHeight: ToolPanelWindowLook.blocksHeight.upperBound)
    }

    private var page: some View {
        ToolPanelView(key: key, size: .standard).padding(16)
    }
}
