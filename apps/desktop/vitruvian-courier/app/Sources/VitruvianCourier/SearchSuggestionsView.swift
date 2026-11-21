// Copyright 2026 VitruvianSoftware
// SPDX-License-Identifier: AGPL-3.0-or-later

import AppKit
import os
import SwiftUI
import WebKit

/// What a click or a load inside Google's search suggestions may do. The suggestions are Google's own HTML and CSS
/// (Gemini's `searchEntryPoint.renderedContent`, shown under a summary because Google's terms require it); they are
/// never navigated inside the app: a click on a Google search link opens in the person's browser, and everything else
/// is refused.
enum SearchSuggestionsPolicy {
    enum Decision: Equatable {
        /// The page's first load (the HTML Courier handed it).
        case allow
        /// Open in the person's browser, and stay.
        case openInBrowser(URL)
        case cancel
    }

    /// Hosts a suggestion's link may lead to: Google's search.
    static func isGoogleSearch(_ url: URL) -> Bool {
        guard url.scheme?.lowercased() == "https", url.user == nil, let host = url.host?.lowercased() else { return false }
        return host == "google.com" || host.hasSuffix(".google.com")
    }

    static func decide(url: URL?, isLinkClick: Bool, isMainFrame: Bool) -> Decision {
        if isLinkClick {
            guard let url, isGoogleSearch(url) else { return .cancel }
            return .openInBrowser(url)
        }
        // Not a click: the first load of the HTML Courier gave it (about:blank), and nothing else.
        if isMainFrame, url == nil || url?.absoluteString == "about:blank" { return .allow }
        return .cancel
    }

    /// The page Courier hands the web view: Google's HTML in a transparent body that scrolls sideways when its chips are
    /// wider than the panel (and never up and down: the timeline does that). Only `html` has an overflow: with one on `body` too,
    /// the body would scroll on its own and the page itself would never get wider.
    static func document(_ html: String) -> String {
        "<!doctype html><html><head><meta charset=\"utf-8\"><style>html,body{margin:0;background:transparent}html{overflow-x:auto;overflow-y:hidden}</style></head><body>\(html)</body></html>"
    }

    /// Whether a scroll event belongs to the suggestions (sideways, or with Shift held) or to the timeline behind
    /// them (up and down).
    static func keepsWheel(deltaX: CGFloat, deltaY: CGFloat, shift: Bool) -> Bool {
        shift || abs(deltaX) > abs(deltaY)
    }

    /// A "Search Google for: …" row of the native fallback.
    struct FallbackLink: Equatable, Identifiable {
        let title: String
        let url: URL
        var id: String { url.absoluteString }
    }

    /// The links shown instead of Google's suggestions when they can't be shown safely: one per search Google ran (at most
    /// three, each cut to 100 characters, repeats left out), each opening Google's results in the browser.
    static func fallbackLinks(queries: [String]) -> [FallbackLink] {
        var seen = Set<String>()
        var out: [FallbackLink] = []
        for raw in queries {
            let query = String(raw.trimmingCharacters(in: .whitespacesAndNewlines).prefix(100))
            guard !query.isEmpty, seen.insert(query.lowercased()).inserted,
                  let encoded = query.addingPercentEncoding(withAllowedCharacters: unreserved),
                  let url = URL(string: "https://www.google.com/search?q=\(encoded)")
            else { continue }
            out.append(FallbackLink(title: String(localized: "Search Google for: \(query)"), url: url))
            if out.count == 3 { break }
        }
        return out
    }

    private static let unreserved = CharacterSet(charactersIn: "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-._~")

    /// Blocks every network request the page itself makes (images, fonts, scripts, frames); the HTML is handed over
    /// in memory, so it is not one.
    static let blockEverythingRules = #"[{"trigger":{"url-filter":".*"},"action":{"type":"block"}}]"#

    /// A configuration with JavaScript off for the page, no stored data, and no link previews.
    static func makeConfiguration() -> WKWebViewConfiguration {
        let configuration = WKWebViewConfiguration()
        configuration.defaultWebpagePreferences.allowsContentJavaScript = false
        configuration.websiteDataStore = .nonPersistent()
        return configuration
    }
}

/// The content-rule list that blocks everything the suggestions page asks for. It is compiled into a store in the app's
/// own caches folder (the shared store may not be writable), and failing that into the shared one. If neither works the
/// caller never loads Google's HTML unblocked: it shows the native fallback. A failure is logged once, with the error's
/// domain and code only.
@MainActor
enum SearchSuggestionsRules {
    typealias StoreProvider = () -> WKContentRuleListStore?

