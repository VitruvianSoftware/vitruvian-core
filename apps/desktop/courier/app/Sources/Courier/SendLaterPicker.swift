// Copyright 2026 VitruvianSoftware
// SPDX-License-Identifier: AGPL-3.0-or-later

import CourierCore
import SwiftUI

/// Send Later (02 §2.6, ⌘⇧L): Remind Me's times, or a day and time, and whether it still goes if they write first.
/// Courier sends it itself, from this Mac, so the footer says the Mac must be awake with Courier running then.
struct SendLaterPicker: View {
    let composer: ComposerModel
    let preferences: ComposerPreferences
    /// Closes the picker (the request is answered).
    let done: () -> Void
    /// The moment the picker opened, for its suggestions; tests and snapshots give their own.
    var now = Date()
    @State private var date = Date()
    @State private var condition = SendLaterCondition.ifNoReply
    @State private var problem: String?
    @State private var started = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(String(localized: "Send Later"))
                .font(.headline)
            VStack(alignment: .leading, spacing: 0) {
                ForEach(Array(presets.enumerated()), id: \.offset) { _, preset in
                    Button { schedule(at: preset.date) } label: {
                        HStack {
                            Text(preset.title)
                            Spacer(minLength: 12)
                            Text(preset.date.formatted(.dateTime.weekday(.abbreviated).hour().minute()))
                                .foregroundStyle(.secondary)
                        }
                        .padding(.horizontal, 8)
                        .padding(.vertical, 5)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
            }
            .background(RoundedRectangle(cornerRadius: 8).fill(Color.primary.opacity(0.04)))
            DatePicker(String(localized: "When"), selection: $date, in: range,
                       displayedComponents: [.date, .hourAndMinute])
                .datePickerStyle(.graphical)
                .labelsHidden()
            Picker(String(localized: "Send it"), selection: $condition) {
                Text(String(localized: "If no reply")).tag(SendLaterCondition.ifNoReply)
                Text(String(localized: "Regardless")).tag(SendLaterCondition.always)
            }
            .help(String(localized: "“If no reply” doesn’t send it when someone else writes in the chat first."))
            if let problem {
                Text(problem)
                    .font(.callout)
                    .foregroundStyle(.red)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Text(String(localized: "Courier sends it from this Mac. It needs to be running, and your Mac awake, at that time."))
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            HStack {
                Spacer()
                Button(String(localized: "Cancel"), role: .cancel, action: done)
                    .keyboardShortcut(.cancelAction)
                Button(String(localized: "Schedule")) { schedule(at: date) }
                    .keyboardShortcut(.defaultAction)
                    .disabled(composer.isScheduling)
            }
        }
        .padding(20)
        .frame(width: 340)
        .onAppear {
            guard !started else { return }
            started = true
            condition = preferences.sendLaterDefault
            date = Calendar.current.date(byAdding: .hour, value: 1, to: now) ?? now
        }
    }

    private var presets: [(title: String, date: Date)] {
        ReminderPresets.presets(now: now, calendar: .current)
    }

    /// From a minute from now to five years ahead: the engine takes no more.
    private var range: ClosedRange<Date> {
        let last = Calendar.current.date(byAdding: DateComponents(year: 5, day: -1), to: now) ?? now
        return now.addingTimeInterval(60) ... last
    }

    /// Schedules for `due` as chosen. A time already past (a suggestion left open a while) or too far ahead is
    /// said, and the person picks again: it is never moved.
    private func schedule(at due: Date) {
        if let late = ScheduleTime.problem(with: due, now: Date()) {
            problem = late
            return
        }
        problem = nil
        let chosen = condition
        Task {
            do {
                try await composer.schedule(at: due, condition: chosen)
                done()
            } catch {
                problem = EngineErrorText.text(for: error, fallback: String(localized: "The message couldn’t be scheduled."))
            }
        }
    }
}
