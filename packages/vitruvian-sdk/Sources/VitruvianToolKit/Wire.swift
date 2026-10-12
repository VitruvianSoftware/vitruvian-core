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
import VitruvianToolProtocol

/// The link to the app, from the tool's end: messages read from one file
/// descriptor and written to another, a line each.
///
/// It is used from one thread. Reading waits, with `poll`, until a message
/// has come, the link has ended, or the time given has passed. It never
/// waits longer than it is told to.
struct Wire {
    enum Next: Equatable {
        case message(RPCMessage)
        /// The other side closed the link, or it broke.
        case ended
        /// The time given passed first.
        case late
    }

    private let input: Int32
    private let output: Int32
    private var splitter = LineSplitter()
    private var lines: [Data] = []
    private(set) var ended = false

    init(input: Int32, output: Int32) {
        self.input = input
        self.output = output
    }

    /// Seconds since the Mac started: a clock nobody can set.
    static var now: TimeInterval { ProcessInfo.processInfo.systemUptime }

    /// The next message. With `deadline` nil it waits for as long as the
    /// link is open. A line that is not a message, and a line over 1 MB,
    /// are dropped: there is no request to answer.
    mutating func next(before deadline: TimeInterval?) -> Next {
        while true {
            while !lines.isEmpty {
                if let message = try? LineFraming.message(from: lines.removeFirst()) { return .message(message) }
            }
            if ended { return .ended }
            var wait: Int32 = -1
            if let deadline {
                let left = deadline - Self.now
                if left <= 0 { return .late }
                wait = Int32(min((left * 1000).rounded(.up), 3_600_000))
            }
            var waiting = pollfd(fd: input, events: Int16(POLLIN), revents: 0)
            let ready = poll(&waiting, 1, wait)
            if ready == 0 { continue }
            if ready < 0 {
                if errno != EINTR { ended = true }
                continue
            }
            var buffer = [UInt8](repeating: 0, count: 65_536)
            let count = read(input, &buffer, buffer.count)
            if count < 0, errno == EINTR { continue }
            guard count > 0 else {
                ended = true
                continue
            }
            for case .line(let line) in splitter.append(Data(buffer[0..<count])) { lines.append(line) }
        }
    }

    /// Writes one message as one line. False when it could not be written;
    /// the link has then ended.
    @discardableResult
    mutating func send(_ message: RPCMessage) -> Bool {
        guard !ended, let line = try? LineFraming.line(for: message) else { return false }
        var sent = 0
        let bytes = [UInt8](line)
        while sent < bytes.count {
            let count = bytes[sent...].withUnsafeBytes { write(output, $0.baseAddress, $0.count) }
            if count < 0, errno == EINTR { continue }
            guard count > 0 else {
                ended = true
                return false
            }
            sent += count
        }
        return true
    }
}