    static let identifier = "courier-search-suggestions-block-all"
    private static let log = Logger(subsystem: "dev.vitruvian.courier", category: "SearchSuggestions")
    /// How many times a failure was logged (once per run of the app).
    private(set) static var failureLogCount = 0
    private static var cached: WKContentRuleList?

    /// The stores to try, in order. Tests replace them.
    static var stores: [StoreProvider] = [appStore, { WKContentRuleListStore.default() }]

    /// A store in `~/Library/Caches/<the app>/search-suggestions-rules`, the person's alone (0700).
    nonisolated static func appStore() -> WKContentRuleListStore? {
        guard let caches = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first else { return nil }
        let dir = caches
            .appendingPathComponent(Bundle.main.bundleIdentifier ?? "VitruvianCourier", isDirectory: true)
            .appendingPathComponent("search-suggestions-rules", isDirectory: true)
        do {
            try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true,
                                                    attributes: [.posixPermissions: 0o700])
        } catch {
            return nil
        }
        return WKContentRuleListStore(url: dir)
    }

    /// The compiled rules, or nil when no store could make them.
    static func compile(rules: String = SearchSuggestionsPolicy.blockEverythingRules,
                        stores override: [StoreProvider]? = nil) async -> WKContentRuleList? {
        let useCache = override == nil && rules == SearchSuggestionsPolicy.blockEverythingRules
        if useCache, let cached { return cached }
        var lastError: Error?
        for provider in override ?? stores {
            guard let store = provider() else { continue }
            do {
                let list = try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<WKContentRuleList, Error>) in
                    store.compileContentRuleList(forIdentifier: identifier, encodedContentRuleList: rules) { list, error in
                        if let list { continuation.resume(returning: list) } else {
                            continuation.resume(throwing: error ?? CocoaError(.fileReadUnknown))
                        }
                    }
                }
                if useCache { cached = list }
                return list
            } catch {
                lastError = error
            }
        }
        if failureLogCount == 0 {
            failureLogCount = 1
            let detail = (lastError as NSError?).map { "\($0.domain) \($0.code)" } ?? "no store"
            log.error("Google's search suggestions can't be shown: the block rules did not compile (\(detail, privacy: .public))")
        }
        return nil
    }

    static func resetForTesting() {
        cached = nil
        failureLogCount = 0
        stores = [appStore, { WKContentRuleListStore.default() }]
    }
}

/// A web view that scrolls sideways (a trackpad swipe, or Shift and the wheel) when Google's chips are wider than the
/// panel, and passes every up-and-down scroll to the timeline behind it.
final class SuggestionsWebView: WKWebView {
    override func scrollWheel(with event: NSEvent) {
        if SearchSuggestionsPolicy.keepsWheel(deltaX: event.scrollingDeltaX, deltaY: event.scrollingDeltaY,
                                              shift: event.modifierFlags.contains(.shift)) {
            super.scrollWheel(with: event)
        } else {
            nextResponder?.scrollWheel(with: event)
        }
    }

    override var acceptsFirstResponder: Bool { false }
}

/// Google's search suggestions under a summary: a small web view sized to its content, JavaScript off, no network,
/// links opening in the browser.
struct SearchSuggestionsView: NSViewRepresentable {
    let html: String
    static let width: CGFloat = 296
    let height: CGFloat
    /// Tells the summary's model how tall the content is, so the timeline measures the row again.
    let onHeight: (CGFloat) -> Void
    /// The block rules couldn't be made: nothing was loaded, and the caller shows the native fallback.
    let onRulesFailed: () -> Void

    func makeCoordinator() -> Coordinator { Coordinator(onHeight: onHeight, onRulesFailed: onRulesFailed) }

    func makeNSView(context: Context) -> SuggestionsWebView {
        let view = SuggestionsWebView(frame: NSRect(x: 0, y: 0, width: Self.width, height: max(height, 1)),
                                      configuration: SearchSuggestionsPolicy.makeConfiguration())
        view.navigationDelegate = context.coordinator
        view.allowsLinkPreview = false
        view.setValue(false, forKey: "drawsBackground")
        context.coordinator.load(html: html, in: view)
        return view
    }

