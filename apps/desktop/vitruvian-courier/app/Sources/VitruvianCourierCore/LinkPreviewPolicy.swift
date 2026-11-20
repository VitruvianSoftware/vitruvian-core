// Copyright 2026 VitruvianSoftware
// SPDX-License-Identifier: AGPL-3.0-or-later

import Foundation

/// The one question every request Courier makes for a link card (a picture, a title, anything else about the page)
/// asks first: "Show link previews" (`ComposerPreferences.showLinkPreviews`, on by default).
///
/// Off, Courier asks the link's site for nothing, so the site never learns this Mac's address from a link in a chat.
/// A card then shows only what the chat network's own preview brought with the message (saved on this Mac), or a
/// plain link card. The inline player is a separate choice ("Load external embeds automatically").
///
/// The network's own previews are not affected: those arrive with the message and need no request here. The engine's
/// look-ups for links in messages you send have their own setting ("Disable link previews in outgoing messages").
public enum LinkPreviewPolicy {
    /// The line under the setting.
    public static var settingExplanation: String {
        String(localized: "Fetches the picture and title for links you receive. The site sees your Mac's address.")
    }

    /// Whether Courier may make a request to `url` for a link card.
    public static func mayRequest(_ url: URL, showLinkPreviews: Bool) -> Bool {
        guard showLinkPreviews, let scheme = url.scheme?.lowercased() else { return false }
        return scheme == "https" || scheme == "http"
    }
}
