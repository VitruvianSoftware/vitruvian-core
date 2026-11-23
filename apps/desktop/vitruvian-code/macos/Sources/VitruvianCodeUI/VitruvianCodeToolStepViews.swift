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
// Shared by the standalone Vitruvian Code app and the Code feature of the
// Vitruvian desktop app. Written for Vitruvian and released under MIT by its
// copyright holder on 2026-10-09 (apps/desktop/vitruvian-atrium/UPSTREAM.md).


import AppKit
import VitruvianCodeCore
import SwiftUI

/// A line diff between the text a tool replaced and the text it wrote, as the
/// tool-step card draws it.
public enum VitruvianCodeLineDiff {
    public struct Line: Equatable, Sendable {
        public enum Kind: Equatable, Sendable { case context, removed, added }
        public let kind: Kind
        public let text: String

        public init(_ kind: Kind, _ text: String) {
            self.kind = kind
            self.text = text
        }

        /// The line as a unified diff writes it.
        public var unified: String {
            switch kind {
            case .context: return "  " + text
            case .removed: return "- " + text
            case .added: return "+ " + text
            }
        }
    }

    /// Past this many lines on both sides the middle is not searched for
    /// common lines; it is shown as removed and then added.
    static let searchLimit = 400

    /// Maximum diff lines drawn inside a single tool-step card before truncating.
    public static let maxDisplayedLines = 200

    /// Computes line diff entries capped at `limit` lines, returning the hidden remainder count.
    public static func cappedLines(
        old: String?,
        new: String?,
        limit: Int = maxDisplayedLines
    ) -> (lines: [Line], truncatedCount: Int) {
        let all = lines(old: old, new: new)
        let effectiveLimit = max(1, limit)
        guard all.count > effectiveLimit else {
            return (all, 0)
        }
        return (Array(all.prefix(effectiveLimit)), all.count - effectiveLimit)
    }

    /// The lines from `old` to `new`. A nil or empty `old` (a new file) is
    /// every line added. Common leading and trailing lines are context; the
    /// middle is matched line by line on its longest common subsequence.
    public static func lines(old: String?, new: String?) -> [Line] {
        let oldLines = split(old)
        let newLines = split(new)
        var prefix = 0
        while prefix < oldLines.count, prefix < newLines.count, oldLines[prefix] == newLines[prefix] {
            prefix += 1
        }
        var suffix = 0
        while suffix < oldLines.count - prefix, suffix < newLines.count - prefix,
            oldLines[oldLines.count - 1 - suffix] == newLines[newLines.count - 1 - suffix]
        {
            suffix += 1
        }
        let oldMiddle = Array(oldLines[prefix..<(oldLines.count - suffix)])
        let newMiddle = Array(newLines[prefix..<(newLines.count - suffix)])

        var result = oldLines[0..<prefix].map { Line(.context, $0) }
        result += middle(oldMiddle, newMiddle)
        result += oldLines[(oldLines.count - suffix)...].map { Line(.context, $0) }
        return result
    }

    private static func split(_ text: String?) -> [String] {
        guard let text, !text.isEmpty else { return [] }
        var lines = text.components(separatedBy: "\n")
        // A final newline ends the last line; it does not start another.
        if lines.count > 1, lines.last == "" { lines.removeLast() }
        return lines
    }

    private static func middle(_ old: [String], _ new: [String]) -> [Line] {
        if old.isEmpty { return new.map { Line(.added, $0) } }
        if new.isEmpty { return old.map { Line(.removed, $0) } }
        guard old.count <= searchLimit, new.count <= searchLimit else {
            return old.map { Line(.removed, $0) } + new.map { Line(.added, $0) }
        }
        // lengths[i][j]: the longest common subsequence of old[i...] and new[j...].
        var lengths = Array(repeating: Array(repeating: 0, count: new.count + 1), count: old.count + 1)
        for i in stride(from: old.count - 1, through: 0, by: -1) {
            for j in stride(from: new.count - 1, through: 0, by: -1) {
                lengths[i][j] = old[i] == new[j] ? lengths[i + 1][j + 1] + 1 : max(lengths[i + 1][j], lengths[i][j + 1])
            }
        }
        var result: [Line] = []
        var i = 0
        var j = 0
        while i < old.count, j < new.count {
            if old[i] == new[j] {
                result.append(Line(.context, old[i]))
                i += 1
                j += 1
            } else if lengths[i + 1][j] >= lengths[i][j + 1] {
                result.append(Line(.removed, old[i]))
                i += 1
            } else {
                result.append(Line(.added, new[j]))
                j += 1
            }
        }
        result += old[i...].map { Line(.removed, $0) }
        result += new[j...].map { Line(.added, $0) }
        return result
    }
}

