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

import Combine
import CoreGraphics
import Foundation

// MARK: - Annotate AI Diffs

/// A single line inside a unified diff hunk.
public struct NexusAgentDiffLine: Identifiable, Equatable, Sendable {
    public enum Kind: String, Equatable, Sendable, Codable {
        case context
        case addition
        case deletion
        case header
    }

    public let id: String
    public let kind: Kind
    public let oldLineNumber: Int?
    public let newLineNumber: Int?
    public let content: String

    public init(
        id: String,
        kind: Kind,
        oldLineNumber: Int? = nil,
        newLineNumber: Int? = nil,
        content: String
    ) {
        self.id = id
        self.kind = kind
        self.oldLineNumber = oldLineNumber
        self.newLineNumber = newLineNumber
        self.content = content
    }

    /// The primary line number used for anchoring review comments (prefers new line number).
    public var anchorLineNumber: Int? {
        newLineNumber ?? oldLineNumber
    }
}

/// A contiguous hunk in a unified diff.
public struct NexusAgentDiffHunk: Identifiable, Equatable, Sendable {
    public let id: String
    public let header: String
    public let lines: [NexusAgentDiffLine]

    public init(id: String, header: String, lines: [NexusAgentDiffLine]) {
        self.id = id
        self.header = header
        self.lines = lines
    }
}

/// A single file's parsed unified diff, with hunk breakdown and +/- counts.
public struct NexusAgentDiffFile: Identifiable, Equatable, Sendable {
    public let id: String
    public let oldPath: String
    public let newPath: String
    public let hunks: [NexusAgentDiffHunk]
    public let addedCount: Int
    public let removedCount: Int

    public init(
        id: String,
        oldPath: String,
        newPath: String,
        hunks: [NexusAgentDiffHunk],
        addedCount: Int,
        removedCount: Int
    ) {
        self.id = id
        self.oldPath = oldPath
        self.newPath = newPath
        self.hunks = hunks
        self.addedCount = addedCount
        self.removedCount = removedCount
    }

    /// Display path preferring `newPath` unless the file was deleted (`/dev/null`).
    public var displayPath: String {
        if newPath == "/dev/null" || newPath.isEmpty {
            return oldPath
        }
        return newPath
    }
}

