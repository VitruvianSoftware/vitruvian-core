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

import Foundation

/// The limits that belong to the link itself.
public enum WireLimits {
    /// The longest line either side may send, in bytes, not counting the
    /// line break that ends it: 1 MB.
    public static let maxLineBytes = 1_048_576
}

/// One message per line: how a message becomes bytes on the link, and back.
public enum LineFraming {
    /// A message too long to send.
    public struct LineTooLong: Error, Equatable, Sendable {
        public let bytes: Int

        public init(bytes: Int) {
            self.bytes = bytes
        }
    }

    /// The message as one line of UTF-8, ending with its line break. The
    /// line never holds a line break of its own: JSON writes one inside a
    /// string as `\n`.
    public static func line(for message: RPCMessage) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        var line = try encoder.encode(message)
        guard line.count <= WireLimits.maxLineBytes else { throw LineTooLong(bytes: line.count) }
        line.append(0x0A)
        return line
    }

    /// Reads one line, without its line break, as a message. Throws when the
    /// line is not a JSON-RPC 2.0 message.
    public static func message(from line: Data) throws -> RPCMessage {
        try JSONDecoder().decode(RPCMessage.self, from: line)
    }
}

/// Cuts a stream of bytes into lines. Bytes arrive in pieces of any size; a
/// line is given out once its line break has arrived. It never holds more
/// than `limit` bytes, however long a line the other side sends.
public struct LineSplitter: Sendable {
    public enum Piece: Equatable, Sendable {
        /// One line, without its line break. Never empty or only spaces.
        case line(Data)
        /// A line went over the limit. Given out once, as soon as it is
        /// known; the rest of that line is thrown away.
        case oversized
    }

    public let limit: Int
    private var pending = Data()
    private var discarding = false

    public init(limit: Int = WireLimits.maxLineBytes) {
        self.limit = limit
    }

    public mutating func append(_ bytes: Data) -> [Piece] {
        var pieces: [Piece] = []
        var rest = bytes[bytes.startIndex...]
        while let lineBreak = rest.firstIndex(of: 0x0A) {
            let head = rest[rest.startIndex..<lineBreak]
            rest = rest[rest.index(after: lineBreak)...]
            if discarding {
                discarding = false
            } else if pending.count + head.count > limit {
                pieces.append(.oversized)
            } else {
                pending.append(head)
                if !pending.allSatisfy(Self.isBlank) { pieces.append(.line(pending)) }
            }
            pending = Data()
        }
        guard !discarding else { return pieces }
        if pending.count + rest.count > limit {
            pending = Data()
            discarding = true
            pieces.append(.oversized)
        } else {
            pending.append(rest)
        }
        return pieces
    }

    private static func isBlank(_ byte: UInt8) -> Bool {
        byte == 0x20 || byte == 0x09 || byte == 0x0D
    }
}
