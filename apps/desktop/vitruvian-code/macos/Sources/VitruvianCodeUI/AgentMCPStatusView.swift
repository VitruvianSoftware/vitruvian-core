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
import SwiftUI
import VitruvianCodeCore

/// The words of the MCP status panel, chosen from the chat strings.
public enum AgentMCPStatusLabels {
    public static func state(_ state: AgentMCPServerStatus.State, strings: VitruvianCodeChatStrings) -> String {
        switch state {
        case .connected: return strings.mcpStateConnected
        case .failed: return strings.mcpStateFailed
        case .needsSignIn: return strings.mcpStateNeedsSignIn
        case .pending: return strings.mcpStatePending
        case .disabled: return strings.mcpStateDisabled
        case .unknown: return strings.mcpStateUnknown
        }
    }

    public static func source(_ source: AgentMCPServerStatus.Source, strings: VitruvianCodeChatStrings) -> String {
        switch source {
        case .claudeUser: return strings.mcpSourceClaudeUser
        case .claudeLocal: return strings.mcpSourceClaudeLocal
        case .claudeProject: return strings.mcpSourceClaudeProject
        case .claudeAI: return strings.mcpSourceClaudeAI
        case .claudeManaged: return strings.mcpSourceClaudeManaged
        case .claudePlugin: return strings.mcpSourceClaudePlugin
        case .claudeAgent: return strings.mcpSourceClaudeAgent
        case .claudeOther: return strings.mcpSourceClaudeOther
        case .agySettings: return strings.mcpSourceAgy
        }
    }

    /// The colour of a state's dot: green connected, red failed, amber waiting, grey otherwise.
    public static func color(_ state: AgentMCPServerStatus.State) -> Color {
        switch state {
        case .connected: return .green
        case .failed: return .red
        case .needsSignIn, .pending: return .orange
        case .disabled, .unknown: return .secondary
        }
    }
}

/// The list of the MCP servers a live chat's agent loaded: name, state, and where each is
/// configured, with Show in Finder for the file where there is one. Each agent owns its MCP
/// config; this only shows it.
public struct AgentMCPStatusView: View {
    public let panel: AgentMCPStatusPanel
    public let strings: VitruvianCodeChatStrings
    public let onRefresh: () -> Void
    public var reveal: (String) -> Void

    public init(
        panel: AgentMCPStatusPanel,
        strings: VitruvianCodeChatStrings,
        onRefresh: @escaping () -> Void,
        reveal: @escaping (String) -> Void = { path in
            NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: path)])
        }
    ) {
        self.panel = panel
        self.strings = strings
        self.onRefresh = onRefresh
        self.reveal = reveal
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(strings.mcpStatusButton)
                    .font(.system(size: 12, weight: .semibold))
                Spacer()
                if panel.isLoading {
                    ProgressView().controlSize(.mini)
                }
                Button(strings.mcpStatusRefresh, action: onRefresh)
                    .controlSize(.small)
                    .buttonStyle(.plain)
                    .foregroundStyle(VitruvianCodeTheme.warmCoral)
                    .disabled(panel.isLoading)
            }
            Text(strings.mcpStatusExplanation)
                .font(.system(size: 10.5))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            if let problem = panel.problem {
                AgentBannerLogic.verbatimText(Self.problemText(problem, strings: strings))
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            } else if panel.servers.isEmpty && !panel.isLoading {
                Text(strings.mcpStatusNone)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }

            ScrollView {
                VStack(alignment: .leading, spacing: 6) {
                    ForEach(panel.servers) { server in
                        row(server)
                    }
                }
            }
            .frame(maxHeight: 320)
        }
        .padding(12)
        .frame(width: 340)
    }

    public static func problemText(_ problem: AgentMCPStatusPanel.Problem, strings: VitruvianCodeChatStrings) -> String {
        switch problem {
        case .notConnected: return strings.mcpStatusNotConnected
        case .failed(let message): return strings.mcpStatusFailedPrefix + message
        }
    }

    private func row(_ server: AgentMCPServerStatus) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Circle()
                .fill(AgentMCPStatusLabels.color(server.state))
                .frame(width: 7, height: 7)
                .padding(.top, 4)
            VStack(alignment: .leading, spacing: 1) {
                AgentBannerLogic.verbatimText(server.name)
                    .font(.system(size: 11.5, weight: .medium))
                    .lineLimit(1)
                    .truncationMode(.middle)
                Text("\(AgentMCPStatusLabels.state(server.state, strings: strings)) · \(AgentMCPStatusLabels.source(server.source, strings: strings))")
                    .font(.system(size: 10.5))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                if let detail = server.detail {
                    AgentBannerLogic.verbatimText(detail)
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundStyle(.red.opacity(0.85))
                        .lineLimit(3)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            if let path = server.configPath {
                Button {
                    reveal(path)
                } label: {
                    Image(systemName: "folder")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .help(strings.mcpStatusReveal)
                .accessibilityLabel(strings.mcpStatusReveal)
            }
        }
    }
}
