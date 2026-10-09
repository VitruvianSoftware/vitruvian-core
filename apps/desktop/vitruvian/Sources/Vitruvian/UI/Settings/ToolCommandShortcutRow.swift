// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 VitruvianSoftware

import SwiftUI
import VitruvianCore
import VitruvianDesign
import VitruvianServices

/// One tool's commands that may have a shortcut, for the Shortcuts page.
package struct ToolCommandShortcutSection: Identifiable, Equatable {
    package let toolID: ToolID
    package let name: String
    package let commands: [CommandDescriptor]
    package var id: String { toolID.rawValue }

    // Spelled out because a memberwise initializer never leaves its module.
    package init(toolID: ToolID, name: String, commands: [CommandDescriptor]) {
        self.toolID = toolID
        self.name = name
        self.commands = commands
    }

    /// A section per tool, headed by the tool's own name. Sections are in
    /// the order of their tool ids, so the page reads the same whatever
    /// order the tools registered in; a tool's commands stay in the order it
    /// declared them. Empty when no registered command asks for a shortcut,
    /// and a tool that is switched off has no section.
    @MainActor package static func all(registry: ToolRegistry = .shared,
                                       language: AppLanguage = L10n.shared.language) -> [ToolCommandShortcutSection] {
        var byTool: [ToolID: [CommandDescriptor]] = [:]
        for command in registry.commands(on: .shortcut) {
            byTool[command.id.tool, default: []].append(command)
        }
        return byTool.keys.sorted { $0.rawValue < $1.rawValue }.map { tool in
            ToolCommandShortcutSection(toolID: tool,
                                       name: registry.name(for: tool, language: language) ?? tool.rawValue,
                                       commands: byTool[tool] ?? [])
        }
    }
}

