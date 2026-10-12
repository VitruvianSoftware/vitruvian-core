// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 VitruvianSoftware

import Foundation
import VitruvianCore
import VitruvianToolProtocol

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

/// Why a preference could not be read or written by its key.
package enum StorageProblem: Error, Equatable, Sendable {
    case refused(BrokerRefusal)
    /// The tool's manifest declares no preference with this key.
    case undeclared(String)
    /// The value is not of the kind the manifest gives the preference.
    case wrongKind(String)
    /// The value is text longer than a preference may be set to.
    case tooLong(String)
}

/// The `storage` capability: the preferences a tool's manifest declares.
///
/// A tool compiled into the app reads them through a `StorageReader`, by
/// `Preference`, and a view of the tool binds the same keys with
/// `@AppStorage`. A tool that runs as its own program has no `Preference`
/// and no view: it reads and writes by key, with `value(for:)` and
/// `set(_:for:)`, and only the keys its manifest declares.
@MainActor
package struct StorageAccess {
    package struct Backing {
        /// The saved value or the registered default, on any thread.
        package var read: @Sendable (String) -> Any?
        /// Saves a value under a key.
        package var write: @Sendable (String, Any) -> Void
        /// Told the key a tool asked for without declaring it.
        package var undeclaredKey: @Sendable (String) -> Void

        package init(read: @escaping @Sendable (String) -> Any?,
                     write: @escaping @Sendable (String, Any) -> Void = { _, _ in },
                     undeclaredKey: @escaping @Sendable (String) -> Void = { _ in }) {
            self.read = read
            self.write = write
            self.undeclaredKey = undeclaredKey
        }

        @MainActor package static let live = Backing(
            read: { UserDefaults.standard.object(forKey: $0) },
            write: { UserDefaults.standard.set($1, forKey: $0) },
            undeclaredKey: { assertionFailure("a tool read the preference \($0) without declaring it") })

        /// Holds nothing. For tests of other capabilities.
        package static var inert: Backing { Backing(read: { _ in nil }) }
    }

    let gate: () -> BrokerRefusal?
    let keys: Set<String>
    /// Each declared preference's default, by its key.
    let defaults: [String: PreferenceDeclaration.Value]
    let backing: Backing

    /// A reader, once the checks pass. Ask each time a piece of work starts.
    package func reader() -> Result<StorageReader, BrokerRefusal> {
        if let refusal = gate() { return .failure(refusal) }
        return .success(StorageReader(keys: keys, read: backing.read, undeclared: backing.undeclaredKey))
    }

    /// The saved value of the preference with this key; its default when
    /// nothing is saved, or what is saved is of another kind. A key the
    /// manifest does not declare is refused, and nothing is read.
    package func value(for key: String) -> Result<PreferenceDeclaration.Value, StorageProblem> {
        if let refusal = gate() { return .failure(.refused(refusal)) }
        guard let fallback = defaults[key] else { return .failure(.undeclared(key)) }
        let saved = backing.read(key)
        switch fallback {
        case .bool: return .success((saved as? Bool).map(PreferenceDeclaration.Value.bool) ?? fallback)
        case .string: return .success((saved as? String).map(PreferenceDeclaration.Value.string) ?? fallback)
        case .int: return .success((saved as? Int).map(PreferenceDeclaration.Value.int) ?? fallback)
        case .double: return .success((saved as? Double).map(PreferenceDeclaration.Value.double) ?? fallback)
        }
    }

    /// Saves `value` as the preference with this key. Refused, with
    /// nothing written, for a key the manifest does not declare, for a
    /// value of another kind than the preference's default, and for text
    /// longer than `StorageLimits.maxTextLength`, the protocol's number.
    @discardableResult
    package func set(_ value: PreferenceDeclaration.Value, for key: String) -> StorageProblem? {
        if let refusal = gate() { return .refused(refusal) }
        guard let fallback = defaults[key] else { return .undeclared(key) }
        switch (fallback, value) {
        case (.string, .string(let text)) where text.unicodeScalars.count > StorageLimits.maxTextLength:
            return .tooLong(key)
        case (.bool, .bool), (.string, .string), (.int, .int), (.double, .double):
            backing.write(key, value.defaultsValue)
            return nil
        default:
            return .wrongKind(key)
        }
    }
}

extension StorageAccess {
    /// Access to the preferences `manifest` declares, behind `gate`.
    init(gate: @escaping () -> BrokerRefusal?, manifest: ToolManifest, backing: Backing) {
        self.init(gate: gate, keys: Set(manifest.preferences.map(\.key)),
                  defaults: Dictionary(manifest.preferences.map { ($0.key, $0.defaultValue) },
                                       uniquingKeysWith: { first, _ in first }),
                  backing: backing)
    }
}
