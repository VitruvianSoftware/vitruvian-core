// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 VitruvianSoftware
//
// Adapted from the standalone Nexus Agent app (apps/desktop/nexus-agent,
// MIT, Copyright (c) 2026 VitruvianSoftware): its Spotlight-style Quick
// Prompt window, its sessions drawer and its chat view.

import AppKit
import SwiftUI
import VitruvianCore
import VitruvianDesign
import VitruvianServices

/// The Spotlight-style Quick Prompt: a floating pill with the prompt, a
/// recent-sessions drawer that opens under it, and the streaming chat with
/// a follow-up bar. Return sends, Shift-Return adds a line, Esc closes.
/// Sizes come from `NexusAgentQuickPromptLayout`; the service resizes the
/// panel when `session.mode` changes.
package struct NexusAgentQuickPromptView: View {
    @ObservedObject private var service = NexusAgentService.shared
    @ObservedObject private var session = NexusAgentService.shared.session
    @ObservedObject private var l10n = L10n.shared
    @FocusState private var inputFocused: Bool

    package init() {}

    private typealias Layout = NexusAgentQuickPromptLayout
    private var strings: NexusAgentFeatureStrings { FeatureStrings.nexusAgent(l10n.language) }
    private var shape: RoundedRectangle { RoundedRectangle(cornerRadius: Layout.cornerRadius, style: .continuous) }

    package var body: some View {
        VStack(spacing: 0) {
            if session.mode == .chat {
                chatHeader
                Divider().opacity(0.5)
                conversation
                Divider().opacity(0.5)
                followUpBar
            } else {
                pill
                if session.mode == .sessions {
                    Divider().opacity(0.5)
                    drawer
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(HUDBackdrop(cornerRadius: Layout.cornerRadius))
        .clipShape(shape)
        .overlay(shape.strokeBorder(Color.white.opacity(0.12), lineWidth: 1))
        .onAppear { inputFocused = true }
        .onChange(of: session.focusSerial) { _, _ in inputFocused = true }
        .onChange(of: session.mode) { _, _ in inputFocused = true }
    }

    // MARK: - Pill

    private var pill: some View {
        HStack(spacing: 12) {
            sparkles
            TextField(strings.promptPlaceholder, text: $session.draft)
                .textFieldStyle(.plain)
                .font(.system(size: 18))
                .focused($inputFocused)
                .onSubmit { if session.canSend { service.sendQuickPrompt() } }
            sessionsButton
            planButton
            sendButton
        }
        .padding(.horizontal, 20)
        .frame(height: Layout.compactHeight)
    }

    private var sparkles: some View {
        Image(systemName: "sparkles")
            .font(.system(size: 20, weight: .semibold))
            .foregroundStyle(LinearGradient(colors: [.purple, .blue, .cyan],
                                            startPoint: .topLeading, endPoint: .bottomTrailing))
            .frame(width: 28, height: 28)
            .background(QuickPromptDragHandle())
            .accessibilityHidden(true)
    }

    private var sessionsButton: some View {
        modeButton(icon: "clock.arrow.circlepath", active: session.mode == .sessions,
                   tint: .accentColor, help: strings.sessionsToggle) {
            session.toggleSessions(configuration: service.configuration)
        }
    }

    private var planButton: some View {
        modeButton(icon: session.planMode ? "doc.text.fill" : "doc.text", active: session.planMode,
                   tint: .orange, help: session.planMode ? strings.planModeOn : strings.planModeOff) {
            session.planMode.toggle()
        }
    }

    private func modeButton(icon: String, active: Bool, tint: Color, help: String,
                            action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(active ? tint : Color.secondary)
                .frame(width: 30, height: 30)
                .background(Circle().fill(active ? tint.opacity(0.15) : Color.primary.opacity(0.05)))
        }
        .buttonStyle(.plain)
        .help(help)
        .accessibilityLabel(help)
        .accessibilityAddTraits(active ? .isSelected : [])
    }

    @ViewBuilder
    private var sendButton: some View {
        if session.isRunning {
            circleButton(icon: "stop.fill", enabled: true, label: strings.stopReply) { session.stop() }
        } else {
            circleButton(icon: "arrow.up", enabled: session.canSend, label: strings.send) {
                service.sendQuickPrompt()
            }
        }
    }

    private func circleButton(icon: String, enabled: Bool, label: String,
                              action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: 14, weight: .bold))
                .foregroundStyle(Color.white)
                .frame(width: 32, height: 32)
                .background(Circle().fill(enabled ? Color.accentColor : Color.secondary.opacity(0.3)))
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
        .help(label)
        .accessibilityLabel(label)
    }

    // MARK: - Sessions drawer

    private var drawer: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Image(systemName: "line.3.horizontal.decrease").foregroundStyle(.secondary)
                TextField(strings.sessionsFilter, text: $session.sessionFilter)
                    .textFieldStyle(.plain)
                    .font(.system(size: 13))
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(Color.primary.opacity(0.05)))
            ScrollView {
                LazyVStack(spacing: 6) {
                    if session.filteredSessions.isEmpty {
                        Text(strings.noSessions)
                            .font(.callout)
                            .foregroundStyle(.secondary)
                            .padding(.top, 24)
                    }
                    ForEach(session.filteredSessions) { summary in
                        sessionCard(summary)
                    }
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
    }

    private func sessionCard(_ summary: NexusAgentSessionSummary) -> some View {
        Button { session.resume(summary) } label: {
            HStack(spacing: 10) {
                Image(systemName: "bubble.left.and.text.bubble.right").foregroundStyle(.secondary)
                Text(summary.title.isEmpty ? strings.untitledSession : summary.title)
                    .font(.system(size: 13, weight: .medium))
                    .lineLimit(1)
                Spacer(minLength: 8)
                if let modified = summary.modified {
                    Text(modified, format: .relative(presentation: .named))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(Color.primary.opacity(0.05)))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    // MARK: - Chat

    private var chatHeader: some View {
        HStack(spacing: 8) {
            sparkles
            Text(strings.quickPromptTitle).font(.system(size: 13, weight: .semibold))
            Spacer()
            sessionsButton
            Button(strings.newChat) { session.newChat() }
                .buttonStyle(.borderless)
                .controlSize(.small)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .background(QuickPromptDragHandle())
    }

    private var conversation: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 10) {
                    ForEach(session.messages) { message in
                        if !(message.role == .agent && message.text.isEmpty) {
                            NexusAgentMessageBubble(message: message)
                        }
                    }
                    if session.isRunning { progress }
                    Color.clear.frame(height: 1).id(Self.bottomID)
                }
                .padding(14)
            }
            .onChange(of: session.messages) { _, _ in proxy.scrollTo(Self.bottomID, anchor: .bottom) }
            .onChange(of: session.isRunning) { _, _ in proxy.scrollTo(Self.bottomID, anchor: .bottom) }
        }
    }

    private static let bottomID = "nexusAgentBottom"

    private var progress: some View {
        HStack(spacing: 6) {
            ProgressView().controlSize(.small)
            if let tool = session.activity {
                Text(strings.working)
                Text(tool).font(.system(size: 11, design: .monospaced))
            } else {
                Text(strings.thinking)
            }
        }
        .font(.caption)
        .foregroundStyle(.secondary)
    }

    private var followUpBar: some View {
        HStack(alignment: .bottom, spacing: 8) {
            planButton
            TextField(strings.followUpPlaceholder, text: $session.draft, axis: .vertical)
                .textFieldStyle(.plain)
                .font(.system(size: 14))
                .lineLimit(1...6)
                .focused($inputFocused)
                .onSubmit { if session.canSend { service.sendQuickPrompt() } }
                .padding(.horizontal, 10)
                .padding(.vertical, 7)
                .background(RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .strokeBorder(session.planMode ? Color.orange.opacity(0.5) : Color.primary.opacity(0.12)))
            sendButton
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
    }
}

/// One chat bubble: prose with inline markdown, fenced code in its own box.
private struct NexusAgentMessageBubble: View {
    let message: NexusAgentChatMessage

    var body: some View {
        let isUser = message.role == .user
        HStack {
            if isUser { Spacer(minLength: 60) }
            VStack(alignment: .leading, spacing: 6) {
                ForEach(Array(NexusAgentReplyBlock.parse(message.text).enumerated()), id: \.offset) { _, block in
                    switch block {
                    case .text(let text):
                        Text(Self.markdown(text))
                            .font(.system(size: 13))
                            .foregroundStyle(message.isError ? Color.orange : Color.primary)
                    case .code(_, let body):
                        ScrollView(.horizontal, showsIndicators: false) {
                            Text(body).font(.system(size: 12, design: .monospaced)).padding(8)
                        }
                        .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(Color.black.opacity(0.25)))
                    }
                }
            }
            .textSelection(.enabled)
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .background(RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(isUser ? Color.accentColor.opacity(0.22) : Color.primary.opacity(0.06)))
            if !isUser { Spacer(minLength: 60) }
        }
    }

    private static func markdown(_ text: String) -> AttributedString {
        let options = AttributedString.MarkdownParsingOptions(interpretedSyntax: .inlineOnlyPreservingWhitespace)
        return (try? AttributedString(markdown: text, options: options)) ?? AttributedString(text)
    }
}

/// A transparent strip behind the header that moves the panel when dragged;
/// the conversation below stays free for text selection.
private struct QuickPromptDragHandle: NSViewRepresentable {
    func makeNSView(context: Context) -> DragHandleView {
        DragHandleView()
    }

    func updateNSView(_ nsView: DragHandleView, context: Context) {}

    final class DragHandleView: NSView {
        override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

        override func mouseDown(with event: NSEvent) {
            window?.performDrag(with: event)
        }
    }
}
