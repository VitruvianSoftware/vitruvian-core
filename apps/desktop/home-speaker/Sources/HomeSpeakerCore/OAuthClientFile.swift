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

import Foundation

/// The Google sign-in client an extension ships with, in a file beside its
/// program (`google-oauth-client.json` in the tool folder):
///
///     {"client_id": "...", "client_secret": "..."}
///
/// Whoever packages the extension puts it there; the program only reads it,
/// and never writes it. Google treats an installed app's client secret as
/// public, so shipping it in a file is the documented pattern.
public enum OAuthClientFile {
    /// The file's name in the tool folder.
    public static let fileName = "google-oauth-client.json"

    private struct Contents: Decodable {
        var client_id: String?
        var client_secret: String?
    }

    /// The client in the file at `url`. Nil when there is no file, it is
    /// empty or not a client, or its client id is blank. A missing secret
    /// is an empty one, as with the app's Info.plist.
    public static func read(_ url: URL) -> OAuthClient? {
        guard let data = try? Data(contentsOf: url), !data.isEmpty,
              let contents = try? JSONDecoder().decode(Contents.self, from: data),
              let id = contents.client_id?.trimmingCharacters(in: .whitespacesAndNewlines),
              !id.isEmpty
        else { return nil }
        return OAuthClient(clientId: id, clientSecret: contents.client_secret ?? "")
    }
}
