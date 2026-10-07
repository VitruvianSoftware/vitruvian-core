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
import WebKit

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
    /// The pointer is over the pill, which is what brings the action buttons in.
    @State private var isHoveringInput = false
    @State private var sparklePulse = false
    @State private var hoveringPin = false
    @State private var typingDotPhase = 0
    @State private var isNearBottom = true
    @State private var scrollViewHeight: CGFloat = 500
    @State private var hoveringInlineStop = false
    @State private var hoveringNewChat = false
    @State private var hoveringSessions = false

    package init() {}

    private typealias Layout = NexusAgentQuickPromptLayout
    private var strings: NexusAgentFeatureStrings { FeatureStrings.nexusAgent(l10n.language) }
    private var shape: RoundedRectangle { RoundedRectangle(cornerRadius: Layout.cornerRadius, style: .continuous) }

    private var isGitDir: Bool {
        let path = session.workingDirectory(for: service.configuration)
        return NexusAgentSupport.isGitRepo(at: URL(fileURLWithPath: path))
    }

    private var contextualPlaceholder: String {
        if session.mode == .sessions {
            return strings.sessionsFilter
        }
        let providerName = service.activeProvider.name.components(separatedBy: " ").first ?? "Agent"
        return "Ask \(providerName) anything…"
    }

    private var followUpPlaceholder: String {
        if session.planMode {
            return strings.planModeOn
        }
        let providerName = service.activeProvider.name.components(separatedBy: " ").first ?? "Agent"
        return "Follow up with \(providerName)…"
    }

    package var body: some View {
        VStack(spacing: 0) {
            if session.mode == .chat {
                chatHeader
                Divider().opacity(0.5)
                conversation
                Divider().opacity(0.5)
                ModeToggleStrip(
                    planEnabled: $session.planMode,
                    worktreeEnabled: $session.worktreeMode,
                    isGitDir: isGitDir,
                    worktreeSupported: service.configuration.activeProvider.id != NexusAgentCLIProvider.antigravity.id,
                    strings: strings
                )
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

    /// The action buttons show while the pointer is over the pill, and stay
    /// while the sessions drawer is open.
    private var showActionButtons: Bool {
        isHoveringInput || session.mode == .sessions
    }

    private var pill: some View {
        HStack(spacing: 8) {
            inputBar
            if showActionButtons {
                actionButtons
                    .transition(.asymmetric(
                        insertion: .move(edge: .trailing).combined(with: .opacity).combined(with: .scale(scale: 0.8)),
                        removal: .move(edge: .trailing).combined(with: .opacity).combined(with: .scale(scale: 0.8))
                    ))
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .frame(height: Layout.compactHeight)
        .clipped()
        .animation(.spring(response: 0.4, dampingFraction: 0.75), value: showActionButtons)
        .onHover { hovering in
            isHoveringInput = hovering
        }
    }

    private var inputBar: some View {
        HStack(spacing: 12) {
            pulsingSparkles
            TextField(contextualPlaceholder, text: $session.draft)
                .textFieldStyle(.plain)
                .font(.system(size: 18, weight: .regular))
                .focused($inputFocused)
                .onSubmit { if session.canSend { service.sendQuickPrompt() } }
            if !session.draft.isEmpty {
                clearButton
            }
            pillSendButton
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .strokeBorder(Color.primary.opacity(0.08), lineWidth: 0.5)
        )
    }

    private var clearButton: some View {
        Button {
            withAnimation(.easeOut(duration: 0.15)) { session.draft = "" }
        } label: {
            Image(systemName: "xmark.circle.fill")
                .font(.system(size: 14))
                .foregroundStyle(.quaternary)
        }
        .buttonStyle(.plain)
        .transition(.opacity.combined(with: .scale(scale: 0.8)))
    }

    /// The pill's sparkle breathes while the prompt is empty and holds
    /// still once there is text.
    private var pulsingSparkles: some View {
        Image(systemName: "sparkles")
            .font(.title2)
            .foregroundStyle(.linearGradient(colors: [.blue, .purple],
                                             startPoint: .topLeading, endPoint: .bottomTrailing))
            .opacity(sparklePulse ? 0.5 : 1.0)
            .onAppear {
                guard session.draft.isEmpty else { return }
                withAnimation(.easeInOut(duration: 1.8).repeatForever(autoreverses: true)) {
                    sparklePulse = true
                }
            }
            .onChange(of: session.draft.isEmpty) { _, isEmpty in
                if isEmpty {
                    withAnimation(.easeInOut(duration: 1.8).repeatForever(autoreverses: true)) {
                        sparklePulse = true
                    }
                } else {
                    withAnimation(.easeInOut(duration: 0.3)) {
                        sparklePulse = false
                    }
                }
            }
            .onDisappear {
                sparklePulse = false
            }
            .background(QuickPromptDragHandle())
            .accessibilityHidden(true)
    }

    /// Recent sessions, plan mode and the working folder: the round buttons
    /// that float in beside the input bar.
    private var actionButtons: some View {
        HStack(spacing: 8) {
            ModularButtonView(icon: session.mode == .sessions ? "clock.fill" : "clock",
                              isActive: session.mode == .sessions,
                              help: strings.sessionsToggle) {
                withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) {
                    session.toggleSessions(configuration: service.configuration)
                }
            }
            .overlay(alignment: .topTrailing) {
                if session.mode != .sessions && !session.sessions.isEmpty {
                    Text("\(session.sessions.count)")
                        .font(.system(size: 8, weight: .bold, design: .rounded))
                        .foregroundStyle(.white)
                        .frame(minWidth: 14, minHeight: 14)
                        .background(Circle().fill(Color.blue))
                        .offset(x: 4, y: -4)
                        .transition(.scale.combined(with: .opacity))
                        .accessibilityHidden(true)
                }
            }

            ModularButtonView(icon: session.planMode ? "doc.text.fill" : "doc.text",
                              isActive: session.planMode,
                              help: session.planMode ? strings.planModeOn : strings.planModeOff,
                              activeColor: .orange) {
                withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                    session.planMode.toggle()
                }
            }

            if isGitDir && service.configuration.activeProvider.id != NexusAgentCLIProvider.antigravity.id {
                ModularButtonView(icon: "arrow.triangle.branch",
                                  isActive: session.worktreeMode,
                                  help: session.worktreeMode ? strings.worktreeModeOn : strings.worktreeModeOff,
                                  activeColor: .green) {
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                        session.worktreeMode.toggle()
                    }
                }
            }

            ModularButtonView(icon: "folder", isActive: false, help: strings.workingFolder) {
                chooseWorkingFolder()
            }

            ModularProviderButtonView(service: service)
        }
    }

    /// Picks the folder agy runs in, starting from the current one, and
    /// saves it with the rest of the bot's settings.
    private func chooseWorkingFolder() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.directoryURL = URL(fileURLWithPath: session.workingDirectory(for: service.configuration))
        NSApp.activate(ignoringOtherApps: true)
        if panel.runModal() == .OK, let url = panel.url {
            var next = service.configuration
            next.workingDirectory = url.path
            service.save(next)
        }
        // A click in the folder panel counts as a click outside the prompt,
        // which hides it; bring it back to where the user was.
        service.showQuickPrompt()
    }

    @ViewBuilder
    private var pillSendButton: some View {
        if session.isRunning {
            sendButton
        } else {
            SendButtonView(isEnabled: session.canSend, label: strings.send) {
                service.sendQuickPrompt()
            }
        }
    }

    private var sparkles: some View {
        Image(systemName: "sparkles")
            .font(.system(size: 18, weight: .medium))
            .foregroundStyle(LinearGradient(colors: [.blue, .purple],
                                            startPoint: .topLeading, endPoint: .bottomTrailing))
            .frame(width: 24, height: 24)
            .background(QuickPromptDragHandle())
            .accessibilityHidden(true)
    }

    private var sessionsButton: some View {
        Button {
            session.toggleSessions(configuration: service.configuration)
        } label: {
            Image(systemName: session.mode == .sessions ? "chevron.down" : "chevron.up")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(Color.primary.opacity(session.mode == .sessions ? 0.85 : 0.55))
                .frame(width: 26, height: 24)
                .background(
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .fill(Color.primary.opacity(session.mode == .sessions ? 0.16 : 0.08))
                )
        }
        .buttonStyle(.plain)
        .help(strings.sessionsToggle)
        .accessibilityLabel(strings.sessionsToggle)
        .accessibilityAddTraits(session.mode == .sessions ? .isSelected : [])
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
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(active ? tint : Color.secondary)
                .frame(width: 26, height: 26)
                .background(RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(active ? tint.opacity(0.18) : Color.primary.opacity(0.06)))
        }
        .buttonStyle(.plain)
        .help(help)
        .accessibilityLabel(help)
        .accessibilityAddTraits(active ? .isSelected : [])
    }

    @ViewBuilder
    private var sendButton: some View {
        if session.isRunning {
            Button { session.stop() } label: {
                Image(systemName: "stop.fill")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(Color.white)
                    .frame(width: 26, height: 26)
                    .background(Circle().fill(Color.red))
            }
            .buttonStyle(.plain)
            .help(strings.stopReply)
            .accessibilityLabel(strings.stopReply)
        } else {
            Button { service.sendQuickPrompt() } label: {
                Image(systemName: "arrow.up")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(session.canSend ? Color.white : Color.primary.opacity(0.35))
                    .frame(width: 26, height: 26)
                    .background(Circle().fill(session.canSend ? Color.accentColor : Color.primary.opacity(0.08)))
            }
            .buttonStyle(.plain)
            .disabled(!session.canSend)
            .help(strings.send)
            .accessibilityLabel(strings.send)
        }
    }

    // MARK: - Sessions drawer

    private var drawer: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                HStack(spacing: 6) {
                    Image(systemName: "line.3.horizontal.decrease").foregroundStyle(.secondary)
                    TextField(strings.sessionsFilter, text: $session.sessionFilter)
                        .textFieldStyle(.plain)
                        .font(.system(size: 13))
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(Color.primary.opacity(0.05)))

                planButton
            }
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
            Text(session.sessionTitle ?? strings.quickPromptTitle)
                .font(.system(size: 13, weight: .semibold))
                .lineLimit(1)
                .truncationMode(.tail)
            if session.isResumed && !session.isRunning {
                Text("Resumed")
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(Color.accentColor.opacity(0.85))
                    .padding(.horizontal, 5)
                    .padding(.vertical, 1)
                    .background(Capsule().fill(Color.accentColor.opacity(0.12)))
            }
            if !session.messages.isEmpty {
                Text("\(session.messages.count)")
                    .font(.system(size: 10, weight: .semibold, design: .rounded))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 5)
                    .padding(.vertical, 1)
                    .background(Capsule().fill(Color.primary.opacity(0.06)))
                    .contentTransition(.numericText())
                    .animation(.easeInOut(duration: 0.2), value: session.messages.count)

                Circle()
                    .fill(Color.secondary.opacity(0.3))
                    .frame(width: 3, height: 3)
            }

            ChatProviderBadge(service: service)
            ChatModelBadge(service: service)
            ChatWorkingDirectoryBadge(service: service, session: session)

            Spacer()

            Button {
                session.newChat()
            } label: {
                Image(systemName: "plus.circle")
                    .font(.system(size: 16))
                    .foregroundStyle(hoveringNewChat ? Color.primary : Color.secondary)
                    .scaleEffect(hoveringNewChat ? 1.1 : 1.0)
                    .animation(.easeInOut(duration: 0.15), value: hoveringNewChat)
            }
            .buttonStyle(.plain)
            .help(strings.newChat + " (⌘N)")
            .onHover { hoveringNewChat = $0 }

            Button {
                session.toggleSessions(configuration: service.configuration)
            } label: {
                Image(systemName: "clock")
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(hoveringSessions ? Color.primary : Color.secondary.opacity(0.8))
                    .scaleEffect(hoveringSessions ? 1.1 : 1.0)
                    .animation(.easeInOut(duration: 0.15), value: hoveringSessions)
            }
            .buttonStyle(.plain)
            .help(strings.sessionsToggle)
            .onHover { hoveringSessions = $0 }

            Button {
                service.isPinned.toggle()
            } label: {
                Group {
                    if service.isPinned {
                        Image(systemName: "pin.circle.fill")
                    } else {
                        Image(systemName: "pin.circle")
                    }
                }
                .font(.system(size: 16))
                .foregroundStyle(service.isPinned ? Color.blue : (hoveringPin ? Color.primary : Color.secondary.opacity(0.5)))
                .rotationEffect(.degrees(service.isPinned ? 0 : 45))
                .scaleEffect(hoveringPin ? 1.1 : 1.0)
                .animation(.spring(response: 0.3, dampingFraction: 0.7), value: service.isPinned)
                .animation(.easeInOut(duration: 0.15), value: hoveringPin)
            }
            .buttonStyle(.plain)
            .help(service.isPinned ? strings.unpinWindow : strings.pinWindow)
            .onHover { hoveringPin = $0 }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .background(QuickPromptDragHandle())
    }

    private var conversation: some View {
        ZStack(alignment: .bottom) {
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 10) {
                        if session.messages.isEmpty && session.isRunning {
                            VStack(spacing: 12) {
                                ForEach(0..<3, id: \.self) { i in
                                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                                        .fill(Color.primary.opacity(0.05))
                                        .frame(height: i == 1 ? 40 : 20)
                                        .frame(maxWidth: i == 2 ? 200 : .infinity)
                                        .shimmer()
                                }
                            }
                            .padding(.horizontal, 16)
                            .padding(.top, 20)
                        }
                        ForEach(session.messages) { message in
                            if !(message.role == .agent && message.text.isEmpty) {
                                NexusAgentMessageBubble(message: message)
                            }
                        }
                        if session.isRunning { progress }
                        if session.lastFailedPrompt != nil {
                            HStack(spacing: 6) {
                                Image(systemName: "exclamationmark.triangle.fill")
                                    .font(.caption)
                                    .foregroundStyle(.orange)
                                Text(strings.agentFailed)
                                    .foregroundStyle(.secondary)
                                    .font(.caption)
                                Spacer()
                                Button {
                                    service.retryQuickPrompt()
                                } label: {
                                    HStack(spacing: 4) {
                                        Image(systemName: "arrow.clockwise")
                                            .font(.caption)
                                        Text(strings.retry)
                                            .font(.caption)
                                    }
                                    .foregroundStyle(Color.accentColor)
                                }
                                .buttonStyle(.plain)
                                .help(strings.retry)

                                Button {
                                    session.lastFailedPrompt = nil
                                } label: {
                                    Image(systemName: "xmark.circle.fill")
                                        .font(.caption)
                                        .foregroundStyle(.quaternary)
                                }
                                .buttonStyle(.plain)
                            }
                            .padding(.horizontal, 12)
                            .padding(.vertical, 6)
                            .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(Color.red.opacity(0.08)))
                        }
                        Color.clear.frame(height: 1).id(Self.bottomID)
                    }
                    .padding(14)
                    .background(
                        GeometryReader { geo in
                            Color.clear.preference(
                                key: ScrollOffsetPreferenceKey.self,
                                value: geo.frame(in: .named("chatScroll")).maxY
                            )
                        }
                    )
                }
                .overlay(
                    GeometryReader { scrollGeo in
                        Color.clear.preference(
                            key: ScrollViewHeightPreferenceKey.self,
                            value: scrollGeo.size.height
                        )
                    }
                )
                .coordinateSpace(name: "chatScroll")
                .onPreferenceChange(ScrollOffsetPreferenceKey.self) { maxY in
                    isNearBottom = maxY < scrollViewHeight + 60
                }
                .onPreferenceChange(ScrollViewHeightPreferenceKey.self) { height in
                    scrollViewHeight = height
                }
                .onChange(of: session.messages) { _, _ in
                    if isNearBottom {
                        withAnimation(.easeOut(duration: 0.2)) {
                            proxy.scrollTo(Self.bottomID, anchor: .bottom)
                        }
                    }
                }
                .onChange(of: session.isRunning) { _, loading in
                    if loading && isNearBottom {
                        withAnimation(.easeOut(duration: 0.2)) {
                            proxy.scrollTo(Self.bottomID, anchor: .bottom)
                        }
                    }
                }

                if !isNearBottom {
                    Button {
                        withAnimation(.easeOut(duration: 0.3)) {
                            proxy.scrollTo(Self.bottomID, anchor: .bottom)
                        }
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: "arrow.down")
                                .font(.caption2.weight(.bold))
                            Text(session.isRunning ? strings.newMessages : strings.scrollToBottom)
                                .font(.caption2)
                        }
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(.ultraThinMaterial, in: Capsule())
                        .shadow(color: .black.opacity(0.15), radius: 4, y: 2)
                    }
                    .buttonStyle(.plain)
                    .padding(.bottom, 8)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                }
            }
            .animation(.easeInOut(duration: 0.25), value: isNearBottom)
        }
    }

    private static let bottomID = "nexusAgentBottom"

    private var progress: some View {
        HStack(spacing: 6) {
            Image(systemName: "ellipsis.bubble")
                .font(.caption2)
                .foregroundStyle(.linearGradient(
                    colors: [.blue, .purple],
                    startPoint: .top, endPoint: .bottom
                ))
                .frame(width: 22, height: 22)
                .background(Circle().fill(Color.blue.opacity(0.15)))

            HStack(spacing: 4) {
                ForEach(0..<3, id: \.self) { i in
                    Circle()
                        .fill(Color.blue.opacity(0.6))
                        .frame(width: 6, height: 6)
                        .scaleEffect(typingDotPhase == i ? 1.3 : 0.7)
                        .animation(
                            .easeInOut(duration: 0.4)
                                .repeatForever(autoreverses: true)
                                .delay(Double(i) * 0.15),
                            value: typingDotPhase
                        )
                }
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 6)
            .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Color.secondary.opacity(0.1)))

            if let tool = session.activity {
                Text(strings.working)
                Text(tool).font(.system(size: 11, design: .monospaced))
            } else {
                Text(strings.thinking)
            }

            if session.elapsedSeconds > 0 {
                Text("\(session.elapsedSeconds)s")
                    .font(.system(.caption2, design: .rounded))
                    .foregroundStyle(.tertiary)
                    .contentTransition(.numericText())
                    .animation(.easeInOut(duration: 0.2), value: session.elapsedSeconds)
            }

            Spacer()

            Button {
                session.stop()
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: "stop.circle.fill")
                    Text(strings.stopReply)
                }
                .font(.caption)
                .foregroundStyle(Color.red.opacity(hoveringInlineStop ? 0.6 : 1.0))
                .animation(.easeInOut(duration: 0.12), value: hoveringInlineStop)
            }
            .buttonStyle(.plain)
            .onHover { hoveringInlineStop = $0 }
        }
        .font(.caption)
        .foregroundStyle(.secondary)
        .onAppear { typingDotPhase = 1 }
    }

    private var followUpBar: some View {
        HStack(alignment: .bottom, spacing: 8) {
            planButton
            TextField(followUpPlaceholder, text: $session.draft, axis: .vertical)
                .textFieldStyle(.plain)
                .font(.system(size: 14))
                .lineLimit(1...6)
                .focused($inputFocused)
                .onSubmit { if session.canSend { service.sendQuickPrompt() } }
                .onExitCommand { if session.isRunning { session.stop() } }
                .onKeyPress(.upArrow) {
                    if session.draft.isEmpty && !session.promptHistory.isEmpty {
                        if session.historyIndex < 0 { session.historyIndex = session.promptHistory.count }
                        session.historyIndex = max(0, session.historyIndex - 1)
                        session.draft = session.promptHistory[session.historyIndex]
                        return .handled
                    }
                    return .ignored
                }
                .onKeyPress(.downArrow) {
                    if session.historyIndex >= 0 && session.historyIndex < session.promptHistory.count - 1 {
                        session.historyIndex += 1
                        session.draft = session.promptHistory[session.historyIndex]
                        return .handled
                    } else if session.historyIndex >= 0 {
                        session.historyIndex = -1
                        session.draft = ""
                        return .handled
                    }
                    return .ignored
                }
                .overlay(alignment: .bottomTrailing) {
                    if session.draft.count > 20 {
                        Text("\(session.draft.count)")
                            .font(.system(size: 9, weight: .medium, design: .rounded))
                            .foregroundStyle(.quaternary)
                            .padding(.trailing, 4)
                            .padding(.bottom, 2)
                            .transition(.opacity)
                    }
                }
                .animation(.easeInOut(duration: 0.15), value: session.draft.count > 20)
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

/// One chat bubble: rich Markdown blocks (headings, lists, quotes, dividers) and interactive code/diagram cards.
private struct NexusAgentMessageBubble: View {
    let message: NexusAgentChatMessage
    @State private var copied = false
    @State private var copyBounce = false
    @State private var hovering = false
    @State private var showingStats = false

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
            parts.append("\(formatTokenCount(input)) in")
        }
        if let output = message.outputTokens {
            parts.append("\(formatTokenCount(output)) out")
        }
        if let cached = message.cachedTokens, cached > 0 {
            parts.append("\(formatTokenCount(cached)) cached")
        }
        if let tools = message.toolCalls, tools > 0 {
            parts.append("\(tools) tool\(tools == 1 ? "" : "s")")
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
                Image(systemName: "bubble.left.fill")
                    .font(.system(size: 10))
                    .foregroundStyle(.linearGradient(
                        colors: [.blue, .purple],
                        startPoint: .top, endPoint: .bottom
                    ))
                    .frame(width: 22, height: 22)
                    .background(Circle().fill(Color.blue.opacity(0.15)))
                    .padding(.top, 4)
            }

            VStack(alignment: isUser ? .trailing : .leading, spacing: 4) {
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
                                            .foregroundStyle(message.isError ? Color.orange : Color.primary)
                                            .padding(.vertical, 2)
                                    case .bulletItem(let bulletText):
                                        HStack(alignment: .top, spacing: 6) {
                                            Image(systemName: "circle.fill")
                                                .font(.system(size: 4))
                                                .foregroundStyle(Color.accentColor)
                                                .padding(.top, 6)
                                            Text(Self.markdown(bulletText))
                                                .font(.system(size: 13))
                                                .foregroundStyle(message.isError ? Color.orange : Color.primary)
                                        }
                                    case .numberedItem(let number, let itemText):
                                        HStack(alignment: .top, spacing: 6) {
                                            Text("\(number).")
                                                .font(.system(size: 12, weight: .medium, design: .rounded))
                                                .foregroundStyle(.secondary)
                                                .padding(.top, 1)
                                            Text(Self.markdown(itemText))
                                                .font(.system(size: 13))
                                                .foregroundStyle(message.isError ? Color.orange : Color.primary)
                                        }
                                    case .blockquote(let quoteText):
                                        HStack(alignment: .top, spacing: 8) {
                                            RoundedRectangle(cornerRadius: 1.5)
                                                .fill(Color.accentColor.opacity(0.6))
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
                                            .foregroundStyle(message.isError ? Color.orange : Color.primary)
                                    }
                                }
                            }
                        case .code(let language, let body):
                            if let lang = language?.lowercased(), lang == "mermaid" {
                                NexusAgentMermaidCard(source: body)
                            } else {
                                NexusAgentCodeBlockView(language: language, bodyText: body)
                            }
                        }
                    }
                }
                .textSelection(.enabled)
                .padding(.horizontal, 10)
                .padding(.vertical, 7)
                .background(RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(isUser ? Color.accentColor.opacity(0.22) : Color.primary.opacity(0.06)))

                Button(action: copyContent) {
                    HStack(spacing: 4) {
                        Image(systemName: copied ? "checkmark" : "doc.on.doc")
                        Text(copied ? "Copied!" : "Copy")
                    }
                    .font(.caption2)
                    .foregroundStyle(copied ? Color.blue : Color.secondary)
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
                                if let model = message.modelName { statsRow("Model", model) }
                                if let ms = message.durationMs { statsRow("Duration", String(format: "%.1fs", locale: Locale.current, Double(ms) / 1000.0)) }
                                if let input = message.inputTokens { statsRow("Input", "\(formatTokenCount(input)) tokens") }
                                if let output = message.outputTokens { statsRow("Output", "\(formatTokenCount(output)) tokens") }
                                if let cached = message.cachedTokens, cached > 0 { statsRow("Cached", "\(formatTokenCount(cached)) tokens") }
                                if let tools = message.toolCalls, tools > 0 { statsRow("Tool calls", "\(tools)") }
                                if let turns = message.numTurns, turns > 0 { statsRow("Turns", "\(turns)") }
                                if let reason = message.stopReason { statsRow("Status", reason) }
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
                        colors: [.indigo, .purple],
                        startPoint: .top, endPoint: .bottom
                    ))
                    .frame(width: 22, height: 22)
                    .background(Circle().fill(Color.indigo.opacity(0.15)))
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

