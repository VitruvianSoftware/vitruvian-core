// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import AppKit
import CoreGraphics
import Foundation
import VitruvianCore
import VitruvianServices

/// Runs the production paste and restore sequence on a private pasteboard,
/// read on the main queue as the test reads it. Held modifiers and the posted
/// Command-V are the rig's; no system keys are posted.
enum TransientPasteTests {
    final class Rig {
        let pasteboard = NSPasteboard(name: NSPasteboard.Name("VitruvianTransientPasteTests-" + UUID().uuidString))
        var held: CGEventFlags = []
        /// What the pasteboard held as each Command-V went down.
        var inserted: [String] = []
        var keyUps = 0

        var environment: TransientPaste.Environment {
            // Read on the lane, which this rig runs on the main queue.
            nonisolated(unsafe) let board = pasteboard
            return TransientPaste.Environment(
                pasteboard: { board },
                lane: GeneralPasteboardAccess(label: "test.transient-paste", queue: .main),
                heldModifiers: { [unowned self] in self.held },
                commandV: { [unowned self] in
                    ({ self.inserted.append(self.pasteboard.string(forType: .string) ?? "") },
                     { self.keyUps += 1 })
                },
                ignoreHistory: { _ in })
        }
    }

    final class PromisedImage: NSObject, NSPasteboardItemDataProvider {
        var reads = 0
        func pasteboard(_ pasteboard: NSPasteboard?, item: NSPasteboardItem,
                        provideDataForType type: NSPasteboard.PasteboardType) {
            reads += 1
            item.setData(Data([1, 2, 3]), forType: type)
        }
    }

    private static func pump(until condition: () -> Bool) {
        let deadline = Date(timeIntervalSinceNow: 3)
        while !condition(), Date() < deadline {
            RunLoop.current.run(until: Date(timeIntervalSinceNow: 0.005))
        }
    }

    static func run(_ suite: TestSuite) {
        let rig = Rig()
        let pasteboard = rig.pasteboard
        defer { pasteboard.releaseGlobally() }
        let host = TransientPaste(environment: rig.environment)
        let rich = Data("{\\rtf1 original}".utf8)
        func reset() {
            rig.inserted = []
            rig.keyUps = 0
            rig.held = .maskCommand
            pasteboard.clearContents()
            pasteboard.setString("original", forType: .string)
            pasteboard.setData(rich, forType: .rtf)
        }

        reset()
        var before = 0, posted = 0, failed = 0
        suite.expect(host.paste("requested", willPostShortcut: { before += 1 },
                                didPostShortcut: { posted += 1 }, didFail: { failed += 1 }),
                     "the first paste is admitted")
        suite.expect(!host.paste("second"), "a pending paste rejects another insertion")
        pump { pasteboard.string(forType: .string) == "requested" }
        pasteboard.clearContents()
        pasteboard.setString("new copy", forType: .string)
        rig.held = []
        pump { posted + failed == 1 }
        suite.expect(rig.inserted.isEmpty && rig.keyUps == 0,
                     "a copy made while modifiers are held cancels both synthetic paste keys")
        suite.expect(before == 0 && posted == 0 && failed == 1,
                     "cancellation reports failure once without deleting a snippet trigger")
        RunLoop.current.run(until: Date(timeIntervalSinceNow: 0.6))
        suite.expect(pasteboard.string(forType: .string) == "new copy",
                     "a cancelled paste does not restore over the newer copy")

        reset()
        before = 0; posted = 0; failed = 0
        suite.expect(host.paste("requested", willPostShortcut: { before += 1 },
                                didPostShortcut: { posted += 1 }, didFail: { failed += 1 }),
                     "cancellation releases the paste admission flag")
        pump { pasteboard.string(forType: .string) == "requested" }
        rig.held = []
        pump { posted + failed == 1 }
        suite.expect(rig.inserted == ["requested"] && rig.keyUps == 1,
                     "an unchanged pasteboard delivers the requested text and a balanced key pair")
        suite.expect(before == 1 && posted == 1 && failed == 0,
                     "a successful paste invokes its callbacks once")
        pump { pasteboard.string(forType: .string) == "original" }
        suite.expect(pasteboard.string(forType: .string) == "original"
                        && pasteboard.data(forType: .rtf) == rich,
                     "a successful paste restores the original clipboard, rich text included")

        reset()
        posted = 0; failed = 0
        suite.expect(host.paste("requested", didPostShortcut: { posted += 1 }, didFail: { failed += 1 }),
                     "another normal paste is admitted")
        pump { pasteboard.string(forType: .string) == "requested" }
        rig.held = []
        pump { posted == 1 }
        pasteboard.clearContents()
        pasteboard.setString("copy after paste", forType: .string)
        RunLoop.current.run(until: Date(timeIntervalSinceNow: 0.6))
        suite.expect(rig.inserted == ["requested"] && failed == 0
                     && pasteboard.string(forType: .string) == "copy after paste",
                     "a copy after delivery is preserved by the existing restore guard")

        reset()
        let provider = PromisedImage()
        let item = NSPasteboardItem()
        item.setDataProvider(provider, forTypes: [.png])
        pasteboard.clearContents()
        pasteboard.writeObjects([item])
        let originalCount = pasteboard.changeCount
        before = 0; posted = 0; failed = 0
        suite.expect(host.pasteCurrentContents(willPostShortcut: { before += 1 },
                                               didPostShortcut: { posted += 1 },
                                               didFail: { failed += 1 }),
                     "promised media can use the shared paste path")
        rig.held = []
        pump { posted + failed == 1 }
        suite.expect(before == 1 && posted == 1 && failed == 0 && rig.keyUps == 1,
                     "unchanged media forwards a balanced paste without conversion")
        suite.expect(provider.reads == 0 && pasteboard.changeCount == originalCount,
                     "media forwarding neither reads promised bytes nor changes the pasteboard")

        reset()
        before = 0; posted = 0; failed = 0
        suite.expect(host.pasteCurrentContents(willPostShortcut: { before += 1 },
                                               didPostShortcut: { posted += 1 },
                                               didFail: { failed += 1 }),
                     "forwarding releases admission after completion")
        // The count it forwards against is read on the lane first.
        RunLoop.current.run(until: Date(timeIntervalSinceNow: 0.05))
        pasteboard.clearContents()
        pasteboard.setString("new media copy", forType: .string)
        rig.held = []
        pump { posted + failed == 1 }
        suite.expect(before == 0 && posted == 0 && failed == 1
                     && rig.inserted.isEmpty && rig.keyUps == 0,
                     "a copy during forwarding cancels before callbacks or synthetic keys")
        suite.expect(pasteboard.string(forType: .string) == "new media copy",
                     "cancelled forwarding preserves the newer clipboard")
    }
}
