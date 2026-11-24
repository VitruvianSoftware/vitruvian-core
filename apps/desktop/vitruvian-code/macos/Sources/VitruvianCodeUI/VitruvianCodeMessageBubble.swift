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

/// An interactive tool execution approval card shown within a message bubble.
struct VitruvianCodeApprovalCardView: View {
    let request: VitruvianCodeApprovalRequest
    let strings: VitruvianCodeChatStrings
    let onDecision: ((VitruvianCodeApprovalRequest.Status) -> Void)?
    var onOptionSelected: ((String) -> Void)? = nil
    @State private var hoveredButton: String?

    static func partitionOptions(
        _ options: [AgentPermissionOption]
    ) -> (primary: [AgentPermissionOption], more: [AgentPermissionOption]) {
        let rejectOnce = options.filter { $0.kind == .rejectOnce }
        let allowOnce = options.filter { $0.kind == .allowOnce }
        let primary = rejectOnce + allowOnce
        let more = options.filter { $0.kind != .rejectOnce && $0.kind != .allowOnce }
        return (primary, more)
    }

    static func optionLabel(_ option: AgentPermissionOption, strings: VitruvianCodeChatStrings) -> String {
        let trimmed = option.name.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty { return trimmed }
        switch option.kind {
        case .allowOnce: return strings.allow
        case .allowAlways: return strings.allowForSession
        case .rejectOnce, .rejectAlways: return strings.deny
        }
    }

    static func kindColor(_ kind: AgentPermissionOption.Kind) -> Color {
        switch kind {
        case .allowOnce: return .green
        case .allowAlways: return VitruvianCodeTheme.warmCoral
        case .rejectOnce, .rejectAlways: return .red
        }
    }

    @ViewBuilder
    static func kindIcon(_ kind: AgentPermissionOption.Kind) -> some View {
        switch kind {
        case .allowOnce:
            Image(systemName: "checkmark.circle")
        case .allowAlways:
            Image(systemName: "checkmark.circle.fill")
        case .rejectOnce:
            Image(systemName: "xmark.circle")
        case .rejectAlways:
            Image(systemName: "xmark.circle.fill")
        }
    }