/// What a tool command's row does with a combination the person recorded.
/// The rule is here, with everything it reads handed in; the row only calls
/// it and shows the answer.
package enum ToolCommandShortcutSave: Equatable {
    /// Give it to the registrar. `clearTakeOver` drops a take-over the
    /// command no longer needs.
    case save(clearTakeOver: Bool)
    case refuse(Refusal)
    /// macOS answers this combination: ask before taking it over.
    case offerTakeOver

    package enum Refusal: Equatable {
        /// Not a combination a global shortcut may use.
        case invalid
        /// Something else has it, by the name its own row shows.
        case held(by: String)
        /// The list of tool command shortcuts holds as many as it may.
        case full

        /// `limitFormat` is the Command Bar's "up to %d shortcuts" message,
        /// which does not name the Command Bar.
        package func message(_ strings: Strings, limitFormat: String) -> String {
            switch self {
            case .invalid: return strings.shortcutInvalid
            case .held(let name): return String(format: strings.shortcutConflictFormat, name)
            case .full: return String(format: limitFormat, ToolCommandShortcuts.limit)
            }
        }
    }

    /// Everything outside the list of tool command shortcuts that the rule asks.
    package struct Checks {
        /// The role or wheel that holds a combination, by name.
        package var roleHolder: (GlobalShortcut) -> String?
        /// The window-layout action, or the directional key, that holds it.
        package var windowLayoutHolder: (GlobalShortcut) -> String?
        /// The Command Bar row or other tool command that holds it.
        package var otherHolder: (GlobalShortcut) -> String?
        /// What to call a command, from its id text.
        package var commandName: (String) -> String
        package var conflictsWithMacOS: (GlobalShortcut) -> Bool
        /// Whether this command already took a macOS shortcut over.
        package var takenOver: Bool

        package init(roleHolder: @escaping (GlobalShortcut) -> String?,
                     windowLayoutHolder: @escaping (GlobalShortcut) -> String?,
                     otherHolder: @escaping (GlobalShortcut) -> String?,
                     commandName: @escaping (String) -> String,
                     conflictsWithMacOS: @escaping (GlobalShortcut) -> Bool,
                     takenOver: Bool) {
            self.roleHolder = roleHolder
            self.windowLayoutHolder = windowLayoutHolder
            self.otherHolder = otherHolder
            self.commandName = commandName
            self.conflictsWithMacOS = conflictsWithMacOS
            self.takenOver = takenOver
        }
    }

    /// Every list that can hold a combination is asked before it is saved,
    /// in the order the other rows ask: roles and wheels, window layout,
    /// then Command Bar rows and other tool commands. Then the list's own
    /// rules, the ones `ToolShortcutRegistrar.assign` enforces. macOS is
    /// asked last, so an offer is only made for a combination that would be
    /// kept if accepted.
    package static func decide(_ shortcut: GlobalShortcut, for id: CommandID,
                               saved: [String: GlobalShortcut], checks: Checks) -> ToolCommandShortcutSave {
        if let holder = checks.roleHolder(shortcut) { return .refuse(.held(by: holder)) }
        if let holder = checks.windowLayoutHolder(shortcut) { return .refuse(.held(by: holder)) }
        if let holder = checks.otherHolder(shortcut) { return .refuse(.held(by: holder)) }
        if let issue = ShortcutMap.assignmentIssue(shortcut, for: id.rawValue, in: saved,
                                                   limit: ToolCommandShortcuts.limit) {
            return .refuse(refusal(for: issue, commandName: checks.commandName))
        }
        switch SystemShortcutTakeoverSupport.recorderDecision(
            shortcut: shortcut,
            conflictsWithMacOS: checks.conflictsWithMacOS(shortcut),
            takenOver: checks.takenOver,
            current: ToolCommandShortcuts.shortcut(for: id, in: saved)) {
        case .offer: return .offerTakeOver
        case .save(let clearTakeOver): return .save(clearTakeOver: clearTakeOver)
        }
    }

    /// Why `ToolShortcutRegistrar.assign` saved nothing, as a row shows it.
    package static func refusal(for issue: ShortcutMap.AssignmentIssue,
                                commandName: (String) -> String) -> Refusal {
        switch issue {
        case .invalid: return .invalid
        case .occupied(let other): return .held(by: commandName(other))
        case .full: return .full
        }
    }

    /// What a save does to the command's take-over of a macOS shortcut.
    package enum TakeOver: Equatable {
        /// The person accepted the offer: switch it on.
        case accept
        /// The combination is not one macOS answers: drop a take-over left
        /// from the one before.
        case clear
        /// The combination already taken over, recorded again: leave it.
        case keep
    }

    /// How a save ended, for the row to show.
    package enum Outcome: Equatable {
        case saved
        /// Nothing was saved, and the take-over is as it was.
        case refused(Refusal)
    }

    /// The step after `decide`: hands `shortcut` to the list of tool command
    /// shortcuts through `assign`, whose answer is the last word.
    ///
    /// The take-over is written before the key is taken, because taking the
    /// key is what reads it (`assign` re-syncs the registrar). It is written
    /// only when it changes, and put back as it was if `assign` refuses.
    ///
    /// An offer can stay up while the person records on other rows, so by
    /// the time it is accepted something else may hold the combination.
    /// Accepting asks the holders again, in `decide`'s order, and refuses
    /// before anything is written. The other two follow `decide` at once.
    package static func commit(_ shortcut: GlobalShortcut, takeOver: TakeOver, checks: Checks,
                               isTakenOver: () -> Bool, setTakeOver: (Bool) -> Void,
                               assign: (GlobalShortcut) -> ShortcutMap.AssignmentIssue?) -> Outcome {
        if takeOver == .accept,
           let holder = checks.roleHolder(shortcut) ?? checks.windowLayoutHolder(shortcut)
           ?? checks.otherHolder(shortcut) {
            return .refused(.held(by: holder))
        }
        let was = isTakenOver()
        let wanted: Bool
        switch takeOver {
        case .accept: wanted = true
        case .clear: wanted = false
        case .keep: wanted = was
        }
        if wanted != was { setTakeOver(wanted) }
        if let issue = assign(shortcut) {
            if wanted != was { setTakeOver(was) }
            return .refused(refusal(for: issue, commandName: checks.commandName))
        }
        return .saved
    }
}

