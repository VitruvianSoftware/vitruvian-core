// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import AppKit
import VitruvianCore
import VitruvianDesign
import VitruvianServices
import VitruvianUI

/// AppKit describes a non-activating panel as a system dialog, which tiling
/// window managers track and list on whichever space is current. The shared
/// panel class comes from `VitruvianDesign`; each floating surface builds its
/// panels through its own factory, which is asked for one here. None is shown.
enum OverlayPanelTests {
    static func run(_ suite: TestSuite) {
        // The Clipboard History window keeps a title bar strip to drag it by.
        for style: NSWindow.StyleMask in [[.borderless, .nonactivatingPanel],
                                          [.titled, .closable, .fullSizeContentView, .nonactivatingPanel]] {
            let overlay = OverlayPanel(contentRect: CGRect(x: 0, y: 0, width: 200, height: 40),
                                       styleMask: style, backing: .buffered, defer: true)
            suite.expect(overlay.accessibilitySubrole() == .unknown,
                         "a floating overlay describes itself as an undescribed window, so window managers skip it")
            suite.expect(overlay.accessibilityRole() == .window && overlay.isAccessibilityElement(),
                         "a floating overlay stays an accessible window for assistive technology")
        }

        // HUDs, previews, pickers and the menu's positioning helper: none is a
        // document window, and each floats over other apps' windows.
        let frame = CGRect(x: 0, y: 0, width: 200, height: 40)
        let surfaces: [(String, NSPanel)] = [
            ("the menu panel's popover anchor", AppKitMenuPanel.makePositioningPanel(at: frame)),
            ("the permission guide", PermissionGuideOverlay.makePanel(frame: frame)),
            ("the quit protection confirmation", QuitProtectionHUD.makePanel(size: frame.size)),
            ("the quick tool confirmation", QuickToolHUD.makePanel()),
            ("the scrolling capture controls", QuickToolHUD.makeScrollingPanel()),
            ("the quick launcher", QuickLauncherService.makePanel()),
            ("the camera preview", CameraPreviewService.makePanel()),
            ("the recent captures", RecentCaptureService.makeHistoryPanel()),
            ("the screenshot preview", ScreenshotQuickPreviewController.makePanel(size: frame.size)),
            ("the QR result", QRResultController.makePanel(size: frame.size)),
            ("the scratchpad", ScratchpadService.makePanel()),
            ("the snippet library", SnippetLibraryService.makePanel()),
            ("the clipboard history", ClipboardHistoryService.makePanel(size: frame.size)),
            ("the command bar", CommandBarService.makePanel()),
            ("the app switcher", AppSwitcher.makePanel()),
            ("the radial menu", RadialMenuService.makePanel()),
            ("the radial now playing card", RadialNowPlayingService.makePanel()),
            ("the Dock preview, hovered or pinned", DockPreviewService.makePanel()),
            ("the window layout indicator and edge snap preview", WindowLayoutService.makeOverlayPanel()),
            ("the disk image install progress", DiskImageInstallerService.makeProgressPanel()),
            ("the Finder cut feedback", FinderCutPaste.makePanel()),
            ("the brightness level indicator", BrightnessOSD.makePanel()),
            ("the cleaning mode cover", CleaningModeManager.makePanel(frame: frame)),
            ("the recording pill and region guide", RecorderIndicator.makePanel(frame: frame)),
        ]
        for (surface, panel) in surfaces {
            suite.expect(panel is OverlayPanel && panel.accessibilitySubrole() == .unknown,
                         "\(surface) builds its floating panels as overlays, which window managers do not list")
        }
        // Built with what they show, so their class is what is checked: the
        // screenshot chooser's per-display panels and a pinned capture.
        suite.expect(ScreenshotOverlayPanel.isSubclass(of: OverlayPanel.self),
                     "the screenshot chooser builds its floating panels as overlays, which window managers do not list")
        suite.expect(ScreenshotPinWindow.isSubclass(of: OverlayPanel.self),
                     "a screenshot pin builds its floating panel as an overlay, which window managers do not list")
    }
}
