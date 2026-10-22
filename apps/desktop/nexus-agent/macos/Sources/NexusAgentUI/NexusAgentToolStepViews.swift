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


import AppKit
import NexusAgentCore
import SwiftUI

/// A line diff between the text a tool replaced and the text it wrote, as the
/// tool-step card draws it.
public enum NexusAgentLineDiff {
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
struct NexusAgentToolStepList: View {
    let steps: [NexusAgentToolStep]
    let strings: NexusAgentChatStrings
    @State private var expanded: Set<String> = []

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            ForEach(steps) { step in
                NexusAgentToolStepRow(
                    step: step,
                    strings: strings,
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
struct NexusAgentToolStepRow: View {
    let step: NexusAgentToolStep
    let strings: NexusAgentChatStrings
    let isExpanded: Bool
    let toggle: () -> Void
    @State private var hovering = false

    static func symbol(for kind: NexusAgentToolStep.Kind) -> String {
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
                NexusAgentToolStepDetail(step: step, strings: strings)
                    .padding(.leading, 22)
                    .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
    }

    @ViewBuilder
    private var status: some View {
        if !step.isFinished {
            ProgressView()
                .controlSize(.mini)
                .frame(width: 10, height: 10)
        } else if step.isError {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 9))
                .foregroundStyle(Color.red)
        } else {
            Image(systemName: "checkmark")
                .font(.system(size: 8, weight: .bold))
                .foregroundStyle(Color.green.opacity(0.85))
        }
    }
}

/// What a step did: the diff of an edit or a write, or a command's output.
struct NexusAgentToolStepDetail: View {
    let step: NexusAgentToolStep
    let strings: NexusAgentChatStrings

    /// One line of the 11-point monospaced text these cards draw.
    static let lineHeight: CGFloat = 15
    /// How many lines of output show before the block scrolls.
    static let visibleOutputLines = 12
    /// How many lines of a diff show before it scrolls.
    static let visibleDiffLines = 16

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            if let path = step.filePath, !path.isEmpty {
                Button {
                    NSWorkspace.shared.open(URL(fileURLWithPath: (path as NSString).expandingTildeInPath))
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "doc.text")
                            .font(.system(size: 9))
                        Text(path)
                            .font(.system(size: 10, design: .monospaced))
                            .lineLimit(1)
                            .truncationMode(.head)
                            .underline()
                    }
                    .foregroundStyle(NexusAgentTheme.warmCoral)
                }
                .buttonStyle(.plain)
                .help(strings.openFile)
            }
            if step.kind == .edit || step.kind == .write, step.diffOld != nil || step.diffNew != nil {
                diff
            }
            if let output = step.output, !output.isEmpty {
                NexusAgentOutputBlock(text: output, isError: step.isError, strings: strings)
            }
        }
    }

    private var diff: some View {
        let lines = NexusAgentLineDiff.lines(old: step.kind == .write ? nil : step.diffOld, new: step.diffNew)
        let content = VStack(alignment: .leading, spacing: 0) {
            ForEach(Array(lines.enumerated()), id: \.offset) { _, line in
                Text(line.unified.isEmpty ? " " : line.unified)
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(line.kind == .context ? Color.secondary : Color.primary)
                    .frame(maxWidth: .infinity, minHeight: Self.lineHeight, alignment: .leading)
                    .padding(.horizontal, 8)
                    .background(Self.fill(for: line.kind))
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(.vertical, 4)
        .textSelection(.enabled)
        return NexusAgentCappedBlock(lineCount: lines.count, visibleLines: Self.visibleDiffLines) { content }
            .background(RoundedRectangle(cornerRadius: 6, style: .continuous).fill(Color.primary.opacity(0.03)))
            .overlay(RoundedRectangle(cornerRadius: 6, style: .continuous).strokeBorder(Color.primary.opacity(0.08), lineWidth: 0.5))
            .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
    }

    static func fill(for kind: NexusAgentLineDiff.Line.Kind) -> Color {
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
struct NexusAgentCappedBlock<Content: View>: View {
    let lineCount: Int
    let visibleLines: Int
    @ViewBuilder let content: () -> Content

    var body: some View {
        if lineCount > visibleLines {
            ScrollView(.vertical) { content() }
                .frame(height: CGFloat(visibleLines) * NexusAgentToolStepDetail.lineHeight + 8)
        } else {
            content()
        }
    }
}

/// A command's output: monospaced, at most twelve lines tall, with a copy
/// button. Red when the command failed.
struct NexusAgentOutputBlock: View {
    let text: String
    let isError: Bool
    let strings: NexusAgentChatStrings
    @State private var copied = false

    var body: some View {
        let lineCount = text.components(separatedBy: "\n").count
        ZStack(alignment: .topTrailing) {
            NexusAgentCappedBlock(lineCount: lineCount, visibleLines: NexusAgentToolStepDetail.visibleOutputLines) {
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
extension NexusAgentChatStrings {
    public var openFile: String { "Open file" }
    public var runInTerminal: String { "Run" }
    public var confirmRun: String { "Confirm?" }
    public var runInTerminalHelp: String { "Run this in Terminal" }
    public var thinkingNow: String { "Thinking…" }
    public var thoughtForPrefix: String { "Thought for " }
    public var thoughtLabel: String { "Thought" }
    public var tokensShortSuffix: String { " tok" }
}
