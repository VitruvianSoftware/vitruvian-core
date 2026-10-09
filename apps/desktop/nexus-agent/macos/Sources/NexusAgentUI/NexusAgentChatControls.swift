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

/// A round action button beside the input bar, with a hover highlight.
struct ModularButtonView: View {
    let icon: String
    let isActive: Bool
    let help: String
    var activeColor: Color = NexusAgentTheme.warmCoral
    let action: () -> Void
    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            Group {
                if icon == "clock.fill" {
                    Image(systemName: "clock.fill")
                } else if icon == "clock" {
                    Image(systemName: "clock")
                } else if icon == "doc.text.fill" {
                    Image(systemName: "doc.text.fill")
                } else if icon == "doc.text" {
                    Image(systemName: "doc.text")
                } else if icon == "arrow.triangle.branch" {
                    Image(systemName: "arrow.triangle.branch")
                } else if icon == "folder" {
                    Image(systemName: "folder")
                } else {
                    Image(systemName: icon)
                }
            }
            .font(.system(size: 14, weight: .medium))
                .foregroundStyle(isActive ? activeColor : Color.primary.opacity(isHovered ? 0.7 : 0.45))
                .frame(width: 34, height: 34)
                .background(
                    Circle()
                        .fill(isHovered ? Color.primary.opacity(0.06) : Color.clear)
                )
                .background(
                    Circle()
                        .strokeBorder(Color.primary.opacity(isHovered ? 0.18 : 0.1), lineWidth: 0.5)
                )
                .scaleEffect(isHovered ? 1.08 : 1.0)
                .animation(.easeInOut(duration: 0.15), value: isHovered)
        }
        .buttonStyle(.plain)
        .help(help)
        .accessibilityLabel(help)
        .accessibilityAddTraits(isActive ? .isSelected : [])
        .contentShape(Circle())
        .onHover { hovering in
            isHovered = hovering
        }
    }
}

/// The send arrow inside the input bar; it grows a little under the pointer.
struct SendButtonView: View {
    let isEnabled: Bool
    let label: String
    let action: () -> Void
    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            Image(systemName: "arrow.up.circle.fill")
                .font(.title2)
                .foregroundStyle(isEnabled ? (isHovered ? NexusAgentTheme.warmCoralLight : NexusAgentTheme.warmCoral) : Color.gray)
                .scaleEffect(isHovered && isEnabled ? 1.15 : 1.0)
                .animation(.easeInOut(duration: 0.15), value: isHovered)
        }
        .buttonStyle(.plain)
        .disabled(!isEnabled)
        .help(label)
        .accessibilityLabel(label)
        .onHover { isHovered = $0 }
    }
}

/// A transparent strip behind the header that moves the panel when dragged;
/// the conversation below stays free for text selection.
struct QuickPromptDragHandle: NSViewRepresentable {
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

/// Compact provider picker button beside the prompt bar.
struct ModularProviderButtonView: View {
    @ObservedObject var engine: NexusAgentEngine
    let strings: NexusAgentChatStrings
    @State private var isHovered = false

    var body: some View {
        Menu {
            ForEach(engine.providers) { provider in
                Button {
                    engine.updateActiveProvider(provider)
                } label: {
                    HStack {
                        Text(provider.name)
                        if engine.configuration.activeProvider.id == provider.id {
                            Image(systemName: "checkmark")
                        }
                    }
                }
            }
        } label: {
            Image(systemName: "cpu")
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(Color.primary.opacity(isHovered ? 0.7 : 0.45))
                .frame(width: 34, height: 34)
                .background(Circle().fill(isHovered ? Color.primary.opacity(0.06) : Color.clear))
                .background(Circle().strokeBorder(Color.primary.opacity(isHovered ? 0.18 : 0.1), lineWidth: 0.5))
                .scaleEffect(isHovered ? 1.08 : 1.0)
                .animation(.easeInOut(duration: 0.15), value: isHovered)
        }
        .menuStyle(.borderlessButton)
        .fixedSize()
        .help(strings.switchProvider)
        .onHover { isHovered = $0 }
    }
}

/// Compact provider picker badge for the chat header.
struct ChatProviderBadge: View {
    @ObservedObject var engine: NexusAgentEngine
    let strings: NexusAgentChatStrings
    @State private var isHovered = false

    var body: some View {
        Menu {
            ForEach(engine.providers) { provider in
                Button {
                    engine.updateActiveProvider(provider)
                } label: {
                    HStack {
                        Text(provider.name)
                        if engine.configuration.activeProvider.id == provider.id {
                            Image(systemName: "checkmark")
                        }
                    }
                }
            }
        } label: {
            Text(engine.configuration.activeProvider.name)
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(isHovered ? Color.secondary : Color.secondary.opacity(0.6))
                .padding(.horizontal, 5)
                .padding(.vertical, 2)
                .background(
                    RoundedRectangle(cornerRadius: 4, style: .continuous)
                        .fill(Color.secondary.opacity(isHovered ? 0.15 : 0.1))
                )
        }
        .menuStyle(.borderlessButton)
        .fixedSize()
        .help(strings.switchProvider)
        .onHover { isHovered = $0 }
    }
}

/// Compact clickable model badge for the chat header.
struct ChatModelBadge: View {
    @ObservedObject var engine: NexusAgentEngine
    let strings: NexusAgentChatStrings
    @State private var isEditing = false
    @State private var draft = ""
    @State private var isHovered = false
    @FocusState private var isFocused: Bool