/// Pure static parser for standard unified `git diff` output.
public enum NexusAgentDiffParser: Sendable {
    public static func parseUnifiedDiff(_ rawDiff: String) -> [NexusAgentDiffFile] {
        let normalized = rawDiff.replacingOccurrences(of: "\r\n", with: "\n")
        let rawLines = normalized.components(separatedBy: "\n")

        var files: [NexusAgentDiffFile] = []
        var currentOldPath: String?
        var currentNewPath: String?
        var currentHunks: [NexusAgentDiffHunk] = []
        var currentHunkHeader: String?
        var currentHunkLines: [NexusAgentDiffLine] = []
        var currentAdded = 0
        var currentRemoved = 0
        var oldLine = 0
        var newLine = 0
        var hunkIndex = 0
        var lineIndex = 0

        func flushHunk(forFileID fileID: String) {
            guard let header = currentHunkHeader else { return }
            let hunkID = "\(fileID)#hunk-\(hunkIndex)"
            currentHunks.append(
                NexusAgentDiffHunk(
                    id: hunkID,
                    header: header,
                    lines: currentHunkLines
                )
            )
            hunkIndex += 1
            currentHunkHeader = nil
            currentHunkLines = []
        }

        func flushFile() {
            guard currentOldPath != nil || currentNewPath != nil || !currentHunks.isEmpty || currentHunkHeader != nil else {
                return
            }
            let resolvedOld = currentOldPath ?? ""
            let resolvedNew = currentNewPath ?? resolvedOld
            let fileID = (!resolvedNew.isEmpty && resolvedNew != "/dev/null") ? resolvedNew : resolvedOld
            guard !fileID.isEmpty else { return }

            flushHunk(forFileID: fileID)

            files.append(
                NexusAgentDiffFile(
                    id: fileID,
                    oldPath: resolvedOld,
                    newPath: resolvedNew,
                    hunks: currentHunks,
                    addedCount: currentAdded,
                    removedCount: currentRemoved
                )
            )
            currentOldPath = nil
            currentNewPath = nil
            currentHunks = []
            currentHunkHeader = nil
            currentHunkLines = []
            currentAdded = 0
            currentRemoved = 0
            hunkIndex = 0
            lineIndex = 0
        }

        for line in rawLines {
            if line.hasPrefix("diff --git ") {
                flushFile()
                let rest = String(line.dropFirst("diff --git ".count))
                if let range = rest.range(of: " b/", options: .backwards) ?? rest.range(of: " \"b/", options: .backwards) {
                    let left = String(rest[..<range.lowerBound]).trimmingCharacters(in: .whitespaces)
                    let right = String(rest[range.lowerBound...]).trimmingCharacters(in: .whitespaces)
                    currentOldPath = stripDiffPrefix(left)
                    currentNewPath = stripDiffPrefix(right)
                } else {
                    let parts = rest.components(separatedBy: " ")
                    if parts.count >= 2 {
                        currentOldPath = stripDiffPrefix(parts[0])
                        currentNewPath = stripDiffPrefix(parts[1])
                    }
                }
                continue
            }

            if line.hasPrefix("--- ") {
                if currentHunkHeader != nil {
                    flushFile()
                }
                let pathPart = String(line.dropFirst(4)).trimmingCharacters(in: .whitespaces)
                currentOldPath = stripDiffPrefix(pathPart)
                continue
            }

            if line.hasPrefix("+++ ") && currentHunkHeader == nil {
                let pathPart = String(line.dropFirst(4)).trimmingCharacters(in: .whitespaces)
                currentNewPath = stripDiffPrefix(pathPart)
                continue
            }

            if line.hasPrefix("@@ ") {
                let fileID = currentNewPath ?? currentOldPath ?? "file-\(files.count)"
                flushHunk(forFileID: fileID)
                currentHunkHeader = line
                if let (parsedOld, parsedNew) = parseHunkCoordinates(line) {
                    oldLine = parsedOld
                    newLine = parsedNew
                } else {
                    oldLine = 1
                    newLine = 1
                }
                lineIndex += 1
                currentHunkLines.append(
                    NexusAgentDiffLine(
                        id: "\(fileID):h\(hunkIndex):l\(lineIndex)",
                        kind: .header,
                        oldLineNumber: nil,
                        newLineNumber: nil,
                        content: line
                    )
                )
                continue
            }

            guard currentHunkHeader != nil else {
                continue
            }

            let fileID = currentNewPath ?? currentOldPath ?? "file-\(files.count)"
            lineIndex += 1
            if line.hasPrefix("+") {
                let content = String(line.dropFirst())
                currentHunkLines.append(
                    NexusAgentDiffLine(
                        id: "\(fileID):h\(hunkIndex):l\(lineIndex)",
                        kind: .addition,
                        oldLineNumber: nil,
                        newLineNumber: newLine,
                        content: content
                    )
                )
                newLine += 1
                currentAdded += 1
            } else if line.hasPrefix("-") {
                let content = String(line.dropFirst())
                currentHunkLines.append(
                    NexusAgentDiffLine(
                        id: "\(fileID):h\(hunkIndex):l\(lineIndex)",
                        kind: .deletion,
                        oldLineNumber: oldLine,
                        newLineNumber: nil,
                        content: content
                    )
                )
                oldLine += 1
                currentRemoved += 1
            } else if line.hasPrefix(" ") {
                let content = String(line.dropFirst())
                currentHunkLines.append(
                    NexusAgentDiffLine(
                        id: "\(fileID):h\(hunkIndex):l\(lineIndex)",
                        kind: .context,
                        oldLineNumber: oldLine,
                        newLineNumber: newLine,
                        content: content
                    )
                )
                oldLine += 1
                newLine += 1
            } else if line.hasPrefix("\\ No newline at end of file") {
                continue
            }
        }

        flushFile()
        return files
    }

    private static func stripDiffPrefix(_ rawPath: String) -> String {
        var trimmed = (rawPath.components(separatedBy: "\t").first ?? rawPath)
            .trimmingCharacters(in: .whitespaces)
        if trimmed.count >= 2, trimmed.hasPrefix("\""), trimmed.hasSuffix("\"") {
            trimmed = String(trimmed.dropFirst().dropLast())
        }
        if trimmed == "/dev/null" {
            return trimmed
        }
        if trimmed.hasPrefix("a/") || trimmed.hasPrefix("b/") {
            return String(trimmed.dropFirst(2))
        }
        return trimmed
    }

