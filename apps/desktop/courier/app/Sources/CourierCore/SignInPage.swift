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

    /// The bar follows the page that is shown: an address counts once WebKit commits it (the new page starts
    /// replacing the old) or finishes loading it, never while it is only being asked for. Until then the bar keeps
    /// the page that is on screen, so a slow or refused request can't put its host over the old page's form.
    /// (Within a page, the address can only change within its own site, which the bar shows the same.)
    public struct Bar: Equatable, Sendable {
        public private(set) var address = SignInPage.address(of: nil)

        public init() {}

        /// WebKit committed, or finished loading, the page at `url`.
        public mutating func shown(_ url: URL?) {
            address = SignInPage.address(of: url)
        }
    }

    /// How the sign-in window's web view says what it is.
    public enum UserAgent: Equatable, Sendable {
        /// The step's own user agent, given whole.
        case custom(String)
        /// WebKit's own, with this application name added to the end (WKWebViewConfiguration's
        /// applicationNameForUserAgent).
        case applicationName(String)
    }

    /// Added to WebKit's user agent when the step gives none, so it reads as Safari's. Some sign-in pages (Google's,
    /// for Google Messages) refuse a browser they don't recognise, and a bare WKWebView names no browser.
    public static let safariApplicationName = "Version/26.0 Safari/605.1.15"

    /// The user agent for a step that asks for `given`: that one if there is one, else WebKit's as Safari's.
    public static func userAgent(_ given: String?) -> UserAgent {
        if let given, !given.isEmpty { return .custom(given) }
        return .applicationName(safariApplicationName)
    }

    /// Whether the page at `url` is on the step's own site: its host or a subdomain of it, over https. Local
    /// storage is read, and the step's script run, only there.
    public static func isOnStepSite(_ url: URL?, step: URL) -> Bool {
        guard let url, url.scheme?.lowercased() == "https", let host = url.host?.lowercased(),
              let stepHost = step.host?.lowercased(), !stepHost.isEmpty else { return false }
        return host == stepHost || host.hasSuffix("." + stepHost)
    }
}
