// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 VitruvianSoftware

import Foundation

/// Why connecting GitHub did not finish (design spec §6). A plain value, so
/// Settings can word it (`NotchGitHubStrings.message(for:)`) without knowing
/// the service that raised it.
package enum GitHubAuthError: Error, Sendable, Equatable {
    /// `Preferences.githubClientID` is empty: the GitHub App is not registered yet.
    case notConfigured
    /// The relay URL preference is not an http(s) URL with a host.
    case invalidRelayURL
    /// No answer from the relay. The message names `host`, and the device
    /// flow, which needs no relay, is the way round it.
    case relayUnreachable(host: String)
    /// The relay answered with an error; `reason` is its `error` field.
    case relayRefused(host: String, reason: String)
    /// GitHub's redirect was refused before any exchange (wrong callback,
    /// someone else's `state`, the person declined).
    case callback(GitHubOAuthError)
    /// The sign-in window could not run.
    case browserFailed
    case deviceFlow(GitHubDeviceFlowFailure)
    /// No answer from github.com or api.github.com.
    case gitHubUnreachable
    /// GitHub answered with an HTTP error other than 401.
    case gitHubRefused(status: Int)
    /// The Keychain refused to keep or drop the token; `status` is the OSStatus.
    case keychain(status: Int32)
}
