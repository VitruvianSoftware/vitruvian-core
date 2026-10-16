// Copyright (c) 2026 VitruvianSoftware
//
// Permission is hereby granted, free of charge, to any person obtaining a copy
// of this software and associated documentation files (the "Software"), to deal
// in the Software without restriction, including without limitation the rights
// to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
// copies of the Software, and to permit persons to whom the Software is
// furnished to do so, subject to the following conditions:
//
// The above copyright notice and this permission notice shall be included in
// all copies or substantial portions of the Software.
//
// THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
// IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
// FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
// AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
// LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
// OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
// SOFTWARE.

import Foundation
import HomeSpeakerCore

/// The Google Home sign-in, as far as the tool's Settings needs it: whether
/// there is one and whose, whether Sign In can work, and the Antigravity
/// import. The tokens themselves never leave this seam, so nothing the tool
/// draws or keeps can hold one.
public protocol GoogleAccount: AnyObject {
    var isSignedIn: Bool { get }
    var email: String? { get }
    /// An OAuth client is known (the person's own, HomeSpeaker's, or an
    /// imported login's), so Sign In has something to sign in with.
    var hasOAuthClient: Bool { get }
    /// The Antigravity Google Home connector left a login on this Mac.
    var hasAntigravityTokens: Bool { get }
    /// Copies that login into HomeSpeaker's secrets. False when the file
    /// holds no usable login.
    func importFromAntigravity() throws -> Bool
    /// The person's own OAuth client id, saved under Google Cloud; nil when
    /// there is none. Its secret is never read back out.
    var customOAuthClientId: String? { get }
    /// A secret is saved with that client.
    var hasCustomOAuthClientSecret: Bool { get }
    /// HomeSpeaker.app was packaged with a shared OAuth client.
    var hasBundledOAuthClient: Bool { get }
    /// Saves the person's own OAuth client in one write: `id` as given (the
    /// caller trims it), and `secret` too unless it is nil, which keeps the
    /// secret already saved.
    func saveOAuthClient(id: String, secret: String?) throws
    /// Forgets the person's own OAuth client, id and secret both.
    func clearOAuthClient() throws
}

/// One HomeSpeaker's secrets file, read afresh on every question, as the
/// app reads its own: that HomeSpeaker, its tool and its command line all
/// sign in and out of it.
public final class SecretStoreAccount: GoogleAccount {
    /// The secrets file: the extension's engine's, never the app's.
    public let store: SecretStore
    private let antigravityTokens: URL
    /// Says which sign-in client is shipped: the extension's, in its tool
    /// folder.
    public let profile: HomeSpeakerProfile

    /// Every part is named: a default would be the app's secrets, which the
    /// extension must never sign in or out of.
    public init(
        store: SecretStore, antigravityTokens: URL = SecretStore.antigravityTokensURL,
        profile: HomeSpeakerProfile
    ) {
        self.store = store
        self.antigravityTokens = antigravityTokens
        self.profile = profile
    }

    public var isSignedIn: Bool { !(store.load().google?.refreshToken.isEmpty ?? true) }
    public var email: String? { store.load().google?.email }
    public var hasOAuthClient: Bool { OAuthClient.resolve(secrets: store.load(), shipped: profile.shippedClient) != nil }
    public var hasAntigravityTokens: Bool { FileManager.default.fileExists(atPath: antigravityTokens.path) }

    public func importFromAntigravity() throws -> Bool {
        try store.importFromAntigravity(at: antigravityTokens)
    }

    public var customOAuthClientId: String? {
        let id = store.load().oauthClientIdOverride?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return id.isEmpty ? nil : id
    }

    public var hasCustomOAuthClientSecret: Bool { !(store.load().oauthClientSecretOverride?.isEmpty ?? true) }

    public var hasBundledOAuthClient: Bool { profile.shippedClient != nil }

    /// One `SecretStore.update`, under its cross-process lock, so the id
    /// and the secret land together and nothing the app or the CLI writes
    /// meanwhile is lost. With no secret given, the saved one stays only
    /// for the same client: a different id never inherits another
    /// client's secret.
    public func saveOAuthClient(id: String, secret: String?) throws {
        try store.update {
            let newId = id.isEmpty ? nil : id
            let sameClient = newId == $0.oauthClientIdOverride
            $0.oauthClientIdOverride = newId
            if let secret {
                $0.oauthClientSecretOverride = secret.isEmpty ? nil : secret
            } else if !sameClient {
                $0.oauthClientSecretOverride = nil
            }
        }
    }

    public func clearOAuthClient() throws {
        try store.update {
            $0.oauthClientIdOverride = nil
            $0.oauthClientSecretOverride = nil
        }
    }
}

/// No account at all: the tool before it is told of one.
public final class NoGoogleAccount: GoogleAccount {
    public init() {}
    public var isSignedIn: Bool { false }
    public var email: String? { nil }
    public var hasOAuthClient: Bool { false }
    public var hasAntigravityTokens: Bool { false }
    public func importFromAntigravity() throws -> Bool { false }
    public var customOAuthClientId: String? { nil }
    public var hasCustomOAuthClientSecret: Bool { false }
    public var hasBundledOAuthClient: Bool { false }
    public func saveOAuthClient(id: String, secret: String?) throws {}
    public func clearOAuthClient() throws {}
}

/// The Chat & Slack credentials, as far as the tool's Settings needs them:
/// whether a Slack or Beeper token is saved and whether Google Chat access
/// was granted, never a value. A token goes in through `saveSlackToken` or
/// `saveBeeperToken` and nothing reads it back out.
public protocol ChatCredentials: AnyObject {
    var hasSlackToken: Bool { get }
    /// The Google Chat login exists with every Chat scope.
    var hasChatAccess: Bool { get }
    var hasBeeperToken: Bool { get }
    /// Saves `token` as it is given: the caller trims it.
    func saveSlackToken(_ token: String) throws
    func clearSlackToken() throws
    /// Saves `token` as it is given: the caller trims it.
    func saveBeeperToken(_ token: String) throws
    func clearBeeperToken() throws
}

/// One HomeSpeaker's secrets file, read afresh on every question, and
/// written through `SecretStore.update`, under its lock, so that
/// HomeSpeaker refreshing a Google token never writes over the token saved
/// here.
public final class SecretStoreChatCredentials: ChatCredentials {
    /// The secrets file: the extension's engine's, never the app's.
    public let store: SecretStore

    public init(store: SecretStore) {
        self.store = store
    }

    public var hasSlackToken: Bool { !(store.load().slackToken?.isEmpty ?? true) }
    public var hasChatAccess: Bool { store.load().hasChatAccess }

    public func saveSlackToken(_ token: String) throws {
        try store.update { $0.slackToken = token.isEmpty ? nil : token }
    }

    public func clearSlackToken() throws {
        try store.update { $0.slackToken = nil }
    }

    public var hasBeeperToken: Bool { !(store.load().beeperToken?.isEmpty ?? true) }

    public func saveBeeperToken(_ token: String) throws {
        try store.update { $0.beeperToken = token.isEmpty ? nil : token }
    }

    public func clearBeeperToken() throws {
        try store.update { $0.beeperToken = nil }
    }
}

/// No credentials at all: the tool before it is told of any.
public final class NoChatCredentials: ChatCredentials {
    public init() {}
    public var hasSlackToken: Bool { false }
    public var hasChatAccess: Bool { false }
    public func saveSlackToken(_ token: String) throws {}
    public func clearSlackToken() throws {}
    public var hasBeeperToken: Bool { false }
    public func saveBeeperToken(_ token: String) throws {}
    public func clearBeeperToken() throws {}
}
