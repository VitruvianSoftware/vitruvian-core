// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import AppKit
import CoreGraphics

package enum SwitcherAppIconCache {
    private static let lock = NSLock()
    /// Read and written only under `lock`.
    nonisolated(unsafe) private static var icons: [pid_t: NSImage]?

    package static func beginSession() {
        lock.withLock { icons = [:] }
    }

    package static func endSession() {
        lock.withLock { icons = nil }
    }

    /// On the main thread, which owns the app's appearance.
    @preconcurrency @MainActor
    package static func icon(for pid: pid_t) -> NSImage? {
        if let cached = lock.withLock({ icons?[pid] }) { return cached }
        guard let resolved = stableBundleIcon(pid: pid,
                                              appearance: NSApplication.shared.effectiveAppearance)
        else { return nil }
        // Outside a switcher session, Dock previews must resolve the current icon.
        lock.withLock { icons?[pid] = resolved }
        return resolved
    }

    package static func declaredDockIconURL(bundleURL: URL,
                                    resourceName: String?,
                                    darkMode: Bool) -> URL? {
        guard let resourceName = resourceName?.trimmingCharacters(in: .whitespacesAndNewlines),
              !resourceName.isEmpty,
              !resourceName.hasPrefix("/") else { return nil }
        let replacements: [(String, String)] = darkMode
            ? [("-light.", "-dark-color."), ("-light.", "-dark.")]
            : [("-dark-color.", "-light."), ("-dark.", "-light.")]
        let names = replacements.compactMap { source, destination in
            resourceName.contains(source)
                ? resourceName.replacingOccurrences(of: source, with: destination)
                : nil
        } + [resourceName]

        let resources = bundleURL.appendingPathComponent("Contents/Resources", isDirectory: true)
            .resolvingSymlinksInPath().standardizedFileURL
        let bundle = bundleURL.resolvingSymlinksInPath().standardizedFileURL
        guard resources.path.hasPrefix(bundle.path + "/") else { return nil }
        for name in names {
            let candidate = resources.appendingPathComponent(name)
                .resolvingSymlinksInPath().standardizedFileURL
            guard candidate.path.hasPrefix(resources.path + "/") else { continue }
            var isDirectory: ObjCBool = false
            if FileManager.default.fileExists(atPath: candidate.path, isDirectory: &isDirectory),
               !isDirectory.boolValue {
                return candidate
            }
        }
        return nil
    }

    private static func stableBundleIcon(pid: pid_t, appearance: NSAppearance) -> NSImage? {
        guard let app = NSRunningApplication(processIdentifier: pid) else { return nil }
        let darkMode = appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
        let declaredIcon = app.bundleURL.flatMap { bundleURL -> NSImage? in
            guard let bundleIdentifier = app.bundleIdentifier,
                  let resourceName = CFPreferencesCopyAppValue(
                      "DockIconResourceName" as CFString,
                      bundleIdentifier as CFString
                  ) as? String,
                  let resourceURL = declaredDockIconURL(bundleURL: bundleURL,
                                                        resourceName: resourceName,
                                                        darkMode: darkMode)
            else { return nil }
            return NSImage(contentsOf: resourceURL)
        }
        let source = declaredIcon
            ?? app.bundleURL.map { NSWorkspace.shared.icon(forFile: $0.path) }
            ?? app.icon
        guard let source else { return nil }
        return NSImage(size: source.size, flipped: false) { rect in
            appearance.performAsCurrentDrawingAppearance { source.draw(in: rect) }
            return true
        }
    }
}

package enum WindowSwitchMinimizedPlacement: String, CaseIterable {
    case normal
    case end
    case hidden
}