    private static func parseHunkCoordinates(_ header: String) -> (oldStart: Int, newStart: Int)? {
        guard let firstAt = header.range(of: "@@ "),
              let secondAt = header.range(of: " @@", range: firstAt.upperBound..<header.endIndex) else {
            return nil
        }
        let coords = header[firstAt.upperBound..<secondAt.lowerBound]
        let tokens = coords.split(separator: " ")
        guard tokens.count >= 2 else { return nil }

        func parseStart(_ token: Substring) -> Int? {
            let stripped = token.dropFirst()
            let numberPart = stripped.split(separator: ",").first ?? stripped
            return Int(numberPart)
        }

        guard let oldStart = parseStart(tokens[0]),
              let newStart = parseStart(tokens[1]) else {
            return nil
        }
        return (oldStart, newStart)
    }
}

/// A line-anchored review comment attached to a diff range.
public struct NexusAgentDiffAnnotation: Identifiable, Equatable, Sendable, Codable {
    public let id: UUID
    public var filePath: String
    public var lineID: String?
    public var startLine: Int
    public var endLine: Int
    public var lineSnippet: String
    public var commentMarkdown: String
    public var isResolved: Bool
    public var createdAt: Date

    public init(
        id: UUID = UUID(),
        filePath: String,
        lineID: String? = nil,
        startLine: Int,
        endLine: Int,
        lineSnippet: String,
        commentMarkdown: String,
        isResolved: Bool = false,
        createdAt: Date = Date()
    ) {
        self.id = id
        self.filePath = filePath
        self.lineID = lineID
        self.startLine = min(startLine, endLine)
        self.endLine = max(startLine, endLine)
        self.lineSnippet = lineSnippet
        self.commentMarkdown = commentMarkdown
        self.isResolved = isResolved
        self.createdAt = createdAt
    }
}

/// Observable review session holding parsed diff files and line-anchored annotations.
@MainActor
public final class NexusAgentDiffReviewSession: ObservableObject {
    @Published public private(set) var files: [NexusAgentDiffFile]
    @Published public private(set) var annotations: [NexusAgentDiffAnnotation]

    public init(
        files: [NexusAgentDiffFile] = [],
        annotations: [NexusAgentDiffAnnotation] = []
    ) {
        self.files = files
        self.annotations = annotations
    }

    public func loadDiff(_ rawDiff: String) {
        self.files = NexusAgentDiffParser.parseUnifiedDiff(rawDiff)
    }

    @discardableResult
    public func addAnnotation(
        filePath: String,
        lineID: String? = nil,
        startLine: Int,
        endLine: Int,
        lineSnippet: String,
        commentMarkdown: String
    ) -> NexusAgentDiffAnnotation {
        let trimmedComment = commentMarkdown.trimmingCharacters(in: .whitespacesAndNewlines)
        let annotation = NexusAgentDiffAnnotation(
            filePath: filePath,
            lineID: lineID,
            startLine: startLine,
            endLine: endLine,
            lineSnippet: lineSnippet,
            commentMarkdown: trimmedComment
        )
        annotations.append(annotation)
        return annotation
    }

