// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 VitruvianSoftware

import AppKit
import SwiftUI
import VitruvianCore

/// The SwiftUI content services host in their own panels and windows.
///
/// `UI` implements it and `main.swift` installs it before the app runs, so a
/// service shows its view without naming it (REFACTOR.md step 3.2c). A service
/// still owns its window: where it sits, when it shows and how it closes.
///
/// Not `@MainActor`, like `AppShell`: the services that call it are not
/// actor-isolated, and in the Swift 5 language mode they could not call an
/// explicitly main-actor protocol. They all build their views on the main
/// thread, as before.
protocol ServiceViewFactory {
    func switcher(_ switcher: AppSwitcher) -> AnyView
    func dockPreview(_ service: DockPreviewService) -> AnyView
    func pinnedDockPreview(_ panel: DockPreviewPinnedPanel) -> AnyView
    func shelf(_ shelf: ShelfService) -> AnyView
    func dockedShelf(_ shelf: ShelfService) -> AnyView
    func commandBar() -> AnyView
    func clipboardQuickPanel() -> AnyView
    func snippetLibrary() -> AnyView
    func scratchpad() -> AnyView
    func quickLauncher() -> AnyView
    func radialMenu() -> AnyView
    func cameraPreview() -> AnyView
    func recentCaptures(onClose: @escaping () -> Void) -> AnyView
    func cutFeedback(_ cutPaste: FinderCutPaste) -> AnyView
    func cleaningOverlay() -> AnyView
    func screenshotEditor(model: ScreenshotEditorModel, controller: ScreenshotEditorController) -> AnyView
    func recorderEditor(model: RecorderEditorModel, controller: RecorderEditorController) -> AnyView
}

/// Where services find the installed view factory.
enum ServiceViews {
    private static var installed: ServiceViewFactory?

    /// Called once, from `main.swift`, before anything can present.
    static func install(_ factory: ServiceViewFactory) {
        installed = factory
    }

    static var factory: ServiceViewFactory {
        guard let installed else {
            preconditionFailure("ServiceViews.install(_:) runs in main.swift before anything presents")
        }
        return installed
    }
}