    @ViewBuilder
    private var statusBadge: some View {
        if request.status == .pending {
            Text(strings.awaitingConfirmation)
                .font(.system(size: 9, weight: .medium))
                .foregroundStyle(VitruvianCodeTheme.warmCoral)
        } else if !request.options.isEmpty,
                  let chosenID = request.chosenOptionID,
                  let chosen = request.options.first(where: { $0.id == chosenID }) {
            HStack(spacing: 3) {
                Self.kindIcon(chosen.kind)
                    .font(.system(size: 10))
                Text(Self.optionLabel(chosen, strings: strings))
                    .font(.system(size: 10, weight: .semibold))
            }
            .foregroundStyle(Self.kindColor(chosen.kind))
        } else {
            switch request.status {
            case .pending:
                EmptyView()
            case .approved:
                HStack(spacing: 3) {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 10))
                        .foregroundStyle(.green)
                    Text(strings.approved)
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(.green)
                }
            case .denied:
                HStack(spacing: 3) {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 10))
                        .foregroundStyle(.red)
                    Text(strings.denied)
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(.red)
                }
            case .sessionAllowed:
                HStack(spacing: 3) {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 10))
                        .foregroundStyle(VitruvianCodeTheme.warmCoral)
                    Text(strings.allowedForSession)
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(VitruvianCodeTheme.warmCoral)
                }
            }
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Image(systemName: "hand.raised.fill")
                    .font(.system(size: 11))
                    .foregroundStyle(request.status == .pending ? VitruvianCodeTheme.warmCoral : Color.secondary)
                Text(strings.permissionRequest)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(Color.primary)
                Text(request.toolName)
                    .font(.system(size: 10, weight: .bold, design: .monospaced))
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Capsule().fill(Color.primary.opacity(0.08)))
                Spacer()
                statusBadge
            }

            if !request.commandOrPath.isEmpty {
                Text(request.commandOrPath)
                    .font(.system(size: 11, design: .monospaced))
                    .lineLimit(4)
                    .foregroundStyle(.primary.opacity(0.85))
                    .padding(6)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(RoundedRectangle(cornerRadius: 6).fill(Color.primary.opacity(0.04)))
                    .overlay(
                        RoundedRectangle(cornerRadius: 6)
                            .strokeBorder(Color.primary.opacity(0.08), lineWidth: 1)
                    )
            }

            if request.status == .pending {
                if request.options.isEmpty {
                    legacyActionRow
                } else {
                    agentOptionsActionRow
                }
            }
        }
        .padding(8)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(Color.primary.opacity(0.03))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .strokeBorder(request.status == .pending ? VitruvianCodeTheme.warmCoral.opacity(0.3) : Color.primary.opacity(0.08), lineWidth: 1)
        )
    }

    private var agentOptionsActionRow: some View {
        let partition = Self.partitionOptions(request.options)
        return HStack(spacing: 8) {
            ForEach(partition.primary) { option in
                let isAllow = option.kind == .allowOnce
                let label = Self.optionLabel(option, strings: strings)
                Button {
                    onOptionSelected?(option.id)
                } label: {
                    HStack(spacing: 4) {
                        Self.kindIcon(option.kind)
                            .font(.system(size: 10, weight: .semibold))
                        Text(label)
                            .font(.system(size: 11, weight: .medium))
                            .lineLimit(1)
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 4)
                    .background(
                        RoundedRectangle(cornerRadius: 6)
                            .fill(isAllow
                                ? (hoveredButton == option.id ? VitruvianCodeTheme.warmCoralLight : VitruvianCodeTheme.warmCoral)
                                : Color.primary.opacity(hoveredButton == option.id ? 0.12 : 0.06))
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 6)
                            .strokeBorder(isAllow ? Color.clear : Color.primary.opacity(0.16), lineWidth: 1)
                    )
                    .foregroundStyle(isAllow ? Color.white : Color.primary.opacity(0.9))
                }
                .buttonStyle(.plain)
                .onHover { hoveredButton = $0 ? option.id : nil }
            }

            if !partition.more.isEmpty {
                Menu {
                    ForEach(partition.more) { option in
                        Button {
                            onOptionSelected?(option.id)
                        } label: {
                            switch option.kind {
                            case .allowOnce:
                                Label(Self.optionLabel(option, strings: strings), systemImage: "checkmark.circle")
                            case .allowAlways:
                                Label(Self.optionLabel(option, strings: strings), systemImage: "checkmark.circle.fill")
                            case .rejectOnce:
                                Label(Self.optionLabel(option, strings: strings), systemImage: "xmark.circle")
                            case .rejectAlways:
                                Label(Self.optionLabel(option, strings: strings), systemImage: "xmark.circle.fill")
                            }
                        }
                    }
                } label: {
                    Image(systemName: "ellipsis")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(Color.primary.opacity(0.85))
                        .padding(.horizontal, 8)
                        .padding(.vertical, 6)
                        .background(
                            RoundedRectangle(cornerRadius: 6)
                                .fill(Color.primary.opacity(hoveredButton == "more" ? 0.12 : 0.06))
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 6)
                                .strokeBorder(Color.primary.opacity(0.16), lineWidth: 1)
                        )
                }
                .menuStyle(.borderlessButton)
                .menuIndicator(.hidden)
                .fixedSize()
                .accessibilityLabel(strings.moreApprovalOptions)
                .help(strings.moreApprovalOptions)
                .onHover { hoveredButton = $0 ? "more" : nil }
            }

            Spacer(minLength: 0)
        }
        .padding(.top, 2)
    }

    private var legacyActionRow: some View {
        HStack(spacing: 8) {
            Button {
                onDecision?(.approved)
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: "checkmark")
                        .font(.system(size: 10, weight: .bold))
                    Text(strings.allow)
                        .font(.system(size: 11, weight: .medium))
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 4)
                .background(RoundedRectangle(cornerRadius: 6).fill(Color.green.opacity(hoveredButton == "allow" ? 0.25 : 0.15)))
                .foregroundStyle(Color.green)
            }
            .buttonStyle(.plain)
            .onHover { hoveredButton = $0 ? "allow" : nil }

            Button {
                onDecision?(.denied)
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: "xmark")
                        .font(.system(size: 10, weight: .bold))
                    Text(strings.deny)
                        .font(.system(size: 11, weight: .medium))
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 4)
                .background(RoundedRectangle(cornerRadius: 6).fill(Color.red.opacity(hoveredButton == "deny" ? 0.25 : 0.15)))
                .foregroundStyle(Color.red)
            }
            .buttonStyle(.plain)
            .onHover { hoveredButton = $0 ? "deny" : nil }

            Button {
                onDecision?(.sessionAllowed)
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: "lock.fill")
                        .font(.system(size: 9))
                    Text(strings.allowForSession)
                        .font(.system(size: 11, weight: .medium))
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 4)
                .background(RoundedRectangle(cornerRadius: 6).fill(VitruvianCodeTheme.warmCoral.opacity(hoveredButton == "session" ? 0.25 : 0.15)))
                .foregroundStyle(VitruvianCodeTheme.warmCoral)
            }
            .buttonStyle(.plain)
            .onHover { hoveredButton = $0 ? "session" : nil }

            Spacer()
        }
        .padding(.top, 2)
    }
}

