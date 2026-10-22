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

import XCTest

import NexusAgentCore
import NexusAgentToolCore
import VitruvianToolKit
import VitruvianToolProtocol

final class PagesTests: XCTestCase {
    private func ids(_ tree: UITree) -> [String] { tree.blocks.compactMap(\.id) }

    private func texts(_ tree: UITree, language: String = "en") -> [String] {
        tree.blocks.compactMap { block in
            switch block.content {
            case .text(let text): return text.text.text(for: language)
            case .heading(let heading): return heading.text.text(for: language)
            case .button(let button): return button.title.text(for: language)
            case .row(let row): return row.title.text(for: language) + " " + (row.subtitle?.text(for: language) ?? "")
            default: return nil
            }
        }
    }

    func testTheIslandPageSaysWhatTheBotAndTheAgentAreDoing() {
        var status = Pages.Status()
        let stopped = Pages.island(status, language: "en")
        XCTAssertEqual(ids(stopped), ["open", "newChat", "startBot"])
        XCTAssertTrue(texts(stopped).contains(Words.text("newChat", "en")))
        XCTAssertTrue(texts(stopped).contains("Telegram bot Stopped"))
        status.isRunning = true
        status.pid = 42
        status.replyStreaming = true
        status.problem = "No bot was found in this folder."
        status.sessions = [NexusAgentSessionSummary(id: "s1", title: "Fix the build", preview: "I will look", steps: 3,
                                                    modified: nil, isArchived: false)]
        let running = Pages.island(status, language: "en")
        XCTAssertEqual(ids(running), ["open", "newChat", "stopBot", "sessions"])
        XCTAssertTrue(texts(running).contains("A reply is arriving…"))
        XCTAssertTrue(texts(running).contains("Telegram bot Running · PID 42"))
        XCTAssertTrue(texts(running).contains("No bot was found in this folder."))
        status.replyStreaming = false
        status.awaitingApproval = true
        XCTAssertTrue(texts(Pages.island(status, language: "fr")).contains(Words.text("awaitingApproval", "fr")))
        status.awaitingApproval = false
        status.lastReply = "First line of the reply\nSecond line"
        XCTAssertTrue(texts(Pages.island(status, language: "en")).contains("Last reply: First line of the reply"))
    }

    func testSessionsAreAtMostTenWithTitlesCutAndTheUntitledNamed() {
        let sessions = (1...14).map {
            NexusAgentSessionSummary(id: "s\($0)", title: $0 == 1 ? "" : String(repeating: "x", count: 200),
                                     preview: "", steps: 0, modified: nil, isArchived: false)
        }
        let rows = Pages.sessionRows(sessions, language: "de")
        XCTAssertEqual(rows.count, Pages.maxSessionRows)
        XCTAssertEqual(rows.first?.title.text(for: "de"), Words.text("untitledSession", "de"))
        XCTAssertEqual(rows[1].title.text(for: "de").count, Pages.maxTitleLength)
        XCTAssertTrue(rows[1].title.text(for: "de").hasSuffix("…"))
        XCTAssertNil(rows.first?.subtitle, "no preview, no subtitle")
    }

    func testTheSettingsPanelDrawsTheEnvWithSaveOnlyWhenItChanged() {
        var saved = NexusAgentConfiguration(botToken: "1:abc", allowedUserIDs: "7", workingDirectory: "/w",
                                            approvalMode: .plan, model: "", effort: .high)
        let same = Pages.settings(Pages.Status(), draft: saved, saved: saved, logLines: [], language: "en")
        XCTAssertEqual(ids(same), ["startBot", "openLog", "token", "allowedUsers", "workingFolder", "chooseFolder",
                                   "approval", "model", "effort", "save"])
        guard case .button(let save)? = same.blocks.first(where: { $0.id == "save" })?.content else { return XCTFail("no Save") }
        XCTAssertEqual(save.enabled, false)
        guard case .field(let token)? = same.blocks.first(where: { $0.id == "token" })?.content else { return XCTFail("no token") }
        XCTAssertEqual(token.kind, FieldBlock.Kind.secret)
        XCTAssertEqual(token.value, "", "the secret is never sent back")
        XCTAssertEqual(token.placeholder?.text(for: "en"), "••••••••", "dots say one is set")
        XCTAssertNil(token.help, "an app without sections gets the caption as a text")
        XCTAssertTrue(texts(same).contains(Words.text("tokenCaption", "en")))
        guard case .list(let approval)? = same.blocks.first(where: { $0.id == "approval" })?.content else { return XCTFail("no list") }
        XCTAssertEqual(approval.rows.map(\.id), ["yolo", "accept-edits", "plan", "default"])
        XCTAssertEqual(approval.rows.map { $0.trailing?.text(for: "en") }, [nil, nil, "✓", nil])
        guard case .list(let effort)? = same.blocks.first(where: { $0.id == "effort" })?.content else { return XCTFail("no list") }
        XCTAssertEqual(effort.rows.map(\.id), ["automatic", "low", "medium", "high", "max"])
        XCTAssertEqual(effort.rows.map { $0.trailing?.text(for: "en") }, [nil, nil, nil, "✓", nil])
        XCTAssertTrue(texts(same).contains("Nothing logged yet."))

        var draft = saved
        draft.model = "gemini"
        var status = Pages.Status()
        status.isRunning = true
        status.needsRestart = true
        let changed = Pages.settings(status, draft: draft, saved: saved, logLines: ["a", "b"], language: "en")
        XCTAssertEqual(ids(changed).prefix(2), ["restartBot", "stopBot"])
        guard case .button(let save2)? = changed.blocks.first(where: { $0.id == "save" })?.content else { return XCTFail("no Save") }
        XCTAssertEqual(save2.enabled, true)
        XCTAssertTrue(texts(changed).contains("a\nb") && texts(changed).contains("Saved. Restart the bot to use the new settings."))
        saved.model = "x"
    }

