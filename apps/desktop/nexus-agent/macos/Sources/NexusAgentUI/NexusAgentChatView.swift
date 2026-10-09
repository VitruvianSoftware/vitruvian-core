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

/// The chat's own colours, the same in either app.
enum NexusAgentTheme {
    static let warmCoral = Color(red: 0.85, green: 0.47, blue: 0.34)
    static let warmCoralLight = Color(red: 0.92, green: 0.55, blue: 0.42)
    static let gradient = LinearGradient(
        colors: [warmCoralLight, warmCoral],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )
    static let cardFill = Color.white.opacity(0.065)
    static let cardBorder = Color.white.opacity(0.08)
}

/// The Spotlight-style Quick Prompt: a floating pill with the prompt, a
/// recent-sessions drawer that opens under it, and the streaming chat with
/// a follow-up bar. Return sends, Shift-Return adds a line. Sizes come from
/// `NexusAgentQuickPromptLayout`; the app that shows the view resizes its
/// window when `session.mode` changes, and closes it on Esc.
///
/// The view knows no app. It is handed the engine whose chat it shows, its
/// text in the app's language, and what differs between the apps around it.
/// It observes the engine and the engine's session, so it redraws when
/// either changes; an app whose text or chrome can change rebuilds the view
/// with the new values.
public struct NexusAgentChatView: View {
    @ObservedObject private var engine: NexusAgentEngine
    @ObservedObject private var session: NexusAgentQuickPromptSession
    private let strings: NexusAgentChatStrings
    private let chrome: NexusAgentChatChrome
    @FocusState private var inputFocused: Bool
    /// The pointer is over the pill, which is what brings the action buttons in.
    @State private var isHoveringInput = false
    @State private var sparklePulse = false
    @State private var hoveringPin = false
    @State private var hoveringDock = false
    @State private var typingDotPhase = 0
    @State private var isNearBottom = true
    @State private var scrollViewHeight: CGFloat = 500
    @State private var hoveringInlineStop = false
    @State private var hoveringNewChat = false
    @State private var hoveringSessions = false
    @State private var isArchivedExpanded = false
    /// The drawer row the arrow keys have, counted from the top of the
    /// rows on show; nil when none is selected.
    @State private var selectedSessionIndex: Int?
    /// When Clear All was first clicked, or nil. Whether the button is
    /// asking its question is worked out from this and the time now
    /// (`NexusAgentClearAllGuard`), so a time left lying here does no harm.
    @State private var clearAllFirstClick: Date?

    public init(engine: NexusAgentEngine, strings: NexusAgentChatStrings, chrome: NexusAgentChatChrome) {
        self.engine = engine
        self.session = engine.session
        self.strings = strings
        self.chrome = chrome
    }

    private typealias Layout = NexusAgentQuickPromptLayout
    private var shape: RoundedRectangle { RoundedRectangle(cornerRadius: Layout.cornerRadius, style: .continuous) }

    private var isGitDir: Bool {
        let path = session.workingDirectory(for: engine.configuration)
        return NexusAgentSupport.isGitRepo(at: URL(fileURLWithPath: path))
    }

    private var contextualPlaceholder: String {
        if session.mode == .sessions {
            return strings.sessionsFilter
        }
        let providerName = engine.activeProvider.name.components(separatedBy: " ").first ?? strings.fallbackProviderName
        return strings.askPrefix + providerName + strings.askSuffix
    }

    private var followUpPlaceholder: String {
        if session.planMode {
            return strings.planModeOn
        }
        let providerName = engine.activeProvider.name.components(separatedBy: " ").first ?? strings.fallbackProviderName
        return strings.followUpPrefix + providerName + strings.followUpSuffix
    }