/// Renders rich Markdown blocks (headings, lists, quotes, dividers, tables, code/mermaid cards).
struct VitruvianCodeMarkdownContentView: View {
    let text: String
    let strings: VitruvianCodeChatStrings
    let errorScheme: String
    var isError: Bool = false
    var workingDirectory: String? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            ForEach(Array(VitruvianCodeReplyBlock.parse(text).enumerated()), id: \.offset) { _, block in
                switch block {
                case .text(let chunk):
                    VStack(alignment: .leading, spacing: 6) {
                        ForEach(Array(VitruvianCodeMarkdownBlock.parse(chunk).enumerated()), id: \.offset) { _, mdBlock in
                            switch mdBlock {
                            case .heading(let level, let headingText):
                                Text(VitruvianCodeMessageBubble.markdown(headingText, workingDirectory: workingDirectory))
                                    .font(.system(size: level == 1 ? 15 : (level == 2 ? 14 : 13), weight: .bold))
                                    .foregroundStyle(isError ? VitruvianCodeTheme.warmCoral : Color.primary)
                                    .fixedSize(horizontal: false, vertical: true)
                                    .padding(.vertical, 2)
                            case .bulletItem(let bulletText):
                                HStack(alignment: .top, spacing: 6) {
                                    Image(systemName: "circle.fill")
                                        .font(.system(size: 4))
                                        .foregroundStyle(VitruvianCodeTheme.warmCoral)
                                        .padding(.top, 6)
                                    Text(VitruvianCodeMessageBubble.markdown(bulletText, workingDirectory: workingDirectory))
                                        .font(.system(size: 13))
                                        .foregroundStyle(isError ? VitruvianCodeTheme.warmCoral : Color.primary)
                                        .fixedSize(horizontal: false, vertical: true)
                                }
                            case .numberedItem(let number, let itemText):
                                HStack(alignment: .top, spacing: 6) {
                                    Text("\(number).")
                                        .font(.system(size: 12, weight: .medium, design: .rounded))
                                        .foregroundStyle(.secondary)
                                        .padding(.top, 1)
                                    Text(VitruvianCodeMessageBubble.markdown(itemText, workingDirectory: workingDirectory))
                                        .font(.system(size: 13))
                                        .foregroundStyle(isError ? VitruvianCodeTheme.warmCoral : Color.primary)
                                        .fixedSize(horizontal: false, vertical: true)
                                }
                            case .blockquote(let quoteText):
                                HStack(alignment: .top, spacing: 8) {
                                    RoundedRectangle(cornerRadius: 1.5)
                                        .fill(VitruvianCodeTheme.warmCoral.opacity(0.7))
                                        .frame(width: 3)
                                    Text(VitruvianCodeMessageBubble.markdown(quoteText, workingDirectory: workingDirectory))
                                        .font(.system(size: 13))
                                        .italic()
                                        .foregroundStyle(.secondary)
                                        .fixedSize(horizontal: false, vertical: true)
                                }
                                .padding(.vertical, 2)
                            case .divider:
                                Divider()
                                    .opacity(0.4)
                                    .padding(.vertical, 4)
                            case .paragraph(let paragraphText):
                                Text(VitruvianCodeMessageBubble.markdown(paragraphText, workingDirectory: workingDirectory))
                                    .font(.system(size: 13))
                                    .foregroundStyle(isError ? VitruvianCodeTheme.warmCoral : Color.primary)
                                    .fixedSize(horizontal: false, vertical: true)
                            case .table(let headers, let rows):
                                VitruvianCodeMarkdownTableView(
                                    headers: headers,
                                    rows: rows,
                                    render: { VitruvianCodeMessageBubble.markdown($0, workingDirectory: workingDirectory) },
                                    isError: isError
                                )
                                .padding(.vertical, 2)
                            }
                        }
                    }
                case .code(let language, let body):
                    if let lang = language?.lowercased(), lang == "mermaid" {
                        VitruvianCodeMermaidCard(source: body, strings: strings, errorScheme: errorScheme)
                    } else {
                        VitruvianCodeCodeBlockView(language: language, bodyText: body, strings: strings, workingDirectory: workingDirectory)
                    }
                }
            }
        }
        .textSelection(.enabled)
        .environment(\.openURL, OpenURLAction { url in VitruvianCodeMessageBubble.open(url) })
    }
}

