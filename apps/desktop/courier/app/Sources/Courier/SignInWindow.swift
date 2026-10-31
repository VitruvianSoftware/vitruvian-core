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
    /// The page that is shown (SignInPage.Bar): it moves when a page is committed or loaded, never to a page that
    /// is only being asked for, and never keeps a host from before.
    @Published var bar = SignInPage.Bar()
    var address: SignInPage.Address { bar.address }
    @Published var notice: String?
}

/// The sign-in window: the step's page in a web view that keeps nothing (a non-persistent data store, so no
/// cookie or storage outlives the window), and an "I've signed in" button.
///
/// The page itself may only be https (SignInPage.allows), and the bar shows where it really is, with a lock only
/// for https, so a page can't put a form of its own under another site's name.
///
/// It looks for the step's values after every page load and every second while it is open: the page's cookies,
/// its local storage, and what the step's ExtractJS resolves to. Local storage and the script are read only on
/// the step's own site (its host or a subdomain). The script runs once per page load, with callAsyncJavaScript:
/// one run at a time, a new page load replacing it. Its answer is waited for 15 seconds; after that a press of
/// "I've signed in" may run it again, and a late answer from the run still counts. Once every required value is
/// there and the address matches wait_for_url (if the step has one), it hands them over and closes. "I've signed
/// in" hands over whatever is there if every required value is, address or not. Closing the window any other way
/// cancels the sign-in.
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
    private var checking = false
    /// The script's current run, by number; nil when none is running or the last one ran past its time.
    private var extractRun: Int?
    private var extractRuns = 0
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
        let userAgent = SignInPage.userAgent(params.userAgent)
        if case let .applicationName(name) = userAgent { configuration.applicationNameForUserAgent = name }
        webView = WKWebView(frame: .zero, configuration: configuration)
        if case let .custom(agent) = userAgent { webView.customUserAgent = agent }
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
        window.center()
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        self.timer?.invalidate()
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
        // A run that went past its time may have missed what the page has now.
        if extractRun == nil { runExtract() }
        Task { await check(manual: true) }
    }

    /// Whether the page is on the step's own site now.
    private var onStepSite: Bool { SignInPage.isOnStepSite(webView.url, step: page) }

    private func check(manual: Bool) async {
        guard !finished, manual || !checking else { return }
        checking = true
        defer { checking = false }
        let cookies = await webView.configuration.websiteDataStore.httpCookieStore.allCookies()
            .map { BrowserCookie(name: $0.name, domain: $0.domain, value: $0.value) }
        await readLocalStorage()
        guard !finished else { return }
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
    /// on the step's own site only. This run replaces any earlier one, whose answer then no longer counts. After
    /// 15 seconds the run stops holding its place, but its answer still counts if no run has replaced it.
    private func runExtract() {
        guard !finished, let js = params.extractJS, !js.isEmpty, onStepSite,
              !(lastCollected?.isComplete ?? false) else { return }
        extractRuns += 1
        let run = extractRuns
        extractRun = run
        DispatchQueue.main.asyncAfter(deadline: .now() + Self.extractTimeout) { [weak self] in
            if self?.extractRun == run { self?.extractRun = nil }
        }
        Task {
            let values = await evaluate(CookieCollector.extractScript(js), arguments: [:], in: .page, timeout: nil)
            if extractRun == run { extractRun = nil }
            // Replaced by a later run (a new page): not this page's answer.
            guard !finished, run == extractRuns, let values, !values.isEmpty else { return }
            extracted.merge(values) { _, new in new }
            await check(manual: false)
        }
    }

    /// Reads the step's local storage keys, on the step's own site only, in a world of Courier's own so the
    /// page can't see or change it.
    private func readLocalStorage() async {
        let keys = CookieCollector.localStorageKeys(params)
        guard !keys.isEmpty, onStepSite else { return }
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

    /// The string values of the object a function body returns, or nil if it failed or ran past `timeout` (nil:
    /// no limit; the answer comes, or WebKit fails the call when the page goes away).
    private func evaluate(_ body: String, arguments: [String: Any], in world: WKContentWorld,
                          timeout: TimeInterval?) async -> [String: String]? {
        await withCheckedContinuation { (continuation: CheckedContinuation<[String: String]?, Never>) in
            let answered = Flag()
            webView.callAsyncJavaScript(body, arguments: arguments, in: nil, in: world) { result in
                guard answered.set() else { return }
                switch result {
                case let .success(value): continuation.resume(returning: CookieCollector.extractedValues(from: value))
                case .failure: continuation.resume(returning: nil)
                }
            }
            if let timeout {
                DispatchQueue.main.asyncAfter(deadline: .now() + timeout) {
                    guard answered.set() else { return }
                    continuation.resume(returning: nil)
                }
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
        // No target frame is a new window, which loads in this view: the page itself.
        let mainFrame = action.targetFrame?.isMainFrame ?? true
        decisionHandler(SignInPage.allows(action.request.url, mainFrame: mainFrame) ? .allow : .cancel)
    }

    func webView(_ webView: WKWebView, didCommit navigation: WKNavigation!) {
        state.bar.shown(webView.url)
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        state.bar.shown(webView.url)
        runExtract()
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
struct SignInWindowContent: View {
    @ObservedObject var state: SignInWindowState
    let webView: WKWebView
    let networkName: String
    let signedIn: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 10) {
                Image(systemName: state.address.isSecure ? "lock.fill" : "exclamationmark.triangle.fill")
                    .foregroundStyle(state.address.isSecure ? Color.secondary : Color.orange)
                    .accessibilityHidden(true)
                Text(state.address.text)
                    .font(.callout.monospaced())
                    .foregroundStyle(state.address.isSecure ? Color.secondary : Color.orange)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .accessibilityLabel(String(localized: "Page address: \(state.address.text)"))
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