/// An interactive card rendering a Mermaid diagram with Diagram and Source toggle modes.
private struct NexusAgentMermaidCard: View {
    let source: String
    @State private var mode: DiagramViewMode = .diagram
    @State private var copied = false
    @State private var renderFailed = false
    @Environment(\.colorScheme) private var colorScheme

    private enum DiagramViewMode: String, CaseIterable, Identifiable {
        case diagram = "Diagram"
        case source = "Source"
        var id: String { rawValue }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 8) {
                Image(systemName: "point.3.connected.trianglepath.dotted")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(Color.accentColor)
                Text("Diagram")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.secondary)
                Spacer()
                Picker("", selection: $mode) {
                    ForEach(DiagramViewMode.allCases) { item in
                        Text(item.rawValue).tag(item)
                    }
                }
                .pickerStyle(.segmented)
                .controlSize(.small)
                .frame(width: 140)

                Button {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(source, forType: .string)
                    copied = true
                    DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                        copied = false
                    }
                } label: {
                    Image(systemName: copied ? "checkmark" : "doc.on.doc")
                        .font(.system(size: 11))
                        .foregroundStyle(copied ? Color.green : Color.secondary)
                }
                .buttonStyle(.plain)
                .help("Copy source")
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(Color.primary.opacity(0.04))

            Divider().opacity(0.3)

            if mode == .diagram && !renderFailed {
                NexusAgentMermaidWebView(source: source, isDark: colorScheme == .dark, onRenderError: {
                    renderFailed = true
                })
                .frame(minHeight: 180, idealHeight: 240, maxHeight: 420)
            } else {
                VStack(alignment: .leading, spacing: 4) {
                    if renderFailed {
                        HStack(spacing: 4) {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .font(.system(size: 11))
                                .foregroundStyle(.orange)
                            Text("Diagram render failed — showing source")
                                .font(.system(size: 11))
                                .foregroundStyle(.secondary)
                        }
                        .padding(.horizontal, 8)
                        .padding(.top, 6)
                    }
                    ScrollView(.horizontal, showsIndicators: false) {
                        Text(source)
                            .font(.system(size: 11, design: .monospaced))
                            .padding(8)
                    }
                }
                .background(Color.black.opacity(0.25))
            }
        }
        .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(Color.primary.opacity(0.03)))
        .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous).strokeBorder(Color.primary.opacity(0.12), lineWidth: 0.5))
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
    }
}