/// One selectable entry in the switcher. Most entries are real user-facing
/// windows; Finder can also appear as an app entry when it has no windows, so
/// the user can still switch to the desktop/menu bar like the system switcher.
package struct SwitcherItem: Identifiable, Equatable {
    package let id: String
    package let title: String
    package let appName: String
    /// The regular app represented by this entry. App grouping, icons, MRU,
    /// activation and quit actions use this process.
    package let pid: pid_t
    /// The process that actually owns `windowID`. Multi-process apps can render
    /// their user-facing windows in an embedded accessory helper.
    package let windowOwnerPID: pid_t
    /// The backing CGWindow: thumbnails and AX raising go through it.
    package let windowID: CGWindowID?
    package let isOnScreen: Bool
    package let isAppHidden: Bool
    package let isMinimized: Bool
    package let isFullscreen: Bool
    /// The window belongs only to Spaces that are not currently visible.
    package let isOnHiddenSpace: Bool
    /// Window-server coordinates, top-left origin: `kCGWindowBounds`, or the
    /// Accessibility position and size when the window server has no usable
    /// bounds. Never an AppKit (bottom-left) frame, so it can be compared with
    /// `CGDisplayBounds` directly. `.zero` for an entry without a window.
    package let frame: CGRect

    /// The window whose thumbnail represents this entry.
    package var previewWindowID: CGWindowID? { windowID }

    /// Label shown under the thumbnail; untitled windows fall back to the app name.
    package var displayTitle: String {
        title.isEmpty ? appName : title
    }

    package func windowLabel(noOpenWindow: String) -> String {
        isAppEntry ? noOpenWindow : displayTitle
    }

    /// The line under an app's name, when there is one worth reading. A window
    /// titled after its own app would only repeat the line above it, which is
    /// the same rule `displaySubtitle` already applies the other way round.
    package func windowDetail(noOpenWindow: String) -> String? {
        if isAppEntry { return noOpenWindow }
        return displaySubtitle == nil ? nil : displayTitle
    }

    /// Secondary label used when the window title does not already identify the
    /// app. This keeps crowded switcher grids readable without repeating text.
    package var displaySubtitle: String? {
        let cleanTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        let cleanAppName = appName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanAppName.isEmpty,
              !cleanTitle.isEmpty,
              cleanTitle.caseInsensitiveCompare(cleanAppName) != .orderedSame
        else { return nil }
        return cleanAppName
    }

    package var accessibilityTitle: String {
        if let displaySubtitle {
            return "\(displayTitle), \(displaySubtitle)"
        }
        return displayTitle
    }

    /// Whether this entry stands for the app itself because it has no window
    /// to switch to. Those entries have no thumbnail to draw and no window to
    /// name, so several places have to present them differently.
    package var isAppEntry: Bool { windowID == nil }

    /// A hidden app follows the minimized-windows placement only when the
    /// user explicitly opts in; an actually minimized window always does.
    package func isMinimizedForPlacement(treatHiddenAppsLikeMinimized: Bool) -> Bool {
        isMinimized || (treatHiddenAppsLikeMinimized && isAppHidden)
    }

    /// What the screen reader hears. An app entry replaces the window title
    /// with its state on screen, so the label has to carry that state too or
    /// the entry sounds identical to a window of the same app.
    ///
    /// Lives on the model rather than beside one view: the Dock preview card
    /// draws the same badges and owes its reader the same sentence.
    package func spokenLabel(noOpenWindow: String,
                     hiddenApp: String,
                     otherDesktop: String) -> String {
        var label = isAppEntry ? "\(appName), \(noOpenWindow)" : accessibilityTitle
        if isAppHidden { label += ", \(hiddenApp)" }
        if isOnHiddenSpace { label += ", \(otherDesktop)" }
        return label
    }

    /// The badges a card draws along the bottom of this window's picture, in
    /// order: the App Switcher's grid card and the Dock preview card show the
    /// same ones. A window that lives on another desktop is badged as such,
    /// which `spokenLabel` says to the reader.
    package var statusBadges: [WindowStatusBadge] {
        var badges: [WindowStatusBadge] = []
        if isMinimized { badges.append(.minimized) }
        if isFullscreen { badges.append(.fullscreen) }
        if isOnHiddenSpace { badges.append(.otherDesktop) }
        return badges
    }

    /// Prefer an explicitly declared alternate icon, otherwise use the system
    /// bundle icon. Reuse the image only while a switcher session is open.
    @preconcurrency @MainActor
    package var appIcon: NSImage? {
        SwitcherAppIconCache.icon(for: pid)
    }

    package func withMinimized(_ minimized: Bool) -> SwitcherItem {
        SwitcherItem(id: id,
                     title: title,
                     appName: appName,
                     pid: pid,
                     windowOwnerPID: windowOwnerPID,
                     windowID: windowID,
                     isOnScreen: minimized ? false : true,
                     isAppHidden: isAppHidden,
                     isMinimized: minimized,
                     isFullscreen: isFullscreen,
                     isOnHiddenSpace: isOnHiddenSpace,
                     frame: frame)
    }

    package func withHiddenSpaceState(_ hidden: Bool) -> SwitcherItem {
        SwitcherItem(id: id,
                     title: title,
                     appName: appName,
                     pid: pid,
                     windowOwnerPID: windowOwnerPID,
                     windowID: windowID,
                     isOnScreen: isOnScreen,
                     isAppHidden: isAppHidden,
                     isMinimized: isMinimized,
                     isFullscreen: isFullscreen,
                     isOnHiddenSpace: hidden,
                     frame: frame)
    }

    package static func window(id: CGWindowID, title: String, appName: String, pid: pid_t,
                       windowOwnerPID: pid_t? = nil,
                       isOnScreen: Bool, isAppHidden: Bool = false,
                       isMinimized: Bool = false,
                       isFullscreen: Bool = false, frame: CGRect) -> SwitcherItem {
        SwitcherItem(id: "w:\(id)", title: title, appName: appName,
                     pid: pid, windowOwnerPID: windowOwnerPID ?? pid,
                     windowID: id, isOnScreen: isOnScreen,
                     isAppHidden: isAppHidden,
                     isMinimized: isMinimized, isFullscreen: isFullscreen,
                     isOnHiddenSpace: false,
                     frame: frame)
    }

    package static func appOnly(appName: String, pid: pid_t,
                        isAppHidden: Bool = false) -> SwitcherItem {
        SwitcherItem(id: "a:\(pid)", title: appName, appName: appName,
                     pid: pid, windowOwnerPID: pid, windowID: nil, isOnScreen: false,
                     isAppHidden: isAppHidden,
                     isMinimized: false, isFullscreen: false,
                     isOnHiddenSpace: false, frame: .zero)
    }

    // Spelled out because a memberwise initializer never leaves its module.
    package init(id: String, title: String, appName: String, pid: pid_t, windowOwnerPID: pid_t, windowID: CGWindowID?, isOnScreen: Bool, isAppHidden: Bool, isMinimized: Bool, isFullscreen: Bool, isOnHiddenSpace: Bool, frame: CGRect) {
        self.id = id
        self.title = title
        self.appName = appName
        self.pid = pid
        self.windowOwnerPID = windowOwnerPID
        self.windowID = windowID
        self.isOnScreen = isOnScreen
        self.isAppHidden = isAppHidden
        self.isMinimized = isMinimized
        self.isFullscreen = isFullscreen
        self.isOnHiddenSpace = isOnHiddenSpace
        self.frame = frame
    }
}

/// A state a window card badges in the corner of its picture.
package enum WindowStatusBadge: Hashable, Sendable {
    case minimized
    case fullscreen
    /// The window lives only on desktops that are not showing.
    case otherDesktop

    /// The symbol the badge draws.
    package var systemImage: String {
        switch self {
        case .minimized: return "minus.rectangle"
        case .fullscreen: return "arrow.up.left.and.arrow.down.right"
        case .otherDesktop: return "rectangle.stack"
        }
    }
}
