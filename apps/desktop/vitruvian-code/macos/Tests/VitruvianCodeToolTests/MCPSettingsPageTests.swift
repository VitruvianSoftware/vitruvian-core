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
import VitruvianCodeCore
@testable import VitruvianCodeToolCore
import VitruvianToolKit
import VitruvianToolProtocol
import XCTest

/// The MCP part of the extension's settings panel, and its words.
@MainActor
final class MCPSettingsPageTests: XCTestCase {
    private let keys = ["mcpSection", "mcpCaption", "mcpNone", "mcpAdd", "mcpFromClaudeCode", "mcpOn", "mcpOff",
                        "mcpName", "mcpTransport", "mcpTransportStdio", "mcpTransportHTTP", "mcpCommand", "mcpArguments",
                        "mcpURL", "mcpSecretEnvironment", "mcpSecretHeader", "mcpSecretCaption", "mcpSecretsKept",
                        "mcpClearSecrets", "mcpEnabled", "mcpSaveServer", "mcpRemove", "mcpCancel", "mcpProblemName",
                        "mcpProblemDuplicate", "mcpProblemCommand", "mcpProblemURL", "mcpProblemSecret", "mcpSaveFailed",
                        "projectMCPTitle", "projectMCPExplanation", "projectMCPAllow", "projectMCPNotNow"]

    func testTheMCPWordsExistAndTranslateInAllFifteenLanguages() {
        for key in keys {
            XCTAssertTrue(Words.keys.contains(key), "\(key) missing from Words.keys")
            for language in Words.languages {
                let word = Words.text(key, language)
                XCTAssertFalse(word.isEmpty || word == key, "\(language).\(key) missing translation")
                if language != "en" {
                    XCTAssertNotEqual(word, Words.text(key, "en"), "\(language).\(key) is still English")
                }
            }
        }
    }

    private let server = AgentMCPServer(id: UUID(uuidString: "11111111-2222-3333-4444-555555555555")!, name: "docs",
                                        transport: .stdio, command: "npx", arguments: ["-y", "docs-mcp"],
                                        isEnabled: false, source: .claudeCode)

    func testTheSectionIsOnlyThereWhenTheToolHasAListAndShowsEachServer() {
        let configuration = VitruvianCodeConfiguration()
        let without = Pages.settings(Pages.Status(), draft: configuration, saved: configuration, logLines: [], language: "en")
        XCTAssertFalse(without.blocks.contains { $0.id?.hasPrefix("mcp") == true })

        let with = Pages.settings(Pages.Status(), draft: configuration, saved: configuration, logLines: [], language: "en",
                                  mcp: Pages.MCP(servers: [server]))
        XCTAssertEqual(with.blocks.compactMap(\.id).filter { $0.hasPrefix("mcp") }, ["mcpServers", "mcpAdd"])
        guard case .list(let list)? = with.blocks.first(where: { $0.id == "mcpServers" })?.content else { return XCTFail("no list") }
        XCTAssertEqual(list.rows.first?.title.text(for: "en"), "docs")
        XCTAssertEqual(list.rows.first?.subtitle?.text(for: "en"), "stdio · npx -y docs-mcp · from Claude Code")
        XCTAssertEqual(list.rows.first?.trailing?.text(for: "en"), "Off")
    }

    func testTheEditorNeverCarriesASecretAndShowsTheFieldsOfItsTransport() throws {
        var draft = AgentMCPServerDraft(server)
        draft.secrets = ["DOCS_TOKEN": "docs-secret-1"]
        let page = Pages.MCP(servers: [server], draft: draft, secretNames: ["DOCS_TOKEN"], problem: .missingCommand)
        let blocks = Pages.mcpBlocks(page, language: "en", supportsChoice: true, supportsSections: true)
        let ids = blocks.compactMap(\.id)
        XCTAssertEqual(ids, ["mcpServers", "mcpName", "mcpTransport", "mcpCommand", "mcpArguments", "mcpSecret",
                             "mcpClearSecrets", "mcpEnabled", "mcpSaveServer", "mcpRemove", "mcpCancel"])
        guard case .field(let secret)? = blocks.first(where: { $0.id == "mcpSecret" })?.content else { return XCTFail("no field") }
        XCTAssertEqual(secret.kind, .secret)
        XCTAssertEqual(secret.value, "")
        let text = String(decoding: try JSONEncoder().encode(UITree(blocks: blocks)), as: UTF8.self)
        XCTAssertFalse(text.contains("docs-secret-1"))
        XCTAssertTrue(text.contains("DOCS_TOKEN"))
        XCTAssertTrue(text.contains(Words.text("mcpProblemCommand", "en")))

        draft.transport = .http
        let http = Pages.mcpBlocks(Pages.MCP(draft: draft), language: "en", supportsChoice: false, supportsSections: false)
        XCTAssertTrue(http.contains { $0.id == "mcpURL" })
        XCTAssertFalse(http.contains { $0.id == "mcpCommand" })
    }

    func testASecretIsTypedAsNameEqualsValue() {
        XCTAssertEqual(Pages.secretEntry("Authorization=Bearer a=b")?.name, "Authorization")
        XCTAssertEqual(Pages.secretEntry("Authorization=Bearer a=b")?.value, "Bearer a=b")
        XCTAssertNil(Pages.secretEntry("=v"))
        XCTAssertNil(Pages.secretEntry("no equals"))
    }

    func testAFullListWithTheEditorOpenIsWithinTheProtocolsLimitsInEveryLanguage() throws {
        let servers = (1...40).map { index in
            AgentMCPServer(name: String(repeating: "n", count: 60) + "\(index)", transport: .http,
                           url: "https://" + String(repeating: "u", count: 100) + ".example.com", source: .claudeCode)
        }
        let configuration = VitruvianCodeConfiguration(botToken: "1:abc", workingDirectory: "/Users/someone/Work")
        for language in Words.languages {
            let tree = Pages.settings(Pages.Status(), draft: configuration, saved: configuration,
                                      logLines: Array(repeating: String(repeating: "l", count: 120), count: 10),
                                      language: language, supportsChoice: true, supportsSections: true,
                                      mcp: Pages.MCP(servers: servers, draft: AgentMCPServerDraft(servers[0]),
                                                     secretNames: ["A", "B"], problem: .invalidURL))
            XCTAssertLessThan(try JSONEncoder().encode(tree).count, UILimits.maxTreeBytes, language)
            XCTAssertLessThanOrEqual(tree.blocks.count, UILimits.maxBlocks, language)
        }
    }
}
