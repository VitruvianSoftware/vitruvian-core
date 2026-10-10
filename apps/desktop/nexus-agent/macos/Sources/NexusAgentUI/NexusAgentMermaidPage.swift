// Copyright (c) 2026 VitruvianSoftware
//
// Permission is hereby granted, free of charge, to any person obtaining a copy
// of this software and associated documentation files (the "Software"), to deal
// in the Software without restriction, including without limitation the rights
// to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
// copies of the Software, and to permit persons to whom the Software is
// furnished to do so, subject to the following conditions:
//
// The above copyright notice and this permission notice shall be included in
// all copies or substantial portions of the Software.
//
// THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
// IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
// FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
// AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
// LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
// OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
// SOFTWARE.

import Foundation
import WebKit

/// The page a diagram card draws in, and the copy of Mermaid it draws with.
///
/// Mermaid ships inside the app (`Resources/mermaid.min.js`, see
/// `THIRD_PARTY_NOTICES.md`), so a diagram needs no network and the app runs
/// no script it did not ship. The page itself holds no script at all: the app
/// hands the web view Mermaid and a few lines that start it, and the page's
/// policy refuses everything else. A diagram's source comes from an agent's
/// reply, so nothing in it is trusted to run or to load.
public enum NexusAgentMermaidPage {

    // MARK: - Finding the script

    /// The file name of the bundled copy of Mermaid.
    public static let scriptFileName = "mermaid.min.js"

    /// The folder SwiftPM puts this library's resources in, beside the
    /// executable it builds. `scripts/bundle.sh` copies it into the app's
    /// `Contents/Resources`.
    public static let swiftPMResourceBundleName = "NexusAgent_NexusAgentUI.bundle"

    /// Where the script can be, for an app or executable whose main bundle
    /// is `bundle`, most likely first.
    ///
    /// The two builds put it in different places, and nothing the compiler
    /// defines tells them apart reliably (`Bundle.module` exists only under
    /// SwiftPM, and stops the app when its folder is not where it expects),
    /// so every place is tried:
    /// - Bazel copies a library's resources straight into the app's
    ///   `Contents/Resources`;
    /// - SwiftPM writes them into a folder of its own, which the release
    ///   script copies into `Contents/Resources`, and which sits beside the
    ///   executable when the package is run without being packaged.
    public static func scriptDirectories(for bundle: Bundle) -> [URL] {
        var roots: [URL] = []
        if let resources = bundle.resourceURL { roots.append(resources) }
        if let executable = bundle.executableURL { roots.append(executable.deletingLastPathComponent()) }
        var directories: [URL] = []
        for root in roots {
            let swiftPM = root.appendingPathComponent(swiftPMResourceBundleName, isDirectory: true)
            directories.append(root)
            directories.append(swiftPM)
            directories.append(swiftPM.appendingPathComponent("Contents/Resources", isDirectory: true))
        }
        return directories
    }

    /// The script's file in the first of `directories` that has it.
    public static func scriptURL(in directories: [URL]) -> URL? {
        directories
            .map { $0.appendingPathComponent(scriptFileName, isDirectory: false) }
            .first { FileManager.default.isReadableFile(atPath: $0.path) }
    }

    /// The script's text, or nil when it is in none of `directories`, cannot
    /// be read, or is empty. Nil is not an error to report here: the page is
    /// still loaded, finds no Mermaid, and says so the way a diagram that
    /// cannot be drawn does.
    public static func script(in directories: [URL]) -> String? {
        guard let url = scriptURL(in: directories),
              let text = try? String(contentsOf: url, encoding: .utf8),
              !text.isEmpty else { return nil }
        return text
    }

    /// The copy this app shipped, read once: it is a few megabytes, and every
    /// diagram card uses the same one.
    public static let bundledScript: String? = script(in: scriptDirectories(for: .main))

    // MARK: - The page

    /// What the page may load: nothing, from anywhere. Its own style sheet
    /// and the styles Mermaid writes into a drawing are inline, which is the
    /// one thing allowed. No script source is allowed, so nothing in the
    /// page, and nothing a diagram's source turns into, can run; the two
    /// scripts that do run are put there by the app (`makeWebView`), which
    /// this policy does not govern.
    public static let contentSecurityPolicy = "default-src 'none'; style-src 'unsafe-inline'"

