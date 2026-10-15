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

/// Google OAuth material for one signed-in account.
public struct GoogleCredentials: Codable, Equatable {
    public var clientId: String
    public var clientSecret: String
    public var accessToken: String
    public var refreshToken: String
    public var expiry: Date?
    /// Scopes the user actually granted; incremental auth adds to this.
    public var scopes: [String]
    /// Google account id (OIDC `sub`); the Chat API names the same person
    /// `users/<sub>`, which is how own messages are recognised and muted.
    public var userId: String?
    public var email: String?

    public init(
        clientId: String, clientSecret: String,
        accessToken: String, refreshToken: String,
        expiry: Date? = nil, scopes: [String] = [],
        userId: String? = nil, email: String? = nil
    ) {
        self.clientId = clientId
        self.clientSecret = clientSecret
        self.accessToken = accessToken
        self.refreshToken = refreshToken
        self.expiry = expiry
        self.scopes = scopes
        self.userId = userId
        self.email = email
    }

    public func hasScope(_ scope: String) -> Bool { scopes.contains(scope) }

    /// True when the access token is missing or within 60 s of expiring.
    public func needsRefresh(at date: Date = Date()) -> Bool {
        guard !accessToken.isEmpty, let expiry else { return true }
        return expiry.timeIntervalSince(date) < 60
    }
}

/// Everything the app must keep private, in one file.
public struct Secrets: Codable, Equatable {
    /// Google Home login (scope home.platform.v2). Google refuses to grant
    /// that scope together with any other API's, so Chat has its own slot.
    public var google: GoogleCredentials?
    /// Google Chat login (chat.*.readonly), a separate consent and token.
    public var googleChat: GoogleCredentials?
    public var slackToken: String?
    /// Optional user-supplied OAuth client, used instead of the one baked
    /// into Info.plist. Lets anyone run the app against their own Google
    /// Cloud project without rebuilding it.
    public var oauthClientIdOverride: String?
    public var oauthClientSecretOverride: String?

    public init(
        google: GoogleCredentials? = nil, googleChat: GoogleCredentials? = nil, slackToken: String? = nil,
        oauthClientIdOverride: String? = nil, oauthClientSecretOverride: String? = nil
    ) {
        self.google = google
        self.googleChat = googleChat
        self.slackToken = slackToken
        self.oauthClientIdOverride = oauthClientIdOverride
        self.oauthClientSecretOverride = oauthClientSecretOverride
    }
}

/// Owner-only (0600) JSON file under ~/Library/Application Support.
///
/// Why not the Keychain: the app ships ad-hoc signed (no Developer ID), so its
/// code identity changes with every build. Keychain ACLs are keyed to that
/// identity, which would mean a "HomeSpeaker wants to use your keychain"
/// prompt after every update. A 0600 file in the user's own Application
/// Support folder is what gcloud and gh do, and it is what the Claude Code
/// hook process (a second copy of this binary) can read without prompts.
///
/// Several processes write it: the running app refreshing a Google token,
/// `HomeSpeaker --sign-in` / `--sign-out`, and the Vitruvian tool saving a
/// Slack token. So every write -- above all `update`'s read-modify-write --
/// holds an exclusive `flock` on `secrets.json.lock` beside it; without it,
/// the app's token refresh could write back a copy read a moment before the
/// tool saved a Slack token, and the token would be gone.
///
/// Re-entrancy: BSD `flock` belongs to an open file description, so a
/// second `open()` of the lock file in the same process waits on the first,
/// like another process would, and nesting would deadlock. The lock is
/// therefore only ever taken inside `queue`, which is serial and is entered
/// once per public call (`save`, `update`, `clear`), never from inside
/// another; at most one descriptor in this process holds or waits for it.
/// `mutate` must not call back into the store. Reads take no lock: a write
/// replaces the file atomically (rename), so a reader sees the old file or
/// the new one, never half of one.
public final class SecretStore: @unchecked Sendable {
    public static let shared = SecretStore()

    public let fileURL: URL
    private let queue = DispatchQueue(label: "com.vitruviansoftware.homespeaker.secrets")

