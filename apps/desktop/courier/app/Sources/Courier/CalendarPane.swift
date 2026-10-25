// Copyright 2026 VitruvianSoftware
// SPDX-License-Identifier: AGPL-3.0-or-later

import AppKit
import CourierCore
import SwiftUI

/// The Calendar right sidebar (`width: 280`, toggled by `⌘⌥K`).
///
/// Shows the user's macOS Calendar (`EventKit`) schedule for the selected day with 1-click **Join** buttons
/// on video calls (`meet.google.com`, `zoom.us`, `teams.microsoft.com`, `webex.com`). When Calendar access is
/// `.denied` or `.restricted`, renders a non-blocking explanation and an **Open System Settings** button.
public struct CalendarPane: View {
    @ObservedObject public var bridge: CalendarBridge
    public var showsCloseButton: Bool
    public var locale: Locale
    public var onJoinMeeting: ((URL) -> Void)?
    public var onClose: () -> Void

    public init(
        bridge: CalendarBridge,
        showsCloseButton: Bool = true,
        locale: Locale = Locale(identifier: "en_US"),
        onJoinMeeting: ((URL) -> Void)? = nil,
        onClose: @escaping () -> Void = {}
    ) {
        self.bridge = bridge
        self.showsCloseButton = showsCloseButton
        self.locale = locale
        self.onJoinMeeting = onJoinMeeting
        self.onClose = onClose
    }

    public var body: some View {
        VStack(spacing: 0) {
            topBar
            Divider()
            dayNavigationHeader
            Divider()
            contentArea
        }
        .frame(width: 280)
        .background(Color(nsColor: .textBackgroundColor).opacity(0.4))
    }

    // MARK: - Top Bar

