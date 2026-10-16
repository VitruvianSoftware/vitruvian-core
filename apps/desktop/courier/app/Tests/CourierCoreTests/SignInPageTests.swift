// Copyright 2026 VitruvianSoftware
// SPDX-License-Identifier: AGPL-3.0-or-later

import XCTest

@testable import CourierCore

/// What the sign-in window lets its page do, and what its address bar says: the page must never be able to
/// show a form of its own under another site's name.
final class SignInPageTests: XCTestCase {
    private func url(_ string: String) -> URL? { URL(string: string) }

    func testMainFrameIsHTTPSOnly() {
        XCTAssertTrue(SignInPage.allows(url("https://slack.com/signin"), mainFrame: true))
        XCTAssertTrue(SignInPage.allows(url("HTTPS://app.slack.com/client"), mainFrame: true))
        for refused in ["http://slack.com/signin", "data:text/html,<form>", "blob:https://slack.com/1234",
                        "about:blank", "slack://open", "file:///etc/hosts", "javascript:alert(1)"] {
            XCTAssertFalse(SignInPage.allows(url(refused), mainFrame: true), refused)
        }
        XCTAssertFalse(SignInPage.allows(nil, mainFrame: true))
    }

    func testSubframesMayAlsoBeDataBlobAndAbout() {
        for allowed in ["https://www.google.com/recaptcha/api2/anchor", "data:text/html,x",
                        "blob:https://slack.com/1234", "about:blank", "about:srcdoc"] {
            XCTAssertTrue(SignInPage.allows(url(allowed), mainFrame: false), allowed)
        }
        for refused in ["http://example.invalid/", "slack://open", "file:///etc/hosts", "javascript:alert(1)"] {
            XCTAssertFalse(SignInPage.allows(url(refused), mainFrame: false), refused)
        }
    }

    func testAddressBarSaysWhereThePageReallyIs() {
        XCTAssertEqual(SignInPage.address(of: url("https://app.slack.com/client/T1?x=1")),
                       SignInPage.Address(text: "https://app.slack.com", isSecure: true))
        // Anything that is not https says so, with no lock, whatever was shown before.
        for insecure in ["http://slack.com/signin", "data:text/html,<form>", "blob:https://slack.com/1234",
                         "about:blank"] {
            XCTAssertEqual(SignInPage.address(of: url(insecure)),
                           SignInPage.Address(text: SignInPage.notSecureText, isSecure: false), insecure)
        }
        XCTAssertEqual(SignInPage.address(of: nil), SignInPage.Address(text: SignInPage.notSecureText, isSecure: false))
        // A port is part of where you are.
        XCTAssertEqual(SignInPage.address(of: url("https://slack.com:8443/x")).text, "https://slack.com:8443")
    }

    func testStepSiteIsTheStepHostOrItsSubdomains() {
        let step = URL(string: "https://slack.com/signin")!
        XCTAssertTrue(SignInPage.isOnStepSite(url("https://slack.com/x"), step: step))
        XCTAssertTrue(SignInPage.isOnStepSite(url("https://app.slack.com/client"), step: step))
        XCTAssertTrue(SignInPage.isOnStepSite(url("https://team.slack.com/"), step: step))
        for other in ["https://notslack.com/", "https://slack.com.example.invalid/", "http://slack.com/",
                      "data:text/html,x", "https://accounts.google.com/"] {
            XCTAssertFalse(SignInPage.isOnStepSite(url(other), step: step), other)
        }
        XCTAssertFalse(SignInPage.isOnStepSite(nil, step: step))
    }
}
