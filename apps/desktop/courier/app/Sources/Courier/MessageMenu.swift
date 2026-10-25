// Copyright 2026 VitruvianSoftware
// SPDX-License-Identifier: AGPL-3.0-or-later

import CourierCore
import SwiftUI

/// A message's menu (02 §3.4.2's order, the 4.3 subset), from `MessageMenu.sections`: the sections a divider apart,
/// each item with its key, a greyed one with why as its tooltip, and the greyed lines that only say something.
struct MessageMenuItems: View {
    let sections: [[MessageMenuItem]]
    let choose: (MessageMenuItem.Command) -> Void

    var body: some View {
        ForEach(Array(sections.enumerated()), id: \.offset) { index, section in
            if index > 0 { Divider() }
            ForEach(section) { item in
                button(item)
            }
        }
    }

    @ViewBuilder
    private func button(_ item: MessageMenuItem) -> some View {
        if let key = item.key {
            Button(item.title) { choose(item.command) }
                .keyboardShortcut(key.shortcut)
                .disabled(!item.isEnabled)
                .help(item.help ?? "")
        } else {
            Button(item.title) { choose(item.command) }
                .disabled(!item.isEnabled)
                .help(item.help ?? "")
        }
    }
}

/// The same menu as a list, for a double click set to "Show the menu", and for the snapshots: what the context
/// menu holds, drawn where it can be seen.
struct MessageMenuList: View {
    let sections: [[MessageMenuItem]]
    let choose: (MessageMenuItem.Command) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(Array(sections.enumerated()), id: \.offset) { index, section in
                if index > 0 { Divider().padding(.vertical, 4) }
                ForEach(section) { item in
                    Button { choose(item.command) } label: {
                        HStack(spacing: 16) {
                            VStack(alignment: .leading, spacing: 1) {
                                Text(item.title)
                                    .foregroundStyle(item.isEnabled ? .primary : .secondary)
                                if let help = item.help {
                                    Text(help).font(.caption).foregroundStyle(.secondary)
                                }
                            }
                            Spacer(minLength: 0)
                            if let key = item.key {
                                Text(key.symbols).foregroundStyle(.secondary)
                            }
                        }
                        .padding(.horizontal, 10)
                        .padding(.vertical, 3)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .disabled(!item.isEnabled)
                }
            }
        }
        .padding(.vertical, 6)
        .frame(minWidth: 240)
    }
}

extension MenuKey {
    var shortcut: KeyboardShortcut {
        switch self {
        case .commandT: KeyboardShortcut("t", modifiers: .command)
        case .commandR: KeyboardShortcut("r", modifiers: .command)
        case .commandDown: KeyboardShortcut(.downArrow, modifiers: .command)
        case .commandC: KeyboardShortcut("c", modifiers: .command)
        case .commandShiftH: KeyboardShortcut("h", modifiers: [.command, .shift])
        case .commandShiftF: KeyboardShortcut("f", modifiers: [.command, .shift])
        }
    }
}

/// What a message row does, for the chat's rows and the thread pane's: its menu from `MessageMenu`, its items through
/// `MessageActionsModel.perform(_:on:from:)` (the pane's `from: .thread`, the chat's `.chat`), its poll votes, its
/// thread, and a click on a held message when "Click pending messages to undo send" is on.
@MainActor
enum MessageRowActions {
    static func make(conversation: ConversationModel, messageActions: MessageActionsModel,
                     preferences: ComposerPreferences, composer: ComposerModel, ui: MessageUI, source: MessageSource,
                     select: @escaping (String) -> Void) -> MessageActions {
        func perform(_ action: MessageAction, _ id: String) {
            Task { await messageActions.perform(action, on: id, from: source) }
        }
        /// Reply, or where the chat's replies are thread replies, Reply in Thread.
        func reply(_ id: String) {
            guard let message = conversation.message(id, from: source),
                  let action = conversation.replyAction(for: message) else { return }
            perform(action, id)
        }
        return MessageActions(
            select: select,
            reply: reply,
            react: { id, key in Task { await conversation.react(to: id, key: key) } },
            retry: { id in Task { await conversation.retry(id) } },
            discard: { id in Task { await conversation.discard(id) } },
            dontSend: { id in Task { await messageActions.dontSend(id, from: source) } },
            waitingHelp: { StatusLine.waitingHelp(network: conversation.network) },
            menu: { message in
                MessageMenu.sections(for: message, available: conversation.availableActions(for: message),
                                     features: conversation.features, disappearsIn: conversation.disappearsIn(message),
                                     time: { $0.formatted(date: .abbreviated, time: .shortened) })
            },
            perform: { command, id in
                switch command {
                case let .action(action): perform(action, id)
                case .showReplies: conversation.openThread(id)
                case .info: break
                }
            },
            undoHeld: preferences.clickPendingToUndo ? { id in Task { await composer.undoHeld(id) } } : nil,
            vote: { id, options in Task { await messageActions.vote(id, options: options) } },
            openThread: source == .chat ? { conversation.openThread($0) } : nil,
            timerNote: { conversation.timerChangeNote(for: $0) },
            callCaller: { conversation.callCaller(for: $0) },
            disappearsIn: { conversation.disappearsIn($0) },
            timerChoices: { conversation.timerChoices },
            setTimer: { choice in Task { await conversation.setTimer(choice) } },
            doubleClick: { id in
                switch preferences.doubleClickMessage {
                case .reply: reply(id)
                case .nothing, .menu: break // .menu: the row shows the menu itself
                case .reactionPicker: perform(.react, id)
                case .forward: perform(.forward, id)
                case .reactWith: Task { await conversation.react(to: id, key: preferences.quickReaction) }
                }
            },
            doubleClickShowsMenu: preferences.doubleClickMessage == .menu,
            hoverSender: { hovering, message in
                conversation.setTriggerHovered(hovering, for: message)
            })
    }
}
