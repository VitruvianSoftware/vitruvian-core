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

/// What the user did to an Antigravity conversation. agy keeps it out of the
/// conversation index, in `annotations/<id>.pbtxt` (protobuf text) beside the
/// conversation, so the index's `killed` column says nothing about archiving:
/// it marks an aborted run. Lives in NexusAgentCore so it can be unit-tested.
public enum AntigravityAnnotations {
    /// agy's data folders under the home folder: the desktop app's, then the CLI's own.
    public static let dataDirectories = [".gemini/antigravity", ".gemini/antigravity-cli"]

    /// A quoted string, or the `archived` field. Strings are matched so a
    /// title cannot pass for the field.
    private static let archivedField = try? NSRegularExpression(
        pattern: #""(?:[^"\\]|\\.)*"|'(?:[^'\\]|\\.)*'|\barchived\s*:\s*(true|false)\b"#)

    /// Whether an annotation (`archived:true` or `archived: true`) marks its
    /// conversation archived.
    public static func isArchived(_ text: String) -> Bool {
        guard let archivedField else { return false }
        let values = archivedField.matches(in: text, range: NSRange(text.startIndex..., in: text))
            .compactMap { Range($0.range(at: 1), in: text).map { String(text[$0]) } }
        return values.last == "true"
    }

    /// The conversations marked archived in the `annotations` folder of each data directory.
    public static func archivedConversationIDs(in dataDirectories: [URL]) -> Set<String> {
        var archived = Set<String>()
        for directory in dataDirectories {
            let annotations = directory.appendingPathComponent("annotations")
            for name in (try? FileManager.default.contentsOfDirectory(atPath: annotations.path)) ?? []
            where name.hasSuffix(".pbtxt") {
                guard let text = try? String(contentsOf: annotations.appendingPathComponent(name), encoding: .utf8),
                      isArchived(text) else { continue }
                archived.insert(String(name.dropLast(".pbtxt".count)))
            }
        }
        return archived
    }
}
