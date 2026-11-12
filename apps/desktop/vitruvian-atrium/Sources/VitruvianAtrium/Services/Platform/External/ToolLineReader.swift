// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 VitruvianSoftware

import Foundation
import VitruvianToolProtocol

/// One thing a tool wrote on its standard output.
package enum ToolInbound: Equatable, Sendable {
    case message(RPCMessage)
    /// A line that is not a JSON-RPC 2.0 message.
    case notAMessage
    /// A line longer than the protocol allows. Given once for that line;
    /// the rest of the line is never held.
    case tooLong
}

/// Turns the bytes a tool writes into messages.
///
/// It is a plain value that belongs to no actor. Whoever reads the tool's
/// output runs it where the bytes arrive, off the main thread, so that
/// taking a message apart costs the main thread nothing.
///
/// A last line with no line break is never given out: the protocol says a
/// message ends with one, and when a tool's output ends its link is over
/// anyway. So there is nothing to flush, and no `finish`.
package struct ToolLineReader: Sendable {
    private var splitter: LineSplitter

    package init(limit: Int = WireLimits.maxLineBytes) {
        splitter = LineSplitter(limit: limit)
    }

    /// What `bytes` completes, in order. Bytes after the last line break
    /// are kept for the next call.
    package mutating func read(_ bytes: Data) -> [ToolInbound] {
        splitter.append(bytes).map { piece in
            switch piece {
            case .oversized:
                return .tooLong
            case .line(let line):
                guard let message = try? LineFraming.message(from: line) else { return .notAMessage }
                return .message(message)
            }
        }
    }
}
