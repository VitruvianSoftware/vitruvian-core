// Copyright 2026 VitruvianSoftware
// SPDX-License-Identifier: AGPL-3.0-or-later

import CourierCore
import SwiftUI

/// Remind Me ▸: Last Used, the suggested times, Custom…, and Dismiss Reminder when there is one.
struct RemindMeMenu: View {
    @ObservedObject var inbox: InboxModel
    let ui: InboxUI
    let ids: [String]?

    var body: some View {
        Menu(String(localized: "Remind Me")) {
            RemindMeItems(inbox: inbox, ui: ui, ids: ids)
        }
        .help(String(localized: "Brings the chat back to your inbox at the time you pick."))
    }
}

/// The Remind Me items, for a menu or the ⌘L popover. Times are worked out in the Mac's time zone, when the item
/// is chosen.
struct RemindMeItems: View {
    @ObservedObject var inbox: InboxModel
    let ui: InboxUI
    let ids: [String]?
    /// Called after an item was chosen (the popover closes).
    var done: () -> Void = {}

    var body: some View {
        if inbox.isEntitled(.reminders) {
            let presets = ReminderPresets.presets(
                now: Date(),
                calendar: .current,
                lastUsed: inbox.preferences.lastUsedReminder,
                suggestions: inbox.preferences.timeSuggestions
            )
            ForEach(Array(presets.enumerated()), id: \.offset) { _, preset in
                Button(preset.title) { remind(preset.title, fallback: preset.date) }
            }
            Divider()
            Button(String(localized: "Custom…")) {
                let request = ReminderRequest(ids: ids ?? inbox.targets)
                inbox.customReminder = request
                ui.customReminder = request
                done()
            }
        } else {
            Button(String(localized: "Available with a plan")) {}
                .disabled(true)
        }
        if inbox.targetRows(ids).contains(where: { $0.reminder != nil }) {
            Divider()
            Button(String(localized: "Dismiss Reminder")) {
                Task { await inbox.dismissReminder(ids: ids) }
                done()
            }
        }
    }

    /// A menu is drawn before it is opened, so "In an Hour" is worked out again from now when it is chosen.
    private func remind(_ title: String, fallback: Date) {
        let now = Date()
        let due = ReminderPresets.presets(
            now: now,
            calendar: .current,
            lastUsed: inbox.preferences.lastUsedReminder,
            suggestions: inbox.preferences.timeSuggestions
        )
            .first { $0.title == title }?.date ?? fallback
        let condition = inbox.preferences.remindDefault
        Task { await inbox.remind(at: max(due, now.addingTimeInterval(60)), condition: condition, ids: ids) }
        done()
    }
}

/// Remind Me ▸ Custom…: a day and a time, in the Mac's time zone, and whether to remind only if no one has
/// answered.
struct CustomReminderSheet: View {
    let request: ReminderRequest
    let inbox: InboxModel
    @Environment(\.dismiss) private var dismiss
    @State private var date = Calendar.current.date(byAdding: .day, value: 1, to: Date()) ?? Date()
    @State private var condition = RemindCondition.ifNoReply

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(String(localized: "Remind Me"))
                .font(.headline)
            DatePicker(String(localized: "When"), selection: $date, in: range,
                       displayedComponents: [.date, .hourAndMinute])
                .datePickerStyle(.graphical)
                .labelsHidden()
                .environment(\.timeZone, .current)
            Picker(String(localized: "Remind me"), selection: $condition) {
                Text(String(localized: "If no reply")).tag(RemindCondition.ifNoReply)
                Text(String(localized: "Always")).tag(RemindCondition.always)
            }
            .help(RemindHelp.condition)
            HStack {
                Spacer()
                Button(String(localized: "Cancel"), role: .cancel) { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button(String(localized: "Set Reminder")) {
                    let due = max(date, Date().addingTimeInterval(60))
                    Task { await inbox.remind(at: due, condition: condition, ids: request.ids) }
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(20)
        .frame(width: 340)
        .onAppear { condition = inbox.preferences.remindDefault }
    }

    /// From a minute from now to five years ahead: the engine takes no more.
    private var range: ClosedRange<Date> {
        let now = Date()
        let last = Calendar.current.date(byAdding: DateComponents(year: 5, day: -1), to: now) ?? now
        return now.addingTimeInterval(60) ... last
    }
}

enum RemindHelp {
    /// What "If no reply" means. Inferred (inventory 01 §18): "if I haven't sent a message since setting it".
    static var condition: String {
        String(localized: "“If no reply” skips the reminder when you have sent a message in the chat since you set it.")
    }
}
