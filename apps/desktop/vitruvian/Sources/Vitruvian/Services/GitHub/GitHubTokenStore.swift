// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 VitruvianSoftware

import Foundation
import Security
import VitruvianCore

/// Where the GitHub user token lives between launches (design spec §2.2).
/// The token never goes to preferences, logs or backups.
package protocol GitHubTokenStore: Sendable {
    /// The saved token, or nil when there is none.
    func load() throws -> String?
    func save(_ token: String) throws
    /// Removes the token. Removing a token that is not there is not an error.
    func delete() throws
}

/// The Keychain refused a call; `status` is its OSStatus.
package struct GitHubTokenStoreError: Error, Equatable, Sendable {
    package let status: OSStatus

    package init(status: OSStatus) { self.status = status }
}

/// The token as one generic-password item: service = the bundle id +
/// `.github`, account = `user-token`.
///
/// **Keychain caveat (design spec §2.2).** The item is written to the
/// data-protection Keychain (`kSecUseDataProtectionKeychain`), whose items
/// are bound to the writing app's code-signing identity and never raise a
/// legacy access prompt for that app. macOS only opens the data-protection
/// Keychain to apps signed with a `keychain-access-groups` or
/// `application-identifier` entitlement backed by a provisioning profile,
/// and this app ships with neither (`Resources/Vitruvian.entitlements`, ad-hoc
/// or Developer ID signing). Without one every call answers
/// `errSecMissingEntitlement`, so the store falls back to the file-based login
/// Keychain. There the item's access list trusts the app that created it, so
/// that app reads it without a prompt as long as its signature stays the
/// same; a rebuilt ad-hoc app is a different app to the Keychain and may be
/// asked once. Either way, a locally built app and a notarized release do not
/// see each other's token: each asks you to connect once.
package struct KeychainGitHubTokenStore: GitHubTokenStore {
    package static let account = "user-token"
    package static let defaultService = (Bundle.main.bundleIdentifier ?? "com.vitruviansoftware.vitruvian") + ".github"

    package let service: String
    private let keychain: KeychainCalls

    package init(service: String = KeychainGitHubTokenStore.defaultService) {
        self.init(service: service, keychain: .system)
    }

    /// `keychain` stands in for the Security calls, so a test can answer as
    /// a Mac without the data-protection entitlement does.
    package init(service: String, keychain: KeychainCalls) {
        self.service = service
        self.keychain = keychain
    }

    package func load() throws -> String? {
        for dataProtection in [true, false] {
            var query = baseQuery(dataProtection: dataProtection)
            query[kSecReturnData as String] = true
            query[kSecMatchLimit as String] = kSecMatchLimitOne
            let (status, data) = keychain.copyMatching(query)
            switch status {
            case errSecSuccess:
                guard let data, let token = String(data: data, encoding: .utf8), !token.isEmpty else { return nil }
                return token
            case errSecItemNotFound, errSecMissingEntitlement:
                continue
            default:
                throw GitHubTokenStoreError(status: status)
            }
        }
        return nil
    }

    package func save(_ token: String) throws {
        let data = Data(token.utf8)
        var status = write(data, dataProtection: true)
        if status == errSecMissingEntitlement { status = write(data, dataProtection: false) }
        guard status == errSecSuccess else { throw GitHubTokenStoreError(status: status) }
    }

    package func delete() throws {
        for dataProtection in [true, false] {
            let status = keychain.delete(baseQuery(dataProtection: dataProtection))
            guard [errSecSuccess, errSecItemNotFound, errSecMissingEntitlement].contains(status) else {
                throw GitHubTokenStoreError(status: status)
            }
        }
    }

    private func write(_ data: Data, dataProtection: Bool) -> OSStatus {
        let query = baseQuery(dataProtection: dataProtection)
        let updated = keychain.update(query, [kSecValueData as String: data])
        guard updated == errSecItemNotFound else { return updated }
        var item = query
        item[kSecValueData as String] = data
        // Accessibility classes belong to the data-protection Keychain only.
        if dataProtection { item[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock }
        item[kSecAttrLabel as String] = "Vitruvian GitHub sign-in"
        return keychain.add(item)
    }

    private func baseQuery(dataProtection: Bool) -> [String: Any] {
        var query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: Self.account,
        ]
        if dataProtection { query[kSecUseDataProtectionKeychain as String] = true }
        return query
    }
}

/// The four Security calls the token store makes.
package struct KeychainCalls: Sendable {
    package let copyMatching: @Sendable ([String: Any]) -> (OSStatus, Data?)
    package let add: @Sendable ([String: Any]) -> OSStatus
    package let update: @Sendable ([String: Any], [String: Any]) -> OSStatus
    package let delete: @Sendable ([String: Any]) -> OSStatus

    package init(copyMatching: @escaping @Sendable ([String: Any]) -> (OSStatus, Data?),
                 add: @escaping @Sendable ([String: Any]) -> OSStatus,
                 update: @escaping @Sendable ([String: Any], [String: Any]) -> OSStatus,
                 delete: @escaping @Sendable ([String: Any]) -> OSStatus) {
        self.copyMatching = copyMatching
        self.add = add
        self.update = update
        self.delete = delete
    }

    package static let system = KeychainCalls(
        copyMatching: { query in
            var result: CFTypeRef?
            let status = SecItemCopyMatching(query as CFDictionary, &result)
            return (status, result as? Data)
        },
        add: { SecItemAdd($0 as CFDictionary, nil) },
        update: { SecItemUpdate($0 as CFDictionary, $1 as CFDictionary) },
        delete: { SecItemDelete($0 as CFDictionary) })
}

/// A token store in memory, for tests and previews.
package final class InMemoryGitHubTokenStore: GitHubTokenStore, @unchecked Sendable {
    // Guarded by `lock`.
    private let lock = NSLock()
    private var token: String?

    package init(token: String? = nil) { self.token = token }

    package func load() throws -> String? { lock.withLock { token } }
    package func save(_ token: String) throws { lock.withLock { self.token = token } }
    package func delete() throws { lock.withLock { token = nil } }
}
