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

    @State private var isHovered = false
    @State private var isActionHovered = false

    var body: some View {
        Button {
            session.resume(summary, configuration: engine.configuration)
        } label: {
            HStack(spacing: 10) {
                Image(systemName: summary.isArchived ? "archivebox" : "bubble.left.and.text.bubble.right")
                    .foregroundStyle(NexusAgentTheme.warmCoral)
                Text(summary.title.isEmpty ? strings.untitledSession : summary.title)
                    .font(.system(size: 13, weight: .medium))
                    .lineLimit(1)
                Spacer(minLength: 8)
                if isHovered {
                    actionButton
                        .transition(.opacity.combined(with: .scale(scale: 0.85)))
                } else if let modified = summary.modified {
                    Text(modified, format: .relative(presentation: .named))
                        .font(.caption)
                        .foregroundStyle(NexusAgentTheme.warmCoral.opacity(0.85))
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(Color.white.opacity(isHovered ? 0.09 : 0.055))
                    .overlay(
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .strokeBorder(Color.white.opacity(isHovered ? 0.14 : 0.07), lineWidth: 0.5)
                    )
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
        .contextMenu {
            // Only agy's conversations can be deleted; the engine refuses
            // any other provider's, so the item is not offered for them.
            if engine.activeProvider.id == NexusAgentCLIProvider.antigravity.id {
                Button(role: .destructive) {
                    session.delete(summary, configuration: engine.configuration)
                } label: {
                    Label(engine.hostStrings.deleteSession, systemImage: "trash")
                }
            }
        }
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
