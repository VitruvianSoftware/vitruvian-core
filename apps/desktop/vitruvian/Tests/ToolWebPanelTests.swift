// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 VitruvianSoftware

import Foundation
import VitruvianCore
import VitruvianServices
import VitruvianToolProtocol
import VitruvianUI

/// A web panel and a tool's window, checked where no web view and no window
/// is needed: where a page may go, the script that gives it
/// `window.vitruvian`, how its calls and answers cross, and how a window is
/// titled and sized. What WebKit itself does is checked by hand.
enum ToolWebPanelTests {
    static func run(_ suite: TestSuite) {
        navigation(suite)
        theScript(suite)
        callsAndAnswers(suite)
        windows(suite)
    }

    static func navigation(_ suite: TestSuite) {
        ToolPanelTests.folder { root in
            let tool = root.appendingPathComponent("tool", isDirectory: true)
            try? FileManager.default.createDirectory(at: tool.appendingPathComponent("ui"), withIntermediateDirectories: true)
            FileManager.default.createFile(atPath: tool.appendingPathComponent("ui/page.html").path, contents: Data())
            suite.expect(ToolWebBridge.decide(tool.appendingPathComponent("ui/page.html"), folder: tool) == .allow
                             && ToolWebBridge.decide(URL(string: "about:blank"), folder: tool) == .allow,
                         "a page may go to a file of its tool's folder")
            let away: [URL?] = [root.appendingPathComponent("elsewhere.html"), URL(string: "https://example.com/"),
                                URL(string: "file:///etc/hosts"), nil]
            suite.expect(away.allSatisfy { ToolWebBridge.decide($0, folder: tool) == .refuse },
                         "a page may go nowhere outside its folder: not another file, not the network, not a new window")
        }
        let bench = ToolPanelHostTests.Bench()
        bench.host.open(ToolPanelHostTests.key("dashboard"), in: .window)
        bench.host.refused(ToolPanelHostTests.key("dashboard"), URL(string: "https://example.com/"))
        suite.expect(bench.logged.last == "the page of the panel dashboard tried to go to https://example.com/, "
                         + "outside the tool's folder, and was not let"
                         && bench.host.shown[ToolPanelHostTests.key("dashboard")] != .notShown,
                     "a page that tries to leave is not let, stays shown, and the tool's log says where it tried to go")
    }

    static func theScript(_ suite: TestSuite) {
        let script = ToolWebBridge.script(language: "fr", appearance: "dark")
        suite.expect(script.contains(#"{"appearance":"dark","language":"fr"}"#) || script.contains(#"{"language":"fr","appearance":"dark"}"#),
                     "the page is told the app's language and appearance before its own scripts run")
        suite.expect(script.contains("Object.freeze(bridge)") && script.contains("writable: false, configurable: false")
                         && script.contains("window.webkit.messageHandlers.vitruvian.postMessage"),
                     "window.vitruvian cannot be replaced, and its calls go to the app's one handler")
        let hostile = ToolWebBridge.script(language: #"fr", "x": "</script><script>alert(1)"#, appearance: "light")
        suite.expect(!hostile.contains(#"fr", "x""#) && hostile.contains(#"fr\", \"x\""#),
                     "what the page is told is written as JSON, so no value can end the script early")
        suite.expect(ToolWebBridge.emitting("language/changed", .object(["language": .string("de")]))
                         == #"window.vitruvian._emit("language\/changed", {"language":"de"});"#,
                     "a notice is delivered to the page's handlers as the params its tool is sent")
    }

    static func callsAndAnswers(_ suite: TestSuite) {
        let body: [String: Any] = ["method": "notify/hud", "params": ["icon": "checkmark", "message": "Saved"]]
        let read = ToolWebBridge.call(from: body)
        suite.expect(read?.method == "notify/hud"
                         && read?.params == .object(["icon": .string("checkmark"), "message": .string("Saved")]),
                     "a call the page posts is its method and its params")
        suite.expect(ToolWebBridge.call(from: ["method": "tool/refresh", "params": NSNull()])?.params == nil
                         && ToolWebBridge.call(from: ["params": [:]]) == nil
                         && ToolWebBridge.call(from: "notify/hud") == nil && ToolWebBridge.call(from: ["method": 7]) == nil,
                     "params of null are none, and something that is not a call is not read")
        let done = ToolWebBridge.answer(.success(.object(["shown": .bool(true)])))
        suite.expect((done.value as? [String: Any])?["shown"] as? Bool == true && done.error == nil,
                     "a reply reaches the page as a JavaScript value")
        suite.expect(ToolWebBridge.answer(.success(.null)).value == nil,
                     "a reply of nothing is undefined to the page")
        let refused = ToolWebBridge.answer(.failure(RefusalCode.notInUses.error(service: .clipboardRead)))
        suite.expect(refused.value == nil && refused.error == "-32001 not listed in uses",
                     "a refusal rejects the page's promise with its code and its words")
    }

    static func windows(_ suite: TestSuite) {
        let bench = ExternalToolStoreTests.Bench()
        defer { bench.close() }
        let long = String(repeating: "Log ", count: 60)
        bench.add(bench.folder(manifest: ExternalToolManifestTests.file(#"""
            {"protocol": "2", "name": {"en": "Deploys", "fr": "Déploiements"}, "contributes": {"panels": [
              {"id": "deploys", "title": {"en": "Deploys"}, "placement": "island"},
              {"id": "log", "title": {"en": "\#(long)"}, "placement": "window"},
              {"id": "dashboard", "title": {"en": "Dashboard", "fr": "Tableau"}, "placement": "window", "kind": "web", "entry": "ui/d.html"}]}}
            """#)))
        let key = { ToolPanelHost.Key(tool: ExternalToolTests.id, panel: $0) }
        let web = ToolPanelWindowLook(key: key("dashboard"), store: bench.store, language: .fr)
        suite.expect(web?.title == "Tableau" && web?.subtitle == "Déploiements" && web?.isWeb == true,
                     "a window is titled with its panel's title and the tool's name, in the person's language")
        let blocks = ToolPanelWindowLook(key: key("log"), store: bench.store, language: .enUS)
        suite.expect(blocks?.isWeb == false && blocks?.title.count == ToolOwnWords.limit,
                     "a title of any length is one line of 120 characters at most")
        suite.expect(ToolPanelWindowLook(key: key("deploys"), store: bench.store, language: .enUS) == nil
                         && ToolPanelWindowLook(key: key("nothing"), store: bench.store, language: .enUS) == nil,
                     "only a window panel the tool declares is a window")
        suite.expect(ToolPanelWindowLook.blocksWidth == 380 && ToolPanelWindowLook.blocksHeight == 120...560
                         && ToolPanelWindowLook.webSize == CGSize(width: 640, height: 480)
                         && ToolPanelWindowLook.webSmallest == CGSize(width: 320, height: 240),
                     "a page of blocks is 380 points wide and 120 to 560 high; a web page starts at 640 by 480")
    }
}