    func updateNSView(_ view: SuggestionsWebView, context: Context) {
        if context.coordinator.loadedHTML != html { context.coordinator.load(html: html, in: view) }
    }

    @MainActor
    final class Coordinator: NSObject, WKNavigationDelegate {
        var loadedHTML: String?
        private var onHeight: (CGFloat) -> Void
        private var onRulesFailed: () -> Void

        init(onHeight: @escaping (CGFloat) -> Void, onRulesFailed: @escaping () -> Void) {
            self.onHeight = onHeight
            self.onRulesFailed = onRulesFailed
        }

        /// Loads `html` once the block-everything rules are in. If they can't be made it never loads the page: it says
        /// so (`onRulesFailed`) and the caller shows the native fallback.
        func load(html: String, in view: WKWebView) {
            loadedHTML = html
            Task { @MainActor [weak self, weak view] in
                let list = await SearchSuggestionsRules.compile()
                guard let self, let view, self.loadedHTML == html else { return }
                guard let list else {
                    self.onRulesFailed()
                    return
                }
                let controller = view.configuration.userContentController
                controller.removeAllContentRuleLists()
                controller.add(list)
                view.loadHTMLString(SearchSuggestionsPolicy.document(html), baseURL: nil)
            }
        }

        func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction,
                     decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
            let decision = SearchSuggestionsPolicy.decide(
                url: navigationAction.request.url,
                isLinkClick: navigationAction.navigationType == .linkActivated,
                isMainFrame: navigationAction.targetFrame?.isMainFrame ?? false)
            switch decision {
            case .allow:
                decisionHandler(.allow)
            case let .openInBrowser(url):
                NSWorkspace.shared.open(url)
                decisionHandler(.cancel)
            case .cancel:
                decisionHandler(.cancel)
            }
        }

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            // The app's own script (the page's are off) reads how tall the content is.
            webView.evaluateJavaScript("document.documentElement.scrollHeight") { [weak self] value, _ in
                guard let points = (value as? NSNumber)?.doubleValue, points > 0 else { return }
                Task { @MainActor in self?.onHeight(ceil(CGFloat(points))) }
            }
        }
    }
}

/// What stands in for Google's suggestions when they can't be shown safely: the searches Google ran, each a link that
/// opens Google's results in the browser.
struct SearchSuggestionsFallback: View {
    let queries: [String]
    var open: (URL) -> Void = { url in _ = NSWorkspace.shared.open(url) }
    static let rowHeight: CGFloat = 22

    static func height(for queries: [String]) -> CGFloat {
        CGFloat(max(SearchSuggestionsPolicy.fallbackLinks(queries: queries).count, 1)) * rowHeight
    }

    var body: some View {
        let links = SearchSuggestionsPolicy.fallbackLinks(queries: queries)
        VStack(alignment: .leading, spacing: 0) {
            if links.isEmpty {
                Text(String(localized: "Found with Google Search."))
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .frame(height: Self.rowHeight, alignment: .leading)
            } else {
                ForEach(links) { link in
                    Button { open(link.url) } label: {
                        Text(link.title)
                            .font(.caption2)
                            .foregroundStyle(Color.accentColor)
                            .lineLimit(1)
                            .frame(maxWidth: .infinity, minHeight: Self.rowHeight, alignment: .leading)
                    }
                    .buttonStyle(.plain)
                    .help(link.url.absoluteString)
                }
            }
        }
        .frame(width: SearchSuggestionsView.width, alignment: .leading)
    }
}

/// The suggestions as a block under a summary: Google's own, sized to what its HTML needs, or the native fallback when
/// the block rules can't be made.
struct SearchSuggestionsBlock: View {
    let html: String
    /// The searches Google ran, for the fallback.
    var queries: [String] = []
    /// The content's height once measured; a line of chips until then.
    var height: CGFloat = SearchSuggestionsBlock.placeholderHeight
    var onHeight: (CGFloat) -> Void = { _ in }
    static let placeholderHeight: CGFloat = 44
    @State private var rulesFailed = false

    var body: some View {
        if rulesFailed {
            SearchSuggestionsFallback(queries: queries)
        } else {
            SearchSuggestionsView(html: html, height: height, onHeight: onHeight, onRulesFailed: {
                rulesFailed = true
                onHeight(SearchSuggestionsFallback.height(for: queries))
            })
            .frame(width: SearchSuggestionsView.width, height: height)
            .accessibilityLabel(String(localized: "Google search suggestions"))
        }
    }
}
