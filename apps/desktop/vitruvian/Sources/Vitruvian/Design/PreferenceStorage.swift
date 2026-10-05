// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 VitruvianSoftware

import SwiftUI
import VitruvianCore

// `@AppStorage(Preferences.someSetting) var someSetting: Bool` stores a
// preference under its key and starts from its declared default, so a view
// writes neither (see `Preference`). The property's type is written out, as
// it was when the default sat beside it.

extension AppStorage where Value == Bool {
    package init(_ preference: Preference<Bool>, store: UserDefaults? = nil) {
        self.init(wrappedValue: preference.defaultValue, preference.key, store: store)
    }
}

extension AppStorage where Value == Int {
    package init(_ preference: Preference<Int>, store: UserDefaults? = nil) {
        self.init(wrappedValue: preference.defaultValue, preference.key, store: store)
    }
}

extension AppStorage where Value == Double {
    package init(_ preference: Preference<Double>, store: UserDefaults? = nil) {
        self.init(wrappedValue: preference.defaultValue, preference.key, store: store)
    }
}

extension AppStorage where Value == String {
    package init(_ preference: Preference<String>, store: UserDefaults? = nil) {
        self.init(wrappedValue: preference.defaultValue, preference.key, store: store)
    }
}

extension AppStorage where Value == Data {
    package init(_ preference: Preference<Data>, store: UserDefaults? = nil) {
        self.init(wrappedValue: preference.defaultValue, preference.key, store: store)
    }
}

// An enum stored as its raw text, such as a mode, starts from the case its
// preference's default names. Declare the default from the case
// (`default: NotchTimerMode.timer.rawValue`), so it always names one.
extension AppStorage where Value: RawRepresentable, Value.RawValue == String {
    package init(_ preference: Preference<String>, store: UserDefaults? = nil) {
        guard let initial = Value(rawValue: preference.defaultValue) else {
            preconditionFailure("\(preference.key)'s default names no \(Value.self)")
        }
        self.init(wrappedValue: initial, preference.key, store: store)
    }
}