    public var body: some View {
        VStack(spacing: 0) {
            if session.mode == .chat {
                chatHeader
                Divider().opacity(0.3)
                conversation
                Divider().opacity(0.3)
                ModeToggleStrip(
                    planEnabled: $session.planMode,
                    worktreeEnabled: $session.worktreeMode,
                    isGitDir: isGitDir,
                    worktreeSupported: engine.configuration.activeProvider.id != NexusAgentCLIProvider.antigravity.id,
                    strings: strings
                )
                if !session.activeSubagents.isEmpty {
                    ActiveSubagentBannerView(subagents: session.activeSubagents, strings: strings)
                        .padding(.horizontal, 14)
                        .padding(.bottom, 4)
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                }
                followUpBar
            } else {
                pill
                if chrome.isEmbedded || session.mode == .sessions {
                    Divider().opacity(0.3)
                    drawer
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(backdropView)
        .clipShape(shape)
        .overlay(overlayBorder)
        .onAppear {
            inputFocused = true
            if chrome.isEmbedded && session.sessions.isEmpty {
                session.refreshSessions(configuration: engine.configuration)
            }
        }
        .onChange(of: session.focusSerial) { _, _ in inputFocused = true }
        .onChange(of: session.mode) { _, _ in
            inputFocused = true
            // A drawer that opens, or closes, starts with no row selected,
            // and with Clear All not yet clicked.
            selectedSessionIndex = nil
            clearAllFirstClick = nil
        }
        // Clear All's question was asked about the list as it then was: a
        // filter typed since, or another provider, takes the question back.
        .onChange(of: session.sessionFilter) { _, _ in clearAllFirstClick = nil }
        .onChange(of: engine.activeProvider.id) { _, _ in clearAllFirstClick = nil }
        // A prompt being typed is what Return sends: the selection is let
        // go, so that Return does not open a session instead.
        .onChange(of: session.draft) { _, _ in selectedSessionIndex = nil }
    }

    // MARK: - Keys in the sessions drawer

    /// The drawer is on show: opened from the pill, or always, under an
    /// embedded pill. Never while the conversation is.
    private var isDrawerShown: Bool {
        session.mode != .chat && (chrome.isEmbedded || session.mode == .sessions)
    }

    /// The drawer's rows from the top, as the arrow keys count them: the
    /// sessions, then the archived ones while their heading is open.
    private var rowsOnShow: [NexusAgentSessionSummary] {
        let filtered = session.filteredSessions
        return filtered.filter { !$0.isArchived } + (isArchivedExpanded ? filtered.filter { $0.isArchived } : [])
    }

    /// An arrow key moves the selection (`NexusAgentSessionListKeys`). It
    /// is asked from the two fields the caret can be in beside a drawer.
    /// The drawer's filter always gives the list its arrows. The pill's
    /// prompt gives them only while it is empty: this is not the
    /// standalone's rule, where the pill's text is the filter, because
    /// here it is a prompt, and an arrow pressed in a typed prompt means
    /// the caret. With a modifier held, no drawer, or no row in it, the key
    /// is left to the field too. The chat's follow-up bar is a different
    /// field with its own use for the arrows (the prompt history), and
    /// never asks.
    private func moveSelection(_ arrow: NexusAgentSessionListKeys.Arrow, in field: NexusAgentSessionListKeys.Field,
                               press: KeyPress) -> KeyPress.Result {
        let count = rowsOnShow.count
        // An arrow key always carries the keypad and function flags, so
        // only the four keys a person holds count as modifiers.
        let held = !press.modifiers.isDisjoint(with: [.shift, .option, .command, .control])
        guard isDrawerShown,
              NexusAgentSessionListKeys.arrowMovesSelection(in: field, hasModifiers: held, count: count)
        else { return .ignored }
        selectedSessionIndex = NexusAgentSessionListKeys.selection(after: arrow, from: selectedSessionIndex,
                                                                   count: count)
        return .handled
    }

    /// Return opens the selected row, if there is one and the field it was
    /// pressed in lets it: a prompt with text in it is sent instead. False
    /// leaves Return to the field. No row is opened while Clear All is
    /// removing the conversations' files.
    private func resumeSelectedSession(from field: NexusAgentSessionListKeys.Field) -> Bool {
        let rows = rowsOnShow
        guard isDrawerShown, !session.isClearingSessions,
              let row = NexusAgentSessionListKeys.rowToResume(from: field, selection: selectedSessionIndex,
                                                              count: rows.count)
        else { return false }
        selectedSessionIndex = nil
        session.resume(rows[row], configuration: engine.configuration)
        return true
    }

    @ViewBuilder
    private var backdropView: some View {
        if chrome.isEmbedded {
            Color.clear
        } else {
            chrome.backdrop
        }
    }

    @ViewBuilder
    private var overlayBorder: some View {
        if chrome.isEmbedded {
            EmptyView()
        } else {
            shape.strokeBorder(Color.white.opacity(0.12), lineWidth: 1)
        }
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
                .onSubmit {
                    if resumeSelectedSession(from: .prompt(session.draft)) { return }
                    if session.canSend { engine.sendQuickPrompt() }
                }
                .onKeyPress(.upArrow, phases: [.down, .repeat]) {
                    moveSelection(.up, in: .prompt(session.draft), press: $0)
                }
                .onKeyPress(.downArrow, phases: [.down, .repeat]) {
                    moveSelection(.down, in: .prompt(session.draft), press: $0)
                }
            if !session.draft.isEmpty {
                clearButton
            }
            pillSendButton
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Color.white.opacity(0.065))
                .overlay(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .strokeBorder(Color.white.opacity(0.08), lineWidth: 0.5)
                )
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
            .foregroundStyle(NexusAgentTheme.gradient)
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
                    session.toggleSessions(configuration: engine.configuration)
                }
            }
            .overlay(alignment: .topTrailing) {
                if session.mode != .sessions && !session.sessions.isEmpty {
                    Text("\(session.sessions.count)")
                        .font(.system(size: 8, weight: .bold, design: .rounded))
                        .foregroundStyle(.white)
                        .frame(minWidth: 14, minHeight: 14)
                        .background(Circle().fill(NexusAgentTheme.warmCoral))
                        .offset(x: 4, y: -4)
                        .transition(.scale.combined(with: .opacity))
                        .accessibilityHidden(true)
                }
            }

            ModularButtonView(icon: session.planMode ? "doc.text.fill" : "doc.text",
                              isActive: session.planMode,
                              help: session.planMode ? strings.planModeOn : strings.planModeOff,
                              activeColor: NexusAgentTheme.warmCoral) {
                withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                    session.planMode.toggle()
                }
            }

