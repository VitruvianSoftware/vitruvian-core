// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 VitruvianSoftware

import Foundation
import VitruvianCore
import VitruvianDesign
import VitruvianServices
import VitruvianUI

/// Every independently selectable suite, in run order. Swift Testing runs
/// each as one case (`Tests/SwiftTesting/UnitTests.swift`).
enum TestGroups {
    /// The suites' names, spelled out so Swift Testing can list them before
    /// anything runs. `TestHarnessTests` checks they match `all(_:)`.
    nonisolated static let names = [
        "harness",
        "metrics",
        "clipboard",
        "pointer-input",
        "scroll-modifier",
        "linear-scroll",
        "preferences",
        "app-management",
        "window-layout",
        "media",
        "mixer",
        "audio-priority",
        "shelf",
        "overlays",
        "updates",
        "repository",
        "screenshots",
        "recorder",
        "command-bar",
        "notch",
        "switcher-model",
        "agents",
        "features",
        "utilities",
        "settings",
        "display-restoration",
        "software-dimming",
        "capture",
        "keyboard",
        "storage",
        "quit-protection",
        "scratchpad",
        "recording",
        "network",
        "app-updates",
        "localization",
        "cleaner",
        "uninstaller",
        "launcher",
        "dock-autohide",
        "switcher",
        "keep-awake",
        "wallpaper",
        "emoji",
    ]

    /// The suites a run asks for, or all of them. `bazel/run_unit_tests.sh`
    /// turns each `--suite=` into a name in `VITRUVIAN_TEST_SUITES`.
    nonisolated static var selected: [String] {
        let asked = ProcessInfo.processInfo.environment["VITRUVIAN_TEST_SUITES"]?
            .split(separator: ",").map(String.init) ?? []
        return asked.isEmpty ? names : asked
    }

