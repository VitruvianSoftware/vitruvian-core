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

struct NexusAgentSessionRow: View {
    let summary: NexusAgentSessionSummary
    @ObservedObject var session: NexusAgentQuickPromptSession
    @ObservedObject var engine: NexusAgentEngine
    let strings: NexusAgentChatStrings
    /// The arrow keys have this row: it is tinted, and shows that Return
    /// opens it.
    var isSelected = false
    /// Told when the pointer comes over the row or leaves it, so the
    /// drawer can let go of a keyboard selection.
    var onHover: (Bool) -> Void = { _ in }

    @State private var isHovered = false
    @State private var isActionHovered = false
    /// The name being typed while the row is renamed.
    @State private var renameDraft = ""
    @FocusState private var renameFocused: Bool
    /// The live dot's breath.
    @State private var livePulse = false

    /// The row's name is open for editing (Rename…).
    private var isRenaming: Bool { session.renamingSessionID == summary.id }

    var body: some View {
        if isRenaming {
            renameRow
        } else {
            row
        }
    }

    /// The row with its name in a field: Return keeps the name, Esc (or
    /// leaving the field) goes back without it.
    private var renameRow: some View {
        HStack(spacing: 10) {
            Image(systemName: "pencil")
                .foregroundStyle(NexusAgentTheme.warmCoral)
            TextField(strings.renameSession, text: $renameDraft)
                .textFieldStyle(.plain)
                .font(.system(size: 13, weight: .medium))
                .focused($renameFocused)
                .onSubmit { session.rename(summary, to: renameDraft) }
                .onExitCommand { session.renamingSessionID = nil }
                .onAppear {
                    renameDraft = summary.title
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) { renameFocused = true }
                }
                .onChange(of: renameFocused) { _, focused in
                    if !focused && isRenaming { session.renamingSessionID = nil }
                }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(rowBackground(highlighted: true))
    }

    private func rowBackground(highlighted: Bool) -> some View {
        RoundedRectangle(cornerRadius: 10, style: .continuous)
            .fill(isSelected ? NexusAgentTheme.warmCoral.opacity(0.2)
                             : Color.white.opacity(highlighted ? 0.09 : 0.055))
            .overlay(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .strokeBorder(highlighted && isRenaming ? NexusAgentTheme.warmCoral.opacity(0.5)
                                                            : Color.white.opacity(highlighted ? 0.14 : 0.07),
                                  lineWidth: 0.5)
            )
    }

    /// A small green dot that breathes while the session's transcript is
    /// being written.
    private var liveDot: some View {
        Circle().fill(Color.green).frame(width: 6, height: 6)
            .opacity(livePulse ? 0.35 : 1)
            .onAppear {
                withAnimation(.easeInOut(duration: 0.9).repeatForever(autoreverses: true)) { livePulse = true }
            }
            .onDisappear { livePulse = false }
            .help(strings.sessionIsLive)
            .accessibilityLabel(strings.sessionIsLive)
    }

    private var row: some View {
        Button {
            resume()
        } label: {
            HStack(spacing: 10) {
                Image(systemName: summary.isArchived ? "archivebox" : "bubble.left.and.text.bubble.right")
                    .foregroundStyle(NexusAgentTheme.warmCoral)
                Text(displayedTitle)
                    .font(.system(size: 13, weight: .medium))
                    .lineLimit(1)
                if summary.isLive { liveDot }
                if summary.isPinned {
                    Image(systemName: "pin.fill")
                        .font(.system(size: 9))
                        .foregroundStyle(NexusAgentTheme.warmCoral.opacity(0.8))
                        .accessibilityLabel(strings.pinSession)
                }
                Spacer(minLength: 8)
                if isHovered {
                    actionButton
                        .transition(.opacity.combined(with: .scale(scale: 0.85)))
                } else if isSelected {
                    Image(systemName: "return")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(.secondary)
                        .accessibilityHidden(true)
                } else if let modified = summary.modified {
                    Text(modified, format: .relative(presentation: .named))
                        .font(.caption)
                        .foregroundStyle(NexusAgentTheme.warmCoral.opacity(0.85))
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(rowBackground(highlighted: isHovered))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        // While Clear All runs, a conversation's files are being removed:
        // it is not opened, and not deleted a second time.
        .disabled(session.isClearingSessions)
        .onHover {
            isHovered = $0
            onHover($0)
        }
        .accessibilityAddTraits(isSelected ? .isSelected : [])
        .contextMenu {
            // The standalone's menu, for every provider's conversations:
            // Resume is a click on the row, and Copy Title takes what the
            // row shows.
            Button(strings.resumeSession) { resume() }
                .disabled(session.isClearingSessions)
            // For a conversation with no title that is the placeholder
            // ("Untitled"), not nothing: the standalone's menu copied the
            // placeholder too, and this is left as it was.
            Button(strings.copySessionTitle) {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(displayedTitle, forType: .string)
            }
            Divider()
            Button {
                session.togglePin(summary)
            } label: {
                if summary.isPinned {
                    Label(strings.unpinSession, systemImage: "pin.slash.fill")
                } else {
                    Label(strings.pinSession, systemImage: "pin")
                }
            }
            Button {
                session.renamingSessionID = summary.id
            } label: {
                Label(strings.renameSession, systemImage: "pencil")
            }
            Button {
                guard !session.isClearingSessions else { return }
                session.fork(summary, configuration: engine.configuration)
            } label: {
                Label(strings.forkSession, systemImage: "arrow.triangle.branch")
            }
            .disabled(session.isClearingSessions)
            // Only agy's conversations can be deleted; the engine refuses
            // any other provider's, so the item is not offered for them.
            if engine.activeProvider.id == NexusAgentCLIProvider.antigravity.id {
                Divider()
                Button(role: .destructive) {
                    session.delete(summary, configuration: engine.configuration)
                } label: {
                    Label(engine.hostStrings.deleteSession, systemImage: "trash")
                }
                .disabled(session.isClearingSessions)
            }
        }
    }

    /// The title as the row shows it: a conversation with none gets the
    /// app's word for that.
    private var displayedTitle: String {
        summary.title.isEmpty ? strings.untitledSession : summary.title
    }

    private func resume() {
        guard !session.isClearingSessions else { return }
        session.resume(summary, configuration: engine.configuration)
    }

    @ViewBuilder
    private var actionButton: some View {
        if !summary.isArchived {
            Button {
                session.archive(summary, configuration: engine.configuration)
            } label: {
                Image(systemName: "archivebox")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.secondary)
                    .scaleEffect(isActionHovered ? 1.15 : 1.0)
                    .animation(.easeInOut(duration: 0.15), value: isActionHovered)
                    .frame(width: 22, height: 22)
                    .background(Circle().fill(Color.primary.opacity(isActionHovered ? 0.12 : 0.05)))
            }
            .buttonStyle(.plain)
            .help(strings.archiveSession)
            .onHover { isActionHovered = $0 }
        } else {
            Button {
                session.unarchive(summary, configuration: engine.configuration)
            } label: {
                Image(systemName: "arrow.uturn.backward.circle")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(.secondary)
                    .scaleEffect(isActionHovered ? 1.15 : 1.0)
                    .animation(.easeInOut(duration: 0.15), value: isActionHovered)
                    .frame(width: 22, height: 22)
                    .background(Circle().fill(Color.primary.opacity(isActionHovered ? 0.12 : 0.05)))
            }
            .buttonStyle(.plain)
            .help(strings.unarchiveSession)
            .onHover { isActionHovered = $0 }
        }
    }
}