    /// The file `flock` is taken on: `secrets.json.lock`, next to it. Its
    /// own file, so the atomic replace of `secrets.json` never swaps the
    /// locked inode out from under a waiting writer.
    public var lockURL: URL { fileURL.appendingPathExtension("lock") }

    public static func defaultURL() -> URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Application Support")
        return base.appendingPathComponent("HomeSpeaker/secrets.json")
    }

    public init(fileURL: URL = SecretStore.defaultURL()) {
        self.fileURL = fileURL
    }

    public func load() -> Secrets {
        queue.sync { read() }
    }

    public func save(_ secrets: Secrets) throws {
        try queue.sync {
            try withFileLock { try write(secrets) }
        }
    }

    /// Reads, changes and writes the secrets as one step, under the lock,
    /// so a change another process made meanwhile is never written over.
    public func update(_ mutate: (inout Secrets) -> Void) throws {
        try queue.sync {
            try withFileLock {
                var s = read()
                mutate(&s)
                try write(s)
            }
        }
    }

    public func clear() throws {
        try queue.sync {
            guard FileManager.default.fileExists(atPath: fileURL.deletingLastPathComponent().path) else { return }
            try withFileLock { try? FileManager.default.removeItem(at: fileURL) }
        }
    }

    // MARK: Inside the queue

    /// Call only inside `queue`.
    private func read() -> Secrets {
        guard let data = try? Data(contentsOf: fileURL),
              let secrets = try? Self.decoder.decode(Secrets.self, from: data) else { return Secrets() }
        return secrets
    }

    /// Call only inside `queue` and the file lock.
    private func write(_ secrets: Secrets) throws {
        let data = try Self.encoder.encode(secrets)
        try data.write(to: fileURL, options: .atomic)
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: fileURL.path)
    }

    /// Runs `body` holding an exclusive `flock` on `lockURL` (see
    /// `FileLock`), creating the folder (0700) and the lock file (0600) if
    /// need be. Blocks while another process -- or another `SecretStore` on
    /// the same file -- holds it. Call only inside `queue`: see the type's
    /// note on re-entrancy.
    private func withFileLock<T>(_ body: () throws -> T) throws -> T {
        try FileLock.withExclusiveLock(at: lockURL, directoryPermissions: 0o700, body)
    }

    // MARK: Antigravity import

    /// Path the Antigravity Google Home connector writes its OAuth tokens to.
    public static var antigravityTokensURL: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".gemini/antigravity/mcp_oauth_tokens.json")
    }

    /// Reads an Antigravity `mcp_oauth_tokens.json` and returns credentials for
    /// the Google Home MCP entry, or nil when the file has no usable login.
    /// The client id/secret come along so refreshes keep working.
    public static func parseAntigravityTokens(_ data: Data) -> GoogleCredentials? {
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let home = json[GoogleHomeClient.mcpEndpointString] as? [String: Any],
              let token = home["token"] as? [String: Any],
              let access = token["access_token"] as? String,
              let refresh = token["refresh_token"] as? String,
              let clientId = home["client_id"] as? String,
              let clientSecret = home["client_secret"] as? String,
              !access.isEmpty, !refresh.isEmpty else { return nil }
        var expiry: Date?
        if let expiryText = token["expiry"] as? String {
            expiry = ISO8601DateFormatter.fractional.date(from: expiryText)
                ?? ISO8601DateFormatter().date(from: expiryText)
        }
        return GoogleCredentials(
            clientId: clientId, clientSecret: clientSecret,
            accessToken: access, refreshToken: refresh,
            expiry: expiry, scopes: [GoogleAuth.homeScope])
    }

    public func importFromAntigravity(at url: URL = SecretStore.antigravityTokensURL) throws -> Bool {
        guard let data = try? Data(contentsOf: url),
              let creds = Self.parseAntigravityTokens(data) else { return false }
        try update { $0.google = creds }
        return true
    }

    private static let encoder: JSONEncoder = {
        let e = JSONEncoder()
        e.outputFormatting = [.prettyPrinted, .sortedKeys]
        e.dateEncodingStrategy = .iso8601
        return e
    }()

    private static let decoder: JSONDecoder = {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .iso8601
        return d
    }()
}

extension ISO8601DateFormatter {
    static let fractional: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }()
}
