// Copyright 2026 VitruvianSoftware
// SPDX-License-Identifier: AGPL-3.0-or-later

import AppKit
import SwiftUI
import VitruvianCourierCore
import WebKit
import XCTest

@testable import VitruvianCourier

/// Google's search suggestions, round 2: when the block rules can't be made the page is never loaded unblocked and a
/// native "Search Google for: …" row stands in; and chips wider than the panel can be scrolled to.
@MainActor
final class ArticleSummarySuggestionsRound2Tests: XCTestCase {
    private var tempDirs: [URL] = []

    override func tearDown() async throws {
        SearchSuggestionsRules.resetForTesting()
        for dir in tempDirs { try? FileManager.default.removeItem(at: dir) }
        tempDirs = []
    }

    private func ownStore() throws -> WKContentRuleListStore {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("round2-rules-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        tempDirs.append(dir)
        return try XCTUnwrap(WKContentRuleListStore(url: dir))
    }

    private final class Loaded: NSObject, WKNavigationDelegate {
        var continuation: CheckedContinuation<Void, Never>?
        func finished() async { await withCheckedContinuation { continuation = $0 } }
        func webView(_ w: WKWebView, didFinish n: WKNavigation!) { continuation?.resume(); continuation = nil }
        func webView(_ w: WKWebView, didFail n: WKNavigation!, withError e: Error) { continuation?.resume(); continuation = nil }
    }

    // MARK: 1. The rules, and what happens when they can't be made

    func testTheRulesComeFromTheNextStoreWhenTheFirstIsUnavailable() async throws {
        let store = try ownStore()
        let list = await SearchSuggestionsRules.compile(stores: [{ nil }, { store }])
        XCTAssertNotNil(list, "an unavailable store is skipped, and the next one makes the rules")
        XCTAssertEqual(SearchSuggestionsRules.failureLogCount, 0)
    }

    func testWhenNoStoreCanMakeTheRulesThereIsNothingToLoadWithAndTheFailureIsLoggedOnce() async throws {
        let store = try ownStore()
        let none = await SearchSuggestionsRules.compile(stores: [{ nil }])
        XCTAssertNil(none)
        let broken = await SearchSuggestionsRules.compile(rules: "not rules", stores: [{ store }])
        XCTAssertNil(broken, "rules that don't compile are no rules")
        let again = await SearchSuggestionsRules.compile(rules: "not rules", stores: [{ store }])
        XCTAssertNil(again)
        XCTAssertEqual(SearchSuggestionsRules.failureLogCount, 1, "logged once, not on every summary")
    }

    func testTheAppOwnedStoreIsInTheCachesFolderAndPrivate() throws {
        let store = SearchSuggestionsRules.appStore()
        XCTAssertNotNil(store)
        let caches = try XCTUnwrap(FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first)
        let dir = caches.appendingPathComponent(Bundle.main.bundleIdentifier ?? "VitruvianCourier")
            .appendingPathComponent("search-suggestions-rules")
        let mode = try FileManager.default.attributesOfItem(atPath: dir.path)[.posixPermissions] as? Int
        XCTAssertEqual(mode.map { $0 & 0o777 }, 0o700)
    }

    func testAFailedCompileNeverLoadsGooglesPageAndTellsTheCaller() async throws {
        SearchSuggestionsRules.stores = [{ nil }]
        var failures = 0
        let coordinator = SearchSuggestionsView.Coordinator(onHeight: { _ in }, onRulesFailed: { failures += 1 })
        let view = SuggestionsWebView(frame: NSRect(x: 0, y: 0, width: 296, height: 44),
                                      configuration: SearchSuggestionsPolicy.makeConfiguration())
        view.navigationDelegate = coordinator
        coordinator.load(html: "<a href=\"https://www.google.com/search?q=x\">x</a>", in: view)
        try await Task.sleep(for: .milliseconds(600))
        XCTAssertEqual(failures, 1, "the caller is told, so it shows the fallback")
        XCTAssertNil(view.url, "nothing was loaded")
        XCTAssertFalse(view.isLoading)
    }

    func testWhenTheRulesAreMadeThePageLoadsAndTheCallerIsNotTold() async throws {
        let store = try ownStore()
        SearchSuggestionsRules.stores = [{ store }]
        var failures = 0
        let coordinator = SearchSuggestionsView.Coordinator(onHeight: { _ in }, onRulesFailed: { failures += 1 })
        let view = SuggestionsWebView(frame: NSRect(x: 0, y: 0, width: 296, height: 44),
                                      configuration: SearchSuggestionsPolicy.makeConfiguration())
        let loaded = Loaded()
        view.navigationDelegate = loaded
        coordinator.load(html: "<a class=\"chip\" href=\"https://www.google.com/search?q=x\">chip text</a>", in: view)
        await loaded.finished()
        XCTAssertEqual(failures, 0)
        let text = try await view.evaluateJavaScript("document.body.innerText") as? String
        XCTAssertEqual(text?.trimmingCharacters(in: .whitespacesAndNewlines), "chip text")
    }

    // MARK: The native fallback

    func testTheFallbackIsOneGoogleSearchLinkPerQuery() throws {
        let links = SearchSuggestionsPolicy.fallbackLinks(queries: [
            "  bridge opens early ", "Bridge Opens Early", "span & tower: 2026?", "", "q4", "q5",
        ])
        XCTAssertEqual(links.map(\.title), ["Search Google for: bridge opens early", "Search Google for: span & tower: 2026?", "Search Google for: q4"],
                       "repeats and empties are left out, at most three")
        XCTAssertEqual(links[0].url.absoluteString, "https://www.google.com/search?q=bridge%20opens%20early")
        XCTAssertEqual(links[1].url.absoluteString, "https://www.google.com/search?q=span%20%26%20tower%3A%202026%3F",
                       "a query can't add parameters of its own")
        for link in links {
            XCTAssertTrue(SearchSuggestionsPolicy.isGoogleSearch(link.url), "opens only Google's results")
            XCTAssertEqual(SearchSuggestionsPolicy.decide(url: link.url, isLinkClick: true, isMainFrame: true), .openInBrowser(link.url))
        }
        XCTAssertEqual(SearchSuggestionsPolicy.fallbackLinks(queries: [String(repeating: "x", count: 300)])[0].title.count,
                       "Search Google for: ".count + 100)
        XCTAssertTrue(SearchSuggestionsPolicy.fallbackLinks(queries: []).isEmpty)
    }

    func testTheFallbackDrawsAndSaysSomethingEvenWithNoQueries() throws {
        let withQueries = try Snapshot.render("suggestions-fallback", width: 320) {
            SearchSuggestionsFallback(queries: ["bridge opens early", "span opening date"]).padding(12)
        }
        let none = try Snapshot.render("suggestions-fallback-none", width: 320) {
            SearchSuggestionsFallback(queries: []).padding(12)
        }
        XCTAssertGreaterThan(withQueries[0].height, none[0].height, "a row per query")
        XCTAssertGreaterThan(none[0].height, 20, "never nothing")
        XCTAssertEqual(SearchSuggestionsFallback.height(for: ["a", "b"]), 2 * SearchSuggestionsFallback.rowHeight)
        XCTAssertEqual(SearchSuggestionsFallback.height(for: []), SearchSuggestionsFallback.rowHeight)
    }

    // MARK: 2. Chips wider than the panel

    func testSidewaysScrollsStayInTheSuggestionsAndUpAndDownGoToTheTimeline() {
        XCTAssertTrue(SearchSuggestionsPolicy.keepsWheel(deltaX: 12, deltaY: 1, shift: false), "a trackpad swipe sideways")
        XCTAssertTrue(SearchSuggestionsPolicy.keepsWheel(deltaX: 0, deltaY: 5, shift: true), "Shift and the wheel")
        XCTAssertFalse(SearchSuggestionsPolicy.keepsWheel(deltaX: 1, deltaY: 12, shift: false), "up and down is the timeline's")
        XCTAssertFalse(SearchSuggestionsPolicy.keepsWheel(deltaX: 0, deltaY: 0, shift: false))
    }

    func testContentWiderThanThePanelCanBeScrolledTo() async throws {
        let store = try ownStore()
        let compiled = await SearchSuggestionsRules.compile(stores: [{ store }])
        let list = try XCTUnwrap(compiled)
        let configuration = SearchSuggestionsPolicy.makeConfiguration()
        configuration.userContentController.add(list)
        let view = SuggestionsWebView(frame: NSRect(x: 0, y: 0, width: SearchSuggestionsView.width, height: 60), configuration: configuration)
        let window = NSWindow(contentRect: view.frame, styleMask: [.borderless], backing: .buffered, defer: false)
        window.contentView = view
        let loaded = Loaded()
        view.navigationDelegate = loaded
        let chips = (1 ... 8).map { "<a style=\"display:inline-block;width:120px;white-space:nowrap\" href=\"https://www.google.com/search?q=\($0)\">chip \($0)</a>" }.joined()
        view.loadHTMLString(SearchSuggestionsPolicy.document("<div style=\"white-space:nowrap;width:1000px\">\(chips)</div>"), baseURL: nil)
        await loaded.finished()
        let overflow = try await view.evaluateJavaScript("getComputedStyle(document.documentElement).overflowX") as? String
        XCTAssertEqual(overflow, "auto", "sideways overflow scrolls, it isn't cut off")
        let wide = try await view.evaluateJavaScript("document.documentElement.scrollWidth") as? Int ?? 0
        XCTAssertGreaterThan(wide, Int(SearchSuggestionsView.width), "the content is wider than the panel")
        let reached = try await view.evaluateJavaScript("document.scrollingElement.scrollLeft = 400; document.scrollingElement.scrollLeft") as? Int ?? 0
        XCTAssertGreaterThan(reached, 0, "the far chips can be reached")
        let vertical = try await view.evaluateJavaScript("getComputedStyle(document.documentElement).overflowY") as? String
        XCTAssertEqual(vertical, "hidden", "up and down is the timeline's")
        window.contentView = nil
    }
}