            if isGitDir && engine.configuration.activeProvider.id != NexusAgentCLIProvider.antigravity.id {
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

            ModularProviderButtonView(engine: engine, strings: strings)
        }
    }

    /// Picks the folder agy runs in, starting from the current one, and
    /// saves it with the rest of the bot's settings.
    private func chooseWorkingFolder() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.directoryURL = URL(fileURLWithPath: session.workingDirectory(for: engine.configuration))
        NSApp.activate(ignoringOtherApps: true)
        if panel.runModal() == .OK, let url = panel.url {
            var next = engine.configuration
            next.workingDirectory = url.path
            engine.save(next)
        }
        // A click in the folder panel counts as a click outside the prompt,
        // which hides it; bring it back to where the user was.
        chrome.showWindow()
    }

    @ViewBuilder
    private var pillSendButton: some View {
        if session.isRunning {
            sendButton
        } else {
            SendButtonView(isEnabled: session.canSend, label: strings.send) {
                engine.sendQuickPrompt()
            }
        }
    }

    private var sparkles: some View {
        Image(systemName: "sparkles")
            .font(.system(size: 18, weight: .medium))
            .foregroundStyle(NexusAgentTheme.gradient)
            .frame(width: 24, height: 24)
            .background(QuickPromptDragHandle())
            .accessibilityHidden(true)
    }

    private var sessionsButton: some View {
        Button {
            session.toggleSessions(configuration: engine.configuration)
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
                   tint: NexusAgentTheme.warmCoral, help: session.planMode ? strings.planModeOn : strings.planModeOff) {
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
            Button { engine.sendQuickPrompt() } label: {
                Image(systemName: "arrow.up")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(session.canSend ? Color.white : Color.primary.opacity(0.35))
                    .frame(width: 26, height: 26)
                    .background(Circle().fill(session.canSend ? NexusAgentTheme.warmCoral : Color.primary.opacity(0.08)))
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
                        .onSubmit { _ = resumeSelectedSession(from: .filter) }
                        .onKeyPress(.upArrow, phases: [.down, .repeat]) { moveSelection(.up, in: .filter, press: $0) }
                        .onKeyPress(.downArrow, phases: [.down, .repeat]) { moveSelection(.down, in: .filter, press: $0) }
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(Color.white.opacity(0.065))
                        .overlay(
                            RoundedRectangle(cornerRadius: 10, style: .continuous)
                                .strokeBorder(Color.white.opacity(0.08), lineWidth: 0.5)
                        )
                )

                if showsClearAll {
                    clearAllButton
                }
                planButton
            }
            ScrollViewReader { proxy in
                ScrollView {
                    sessionsList
                }
                // A row the arrow keys reach below the fold is brought into view.
                .onChange(of: selectedSessionIndex) { _, selected in
                    let rows = rowsOnShow
                    guard let selected, rows.indices.contains(selected) else { return }
                    proxy.scrollTo(rows[selected].id)
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
    }

    /// Clear All is offered where the app wants it, for the one provider
    /// whose conversations can be deleted (agy's; the engine refuses any
    /// other), while there is something to clear and no filter is typed:
    /// it clears the folder's conversations, not the ones the filter shows.
    private var showsClearAll: Bool {
        chrome.offersClearAll
            && engine.activeProvider.id == NexusAgentCLIProvider.antigravity.id
            && !session.sessions.isEmpty
            && session.sessionFilter.trimmingCharacters(in: .whitespaces).isEmpty
    }

    /// Two clicks, as in the standalone app: the first turns the button
    /// into a question, the second within two seconds deletes. Whether a
    /// click deletes is decided from the time of the first click and the
    /// time of this one (`NexusAgentClearAllGuard`), not from anything
    /// that has to run in between: Clear All cannot be undone, so a first
    /// click must never be left counting. While the deleting runs the
    /// button is replaced by a spinner, and cannot start another.
    @ViewBuilder
    private var clearAllButton: some View {
        if session.isClearingSessions {
            ProgressView()
                .controlSize(.small)
                .accessibilityLabel(strings.clearAll)
        } else {
            let asking = NexusAgentClearAllGuard.isArmed(firstClick: clearAllFirstClick, now: Date())
            Button {
                switch NexusAgentClearAllGuard.click(firstClick: clearAllFirstClick, now: Date()) {
                case .arm(let time):
                    clearAllFirstClick = time
                case .delete:
                    clearAllFirstClick = nil
                    session.deleteAll(in: engine.configuration)
                }
            } label: {
                Text(asking ? strings.clearAllConfirm : strings.clearAll)
                    .font(.caption)
                    .foregroundStyle(asking ? Color.red : Color.red.opacity(0.6))
                    .fontWeight(asking ? .semibold : .regular)
                    .contentTransition(.numericText())
                    .animation(.easeInOut(duration: 0.15), value: asking)
            }
            .buttonStyle(.plain)
            // Only for the look of it: when the two seconds are up the
            // first click is forgotten, which redraws the button with its
            // name. If this wait is cut short (the button went away), the
            // time stays, and is too old to count whenever it is read.
            .task(id: clearAllFirstClick) {
                guard let first = clearAllFirstClick else { return }
                let left = NexusAgentClearAllGuard.window - Date().timeIntervalSince(first)
                if left > 0 {
                    try? await Task.sleep(nanoseconds: UInt64(left * 1_000_000_000))
                }
                if !Task.isCancelled, clearAllFirstClick == first { clearAllFirstClick = nil }
            }
            // A button that goes (a filter typed, the drawer closed, a
            // conversation opened) comes back unasked.
            .onDisappear { clearAllFirstClick = nil }
        }
    }

    /// One row of the drawer. `index` is its place among the rows on show,
    /// which is what the arrow keys' selection counts.
    private func sessionRow(_ summary: NexusAgentSessionSummary, index: Int) -> NexusAgentSessionRow {
        NexusAgentSessionRow(summary: summary, session: session, engine: engine, strings: strings,
                             isSelected: selectedSessionIndex == index,
                             // The pointer takes over from the keyboard, as in the standalone.
                             onHover: { hovering in if hovering { selectedSessionIndex = nil } })
    }

    private var sessionsList: some View {
        let activeSessions = session.filteredSessions.filter { !$0.isArchived }
        let archivedSessions = session.filteredSessions.filter { $0.isArchived }

        return LazyVStack(spacing: 6) {
            if activeSessions.isEmpty && archivedSessions.isEmpty {
                if chrome.isEmbedded {
                    agentEnvironmentCard
                } else {
                    // Conversations there are, and the filter shows none
                    // of them: say that, not that there are none.
                    Text(session.sessions.isEmpty ? strings.noSessions : strings.noMatchingSessions)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .padding(.top, 24)
                }
            }

            ForEach(Array(activeSessions.enumerated()), id: \.element.id) { index, summary in
                sessionRow(summary, index: index)
            }

            if !archivedSessions.isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    Button {
                        withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
                            isArchivedExpanded.toggle()
                        }
                    } label: {
                        HStack(spacing: 6) {
                            Image(systemName: isArchivedExpanded ? "chevron.down" : "chevron.right")
                                .font(.system(size: 10, weight: .semibold))
                                .foregroundStyle(.secondary)
                            Text("\(strings.archivedPrefix)\(archivedSessions.count)\(strings.archivedSuffix)")
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundStyle(.secondary)
                            Spacer()
                        }
                        .padding(.horizontal, 6)
                        .padding(.vertical, 4)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)

                    if isArchivedExpanded {
                        ForEach(Array(archivedSessions.enumerated()), id: \.element.id) { index, summary in
                            sessionRow(summary, index: activeSessions.count + index)
                                .opacity(0.85)
                        }
                        .transition(.opacity.combined(with: .move(edge: .top)))
                    }
                }
                .padding(.top, 4)
            }
        }
    }

    private var agentEnvironmentCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Image(systemName: "sparkles")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(NexusAgentTheme.warmCoral)
                Text(strings.agentEnvironment)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.9))
                Spacer()
                HStack(spacing: 4) {
                    Circle()
                        .fill(NexusAgentTheme.warmCoral)
                        .frame(width: 6, height: 6)
                    Text(strings.ready)
                        .font(.system(size: 9.5, weight: .medium))
                        .foregroundStyle(NexusAgentTheme.warmCoral)
                }
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(Capsule().fill(NexusAgentTheme.warmCoral.opacity(0.14)))
            }

            VStack(alignment: .leading, spacing: 6) {
                environmentRow(label: strings.environmentProvider, value: engine.configuration.activeProvider.name, icon: "cpu")
                environmentRow(label: strings.environmentModel, value: engine.configuration.model.isEmpty ? strings.defaultModel : engine.configuration.model, icon: "cube")
                environmentRow(label: strings.environmentDirectory, value: URL(fileURLWithPath: session.workingDirectory(for: engine.configuration)).lastPathComponent, icon: "folder")
            }

            Divider().opacity(0.2)

            Text(strings.environmentHint)
                .font(.system(size: 10))
                .foregroundStyle(.secondary)
                .lineLimit(2)
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Color.white.opacity(0.065))
                .overlay(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .strokeBorder(Color.white.opacity(0.08), lineWidth: 0.5)
                )
        )
        .padding(.top, 8)
    }

    private func environmentRow(label: String, value: String, icon: String) -> some View {
        HStack(spacing: 6) {
            Image(systemName: icon)
                .font(.system(size: 9))
                .foregroundStyle(.secondary)
                .frame(width: 14)
            Text(label)
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(.secondary)
                .frame(width: 58, alignment: .leading)
            Text(value)
                .font(.system(size: 10, weight: .semibold, design: .monospaced))
                .foregroundStyle(.white.opacity(0.85))
                .lineLimit(1)
        }
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
                Text(strings.resumed)
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(NexusAgentTheme.warmCoral.opacity(0.9))
                    .padding(.horizontal, 5)
                    .padding(.vertical, 1)
                    .background(Capsule().fill(NexusAgentTheme.warmCoral.opacity(0.18)))
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

            ChatProviderBadge(engine: engine, strings: strings)
            ChatModelBadge(engine: engine, strings: strings)
            ChatWorkingDirectoryBadge(engine: engine, session: session, strings: strings, showWindow: chrome.showWindow)

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
            .help(strings.newChat + strings.newChatShortcut)
            .onHover { hoveringNewChat = $0 }

            Button {
                session.toggleSessions(configuration: engine.configuration)
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

            if let pinned = chrome.isPinned {
                Button {
                    pinned.wrappedValue.toggle()
                } label: {
                    Group {
                        if pinned.wrappedValue {
                            Image(systemName: "pin.circle.fill")
                        } else {
                            Image(systemName: "pin.circle")
                        }
                    }
                    .font(.system(size: 16))
                    .foregroundStyle(pinned.wrappedValue ? NexusAgentTheme.warmCoral : (hoveringPin ? Color.primary : Color.secondary.opacity(0.5)))
                    .rotationEffect(.degrees(pinned.wrappedValue ? 0 : 45))
                    .scaleEffect(hoveringPin ? 1.1 : 1.0)
                    .animation(.spring(response: 0.3, dampingFraction: 0.7), value: pinned.wrappedValue)
                    .animation(.easeInOut(duration: 0.15), value: hoveringPin)
                }
                .buttonStyle(.plain)
                .help(pinned.wrappedValue ? strings.unpinWindow : strings.pinWindow)
                .onHover { hoveringPin = $0 }
            }

            if let dockToNotch = chrome.dockToNotch {
                Button {
                    dockToNotch()
                } label: {
                    Image(systemName: "sparkles.rectangle.stack")
                        .font(.system(size: 15))
                        .foregroundStyle(hoveringDock ? Color.primary : Color.secondary.opacity(0.5))
                        .scaleEffect(hoveringDock ? 1.1 : 1.0)
                        .animation(.easeInOut(duration: 0.15), value: hoveringDock)
                }
                .buttonStyle(.plain)
                .help(chrome.dockToNotchHelp)
                .onHover { hoveringDock = $0 }
            }
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
                            if !(message.role == .agent && message.text.isEmpty && message.approvalRequest == nil && (message.toolSteps ?? []).isEmpty) {
                                NexusAgentMessageBubble(message: message, strings: strings, errorScheme: chrome.errorScheme, onDecision: { decision in
                                    session.decideApproval(messageID: message.id, decision: decision)
                                })
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
                                    engine.retryQuickPrompt()
                                } label: {
                                    HStack(spacing: 4) {
                                        Image(systemName: "arrow.clockwise")
                                            .font(.caption)
                                        Text(strings.retry)
                                            .font(.caption)
                                    }
                                    .foregroundStyle(NexusAgentTheme.warmCoral)
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
                // Written through bindings: some SDKs call these two off the
                // view's own isolation, where its state cannot be named.
                .onPreferenceChange(ScrollOffsetPreferenceKey.self) { [nearBottom = $isNearBottom, viewHeight = $scrollViewHeight] maxY in
                    nearBottom.wrappedValue = maxY < viewHeight.wrappedValue + 60
                }
                .onPreferenceChange(ScrollViewHeightPreferenceKey.self) { [viewHeight = $scrollViewHeight] height in
                    viewHeight.wrappedValue = height
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
                .foregroundStyle(NexusAgentTheme.gradient)
                .frame(width: 22, height: 22)
                .background(Circle().fill(NexusAgentTheme.warmCoral.opacity(0.18)))

            HStack(spacing: 4) {
                ForEach(0..<3, id: \.self) { i in
                    Circle()
                        .fill(NexusAgentTheme.warmCoral.opacity(0.7))
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
                .onSubmit { if session.canSend { engine.sendQuickPrompt() } }
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
                .background(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(Color.white.opacity(0.065))
                        .overlay(
                            RoundedRectangle(cornerRadius: 12, style: .continuous)
                                .strokeBorder(session.planMode ? NexusAgentTheme.warmCoral.opacity(0.6) : Color.white.opacity(0.08), lineWidth: 0.5)
                        )
                )
            sendButton
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
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
