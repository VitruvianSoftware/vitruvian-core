// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 VitruvianSoftware

import SwiftUI
import VitruvianCore
import VitruvianDesign
import VitruvianServices

/// The views behind `ServiceViewFactory`: each service's SwiftUI content,
/// built exactly as the service used to build it itself.
package struct UIServiceViewFactory: ServiceViewFactory {
    package func switcher(_ switcher: AppSwitcher) -> AnyView {
        AnyView(SwitcherView().environmentObject(switcher))
    }

    package func dockPreview(_ service: DockPreviewService) -> AnyView {
        AnyView(DockPreviewPanelView(service: service))
    }

    package func pinnedDockPreview(_ panel: DockPreviewPinnedPanel) -> AnyView {
        AnyView(DockPreviewPinnedPanelView(panel: panel))
    }

    package func shelf(_ shelf: ShelfService) -> AnyView {
        AnyView(ShelfView().environmentObject(shelf))
    }

    package func dockedShelf(_ shelf: ShelfService) -> AnyView {
        AnyView(DockedShelfView().environmentObject(shelf))
    }

    package func commandBar() -> AnyView {
        AnyView(CommandBarView())
    }

    package func clipboardQuickPanel() -> AnyView {
        AnyView(ClipboardQuickPanelView())
    }

    package func snippetLibrary() -> AnyView {
        AnyView(SnippetLibraryView())
    }

    package func scratchpad() -> AnyView {
        AnyView(ScratchpadView())
    }

    package func quickLauncher() -> AnyView {
        AnyView(QuickLauncherView())
    }

    package func radialMenu() -> AnyView {
        AnyView(RadialMenuView())
    }

    package func cameraPreview() -> AnyView {
        AnyView(CameraPreviewView())
    }

    package func recentCaptures(onClose: @escaping () -> Void) -> AnyView {
        AnyView(RecentCapturesWindowView(onClose: onClose))
    }

    package func cutFeedback(_ cutPaste: FinderCutPaste) -> AnyView {
        AnyView(CutFeedbackView().environmentObject(cutPaste))
    }

    package func cleaningOverlay() -> AnyView {
        AnyView(CleaningOverlayView())
    }

    package func screenshotEditor(model: ScreenshotEditorModel, controller: ScreenshotEditorController) -> AnyView {
        AnyView(ScreenshotEditorView(model: model, controller: controller))
    }

    package func recorderEditor(model: RecorderEditorModel, controller: RecorderEditorController) -> AnyView {
        AnyView(RecorderEditorView(model: model, controller: controller))
    }

    package func notch(_ service: NotchService) -> AnyView {
        AnyView(NotchView(service: service))
    }

    package func notchMirror(_ service: NotchService, mirror: NotchMirrorModel) -> AnyView {
        AnyView(NotchMirrorView(service: service, mirror: mirror))
    }

    package func notchQuickAccess(_ service: NotchService, motion: NotchQuickAccessMotion,
                          backdrop: NotchBackdropPresentation) -> AnyView {
        AnyView(NotchQuickAccessView(service: service, motion: motion, backdrop: backdrop))
    }

    package func notchBackground(_ presentation: NotchBackdropPresentation) -> AnyView {
        AnyView(NotchWindowBackground(presentation: presentation))
    }

    package func lockScreenPlayer(model: NotchLockScreenModel, size: CGSize) -> AnyView {
        AnyView(NotchLockScreenPlayer(model: model, size: size))
    }

    package func lockScreenActivities(model: NotchLockScreenModel, size: CGSize) -> AnyView {
        AnyView(NotchLockScreenActivities(model: model, size: size))
    }

    package func lockScreenIsland(model: NotchLockScreenModel, size: CGSize, cameraWidth: CGFloat) -> AnyView {
        AnyView(NotchLockScreenIsland(model: model, size: size, cameraWidth: cameraWidth))
    }

    // Spelled out because a memberwise initializer never leaves its module.
    package init() {
    }
}
