// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 VitruvianSoftware

import Foundation

/// Where the GitHub token lives between runs: `secrets.json` in the folder
/// the app gives the tool for its own files, readable by its owner alone
/// (0600, in a 0700 folder).
///
/// Why not the Keychain: the tool is a program signed ad hoc, and every
/// release is a new program to the Keychain, which would ask the person
/// to allow it each time, or refuse in silence. A file the person alone can
/// read, in their own Application Support folder, is what `gh` and `gcloud`
/// do, and what HomeSpeaker does. The app's feature kept the token in the
/// Keychain and hands it to the tool once through `storage`; the tool keeps
/// it here from then on and clears the handed copy.
public final class SecretStore {
    public static let fileName = "secrets.json"

    public let fileURL: URL

    private struct Secrets: Codable {
        var token: String?
    }

    public init(folder: URL) {
        fileURL = folder.appendingPathComponent(Self.fileName)
    }

    /// The saved token, or nil when there is none.
    public func token() -> String? {
        guard let data = try? Data(contentsOf: fileURL),
              let secrets = try? JSONDecoder().decode(Secrets.self, from: data),
              let token = secrets.token, !token.isEmpty else { return nil }
        return token
    }

    /// Keeps the token. Nothing but the person can read the file after.
    public func save(token: String) throws {
        let folder = fileURL.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true,
                                                attributes: [.posixPermissions: 0o700])
        let data = try JSONEncoder().encode(Secrets(token: token))
        try data.write(to: fileURL, options: .atomic)
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: fileURL.path)
    }

    /// Forgets the token. Forgetting one that is not there is not an error.
    public func clear() {
        try? FileManager.default.removeItem(at: fileURL)
    }
}