/// The steps a reply took, each a row that opens into what the tool did.
struct VitruvianCodeToolStepList: View {
    let steps: [VitruvianCodeToolStep]
    let strings: VitruvianCodeChatStrings
    var workingDirectory: String? = nil
    var openFileURL: (URL) -> Void = { _ = VitruvianCodeMessageBubble.open($0) }
    @State private var expanded: Set<String> = []

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            ForEach(steps) { step in
                VitruvianCodeToolStepRow(
                    step: step,
                    strings: strings,
                    workingDirectory: workingDirectory,
                    openFileURL: openFileURL,
                    isExpanded: expanded.contains(step.id),
                    toggle: {
                        withAnimation(.easeInOut(duration: 0.15)) {
                            if expanded.contains(step.id) {
                                expanded.remove(step.id)
                            } else {
                                expanded.insert(step.id)
                            }
                        }
                    }
                )
            }
        }
        .padding(.vertical, 2)
    }
}

/// One tool step: what kind of tool, what it was asked, and how it went.
struct VitruvianCodeToolStepRow: View {
    let step: VitruvianCodeToolStep
    let strings: VitruvianCodeChatStrings
    var workingDirectory: String? = nil
    var openFileURL: (URL) -> Void = { _ = VitruvianCodeMessageBubble.open($0) }
    let isExpanded: Bool
    let toggle: () -> Void
    @State private var hovering = false

    static func symbol(for kind: VitruvianCodeToolStep.Kind) -> String {
        switch kind {
        case .edit: return "pencil"
        case .write: return "doc.badge.plus"
        case .bash: return "terminal"
        case .read: return "doc.text"
        case .search: return "magnifyingglass"
        case .subagent: return "sparkles"
        case .other: return "gearshape"
        }
    }

