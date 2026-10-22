// Copyright 2026 VitruvianSoftware
// SPDX-License-Identifier: AGPL-3.0-or-later

import CourierCore
import SwiftUI

/// Above the composer, the open chat's messages to send later (01 §5's ScheduledMessages), from the model.
struct ScheduledStrip: View {
    @ObservedObject var scheduled: ScheduledModel

    var body: some View {
        ScheduledList(messages: scheduled.scheduled, actions: ScheduledActions(
            sendNow: { id in Task { await scheduled.sendNow(id) } },
            delete: { id in Task { await scheduled.delete(id) } },
            edit: { id, text in Task { await scheduled.edit(id, text: text) } },
            reschedule: { id, due in Task { await scheduled.reschedule(id, to: due) } }))
    }
}

/// What a scheduled message's buttons do.
struct ScheduledActions {
    var sendNow: (Int64) -> Void = { _ in }
    var delete: (Int64) -> Void = { _ in }
    var edit: (Int64, RichText) -> Void = { _, _ in }
    var reschedule: (Int64, Date) -> Void = { _, _ in }
}

/// "2 Messages to Send Later", which opens the list. Each row has its time, its words, and Send Now, Edit,
/// Reschedule and Delete Without Sending; one that won't go by itself says why.
struct ScheduledList: View {
    let messages: [ScheduledMessage]
    let actions: ScheduledActions
    @State var isOpen = false
    @State private var editing: ScheduledMessage?
    @State private var rescheduling: ScheduledMessage?

    var body: some View {
        if !messages.isEmpty {
            VStack(alignment: .leading, spacing: 6) {
                Button { withAnimation(.easeOut(duration: 0.15)) { isOpen.toggle() } } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "clock.arrow.circlepath")
                        Text(title)
                            .font(.callout.weight(.medium))
                        if messages.contains(where: { $0.state != .waiting }) {
                            Image(systemName: "exclamationmark.circle.fill")
                                .foregroundStyle(.orange)
                                .accessibilityLabel(String(localized: "Needs attention"))
                        }
                        Spacer(minLength: 0)
                        Image(systemName: isOpen ? "chevron.up" : "chevron.down")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                if isOpen {
                    ForEach(messages) { message in
                        ScheduledRow(message: message, actions: actions, edit: { editing = message },
                                     reschedule: { rescheduling = message })
                    }
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .background(Color.accentColor.opacity(0.06))
            .sheet(item: $editing) { message in ScheduledEditSheet(message: message, actions: actions) }
            .sheet(item: $rescheduling) { message in ScheduledRescheduleSheet(message: message, actions: actions) }
        }
    }

    private var title: String {
        let count = messages.count
        return count == 1 ? String(localized: "\(count) Message to Send Later")
            : String(localized: "\(count) Messages to Send Later")
    }
}

private struct ScheduledRow: View {
    let message: ScheduledMessage
    let actions: ScheduledActions
    let edit: () -> Void
    let reschedule: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: 8) {
                Text(Date(timeIntervalSince1970: Double(message.dueAt) / 1000)
                    .formatted(date: .abbreviated, time: .shortened))
                    .font(.caption.weight(.semibold))
                Text(message.condition == .always ? String(localized: "Regardless")
                    : String(localized: "If no reply"))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer(minLength: 0)
            }
            Text(message.text)
                .lineLimit(2)
                .font(.callout)
            if let state = stateLine {
                Label(state, systemImage: "exclamationmark.circle")
                    .font(.caption)
                    .foregroundStyle(.orange)
            }
            HStack(spacing: 12) {
                Button(String(localized: "Send Now")) { actions.sendNow(message.outboxID) }
                Button(String(localized: "Edit"), action: edit)
                Button(String(localized: "Reschedule"), action: reschedule)
                Button(String(localized: "Delete Without Sending"), role: .destructive) {
                    actions.delete(message.outboxID)
                }
            }
            .buttonStyle(.link)
            .font(.caption)
        }
        .padding(8)
        .background(RoundedRectangle(cornerRadius: 8).fill(Color.primary.opacity(0.05)))
        .accessibilityElement(children: .contain)
    }

    private var stateLine: String? {
        switch message.state {
        case .canceled: String(localized: "Canceled: they wrote first")
        case .missed: String(localized: "Missed its time while Courier was closed")
        default: nil
        }
    }
}

/// "Edit" on a scheduled message: its words. Their formatting stays while they are unchanged.
private struct ScheduledEditSheet: View {
    let message: ScheduledMessage
    let actions: ScheduledActions
    @Environment(\.dismiss) private var dismiss
    @State private var text = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(String(localized: "Edit Scheduled Message"))
                .font(.headline)
            TextEditor(text: $text)
                .font(.body)
                .frame(minHeight: 90)
                .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(.quaternary))
            HStack {
                Spacer()
                Button(String(localized: "Cancel"), role: .cancel) { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button(String(localized: "Save")) {
                    let rich = text == message.text ? RichText(text: text, entities: message.entities)
                        : RichText(text: text)
                    actions.edit(message.outboxID, rich)
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
                .disabled(text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .padding(20)
        .frame(width: 380)
        .onAppear { text = message.text }
    }
}

/// "Reschedule": a new day and time, which makes a canceled or missed message wait again.
private struct ScheduledRescheduleSheet: View {
    let message: ScheduledMessage
    let actions: ScheduledActions
    @Environment(\.dismiss) private var dismiss
    @State private var date = Date()
    @State private var problem: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(String(localized: "Reschedule"))
                .font(.headline)
            DatePicker(String(localized: "When"), selection: $date, in: range,
                       displayedComponents: [.date, .hourAndMinute])
                .datePickerStyle(.graphical)
                .labelsHidden()
                // A new pick clears what was said of the last.
                .onChange(of: date) { _, _ in problem = nil }
            if let problem {
                Text(problem)
                    .font(.callout)
                    .foregroundStyle(.red)
            }
            HStack {
                Spacer()
                Button(String(localized: "Cancel"), role: .cancel) { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button(String(localized: "Reschedule")) {
                    // A time that has passed while the sheet was open, or too far ahead, is said, not moved.
                    if let late = ScheduleTime.problem(with: date, now: Date()) {
                        problem = late
                        return
                    }
                    actions.reschedule(message.outboxID, date)
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(20)
        .frame(width: 340)
        .onAppear {
            let due = Date(timeIntervalSince1970: Double(message.dueAt) / 1000)
            date = max(due, Date().addingTimeInterval(3600))
        }
    }

    /// From a minute from now to five years ahead: the engine takes no more.
    private var range: ClosedRange<Date> {
        let now = Date()
        let last = Calendar.current.date(byAdding: DateComponents(year: 5, day: -1), to: now) ?? now
        return now.addingTimeInterval(60) ... last
    }
}