/// A WKWebView rendering a Mermaid diagram via self-contained HTML.
private struct NexusAgentMermaidWebView: NSViewRepresentable {
    let source: String
    let isDark: Bool
    let onRenderError: @MainActor () -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(onRenderError: onRenderError)
    }

    func makeNSView(context: Context) -> WKWebView {
        let configuration = WKWebViewConfiguration()
        let webView = WKWebView(frame: .zero, configuration: configuration)
        webView.setValue(false, forKey: "drawsBackground")
        webView.navigationDelegate = context.coordinator
        loadDiagram(in: webView)
        return webView
    }

    func updateNSView(_ nsView: WKWebView, context: Context) {
        context.coordinator.onRenderError = onRenderError
        loadDiagram(in: nsView)
    }

    private func loadDiagram(in webView: WKWebView) {
        let escapedSource = source
            .replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
        let theme = isDark ? "dark" : "default"
        let html = """
        <!DOCTYPE html>
        <html>
        <head>
        <meta charset="utf-8">
        <meta name="viewport" content="width=device-width, initial-scale=1">
        <style>
          * { box-sizing: border-box; }
          body {
            margin: 0;
            padding: 16px;
            background: transparent;
            display: flex;
            justify-content: center;
            align-items: center;
            min-height: 100vh;
            font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", Roboto, sans-serif;
            overflow: auto;
          }
          .mermaid {
            width: 100%;
            display: flex;
            justify-content: center;
          }
          svg {
            max-width: 100%;
            height: auto;
          }
        </style>
        <script src="https://cdn.jsdelivr.net/npm/mermaid@10/dist/mermaid.min.js"></script>
        <script>
          try {
            mermaid.initialize({
              startOnLoad: true,
              theme: '\(theme)',
              securityLevel: 'loose'
            });
          } catch(e) {
            window.location.href = "vitruvian-error://error";
          }
        </script>
        </head>
        <body>
        <div class="mermaid">
        \(escapedSource)
        </div>
        </body>
        </html>
        """
        webView.loadHTMLString(html, baseURL: nil)
    }

    @MainActor
    final class Coordinator: NSObject, WKNavigationDelegate {
        var onRenderError: @MainActor () -> Void

        init(onRenderError: @escaping @MainActor () -> Void) {
            self.onRenderError = onRenderError
        }

        func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
            onRenderError()
        }

        func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
            onRenderError()
        }

        func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction,
                     decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
            if let url = navigationAction.request.url, url.scheme == "vitruvian-error" {
                decisionHandler(.cancel)
                onRenderError()
                return
            }
            decisionHandler(.allow)
        }
    }
}

