// Copyright 2026 VitruvianSoftware
// SPDX-License-Identifier: AGPL-3.0-or-later

import XCTest

@testable import CourierCore

/// What the sign-in window collects from a page, as a pure mapping: given the page's cookies, its local storage
/// and what the step's ExtractJS resolved to, which values go to login.submit. The steps here are shaped like the
/// bridges' own (Slack's "token" flow, Google Messages' "google" flow); every value is made up.
final class CookieCollectorTests: XCTestCase {
    private func source(_ type: LoginCookieSourceType, _ name: String, domain: String? = nil) -> LoginCookieSource {
        LoginCookieSource(type: type, name: name, cookieDomain: domain)
    }

    private func field(_ id: String, required: Bool = true, _ sources: [LoginCookieSource]) -> LoginCookieField {
        LoginCookieField(id: id, required: required, sources: sources, pattern: nil)
    }

    private func step(_ fields: [LoginCookieField], extractJS: String? = nil,
                      waitForURL: String? = nil) -> LoginCookies {
        LoginCookies(url: "https://example.invalid/signin", userAgent: nil, waitForURL: waitForURL,
                     extractJS: extractJS, fields: fields)
    }

    /// Slack's token step (mautrix-slack login-cookie.go): auth_token from its ExtractJS or a request body,
    /// cookie_token from the `d` cookie on slack.com.
    private var slackLike: LoginCookies {
        step([
            field("auth_token", [source(.special, "fi.mau.slack.auth_token"), source(.requestBody, "token")]),
            field("cookie_token", [source(.cookie, "d", domain: "slack.com")]),
        ], extractJS: "new Promise(resolve => resolve({}))")
    }

    func testCookieSourceByNameAndDomain() {
        let params = step([
            field("SID", [source(.cookie, "SID", domain: ".example.com")]),
            field("OSID", [source(.cookie, "OSID", domain: "messages.example.com")]),
            field("any", [source(.cookie, "any")]),
        ])
        let cookies = [
            // Same name, other domains: never the one asked for.
            BrowserCookie(name: "SID", domain: "other.invalid", value: "wrong-1"),
            BrowserCookie(name: "OSID", domain: "accounts.example.com", value: "wrong-2"),
            BrowserCookie(name: "OSID", domain: ".example.com", value: "wrong-3"),
            // A subdomain of the domain asked for counts; a leading dot is the same domain.
            BrowserCookie(name: "SID", domain: "www.example.com", value: "sid-sub"),
            BrowserCookie(name: "OSID", domain: "messages.example.com", value: "osid-1"),
            BrowserCookie(name: "sid", domain: "example.com", value: "wrong-case"),
            // No domain asked for: any.
            BrowserCookie(name: "any", domain: "anywhere.invalid", value: "any-1"),
        ]
        let collected = CookieCollector.collect(params, cookies: cookies, localStorage: [:], extracted: [:])
        XCTAssertEqual(collected.values, ["SID": "sid-sub", "OSID": "osid-1", "any": "any-1"])
        XCTAssertTrue(collected.isComplete)

        // When both the domain itself and a subdomain have one, the domain's own wins.
        let both = [
            BrowserCookie(name: "SID", domain: "www.example.com", value: "sid-sub"),
            BrowserCookie(name: "SID", domain: ".example.com", value: "sid-exact"),
        ]
        let exact = CookieCollector.collect(step([field("SID", [source(.cookie, "SID", domain: "example.com")])]),
                                            cookies: both, localStorage: [:], extracted: [:])
        XCTAssertEqual(exact.values, ["SID": "sid-exact"])

        // A value is sent raw, as the browser has it: the engine URL-decodes and checks it.
        let raw = CookieCollector.collect(slackLike,
                                          cookies: [BrowserCookie(name: "d", domain: ".slack.com", value: "xoxd-a%2Fb%3D")],
                                          localStorage: [:], extracted: ["auth_token": "xoxc-made-up"])
        XCTAssertEqual(raw.values, ["auth_token": "xoxc-made-up", "cookie_token": "xoxd-a%2Fb%3D"])
    }

    func testLocalStorageSource() {
        let params = step([field("token", [source(.localStorage, "session_token")])])
        XCTAssertEqual(CookieCollector.localStorageKeys(params), ["session_token"])
        let collected = CookieCollector.collect(params, cookies: [], localStorage: ["session_token": "made-up"],
                                                extracted: [:])
        XCTAssertEqual(collected.values, ["token": "made-up"])
    }

