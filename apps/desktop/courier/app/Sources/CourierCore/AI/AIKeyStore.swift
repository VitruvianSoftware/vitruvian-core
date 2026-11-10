// Copyright 2026 VitruvianSoftware
// SPDX-License-Identifier: AGPL-3.0-or-later

import Foundation

public struct AIKeyStoreError: Error, LocalizedError, Equatable, Sendable {
    public let message: String

    public init(message: String) {
        self.message = message
    }

    public var errorDescription: String? { message }

    public static func saveFailed(_ error: Error) -> AIKeyStoreError {
        AIKeyStoreError(
            message: String(localized: "Couldn’t save key to Keychain (\(describe(error))).")
        )
    }

    public static func removeFailed(_ error: Error) -> AIKeyStoreError {
        AIKeyStoreError(
            message: String(localized: "Couldn’t remove key from Keychain (\(describe(error))).")
        )
    }

    private static func describe(_ error: Error) -> String {
        if let failure = error as? KeychainStore.Failure {
            return "OSStatus \(failure.status)"
        }
        if let localized = (error as? LocalizedError)?.errorDescription,
           !localized.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        {
            return localized
        }
        return error.localizedDescription
    }
}

/// API keys for AI providers stored in the Keychain via `CredentialStore`.
/// Keys never go to UserDefaults, logs, or string descriptions.
public struct AIKeyStore: Sendable {
    /// The Keychain service: the test copy (`TestCopy`) keeps its own, separate from the installed app.
    public static var service: String { service(for: Bundle.main.bundleIdentifier) }

    public static func service(for bundleIdentifier: String?) -> String {
        bundleIdentifier == TestCopy.bundleIdentifier
            ? "com.vitruviansoftware.courier.dev.ai"
            : "com.vitruviansoftware.courier.ai"
    }

    public let store: any CredentialStore

    public init(store: any CredentialStore = KeychainStore(service: AIKeyStore.service)) {
        self.store = store
    }

    public func key(for provider: AIProviderKind) -> String? {
        guard let raw = try? store.read(account: provider.rawValue) else { return nil }
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    public func hasKey(for provider: AIProviderKind) -> Bool {
        key(for: provider) != nil
    }

    /// Last 4 characters of the stored key for UI confirmation (`Stored in Keychain · …<last 4>`), or nil when none is stored.
    public func keyLastFour(for provider: AIProviderKind) -> String? {
        guard let stored = key(for: provider), !stored.isEmpty else { return nil }
        return String(stored.suffix(4))
    }

    @discardableResult
    public func saveKey(_ key: String, for provider: AIProviderKind) -> Result<Void, AIKeyStoreError> {
        let trimmed = key.trimmingCharacters(in: .whitespacesAndNewlines)
        do {
            if trimmed.isEmpty {
                try store.delete(account: provider.rawValue)
            } else {
                try store.write(trimmed, account: provider.rawValue)
            }
            return .success(())
        } catch {
            return .failure(.saveFailed(error))
        }
    }

    @discardableResult
    public func removeKey(for provider: AIProviderKind) -> Result<Void, AIKeyStoreError> {
        do {
            try store.delete(account: provider.rawValue)
            return .success(())
        } catch {
            return .failure(.removeFailed(error))
        }
    }

    @discardableResult
    public func deleteKey(for provider: AIProviderKind) -> Result<Void, AIKeyStoreError> {
        removeKey(for: provider)
    }
}

extension AIKeyStore: CustomStringConvertible, CustomDebugStringConvertible {
    public var description: String { "AIKeyStore(<redacted>)" }
    public var debugDescription: String { description }
}
