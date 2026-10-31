// Copyright 2026 VitruvianSoftware
// SPDX-License-Identifier: AGPL-3.0-or-later

import CoreGraphics
import EventKit
import Foundation

public enum CalendarAuthStatus: String, Sendable, Equatable {
    case notDetermined, writeOnly, fullAccess, denied, restricted
}

public struct CalendarEventItem: Identifiable, Sendable, Equatable {
    public var id: String
    public var title: String
    public var startDate: Date
    public var endDate: Date
    public var isAllDay: Bool
    public var calendarColorHex: String
    public var location: String?
    public var meetingURL: URL?

    public init(
        id: String,
        title: String,
        startDate: Date,
        endDate: Date,
        isAllDay: Bool = false,
        calendarColorHex: String = "#0A84FF",
        location: String? = nil,
        meetingURL: URL? = nil
    ) {
        self.id = id
        self.title = title
        self.startDate = startDate
        self.endDate = endDate
        self.isAllDay = isAllDay
        self.calendarColorHex = calendarColorHex
        self.location = location
        self.meetingURL = meetingURL
    }
}

public struct DetectedMessageDate: Sendable, Equatable {
    public var range: Range<String.Index>
    public var matchedText: String
    public var startDate: Date
    public var durationSeconds: TimeInterval

    public init(
        range: Range<String.Index>,
        matchedText: String,
        startDate: Date,
        durationSeconds: TimeInterval = 3600
    ) {
        self.range = range
        self.matchedText = matchedText
        self.startDate = startDate
        self.durationSeconds = durationSeconds
    }
}

public enum CalendarBridgeError: LocalizedError, Equatable, Sendable {
    case accessDenied
    case noDefaultCalendar

    public var errorDescription: String? {
        switch self {
        case .accessDenied:
            String(localized: "Calendar access is turned off in System Settings.")
        case .noDefaultCalendar:
            String(localized: "No writable calendar is available in Calendar.")
        }
    }
}

public protocol CalendarStoreProtocol: Sendable {
    func authorizationStatus() -> CalendarAuthStatus
    func requestFullAccess() async -> Bool
    func events(forDay day: Date) async -> [CalendarEventItem]
    func createEvent(title: String, startDate: Date, endDate: Date, notes: String?) async throws -> CalendarEventItem
}

/// On-demand bridge to macOS `EventKit` (`EKEventStore`) and `NSDataDetector` date/meeting extraction.
///
/// Calendar access is requested only when the user opens the Calendar pane (`⌘⌥K`) or clicks a detected date
/// in a message, never at launch. If denied or restricted, it never prompts again. Calendar data stays strictly
/// on this Mac and is never logged or sent to the Courier engine.
@MainActor
public final class CalendarBridge: ObservableObject {
    @Published public private(set) var status: CalendarAuthStatus
    @Published public private(set) var selectedDay: Date
    @Published public private(set) var events: [CalendarEventItem] = []
    @Published public private(set) var lastError: String?

    private let store: CalendarStoreProtocol
    public let now: () -> Date
    private let calendar: Calendar

    nonisolated private static let allowedMeetingHosts: [String] = [
        "meet.google.com",
        "zoom.us",
        "teams.microsoft.com",
        "webex.com",
    ]

    private nonisolated static let linkDetector = try? NSDataDetector(
        types: NSTextCheckingResult.CheckingType.link.rawValue
    )
    private nonisolated static let dateDetector = try? NSDataDetector(
        types: NSTextCheckingResult.CheckingType.date.rawValue
    )

    public init(
        store: CalendarStoreProtocol = SystemCalendarStore(),
        now: @escaping () -> Date = Date.init,
        calendar: Calendar = .current
    ) {
        self.store = store
        self.now = now
        self.calendar = calendar
        self.status = store.authorizationStatus()
        self.selectedDay = now()
    }

    public var isAccessDenied: Bool {
        status == .denied || status == .restricted
    }

    public var isWriteOnly: Bool {
        status == .writeOnly
    }

    /// Checks whether a URL is an `https://` video-call link on one of the allowed hosts or their subdomains
    /// (`meet.google.com`, `zoom.us`, `teams.microsoft.com`, `webex.com`). Rejects lookalike domains such as
    /// `zoom.us.evil.com` or `notzoom.us`.
    nonisolated public static func isAllowedMeetingURL(_ url: URL) -> Bool {
        guard url.scheme?.lowercased() == "https" else { return false }
        var host = (url.host ?? "").lowercased()
        while host.hasSuffix(".") {
            host.removeLast()
        }
        guard !host.isEmpty else { return false }
        for allowed in allowedMeetingHosts {
            if host == allowed || host.hasSuffix("." + allowed) {
                return true
            }
        }
        return false
    }

