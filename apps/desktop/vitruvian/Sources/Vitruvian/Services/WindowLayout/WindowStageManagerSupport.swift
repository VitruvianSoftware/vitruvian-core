// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import AppKit
import CoreGraphics
import VitruvianCore

/// Shared by the green button and Window Layout. Window-server bounds are in
/// points and need no screen capture; no window titles or images are read.
package enum WindowStageManagerSupport {
    // UserDefaults is thread-safe, though the SDK does not mark it Sendable.
    nonisolated(unsafe) private static let windowManagerDefaults = UserDefaults(suiteName: "com.apple.WindowManager")
    nonisolated(unsafe) private static let dockDefaults = UserDefaults(suiteName: "com.apple.dock")
    /// The last window-server read, shared by every caller behind the lock.
    private static let sampleLock = NSLock()
    nonisolated(unsafe) private static var sampledAt: TimeInterval = -.infinity
    nonisolated(unsafe) private static var sampledFrames: [CGRect] = []

    package static func visibleFrame(for screen: NSScreen) -> CGRect {
        adjustedFrame(
            visibleFrame: screen.visibleFrame,
            screenFrame: screen.frame,
            enabled: UserDefaults.standard[Preferences.windowReserveStageManagerSpace],
            stageManagerEnabled: windowManagerDefaults?.bool(forKey: "GloballyEnabled") == true,
            autoHide: windowManagerDefaults?.object(forKey: "AutoHide") as? Bool,
            dockPosition: dockDefaults?.string(forKey: "orientation"),
            rightToLeft: Locale.current.language.characterDirection == .rightToLeft,
            stripFrames: currentStripFrames())
    }

    /// `stripFrames` is lazy: the default/off paths never query the window server.
    /// Keep the existing menu-bar and Dock exclusions and remove only the strip's
    /// side. A hidden/temporarily unavailable strip gets a 75pt fallback, allowing
    /// a window which already covers it to move out of the way on the first use.
    package static func adjustedFrame(visibleFrame: CGRect,
                              screenFrame: CGRect,
                              enabled: Bool,
                              stageManagerEnabled: Bool,
                              autoHide: Bool?,
                              dockPosition: String?,
                              rightToLeft: Bool = false,
                              stripFrames: @autoclosure () -> [CGRect]) -> CGRect {
        guard enabled, stageManagerEnabled, autoHide == false,
              visibleFrame.width > 80, visibleFrame.height > 0 else { return visibleFrame }
        let onRight = dockPosition == "left" || (dockPosition != "right" && rightToLeft)
        let candidates = stripFrames().filter { frame in
            guard !frame.isNull, !frame.isInfinite,
                  frame.width >= 16, frame.height >= 32,
                  frame.width <= screenFrame.width / 4,
                  frame.minY >= screenFrame.minY, frame.maxY <= screenFrame.maxY else { return false }
            // WindowManager also owns desktop overlays and a dragged-window
            // proxy. Only narrow, on-screen artwork beside the expected edge
            // can describe this display's recent-apps strip.
            let distance = onRight ? screenFrame.maxX - frame.maxX : frame.minX - screenFrame.minX
            return distance >= -1 && distance <= 24
        }
        let boundary: CGFloat
        if onRight {
            boundary = candidates.map(\.minX).min().map { $0 - 8 } ?? (screenFrame.maxX - 75)
        } else {
            boundary = candidates.map(\.maxX).max().map { $0 + 8 } ?? (screenFrame.minX + 75)
        }
        let inset = min(max(0, onRight ? visibleFrame.maxX - boundary : boundary - visibleFrame.minX),
                        visibleFrame.width - 80)
        return CGRect(x: visibleFrame.minX + (onRight ? 0 : inset), y: visibleFrame.minY,
                      width: visibleFrame.width - inset, height: visibleFrame.height)
    }

    package static func stripFrames(from windows: [[String: Any]], screenTop: CGFloat) -> [CGRect] {
        windows.compactMap { window in
            guard window[kCGWindowOwnerName as String] as? String == "WindowManager",
                  (window[kCGWindowAlpha as String] as? NSNumber)?.doubleValue ?? 1 > 0,
                  let bounds = window[kCGWindowBounds as String] as? [String: Any],
                  let frame = CGRect(dictionaryRepresentation: bounds as CFDictionary) else { return nil }
            return CGRect(x: frame.minX, y: screenTop - frame.maxY,
                          width: frame.width, height: frame.height)
        }
    }

    private static func currentStripFrames() -> [CGRect] {
        // Edge-snap previews may ask on each pointer sample. Share a short-lived
        // snapshot across displays instead of querying on every mouse event.
        let now = ProcessInfo.processInfo.systemUptime
        let screenTop = NSScreen.screens.first?.frame.maxY ?? 0
        return sampleLock.withLock {
            if now - sampledAt >= 0.25 {
                sampledAt = now
                let windows = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements],
                                                         kCGNullWindowID) as? [[String: Any]] ?? []
                sampledFrames = stripFrames(from: windows, screenTop: screenTop)
            }
            return sampledFrames
        }
    }
}

extension NSScreen {
    package var windowLayoutVisibleFrame: CGRect { WindowStageManagerSupport.visibleFrame(for: self) }
}