    public func updateAnnotation(id: UUID, commentMarkdown: String) {
        guard let index = annotations.firstIndex(where: { $0.id == id }) else { return }
        annotations[index].commentMarkdown = commentMarkdown.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    public func toggleResolved(id: UUID) {
        guard let index = annotations.firstIndex(where: { $0.id == id }) else { return }
        annotations[index].isResolved.toggle()
    }

    public func removeAnnotation(id: UUID) {
        annotations.removeAll { $0.id == id }
    }

    public var unresolvedAnnotations: [NexusAgentDiffAnnotation] {
        annotations.filter { !$0.isResolved && !$0.commentMarkdown.isEmpty }
    }

    /// Formats all unresolved line-anchored comments grouped by file into a single coherent markdown prompt.
    public func composeReviewBatchPrompt() -> String? {
        let pending = unresolvedAnnotations
        guard !pending.isEmpty else { return nil }

        var groupedOrder: [String] = []
        var groupedMap: [String: [NexusAgentDiffAnnotation]] = [:]
        for item in pending {
            if groupedMap[item.filePath] == nil {
                groupedOrder.append(item.filePath)
                groupedMap[item.filePath] = []
            }
            groupedMap[item.filePath]?.append(item)
        }

        var lines: [String] = [
            "Please address the following code review annotations on the current diff:",
            ""
        ]

        for filePath in groupedOrder {
            lines.append("### `\(filePath)`")
            let items = (groupedMap[filePath] ?? []).sorted {
                if $0.startLine != $1.startLine { return $0.startLine < $1.startLine }
                return $0.endLine < $1.endLine
            }
            for item in items {
                let lineLabel = item.startLine == item.endLine
                    ? "Line \(item.startLine)"
                    : "Lines \(item.startLine)-\(item.endLine)"
                lines.append("- **\(lineLabel)**: \(item.commentMarkdown)")
                let snippet = item.lineSnippet.trimmingCharacters(in: .newlines)
                if !snippet.isEmpty {
                    lines.append("  ```")
                    for snippetLine in snippet.components(separatedBy: "\n") {
                        lines.append("  \(snippetLine)")
                    }
                    lines.append("  ```")
                }
            }
            lines.append("")
        }

        return lines.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

// MARK: - Design Mode (Point-and-Click DOM Inspector to Prompt)

/// Metadata and styling captured when a user clicks a DOM element in Design Mode.
public struct NexusAgentDesignElementCapture: Identifiable, Equatable, Sendable, Codable {
    public let id: UUID
    public var pageURL: String
    public var tagName: String
    public var cssSelector: String
    public var outerHTMLSnippet: String
    public var computedStyles: [String: String]
    public var boundingBox: CGRect
    public var sourceLocation: String?
    public var userIntentNote: String
    public var screenshotPNGData: Data?

    public init(
        id: UUID = UUID(),
        pageURL: String,
        tagName: String,
        cssSelector: String,
        outerHTMLSnippet: String,
        computedStyles: [String: String] = [:],
        boundingBox: CGRect = .zero,
        sourceLocation: String? = nil,
        userIntentNote: String = "",
        screenshotPNGData: Data? = nil
    ) {
        self.id = id
        self.pageURL = pageURL
        self.tagName = tagName
        self.cssSelector = cssSelector
        self.outerHTMLSnippet = outerHTMLSnippet
        self.computedStyles = computedStyles
        self.boundingBox = boundingBox
        self.sourceLocation = sourceLocation
        self.userIntentNote = userIntentNote
        self.screenshotPNGData = screenshotPNGData
    }
}

/// JavaScript bridge and prompt formatter for WKWebView Design Mode inspection.
public enum NexusAgentDesignModeScript: Sendable {
    public static let messageHandlerName = "nexusDesignMode"

    /// JavaScript injected into a `WKWebView` when Design Mode is active.
    public static let inspectorJavaScript: String = """
    (function() {
      if (window.__nexusDesignModeCleanup) {
        window.__nexusDesignModeCleanup();
      }
      const overlay = document.createElement('div');
      overlay.id = '__nexus_design_mode_overlay';
      Object.assign(overlay.style, {
        position: 'fixed',
        pointerEvents: 'none',
        zIndex: '2147483647',
        border: '2px solid #D97857',
        backgroundColor: 'rgba(217, 120, 87, 0.14)',
        borderRadius: '4px',
        transition: 'all 0.05s ease-out',
        display: 'none'
      });
      document.documentElement.appendChild(overlay);

      function computeSelector(el) {
        if (!el || el.nodeType !== 1) return '';
        if (el.id) return '#' + CSS.escape(el.id);
        const parts = [];
        let cur = el;
        while (cur && cur.nodeType === 1 && cur !== document.body && parts.length < 5) {
          let part = cur.tagName.toLowerCase();
          if (cur.classList && cur.classList.length > 0) {
            part += '.' + Array.from(cur.classList).slice(0, 2).map(c => CSS.escape(c)).join('.');
          }
          const parent = cur.parentElement;
          if (parent) {
            const siblings = Array.from(parent.children).filter(c => c.tagName === cur.tagName);
            if (siblings.length > 1) {
              const idx = siblings.indexOf(cur) + 1;
              part += ':nth-of-type(' + idx + ')';
            }
          }
          parts.unshift(part);
          cur = parent;
        }
        return parts.join(' > ');
      }

      function findSourceLocation(el) {
        let cur = el;
        while (cur && cur.nodeType === 1) {
          const attr = cur.getAttribute('data-source')
            || cur.getAttribute('data-inspector-line')
            || cur.getAttribute('data-vite-dev-id')
            || cur.getAttribute('data-sentry-source-file');
          if (attr) return attr;
          cur = cur.parentElement;
        }
        return null;
      }

      function onMouseMove(e) {
        const el = document.elementFromPoint(e.clientX, e.clientY);
        if (!el || el === overlay) {
          overlay.style.display = 'none';
          return;
        }
        const rect = el.getBoundingClientRect();
        overlay.style.display = 'block';
        overlay.style.left = rect.left + 'px';
        overlay.style.top = rect.top + 'px';
        overlay.style.width = rect.width + 'px';
        overlay.style.height = rect.height + 'px';
      }

      function onClick(e) {
        e.preventDefault();
        e.stopPropagation();
        const el = document.elementFromPoint(e.clientX, e.clientY);
        if (!el || el === overlay) return;
        const rect = el.getBoundingClientRect();
        const cs = window.getComputedStyle(el);
        const snippet = (el.outerHTML || '').slice(0, 600);
        const payload = {
          tagName: (el.tagName || 'div').toLowerCase(),
          cssSelector: computeSelector(el),
          outerHTMLSnippet: snippet,
          computedStyles: {
            color: cs.color || '',
            backgroundColor: cs.backgroundColor || '',
            fontFamily: cs.fontFamily || '',
            fontSize: cs.fontSize || '',
            fontWeight: cs.fontWeight || '',
            padding: cs.padding || '',
            margin: cs.margin || '',
            display: cs.display || ''
          },
          boundingBox: {
            x: rect.left,
            y: rect.top,
            width: rect.width,
            height: rect.height
          },
          sourceLocation: findSourceLocation(el)
        };
        if (window.webkit && window.webkit.messageHandlers && window.webkit.messageHandlers.nexusDesignMode) {
          window.webkit.messageHandlers.nexusDesignMode.postMessage(JSON.stringify(payload));
        }
      }

      window.addEventListener('mousemove', onMouseMove, true);
      window.addEventListener('click', onClick, true);
      window.__nexusDesignModeCleanup = function() {
        window.removeEventListener('mousemove', onMouseMove, true);
        window.removeEventListener('click', onClick, true);
        if (overlay.parentNode) overlay.parentNode.removeChild(overlay);
      };
    })();
    """

    public static let disableInspectorJavaScript: String = """
    if (window.__nexusDesignModeCleanup) {
      window.__nexusDesignModeCleanup();
      delete window.__nexusDesignModeCleanup;
    }
    """

    private struct RawCapturePayload: Decodable {
        struct RawRect: Decodable {
            let x: Double
            let y: Double
            let width: Double
            let height: Double
        }
        let tagName: String?
        let cssSelector: String?
        let outerHTMLSnippet: String?
        let computedStyles: [String: String]?
        let boundingBox: RawRect?
        let sourceLocation: String?
        let userIntentNote: String?
    }

    public static func parseCapture(fromJSON jsonString: String, pageURL: String) -> NexusAgentDesignElementCapture? {
        guard let data = jsonString.data(using: .utf8),
              let raw = try? JSONDecoder().decode(RawCapturePayload.self, from: data) else {
            return nil
        }
        let selector = (raw.cssSelector ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        let tag = (raw.tagName ?? "div").trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !selector.isEmpty || !(raw.outerHTMLSnippet ?? "").isEmpty else {
            return nil
        }
        let rect: CGRect
        if let box = raw.boundingBox {
            rect = CGRect(x: box.x, y: box.y, width: box.width, height: box.height)
        } else {
            rect = .zero
        }
        let cleanedSource = raw.sourceLocation?.trimmingCharacters(in: .whitespacesAndNewlines)
        return NexusAgentDesignElementCapture(
            pageURL: pageURL,
            tagName: tag.isEmpty ? "div" : tag,
            cssSelector: selector.isEmpty ? tag : selector,
            outerHTMLSnippet: raw.outerHTMLSnippet ?? "",
            computedStyles: raw.computedStyles ?? [:],
            boundingBox: rect,
            sourceLocation: (cleanedSource?.isEmpty == false) ? cleanedSource : nil,
            userIntentNote: raw.userIntentNote ?? ""
        )
    }

    public static func formatPromptAttachment(for captures: [NexusAgentDesignElementCapture]) -> String {
        guard !captures.isEmpty else { return "" }
        var lines: [String] = [
            "## UI Design Mode Element Captures",
            ""
        ]
        for (index, capture) in captures.enumerated() {
            lines.append("### \(index + 1). `<" + capture.tagName + ">` (`" + capture.cssSelector + "`)")
            lines.append("- **Page URL**: `\(capture.pageURL)`")
            if let sourceLocation = capture.sourceLocation, !sourceLocation.isEmpty {
                lines.append("- **Source Location**: `\(sourceLocation)`")
            }
            let rect = capture.boundingBox
            if rect != .zero {
                lines.append(
                    "- **Bounding Box**: `x: \(Int(rect.origin.x)), y: \(Int(rect.origin.y)), width: \(Int(rect.size.width)), height: \(Int(rect.size.height))`"
                )
            }
            if !capture.computedStyles.isEmpty {
                let styleSummary = capture.computedStyles
                    .filter { !$0.value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
                    .sorted { $0.key < $1.key }
                    .map { "\($0.key): \($0.value)" }
                    .joined(separator: "; ")
                if !styleSummary.isEmpty {
                    lines.append("- **Computed Styles**: `\(styleSummary)`")
                }
            }
            if !capture.outerHTMLSnippet.isEmpty {
                lines.append("- **DOM Snippet**:")
                lines.append("  ```html")
                for htmlLine in capture.outerHTMLSnippet.components(separatedBy: "\n") {
                    lines.append("  \(htmlLine)")
                }
                lines.append("  ```")
            }
            let note = capture.userIntentNote.trimmingCharacters(in: .whitespacesAndNewlines)
            if !note.isEmpty {
                lines.append("- **Requested Change**: \(note)")
            }
            lines.append("")
        }
        return lines.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

// MARK: - Rich Workspace Previews & Notes

/// Classifies workspace files into rich preview categories.
public enum NexusAgentPreviewKind: String, Equatable, Sendable, CaseIterable {
    case markdown
    case mermaid
    case html
    case pdf
    case image
    case code

    public static func classify(path: String) -> NexusAgentPreviewKind {
        let lower = (path as NSString).lastPathComponent.lowercased()
        let ext = (lower as NSString).pathExtension

        switch ext {
        case "md", "markdown", "mdown", "mdx":
            return .markdown
        case "mmd", "mermaid":
            return .mermaid
        case "html", "htm", "xhtml":
            return .html
        case "pdf":
            return .pdf
        case "png", "jpg", "jpeg", "gif", "webp", "svg", "ico", "bmp", "tiff", "heic":
            return .image
        default:
            return .code
        }
    }
}

/// Manages reading and saving a per-worktree `PLAN.md` / scratchpad note via injected closures.
@MainActor
public final class NexusAgentWorkspaceNoteStore: ObservableObject {
    @Published public var noteContent: String = ""
    @Published public private(set) var noteFilePath: String
    @Published public private(set) var isDirty: Bool = false
    @Published public private(set) var lastSavedAt: Date?

    private let readFile: (String) -> String?
    private let writeFile: (String, String) -> Bool

    public init(
        worktreePath: String,
        fileName: String = "PLAN.md",
        readFile: @escaping (String) -> String? = { path in
            try? String(contentsOfFile: path, encoding: .utf8)
        },
        writeFile: @escaping (String, String) -> Bool = { path, content in
            do {
                try content.write(toFile: path, atomically: true, encoding: .utf8)
                return true
            } catch {
                return false
            }
        }
    ) {
        let trimmedRoot = worktreePath.hasSuffix("/")
            ? String(worktreePath.dropLast())
            : worktreePath
        self.noteFilePath = trimmedRoot.isEmpty ? fileName : "\(trimmedRoot)/\(fileName)"
        self.readFile = readFile
        self.writeFile = writeFile
    }

    public func setWorktreePath(_ worktreePath: String, fileName: String = "PLAN.md") {
        let trimmedRoot = worktreePath.hasSuffix("/")
            ? String(worktreePath.dropLast())
            : worktreePath
        self.noteFilePath = trimmedRoot.isEmpty ? fileName : "\(trimmedRoot)/\(fileName)"
        load()
    }

    public func load() {
        if let existing = readFile(noteFilePath) {
            noteContent = existing
        } else {
            noteContent = ""
        }
        isDirty = false
    }

    public func updateContent(_ updated: String) {
        guard noteContent != updated else { return }
        noteContent = updated
        isDirty = true
    }

    @discardableResult
    public func save() -> Bool {
        let ok = writeFile(noteFilePath, noteContent)
        if ok {
            isDirty = false
            lastSavedAt = Date()
        }
        return ok
    }

    public func formattedPromptExcerpt() -> String? {
        let trimmed = noteContent.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        return """
        ## Workspace Plan & Notes (`\(noteFilePath)`)

        \(trimmed)
        """
    }
}
