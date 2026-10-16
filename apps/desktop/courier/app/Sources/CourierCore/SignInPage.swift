// Copyright 2026 VitruvianSoftware
// SPDX-License-Identifier: AGPL-3.0-or-later

import Foundation

/// What the sign-in window lets its page do, and what its address bar says. The person decides whether to type
/// a password from what the bar shows, so the bar is worked out from the page's address as it is now, every
/// time, and only https earns the lock.
public enum SignInPage {
    /// What the bar shows: `https://host` for a secure page, or that it isn't one.
    public struct Address: Equatable, Sendable {
        public var text: String
        /// Shown with a lock.
        public var isSecure: Bool

        public init(text: String, isSecure: Bool) {
            self.text = text
            self.isSecure = isSecure
        }
    }

    public static var notSecureText: String { String(localized: "Not a secure page") }

    /// Whether the window lets the page go to `url`. The page itself (the main frame) only to https: a plain
    /// http, data:, blob: or about: page could show a form of its own with no real address to show for it.
    /// Frames inside the page may also be data:, blob: or about: (sign-in pages build their own); never http, and
    /// never a link into an app ("slack://…").
    public static func allows(_ url: URL?, mainFrame: Bool) -> Bool {
        let scheme = url?.scheme?.lowercased() ?? ""
        if scheme == "https" { return url?.host != nil }
        return !mainFrame && ["about", "blob", "data"].contains(scheme)
    }

    /// The bar for the page at `url`.
    public static func address(of url: URL?) -> Address {
        guard let url, url.scheme?.lowercased() == "https", let host = url.host, !host.isEmpty else {
            return Address(text: notSecureText, isSecure: false)
        }
        let port = url.port.map { ":\($0)" } ?? ""
        return Address(text: "https://\(host.lowercased())\(port)", isSecure: true)
    }

    /// Whether the page at `url` is on the step's own site: its host or a subdomain of it, over https. Local
    /// storage is read, and the step's script run, only there.
    public static func isOnStepSite(_ url: URL?, step: URL) -> Bool {
        guard let url, url.scheme?.lowercased() == "https", let host = url.host?.lowercased(),
              let stepHost = step.host?.lowercased(), !stepHost.isEmpty else { return false }
        return host == stepHost || host.hasSuffix("." + stepHost)
    }
}