    /// Extracts the first allowed `https://` video-meeting URL (`meet.google.com`, `zoom.us`,
    /// `teams.microsoft.com`, `webex.com` or their subdomains) from `text`.
    nonisolated public static func extractMeetingURL(from text: String) -> URL? {
        guard !text.isEmpty, let detector = linkDetector else { return nil }
        let whole = NSRange(text.startIndex..., in: text)
        for match in detector.matches(in: text, options: [], range: whole) {
            if let url = match.url, isAllowedMeetingURL(url) {
                return url
            }
        }
        return nil
    }

    /// Detects future dates/times in `text` relative to `referenceDate` using `NSDataDetector`,
    /// excluding any match inside links, markdown code spans, or `excludedRanges`.
    /// Defaults `durationSeconds` to `3600` when the detector returns `0`.
    nonisolated public static func detectDates(
        in text: String,
        referenceDate: Date,
        excludedRanges: [Range<String.Index>] = []
    ) -> [DetectedMessageDate] {
        guard !text.isEmpty, let detector = dateDetector else { return [] }
        let whole = NSRange(text.startIndex..., in: text)

        var forbidden = excludedRanges
        if let linkDetector {
            for linkMatch in linkDetector.matches(in: text, options: [], range: whole) {
                if let r = Range(linkMatch.range, in: text) {
                    forbidden.append(r)
                }
            }
        }
        forbidden.append(contentsOf: inlineBacktickCodeRanges(in: text))

        var results: [DetectedMessageDate] = []
        for match in detector.matches(in: text, options: [], range: whole) {
            guard match.resultType == .date,
                  let rawDate = match.date,
                  let range = Range(match.range, in: text)
            else { continue }

            // Never underline inside code spans, links, or excluded ranges.
            if forbidden.contains(where: { $0.overlaps(range) }) {
                continue
            }

            let matchedText = String(text[range])
            let resolvedStart = resolveStartDate(
                rawDate: rawDate,
                matchedText: matchedText,
                referenceDate: referenceDate
            )

            // Only underline dates strictly in the future relative to referenceDate.
            guard resolvedStart > referenceDate else { continue }

            let duration = match.duration > 0 ? match.duration : 3600
            results.append(
                DetectedMessageDate(
                    range: range,
                    matchedText: matchedText,
                    startDate: resolvedStart,
                    durationSeconds: duration
                )
            )
        }
        return results
    }

    /// Detects future dates/times in a `RichText` value, excluding `.code`, `.pre`, `.link`, `.mention`, and `.spoiler` entities.
    nonisolated public static func detectDates(
        in rich: RichText,
        referenceDate: Date
    ) -> [DetectedMessageDate] {
        let nsText = rich.text as NSString
        var excluded: [Range<String.Index>] = []
        for entity in rich.entities {
            switch entity.kind {
            case .code, .pre, .link, .mention, .spoiler:
                let nsRange = NSRange(location: entity.offset, length: entity.length)
                if nsRange.location >= 0,
                   nsRange.location + nsRange.length <= nsText.length,
                   let range = Range(nsRange, in: rich.text) {
                    excluded.append(range)
                }
            default:
                break
            }
        }
        return detectDates(in: rich.text, referenceDate: referenceDate, excludedRanges: excluded)
    }

    /// Encodes a `DetectedMessageDate` as an internal URL (`courier-calendar://add?...`) for `AttributedString.link`.
    nonisolated public static func dateActionURL(for detected: DetectedMessageDate) -> URL? {
        var components = URLComponents()
        components.scheme = "courier-calendar"
        components.host = "add"
        components.queryItems = [
            URLQueryItem(name: "start", value: String(detected.startDate.timeIntervalSince1970)),
            URLQueryItem(name: "duration", value: String(detected.durationSeconds)),
            URLQueryItem(name: "text", value: detected.matchedText),
        ]
        return components.url
    }

