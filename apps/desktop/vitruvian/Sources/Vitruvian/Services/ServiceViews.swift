// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 VitruvianSoftware

import AppKit
import SwiftUI
import VitruvianCore
import VitruvianDesign

/// The SwiftUI content services host in their own panels and windows.
///
/// `UI` implements it and `main.swift` installs it before the app runs, so a
/// service shows its view without naming it (REFACTOR.md step 3.2c). A service
/// still owns its window: where it sits, when it shows and how it closes.
///
/// Main-actor isolated, since every view it builds is. `@preconcurrency`
/// keeps the services that call it, which are not actor-isolated yet, free
/// of diagnostics; they all build their views on the main thread.
@preconcurrency @MainActor
package protocol ServiceViewFactory {
    func switcher(_ switcher: AppSwitcher) -> AnyView
    func dockPreview(_ service: DockPreviewService) -> AnyView
    func pinnedDockPreview(_ panel: DockPreviewPinnedPanel) -> AnyView
    func shelf(_ shelf: ShelfService) -> AnyView
    func dockedShelf(_ shelf: ShelfService) -> AnyView
    func commandBar() -> AnyView
    func clipboardQuickPanel() -> AnyView
    func snippetLibrary() -> AnyView
    func scratchpad() -> AnyView
    func nexusAgentQuickPrompt() -> AnyView
    func quickLauncher() -> AnyView
    func radialMenu() -> AnyView
    func cameraPreview() -> AnyView
    func recentCaptures(onClose: @escaping () -> Void) -> AnyView
    func cutFeedback(_ cutPaste: FinderCutPaste) -> AnyView
    func cleaningOverlay() -> AnyView
    func screenshotEditor(model: ScreenshotEditorModel, controller: ScreenshotEditorController) -> AnyView
    func recorderEditor(model: RecorderEditorModel, controller: RecorderEditorController) -> AnyView
    func notch(_ service: NotchService) -> AnyView
    func notchMirror(_ service: NotchService, mirror: NotchMirrorModel) -> AnyView
    func notchQuickAccess(_ service: NotchService, motion: NotchQuickAccessMotion,
                          backdrop: NotchBackdropPresentation) -> AnyView
    func notchBackground(_ presentation: NotchBackdropPresentation) -> AnyView
    func lockScreenPlayer(model: NotchLockScreenModel, size: CGSize) -> AnyView
    func lockScreenActivities(model: NotchLockScreenModel, size: CGSize) -> AnyView
    /// The locked island at `size`, drawn at `origin` in a window of
    /// `window`, with the music strip's `geometry` for its padlock and bars.
    func lockScreenIsland(model: NotchLockScreenModel, size: CGSize, cameraWidth: CGFloat, geometry: NotchGeometry,
                          window: CGSize, origin: CGPoint) -> AnyView
}

/// Where services find the installed view factory.
@MainActor
package enum ServiceViews {
    private static var installed: ServiceViewFactory?

    /// Called once, from `main.swift`, before anything can present.
    package static func install(_ factory: ServiceViewFactory) {
        installed = factory
    }

    package static var factory: ServiceViewFactory {
        guard let installed else {
            preconditionFailure("ServiceViews.install(_:) runs in main.swift before anything presents")
        }
        return installed
    }
}