/// What a tool command's row shows about its shortcut.
package struct ToolCommandShortcutRowState: Equatable {
    /// What is saved, whether or not it is a working key.
    package let shortcut: GlobalShortcut?
    /// macOS would not give the key: another app holds it.
    package let isRefused: Bool
    /// Holds a key now: it has a combination, its command can run, and macOS gave it.
    package let isActive: Bool

    package init(shortcut: GlobalShortcut?, isRefused: Bool, isActive: Bool) {
        self.shortcut = shortcut
        self.isRefused = isRefused
        self.isActive = isActive
    }

    /// The one line under the row.
    package enum Caption: Equatable {
        /// Why the attempt just made was not saved.
        case error(String)
        /// The hint shown while the field is listening.
        case recording
        /// The saved key is one macOS would not give.
        case unavailable
    }

    /// Which line the row shows. The error of the attempt just made comes
    /// first, even when the saved key is also unavailable: it answers what
    /// the person just did. The row clears it when the next recording starts
    /// or a save succeeds, and the unavailable caption is back then. While a
    /// take-over is offered, the offer stands in its place.
    package func caption(error: String?, isRecording: Bool, isOfferingTakeOver: Bool) -> Caption? {
        if let error { return .error(error) }
        if isRecording { return .recording }
        if isRefused, !isOfferingTakeOver { return .unavailable }
        return nil
    }

    @MainActor package init(command id: CommandID, registry: ToolRegistry, registrar: ToolShortcutRegistrar) {
        let shortcut = ToolCommandShortcuts.shortcut(for: id, in: registrar.shortcuts)
        let isRefused = shortcut != nil && registrar.refused.contains(id)
        self.init(shortcut: shortcut, isRefused: isRefused,
                  isActive: shortcut != nil && !isRefused && registry.canRun(id))
    }
}