    /// Decodes a `courier-calendar://add` URL back into a `DetectedMessageDate`.
    nonisolated public static func detectedDate(from url: URL) -> DetectedMessageDate? {
        guard url.scheme == "courier-calendar",
              url.host == "add",
              let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
              let items = components.queryItems
        else { return nil }
        var startSeconds: Double?
        var durationSeconds: Double = 3600
        var matchedText = ""
        for item in items {
            switch item.name {
            case "start":
                if let val = item.value, let parsed = Double(val) {
                    startSeconds = parsed
                }
            case "duration":
                if let val = item.value, let parsed = Double(val), parsed > 0 {
                    durationSeconds = parsed
                }
            case "text":
                matchedText = item.value ?? ""
            default:
                break
            }
        }
        guard let startSeconds else { return nil }
        return DetectedMessageDate(
            range: matchedText.startIndex ..< matchedText.endIndex,
            matchedText: matchedText,
            startDate: Date(timeIntervalSince1970: startSeconds),
            durationSeconds: durationSeconds
        )
    }

    // MARK: - On-Demand Authorization & Agenda Loading

    /// Requests Calendar access on demand if `.notDetermined` or `.writeOnly`, or immediately loads events for `selectedDay`
    /// if `.fullAccess`. Never prompts if `.denied` or `.restricted`.
    public func loadSelectedDay() async {
        guard AppLockGate.shared.canPerform(.other) else { return }
        lastError = nil
        status = store.authorizationStatus()
        switch status {
        case .notDetermined, .writeOnly:
            let previous = status
            let granted = await store.requestFullAccess()
            let updated = store.authorizationStatus()
            if updated == .notDetermined || updated == .writeOnly {
                status = granted ? .fullAccess : (previous == .writeOnly ? .writeOnly : .denied)
            } else {
                status = updated
            }
            if status == .fullAccess {
                events = (await store.events(forDay: selectedDay)).sorted { $0.startDate < $1.startDate }
            } else {
                events = []
            }
        case .fullAccess:
            events = (await store.events(forDay: selectedDay)).sorted { $0.startDate < $1.startDate }
        case .denied, .restricted:
            events = []
        }
    }

    public func selectPreviousDay() async {
        guard AppLockGate.shared.canPerform(.other) else { return }
        if let prev = calendar.date(byAdding: .day, value: -1, to: selectedDay) {
            selectedDay = prev
        }
        await loadSelectedDay()
    }

    public func selectToday() async {
        guard AppLockGate.shared.canPerform(.other) else { return }
        selectedDay = now()
        await loadSelectedDay()
    }

    public func selectNextDay() async {
        guard AppLockGate.shared.canPerform(.other) else { return }
        if let next = calendar.date(byAdding: .day, value: 1, to: selectedDay) {
            selectedDay = next
        }
        await loadSelectedDay()
    }

    public func selectDay(_ day: Date) async {
        guard AppLockGate.shared.canPerform(.other) else { return }
        selectedDay = day
        await loadSelectedDay()
    }

    /// Creates a calendar event on demand when the user clicks **Add to Calendar** in `AddCalendarEventPopover`.
    @discardableResult
    public func addEvent(
        title: String,
        startDate: Date,
        endDate: Date,
        notes: String? = nil
    ) async throws -> CalendarEventItem {
        try AppLockGate.shared.ensureUnlocked(.other)
        lastError = nil
        status = store.authorizationStatus()
        if status == .notDetermined || status == .writeOnly {
            let previous = status
            let granted = await store.requestFullAccess()
            let updated = store.authorizationStatus()
            if updated == .notDetermined || updated == .writeOnly {
                status = granted ? .fullAccess : (previous == .writeOnly ? .writeOnly : .denied)
            } else {
                status = updated
            }
        }
        guard status == .fullAccess else {
            throw CalendarBridgeError.accessDenied
        }
        do {
            let created = try await store.createEvent(
                title: title,
                startDate: startDate,
                endDate: endDate,
                notes: notes
            )
            if calendar.isDate(startDate, inSameDayAs: selectedDay) {
                events = (await store.events(forDay: selectedDay)).sorted { $0.startDate < $1.startDate }
            }
            return created
        } catch {
            lastError = error.localizedDescription
            throw error
        }
    }

    // MARK: - Private Helpers

    /// Finds markdown backtick code spans (e.g. `` `code` `` or ```` ```code``` ````) in `text`.
    nonisolated private static func inlineBacktickCodeRanges(in text: String) -> [Range<String.Index>] {
        var ranges: [Range<String.Index>] = []
        var index = text.startIndex
        while index < text.endIndex {
            if text[index] == "`" {
                let tickStart = index
                var tickEnd = index
                while tickEnd < text.endIndex && text[tickEnd] == "`" {
                    tickEnd = text.index(after: tickEnd)
                }
                let fence = String(text[tickStart ..< tickEnd])
                if let closing = text.range(of: fence, range: tickEnd ..< text.endIndex) {
                    ranges.append(tickStart ..< closing.upperBound)
                    index = closing.upperBound
                    continue
                }
            }
            index = text.index(after: index)
        }
        return ranges
    }

