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

import CoreGraphics
import Foundation
import NexusAgentCore
import XCTest

@MainActor
final class OrcaDiffAndDesignModeTests: XCTestCase {

    // MARK: - Unified Git Diff Parsing

    func testParseUnifiedDiffAcrossMultipleFilesAndHunks() {
        let sampleDiff = """
        diff --git a/Sources/App/AuthService.swift b/Sources/App/AuthService.swift
        index 1111111..2222222 100644
        --- a/Sources/App/AuthService.swift
        +++ b/Sources/App/AuthService.swift
        @@ -10,4 +10,5 @@ final class AuthService {
             func login(user: String) -> Bool {
        -        return false
        +        guard !user.isEmpty else { return false }
        +        return true
             }
        @@ -25,2 +26,3 @@ final class AuthService {
             func logout() {
        +        clearSession()
             }
        diff --git a/Sources/App/Router.swift b/Sources/App/Router.swift
        index 3333333..4444444 100644
        --- a/Sources/App/Router.swift
        +++ b/Sources/App/Router.swift
        @@ -1,3 +1,3 @@
         import Foundation
        -let defaultTimeout = 10
        +let defaultTimeout = 30
         let maxRetries = 3
        """

        let files = NexusAgentDiffParser.parseUnifiedDiff(sampleDiff)
        XCTAssertEqual(files.count, 2)

        let first = files[0]
        XCTAssertEqual(first.oldPath, "Sources/App/AuthService.swift")
        XCTAssertEqual(first.newPath, "Sources/App/AuthService.swift")
        XCTAssertEqual(first.addedCount, 3)
        XCTAssertEqual(first.removedCount, 1)
        XCTAssertEqual(first.hunks.count, 2)

        let hunk0Lines = first.hunks[0].lines
        XCTAssertEqual(hunk0Lines.count, 6)
        XCTAssertEqual(hunk0Lines[0].kind, .header)
        XCTAssertEqual(hunk0Lines[1].kind, .context)
        XCTAssertEqual(hunk0Lines[1].oldLineNumber, 10)
        XCTAssertEqual(hunk0Lines[1].newLineNumber, 10)
        XCTAssertEqual(hunk0Lines[2].kind, .deletion)
        XCTAssertEqual(hunk0Lines[2].oldLineNumber, 11)
        XCTAssertNil(hunk0Lines[2].newLineNumber)
        XCTAssertEqual(hunk0Lines[3].kind, .addition)
        XCTAssertNil(hunk0Lines[3].oldLineNumber)
        XCTAssertEqual(hunk0Lines[3].newLineNumber, 11)
        XCTAssertEqual(hunk0Lines[4].kind, .addition)
        XCTAssertEqual(hunk0Lines[4].newLineNumber, 12)
        XCTAssertEqual(hunk0Lines[5].kind, .context)
        XCTAssertEqual(hunk0Lines[5].oldLineNumber, 12)
        XCTAssertEqual(hunk0Lines[5].newLineNumber, 13)

        let second = files[1]
        XCTAssertEqual(second.displayPath, "Sources/App/Router.swift")
        XCTAssertEqual(second.addedCount, 1)
        XCTAssertEqual(second.removedCount, 1)
        XCTAssertEqual(second.hunks.count, 1)
    }

    // MARK: - Diff Annotations & Review Batch Composition

    func testDiffReviewSessionAnnotationsAndBatchPrompt() {
        let session = NexusAgentDiffReviewSession()
        session.loadDiff(
            """
            diff --git a/Sources/Server.swift b/Sources/Server.swift
            --- a/Sources/Server.swift
            +++ b/Sources/Server.swift
            @@ -4,2 +4,3 @@
             let port = 8080
            +let host = "0.0.0.0"
             let tlsEnabled = true
            """
        )
        XCTAssertEqual(session.files.count, 1)

        let singleLine = session.addAnnotation(
            filePath: "Sources/Server.swift",
            startLine: 5,
            endLine: 5,
            lineSnippet: "let host = \"0.0.0.0\"",
            commentMarkdown: "Bind to `127.0.0.1` by default for local security."
        )
        let multiLine = session.addAnnotation(
            filePath: "Sources/Config.swift",
            startLine: 18,
            endLine: 12,
            lineSnippet: "let retries = 0\nlet backoff = 0",
            commentMarkdown: "Use exponential backoff with at least 3 retries."
        )

        XCTAssertEqual(multiLine.startLine, 12)
        XCTAssertEqual(multiLine.endLine, 18)
        XCTAssertEqual(session.unresolvedAnnotations.count, 2)

        session.toggleResolved(id: singleLine.id)
        XCTAssertEqual(session.unresolvedAnnotations.count, 1)

        let promptWhileResolved = session.composeReviewBatchPrompt()
        XCTAssertNotNil(promptWhileResolved)
        XCTAssertFalse(promptWhileResolved?.contains("127.0.0.1") ?? true)
        XCTAssertTrue(promptWhileResolved?.contains("Sources/Config.swift") ?? false)
        XCTAssertTrue(promptWhileResolved?.contains("Lines 12-18") ?? false)
        XCTAssertTrue(promptWhileResolved?.contains("Use exponential backoff") ?? false)

        session.toggleResolved(id: singleLine.id)
        session.updateAnnotation(
            id: singleLine.id,
            commentMarkdown: "Bind to localhost unless explicitly configured."
        )
        let fullPrompt = session.composeReviewBatchPrompt()
        XCTAssertNotNil(fullPrompt)
        XCTAssertTrue(fullPrompt?.contains("Sources/Server.swift") ?? false)
        XCTAssertTrue(fullPrompt?.contains("Line 5") ?? false)
        XCTAssertTrue(fullPrompt?.contains("Bind to localhost unless explicitly configured.") ?? false)
        XCTAssertTrue(fullPrompt?.contains("let host = \"0.0.0.0\"") ?? false)

        session.removeAnnotation(id: singleLine.id)
        session.removeAnnotation(id: multiLine.id)
        XCTAssertNil(session.composeReviewBatchPrompt())
    }

