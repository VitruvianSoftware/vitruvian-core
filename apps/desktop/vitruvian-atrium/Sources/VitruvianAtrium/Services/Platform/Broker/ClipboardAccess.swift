// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 VitruvianSoftware

import AppKit
import VitruvianCore

/// The clipboard capabilities: writing text, reading text, and rewriting a
/// copied link in place. Each operation checks its own capability.
@MainActor
package struct ClipboardAccess {
    package struct Backing {
        /// Replace the clipboard with `text`, then say on the main thread
        /// whether it took.
        package var write: (_ text: String, _ completion: @escaping @MainActor (Bool) -> Void) -> Void
        /// The clipboard, its lane and its timer, for reading, for writing
        /// a link and for the watch.
        package var watching: ClipboardWatcher.Environment

        package init(write: @escaping (String, @escaping @MainActor (Bool) -> Void) -> Void,
                     watching: ClipboardWatcher.Environment = .inert) {
            self.write = write
            self.watching = watching
        }

        @MainActor package static let live = Backing(write: { text, completion in
            GeneralPasteboardAccess.shared.async({
                NSPasteboard.general.clearContents()
                NSPasteboard.general.declareVitruvianSource()
                return NSPasteboard.general.setString(text, forType: .string)
            }, then: { copied in
                completion(copied)
            })
        }, watching: .live)
    }

    let gate: (Capability) -> BrokerRefusal?
    let backing: Backing
    let watcher: ClipboardWatcher
    let tool: ToolID

    /// Replaces the clipboard with `text`. `completion` hears whether it
    /// took; it is not called when the call is refused.
    @discardableResult
    package func write(_ text: String, completion: @escaping @MainActor (Bool) -> Void = { _ in }) -> BrokerRefusal? {
        if let refusal = gate(.clipboardWrite) { return refusal }
        backing.write(text, completion)
        return nil
    }

    /// Replaces the clipboard with a link the tool made: as text and as a
    /// URL, signed as the app's own. The tool's watch, when it has one,
    /// does not take the write for a new copy. `completion` is called once
    /// the write is done, and not when the call is refused.
    @discardableResult
    package func writeLink(_ link: String, completion: @escaping @MainActor () -> Void = {}) -> BrokerRefusal? {
        if let refusal = gate(.clipboardWrite) { return refusal }
        watcher.writeLink(link, by: tool, completion: completion)
        return nil
    }

    /// Reads the clipboard's text. `completion` hears it on the main
    /// thread, nil when there is none; it is not called when the call is
    /// refused.
    @discardableResult
    package func readText(completion: @escaping @MainActor (String?) -> Void) -> BrokerRefusal? {
        if let refusal = gate(.clipboardRead) { return refusal }
        watcher.readText(completion: completion)
        return nil
    }

    /// Reads the clipboard's text without its formatting: the plain string,
    /// else the words of its rich text. `completion` hears it on the main
    /// thread, nil when there is none; it is not called when the call is
    /// refused.
    @discardableResult
    package func readPlainText(completion: @escaping @MainActor (String?) -> Void) -> BrokerRefusal? {
        if let refusal = gate(.clipboardRead) { return refusal }
        watcher.readPlainText(completion: completion)
        return nil
    }

    /// Watches the clipboard and, each time somebody copies, asks `rule`
    /// whether to put something in the copy's place. The whole look (read,
    /// ask, check the copy is still the one read, write) is one job on the
    /// clipboard lane. `onRewrite` hears each replacement on the main
    /// thread. It reads what it rewrites, so it needs both capabilities.
    @discardableResult
    package func rewriteLinks(rule: ClipboardRewriteRule,
                              onRewrite: @escaping @MainActor (ClipboardReplacement) -> Void) -> BrokerRefusal? {
        if let refusal = gate(.clipboardRewrite) ?? gate(.clipboardRead) { return refusal }
        watcher.start(for: tool, rule: rule, onRewrite: onRewrite)
        return nil
    }

    /// Stops the watch `rewriteLinks` started. Never refused: a tool that
    /// was removed in the hub must still be able to stop.
    package func stopRewritingLinks() {
        watcher.stop(for: tool)
    }
}