    /// Anchors relative day words (`today`, `tonight`, `tomorrow`, `yesterday`) to `referenceDate`
    /// while keeping absolute dates untouched, so tests and snapshots with injected clocks are deterministic.
    nonisolated private static func resolveStartDate(
        rawDate: Date,
        matchedText: String,
        referenceDate: Date
    ) -> Date {
        let lower = matchedText.lowercased()
        let words = lower.split { !$0.isLetter }
        let hasExplicitFourDigitYear = matchedText.range(
            of: #"\b\d{4}\b"#,
            options: .regularExpression
        ) != nil
        guard !hasExplicitFourDigitYear else { return rawDate }

        let relativeDayDelta: Int?
        if words.contains("tomorrow") {
            relativeDayDelta = 1
        } else if words.contains("yesterday") {
            relativeDayDelta = -1
        } else if words.contains("today") || words.contains("tonight") {
            relativeDayDelta = 0
        } else {
            relativeDayDelta = nil
        }

        guard let dayDelta = relativeDayDelta else { return rawDate }
        let cal = Calendar.current
        let timeComponents = cal.dateComponents([.hour, .minute, .second], from: rawDate)
        let baseDay = cal.startOfDay(for: referenceDate)
        guard let targetDay = cal.date(byAdding: .day, value: dayDelta, to: baseDay),
              let combined = cal.date(
                  bySettingHour: timeComponents.hour ?? 9,
                  minute: timeComponents.minute ?? 0,
                  second: timeComponents.second ?? 0,
                  of: targetDay
              )
        else {
            return rawDate
        }
        return combined
    }
}

/// Production `CalendarStoreProtocol` backed by macOS 14 `EKEventStore`.
/// `EKEventStore` is created eagerly in `init` so detached tasks never race on a lazy property.
public final class SystemCalendarStore: CalendarStoreProtocol, @unchecked Sendable {
    private let eventStore: EKEventStore

    public init() {
        self.eventStore = EKEventStore()
    }

    public func authorizationStatus() -> CalendarAuthStatus {
        switch EKEventStore.authorizationStatus(for: .event) {
        case .notDetermined:
            return .notDetermined
        case .fullAccess:
            return .fullAccess
        case .writeOnly:
            return .writeOnly
        case .denied:
            return .denied
        case .restricted:
            return .restricted
        @unknown default:
            return .denied
        }
    }

    public func requestFullAccess() async -> Bool {
        (try? await eventStore.requestFullAccessToEvents()) ?? false
    }

    public func events(forDay day: Date) async -> [CalendarEventItem] {
        guard authorizationStatus() == .fullAccess else { return [] }
        return await Task.detached { [self] in
            let cal = Calendar.current
            let startOfDay = cal.startOfDay(for: day)
            guard let endOfDay = cal.date(byAdding: .day, value: 1, to: startOfDay) else { return [] }
            let predicate = self.eventStore.predicateForEvents(withStart: startOfDay, end: endOfDay, calendars: nil)
            let ekEvents = self.eventStore.events(matching: predicate)
            return ekEvents.map { ev in
                let meeting = Self.resolveMeetingURL(for: ev)
                return CalendarEventItem(
                    id: ev.eventIdentifier ?? UUID().uuidString,
                    title: (ev.title ?? "").isEmpty ? String(localized: "Untitled Event") : ev.title,
                    startDate: ev.startDate,
                    endDate: ev.endDate,
                    isAllDay: ev.isAllDay,
                    calendarColorHex: Self.hexColor(from: ev.calendar?.cgColor),
                    location: ev.location,
                    meetingURL: meeting
                )
            }
            .sorted { $0.startDate < $1.startDate }
        }.value
    }

