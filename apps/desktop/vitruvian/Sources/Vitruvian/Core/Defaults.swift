// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import CoreGraphics
import Carbon.HIToolbox
import Foundation
import FanControlKit

/// Bump `currentFeatureSet` when first-run feature defaults need a quiet marker.
package enum OnboardingInfo {
    // 2: system monitor, configurable panel and menu bar metrics.
    // 3: app languages and support settings.
    // 4: navigable menu panel sections.
    package static let currentFeatureSet = 4
}

/// The one-time tour of this release's headline feature, shown after updating.
package enum UpdateHighlightsInfo {
    // Keep this marker unchanged for every stable patch in the 3.4 series.
    package static let releaseVersion = "3.4.0"
    package static let betaSeenVersion = "3.4.0-beta.1"

    package static func matchesRelease(_ appVersion: String) -> Bool {
        guard let version = UpdateServiceSupport.SemanticVersion(raw: appVersion),
              let release = UpdateServiceSupport.SemanticVersion(raw: releaseVersion),
              (version.major, version.minor) == (release.major, release.minor),
              version.patch >= release.patch else { return false }
        if version.prerelease.isEmpty { return true }
        guard version.patch == release.patch, (2...3).contains(version.prerelease.count), version.prerelease[0].description == "beta",
              let number = Int(version.prerelease[1].description) else { return false }
        if version.prerelease.count == 3 {
            guard case let .numeric(hotfix) = version.prerelease[2], hotfix >= 0 else { return false }
        }
        return number >= 1
    }

    package static func shouldShow(appVersion: String, lastSeenVersion: String?) -> Bool {
        guard let marker = seenVersion(for: appVersion) else { return false }
        return lastSeenVersion != marker
    }

    package static func seenVersion(for appVersion: String) -> String? {
        guard matchesRelease(appVersion),
              let version = UpdateServiceSupport.SemanticVersion(raw: appVersion) else { return nil }
        return version.prerelease.isEmpty ? releaseVersion : betaSeenVersion
    }
}

/// A single invitation for existing Dynamic Island users to turn on display
/// controls after updating. "pending" survives a launch interrupted before
/// the invitation can be shown; "handled" prevents future updates replaying it.
package enum BrightnessUpdatePromptInfo {
    package static let pending = "pending"
    package static let handled = "handled"

    package static func isUpgrade(appVersion: String, previousVersion: String?) -> Bool {
        guard let previousVersion,
              let previous = UpdateServiceSupport.SemanticVersion(raw: previousVersion),
              let current = UpdateServiceSupport.SemanticVersion(raw: appVersion) else { return false }
        return current > previous
    }

    package static func needsSetup(notchAvailable: Bool, brightnessAvailable: Bool,
                           notchEnabled: Bool, notchBrightness: Bool, brightnessEnabled: Bool) -> Bool {
        notchAvailable && brightnessAvailable && notchEnabled && notchBrightness && !brightnessEnabled
    }
}

package enum SupportUpdateIntroInfo {
    /// The stable release series that gets this invitation. Patch updates share
    /// one completion marker, including when someone skips the initial release.
    package static let releaseVersion = "3.4.0"

    // Older beta onboarding wrote the release version before this screen was
    // available. A distinct completion marker keeps those upgraders eligible.
    package static let seenVersion = "3.4.0-support"

    package static func matchesRelease(_ appVersion: String) -> Bool {
        guard let version = UpdateServiceSupport.SemanticVersion(raw: appVersion),
              let release = UpdateServiceSupport.SemanticVersion(raw: releaseVersion) else { return false }
        return (version.major, version.minor) == (release.major, release.minor)
            && version.patch >= release.patch && version.prerelease.isEmpty
    }

    /// The invitation asks for upstream's donations, so Vitruvian keeps it off
    /// until it has channels of its own (AppInfo.hasCommunityChannels). Tests
    /// switch it on to keep the retained flow covered.
    ///
    /// Only tests write it, before anything reads it.
    nonisolated(unsafe) package static var isOffered = AppInfo.hasCommunityChannels

    package static func shouldShow(appVersion: String, lastSeenVersion: String?) -> Bool {
        isOffered && matchesRelease(appVersion) && lastSeenVersion != seenVersion
    }
}

package enum KeepAwakeIconTint: String, CaseIterable, Identifiable {
    case orange, green, blue, purple, pink, none

    package var id: String { rawValue }

    package static var current: KeepAwakeIconTint {
        Defaults.sanitizedKeepAwakeIconTint(
            UserDefaults.standard.string(forKey: DefaultsKey.keepAwakeIconTint)
        )
    }

    package func title(_ strings: Strings) -> String {
        switch self {
        case .orange: return strings.keepAwakeIconTintOrange
        case .green: return strings.keepAwakeIconTintGreen
        case .blue: return strings.keepAwakeIconTintBlue
        case .purple: return strings.keepAwakeIconTintPurple
        case .pink: return strings.keepAwakeIconTintPink
        case .none: return strings.keepAwakeIconTintNone
        }
    }
}

package enum KeepAwakeActiveIcon: String, CaseIterable, Identifiable {
    case vitruvian, coffee, eye, moon, light

    package var id: String { rawValue }

    package static var current: KeepAwakeActiveIcon {
        Defaults.sanitizedKeepAwakeActiveIcon(
            UserDefaults.standard.string(forKey: DefaultsKey.keepAwakeActiveIcon)
        )
    }

    package var systemSymbolName: String? {
        switch self {
        case .vitruvian: return nil
        case .coffee: return "cup.and.saucer.fill"
        case .eye: return "eye.fill"
        case .moon: return "moon.fill"
        case .light: return "lightbulb.fill"
        }
    }

    /// Nudge down the menu bar canvas, in points. Symbols carrying their mass
    /// above the shape's middle — steam over a cup, a bulb over its base — read
    /// as sitting high when their ink is centered geometrically.
    package var menuBarDrop: CGFloat {
        switch self {
        case .coffee: return 1
        case .light: return 0.5
        case .vitruvian, .eye, .moon: return 0
        }
    }

    package func title(_ strings: Strings) -> String {
        switch self {
        case .vitruvian: return strings.keepAwakeActiveIconVitruvian
        case .coffee: return strings.keepAwakeActiveIconCoffee
        case .eye: return strings.keepAwakeActiveIconEye
        case .moon: return strings.keepAwakeActiveIconMoon
        case .light: return strings.keepAwakeActiveIconLight
        }
    }
}

/// Thumbnail size for Dock Preview and, separately, the app switcher. Captures
/// scale by the same factor, so larger previews stay sharp.
package enum PreviewSizing {
    package static func sanitized(_ value: String) -> String {
        Defaults.allowedPreviewSizes.contains(value) ? value : "normal"
    }

    package static func scale(for value: String) -> CGFloat {
        switch sanitized(value) {
        case "small": return 0.75
        case "large": return 1.4
        case "xlarge": return 1.8
        default: return 1.0
        }
    }

    package static var scale: CGFloat {
        scale(for: UserDefaults.standard.string(forKey: DefaultsKey.previewSize) ?? "normal")
    }

    package static var switcherScale: CGFloat {
        scale(for: UserDefaults.standard.string(forKey: DefaultsKey.switcherPreviewSize) ?? "normal")
    }
}

