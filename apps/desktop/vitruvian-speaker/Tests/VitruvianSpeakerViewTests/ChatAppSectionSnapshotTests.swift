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
import SwiftUI
import XCTest
@testable import VitruvianSpeaker
@testable import VitruvianSpeakerCore

/// Draws a view to `name`-light.png and `name`-dark.png.
@MainActor
enum Snapshot {
    /// Bazel's undeclared outputs for this test, or (outside Bazel) a
    /// folder under the temporary directory.
    static var directory: URL {
        let environment = ProcessInfo.processInfo.environment
        let base = environment["TEST_UNDECLARED_OUTPUTS_DIR"].map { URL(fileURLWithPath: $0) }
            ?? FileManager.default.temporaryDirectory.appendingPathComponent("VitruvianSpeakerViewTests")
        try? FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
        return base
    }

    /// Renders `view` at `width`, as tall as it needs, light and dark, and
    /// returns the two sizes in pixels.
    @discardableResult
    static func render<V: View>(_ name: String, width: CGFloat, @ViewBuilder _ view: () -> V) throws -> [NSSize] {
        _ = NSApplication.shared
        var sizes: [NSSize] = []
        for (suffix, appearance) in [("light", NSAppearance.Name.aqua), ("dark", .darkAqua)] {
            let content = view()
                .frame(width: width)
                .fixedSize(horizontal: false, vertical: true)
                .background(Color(nsColor: .windowBackgroundColor))
            let host = NSHostingView(rootView: content)
            host.appearance = NSAppearance(named: appearance)
            let size = NSSize(width: width, height: max(host.fittingSize.height, 1))
            let window = NSWindow(contentRect: NSRect(origin: .zero, size: size), styleMask: [.borderless],
                                  backing: .buffered, defer: false)
            window.appearance = NSAppearance(named: appearance)
            window.contentView = host
            host.frame = NSRect(origin: .zero, size: size)
            host.layoutSubtreeIfNeeded()
            window.displayIfNeeded()
            for _ in 0 ..< 25 {
                RunLoop.main.run(mode: .default, before: Date(timeIntervalSinceNow: 0.004))
                host.layoutSubtreeIfNeeded()
            }
            window.displayIfNeeded()
            guard let bitmap = host.bitmapImageRepForCachingDisplay(in: host.bounds) else {
                throw SnapshotError.noBitmap(name)
            }
            host.cacheDisplay(in: host.bounds, to: bitmap)
            guard let png = bitmap.representation(using: .png, properties: [:]) else { throw SnapshotError.noBitmap(name) }
            try png.write(to: directory.appendingPathComponent("\(name)-\(suffix).png"))
            sizes.append(NSSize(width: bitmap.pixelsWide, height: bitmap.pixelsHigh))
            window.contentView = nil
        }
        return sizes
    }
}

enum SnapshotError: Error {
    case noBitmap(String)
}

/// Settings › Chats' Beeper and Courier sections, in the states a person
/// meets them, at the Settings window's width. Made-up networks only.
@MainActor
final class ChatAppSectionSnapshotTests: XCTestCase {
    private func section(
        _ app: ChatApp, isOn: Bool, hasToken: Bool, listed: [BeeperNetworkState]? = nil, muted: [String] = [],
        address: String = "", readingLine: String? = nil, readAnyway: [String] = []
    ) -> some View {
        Form {
            ChatAppSection(
                app: app,
                isOn: .constant(isOn),
                announce: .constant(.directAndMentions),
                networks: BeeperNetworkList(listed: listed, muted: muted),
                networkSwitch: { key in .constant(!muted.contains(key)) },
                hasToken: hasToken,
                tokenDraft: .constant(""),
                showReplaceToken: .constant(false),
                saveToken: {},
                addressDraft: .constant(address),
                saveAddress: {},
                readingLine: readingLine,
                readAnyway: app == .courier ? { key in .constant(readAnyway.contains(key)) } : nil,
                readAnywayKeys: readAnyway)
        }
        .formStyle(.grouped)
    }