    func testSpecialFromExtractJS() {
        // Slack's ExtractJS resolves to `{ auth_token }`: the result is keyed by field id, not by the source's name.
        let extracted = CookieCollector.extractedValues(from: ["auth_token": "xoxc-made-up", "count": 3,
                                                               "empty": "", "nested": ["a": "b"]] as [String: Any])
        XCTAssertEqual(extracted, ["auth_token": "xoxc-made-up"], "only non-empty strings are values")
        XCTAssertEqual(CookieCollector.extractedValues(from: "xoxc-not-an-object"), [:])
        XCTAssertEqual(CookieCollector.extractedValues(from: nil), [:])

        let before = CookieCollector.collect(slackLike,
                                             cookies: [BrowserCookie(name: "d", domain: ".slack.com", value: "xoxd-1")],
                                             localStorage: [:], extracted: [:])
        XCTAssertFalse(before.isComplete)
        XCTAssertEqual(before.missingRequired, ["auth_token"])

        let after = CookieCollector.collect(slackLike,
                                            cookies: [BrowserCookie(name: "d", domain: ".slack.com", value: "xoxd-1")],
                                            localStorage: [:], extracted: extracted)
        XCTAssertTrue(after.isComplete)
        XCTAssertEqual(after.values, ["auth_token": "xoxc-made-up", "cookie_token": "xoxd-1"])

        // A special-only field is filled by the script's result.
        let special = step([field("captcha_token", [source(.special, "captcha_token")])], extractJS: "x")
        XCTAssertEqual(CookieCollector.collect(special, cookies: [], localStorage: [:],
                                               extracted: ["captcha_token": "made-up"]).values,
                       ["captcha_token": "made-up"])

        // The script is awaited: callAsyncJavaScript's body returns the promise's value.
        let script = CookieCollector.extractScript("new Promise(r => r({}))\n")
        XCTAssertTrue(script.hasPrefix("return await ("), script)
        XCTAssertTrue(script.contains("new Promise(r => r({}))"))
    }

    func testUncapturableSourceSaysSo() {
        // Slack's step is fine: auth_token can come from its ExtractJS, even though its request-body source can't.
        XCTAssertEqual(CookieCollector.uncapturableFields(slackLike), [])

        // A required field that only a request header or body has: the window can never fill it.
        let headerOnly = step([
            field("bearer", [source(.requestHeader, "Authorization")]),
            field("body", [source(.requestBody, "token")]),
            field("ok", [source(.cookie, "ok")]),
            field("optional", required: false, [source(.requestHeader, "X-Optional")]),
        ])
        XCTAssertEqual(CookieCollector.uncapturableFields(headerOnly), ["bearer", "body"],
                       "an optional field the window can't read is not a reason to stop")

        // A special source with no script to fill it is as good as none.
        let noScript = step([field("special", [source(.special, "fi.example.token")])])
        XCTAssertEqual(CookieCollector.uncapturableFields(noScript), ["special"])

        // The page must be an https one.
        XCTAssertEqual(CookieCollector.pageURL(slackLike)?.absoluteString, "https://example.invalid/signin")
        for bad in ["http://example.invalid/", "file:///etc/hosts", "javascript:alert(1)", "", "https://"] {
            let params = LoginCookies(url: bad, userAgent: nil, waitForURL: nil, extractJS: nil, fields: [])
            XCTAssertNil(CookieCollector.pageURL(params), bad)
        }

        // A source type this app does not know is not one it can read.
        let unknown = step([field("new", [source(LoginCookieSourceType(rawValue: "indexed_db"), "x")])])
        XCTAssertEqual(CookieCollector.uncapturableFields(unknown), ["new"])
    }

    func testOptionalMissingIsOmittedNotEmpty() {
        let params = step([
            field("SID", [source(.cookie, "SID", domain: "example.com")]),
            field("PSIDTS", required: false, [source(.cookie, "PSIDTS", domain: "example.com")]),
            field("blank", required: false, [source(.localStorage, "blank")]),
        ])
        let collected = CookieCollector.collect(
            params, cookies: [BrowserCookie(name: "SID", domain: "example.com", value: "sid-1")],
            localStorage: ["blank": ""], extracted: [:])
        XCTAssertEqual(collected.values, ["SID": "sid-1"])
        XCTAssertNil(collected.values["PSIDTS"])
        XCTAssertNil(collected.values["blank"], "an empty value is no value")
        XCTAssertTrue(collected.isComplete, "only required fields hold it up")

        // An empty required value is missing too.
        let empty = CookieCollector.collect(
            params, cookies: [BrowserCookie(name: "SID", domain: "example.com", value: "")], localStorage: [:],
            extracted: [:])
        XCTAssertEqual(empty.values, [:])
        XCTAssertEqual(empty.missingRequired, ["SID"])
    }

