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
import CoreGraphics

import NexusAgentCore

/// The pure rules' tests, ported from the Vitruvian app's test runner with
/// their conditions and messages unchanged, so the shared code is tested
/// where it lives.
final class PortedRulesTests: XCTestCase {
    func testEnvFile() {
        let legacy = """
        # Telegram Bot Token
        export TELEGRAM_BOT_TOKEN="123:abc"
        ALLOWED_USER_IDS= 1, 2 ,,3 # me
        GEMINI_WORKING_DIR=~/code
        GEMINI_APPROVAL_MODE=auto_edit
        GEMINI_MODEL=gemini-x
        GEMINI_THINKING=true
        CUSTOM=keep\r
        """
        let parsed = NexusAgentEnvFile.parse(legacy)
        XCTAssertTrue(parsed.botToken == "123:abc" && parsed.allowedUserIDList == ["1", "2", "3"]
                      && parsed.workingDirectory == "~/code" && parsed.approvalMode == .acceptEdits
                      && parsed.model == "gemini-x" && parsed.effort == .high,
                      "the .env reads as dotenv does, with the Gemini names as fallbacks: \(parsed)")
        XCTAssertTrue(NexusAgentEnvFile.values(in: legacy)["CUSTOM"] == "keep",
                      "a CRLF line ending is not part of the value")

        let both = "AGY_MODEL=new\nGEMINI_MODEL=old\nAGY_EFFORT=low\nGEMINI_THINKING=true\n"
        let preferred = NexusAgentEnvFile.parse(both)
        XCTAssertTrue(preferred.model == "new" && preferred.effort == .low,
                      "an AGY_ key beats its Gemini fallback, and an explicit effort beats GEMINI_THINKING")
        XCTAssertTrue(NexusAgentEnvFile.parse("AGY_MODEL=a\nAGY_MODEL=b\n").model == "b",
                      "the last copy of a key wins, as dotenv reads it")

        var edited = parsed
        edited.botToken = "999:zzz"
        edited.approvalMode = .plan
        edited.effort = .medium
        edited.model = "model #2"
        let rendered = NexusAgentEnvFile.render(edited, over: legacy)
        let reread = NexusAgentEnvFile.parse(rendered)
        var expected = edited
        expected.allowedUserIDs = "1,2,3"
        XCTAssertTrue(reread == expected, "a saved .env reads back as written, the user list tidied: \(reread)")
        XCTAssertTrue(rendered.hasPrefix("# Telegram Bot Token\n") && rendered.contains("CUSTOM=keep"),
                      "saving keeps comments and keys the page does not own")
        XCTAssertTrue(!rendered.contains("GEMINI_"), "saving drops the superseded Gemini names")
        XCTAssertTrue(rendered.hasSuffix("\n") && !rendered.hasSuffix("\n\n\n"), "the file ends with one newline")

        let twice = NexusAgentEnvFile.render(NexusAgentConfiguration(botToken: "t"),
                                             over: "TELEGRAM_BOT_TOKEN=a\nOTHER=1\nTELEGRAM_BOT_TOKEN=b\n")
        XCTAssertTrue(twice.components(separatedBy: "TELEGRAM_BOT_TOKEN=t").count == 3
                      && !twice.contains("=a") && !twice.contains("=b"),
                      "every copy of an owned key gets the new value")

        var injected = NexusAgentConfiguration(botToken: "a\nCUSTOM=evil", allowedUserIDs: "1\r\n2")
        injected.model = " padded "
        let guarded = NexusAgentEnvFile.render(injected, over: "CUSTOM=keep\n")
        let guardedValues = NexusAgentEnvFile.values(in: guarded)
        XCTAssertTrue(guardedValues["CUSTOM"] == "keep" && guardedValues[NexusAgentEnvFile.tokenKey] == "aCUSTOM=evil",
                      "a pasted line break can never smuggle in another assignment: \(guarded)")
        XCTAssertTrue(guardedValues[NexusAgentEnvFile.modelKey] == "padded",
                      "values are trimmed before they are written")

        let fresh = NexusAgentEnvFile.render(NexusAgentConfiguration(botToken: "x"), over: nil)
        XCTAssertTrue(fresh.contains("AGY_TIMEOUT_MS=300000") && fresh.contains("CLI_PROVIDER=agy")
                      && NexusAgentEnvFile.parse(fresh) == NexusAgentConfiguration(botToken: "x"),
                      "a first save writes the bot's template with the page's values")
        XCTAssertTrue(NexusAgentEnvFile.render(NexusAgentConfiguration(), over: "  \n") == NexusAgentEnvFile.render(NexusAgentConfiguration(), over: nil),
                      "a blank file is treated as no file")
        XCTAssertTrue(NexusAgentEnvFile.encoded("it's #1") == "\"it's #1\"" && NexusAgentEnvFile.encoded("a#b") == "'a#b'"
                      && NexusAgentEnvFile.encoded("plain") == "plain",
                      "a value dotenv would cut is quoted, in quotes it keeps")
        XCTAssertTrue(NexusAgentEnvFile.assignment(in: "# KEY=value") == nil
                      && NexusAgentEnvFile.assignment(in: "not an assignment") == nil
                      && NexusAgentEnvFile.assignment(in: "=value") == nil,
                      "comments, prose and keyless lines are not assignments")
    }