/// One chat bubble: rich Markdown blocks (headings, lists, quotes, dividers) and interactive code/diagram cards.
struct VitruvianCodeMessageBubble: View {
    let message: VitruvianCodeChatMessage
    let strings: VitruvianCodeChatStrings
    /// Handed on to a diagram in the message.
    let errorScheme: String
    var onDecision: ((VitruvianCodeApprovalRequest.Status) -> Void)? = nil
    var onApprovalOption: ((String) -> Void)? = nil
    var onAnswerQuestion: (([String: String]) -> Void)? = nil
    var onSkipQuestion: (() -> Void)? = nil
    var isFirstPendingQuestion: Bool = false
    /// True while this reply is still being written, so the thinking pill
    /// says "Thinking…" rather than how long it took.
    var isStreaming: Bool = false
    /// The conversation's working folder: relative `file:line` references
    /// in the reply are resolved against it (`VitruvianCodePathLinks`).
    var workingDirectory: String? = nil
    @State private var copied = false
    @State private var copyBounce = false
    @State private var hovering = false
    @State private var showingStats = false
    @State private var showingToolSteps = false
    @State private var showingThinking = false

    private func copyContent() {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(message.text, forType: .string)
        copied = true
        copyBounce = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { copyBounce = false }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { copied = false }
    }

    private func formatTokenCount(_ count: Int) -> String {
        if count >= 1000 {
            return String(format: "%.1fK", locale: Locale.current, Double(count) / 1000.0)
        }
        return "\(count)"
    }

    private func buildStatsParts() -> [String] {
        var parts: [String] = []
        if let ms = message.durationMs {
            parts.append(String(format: "%.1fs", locale: Locale.current, Double(ms) / 1000.0))
        }
        if let input = message.inputTokens {
            parts.append("\(formatTokenCount(input))\(strings.statsInSuffix)")
        }
        if let output = message.outputTokens {
            parts.append("\(formatTokenCount(output))\(strings.statsOutSuffix)")
        }
        if let cached = message.cachedTokens, cached > 0 {
            parts.append("\(formatTokenCount(cached))\(strings.statsCachedSuffix)")
        }
        if let cost = message.totalCostUSD, cost > 0 {
            parts.append(String(format: "$%.4f", locale: Locale.current, cost))
        }
        if let tools = message.toolCalls, tools > 0 {
            parts.append("\(tools)\(tools == 1 ? strings.statsToolSuffix : strings.statsToolsSuffix)")
        }
        return parts
    }

    @ViewBuilder
    private func statsRow(_ label: String, _ value: String) -> some View {
        HStack(spacing: 6) {
            Text(label)
                .foregroundStyle(.quaternary)
                .frame(width: 65, alignment: .trailing)
            Text(value)
                .foregroundStyle(.tertiary)
        }
        .font(.system(size: 9, weight: .medium, design: .rounded))
    }

    var body: some View {
        if let compaction = message.compaction {
            AgentCompactionRowView(compaction: compaction, strings: strings)
        } else {
            bubbleBody
        }
    }