/// A styled monospaced code container with language badge, line numbers, and copy button.
private struct NexusAgentCodeBlockView: View {
    let language: String?
    let bodyText: String
    @State private var copied = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                if let language = language, !language.isEmpty {
                    Text(language.lowercased())
                        .font(.system(size: 11, weight: .medium, design: .monospaced))
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(RoundedRectangle(cornerRadius: 4, style: .continuous).fill(Color.primary.opacity(0.08)))
                } else {
                    Text("code")
                        .font(.system(size: 11, weight: .medium, design: .monospaced))
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(bodyText, forType: .string)
                    copied = true
                    DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                        copied = false
                    }
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: copied ? "checkmark" : "doc.on.doc")
                            .font(.system(size: 11))
                        Text(copied ? "Copied" : "Copy")
                            .font(.system(size: 11))
                    }
                    .foregroundStyle(copied ? Color.green : Color.secondary)
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(Color.primary.opacity(0.04))

            Divider().opacity(0.3)

            let lines = bodyText.components(separatedBy: "\n")
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(alignment: .top, spacing: 12) {
                    VStack(alignment: .trailing, spacing: 2) {
                        ForEach(0..<lines.count, id: \.self) { idx in
                            Text("\(idx + 1)")
                                .font(.system(size: 11, design: .monospaced))
                                .foregroundStyle(Color.secondary.opacity(0.6))
                        }
                    }
                    VStack(alignment: .leading, spacing: 2) {
                        ForEach(0..<lines.count, id: \.self) { idx in
                            Text(lines[idx].isEmpty ? " " : lines[idx])
                                .font(.system(size: 11, design: .monospaced))
                                .foregroundStyle(Color.primary)
                        }
                    }
                }
                .padding(10)
            }
        }
        .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(Color.black.opacity(0.25)))
        .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous).strokeBorder(Color.primary.opacity(0.12), lineWidth: 0.5))
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
    }
}