    func testModes() {
        XCTAssertTrue(NexusAgentApprovalMode.parse(nil) == .yolo && NexusAgentApprovalMode.parse("") == .standard
                      && NexusAgentApprovalMode.parse(" PLAN ") == .plan
                      && NexusAgentApprovalMode.parse("accept_edits") == .acceptEdits
                      && NexusAgentApprovalMode.parse("auto_edit") == .acceptEdits
                      && NexusAgentApprovalMode.parse("bogus") == .standard,
                      "approval modes parse as the bot reads them")
        XCTAssertTrue(NexusAgentApprovalMode.yolo.agyArguments == ["--dangerously-skip-permissions"]
                      && NexusAgentApprovalMode.acceptEdits.agyArguments == ["--mode", "accept-edits"]
                      && NexusAgentApprovalMode.standard.agyArguments.isEmpty,
                      "each approval mode passes agy the bot's flags")
        XCTAssertTrue(NexusAgentEffort.parse("HIGH") == .high && NexusAgentEffort.parse(nil) == .automatic
                      && NexusAgentEffort.parse("max") == .automatic,
                      "effort parses, unknown values leaving the choice to agy")
        XCTAssertTrue(!NexusAgentConfiguration().isConfigured
                      && !NexusAgentConfiguration(botToken: NexusAgentConfiguration.placeholderToken).isConfigured
                      && !NexusAgentConfiguration(botToken: "   ").isConfigured
                      && NexusAgentConfiguration(botToken: "1:a").isConfigured,
                      "only a real token counts as configured")

        let configuration = NexusAgentConfiguration(approvalMode: .plan, model: " m ", effort: .low)
        XCTAssertTrue(NexusAgentSupport.agentArguments(prompt: "hi", configuration: configuration, conversationID: "c1")
                      == ["-p", "hi", "--output-format", "stream-json", "--mode", "plan", "--model", "m",
                          "--effort", "low", "--conversation", "c1"],
                      "a turn passes the prompt, streamed JSON, the bot's settings and the conversation")
        XCTAssertTrue(NexusAgentSupport.agentArguments(prompt: "hi", configuration: NexusAgentConfiguration(approvalMode: .standard),
                                                       conversationID: "")
                      == ["-p", "hi", "--output-format", "stream-json"],
                      "a first turn with agy defaults passes nothing else")
    }