    @ViewBuilder
    private var bubbleBody: some View {
        let isUser = message.role == .user
        HStack(alignment: .top, spacing: 8) {
            if isUser { Spacer(minLength: 40) }

            if !isUser {
                Image(systemName: "sparkles")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(.linearGradient(
                        colors: [VitruvianCodeTheme.warmCoralLight, VitruvianCodeTheme.warmCoral],
                        startPoint: .top, endPoint: .bottom
                    ))
                    .frame(width: 22, height: 22)
                    .background(Circle().fill(VitruvianCodeTheme.warmCoral.opacity(0.18)))
                    .padding(.top, 4)
            }

            VStack(alignment: isUser ? .trailing : .leading, spacing: 4) {
                if !isUser, let toolSteps = message.toolSteps, !toolSteps.isEmpty {
                    VStack(alignment: .leading, spacing: 4) {
                        Button {
                            withAnimation(.easeInOut(duration: 0.15)) {
                                showingToolSteps.toggle()
                            }
                        } label: {
                            HStack(spacing: 5) {
                                // A green tick only once every step is done:
                                // a step still running shows a spinner.
                                if toolSteps.contains(where: { !$0.isFinished }) {
                                    ProgressView()
                                        .controlSize(.mini)
                                        .frame(width: 10, height: 10)
                                } else if toolSteps.contains(where: { $0.isError }) {
                                    Image(systemName: "exclamationmark.triangle.fill")
                                        .font(.system(size: 10))
                                        .foregroundStyle(Color.red)
                                } else {
                                    Image(systemName: "checkmark.circle.fill")
                                        .font(.system(size: 10))
                                        .foregroundStyle(Color.green)
                                }
                                Text(toolSteps.count == 1 ? (toolSteps.first?.title ?? strings.oneToolExecutionFinished) : "\(toolSteps.count)\(strings.toolExecutionsFinishedSuffix)")
                                    .font(.system(size: 11, weight: .medium))
                                    .foregroundStyle(.secondary)
                                    // A long command stays on one line, so
                                    // it never breaks out of the capsule.
                                    .lineLimit(1)
                                    .truncationMode(.tail)
                                Image(systemName: showingToolSteps ? "chevron.up" : "chevron.down")
                                    .font(.system(size: 8, weight: .bold))
                                    .foregroundStyle(.secondary.opacity(0.8))
                            }
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(Capsule().fill(Color.primary.opacity(0.05)))
                        }
                        .buttonStyle(.plain)

                        if showingToolSteps {
                            VitruvianCodeToolStepList(
                                steps: toolSteps,
                                strings: strings,
                                workingDirectory: workingDirectory
                            )
                            .frame(maxWidth: 560, alignment: .leading)
                        }
                    }
                }

                let thinkingText = message.thinkingText ?? ""
                let pill = VitruvianCodeThinkingPill.label(
                    durationMs: message.thinkingDurationMs, tokens: message.thinkingTokens,
                    isStreaming: isStreaming, strings: strings)
                if !isUser, !thinkingText.isEmpty || pill != nil {
                    VStack(alignment: .leading, spacing: 4) {
                        Button {
                            guard !thinkingText.isEmpty else { return }
                            withAnimation(.easeInOut(duration: 0.15)) {
                                showingThinking.toggle()
                            }
                        } label: {
                            HStack(spacing: 5) {
                                if isStreaming && message.thinkingDurationMs == nil {
                                    ProgressView()
                                        .controlSize(.mini)
                                        .frame(width: 10, height: 10)
                                } else {
                                    Image(systemName: "sparkles")
                                        .font(.system(size: 10))
                                        .foregroundStyle(VitruvianCodeTheme.warmCoral)
                                }
                                Text(pill ?? strings.thinkingProcess)
                                    .font(.system(size: 11, weight: .medium))
                                    .foregroundStyle(.secondary)
                                    .monospacedDigit()
                                if !thinkingText.isEmpty {
                                    Image(systemName: showingThinking ? "chevron.up" : "chevron.down")
                                        .font(.system(size: 8, weight: .bold))
                                        .foregroundStyle(.secondary.opacity(0.8))
                                }
                            }
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(Capsule().fill(VitruvianCodeTheme.warmCoral.opacity(0.12)))
                        }
                        .buttonStyle(.plain)

                        if showingThinking && !thinkingText.isEmpty {
                            Text(thinkingText)
                                .font(.system(size: 11))
                                .foregroundStyle(.secondary)
                                .padding(8)
                                .background(RoundedRectangle(cornerRadius: 6).fill(Color.primary.opacity(0.03)))
                        }
                    }
                }

                if !isUser, let req = message.approvalRequest {
                    VitruvianCodeApprovalCardView(
                        request: req,
                        strings: strings,
                        onDecision: onDecision,
                        onOptionSelected: onApprovalOption
                    )
                }

                if !isUser, let question = message.question {
                    AgentFormCard(
                        question: question,
                        status: message.questionStatus ?? .pending,
                        strings: strings,
                        errorScheme: errorScheme,
                        workingDirectory: workingDirectory,
                        isShortcutActive: isFirstPendingQuestion,
                        onAnswer: { answers in onAnswerQuestion?(answers) },
                        onSkip: { onSkipQuestion?() }
                    )
                }

                if !message.text.isEmpty {
                    VitruvianCodeMarkdownContentView(
                        text: message.text,
                        strings: strings,
                        errorScheme: errorScheme,
                        isError: message.isError,
                        workingDirectory: workingDirectory
                    )
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .fill(isUser ? VitruvianCodeTheme.warmCoral.opacity(0.25) : Color.white.opacity(0.065))
                            .overlay(
                                RoundedRectangle(cornerRadius: 14, style: .continuous)
                                    .strokeBorder(isUser ? VitruvianCodeTheme.warmCoral.opacity(0.4) : Color.white.opacity(0.08), lineWidth: 0.5)
                            )
                    )
                }

                if !isUser && message.stopReason == "interrupted" {
                    HStack(spacing: 4) {
                        Image(systemName: "bolt.slash.fill")
                            .font(.system(size: 9.5))
                            .foregroundStyle(.orange)
                        Text(strings.turnInterrupted)
                            .font(.system(size: 10.5, weight: .semibold))
                            .foregroundStyle(.orange)
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(Capsule().fill(Color.orange.opacity(0.12)))
                }

                Button(action: copyContent) {
                    HStack(spacing: 4) {
                        Image(systemName: copied ? "checkmark" : "doc.on.doc")
                        Text(copied ? strings.copiedMessage : strings.copy)
                    }
                    .font(.caption2)
                    .foregroundStyle(copied ? VitruvianCodeTheme.warmCoral : Color.secondary)
                    .scaleEffect(copyBounce ? 1.25 : 1.0)
                    .animation(.spring(response: 0.25, dampingFraction: 0.5), value: copyBounce)
                }
                .buttonStyle(.plain)
                .opacity(hovering || copied ? 1 : 0)

                if !isUser && (message.durationMs != nil || message.outputTokens != nil) {
                    VStack(alignment: .leading, spacing: 4) {
                        Button {
                            withAnimation(.easeInOut(duration: 0.2)) {
                                showingStats.toggle()
                            }
                        } label: {
                            HStack(spacing: 0) {
                                let parts = buildStatsParts()
                                ForEach(Array(parts.enumerated()), id: \.offset) { i, part in
                                    if i > 0 { Text(" · ") }
                                    Text(part)
                                }
                                Text("  ")
                                Image(systemName: showingStats ? "chevron.up" : "chevron.down")
                                    .font(.system(size: 7, weight: .bold))
                            }
                            .foregroundStyle(.tertiary)
                            .font(.system(size: 9, weight: .medium, design: .rounded))
                        }
                        .buttonStyle(.plain)

                        if showingStats {
                            VStack(alignment: .leading, spacing: 3) {
                                if let model = message.modelName { statsRow(strings.statsModel, model) }
                                if let ms = message.durationMs { statsRow(strings.statsDuration, String(format: "%.1fs", locale: Locale.current, Double(ms) / 1000.0)) }
                                if let input = message.inputTokens { statsRow(strings.statsInput, "\(formatTokenCount(input))\(strings.statsTokensSuffix)") }
                                if let output = message.outputTokens { statsRow(strings.statsOutput, "\(formatTokenCount(output))\(strings.statsTokensSuffix)") }
                                if let cached = message.cachedTokens, cached > 0 { statsRow(strings.statsCached, "\(formatTokenCount(cached))\(strings.statsTokensSuffix)") }
                                if let cost = message.totalCostUSD, cost > 0 { statsRow(strings.statsCost, String(format: "$%.4f", locale: Locale.current, cost)) }
                                if let tools = message.toolCalls, tools > 0 { statsRow(strings.statsToolCalls, "\(tools)") }
                                if let turns = message.numTurns, turns > 0 { statsRow(strings.statsTurns, "\(turns)") }
                                if let reason = message.stopReason { statsRow(strings.statsStatus, reason) }
                            }
                            .padding(.horizontal, 8)
                            .padding(.vertical, 6)
                            .background(
                                RoundedRectangle(cornerRadius: 8, style: .continuous)
                                    .fill(Color.primary.opacity(0.03))
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                                            .strokeBorder(Color.primary.opacity(0.06), lineWidth: 0.5)
                                    )
                            )
                            .transition(.opacity.combined(with: .move(edge: .top)))
                        }
                    }
                }
            }
            .contentShape(Rectangle())
            .onHover { hovering = $0 }

            if isUser {
                Text(String(NSFullUserName().prefix(1)).uppercased())
                    .font(.system(size: 10, weight: .semibold, design: .rounded))
                    .foregroundStyle(.linearGradient(
                        colors: [VitruvianCodeTheme.warmCoralLight, VitruvianCodeTheme.warmCoral],
                        startPoint: .top, endPoint: .bottom
                    ))
                    .frame(width: 22, height: 22)
                    .background(Circle().fill(VitruvianCodeTheme.warmCoral.opacity(0.18)))
                    .padding(.top, 4)
            }

            if !isUser { Spacer(minLength: 40) }
        }
    }

    /// Inline Markdown for a line of the reply, with `file:line`
    /// references turned into links first.
    private func markdown(_ text: String) -> AttributedString {
        Self.markdown(text, workingDirectory: workingDirectory)
    }

    static func markdown(_ text: String, workingDirectory: String?) -> AttributedString {
        let linked = VitruvianCodePathLinks.linkify(text, workingDirectory: workingDirectory)
        let options = AttributedString.MarkdownParsingOptions(interpretedSyntax: .inlineOnlyPreservingWhitespace)
        return (try? AttributedString(markdown: linked, options: options)) ?? AttributedString(text)
    }

    /// A link in the reply: a file opens in the app that opens it (the
    /// `#L` line in its fragment is not something every app can take);
    /// anything else goes where the system sends it.
    static func open(_ url: URL) -> OpenURLAction.Result {
        guard url.isFileURL else { return .systemAction }
        NSWorkspace.shared.open(URL(fileURLWithPath: url.path))
        return .handled
    }
}

