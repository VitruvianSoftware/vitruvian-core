// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 VitruvianSoftware

import Foundation

/// What a tool said for its author to read: its standard error, its `log`
/// messages, and what the runtime noted about it. The newest is kept, up to
/// a number of bytes; the oldest goes first. Nothing here is ever shown to
/// the person as a message.
@MainActor
package final class ToolLog {
    package enum Source: Equatable, Sendable {
        /// The tool's standard error.
        case standardError
        /// A `log` message.
        case message
        /// The runtime: the tool started, stopped, or was stopped.
        case runtime
    }

    package struct Entry: Equatable, Sendable {
        package let source: Source
        package let text: String

        package init(source: Source, text: String) {
            self.source = source
            self.text = text
        }
    }

    private let limit: Int
    private var kept: [Entry] = []
    /// Entries before this one are dropped. Dropping moves it instead of
    /// the array, so a tool that logs a great many short lines costs the
    /// same for each.
    private var first = 0
    private var bytes = 0

    package init(limit: Int) {
        self.limit = max(0, limit)
    }

    package var entries: [Entry] { Array(kept[first...]) }

    /// Each entry on a line of its own.
    package var text: String { kept[first...].map(\.text).joined(separator: "\n") }

    package func add(_ text: String, from source: Source) {
        // One entry longer than everything the log may hold keeps its end.
        let text = text.utf8.count > limit ? String(decoding: Array(text.utf8.suffix(limit)), as: UTF8.self) : text
        kept.append(Entry(source: source, text: text))
        bytes += Self.cost(text)
        while bytes > limit, first < kept.count - 1 {
            bytes -= Self.cost(kept[first].text)
            first += 1
        }
        if first > 512, first > kept.count / 2 {
            kept.removeFirst(first)
            first = 0
        }
    }

    /// An entry costs its bytes and one more, so that empty ones still add up.
    private static func cost(_ text: String) -> Int { text.utf8.count + 1 }
}
