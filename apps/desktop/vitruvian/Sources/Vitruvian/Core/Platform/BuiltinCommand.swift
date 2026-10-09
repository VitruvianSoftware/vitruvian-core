// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 VitruvianSoftware

import Foundation

/// Every action of the app's own tools that a surface can trigger. The one
/// list: the radial menu, the Quick panel and the command bar map onto it
/// instead of each choosing a service call. Raw values are command ids and
/// may end up in saved state; never rename one.
package enum BuiltinCommand: String, CaseIterable, Sendable {
    case screenshotCapture = "screenshot/capture"
    case screenRecorderToggle = "screenRecorder/toggle"
    case colorPickerPick = "colorPicker/pick"
    case screenOCRCapture = "screenOCR/capture"
    case micMuteToggle = "micMute/toggle"
    case clipboardHistoryShow = "clipboardHistory/show"
    case quickLauncherShow = "quickLauncher/show"
    case cameraPreviewShow = "cameraPreview/show"
    case scratchpadShow = "scratchpad/show"
    case shelfSummon = "shelf/summon"
    case cleanerOpen = "cleaner/open"
    case uninstallerOpen = "uninstaller/open"
    case appUpdatesCheck = "appUpdates/check"
    case cleaningModeActivate = "cleaningMode/activate"
    case keepAwakeToggle = "keepAwake/toggle"

    /// Every raw value above parses and names a real feature; the `builtins`
    /// checks in `ToolPlatformTests` fail the build's tests otherwise.
    package var id: CommandID { CommandID(rawValue)! }

    package var feature: AppFeature { AppFeature(rawValue: id.tool.rawValue)! }
}
