// Copyright 2026 VitruvianSoftware
// SPDX-License-Identifier: AGPL-3.0-or-later

import VitruvianCourierCore
import SwiftUI

/// The chat header's Disappearing Messages menu (01 §5): Off, then the chat's timers, the one in use ticked, and the
/// line that says what it does. Only for a chat whose network has a timer.
struct DisappearingMenu: View {
    @ObservedObject var conversation: ConversationModel
    /// In the window's toolbar (with Liquid Glass): the toolbar's own menu style, not a borderless one.
    var inToolbar = false

    var body: some View {
        let choices = conversation.timerChoices
        if !choices.isEmpty {
            let menu = Menu {
                DisappearingItems(choices: choices) { choice in Task { await conversation.setTimer(choice) } }
            } label: {
                Image(systemName: conversation.features.currentTimer.map { $0.timerMS > 0 } == true
                    ? "timer" : "timer.circle")
            }
            Group {
                if inToolbar { menu } else { menu.menuStyle(.borderlessButton) }
            }
            .menuIndicator(.hidden)
            .fixedSize()
            .disabled(conversation.isChangingTimer)
            .help(String(localized: "Disappearing Messages"))
            .accessibilityLabel(String(localized: "Disappearing Messages"))
        }
    }
}

/// The timer choices, for the header's menu and a timer note's "Change Setting".
struct DisappearingItems: View {
    let choices: [DisappearingChoice]
    let set: (DisappearingChoice) -> Void

    var body: some View {
        Section {
            ForEach(choices) { choice in
                Toggle(choice.title, isOn: Binding(get: { choice.isCurrent }, set: { if $0 { set(choice) } }))
            }
        } header: {
            Text(String(localized: "Disappearing Messages"))
        }
        Divider()
        Text(String(localized: "For added privacy, new messages disappear after the set time."))
    }
}