    func testReadyNeedsTheURLWhenTheStepNamesOne() {
        let params = step([field("SID", [source(.cookie, "SID")])], waitForURL: #"^https://app\.example\.com/"#)
        let complete = CookieCollector.collect(params, cookies: [BrowserCookie(name: "SID", domain: "x", value: "1")],
                                               localStorage: [:], extracted: [:])
        XCTAssertFalse(CookieCollector.isReady(params, url: "https://example.com/signin", collected: complete))
        XCTAssertTrue(CookieCollector.isReady(params, url: "https://app.example.com/home", collected: complete))
        // The URL alone is not enough: there is nothing to send yet.
        let empty = CookieCollector.collect(params, cookies: [], localStorage: [:], extracted: [:])
        XCTAssertFalse(CookieCollector.isReady(params, url: "https://app.example.com/home", collected: empty))

        // No pattern: ready as soon as every required field is there.
        let noPattern = step([field("SID", [source(.cookie, "SID")])])
        XCTAssertTrue(CookieCollector.isReady(noPattern, url: nil, collected: complete))
        // A pattern this app can't compile never matches, so only "I've signed in" sends.
        let bad = step([field("SID", [source(.cookie, "SID")])], waitForURL: "(")
        XCTAssertFalse(CookieCollector.isReady(bad, url: "https://example.com/", collected: complete))
    }

    func testCollectsGoogleChatDomainScopedCookies() {
        let params = LoginCookies(
            url: "https://chat.google.com/",
            userAgent: nil,
            waitForURL: #"^https://chat\.google\.com/"#,
            extractJS: nil,
            fields: [
                field("COMPASS", [source(.cookie, "COMPASS", domain: "chat.google.com")]),
                field("OSID", [source(.cookie, "OSID", domain: "chat.google.com")]),
                field("SID", [source(.cookie, "SID", domain: "google.com")]),
                field("HSID", [source(.cookie, "HSID", domain: "google.com")]),
                field("SSID", [source(.cookie, "SSID", domain: "google.com")]),
                field("APISID", required: false, [source(.cookie, "APISID", domain: "google.com")]),
                field("SAPISID", required: false, [source(.cookie, "SAPISID", domain: "google.com")]),
                field("__Secure-1PSID", required: false, [source(.cookie, "__Secure-1PSID", domain: "google.com")]),
                field("__Secure-3PSID", required: false, [source(.cookie, "__Secure-3PSID", domain: "google.com")]),
                field("user_agent", required: false, [source(.special, "user_agent")]),
            ]
        )
        XCTAssertEqual(CookieCollector.uncapturableFields(params), [])
        XCTAssertEqual(NetworkNames.displayName(of: "gchat"), "Google Chat")

        let cookies = [
            BrowserCookie(name: "COMPASS", domain: "chat.google.com", value: "dynamite-ui=synthetic"),
            BrowserCookie(name: "OSID", domain: "chat.google.com", value: "osid-chat"),
            BrowserCookie(name: "OSID", domain: "mail.google.com", value: "osid-wrong"),
            BrowserCookie(name: "SID", domain: ".google.com", value: "sid-google"),
            BrowserCookie(name: "HSID", domain: ".google.com", value: "hsid-google"),
            BrowserCookie(name: "SSID", domain: ".google.com", value: "ssid-google"),
        ]
        let collected = CookieCollector.collect(params, cookies: cookies, localStorage: [:], extracted: [:])
        XCTAssertTrue(collected.isComplete)
        XCTAssertEqual(collected.values["COMPASS"], "dynamite-ui=synthetic")
        XCTAssertEqual(collected.values["OSID"], "osid-chat")
        XCTAssertEqual(collected.values["SID"], "sid-google")
        XCTAssertEqual(collected.values["HSID"], "hsid-google")
        XCTAssertEqual(collected.values["SSID"], "ssid-google")
        XCTAssertFalse(CookieCollector.isReady(params, url: "https://accounts.google.com/ServiceLogin", collected: collected))
        XCTAssertTrue(CookieCollector.isReady(params, url: "https://chat.google.com/u/0/", collected: collected))
    }
}