    static func all(_ suite: TestSuite) -> [(String, () -> Void)] {
        [
            ("harness", {
                TestHarnessTests.run(suite)
                PreferenceNamespaceTests.run(suite)
            }),
            ("metrics", {
                MetricsFeatureTests.run(suite)
                ProcessNameContract.run(suite)
                SystemMonitorCPUTests.run(suite)
            }),
            ("clipboard", { ClipboardFeatureTests.run(suite) }),
            ("pointer-input", {
                PointerOnDisplayContract.run(suite)
                PointerInputFeatureTests.run(suite)
                MouseButtonCaptureContract.run(suite)
                KeyboardDebounceTapTests.run(suite)
                PointerDisplayLookupContract.run(suite)
                SuperKeyTapContract.run(suite)
                PointerScreenContract.run(suite)
            }),
            ("scroll-modifier", { ScrollHorizontalModifierTests.run(suite) }),
            ("linear-scroll", { LinearScrollTapTests.run(suite) }),
            ("preferences", { PreferencesFeatureTests.run(suite); PreferenceTests.run(suite) }),
            ("app-management", { AppManagementFeatureTests.run(suite) }),
            ("window-layout", { WindowLayoutFeatureTests.run(suite) }),
            ("media", { MediaFeatureTests.run(suite) }),
            ("mixer", {
                MixerNativeDragTests.run(suite)
                MixerOutputAdjustmentContract.run(suite)
                SoundOutputSwitchContract.run(suite)
                AirPlayRingBufferContract.run(suite)
                AirPlayRouteContract.run(suite)
                AirPlayMixLimiterContract.run(suite)
                AirPlayStreamRegistryContract.run(suite)
                AirPlayFeedDriverContract.run(suite)
                AirPlayRateChangeContract.run(suite)
                AirPlayPrivateAPIContract.run(suite)
                AirPlayAvailabilityContract.run(suite)
                AirPlayConcurrentLanesContract.run(suite)
                AirPlayBacklogContract.run(suite)
                MixerInputVolumeContract.run(suite)
                MixerPercentKeyTests.run(suite)
                MixerFeatureTests.run(suite)
            }),
            ("audio-priority", { AudioPriorityTests.run(suite) }),
            ("shelf", { ShelfFeatureTests.run(suite) }),
            ("overlays", { OverlayPanelTests.run(suite) }),
            ("updates", {
                UpdateFeatureTests.run(suite)
                PostUpdateStatusItemRecoveryTests.run(suite)
                UpdateAdminInstallContract.run(suite)
                UpdateHighlightsTests.run(suite)
                UpdateIntroFlowTests.run(suite)
            }),
            ("repository", {
                RepositoryFeatureTests.run(suite)
                TestRegistrationContract.run(suite)
            }),
            ("screenshots", {
                ScreenshotPreviewHoverTests.run(suite)
                ScreenshotWatermarkTests.run(suite)
                ScreenshotFeatureTests.run(suite)
                ScreenshotShareCompletionTests.run(suite)
                ScreenshotScrollingCaptureTests.run(suite)
                ScreenCaptureToolPickerTests.run(suite)
            }),
            ("recorder", {
                RecorderFeatureTests.run(suite)
                RecorderZoomAimingTests.run(suite)
                RecorderExportSpeedTests.run(suite)
                RecorderExportRenderingTests.run(suite)
            }),
            ("command-bar", { CommandBarFeatureTests.run(suite) }),
            ("notch", {
                NotchTests.run(suite)
                NotchCompactTests.run(suite)
                NotchCapsuleTests.run(suite)
                NotchVolumeKeyTests.run(suite)
                NotchSettingsTabRowTests.run(suite)
            }),
            ("switcher-model", { SwitcherModelFeatureTests.run(suite) }),
            ("agents", { NotchAgentTests.run(suite) }),
            ("features", {
                FeatureCatalogTests.run(suite)
                FeatureRuntimeContract.run(suite)
                MenuPanelSectionGateContract.run(suite)
            }),
            ("utilities", {
                UtilitiesFeatureTests.run(suite)
                PortManagerRefreshTests.run(suite)
            }),
            ("settings", {
                SettingsFeatureTests.run(suite)
                SettingsWindowTests.run { suite.expect($0, $1) }
                NotchSettingsChoiceTests.run(suite)
            }),
            ("display-restoration", {
                DisplayRestorationTests.run(suite)
                BrightnessStepTests.run(suite)
            }),
            ("software-dimming", { SoftwareDimmingRouteTests.run { suite.expect($0, $1) } }),
            ("capture", { ScreenshotSelectionRefreshContract.run(suite) }),
            ("keyboard", {
                KeyboardFeatureTests.run(suite)
                AssistiveKeyboardTests.run(suite)
                ScreenshotToolShortcutTests.run(suite)
            }),
            ("storage", {
                RecentCaptureStoreTests.run(suite)
                RecorderPresetImageStoreTests.run(suite)
                StorageFeatureTests.run(suite)
                ScratchpadStoreContractTests.run(suite)
            }),
            // The HUD is main-actor, and this runner is on the main thread.
            ("quit-protection", { MainActor.assumeIsolated { QuitProtectionHUD.progressChecks(suite) } }),
            ("scratchpad", { ScratchpadMarkTests.run { suite.expect($0, $1) } }),
            ("recording", {
                RecorderSampleTimingTests.run(suite)
                RecorderWriterTests.run(suite)
                RecorderExportChipTests.run { suite.expect($0, $1) }
            }),
            ("network", {
                NetworkFeatureTests.run(suite)
                SpeedTestTests.run(suite)
                NetworkAddressTests.run { suite.expect($0, $1) }
            }),
            ("app-updates", {
                AppUpdatesContract.run(suite)
                AppUpdateRulesContract.run(suite)
            }),
            ("localization", {
                LocalizationTests.run(suite)
                LocalizationFeatureContractTests.run(suite)
            }),
            ("cleaner", {
                CleanerEligibilityTests.run(suite)
                CleanerLastRunContract.run(suite)
                CleanerScanFlowTests.run(suite)
            }),
            ("uninstaller", {
                UninstallerFlowTests.run(suite)
                SelfUninstallContract.run(suite)
            }),
            ("launcher", { QuickLauncherContract.run(suite) }),
            ("dock-autohide", {
                DockAutohideHoldTests.run(suite)
                DockPreviewFrameRestorationTests.run(suite)
            }),
            ("switcher", {
                SwitcherScrollContract.run(suite)
                SwitcherActivationTests.run(suite)
                WindowServerCaptureContract.run(suite)
            }),
            ("keep-awake", {
                KeepAwakeLidSleepTests.run { suite.expect($0, $1) }
                KeepAwakeTimerHandoffTests.run { suite.expect($0, $1) }
            }),
            ("wallpaper", { WallpaperContract.run(suite) }),
            ("emoji", { CommandBarEmojiContract.run(suite) }),
        ]
    }
}