    /// The page for one diagram. `errorScheme` is the URL scheme the page
    /// goes to when the diagram cannot be drawn.
    public static func html(source: String, isDark: Bool, errorScheme: String) -> String {
        let theme = isDark ? "dark" : "default"
        return """
        <!DOCTYPE html>
        <html>
        <head>
        <meta charset="utf-8">
        <meta http-equiv="Content-Security-Policy" content="\(contentSecurityPolicy)">
        <meta name="viewport" content="width=device-width, initial-scale=1">
        <style>
          * { box-sizing: border-box; }
          body {
            margin: 0;
            padding: 16px;
            background: transparent;
            display: flex;
            justify-content: center;
            align-items: center;
            min-height: 100vh;
            font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", Roboto, sans-serif;
            overflow: auto;
          }
          .mermaid {
            width: 100%;
            display: flex;
            justify-content: center;
          }
          svg {
            max-width: 100%;
            height: auto;
          }
        </style>
        </head>
        <body data-theme="\(theme)" data-error-url="\(escaped(errorScheme))://error">
        <div class="mermaid">
        \(escaped(source))
        </div>
        </body>
        </html>
        """
    }

    /// `text` as it must be written to stand for itself in the page, in an
    /// element or in a quoted attribute, and never as markup.
    static func escaped(_ text: String) -> String {
        text
            .replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
            .replacingOccurrences(of: "\"", with: "&quot;")
    }

    /// The lines that draw the diagram once the page is read. They take the
    /// theme and where to go on failure from the page, so they are the same
    /// for every diagram. A missing Mermaid, a setting it refuses and a
    /// diagram it cannot read all end the same way: the page goes to its
    /// error address, which the web view's delegate turns into the card's
    /// "could not draw" state.
    ///
    /// `securityLevel: 'strict'` is Mermaid's own guard over the source:
    /// markup in a label is shown as text and a node cannot carry a click
    /// action or a link.
    static let startScript = """
    (function () {
      var fail = function () { window.location.href = document.body.dataset.errorUrl; };
      try {
        if (typeof mermaid === 'undefined') { fail(); return; }
        mermaid.initialize({
          startOnLoad: false,
          theme: document.body.dataset.theme,
          securityLevel: 'strict'
        });
        mermaid.run({ querySelector: '.mermaid' }).catch(fail);
      } catch (e) {
        fail();
      }
    })();
    """

    /// A web view that draws `html(source:isDark:errorScheme:)` with
    /// `script`, the text of Mermaid. With `script` nil the page finds no
    /// Mermaid and goes to its error address.
    @MainActor
    public static func makeWebView(script: String?) -> WKWebView {
        let configuration = WKWebViewConfiguration()
        // The page keeps nothing, so it is given nowhere on disk to keep it.
        configuration.websiteDataStore = .nonPersistent()
        let scripts = configuration.userContentController
        if let script {
            scripts.addUserScript(WKUserScript(source: script, injectionTime: .atDocumentStart, forMainFrameOnly: true))
        }
        scripts.addUserScript(WKUserScript(source: startScript, injectionTime: .atDocumentEnd, forMainFrameOnly: true))
        let webView = WKWebView(frame: .zero, configuration: configuration)
        webView.setValue(false, forKey: "drawsBackground")
        return webView
    }

    /// Loads one diagram into a web view `makeWebView` built.
    @MainActor
    public static func load(source: String, isDark: Bool, errorScheme: String, in webView: WKWebView) {
        webView.loadHTMLString(html(source: source, isDark: isDark, errorScheme: errorScheme), baseURL: nil)
    }

    // MARK: - Where the page may go

    /// What to do with a place the page asks to go.
    public enum Navigation: Equatable, Sendable {
        /// The page itself, which is loaded from text and so has a blank address.
        case allow
        /// The page's way of saying the diagram could not be drawn.
        case renderError
        /// Anywhere else. The page needs nothing from outside, so nothing
        /// in a diagram may send the card to a website or a file.
        case refuse
    }

    public static func navigation(to url: URL?, errorScheme: String) -> Navigation {
        guard let scheme = url?.scheme?.lowercased() else { return .refuse }
        if scheme == errorScheme.lowercased() { return .renderError }
        return scheme == "about" ? .allow : .refuse
    }
}

/// Listens to a diagram's web view: tells the card when the diagram could not
/// be drawn, and keeps the page where it is.
@MainActor
public final class NexusAgentMermaidNavigationDelegate: NSObject, WKNavigationDelegate {
    public var errorScheme: String
    public var onRenderError: @MainActor () -> Void

    public init(errorScheme: String, onRenderError: @escaping @MainActor () -> Void) {
        self.errorScheme = errorScheme
        self.onRenderError = onRenderError
    }

    public func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        onRenderError()
    }

    public func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
        onRenderError()
    }

    // The async form on purpose. The completion-handler form only counts
    // as WebKit's method when its closure is annotated exactly as the SDK
    // in use annotates it, and that differs between SDKs; written
    // slightly off, it compiles with a warning and is never called.
    public func webView(_ webView: WKWebView,
                        decidePolicyFor navigationAction: WKNavigationAction) async -> WKNavigationActionPolicy {
        switch NexusAgentMermaidPage.navigation(to: navigationAction.request.url, errorScheme: errorScheme) {
        case .allow:
            return .allow
        case .renderError:
            onRenderError()
            return .cancel
        case .refuse:
            return .cancel
        }
    }
}
