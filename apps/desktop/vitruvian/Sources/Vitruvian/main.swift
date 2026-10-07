// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import AppKit
import VitruvianCore
import VitruvianDesign
import VitruvianServices
import VitruvianUI

SuperKeyMappingGuard.runIfRequestedAndExit()
Defaults.register()
// Services show their SwiftUI content through this, so it is in place before
// anything below can present. Top-level code runs on the main thread.
MainActor.assumeIsolated { ServiceViews.install(UIServiceViewFactory()) }
// The island calls back into the services that follow it through these, so
// it names none of them. Top-level code runs on the main thread.
MainActor.assumeIsolated {
    NotchService.collaborators = NotchCollaborators(
        feedbackRoutingDidChange: {
            if AppFeature.mixer.isAvailable { PreciseVolumeRollerService.shared.syncWithPreferences() }
            if AppFeature.brightness.isAvailable { BrightnessService.shared.syncWithPreferences() }
        },
        fileRoutingDidChange: {
            if AppFeature.shelf.isAvailable { ShelfService.shared.syncWithPreferences() }
        },
        shelfCanAccept: { !ShelfService.shared.isInternalDragActive && ShelfService.shared.canAcceptPasteboard($0) },
        shelfAccept: { ShelfService.shared.acceptDrop(pasteboard: $0) },
        commandBarIslandDidClose: { CommandBarService.shared.islandDidClose() })
}
MouseAccelerationGuard.runIfRequestedAndExit()
// Top-level code runs on the main thread.
MainActor.assumeIsolated { MouseAccelerationService.recoverPendingAtLaunch() }

#if VITRUVIAN_DEVELOPMENT
if CommandLine.arguments.contains("--notch-presentation-test") {
    NotchPresentationProbe.runAndExit()
}
#endif

if CommandLine.arguments.contains("--selftest") {
    SelfTest.runAndExit()
}
if CommandLine.arguments.contains("--sensors") {
    SensorDump.runAndExit()
}
if CommandLine.arguments.contains("--uninstall") {
    Uninstaller.runAndExit()
}

let app = NSApplication.shared
// Top-level code runs on the main thread.
let delegate = MainActor.assumeIsolated { AppDelegate() }
app.delegate = delegate
app.run()