package enum Defaults {
    package static let finderBundleIdentifier = "com.apple.finder"
    /// Continuity / Calls on Mac. Quitting Phone when its UI flickers window-less
    /// during an incoming relay disconnects the call (issue #1534). Kept in the
    /// mandatory exception list even when Phone.app is absent; the settings UI
    /// hides the row until the app is installed.
    package static let phoneBundleIdentifier = "com.apple.mobilephone"
    package static let mandatoryAutoQuitExceptionBundleIDs = [
        finderBundleIdentifier,
        phoneBundleIdentifier,
    ]

    package static let allowedDurations = [0, 15, 30, 60, 120, 240, 480]
    package static let allowedKeepAwakeMouseJiggleIntervals = [1, 2, 5, 10, 15]
    package static let allowedBatteryLimits = [0, 5, 10, 15, 20]
    package static let allowedMonitorIntervals = [1, 2, 5]
    package static let defaultKeyboardDebounceWindowMs = 5
    package static let defaultSnippetSoundName = "Tink"
    package static let allowedKeyboardDebounceWindowRange = 0...500
    /// Stepper increment for the keyboard debounce window. Kept at 1 ms so
    /// magnetic-keyboard users can pick values below the old 5 ms UI step
    /// without changing the stored range (issue #1551).
    package static let keyboardDebounceWindowStep = 1
    package static let defaultMouseClickDebounceWindowMs = 25
    package static let allowedMouseClickDebounceWindowRange = 5...100
    package static let allowedMenuBarPresets = ["dense"]
    package static let allowedMenuBarMetricSpacings = ["standard", "compact"]
    package static let allowedMenuBarMetricAppearances = ["values", "bars"]
    package static let defaultMenuBarMetricOrder = [
        "cpu", "cpuTemperature",
        "gpu", "gpuTemperature",
        "memory",
        "battery", "batteryTime", "batteryTemperature", "peripheralBattery",
        "network", "diskUsage", "diskActivity", "connectedDevices", "power", "fanSpeed",
    ]
    package static let allowedMenuBarLabelStyles = ["compact", "classic"]
    package static let allowedMenuBarMemoryStyles = ["dot", "percent", "both"]
    package static let allowedMonitorMemoryMetrics = ["used", "app"]
    package static let allowedPreviewSizes = ["small", "normal", "large", "xlarge"]
    package static let allowedClipboardHistoryLimits = [20, 50, 100, 250, 500, 1_000, 10_000, 0]
    package static let allowedClipboardAutoClearDelayRange = 5...3_600
    package static let defaultClipboardAutoClearDelay = 20
    package static let allowedClipboardMenuBarPreviewLengthRange = 5...50
    package static let defaultClipboardMenuBarPreviewLength = 20
    package static let allowedMonitorAlertCooldowns = [2, 5, 15, 30, 60]

    /// Property-list values that nothing mutates, so any thread may read them.
    nonisolated(unsafe) package static let registeredDefaults: [String: Any] = [
        DefaultsKey.appearance: Preferences.appearance.defaultValue,
        DefaultsKey.liquidGlassEnabled: Preferences.liquidGlassEnabled.defaultValue,
        DefaultsKey.notchLiquidGlassEnabled: Preferences.notchLiquidGlassEnabled.defaultValue,
        DefaultsKey.clamshellPreferred: Preferences.clamshellPreferred.defaultValue,
        DefaultsKey.dimScreenOnLidClose: Preferences.dimScreenOnLidClose.defaultValue,
        DefaultsKey.defaultDuration: Preferences.defaultDuration.defaultValue,
        DefaultsKey.batteryLimit: Preferences.batteryLimit.defaultValue,
        DefaultsKey.keepAwakeAutoStart: Preferences.keepAwakeAutoStart.defaultValue,
        DefaultsKey.keepAwakeRightClickToggle: Preferences.keepAwakeRightClickToggle.defaultValue,
        DefaultsKey.keepAwakeAllowDisplaySleep: Preferences.keepAwakeAllowDisplaySleep.defaultValue,
        DefaultsKey.keepAwakeExternalDisplay: Preferences.keepAwakeExternalDisplay.defaultValue,
        DefaultsKey.keepAwakeConnectedToPower: Preferences.keepAwakeConnectedToPower.defaultValue,
        DefaultsKey.keepAwakeRunningApps: Preferences.keepAwakeRunningApps.defaultValue,
        DefaultsKey.keepAwakeRunningAppBundleIDs: Preferences.keepAwakeRunningAppBundleIDs.defaultValue,
        DefaultsKey.keepAwakeAutomationRequireAll: Preferences.keepAwakeAutomationRequireAll.defaultValue,
        DefaultsKey.keepAwakePauseWhenLocked: Preferences.keepAwakePauseWhenLocked.defaultValue,
        DefaultsKey.keepAwakeSwitchUsesUntil: Preferences.keepAwakeSwitchUsesUntil.defaultValue,
        DefaultsKey.keepAwakeUntilTime: Preferences.keepAwakeUntilTime.defaultValue,
        DefaultsKey.keepAwakeMouseJiggleEnabled: Preferences.keepAwakeMouseJiggleEnabled.defaultValue,
        DefaultsKey.keepAwakeMouseJiggleInterval: Preferences.keepAwakeMouseJiggleInterval.defaultValue,
        DefaultsKey.hotkeyEnabled: Preferences.hotkeyEnabled.defaultValue,
        DefaultsKey.launchAtLoginWanted: Preferences.launchAtLoginWanted.defaultValue,
        DefaultsKey.keepAwakeShortcut: Preferences.keepAwakeShortcut.defaultValue,
        DefaultsKey.keepAwakeIconTint: Preferences.keepAwakeIconTint.defaultValue,
        DefaultsKey.keepAwakeActiveIcon: Preferences.keepAwakeActiveIcon.defaultValue,
        DefaultsKey.showCountdown: Preferences.showCountdown.defaultValue,
        DefaultsKey.scrollInverterEnabled: Preferences.scrollInverterEnabled.defaultValue,
        DefaultsKey.scrollInverterHorizontalEnabled: Preferences.scrollInverterHorizontalEnabled.defaultValue,
        DefaultsKey.scrollHorizontalEnabled: Preferences.scrollHorizontalEnabled.defaultValue,
        DefaultsKey.scrollHorizontalModifier: Preferences.scrollHorizontalModifier.defaultValue,
        DefaultsKey.focusFollowsMouseEnabled: Preferences.focusFollowsMouseEnabled.defaultValue,
        DefaultsKey.focusFollowsMouseRaise: Preferences.focusFollowsMouseRaise.defaultValue,
        DefaultsKey.focusFollowsMouseWaitForStop: Preferences.focusFollowsMouseWaitForStop.defaultValue,
        DefaultsKey.focusFollowsMouseDelay: Preferences.focusFollowsMouseDelay.defaultValue,
        DefaultsKey.smoothScrollEnabled: Preferences.smoothScrollEnabled.defaultValue,
        DefaultsKey.smoothScrollStep: Preferences.smoothScrollStep.defaultValue,
        DefaultsKey.linearScrollEnabled: Preferences.linearScrollEnabled.defaultValue,
        DefaultsKey.linearScrollLines: Preferences.linearScrollLines.defaultValue,
        DefaultsKey.mouseAccelerationDisabled: Preferences.mouseAccelerationDisabled.defaultValue,
        DefaultsKey.smoothScrollResponse: Preferences.smoothScrollResponse.defaultValue,
        DefaultsKey.smoothScrollCoast: Preferences.smoothScrollCoast.defaultValue,
        DefaultsKey.mouseNavigationEnabled: Preferences.mouseNavigationEnabled.defaultValue,
        DefaultsKey.mouseButtonShortcutsEnabled: Preferences.mouseButtonShortcutsEnabled.defaultValue,
        DefaultsKey.mouseButtonShortcuts: Preferences.mouseButtonShortcuts.defaultValue,
        DefaultsKey.mouseSpacesGestureEnabled: Preferences.mouseSpacesGestureEnabled.defaultValue,
        DefaultsKey.mouseSpacesGestureButton: Preferences.mouseSpacesGestureButton.defaultValue,
        DefaultsKey.mouseSpacesGestureFollowsDrag: Preferences.mouseSpacesGestureFollowsDrag.defaultValue,
        DefaultsKey.mouseClickDebounceEnabled: Preferences.mouseClickDebounceEnabled.defaultValue,
        DefaultsKey.mouseClickDebounceWindowMs: Preferences.mouseClickDebounceWindowMs.defaultValue,
        DefaultsKey.superKeyEnabled: Preferences.superKeyEnabled.defaultValue,
        DefaultsKey.superKeySource: Preferences.superKeySource.defaultValue,
        DefaultsKey.superKeyModifiers: Preferences.superKeyModifiers.defaultValue,
        DefaultsKey.superKeySoloAction: Preferences.superKeySoloAction.defaultValue,
        DefaultsKey.smoothScrollExceptions: Preferences.smoothScrollExceptions.defaultValue,
        DefaultsKey.linearScrollExceptions: Preferences.linearScrollExceptions.defaultValue,
        DefaultsKey.scrollInverterExceptions: Preferences.scrollInverterExceptions.defaultValue,
        DefaultsKey.focusFollowsMouseExceptions: Preferences.focusFollowsMouseExceptions.defaultValue,
        DefaultsKey.mouseNavigationExceptions: Preferences.mouseNavigationExceptions.defaultValue,
        DefaultsKey.mouseButtonExceptions: Preferences.mouseButtonExceptions.defaultValue,
        DefaultsKey.middleClickExceptions: Preferences.middleClickExceptions.defaultValue,
        DefaultsKey.superKeyExceptions: Preferences.superKeyExceptions.defaultValue,
        DefaultsKey.switcherEnabled: Preferences.switcherEnabled.defaultValue,
        DefaultsKey.switcherTakeOverSystemShortcuts: Preferences.switcherTakeOverSystemShortcuts.defaultValue,
        DefaultsKey.switcherShortcut: Preferences.switcherShortcut.defaultValue,
        DefaultsKey.switcherWindowShortcut: Preferences.switcherWindowShortcut.defaultValue,
        DefaultsKey.switcherIconRowMode: Preferences.switcherIconRowMode.defaultValue,
        DefaultsKey.switcherSimpleMode: Preferences.switcherSimpleMode.defaultValue,
        DefaultsKey.switcherMergeTabs: Preferences.switcherMergeTabs.defaultValue,
        DefaultsKey.switcherShowWindowlessFinder: Preferences.switcherShowWindowlessFinder.defaultValue,
        DefaultsKey.switcherWindowlessApps: Preferences.switcherWindowlessApps.defaultValue,
        DefaultsKey.switcherMinimizedPlacement: Preferences.switcherMinimizedPlacement.defaultValue,
        DefaultsKey.switcherTreatHiddenAppsLikeMinimized: Preferences.switcherTreatHiddenAppsLikeMinimized.defaultValue,
        DefaultsKey.switcherShowFullscreenWindows: Preferences.switcherShowFullscreenWindows.defaultValue,
        DefaultsKey.switcherAppRules: Preferences.switcherAppRules.defaultValue,
        DefaultsKey.switcherCurrentSpaceOnly: Preferences.switcherCurrentSpaceOnly.defaultValue,
        DefaultsKey.switcherSearchPinEnabled: Preferences.switcherSearchPinEnabled.defaultValue,
        DefaultsKey.switcherShowShortcutHints: Preferences.switcherShowShortcutHints.defaultValue,
        DefaultsKey.switcherAppearanceDelay: Preferences.switcherAppearanceDelay.defaultValue,
        DefaultsKey.switcherInstantSelection: Preferences.switcherInstantSelection.defaultValue,
        DefaultsKey.switcherScreenPlacement: Preferences.switcherScreenPlacement.defaultValue,
        DefaultsKey.switcherCurrentDisplayOnly: Preferences.switcherCurrentDisplayOnly.defaultValue,
        DefaultsKey.minimalWindowPreviews: Preferences.minimalWindowPreviews.defaultValue,
        DefaultsKey.dockPreviewEnabled: Preferences.dockPreviewEnabled.defaultValue,
        DefaultsKey.dockPreviewCurrentSpaceOnly: Preferences.dockPreviewCurrentSpaceOnly.defaultValue,
        DefaultsKey.dockPreviewKeepDockVisible: Preferences.dockPreviewKeepDockVisible.defaultValue,
        DefaultsKey.dockPreviewBackgroundOpacity: Preferences.dockPreviewBackgroundOpacity.defaultValue,
        DefaultsKey.dockPreviewOpenDelay: Preferences.dockPreviewOpenDelay.defaultValue,
        DefaultsKey.dockPreviewQuitAppOnClose: Preferences.dockPreviewQuitAppOnClose.defaultValue,
        DefaultsKey.dockPreviewOrderByCreation: Preferences.dockPreviewOrderByCreation.defaultValue,
        DefaultsKey.dockClickMinimize: Preferences.dockClickMinimize.defaultValue,
        DefaultsKey.dockClickHide: Preferences.dockClickHide.defaultValue,
        DefaultsKey.dockClickCycleWindows: Preferences.dockClickCycleWindows.defaultValue,
        DefaultsKey.spacesOrderEnabled: Preferences.spacesOrderEnabled.defaultValue,
        DefaultsKey.middleClickEnabled: Preferences.middleClickEnabled.defaultValue,
        DefaultsKey.middleClickTapFingers: Preferences.middleClickTapFingers.defaultValue,
        DefaultsKey.previewSize: Preferences.previewSize.defaultValue,
        DefaultsKey.switcherPreviewSize: Preferences.switcherPreviewSize.defaultValue,
        DefaultsKey.autoCheckUpdates: Preferences.autoCheckUpdates.defaultValue,
        DefaultsKey.includeBetaUpdates: Preferences.includeBetaUpdates.defaultValue,
        DefaultsKey.releaseNotesOnUpdate: Preferences.releaseNotesOnUpdate.defaultValue,
        DefaultsKey.updateShowcaseIntroVersion: Preferences.updateShowcaseIntroVersion.defaultValue,
        DefaultsKey.updateShowcaseMediaOverride: Preferences.updateShowcaseMediaOverride.defaultValue,
        DefaultsKey.mixerShowFinder: Preferences.mixerShowFinder.defaultValue,
        DefaultsKey.mixerHideInactiveApps: Preferences.mixerHideInactiveApps.defaultValue,
        DefaultsKey.mixerAppArrangement: Preferences.mixerAppArrangement.defaultValue,
        DefaultsKey.mixerLowerVolumeOnHeadphonesDisconnect: Preferences.mixerLowerVolumeOnHeadphonesDisconnect.defaultValue,
        DefaultsKey.mixerHeadphonesDisconnectVolumePercent: Preferences.mixerHeadphonesDisconnectVolumePercent.defaultValue,
        DefaultsKey.preciseVolumeRollerEnabled: Preferences.preciseVolumeRollerEnabled.defaultValue,
        DefaultsKey.soundOutputSwitcherEnabled: Preferences.soundOutputSwitcherEnabled.defaultValue,
        DefaultsKey.soundOutputSwitcherShortcut: Preferences.soundOutputSwitcherShortcut.defaultValue,
        // The feature itself ships uninstalled. On first install both halves
        // work immediately; an explicit off choice is persisted and wins over
        // these registered defaults on later launches or reinstalls.
        DefaultsKey.audioPriorityOutputEnabled: Preferences.audioPriorityOutputEnabled.defaultValue,
        DefaultsKey.audioPriorityInputEnabled: Preferences.audioPriorityInputEnabled.defaultValue,
        DefaultsKey.audioPriorityOutputUIDs: Preferences.audioPriorityOutputUIDs.defaultValue,
        DefaultsKey.audioPriorityInputUIDs: Preferences.audioPriorityInputUIDs.defaultValue,
        DefaultsKey.audioPriorityDeviceNames: Preferences.audioPriorityDeviceNames.defaultValue,
        // Finder never benefits from being "quit" (it just relaunches), so
        // it's excepted out of the box.
        DefaultsKey.autoQuitExceptions: Preferences.autoQuitExceptions.defaultValue,
        DefaultsKey.quitProtectionQuitEnabled: Preferences.quitProtectionQuitEnabled.defaultValue,
        DefaultsKey.quitProtectionQuitMode: Preferences.quitProtectionQuitMode.defaultValue,
        DefaultsKey.quitProtectionQuitHoldDurationMs: Preferences.quitProtectionQuitHoldDurationMs.defaultValue,
        DefaultsKey.quitProtectionQuitDoubleIntervalMs: Preferences.quitProtectionQuitDoubleIntervalMs.defaultValue,
        DefaultsKey.quitProtectionQuitExtraModifier: Preferences.quitProtectionQuitExtraModifier.defaultValue,
        DefaultsKey.quitProtectionQuitScope: Preferences.quitProtectionQuitScope.defaultValue,
        DefaultsKey.quitProtectionQuitExceptions: Preferences.quitProtectionQuitExceptions.defaultValue,
        DefaultsKey.quitProtectionQuitShowFeedback: Preferences.quitProtectionQuitShowFeedback.defaultValue,
        DefaultsKey.quitProtectionCloseEnabled: Preferences.quitProtectionCloseEnabled.defaultValue,
        DefaultsKey.quitProtectionCloseMode: Preferences.quitProtectionCloseMode.defaultValue,
        DefaultsKey.quitProtectionCloseHoldDurationMs: Preferences.quitProtectionCloseHoldDurationMs.defaultValue,
        DefaultsKey.quitProtectionCloseDoubleIntervalMs: Preferences.quitProtectionCloseDoubleIntervalMs.defaultValue,
        DefaultsKey.quitProtectionCloseExtraModifier: Preferences.quitProtectionCloseExtraModifier.defaultValue,
        DefaultsKey.quitProtectionCloseScope: Preferences.quitProtectionCloseScope.defaultValue,
        DefaultsKey.quitProtectionCloseExceptions: Preferences.quitProtectionCloseExceptions.defaultValue,
        DefaultsKey.quitProtectionCloseShowFeedback: Preferences.quitProtectionCloseShowFeedback.defaultValue,
        // When the shelf is on, the shake gesture is on too (still toggleable).
        DefaultsKey.shelfShortcutEnabled: Preferences.shelfShortcutEnabled.defaultValue,
        DefaultsKey.shelfShortcut: Preferences.shelfShortcut.defaultValue,
        DefaultsKey.shelfShakeToOpen: Preferences.shelfShakeToOpen.defaultValue,
        // On by default (owner's call): it costs nothing until the shelf itself
        // is on, and then the shelf lives handily under the menu bar icon.
        DefaultsKey.shelfDropZoneEnabled: Preferences.shelfDropZoneEnabled.defaultValue,
        DefaultsKey.shelfDockPlacement: Preferences.shelfDockPlacement.defaultValue,
        // New Shelf behavior stays opt-in for existing users.
        DefaultsKey.shelfEdgeDragEnabled: Preferences.shelfEdgeDragEnabled.defaultValue,
        // Closing after a drop is new behavior, so it arrives OFF for people
        // who already rely on the panel staying put; removing after a drop
        // keeps the value shipped releases always had.
        DefaultsKey.shelfCloseAfterDrop: Preferences.shelfCloseAfterDrop.defaultValue,
        DefaultsKey.shelfRemoveAfterDrop: Preferences.shelfRemoveAfterDrop.defaultValue,
        DefaultsKey.shelfClearOnClose: Preferences.shelfClearOnClose.defaultValue,
        DefaultsKey.shelfShortcutAddsFinderSelection: Preferences.shelfShortcutAddsFinderSelection.defaultValue,
        DefaultsKey.shelfAutomaticExclusions: Preferences.shelfAutomaticExclusions.defaultValue,
        DefaultsKey.extraBrightnessEnabled: Preferences.extraBrightnessEnabled.defaultValue,
        DefaultsKey.extraBrightnessLevel: Preferences.extraBrightnessLevel.defaultValue,
        DefaultsKey.brightnessControlEnabled: Preferences.brightnessControlEnabled.defaultValue,
        DefaultsKey.brightnessKeysEnabled: Preferences.brightnessKeysEnabled.defaultValue,
        DefaultsKey.brightnessOSDEnabled: Preferences.brightnessOSDEnabled.defaultValue,
        DefaultsKey.brightnessKeyStep: Preferences.brightnessKeyStep.defaultValue,
        DefaultsKey.displayBrightnessShortcutsEnabled: Preferences.displayBrightnessShortcutsEnabled.defaultValue,
        DefaultsKey.displayBrightnessDecreaseShortcut: Preferences.displayBrightnessDecreaseShortcut.defaultValue,
        DefaultsKey.displayBrightnessIncreaseShortcut: Preferences.displayBrightnessIncreaseShortcut.defaultValue,
        DefaultsKey.keyboardBrightnessShortcutsEnabled: Preferences.keyboardBrightnessShortcutsEnabled.defaultValue,
        DefaultsKey.keyboardBrightnessDecreaseShortcut: Preferences.keyboardBrightnessDecreaseShortcut.defaultValue,
        DefaultsKey.keyboardBrightnessIncreaseShortcut: Preferences.keyboardBrightnessIncreaseShortcut.defaultValue,
        DefaultsKey.bluetoothSleepEnabled: Preferences.bluetoothSleepEnabled.defaultValue,
        DefaultsKey.bluetoothSleepRestoreOnWake: Preferences.bluetoothSleepRestoreOnWake.defaultValue,
        DefaultsKey.bluetoothSleepRestorePending: Preferences.bluetoothSleepRestorePending.defaultValue,
        DefaultsKey.musicBlockEnabled: Preferences.musicBlockEnabled.defaultValue,
        DefaultsKey.musicBlockReplacementPath: Preferences.musicBlockReplacementPath.defaultValue,
        DefaultsKey.musicBlockPlayReplacement: Preferences.musicBlockPlayReplacement.defaultValue,
        DefaultsKey.cleanerScheduleFrequency: Preferences.cleanerScheduleFrequency.defaultValue,
        DefaultsKey.cleanerScheduleHour: Preferences.cleanerScheduleHour.defaultValue,
        DefaultsKey.cleanerScheduleMinute: Preferences.cleanerScheduleMinute.defaultValue,
        DefaultsKey.cleanerScheduleWeekday: Preferences.cleanerScheduleWeekday.defaultValue,
        DefaultsKey.cleanerScheduleNotify: Preferences.cleanerScheduleNotify.defaultValue,
        DefaultsKey.cleanerLastAutoRun: Preferences.cleanerLastAutoRun.defaultValue,
        DefaultsKey.cleanerLastAutoFreed: Preferences.cleanerLastAutoFreed.defaultValue,
        DefaultsKey.cleanerLastAutoFailed: Preferences.cleanerLastAutoFailed.defaultValue,
        DefaultsKey.cleanerScreenshotAgeDays: Preferences.cleanerScreenshotAgeDays.defaultValue,
        DefaultsKey.whatsAppDownloadsEnabled: Preferences.whatsAppDownloadsEnabled.defaultValue,
        DefaultsKey.whatsAppDownloadsAutomaticEnabled: Preferences.whatsAppDownloadsAutomaticEnabled.defaultValue,
        DefaultsKey.whatsAppDownloadsCategories: Preferences.whatsAppDownloadsCategories.defaultValue,
        DefaultsKey.whatsAppDownloadsRetentionDays: Preferences.whatsAppDownloadsRetentionDays.defaultValue,
        DefaultsKey.whatsAppDownloadsNotify: Preferences.whatsAppDownloadsNotify.defaultValue,
        DefaultsKey.whatsAppDownloadsIncludeExisting: Preferences.whatsAppDownloadsIncludeExisting.defaultValue,
        DefaultsKey.whatsAppDownloadsAutomaticStartDate: Preferences.whatsAppDownloadsAutomaticStartDate.defaultValue,
        DefaultsKey.whatsAppDownloadsLastAutoRun: Preferences.whatsAppDownloadsLastAutoRun.defaultValue,
        DefaultsKey.whatsAppDownloadsLastCleanup: Preferences.whatsAppDownloadsLastCleanup.defaultValue,
        DefaultsKey.whatsAppDownloadsLastCleanupCount: Preferences.whatsAppDownloadsLastCleanupCount.defaultValue,
        DefaultsKey.whatsAppDownloadsLastCleanupBytes: Preferences.whatsAppDownloadsLastCleanupBytes.defaultValue,
        DefaultsKey.whatsAppDownloadsLastCleanupFailed: Preferences.whatsAppDownloadsLastCleanupFailed.defaultValue,
        DefaultsKey.whatsAppDownloadsLastCleanupAutomatic: Preferences.whatsAppDownloadsLastCleanupAutomatic.defaultValue,
        DefaultsKey.whatsAppDownloadsExclusions: Preferences.whatsAppDownloadsExclusions.defaultValue,
        DefaultsKey.whatsAppDownloadsAccessConfirmed: Preferences.whatsAppDownloadsAccessConfirmed.defaultValue,
        DefaultsKey.whatsAppOrganizerEnabled: Preferences.whatsAppOrganizerEnabled.defaultValue,
        DefaultsKey.whatsAppOrganizerDestinationPath: Preferences.whatsAppOrganizerDestinationPath.defaultValue,
        DefaultsKey.whatsAppOrganizerDelayMinutes: Preferences.whatsAppOrganizerDelayMinutes.defaultValue,
        DefaultsKey.whatsAppOrganizerCategories: Preferences.whatsAppOrganizerCategories.defaultValue,
        DefaultsKey.whatsAppOrganizerLayout: Preferences.whatsAppOrganizerLayout.defaultValue,
        DefaultsKey.whatsAppOrganizerDuplicateAction: Preferences.whatsAppOrganizerDuplicateAction.defaultValue,
        DefaultsKey.whatsAppOrganizerRecords: Preferences.whatsAppOrganizerRecords.defaultValue,
        DefaultsKey.whatsAppOrganizerUndoTransaction: Preferences.whatsAppOrganizerUndoTransaction.defaultValue,
        DefaultsKey.whatsAppOrganizerLastRun: Preferences.whatsAppOrganizerLastRun.defaultValue,
        DefaultsKey.whatsAppOrganizerLastMoved: Preferences.whatsAppOrganizerLastMoved.defaultValue,
        DefaultsKey.whatsAppOrganizerLastDuplicates: Preferences.whatsAppOrganizerLastDuplicates.defaultValue,
        DefaultsKey.whatsAppOrganizerLastFailed: Preferences.whatsAppOrganizerLastFailed.defaultValue,
        DefaultsKey.urlCleanerEnabled: Preferences.urlCleanerEnabled.defaultValue,
        DefaultsKey.urlCleanerCustomParameters: Preferences.urlCleanerCustomParameters.defaultValue,
        DefaultsKey.urlCleanerSiteParameters: Preferences.urlCleanerSiteParameters.defaultValue,
        DefaultsKey.urlCleanerDisabledParameters: Preferences.urlCleanerDisabledParameters.defaultValue,
        DefaultsKey.textSnippetsEnabled: Preferences.textSnippetsEnabled.defaultValue,
        DefaultsKey.snippetLibraryEnabled: Preferences.snippetLibraryEnabled.defaultValue,
        DefaultsKey.snippetLibraryShortcut: Preferences.snippetLibraryShortcut.defaultValue,
        DefaultsKey.snippetSoundEnabled: Preferences.snippetSoundEnabled.defaultValue,
        DefaultsKey.snippetSoundName: Preferences.snippetSoundName.defaultValue,
        DefaultsKey.notchShowPlayingMusic: Preferences.notchShowPlayingMusic.defaultValue,
        DefaultsKey.notchIncludeOtherPlayers: Preferences.notchIncludeOtherPlayers.defaultValue,
        DefaultsKey.notchIdleContent: Preferences.notchIdleContent.defaultValue,
        DefaultsKey.notchHiddenControls: Preferences.notchHiddenControls.defaultValue,
        DefaultsKey.notchScratchpadControlHidden: Preferences.notchScratchpadControlHidden.defaultValue,
        DefaultsKey.notchKeyboardLightControlHidden: Preferences.notchKeyboardLightControlHidden.defaultValue,
        DefaultsKey.notchControlOrder: Preferences.notchControlOrder.defaultValue,
        DefaultsKey.notchSize: Preferences.notchSize.defaultValue,
        DefaultsKey.notchOutlineEnabled: Preferences.notchOutlineEnabled.defaultValue,
        DefaultsKey.notchCustomWidth: Preferences.notchCustomWidth.defaultValue,
        DefaultsKey.notchCustomHeight: Preferences.notchCustomHeight.defaultValue,
        DefaultsKey.notchCameraFitWidth: Preferences.notchCameraFitWidth.defaultValue,
        DefaultsKey.notchCameraFitHeight: Preferences.notchCameraFitHeight.defaultValue,
        DefaultsKey.notchHapticFeedback: Preferences.notchHapticFeedback.defaultValue,
        DefaultsKey.notchTranslucentBackground: Preferences.notchTranslucentBackground.defaultValue,
        DefaultsKey.notchShelf: Preferences.notchShelf.defaultValue,
        DefaultsKey.notchDragReveal: Preferences.notchDragReveal.defaultValue,
        DefaultsKey.notchCaptureControls: Preferences.notchCaptureControls.defaultValue,
        DefaultsKey.notchQuickPanel: Preferences.notchQuickPanel.defaultValue,
        DefaultsKey.notchAppPanel: Preferences.notchAppPanel.defaultValue,
        DefaultsKey.notchHidesMenuBarIcon: Preferences.notchHidesMenuBarIcon.defaultValue,
        DefaultsKey.notchKeepAwakeActivity: Preferences.notchKeepAwakeActivity.defaultValue,
        DefaultsKey.notchScratchpad: Preferences.notchScratchpad.defaultValue,
        DefaultsKey.notchHoverExpands: Preferences.notchHoverExpands.defaultValue,
        DefaultsKey.notchGesturesEnabled: Preferences.notchGesturesEnabled.defaultValue,
        DefaultsKey.notchKeyboardLight: Preferences.notchKeyboardLight.defaultValue,
        DefaultsKey.notchNotificationsEnabled: Preferences.notchNotificationsEnabled.defaultValue,
        DefaultsKey.notchDismissNativeNotifications: Preferences.notchDismissNativeNotifications.defaultValue,
        DefaultsKey.notchTimerEnabled: Preferences.notchTimerEnabled.defaultValue,
        DefaultsKey.notchTimerMode: Preferences.notchTimerMode.defaultValue,
        DefaultsKey.notchTimerSoundEnabled: Preferences.notchTimerSoundEnabled.defaultValue,
        DefaultsKey.notchHideTimerCountdown: Preferences.notchHideTimerCountdown.defaultValue,
        DefaultsKey.notchTimerMinutes: Preferences.notchTimerMinutes.defaultValue,
        DefaultsKey.notchPomodoroFocusMinutes: Preferences.notchPomodoroFocusMinutes.defaultValue,
        DefaultsKey.notchPomodoroShortBreakMinutes: Preferences.notchPomodoroShortBreakMinutes.defaultValue,
        DefaultsKey.notchPomodoroLongBreakMinutes: Preferences.notchPomodoroLongBreakMinutes.defaultValue,
        DefaultsKey.notchPomodoroLongBreakInterval: Preferences.notchPomodoroLongBreakInterval.defaultValue,
        DefaultsKey.notchPomodoroTotalSessions: Preferences.notchPomodoroTotalSessions.defaultValue,
        DefaultsKey.notchCameraEnabled: Preferences.notchCameraEnabled.defaultValue,
        DefaultsKey.notchAccessoriesEnabled: Preferences.notchAccessoriesEnabled.defaultValue,
        DefaultsKey.notchCalendarEnabled: Preferences.notchCalendarEnabled.defaultValue,
        DefaultsKey.notchCalendarCountdown: Preferences.notchCalendarCountdown.defaultValue,
        DefaultsKey.notchCalendarTimeLeft: Preferences.notchCalendarTimeLeft.defaultValue,
        DefaultsKey.notchCalendarExcluded: Preferences.notchCalendarExcluded.defaultValue,
        DefaultsKey.notchAgentsEnabled: Preferences.notchAgentsEnabled.defaultValue,
        DefaultsKey.notchAgentsClaude: Preferences.notchAgentsClaude.defaultValue,
        DefaultsKey.notchAgentsCodex: Preferences.notchAgentsCodex.defaultValue,
        DefaultsKey.notchAgentsOpenCode: Preferences.notchAgentsOpenCode.defaultValue,
        DefaultsKey.notchAgentsCopilot: Preferences.notchAgentsCopilot.defaultValue,
        DefaultsKey.notchAgentsCardOrder: Preferences.notchAgentsCardOrder.defaultValue,
        DefaultsKey.notchAgentsHiddenCards: Preferences.notchAgentsHiddenCards.defaultValue,
        DefaultsKey.notchAgentsPeriod: Preferences.notchAgentsPeriod.defaultValue,
        DefaultsKey.notchAgentsLimitDisplay: Preferences.notchAgentsLimitDisplay.defaultValue,
        DefaultsKey.notchAgentsLimitFocus: Preferences.notchAgentsLimitFocus.defaultValue,
        DefaultsKey.notchAgentsLiveActivity: Preferences.notchAgentsLiveActivity.defaultValue,
        DefaultsKey.notchAgentsReadout: Preferences.notchAgentsReadout.defaultValue,
        DefaultsKey.notchAgentsFinishAlert: Preferences.notchAgentsFinishAlert.defaultValue,
        DefaultsKey.notchAgentsFinishMinimum: Preferences.notchAgentsFinishMinimum.defaultValue,
        DefaultsKey.notchAgentsLimitAlert: Preferences.notchAgentsLimitAlert.defaultValue,
        DefaultsKey.notchAgentsLimitThreshold: Preferences.notchAgentsLimitThreshold.defaultValue,
        DefaultsKey.notchAgentsDailyBudget: Preferences.notchAgentsDailyBudget.defaultValue,
        DefaultsKey.notchAgentsPriceUpdates: Preferences.notchAgentsPriceUpdates.defaultValue,
        DefaultsKey.notchLyricsEnabled: Preferences.notchLyricsEnabled.defaultValue,
        DefaultsKey.notchLyricsOnline: Preferences.notchLyricsOnline.defaultValue,
        DefaultsKey.notchLiveEqualizer: Preferences.notchLiveEqualizer.defaultValue,
        DefaultsKey.notchQueueEnabled: Preferences.notchQueueEnabled.defaultValue,
        DefaultsKey.notchDownloadsEnabled: Preferences.notchDownloadsEnabled.defaultValue,
        DefaultsKey.notchWatchEnabled: Preferences.notchWatchEnabled.defaultValue,
        DefaultsKey.notchWatchSound: Preferences.notchWatchSound.defaultValue,
        DefaultsKey.notchWatchCondition: Preferences.notchWatchCondition.defaultValue,
        DefaultsKey.notchEnabled: Preferences.notchEnabled.defaultValue,
        DefaultsKey.notchDisplay: Preferences.notchDisplay.defaultValue,
        DefaultsKey.notchSilhouette: Preferences.notchSilhouette.defaultValue,
        DefaultsKey.notchCapsuleFitWidth: Preferences.notchCapsuleFitWidth.defaultValue,
        DefaultsKey.notchCapsuleFitHeight: Preferences.notchCapsuleFitHeight.defaultValue,
        DefaultsKey.notchCapsuleFitDrop: Preferences.notchCapsuleFitDrop.defaultValue,
        DefaultsKey.notchOpenOnHover: Preferences.notchOpenOnHover.defaultValue,
        DefaultsKey.notchHideInFullscreen: Preferences.notchHideInFullscreen.defaultValue,
        DefaultsKey.notchHideUntilHover: Preferences.notchHideUntilHover.defaultValue,
        DefaultsKey.notchCoversMenus: Preferences.notchCoversMenus.defaultValue,
        DefaultsKey.notchHoverDelay: Preferences.notchHoverDelay.defaultValue,
        DefaultsKey.notchReturnHome: Preferences.notchReturnHome.defaultValue,
        DefaultsKey.notchHomeModule: Preferences.notchHomeModule.defaultValue,
        DefaultsKey.notchOpensActivity: Preferences.notchOpensActivity.defaultValue,
        DefaultsKey.notchHiddenModules: Preferences.notchHiddenModules.defaultValue,
        DefaultsKey.notchModuleOrder: Preferences.notchModuleOrder.defaultValue,
        DefaultsKey.notchQuickAccessLayout: Preferences.notchQuickAccessLayout.defaultValue,
        DefaultsKey.notchVolume: Preferences.notchVolume.defaultValue,
        DefaultsKey.notchMicrophone: Preferences.notchMicrophone.defaultValue,
        DefaultsKey.notchBrightness: Preferences.notchBrightness.defaultValue,
        DefaultsKey.notchBattery: Preferences.notchBattery.defaultValue,
        DefaultsKey.notchClipboard: Preferences.notchClipboard.defaultValue,
        DefaultsKey.notchClipboardWindow: Preferences.notchClipboardWindow.defaultValue,
        DefaultsKey.notchCapture: Preferences.notchCapture.defaultValue,
        DefaultsKey.notchTrackChange: Preferences.notchTrackChange.defaultValue,
        DefaultsKey.notchMusicActivity: Preferences.notchMusicActivity.defaultValue,
        DefaultsKey.notchShowInCaptures: Preferences.notchShowInCaptures.defaultValue,
        DefaultsKey.notchLockScreen: Preferences.notchLockScreen.defaultValue,
        DefaultsKey.notchLockSounds: Preferences.notchLockSounds.defaultValue,
        DefaultsKey.notchMascotEnabled: Preferences.notchMascotEnabled.defaultValue,
        DefaultsKey.notchMascotVisits: Preferences.notchMascotVisits.defaultValue,
        DefaultsKey.notchMascotReactions: Preferences.notchMascotReactions.defaultValue,
        DefaultsKey.notchMascotStyle: Preferences.notchMascotStyle.defaultValue,
        DefaultsKey.notchMascotShape: Preferences.notchMascotShape.defaultValue,
        DefaultsKey.notchMascotPalette: Preferences.notchMascotPalette.defaultValue,
        DefaultsKey.notchMascotSide: Preferences.notchMascotSide.defaultValue,
        DefaultsKey.notchMascotVisitFrequency: Preferences.notchMascotVisitFrequency.defaultValue,
        DefaultsKey.notchCommandBar: Preferences.notchCommandBar.defaultValue,
        DefaultsKey.notchCommandBarStyle: Preferences.notchCommandBarStyle.defaultValue,
        DefaultsKey.notchHideInCaptures: Preferences.notchHideInCaptures.defaultValue,
        DefaultsKey.panelControlNotch: Preferences.panelControlNotch.defaultValue,
        DefaultsKey.radialMenuEnabled: Preferences.radialMenuEnabled.defaultValue,
        DefaultsKey.radialMenuShortcut: Preferences.radialMenuShortcut.defaultValue,
        DefaultsKey.radialMenuAtPointer: Preferences.radialMenuAtPointer.defaultValue,
        DefaultsKey.radialMenuMouseButton: Preferences.radialMenuMouseButton.defaultValue,
        DefaultsKey.radialMenuActivationMode: Preferences.radialMenuActivationMode.defaultValue,
        DefaultsKey.windowMaximizeEnabled: Preferences.windowMaximizeEnabled.defaultValue,
        DefaultsKey.windowMaximizeExcludedApps: Preferences.windowMaximizeExcludedApps.defaultValue,
        DefaultsKey.keyboardDebounceEnabled: Preferences.keyboardDebounceEnabled.defaultValue,
        DefaultsKey.keyboardDebounceWindowMs: Preferences.keyboardDebounceWindowMs.defaultValue,
        DefaultsKey.keyboardDebounceKeyWindows: Preferences.keyboardDebounceKeyWindows.defaultValue,
        DefaultsKey.panelUtilityCleaning: Preferences.panelUtilityCleaning.defaultValue,
        DefaultsKey.cleaningModeKeepScreenVisible: Preferences.cleaningModeKeepScreenVisible.defaultValue,
        DefaultsKey.panelUtilityURLCleaner: Preferences.panelUtilityURLCleaner.defaultValue,
        DefaultsKey.panelUtilityUninstaller: Preferences.panelUtilityUninstaller.defaultValue,
        DefaultsKey.uninstallerCommandBarEnabled: Preferences.uninstallerCommandBarEnabled.defaultValue,
        DefaultsKey.killProcessCommandBarEnabled: Preferences.killProcessCommandBarEnabled.defaultValue,
        DefaultsKey.killProcessGroupRelated: Preferences.killProcessGroupRelated.defaultValue,
        DefaultsKey.killProcessSortBy: Preferences.killProcessSortBy.defaultValue,
        DefaultsKey.killProcessSortAscending: Preferences.killProcessSortAscending.defaultValue,
        DefaultsKey.panelUtilityCleaner: Preferences.panelUtilityCleaner.defaultValue,
        DefaultsKey.panelUtilityHomebrew: Preferences.panelUtilityHomebrew.defaultValue,
        DefaultsKey.homebrewGroupDependencies: Preferences.homebrewGroupDependencies.defaultValue,
        DefaultsKey.panelUtilityAppUpdates: Preferences.panelUtilityAppUpdates.defaultValue,
        // The list itself costs nothing until it is opened; only the
        // background check keeps a timer, so it starts off.
        DefaultsKey.appUpdatesCheckFrequency: Preferences.appUpdatesCheckFrequency.defaultValue,
        DefaultsKey.appUpdatesIncludeHomebrewApps: Preferences.appUpdatesIncludeHomebrewApps.defaultValue,
        DefaultsKey.appUpdatesIncludeAppStore: Preferences.appUpdatesIncludeAppStore.defaultValue,
        DefaultsKey.appUpdatesIncludeOnlineCatalog: Preferences.appUpdatesIncludeOnlineCatalog.defaultValue,
        DefaultsKey.appUpdatesNotify: Preferences.appUpdatesNotify.defaultValue,
        DefaultsKey.appUpdatesRules: Preferences.appUpdatesRules.defaultValue,
        DefaultsKey.appUpdatesLastCheck: Preferences.appUpdatesLastCheck.defaultValue,
        DefaultsKey.appUpdatesLastCount: Preferences.appUpdatesLastCount.defaultValue,
        DefaultsKey.appUpdatesNotifiedIDs: Preferences.appUpdatesNotifiedIDs.defaultValue,
        DefaultsKey.panelUtilityMedia: Preferences.panelUtilityMedia.defaultValue,
        DefaultsKey.panelUtilityClipboard: Preferences.panelUtilityClipboard.defaultValue,
        DefaultsKey.panelUtilityWindowLayout: Preferences.panelUtilityWindowLayout.defaultValue,
        DefaultsKey.panelControlMouseScroll: Preferences.panelControlMouseScroll.defaultValue,
        DefaultsKey.panelControlFocusFollowsMouse: Preferences.panelControlFocusFollowsMouse.defaultValue,
        DefaultsKey.panelControlMouseNavigation: Preferences.panelControlMouseNavigation.defaultValue,
        DefaultsKey.panelControlSwitcher: Preferences.panelControlSwitcher.defaultValue,
        DefaultsKey.panelControlDockPreview: Preferences.panelControlDockPreview.defaultValue,
        DefaultsKey.panelControlCutPaste: Preferences.panelControlCutPaste.defaultValue,
        DefaultsKey.panelControlAutoQuit: Preferences.panelControlAutoQuit.defaultValue,
        DefaultsKey.panelControlShelf: Preferences.panelControlShelf.defaultValue,
        DefaultsKey.panelControlWindowMaximize: Preferences.panelControlWindowMaximize.defaultValue,
        DefaultsKey.panelControlKeyDebounce: Preferences.panelControlKeyDebounce.defaultValue,
        DefaultsKey.panelControlDockClick: Preferences.panelControlDockClick.defaultValue,
        DefaultsKey.panelControlDockClickHide: Preferences.panelControlDockClickHide.defaultValue,
        DefaultsKey.panelControlDockClickCycle: Preferences.panelControlDockClickCycle.defaultValue,
        DefaultsKey.panelControlMiddleClick: Preferences.panelControlMiddleClick.defaultValue,
        DefaultsKey.panelControlTextSnippets: Preferences.panelControlTextSnippets.defaultValue,
        DefaultsKey.panelControlSuperKey: Preferences.panelControlSuperKey.defaultValue,
        DefaultsKey.panelControlRadialMenu: Preferences.panelControlRadialMenu.defaultValue,
        DefaultsKey.panelControlMouseButtonShortcuts: Preferences.panelControlMouseButtonShortcuts.defaultValue,
        DefaultsKey.panelControlMouseAcceleration: Preferences.panelControlMouseAcceleration.defaultValue,
        DefaultsKey.panelControlLinearScroll: Preferences.panelControlLinearScroll.defaultValue,
        DefaultsKey.panelControlMouseClickDebounce: Preferences.panelControlMouseClickDebounce.defaultValue,
        DefaultsKey.panelControlSpacesOrder: Preferences.panelControlSpacesOrder.defaultValue,
        DefaultsKey.panelControlWindowsExpanded: Preferences.panelControlWindowsExpanded.defaultValue,
        DefaultsKey.panelControlInputExpanded: Preferences.panelControlInputExpanded.defaultValue,
        DefaultsKey.panelControlFilesExpanded: Preferences.panelControlFilesExpanded.defaultValue,
        DefaultsKey.panelShowKeepAwake: Preferences.panelShowKeepAwake.defaultValue,
        DefaultsKey.panelShowBrightness: Preferences.panelShowBrightness.defaultValue,
        DefaultsKey.panelShowUtilities: Preferences.panelShowUtilities.defaultValue,
        DefaultsKey.panelShowControls: Preferences.panelShowControls.defaultValue,
        DefaultsKey.panelShowToggles: Preferences.panelShowToggles.defaultValue,
        DefaultsKey.panelShowWallpaper: Preferences.panelShowWallpaper.defaultValue,
        DefaultsKey.panelToggleDarkMode: Preferences.panelToggleDarkMode.defaultValue,
        DefaultsKey.panelToggleKeyboardLight: Preferences.panelToggleKeyboardLight.defaultValue,
        DefaultsKey.panelToggleMicMute: Preferences.panelToggleMicMute.defaultValue,
        DefaultsKey.panelToggleEmptyTrash: Preferences.panelToggleEmptyTrash.defaultValue,
        DefaultsKey.panelToggleEjectDisks: Preferences.panelToggleEjectDisks.defaultValue,
        DefaultsKey.panelToggleHiddenFiles: Preferences.panelToggleHiddenFiles.defaultValue,
        DefaultsKey.panelToggleDesktopIcons: Preferences.panelToggleDesktopIcons.defaultValue,
        DefaultsKey.panelToggleLockScreen: Preferences.panelToggleLockScreen.defaultValue,
        DefaultsKey.panelToggleDisplayOff: Preferences.panelToggleDisplayOff.defaultValue,
        DefaultsKey.panelToggleScreenSaver: Preferences.panelToggleScreenSaver.defaultValue,
        // Menu bar metrics start off (the icon stays clean) and are opt-in.
        // The panel shows every monitoring block by default; users hide what
        // they don't want.
        DefaultsKey.monitorInterval: Preferences.monitorInterval.defaultValue,
        DefaultsKey.temperatureUnit: Preferences.temperatureUnit.defaultValue,
        DefaultsKey.menuBarCPUTemperature: Preferences.menuBarCPUTemperature.defaultValue,
        DefaultsKey.menuBarGPUTemperature: Preferences.menuBarGPUTemperature.defaultValue,
        DefaultsKey.menuBarBatteryTemperature: Preferences.menuBarBatteryTemperature.defaultValue,
        DefaultsKey.menuBarBatteryTime: Preferences.menuBarBatteryTime.defaultValue,
        DefaultsKey.menuBarDiskUsage: Preferences.menuBarDiskUsage.defaultValue,
        DefaultsKey.menuBarDiskActivity: Preferences.menuBarDiskActivity.defaultValue,
        DefaultsKey.menuBarPeripheralBattery: Preferences.menuBarPeripheralBattery.defaultValue,
        DefaultsKey.menuBarConnectedDevices: Preferences.menuBarConnectedDevices.defaultValue,
        DefaultsKey.menuBarFanSpeed: Preferences.menuBarFanSpeed.defaultValue,
        DefaultsKey.menuBarPreset: Preferences.menuBarPreset.defaultValue,
        DefaultsKey.menuBarMetricSpacing: Preferences.menuBarMetricSpacing.defaultValue,
        DefaultsKey.menuBarMetricAppearance: Preferences.menuBarMetricAppearance.defaultValue,
        DefaultsKey.menuBarUsageBarNormalColor: Preferences.menuBarUsageBarNormalColor.defaultValue,
        DefaultsKey.menuBarUsageBarElevatedColor: Preferences.menuBarUsageBarElevatedColor.defaultValue,
        DefaultsKey.menuBarUsageBarCriticalColor: Preferences.menuBarUsageBarCriticalColor.defaultValue,
        DefaultsKey.menuBarUsageBarMediumThreshold: Preferences.menuBarUsageBarMediumThreshold.defaultValue,
        DefaultsKey.menuBarUsageBarHighThreshold: Preferences.menuBarUsageBarHighThreshold.defaultValue,
        DefaultsKey.menuBarHideIconWithMetrics: Preferences.menuBarHideIconWithMetrics.defaultValue,
        DefaultsKey.menuBarIconSymbol: Preferences.menuBarIconSymbol.defaultValue,
        DefaultsKey.windowLayoutHiddenActions: Preferences.windowLayoutHiddenActions.defaultValue,
        DefaultsKey.windowLayoutWindowGap: Preferences.windowLayoutWindowGap.defaultValue,
        DefaultsKey.windowLayoutScreenGap: Preferences.windowLayoutScreenGap.defaultValue,
        DefaultsKey.windowLayoutMarginPercent: Preferences.windowLayoutMarginPercent.defaultValue,
        DefaultsKey.windowLayoutSideRepeatCyclesThirds: Preferences.windowLayoutSideRepeatCyclesThirds.defaultValue,
        DefaultsKey.menuBarMetricOrder: Preferences.menuBarMetricOrder.defaultValue,
        DefaultsKey.menuBarCombineTemperatures: Preferences.menuBarCombineTemperatures.defaultValue,
        DefaultsKey.menuBarSeparateMetrics: Preferences.menuBarSeparateMetrics.defaultValue,
        DefaultsKey.menuBarNetworkUploadFirst: Preferences.menuBarNetworkUploadFirst.defaultValue,
        DefaultsKey.menuBarLabelStyle: Preferences.menuBarLabelStyle.defaultValue,
        DefaultsKey.menuBarMemoryStyle: Preferences.menuBarMemoryStyle.defaultValue,
        DefaultsKey.menuBarDiskStyle: Preferences.menuBarDiskStyle.defaultValue,
        DefaultsKey.monitorMemoryMetric: Preferences.monitorMemoryMetric.defaultValue,
        DefaultsKey.monitorShowSystem: Preferences.monitorShowSystem.defaultValue,
        DefaultsKey.monitorShowNetwork: Preferences.monitorShowNetwork.defaultValue,
        DefaultsKey.monitorShowDisk: Preferences.monitorShowDisk.defaultValue,
        DefaultsKey.monitorShowPower: Preferences.monitorShowPower.defaultValue,
        DefaultsKey.monitorShowMixer: Preferences.monitorShowMixer.defaultValue,
        DefaultsKey.panelShowFanControl: Preferences.panelShowFanControl.defaultValue,
        DefaultsKey.fanControlMode: Preferences.fanControlMode.defaultValue,
        DefaultsKey.fanControlCoolingLevel: Preferences.fanControlCoolingLevel.defaultValue,
        DefaultsKey.fanControlCurves: Preferences.fanControlCurves.defaultValue,
        DefaultsKey.fanControlResume: Preferences.fanControlResume.defaultValue,
        DefaultsKey.fanControlResumeConfiguration: Preferences.fanControlResumeConfiguration.defaultValue,
        DefaultsKey.fanControlRecoveryNeeded: Preferences.fanControlRecoveryNeeded.defaultValue,
        DefaultsKey.fanControlHelperVersion: Preferences.fanControlHelperVersion.defaultValue,
        DefaultsKey.panelNavigationEnabled: Preferences.panelNavigationEnabled.defaultValue,
        DefaultsKey.monitorGraphCPU: Preferences.monitorGraphCPU.defaultValue,
        DefaultsKey.monitorGraphGPU: Preferences.monitorGraphGPU.defaultValue,
        DefaultsKey.monitorGraphMemory: Preferences.monitorGraphMemory.defaultValue,
        DefaultsKey.monitorGraphNetwork: Preferences.monitorGraphNetwork.defaultValue,
        DefaultsKey.monitorGraphDisk: Preferences.monitorGraphDisk.defaultValue,
        DefaultsKey.monitorGraphPower: Preferences.monitorGraphPower.defaultValue,
        DefaultsKey.monitorGraphBattery: Preferences.monitorGraphBattery.defaultValue,
        DefaultsKey.monitorGraphScale: Preferences.monitorGraphScale.defaultValue,
        // Every per-item block shows by default; users hide what they don't want.
        DefaultsKey.monitorSysTemps: Preferences.monitorSysTemps.defaultValue,
        DefaultsKey.monitorSysCPU: Preferences.monitorSysCPU.defaultValue,
        DefaultsKey.monitorSysGPU: Preferences.monitorSysGPU.defaultValue,
        DefaultsKey.monitorSysBattery: Preferences.monitorSysBattery.defaultValue,
        DefaultsKey.monitorSysMemory: Preferences.monitorSysMemory.defaultValue,
        DefaultsKey.monitorSysAlerts: Preferences.monitorSysAlerts.defaultValue,
        DefaultsKey.monitorSysUptime: Preferences.monitorSysUptime.defaultValue,
        DefaultsKey.monitorNetSpeed: Preferences.monitorNetSpeed.defaultValue,
        DefaultsKey.monitorNetApps: Preferences.monitorNetApps.defaultValue,
        DefaultsKey.monitorNetTotals: Preferences.monitorNetTotals.defaultValue,
        DefaultsKey.monitorNetAddresses: Preferences.monitorNetAddresses.defaultValue,
        DefaultsKey.monitorNetTest: Preferences.monitorNetTest.defaultValue,
        DefaultsKey.monitorDiskUsage: Preferences.monitorDiskUsage.defaultValue,
        DefaultsKey.monitorDiskActivity: Preferences.monitorDiskActivity.defaultValue,
        DefaultsKey.monitorDiskSMART: Preferences.monitorDiskSMART.defaultValue,
        DefaultsKey.monitorDiskProtection: Preferences.monitorDiskProtection.defaultValue,
        DefaultsKey.monitorDiskTools: Preferences.monitorDiskTools.defaultValue,
        DefaultsKey.monitorPwrTemperature: Preferences.monitorPwrTemperature.defaultValue,
        DefaultsKey.monitorPwrSystem: Preferences.monitorPwrSystem.defaultValue,
        DefaultsKey.monitorPwrAdapter: Preferences.monitorPwrAdapter.defaultValue,
        DefaultsKey.monitorPwrBattery: Preferences.monitorPwrBattery.defaultValue,
        DefaultsKey.monitorPwrTimeRemaining: Preferences.monitorPwrTimeRemaining.defaultValue,
        DefaultsKey.monitorPwrHealth: Preferences.monitorPwrHealth.defaultValue,
        DefaultsKey.monitorAlertCPU: Preferences.monitorAlertCPU.defaultValue,
        DefaultsKey.monitorAlertCPUTemperature: Preferences.monitorAlertCPUTemperature.defaultValue,
        DefaultsKey.monitorAlertBatteryTemperature: Preferences.monitorAlertBatteryTemperature.defaultValue,
        DefaultsKey.monitorAlertMemory: Preferences.monitorAlertMemory.defaultValue,
        DefaultsKey.monitorAlertDisk: Preferences.monitorAlertDisk.defaultValue,
        DefaultsKey.monitorAlertBattery: Preferences.monitorAlertBattery.defaultValue,
        DefaultsKey.monitorAlertCPUThreshold: Preferences.monitorAlertCPUThreshold.defaultValue,
        DefaultsKey.monitorAlertCPUTemperatureThreshold: Preferences.monitorAlertCPUTemperatureThreshold.defaultValue,
        DefaultsKey.monitorAlertBatteryTemperatureThreshold: Preferences.monitorAlertBatteryTemperatureThreshold.defaultValue,
        DefaultsKey.monitorAlertDiskFreePercent: Preferences.monitorAlertDiskFreePercent.defaultValue,
        DefaultsKey.monitorAlertBatteryPercent: Preferences.monitorAlertBatteryPercent.defaultValue,
        DefaultsKey.monitorAlertCooldownMinutes: Preferences.monitorAlertCooldownMinutes.defaultValue,
        DefaultsKey.mediaLastTool: Preferences.mediaLastTool.defaultValue,
        DefaultsKey.mediaVideoStart: Preferences.mediaVideoStart.defaultValue,
        DefaultsKey.mediaVideoEnd: Preferences.mediaVideoEnd.defaultValue,
        DefaultsKey.mediaVideoQuality: Preferences.mediaVideoQuality.defaultValue,
        DefaultsKey.mediaVideoMaxDimension: Preferences.mediaVideoMaxDimension.defaultValue,
        DefaultsKey.mediaVideoFPS: Preferences.mediaVideoFPS.defaultValue,
        DefaultsKey.mediaVideoKeepAudio: Preferences.mediaVideoKeepAudio.defaultValue,
        DefaultsKey.mediaVideoCodec: Preferences.mediaVideoCodec.defaultValue,
        DefaultsKey.mediaVideoSizing: Preferences.mediaVideoSizing.defaultValue,
        DefaultsKey.mediaVideoTargetMegabytes: Preferences.mediaVideoTargetMegabytes.defaultValue,
        DefaultsKey.mediaGIFStart: Preferences.mediaGIFStart.defaultValue,
        DefaultsKey.mediaGIFEnd: Preferences.mediaGIFEnd.defaultValue,
        DefaultsKey.mediaGIFQuality: Preferences.mediaGIFQuality.defaultValue,
        DefaultsKey.mediaGIFWidth: Preferences.mediaGIFWidth.defaultValue,
        DefaultsKey.mediaGIFFPS: Preferences.mediaGIFFPS.defaultValue,
        DefaultsKey.mediaGIFLoops: Preferences.mediaGIFLoops.defaultValue,
        DefaultsKey.mediaGIFSizing: Preferences.mediaGIFSizing.defaultValue,
        DefaultsKey.mediaGIFTargetMegabytes: Preferences.mediaGIFTargetMegabytes.defaultValue,
        DefaultsKey.mediaImageQuality: Preferences.mediaImageQuality.defaultValue,
        DefaultsKey.mediaImageMaxDimension: Preferences.mediaImageMaxDimension.defaultValue,
        DefaultsKey.mediaImageFormat: Preferences.mediaImageFormat.defaultValue,
        DefaultsKey.mediaImageStripMetadata: Preferences.mediaImageStripMetadata.defaultValue,
        DefaultsKey.mediaImageResizeKind: Preferences.mediaImageResizeKind.defaultValue,
        DefaultsKey.mediaImageResizeWidth: Preferences.mediaImageResizeWidth.defaultValue,
        DefaultsKey.mediaImageResizeHeight: Preferences.mediaImageResizeHeight.defaultValue,
        DefaultsKey.mediaImageExactResizeMode: Preferences.mediaImageExactResizeMode.defaultValue,
        DefaultsKey.mediaImageWatermarkKind: Preferences.mediaImageWatermarkKind.defaultValue,
        DefaultsKey.mediaImageWatermarkText: Preferences.mediaImageWatermarkText.defaultValue,
        DefaultsKey.mediaImageWatermarkLogoPath: Preferences.mediaImageWatermarkLogoPath.defaultValue,
        DefaultsKey.mediaImageWatermarkPosition: Preferences.mediaImageWatermarkPosition.defaultValue,
        DefaultsKey.mediaImageWatermarkOpacity: Preferences.mediaImageWatermarkOpacity.defaultValue,
        DefaultsKey.mediaImageWatermarkMargin: Preferences.mediaImageWatermarkMargin.defaultValue,
        DefaultsKey.mediaImageWatermarkScale: Preferences.mediaImageWatermarkScale.defaultValue,
        DefaultsKey.mediaImageRenamePattern: Preferences.mediaImageRenamePattern.defaultValue,
        DefaultsKey.mediaImageBackground: Preferences.mediaImageBackground.defaultValue,
        DefaultsKey.mediaImagePreserveModificationDate: Preferences.mediaImagePreserveModificationDate.defaultValue,
        DefaultsKey.mediaImageSaveInSubfolder: Preferences.mediaImageSaveInSubfolder.defaultValue,
        DefaultsKey.mediaImageProfiles: Preferences.mediaImageProfiles.defaultValue,
        DefaultsKey.mediaImageSelectedProfileID: Preferences.mediaImageSelectedProfileID.defaultValue,
        DefaultsKey.mediaTextAccurate: Preferences.mediaTextAccurate.defaultValue,
        DefaultsKey.mediaTextLanguageCorrection: Preferences.mediaTextLanguageCorrection.defaultValue,
        DefaultsKey.clipboardHistoryEnabled: Preferences.clipboardHistoryEnabled.defaultValue,
        DefaultsKey.clipboardHistoryLimit: Preferences.clipboardHistoryLimit.defaultValue,
        DefaultsKey.clipboardHistorySkipSensitive: Preferences.clipboardHistorySkipSensitive.defaultValue,
        DefaultsKey.clipboardHistoryIncludeImagesFiles: Preferences.clipboardHistoryIncludeImagesFiles.defaultValue,
        DefaultsKey.clipboardHistoryIgnoredApps: Preferences.clipboardHistoryIgnoredApps.defaultValue,
        DefaultsKey.windowLayoutIgnoredApps: Preferences.windowLayoutIgnoredApps.defaultValue,
        DefaultsKey.clipboardHistoryQuickPreview: Preferences.clipboardHistoryQuickPreview.defaultValue,
        DefaultsKey.clipboardHistoryWindowWidth: Preferences.clipboardHistoryWindowWidth.defaultValue,
        DefaultsKey.clipboardHistoryWindowHeight: Preferences.clipboardHistoryWindowHeight.defaultValue,
        DefaultsKey.clipboardHistoryMenuBarPreview: Preferences.clipboardHistoryMenuBarPreview.defaultValue,
        DefaultsKey.clipboardHistoryMenuBarPreviewLength: Preferences.clipboardHistoryMenuBarPreviewLength.defaultValue,
        DefaultsKey.clipboardAutoClearOnDelay: Preferences.clipboardAutoClearOnDelay.defaultValue,
        DefaultsKey.clipboardAutoClearDelay: Preferences.clipboardAutoClearDelay.defaultValue,
        DefaultsKey.clipboardAutoClearOnSleep: Preferences.clipboardAutoClearOnSleep.defaultValue,
        DefaultsKey.clipboardAutoClearOnDisplaySleep: Preferences.clipboardAutoClearOnDisplaySleep.defaultValue,
        DefaultsKey.clipboardAutoClearOnScreenLock: Preferences.clipboardAutoClearOnScreenLock.defaultValue,
        DefaultsKey.finderCutPasteShowHUD: Preferences.finderCutPasteShowHUD.defaultValue,
        DefaultsKey.finderPasteImageAsFile: Preferences.finderPasteImageAsFile.defaultValue,
        DefaultsKey.windowPreviewExcludedApps: Preferences.windowPreviewExcludedApps.defaultValue,
        DefaultsKey.switcherPreviewExcludedApps: Preferences.switcherPreviewExcludedApps.defaultValue,
        DefaultsKey.diskEjectExcludedVolumes: Preferences.diskEjectExcludedVolumes.defaultValue,
        DefaultsKey.pastePlainEnabled: Preferences.pastePlainEnabled.defaultValue,
        DefaultsKey.pastePlainShortcut: Preferences.pastePlainShortcut.defaultValue,
        DefaultsKey.finderRenameEnabled: Preferences.finderRenameEnabled.defaultValue,
        DefaultsKey.finderRenameShortcut: Preferences.finderRenameShortcut.defaultValue,
        DefaultsKey.diskImageInstallerUseUserApplications: Preferences.diskImageInstallerUseUserApplications.defaultValue,
        DefaultsKey.diskImageInstallerTrashesDownload: Preferences.diskImageInstallerTrashesDownload.defaultValue,
        DefaultsKey.diskImageInstallerRevealsApp: Preferences.diskImageInstallerRevealsApp.defaultValue,
        DefaultsKey.colorPickerShortcutEnabled: Preferences.colorPickerShortcutEnabled.defaultValue,
        DefaultsKey.colorPickerShortcut: Preferences.colorPickerShortcut.defaultValue,
        DefaultsKey.colorPickerFormat: Preferences.colorPickerFormat.defaultValue,
        DefaultsKey.colorPickerBareHex: Preferences.colorPickerBareHex.defaultValue,
        DefaultsKey.screenOCRShortcutEnabled: Preferences.screenOCRShortcutEnabled.defaultValue,
        DefaultsKey.screenOCRShortcut: Preferences.screenOCRShortcut.defaultValue,
        DefaultsKey.screenOCRRemoveLineBreaks: Preferences.screenOCRRemoveLineBreaks.defaultValue,
        DefaultsKey.screenOCRDetectQRCodes: Preferences.screenOCRDetectQRCodes.defaultValue,
        DefaultsKey.micMuteShortcutEnabled: Preferences.micMuteShortcutEnabled.defaultValue,
        DefaultsKey.micMuteShortcut: Preferences.micMuteShortcut.defaultValue,
        DefaultsKey.cameraPreviewShortcutEnabled: Preferences.cameraPreviewShortcutEnabled.defaultValue,
        DefaultsKey.cameraPreviewShortcut: Preferences.cameraPreviewShortcut.defaultValue,
        DefaultsKey.wallpaperApplyAllDisplays: Preferences.wallpaperApplyAllDisplays.defaultValue,
        DefaultsKey.wallpaperFilter: Preferences.wallpaperFilter.defaultValue,
        DefaultsKey.scratchpadShortcutEnabled: Preferences.scratchpadShortcutEnabled.defaultValue,
        DefaultsKey.scratchpadShortcut: Preferences.scratchpadShortcut.defaultValue,
        DefaultsKey.commandBarShortcutEnabled: Preferences.commandBarShortcutEnabled.defaultValue,
        DefaultsKey.commandBarCompactMode: Preferences.commandBarCompactMode.defaultValue,
        DefaultsKey.commandBarASCIILayoutEnabled: Preferences.commandBarASCIILayoutEnabled.defaultValue,
        DefaultsKey.commandBarDisabledSources: Preferences.commandBarDisabledSources.defaultValue,
        DefaultsKey.commandBarAliases: Preferences.commandBarAliases.defaultValue,
        DefaultsKey.commandBarPins: Preferences.commandBarPins.defaultValue,
        DefaultsKey.commandBarHidden: Preferences.commandBarHidden.defaultValue,
        DefaultsKey.commandBarFileScopes: Preferences.commandBarFileScopes.defaultValue,
        DefaultsKey.commandBarFileIgnores: Preferences.commandBarFileIgnores.defaultValue,
        DefaultsKey.commandBarShortcut: Preferences.commandBarShortcut.defaultValue,
        DefaultsKey.commandBarPositionOffset: Preferences.commandBarPositionOffset.defaultValue,
        DefaultsKey.commandBarEmojiSkinTone: Preferences.commandBarEmojiSkinTone.defaultValue,
        DefaultsKey.panelUtilityCommandBar: Preferences.panelUtilityCommandBar.defaultValue,
        DefaultsKey.scratchpadRetention: Preferences.scratchpadRetention.defaultValue,
        DefaultsKey.scratchpadCloseOnClickOutside: Preferences.scratchpadCloseOnClickOutside.defaultValue,
        DefaultsKey.scratchpadBackgroundOpacity: Preferences.scratchpadBackgroundOpacity.defaultValue,
        DefaultsKey.scratchpadTextSize: Preferences.scratchpadTextSize.defaultValue,
        DefaultsKey.micMuteActive: Preferences.micMuteActive.defaultValue,
        DefaultsKey.micMuteSavedVolume: Preferences.micMuteSavedVolume.defaultValue,
        DefaultsKey.micMuteMenuBarIndicator: Preferences.micMuteMenuBarIndicator.defaultValue,
        DefaultsKey.quickLauncherShortcutEnabled: Preferences.quickLauncherShortcutEnabled.defaultValue,
        DefaultsKey.quickLauncherShortcut: Preferences.quickLauncherShortcut.defaultValue,
        DefaultsKey.quickLauncherHiddenItems: Preferences.quickLauncherHiddenItems.defaultValue,
        DefaultsKey.panelUtilityQuickLauncher: Preferences.panelUtilityQuickLauncher.defaultValue,
        DefaultsKey.panelUtilityColorPicker: Preferences.panelUtilityColorPicker.defaultValue,
        DefaultsKey.panelUtilityScreenOCR: Preferences.panelUtilityScreenOCR.defaultValue,
        DefaultsKey.panelUtilityCameraPreview: Preferences.panelUtilityCameraPreview.defaultValue,
        DefaultsKey.panelUtilityScratchpad: Preferences.panelUtilityScratchpad.defaultValue,
        DefaultsKey.clipboardHistoryShortcutEnabled: Preferences.clipboardHistoryShortcutEnabled.defaultValue,
        DefaultsKey.clipboardHistoryShortcut: Preferences.clipboardHistoryShortcut.defaultValue,
        DefaultsKey.recorderShortcutEnabled: Preferences.recorderShortcutEnabled.defaultValue,
        DefaultsKey.recorderShortcut: Preferences.recorderShortcut.defaultValue,
        DefaultsKey.recorderCountdown: Preferences.recorderCountdown.defaultValue,
        DefaultsKey.recorderQuality: Preferences.recorderQuality.defaultValue,
        DefaultsKey.recorderFrameRate: Preferences.recorderFrameRate.defaultValue,
        DefaultsKey.recorderSystemAudio: Preferences.recorderSystemAudio.defaultValue,
        DefaultsKey.recorderMicrophone: Preferences.recorderMicrophone.defaultValue,
        DefaultsKey.recorderSaveFolder: Preferences.recorderSaveFolder.defaultValue,
        DefaultsKey.recorderOpenEditor: Preferences.recorderOpenEditor.defaultValue,
        DefaultsKey.recorderAutomaticZoom: Preferences.recorderAutomaticZoom.defaultValue,
        DefaultsKey.recorderGIFSize: Preferences.recorderGIFSize.defaultValue,
        DefaultsKey.recorderGIFFrameRate: Preferences.recorderGIFFrameRate.defaultValue,
        DefaultsKey.recorderEditorPresets: Preferences.recorderEditorPresets.defaultValue,
        DefaultsKey.recorderSharingEnabled: Preferences.recorderSharingEnabled.defaultValue,
        DefaultsKey.panelUtilityScreenRecorder: Preferences.panelUtilityScreenRecorder.defaultValue,
        DefaultsKey.panelUtilityPortManager: Preferences.panelUtilityPortManager.defaultValue,
        DefaultsKey.nexusAgentShortcutEnabled: Preferences.nexusAgentShortcutEnabled.defaultValue,
        DefaultsKey.nexusAgentShortcut: Preferences.nexusAgentShortcut.defaultValue,
        DefaultsKey.nexusAgentAutoStart: Preferences.nexusAgentAutoStart.defaultValue,
        DefaultsKey.nexusAgentPlanMode: Preferences.nexusAgentPlanMode.defaultValue,
        DefaultsKey.nexusAgentBotDirectory: Preferences.nexusAgentBotDirectory.defaultValue,
        DefaultsKey.panelUtilityNexusAgent: Preferences.panelUtilityNexusAgent.defaultValue,
        DefaultsKey.screenshotShowCaptureMenuOnShortcut: Preferences.screenshotShowCaptureMenuOnShortcut.defaultValue,
        DefaultsKey.recorderShowCaptureMenuOnShortcut: Preferences.recorderShowCaptureMenuOnShortcut.defaultValue,
        DefaultsKey.screenOCRShowCaptureMenuOnShortcut: Preferences.screenOCRShowCaptureMenuOnShortcut.defaultValue,
        DefaultsKey.colorPickerShowCaptureMenuOnShortcut: Preferences.colorPickerShowCaptureMenuOnShortcut.defaultValue,
        DefaultsKey.screenshotShortcutEnabled: Preferences.screenshotShortcutEnabled.defaultValue,
        DefaultsKey.screenshotShortcut: Preferences.screenshotShortcut.defaultValue,
        DefaultsKey.unifiedScreenCaptureShortcutMigrated: Preferences.unifiedScreenCaptureShortcutMigrated.defaultValue,
        DefaultsKey.restoredScreenCaptureShortcutsMigrated: Preferences.restoredScreenCaptureShortcutsMigrated.defaultValue,
        DefaultsKey.screenshotFullScreenShortcutEnabled: Preferences.screenshotFullScreenShortcutEnabled.defaultValue,
        DefaultsKey.screenshotFullScreenShortcut: Preferences.screenshotFullScreenShortcut.defaultValue,
        DefaultsKey.screenshotLastCaptureShortcutEnabled: Preferences.screenshotLastCaptureShortcutEnabled.defaultValue,
        DefaultsKey.screenshotLastCaptureShortcut: Preferences.screenshotLastCaptureShortcut.defaultValue,
        DefaultsKey.recentCapturesShortcutEnabled: Preferences.recentCapturesShortcutEnabled.defaultValue,
        DefaultsKey.recentCapturesShortcut: Preferences.recentCapturesShortcut.defaultValue,
        DefaultsKey.screenshotClipboardShortcutEnabled: Preferences.screenshotClipboardShortcutEnabled.defaultValue,
        DefaultsKey.screenshotClipboardShortcut: Preferences.screenshotClipboardShortcut.defaultValue,
        DefaultsKey.screenshotFreeze: Preferences.screenshotFreeze.defaultValue,
        DefaultsKey.screenshotHideVitruvianWindows: Preferences.screenshotHideVitruvianWindows.defaultValue,
        DefaultsKey.screenshotSaveFolder: Preferences.screenshotSaveFolder.defaultValue,
        DefaultsKey.screenshotSaveSubfolder: Preferences.screenshotSaveSubfolder.defaultValue,
        DefaultsKey.screenshotFileNamePattern: Preferences.screenshotFileNamePattern.defaultValue,
        DefaultsKey.screenshotFileNumberStart: Preferences.screenshotFileNumberStart.defaultValue,
        DefaultsKey.screenshotFileNumberNext: Preferences.screenshotFileNumberNext.defaultValue,
        DefaultsKey.screenshotDefaultAction: Preferences.screenshotDefaultAction.defaultValue,
        DefaultsKey.screenshotIncludePointer: Preferences.screenshotIncludePointer.defaultValue,
        DefaultsKey.screenshotShowLastRegion: Preferences.screenshotShowLastRegion.defaultValue,
        DefaultsKey.screenshotLoupeStartsOn: Preferences.screenshotLoupeStartsOn.defaultValue,
        DefaultsKey.screenshotLoupeRememberZoom: Preferences.screenshotLoupeRememberZoom.defaultValue,
        DefaultsKey.screenshotLoupeDefaultZoom: Preferences.screenshotLoupeDefaultZoom.defaultValue,
        DefaultsKey.screenshotLoupeLastZoom: Preferences.screenshotLoupeLastZoom.defaultValue,
        DefaultsKey.screenshotLoupeSteppedZoomByDefault: Preferences.screenshotLoupeSteppedZoomByDefault.defaultValue,
        DefaultsKey.screenshotDownscale: Preferences.screenshotDownscale.defaultValue,
        DefaultsKey.screenshotDelay: Preferences.screenshotDelay.defaultValue,
        DefaultsKey.screenshotLastTool: Preferences.screenshotLastTool.defaultValue,
        DefaultsKey.screenshotLastColor: Preferences.screenshotLastColor.defaultValue,
        DefaultsKey.screenshotLastStroke: Preferences.screenshotLastStroke.defaultValue,
        DefaultsKey.screenshotLastTextSize: Preferences.screenshotLastTextSize.defaultValue,
        DefaultsKey.screenshotLastBlurLevel: Preferences.screenshotLastBlurLevel.defaultValue,
        DefaultsKey.screenshotLastArrowStyle: Preferences.screenshotLastArrowStyle.defaultValue,
        DefaultsKey.screenshotLastSticker: Preferences.screenshotLastSticker.defaultValue,
        DefaultsKey.screenshotAnnotationShadows: Preferences.screenshotAnnotationShadows.defaultValue,
        DefaultsKey.screenshotToolOrder: Preferences.screenshotToolOrder.defaultValue,
        DefaultsKey.screenshotToolShortcutsEnabled: Preferences.screenshotToolShortcutsEnabled.defaultValue,
        DefaultsKey.screenshotToolShortcuts: Preferences.screenshotToolShortcuts.defaultValue,
        DefaultsKey.screenshotBackdropStyle: Preferences.screenshotBackdropStyle.defaultValue,
        DefaultsKey.screenshotBackdropPresets: Preferences.screenshotBackdropPresets.defaultValue,
        DefaultsKey.screenshotWatermarkStyle: Preferences.screenshotWatermarkStyle.defaultValue,
        DefaultsKey.screenshotWatermarkPresets: Preferences.screenshotWatermarkPresets.defaultValue,
        DefaultsKey.screenshotOpenEditorDirectly: Preferences.screenshotOpenEditorDirectly.defaultValue,
        DefaultsKey.screenshotCopyToClipboard: Preferences.screenshotCopyToClipboard.defaultValue,
        DefaultsKey.screenshotPreviewPosition: Preferences.screenshotPreviewPosition.defaultValue,
        DefaultsKey.screenshotPreviewTakesFocus: Preferences.screenshotPreviewTakesFocus.defaultValue,
        DefaultsKey.screenshotUploadShortcutEnabled: Preferences.screenshotUploadShortcutEnabled.defaultValue,
        DefaultsKey.screenshotUploadShortcut: Preferences.screenshotUploadShortcut.defaultValue,
        DefaultsKey.screenshotUploadDuration: Preferences.screenshotUploadDuration.defaultValue,
        DefaultsKey.screenshotPreviewEnabled: Preferences.screenshotPreviewEnabled.defaultValue,
        DefaultsKey.screenshotPreviewDuration: Preferences.screenshotPreviewDuration.defaultValue,
        DefaultsKey.screenshotSharingEnabled: Preferences.screenshotSharingEnabled.defaultValue,
        DefaultsKey.panelUtilityScreenshot: Preferences.panelUtilityScreenshot.defaultValue,
        DefaultsKey.windowLayoutShortcutsEnabled: Preferences.windowLayoutShortcutsEnabled.defaultValue,
        DefaultsKey.windowDirectionalEnabled: Preferences.windowDirectionalEnabled.defaultValue,
        DefaultsKey.windowDirectionalShortcut: Preferences.windowDirectionalShortcut.defaultValue,
        DefaultsKey.pointerDisplayEnabled: Preferences.pointerDisplayEnabled.defaultValue,
        DefaultsKey.pointerDisplayShortcut: Preferences.pointerDisplayShortcut.defaultValue,
        DefaultsKey.windowEdgeSnapEnabled: Preferences.windowEdgeSnapEnabled.defaultValue,
        DefaultsKey.windowEdgeSnapDisabledZones: Preferences.windowEdgeSnapDisabledZones.defaultValue,
        DefaultsKey.windowGestureEnabled: Preferences.windowGestureEnabled.defaultValue,
        DefaultsKey.windowGestureModifiers: Preferences.windowGestureModifiers.defaultValue,
        DefaultsKey.windowGestureRaiseWindow: Preferences.windowGestureRaiseWindow.defaultValue,
        DefaultsKey.windowLayoutShortcutLeft: Preferences.windowLayoutShortcutLeft.defaultValue,
        DefaultsKey.windowLayoutShortcutRight: Preferences.windowLayoutShortcutRight.defaultValue,
        DefaultsKey.windowLayoutShortcutTop: Preferences.windowLayoutShortcutTop.defaultValue,
        DefaultsKey.windowLayoutShortcutBottom: Preferences.windowLayoutShortcutBottom.defaultValue,
        DefaultsKey.windowLayoutShortcutCenterHalf: Preferences.windowLayoutShortcutCenterHalf.defaultValue,
        DefaultsKey.windowLayoutShortcutTopLeft: Preferences.windowLayoutShortcutTopLeft.defaultValue,
        DefaultsKey.windowLayoutShortcutTopRight: Preferences.windowLayoutShortcutTopRight.defaultValue,
        DefaultsKey.windowLayoutShortcutBottomLeft: Preferences.windowLayoutShortcutBottomLeft.defaultValue,
        DefaultsKey.windowLayoutShortcutBottomRight: Preferences.windowLayoutShortcutBottomRight.defaultValue,
        DefaultsKey.windowLayoutShortcutMaximize: Preferences.windowLayoutShortcutMaximize.defaultValue,
        DefaultsKey.windowLayoutShortcutMarginMaximize: Preferences.windowLayoutShortcutMarginMaximize.defaultValue,
        DefaultsKey.windowLayoutShortcutCenter: Preferences.windowLayoutShortcutCenter.defaultValue,
        DefaultsKey.windowLayoutShortcutRestore: Preferences.windowLayoutShortcutRestore.defaultValue,
        DefaultsKey.windowLayoutShortcutLeftThird: Preferences.windowLayoutShortcutLeftThird.defaultValue,
        DefaultsKey.windowLayoutShortcutCenterThird: Preferences.windowLayoutShortcutCenterThird.defaultValue,
        DefaultsKey.windowLayoutShortcutRightThird: Preferences.windowLayoutShortcutRightThird.defaultValue,
        DefaultsKey.windowLayoutShortcutLeftTwoThirds: Preferences.windowLayoutShortcutLeftTwoThirds.defaultValue,
        DefaultsKey.windowLayoutShortcutRightTwoThirds: Preferences.windowLayoutShortcutRightTwoThirds.defaultValue,
        DefaultsKey.windowLayoutShortcutCenterTwoThirds: Preferences.windowLayoutShortcutCenterTwoThirds.defaultValue,
        DefaultsKey.windowLayoutShortcutTopThird: Preferences.windowLayoutShortcutTopThird.defaultValue,
        DefaultsKey.windowLayoutShortcutMiddleThird: Preferences.windowLayoutShortcutMiddleThird.defaultValue,
        DefaultsKey.windowLayoutShortcutBottomThird: Preferences.windowLayoutShortcutBottomThird.defaultValue,
        DefaultsKey.windowLayoutShortcutTopTwoThirds: Preferences.windowLayoutShortcutTopTwoThirds.defaultValue,
        DefaultsKey.windowLayoutShortcutBottomTwoThirds: Preferences.windowLayoutShortcutBottomTwoThirds.defaultValue,
        DefaultsKey.windowLayoutShortcutTopQuarter: Preferences.windowLayoutShortcutTopQuarter.defaultValue,
        DefaultsKey.windowLayoutShortcutUpperMiddleQuarter: Preferences.windowLayoutShortcutUpperMiddleQuarter.defaultValue,
        DefaultsKey.windowLayoutShortcutLowerMiddleQuarter: Preferences.windowLayoutShortcutLowerMiddleQuarter.defaultValue,
        DefaultsKey.windowLayoutShortcutBottomQuarter: Preferences.windowLayoutShortcutBottomQuarter.defaultValue,
        DefaultsKey.windowLayoutShortcutLeftQuarter: Preferences.windowLayoutShortcutLeftQuarter.defaultValue,
        DefaultsKey.windowLayoutShortcutLeftMiddleQuarter: Preferences.windowLayoutShortcutLeftMiddleQuarter.defaultValue,
        DefaultsKey.windowLayoutShortcutRightMiddleQuarter: Preferences.windowLayoutShortcutRightMiddleQuarter.defaultValue,
        DefaultsKey.windowLayoutShortcutRightQuarter: Preferences.windowLayoutShortcutRightQuarter.defaultValue,
        DefaultsKey.windowLayoutShortcutPreviousDisplay: Preferences.windowLayoutShortcutPreviousDisplay.defaultValue,
        DefaultsKey.windowLayoutShortcutNextDisplay: Preferences.windowLayoutShortcutNextDisplay.defaultValue,
        DefaultsKey.windowLayoutShortcutTopLeftSixth: Preferences.windowLayoutShortcutTopLeftSixth.defaultValue,
        DefaultsKey.windowLayoutShortcutTopCenterSixth: Preferences.windowLayoutShortcutTopCenterSixth.defaultValue,
        DefaultsKey.windowLayoutShortcutTopRightSixth: Preferences.windowLayoutShortcutTopRightSixth.defaultValue,
        DefaultsKey.windowLayoutShortcutBottomLeftSixth: Preferences.windowLayoutShortcutBottomLeftSixth.defaultValue,
        DefaultsKey.windowLayoutShortcutBottomCenterSixth: Preferences.windowLayoutShortcutBottomCenterSixth.defaultValue,
        DefaultsKey.windowLayoutShortcutBottomRightSixth: Preferences.windowLayoutShortcutBottomRightSixth.defaultValue,
        DefaultsKey.windowLayoutShortcutFullScreen: Preferences.windowLayoutShortcutFullScreen.defaultValue,
        DefaultsKey.autoQuitEnabled: Preferences.autoQuitEnabled.defaultValue,
        DefaultsKey.finderCutPasteEnabled: Preferences.finderCutPasteEnabled.defaultValue,
        DefaultsKey.shelfEnabled: Preferences.shelfEnabled.defaultValue,
        DefaultsKey.menuBarCPU: Preferences.menuBarCPU.defaultValue,
        DefaultsKey.menuBarGPU: Preferences.menuBarGPU.defaultValue,
        DefaultsKey.menuBarMemory: Preferences.menuBarMemory.defaultValue,
        DefaultsKey.menuBarNetwork: Preferences.menuBarNetwork.defaultValue,
        DefaultsKey.menuBarBattery: Preferences.menuBarBattery.defaultValue,
        DefaultsKey.menuBarPower: Preferences.menuBarPower.defaultValue,
        DefaultsKey.onboardingStep: Preferences.onboardingStep.defaultValue,
        DefaultsKey.commandBarLinks: Preferences.commandBarLinks.defaultValue,
        DefaultsKey.commandBarRowShortcuts: Preferences.commandBarRowShortcuts.defaultValue,
    ]

    package static func register() {
        let defaults = UserDefaults.standard
        migrateExistingNotchDefaults(in: defaults)
        migrateLiquidGlassIsland(in: defaults)
        migrateFanControlVisibility(in: defaults)
        migrateScrollInverterAxes(in: defaults)
        migrateLinearScrollAvailability(in: defaults)
        migrateWhatsAppDownloadsEnabled(in: defaults)
        migrateBatteryTemperatureVisibility(in: defaults)
        migrateSwitcherPreviewSize(in: defaults)
        migrateSwitcherPreviewExcludedApps(in: defaults)
        defaults.register(defaults: registeredDefaults)
        defaults.register(defaults: AppFeature.availabilityDefaults)
        activateBetaChannelIfRunningBeta(in: defaults)
        installCompanionForBetaCommandBar(in: defaults)
        migrateLegacyMenuBarTemperatureMetric(in: defaults)
        migrateLegacySwitcherWindowShortcut(in: defaults)
        migrateLegacyKeyboardDebounceWindow(in: defaults)
        migrateUtilityOrderForScreenshot(in: defaults)
        migrateUtilityOrderForAppUpdates(in: defaults)
        migrateScreenshotOpenEditorDirectly(in: defaults)
        migrateUnifiedScreenCaptureShortcut(in: defaults)
        migrateRestoredScreenCaptureShortcuts(in: defaults)
        migrateOrphanedCaptureShortcut(in: defaults)
        migrateSilentHeadphonesDisconnectVolume(in: defaults)
        migrateSwitcherWindowlessFinder(in: defaults)
        recheckBrightnessDDCWriteOnlyPaths(in: defaults)
        hideScratchpadControlOnce(in: defaults)
        hideKeyboardLightControlOnce(in: defaults)
    }

    /// Existing users keep the island's previous glass choice. The island
    /// value is saved once, even when off, so turning on glass for other
    /// windows later never reaches the island on the next launch.
    package static func migrateLiquidGlassIsland(in defaults: UserDefaults,
                                         domainName: String? = Bundle.main.bundleIdentifier) {
        guard let domainName else { return }
        let saved = defaults.persistentDomain(forName: domainName) ?? [:]
        guard saved[DefaultsKey.notchLiquidGlassEnabled] == nil else { return }
        defaults.set(saved[DefaultsKey.liquidGlassEnabled] as? Bool ?? false,
                     forKey: DefaultsKey.notchLiquidGlassEnabled)
    }

    /// Keep the previous implicit choices for people who already configured
    /// the island. A fresh setup gets the new profile instead.
    package static func migrateExistingNotchDefaults(in defaults: UserDefaults,
                                             domainName: String? = Bundle.main.bundleIdentifier) {
        guard let domainName else { return }
        let saved = defaults.persistentDomain(forName: domainName) ?? [:]
        guard saved[DefaultsKey.notchDefaultProfileInitialized] == nil else {
            // The previous profile registered Compact without persisting it.
            // Preserve that implicit choice before registering Spacious.
            if saved[DefaultsKey.notchSize] == nil {
                defaults.set(NotchSize.compact.rawValue, forKey: DefaultsKey.notchSize)
            }
            return
        }
        let automaticKeys: Set<String> = [DefaultsKey.notchScratchpadControlHidden,
                                          DefaultsKey.notchKeyboardLightControlHidden,
                                          DefaultsKey.notchHidesMenuBarIcon]
        let wasConfigured = saved.keys.contains {
            $0.hasPrefix("notch") && !automaticKeys.contains($0)
                && ($0 != DefaultsKey.notchHiddenControls
                    || saved[$0] as? String != NotchControlItem.defaultHidden)
        } || saved[DefaultsKey.notchHidesMenuBarIcon] as? Bool == true
        if wasConfigured {
            defaults.set(true, forKey: DefaultsKey.notchInitialExtensionsInstalled)
            let previous: [String: Any] = [
                DefaultsKey.notchSize: NotchSize.spacious.rawValue,
                DefaultsKey.notchAppPanel: true,
                DefaultsKey.notchKeyboardLight: false,
                DefaultsKey.notchNotificationsEnabled: false,
                DefaultsKey.notchCameraEnabled: false,
                DefaultsKey.notchAccessoriesEnabled: false,
                DefaultsKey.notchAgentsEnabled: false,
                DefaultsKey.notchLyricsEnabled: false,
                DefaultsKey.notchLiveEqualizer: false,
                DefaultsKey.notchQueueEnabled: false,
                DefaultsKey.notchDownloadsEnabled: false,
                DefaultsKey.notchOpenOnHover: true,
                DefaultsKey.notchClipboard: false,
                DefaultsKey.notchCapture: false,
                DefaultsKey.notchTrackChange: false,
            ]
            for (key, value) in previous where saved[key] == nil {
                defaults.set(value, forKey: key)
            }
        }
        if !wasConfigured {
            // Pin the new choice so subsequent launches cannot mistake this
            // setup for an older profile with an implicit Compact size.
            defaults.set(NotchSize.spacious.rawValue, forKey: DefaultsKey.notchSize)
        }
        defaults.set(true, forKey: DefaultsKey.notchDefaultProfileInitialized)
    }

    /// The Scratchpad tile joined the controls hidden by default after lists
    /// had been saved without it, and a saved list is read whole: a setup
    /// customized before then would show a tile nobody asked for. Once, so
    /// showing it afterwards stays the user's choice.
    package static func hideScratchpadControlOnce(in defaults: UserDefaults) {
        guard !defaults.bool(forKey: DefaultsKey.notchScratchpadControlHidden) else { return }
        defaults.set(true, forKey: DefaultsKey.notchScratchpadControlHidden)
        guard let saved = defaults.string(forKey: DefaultsKey.notchHiddenControls) else { return }
        var hidden = saved.split(separator: ",").map(String.init)
        guard !hidden.contains(NotchControlItem.scratchpad.rawValue) else { return }
        hidden.append(NotchControlItem.scratchpad.rawValue)
        defaults.set(hidden.joined(separator: ","), forKey: DefaultsKey.notchHiddenControls)
    }

    /// The keyboard light level joined the hidden controls the same way, and
    /// a list saved before it would otherwise grow a third slider on update.
    package static func hideKeyboardLightControlOnce(in defaults: UserDefaults) {
        guard !defaults.bool(forKey: DefaultsKey.notchKeyboardLightControlHidden) else { return }
        defaults.set(true, forKey: DefaultsKey.notchKeyboardLightControlHidden)
        guard let saved = defaults.string(forKey: DefaultsKey.notchHiddenControls) else { return }
        var hidden = saved.split(separator: ",").map(String.init)
        guard !hidden.contains(NotchControlItem.keyboardLight.rawValue) else { return }
        hidden.append(NotchControlItem.keyboardLight.rawValue)
        defaults.set(hidden.joined(separator: ","), forKey: DefaultsKey.notchHiddenControls)
    }

    /// Discovery used to send one request per read, which reads a monitor that
    /// answers only paired requests as write-only. That verdict is cached and
    /// never re-probed, so it would outlive the fix: drop the cache once.
    package static func recheckBrightnessDDCWriteOnlyPaths(in defaults: UserDefaults) {
        guard !defaults.bool(forKey: DefaultsKey.brightnessDDCWriteOnlyPathsRechecked) else {
            return
        }
        defaults.set(true, forKey: DefaultsKey.brightnessDDCWriteOnlyPathsRechecked)
        defaults.removeObject(forKey: DefaultsKey.brightnessDDCWriteOnlyPaths)
    }

    /// The app switcher used to share Dock Preview's thumbnail size. Copy it
    /// once, before defaults are registered, so neither changes on upgrade.
    /// With no size chosen yet, store the default all the same: a Dock size
    /// picked later would otherwise be copied at the next launch.
    package static func migrateSwitcherPreviewSize(in defaults: UserDefaults) {
        guard defaults.object(forKey: DefaultsKey.switcherPreviewSize) == nil else { return }
        defaults.set(defaults.string(forKey: DefaultsKey.previewSize) ?? "normal",
                     forKey: DefaultsKey.switcherPreviewSize)
    }

    /// The app switcher used to share Dock Preview's paused apps. Copy the
    /// list once, before defaults are registered, so both keep pausing in
    /// the same apps after the upgrade. With no list saved yet, store an
    /// empty one: an app paused in Dock Preview later would otherwise be
    /// copied at the next launch.
    package static func migrateSwitcherPreviewExcludedApps(in defaults: UserDefaults) {
        guard defaults.object(forKey: DefaultsKey.switcherPreviewExcludedApps) == nil else { return }
        defaults.set(defaults.stringArray(forKey: DefaultsKey.windowPreviewExcludedApps) ?? [],
                     forKey: DefaultsKey.switcherPreviewExcludedApps)
    }

    package static func migrateBatteryTemperatureVisibility(in defaults: UserDefaults) {
        guard defaults.object(forKey: DefaultsKey.monitorPwrTemperature) == nil else { return }
        defaults.set(defaults.object(forKey: DefaultsKey.monitorSysTemps) as? Bool ?? true,
                     forKey: DefaultsKey.monitorPwrTemperature)
    }

    /// When the user installs or runs a beta pre-release, activate the beta
    /// channel default once so they seamlessly receive subsequent beta builds.
    package static func activateBetaChannelIfRunningBeta(in defaults: UserDefaults,
                                                 version: String = AppInfo.version,
                                                 isBeta: Bool = AppInfo.isBeta) {
        let isPre = isBeta || {
            let v = version.lowercased()
            return v.contains("-beta") || v.contains("-rc") || v.contains("-alpha")
        }()
        guard isPre else { return }
        let markerKey = "betaChannelActivatedFor.\(version)"
        guard !defaults.bool(forKey: markerKey) else { return }
        defaults.set(true, forKey: markerKey)
        defaults.set(true, forKey: DefaultsKey.includeBetaUpdates)
    }

    /// On a beta, people with the Command Bar get the island's companion,
    /// which can be its face, installed and on, once: uninstalled afterwards,
    /// it stays out. A clean install waits for its setup to finish, since
    /// setup picks the installed features afresh. It lives in the island, so
    /// someone without the island gets nothing.
    package static func installsCompanionForBeta(in defaults: UserDefaults, isBeta: Bool = AppInfo.isBeta) -> Bool {
        isBeta && defaults.bool(forKey: DefaultsKey.hasOnboarded)
            && !defaults.bool(forKey: DefaultsKey.notchMascotBetaInstalled)
            && AppFeature.commandBar.isAvailable(in: defaults)
            && AppFeature.notch.isAvailable(in: defaults)
    }

    package static func installCompanionForBetaCommandBar(in defaults: UserDefaults, isBeta: Bool = AppInfo.isBeta) {
        guard installsCompanionForBeta(in: defaults, isBeta: isBeta) else { return }
        defaults.set(true, forKey: DefaultsKey.notchMascotBetaInstalled)
        defaults.set(true, forKey: AppFeature.notchMascot.availabilityKey)
        defaults[Preferences.notchMascotEnabled] = true
    }

    /// The downloads cleanup for a messaging app used to sit in Cleaner for
    /// everyone. Keep it visible only when someone already turned automatic
    /// cleanup or the organizer on; everyone else gets the new off-by-default
    /// choice.
    package static func migrateWhatsAppDownloadsEnabled(in defaults: UserDefaults) {
        guard defaults.object(forKey: DefaultsKey.whatsAppDownloadsEnabled) == nil else {
            return
        }
        let alreadyUsing = defaults.bool(forKey: DefaultsKey.whatsAppDownloadsAutomaticEnabled)
            || defaults.bool(forKey: DefaultsKey.whatsAppOrganizerEnabled)
        if alreadyUsing {
            defaults.set(true, forKey: DefaultsKey.whatsAppDownloadsEnabled)
        }
    }

    /// The former single switch also reversed vertical wheel events redirected
    /// sideways with Shift. Mirror that choice once so updates and older
    /// settings backups keep the same behavior until the user separates axes.
    package static func migrateScrollInverterAxes(in defaults: UserDefaults) {
        guard defaults.object(forKey: DefaultsKey.scrollInverterHorizontalEnabled) == nil else {
            return
        }
        defaults.set(defaults.bool(forKey: DefaultsKey.scrollInverterEnabled),
                     forKey: DefaultsKey.scrollInverterHorizontalEnabled)
    }

    /// Linear scrolling reached development builds installed, before new
    /// features became opt-in. Whoever switched it on keeps it installed.
    package static func migrateLinearScrollAvailability(in defaults: UserDefaults) {
        guard defaults.object(forKey: AppFeature.linearScroll.availabilityKey) == nil,
              defaults.object(forKey: DefaultsKey.linearScrollEnabled) as? Bool == true
        else { return }
        defaults.set(true, forKey: AppFeature.linearScroll.availabilityKey)
    }

    package static func migrateFanControlVisibility(in defaults: UserDefaults) {
        if let oldValue = defaults.object(forKey: DefaultsKey.monitorShowFanControlBeta) as? Bool {
            if defaults.object(forKey: DefaultsKey.panelShowFanControl) == nil {
                defaults.set(oldValue, forKey: DefaultsKey.panelShowFanControl)
            }
            if oldValue,
               defaults.object(forKey: AppFeature.fanControl.availabilityKey) == nil {
                defaults.set(true, forKey: AppFeature.fanControl.availabilityKey)
            }
        }
        defaults.removeObject(forKey: DefaultsKey.monitorShowFanControlBeta)
    }

    /// The "show the desktop app without windows" toggle became one choice of
    /// the windowless apps picker. Only an explicit off has to travel: the
    /// picker ships on the same choice the toggle shipped on, so a setup that
    /// never touched it keeps the switcher it already had. Clearing the old
    /// toggle is what makes this run once and never fight a later choice.
    package static func migrateSwitcherWindowlessFinder(in defaults: UserDefaults) {
        let showsWindowlessFinder = defaults.bool(forKey: DefaultsKey.switcherShowWindowlessFinder)
        guard !showsWindowlessFinder else { return }
        defaults.set(true, forKey: DefaultsKey.switcherShowWindowlessFinder)
        let mode = SwitcherWindowlessApps.migrated(showsWindowlessFinder: showsWindowlessFinder)
        defaults.set(mode.rawValue, forKey: DefaultsKey.switcherWindowlessApps)
    }

    /// The "open the editor right after capturing" toggle became the Edit
    /// choice of the after-capture action picker. A setup that jumped
    /// straight into the editor keeps doing exactly that, unless a newer
    /// picker choice already exists.
    package static func migrateScreenshotOpenEditorDirectly(in defaults: UserDefaults) {
        guard defaults.bool(forKey: DefaultsKey.screenshotOpenEditorDirectly) else { return }
        defaults.set(false, forKey: DefaultsKey.screenshotOpenEditorDirectly)
        let action = defaults.string(forKey: DefaultsKey.screenshotDefaultAction) ?? ""
        guard action.isEmpty else { return }
        defaults.set(ScreenshotDefaultAction.edit.rawValue,
                     forKey: DefaultsKey.screenshotDefaultAction)
    }

    /// The four screen tools now share the screenshot shortcut. Preserve the
    /// first dedicated shortcut an existing setup had enabled, while fresh
    /// installs keep the combined shortcut off by default.
    package static func migrateUnifiedScreenCaptureShortcut(in defaults: UserDefaults) {
        guard !defaults.bool(forKey: DefaultsKey.unifiedScreenCaptureShortcutMigrated) else {
            return
        }
        defer {
            defaults.set(true, forKey: DefaultsKey.unifiedScreenCaptureShortcutMigrated)
        }
        guard !defaults.bool(forKey: DefaultsKey.screenshotShortcutEnabled) else { return }

        let legacyChoices: [(enabled: String, shortcut: String, fallback: GlobalShortcut)] = [
            (DefaultsKey.recorderShortcutEnabled,
             DefaultsKey.recorderShortcut,
             .screenRecorderDefault),
            (DefaultsKey.screenOCRShortcutEnabled,
             DefaultsKey.screenOCRShortcut,
             .screenOCRDefault),
            (DefaultsKey.colorPickerShortcutEnabled,
             DefaultsKey.colorPickerShortcut,
             .colorPickerDefault),
        ]
        guard let choice = legacyChoices.first(where: {
            defaults.bool(forKey: $0.enabled)
        }) else { return }
        let shortcut = defaults.string(forKey: choice.shortcut) ?? choice.fallback.storageValue
        defaults.set(true, forKey: DefaultsKey.screenshotShortcutEnabled)
        defaults.set(shortcut, forKey: DefaultsKey.screenshotShortcut)
    }

    /// The unified-capture migration copied an enabled dedicated shortcut to
    /// the general capture role. Now that dedicated shortcuts are back, keep
    /// the original role instead of registering the same combination twice.
    package static func migrateRestoredScreenCaptureShortcuts(in defaults: UserDefaults) {
        guard !defaults.bool(forKey: DefaultsKey.restoredScreenCaptureShortcutsMigrated) else {
            return
        }
        defer {
            defaults.set(true, forKey: DefaultsKey.restoredScreenCaptureShortcutsMigrated)
        }
        guard defaults.bool(forKey: DefaultsKey.screenshotShortcutEnabled),
              let generalShortcut = defaults.string(forKey: DefaultsKey.screenshotShortcut)
        else { return }

        let dedicatedKeys = [
            (DefaultsKey.recorderShortcutEnabled, DefaultsKey.recorderShortcut),
            (DefaultsKey.screenOCRShortcutEnabled, DefaultsKey.screenOCRShortcut),
            (DefaultsKey.colorPickerShortcutEnabled, DefaultsKey.colorPickerShortcut),
        ]
        guard dedicatedKeys.contains(where: { enabledKey, shortcutKey in
            defaults.bool(forKey: enabledKey)
                && defaults.string(forKey: shortcutKey) == generalShortcut
        }) else { return }
        defaults.set(false, forKey: DefaultsKey.screenshotShortcutEnabled)
    }

    /// The general capture shortcut now belongs to the screenshot tool, so on
    /// an install without that tool a saved combination would register
    /// nothing. Move it once onto the first available tool that has no
    /// shortcut of its own, so the combination keeps opening the chooser.
    /// A tool whose shortcut is switched off but was customized still counts
    /// as having its own, so its saved combination is never overwritten.
    /// Availability is read from the passed defaults — the same key
    /// `isAvailable` reads from the standard ones — to stay testable.
    package static func migrateOrphanedCaptureShortcut(in defaults: UserDefaults) {
        guard !defaults.bool(forKey: DefaultsKey.orphanedCaptureShortcutMigrated) else {
            return
        }
        defer {
            defaults.set(true, forKey: DefaultsKey.orphanedCaptureShortcutMigrated)
        }
        guard defaults.bool(forKey: DefaultsKey.screenshotShortcutEnabled),
              !defaults.bool(forKey: AppFeature.screenshot.availabilityKey)
        else { return }
        let shortcut = defaults.string(forKey: DefaultsKey.screenshotShortcut)
            ?? GlobalShortcut.screenshotDefault.storageValue

        let candidates: [(feature: AppFeature, enabled: String,
                          shortcut: String, unset: String)] = [
            (.screenRecorder, DefaultsKey.recorderShortcutEnabled,
             DefaultsKey.recorderShortcut,
             GlobalShortcut.screenRecorderDefault.storageValue),
            (.screenOCR, DefaultsKey.screenOCRShortcutEnabled,
             DefaultsKey.screenOCRShortcut,
             GlobalShortcut.screenOCRDefault.storageValue),
            (.colorPicker, DefaultsKey.colorPickerShortcutEnabled,
             DefaultsKey.colorPickerShortcut,
             GlobalShortcut.colorPickerDefault.storageValue),
        ]
        guard let target = candidates.first(where: {
            defaults.bool(forKey: $0.feature.availabilityKey)
                && !defaults.bool(forKey: $0.enabled)
                && (defaults.string(forKey: $0.shortcut) ?? $0.unset) == $0.unset
        }) else { return }
        defaults.set(true, forKey: target.enabled)
        defaults.set(shortcut, forKey: target.shortcut)
        defaults.set(false, forKey: DefaultsKey.screenshotShortcutEnabled)
    }

    package static func migrateLegacySwitcherWindowShortcut(in defaults: UserDefaults) {
        let wrongDeveloperDefault = GlobalShortcut(keyCode: Int64(kVK_ANSI_Grave),
                                                   modifiers: [.control, .option, .command]).storageValue
        guard defaults.string(forKey: DefaultsKey.switcherWindowShortcut) == wrongDeveloperDefault else {
            return
        }
        defaults.set(GlobalShortcut.switcherWindowDefault.storageValue,
                     forKey: DefaultsKey.switcherWindowShortcut)
    }

    package static func migrateLegacyKeyboardDebounceWindow(in defaults: UserDefaults) {
        guard let storedWindow = defaults.object(forKey: DefaultsKey.keyboardDebounceWindowMs) as? Int,
              storedWindow == 30 || storedWindow == 10,
              defaults.bool(forKey: DefaultsKey.keyboardDebounceEnabled) == false,
              (defaults.string(forKey: DefaultsKey.keyboardDebounceKeyWindows) ?? "").isEmpty
        else { return }
        defaults.set(defaultKeyboardDebounceWindowMs, forKey: DefaultsKey.keyboardDebounceWindowMs)
    }

    package static func migrateUtilityOrderForScreenshot(in defaults: UserDefaults) {
        guard let storedOrder = defaults.object(forKey: DefaultsKey.panelUtilityOrder) as? String else {
            return
        }
        let ids = storedOrder.split(separator: ",").map(String.init)
        guard !ids.contains("screenshot") else { return }
        defaults.set((["screenshot"] + ids).joined(separator: ","),
                     forKey: DefaultsKey.panelUtilityOrder)
    }

    /// App updates joins the panel next to the other app-management tools
    /// instead of at the end of a long list, without disturbing the rest of
    /// a layout the user arranged.
    package static func migrateUtilityOrderForAppUpdates(in defaults: UserDefaults) {
        guard let storedOrder = defaults.object(forKey: DefaultsKey.panelUtilityOrder) as? String else {
            return
        }
        defaults.set(utilityOrderWithAppUpdates(storedOrder).joined(separator: ","),
                     forKey: DefaultsKey.panelUtilityOrder)
    }

    package static func utilityOrderWithAppUpdates(_ storedOrder: String) -> [String] {
        var ids = storedOrder.split(separator: ",").map(String.init)
        guard !ids.contains("appUpdates") else { return ids }
        let anchor = ids.firstIndex(of: "cleaner") ?? min(1, ids.count)
        ids.insert("appUpdates", at: anchor)
        return ids
    }

    package static func sanitizedDefaultDuration(_ minutes: Int) -> Int {
        allowedDurations.contains(minutes) ? minutes : 0
    }

    package static func sanitizedBatteryLimit(_ percent: Int) -> Int {
        allowedBatteryLimits.contains(percent) ? percent : 10
    }

    package static func sanitizedKeepAwakeMouseJiggleInterval(_ minutes: Int) -> Int {
        allowedKeepAwakeMouseJiggleIntervals.contains(minutes) ? minutes : 5
    }

    package static func sanitizedKeepAwakeIconTint(_ rawValue: String?) -> KeepAwakeIconTint {
        guard let rawValue,
              let tint = KeepAwakeIconTint(rawValue: rawValue) else {
            return .orange
        }
        return tint
    }

    package static func sanitizedKeepAwakeActiveIcon(_ rawValue: String?) -> KeepAwakeActiveIcon {
        guard let rawValue,
              let icon = KeepAwakeActiveIcon(rawValue: rawValue) else {
            return .vitruvian
        }
        return icon
    }

    /// A typed symbol name without the spaces around it; empty keeps the
    /// Vitruvian glyph. Whether this Mac has the symbol is left to the menu
    /// bar drawing, since a backup can carry a name from a newer macOS.
    package static func sanitizedMenuBarIconSymbol(_ rawValue: String?) -> String {
        rawValue?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    }

    /// What the menu bar icon field saves as it is typed: a name this Mac has
    /// a symbol for, nothing for the Vitruvian icon, and otherwise the name
    /// the field opened with, so a typo never leaves a valid half behind.
    package static func menuBarIconSymbolToSave(typed: String?, opening: String,
                                        exists: (String) -> Bool) -> String {
        let name = sanitizedMenuBarIconSymbol(typed)
        return name.isEmpty || exists(name) ? name : opening
    }

    /// The symbols the menu bar icon gallery offers after the Vitruvian icon:
    /// solid shapes that still read at menu bar size, all present on macOS 14
    /// (some under older names, which later versions still accept). Keep
    /// Awake's symbols stay out, so an active session still stands out.
    package static let menuBarIconGallery = [
        "bolt.fill", "star.fill", "heart.fill", "flame.fill", "sparkles", "leaf.fill",
        "drop.fill", "snowflake", "sun.max.fill", "moon.stars.fill", "cloud.fill", "mountain.2.fill",
        "circle.fill", "square.fill", "triangle.fill", "diamond.fill", "hexagon.fill", "seal.fill",
        "circle.lefthalf.filled", "circle.hexagongrid.fill", "infinity",
        "command", "cpu.fill", "memorychip.fill", "gauge.with.dots.needle.67percent",
        "fanblades.fill", "gearshape.fill", "terminal.fill", "waveform",
        "wand.and.stars", "key.fill", "crown.fill", "gamecontroller.fill", "headphones",
        "music.note", "paperplane.fill", "pawprint.fill", "cat.fill", "hare.fill", "tortoise.fill",
    ]

    package static func sanitizedMonitorInterval(_ seconds: Int) -> Int {
        allowedMonitorIntervals.contains(seconds) ? seconds : 2
    }

    /// Tap-to-middle-click accepts exactly three or four fingers; anything
    /// else means the option is off.
    package static func sanitizedMiddleClickTapFingers(_ raw: Int) -> Int {
        raw == 3 || raw == 4 ? raw : 0
    }

    package static func sanitizedKeyboardDebounceWindow(_ milliseconds: Int) -> Int {
        allowedKeyboardDebounceWindowRange.contains(milliseconds)
            ? milliseconds
            : defaultKeyboardDebounceWindowMs
    }

    package static func sanitizedMouseClickDebounceWindow(_ milliseconds: Int) -> Int {
        allowedMouseClickDebounceWindowRange.contains(milliseconds)
            ? milliseconds
            : defaultMouseClickDebounceWindowMs
    }

    /// Clamps rather than falling back to the default: a typed 4 becoming 5 is
    /// the correction the person meant, a typed 4 becoming 20 is not.
    package static func sanitizedClipboardAutoClearDelay(_ seconds: Int) -> Int {
        min(max(seconds, allowedClipboardAutoClearDelayRange.lowerBound),
            allowedClipboardAutoClearDelayRange.upperBound)
    }

    /// Same clamping reasoning as sanitizedClipboardAutoClearDelay above.
    package static func sanitizedClipboardMenuBarPreviewLength(_ characters: Int) -> Int {
        min(max(characters, allowedClipboardMenuBarPreviewLengthRange.lowerBound),
            allowedClipboardMenuBarPreviewLengthRange.upperBound)
    }

    package static func sanitizedMenuBarPreset(_ preset: String) -> String {
        allowedMenuBarPresets.contains(preset) ? preset : "dense"
    }

    package static func sanitizedMenuBarMetricSpacing(_ spacing: String) -> String {
        // Corrupt values fall back to the registered default (compact).
        allowedMenuBarMetricSpacings.contains(spacing) ? spacing : "compact"
    }

    package static func sanitizedMenuBarMetricAppearance(_ appearance: String) -> String {
        allowedMenuBarMetricAppearances.contains(appearance) ? appearance : "values"
    }

    package static func sanitizedMenuBarMetricOrder(_ raw: String) -> [String] {
        let defaults = defaultMenuBarMetricOrder
        var seen = Set<String>()
        var result: [String] = []
        for rawValue in raw.split(separator: ",").map({ String($0) }) {
            let values = rawValue == "temperature"
                ? ["cpuTemperature", "gpuTemperature", "batteryTemperature"]
                : [rawValue]
            for value in values {
                guard defaults.contains(value), !seen.contains(value) else { continue }
                seen.insert(value)
                result.append(value)
            }
        }
        for value in defaults where !seen.contains(value) {
            result.append(value)
        }
        return result
    }

    private static func migrateLegacyMenuBarTemperatureMetric(in defaults: UserDefaults) {
        guard let domainName = Bundle.main.bundleIdentifier,
              let domain = defaults.persistentDomain(forName: domainName),
              let legacyEnabled = domain[DefaultsKey.menuBarTemperature] as? Bool
        else { return }

        let newKeys = [
            DefaultsKey.menuBarCPUTemperature,
            DefaultsKey.menuBarGPUTemperature,
            DefaultsKey.menuBarBatteryTemperature,
        ]
        let alreadyMigrated = newKeys.contains { domain[$0] != nil }
        if legacyEnabled, !alreadyMigrated {
            for key in newKeys {
                defaults.set(true, forKey: key)
            }
        }
        if let rawOrder = domain[DefaultsKey.menuBarMetricOrder] as? String {
            defaults.set(sanitizedMenuBarMetricOrder(rawOrder).joined(separator: ","),
                         forKey: DefaultsKey.menuBarMetricOrder)
        }
        defaults.removeObject(forKey: DefaultsKey.menuBarTemperature)
    }

    package static func sanitizedMenuBarLabelStyle(_ style: String) -> String {
        allowedMenuBarLabelStyles.contains(style) ? style : "compact"
    }

    package static func sanitizedMenuBarMemoryStyle(_ style: String) -> String {
        allowedMenuBarMemoryStyles.contains(style) ? style : "percent"
    }

    package static func sanitizedMonitorMemoryMetric(_ metric: String) -> String {
        allowedMonitorMemoryMetrics.contains(metric) ? metric : "used"
    }

    package static func sanitizedClipboardHistoryLimit(_ value: Int) -> Int {
        allowedClipboardHistoryLimits.contains(value) ? value : 50
    }

    package static func sanitizedMonitorAlertCooldown(_ value: Int) -> Int {
        allowedMonitorAlertCooldowns.contains(value) ? value : 15
    }

    package static func sanitizedPercent(_ value: Int, fallback: Int, range: ClosedRange<Int>) -> Int {
        range.contains(value) ? value : fallback
    }

    package static func sanitizedBundleIdentifierList(_ bundleIDs: [String]) -> [String] {
        var seen = Set<String>()
        var result: [String] = []
        for raw in bundleIDs {
            // A mouse exception list also carries the path of a program that
            // has no bundle identifier (issue #1009), and a file name may
            // legally end in a space. Trimming one would store a spelling the
            // running program never reports, so only an identifier is trimmed.
            let bundleID = MouseAppExceptionSupport.isExecutablePathIdentity(raw)
                ? raw
                : raw.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !bundleID.isEmpty, !seen.contains(bundleID) else { continue }
            seen.insert(bundleID)
            result.append(bundleID)
        }
        return result
    }

    package static func sanitizedAutoQuitExceptions(_ bundleIDs: [String]) -> [String] {
        sanitizedBundleIdentifierList(mandatoryAutoQuitExceptionBundleIDs + bundleIDs)
    }

    package static func sanitizedDiskExclusionList(_ list: [String]) -> [String] {
        var seen = Set<String>()
        var result: [String] = []
        for raw in list {
            let item = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            let lower = item.lowercased()
            guard !item.isEmpty, seen.insert(lower).inserted else { continue }
            result.append(item)
        }
        return result
    }

    package static func sanitizedPanelItemOrder(_ raw: String, defaultOrder: [String]) -> [String] {
        let allowed = Set(defaultOrder)
        var seen = Set<String>()
        var result: [String] = []
        for id in raw.split(separator: ",").map(String.init) {
            guard allowed.contains(id), seen.insert(id).inserted else { continue }
            result.append(id)
        }
        for id in defaultOrder where seen.insert(id).inserted {
            result.append(id)
        }
        return result
    }

    package static func sanitizedAppVolume(_ volume: Double) -> Double {
        guard volume.isFinite else { return 1 }
        return min(max(volume, 0), 2)
    }

    /// The volume the speakers are set to when headphones disconnect. It is a
    /// protection against a sudden blast, not a mute, so it never goes low
    /// enough to leave the sound inaudible.
    package static let minimumMixerHeadphonesDisconnectVolumePercent = 10
    package static let defaultMixerHeadphonesDisconnectVolumePercent = 25

    package static func sanitizedMixerHeadphonesDisconnectVolumePercent(_ percent: Int) -> Int {
        min(max(percent, minimumMixerHeadphonesDisconnectVolumePercent), 100)
    }

    /// The option shipped with a stored value of 0, so ticking the box without
    /// touching the stepper silenced the speakers on the next disconnect. A
    /// value below the floor becomes the sane default.
    package static func migrateSilentHeadphonesDisconnectVolume(in defaults: UserDefaults) {
        guard let stored = defaults.object(forKey: DefaultsKey.mixerHeadphonesDisconnectVolumePercent) as? Int,
              stored < minimumMixerHeadphonesDisconnectVolumePercent else { return }
        defaults.set(defaultMixerHeadphonesDisconnectVolumePercent,
                     forKey: DefaultsKey.mixerHeadphonesDisconnectVolumePercent)
    }

    package static func sanitizedAppOutputDeviceUID(_ value: Any?) -> String? {
        MixerRoutingSupport.sanitizedDeviceUID(value)
    }

    package static func sanitizedAppOutputDevices(_ raw: [String: Any]) -> [String: String] {
        MixerRoutingSupport.sanitizedRouteMap(raw)
    }

    package static func sanitizedSoundOutputSwitcherDeviceUIDs(_ raw: [Any]) -> [String] {
        var seen = Set<String>()
        var result: [String] = []
        for value in raw {
            guard let uid = MixerRoutingSupport.sanitizedDeviceUID(value),
                  seen.insert(uid).inserted else { continue }
            result.append(uid)
        }
        return result
    }

    package static func sanitizedPreferredInputDeviceUID(_ value: Any?) -> String? {
        MixerRoutingSupport.sanitizedDeviceUID(value)
    }

    package static let audioPriorityMaxListSize = 64

    package static func sanitizedAudioPriorityUIDs(_ raw: [Any]) -> [String] {
        var seen = Set<String>()
        var result: [String] = []
        for value in raw {
            guard let uid = MixerRoutingSupport.sanitizedDeviceUID(value),
                  seen.insert(uid).inserted else { continue }
            result.append(uid)
            if result.count >= audioPriorityMaxListSize { break }
        }
        return result
    }

    package static func sanitizedAudioPriorityDeviceNames(_ raw: [String: Any]) -> [String: String] {
        var result: [String: String] = [:]
        for (rawUID, rawName) in raw {
            guard let uid = MixerRoutingSupport.sanitizedDeviceUID(rawUID),
                  let name = MixerRoutingSupport.sanitizedDeviceUID(rawName) else { continue }
            result[uid] = name
        }
        return result
    }
}
