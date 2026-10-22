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

import AppKit
import NexusAgentCore
import SwiftUI
import XCTest

@testable import NexusAgentUI

/// Draws a reply with a diff step, a table and a highlighted code block to a
/// PNG, so the layout can be looked at. Bazel keeps the picture in the test's
/// undeclared outputs; elsewhere it goes to the temporary folder.
final class BubbleSnapshotTests: XCTestCase {
    @MainActor
    func testRendersARichReply() throws {
        let steps = [
            NexusAgentToolStep(
                title: "Edit Sources/App.swift", kind: .edit, filePath: "/repo/Sources/App.swift",
                diffOld: "let a = 1\nlet b = 2\nprint(a)", diffNew: "let a = 1\nlet b = 3\nprint(a + b)"),
            NexusAgentToolStep(title: "swift build", kind: .bash, output: "Building…\nerror: missing ;", isError: true),
            NexusAgentToolStep(title: "Read README.md", isFinished: false, kind: .read),
        ]
        let text = """
        ## Result
        The fix is in Sources/App.swift:2 and `ignored.swift:1`.

        | File | Lines | Status |
        | --- | ---: | :---: |
        | App.swift | 12 | **done** |
        | Tests.swift | 3 | pending |

        ```swift
        // Adds the two.
        func add(_ a: Int, _ b: Int) -> Int { return a + b }
        let s = "sum"
        ```

        ```bash
        swift build && echo "ok" # build
        ```
        """
        let message = NexusAgentChatMessage(
            role: .agent, text: text, durationMs: 4200, outputTokens: 900, toolSteps: steps,
            thinkingText: "Considering the edit.", thinkingTokens: 320, thinkingDurationMs: 4200)

        for (name, scheme) in [("dark", ColorScheme.dark), ("light", ColorScheme.light)] {
            let view = ExpandedBubble(message: message)
                .frame(width: 620)
                .padding(16)
                .background(scheme == .dark ? Color(white: 0.12) : Color(white: 0.97))
                .environment(\.colorScheme, scheme)
            let renderer = ImageRenderer(content: view)
            renderer.scale = 2
            guard let image = renderer.cgImage else { throw XCTSkip("ImageRenderer drew nothing here") }
            let data = try XCTUnwrap(NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:]))
            let folder = ProcessInfo.processInfo.environment["TEST_UNDECLARED_OUTPUTS_DIR"] ?? NSTemporaryDirectory()
            let url = URL(fileURLWithPath: folder).appendingPathComponent("bubble-\(name).png")
            try data.write(to: url)
            XCTAssertGreaterThan(image.height, 200)
        }
    }
}

/// The bubble with its tool steps open, as a click would leave it.
private struct ExpandedBubble: View {
    let message: NexusAgentChatMessage

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            NexusAgentMessageBubble(
                message: message, strings: NexusAgentChatStrings(), errorScheme: "x-test",
                workingDirectory: "/repo")
            NexusAgentToolStepRow(
                step: message.toolSteps![0], strings: NexusAgentChatStrings(), isExpanded: true, toggle: {})
            NexusAgentToolStepRow(
                step: message.toolSteps![1], strings: NexusAgentChatStrings(), isExpanded: true, toggle: {})
            NexusAgentToolStepRow(
                step: message.toolSteps![2], strings: NexusAgentChatStrings(), isExpanded: false, toggle: {})
            // The code's own lines: ImageRenderer draws no horizontal
            // scroll view, so the blocks above show empty in the picture.
            NexusAgentCodeBlockView(
                language: "swift", bodyText: "// Adds the two.\nfunc add(_ a: Int) -> Int { return a + 1 }\nlet s = \"sum\"",
                strings: NexusAgentChatStrings()).codeLines
            NexusAgentCodeBlockView(
                language: "bash", bodyText: "swift build && echo \"ok\" # build\nexport X=$HOME",
                strings: NexusAgentChatStrings()).codeLines
        }
    }
}