    func testLocations() {
        let home = "/Users/test"
        XCTAssertTrue(NexusAgentSupport.botDirectory(configured: "", home: home) == "/Users/test/.config/nexus-agent"
                      && NexusAgentSupport.botDirectory(configured: "~", home: home) == home
                      && NexusAgentSupport.botDirectory(configured: " ~/bots/nexus ", home: home) == "/Users/test/bots/nexus"
                      && NexusAgentSupport.botDirectory(configured: "/opt/nexus", home: home) == "/opt/nexus",
                      "the bot folder defaults to the standalone app's and expands ~")
        let installed: Set<String> = ["/opt/homebrew/bin/agy", "/custom/agy", "/usr/local/bin/node"]
        XCTAssertTrue(NexusAgentSupport.locateAgent(environment: ["AGY_BIN": "/custom/agy"], home: home,
                                                    isExecutable: installed.contains) == "/custom/agy"
                      && NexusAgentSupport.locateAgent(environment: ["AGY_BIN": "/missing/agy"], home: home,
                                                       isExecutable: installed.contains) == "/opt/homebrew/bin/agy"
                      && NexusAgentSupport.locateAgent(environment: [:], home: home, isExecutable: { _ in false }) == nil,
                      "AGY_BIN wins when it runs; otherwise the usual install folders, or nothing")
        XCTAssertTrue(NexusAgentSupport.locateNode(home: home, isExecutable: installed.contains) == "/usr/local/bin/node"
                      && NexusAgentSupport.locateNode(home: home, isExecutable: { _ in false }) == nil,
                      "Node is found where Homebrew or its installer put it")
        let child = NexusAgentSupport.childEnvironment(base: ["PATH": "/opt/homebrew/bin:/usr/bin", "KEEP": "1"], home: home)
        XCTAssertTrue(child["PATH"] == "/Users/test/.local/bin:/usr/local/bin:/opt/homebrew/bin:/usr/bin"
                      && child["NO_COLOR"] == "1" && child["KEEP"] == "1",
                      "the child gets the install folders in front of PATH, once each: \(child["PATH"] ?? "")")
        XCTAssertTrue(NexusAgentSupport.childEnvironment(base: [:], home: home)["PATH"]?.hasSuffix(":/usr/bin:/bin:/usr/sbin:/sbin") == true,
                      "an app with no PATH still gives the child the system folders")
        XCTAssertTrue(NexusAgentSupport.tail("a\n\nb\nc\n", count: 2) == ["b", "c"]
                      && NexusAgentSupport.tail("x", count: 0).isEmpty,
                      "the log tail keeps the last non-empty lines")
        XCTAssertTrue(NexusAgentSupport.processID(fromPIDFile: " 42\n") == 42
                      && NexusAgentSupport.processID(fromPIDFile: "0") == nil
                      && NexusAgentSupport.processID(fromPIDFile: "-5") == nil
                      && NexusAgentSupport.processID(fromPIDFile: "abc") == nil,
                      "a PID file names a positive process id or nothing")
        let models = NexusAgentSupport.parseModels("Fetching models…\ngemini-3\tGemini 3\nsolo\n\n")
        XCTAssertTrue(models.map(\.id) == ["gemini-3", "solo"] && models.map(\.name) == ["Gemini 3", "solo"],
                      "agy models reads id and name rows")
    }

