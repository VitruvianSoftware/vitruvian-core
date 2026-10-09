// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 VitruvianSoftware

import Foundation
import SwiftUI
import VitruvianCore
import VitruvianDesign
import VitruvianServices
import VitruvianUI

/// A preference declared with its default is registered with that default,
/// read with it through `UserDefaults`, and shown with it by `@AppStorage`,
/// with or without registration. Runs the module's own types.
enum PreferenceTests {
    static func run(_ suite: TestSuite) {
        expectRegistered(Preferences.menuBarMetricSpacing, suite)
        expectRegistered(Preferences.menuBarMetricOrder, suite)
        expectRegistered(Preferences.micMuteMenuBarIndicator, suite)
        expectRegistered(Preferences.screenshotPreviewPosition, suite)
        expectRegistered(Preferences.windowLayoutShortcutsEnabled, suite)
        // Registered in step 6zzo; each read as its type's empty value before.
        expectRegistered(Preferences.autoQuitEnabled, suite)
        expectRegistered(Preferences.finderCutPasteEnabled, suite)
        expectRegistered(Preferences.shelfEnabled, suite)
        expectRegistered(Preferences.menuBarCPU, suite)
        expectRegistered(Preferences.menuBarGPU, suite)
        expectRegistered(Preferences.menuBarMemory, suite)
        expectRegistered(Preferences.menuBarNetwork, suite)
        expectRegistered(Preferences.menuBarBattery, suite)
        expectRegistered(Preferences.menuBarPower, suite)
        expectRegistered(Preferences.onboardingStep, suite)
        expectRegistered(Preferences.commandBarLinks, suite)
        expectRegistered(Preferences.commandBarRowShortcuts, suite)
        expectRegistered(Preferences.toolCommandShortcuts, suite)

        let domain = "com.vitruviansoftware.vitruvian.tests.preference"
        let defaults = UserDefaults(suiteName: domain)!
        defaults.removePersistentDomain(forName: domain)
        defer { defaults.removePersistentDomain(forName: domain) }
        let count = Preference("count", default: 3)
        suite.expect(defaults[count] == 3, "a missing preference reads as its declared default")
        defaults[count] = 7
        suite.expect(defaults[count] == 7 && defaults.integer(forKey: "count") == 7,
                     "a preference writes under its key, readable either way")
        defaults.set("seven", forKey: "count")
        suite.expect(defaults[count] == 3, "a value of another type reads as the declared default")
        defaults[count] = 7
        defaults.removeValue(for: count)
        suite.expect(defaults[count] == 3 && defaults.object(forKey: "count") == nil,
                     "removing a preference's value reads its declared default again")

        let apps = Preference("apps", default: ["com.example.first"])
        suite.expect(defaults[apps] == ["com.example.first"], "a missing list reads as its declared default")
        defaults[apps] = ["com.example.second"]
        suite.expect(defaults[apps] == ["com.example.second"]
                     && defaults.stringArray(forKey: "apps") == ["com.example.second"],
                     "a list writes under its key, readable either way")
        defaults.set([1, 2], forKey: "apps")
        suite.expect(defaults[apps] == ["com.example.first"], "a list of another type reads as the declared default")

        let names = Preference("names", default: ["built-in": "Speakers"])
        suite.expect(defaults[names] == ["built-in": "Speakers"], "a missing table reads as its declared default")
        defaults[names] = ["usb": "Headphones"]
        suite.expect(defaults[names] == ["usb": "Headphones"]
                     && defaults.dictionary(forKey: "names") as? [String: String] == ["usb": "Headphones"],
                     "a table writes under its key, readable either way")
        defaults.set(["usb": 1], forKey: "names")
        suite.expect(defaults[names] == ["built-in": "Speakers"], "a table of another type reads as the declared default")

        let registeredExceptions = Defaults.registeredDefaults[Preferences.autoQuitExceptions.key] as? [String]
        suite.expect(registeredExceptions == Defaults.mandatoryAutoQuitExceptionBundleIDs
                     && Preferences.autoQuitExceptions.defaultValue == Defaults.mandatoryAutoQuitExceptionBundleIDs,
                     "a list is registered with its declared default")

        // An enum stored as its raw text (step 6zzr).
        expectRegistered(Preferences.notchTimerMode, suite)
        expectRegistered(Preferences.scrollHorizontalModifier, suite)
        let modes = UserDefaults(suiteName: "com.vitruviansoftware.vitruvian.tests.preference.enum")!
        modes.removePersistentDomain(forName: "com.vitruviansoftware.vitruvian.tests.preference.enum")
        defer { modes.removePersistentDomain(forName: "com.vitruviansoftware.vitruvian.tests.preference.enum") }
        suite.expect(AppStorage<NotchTimerMode>(Preferences.notchTimerMode, store: modes).wrappedValue == .timer
                     && AppStorage<ScrollHorizontalModifier>(Preferences.scrollHorizontalModifier, store: modes)
                        .wrappedValue == .shift,
                     "an enum starts from the case its preference's default names")
        modes.set(NotchTimerMode.stopwatch.rawValue, forKey: Preferences.notchTimerMode.key)
        modes.set(ScrollHorizontalModifier.option.rawValue, forKey: Preferences.scrollHorizontalModifier.key)
        suite.expect(AppStorage<NotchTimerMode>(Preferences.notchTimerMode, store: modes).wrappedValue == .stopwatch
                     && AppStorage<ScrollHorizontalModifier>(Preferences.scrollHorizontalModifier, store: modes)
                        .wrappedValue == .option,
                     "an enum reads the case stored as its raw text")
    }

    /// The app registers the declared default, and a view shows it whether or
    /// not registration ran, as in a preview or a test. Registration is
    /// process-wide, so the suite stores the registered value instead.
    private static func expectRegistered<Value: PreferenceValue & Equatable>(_ preference: Preference<Value>,
                                                                             _ suite: TestSuite) {
        let registered = Defaults.registeredDefaults[preference.key].flatMap(Value.init(storedValue:))
        suite.expect(registered == preference.defaultValue, "\(preference.key) is registered with its declared default")

        let domain = "com.vitruviansoftware.vitruvian.tests.preference.\(preference.key)"
        let defaults = UserDefaults(suiteName: domain)!
        defaults.removePersistentDomain(forName: domain)
        defer { defaults.removePersistentDomain(forName: domain) }
        suite.expect(defaults[preference] == preference.defaultValue,
                     "\(preference.key) reads as its declared default before registration")
        suite.expect(storedThroughAppStorage(preference, defaults) == preference.defaultValue,
                     "\(preference.key) starts from its declared default in a view before registration")
        defaults.set(Defaults.registeredDefaults[preference.key], forKey: preference.key)
        suite.expect(defaults[preference] == preference.defaultValue
                     && storedThroughAppStorage(preference, defaults) == preference.defaultValue,
                     "\(preference.key) reads the same with the registered value stored")
    }

    private static func storedThroughAppStorage<Value>(_ preference: Preference<Value>, _ defaults: UserDefaults) -> Value? {
        switch preference {
        case let preference as Preference<Bool>: return AppStorage(preference, store: defaults).wrappedValue as? Value
        case let preference as Preference<Int>: return AppStorage(preference, store: defaults).wrappedValue as? Value
        case let preference as Preference<Double>: return AppStorage(preference, store: defaults).wrappedValue as? Value
        case let preference as Preference<String>:
            return AppStorage<String>(preference, store: defaults).wrappedValue as? Value
        case let preference as Preference<Data>: return AppStorage(preference, store: defaults).wrappedValue as? Value
        default: return nil
        }
    }
}
