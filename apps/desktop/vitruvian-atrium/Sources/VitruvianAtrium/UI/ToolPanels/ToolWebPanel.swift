// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 VitruvianSoftware

import AppKit
import SwiftUI
import VitruvianCore
import VitruvianDesign
import VitruvianServices
import VitruvianToolProtocol
import WebKit

/// What a web panel's page may do, as plain functions: where it may go, the
/// script that gives it `window.vitruvian`, and how its calls and their
/// answers cross between JavaScript and the protocol's values.
package enum ToolWebBridge {
    /// The name the page's calls are posted under.
    package static let handlerName = "vitruvian"

    /// What the web view does with a navigation.
    package enum Decision: Equatable, Sendable {
        case allow
        /// Not let: it would leave the tool's folder.
        case refuse
    }

    /// Whether a page may go to `url`: a file of the tool's folder, or the
    /// empty page. The main frame and every frame inside it alike.
    package static func decide(_ url: URL?, folder: URL) -> Decision {
        guard let url, ToolWebPolicy.allows(url, in: folder) else { return .refuse }
        return .allow
    }

    /// The script run before the page's own: `window.vitruvian`, with
    /// `call`, `on`, `language` and `appearance`, frozen so a page cannot
    /// replace it. A call is answered by a promise.
    package static func script(language: String, appearance: String) -> String {
        let settings = (try? JSONSerialization.data(withJSONObject: ["language": language, "appearance": appearance]))
            .map { String(decoding: $0, as: UTF8.self) } ?? "{}"
        return """
            (function () {
              if (window.vitruvian) { return; }
              var settings = \(settings);
              var handlers = {};
              var bridge = {
                language: settings.language,
                appearance: settings.appearance,
                call: function (method, params) {
                  return window.webkit.messageHandlers.\(handlerName).postMessage(
                    { method: String(method), params: params === undefined ? null : params });
                },
                on: function (name, handler) {
                  if (typeof handler !== "function") { return; }
                  (handlers[name] = handlers[name] || []).push(handler);
                }
              };
              Object.defineProperty(bridge, "_emit", { value: function (name, params) {
                (handlers[name] || []).forEach(function (handler) { try { handler(params); } catch (e) {} });
              } });
              Object.freeze(bridge);
              Object.defineProperty(window, "vitruvian", { value: bridge, writable: false, configurable: false });
            })();
            """
    }

    /// The method and params of a call the page posted; nil for anything
    /// that is not one.
    package static func call(from body: Any) -> (method: String, params: JSONValue?)? {
        guard let fields = body as? [String: Any], let method = fields["method"] as? String,
              JSONSerialization.isValidJSONObject(fields),
              let data = try? JSONSerialization.data(withJSONObject: fields),
              let value = try? JSONDecoder().decode(JSONValue.self, from: data) else { return nil }
        let params = value["params"]
        return (method, params == .null ? nil : params)
    }

    /// An answer as JavaScript gets it: the reply as a JavaScript value, or
    /// the failure's code and words as the promise's error.
    package static func answer(_ answer: Result<JSONValue, RPCErrorObject>) -> (value: Any?, error: String?) {
        switch answer {
        case .success(let value):
            guard let data = try? JSONEncoder().encode(value),
                  let object = try? JSONSerialization.jsonObject(with: data, options: [.fragmentsAllowed]) else {
                return (nil, "\(RPCErrorCode.internalError) the answer could not be read")
            }
            return (object is NSNull ? nil : object, nil)
        case .failure(let error):
            return (nil, "\(error.code) \(error.message)")
        }
    }

    /// One of the app's notices for the page's `on` handlers, as the line of
    /// JavaScript that delivers it.
    package static func emitting(_ name: String, _ params: JSONValue) -> String? {
        guard let name = try? JSONEncoder().encode(JSONValue.string(name)),
              let params = try? JSONEncoder().encode(params) else { return nil }
        return "window.vitruvian._emit(\(String(decoding: name, as: UTF8.self)), \(String(decoding: params, as: UTF8.self)));"
    }

    /// The appearance the page is told: the app's, as it is drawn now.
    @MainActor package static var appearance: String {
        NSApp.effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua ? "dark" : "light"
    }
}