    func testEffortRowsAndTheirChoices() {
        XCTAssertEqual(Pages.effortChoice(ofRow: "automatic"), "")
        XCTAssertEqual(Pages.effortChoice(ofRow: "low"), "low")
        XCTAssertEqual(Pages.effortChoice(ofRow: "written:xhigh"), "xhigh")
        XCTAssertEqual(Pages.approvalName(.yolo, language: "en"), "Run everything without asking")
        XCTAssertEqual(Pages.effortName(.automatic, language: "en"), "Automatic")
    }

    func testBothPagesAreWithinTheProtocolsLimitsInEveryLanguage() throws {
        var status = Pages.Status()
        status.sessions = (1...10).map {
            NexusAgentSessionSummary(id: "s\($0)", title: String(repeating: "t", count: 80), preview: String(repeating: "p", count: 80),
                                     steps: 0, modified: nil, isArchived: false)
        }
        status.problem = "x"
        status.needsRestart = true
        let configuration = NexusAgentConfiguration(botToken: String(repeating: "t", count: 60), allowedUserIDs: "1,2,3",
                                                    workingDirectory: "/Users/someone/Work", model: "gemini-3", effort: .low)
        for language in Words.languages {
            for tree in [Pages.island(status, language: language),
                         Pages.settings(status, draft: configuration, saved: NexusAgentConfiguration(),
                                        logLines: Array(repeating: String(repeating: "l", count: 120), count: 10), language: language),
                         Pages.settings(status, draft: configuration, saved: NexusAgentConfiguration(),
                                        logLines: Array(repeating: String(repeating: "l", count: 120), count: 10), language: language,
                                        supportsChoice: true, supportsSections: true)] {
                let bytes = try JSONEncoder().encode(tree).count
                XCTAssertLessThan(bytes, UILimits.maxTreeBytes, language)
                XCTAssertLessThanOrEqual(tree.blocks.count, UILimits.maxBlocks, language)
            }
        }
    }

    func testAnEmptyTokenHasNoDotsAndTheLogShowsTenLines() {
        let empty = Pages.settings(Pages.Status(), draft: NexusAgentConfiguration(), saved: NexusAgentConfiguration(),
                                   logLines: (1...14).map { "line \($0)" }, language: "en")
        guard case .field(let token)? = empty.blocks.first(where: { $0.id == "token" })?.content else { return XCTFail("no token") }
        XCTAssertNil(token.placeholder)
        let log = empty.blocks.compactMap { block -> TextBlock? in
            if case .text(let text) = block.content, text.style == .monospaced { return text }
            return nil
        }.first
        XCTAssertEqual(log?.lines, 10)
        XCTAssertEqual(Pages.logPreviewLines, UILimits.maxTextLines)
        XCTAssertEqual(log?.text.text(for: "en"), (5...14).map { "line \($0)" }.joined(separator: "\n"), "the last ten")
    }

    func testChoiceAndSectionsAreSentOnlyToAnAppThatHasThem() {
        let draft = NexusAgentConfiguration(botToken: "1:abc", approvalMode: .acceptEdits, effort: .high)
        let rich = Pages.settings(Pages.Status(), draft: draft, saved: draft, logLines: [], language: "de",
                                  supportsChoice: true, supportsSections: true)
        XCTAssertEqual(ids(rich), ["startBot", "openLog", "token", "allowedUsers", "workingFolder", "chooseFolder",
                                   "approval", "model", "effort", "save"])
        guard case .choice(let approval)? = rich.blocks.first(where: { $0.id == "approval" })?.content else { return XCTFail("no menu") }
        XCTAssertEqual(approval.value, "accept-edits")
        XCTAssertEqual(approval.title?.text(for: "de"), Words.text("approvalMode", "de"))
        guard case .choice(let effort)? = rich.blocks.first(where: { $0.id == "effort" })?.content else { return XCTFail("no menu") }
        XCTAssertEqual(effort.value, "high")
        XCTAssertEqual(effort.options.map(\.value), ["automatic", "low", "medium", "high", "max"])
        guard case .field(let token)? = rich.blocks.first(where: { $0.id == "token" })?.content else { return XCTFail("no token") }
        XCTAssertEqual(token.help?.text(for: "de"), Words.text("tokenCaption", "de"))
        guard case .field(let folder)? = rich.blocks.first(where: { $0.id == "workingFolder" })?.content else { return XCTFail("no folder") }
        XCTAssertEqual(folder.help?.text(for: "de"), Words.text("workingFolderCaption", "de"))
        XCTAssertFalse(texts(rich, language: "de").contains(Words.text("tokenCaption", "de")), "the caption is not said twice")
        let headings = rich.blocks.compactMap { block -> HeadingBlock? in
            if case .heading(let heading) = block.content { return heading }
            return nil
        }
        XCTAssertEqual(headings.map(\.section), [true])

        let plain = Pages.settings(Pages.Status(), draft: draft, saved: draft, logLines: [], language: "de")
        XCTAssertFalse(plain.blocks.contains { if case .choice = $0.content { return true }; return false })
        XCTAssertTrue(plain.blocks.allSatisfy { block in
            if case .heading(let heading) = block.content { return heading.section == nil }
            return true
        }, "an older app gets a plain heading")
        XCTAssertEqual(Pages.effortValue(NexusAgentConfiguration(effort: .low)), "low")
        XCTAssertEqual(Pages.effortValue(NexusAgentConfiguration()), "automatic")
    }
}
