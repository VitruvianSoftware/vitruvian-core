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
//
// Shared by the standalone Nexus Agent app and the Nexus Agent feature of the
// Vitruvian desktop app. Written for Vitruvian and released under MIT by its
// copyright holder on 2026-10-09 (apps/desktop/vitruvian/UPSTREAM.md).


import Foundation

/// Turns `path/to/file.ext:123` in a reply into a link that opens the file.
///
/// What is linked: a path with a file extension, then `:line`, optionally
/// `:column`. Absolute paths and `~/` paths are always linked. A relative
/// path (`src/app.ts:4`, `./x.go:9`, `../y.py:1`) is linked only when the
/// conversation's working folder is known, and is resolved against it;
/// without one it is left as text, since a guess would open the wrong file.
/// A bare `name.ext:N` with no folder in it is linked too, unless its
/// extension reads as a web domain (`example.com:8080` is a host and port).
///
/// What is never touched: inline code spans, existing Markdown links and
/// `<autolinks>`, and anything inside a URL (`https://x:8080`). Times such
/// as `10:30` have no extension, so they never match.
///
/// The link is a `file://` URL with `#L<line>` (and `C<column>`) as its
/// fragment; the bubble opens the file and ignores the fragment.
public enum NexusAgentPathLinks {
    /// Spans the rewrite leaves alone: code spans, links, autolinks, URLs.
    nonisolated(unsafe) private static let protected = try! NSRegularExpression(
        pattern: #"(`+)[\s\S]*?\1(?!`)|!?\[[^\]\n]*\]\([^)\n]*\)|<[^>\s]+>|\b[A-Za-z][A-Za-z0-9+.-]*://[^\s<>()\[\]]+"#
    )

    nonisolated(unsafe) private static let candidate = try! NSRegularExpression(
        pattern: #"(?<![\w/.~:@+-])((?:~/|\.{1,2}/|/)?(?:[\w.@+-]+/)*[\w@+-][\w.@+-]*\.[A-Za-z][A-Za-z0-9]{0,9}):(\d+)(?::(\d+))?(?![\w:/]|\.\d)"#
    )

    /// Extensions that, on a name with no folder in it, mean a host name.
    static let domainExtensions: Set<String> = [
        "com", "net", "org", "io", "dev", "app", "ai", "co", "local", "lan", "internal", "localhost", "cloud", "me",
    ]

    /// The text with each such path rewritten as `[path:line](file://…#Lline)`.
    public static func linkify(_ text: String, workingDirectory: String?) -> String {
        guard text.contains(":") else { return text }
        let ns = text as NSString
        var result = ""
        var cursor = 0
        for match in protected.matches(in: text, range: NSRange(location: 0, length: ns.length)) {
            if match.range.location > cursor {
                result += rewrite(ns.substring(with: NSRange(location: cursor, length: match.range.location - cursor)),
                                  workingDirectory: workingDirectory)
            }
            result += ns.substring(with: match.range)
            cursor = match.range.location + match.range.length
        }
        if cursor < ns.length {
            result += rewrite(ns.substring(from: cursor), workingDirectory: workingDirectory)
        }
        return result
    }

    /// The file a path in a reply names, or nil when it cannot be placed.
    public static func resolve(_ path: String, workingDirectory: String?) -> String? {
        if path.hasPrefix("/") { return (path as NSString).standardizingPath }
        if path.hasPrefix("~/") { return (path as NSString).expandingTildeInPath }
        guard let workingDirectory, !workingDirectory.isEmpty else { return nil }
        let base = (workingDirectory as NSString).expandingTildeInPath
        return ((base as NSString).appendingPathComponent(path) as NSString).standardizingPath
    }

    private static func rewrite(_ segment: String, workingDirectory: String?) -> String {
        let ns = segment as NSString
        var result = ""
        var cursor = 0
        for match in candidate.matches(in: segment, range: NSRange(location: 0, length: ns.length)) {
            let path = ns.substring(with: match.range(at: 1))
            let line = ns.substring(with: match.range(at: 2))
            let column = match.range(at: 3).location == NSNotFound ? nil : ns.substring(with: match.range(at: 3))
            if !path.contains("/"), domainExtensions.contains((path as NSString).pathExtension.lowercased()) { continue }
            guard let file = resolve(path, workingDirectory: workingDirectory) else { continue }
            var fragment = "L\(line)"
            if let column { fragment += "C\(column)" }
            let url = URL(fileURLWithPath: file).absoluteString + "#" + fragment
            result += ns.substring(with: NSRange(location: cursor, length: match.range.location - cursor))
            result += "[\(ns.substring(with: match.range))](\(url))"
            cursor = match.range.location + match.range.length
        }
        result += ns.substring(from: cursor)
        return result
    }
}