    private var displayName: String {
        let m = engine.configuration.model.trimmingCharacters(in: .whitespaces)
        return m.isEmpty ? strings.autoModel : m
    }

    var body: some View {
        if isEditing {
            TextField(strings.modelNamePlaceholder, text: $draft)
                .textFieldStyle(.plain)
                .font(.system(size: 10, weight: .medium, design: .monospaced))
                .frame(width: 100)
                .padding(.horizontal, 5)
                .padding(.vertical, 2)
                .background(
                    RoundedRectangle(cornerRadius: 4, style: .continuous)
                        .fill(Color.secondary.opacity(0.15))
                        .overlay(
                            RoundedRectangle(cornerRadius: 4, style: .continuous)
                                .strokeBorder(NexusAgentTheme.warmCoral.opacity(0.6), lineWidth: 1)
                        )
                )
                .focused($isFocused)
                .onSubmit {
                    var next = engine.configuration
                    next.model = draft.trimmingCharacters(in: .whitespaces)
                    engine.save(next)
                    isEditing = false
                }
                .onExitCommand { isEditing = false }
        } else {
            Button {
                draft = engine.configuration.model
                isEditing = true
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                    isFocused = true
                }
            } label: {
                Text(displayName)
                    .font(.system(size: 10, weight: .medium, design: engine.configuration.model.isEmpty ? .default : .monospaced))
                    .foregroundStyle(engine.configuration.model.isEmpty
                        ? (isHovered ? Color.secondary : Color.secondary.opacity(0.4))
                        : (isHovered ? Color.secondary : Color.secondary.opacity(0.7)))
                    .padding(.horizontal, 5)
                    .padding(.vertical, 2)
                    .background(
                        RoundedRectangle(cornerRadius: 4, style: .continuous)
                            .fill(Color.secondary.opacity(isHovered ? 0.15 : 0.08))
                    )
            }
            .buttonStyle(.plain)
            .help(engine.configuration.model.isEmpty ? strings.setModel : strings.modelHelpPrefix + engine.configuration.model)
            .onHover { isHovered = $0 }
        }
    }
}

/// Compact badge showing working directory with click to choose.
struct ChatWorkingDirectoryBadge: View {
    @ObservedObject var engine: NexusAgentEngine
    @ObservedObject var session: NexusAgentQuickPromptSession
    let strings: NexusAgentChatStrings
    /// Brings the chat window forward again once the folder picker closes.
    let showWindow: () -> Void
    @State private var isHovered = false

    private var fullDirPath: String {
        session.workingDirectory(for: engine.configuration)
    }

    private var currentDirName: String {
        URL(fileURLWithPath: fullDirPath).lastPathComponent
    }

    var body: some View {
        Button {
            let panel = NSOpenPanel()
            panel.canChooseFiles = false
            panel.canChooseDirectories = true
            panel.allowsMultipleSelection = false
            panel.directoryURL = URL(fileURLWithPath: fullDirPath)
            panel.prompt = strings.setWorkingDirectory

            NSApp.activate(ignoringOtherApps: true)
            if panel.runModal() == .OK, let url = panel.url {
                var next = engine.configuration
                next.workingDirectory = url.path
                engine.save(next)
            }
            showWindow()
        } label: {
            HStack(spacing: 4) {
                Image(systemName: "folder")
                Text(currentDirName)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .frame(maxWidth: 120, alignment: .leading)
            }
            .font(.system(size: 10, weight: .medium))
            .foregroundStyle(isHovered ? Color.secondary : Color.secondary.opacity(0.7))
            .padding(.horizontal, 5)
            .padding(.vertical, 2)
            .background(
                RoundedRectangle(cornerRadius: 4, style: .continuous)
                    .fill(Color.secondary.opacity(isHovered ? 0.15 : 0.08))
            )
        }
        .buttonStyle(.plain)
        .help(strings.workingDirectoryHelpPrefix + fullDirPath + strings.workingDirectoryHelpSuffix)
        .onHover { isHovered = $0 }
    }
}

/// Mode toggle strip above follow-up bar for plan and worktree modes.
struct ModeToggleStrip: View {
    @Binding var planEnabled: Bool
    @Binding var worktreeEnabled: Bool
    var isGitDir: Bool
    var worktreeSupported: Bool
    let strings: NexusAgentChatStrings

