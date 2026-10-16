// Copyright 2026 VitruvianSoftware
// SPDX-License-Identifier: AGPL-3.0-or-later

import AppKit
import Combine
import CourierCore
import SwiftUI
import WebKit

/// Opens the sign-in window when the sign-in reaches a cookies step, and closes it when the sign-in moves on.
/// One window at a time.
@MainActor
final class SignInWindowPresenter {
    private let login: LoginFlowModel
    private var current: SignInWindowController?
    private var subscription: AnyCancellable?

    init(login: LoginFlowModel) {
        self.login = login
        // Handled after the change, not inside the model's willSet.
        subscription = login.$screen
            .receive(on: DispatchQueue.main)
            .sink { [weak self] screen in self?.show(screen) }
    }

    private func show(_ screen: LoginFlowModel.Screen) {
        guard case let .signIn(network, step) = screen, let params = step.cookies,
              let page = CookieCollector.pageURL(params) else {
            current?.dismiss()
            current = nil
            return
        }
        if let current, current.loginID == step.loginID, current.stepID == step.stepID { return }
        current?.dismiss()
        let login = login
        let controller = SignInWindowController(
            loginID: step.loginID, stepID: step.stepID, networkName: login.displayName(network), params: params,
            page: page,
            collected: { values in login.signInCollected(loginID: step.loginID, stepID: step.stepID, values: values) },
            closedEarly: { login.signInWindowClosed(loginID: step.loginID, stepID: step.stepID) })
        current = controller
        controller.show()
    }
}

/// What the window's bar shows.
@MainActor
final class SignInWindowState: ObservableObject {
    @Published var host = ""
    @Published var notice: String?
}

/// The sign-in window: the step's page in a web view that keeps nothing (a non-persistent data store, so no
/// cookie or storage outlives the window), and an "I've signed in" button.
///
/// It looks for the step's values after every page load and every second while it is open: the page's cookies,
/// its local storage, and what the step's ExtractJS resolves to (run with callAsyncJavaScript, at most 15
/// seconds a time). Once every required value is there and the address matches wait_for_url (if the step has
/// one), it hands them over and closes. "I've signed in" hands over whatever is there if every required value
/// is, address or not. Closing the window any other way cancels the sign-in.
@MainActor
final class SignInWindowController: NSObject, NSWindowDelegate, WKNavigationDelegate, WKUIDelegate {
    static let extractTimeout: TimeInterval = 15
    static let storageTimeout: TimeInterval = 5
    static let checkInterval: TimeInterval = 1

    let loginID: String
    let stepID: String
    private let params: LoginCookies
    private let page: URL
    private let collected: ([String: String]) -> Void
    private let closedEarly: () -> Void
    private let webView: WKWebView
    private let window: NSWindow
    private let state = SignInWindowState()
    private var timer: Timer?
    /// Handed over, cancelled or dismissed: nothing more is reported.
    private var finished = false
    private var loaded = false
    private var checking = false
    private var extracting = false
    private var extracted: [String: String] = [:]
    /// Local storage values seen, kept across pages (the page that has them may navigate on).
    private var storage: [String: String] = [:]
    private var lastCollected: CollectedCookies?

