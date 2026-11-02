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

/// The same message heard twice, once through Beeper and once through
/// Courier, while both are on (as they are while moving from one to the
/// other): the second to arrive is not spoken.
///
/// Ids cannot tell: each app numbers its messages and its chats its own
/// way, so the same WhatsApp message has two unrelated ids. What both
/// apps do agree on is what the person would hear. So a message is an
/// echo when one from the *other* app came over the same network, from
/// the same sender, with the same words (ignoring case and spacing), and
/// the times the network gave the two are within `window` of each other.
/// Each message heard answers for at most one echo: Alice sending "ok"
/// twice is spoken twice, once from each pair. Messages from one app are
/// never echoes of each other (each app's own ids already keep it from
/// passing one on twice), and Slack and Google Chat are never touched.
///
/// The cost of this choice: if one app missed a message the other passed
/// on, and the same sender sent the same words on the same network
/// within the window, that one is not spoken. A sender whose name the two
/// apps spell differently is spoken twice. Both are rare, and both are
/// gone once one app is switched off.
public struct ChatAppEchoes {
    /// How far apart the two copies' times may be. Both carry the time the
    /// network gave the message, so they normally agree to the second;
    /// two minutes allows for an app that only has the time it got it.
    public static let window: TimeInterval = 120

    private struct Heard {
        let fingerprint: String
        let source: IncomingMessage.Source
        let timestamp: Date
        var answered = false
    }

    private var heard: [Heard] = []

    public init() {}

    /// True when `message` is the other app's copy of one heard already,
    /// which it then answers for. False, and remembered, otherwise.
    public mutating func isEcho(_ message: IncomingMessage) -> Bool {
        guard message.source == .beeper || message.source == .courier else { return false }
        let print = Self.fingerprint(message)
        if let at = heard.firstIndex(where: {
            !$0.answered && $0.source != message.source && $0.fingerprint == print
                && abs($0.timestamp.timeIntervalSince(message.timestamp)) <= Self.window
        }) {
            heard[at].answered = true
            return true
        }
        heard.append(Heard(fingerprint: print, source: message.source, timestamp: message.timestamp))
        return false
    }

    /// Lets go of messages from before `date`: too old for a copy of them
    /// to still be read by either app.
    public mutating func forget(before date: Date) {
        heard.removeAll { $0.timestamp < date }
    }

    /// Network, sender and words, each lower case with its spacing tidied.
    static func fingerprint(_ message: IncomingMessage) -> String {
        let network = String((message.network ?? "").lowercased().unicodeScalars
            .filter { CharacterSet.alphanumerics.contains($0) }.map(Character.init))
        return [network, tidy(message.senderName), tidy(message.text)].joined(separator: "\u{1F}")
    }

    private static func tidy(_ text: String) -> String {
        text.lowercased().replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespaces)
    }
}
