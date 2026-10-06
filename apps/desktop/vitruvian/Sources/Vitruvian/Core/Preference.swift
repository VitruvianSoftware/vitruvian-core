// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 VitruvianSoftware

import Foundation

/// A preference's key and its default, declared once.
///
/// The default reaches `UserDefaults` through `Defaults.registeredDefaults`,
/// a view through `@AppStorage(preference)`, and a service through
/// `UserDefaults[preference]`. Written out at each of those places instead,
/// the copies drifted: a setting's view assumed one default while the app
/// registered another (REFACTOR.md step 6).
package struct Preference<Value: PreferenceValue>: Sendable {
    package let key: String
    package let defaultValue: Value

    package init(_ key: String, default defaultValue: Value) {
        self.key = key
        self.defaultValue = defaultValue
    }
}

/// What a preference can hold: a property-list value `UserDefaults` stores
/// as it is.
package protocol PreferenceValue: Sendable {
    /// The stored value, or nil when what is stored is of another type.
    init?(storedValue: Any)
    var storedValue: Any { get }
}

extension Bool: PreferenceValue {
    package init?(storedValue: Any) {
        guard let value = storedValue as? Bool else { return nil }
        self = value
    }
    package var storedValue: Any { self }
}

extension Int: PreferenceValue {
    package init?(storedValue: Any) {
        guard let value = storedValue as? Int else { return nil }
        self = value
    }
    package var storedValue: Any { self }
}

extension Double: PreferenceValue {
    package init?(storedValue: Any) {
        guard let value = storedValue as? Double else { return nil }
        self = value
    }
    package var storedValue: Any { self }
}

extension String: PreferenceValue {
    package init?(storedValue: Any) {
        guard let value = storedValue as? String else { return nil }
        self = value
    }
    package var storedValue: Any { self }
}

extension Data: PreferenceValue {
    package init?(storedValue: Any) {
        guard let value = storedValue as? Data else { return nil }
        self = value
    }
    package var storedValue: Any { self }
}

/// A list of text, such as bundle identifiers. `@AppStorage` cannot hold one,
/// so services read it through `UserDefaults[preference]`.
extension Array: PreferenceValue where Element == String {
    package init?(storedValue: Any) {
        guard let value = storedValue as? [String] else { return nil }
        self = value
    }
    package var storedValue: Any { self }
}

/// Text keyed by text, such as a device's name by its identifier.
extension Dictionary: PreferenceValue where Key == String, Value == String {
    package init?(storedValue: Any) {
        guard let value = storedValue as? [String: String] else { return nil }
        self = value
    }
    package var storedValue: Any { self }
}

extension UserDefaults {
    /// The stored value, the registered default, or the preference's own
    /// default when neither is there or the stored value has another type.
    package subscript<Value>(_ preference: Preference<Value>) -> Value {
        get { object(forKey: preference.key).flatMap(Value.init(storedValue:)) ?? preference.defaultValue }
        set { set(newValue.storedValue, forKey: preference.key) }
    }

    /// Forgets the stored value, so the preference reads its default again.
    package func removeValue<Value>(for preference: Preference<Value>) {
        removeObject(forKey: preference.key)
    }
}
