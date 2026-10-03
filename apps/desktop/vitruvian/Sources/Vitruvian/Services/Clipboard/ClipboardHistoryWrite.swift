// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import AppKit
import VitruvianCore
import VitruvianDesign

package protocol ClipboardHistoryPasteboard {
    func clearContents() -> Int
    var changeCount: Int { get }
    func setString(_ string: String, forType type: NSPasteboard.PasteboardType) -> Bool
    func setData(_ data: Data?, forType type: NSPasteboard.PasteboardType) -> Bool
    func writeObjects(_ objects: [NSPasteboardWriting]) -> Bool
}

extension NSPasteboard: ClipboardHistoryPasteboard {}

package struct ClipboardHistoryWriteResult {
    package let succeeded: Bool
    package let changeCount: Int

    // Spelled out because a memberwise initializer never leaves its module.
    package init(succeeded: Bool, changeCount: Int) {
        self.succeeded = succeeded
        self.changeCount = changeCount
    }
}

package enum ClipboardHistoryWrite {
    case text(String)
    case image(png: Data, tiff: Data?)
    case files([NSURL])
    case rich(NSAttributedString, plain: String)

    /// Expiry stops subsequent writes. Once cleared, always read the final
    /// change count so history can exclude our mutation, even after timeout.
    /// A call in progress cannot be cancelled or a partial write undone.
    package func write(to pasteboard: any ClipboardHistoryPasteboard,
               isExpired: () -> Bool) -> ClipboardHistoryWriteResult? {
        guard !isExpired() else { return nil }
        _ = pasteboard.clearContents()

        var succeeded = false
        if !isExpired() {
            switch self {
            case let .text(text):
                succeeded = pasteboard.setString(text, forType: .string)
            case let .image(png, tiff):
                succeeded = pasteboard.setData(png, forType: .png)
                if succeeded, let tiff, !isExpired() {
                    _ = pasteboard.setData(tiff, forType: .tiff)
                }
            case let .files(urls):
                succeeded = pasteboard.writeObjects(urls)
            case let .rich(rich, plain):
                succeeded = pasteboard.writeObjects([rich])
                if succeeded, !plain.isEmpty, !isExpired() {
                    _ = pasteboard.setString(plain, forType: .string)
                }
            }
        }

        let changeCount = pasteboard.changeCount
        return ClipboardHistoryWriteResult(succeeded: !isExpired() && succeeded,
                                           changeCount: changeCount)
    }
}