/// A tool command's row on the Shortcuts page: its shortcut, empty until the
/// person records one. Modelled on the window-layout row beside it, with no
/// Reset button, because a command has no default.
package struct ToolCommandShortcutRow: View {
    @ObservedObject private var l10n = L10n.shared
    @ObservedObject private var registry = ToolRegistry.shared
    @ObservedObject private var registrar = ToolShortcutRegistrar.shared
    private let command: CommandDescriptor
    @State private var errorText: String?
    @State private var isRecording = false
    @State private var pendingTakeOver: GlobalShortcut?

    package init(command: CommandDescriptor) {
        self.command = command
    }

    private var text: ShortcutSettingsStrings { FeatureStrings.shortcuts(l10n.language) }
    private var id: CommandID { command.id }
    private var takeOverKey: String { ToolCommandShortcuts.takeOverKey(for: id) }

    private var state: ToolCommandShortcutRowState {
        ToolCommandShortcutRowState(command: id, registry: registry, registrar: registrar)
    }

    package var body: some View {
        let state = state
        VStack(alignment: .leading, spacing: 5) {
            HStack(alignment: .top, spacing: 8) {
                ShortcutRowLabel(
                    title: registry.title(for: id, language: l10n.language) ?? command.title,
                    symbolName: command.symbol,
                    contextLabel: nil,
                    statusText: state.isActive ? text.active : text.inactive,
                    statusIsActive: state.isActive
                )
                Spacer()
                HStack(spacing: 8) {
                    ShortcutRecorderButton(
                        shortcut: pendingTakeOver ?? state.shortcut ?? .commandBarDefault,
                        isEnabled: true,
                        waitingTitle: l10n.s.shortcutPressKeys,
                        emptyTitle: pendingTakeOver == nil && state.shortcut == nil ? l10n.s.shortcutNone : nil,
                        clearAction: clear,
                        notCapturedAction: { errorText = l10n.s.shortcutNotCaptured },
                        recordingChanged: { recording in
                            isRecording = recording
                            if recording {
                                errorText = nil
                                pendingTakeOver = nil
                            }
                        },
                        invalidAction: { errorText = l10n.s.shortcutInvalid },
                        captureAction: save
                    )
                    .frame(width: 108)
                    Button {
                        clear()
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .symbolRenderingMode(.hierarchical)
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                    .disabled(state.shortcut == nil)
                    .help(l10n.s.shortcutClear)
                    .accessibilityLabel(l10n.s.shortcutClear)
                }
            }
            switch state.caption(error: errorText, isRecording: isRecording,
                                 isOfferingTakeOver: pendingTakeOver != nil) {
            case .error(let text):
                Text(text)
                    .font(.caption)
                    .foregroundStyle(.orange)
            case .recording:
                Text(ShortcutRecordingCaption.text(l10n.s, canClear: true))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            case .unavailable:
                // Read from the registrar each time, so it goes when macOS
                // gives the key after all.
                Text(l10n.s.shortcutUnavailable)
                    .font(.caption)
                    .foregroundStyle(.orange)
            case .none:
                EmptyView()
            }
            if let pendingTakeOver {
                SystemShortcutTakeOverOffer(
                    shortcut: pendingTakeOver,
                    onAccept: {
                        self.pendingTakeOver = nil
                        commit(pendingTakeOver, takeOver: .accept)
                    },
                    onDismiss: {
                        self.pendingTakeOver = nil
                        errorText = message(.held(by: "macOS"))
                    }
                )
            }
        }
        .onChange(of: l10n.language) { _, _ in errorText = nil }
    }

    private func message(_ refusal: ToolCommandShortcutSave.Refusal) -> String {
        refusal.message(l10n.s, limitFormat: FeatureStrings.commandBar(l10n.language).rowShortcutsLimitFormat)
    }

    /// A command by its id text, as the other rows name a holder.
    private func commandName(_ text: String) -> String {
        ShortcutConflicts.name(of: .toolCommand(text), rowTitle: { _ in nil }, rowFallback: text,
                               commandTitle: { registry.title(for: $0, language: l10n.language) })
    }

    private func clear() {
        errorText = nil
        pendingTakeOver = nil
        // The registrar switches the command's take-over off with it.
        registrar.assign(nil, to: id)
    }

    /// What the rule asks of the rest of the app, read when it is asked.
    private var checks: ToolCommandShortcutSave.Checks {
        let strings = l10n.s
        let id = id
        return ToolCommandShortcutSave.Checks(
            roleHolder: {
                GlobalShortcutRole.conflict(for: $0, excluding: nil, includeInactive: true)?.title(strings)
            },
            windowLayoutHolder: { WindowLayoutService.shared.shortcutConflictTitle($0, excluding: nil) },
            otherHolder: { ShortcutConflicts.title(for: $0, excludingCommand: id) },
            commandName: commandName,
            conflictsWithMacOS: { SystemShortcutTakeover.conflictsWithMacOS($0) },
            takenOver: SystemShortcutTakeover.isTakenOver(takeOverKey))
    }

    private func save(_ shortcut: GlobalShortcut) {
        switch ToolCommandShortcutSave.decide(shortcut, for: id, saved: registrar.shortcuts, checks: checks) {
        case .refuse(let refusal):
            errorText = message(refusal)
        case .offerTakeOver:
            pendingTakeOver = shortcut
            errorText = nil
        case .save(let clearTakeOver):
            commit(shortcut, takeOver: clearTakeOver ? .clear : .keep)
        }
    }

    /// Saves through `ToolCommandShortcutSave.commit`, and shows its answer.
    private func commit(_ shortcut: GlobalShortcut, takeOver: ToolCommandShortcutSave.TakeOver) {
        let key = takeOverKey
        let outcome = ToolCommandShortcutSave.commit(
            shortcut, takeOver: takeOver, checks: checks,
            isTakenOver: { SystemShortcutTakeover.isTakenOver(key) },
            setTakeOver: { SystemShortcutTakeover.setTakeOver(key, $0) },
            assign: { registrar.assign($0, to: id) })
        switch outcome {
        case .saved: errorText = nil
        case .refused(let refusal): errorText = message(refusal)
        }
    }
}
