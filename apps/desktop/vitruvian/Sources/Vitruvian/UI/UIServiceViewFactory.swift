// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 VitruvianSoftware

import SwiftUI
import VitruvianCore
import VitruvianDesign

/// The views behind `ServiceViewFactory`: each service's SwiftUI content,
/// built exactly as the service used to build it itself.
struct UIServiceViewFactory: ServiceViewFactory {
    func switcher(_ switcher: AppSwitcher) -> AnyView {
        AnyView(SwitcherView().environmentObject(switcher))
    }

    func dockPreview(_ service: DockPreviewService) -> AnyView {
        AnyView(DockPreviewPanelView(service: service))
    }

    func pinnedDockPreview(_ panel: DockPreviewPinnedPanel) -> AnyView {
        AnyView(DockPreviewPinnedPanelView(panel: panel))
    }

    func shelf(_ shelf: ShelfService) -> AnyView {
        AnyView(ShelfView().environmentObject(shelf))
    }

    func dockedShelf(_ shelf: ShelfService) -> AnyView {
        AnyView(DockedShelfView().environmentObject(shelf))
    }

    func commandBar() -> AnyView {
        AnyView(CommandBarView())
    }

    func clipboardQuickPanel() -> AnyView {
        AnyView(ClipboardQuickPanelView())
    }

    func snippetLibrary() -> AnyView {
        AnyView(SnippetLibraryView())
    }

    func scratchpad() -> AnyView {
        AnyView(ScratchpadView())
    }

    func quickLauncher() -> AnyView {
        AnyView(QuickLauncherView())
    }

    func radialMenu() -> AnyView {
        AnyView(RadialMenuView())
    }

    func cameraPreview() -> AnyView {
        AnyView(CameraPreviewView())
    }

    func recentCaptures(onClose: @escaping () -> Void) -> AnyView {
        AnyView(RecentCapturesWindowView(onClose: onClose))
    }

    func cutFeedback(_ cutPaste: FinderCutPaste) -> AnyView {
        AnyView(CutFeedbackView().environmentObject(cutPaste))
    }

    func cleaningOverlay() -> AnyView {
        AnyView(CleaningOverlayView())
    }

    func screenshotEditor(model: ScreenshotEditorModel, controller: ScreenshotEditorController) -> AnyView {
        AnyView(ScreenshotEditorView(model: model, controller: controller))
    }

    func recorderEditor(model: RecorderEditorModel, controller: RecorderEditorController) -> AnyView {
        AnyView(RecorderEditorView(model: model, controller: controller))
    }

    func notch(_ service: NotchService) -> AnyView {
        AnyView(NotchView(service: service))
    }

    func notchMirror(_ service: NotchService, mirror: NotchMirrorModel) -> AnyView {
        AnyView(NotchMirrorView(service: service, mirror: mirror))
    }

    func notchQuickAccess(_ service: NotchService, motion: NotchQuickAccessMotion,
                          backdrop: NotchBackdropPresentation) -> AnyView {
        AnyView(NotchQuickAccessView(service: service, motion: motion, backdrop: backdrop))
    }

    func notchBackground(_ presentation: NotchBackdropPresentation) -> AnyView {
        AnyView(NotchWindowBackground(presentation: presentation))
    }

    func lockScreenPlayer(model: NotchLockScreenModel, size: CGSize) -> AnyView {
        AnyView(NotchLockScreenPlayer(model: model, size: size))
    }

    func lockScreenActivities(model: NotchLockScreenModel, size: CGSize) -> AnyView {
        AnyView(NotchLockScreenActivities(model: model, size: size))
    }

    func lockScreenIsland(model: NotchLockScreenModel, size: CGSize, cameraWidth: CGFloat) -> AnyView {
        AnyView(NotchLockScreenIsland(model: model, size: size, cameraWidth: cameraWidth))
    }
}
