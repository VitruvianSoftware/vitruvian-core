// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 VitruvianSoftware
//
// Adapted from the standalone Nexus Agent app (apps/desktop/nexus-agent,
// MIT, Copyright (c) 2026 VitruvianSoftware): its Quick Prompt window.

import AppKit
import SwiftUI
import VitruvianCore
import VitruvianDesign
import VitruvianServices

/// The Quick Prompt card: a header to drag it by, the conversation, and the
/// prompt field. Return sends, Shift-Return adds a line, Esc closes.
package struct NexusAgentQuickPromptView: View {
    @ObservedObject private var service = NexusAgentService.shared
    @ObservedObject private var session = NexusAgentService.shared.session
    @ObservedObject private var l10n = L10n.shared
    @FocusState private var inputFocused: Bool

    package init() {}

    private var strings: NexusAgentFeatureStrings { FeatureStrings.nexusAgent(l10n.language) }
    private var canSend: Bool {
        !session.isRunning && !session.draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    package var body: some View {
        VStack(spacing: 0) {
            header
            Divider().opacity(0.5)
            conversation
            Divider().opacity(0.5)
            input
        }
        .frame(minWidth: 380, minHeight: 280)
        .background(HUDBackdrop(cornerRadius: 14))
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(Color.white.opacity(0.12), lineWidth: 1)
        )
        .onAppear { inputFocused = true }
        .onChange(of: session.focusSerial) { _, _ in inputFocused = true }
    }

    private var header: some View {
        HStack(spacing: 8) {
            Label(strings.quickPromptTitle, systemImage: "paperplane")
                .font(.system(size: 13, weight: .semibold))
            Spacer()
            Button(strings.newChat) { session.newChat() }
                .buttonStyle(.borderless)
                .controlSize(.small)
                .disabled(session.messages.isEmpty)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 9)
        .background(QuickPromptDragHandle())
    }

    private var conversation: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 8) {
                    if session.messages.isEmpty {
                        Text(strings.quickPromptCaption)
                            .font(.callout)
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity, alignment: .center)
                            .multilineTextAlignment(.center)
                            .padding(.top, 40)
                    }
                    ForEach(session.messages) { message in
                        if !(message.role == .agent && message.text.isEmpty) {
                            bubble(message)
                        }
                    }
                    if session.isRunning { progress }
                    Color.clear.frame(height: 1).id(Self.bottomID)
                }
                .padding(12)
            }
            .onChange(of: session.messages) { _, _ in proxy.scrollTo(Self.bottomID, anchor: .bottom) }
            .onChange(of: session.isRunning) { _, _ in proxy.scrollTo(Self.bottomID, anchor: .bottom) }
        }
    }

    private static let bottomID = "nexusAgentBottom"

    private func bubble(_ message: NexusAgentChatMessage) -> some View {
        let isUser = message.role == .user
        return HStack {
            if isUser { Spacer(minLength: 40) }
            Text(message.text)
                .font(.system(size: 13))
                .textSelection(.enabled)
                .foregroundStyle(message.isError ? Color.orange : Color.primary)
                .padding(.horizontal, 10)
                .padding(.vertical, 7)
                .background(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(isUser ? Color.accentColor.opacity(0.22) : Color.primary.opacity(0.06))
                )
                .frame(maxWidth: .infinity, alignment: isUser ? .trailing : .leading)
            if !isUser { Spacer(minLength: 40) }
        }
    }

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

    private var input: some View {
        HStack(alignment: .bottom, spacing: 8) {
            TextField(strings.promptPlaceholder, text: $session.draft, axis: .vertical)
                .textFieldStyle(.plain)
                .font(.system(size: 13))
                .lineLimit(1...6)
                .focused($inputFocused)
                .onSubmit { if canSend { service.sendQuickPrompt() } }
            if session.isRunning {
                Button(strings.stopReply) { session.stop() }
                    .controlSize(.small)
            } else {
                Button(strings.send) { service.sendQuickPrompt() }
                    .controlSize(.small)
                    .disabled(!canSend)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
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