    init(loginID: String, stepID: String, networkName: String, params: LoginCookies, page: URL,
         collected: @escaping ([String: String]) -> Void, closedEarly: @escaping () -> Void) {
        self.loginID = loginID
        self.stepID = stepID
        self.params = params
        self.page = page
        self.collected = collected
        self.closedEarly = closedEarly
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = .nonPersistent()
        webView = WKWebView(frame: .zero, configuration: configuration)
        if let agent = params.userAgent, !agent.isEmpty { webView.customUserAgent = agent }
        window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 980, height: 760),
                          styleMask: [.titled, .closable, .miniaturizable, .resizable], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.title = String(localized: "Sign in to \(networkName)")
        window.minSize = NSSize(width: 520, height: 480)
        super.init()
        window.delegate = self
        webView.navigationDelegate = self
        webView.uiDelegate = self
        let content = SignInWindowContent(state: state, webView: webView, networkName: networkName,
                                          signedIn: { [weak self] in self?.signedInPressed() })
        window.contentView = NSHostingView(rootView: content)
    }

    func show() {
        webView.load(URLRequest(url: page))
        state.host = page.host ?? ""
        window.center()
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        let timer = Timer(timeInterval: Self.checkInterval, repeats: true) { [weak self] _ in
            Task { @MainActor in await self?.check(manual: false) }
        }
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    /// Closes the window without reporting anything: the sign-in has moved on.
    func dismiss() {
        finished = true
        window.close()
    }

    // MARK: - Looking for the values

    private func signedInPressed() {
        Task { await check(manual: true) }
    }

    private func check(manual: Bool) async {
        guard !finished, manual || !checking else { return }
        checking = true
        defer { checking = false }
        if loaded, !extracting, !(lastCollected?.isComplete ?? false) { runExtract() }
        let cookies = await webView.configuration.websiteDataStore.httpCookieStore.allCookies()
            .map { BrowserCookie(name: $0.name, domain: $0.domain, value: $0.value) }
        await readLocalStorage()
        guard !finished else { return }
        state.host = webView.url?.host ?? state.host
        let collected = CookieCollector.collect(params, cookies: cookies, localStorage: storage, extracted: extracted)
        lastCollected = collected
        if CookieCollector.isReady(params, url: webView.url?.absoluteString, collected: collected)
            || (manual && collected.isComplete) {
            hand(collected.values)
        } else if manual {
            state.notice = String(localized: "Courier hasn’t found everything it needs yet. Finish signing in, then try again.")
        }
    }

    private func hand(_ values: [String: String]) {
        finished = true
        timer?.invalidate()
        collected(values)
        window.close()
    }

    /// Runs the step's ExtractJS in the page's own world (it reads the page's state and may add to the page),
    /// awaiting the promise it evaluates to, for at most 15 seconds; then it may run again.
    private func runExtract() {
        guard let js = params.extractJS, !js.isEmpty else { return }
        extracting = true
        Task {
            let values = await evaluate(CookieCollector.extractScript(js), arguments: [:], in: .page,
                                        timeout: Self.extractTimeout)
            extracting = false
            guard !finished, let values, !values.isEmpty else { return }
            extracted.merge(values) { _, new in new }
            await check(manual: false)
        }
    }

    /// Reads the step's local storage keys, in a world of Courier's own so the page can't see or change it.
    private func readLocalStorage() async {
        let keys = CookieCollector.localStorageKeys(params)
        guard !keys.isEmpty else { return }
        let body = """
            const out = {};
            for (const key of keys) {
              const value = window.localStorage.getItem(key);
              if (value !== null) { out[key] = value; }
            }
            return out;
            """
        guard let values = await evaluate(body, arguments: ["keys": keys], in: .defaultClient,
                                          timeout: Self.storageTimeout) else { return }
        storage.merge(values) { _, new in new }
    }

    /// The string values of the object a function body returns, or nil if it failed or ran past `timeout`.
    private func evaluate(_ body: String, arguments: [String: Any], in world: WKContentWorld,
                          timeout: TimeInterval) async -> [String: String]? {
        await withCheckedContinuation { (continuation: CheckedContinuation<[String: String]?, Never>) in
            let answered = Flag()
            webView.callAsyncJavaScript(body, arguments: arguments, in: nil, in: world) { result in
                guard answered.set() else { return }
                switch result {
                case let .success(value): continuation.resume(returning: CookieCollector.extractedValues(from: value))
                case .failure: continuation.resume(returning: nil)
                }
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + timeout) {
                guard answered.set() else { return }
                continuation.resume(returning: nil)
            }
        }
    }

    // MARK: - NSWindowDelegate

    func windowWillClose(_ notification: Notification) {
        timer?.invalidate()
        timer = nil
        webView.stopLoading()
        webView.navigationDelegate = nil
        webView.uiDelegate = nil
        guard !finished else { return }
        finished = true
        closedEarly()
    }

    // MARK: - WKNavigationDelegate

    func webView(_ webView: WKWebView, decidePolicyFor action: WKNavigationAction,
                 decisionHandler: @escaping @MainActor @Sendable (WKNavigationActionPolicy) -> Void) {
        // The web only: a link into a network's own app ("slack://…") would only fail here.
        let scheme = action.request.url?.scheme?.lowercased() ?? ""
        decisionHandler(["https", "http", "about", "blob", "data"].contains(scheme) ? .allow : .cancel)
    }

    func webView(_ webView: WKWebView, didCommit navigation: WKNavigation!) {
        state.host = webView.url?.host ?? state.host
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        loaded = true
        Task { await check(manual: false) }
    }

    // MARK: - WKUIDelegate

    /// A popup (a "Sign in with Google" window, say) opens in this same view.
    func webView(_ webView: WKWebView, createWebViewWith configuration: WKWebViewConfiguration,
                 for action: WKNavigationAction, windowFeatures: WKWindowFeatures) -> WKWebView? {
        if action.targetFrame == nil { webView.load(action.request) }
        return nil
    }
}

/// Whether something has happened yet; main thread only.
private final class Flag {
    private var done = false

    /// True the first time.
    func set() -> Bool {
        defer { done = true }
        return !done
    }
}

/// The window's content: a bar with where the page is and "I've signed in", then the page.
private struct SignInWindowContent: View {
    @ObservedObject var state: SignInWindowState
    let webView: WKWebView
    let networkName: String
    let signedIn: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 10) {
                Image(systemName: "lock.fill")
                    .foregroundStyle(.secondary)
                    .accessibilityHidden(true)
                Text(state.host)
                    .font(.callout.monospaced())
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .accessibilityLabel(String(localized: "Page address: \(state.host)"))
                Spacer(minLength: 12)
                Text(String(localized: "Sign in to \(networkName) here."))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                Button(String(localized: "I’ve signed in"), action: signedIn)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            if let notice = state.notice {
                Text(notice)
                    .font(.callout)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 12)
                    .padding(.bottom, 8)
            }
            Divider()
            WebViewHost(webView: webView)
        }
        .frame(minWidth: 520, minHeight: 480)
    }
}

private struct WebViewHost: NSViewRepresentable {
    let webView: WKWebView

    func makeNSView(context: Context) -> WKWebView { webView }
    func updateNSView(_ view: WKWebView, context: Context) {}
}
