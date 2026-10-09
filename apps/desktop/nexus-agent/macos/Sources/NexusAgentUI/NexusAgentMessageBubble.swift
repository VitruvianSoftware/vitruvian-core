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

/// An interactive tool execution approval card shown within a message bubble.
struct NexusAgentApprovalCardView: View {
    let request: NexusAgentApprovalRequest
    let strings: NexusAgentChatStrings
    let onDecision: ((NexusAgentApprovalRequest.Status) -> Void)?
    @State private var hoveredButton: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Image(systemName: "hand.raised.fill")
                    .font(.system(size: 11))
                    .foregroundStyle(request.status == .pending ? NexusAgentTheme.warmCoral : Color.secondary)
                Text(strings.permissionRequest)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(Color.primary)
                Text(request.toolName)
                    .font(.system(size: 10, weight: .bold, design: .monospaced))
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Capsule().fill(Color.primary.opacity(0.08)))
                Spacer()
                switch request.status {
                case .pending:
                    Text(strings.awaitingConfirmation)
                        .font(.system(size: 9, weight: .medium))
                        .foregroundStyle(NexusAgentTheme.warmCoral)
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
                            .foregroundStyle(NexusAgentTheme.warmCoral)
                        Text(strings.allowedForSession)
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundStyle(NexusAgentTheme.warmCoral)
                    }
                }
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
                        .background(RoundedRectangle(cornerRadius: 6).fill(NexusAgentTheme.warmCoral.opacity(hoveredButton == "session" ? 0.25 : 0.15)))
                        .foregroundStyle(NexusAgentTheme.warmCoral)
                    }
                    .buttonStyle(.plain)
                    .onHover { hoveredButton = $0 ? "session" : nil }

                    Spacer()
                }
                .padding(.top, 2)
            }
        }
        .padding(8)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(Color.primary.opacity(0.03))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .strokeBorder(request.status == .pending ? NexusAgentTheme.warmCoral.opacity(0.3) : Color.primary.opacity(0.08), lineWidth: 1)
        )
    }
}

