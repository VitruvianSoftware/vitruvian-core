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
import XCTest

/// Attachments for the next turn, and the `@` mention being typed.
@MainActor
final class AttachmentTests: XCTestCase {
    func testMentionIsTheLastWordWhenItStartsWithAt() {
        XCTAssertEqual(NexusAgentMention.activeQuery(in: "look at @src/ma"), "src/ma")
        XCTAssertEqual(NexusAgentMention.activeQuery(in: "@"), "")
        XCTAssertNil(NexusAgentMention.activeQuery(in: "look at @src/main.swift "), "a space ends it")
        XCTAssertNil(NexusAgentMention.activeQuery(in: "mail me@home"))
        XCTAssertNil(NexusAgentMention.activeQuery(in: ""))
    }

    func testChoosingAFileReplacesOnlyTheMention() {
        XCTAssertEqual(NexusAgentMention.replacingActiveQuery(in: "fix @ma", with: "Sources/main.swift"),
                       "fix @Sources/main.swift ")
        XCTAssertEqual(NexusAgentMention.replacingActiveQuery(in: "@", with: "a.txt"), "@a.txt ")
        XCTAssertEqual(NexusAgentMention.replacingActiveQuery(in: "no mention", with: "a.txt"), "no mention")
    }

    func testAttachmentsAreDedupedAndRemovable() {
        let session = ComposerRig().session()
        let url = URL(fileURLWithPath: "/tmp/one.txt")
        XCTAssertTrue(session.addAttachment(url: url))
        XCTAssertFalse(session.addAttachment(url: URL(fileURLWithPath: "/tmp/./one.txt")))
        XCTAssertTrue(session.addAttachment(url: URL(fileURLWithPath: "/tmp/shot.png")))
        XCTAssertEqual(session.attachments.count, 2)
        XCTAssertTrue(session.attachments[1].isImage)
        session.removeAttachment(id: session.attachments[0].id)
        XCTAssertEqual(session.attachments.map(\.displayName), ["shot.png"])
    }

    func testAttachmentsGoWithTheNextTurnAndAreClearedThen() {
        let rig = ComposerRig()
        let session = rig.session()
        session.addAttachment(url: URL(fileURLWithPath: "/tmp/spec.md"))
        session.send("read it", configuration: NexusAgentConfiguration(activeProvider: .claude),
                     agentPath: "/fake/claude")
        XCTAssertTrue(session.attachments.isEmpty)
        XCTAssertTrue(rig.launches.last?.contains(where: { $0.contains("/tmp/spec.md") }) ?? false,
                      "\(rig.launches)")
        rig.finishCleanly()
        session.stopTranscriptFollower()
    }

    func testPastingAnImageWritesAPNG() throws {
        let pasteboard = NSPasteboard.withUniqueName()
        defer { pasteboard.releaseGlobally() }
        let image = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 2, pixelsHigh: 2, bitsPerSample: 8,
                                     samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                                     colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
        pasteboard.clearContents()
        pasteboard.setData(image.tiffRepresentation, forType: .tiff)
        XCTAssertTrue(NexusAgentQuickPromptSession.pasteboardHasImageOnly(pasteboard))

        let session = ComposerRig().session()
        XCTAssertTrue(session.pasteFromClipboard(pasteboard))
        let attached = try XCTUnwrap(session.attachments.first)
        XCTAssertTrue(attached.isImage)
        XCTAssertEqual(attached.url.pathExtension, "png")
        let data = try Data(contentsOf: attached.url)
        XCTAssertTrue(data.starts(with: [0x89, 0x50, 0x4E, 0x47]), "a real PNG")
        try? FileManager.default.removeItem(at: attached.url)
    }

    func testTextOnTheClipboardIsNotAnImagePaste() {
        let pasteboard = NSPasteboard.withUniqueName()
        defer { pasteboard.releaseGlobally() }
        pasteboard.clearContents()
        pasteboard.setString("hello", forType: .string)
        XCTAssertFalse(NexusAgentQuickPromptSession.pasteboardHasImageOnly(pasteboard))
        XCTAssertFalse(ComposerRig().session().pasteFromClipboard(pasteboard))
    }

    func testPastedFilesAreAttached() {
        let pasteboard = NSPasteboard.withUniqueName()
        defer { pasteboard.releaseGlobally() }
        pasteboard.clearContents()
        pasteboard.writeObjects([URL(fileURLWithPath: "/tmp/a.txt") as NSURL])
        let session = ComposerRig().session()
        XCTAssertTrue(session.pasteFromClipboard(pasteboard))
        XCTAssertEqual(session.attachments.map(\.url.path), ["/tmp/a.txt"])
    }

    func testNotImageDataIsRefused() {
        XCTAssertFalse(ComposerRig().session().attachImage(data: Data("not an image".utf8)))
    }
}
