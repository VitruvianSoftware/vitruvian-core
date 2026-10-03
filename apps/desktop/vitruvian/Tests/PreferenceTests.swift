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
        case let preference as Preference<String>: return AppStorage(preference, store: defaults).wrappedValue as? Value
        default: return nil
        }
    }
}