/// One chat bubble: rich Markdown blocks (headings, lists, quotes, dividers) and interactive code/diagram cards.
struct NexusAgentMessageBubble: View {
    let message: NexusAgentChatMessage
    let strings: NexusAgentChatStrings
    /// Handed on to a diagram in the message.
    let errorScheme: String
    var onDecision: ((NexusAgentApprovalRequest.Status) -> Void)? = nil
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
        let isUser = message.role == .user
        HStack(alignment: .top, spacing: 8) {
            if isUser { Spacer(minLength: 40) }

            if !isUser {
                Image(systemName: "sparkles")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(.linearGradient(
                        colors: [Color(red: 0.92, green: 0.55, blue: 0.42), Color(red: 0.85, green: 0.47, blue: 0.34)],
                        startPoint: .top, endPoint: .bottom
                    ))
                    .frame(width: 22, height: 22)
                    .background(Circle().fill(Color(red: 0.85, green: 0.47, blue: 0.34).opacity(0.18)))
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
                                Image(systemName: "checkmark.circle.fill")
                                    .font(.system(size: 10))
                                    .foregroundStyle(Color.green)
                                Text(toolSteps.count == 1 ? (toolSteps.first?.title ?? strings.oneToolExecutionFinished) : "\(toolSteps.count)\(strings.toolExecutionsFinishedSuffix)")
                                    .font(.system(size: 11, weight: .medium))
                                    .foregroundStyle(.secondary)
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
                            VStack(alignment: .leading, spacing: 3) {
                                ForEach(toolSteps) { step in
                                    HStack(spacing: 6) {
                                        Image(systemName: "terminal")
                                            .font(.system(size: 9))
                                            .foregroundStyle(.secondary)
                                        Text(step.title)
                                            .font(.system(size: 11, design: .monospaced))
                                            .foregroundStyle(.secondary)
                                    }
                                    .padding(.leading, 6)
                                }
                            }
                            .padding(.vertical, 2)
                        }
                    }
                }

                if !isUser, let thinking = message.thinkingText, !thinking.isEmpty {
                    VStack(alignment: .leading, spacing: 4) {
                        Button {
                            withAnimation(.easeInOut(duration: 0.15)) {
                                showingThinking.toggle()
                            }
                        } label: {
                            HStack(spacing: 5) {
                                Image(systemName: "sparkles")
                                    .font(.system(size: 10))
                                    .foregroundStyle(NexusAgentTheme.warmCoral)
                                Text(strings.thinkingProcess)
                                    .font(.system(size: 11, weight: .medium))
                                    .foregroundStyle(.secondary)
                                Image(systemName: showingThinking ? "chevron.up" : "chevron.down")
                                    .font(.system(size: 8, weight: .bold))
                                    .foregroundStyle(.secondary.opacity(0.8))
                            }
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(Capsule().fill(NexusAgentTheme.warmCoral.opacity(0.12)))
                        }
                        .buttonStyle(.plain)

                        if showingThinking {
                            Text(thinking)
                                .font(.system(size: 11))
                                .foregroundStyle(.secondary)
                                .padding(8)
                                .background(RoundedRectangle(cornerRadius: 6).fill(Color.primary.opacity(0.03)))
                        }
                    }
                }

                if !isUser, let req = message.approvalRequest {
                    NexusAgentApprovalCardView(request: req, strings: strings, onDecision: onDecision)
                }

                if !message.text.isEmpty {
                    VStack(alignment: .leading, spacing: 6) {
                        ForEach(Array(NexusAgentReplyBlock.parse(message.text).enumerated()), id: \.offset) { _, block in
                            switch block {
                            case .text(let text):
                                VStack(alignment: .leading, spacing: 6) {
                                    ForEach(Array(NexusAgentMarkdownBlock.parse(text).enumerated()), id: \.offset) { _, mdBlock in
                                        switch mdBlock {
                                        case .heading(let level, let headingText):
                                            Text(Self.markdown(headingText))
                                                .font(.system(size: level == 1 ? 15 : (level == 2 ? 14 : 13), weight: .bold))
                                                .foregroundStyle(message.isError ? NexusAgentTheme.warmCoral : Color.primary)
                                                .padding(.vertical, 2)
                                        case .bulletItem(let bulletText):
                                            HStack(alignment: .top, spacing: 6) {
                                                Image(systemName: "circle.fill")
                                                    .font(.system(size: 4))
                                                    .foregroundStyle(Color(red: 0.85, green: 0.47, blue: 0.34))
                                                    .padding(.top, 6)
                                                Text(Self.markdown(bulletText))
                                                    .font(.system(size: 13))
                                                    .foregroundStyle(message.isError ? NexusAgentTheme.warmCoral : Color.primary)
                                            }
                                        case .numberedItem(let number, let itemText):
                                            HStack(alignment: .top, spacing: 6) {
                                                Text("\(number).")
                                                    .font(.system(size: 12, weight: .medium, design: .rounded))
                                                    .foregroundStyle(.secondary)
                                                    .padding(.top, 1)
                                                Text(Self.markdown(itemText))
                                                    .font(.system(size: 13))
                                                    .foregroundStyle(message.isError ? NexusAgentTheme.warmCoral : Color.primary)
                                            }
                                        case .blockquote(let quoteText):
                                            HStack(alignment: .top, spacing: 8) {
                                                RoundedRectangle(cornerRadius: 1.5)
                                                    .fill(Color(red: 0.85, green: 0.47, blue: 0.34).opacity(0.7))
                                                    .frame(width: 3)
                                                Text(Self.markdown(quoteText))
                                                    .font(.system(size: 13))
                                                    .italic()
                                                    .foregroundStyle(.secondary)
                                            }
                                            .padding(.vertical, 2)
                                        case .divider:
                                            Divider()
                                                .opacity(0.4)
                                                .padding(.vertical, 4)
                                        case .paragraph(let paragraphText):
                                            Text(Self.markdown(paragraphText))
                                                .font(.system(size: 13))
                                                .foregroundStyle(message.isError ? NexusAgentTheme.warmCoral : Color.primary)
                                        }
                                    }
                                }
                            case .code(let language, let body):
                                if let lang = language?.lowercased(), lang == "mermaid" {
                                    NexusAgentMermaidCard(source: body, strings: strings, errorScheme: errorScheme)
                                } else {
                                    NexusAgentCodeBlockView(language: language, bodyText: body, strings: strings)
                                }
                            }
                        }
                    }
                    .textSelection(.enabled)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .fill(isUser ? Color(red: 0.85, green: 0.47, blue: 0.34).opacity(0.25) : Color.white.opacity(0.065))
                            .overlay(
                                RoundedRectangle(cornerRadius: 14, style: .continuous)
                                    .strokeBorder(isUser ? Color(red: 0.85, green: 0.47, blue: 0.34).opacity(0.4) : Color.white.opacity(0.08), lineWidth: 0.5)
                            )
                    )
                }

                Button(action: copyContent) {
                    HStack(spacing: 4) {
                        Image(systemName: copied ? "checkmark" : "doc.on.doc")
                        Text(copied ? strings.copiedMessage : strings.copy)
                    }
                    .font(.caption2)
                    .foregroundStyle(copied ? NexusAgentTheme.warmCoral : Color.secondary)
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
            .onTapGesture(count: 2) { copyContent() }
            .contentShape(Rectangle())
            .onHover { hovering = $0 }

            if isUser {
                Text(String(NSFullUserName().prefix(1)).uppercased())
                    .font(.system(size: 10, weight: .semibold, design: .rounded))
                    .foregroundStyle(.linearGradient(
                        colors: [Color(red: 0.92, green: 0.55, blue: 0.42), Color(red: 0.85, green: 0.47, blue: 0.34)],
                        startPoint: .top, endPoint: .bottom
                    ))
                    .frame(width: 22, height: 22)
                    .background(Circle().fill(Color(red: 0.85, green: 0.47, blue: 0.34).opacity(0.18)))
                    .padding(.top, 4)
            }

            if !isUser { Spacer(minLength: 40) }
        }
    }

    private static func markdown(_ text: String) -> AttributedString {
        let options = AttributedString.MarkdownParsingOptions(interpretedSyntax: .inlineOnlyPreservingWhitespace)
        return (try? AttributedString(markdown: text, options: options)) ?? AttributedString(text)
    }
}
