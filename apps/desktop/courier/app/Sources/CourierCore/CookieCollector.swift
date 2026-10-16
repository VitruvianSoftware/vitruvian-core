// Copyright 2026 VitruvianSoftware
// SPDX-License-Identifier: AGPL-3.0-or-later

import Foundation

/// One cookie the sign-in window's page has, as the web view's cookie store gives it.
public struct BrowserCookie: Equatable, Sendable {
    public var name: String
    /// The cookie's domain, as set: "slack.com", ".google.com" or "messages.google.com".
    public var domain: String
    public var value: String

    public init(name: String, domain: String, value: String) {
        self.name = name
        self.domain = domain
        self.value = value
    }
}

/// What a cookies step's page has given so far: the values to send, and the required fields still missing.
public struct CollectedCookies: Equatable, Sendable {
    /// By field id. Only fields that were found, and never an empty value: an optional field that is missing is
    /// left out.
    public var values: [String: String]
    /// Required fields not found yet, in the step's order.
    public var missingRequired: [String]

    public var isComplete: Bool { missingRequired.isEmpty }
}

/// What the sign-in window reads from its page for a cookies step, worked out without the page: which fields the
/// window can never fill, and which values the page's cookies, local storage and ExtractJS result give.
///
/// The sources, as bridgev2's LoginCookieFieldSource has them:
/// - `cookie`: the cookie of that name whose domain is the one asked for or a subdomain of it.
/// - `local_storage`: the page's `localStorage.getItem(name)`.
/// - `special`: what the step's ExtractJS resolved to. The script's result is an object keyed by field id
///   (mautrix-slack's ExtractSlackTokenJS resolves to `{ auth_token }`), and a field it has is filled whatever
///   its sources say, as bridgev2 says: "Fields that are not present in the promise result must be extracted
///   another way."
/// - `request_header`, `request_body`: not read in this milestone.
///
/// Values are sent as the browser has them: the engine URL-decodes them and checks them against their patterns.
public enum CookieCollector {
    /// The source types this window can read. `special` only when the step has an ExtractJS.
    static func canRead(_ source: LoginCookieSource, extractJS: String?) -> Bool {
        switch source.type {
        case .cookie, .localStorage: true
        case .special: !(extractJS ?? "").isEmpty
        default: false
        }
    }

    /// Required fields that no source this window can read could fill, in the step's order. When there is one,
    /// the sign-in can't finish here: the app says so and cancels before it shows the page.
    public static func uncapturableFields(_ params: LoginCookies) -> [String] {
        params.fields.filter { field in
            field.required && !field.sources.contains { canRead($0, extractJS: params.extractJS) }
        }.map(\.id)
    }

    /// The page the window opens: the step's URL, when it is an https one.
    public static func pageURL(_ params: LoginCookies) -> URL? {
        guard let url = URL(string: params.url), url.scheme?.lowercased() == "https", url.host != nil else { return nil }
        return url
    }

    /// The local storage keys to read from the page.
    public static func localStorageKeys(_ params: LoginCookies) -> [String] {
        var keys: [String] = []
        for field in params.fields {
            for source in field.sources where source.type == .localStorage && !keys.contains(source.name) {
                keys.append(source.name)
            }
        }
        return keys
    }

    /// The values the page gives now.
    public static func collect(_ params: LoginCookies, cookies: [BrowserCookie], localStorage: [String: String],
                               extracted: [String: String]) -> CollectedCookies {
        var values: [String: String] = [:]
        var missing: [String] = []
        for field in params.fields {
            if let value = value(for: field, cookies: cookies, localStorage: localStorage, extracted: extracted) {
                values[field.id] = value
            } else if field.required {
                missing.append(field.id)
            }
        }
        return CollectedCookies(values: values, missingRequired: missing)
    }

    private static func value(for field: LoginCookieField, cookies: [BrowserCookie], localStorage: [String: String],
                              extracted: [String: String]) -> String? {
        if let value = extracted[field.id], !value.isEmpty { return value }
        for source in field.sources {
            let found: String?
            switch source.type {
            case .cookie:
                found = cookie(named: source.name, domain: source.cookieDomain, in: cookies)
            case .localStorage:
                found = localStorage[source.name]
            default:
                found = nil
            }
            if let found, !found.isEmpty { return found }
        }
        return nil
    }

    /// The cookie of that name on that domain: the domain's own first, then one of its subdomains'. No domain
    /// asked for means any.
    static func cookie(named name: String, domain: String?, in cookies: [BrowserCookie]) -> String? {
        let named = cookies.filter { $0.name == name && !$0.value.isEmpty }
        guard let wanted = domain.map(normalized), !wanted.isEmpty else { return named.first?.value }
        if let exact = named.first(where: { normalized($0.domain) == wanted }) { return exact.value }
        return named.first { normalized($0.domain).hasSuffix("." + wanted) }?.value
    }

    private static func normalized(_ domain: String) -> String {
        var domain = domain.lowercased()
        while domain.hasPrefix(".") { domain.removeFirst() }
        return domain
    }

    /// Whether the window may send without the person's say-so: every required field is there, and the page's
    /// address matches the step's wait_for_url, if it names one. A pattern this app can't compile never
    /// matches, so the person's "I've signed in" is what sends then.
    public static func isReady(_ params: LoginCookies, url: String?, collected: CollectedCookies) -> Bool {
        collected.isComplete && urlMatches(url, pattern: params.waitForURL)
    }

    /// True for no pattern; otherwise whether `url` matches it somewhere, as Go's regexp.MatchString does.
    public static func urlMatches(_ url: String?, pattern: String?) -> Bool {
        guard let pattern, !pattern.isEmpty else { return true }
        guard let url, let regex = try? NSRegularExpression(pattern: pattern) else { return false }
        return regex.firstMatch(in: url, range: NSRange(url.startIndex..., in: url)) != nil
    }

    /// What an ExtractJS result gives: its string values that are not empty, by key. Anything that is not an
    /// object gives nothing.
    public static func extractedValues(from result: Any?) -> [String: String] {
        guard let object = result as? [String: Any] else { return [:] }
        return object.compactMapValues { value in
            guard let string = value as? String, !string.isEmpty else { return nil }
            return string
        }
    }

    /// The body for WKWebView's callAsyncJavaScript: ExtractJS is an expression that evaluates to a promise, and
    /// the body returns what it resolves to.
    public static func extractScript(_ extractJS: String) -> String {
        "return await (\n\(extractJS)\n);"
    }
}
