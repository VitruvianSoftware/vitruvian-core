// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 VitruvianSoftware

import SwiftUI
import VitruvianCore

// `@AppStorage(Preferences.someSetting) var someSetting: Bool` stores a
// preference under its key and starts from its declared default, so a view
// writes neither (see `Preference`). Write the property's type: left to be
// inferred from the preference, it makes the compiler give up on the larger
// view bodies that read it ("failed to produce diagnostic").

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
