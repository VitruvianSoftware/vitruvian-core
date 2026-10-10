// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 VitruvianSoftware

import AppKit
import UniformTypeIdentifiers
import VitruvianCore

/// What a tool wants done to a link somebody copied. The host asks these on
/// the clipboard lane, in the middle of one look at the clipboard, so each
/// takes plain values, answers at once and touches nothing else. Over a
/// process boundary each would be a question the host sends the tool and
/// waits for; here it is a function.
package struct ClipboardRewriteRule: Sendable {
    /// Asked first, with the names of the types on the clipboard and none
    /// of its content. False leaves the copy unread.
    package var readsText: @Sendable (_ types: [String]) -> Bool
    /// Asked with the text. What to put in its place, or nil to leave the
    /// copy as it is.
    package var replacement: @Sendable (_ text: String) -> ClipboardReplacement?
    /// Asked only when the copy also carries HTML, which the rewrite drops:
    /// whether dropping it loses nothing.
    package var dropsMarkup: @Sendable (_ html: String, _ text: String) -> Bool

    package init(readsText: @escaping @Sendable ([String]) -> Bool,
                 replacement: @escaping @Sendable (String) -> ClipboardReplacement?,
                 dropsMarkup: @escaping @Sendable (String, String) -> Bool) {
        self.readsText = readsText
        self.replacement = replacement
        self.dropsMarkup = dropsMarkup
    }
}

/// What a rule puts in place of a copied link.
package struct ClipboardReplacement: Equatable, Sendable {
    package let text: String
    /// Whatever the tool wants handed back with the result. The host does
    /// not read it.
    package let note: [String]

    package init(text: String, note: [String] = []) {
        self.text = text
        self.note = note
    }
}

/// What one look at the clipboard found.
package struct ClipboardPoll: Equatable, Sendable {
    /// The clipboard's change count: after the rewrite, when there was one.
    package let changeCount: Int
    /// What the copy was replaced with, or nil when it was left alone.
    package let replaced: ClipboardReplacement?

    package init(changeCount: Int, replaced: ClipboardReplacement?) {
        self.changeCount = changeCount
        self.replaced = replaced
    }
}

/// Calls off a look that is waiting on the lane, or running. `cancelled`
/// sits under `lock`, so it is `@unchecked Sendable`.
package final class ClipboardPollToken: @unchecked Sendable {
    private let lock = NSLock()
    private var cancelled = false

    package init() {}

    package func cancel() {
        lock.lock()
        cancelled = true
        lock.unlock()
    }

    package var isCancelled: Bool {
        lock.lock()
        defer { lock.unlock() }
        return cancelled
    }
}

/// One look at the clipboard, and the write that may follow it.
package enum ClipboardRewrite {
    private static let urlType = NSPasteboard.PasteboardType(UTType.url.identifier)

    /// Runs only on the clipboard lane. Reading the change count, the types
    /// and the content, asking the rule, and any rewrite are one job there,
    /// so nothing else that uses the lane sees the clipboard half way.
    /// Nil when the look was called off before it read anything.
    package static func poll(since sinceChangeCount: Int, token: ClipboardPollToken,
                             rule: ClipboardRewriteRule, pasteboard: NSPasteboard) -> ClipboardPoll? {
        let changeCount = pasteboard.changeCount
        guard !token.isCancelled else { return nil }
        guard changeCount != sinceChangeCount else {
            return ClipboardPoll(changeCount: changeCount, replaced: nil)
        }

        // The types decide before any content is read. Some "copy link"
        // commands put the link on the pasteboard only as a URL, with no
        // text next to it.
        let types = (pasteboard.types ?? []).map(\.rawValue)
        guard rule.readsText(types),
              // The rewrite writes one item, so a copy of several is left alone.
              pasteboard.pasteboardItems?.count == 1,
              let text = pasteboard.string(forType: .string) ?? pasteboard.string(forType: urlType),
              let replacement = rule.replacement(text),
              !token.isCancelled else {
            return ClipboardPoll(changeCount: changeCount, replaced: nil)
        }
        // The rewrite drops the HTML, so the rule is asked whether that
        // loses anything.
        if types.contains("public.html"),
           !rule.dropsMarkup(pasteboard.string(forType: .html) ?? "", text) {
            return ClipboardPoll(changeCount: changeCount, replaced: nil)
        }
        // Another app may have copied since the read. Nothing compares and
        // swaps across processes, so this narrows the window, not closes it.
        guard pasteboard.changeCount == changeCount else {
            return ClipboardPoll(changeCount: changeCount, replaced: nil)
        }

        // The app the copy named as its source stays named, and a copy from
        // another device stays marked as one, so the clipboard history does
        // not credit the rewritten link to the app in front.
        let rewrittenChangeCount = write(replacement.text, source: pasteboard.string(forType: .source),
                                         remote: types.contains("com.apple.is-remote-clipboard"),
                                         to: pasteboard)
        return ClipboardPoll(changeCount: rewrittenChangeCount, replaced: replacement)
    }

    /// Replaces the clipboard with a link, as text and as a URL, and
    /// answers with the change count after it.
    @discardableResult
    package static func write(_ link: String, source: String? = nil, remote: Bool = false,
                              to pasteboard: NSPasteboard) -> Int {
        pasteboard.clearContents()
        pasteboard.setString(link, forType: .string)
        pasteboard.setString(link, forType: urlType)
        if let source { pasteboard.setString(source, forType: .source) }
        if remote { pasteboard.setData(Data(), forType: .remoteClipboard) }
        return pasteboard.changeCount
    }
}
