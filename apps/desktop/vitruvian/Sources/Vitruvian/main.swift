// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import AppKit
import VitruvianCore
import VitruvianDesign
import VitruvianServices
import VitruvianUI

SuperKeyMappingGuard.runIfRequestedAndExit()
Defaults.register()
// The island asks the brightness service whether this Mac has a keyboard
// light. Top-level code runs on the main thread.
MainActor.assumeIsolated { NotchControlItem.wireKeyboardLight() }
// Services show their SwiftUI content through this, so it is in place before
// anything below can present. Top-level code runs on the main thread.
MainActor.assumeIsolated { ServiceViews.install(UIServiceViewFactory()) }
// The app's own tools and commands, in the registry before any surface
// lists or runs one. Top-level code runs on the main thread.
MainActor.assumeIsolated { BuiltinTools.install() }
#if VITRUVIAN_SAMPLE_TOOL
// A tool outside every fixed list, for checking the surfaces by hand. Only
// a build made with --define=vitruvian_sample_tool=true has it.
MainActor.assumeIsolated { SampleTool.install() }
#endif
// The tools that run as their own programs, which the person added in
// Settings and agreed to: back in the registry, as they were at the last
// quit. With none added this reads one file that is not there. Top-level
// code runs on the main thread.
MainActor.assumeIsolated { ExternalToolStore.shared.restore() }
// The windows those tools open, made and closed as the panel host says.
MainActor.assumeIsolated { ToolPanelWindows.shared.start() }
#if VITRUVIAN_SAMPLE_TOOL
// A rehearsal of the tool catalog on this Mac, for the checks by hand: only
// when both of its variables are set, as `bazel run //catalog:rehearse`
// prints them. Before anything below reads where the catalog is.
MainActor.assumeIsolated {
    if let rehearsal = CatalogueSource.rehearsal(ProcessInfo.processInfo.environment) {
        CatalogueSource.inUse = rehearsal
    }
}
#endif
// The tool catalog: a download a quit left behind is deleted, and the list is
// fetched now and once a day, only while a tool from it is installed.
MainActor.assumeIsolated {
    CatalogueInstaller.shared.sweep()
    CatalogueWatch.shared.start()
}
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

if CommandLine.arguments.contains("--selftest") {
    SelfTest.runAndExit()
}
if CommandLine.arguments.contains("--sensors") {
    SensorDump.runAndExit()
}
if CommandLine.arguments.contains("--uninstall") {
    Uninstaller.runAndExit()
}

#if VITRUVIAN_DEVELOPMENT
// A probe mode on its own would otherwise launch the whole app, and TCC kills
// that from a shell whose host app lacks a Bluetooth usage description. The
// commands above come first, so `--selftest` beside a probe mode runs the
// selftest, not the probe.
if NotchPresentationProbeMode.isRequested(by: CommandLine.arguments) {
    NotchPresentationProbe.runAndExit()
}
#endif

let app = NSApplication.shared
// Top-level code runs on the main thread.
let delegate = MainActor.assumeIsolated { AppDelegate() }
app.delegate = delegate
app.run()
