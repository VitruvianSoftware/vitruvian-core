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
import Darwin
import VitruvianCodeCore
import SwiftUI
import UniformTypeIdentifiers

public typealias VitruvianCodeLineDiff = VitruvianCodeCore.VitruvianCodeLineDiff

/// The steps a reply took, each a row that opens into what the tool did.
struct VitruvianCodeToolStepList: View {
    let steps: [VitruvianCodeToolStep]
    let strings: VitruvianCodeChatStrings
    var workingDirectory: String? = nil
    var openFileURL: (URL) -> Void = { VitruvianCodeToolStepDetail.openToolLocationURL($0) }
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
    var openFileURL: (URL) -> Void = { VitruvianCodeToolStepDetail.openToolLocationURL($0) }
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
    var openFileURL: (URL) -> Void = { VitruvianCodeToolStepDetail.openToolLocationURL($0) }

    enum LocationOpenAction: Equatable, Sendable {
        case openAsText(URL)
        case reveal(URL)
        case none
    }

    /// Pure decision for opening an agent-reported tool-card location safely:
    /// resolves symlinks first; opens regular text-conforming files (including scripts
    /// like `.command`) in the default plain-text app so they are never executed;
    /// reveals bundles/directories/binaries in Finder; returns `.none` if missing.
    static func locationOpenAction(for url: URL) -> LocationOpenAction {
        guard url.isFileURL else { return .none }
        let cleanPath = url.path
        guard !cleanPath.isEmpty,
              let cResolved = Darwin.realpath(cleanPath, nil) else {
            return .none
        }
        defer { free(cResolved) }
        let resolvedURL = URL(fileURLWithPath: String(cString: cResolved))
        guard let values = try? resolvedURL.resourceValues(
            forKeys: [.isRegularFileKey, .isDirectoryKey, .isPackageKey, .contentTypeKey]
        ) else {
            return .none
        }
        let isRegularFile = values.isRegularFile == true
            && values.isDirectory != true
            && values.isPackage != true
        if isRegularFile {
            let contentType = values.contentType
                ?? UTType(filenameExtension: resolvedURL.pathExtension)
            if let contentType, contentType.conforms(to: .text) {
                return .openAsText(resolvedURL)
            }
        }
        return .reveal(resolvedURL)
    }

    static func openToolLocationURL(_ url: URL) {
        switch locationOpenAction(for: url) {
        case .openAsText(let resolvedURL):
            if let textAppURL = NSWorkspace.shared.urlForApplication(toOpen: .plainText) {
                NSWorkspace.shared.open(
                    [resolvedURL],
                    withApplicationAt: textAppURL,
                    configuration: NSWorkspace.OpenConfiguration()
                )
            } else {
                NSWorkspace.shared.activateFileViewerSelecting([resolvedURL])
            }
        case .reveal(let resolvedURL):
            NSWorkspace.shared.activateFileViewerSelecting([resolvedURL])
        case .none:
            break
        }
    }

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
        openURL: (URL) -> Void = { VitruvianCodeToolStepDetail.openToolLocationURL($0) }
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
