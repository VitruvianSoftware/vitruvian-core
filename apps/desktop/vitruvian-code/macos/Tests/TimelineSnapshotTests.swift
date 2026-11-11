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
import VitruvianCodeCore
import SwiftUI
import XCTest

@testable import VitruvianCodeUI

/// Draws the conversation timeline over a six-turn chat to PNGs, so it can
/// be looked at: idle on the right edge, with the card open on turn 3, and
/// on the left edge (idle, and with a card), in light and dark. Bazel keeps
/// the pictures in the test's undeclared outputs; elsewhere they go to the
/// temporary folder. The paths are printed.
final class TimelineSnapshotTests: XCTestCase {
    private static let size = CGSize(width: 560, height: 520)

    private func conversation() -> [VitruvianCodeChatMessage] {
        let start = Date(timeIntervalSince1970: 1_792_600_000)
        let pairs: [(String, String)] = [
            ("Why does the release build fail on Intel Macs?",
             "The universal build links an **arm64-only** copy of `libsqlite`. See [the log](https://ci/log)."),
            ("Show me where that library is pulled in",
             "## Where it comes from\nIt arrives through `Package.swift`, line 42:\n```swift\n.package(url: \"…\")\n```"),
            ("Swap it for the system SQLite and rebuild both slices, then run the full test suite on each",
             "Done. Both slices link `/usr/lib/libsqlite3.dylib` now, and the 412 tests pass on arm64 and x86_64."),
            ("Update the changelog", "Added an entry under 1.4.2: - Fixed the Intel build."),
            ("Open a PR", "Opened #4402 with the change and the changelog entry."),
            ("Watch it until it lands", ""),
        ]
        var messages: [VitruvianCodeChatMessage] = []
        for (index, pair) in pairs.enumerated() {
            messages.append(VitruvianCodeChatMessage(role: .user, text: pair.0,
                                                  createdAt: start.addingTimeInterval(Double(index) * 420)))
            if !pair.1.isEmpty { messages.append(VitruvianCodeChatMessage(role: .agent, text: pair.1)) }
        }
        return messages
    }

    @MainActor
    func testRendersTheTimeline() throws {
        let messages = conversation()
        let turns = VitruvianCodeTimeline.turns(from: messages)
        XCTAssertEqual(turns.count, 6)
        let now = Date(timeIntervalSince1970: 1_792_600_000 + 3_000)
        let cases: [(name: String, onLeft: Bool, hovered: Int?)] = [
            ("idle-right", false, nil),
            ("hover-turn3-right", false, 2),
            ("idle-left", true, nil),
            ("hover-turn5-left", true, 4),
        ]
        let folder = ProcessInfo.processInfo.environment["TEST_UNDECLARED_OUTPUTS_DIR"] ?? NSTemporaryDirectory()
        for (schemeName, scheme) in [("light", ColorScheme.light), ("dark", ColorScheme.dark)] {
            for shot in cases {
                let view = ZStack {
                    (scheme == .dark ? Color(white: 0.12) : Color(white: 0.97))
                    FakeConversation(messages: messages, onLeft: shot.onLeft)
                        .frame(width: Self.size.width, height: Self.size.height, alignment: .top)
                        .clipped()
                    VitruvianCodeTimelineScrubber(
                        turns: turns, activeIndex: 1, onLeft: .constant(shot.onLeft),
                        strings: VitruvianCodeChatStrings(), now: now, hovered: shot.hovered, select: { _ in })
                        .frame(width: Self.size.width, height: Self.size.height)
                }
                .frame(width: Self.size.width, height: Self.size.height)
                .environment(\.colorScheme, scheme)
                let renderer = ImageRenderer(content: view)
                renderer.scale = 2
                guard let image = renderer.cgImage else { throw XCTSkip("ImageRenderer drew nothing here") }
                let data = try XCTUnwrap(NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:]))
                let url = URL(fileURLWithPath: folder).appendingPathComponent("timeline-\(shot.name)-\(schemeName).png")
                try data.write(to: url)
                print("timeline snapshot: \(url.path)")
                XCTAssertEqual(image.width, Int(Self.size.width * 2))
            }
        }
    }
}

/// The chat's bubbles in a plain stack: ImageRenderer draws no scroll view.
private struct FakeConversation: View {
    let messages: [VitruvianCodeChatMessage]
    /// The timeline's edge, where the chat leaves it a gutter.
    let onLeft: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            ForEach(messages) { message in
                VitruvianCodeMessageBubble(message: message, strings: VitruvianCodeChatStrings(), errorScheme: "x-test")
            }
        }
        .padding(14)
        .padding(onLeft ? .leading : .trailing, VitruvianCodeTimelineScrubber.gutter(onLeft: onLeft))
        .fixedSize(horizontal: false, vertical: true)
    }
}