    var body: some View {
        HStack(spacing: 6) {
            Button {
                withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                    planEnabled.toggle()
                }
            } label: {
                HStack(spacing: 3) {
                    if planEnabled {
                        Image(systemName: "doc.text.fill")
                            .font(.system(size: 9))
                    } else {
                        Image(systemName: "doc.text")
                            .font(.system(size: 9))
                    }
                    Text(strings.plan)
                        .font(.system(size: 9, weight: .semibold))
                }
                .foregroundStyle(planEnabled ? NexusAgentTheme.warmCoral : Color.secondary.opacity(0.4))
                .padding(.horizontal, 6)
                .padding(.vertical, 3)
                .background(
                    Capsule()
                        .fill(planEnabled ? NexusAgentTheme.warmCoral.opacity(0.18) : Color.clear)
                        .overlay(
                            Capsule()
                                .strokeBorder(planEnabled ? NexusAgentTheme.warmCoral.opacity(0.4) : Color.primary.opacity(0.08), lineWidth: 0.5)
                        )
                )
            }
            .buttonStyle(.plain)
            .help(planEnabled ? strings.planModeOn : strings.planModeOff)

            if isGitDir && worktreeSupported {
                Button {
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                        worktreeEnabled.toggle()
                    }
                } label: {
                    HStack(spacing: 3) {
                        Image(systemName: "arrow.triangle.branch")
                            .font(.system(size: 9))
                        Text(strings.worktree)
                            .font(.system(size: 9, weight: .semibold))
                    }
                    .foregroundStyle(worktreeEnabled ? Color.green : Color.secondary.opacity(0.4))
                    .padding(.horizontal, 6)
                    .padding(.vertical, 3)
                    .background(
                        Capsule()
                            .fill(worktreeEnabled ? Color.green.opacity(0.12) : Color.clear)
                            .overlay(
                                Capsule()
                                    .strokeBorder(worktreeEnabled ? Color.green.opacity(0.3) : Color.primary.opacity(0.08), lineWidth: 0.5)
                            )
                    )
                }
                .buttonStyle(.plain)
                .help(worktreeEnabled ? strings.worktreeModeOn : strings.worktreeModeOff)
            }

            if planEnabled {
                Text(strings.planContext)
                    .font(.system(size: 9))
                    .foregroundStyle(NexusAgentTheme.warmCoral.opacity(0.85))
                    .lineLimit(1)
                    .transition(.opacity.combined(with: .move(edge: .trailing)))
            } else if worktreeEnabled {
                Text(strings.worktreeContext)
                    .font(.system(size: 9))
                    .foregroundStyle(Color.green.opacity(0.7))
                    .lineLimit(1)
                    .transition(.opacity.combined(with: .move(edge: .trailing)))
            }

            Spacer()
        }
        .padding(.horizontal, 14)
        .padding(.top, 4)
    }
}

/// Renders an active subagent status banner replicating the Antigravity UI.
struct ActiveSubagentBannerView: View {
    let subagents: [NexusAgentActiveSubagent]
    let strings: NexusAgentChatStrings
    @State private var isExpanded = false

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Button {
                withAnimation(.spring(response: 0.3, dampingFraction: 0.75)) {
                    isExpanded.toggle()
                }
            } label: {
                HStack(spacing: 8) {
                    ProgressView()
                        .scaleEffect(0.6)
                        .frame(width: 14, height: 14)

                    let count = subagents.count
                    Text("\(count)\(count == 1 ? strings.subagentRunningSuffix : strings.subagentsRunningSuffix)")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(.primary)

                    Spacer()

                    Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(.secondary)
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(Color.primary.opacity(0.06))
                        .overlay(
                            RoundedRectangle(cornerRadius: 8, style: .continuous)
                                .strokeBorder(Color.primary.opacity(0.08), lineWidth: 0.5)
                        )
                )
            }
            .buttonStyle(.plain)

            if isExpanded {
                VStack(alignment: .leading, spacing: 6) {
                    ForEach(subagents) { subagent in
                        HStack(spacing: 8) {
                            ProgressView()
                                .scaleEffect(0.55)
                                .frame(width: 12, height: 12)

                            VStack(alignment: .leading, spacing: 1) {
                                HStack(spacing: 6) {
                                    Text(subagent.role)
                                        .font(.system(size: 12, weight: .medium))
                                        .foregroundStyle(.primary)

                                    Text(subagent.typeName)
                                        .font(.system(size: 10, design: .monospaced))
                                        .foregroundStyle(.secondary)

                                    Spacer()

                                    Text(subagent.model)
                                        .font(.system(size: 9, weight: .bold, design: .monospaced))
                                        .foregroundStyle(NexusAgentTheme.warmCoral)
                                        .padding(.horizontal, 5)
                                        .padding(.vertical, 1)
                                        .background(Capsule().fill(NexusAgentTheme.warmCoral.opacity(0.15)))
                                }

                                if !subagent.prompt.isEmpty {
                                    Text(subagent.prompt)
                                        .font(.system(size: 11))
                                        .foregroundStyle(.secondary)
                                        .lineLimit(1)
                                        .truncationMode(.tail)
                                }
                            }
                        }
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5)
                        .background(RoundedRectangle(cornerRadius: 6, style: .continuous).fill(Color.primary.opacity(0.04)))
                    }
                }
                .padding(6)
                .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(Color.primary.opacity(0.02)))
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
    }
}
