// Copyright 2026 VitruvianSoftware
// SPDX-License-Identifier: AGPL-3.0-or-later

import Foundation
import Security

/// Secrets by account name, within one Keychain service. Behind a protocol so tests keep them in memory.
public protocol CredentialStore: Sendable {
    /// The value, or nil when there is none.
    func read(account: String) throws -> String?
    func write(_ value: String, account: String) throws
    func delete(account: String) throws
}

/// Telegram's api_id and api_hash. The app asks for them once and keeps them in the Keychain; the engine gets
/// them only in its environment, at launch, and nothing ever logs or writes them anywhere else.
public struct TelegramCredentials: Equatable, Sendable {
    public static let service = "com.vitruviansoftware.courier.telegram"
    public static let apiIDAccount = "api_id"
    public static let apiHashAccount = "api_hash"
    /// The variables the engine reads them from.
    public static let apiIDVariable = "COURIER_TELEGRAM_API_ID"
    public static let apiHashVariable = "COURIER_TELEGRAM_API_HASH"

    public var apiID: String
    public var apiHash: String

    public init(apiID: String, apiHash: String) {
        self.apiID = apiID
        self.apiHash = apiHash
    }

    /// Both values, or nil when either is missing or cannot be read: half a pair is no use to the engine.
    public static func load(from store: CredentialStore) -> TelegramCredentials? {
        guard let id = try? store.read(account: apiIDAccount), !id.isEmpty,
              let hash = try? store.read(account: apiHashAccount), !hash.isEmpty else { return nil }
        return TelegramCredentials(apiID: id, apiHash: hash)
    }

    public func save(to store: CredentialStore) throws {
        try store.write(apiID, account: Self.apiIDAccount)
        try store.write(apiHash, account: Self.apiHashAccount)
    }

    /// The two variables for the engine's environment.
    public var environment: [String: String] {
        [Self.apiIDVariable: apiID, Self.apiHashVariable: apiHash]
    }
}

extension TelegramCredentials: CustomStringConvertible, CustomDebugStringConvertible {
    public var description: String { "TelegramCredentials(<redacted>)" }
    public var debugDescription: String { description }
}

/// Generic passwords in the login Keychain, under one service.
public struct KeychainStore: CredentialStore {
    public let service: String

    public init(service: String) {
        self.service = service
    }

    public struct Failure: Error, Equatable {
        public let status: OSStatus
    }

    private func query(_ account: String) -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
    }

    public func read(account: String) throws -> String? {
        var item = query(account)
        item[kSecReturnData as String] = true
        item[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: AnyObject?
        let status = SecItemCopyMatching(item as CFDictionary, &result)
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess, let data = result as? Data else { throw Failure(status: status) }
        return String(data: data, encoding: .utf8)
    }

    public func write(_ value: String, account: String) throws {
        let data = Data(value.utf8)
        let status = SecItemUpdate(query(account) as CFDictionary, [kSecValueData as String: data] as CFDictionary)
        if status == errSecItemNotFound {
            var item = query(account)
            item[kSecValueData as String] = data
            item[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
            let added = SecItemAdd(item as CFDictionary, nil)
            guard added == errSecSuccess else { throw Failure(status: added) }
        } else if status != errSecSuccess {
            throw Failure(status: status)
        }
    }

    public func delete(account: String) throws {
        let status = SecItemDelete(query(account) as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else { throw Failure(status: status) }
    }
}
