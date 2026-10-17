// Copyright 2026 VitruvianSoftware
// SPDX-License-Identifier: AGPL-3.0-or-later

import Foundation

/// Courier's own Telegram app ID, put into the app bundle when it is packaged (scripts/inject-app-credentials.sh):
/// `Contents/Resources/TelegramApp.plist`, with `api_id` as an integer and `api_hash` as a string.
///
/// Telegram wants every app to register its own pair, so a finished Courier carries its own and the person never
/// types one. An app built without it (a development build) has no such file, and Courier asks instead.
public enum TelegramBuiltIn {
    public static let resourceName = "TelegramApp"
    public static let resourceExtension = "plist"
    public static let apiIDKey = "api_id"
    public static let apiHashKey = "api_hash"

    /// The pair packaged into `bundle`, or nil when there is none or it does not fit what Telegram hands out
    /// (the same check the engine makes). A damaged file is the same as no file: Courier falls back to asking.
    public static func load(from bundle: Bundle = .main) -> TelegramCredentials? {
        guard let url = bundle.url(forResource: resourceName, withExtension: resourceExtension) else { return nil }
        return load(plistAt: url)
    }

    static func load(plistAt url: URL) -> TelegramCredentials? {
        guard let data = try? Data(contentsOf: url),
              let plist = try? PropertyListSerialization.propertyList(from: data, format: nil),
              let dictionary = plist as? [String: Any] else { return nil }
        return credentials(from: dictionary)
    }

    static func credentials(from dictionary: [String: Any]) -> TelegramCredentials? {
        // The id is an integer: a string, a real number or a boolean in its place is a file somebody got wrong.
        guard let number = dictionary[apiIDKey] as? NSNumber,
              CFGetTypeID(number) != CFBooleanGetTypeID(),
              !CFNumberIsFloatType(number as CFNumber),
              let hash = dictionary[apiHashKey] as? String else { return nil }
        return valid(apiID: String(number.int64Value), apiHash: hash)
    }

    /// The pair with the spaces at its ends dropped, or nil when it does not fit.
    static func valid(apiID: String, apiHash: String) -> TelegramCredentials? {
        guard TelegramSetup.problems(apiID: apiID, apiHash: apiHash).isEmpty else { return nil }
        return TelegramCredentials(apiID: apiID.trimmingCharacters(in: .whitespacesAndNewlines),
                                   apiHash: apiHash.trimmingCharacters(in: .whitespacesAndNewlines))
    }
}

/// Where Telegram's app ID comes from, in this order: the one built into the app, then the one the person typed
/// (kept in the Keychain), then none. A value that does not fit is passed over, so a damaged built-in file or
/// Keychain entry never stops the next source from being used.
///
/// Read again each time it is asked, so a pair saved a moment ago is found. Nothing here logs or keeps a value.
public struct TelegramCredentialSource: Sendable {
    public let store: CredentialStore
    private let builtIn: @Sendable () -> TelegramCredentials?

    /// - Parameters:
    ///   - store: the Keychain the person's own pair is saved in.
    ///   - builtIn: the pair packaged into the app; tests give their own.
    public init(store: CredentialStore = KeychainStore(service: TelegramCredentials.service),
                builtIn: @escaping @Sendable () -> TelegramCredentials? = { TelegramBuiltIn.load() }) {
        self.store = store
        self.builtIn = builtIn
    }

    public func resolve() -> TelegramCredentials? {
        if let packaged = builtIn().flatMap({ TelegramBuiltIn.valid(apiID: $0.apiID, apiHash: $0.apiHash) }) {
            return packaged
        }
        guard let saved = TelegramCredentials.load(from: store) else { return nil }
        return TelegramBuiltIn.valid(apiID: saved.apiID, apiHash: saved.apiHash)
    }

    /// Whether there is any pair to start Telegram with.
    public var hasCredentials: Bool { resolve() != nil }
}