    // MARK: - Design Mode DOM Capture & Prompt Formatting

    func testDesignModeParseCaptureAndFormatPrompt() {
        let rawJSON = """
        {
          "tagName": "BUTTON",
          "cssSelector": "header.nav > button.cta-primary:nth-of-type(1)",
          "outerHTMLSnippet": "<button class=\\"cta-primary\\">Deploy Now</button>",
          "computedStyles": {
            "backgroundColor": "rgb(217, 120, 87)",
            "color": "rgb(255, 255, 255)",
            "fontSize": "14px",
            "padding": "8px 16px"
          },
          "boundingBox": {
            "x": 240,
            "y": 18,
            "width": 128,
            "height": 36
          },
          "sourceLocation": "src/components/Header.tsx:42",
          "userIntentNote": "Increase horizontal padding to 20px and use semibold font weight."
        }
        """

        let capture = NexusAgentDesignModeScript.parseCapture(
            fromJSON: rawJSON,
            pageURL: "http://localhost:3000/dashboard"
        )
        XCTAssertNotNil(capture)
        XCTAssertEqual(capture?.tagName, "button")
        XCTAssertEqual(capture?.cssSelector, "header.nav > button.cta-primary:nth-of-type(1)")
        XCTAssertEqual(capture?.sourceLocation, "src/components/Header.tsx:42")
        XCTAssertEqual(capture?.boundingBox, CGRect(x: 240, y: 18, width: 128, height: 36))

        let formatted = NexusAgentDesignModeScript.formatPromptAttachment(
            for: [capture].compactMap { $0 }
        )
        XCTAssertTrue(formatted.contains("`<button>` (`header.nav > button.cta-primary:nth-of-type(1)`)"))
        XCTAssertTrue(formatted.contains("http://localhost:3000/dashboard"))
        XCTAssertTrue(formatted.contains("src/components/Header.tsx:42"))
        XCTAssertTrue(formatted.contains("padding: 8px 16px"))
        XCTAssertTrue(formatted.contains("<button class=\"cta-primary\">Deploy Now</button>"))
        XCTAssertTrue(formatted.contains("Increase horizontal padding to 20px"))
    }

    // MARK: - Rich Workspace Previews & Notes

    func testPreviewKindClassificationAndWorkspaceNoteStore() {
        XCTAssertEqual(NexusAgentPreviewKind.classify(path: "/repo/docs/README.md"), .markdown)
        XCTAssertEqual(NexusAgentPreviewKind.classify(path: "architecture.mmd"), .mermaid)
        XCTAssertEqual(NexusAgentPreviewKind.classify(path: "index.html"), .html)
        XCTAssertEqual(NexusAgentPreviewKind.classify(path: "spec.pdf"), .pdf)
        XCTAssertEqual(NexusAgentPreviewKind.classify(path: "assets/mockup.png"), .image)
        XCTAssertEqual(NexusAgentPreviewKind.classify(path: "Sources/main.swift"), .code)

        nonisolated(unsafe) var files: [String: String] = [
            "/workspace/feature-a/PLAN.md": "- [ ] Wire diff parser\n- [ ] Add tests"
        ]
        let store = NexusAgentWorkspaceNoteStore(
            worktreePath: "/workspace/feature-a/",
            readFile: { path in files[path] },
            writeFile: { path, content in
                files[path] = content
                return true
            }
        )
        XCTAssertEqual(store.noteFilePath, "/workspace/feature-a/PLAN.md")

        store.load()
        XCTAssertEqual(store.noteContent, "- [ ] Wire diff parser\n- [ ] Add tests")
        XCTAssertFalse(store.isDirty)

        store.updateContent("- [x] Wire diff parser\n- [x] Add tests")
        XCTAssertTrue(store.isDirty)
        XCTAssertTrue(store.save())
        XCTAssertFalse(store.isDirty)
        XCTAssertEqual(files["/workspace/feature-a/PLAN.md"], "- [x] Wire diff parser\n- [x] Add tests")

        let excerpt = store.formattedPromptExcerpt()
        XCTAssertNotNil(excerpt)
        XCTAssertTrue(excerpt?.contains("/workspace/feature-a/PLAN.md") ?? false)
        XCTAssertTrue(excerpt?.contains("- [x] Wire diff parser") ?? false)
    }
}