    func testStream() {
        XCTAssertTrue(NexusAgentStreamEvent.parse(#"{"event":"init","conversation_id":"c9"}"#) == .started(conversationID: "c9"),
                      "init carries the conversation id")
        XCTAssertTrue(NexusAgentStreamEvent.parse(#"{"event":"step_update","step_update":{"step_type":"agent_response","text_delta":"Hi"}}"#) == .text("Hi"),
                      "a response step carries its text delta")
        XCTAssertTrue(NexusAgentStreamEvent.parse(#"{"event":"step_update","step_update":{"step_type":"tool","tool_name":"grep","state":"RUNNING"}}"#)
                         == .tool(name: "grep", finished: false)
                      && NexusAgentStreamEvent.parse(#"{"event":"step_update","step_update":{"step_type":"tool","state":"done"}}"#)
                         == .tool(name: "tool", finished: true),
                      "a tool step says which tool runs and when it is done")
        XCTAssertTrue(NexusAgentStreamEvent.parse(#"{"event":"result","result":{"status":"ok","response":"All","conversation_id":"c9"}}"#)
                      == .finished(status: "ok", response: "All", error: nil, conversationID: "c9"),
                      "the result carries the status, the whole reply and the id")
        XCTAssertTrue(NexusAgentStreamEvent.parse("") == nil && NexusAgentStreamEvent.parse("Error: boom") == nil
                      && NexusAgentStreamEvent.parse(#"{"event":"heartbeat"}"#) == nil
                      && NexusAgentStreamEvent.parse(#"{"event":"step_update","step_update":{"step_type":"agent_response","text_delta":""}}"#) == nil,
                      "noise, unknown events and empty deltas are skipped")

        var buffer = NexusAgentLineBuffer()
        let bytes = Array("first\nsé".utf8)
        let cut = bytes.count - 1 // inside the two bytes of é
        let firstLines = buffer.append(Data(bytes[..<cut]))
        let secondLines = buffer.append(Data(bytes[cut...]) + Data("cond\nthird".utf8))
        XCTAssertTrue(firstLines == ["first"] && secondLines == ["sécond"] && buffer.finish() == "third"
                      && buffer.finish() == nil,
                      "lines split only at newlines, a character cut between reads comes out whole")
    }

    func testQuickPromptLayout() {
        typealias Layout = NexusAgentQuickPromptLayout
        let screen = CGRect(x: 0, y: 25, width: 1440, height: 875)
        let pill = Layout.initialFrame(for: .compact, screen: screen)
        XCTAssertTrue(pill.size == CGSize(width: 680, height: 72) && Layout.cornerRadius == 22,
                      "the pill is 680 by 72 with 22 pt corners: \(pill)")
        XCTAssertTrue(pill.midX == screen.midX && pill.maxY < screen.maxY
                      && pill.minY > screen.minY + screen.height * 2 / 3
                      && abs((screen.maxY - pill.maxY) - screen.height * 0.18) < 0.5,
                      "the pill sits centred in the upper third, 18% below the top: \(pill)")
        let offset = CGRect(x: -1920, y: 0, width: 1920, height: 1080)
        let other = Layout.initialFrame(for: .compact, screen: offset)
        XCTAssertTrue(offset.contains(other) && other.midX == offset.midX,
                      "on a second screen the pill opens on that screen: \(other)")

        let drawer = Layout.frame(for: .sessions, from: pill, screen: screen)
        XCTAssertTrue(drawer.size == CGSize(width: 680, height: 340) && drawer.maxY == pill.maxY
                      && drawer.midX == pill.midX,
                      "the drawer grows the panel to 680 by 340 downward, keeping its top: \(drawer)")
        let chat = Layout.frame(for: .chat, from: drawer, screen: screen)
        XCTAssertTrue(chat.size == CGSize(width: 680, height: 500) && chat.maxY == pill.maxY,
                      "the chat grows the panel to 680 by 500, keeping its top: \(chat)")
        let back = Layout.frame(for: .compact, from: chat, screen: screen)
        XCTAssertTrue(back == pill, "back to the pill returns to the same frame: \(back)")
        XCTAssertTrue(Layout.isResizable(.chat) && !Layout.isResizable(.compact) && !Layout.isResizable(.sessions)
                      && Layout.chatMinimumSize.width < 680 && Layout.chatMaximumSize.height > 500,
                      "only the chat can be resized, around its 680 by 500 size")

        let low = CGRect(x: 0, y: 0, width: 800, height: 500)
        let lowChat = Layout.frame(for: .chat, from: Layout.initialFrame(for: .compact, screen: low), screen: low)
        XCTAssertTrue(low.contains(lowChat), "on a short screen the chat stays on screen: \(lowChat)")
    }

    func testSessionIndex() {
        let rows = """
        [{"conversation_id":"c1","title":"","preview":"Deploy the site\\nmore","step_count":7,
          "last_modified_time":"2026-10-01T09:30:00.250Z","workspace_uris":"[\\"file:///Users/me/work\\"]"},
          {"conversation_id":"c2","title":"Elsewhere","step_count":1,"workspace_uris":"[\\"file:///tmp/other\\"]"},
          {"conversation_id":"c3","title":"Anywhere","step_count":2,"last_modified_time":"2026-10-01T09:30:00Z"},
          {"conversation_id":"","title":"broken"}]
        """
        let sessions = NexusAgentSessionSummary.parse(Data(rows.utf8), directory: "/Users/me/work/")
        XCTAssertTrue(sessions.map(\.id) == ["c1", "c3"], "the drawer keeps this folder's and folderless sessions: \(sessions.map(\.id))")
        XCTAssertTrue(sessions.first?.title == "Deploy the site" && sessions.first?.steps == 7
                      && sessions.first?.preview == "Deploy the site\nmore"
                      && sessions.first?.modified != nil && sessions.last?.modified != nil,
                      "an untitled session shows its first prompt line, preview, and both date forms parse")
        XCTAssertTrue(NexusAgentSessionSummary.parse(Data("not json".utf8), directory: "/").isEmpty,
                      "an unreadable index lists nothing")
        XCTAssertTrue(NexusAgentSessionSummary.filter(sessions, by: "  ").count == 2
                      && NexusAgentSessionSummary.filter(sessions, by: "site deploy").map(\.id) == ["c1"],
                      "a blank filter keeps all; words match in any order")
        let allSessions = NexusAgentSessionSummary.parse(Data(rows.utf8), directory: "")
        XCTAssertTrue(allSessions.map(\.id) == ["c1", "c2", "c3"],
                      "an empty directory keeps all sessions across workspaces: \(allSessions.map(\.id))")

        // Project slug conversion for Claude Code projects
        XCTAssertTrue(NexusAgentSessionSummary.projectSlug(for: "/Users/james/Workspace/gh/application/vitruvian/vitruvian-core")
                      == "-Users-james-Workspace-gh-application-vitruvian-vitruvian-core",
                      "projectSlug converts monorepo path to slug")
        XCTAssertTrue(NexusAgentSessionSummary.projectSlug(for: "/Users/james/.buzz")
                      == "-Users-james--buzz",
                      "projectSlug converts dot paths to slug")
        XCTAssertTrue(NexusAgentSessionSummary.projectSlug(for: "/Users/james")
                      == "-Users-james",
                      "projectSlug converts simple path to slug")
    }

    func testReplyBlocks() {
        let reply = "Run **this**:\n```swift\nlet x = 1\n\nprint(x)\n```\nDone."
        XCTAssertTrue(NexusAgentReplyBlock.parse(reply) == [
            .text("Run **this**:"), .code(language: "swift", body: "let x = 1\n\nprint(x)"), .text("Done."),
        ], "prose and fenced code split apart, blank lines kept inside code: \(NexusAgentReplyBlock.parse(reply))")
        XCTAssertTrue(NexusAgentReplyBlock.parse("Partial\n```\nstill streaming") == [
            .text("Partial"), .code(language: nil, body: "still streaming"),
        ], "an unclosed fence while streaming is code to the end")
        XCTAssertTrue(NexusAgentReplyBlock.parse("") == [], "an empty reply has no blocks")
    }

    func testMarkdownBlocks() {
        // Headings
        XCTAssertTrue(NexusAgentMarkdownBlock.parse("# Heading 1") == [.heading(level: 1, text: "Heading 1")],
                      "heading 1 parses correctly")
        XCTAssertTrue(NexusAgentMarkdownBlock.parse("## Heading 2") == [.heading(level: 2, text: "Heading 2")],
                      "heading 2 parses correctly")
        XCTAssertTrue(NexusAgentMarkdownBlock.parse("### Heading 3") == [.heading(level: 3, text: "Heading 3")],
                      "heading 3 parses correctly")
        XCTAssertTrue(NexusAgentMarkdownBlock.parse("#NotAHeading") == [.paragraph(text: "#NotAHeading")],
                      "hash without space is treated as paragraph")

        // Bullet list items
        XCTAssertTrue(NexusAgentMarkdownBlock.parse("* item") == [.bulletItem(text: "item")],
                      "asterisk bullet item parses")
        XCTAssertTrue(NexusAgentMarkdownBlock.parse("- item") == [.bulletItem(text: "item")],
                      "dash bullet item parses")
        XCTAssertTrue(NexusAgentMarkdownBlock.parse("+ item") == [.bulletItem(text: "item")],
                      "plus bullet item parses")

        // Numbered list items
        XCTAssertTrue(NexusAgentMarkdownBlock.parse("1. item") == [.numberedItem(number: "1", text: "item")],
                      "numbered item 1. parses")
        XCTAssertTrue(NexusAgentMarkdownBlock.parse("2. item") == [.numberedItem(number: "2", text: "item")],
                      "numbered item 2. parses")
        XCTAssertTrue(NexusAgentMarkdownBlock.parse("1) item") == [.numberedItem(number: "1", text: "item")],
                      "numbered item 1) parses")

        // Blockquotes
        XCTAssertTrue(NexusAgentMarkdownBlock.parse("> quote line 1\n> quote line 2") == [
            .blockquote(text: "quote line 1\nquote line 2"),
        ], "contiguous quote lines merge into a single blockquote")

        // Dividers
        XCTAssertTrue(NexusAgentMarkdownBlock.parse("---") == [.divider],
                      "dash divider parses")
        XCTAssertTrue(NexusAgentMarkdownBlock.parse("***") == [.divider],
                      "asterisk divider parses")

        // Whitespace and empty
        XCTAssertTrue(NexusAgentMarkdownBlock.parse("").isEmpty, "empty text produces no blocks")
        XCTAssertTrue(NexusAgentMarkdownBlock.parse("   \n\n\t  ").isEmpty, "whitespace produces no blocks")

        // Mixed document
        let doc = """
        # Title

        Body paragraph.

        - Bullet A
        - Bullet B

        > A quoted notice

        ---
        1. First
        2. Second
        """
        let parsed = NexusAgentMarkdownBlock.parse(doc)
        XCTAssertTrue(parsed == [
            .heading(level: 1, text: "Title"),
            .paragraph(text: "Body paragraph."),
            .bulletItem(text: "Bullet A"),
            .bulletItem(text: "Bullet B"),
            .blockquote(text: "A quoted notice"),
            .divider,
            .numberedItem(number: "1", text: "First"),
            .numberedItem(number: "2", text: "Second"),
        ], "mixed document parses into structured blocks: \(parsed)")

        // Mermaid detection in reply blocks
        let reply = "```mermaid\ngraph TD\nA --> B\n```"
        XCTAssertTrue(NexusAgentReplyBlock.parse(reply) == [
            .code(language: "mermaid", body: "graph TD\nA --> B"),
        ], "mermaid code fence retains mermaid language")
    }

    func testTurnMetrics() {
        let metrics = NexusAgentTurnMetrics(durationMs: 1250, inputTokens: 500, outputTokens: 150, cachedTokens: 50, numTurns: 2, toolCalls: 3)
        XCTAssertTrue(metrics.durationMs == 1250 && metrics.inputTokens == 500 && metrics.outputTokens == 150, "metrics preserve values")

        let resultJson = """
        {"event":"result","result":{"status":"ok","duration_ms":3400,"input_tokens":1200,"output_tokens":450,"cached_tokens":100,"num_turns":1,"tool_calls":2,"response":"Done."}}
        """
        let event = NexusAgentStreamEvent.parse(resultJson)
        if case .finished(_, _, _, _, let parsedMetrics) = event {
            XCTAssertTrue(parsedMetrics?.durationMs == 3400 && parsedMetrics?.outputTokens == 450, "result event parsed into finished with metrics")
        } else {
            XCTAssertTrue(false, "expected .finished event with metrics: \(String(describing: event))")
        }
    }

    func testClaudeSessionTitles() {
        // 1. Task name formatting
        XCTAssertTrue(NexusAgentSessionSummary.formatTaskName("track-zitadel-login-2fa-fix") == "Track zitadel login 2fa fix",
                      "formatTaskName converts hyphens to spaces and capitalizes first word")
        XCTAssertTrue(NexusAgentSessionSummary.formatTaskName("daily_ci_pipeline_hygiene") == "Daily ci pipeline hygiene",
                      "formatTaskName converts underscores to spaces and capitalizes first word")

        // 2. Extract scheduled task name from XML tags
        let taskXMLDoubleQuote = "<scheduled-task name=\"track-zitadel-login-2fa-fix\" file=\"/path/to/task.md\">\nTask content\n</scheduled-task>"
        XCTAssertTrue(NexusAgentSessionSummary.extractScheduledTaskName(taskXMLDoubleQuote) == "Track zitadel login 2fa fix",
                      "extractScheduledTaskName extracts double-quoted task name")

        let taskXMLSingleQuote = "<scheduled-task name='daily-ci-pipeline-hygiene'>\nCheck pipeline\n</scheduled-task>"
        XCTAssertTrue(NexusAgentSessionSummary.extractScheduledTaskName(taskXMLSingleQuote) == "Daily ci pipeline hygiene",
                      "extractScheduledTaskName extracts single-quoted task name")

        XCTAssertTrue(NexusAgentSessionSummary.extractScheduledTaskName("No scheduled task here") == nil,
                      "extractScheduledTaskName returns nil when no scheduled task tag is present")

        // 3. User prompt sanitization (XML stripping)
        let rawPromptWithTaskAndReminder = """
        <system-reminder>
        UserPromptSubmit hook success
        </system-reminder>
        <scheduled-task name="track-zitadel-login-2fa-fix" file="/some/path">
        Please investigate the Zitadel 2FA issue.
        </scheduled-task>
        """
        let cleanedPrompt = NexusAgentSessionSummary.extractUserPrompt(rawPromptWithTaskAndReminder)
        XCTAssertTrue(cleanedPrompt == "Please investigate the Zitadel 2FA issue.",
                      "extractUserPrompt strips both system-reminder and scheduled-task tags, preserving body text")

        // 4. File-based Claude session title discovery
        let tmpDir = FileManager.default.temporaryDirectory.appendingPathComponent("claude-titles-test-\(UUID().uuidString)")
        let projectsDir = tmpDir.appendingPathComponent(".claude/projects/-test-project")
        try? FileManager.default.createDirectory(at: projectsDir, withIntermediateDirectories: true)
        defer {
            try? FileManager.default.removeItem(at: tmpDir)
        }

        // Case A: Custom title from companion custom-title.json
        let sessionADir = projectsDir.appendingPathComponent("session-a")
        try? FileManager.default.createDirectory(at: sessionADir, withIntermediateDirectories: true)
        let customTitleJSON = "{\"customTitle\": \"Companion File Title\"}"
        try? customTitleJSON.write(to: sessionADir.appendingPathComponent("custom-title.json"), atomically: true, encoding: .utf8)
        let sessionAJSONL = "{\"type\":\"user\",\"content\":\"some user content\"}\n"
        try? sessionAJSONL.write(to: projectsDir.appendingPathComponent("session-a.jsonl"), atomically: true, encoding: .utf8)

        // Case B: In-stream custom-title event
        let sessionBJSONL = """
        {"type":"custom-title","customTitle":"Stream Custom Title"}
        {"type":"user","content":"User prompt for stream test"}
        """
        try? sessionBJSONL.write(to: projectsDir.appendingPathComponent("session-b.jsonl"), atomically: true, encoding: .utf8)

        // Case C: In-stream agent-name event
        let sessionCJSONL = """
        {"type":"agent-name","agentName":"Agent Name Title"}
        {"type":"user","content":"User prompt for agent name"}
        """
        try? sessionCJSONL.write(to: projectsDir.appendingPathComponent("session-c.jsonl"), atomically: true, encoding: .utf8)

        // Case D: Scheduled task fallback title and clean preview
        let sessionDJSONL = """
        {"type":"queue-operation","operation":"enqueue","content":"<scheduled-task name=\\"track-zitadel-login-2fa-fix\\">Check Zitadel 2FA issue</scheduled-task>"}
        {"type":"user","message":{"role":"user","content":"<scheduled-task name=\\"track-zitadel-login-2fa-fix\\">Check Zitadel 2FA issue</scheduled-task>"}}
        """
        try? sessionDJSONL.write(to: projectsDir.appendingPathComponent("session-d.jsonl"), atomically: true, encoding: .utf8)

        // Case E: Regular fallback prompt
        let sessionEJSONL = """
        {"type":"user","message":{"role":"user","content":"Regular user question without title"}}
        """
        try? sessionEJSONL.write(to: projectsDir.appendingPathComponent("session-e.jsonl"), atomically: true, encoding: .utf8)

        let sessions = NexusAgentSessionSummary.parseClaudeSessions(home: tmpDir.path, directory: "/test/project", appHidden: [])
        let summaryA = sessions.first { $0.id == "session-a" }
        let summaryB = sessions.first { $0.id == "session-b" }
        let summaryC = sessions.first { $0.id == "session-c" }
        let summaryD = sessions.first { $0.id == "session-d" }
        let summaryE = sessions.first { $0.id == "session-e" }

        XCTAssertTrue(summaryA?.title == "Companion File Title",
                      "Session A resolves title from companion custom-title.json")
        XCTAssertTrue(summaryB?.title == "Stream Custom Title",
                      "Session B resolves title from in-stream custom-title event")
        XCTAssertTrue(summaryC?.title == "Agent Name Title",
                      "Session C resolves title from in-stream agent-name event")
        XCTAssertTrue(summaryD?.title == "Track zitadel login 2fa fix",
                      "Session D resolves title from scheduled-task name attribute")
        XCTAssertTrue(summaryD?.preview == "Check Zitadel 2FA issue",
                      "Session D preview is sanitized to exclude scheduled-task XML tags")
        XCTAssertTrue(summaryE?.title == "Regular user question without title",
                      "Session E falls back to first line of preview")
    }
}