    static func statusText(for step: VitruvianCodeToolStep, strings: VitruvianCodeChatStrings) -> String {
        if !step.isFinished { return strings.toolStatusRunning }
        return step.isError ? strings.toolStatusFailed : strings.toolStatusDone
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Button(action: { if step.hasDetail { toggle() } }) {
                HStack(spacing: 7) {
                    Image(systemName: Self.symbol(for: step.kind))
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(step.isError ? Color.red : Color.secondary)
                        .frame(width: 14)
                    Text(step.title)
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundStyle(step.isError ? Color.red.opacity(0.9) : Color.primary.opacity(0.75))
                        .lineLimit(1)
                        .truncationMode(.middle)
                    Spacer(minLength: 6)
                    status
                    if step.hasDetail {
                        Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                            .font(.system(size: 8, weight: .bold))
                            .foregroundStyle(.tertiary)
                            .frame(width: 10)
                    }
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .fill(step.isError ? Color.red.opacity(0.08) : Color.primary.opacity(hovering && step.hasDetail ? 0.05 : 0.0))
                )
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .onHover { hovering = $0 }
            .help(step.detail ?? step.title)

            if isExpanded && step.hasDetail {
                VitruvianCodeToolStepDetail(
                    step: step,
                    strings: strings,
                    workingDirectory: workingDirectory,
                    openFileURL: openFileURL
                )
                .padding(.leading, 22)
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
    }

    @ViewBuilder
    private var status: some View {
        if !step.isFinished {
            HStack(spacing: 4) {
                ProgressView()
                    .controlSize(.mini)
                    .frame(width: 10, height: 10)
                Text(strings.toolStatusRunning)
                    .font(.system(size: 9, weight: .medium))
                    .foregroundStyle(.secondary)
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(strings.toolStatusRunning)
        } else if step.isError {
            HStack(spacing: 3) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.system(size: 9))
                    .foregroundStyle(Color.red)
                Text(strings.toolStatusFailed)
                    .font(.system(size: 9, weight: .medium))
                    .foregroundStyle(Color.red)
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(strings.toolStatusFailed)
        } else {
            Image(systemName: "checkmark")
                .font(.system(size: 8, weight: .bold))
                .foregroundStyle(Color.green.opacity(0.85))
                .accessibilityLabel(strings.toolStatusDone)
        }
    }
}

/// What a step did: all file locations, all diffs of edits/writes, and any output.
struct VitruvianCodeToolStepDetail: View {
    let step: VitruvianCodeToolStep
    let strings: VitruvianCodeChatStrings
    var workingDirectory: String? = nil
    var openFileURL: (URL) -> Void = { _ = VitruvianCodeMessageBubble.open($0) }

    /// One line of the 11-point monospaced text these cards draw.
    static let lineHeight: CGFloat = 15
    /// How many lines of output show before the block scrolls.
    static let visibleOutputLines = 12
    /// How many lines of a diff show before it scrolls.
    static let visibleDiffLines = 16

    private static let schemePrefixRegex = try! NSRegularExpression(
        pattern: #"^[A-Za-z][A-Za-z0-9+.-]*:"#
    )

    /// Resolves an untrusted agent-supplied location to a safe `file://` URL, rejecting
    /// non-file URLs, remote hosts, control characters, and unresolvable relative paths.
    static func safeLocationURL(
        for location: VitruvianCodeToolStep.Location,
        workingDirectory: String?
    ) -> URL? {
        let trimmed = location.path.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty,
              !trimmed.contains("\0"),
              !trimmed.contains("\r"),
              !trimmed.contains("\n") else {
            return nil
        }
        let candidatePath: String
        let fullRange = NSRange(trimmed.startIndex..<trimmed.endIndex, in: trimmed)
        if schemePrefixRegex.firstMatch(in: trimmed, range: fullRange) != nil {
            guard let url = URL(string: trimmed),
                  url.isFileURL,
                  url.host == nil || url.host?.isEmpty == true || url.host == "localhost",
                  !url.path.isEmpty else {
                return nil
            }
            candidatePath = url.path
        } else {
            candidatePath = trimmed
        }
        guard let resolved = VitruvianCodePathLinks.resolve(candidatePath, workingDirectory: workingDirectory),
              !resolved.isEmpty else {
            return nil
        }
        let baseURL = URL(fileURLWithPath: resolved)
        guard baseURL.isFileURL else { return nil }
        if let line = location.line, line > 0 {
            var components = URLComponents(url: baseURL, resolvingAgainstBaseURL: false)
            components?.fragment = "L\(line)"
            if let withLine = components?.url, withLine.isFileURL {
                return withLine
            }
        }
        return baseURL
    }

    @discardableResult
    static func openLocation(
        _ location: VitruvianCodeToolStep.Location,
        workingDirectory: String?,
        openURL: (URL) -> Void = { _ = VitruvianCodeMessageBubble.open($0) }
    ) -> Bool {
        guard let url = safeLocationURL(for: location, workingDirectory: workingDirectory),
              url.isFileURL else {
            return false
        }
        openURL(url)
        return true
    }

    static func locationLabel(for location: VitruvianCodeToolStep.Location) -> String {
        if let line = location.line, line > 0 {
            return "\(location.path):\(line)"
        }
        return location.path
    }

    var body: some View {
        let locations = step.effectiveLocations
        let diffs = step.effectiveDiffs
        VStack(alignment: .leading, spacing: 6) {
            if !locations.isEmpty {
                VStack(alignment: .leading, spacing: 3) {
                    ForEach(Array(locations.enumerated()), id: \.offset) { _, location in
                        locationRow(location)
                    }
                }
            }
            ForEach(Array(diffs.enumerated()), id: \.offset) { _, entry in
                diffBlock(entry)
            }
            if let output = step.output, !output.isEmpty {
                VitruvianCodeOutputBlock(text: output, isError: step.isError, strings: strings)
            }
        }
    }

    @ViewBuilder
    private func locationRow(_ location: VitruvianCodeToolStep.Location) -> some View {
        let label = Self.locationLabel(for: location)
        if let url = Self.safeLocationURL(for: location, workingDirectory: workingDirectory) {
            Button {
                openFileURL(url)
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: "doc.text")
                        .font(.system(size: 9))
                    Text(label)
                        .font(.system(size: 10, design: .monospaced))
                        .lineLimit(1)
                        .truncationMode(.head)
                        .underline()
                }
                .foregroundStyle(VitruvianCodeTheme.warmCoral)
            }
            .buttonStyle(.plain)
            .help(strings.openFile)
        } else {
            HStack(spacing: 4) {
                Image(systemName: "doc.text")
                    .font(.system(size: 9))
                Text(label)
                    .font(.system(size: 10, design: .monospaced))
                    .lineLimit(1)
                    .truncationMode(.head)
            }
            .foregroundStyle(.secondary)
        }
    }