/// The compact line about a reply's reasoning: "Thought for 4s · 320 tok",
/// or "Thinking… · 420 tok" while it is still being written.
public enum VitruvianCodeThinkingPill {
    public static func label(durationMs: Int?, tokens: Int?, isStreaming: Bool, strings: VitruvianCodeChatStrings) -> String? {
        guard durationMs != nil || tokens != nil else { return nil }
        var parts: [String] = []
        if let durationMs {
            parts.append(strings.thoughtForPrefix + duration(durationMs))
        } else if isStreaming {
            parts.append(strings.thinkingNow)
        } else {
            parts.append(strings.thoughtLabel)
        }
        if let tokens, tokens > 0 {
            parts.append(tokenCount(tokens) + strings.tokensShortSuffix)
        }
        return parts.joined(separator: " · ")
    }

    public static func duration(_ ms: Int) -> String {
        let seconds = Int((Double(ms) / 1000).rounded())
        if seconds < 1 { return "<1s" }
        if seconds < 60 { return "\(seconds)s" }
        let minutes = seconds / 60
        let rest = seconds % 60
        return rest == 0 ? "\(minutes)m" : "\(minutes)m \(rest)s"
    }

    static func tokenCount(_ count: Int) -> String {
        if count >= 1000 {
            return String(format: "%.1fK", locale: Locale.current, Double(count) / 1000.0)
        }
        return "\(count)"
    }
}