/// A web panel's page: a web view that loads only files of the tool's
/// folder and reaches the app only through `window.vitruvian.call`, which
/// the panel host passes to the tool's program. The host keeps it, and lets
/// go of it when the panel closes or its tool ends.
@MainActor
package final class ToolWebPageView: NSObject, ToolWebPage, WKNavigationDelegate, WKUIDelegate {
    package let webView: WKWebView
    private let key: ToolPanelHost.Key
    private let folder: URL
    private let host: ToolPanelHost

    /// Holds the page's calls without holding the page: the web view's
    /// controller keeps whatever it is given.
    private final class Calls: NSObject, WKScriptMessageHandlerWithReply {
        weak var page: ToolWebPageView?

        func userContentController(_ controller: WKUserContentController, didReceive message: WKScriptMessage,
                                   replyHandler: @escaping @MainActor @Sendable (Any?, String?) -> Void) {
            MainActor.assumeIsolated {
                guard let page, let call = ToolWebBridge.call(from: message.body) else {
                    return replyHandler(nil, "\(RPCErrorCode.invalidRequest) not a call")
                }
                page.host.call(page.key, method: call.method, params: call.params) { answer in
                    let (value, error) = ToolWebBridge.answer(answer)
                    replyHandler(value, error)
                }
            }
        }
    }

    package init(key: ToolPanelHost.Key, page: URL, folder: URL, host: ToolPanelHost, language: String) {
        self.key = key
        self.folder = folder
        self.host = host
        let configuration = WKWebViewConfiguration()
        let calls = Calls()
        configuration.userContentController.addScriptMessageHandler(calls, contentWorld: .page,
                                                                    name: ToolWebBridge.handlerName)
        configuration.userContentController.addUserScript(WKUserScript(
            source: ToolWebBridge.script(language: language, appearance: ToolWebBridge.appearance),
            injectionTime: .atDocumentStart, forMainFrameOnly: false, in: .page))
        webView = WKWebView(frame: .zero, configuration: configuration)
        super.init()
        calls.page = self
        webView.navigationDelegate = self
        webView.uiDelegate = self
        webView.loadFileURL(page, allowingReadAccessTo: folder)
    }

    // MARK: ToolWebPage

    package func emit(_ name: String, _ params: JSONValue) {
        guard let line = ToolWebBridge.emitting(name, params) else { return }
        webView.evaluateJavaScript(line, completionHandler: nil)
    }

    package func close() {
        webView.stopLoading()
        webView.navigationDelegate = nil
        webView.uiDelegate = nil
        webView.configuration.userContentController.removeAllScriptMessageHandlers()
        webView.removeFromSuperview()
    }

    // MARK: WKNavigationDelegate

    package func webView(_ webView: WKWebView, decidePolicyFor action: WKNavigationAction,
                         decisionHandler: @escaping @MainActor @Sendable (WKNavigationActionPolicy) -> Void) {
        switch ToolWebBridge.decide(action.request.url, folder: folder) {
        case .allow:
            decisionHandler(.allow)
        case .refuse:
            host.refused(key, action.request.url)
            decisionHandler(.cancel)
        }
    }

    package func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!,
                         withError error: any Error) {
        host.notShown(key, why: error.localizedDescription)
    }

    package func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: any Error) {
        host.notShown(key, why: error.localizedDescription)
    }

    package func webViewWebContentProcessDidTerminate(_ webView: WKWebView) {
        host.notShown(key, why: "its web content stopped")
    }

    // MARK: WKUIDelegate

    /// `window.open` and a link to a new window: never.
    package func webView(_ webView: WKWebView, createWebViewWith configuration: WKWebViewConfiguration,
                         for action: WKNavigationAction, windowFeatures: WKWindowFeatures) -> WKWebView? {
        host.refused(key, action.request.url)
        return nil
    }
}

/// A web panel, drawn: the page the host keeps for it, made the first time.
package struct ToolWebPanelView: NSViewRepresentable {
    package let key: ToolPanelHost.Key
    package let page: URL
    package let folder: URL

    package init(key: ToolPanelHost.Key, page: URL, folder: URL) {
        self.key = key
        self.page = page
        self.folder = folder
    }

    package func makeNSView(context: Context) -> NSView {
        let host = ToolPanelHost.shared
        let view = (host.page(for: key) as? ToolWebPageView)
            ?? ToolWebPageView(key: key, page: page, folder: folder, host: host,
                               language: L10n.shared.language.rawValue)
        host.keep(view, for: key)
        let container = NSView()
        view.webView.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(view.webView)
        NSLayoutConstraint.activate([
            view.webView.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            view.webView.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            view.webView.topAnchor.constraint(equalTo: container.topAnchor),
            view.webView.bottomAnchor.constraint(equalTo: container.bottomAnchor),
        ])
        return container
    }

    package func updateNSView(_ view: NSView, context: Context) {}
}