    private var topBar: some View {
        HStack(spacing: 8) {
            Label(String(localized: "Calendar"), systemImage: "calendar")
                .font(.headline)
            Spacer(minLength: 0)
            if showsCloseButton {
                Button(action: onClose) {
                    Image(systemName: "xmark")
                }
                .buttonStyle(.borderless)
                .help(String(localized: "Close Calendar (⌘⌥K)"))
                .accessibilityLabel(String(localized: "Close calendar"))
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .frame(minHeight: 48)
        .accessibilityAddTraits(.isHeader)
    }

    // MARK: - Day Navigation Header

    private var dayNavigationHeader: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(formattedDayLabel(bridge.selectedDay))
                .font(.subheadline.weight(.semibold))
                .lineLimit(1)

            HStack(spacing: 6) {
                Button {
                    Task { await bridge.selectPreviousDay() }
                } label: {
                    Image(systemName: "chevron.left")
                        .frame(width: 20, height: 20)
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .help(String(localized: "Previous Day"))
                .accessibilityLabel(String(localized: "Previous Day"))

                Button(String(localized: "Today")) {
                    Task { await bridge.selectToday() }
                }
                .buttonStyle(.bordered)
                .controlSize(.small)

                Button {
                    Task { await bridge.selectNextDay() }
                } label: {
                    Image(systemName: "chevron.right")
                        .frame(width: 20, height: 20)
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .help(String(localized: "Next Day"))
                .accessibilityLabel(String(localized: "Next Day"))

                Spacer(minLength: 0)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
    }

    // MARK: - Content

    @ViewBuilder
    private var contentArea: some View {
        switch bridge.status {
        case .denied, .restricted:
            deniedView
        case .notDetermined, .writeOnly:
            notDeterminedView
        case .fullAccess:
            if bridge.events.isEmpty {
                emptyEventsView
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 8) {
                        ForEach(bridge.events) { event in
                            eventRow(event)
                        }
                    }
                    .padding(12)
                }
            }
        }
    }

    private var deniedView: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top, spacing: 8) {
                Image(systemName: "calendar.badge.exclamationmark")
                    .font(.title3)
                    .foregroundStyle(.secondary)
                Text(String(localized: "Calendar access is turned off in System Settings."))
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Button(String(localized: "Open System Settings")) {
                if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Calendars") {
                    NSWorkspace.shared.open(url)
                }
            }
            .buttonStyle(.bordered)
            .controlSize(.small)

            Spacer(minLength: 0)
        }
        .padding(14)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private var notDeterminedView: some View {
        VStack(spacing: 10) {
            Image(systemName: "calendar")
                .font(.title2)
                .foregroundStyle(.secondary)
            Text(String(localized: "Show your macOS Calendar schedule here."))
                .font(.callout)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            Button(String(localized: "Allow Calendar Access")) {
                Task { await bridge.loadSelectedDay() }
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.small)
        }
        .padding(20)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var emptyEventsView: some View {
        VStack(spacing: 8) {
            Image(systemName: "calendar")
                .font(.title2)
                .foregroundStyle(.tertiary)
            Text(String(localized: "No events scheduled"))
                .font(.callout)
                .foregroundStyle(.secondary)
        }
        .padding(24)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func eventRow(_ item: CalendarEventItem) -> some View {
        HStack(alignment: .top, spacing: 8) {
            RoundedRectangle(cornerRadius: 2)
                .fill(Self.color(fromHex: item.calendarColorHex))
                .frame(width: 4)

            VStack(alignment: .leading, spacing: 3) {
                Text(item.title)
                    .font(.callout.weight(.semibold))
                    .lineLimit(2)

                Text(formattedTimeRange(for: item))
                    .font(.caption)
                    .foregroundStyle(.secondary)

                if let location = item.location, !location.isEmpty, item.meetingURL?.absoluteString != location {
                    Text(location)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }

            Spacer(minLength: 4)

            if let meetingURL = item.meetingURL, CalendarBridge.isAllowedMeetingURL(meetingURL) {
                Button(String(localized: "Join")) {
                    if let onJoinMeeting {
                        onJoinMeeting(meetingURL)
                    } else {
                        NSWorkspace.shared.open(meetingURL)
                    }
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
            }
        }
        .padding(8)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(Color.primary.opacity(0.05))
        )
    }

    // MARK: - Formatting Helpers

    private func formattedDayLabel(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = locale
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "EEE, MMM d, yyyy"
        return formatter.string(from: date)
    }

    private func formattedTimeRange(for item: CalendarEventItem) -> String {
        if item.isAllDay {
            return String(localized: "All day")
        }
        let formatter = DateFormatter()
        formatter.locale = locale
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateStyle = .none
        formatter.timeStyle = .short
        let start = formatter.string(from: item.startDate)
            .replacingOccurrences(of: "\u{202F}", with: " ")
            .replacingOccurrences(of: "\u{00A0}", with: " ")
        let end = formatter.string(from: item.endDate)
            .replacingOccurrences(of: "\u{202F}", with: " ")
            .replacingOccurrences(of: "\u{00A0}", with: " ")
        return "\(start) – \(end)"
    }

    private static func color(fromHex hex: String) -> Color {
        var cleaned = hex.trimmingCharacters(in: .whitespacesAndNewlines)
        if cleaned.hasPrefix("#") {
            cleaned.removeFirst()
        }
        guard cleaned.count == 6, let rgb = UInt64(cleaned, radix: 16) else {
            return .accentColor
        }
        let r = Double((rgb >> 16) & 0xFF) / 255.0
        let g = Double((rgb >> 8) & 0xFF) / 255.0
        let b = Double(rgb & 0xFF) / 255.0
        return Color(red: r, green: g, blue: b)
    }
}

/// Popover shown when clicking a dashed-underlined detected date in a message bubble.
/// Nothing is added to Calendar until the user explicitly clicks **Add to Calendar**.
public struct AddCalendarEventPopover: View {
    @ObservedObject public var bridge: CalendarBridge
    public let detectedDate: DetectedMessageDate
    public var locale: Locale
    public var onAdded: ((CalendarEventItem) -> Void)?
    public var onCancel: () -> Void

    @State private var title: String
    @State private var startDate: Date
    @State private var endDate: Date
    @State private var isSaving = false

    public init(
        bridge: CalendarBridge,
        defaultTitle: String,
        detectedDate: DetectedMessageDate,
        locale: Locale = Locale(identifier: "en_US"),
        onAdded: ((CalendarEventItem) -> Void)? = nil,
        onCancel: @escaping () -> Void = {}
    ) {
        self.bridge = bridge
        self.detectedDate = detectedDate
        self.locale = locale
        self.onAdded = onAdded
        self.onCancel = onCancel
        let cleanTitle = defaultTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        self._title = State(initialValue: cleanTitle.isEmpty ? detectedDate.matchedText : cleanTitle)
        self._startDate = State(initialValue: detectedDate.startDate)
        let duration = detectedDate.durationSeconds > 0 ? detectedDate.durationSeconds : 3600
        self._endDate = State(initialValue: detectedDate.startDate.addingTimeInterval(duration))
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 6) {
                Image(systemName: "calendar.badge.plus")
                    .foregroundStyle(Color.accentColor)
                Text(String(localized: "New Calendar Event"))
                    .font(.subheadline.weight(.semibold))
                Spacer(minLength: 0)
            }

            if bridge.isAccessDenied {
                VStack(alignment: .leading, spacing: 8) {
                    Text(String(localized: "Calendar access is turned off in System Settings."))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Button(String(localized: "Open System Settings")) {
                        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Calendars") {
                            NSWorkspace.shared.open(url)
                        }
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                }
            } else {
                VStack(alignment: .leading, spacing: 6) {
                    Text(String(localized: "Title"))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    TextField(String(localized: "Event title"), text: $title)
                        .textFieldStyle(.roundedBorder)
                        .controlSize(.small)

                    HStack(spacing: 6) {
                        Image(systemName: "clock")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Text(formattedScheduleSummary)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .padding(.top, 2)
                }

                if let error = bridge.lastError, !error.isEmpty {
                    Text(error)
                        .font(.caption2)
                        .foregroundStyle(.red)
                }

                HStack(spacing: 8) {
                    Spacer(minLength: 0)
                    Button(String(localized: "Cancel"), action: onCancel)
                        .controlSize(.small)
                    Button(String(localized: "Add to Calendar")) {
                        isSaving = true
                        Task {
                            defer { isSaving = false }
                            if let created = try? await bridge.addEvent(
                                title: title,
                                startDate: startDate,
                                endDate: endDate,
                                notes: nil
                            ) {
                                onAdded?(created)
                                onCancel()
                            }
                        }
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
                    .disabled(isSaving || title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
        }
        .padding(12)
        .frame(width: 280, alignment: .leading)
    }

    private var formattedScheduleSummary: String {
        let dayFormatter = DateFormatter()
        dayFormatter.locale = locale
        dayFormatter.timeZone = TimeZone(secondsFromGMT: 0)
        dayFormatter.dateFormat = "EEE, MMM d"

        let timeFormatter = DateFormatter()
        timeFormatter.locale = locale
        timeFormatter.timeZone = TimeZone(secondsFromGMT: 0)
        timeFormatter.dateStyle = .none
        timeFormatter.timeStyle = .short

        let dayStr = dayFormatter.string(from: startDate)
        let startStr = timeFormatter.string(from: startDate)
            .replacingOccurrences(of: "\u{202F}", with: " ")
            .replacingOccurrences(of: "\u{00A0}", with: " ")
        let endStr = timeFormatter.string(from: endDate)
            .replacingOccurrences(of: "\u{202F}", with: " ")
            .replacingOccurrences(of: "\u{00A0}", with: " ")
        return "\(dayStr) · \(startStr) – \(endStr)"
    }
}
