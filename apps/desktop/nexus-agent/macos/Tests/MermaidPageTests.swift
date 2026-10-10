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

import CryptoKit
import WebKit
import XCTest

import NexusAgentUI

/// The diagram card's page: that the app finds the copy of Mermaid it ships
/// wherever each build puts it, that the page draws with it and reaches for
/// nothing outside the app, and that every way of failing ends in the card's
/// "could not draw" state.
final class MermaidPageTests: XCTestCase {

    // MARK: - The shipped copy

    /// The folder the shipped script is in on this machine: the target's
    /// runfiles under Bazel, or beside the sources under SwiftPM and Xcode.
    private func shippedDirectory() -> URL? {
        let relative = "apps/desktop/nexus-agent/macos/Sources/NexusAgentUI/Resources"
        var candidates: [String] = []
        let environment = ProcessInfo.processInfo.environment
        if let runfiles = environment["TEST_SRCDIR"] {
            for workspace in [environment["TEST_WORKSPACE"], "_main"].compactMap({ $0 }) {
                candidates.append("\(runfiles)/\(workspace)/\(relative)")
            }
        }
        let here = (#filePath as NSString).deletingLastPathComponent
        candidates.append((here as NSString).deletingLastPathComponent + "/Sources/NexusAgentUI/Resources")
        return candidates.first { FileManager.default.fileExists(atPath: $0) }.map { URL(fileURLWithPath: $0) }
    }

    private func shippedScript() throws -> String {
        let directory = try XCTUnwrap(shippedDirectory(), "the folder of shipped resources is found")
        return try XCTUnwrap(NexusAgentMermaidPage.script(in: [directory]), "the shipped copy of Mermaid is read")
    }

    /// The file is `dist/mermaid.min.js` from the npm package of the version
    /// THIRD_PARTY_NOTICES.md names, byte for byte. A newer copy changes this
    /// line and that file together.
    func testTheShippedCopyIsTheOneTheNoticeNames() throws {
        let directory = try XCTUnwrap(shippedDirectory())
        let url = try XCTUnwrap(NexusAgentMermaidPage.scriptURL(in: [directory]))
        let digest = SHA256.hash(data: try Data(contentsOf: url)).map { String(format: "%02x", $0) }.joined()
        XCTAssertEqual(digest, "581ed7d74bd9048d0e3a91363927d72ef22942d7722546b27f7cc29e35390eb8")
    }

    // MARK: - Finding it in each kind of app

    private var scratch: URL!

    override func setUpWithError() throws {
        scratch = FileManager.default.temporaryDirectory
            .appendingPathComponent("MermaidPageTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: scratch, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: scratch)
    }

    /// An app folder with `files` (paths below `Contents`) in it.
    private func app(_ files: [String: String]) throws -> Bundle {
        let root = scratch.appendingPathComponent("\(UUID().uuidString)/Sample.app", isDirectory: true)
        var all = files
        all["Info.plist"] = """
        <?xml version="1.0" encoding="UTF-8"?>
        <plist version="1.0"><dict>
        <key>CFBundleExecutable</key><string>Sample</string>
        <key>CFBundleIdentifier</key><string>test.mermaid.sample</string>
        <key>CFBundlePackageType</key><string>APPL</string>
        </dict></plist>
        """
        all["MacOS/Sample"] = "#!/bin/sh\n"
        for (path, text) in all {
            let url = root.appendingPathComponent("Contents/" + path)
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try text.write(to: url, atomically: true, encoding: .utf8)
        }
        return try XCTUnwrap(Bundle(url: root))
    }

    private func found(in bundle: Bundle) -> String? {
        NexusAgentMermaidPage.script(in: NexusAgentMermaidPage.scriptDirectories(for: bundle))
    }

    func testFoundWhereBazelPutsIt() throws {
        XCTAssertEqual(found(in: try app(["Resources/mermaid.min.js": "bazel"])), "bazel")
    }

    func testFoundWhereTheReleaseScriptPutsIt() throws {
        let bundle = try app(["Resources/NexusAgent_NexusAgentUI.bundle/mermaid.min.js": "swiftpm"])
        XCTAssertEqual(found(in: bundle), "swiftpm")
    }

    /// SwiftPM's newer build engine gives the folder a bundle's own layout.
    func testFoundInAResourceBundleWithContents() throws {
        let bundle = try app(["Resources/NexusAgent_NexusAgentUI.bundle/Contents/Resources/mermaid.min.js": "nested"])
        XCTAssertEqual(found(in: bundle), "nested")
    }

    /// `swift run`: no app, the resource folder sits beside the executable.
    func testFoundBesideAnExecutableThatIsNotPackaged() throws {
        let directory = scratch.appendingPathComponent("debug", isDirectory: true)
        let resources = directory.appendingPathComponent(NexusAgentMermaidPage.swiftPMResourceBundleName)
        try FileManager.default.createDirectory(at: resources, withIntermediateDirectories: true)
        try "beside".write(to: resources.appendingPathComponent("mermaid.min.js"), atomically: true, encoding: .utf8)
        XCTAssertEqual(found(in: try XCTUnwrap(Bundle(url: directory))), "beside")
    }

    func testAnAppWithoutTheScriptFindsNone() throws {
        let bundle = try app(["Resources/AppIcon.icns": "icon"])
        XCTAssertFalse(NexusAgentMermaidPage.scriptDirectories(for: bundle).isEmpty, "there were places to look")
        XCTAssertNil(NexusAgentMermaidPage.scriptURL(in: NexusAgentMermaidPage.scriptDirectories(for: bundle)))
        XCTAssertNil(found(in: bundle))
        XCTAssertNil(NexusAgentMermaidPage.script(in: []))
    }

    func testAnEmptyOrUnreadableScriptCountsAsMissing() throws {
        XCTAssertNil(found(in: try app(["Resources/mermaid.min.js": ""])), "an empty file draws nothing")

        let locked = try app(["Resources/mermaid.min.js": "locked"])
        let file = try XCTUnwrap(locked.resourceURL).appendingPathComponent("mermaid.min.js")
        try FileManager.default.setAttributes([.posixPermissions: 0o000], ofItemAtPath: file.path)
        defer { try? FileManager.default.setAttributes([.posixPermissions: 0o644], ofItemAtPath: file.path) }
        // Root reads any file, so the mode says nothing there.
        try XCTSkipIf(getuid() == 0, "running as root")
        XCTAssertNil(found(in: locked))
    }

    /// The app `scripts/bundle.sh` assembled from a real SwiftPM build.
    /// `mirror_build_test` names it; without that this has nothing to look at.
    func testFoundInTheAppTheReleaseScriptAssembled() throws {
        guard let path = ProcessInfo.processInfo.environment["NEXUS_AGENT_PACKAGED_APP"], !path.isEmpty else {
            throw XCTSkip("NEXUS_AGENT_PACKAGED_APP is not set: no packaged app to check")
        }
        let bundle = try XCTUnwrap(Bundle(url: URL(fileURLWithPath: path)), "\(path) is an app")
        let url = try XCTUnwrap(NexusAgentMermaidPage.scriptURL(in: NexusAgentMermaidPage.scriptDirectories(for: bundle)),
                                "the packaged app has the script where the lookup tries")
        print("packaged app: found \(url.path)")
        XCTAssertEqual(found(in: bundle), try shippedScript(), "and it is the shipped copy")
    }

    // MARK: - The page

    func testThePageNamesNothingOutsideItself() {
        for isDark in [false, true] {
            let html = NexusAgentMermaidPage.html(source: "graph TD\nA --> B", isDark: isDark, errorScheme: "sample-error")
            XCTAssertFalse(html.contains("http://"), "no address to load from")
            XCTAssertFalse(html.contains("https://"), "no address to load from")
            XCTAssertFalse(html.lowercased().contains("<script"), "the page carries no script of its own")
            XCTAssertFalse(html.lowercased().contains("<link"), "and no style sheet from elsewhere")
            XCTAssertTrue(html.contains("""
            <meta http-equiv="Content-Security-Policy" content="default-src 'none'; style-src 'unsafe-inline'">
            """))
            XCTAssertTrue(html.contains("data-theme=\"\(isDark ? "dark" : "default")\""))
            XCTAssertTrue(html.contains("data-error-url=\"sample-error://error\""))
        }
        XCTAssertFalse(NexusAgentMermaidPage.contentSecurityPolicy.contains("script-src"),
                       "the policy lets no script source in, so the default refuses them all")
    }

    func testADiagramsSourceIsNeverMarkup() {
        let hostile = "graph TD\nA[\"</div><script>alert(1)</script><img src=x onerror=alert(2)>\"] --> B & C"
        let html = NexusAgentMermaidPage.html(source: hostile, isDark: false, errorScheme: "x\"><script>")
        XCTAssertFalse(html.contains("<script"))
        XCTAssertFalse(html.contains("<img"))
        XCTAssertTrue(html.contains("&lt;/div&gt;&lt;script&gt;alert(1)&lt;/script&gt;&lt;img src=x onerror=alert(2)&gt;"))
        XCTAssertTrue(html.contains("B &amp; C"))
        XCTAssertTrue(html.contains("data-error-url=\"x&quot;&gt;&lt;script&gt;://error\""))
    }

    func testThePageGoesNowhereButItsErrorAddress() {
        func decision(_ address: String, scheme: String = "sample-error") -> NexusAgentMermaidPage.Navigation {
            NexusAgentMermaidPage.navigation(to: URL(string: address), errorScheme: scheme)
        }
        XCTAssertEqual(decision("about:blank"), .allow)
        XCTAssertEqual(decision("sample-error://error"), .renderError)
        XCTAssertEqual(decision("SAMPLE-ERROR://error"), .renderError)
        XCTAssertEqual(decision("sample-error://error", scheme: "Sample-Error"), .renderError)
        for elsewhere in ["https://example.com/", "http://example.com/", "file:///etc/hosts", "ftp://example.com/",
                          "other-error://error", "javascript:alert(1)", "data:text/html,hello"] {
            XCTAssertEqual(decision(elsewhere), .refuse, elsewhere)
        }
        XCTAssertEqual(NexusAgentMermaidPage.navigation(to: nil, errorScheme: "sample-error"), .refuse)
    }

    // MARK: - Drawing, in a web view that is never put on screen

    private static let flowchart = "graph TD\nA[Start] --> B{Choice}\nB -->|yes| C[Done]\nB -->|no| A"

    /// One page in a web view no window holds, and what became of it.
    @MainActor
    private final class Page {
        let webView: WKWebView
        let delegate: NexusAgentMermaidNavigationDelegate
        private(set) var errors = 0

        init(script: String?, source: String, isDark: Bool) {
            webView = NexusAgentMermaidPage.makeWebView(script: script)
            webView.frame = NSRect(x: 0, y: 0, width: 640, height: 420)
            delegate = NexusAgentMermaidNavigationDelegate(errorScheme: "sample-error", onRenderError: {})
            webView.navigationDelegate = delegate
            delegate.onRenderError = { [weak self] in self?.errors += 1 }
            NexusAgentMermaidPage.load(source: source, isDark: isDark, errorScheme: "sample-error", in: webView)
        }

        /// Runs the main run loop until `done` or the time is up.
        @discardableResult
        func wait(seconds: TimeInterval = 60, until done: () -> Bool) -> Bool {
            let deadline = Date().addingTimeInterval(seconds)
            while !done() && Date() < deadline {
                RunLoop.main.run(mode: .default, before: Date().addingTimeInterval(0.02))
            }
            return done()
        }

        func evaluate(_ script: String) -> String? {
            var finished = false
            var text: String?
            webView.evaluateJavaScript(script) { value, error in
                text = (value as? String) ?? error.map { "error: \($0.localizedDescription)" }
                finished = true
            }
            wait { finished }
            return text
        }

        /// What the page holds, as JSON: the drawing, and everything the
        /// page asked the network for (nothing, when it is self-contained).
        func facts() -> String? {
            evaluate("""
            (function () {
              var svg = document.querySelector('.mermaid svg');
              return JSON.stringify({
                address: location.href,
                mermaid: typeof mermaid,
                svg: !!svg,
                nodes: svg ? svg.querySelectorAll('g.node').length : 0,
                labels: svg ? Array.from(svg.querySelectorAll('g.node')).map(function (n) { return n.textContent.trim(); }) : [],
                links: svg ? svg.querySelectorAll('path.flowchart-link').length : 0,
                requests: performance.getEntriesByType('resource').map(function (e) { return e.name; })
              });
            })()
            """)
        }

        var hasDrawing: Bool { evaluate("String(!!document.querySelector('.mermaid svg g.node'))") == "true" }
    }

    private func json(_ text: String?) throws -> [String: Any] {
        let data = try XCTUnwrap(text?.data(using: .utf8))
        return try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any], text ?? "")
    }

