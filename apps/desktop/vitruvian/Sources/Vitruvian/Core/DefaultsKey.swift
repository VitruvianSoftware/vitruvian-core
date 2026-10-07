// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Foundation

/// Every UserDefaults key used by the app, in one place.
package enum DefaultsKey {
    package static let language = "appLanguage"                   // AppLanguage.rawValue
    package static let appearance = "appAppearance"               // AppAppearance.rawValue
    package static let liquidGlassEnabled = "liquidGlassEnabled"  // Liquid Glass in windows and panels on macOS 26+
    package static let notchLiquidGlassEnabled = "notchLiquidGlassEnabled" // Dynamic Island glass, independently controlled
    package static let clamshellPreferred = "clamshellPreferred"  // apply closed-lid mode to every session
    package static let dimScreenOnLidClose = "dimScreenOnLidClose" // dim the built-in display to zero while the lid is closed
    package static let onboardingStep = "onboardingStep"          // resume point if onboarding is interrupted
    package static let featuresOnboardingVersion = "featuresOnboardingVersion" // last feature-tour marker handled
    package static let lastUpdateIntroVersion = "lastUpdateIntroVersion"
    package static let supportUpdateIntroVersion = "supportUpdateIntroVersion"
    package static let updateHighlightsSeenVersion = "updateHighlightsSeenVersion"
    package static let featureHubKeptFeatures = "featureHubKeptFeatures" // comma-joined AppFeature raw values
    package static let brightnessUpdatePromptState = "brightnessUpdatePromptState"
    package static let updateShowcaseIntroVersion = "updateShowcaseIntroVersion"
    package static let updateShowcaseMediaOverride = "updateShowcaseMediaOverride"
    package static let defaultDuration = "defaultDurationMinutes" // 0 = indefinite
    package static let batteryLimit = "batteryLimitPercent"       // 0 = never
    package static let keepAwakeAutoStart = "keepAwakeAutoStart"  // start Keep Awake when the app launches
    package static let keepAwakeRightClickToggle = "keepAwakeRightClickToggle"
    package static let keepAwakeAllowDisplaySleep = "keepAwakeAllowDisplaySleep"
    package static let keepAwakeExternalDisplay = "keepAwakeExternalDisplay"
    package static let keepAwakeConnectedToPower = "keepAwakeConnectedToPower"
    package static let keepAwakeRunningApps = "keepAwakeRunningApps"
    package static let keepAwakeRunningAppBundleIDs = "keepAwakeRunningAppBundleIDs"
    // Match mode over the automation conditions: false is Any (one matching
    // condition starts a session), true is All (every enabled condition has
    // to match, and losing one ends the session). Issue #1587.
    package static let keepAwakeAutomationRequireAll = "keepAwakeAutomationRequireAll"
    package static let keepAwakePauseWhenLocked = "keepAwakePauseWhenLocked"
    package static let keepAwakeSwitchUsesUntil = "keepAwakeSwitchUsesUntil" // panel switch restarts the Until chip
    package static let keepAwakeUntilTime = "keepAwakeUntilTime"  // last picked end time; 0 = none yet
    package static let keepAwakeMouseJiggleEnabled = "keepAwakeMouseJiggleEnabled"
    package static let keepAwakeMouseJiggleInterval = "keepAwakeMouseJiggleIntervalMinutes"
    package static let hotkeyEnabled = "hotkeyEnabled"
    package static let launchAtLoginWanted = "launchAtLoginWanted"  // the user's choice; the system record can be lost
    package static let keepAwakeShortcut = "keepAwakeShortcut"    // GlobalShortcut storage value
    package static let keepAwakeIconTint = "keepAwakeIconTint"    // KeepAwakeIconTint.rawValue
    package static let keepAwakeActiveIcon = "keepAwakeActiveIcon" // KeepAwakeActiveIcon.rawValue
    package static let showCountdown = "showCountdownInMenuBar"
    package static let statusItemPlacementGeneration = "statusItemPlacementGeneration"
    package static let hasOnboarded = "hasOnboarded"
    package static let sleepDisabledFlag = "vitruDisabledSleep"   // internal guard for pmset disablesleep
    package static let dimmedDisplaySavedBrightness = "vitruDimmedDisplaySavedBrightness" // internal guard for closed-lid screen dimming recovery
    package static let scrollInverterEnabled = "scrollInverterEnabled"
    package static let scrollInverterHorizontalEnabled = "scrollInverterHorizontalEnabled"
    package static let scrollHorizontalEnabled = "scrollHorizontalEnabled"
    package static let scrollHorizontalModifier = "scrollHorizontalModifier"
    package static let focusFollowsMouseEnabled = "focusFollowsMouseEnabled"
    package static let focusFollowsMouseRaise = "focusFollowsMouseRaise"
    package static let focusFollowsMouseWaitForStop = "focusFollowsMouseWaitForStop"
    package static let focusFollowsMouseDelay = "focusFollowsMouseDelayMilliseconds"
    package static let focusFollowsMouseExceptions = "focusFollowsMouseExceptions"
    package static let smoothScrollEnabled = "smoothScrollEnabled"
    package static let smoothScrollStep = "smoothScrollStep"      // pixels per wheel tick
    package static let linearScrollEnabled = "linearScrollEnabled" // every mouse wheel notch scrolls the same lines (issue #403)
    package static let linearScrollLines = "linearScrollLines"     // lines per wheel notch while linear scrolling is on
    package static let mouseAccelerationDisabled = "mouseAccelerationDisabled" // sets HIDMouseAcceleration to -1 for mice
    package static let smoothScrollResponse = "smoothScrollResponse" // 0...100, higher follows the wheel sooner
    package static let smoothScrollCoast = "smoothScrollCoast" // 0...100, higher coasts the same distance out longer
    package static let mouseNavigationEnabled = "mouseNavigationEnabled" // side buttons trigger Back and Forward
    package static let mouseButtonShortcutsEnabled = "mouseButtonShortcutsEnabled" // extra buttons press a key combination (issue #282)
    package static let mouseButtonShortcuts = "mouseButtonShortcuts" // [button number: GlobalShortcut storage value]
    package static let mouseSpacesGestureEnabled = "mouseSpacesGestureEnabled" // hold a button and drag to switch Spaces (issue #1012)
    package static let mouseSpacesGestureButton = "mouseSpacesGestureButton"   // button number, 0 while none is chosen
    package static let mouseSpacesGestureFollowsDrag = "mouseSpacesGestureFollowsDrag" // the Space moves with the hand, the way natural scrolling does
    package static let mouseClickDebounceEnabled = "mouseClickDebounceEnabled"
    package static let mouseClickDebounceWindowMs = "mouseClickDebounceWindowMs"
    package static let superKeyEnabled = "superKeyEnabled"        // chosen key holds the configured modifiers (issue #330)
    package static let superKeySource = "superKeySource"           // SuperKeySource raw value
    package static let superKeyModifiers = "superKeyModifiers"     // GlobalShortcutModifiers storage tokens
    package static let superKeySoloAction = "superKeySoloAction"  // SuperKeySoloAction raw value
    // Machine state, never exported: whether the keyboard mapping is in place
    // and which source to take back after a crash.
    package static let superKeyMappingApplied = "superKeyMappingApplied"
    package static let superKeyMappedSource = "superKeyMappedSource"
    // One list of bundle ids per mouse feature: apps it leaves alone (issue #358).
    package static let smoothScrollExceptions = "smoothScrollExceptions"
    package static let linearScrollExceptions = "linearScrollExceptions"
    package static let scrollInverterExceptions = "scrollInverterExceptions"
    package static let mouseNavigationExceptions = "mouseNavigationExceptions"
    package static let mouseButtonExceptions = "mouseButtonExceptions"
    package static let middleClickExceptions = "middleClickExceptions"
    package static let superKeyExceptions = "superKeyExceptions"
    package static let switcherEnabled = "switcherEnabled"
    package static let switcherTakeOverSystemShortcuts = "switcherTakeOverSystemShortcuts"
    // Machine state, never exported: the system shortcuts this process owns,
    // so a launch after a crash can restore them. The switcher-only key is
    // what builds before the take-over was shared wrote; it is read once,
    // folded into the shared one, and then retired.
    package static let switcherNativeHotkeysSuppressed = "switcherNativeHotkeysSuppressed"
    package static let systemShortcutsSuppressed = "systemShortcutsSuppressed"
    // Storage keys of shortcuts the user chose to take over from macOS. A
    // preference, exported.
    package static let systemShortcutTakeOverKeys = "systemShortcutTakeOverKeys"
    package static let switcherShortcut = "switcherShortcut"      // GlobalShortcut storage value
    package static let switcherWindowShortcut = "switcherWindowShortcut" // GlobalShortcut storage value
    package static let switcherIconRowMode = "switcherIconRowMode"
    package static let switcherSimpleMode = "switcherSimpleMode"  // app-only row without window captures
    package static let switcherMergeTabs = "switcherMergeTabs"     // show one switcher entry per app (collapse all of an app's windows)
    package static let switcherShowWindowlessFinder = "switcherShowWindowlessFinder" // replaced by switcherWindowlessApps, kept so the migration can read it
    package static let switcherWindowlessApps = "switcherWindowlessApps" // SwitcherWindowlessApps raw value
    package static let switcherMinimizedPlacement = "switcherMinimizedPlacement"
    package static let switcherTreatHiddenAppsLikeMinimized = "switcherTreatHiddenAppsLikeMinimized"
    package static let switcherShowFullscreenWindows = "switcherShowFullscreenWindows"
    package static let switcherAppRules = "switcherAppRules" // [bundle id: SwitcherAppRule raw value]
    package static let switcherCurrentSpaceOnly = "switcherCurrentSpaceOnly" // list only windows on the desktop the user is in (issue #337)
    package static let switcherSearchPinEnabled = "switcherSearchPinEnabled" // S pins the search field open, off by default so existing users typing S as a search letter see no change
    package static let switcherShowShortcutHints = "switcherShowShortcutHints" // show the shortcut bar under the large-icon switcher
    package static let switcherAppearanceDelay = "switcherAppearanceDelay" // milliseconds the shortcut must be held before the panel appears (SwitcherSupport.appearanceDelayMillisecondsRange)
    package static let switcherInstantSelection = "switcherInstantSelection" // skip selection and reveal animations while browsing
    package static let switcherScreenPlacement = "switcherScreenPlacement" // SwitcherScreenPlacement raw value: which display the panel opens on
    package static let switcherCurrentDisplayOnly = "switcherCurrentDisplayOnly" // list only windows on the display under the pointer (issue #1391)
    package static let minimalWindowPreviews = "minimalWindowPreviews"
    package static let dockPreviewEnabled = "dockPreviewEnabled"
    package static let dockPreviewKeepDockVisible = "dockPreviewKeepDockVisible"
    package static let dockPreviewRestoreAutohide = "dockPreviewRestoreAutohide" // local crash recovery; never backed up
    package static let dockPreviewCurrentSpaceOnly = "dockPreviewCurrentSpaceOnly"
    package static let dockPreviewBackgroundOpacity = "dockPreviewBackgroundOpacity" // how solid the preview panel's material is drawn (DockPreviewSupport.backgroundOpacityRange)
    package static let dockPreviewOpenDelay = "dockPreviewOpenDelay" // milliseconds the cursor must rest on a Dock icon before its panel opens (DockPreviewSupport.openDelayMillisecondsRange)
    package static let dockPreviewQuitAppOnClose = "dockPreviewQuitAppOnClose" // the preview card's close button quits the owning app instead of closing one window
    package static let dockPreviewOrderByCreation = "dockPreviewOrderByCreation" // order Dock Preview windows by ascending window ID (creation proxy) instead of last use
    package static let dockClickMinimize = "dockClickMinimize"    // click the active app's Dock icon to minimize its windows
    package static let dockClickHide = "dockClickHide"            // click the active app's Dock icon to hide the app
    package static let dockClickCycleWindows = "dockClickCycleWindows" // click the active app's Dock icon to cycle through its windows
    package static let spacesOrderEnabled = "spacesOrderEnabled" // keeps macOS from rearranging Spaces by recent use (Dock mru-spaces)
    package static let spacesOrderRestore = "spacesOrderRestore" // local recovery; never backed up: "absent" or "on", the mru-spaces state to put back, or "off" when there was nothing to put back
    package static let spacesOrderRestartPending = "spacesOrderRestartPending" // local recovery; never backed up: "<Dock pid> <fixed|rearranging> <absent|on|off>…", the Dock process that owes the restart reading a written mru-spaces, what it runs and the values written under it
    package static let middleClickEnabled = "middleClickEnabled"  // three-finger PHYSICAL click on the trackpad acts as a middle click
    package static let middleClickTapFingers = "middleClickTapFingers"  // 0 = off (default); 3 or 4 = a light tap with that many fingers also middle-clicks (issue #161)
    package static let previewSize = "previewSize"                // dock preview thumbnail size (once shared with the app switcher)
    package static let switcherPreviewSize = "switcherPreviewSize" // app switcher thumbnail size
    package static let autoCheckUpdates = "autoCheckUpdates"
    package static let includeBetaUpdates = "includeBetaUpdates"
    package static let releaseNotesOnUpdate = "releaseNotesOnUpdate" // show What's New after an update
    package static let appVolumes = "appVolumes"                  // [bundle id: 0...2]
    package static let appOutputDevices = "appOutputDevices"      // [bundle id: audio device UID]
    package static let mixerShowFinder = "mixerShowFinder"
    package static let mixerAppArrangement = "mixerAppArrangement"
    package static let mixerHideInactiveApps = "mixerHideInactiveApps"
    package static let mixerHiddenApps = "mixerHiddenApps"        // [persistence id: display name] kept out of the mixer list (issue #300)
    package static let mixerLowerVolumeOnHeadphonesDisconnect = "mixerLowerVolumeOnHeadphonesDisconnect"
    package static let mixerHeadphonesDisconnectVolumePercent = "mixerHeadphonesDisconnectVolumePercent"
    package static let preciseVolumeRollerEnabled = "preciseVolumeRollerEnabled"
    package static let soundOutputSwitcherEnabled = "soundOutputSwitcherEnabled"
    package static let soundOutputSwitcherShortcut = "soundOutputSwitcherShortcut"
    package static let soundOutputSwitcherDeviceUIDs = "soundOutputSwitcherDeviceUIDs"
    // Audio device priority: ordered output and microphone lists the feature
    // enforces automatically when its enable flags are on.
    package static let audioPriorityOutputEnabled = "audioPriorityOutputEnabled"
    package static let audioPriorityInputEnabled = "audioPriorityInputEnabled"
    package static let audioPriorityOutputUIDs = "audioPriorityOutputUIDs"    // [String] ordered device UIDs
    package static let audioPriorityInputUIDs = "audioPriorityInputUIDs"     // [String] ordered device UIDs
    package static let audioPriorityDeviceNames = "audioPriorityDeviceNames" // [uid: name] last-known names
    package static let preferredInputDevice = "preferredInputDevice" // audio input device UID
    package static let finderCutPasteEnabled = "finderCutPasteEnabled"
    package static let finderCutPasteShowHUD = "finderCutPasteShowHUD"
    package static let finderRenameEnabled = "finderRenameEnabled"
    package static let finderRenameShortcut = "finderRenameShortcut"
    package static let diskImageInstallerTrashesDownload = "diskImageInstallerTrashesDownload"
    package static let diskImageInstallerRevealsApp = "diskImageInstallerRevealsApp"
    package static let finderPasteImageAsFile = "finderPasteImageAsFile"
    package static let diskImageInstallerUseUserApplications = "diskImageInstallerUseUserApplications"
    package static let autoQuitEnabled = "autoQuitEnabled"
    package static let autoQuitExceptions = "autoQuitExceptions"  // [bundle id] kept running
    // Quit/close protection: each shortcut owns its full configuration and app list.
    package static let quitProtectionQuitEnabled = "quitProtectionQuitEnabled"
    package static let quitProtectionQuitMode = "quitProtectionQuitMode"
    package static let quitProtectionQuitHoldDurationMs = "quitProtectionQuitHoldDurationMs"
    package static let quitProtectionQuitDoubleIntervalMs = "quitProtectionQuitDoubleIntervalMs"
    package static let quitProtectionQuitExtraModifier = "quitProtectionQuitExtraModifier"
    package static let quitProtectionQuitScope = "quitProtectionQuitScope"
    package static let quitProtectionQuitExceptions = "quitProtectionQuitExceptions"
    package static let quitProtectionQuitShowFeedback = "quitProtectionQuitShowFeedback"
    package static let quitProtectionCloseEnabled = "quitProtectionCloseEnabled"
    package static let quitProtectionCloseMode = "quitProtectionCloseMode"
    package static let quitProtectionCloseHoldDurationMs = "quitProtectionCloseHoldDurationMs"
    package static let quitProtectionCloseDoubleIntervalMs = "quitProtectionCloseDoubleIntervalMs"
    package static let quitProtectionCloseExtraModifier = "quitProtectionCloseExtraModifier"
    package static let quitProtectionCloseScope = "quitProtectionCloseScope"
    package static let quitProtectionCloseExceptions = "quitProtectionCloseExceptions"
    package static let quitProtectionCloseShowFeedback = "quitProtectionCloseShowFeedback"
    package static let shelfEnabled = "shelfEnabled"
    package static let shelfShortcutEnabled = "shelfShortcutEnabled"
    package static let shelfShortcut = "shelfShortcut"            // GlobalShortcut storage value
    package static let shelfShakeToOpen = "shelfShakeToOpen"
    package static let shelfDropZoneEnabled = "shelfDropZoneEnabled"
    package static let shelfDockPlacement = "shelfDockPlacement"   // ShelfDockPlacement raw value
    package static let shelfEdgeDragEnabled = "shelfEdgeDragEnabled"
    package static let shelfCloseAfterDrop = "shelfCloseAfterDrop"
    package static let shelfRemoveAfterDrop = "shelfRemoveAfterDrop"
    package static let shelfClearOnClose = "shelfClearOnClose"
    package static let shelfShortcutAddsFinderSelection = "shelfShortcutAddsFinderSelection"
    package static let shelfAutomaticExclusions = "shelfAutomaticExclusions" // [bundle id] blocks automatic opening only
    package static let extraBrightnessEnabled = "extraBrightnessEnabled"
    package static let extraBrightnessLevel = "extraBrightnessLevel"   // Int percent 0-100
    package static let brightnessControlEnabled = "brightnessControlEnabled" // sliders for every display
    package static let brightnessKeysEnabled = "brightnessKeysEnabled" // brightness keys act on the display under the pointer
    package static let brightnessOSDEnabled = "brightnessOSDEnabled" // brightness adjustment overlay
    package static let brightnessKeyStep = "brightnessKeyStep" // BrightnessSupport.KeyStep raw value
    package static let displayBrightnessShortcutsEnabled = "displayBrightnessShortcutsEnabled"
    package static let displayBrightnessDecreaseShortcut = "displayBrightnessDecreaseShortcut"
    package static let displayBrightnessIncreaseShortcut = "displayBrightnessIncreaseShortcut"
    package static let keyboardBrightnessShortcutsEnabled = "keyboardBrightnessShortcutsEnabled"
    package static let keyboardBrightnessDecreaseShortcut = "keyboardBrightnessDecreaseShortcut"
    package static let keyboardBrightnessIncreaseShortcut = "keyboardBrightnessIncreaseShortcut"
    // Per-monitor connection paths that accept brightness writes but never
    // answer reads. Kept local so wake handling does not repeatedly probe a
    // sensitive display path.
    package static let brightnessDDCWriteOnlyPaths = "brightnessDDCWriteOnlyPaths"
    // Set once the paths cached before paired discovery requests have been
    // dropped, so a monitor written off then is classified again exactly once.
    package static let brightnessDDCWriteOnlyPathsRechecked = "brightnessDDCWriteOnlyPathsRechecked"
    /// A beta already installed the companion for this Command Bar user, once.
    package static let notchMascotBetaInstalled = "notchMascotBetaInstalled"
    // Per-monitor connection paths a person has told this app to dim in
    // software: the only way to know a write-only channel swallows its writes
    // is to watch the panel, which no probe can do. Issue #1589.
    package static let brightnessForcedSoftwarePaths = "brightnessForcedSoftwarePaths"
    // Per-monitor connections where the lower end of the brightness slider
    // also dims the picture below the panel's hardware minimum.
    package static let brightnessExtendedDimmingPaths = "brightnessExtendedDimmingPaths"
    // Displays this app switched off, so a run that ends without putting them
    // back can be repaired on the next start instead of needing a replug.
    package static let displaysSwitchedOff = "displaysSwitchedOff"
    // Identity saved before disabling each display, kept separate so older
    // versions can still read the repair list of display numbers.
    package static let displaysSwitchedOffFingerprints = "displaysSwitchedOffFingerprints"
    // Set while a start is under way and cleared once the app has run
    // healthily for a while, or when it is quit properly. Found still set at
    // the next start, it means the previous one died on the way up.
    package static let startupDidNotFinish = "startupDidNotFinish"
    package static let bluetoothSleepEnabled = "bluetoothSleepEnabled"
    package static let bluetoothSleepRestoreOnWake = "bluetoothSleepRestoreOnWake"
    // Set only while Vitruvian owes a Bluetooth restore, so a Mac shut down
    // while asleep still gets it back on the next launch.
    package static let bluetoothSleepRestorePending = "bluetoothSleepRestorePending"
    package static let musicBlockEnabled = "musicBlockEnabled"
    package static let musicBlockReplacementPath = "musicBlockReplacementPath"  // app bundle path ("" = none)
    package static let musicBlockPlayReplacement = "musicBlockPlayReplacement" // play after Play/Pause opens the replacement
    package static let cleanerScheduleFrequency = "cleanerScheduleFrequency"    // off | daily | weekly
    package static let cleanerScheduleHour = "cleanerScheduleHour"
    package static let cleanerScheduleMinute = "cleanerScheduleMinute"
    package static let cleanerScheduleWeekday = "cleanerScheduleWeekday"        // 1 Sunday ... 7 Saturday
    package static let cleanerScheduleNotify = "cleanerScheduleNotify"
    package static let cleanerLastAutoRun = "cleanerLastAutoRun"                // Double, epoch seconds
    package static let cleanerLastAutoFreed = "cleanerLastAutoFreed"            // Int bytes
    package static let cleanerLastAutoFailed = "cleanerLastAutoFailed"          // Int items left in place
    package static let cleanerScreenshotAgeDays = "cleanerScreenshotAgeDays"    // Int, 0 = off
    // Confirmed WhatsApp downloads in the top level of ~/Downloads.
    package static let whatsAppDownloadsEnabled = "whatsAppDownloadsEnabled"
    package static let whatsAppDownloadsAutomaticEnabled = "whatsAppDownloadsAutomaticEnabled"
    package static let whatsAppDownloadsCategories = "whatsAppDownloadsCategories" // comma-joined category ids
    package static let whatsAppDownloadsRetentionDays = "whatsAppDownloadsRetentionDays"
    package static let whatsAppDownloadsNotify = "whatsAppDownloadsNotify"
    package static let whatsAppDownloadsIncludeExisting = "whatsAppDownloadsIncludeExisting"
    package static let whatsAppDownloadsAutomaticStartDate = "whatsAppDownloadsAutomaticStartDate"
    package static let whatsAppDownloadsLastAutoRun = "whatsAppDownloadsLastAutoRun"
    package static let whatsAppDownloadsLastCleanup = "whatsAppDownloadsLastCleanup"
    package static let whatsAppDownloadsLastCleanupCount = "whatsAppDownloadsLastCleanupCount"
    package static let whatsAppDownloadsLastCleanupBytes = "whatsAppDownloadsLastCleanupBytes"
    package static let whatsAppDownloadsLastCleanupFailed = "whatsAppDownloadsLastCleanupFailed"
    package static let whatsAppDownloadsLastCleanupAutomatic = "whatsAppDownloadsLastCleanupAutomatic"
    package static let whatsAppDownloadsExclusions = "whatsAppDownloadsExclusions" // device:inode ids
    package static let whatsAppDownloadsAccessConfirmed = "whatsAppDownloadsAccessConfirmed"
    // Experimental organizer for confirmed WhatsApp downloads.
    package static let whatsAppOrganizerEnabled = "whatsAppOrganizerEnabled"
    package static let whatsAppOrganizerDestinationPath = "whatsAppOrganizerDestinationPath"
    package static let whatsAppOrganizerDelayMinutes = "whatsAppOrganizerDelayMinutes"
    package static let whatsAppOrganizerCategories = "whatsAppOrganizerCategories"
    package static let whatsAppOrganizerLayout = "whatsAppOrganizerLayout"
    package static let whatsAppOrganizerDuplicateAction = "whatsAppOrganizerDuplicateAction"
    package static let whatsAppOrganizerRecords = "whatsAppOrganizerRecords"
    package static let whatsAppOrganizerUndoTransaction = "whatsAppOrganizerUndoTransaction"
    package static let whatsAppOrganizerLastRun = "whatsAppOrganizerLastRun"
    package static let whatsAppOrganizerLastMoved = "whatsAppOrganizerLastMoved"
    package static let whatsAppOrganizerLastDuplicates = "whatsAppOrganizerLastDuplicates"
    package static let whatsAppOrganizerLastFailed = "whatsAppOrganizerLastFailed"
    package static let settingsWindowWidth = "settingsWindowWidth"     // last user-chosen content size (0 = unset)
    package static let settingsWindowHeight = "settingsWindowHeight"
    package static let shelfItems = "shelfItems"                  // Data: [ShelfPersistedItem] JSON
    package static let urlCleanerEnabled = "urlCleanerEnabled"
    package static let urlCleanerCustomParameters = "urlCleanerCustomParameters"
    package static let urlCleanerSiteParameters = "urlCleanerSiteParameters"       // host|name pairs added to one site
    package static let urlCleanerDisabledParameters = "urlCleanerDisabledParameters" // built-in host|name pairs switched off
    package static let windowMaximizeEnabled = "windowMaximizeEnabled"
    package static let windowMaximizeExcludedApps = "windowMaximizeExcludedApps" // [bundle id] whose green button stays native
    package static let keyboardDebounceEnabled = "keyboardDebounceEnabled"
    package static let keyboardDebounceWindowMs = "keyboardDebounceWindowMs"
    package static let keyboardDebounceKeyWindows = "keyboardDebounceKeyWindows" // comma-separated keyCode:ms
    package static let panelUtilityCleaning = "panelUtilityCleaning"
    package static let cleaningModeKeepScreenVisible = "cleaningModeKeepScreenVisible"
    package static let panelUtilityURLCleaner = "panelUtilityURLCleaner"
    package static let panelUtilityUninstaller = "panelUtilityUninstaller"
    package static let uninstallerCommandBarEnabled = "uninstallerCommandBarEnabled"
    package static let killProcessCommandBarEnabled = "killProcessCommandBarEnabled"
    package static let killProcessGroupRelated = "killProcessGroupRelated"
    package static let killProcessSortBy = "killProcessSortBy" // cpu | memory | name | pid
    package static let killProcessSortAscending = "killProcessSortAscending"
    package static let panelUtilityCleaner = "panelUtilityCleaner"
    package static let panelUtilityHomebrew = "panelUtilityHomebrew"
    package static let homebrewGroupDependencies = "homebrewGroupDependencies"
    package static let panelUtilityAppUpdates = "panelUtilityAppUpdates"
    package static let appUpdatesCheckFrequency = "appUpdatesCheckFrequency"  // off | daily | weekly
    package static let appUpdatesIncludeHomebrewApps = "appUpdatesIncludeHomebrewApps"
    package static let appUpdatesIncludeAppStore = "appUpdatesIncludeAppStore"
    package static let appUpdatesIncludeOnlineCatalog = "appUpdatesIncludeOnlineCatalog"
    package static let appUpdatesNotify = "appUpdatesNotify"
    package static let appUpdatesRules = "appUpdatesRules" // JSON, portable bundle-ID rules
    package static let appUpdatesLastCheck = "appUpdatesLastCheck"            // Double, epoch seconds
    package static let appUpdatesLastCount = "appUpdatesLastCount"
    // Findings already announced once, so a pending update nobody installs
    // does not speak up again after every relaunch.
    package static let appUpdatesNotifiedIDs = "appUpdatesNotifiedIDs"
    package static let panelUtilityMedia = "panelUtilityMedia"
    package static let panelUtilityClipboard = "panelUtilityClipboard"
    package static let panelUtilityWindowLayout = "panelUtilityWindowLayout"
    package static let panelControlMouseScroll = "panelControlMouseScroll"
    package static let panelControlFocusFollowsMouse = "panelControlFocusFollowsMouse"
    package static let panelControlMouseNavigation = "panelControlMouseNavigation"
    package static let panelControlSwitcher = "panelControlSwitcher"
    package static let panelControlDockPreview = "panelControlDockPreview"
    package static let panelControlCutPaste = "panelControlCutPaste"
    package static let panelControlAutoQuit = "panelControlAutoQuit"
    package static let panelControlShelf = "panelControlShelf"
    package static let panelControlWindowMaximize = "panelControlWindowMaximize"
    package static let panelControlKeyDebounce = "panelControlKeyDebounce"
    package static let panelControlDockClick = "panelControlDockClick"
    package static let panelControlDockClickHide = "panelControlDockClickHide"
    package static let panelControlDockClickCycle = "panelControlDockClickCycle"
    package static let panelControlMiddleClick = "panelControlMiddleClick"
    package static let panelControlTextSnippets = "panelControlTextSnippets"
    package static let panelControlSuperKey = "panelControlSuperKey"
    package static let panelControlRadialMenu = "panelControlRadialMenu"
    package static let panelControlMouseButtonShortcuts = "panelControlMouseButtonShortcuts"
    package static let panelControlMouseAcceleration = "panelControlMouseAcceleration"
    package static let panelControlLinearScroll = "panelControlLinearScroll"
    package static let panelControlMouseClickDebounce = "panelControlMouseClickDebounce"
    package static let panelControlSpacesOrder = "panelControlSpacesOrder"
    // Quick-control categories start collapsed and remember being opened.
    package static let panelControlWindowsExpanded = "panelControlWindowsExpanded"
    package static let panelControlInputExpanded = "panelControlInputExpanded"
    package static let panelControlFilesExpanded = "panelControlFilesExpanded"
    // Show/hide whole panel sections that have no monitorShow* key of their own.
    package static let panelShowKeepAwake = "panelShowKeepAwake"
    package static let panelShowBrightness = "panelShowBrightness"
    package static let panelShowUtilities = "panelShowUtilities"
    package static let panelShowControls = "panelShowControls"
    package static let panelShowToggles = "panelShowToggles"
    package static let panelShowWallpaper = "panelShowWallpaper"
    // Quick toggles tab: per-action visibility (the order lives in panelToggleOrder).
    package static let panelToggleDarkMode = "panelToggleDarkMode"
    package static let panelToggleKeyboardLight = "panelToggleKeyboardLight"
    // Keep the existing storage key so moving the row preserves its visibility choice.
    package static let panelToggleMicMute = "panelUtilityMicMute"
    package static let panelToggleEmptyTrash = "panelToggleEmptyTrash"
    package static let panelToggleEjectDisks = "panelToggleEjectDisks"
    package static let panelToggleHiddenFiles = "panelToggleHiddenFiles"
    package static let panelToggleDesktopIcons = "panelToggleDesktopIcons"
    package static let panelToggleLockScreen = "panelToggleLockScreen"
    package static let panelToggleDisplayOff = "panelToggleDisplayOff"
    package static let panelToggleScreenSaver = "panelToggleScreenSaver"

    // System monitor — live metrics shown next to the menu bar icon (opt-in).
    package static let menuBarCPU = "menuBarCPU"
    package static let menuBarGPU = "menuBarGPU"
    package static let menuBarMemory = "menuBarMemory"
    package static let menuBarCPUTemperature = "menuBarCPUTemperature"
    package static let menuBarGPUTemperature = "menuBarGPUTemperature"
    package static let menuBarBatteryTemperature = "menuBarBatteryTemperature"
    package static let menuBarTemperature = "menuBarTemperature" // legacy Developer key for the old generic temperature metric
    package static let menuBarNetwork = "menuBarNetwork"
    package static let menuBarDiskUsage = "menuBarDiskUsage"
    package static let menuBarDiskActivity = "menuBarDiskActivity"
    package static let menuBarBattery = "menuBarBattery"
    package static let menuBarBatteryTime = "menuBarBatteryTime"
    package static let menuBarPeripheralBattery = "menuBarPeripheralBattery"
    package static let menuBarConnectedDevices = "menuBarConnectedDevices"
    package static let menuBarPower = "menuBarPower"
    package static let menuBarFanSpeed = "menuBarFanSpeed"
    package static let menuBarPreset = "menuBarPreset"           // dense
    package static let menuBarMetricSpacing = "menuBarMetricSpacing" // standard | compact
    package static let menuBarMetricAppearance = "menuBarMetricAppearance" // values | bars
    package static let menuBarUsageBarNormalColor = "menuBarUsageBarNormalColor" // #RRGGBB
    package static let menuBarUsageBarElevatedColor = "menuBarUsageBarElevatedColor" // #RRGGBB
    package static let menuBarUsageBarCriticalColor = "menuBarUsageBarCriticalColor" // #RRGGBB
    package static let menuBarUsageBarMediumThreshold = "menuBarUsageBarMediumThreshold" // percent
    package static let menuBarUsageBarHighThreshold = "menuBarUsageBarHighThreshold" // percent
    package static let menuBarHideIconWithMetrics = "menuBarHideIconWithMetrics" // glyph hides while metrics render in the main item
    package static let menuBarIconSymbol = "menuBarIconSymbol" // system symbol name drawn instead of the glyph; empty keeps the glyph
    package static let menuBarMetricOrder = "menuBarMetricOrder" // comma-separated MenuBarMetric raw values
    package static let menuBarCombineTemperatures = "menuBarCombineTemperatures" // usage/charge + temperature in one block when possible
    package static let menuBarSeparateMetrics = "menuBarSeparateMetrics" // one status item per active metric
    package static let menuBarNetworkUploadFirst = "menuBarNetworkUploadFirst" // network menu bar block shows upload above download
    package static let menuBarLabelStyle = "menuBarLabelStyle"     // compact | classic
    package static let menuBarMemoryStyle = "menuBarMemoryStyle"   // dot | percent | both
    package static let menuBarDiskStyle = "menuBarDiskStyle"       // percent | free | used
    package static let monitorMemoryMetric = "monitorMemoryMetric" // used | app
    package static let monitorInterval = "monitorIntervalSeconds"  // sampling cadence: 1/2/5
    package static let temperatureUnit = "temperatureUnit"          // celsius | fahrenheit
    // System monitor — which blocks appear in the panel.
    package static let monitorShowSystem = "monitorShowSystem"
    package static let monitorShowNetwork = "monitorShowNetwork"
    package static let monitorShowDisk = "monitorShowDisk"
    package static let monitorShowPower = "monitorShowPower"
    package static let monitorShowMixer = "monitorShowMixer"
    package static let panelShowFanControl = "panelShowFanControl"
    package static let fanControlMode = "fanControlMode"
    package static let fanControlCoolingLevel = "fanControlCoolingLevel"
    package static let fanControlCurves = "fanControlCurves"
    // Re-apply the last manual speed or curve when the app opens and after wake.
    package static let fanControlResume = "fanControlResume"
    // Machine-only: the control the user left running while resume is on,
    // cleared when they return to System so it never outlives that choice.
    package static let fanControlResumeConfiguration = "fanControlResumeConfiguration"
    // Previous panel visibility key, read once by the migration below.
    package static let monitorShowFanControlBeta = "monitorShowFanControlBeta"
    // Machine-only recovery state. A true value means the helper must confirm
    // automatic fan control before this marker can be cleared.
    package static let fanControlRecoveryNeeded = "fanControlRecoveryNeeded"
    package static let fanControlHelperVersion = "fanControlHelperVersion"
    // System monitor — per-metric history graphs (each independently toggleable).
    package static let monitorGraphCPU = "monitorGraphCPU"
    package static let monitorGraphGPU = "monitorGraphGPU"
    package static let monitorGraphMemory = "monitorGraphMemory"
    package static let monitorGraphNetwork = "monitorGraphNetwork"
    package static let monitorGraphDisk = "monitorGraphDisk"
    package static let monitorGraphPower = "monitorGraphPower"
    package static let monitorGraphBattery = "monitorGraphBattery"
    package static let monitorGraphScale = "monitorGraphScale"
    // System monitor — per-item visibility inside each panel section.
    package static let monitorSysTemps = "monitorSysTemps"
    package static let monitorSysCPU = "monitorSysCPU"
    package static let monitorSysGPU = "monitorSysGPU"
    package static let monitorSysBattery = "monitorSysBattery"
    package static let monitorSysMemory = "monitorSysMemory"
    package static let monitorSysAlerts = "monitorSysAlerts"
    package static let monitorSysUptime = "monitorSysUptime"
    package static let monitorNetSpeed = "monitorNetSpeed"
    package static let monitorNetApps = "monitorNetApps"
    package static let monitorNetTotals = "monitorNetTotals"
    package static let monitorNetAddresses = "monitorNetAddresses"
    package static let monitorNetTest = "monitorNetTest"
    package static let monitorDiskUsage = "monitorDiskUsage"
    package static let monitorDiskActivity = "monitorDiskActivity"
    package static let monitorDiskSMART = "monitorDiskSMART"
    package static let monitorDiskProtection = "monitorDiskProtection"
    package static let monitorDiskTools = "monitorDiskTools"
    package static let monitorPwrTemperature = "monitorPwrTemperature"
    package static let monitorPwrSystem = "monitorPwrSystem"
    package static let monitorPwrAdapter = "monitorPwrAdapter"
    package static let monitorPwrBattery = "monitorPwrBattery"
    package static let monitorPwrTimeRemaining = "monitorPwrTimeRemaining"
    package static let monitorPwrHealth = "monitorPwrHealth"
    // System monitor — optional notifications for sustained or actionable conditions.
    package static let monitorAlertCPU = "monitorAlertCPU"
    package static let monitorAlertCPUTemperature = "monitorAlertCPUTemperature"
    package static let monitorAlertBatteryTemperature = "monitorAlertBatteryTemperature"
    package static let monitorAlertMemory = "monitorAlertMemory"
    package static let monitorAlertDisk = "monitorAlertDisk"
    package static let monitorAlertBattery = "monitorAlertBattery"
    package static let monitorAlertCPUThreshold = "monitorAlertCPUThreshold"
    package static let monitorAlertCPUTemperatureThreshold = "monitorAlertCPUTemperatureThreshold"
    package static let monitorAlertBatteryTemperatureThreshold = "monitorAlertBatteryTemperatureThreshold"
    package static let monitorAlertDiskFreePercent = "monitorAlertDiskFreePercent"
    package static let monitorAlertBatteryPercent = "monitorAlertBatteryPercent"
    package static let monitorAlertCooldownMinutes = "monitorAlertCooldownMinutes"
    // Menu panel layout — the order the major sections appear in and which are
    // collapsed, both comma-joined section ids (see PanelSectionID). Absent keys
    // mean the canonical order and nothing collapsed, so no defaults registration.
    package static let panelSectionOrder = "panelSectionOrder"
    package static let panelUtilityOrder = "panelUtilityOrder"
    package static let panelControlOrder = "panelControlOrder"
    package static let panelToggleOrder = "panelToggleOrder"
    package static let panelSystemOrder = "panelSystemOrder"
    package static let panelNetworkOrder = "panelNetworkOrder"
    package static let panelDiskOrder = "panelDiskOrder"
    package static let panelPowerOrder = "panelPowerOrder"
    package static let panelNavigationEnabled = "panelNavigationEnabled" // legacy: the panel always navigates by sections since 3.1.8
    package static let updateLastInstallFailure = "updateLastInstallFailure" // last installer step that failed (fail-copy etc.)
    package static let windowLayoutHiddenActions = "windowLayoutHiddenActions" // comma-separated action ids hidden from the grid
    package static let windowLayoutWindowGap = "windowLayoutWindowGap" // px between adjacent snapped windows
    package static let windowLayoutScreenGap = "windowLayoutScreenGap" // px between a snapped window and the visible frame edge
    package static let windowLayoutMarginPercent = "windowLayoutMarginPercent" // per-edge percentage for margin maximize
    package static let windowLayoutSideRepeatCyclesThirds = "windowLayoutSideRepeatCyclesThirds" // repeated Left/Right cycles half, 2/3, 1/3 on the same display
    package static let windowLayoutIgnoredApps = "windowLayoutIgnoredApps" // apps that temporarily disable window layout while focused
    package static let panelCollapsedSections = "panelCollapsedSections"
    package static let panelCollapsedResetVersion = "panelCollapsedResetVersion"

    // Media utility — local video, GIF, image and OCR tools.
    package static let mediaLastTool = "mediaLastTool"
    package static let mediaVideoStart = "mediaVideoStart"
    package static let mediaVideoEnd = "mediaVideoEnd"
    package static let mediaVideoQuality = "mediaVideoQuality"
    package static let mediaVideoMaxDimension = "mediaVideoMaxDimension"
    package static let mediaVideoFPS = "mediaVideoFPS"
    package static let mediaVideoKeepAudio = "mediaVideoKeepAudio"
    package static let mediaVideoCodec = "mediaVideoCodec"
    package static let mediaVideoSizing = "mediaVideoSizing"
    package static let mediaVideoTargetMegabytes = "mediaVideoTargetMegabytes"
    package static let mediaGIFStart = "mediaGIFStart"
    package static let mediaGIFEnd = "mediaGIFEnd"
    package static let mediaGIFQuality = "mediaGIFQuality"
    package static let mediaGIFWidth = "mediaGIFWidth"
    package static let mediaGIFFPS = "mediaGIFFPS"
    package static let mediaGIFLoops = "mediaGIFLoops"
    package static let mediaGIFSizing = "mediaGIFSizing"
    package static let mediaGIFTargetMegabytes = "mediaGIFTargetMegabytes"
    package static let mediaImageQuality = "mediaImageQuality"
    package static let mediaImageMaxDimension = "mediaImageMaxDimension"
    package static let mediaImageFormat = "mediaImageFormat"
    package static let mediaImageStripMetadata = "mediaImageStripMetadata"
    package static let mediaImageResizeKind = "mediaImageResizeKind"
    package static let mediaImageResizeWidth = "mediaImageResizeWidth"
    package static let mediaImageResizeHeight = "mediaImageResizeHeight"
    package static let mediaImageExactResizeMode = "mediaImageExactResizeMode"
    package static let mediaImageWatermarkKind = "mediaImageWatermarkKind"
    package static let mediaImageWatermarkText = "mediaImageWatermarkText"
    package static let mediaImageWatermarkLogoPath = "mediaImageWatermarkLogoPath"
    package static let mediaImageWatermarkPosition = "mediaImageWatermarkPosition"
    package static let mediaImageWatermarkOpacity = "mediaImageWatermarkOpacity"
    package static let mediaImageWatermarkMargin = "mediaImageWatermarkMargin"
    package static let mediaImageWatermarkScale = "mediaImageWatermarkScale"
    package static let mediaImageRenamePattern = "mediaImageRenamePattern"
    package static let mediaImageBackground = "mediaImageBackground"
    package static let mediaImagePreserveModificationDate = "mediaImagePreserveModificationDate"
    package static let mediaImageSaveInSubfolder = "mediaImageSaveInSubfolder"
    package static let mediaImageProfiles = "mediaImageProfiles"
    package static let mediaImageSelectedProfileID = "mediaImageSelectedProfileID"
    package static let mediaTextAccurate = "mediaTextAccurate"
    package static let mediaTextLanguageCorrection = "mediaTextLanguageCorrection"

    // Clipboard history — text only, opt-in and local.
    package static let clipboardHistoryEnabled = "clipboardHistoryEnabled"
    package static let clipboardHistoryEntries = "clipboardHistoryEntries"
    package static let clipboardHistoryLimit = "clipboardHistoryLimit"
    package static let clipboardHistorySkipSensitive = "clipboardHistorySkipSensitive"
    package static let clipboardHistoryIncludeImagesFiles = "clipboardHistoryIncludeImagesFiles" // capture copied images and files too
    package static let clipboardHistoryIgnoredApps = "clipboardHistoryIgnoredApps" // apps whose copies are never saved
    package static let clipboardHistoryQuickPreview = "clipboardHistoryQuickPreview"
    package static let clipboardHistoryWindowWidth = "clipboardHistoryWindowWidth"
    package static let clipboardHistoryWindowHeight = "clipboardHistoryWindowHeight"
    package static let clipboardHistoryMenuBarPreview = "clipboardHistoryMenuBarPreview" // show latest copy next to the menu bar icon
    package static let clipboardHistoryMenuBarPreviewLength = "clipboardHistoryMenuBarPreviewLength" // characters shown before truncating

    // Auto clear: wipes the system pasteboard on a delay or on sleep and lock.
    // Deliberately outside the clipboardHistory family, since it clears the
    // pasteboard without touching saved entries, and runs with capture off.
    package static let clipboardAutoClearOnDelay = "clipboardAutoClearOnDelay"
    package static let clipboardAutoClearDelay = "clipboardAutoClearDelaySeconds" // seconds since the last copy
    package static let clipboardAutoClearOnSleep = "clipboardAutoClearOnSleep"
    package static let clipboardAutoClearOnDisplaySleep = "clipboardAutoClearOnDisplaySleep"
    package static let clipboardAutoClearOnScreenLock = "clipboardAutoClearOnScreenLock"

    package static let windowPreviewExcludedApps = "windowPreviewExcludedApps" // pause Dock Preview thumbnail capture while these apps are in front (once shared with the app switcher)
    package static let switcherPreviewExcludedApps = "switcherPreviewExcludedApps" // pause app switcher thumbnail capture while these apps are in front
    package static let diskEjectExcludedVolumes = "diskEjectExcludedVolumes" // volume names/UUIDs excluded from Eject all disks
    // Quick tools: paste as plain text, color picker, screen OCR, mic mute.
    package static let pastePlainEnabled = "pastePlainEnabled"
    package static let pastePlainShortcut = "pastePlainShortcut"
    package static let colorPickerShortcutEnabled = "colorPickerShortcutEnabled"
    package static let colorPickerShortcut = "colorPickerShortcut"
    package static let colorPickerFormat = "colorPickerFormat"       // hex | rgb | hsl | swiftui
    package static let colorPickerBareHex = "colorPickerBareHex"     // copy HEX without the leading #
    package static let screenOCRShortcutEnabled = "screenOCRShortcutEnabled"
    package static let screenOCRShortcut = "screenOCRShortcut"
    package static let screenOCRRemoveLineBreaks = "screenOCRRemoveLineBreaks"
    package static let screenOCRDetectQRCodes = "screenOCRDetectQRCodes" // QR content wins over OCR text
    package static let micMuteShortcutEnabled = "micMuteShortcutEnabled"
    package static let micMuteShortcut = "micMuteShortcut"
    package static let cameraPreviewShortcutEnabled = "cameraPreviewShortcutEnabled"
    package static let cameraPreviewShortcut = "cameraPreviewShortcut"
    package static let wallpaperApplyAllDisplays = "wallpaperApplyAllDisplays"
    package static let wallpaperFilter = "wallpaperFilter"
    package static let wallpaperOwnBookmarks = "wallpaperOwnBookmarks"
    // paths hidden from folder scans (does not delete files)
    package static let wallpaperExcludedOwnPaths = "wallpaperExcludedOwnPaths"
    package static let scratchpadShortcutEnabled = "scratchpadShortcutEnabled"
    package static let scratchpadShortcut = "scratchpadShortcut"
    package static let commandBarShortcutEnabled = "commandBarShortcutEnabled"
    package static let commandBarShortcut = "commandBarShortcut"
    /// Compact mode: an empty field shows nothing but itself. Off by default
    package static let commandBarCompactMode = "commandBarCompactMode"
    /// The ASCII layout borrowed while the bar is open, restored on close. Off by default
    package static let commandBarASCIILayoutEnabled = "commandBarASCIILayoutEnabled"
    package static let commandBarUsage = "commandBarUsage"           // per-command run counts, never queries
    package static let commandBarQueryHabits = "commandBarQueryHabits" // keyed query digests → app row ids
    package static let commandBarDisabledSources = "commandBarDisabledSources" // kinds of result switched off
    package static let commandBarAliases = "commandBarAliases"       // {row id: the name the person gave it}
    package static let commandBarPins = "commandBarPins"             // row keys kept at the top, in order
    package static let commandBarHidden = "commandBarHidden"         // row keys the person never wants offered
    package static let commandBarLinks = "commandBarLinks"           // Data: [CommandBarLink] JSON
    package static let commandBarRowShortcuts = "commandBarRowShortcuts" // {row key: shortcut}
    package static let commandBarPositionOffset = "commandBarPositionOffset" // "dx,dy" from the default spot
    package static let commandBarEmojiSkinTone = "commandBarEmojiSkinTone" // "" is the yellow default
    // The folders a file search looks in, one per line, written with a tilde
    // so an exported list still points somewhere on another Mac. Empty means
    // the bar looks for no files at all, which is the setting out of the box.
    package static let commandBarFileScopes = "commandBarFileScopes"
    package static let commandBarFileIgnores = "commandBarFileIgnores" // names a file search never shows
    package static let panelUtilityCommandBar = "panelUtilityCommandBar"
    package static let scratchpadRetention = "scratchpadRetention"   // never | day | week | month
    package static let scratchpadCloseOnClickOutside = "scratchpadCloseOnClickOutside"
    package static let scratchpadBackgroundOpacity = "scratchpadBackgroundOpacity" // opaque fill over the pad material (ScratchpadSupport.backgroundOpacityRange)
    package static let scratchpadDocument = "scratchpadDocument"     // Data: ScratchpadDocument JSON, including named tabs
    package static let scratchpadTextSize = "scratchpadTextSize"     // pad-wide point size (ScratchpadSupport.textSizeRange)
    package static let micMuteActive = "micMuteActive"               // mic muted by the app (survives relaunch)
    package static let micMuteSavedVolume = "micMuteSavedVolume"     // input volume to restore on unmute (pre 3.2.0 state)
    package static let micMuteSavedVolumes = "micMuteSavedVolumes"   // [device uid: input volume] to restore on unmute
    package static let micMuteSavedChannelVolumes = "micMuteSavedChannelVolumes" // [device uid: [channel: input volume]] to restore on unmute
    package static let micMuteMutedDevices = "micMuteMutedDevices"   // uids of the devices this app muted
    package static let micMuteMenuBarIndicator = "micMuteMenuBarIndicator" // badge the status icon while muted
    package static let quickLauncherShortcutEnabled = "quickLauncherShortcutEnabled"
    package static let quickLauncherShortcut = "quickLauncherShortcut"
    package static let quickLauncherItemOrder = "quickLauncherItemOrder"
    package static let quickLauncherHiddenItems = "quickLauncherHiddenItems"
    package static let panelUtilityQuickLauncher = "panelUtilityQuickLauncher"
    package static let panelUtilityColorPicker = "panelUtilityColorPicker"
    package static let panelUtilityScreenOCR = "panelUtilityScreenOCR"
    package static let panelUtilityCameraPreview = "panelUtilityCameraPreview"
    package static let panelUtilityScratchpad = "panelUtilityScratchpad"
    package static let clipboardHistoryShortcutEnabled = "clipboardHistoryShortcutEnabled"
    package static let clipboardHistoryShortcut = "clipboardHistoryShortcut"
    // Mode chooser visibility for dedicated capture shortcuts.
    package static let screenshotShowCaptureMenuOnShortcut = "screenshotShowCaptureMenuOnShortcut"
    package static let recorderShowCaptureMenuOnShortcut = "recorderShowCaptureMenuOnShortcut"
    package static let screenOCRShowCaptureMenuOnShortcut = "screenOCRShowCaptureMenuOnShortcut"
    package static let colorPickerShowCaptureMenuOnShortcut = "colorPickerShowCaptureMenuOnShortcut"
    // Screenshot capture and editor.
    package static let screenshotShortcutEnabled = "screenshotShortcutEnabled"
    package static let screenshotShortcut = "screenshotShortcut"
    package static let unifiedScreenCaptureShortcutMigrated = "unifiedScreenCaptureShortcutMigrated"
    package static let restoredScreenCaptureShortcutsMigrated = "restoredScreenCaptureShortcutsMigrated"
    package static let orphanedCaptureShortcutMigrated = "orphanedCaptureShortcutMigrated"
    package static let screenshotFullScreenShortcutEnabled = "screenshotFullScreenShortcutEnabled"
    package static let screenshotFullScreenShortcut = "screenshotFullScreenShortcut"
    package static let screenshotLastCaptureShortcutEnabled = "screenshotLastCaptureShortcutEnabled"
    package static let screenshotLastCaptureShortcut = "screenshotLastCaptureShortcut"
    package static let recentCapturesShortcutEnabled = "recentCapturesShortcutEnabled"
    package static let recentCapturesShortcut = "recentCapturesShortcut"
    package static let screenshotClipboardShortcutEnabled = "screenshotClipboardShortcutEnabled"
    package static let screenshotClipboardShortcut = "screenshotClipboardShortcut"
    package static let screenshotFreeze = "screenshotFreeze"
    package static let screenshotHideVitruvianWindows = "screenshotHideVitruvianWindows"
    package static let screenshotSaveFolder = "screenshotSaveFolder"
    package static let screenshotSaveSubfolder = "screenshotSaveSubfolder"
    package static let screenshotFileNamePattern = "screenshotFileNamePattern"
    package static let screenshotFileNumberStart = "screenshotFileNumberStart"
    package static let screenshotFileNumberNext = "screenshotFileNumberNext"
    package static let screenshotDefaultAction = "screenshotDefaultAction"
    package static let screenshotIncludePointer = "screenshotIncludePointer"
    package static let screenshotShowLastRegion = "screenshotShowLastRegion"
    package static let screenshotLoupeStartsOn = "screenshotLoupeStartsOn"
    package static let screenshotLoupeRememberZoom = "screenshotLoupeRememberZoom"
    package static let screenshotLoupeDefaultZoom = "screenshotLoupeDefaultZoom"
    package static let screenshotLoupeLastZoom = "screenshotLoupeLastZoom"
    package static let screenshotLoupeSteppedZoomByDefault = "screenshotLoupeSteppedZoomByDefault"
    package static let screenshotDownscale = "screenshotDownscale"
    package static let screenshotDelay = "screenshotDelay"
    package static let screenshotLastTool = "screenshotLastTool"
    package static let screenshotLastColor = "screenshotLastColor"
    package static let screenshotLastStroke = "screenshotLastStroke"
    package static let screenshotLastTextSize = "screenshotLastTextSize"
    package static let screenshotLastBlurLevel = "screenshotLastBlurLevel"
    package static let screenshotLastArrowStyle = "screenshotLastArrowStyle"
    package static let screenshotLastSticker = "screenshotLastSticker"
    package static let screenshotAnnotationShadows = "screenshotAnnotationShadows"
    package static let screenshotToolOrder = "screenshotToolOrder"
    package static let screenshotToolShortcuts = "screenshotToolShortcuts"
    package static let screenshotToolShortcutsEnabled = "screenshotToolShortcutsEnabled"
    package static let screenshotBackdropStyle = "screenshotBackdropStyle"
    package static let screenshotBackdropPresets = "screenshotBackdropPresets"
    package static let screenshotWatermarkStyle = "screenshotWatermarkStyle"
    package static let screenshotWatermarkPresets = "screenshotWatermarkPresets"
    package static let screenshotOpenEditorDirectly = "screenshotOpenEditorDirectly"
    package static let screenshotCopyToClipboard = "screenshotCopyToClipboard"
    package static let screenshotPreviewPosition = "screenshotPreviewPosition"
    package static let screenshotPreviewTakesFocus = "screenshotPreviewTakesFocus"
    package static let screenshotUploadShortcutEnabled = "screenshotUploadShortcutEnabled"
    package static let screenshotUploadShortcut = "screenshotUploadShortcut"
    package static let screenshotUploadDuration = "screenshotUploadDuration"
    package static let screenshotPreviewEnabled = "screenshotPreviewEnabled"
    package static let screenshotPreviewDuration = "screenshotPreviewDuration"
    package static let screenshotSharingEnabled = "screenshotSharingEnabled"
    // Developer-only endpoint for an isolated test tunnel. The official app
    // ignores it, and settings backups must never carry it to another Mac.
    package static let screenshotSharingDeveloperEndpoint = "screenshotSharingDeveloperEndpoint"
    package static let panelUtilityScreenshot = "panelUtilityScreenshot"

    // Screen recorder - records the picked area, keeps the untouched master
    // in Application Support until retention sweeps it.
    package static let recorderShortcutEnabled = "recorderShortcutEnabled"
    package static let recorderShortcut = "recorderShortcut"
    package static let recorderCountdown = "recorderCountdown"
    package static let recorderQuality = "recorderQuality"
    package static let recorderFrameRate = "recorderFrameRate"
    package static let recorderSystemAudio = "recorderSystemAudio"
    package static let recorderMicrophone = "recorderMicrophone"
    // Machine state, never exported: whether this Mac's audio system has let
    // a recording hear the Mac's sound through a process tap.
    package static let recorderSystemAudioTapVerified = "recorderSystemAudioTapVerified"
    package static let recorderSaveFolder = "recorderSaveFolder"
    package static let recorderOpenEditor = "recorderOpenEditor"
    package static let recorderAutomaticZoom = "recorderAutomaticZoom"
    package static let recorderGIFSize = "recorderGIFSize"
    package static let recorderGIFFrameRate = "recorderGIFFrameRate"
    package static let recorderEditorPresets = "recorderEditorPresets"
    package static let recorderSharingEnabled = "recorderSharingEnabled"
    package static let panelUtilityScreenRecorder = "panelUtilityScreenRecorder"
    package static let panelUtilityPortManager = "panelUtilityPortManager"

    // Nexus Agent — the Telegram bot and the Quick Prompt. The bot's own
    // settings (token, allowed users, agent options) live in its .env file,
    // never here, so the token stays out of preferences and backups.
    package static let nexusAgentShortcutEnabled = "nexusAgentShortcutEnabled"
    package static let nexusAgentShortcut = "nexusAgentShortcut"
    package static let nexusAgentAutoStart = "nexusAgentAutoStart"
    /// Quick Prompt turns run agy in plan mode (read-only) while on.
    package static let nexusAgentPlanMode = "nexusAgentPlanMode"
    // Machine state, never exported: a folder on this Mac.
    package static let nexusAgentBotDirectory = "nexusAgentBotDirectory"
    package static let panelUtilityNexusAgent = "panelUtilityNexusAgent"

    // Window Layout — snapping, global shortcuts and optional pointer gestures.
    package static let windowLayoutShortcutsEnabled = "windowLayoutShortcutsEnabled"
    package static let windowDirectionalEnabled = "windowDirectionalEnabled"
    package static let windowDirectionalShortcut = "windowDirectionalShortcut"
    package static let pointerDisplayEnabled = "pointerDisplayEnabled"
    package static let pointerDisplayShortcut = "pointerDisplayShortcut"
    package static let windowEdgeSnapEnabled = "windowEdgeSnapEnabled"
    package static let windowEdgeSnapDisabledZones = "windowEdgeSnapDisabledZones" // comma-separated visual zone ids
    package static let windowGestureEnabled = "windowGestureEnabled"
    package static let windowGestureModifiers = "windowGestureModifiers"
    package static let windowGestureRaiseWindow = "windowGestureRaiseWindow"
    package static let windowLayoutShortcutLeft = "windowLayoutShortcutLeft"
    package static let windowLayoutShortcutRight = "windowLayoutShortcutRight"
    package static let windowLayoutShortcutTop = "windowLayoutShortcutTop"
    package static let windowLayoutShortcutBottom = "windowLayoutShortcutBottom"
    package static let windowLayoutShortcutCenterHalf = "windowLayoutShortcutCenterHalf"
    package static let windowLayoutShortcutTopLeft = "windowLayoutShortcutTopLeft"
    package static let windowLayoutShortcutTopRight = "windowLayoutShortcutTopRight"
    package static let windowLayoutShortcutBottomLeft = "windowLayoutShortcutBottomLeft"
    package static let windowLayoutShortcutBottomRight = "windowLayoutShortcutBottomRight"
    package static let windowLayoutShortcutMaximize = "windowLayoutShortcutMaximize"
    package static let windowLayoutShortcutMarginMaximize = "windowLayoutShortcutMarginMaximize"
    package static let windowLayoutShortcutCenter = "windowLayoutShortcutCenter"
    package static let windowLayoutShortcutRestore = "windowLayoutShortcutRestore"
    package static let windowLayoutShortcutLeftThird = "windowLayoutShortcutLeftThird"
    package static let windowLayoutShortcutCenterThird = "windowLayoutShortcutCenterThird"
    package static let windowLayoutShortcutRightThird = "windowLayoutShortcutRightThird"
    package static let windowLayoutShortcutLeftTwoThirds = "windowLayoutShortcutLeftTwoThirds"
    package static let windowLayoutShortcutRightTwoThirds = "windowLayoutShortcutRightTwoThirds"
    package static let windowLayoutShortcutCenterTwoThirds = "windowLayoutShortcutCenterTwoThirds"
    package static let windowLayoutShortcutTopThird = "windowLayoutShortcutTopThird"
    package static let windowLayoutShortcutMiddleThird = "windowLayoutShortcutMiddleThird"
    package static let windowLayoutShortcutBottomThird = "windowLayoutShortcutBottomThird"
    package static let windowLayoutShortcutTopTwoThirds = "windowLayoutShortcutTopTwoThirds"
    package static let windowLayoutShortcutBottomTwoThirds = "windowLayoutShortcutBottomTwoThirds"
    package static let windowLayoutShortcutTopQuarter = "windowLayoutShortcutTopQuarter"
    package static let windowLayoutShortcutUpperMiddleQuarter = "windowLayoutShortcutUpperMiddleQuarter"
    package static let windowLayoutShortcutLowerMiddleQuarter = "windowLayoutShortcutLowerMiddleQuarter"
    package static let windowLayoutShortcutBottomQuarter = "windowLayoutShortcutBottomQuarter"
    package static let windowLayoutShortcutLeftQuarter = "windowLayoutShortcutLeftQuarter"
    package static let windowLayoutShortcutLeftMiddleQuarter = "windowLayoutShortcutLeftMiddleQuarter"
    package static let windowLayoutShortcutRightMiddleQuarter = "windowLayoutShortcutRightMiddleQuarter"
    package static let windowLayoutShortcutRightQuarter = "windowLayoutShortcutRightQuarter"
    package static let windowLayoutShortcutPreviousDisplay = "windowLayoutShortcutPreviousDisplay"
    package static let windowLayoutShortcutNextDisplay = "windowLayoutShortcutNextDisplay"
    package static let windowLayoutShortcutFullScreen = "windowLayoutShortcutFullScreen"
    package static let windowLayoutShortcutTopLeftSixth = "windowLayoutShortcutTopLeftSixth"
    package static let windowLayoutShortcutTopCenterSixth = "windowLayoutShortcutTopCenterSixth"
    package static let windowLayoutShortcutTopRightSixth = "windowLayoutShortcutTopRightSixth"
    package static let windowLayoutShortcutBottomLeftSixth = "windowLayoutShortcutBottomLeftSixth"
    package static let windowLayoutShortcutBottomCenterSixth = "windowLayoutShortcutBottomCenterSixth"
    package static let windowLayoutShortcutBottomRightSixth = "windowLayoutShortcutBottomRightSixth"

    // Text snippets: type a trigger, get the expansion.
    package static let textSnippetsEnabled = "textSnippetsEnabled"
    package static let textSnippets = "textSnippets"              // Data: [TextSnippet] JSON
    package static let snippetLibraryEnabled = "snippetLibraryEnabled"
    package static let snippetLibraryShortcut = "snippetLibraryShortcut"
    package static let snippetSoundEnabled = "snippetSoundEnabled"
    package static let snippetSoundName = "snippetSoundName"

    // Optional top-of-screen workspace and activity presentations.
    package static let notchShowPlayingMusic = "notchShowPlayingMusic"
    package static let notchIncludeOtherPlayers = "notchIncludeOtherPlayers"
    package static let notchDefaultProfileInitialized = "notchDefaultProfileInitialized" // local migration marker; never backed up
    package static let notchInitialExtensionsInstalled = "notchInitialExtensionsInstalled" // local first-install marker; never backed up
    package static let notchIdleContent = "notchIdleContent"
    package static let notchHiddenControls = "notchHiddenControls"
    // Travels with the controls so old backups migrate and later choices survive.
    package static let notchScratchpadControlHidden = "notchScratchpadControlHidden"
    package static let notchKeyboardLightControlHidden = "notchKeyboardLightControlHidden"
    package static let notchControlOrder = "notchControlOrder"
    package static let notchSize = "notchSize"
    package static let notchOutlineEnabled = "notchOutlineEnabled"
    package static let notchCustomWidth = "notchCustomWidth"
    package static let notchCustomHeight = "notchCustomHeight"
    // Fits the island to one Mac's camera housing; never backed up.
    package static let notchCameraFitWidth = "notchCameraFitWidth"
    package static let notchCameraFitHeight = "notchCameraFitHeight"
    package static let notchHapticFeedback = "notchHapticFeedback"
    package static let notchTranslucentBackground = "notchTranslucentBackground"
    package static let notchShelf = "notchShelf"
    package static let notchDragReveal = "notchDragReveal"
    package static let notchCaptureControls = "notchCaptureControls"
    package static let notchQuickPanel = "notchQuickPanel"
    package static let notchAppPanel = "notchAppPanel"
    package static let notchHidesMenuBarIcon = "notchHidesMenuBarIcon" // the island takes the glyph's place while it is on
    package static let notchKeepAwakeActivity = "notchKeepAwakeActivity" // a running Keep Awake session in the closed island
    package static let notchScratchpad = "notchScratchpad"
    package static let notchHoverExpands = "notchHoverExpands"
    package static let notchGesturesEnabled = "notchGesturesEnabled"
    package static let notchKeyboardLight = "notchKeyboardLight"
    package static let notchNotificationsEnabled = "notchNotificationsEnabled"
    package static let notchDismissNativeNotifications = "notchDismissNativeNotifications"
    package static let notchTimerEnabled = "notchTimerEnabled"
    package static let notchTimerMode = "notchTimerMode"
    package static let notchTimerSoundEnabled = "notchTimerSoundEnabled"
    package static let notchHideTimerCountdown = "notchHideTimerCountdown"
    package static let notchTimerMinutes = "notchTimerMinutes"
    package static let notchPomodoroFocusMinutes = "notchPomodoroFocusMinutes"
    package static let notchPomodoroShortBreakMinutes = "notchPomodoroShortBreakMinutes"
    package static let notchPomodoroLongBreakMinutes = "notchPomodoroLongBreakMinutes"
    package static let notchPomodoroLongBreakInterval = "notchPomodoroLongBreakInterval"
    package static let notchPomodoroTotalSessions = "notchPomodoroTotalSessions"
    package static let notchCameraEnabled = "notchCameraEnabled"
    package static let notchAccessoriesEnabled = "notchAccessoriesEnabled"
    package static let notchLyricsEnabled = "notchLyricsEnabled"
    package static let notchLyricsOnline = "notchLyricsOnline"
    package static let notchLiveEqualizer = "notchLiveEqualizer"
    package static let notchQueueEnabled = "notchQueueEnabled"
    package static let notchDownloadsEnabled = "notchDownloadsEnabled"
    package static let notchDownloadsFolderBookmark = "notchDownloadsFolderBookmark"
    // Watch: any part of any window read live in the island.
    package static let notchWatchEnabled = "notchWatchEnabled"
    package static let notchWatchSound = "notchWatchSound"
    package static let notchWatchCondition = "notchWatchCondition"
    package static let notchCalendarEnabled = "notchCalendarEnabled"
    package static let notchCalendarCountdown = "notchCalendarCountdown"
    package static let notchCalendarTimeLeft = "notchCalendarTimeLeft" // the event under way counts down to its end
    package static let notchCalendarExcluded = "notchCalendarExcluded" // [EKCalendar.calendarIdentifier] left out of the island
    // [countdown key: event end] chosen from an event's menu; unregistered, so it stays out of backups
    package static let notchCalendarChosenCountdowns = "notchCalendarChosenCountdowns"
    // AI agents: what the island reads from Claude Code, Codex, OpenCode and GitHub Copilot, and shows.
    package static let notchAgentsEnabled = "notchAgentsEnabled"
    package static let notchAgentsClaude = "notchAgentsClaude"
    package static let notchAgentsCodex = "notchAgentsCodex"
    package static let notchAgentsOpenCode = "notchAgentsOpenCode"
    package static let notchAgentsCopilot = "notchAgentsCopilot"
    package static let notchAgentsCardOrder = "notchAgentsCardOrder"
    package static let notchAgentsHiddenCards = "notchAgentsHiddenCards"
    package static let notchAgentsPeriod = "notchAgentsPeriod"
    package static let notchAgentsLimitDisplay = "notchAgentsLimitDisplay"
    package static let notchAgentsLimitFocus = "notchAgentsLimitFocus"
    package static let notchAgentsLiveActivity = "notchAgentsLiveActivity"
    package static let notchAgentsReadout = "notchAgentsReadout"
    package static let notchAgentsFinishAlert = "notchAgentsFinishAlert"
    package static let notchAgentsFinishMinimum = "notchAgentsFinishMinimum"
    package static let notchAgentsLimitAlert = "notchAgentsLimitAlert"
    package static let notchAgentsLimitThreshold = "notchAgentsLimitThreshold"
    package static let notchAgentsDailyBudget = "notchAgentsDailyBudget"
    package static let notchAgentsPriceUpdates = "notchAgentsPriceUpdates"
    package static let notchEnabled = "notchEnabled"
    package static let notchDisplay = "notchDisplay"
    // How the island looks on a display without a camera housing.
    package static let notchSilhouette = "notchSilhouette"
    // The capsule's size and place, fitted by hand on such a display.
    package static let notchCapsuleFitWidth = "notchCapsuleFitWidth"
    package static let notchCapsuleFitHeight = "notchCapsuleFitHeight"
    package static let notchCapsuleFitDrop = "notchCapsuleFitDrop"
    package static let notchOpenOnHover = "notchOpenOnHover"
    package static let notchHideInFullscreen = "notchHideInFullscreen"
    package static let notchHideUntilHover = "notchHideUntilHover"
    package static let notchCoversMenus = "notchCoversMenus"
    package static let notchHoverDelay = "notchHoverDelay"
    package static let notchReturnHome = "notchReturnHome"
    package static let notchHomeModule = "notchHomeModule"
    package static let notchOpensActivity = "notchOpensActivity"
    package static let notchHiddenModules = "notchHiddenModules"
    package static let notchModuleOrder = "notchModuleOrder"
    package static let notchQuickAccessLayout = "notchQuickAccessLayout"
    package static let notchQuickAccessSide = "notchQuickAccessSide"
    package static let notchQuickAccessSecond = "notchQuickAccessSecond"
    package static let notchQuickAccessThird = "notchQuickAccessThird"
    package static let notchVolume = "notchVolume"
    package static let notchMicrophone = "notchMicrophone"
    package static let notchBrightness = "notchBrightness"
    package static let notchBattery = "notchBattery"
    package static let notchClipboard = "notchClipboard"
    package static let notchClipboardWindow = "notchClipboardWindow"
    package static let notchCapture = "notchCapture"
    package static let notchTrackChange = "notchTrackChange"
    // Legacy backup key. Resting content is now selected explicitly by notchIdleContent.
    package static let notchMusicActivity = "notchMusicActivity"
    package static let notchShowInCaptures = "notchShowInCaptures"
    package static let notchLockScreen = "notchLockScreen" // music and live activities over the lock screen
    package static let notchLockSounds = "notchLockSounds" // padlock sounds as the Mac locks and unlocks
    // Companion: a small friend who rests in the closed island and is the Command Bar's face.
    package static let notchMascotEnabled = "notchMascotEnabled"
    package static let notchMascotVisits = "notchMascotVisits" // passes through the island now and then
    package static let notchMascotReactions = "notchMascotReactions" // comes out to react to what the island sees
    package static let notchMascotStyle = "notchMascotStyle" // NotchMascotStyle.rawValue
    package static let notchMascotShape = "notchMascotShape" // NotchMascotShape.rawValue
    package static let notchMascotPalette = "notchMascotPalette" // NotchMascotPalette.rawValue
    package static let notchMascotSide = "notchMascotSide" // NotchMascotSide.rawValue, beside the camera
    package static let notchMascotVisitFrequency = "notchMascotVisitFrequency" // NotchMascotVisitFrequency.rawValue
    package static let notchCommandBar = "notchCommandBar" // the Command Bar comes out of the island
    package static let notchCommandBarStyle = "notchCommandBarStyle" // NotchCommandBarStyle.rawValue
    // Legacy inverse preference; the explicit visibility switch supersedes it.
    package static let notchHideInCaptures = "notchHideInCaptures"
    package static let panelControlNotch = "panelControlNotch"

    // Radial menu: a wheel of actions on a shortcut.
    package static let radialMenuEnabled = "radialMenuEnabled"
    package static let radialMenuShortcut = "radialMenuShortcut"
    package static let radialMenuAtPointer = "radialMenuAtPointer" // false: screen center
    package static let radialMenuMouseButton = "radialMenuMouseButton" // RadialMenuMouseTrigger.rawValue
    package static let radialMenuActivationMode = "radialMenuActivationMode" // RadialMenuActivationMode.rawValue
    package static let radialMenuItems = "radialMenuItems"        // Data: [RadialMenuItem] JSON
    package static let radialMenuProfiles = "radialMenuProfiles"  // Data: [RadialMenuProfile] JSON

    // Dev-build only: force the "update available" UI for local testing.
    package static let simulateUpdate = "simulateUpdate"
    package static let simulateBetaUI = "simulateBetaUI"

    /// Features hub availability layer, one key per AppFeature raw value.
    /// Registered true: unavailable features vanish from every surface and
    /// hold no resources, without ever touching their own enable keys.
    package static func featureAvailable(_ id: String) -> String { "featureAvailable.\(id)" }
}
