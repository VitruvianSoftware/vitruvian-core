// Copyright 2026 VitruvianSoftware
// SPDX-License-Identifier: AGPL-3.0-or-later

import AppKit
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

/// A web view that never scrolls on its own and passes the wheel to the timeline behind it.
final class SuggestionsWebView: WKWebView {
    override func scrollWheel(with event: NSEvent) {
        nextResponder?.scrollWheel(with: event)
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

    func makeCoordinator() -> Coordinator { Coordinator(onHeight: onHeight) }

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
        private static var rules: WKContentRuleList?

        init(onHeight: @escaping (CGFloat) -> Void) { self.onHeight = onHeight }

        /// Loads `html` once the block-everything rules are in: if they can't be made, nothing is shown.
        func load(html: String, in view: WKWebView) {
            loadedHTML = html
            let controller = view.configuration.userContentController
            func start(_ list: WKContentRuleList) {
                controller.removeAllContentRuleLists()
                controller.add(list)
                view.loadHTMLString(Self.document(html), baseURL: nil)
            }
            if let list = Self.rules { start(list); return }
            WKContentRuleListStore.default().compileContentRuleList(
                forIdentifier: "courier-search-suggestions-block-all",
                encodedContentRuleList: SearchSuggestionsPolicy.blockEverythingRules
            ) { list, _ in
                guard let list else { return }
                Task { @MainActor in
                    Self.rules = list
                    start(list)
                }
            }
        }

        private static func document(_ html: String) -> String {
            "<!doctype html><html><head><meta charset=\"utf-8\"><style>html,body{margin:0;background:transparent;overflow:hidden}</style></head><body>\(html)</body></html>"
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

/// The suggestions as a block under a summary: sized to what Google's HTML needs.
struct SearchSuggestionsBlock: View {
    let html: String
    /// The content's height once measured; a line of chips until then.
    var height: CGFloat = SearchSuggestionsBlock.placeholderHeight
    var onHeight: (CGFloat) -> Void = { _ in }
    static let placeholderHeight: CGFloat = 44

    var body: some View {
        SearchSuggestionsView(html: html, height: height, onHeight: onHeight)
            .frame(width: SearchSuggestionsView.width, height: height)
            .accessibilityLabel(String(localized: "Google search suggestions"))
    }
}