    private func diffBlock(_ entry: VitruvianCodeToolStep.Diff) -> some View {
        let capped = VitruvianCodeLineDiff.cappedLines(
            old: step.kind == .write && step.diffs.isEmpty ? nil : entry.oldText,
            new: entry.newText
        )
        let totalVisibleRows = capped.lines.count + (capped.truncatedCount > 0 ? 1 : 0)
        let content = VStack(alignment: .leading, spacing: 0) {
            if !entry.path.isEmpty {
                Text(entry.path)
                    .font(.system(size: 10, weight: .medium, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.head)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color.primary.opacity(0.04))
            }
            ForEach(Array(capped.lines.enumerated()), id: \.offset) { _, line in
                Text(line.unified.isEmpty ? " " : line.unified)
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(line.kind == .context ? Color.secondary : Color.primary)
                    .frame(maxWidth: .infinity, minHeight: Self.lineHeight, alignment: .leading)
                    .padding(.horizontal, 8)
                    .background(Self.fill(for: line.kind))
                    .fixedSize(horizontal: false, vertical: true)
            }
            if capped.truncatedCount > 0 {
                Text(AgentPlanCardState.format(strings.diffTruncatedFormat, "\(capped.truncatedCount)", ""))
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, minHeight: Self.lineHeight, alignment: .leading)
                    .padding(.horizontal, 8)
                    .padding(.top, 2)
            }
        }
        .padding(.vertical, 4)
        .textSelection(.enabled)
        return VitruvianCodeCappedBlock(lineCount: totalVisibleRows, visibleLines: Self.visibleDiffLines) { content }
            .background(RoundedRectangle(cornerRadius: 6, style: .continuous).fill(Color.primary.opacity(0.03)))
            .overlay(RoundedRectangle(cornerRadius: 6, style: .continuous).strokeBorder(Color.primary.opacity(0.08), lineWidth: 0.5))
            .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
    }

    static func fill(for kind: VitruvianCodeLineDiff.Line.Kind) -> Color {
        switch kind {
        case .context: return .clear
        case .removed: return Color.red.opacity(0.12)
        case .added: return Color.green.opacity(0.12)
        }
    }
}

/// Content drawn whole while it is short, and in a scroll view of a fixed
/// height once it is longer than `visibleLines`. A scroll view inside the
/// chat's own would otherwise size itself to nothing.
struct VitruvianCodeCappedBlock<Content: View>: View {
    let lineCount: Int
    let visibleLines: Int
    @ViewBuilder let content: () -> Content

    var body: some View {
        if lineCount > visibleLines {
            ScrollView(.vertical) { content() }
                .frame(height: CGFloat(visibleLines) * VitruvianCodeToolStepDetail.lineHeight + 8)
        } else {
            content()
        }
    }
}

/// A command's output: monospaced, at most twelve lines tall, with a copy
/// button. Red when the command failed.
struct VitruvianCodeOutputBlock: View {
    let text: String
    let isError: Bool
    let strings: VitruvianCodeChatStrings
    @State private var copied = false

    var body: some View {
        let lineCount = text.components(separatedBy: "\n").count
        ZStack(alignment: .topTrailing) {
            VitruvianCodeCappedBlock(lineCount: lineCount, visibleLines: VitruvianCodeToolStepDetail.visibleOutputLines) {
                Text(text)
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(isError ? Color.red.opacity(0.9) : Color.primary.opacity(0.8))
                    .lineSpacing(0)
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 6)
                    .padding(.trailing, 18)
            }
            Button {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(text, forType: .string)
                copied = true
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { copied = false }
            } label: {
                Image(systemName: copied ? "checkmark" : "doc.on.doc")
                    .font(.system(size: 10))
                    .foregroundStyle(copied ? Color.green : Color.secondary)
                    .padding(5)
            }
            .buttonStyle(.plain)
            .help(strings.copy)
        }
        .background(
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .fill(isError ? Color.red.opacity(0.08) : Color.black.opacity(0.18))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .strokeBorder(isError ? Color.red.opacity(0.3) : Color.primary.opacity(0.08), lineWidth: 0.5)
        )
        .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
    }
}

/// Text the new tool-step, code and thinking views show. English for now:
/// these are computed so that they need no new field in the strings each
/// app fills in; an app that translates them should make them fields of
/// its own.
extension VitruvianCodeChatStrings {
    public var openFile: String { "Open file" }
    public var runInTerminal: String { "Run" }
    public var confirmRun: String { "Confirm?" }
    public var runInTerminalHelp: String { "Run this in Terminal" }
    public var thinkingNow: String { "Thinking…" }
    public var thoughtForPrefix: String { "Thought for " }
    public var thoughtLabel: String { "Thought" }
    public var tokensShortSuffix: String { " tok" }
}