    @MainActor
    func testAFlowchartIsDrawnInBothThemesAndNothingIsFetched() throws {
        let script = try shippedScript()
        for isDark in [false, true] {
            let page = Page(script: script, source: Self.flowchart, isDark: isDark)
            XCTAssertTrue(page.wait { page.errors > 0 || page.hasDrawing }, "the page finished one way or the other")
            let found = page.facts()
            print("mermaid probe (\(isDark ? "dark" : "light")): \(found ?? "nothing")")
            let facts = try json(found)
            XCTAssertEqual(page.errors, 0, "the diagram was drawn, not refused")
            XCTAssertEqual(facts["svg"] as? Bool, true)
            XCTAssertEqual(facts["nodes"] as? Int, 3, "Start, Choice and Done")
            XCTAssertEqual(Set(facts["labels"] as? [String] ?? []), ["Start", "Choice", "Done"])
            XCTAssertEqual(facts["links"] as? Int, 3)
            XCTAssertEqual(facts["requests"] as? [String], [], "the page asked the network for nothing")
            XCTAssertEqual(facts["address"] as? String, "about:blank")
            XCTAssertEqual(page.webView.url?.absoluteString, "about:blank")
        }
    }

    /// The page's policy is what keeps a diagram from reaching out, so it
    /// is shown refusing: an image, a request, a script and a style sheet
    /// from elsewhere are each stopped before they leave, and sending the
    /// page to a website leaves it where it was.
    @MainActor
    func testThePageRefusesEverythingFromOutside() throws {
        let page = Page(script: try shippedScript(), source: Self.flowchart, isDark: false)
        XCTAssertTrue(page.wait { page.errors > 0 || page.hasDrawing })
        _ = page.evaluate("""
        (function () {
          window.refused = [];
          document.addEventListener('securitypolicyviolation', function (e) {
            window.refused.push(e.effectiveDirective + ' ' + e.blockedURI);
          });
          var image = document.createElement('img');
          image.src = 'https://example.invalid/pixel.png';
          document.body.appendChild(image);
          var script = document.createElement('script');
          script.src = 'https://example.invalid/script.js';
          document.body.appendChild(script);
          var inline = document.createElement('script');
          inline.textContent = 'window.inlineRan = true;';
          document.body.appendChild(inline);
          var sheet = document.createElement('link');
          sheet.rel = 'stylesheet';
          sheet.href = 'https://example.invalid/style.css';
          document.body.appendChild(sheet);
          try { fetch('https://example.invalid/data').catch(function () {}); } catch (e) {}
          return 'asked';
        })()
        """)
        var refused: [String] = []
        page.wait(seconds: 20) {
            let text = page.evaluate("JSON.stringify(window.refused.slice().sort())") ?? "[]"
            refused = (try? JSONSerialization.jsonObject(with: Data(text.utf8)) as? [String]) ?? []
            return refused.count >= 5
        }
        print("mermaid probe (refused by the page's policy): \(refused)")
        XCTAssertEqual(refused.count, 5, "\(refused)")
        XCTAssertTrue(refused.contains { $0.hasPrefix("img-src https://example.invalid") }, "\(refused)")
        XCTAssertTrue(refused.contains { $0.hasPrefix("connect-src https://example.invalid") }, "\(refused)")
        XCTAssertTrue(refused.contains { $0.hasPrefix("style-src-elem https://example.invalid") }, "\(refused)")
        XCTAssertEqual(refused.filter { $0.hasPrefix("script-src-elem") }.count, 2, "\(refused)")
        XCTAssertEqual(page.evaluate("String(window.inlineRan === true)"), "false", "a script written into the page does not run")
        XCTAssertEqual(try json(page.facts())["requests"] as? [String], [], "none of them reached the network")

        _ = page.evaluate("window.location.href = 'https://example.invalid/away'; 'sent'")
        page.wait(seconds: 1) { false }
        XCTAssertEqual(page.webView.url?.absoluteString, "about:blank", "the page stayed where it was")
        XCTAssertTrue(page.hasDrawing, "with its drawing")
        XCTAssertEqual(page.errors, 0, "and a refused address is not a diagram that failed")
    }

    @MainActor
    func testADiagramThatCannotBeReadEndsInTheErrorState() throws {
        let page = Page(script: try shippedScript(), source: "graph TD\nA --> --> [[[ B", isDark: false)
        XCTAssertTrue(page.wait { page.errors > 0 || page.hasDrawing })
        print("mermaid probe (broken diagram): errors=\(page.errors) drawing=\(page.hasDrawing)")
        XCTAssertEqual(page.errors, 1)
        XCTAssertFalse(page.hasDrawing)
    }

    @MainActor
    func testAMissingScriptEndsInTheErrorState() throws {
        let missing = NexusAgentMermaidPage.script(in: [scratch.appendingPathComponent("nowhere")])
        XCTAssertNil(missing)
        let page = Page(script: missing, source: Self.flowchart, isDark: false)
        XCTAssertTrue(page.wait { page.errors > 0 || page.hasDrawing })
        print("mermaid probe (missing script): errors=\(page.errors) mermaid=\(page.evaluate("typeof mermaid") ?? "?")")
        XCTAssertEqual(page.errors, 1)
        XCTAssertFalse(page.hasDrawing)
    }
}
