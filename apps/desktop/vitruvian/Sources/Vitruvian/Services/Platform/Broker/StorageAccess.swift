// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 VitruvianSoftware

import Foundation
import VitruvianCore

/// What a tool reads its preferences with. It is handed out after the
/// broker's checks pass, reads on any thread, and reads only the keys the
/// tool's manifest declares.
package struct StorageReader: Sendable {
    let keys: Set<String>
    let read: @Sendable (String) -> Any?
    let undeclared: @Sendable (String) -> Void

    /// The saved value, the registered default, or the preference's own
    /// default when neither is there or the saved value has another type.
    /// A key the manifest does not declare is a mistake in the tool: it is
    /// reported, nothing is read, and the preference's own default comes
    /// back.
    package func value<Value>(for preference: Preference<Value>) -> Value {
        guard keys.contains(preference.key) else {
            undeclared(preference.key)
            return preference.defaultValue
        }
        return read(preference.key).flatMap(Value.init(storedValue:)) ?? preference.defaultValue
    }
}

/// The `storage` capability: the preferences a tool's manifest declares.
/// Reading only. A view of the tool binds the same keys with `@AppStorage`.
@MainActor
package struct StorageAccess {
    package struct Backing {
        /// The saved value or the registered default, on any thread.
        package var read: @Sendable (String) -> Any?
        /// Told the key a tool asked for without declaring it.
        package var undeclaredKey: @Sendable (String) -> Void

        package init(read: @escaping @Sendable (String) -> Any?,
                     undeclaredKey: @escaping @Sendable (String) -> Void = { _ in }) {
            self.read = read
            self.undeclaredKey = undeclaredKey
        }

        @MainActor package static let live = Backing(
            read: { UserDefaults.standard.object(forKey: $0) },
            undeclaredKey: { assertionFailure("a tool read the preference \($0) without declaring it") })

        /// Holds nothing. For tests of other capabilities.
        package static var inert: Backing { Backing(read: { _ in nil }) }
    }

    let gate: () -> BrokerRefusal?
    let keys: Set<String>
    let backing: Backing

    /// A reader, once the checks pass. Ask each time a piece of work starts.
    package func reader() -> Result<StorageReader, BrokerRefusal> {
        if let refusal = gate() { return .failure(refusal) }
        return .success(StorageReader(keys: keys, read: backing.read, undeclared: backing.undeclaredKey))
    }
}
