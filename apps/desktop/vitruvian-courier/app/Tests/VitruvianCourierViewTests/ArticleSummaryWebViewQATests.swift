// Copyright 2026 VitruvianSoftware
// SPDX-License-Identifier: AGPL-3.0-or-later

import AppKit
import Network
import WebKit
import XCTest

@testable import VitruvianCourier

/// Google's search suggestions are Google's own HTML. These load such a page in the real web view the app makes and
/// count what reaches a local server (nothing leaves this Mac): the page's images, style sheets and fonts must not.
@MainActor
final class ArticleSummaryWebViewQATests: XCTestCase {
    /// A loopback HTTP server that counts requests.
    private final class Counter: @unchecked Sendable {
        private let lock = NSLock()
        private var paths: [String] = []
        var seen: [String] { lock.lock(); defer { lock.unlock() }; return paths }
        func add(_ path: String) { lock.lock(); paths.append(path); lock.unlock() }
    }

    private func startServer(_ counter: Counter) throws -> (NWListener, UInt16) {
        let listener = try NWListener(using: .tcp, on: .any)
        listener.newConnectionHandler = { connection in
            connection.start(queue: .global())
            connection.receive(minimumIncompleteLength: 1, maximumLength: 8192) { data, _, _, _ in
                let head = String(decoding: data ?? Data(), as: UTF8.self)
                let path = head.split(separator: " ").dropFirst().first.map(String.init) ?? "?"
                counter.add(path)
                let body = path.hasSuffix(".css") ? ".chip{color:red}" : "x"
                let type = path.hasSuffix(".css") ? "text/css" : "image/gif"
                let reply = "HTTP/1.1 200 OK\r\nContent-Type: \(type)\r\nContent-Length: \(body.utf8.count)\r\nConnection: close\r\n\r\n\(body)"
                connection.send(content: Data(reply.utf8), completion: .contentProcessed { _ in connection.cancel() })
            }
        }
        let ready = expectation(description: "listening")
        listener.stateUpdateHandler = { if case .ready = $0 { ready.fulfill() } }
        listener.start(queue: .global())
        wait(for: [ready], timeout: 5)
        return (listener, try XCTUnwrap(listener.port?.rawValue))
    }

    private func page(port: UInt16) -> String {
        """
        <style>.container{display:flex;padding:8px}.chip{display:inline-block;border:solid 1px #d2d2d2;border-radius:16px;padding:5px 16px}</style>
        <link rel="stylesheet" href="http://127.0.0.1:\(port)/remote.css">
        <div class="container"><svg width="20" height="20"><circle cx="10" cy="10" r="8" fill="#4285f4"/></svg>
        <img src="http://127.0.0.1:\(port)/logo.gif" width="20" height="20">
        <a class="chip" href="https://www.google.com/search?q=bridge">bridge opens early</a></div>
        """
    }

    private func settle(_ view: WKWebView, _ seconds: TimeInterval = 1.5) async {
        _ = view
        try? await Task.sleep(for: .seconds(seconds))
    }


    private func compileBlockEverything() async throws -> WKContentRuleList {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("qa-rules-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let store = try XCTUnwrap(WKContentRuleListStore(url: dir))
        return try await withCheckedThrowingContinuation { continuation in
            store.compileContentRuleList(forIdentifier: "qa-block-all", encodedContentRuleList: SearchSuggestionsPolicy.blockEverythingRules) { list, error in
                if let list { continuation.resume(returning: list) } else { continuation.resume(throwing: error ?? CocoaError(.fileReadUnknown)) }
            }
        }
    }

    private final class LoadWaiter: NSObject, WKNavigationDelegate {
        private var continuation: CheckedContinuation<Void, Error>?
        func finished() async throws { try await withCheckedThrowingContinuation { continuation = $0 } }
        func webView(_ w: WKWebView, didFinish n: WKNavigation!) { continuation?.resume(); continuation = nil }
        func webView(_ w: WKWebView, didFail n: WKNavigation!, withError e: Error) { continuation?.resume(throwing: e); continuation = nil }
        func webView(_ w: WKWebView, didFailProvisionalNavigation n: WKNavigation!, withError e: Error) { continuation?.resume(throwing: e); continuation = nil }
    }

    func testGoogleSuggestionsLoadNothingRemoteAndStayLegibleWithoutIt() async throws {
        let counter = Counter()
        let (listener, port) = try startServer(counter)
        defer { listener.cancel() }

        // Control: the same page in the same configuration, without the block rules, does reach the server. If this
        // sees nothing the test can't tell anything (the sandbox may not allow it).
        let control = SuggestionsWebView(frame: NSRect(x: 0, y: 0, width: 296, height: 44),
                                         configuration: SearchSuggestionsPolicy.makeConfiguration())
        control.loadHTMLString("<!doctype html><html><body>\(page(port: port))</body></html>", baseURL: nil)
        await settle(control)
        let controlHits = counter.seen.count
        try XCTSkipIf(controlHits == 0, "the web view could not reach the loopback server here, so blocking can't be shown")

        // Subject: the app's block-everything rules (compiled in a store of our own: the shared store isn't writable in
        // a test sandbox), added to the app's configuration.
        let list = try await compileBlockEverything()
        let before = counter.seen.count
        let configuration = SearchSuggestionsPolicy.makeConfiguration()
        configuration.userContentController.add(list)
        let view = SuggestionsWebView(frame: NSRect(x: 0, y: 0, width: 296, height: 44), configuration: configuration)
        let loaded = LoadWaiter()
        view.navigationDelegate = loaded
        view.loadHTMLString("<!doctype html><html><body>\(page(port: port))</body></html>", baseURL: nil)
        try await loaded.finished()
        await settle(view)
        XCTAssertEqual(counter.seen.count, before, "the page made requests: \(counter.seen.dropFirst(before))")
        let scrollHeight = try await view.evaluateJavaScript("document.documentElement.scrollHeight") as? Int ?? 0
        XCTAssertGreaterThan(scrollHeight, 0)

        // Legible: Google's own inline style still applies (chip is a bordered pill) and its text is there.
        let radius = try await view.evaluateJavaScript("getComputedStyle(document.querySelector('.chip')).borderRadius") as? String
        XCTAssertEqual(radius, "16px")
        let text = try await view.evaluateJavaScript("document.body.innerText") as? String
        XCTAssertEqual(text?.trimmingCharacters(in: .whitespacesAndNewlines), "bridge opens early")
    }
}
