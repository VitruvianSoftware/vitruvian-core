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
}

/// HomeSpeaker's own secrets file, read afresh on every question, as the
/// app reads it: the app, the tool and the CLI all sign in and out of it.
public final class SecretStoreAccount: GoogleAccount {
    private let store: SecretStore
    private let antigravityTokens: URL
    private let bundle: Bundle

    /// `bundle` is HomeSpeaker.app's, whose Info.plist may carry the OAuth
    /// client it was packaged with: the tool's own bundle has none.
    public init(store: SecretStore = .shared, antigravityTokens: URL = SecretStore.antigravityTokensURL, bundle: Bundle = .main) {
        self.store = store
        self.antigravityTokens = antigravityTokens
        self.bundle = bundle
    }

    public var isSignedIn: Bool { !(store.load().google?.refreshToken.isEmpty ?? true) }
    public var email: String? { store.load().google?.email }
    public var hasOAuthClient: Bool { OAuthClient.resolve(secrets: store.load(), bundle: bundle) != nil }
    public var hasAntigravityTokens: Bool { FileManager.default.fileExists(atPath: antigravityTokens.path) }

    public func importFromAntigravity() throws -> Bool {
        try store.importFromAntigravity(at: antigravityTokens)
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
}