    public func createEvent(
        title: String,
        startDate: Date,
        endDate: Date,
        notes: String?
    ) async throws -> CalendarEventItem {
        guard authorizationStatus() == .fullAccess else {
            throw CalendarBridgeError.accessDenied
        }
        return try await Task.detached { [self] in
            guard let targetCalendar = self.eventStore.defaultCalendarForNewEvents
                ?? self.eventStore.calendars(for: .event).first(where: \.allowsContentModifications)
            else {
                throw CalendarBridgeError.noDefaultCalendar
            }
            let ev = EKEvent(eventStore: self.eventStore)
            ev.calendar = targetCalendar
            ev.title = title.trimmingCharacters(in: .whitespacesAndNewlines)
            ev.startDate = startDate
            ev.endDate = endDate > startDate ? endDate : startDate.addingTimeInterval(3600)
            ev.notes = notes
            try self.eventStore.save(ev, span: .thisEvent)

            return CalendarEventItem(
                id: ev.eventIdentifier ?? UUID().uuidString,
                title: ev.title,
                startDate: ev.startDate,
                endDate: ev.endDate,
                isAllDay: ev.isAllDay,
                calendarColorHex: Self.hexColor(from: targetCalendar.cgColor),
                location: ev.location,
                meetingURL: Self.resolveMeetingURL(for: ev)
            )
        }.value
    }

    private static func resolveMeetingURL(for event: EKEvent) -> URL? {
        if let url = event.url, CalendarBridge.isAllowedMeetingURL(url) {
            return url
        }
        if let location = event.location, let url = CalendarBridge.extractMeetingURL(from: location) {
            return url
        }
        if let notes = event.notes, let url = CalendarBridge.extractMeetingURL(from: notes) {
            return url
        }
        return nil
    }

    private static func hexColor(from cgColor: CGColor?) -> String {
        guard let cgColor,
              let srgb = CGColorSpace(name: CGColorSpace.sRGB),
              let converted = cgColor.converted(to: srgb, intent: .defaultIntent, options: nil),
              let components = converted.components,
              components.count >= 3
        else {
            return "#0A84FF"
        }
        let r = Int(max(0, min(255, round(components[0] * 255))))
        let g = Int(max(0, min(255, round(components[1] * 255))))
        let b = Int(max(0, min(255, round(components[2] * 255))))
        return String(format: "#%02X%02X%02X", r, g, b)
    }
}

/// In-memory `CalendarStoreProtocol` for unit and snapshot tests. Never touches macOS `EKEventStore`.
public final class FakeCalendarStore: CalendarStoreProtocol, @unchecked Sendable {
    private let lock = NSLock()
    private var _status: CalendarAuthStatus
    private let _requestGrantResult: Bool
    private var _events: [CalendarEventItem]
    private var _requestAccessCalls = 0

    public init(
        status: CalendarAuthStatus = .fullAccess,
        requestGrantResult: Bool = true,
        events: [CalendarEventItem] = []
    ) {
        self._status = status
        self._requestGrantResult = requestGrantResult
        self._events = events
    }

    public var requestAccessCalls: Int {
        lock.withLock { _requestAccessCalls }
    }

    public var storedEvents: [CalendarEventItem] {
        lock.withLock { _events }
    }

    public func authorizationStatus() -> CalendarAuthStatus {
        lock.withLock { _status }
    }

    public func requestFullAccess() async -> Bool {
        lock.withLock {
            _requestAccessCalls += 1
            _status = _requestGrantResult ? .fullAccess : .denied
            return _requestGrantResult
        }
    }

    public func events(forDay day: Date) async -> [CalendarEventItem] {
        let snapshot = lock.withLock { (_status, _events) }
        guard snapshot.0 == .fullAccess else { return [] }
        let cal = Calendar.current
        return snapshot.1.filter { event in
            cal.isDate(event.startDate, inSameDayAs: day) || cal.isDate(event.endDate, inSameDayAs: day)
        }
    }

    public func createEvent(
        title: String,
        startDate: Date,
        endDate: Date,
        notes: String?
    ) async throws -> CalendarEventItem {
        try lock.withLock {
            guard _status == .fullAccess else {
                throw CalendarBridgeError.accessDenied
            }
            let cleanTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
            let meeting = notes.flatMap(CalendarBridge.extractMeetingURL(from:))
                ?? CalendarBridge.extractMeetingURL(from: cleanTitle)
            let created = CalendarEventItem(
                id: "fake-cal-event-\(_events.count + 1)",
                title: cleanTitle.isEmpty ? "Untitled Event" : cleanTitle,
                startDate: startDate,
                endDate: endDate > startDate ? endDate : startDate.addingTimeInterval(3600),
                isAllDay: false,
                calendarColorHex: "#0A84FF",
                location: nil,
                meetingURL: meeting
            )
            _events.append(created)
            return created
        }
    }
}