    private let listed = [
        BeeperNetworkState(key: "whatsapp", name: "WhatsApp", state: .reading),
        BeeperNetworkState(key: "signal", name: "Signal", state: .muted),
        BeeperNetworkState(key: "slackgo", name: "Slack", state: .skipped),
    ]

    private func expectSensible(_ sizes: [NSSize], _ name: String) {
        XCTAssertEqual(sizes.count, 2, name)
        for size in sizes {
            XCTAssertGreaterThanOrEqual(size.width, 540, name)
            XCTAssertGreaterThan(size.height, 60, name)
            XCTAssertLessThan(size.height, 2000, name)
        }
    }

    /// Courier with no token: its switch greyed, the token field showing.
    func testCourierWithoutAToken() throws {
        expectSensible(try Snapshot.render("courier-no-token", width: 540) {
            section(.courier, isOn: false, hasToken: false)
        }, "courier-no-token")
    }

    /// Courier on, read, with its networks: one read, one muted, one left
    /// to Vitruvian Speaker's own Slack reader.
    func testCourierOn() throws {
        expectSensible(try Snapshot.render("courier-on", width: 540) {
            section(.courier, isOn: true, hasToken: true, listed: listed, muted: ["signal"],
                    readingLine: "Reading Courier: WhatsApp · Slack skipped (read directly)")
        }, "courier-on")
    }

    /// Courier's Slack switched on to be read through Courier as well.
    func testCourierSlackAlsoRead() throws {
        let states = [
            BeeperNetworkState(key: "whatsapp", name: "WhatsApp", state: .reading),
            BeeperNetworkState(key: "slack", name: "Slack", state: .reading),
        ]
        expectSensible(try Snapshot.render("courier-slack-also-read", width: 540) {
            section(.courier, isOn: true, hasToken: true, listed: states,
                    readingLine: "Reading Courier: Slack, WhatsApp", readAnyway: ["slack"])
        }, "courier-slack-also-read")
    }

    /// Courier on, not read yet, with an address that is not on this Mac.
    func testCourierWithABadAddress() throws {
        expectSensible(try Snapshot.render("courier-bad-address", width: 540) {
            section(.courier, isOn: true, hasToken: true, address: "http://example.com:23390")
        }, "courier-bad-address")
    }

    /// Beeper on, as before, with the new address row.
    func testBeeperOn() throws {
        expectSensible(try Snapshot.render("beeper-on", width: 540) {
            section(.beeper, isOn: true, hasToken: true, listed: listed, muted: ["signal"],
                    readingLine: "Reading Beeper: WhatsApp · Slack skipped (read directly)")
        }, "beeper-on")
    }

    /// Both, one after the other, as the Chats tab shows them.
    func testBothOff() throws {
        expectSensible(try Snapshot.render("both-off", width: 540) {
            Form {
                ChatAppSection(
                    app: .beeper, isOn: .constant(false), announce: .constant(.directAndMentions),
                    networks: BeeperNetworkList(listed: nil, muted: []), networkSwitch: { _ in .constant(true) },
                    hasToken: false, tokenDraft: .constant(""), showReplaceToken: .constant(false), saveToken: {},
                    addressDraft: .constant(""), saveAddress: {}, readingLine: nil)
                ChatAppSection(
                    app: .courier, isOn: .constant(false), announce: .constant(.directAndMentions),
                    networks: BeeperNetworkList(listed: nil, muted: []), networkSwitch: { _ in .constant(true) },
                    hasToken: true, tokenDraft: .constant(""), showReplaceToken: .constant(false), saveToken: {},
                    addressDraft: .constant(""), saveAddress: {}, readingLine: nil)
            }
            .formStyle(.grouped)
        }, "both-off")
    }
}