/// A round action button beside the input bar, with a hover highlight.
private struct ModularButtonView: View {
    let icon: String
    let isActive: Bool
    let help: String
    var activeColor: Color = .blue
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
private struct SendButtonView: View {
    let isEnabled: Bool
    let label: String
    let action: () -> Void
    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            Image(systemName: "arrow.up.circle.fill")
                .font(.title2)
                .foregroundStyle(isEnabled ? (isHovered ? Color.blue.opacity(0.8) : Color.blue) : Color.gray)
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

/// Compact provider picker button beside the prompt bar.
private struct ModularProviderButtonView: View {
    @ObservedObject var service: NexusAgentService
    @State private var isHovered = false

    var body: some View {
        Menu {
            ForEach(NexusAgentCLIProvider.builtIns) { provider in
                Button {
                    service.updateActiveProvider(provider)
                } label: {
                    HStack {
                        Text(provider.name)
                        if service.configuration.activeProvider.id == provider.id {
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
        .help("Switch provider")
        .onHover { isHovered = $0 }
    }
}

/// Compact provider picker badge for the chat header.
private struct ChatProviderBadge: View {
    @ObservedObject var service: NexusAgentService
    @State private var isHovered = false

    var body: some View {
        Menu {
            ForEach(NexusAgentCLIProvider.builtIns) { provider in
                Button {
                    service.updateActiveProvider(provider)
                } label: {
                    HStack {
                        Text(provider.name)
                        if service.configuration.activeProvider.id == provider.id {
                            Image(systemName: "checkmark")
                        }
                    }
                }
            }
        } label: {
            Text(service.configuration.activeProvider.name)
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
        .help("Switch provider")
        .onHover { isHovered = $0 }
    }
}

/// Compact clickable model badge for the chat header.
private struct ChatModelBadge: View {
    @ObservedObject var service: NexusAgentService
    @State private var isEditing = false
    @State private var draft = ""
    @State private var isHovered = false
    @FocusState private var isFocused: Bool

    private var displayName: String {
        let m = service.configuration.model.trimmingCharacters(in: .whitespaces)
        return m.isEmpty ? "Auto" : m
    }

    var body: some View {
        if isEditing {
            TextField("model name", text: $draft)
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
                                .strokeBorder(Color.blue.opacity(0.4), lineWidth: 1)
                        )
                )
                .focused($isFocused)
                .onSubmit {
                    var next = service.configuration
                    next.model = draft.trimmingCharacters(in: .whitespaces)
                    service.save(next)
                    isEditing = false
                }
                .onExitCommand { isEditing = false }
        } else {
            Button {
                draft = service.configuration.model
                isEditing = true
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                    isFocused = true
                }
            } label: {
                Text(displayName)
                    .font(.system(size: 10, weight: .medium, design: service.configuration.model.isEmpty ? .default : .monospaced))
                    .foregroundStyle(service.configuration.model.isEmpty
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
            .help(service.configuration.model.isEmpty ? "Set model" : "Model: \(service.configuration.model)")
            .onHover { isHovered = $0 }
        }
    }
}

/// Compact badge showing working directory with click to choose.
private struct ChatWorkingDirectoryBadge: View {
    @ObservedObject var service: NexusAgentService
    @ObservedObject var session: NexusAgentQuickPromptSession
    @State private var isHovered = false

    private var fullDirPath: String {
        session.workingDirectory(for: service.configuration)
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
            panel.prompt = "Set Working Directory"

            NSApp.activate(ignoringOtherApps: true)
            if panel.runModal() == .OK, let url = panel.url {
                var next = service.configuration
                next.workingDirectory = url.path
                service.save(next)
            }
            service.showQuickPrompt()
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
        .help("Working Directory: \(fullDirPath)\nClick to change")
        .onHover { isHovered = $0 }
    }
}

/// Mode toggle strip above follow-up bar for plan and worktree modes.
private struct ModeToggleStrip: View {
    @Binding var planEnabled: Bool
    @Binding var worktreeEnabled: Bool
    var isGitDir: Bool
    var worktreeSupported: Bool
    let strings: NexusAgentFeatureStrings

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
                    Text("Plan")
                        .font(.system(size: 9, weight: .semibold))
                }
                .foregroundStyle(planEnabled ? Color.orange : Color.secondary.opacity(0.4))
                .padding(.horizontal, 6)
                .padding(.vertical, 3)
                .background(
                    Capsule()
                        .fill(planEnabled ? Color.orange.opacity(0.12) : Color.clear)
                        .overlay(
                            Capsule()
                                .strokeBorder(planEnabled ? Color.orange.opacity(0.3) : Color.primary.opacity(0.08), lineWidth: 0.5)
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
                        Text("Worktree")
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
                    .foregroundStyle(Color.orange.opacity(0.7))
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

private struct ScrollOffsetPreferenceKey: PreferenceKey {
    static let defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = nextValue()
    }
}

private struct ScrollViewHeightPreferenceKey: PreferenceKey {
    static let defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = nextValue()
    }
}

private struct ShimmerModifier: ViewModifier {
    @State private var phase: CGFloat = 0

    func body(content: Content) -> some View {
        content
            .overlay(
                LinearGradient(
                    colors: [
                        Color.clear,
                        Color.primary.opacity(0.06),
                        Color.clear,
                    ],
                    startPoint: .leading,
                    endPoint: .trailing
                )
                .offset(x: phase)
                .mask(content)
            )
            .onAppear {
                withAnimation(.linear(duration: 1.5).repeatForever(autoreverses: false)) {
                    phase = 400
                }
            }
            .onDisappear {
                phase = 0
            }
    }
}

private extension View {
    func shimmer() -> some View {
        modifier(ShimmerModifier())
    }
}

