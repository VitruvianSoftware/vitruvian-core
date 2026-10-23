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
// Wave C of the Orca feature set: putting idle sessions to sleep, recurring
// agent tasks, multi-agent orchestration runs driven over a JSON control
// protocol, and the SSH / mobile companion bridge. Everything here is plain
// state and pure rules; the app wires it to processes and windows.

import Combine
import Foundation

// MARK: - Agent hibernation

/// What the hibernation rules need to know about one open session.
public struct NexusAgentHibernationCandidate: Equatable, Sendable {
    public var sessionID: String
    public var providerRoute: NexusAgentProviderRoute
    /// The agent finished its last turn and is not producing output.
    public var isTurnDone: Bool
    /// The session is the one the user is looking at.
    public var isForeground: Bool
    /// Seconds since anything happened in the session.
    public var idleSeconds: TimeInterval
    /// The agent is waiting on the user to approve or deny something.
    public var hasPendingApproval: Bool
    /// Subagents the session started that are still running.
    public var activeSubagentCount: Int
    /// An orchestration run handed this session work it has not reported back on.
    public var hasUnsettledOrchestrationDispatch: Bool
    /// The mobile companion is driving the session right now.
    public var isDrivenByMobile: Bool
    /// Where the transcript was scrolled to, so waking puts it back.
    public var scrollOffsetY: Double

    public init(sessionID: String,
                providerRoute: NexusAgentProviderRoute,
                isTurnDone: Bool,
                isForeground: Bool,
                idleSeconds: TimeInterval,
                hasPendingApproval: Bool = false,
                activeSubagentCount: Int = 0,
                hasUnsettledOrchestrationDispatch: Bool = false,
                isDrivenByMobile: Bool = false,
                scrollOffsetY: Double = 0) {
        self.sessionID = sessionID
        self.providerRoute = providerRoute
        self.isTurnDone = isTurnDone
        self.isForeground = isForeground
        self.idleSeconds = idleSeconds
        self.hasPendingApproval = hasPendingApproval
        self.activeSubagentCount = activeSubagentCount
        self.hasUnsettledOrchestrationDispatch = hasUnsettledOrchestrationDispatch
        self.isDrivenByMobile = isDrivenByMobile
        self.scrollOffsetY = scrollOffsetY
    }
}

/// The eight safety checks a session must pass before it may be put to
/// sleep. Failing any one keeps it awake: hibernating it would lose work or
/// strand someone waiting on it.
public struct NexusAgentHibernationEvaluator: Equatable, Sendable {
    public enum Check: String, CaseIterable, Sendable {
        case turnDone
        case notForeground
        case idleLongEnough
        case providerResumes
        case noPendingApproval
        case noActiveSubagents
        case noUnsettledDispatch
        case notDrivenByMobile
    }

    /// How long a session must sit idle first. Thirty minutes by default.
    public var idleThreshold: TimeInterval

    public init(idleThreshold: TimeInterval = 1800) {
        self.idleThreshold = idleThreshold
    }

    /// Whether a provider can pick a conversation back up by its id. A
    /// session whose provider cannot would come back empty, so it is never
    /// put to sleep. Claude Code (and Ollama, which runs it) resume with
    /// `--resume`, OpenCode with `--session`, agy by conversation id; a
    /// command of the user's own has no such thing.
    public static func supportsSessionResume(_ route: NexusAgentProviderRoute) -> Bool {
        switch route {
        case .claude, .ollama, .opencode, .antigravity: return true
        case .custom: return false
        }
    }

    /// The checks `candidate` fails, in the order they are listed.
    public func failedChecks(_ candidate: NexusAgentHibernationCandidate) -> [Check] {
        Check.allCases.filter { !passes($0, candidate) }
    }

    public func canHibernate(_ candidate: NexusAgentHibernationCandidate) -> Bool {
        failedChecks(candidate).isEmpty
    }

    public func passes(_ check: Check, _ candidate: NexusAgentHibernationCandidate) -> Bool {
        switch check {
        case .turnDone: return candidate.isTurnDone
        case .notForeground: return !candidate.isForeground
        case .idleLongEnough: return candidate.idleSeconds >= idleThreshold
        case .providerResumes: return Self.supportsSessionResume(candidate.providerRoute)
        case .noPendingApproval: return !candidate.hasPendingApproval
        case .noActiveSubagents: return candidate.activeSubagentCount == 0
        case .noUnsettledDispatch: return !candidate.hasUnsettledOrchestrationDispatch
        case .notDrivenByMobile: return !candidate.isDrivenByMobile
        }
    }
}

/// What is kept of a session while it sleeps: enough to resume the
/// provider's conversation and put the view back where it was.
public struct NexusAgentHibernatedSessionRecord: Identifiable, Equatable, Sendable, Codable {
    public var sessionID: String
    public var providerID: UUID
    public var workingDirectory: String
    public var scrollOffsetY: Double
    public var hibernatedAt: Date

    public var id: String { sessionID }

    public init(sessionID: String, providerID: UUID, workingDirectory: String,
                scrollOffsetY: Double, hibernatedAt: Date) {
        self.sessionID = sessionID
        self.providerID = providerID
        self.workingDirectory = workingDirectory
        self.scrollOffsetY = scrollOffsetY
        self.hibernatedAt = hibernatedAt
    }
}

/// Keeps the list of sleeping sessions. The app asks it to hibernate a
/// session when it goes idle and to restore one when the user focuses it.
@MainActor
public final class NexusAgentHibernationManager: ObservableObject {
    @Published public private(set) var hibernated: [NexusAgentHibernatedSessionRecord] = []
    public var evaluator: NexusAgentHibernationEvaluator
    private let now: () -> Date

    public init(evaluator: NexusAgentHibernationEvaluator = NexusAgentHibernationEvaluator(),
                now: @escaping () -> Date = Date.init) {
        self.evaluator = evaluator
        self.now = now
    }

    public func isHibernated(_ sessionID: String) -> Bool {
        hibernated.contains { $0.sessionID == sessionID }
    }

    /// Puts the session to sleep if it passes every check. Returns the
    /// record kept for it, or nil when it stays awake.
    @discardableResult
    public func hibernateIfEligible(_ candidate: NexusAgentHibernationCandidate,
                                    providerID: UUID,
                                    workingDirectory: String) -> NexusAgentHibernatedSessionRecord? {
        guard evaluator.canHibernate(candidate) else { return nil }
        let record = NexusAgentHibernatedSessionRecord(sessionID: candidate.sessionID,
                                                       providerID: providerID,
                                                       workingDirectory: workingDirectory,
                                                       scrollOffsetY: candidate.scrollOffsetY,
                                                       hibernatedAt: now())
        hibernated.removeAll { $0.sessionID == candidate.sessionID }
        hibernated.append(record)
        return record
    }

    /// Wakes the session: forgets it here and returns what the app needs to
    /// resume it. Nil when it was not asleep.
    @discardableResult
    public func restore(sessionID: String) -> NexusAgentHibernatedSessionRecord? {
        guard let index = hibernated.firstIndex(where: { $0.sessionID == sessionID }) else { return nil }
        return hibernated.remove(at: index)
    }
}

// MARK: - Scheduled automations

/// A parsed five-field cron expression: minute, hour, day of month, month,
/// day of week. Fields take `*`, numbers, lists (`1,15`), ranges (`1-5`) and
/// steps (`*/15`, `0-30/10`). Day of week runs 0-7 with both 0 and 7 Sunday.
/// As in cron, when both day fields are restricted a day matching either runs.
public struct NexusAgentCronExpression: Equatable, Sendable {
    public var minutes: Set<Int>
    public var hours: Set<Int>
    public var daysOfMonth: Set<Int>
    public var months: Set<Int>
    public var daysOfWeek: Set<Int>
    public var isDayOfMonthRestricted: Bool
    public var isDayOfWeekRestricted: Bool

    public init?(_ text: String) {
        let fields = text.split(whereSeparator: { $0 == " " || $0 == "\t" }).map(String.init)
        guard fields.count == 5,
              let minutes = Self.parse(fields[0], range: 0...59),
              let hours = Self.parse(fields[1], range: 0...23),
              let days = Self.parse(fields[2], range: 1...31),
              let months = Self.parse(fields[3], range: 1...12),
              let weekdays = Self.parse(fields[4], range: 0...7) else { return nil }
        self.minutes = minutes
        self.hours = hours
        self.daysOfMonth = days
        self.months = months
        self.daysOfWeek = Set(weekdays.map { $0 == 7 ? 0 : $0 })
        self.isDayOfMonthRestricted = fields[2] != "*"
        self.isDayOfWeekRestricted = fields[4] != "*"
    }

    static func parse(_ field: String, range: ClosedRange<Int>) -> Set<Int>? {
        var values = Set<Int>()
        for part in field.split(separator: ",", omittingEmptySubsequences: false) {
            let pieces = part.split(separator: "/", omittingEmptySubsequences: false)
            guard pieces.count == 1 || pieces.count == 2 else { return nil }
            var step = 1
            if pieces.count == 2 {
                guard let parsed = Int(pieces[1]), parsed > 0 else { return nil }
                step = parsed
            }
            let base = pieces[0]
            let lower: Int
            let upper: Int
            if base == "*" {
                lower = range.lowerBound
                upper = range.upperBound
            } else if base.contains("-") {
                let bounds = base.split(separator: "-", omittingEmptySubsequences: false)
                guard bounds.count == 2, let low = Int(bounds[0]), let high = Int(bounds[1]), low <= high else {
                    return nil
                }
                lower = low
                upper = high
            } else {
                guard let single = Int(base) else { return nil }
                lower = single
                upper = pieces.count == 2 ? range.upperBound : single
            }
            guard range.contains(lower), range.contains(upper) else { return nil }
            values.formUnion(stride(from: lower, through: upper, by: step))
        }
        return values.isEmpty ? nil : values
    }

    /// The first whole minute strictly after `date` that matches, looking
    /// no further than five years ahead (an expression like `0 0 30 2 *`
    /// never matches).
    public func nextDate(after date: Date, calendar: Calendar) -> Date? {
        var parts = calendar.dateComponents([.era, .year, .month, .day, .hour, .minute], from: date)
        parts.second = 0
        guard let truncated = calendar.date(from: parts),
              var candidate = calendar.date(byAdding: .minute, value: 1, to: truncated),
              let limit = calendar.date(byAdding: .year, value: 5, to: date) else { return nil }
        while candidate <= limit {
            let fields = calendar.dateComponents([.month, .day, .hour, .minute, .weekday], from: candidate)
            guard let month = fields.month, let day = fields.day, let hour = fields.hour,
                  let minute = fields.minute, let weekday = fields.weekday else { return nil }
            if !months.contains(month) {
                guard let next = calendar.dateInterval(of: .month, for: candidate)?.end else { return nil }
                candidate = next
                continue
            }
            if !dayMatches(day: day, weekday: weekday - 1) {
                guard let next = calendar.dateInterval(of: .day, for: candidate)?.end else { return nil }
                candidate = next
                continue
            }
            if !hours.contains(hour) {
                guard let next = calendar.dateInterval(of: .hour, for: candidate)?.end else { return nil }
                candidate = next
                continue
            }
            if !minutes.contains(minute) {
                guard let next = calendar.date(byAdding: .minute, value: 1, to: candidate) else { return nil }
                candidate = next
                continue
            }
            return candidate
        }
        return nil
    }

    private func dayMatches(day: Int, weekday: Int) -> Bool {
        switch (isDayOfMonthRestricted, isDayOfWeekRestricted) {
        case (true, true): return daysOfMonth.contains(day) || daysOfWeek.contains(weekday)
        case (true, false): return daysOfMonth.contains(day)
        case (false, true): return daysOfWeek.contains(weekday)
        case (false, false): return true
        }
    }
}

/// When a scheduled task runs. Saved as one line of text: `@hourly`,
/// `@daily`, `@weekdays9am`, `@every 30m`, or a five-field cron expression.
public enum NexusAgentAutomationSchedule: Equatable, Sendable, Codable {
    /// At the top of every hour.
    case hourly
    /// Every day at midnight.
    case daily
    /// Monday to Friday at 9:00.
    case weekdays9am
    /// Every this many minutes after the last run.
    case intervalMinutes(Int)
    /// A five-field cron expression.
    case cron(String)

    public init?(text: String) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        switch trimmed {
        case "@hourly": self = .hourly
        case "@daily", "@midnight": self = .daily
        case "@weekdays9am": self = .weekdays9am
        default:
            if trimmed.hasPrefix("@every ") {
                var amount = trimmed.dropFirst("@every ".count).trimmingCharacters(in: .whitespaces)
                if amount.hasSuffix("m") { amount.removeLast() }
                guard let minutes = Int(amount), minutes > 0 else { return nil }
                self = .intervalMinutes(minutes)
            } else if NexusAgentCronExpression(trimmed) != nil {
                self = .cron(trimmed)
            } else {
                return nil
            }
        }
    }

    public var text: String {
        switch self {
        case .hourly: return "@hourly"
        case .daily: return "@daily"
        case .weekdays9am: return "@weekdays9am"
        case .intervalMinutes(let minutes): return "@every \(minutes)m"
        case .cron(let expression): return expression
        }
    }

    /// The schedule as a short badge.
    public var displayName: String {
        switch self {
        case .hourly: return "Hourly"
        case .daily: return "Daily"
        case .weekdays9am: return "Weekdays 9:00"
        case .intervalMinutes(let minutes): return "Every \(minutes) min"
        case .cron(let expression): return "Cron \(expression)"
        }
    }

    /// The cron expression the schedule stands for; nil for an interval.
    public var cronExpression: String? {
        switch self {
        case .hourly: return "0 * * * *"
        case .daily: return "0 0 * * *"
        case .weekdays9am: return "0 9 * * 1-5"
        case .intervalMinutes: return nil
        case .cron(let expression): return expression
        }
    }

    /// When the schedule next fires after `date`; nil if it never does.
    public func nextFireDate(after date: Date, calendar: Calendar = .current) -> Date? {
        if case .intervalMinutes(let minutes) = self {
            guard minutes > 0 else { return nil }
            return date.addingTimeInterval(TimeInterval(minutes) * 60)
        }
        guard let text = cronExpression, let expression = NexusAgentCronExpression(text) else { return nil }
        return expression.nextDate(after: date, calendar: calendar)
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        let text = try container.decode(String.self)
        guard let schedule = NexusAgentAutomationSchedule(text: text) else {
            throw DecodingError.dataCorruptedError(in: container, debugDescription: "unknown schedule \(text)")
        }
        self = schedule
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(text)
    }
}

/// A prompt the app sends to an agent on a schedule.
public struct NexusAgentScheduledTask: Identifiable, Equatable, Sendable, Codable {
    public var id: UUID
    public var name: String
    public var prompt: String
    public var workingDirectory: String
    public var providerID: UUID
    public var model: String
    public var useWorktree: Bool
    public var schedule: NexusAgentAutomationSchedule
    public var isEnabled: Bool
    public var lastRunAt: Date?
    public var lastRunSucceeded: Bool?

    public init(id: UUID = UUID(), name: String, prompt: String, workingDirectory: String,
                providerID: UUID, model: String = "", useWorktree: Bool = false,
                schedule: NexusAgentAutomationSchedule, isEnabled: Bool = true,
                lastRunAt: Date? = nil, lastRunSucceeded: Bool? = nil) {
        self.id = id
        self.name = name
        self.prompt = prompt
        self.workingDirectory = workingDirectory
        self.providerID = providerID
        self.model = model
        self.useWorktree = useWorktree
        self.schedule = schedule
        self.isEnabled = isEnabled
        self.lastRunAt = lastRunAt
        self.lastRunSucceeded = lastRunSucceeded
    }

    /// When the task should next run. A task that has never run counts
    /// from the minute before `now`, so a schedule firing this minute is due;
    /// an interval task that has never run is due at once.
    public func nextRunDate(now: Date, calendar: Calendar = .current) -> Date? {
        if let lastRunAt { return schedule.nextFireDate(after: lastRunAt, calendar: calendar) }
        if case .intervalMinutes = schedule { return now }
        return schedule.nextFireDate(after: now.addingTimeInterval(-60), calendar: calendar)
    }
}

/// Keeps the scheduled tasks, saved as JSON in the app's state folder.
@MainActor
public final class NexusAgentAutomationManager: ObservableObject {
    @Published public private(set) var tasks: [NexusAgentScheduledTask] = []
    /// What went wrong reading or writing the saved file, if anything.
    @Published public private(set) var lastError: String?
    public let stateDirectory: URL
    public var calendar: Calendar

    public static let fileName = "scheduled-tasks.json"

    public var fileURL: URL { stateDirectory.appendingPathComponent(Self.fileName) }

    public init(stateDirectory: URL, calendar: Calendar = .current) {
        self.stateDirectory = stateDirectory
        self.calendar = calendar
        load()
    }

    public func load() {
        guard let data = try? Data(contentsOf: fileURL) else {
            tasks = []
            return
        }
        do {
            tasks = try JSONDecoder().decode([NexusAgentScheduledTask].self, from: data)
            lastError = nil
        } catch {
            tasks = []
            lastError = "Could not read \(Self.fileName): \(error.localizedDescription)"
        }
    }

    public func save() {
        do {
            try FileManager.default.createDirectory(at: stateDirectory, withIntermediateDirectories: true)
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            try encoder.encode(tasks).write(to: fileURL, options: .atomic)
            lastError = nil
        } catch {
            lastError = "Could not save \(Self.fileName): \(error.localizedDescription)"
        }
    }

    /// Adds the task, or replaces the one with its id.
    public func upsert(_ task: NexusAgentScheduledTask) {
        if let index = tasks.firstIndex(where: { $0.id == task.id }) {
            tasks[index] = task
        } else {
            tasks.append(task)
        }
        save()
    }

    public func remove(id: UUID) {
        tasks.removeAll { $0.id == id }
        save()
    }

    public func setEnabled(_ enabled: Bool, id: UUID) {
        guard let index = tasks.firstIndex(where: { $0.id == id }) else { return }
        tasks[index].isEnabled = enabled
        save()
    }

    /// The enabled tasks whose next run is at or before `now`.
    public func dueTasks(at now: Date) -> [NexusAgentScheduledTask] {
        tasks.filter { task in
            guard task.isEnabled, let next = task.nextRunDate(now: now, calendar: calendar) else { return false }
            return next <= now
        }
    }

    public func markExecuted(id: UUID, at date: Date, succeeded: Bool) {
        guard let index = tasks.firstIndex(where: { $0.id == id }) else { return }
        tasks[index].lastRunAt = date
        tasks[index].lastRunSucceeded = succeeded
        save()
    }

    /// The launchd label a task's LaunchAgent is saved under.
    public nonisolated static func launchdLabel(for task: NexusAgentScheduledTask) -> String {
        "nexus-agent.automation.\(task.id.uuidString.lowercased())"
    }

    /// A LaunchAgent property list that runs `executablePath --run-automation
    /// <id>` on the task's schedule, so it runs even with the app closed.
    /// Cron schedules become `StartCalendarInterval` entries; an interval, or
    /// a cron expression that would need more than 256 entries, becomes
    /// `StartInterval` (the app then checks `dueTasks` itself on each wake).
    public func launchdPlistXML(for task: NexusAgentScheduledTask, executablePath: String) -> String {
        Self.plistXML(for: task, executablePath: executablePath)
    }

    public nonisolated static func plistXML(for task: NexusAgentScheduledTask, executablePath: String) -> String {
        var body = ""
        body += "\t<key>Label</key>\n\t<string>\(xmlEscape(launchdLabel(for: task)))</string>\n"
        body += "\t<key>ProgramArguments</key>\n\t<array>\n"
        for argument in [executablePath, "--run-automation", task.id.uuidString] {
            body += "\t\t<string>\(xmlEscape(argument))</string>\n"
        }
        body += "\t</array>\n"
        if !task.workingDirectory.isEmpty {
            body += "\t<key>WorkingDirectory</key>\n\t<string>\(xmlEscape(task.workingDirectory))</string>\n"
        }
        body += "\t<key>RunAtLoad</key>\n\t<false/>\n"
        if let entries = calendarIntervals(for: task.schedule) {
            body += "\t<key>StartCalendarInterval</key>\n"
            if entries.count == 1 {
                body += dictXML(entries[0], indent: "\t")
            } else {
                body += "\t<array>\n"
                for entry in entries { body += dictXML(entry, indent: "\t\t") }
                body += "\t</array>\n"
            }
        } else {
            let seconds: Int
            if case .intervalMinutes(let minutes) = task.schedule { seconds = max(1, minutes) * 60 } else { seconds = 60 }
            body += "\t<key>StartInterval</key>\n\t<integer>\(seconds)</integer>\n"
        }
        return """
        <?xml version="1.0" encoding="UTF-8"?>
        <!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
        <plist version="1.0">
        <dict>
        \(body)</dict>
        </plist>

        """
    }

    /// The `StartCalendarInterval` entries for a cron schedule, each a list
    /// of (key, value) pairs; nil for an interval or an expression too wide.
    nonisolated static func calendarIntervals(for schedule: NexusAgentAutomationSchedule) -> [[(String, Int)]]? {
        guard let text = schedule.cronExpression else { return nil }
        let fields = text.split(whereSeparator: { $0 == " " || $0 == "\t" }).map(String.init)
        guard fields.count == 5, let cron = NexusAgentCronExpression(text) else { return nil }
        // A day-of-month or-day-of-week schedule cannot be said as one
        // product of launchd keys.
        if cron.isDayOfMonthRestricted && cron.isDayOfWeekRestricted { return nil }
        let keyed: [(String, Set<Int>, Bool)] = [
            ("Minute", cron.minutes, fields[0] != "*"),
            ("Hour", cron.hours, fields[1] != "*"),
            ("Day", cron.daysOfMonth, fields[2] != "*"),
            ("Month", cron.months, fields[3] != "*"),
            ("Weekday", cron.daysOfWeek, fields[4] != "*"),
        ]
        var entries: [[(String, Int)]] = [[]]
        for (key, values, restricted) in keyed where restricted {
            entries = entries.flatMap { entry in values.sorted().map { entry + [(key, $0)] } }
            if entries.count > 256 { return nil }
        }
        return entries
    }

    private nonisolated static func dictXML(_ entry: [(String, Int)], indent: String) -> String {
        var xml = "\(indent)<dict>\n"
        for (key, value) in entry {
            xml += "\(indent)\t<key>\(key)</key>\n\(indent)\t<integer>\(value)</integer>\n"
        }
        return xml + "\(indent)</dict>\n"
    }

    nonisolated static func xmlEscape(_ text: String) -> String {
        text.replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
            .replacingOccurrences(of: "\"", with: "&quot;")
            .replacingOccurrences(of: "'", with: "&apos;")
    }
}

// MARK: - Orchestration runs

/// What a worker in a run may do.
public enum NexusAgentWorkerRole: String, Equatable, Sendable, Codable, CaseIterable {
    /// Writes code, in a git worktree of its own.
    case writerWorktree
    /// Reads and reviews; changes nothing.
    case reviewerReadOnly

    public var displayName: String {
        switch self {
        case .writerWorktree: return "Writer"
        case .reviewerReadOnly: return "Reviewer"
        }
    }
}

/// One unit of work in an orchestration run.
public struct NexusAgentWorkerTask: Identifiable, Equatable, Sendable, Codable {
    public enum Status: String, Equatable, Sendable, Codable, CaseIterable {
        /// Waiting on tasks it depends on.
        case pending
        /// Every dependency is done; it can be handed to a worker.
        case ready
        /// A worker has it.
        case dispatched
        case completed
        case failed
        /// Failed too many times, or a task it depends on did; it will not run.
        case circuitBroken

        public var isTerminal: Bool {
            self == .completed || self == .failed || self == .circuitBroken
        }
    }

    public var id: UUID
    public var title: String
    public var promptSpec: String
    public var role: NexusAgentWorkerRole
    public var dependsOnTaskIDs: [UUID]
    public var assignedProviderName: String
    public var worktreePath: String?
    public var status: Status
    public var resultSummary: String?
    /// How many times a worker has reported this task failed.
    public var failureCount: Int

    public init(id: UUID = UUID(), title: String, promptSpec: String,
                role: NexusAgentWorkerRole = .writerWorktree, dependsOnTaskIDs: [UUID] = [],
                assignedProviderName: String = "", worktreePath: String? = nil,
                status: Status = .pending, resultSummary: String? = nil, failureCount: Int = 0) {
        self.id = id
        self.title = title
        self.promptSpec = promptSpec
        self.role = role
        self.dependsOnTaskIDs = dependsOnTaskIDs
        self.assignedProviderName = assignedProviderName
        self.worktreePath = worktreePath
        self.status = status
        self.resultSummary = resultSummary
        self.failureCount = failureCount
    }

    enum CodingKeys: String, CodingKey {
        case id, title, promptSpec, role, dependsOnTaskIDs, assignedProviderName
        case worktreePath, status, resultSummary, failureCount
    }

    /// Only `title` and `promptSpec` are required, so a CLI caller can send
    /// a bare task list.
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        title = try container.decode(String.self, forKey: .title)
        promptSpec = try container.decode(String.self, forKey: .promptSpec)
        role = try container.decodeIfPresent(NexusAgentWorkerRole.self, forKey: .role) ?? .writerWorktree
        dependsOnTaskIDs = try container.decodeIfPresent([UUID].self, forKey: .dependsOnTaskIDs) ?? []
        assignedProviderName = try container.decodeIfPresent(String.self, forKey: .assignedProviderName) ?? ""
        worktreePath = try container.decodeIfPresent(String.self, forKey: .worktreePath)
        status = try container.decodeIfPresent(Status.self, forKey: .status) ?? .pending
        resultSummary = try container.decodeIfPresent(String.self, forKey: .resultSummary)
        failureCount = try container.decodeIfPresent(Int.self, forKey: .failureCount) ?? 0
    }
}

/// A set of worker tasks that depend on one another (a DAG).
public struct NexusAgentOrchestrationRun: Identifiable, Equatable, Sendable, Codable {
    public var id: UUID
    public var name: String
    public var tasks: [NexusAgentWorkerTask]
    public var createdAt: Date

    public init(id: UUID = UUID(), name: String, tasks: [NexusAgentWorkerTask], createdAt: Date = Date()) {
        self.id = id
        self.name = name
        self.tasks = tasks
        self.createdAt = createdAt
    }

    /// Tasks not yet handed out whose dependencies have all completed.
    public var readyTasks: [NexusAgentWorkerTask] {
        let completed = Set(tasks.filter { $0.status == .completed }.map(\.id))
        return tasks.filter { task in
            (task.status == .pending || task.status == .ready)
                && task.dependsOnTaskIDs.allSatisfy { completed.contains($0) }
        }
    }

    /// Every task has finished one way or another.
    public var isComplete: Bool {
        !tasks.isEmpty && tasks.allSatisfy { $0.status.isTerminal }
    }

    /// Every task completed.
    public var succeeded: Bool {
        !tasks.isEmpty && tasks.allSatisfy { $0.status == .completed }
    }

    public var completedCount: Int { tasks.filter { $0.status == .completed }.count }

    /// Why the task list cannot be run, or nil when it can: a dependency
    /// names no task in the run, or the dependencies loop.
    public var validationError: String? {
        let ids = Set(tasks.map(\.id))
        guard ids.count == tasks.count else { return "two tasks share an id" }
        for task in tasks {
            for dependency in task.dependsOnTaskIDs where !ids.contains(dependency) {
                return "task \"\(task.title)\" depends on \(dependency.uuidString), which is not in the run"
            }
        }
        var remaining = Dictionary(uniqueKeysWithValues: tasks.map { ($0.id, Set($0.dependsOnTaskIDs)) })
        while !remaining.isEmpty {
            let free = remaining.filter { $0.value.isEmpty }.map(\.key)
            if free.isEmpty { return "the task dependencies form a cycle" }
            for id in free { remaining.removeValue(forKey: id) }
            for key in remaining.keys { remaining[key]?.subtract(free) }
        }
        return nil
    }

    /// Marks pending tasks whose dependencies completed as ready, and
    /// breaks the circuit on every task downstream of one that will never
    /// complete.
    public mutating func refreshStatuses() {
        var changed = true
        while changed {
            changed = false
            let byID = Dictionary(uniqueKeysWithValues: tasks.map { ($0.id, $0.status) })
            for index in tasks.indices where tasks[index].status == .pending || tasks[index].status == .ready {
                let statuses = tasks[index].dependsOnTaskIDs.compactMap { byID[$0] }
                if statuses.contains(where: { $0 == .failed || $0 == .circuitBroken }) {
                    tasks[index].status = .circuitBroken
                    tasks[index].resultSummary = "A task it depends on did not complete."
                    changed = true
                } else if tasks[index].status == .pending, statuses.allSatisfy({ $0 == .completed }) {
                    tasks[index].status = .ready
                    changed = true
                }
            }
        }
    }
}

// MARK: - Control protocol

/// A request to Nexus Agent over its JSON control protocol, from the CLI or
/// from an agent (as an MCP tool). One JSON object per request:
/// `{"id":"1","method":"orchestration.worker_done","params":{...}}`.
public struct NexusAgentControlCommand: Equatable, Sendable, Codable {
    public enum Method: String, Equatable, Sendable, Codable, CaseIterable {
        case status
        case worktreeCreate = "worktree.create"
        case orchestrationDispatch = "orchestration.dispatch"
        case orchestrationWorkerDone = "orchestration.worker_done"
        case inboxList = "inbox.list"
    }

    public struct Params: Equatable, Sendable, Codable {
        /// The run to act on. `orchestration.dispatch` without it starts a new run.
        public var runID: UUID?
        public var taskID: UUID?
        /// The new run's name (`orchestration.dispatch`).
        public var runName: String?
        /// The new run's tasks (`orchestration.dispatch`).
        public var tasks: [NexusAgentWorkerTask]?
        /// Whether the worker finished its task (`orchestration.worker_done`).
        public var succeeded: Bool?
        /// What the worker reports (`orchestration.worker_done`).
        public var summary: String?
        /// The worktree's branch (`worktree.create`).
        public var branch: String?

        public init(runID: UUID? = nil, taskID: UUID? = nil, runName: String? = nil,
                    tasks: [NexusAgentWorkerTask]? = nil, succeeded: Bool? = nil,
                    summary: String? = nil, branch: String? = nil) {
            self.runID = runID
            self.taskID = taskID
            self.runName = runName
            self.tasks = tasks
            self.succeeded = succeeded
            self.summary = summary
            self.branch = branch
        }
    }

    public var id: String?
    public var method: Method
    public var params: Params

    public init(id: String? = nil, method: Method, params: Params = Params()) {
        self.id = id
        self.method = method
        self.params = params
    }

    enum CodingKeys: String, CodingKey { case id, method, params }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decodeIfPresent(String.self, forKey: .id)
        method = try container.decode(Method.self, forKey: .method)
        params = try container.decodeIfPresent(Params.self, forKey: .params) ?? Params()
    }
}

/// A worker's report, kept for the user to read.
public struct NexusAgentInboxItem: Identifiable, Equatable, Sendable, Codable {
    public var id: UUID
    public var runID: UUID
    public var taskID: UUID
    public var title: String
    public var summary: String
    public var succeeded: Bool
    public var receivedAt: Date

    public init(id: UUID = UUID(), runID: UUID, taskID: UUID, title: String,
                summary: String, succeeded: Bool, receivedAt: Date) {
        self.id = id
        self.runID = runID
        self.taskID = taskID
        self.title = title
        self.summary = summary
        self.succeeded = succeeded
        self.receivedAt = receivedAt
    }
}

/// The answer to a control command.
public struct NexusAgentControlResponse: Equatable, Sendable, Codable {
    public struct Result: Equatable, Sendable, Codable {
        public var runs: [NexusAgentOrchestrationRun]?
        public var run: NexusAgentOrchestrationRun?
        /// Tasks this command handed to workers.
        public var dispatched: [NexusAgentWorkerTask]?
        public var inbox: [NexusAgentInboxItem]?
        public var worktreePath: String?
        /// The git arguments that create the worktree; the caller runs them.
        public var gitArguments: [String]?
        public var hibernatedSessionIDs: [String]?

        public init(runs: [NexusAgentOrchestrationRun]? = nil, run: NexusAgentOrchestrationRun? = nil,
                    dispatched: [NexusAgentWorkerTask]? = nil, inbox: [NexusAgentInboxItem]? = nil,
                    worktreePath: String? = nil, gitArguments: [String]? = nil,
                    hibernatedSessionIDs: [String]? = nil) {
            self.runs = runs
            self.run = run
            self.dispatched = dispatched
            self.inbox = inbox
            self.worktreePath = worktreePath
            self.gitArguments = gitArguments
            self.hibernatedSessionIDs = hibernatedSessionIDs
        }
    }

    public var id: String?
    public var ok: Bool
    public var error: String?
    public var result: Result?

    public init(id: String?, ok: Bool, error: String? = nil, result: Result? = nil) {
        self.id = id
        self.ok = ok
        self.error = error
        self.result = result
    }

    public static func failure(_ id: String?, _ message: String) -> NexusAgentControlResponse {
        NexusAgentControlResponse(id: id, ok: false, error: message)
    }
}

/// Holds the orchestration runs and answers control commands. It records
/// state only: the app starts a worker for each task a dispatch hands out
/// and creates the worktrees from the git arguments it is given.
@MainActor
public final class NexusAgentOrchestrationCoordinator: ObservableObject {
    @Published public private(set) var runs: [NexusAgentOrchestrationRun] = []
    @Published public private(set) var inbox: [NexusAgentInboxItem] = []
    /// Where writer worktrees are made.
    public var worktreeRoot: String
    /// Failures a task may have before its circuit breaks.
    public var maxFailures: Int
    /// Sessions asleep, reported by `status`. The app keeps it current.
    public var hibernatedSessionIDs: () -> [String] = { [] }
    private let now: () -> Date

    public init(worktreeRoot: String, maxFailures: Int = 2, now: @escaping () -> Date = Date.init) {
        self.worktreeRoot = worktreeRoot
        self.maxFailures = max(1, maxFailures)
        self.now = now
    }

    public func run(id: UUID) -> NexusAgentOrchestrationRun? {
        runs.first { $0.id == id }
    }

    /// Answers one JSON request with one JSON response. Bad JSON gets a
    /// failure response rather than an error, so a caller always hears back.
    public func handle(json: Data) -> Data {
        let response: NexusAgentControlResponse
        do {
            let command = try JSONDecoder.nexusAgentControl.decode(NexusAgentControlCommand.self, from: json)
            response = handle(command)
        } catch {
            response = .failure(nil, "could not read the command: \(error.localizedDescription)")
        }
        return (try? JSONEncoder.nexusAgentControl.encode(response)) ?? Data("{\"ok\":false}".utf8)
    }

    public func handle(_ command: NexusAgentControlCommand) -> NexusAgentControlResponse {
        let params = command.params
        switch command.method {
        case .status:
            return NexusAgentControlResponse(id: command.id, ok: true, result: NexusAgentControlResponse.Result(
                runs: runs, hibernatedSessionIDs: hibernatedSessionIDs()))
        case .inboxList:
            return NexusAgentControlResponse(id: command.id, ok: true, result: NexusAgentControlResponse.Result(inbox: inbox))
        case .worktreeCreate:
            guard let branch = params.branch?.trimmingCharacters(in: .whitespaces), !branch.isEmpty else {
                return .failure(command.id, "worktree.create needs a branch")
            }
            let path = worktreePath(named: branch)
            return NexusAgentControlResponse(id: command.id, ok: true, result: NexusAgentControlResponse.Result(
                worktreePath: path, gitArguments: ["worktree", "add", "-b", branch, path]))
        case .orchestrationDispatch:
            if let runID = params.runID {
                guard runs.contains(where: { $0.id == runID }) else {
                    return .failure(command.id, "no run \(runID.uuidString)")
                }
                let dispatched = dispatchReady(runID: runID)
                return NexusAgentControlResponse(id: command.id, ok: true, result: NexusAgentControlResponse.Result(
                    run: run(id: runID), dispatched: dispatched))
            }
            guard let tasks = params.tasks, !tasks.isEmpty else {
                return .failure(command.id, "orchestration.dispatch needs a runID or tasks")
            }
            switch startRun(name: params.runName ?? "Run", tasks: tasks) {
            case .failure(let error):
                return .failure(command.id, error.message)
            case .success(let run):
                let dispatched = dispatchReady(runID: run.id)
                return NexusAgentControlResponse(id: command.id, ok: true, result: NexusAgentControlResponse.Result(
                    run: self.run(id: run.id), dispatched: dispatched))
            }
        case .orchestrationWorkerDone:
            guard let runID = params.runID, let taskID = params.taskID else {
                return .failure(command.id, "orchestration.worker_done needs a runID and a taskID")
            }
            guard let succeeded = params.succeeded else {
                return .failure(command.id, "orchestration.worker_done needs succeeded")
            }
            if let error = workerDone(runID: runID, taskID: taskID, succeeded: succeeded,
                                      summary: params.summary ?? "") {
                return .failure(command.id, error)
            }
            return NexusAgentControlResponse(id: command.id, ok: true, result: NexusAgentControlResponse.Result(run: run(id: runID)))
        }
    }

    public struct RunError: Error, Equatable, Sendable {
        public var message: String
    }

    /// Adds a run of these tasks, every one waiting until dispatched.
    public func startRun(name: String, tasks: [NexusAgentWorkerTask]) -> Result<NexusAgentOrchestrationRun, RunError> {
        var run = NexusAgentOrchestrationRun(name: name, tasks: tasks.map { task in
            var fresh = task
            fresh.status = .pending
            fresh.failureCount = 0
            fresh.resultSummary = nil
            return fresh
        }, createdAt: now())
        if let error = run.validationError { return .failure(RunError(message: error)) }
        run.refreshStatuses()
        runs.append(run)
        return .success(run)
    }

    /// Hands every ready task of the run to a worker: marks it dispatched
    /// and gives a writer its worktree path. Returns the tasks handed out.
    @discardableResult
    public func dispatchReady(runID: UUID) -> [NexusAgentWorkerTask] {
        guard let runIndex = runs.firstIndex(where: { $0.id == runID }) else { return [] }
        runs[runIndex].refreshStatuses()
        let readyIDs = Set(runs[runIndex].readyTasks.map(\.id))
        var dispatched: [NexusAgentWorkerTask] = []
        for index in runs[runIndex].tasks.indices where readyIDs.contains(runs[runIndex].tasks[index].id) {
            var task = runs[runIndex].tasks[index]
            task.status = .dispatched
            if task.role == .writerWorktree, task.worktreePath == nil {
                task.worktreePath = worktreePath(named: Self.slug(runs[runIndex].name)
                    + "-" + String(task.id.uuidString.prefix(8)).lowercased())
            }
            runs[runIndex].tasks[index] = task
            dispatched.append(task)
        }
        return dispatched
    }

    /// Records a worker's report. A failure sends the task back to ready to
    /// be tried again, until it has failed `maxFailures` times; then its
    /// circuit breaks, and with it every task downstream. Returns an error
    /// message when the report does not fit the run.
    @discardableResult
    public func workerDone(runID: UUID, taskID: UUID, succeeded: Bool, summary: String) -> String? {
        guard let runIndex = runs.firstIndex(where: { $0.id == runID }) else {
            return "no run \(runID.uuidString)"
        }
        guard let index = runs[runIndex].tasks.firstIndex(where: { $0.id == taskID }) else {
            return "no task \(taskID.uuidString) in the run"
        }
        guard runs[runIndex].tasks[index].status == .dispatched else {
            return "task \(taskID.uuidString) is \(runs[runIndex].tasks[index].status.rawValue), not dispatched"
        }
        var task = runs[runIndex].tasks[index]
        task.resultSummary = summary
        if succeeded {
            task.status = .completed
        } else {
            task.failureCount += 1
            task.status = task.failureCount >= maxFailures ? .circuitBroken : .ready
        }
        runs[runIndex].tasks[index] = task
        runs[runIndex].refreshStatuses()
        inbox.append(NexusAgentInboxItem(runID: runID, taskID: taskID, title: task.title,
                                         summary: summary, succeeded: succeeded, receivedAt: now()))
        return nil
    }

    public func removeRun(id: UUID) {
        runs.removeAll { $0.id == id }
    }

    func worktreePath(named name: String) -> String {
        let root = worktreeRoot.hasSuffix("/") ? String(worktreeRoot.dropLast()) : worktreeRoot
        return root + "/" + Self.slug(name)
    }

    static func slug(_ text: String) -> String {
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-_"))
        let mapped = text.lowercased().unicodeScalars.map { allowed.contains($0) ? Character($0) : "-" }
        let collapsed = String(mapped).split(separator: "-", omittingEmptySubsequences: true).joined(separator: "-")
        return collapsed.isEmpty ? "run" : collapsed
    }
}

extension JSONEncoder {
    /// Sorted keys and ISO 8601 dates: what the control protocol and the
    /// mobile companion read.
    static var nexusAgentControl: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }
}

extension JSONDecoder {
    static var nexusAgentControl: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }
}

// MARK: - SSH worktrees and the mobile companion

/// A machine reached over SSH where an agent can run in a remote worktree.
public struct NexusAgentRemoteHost: Identifiable, Equatable, Sendable, Codable {
    public var id: UUID
    public var label: String
    public var sshHost: String
    public var sshUser: String
    public var remoteWorkspacePath: String
    /// With `portForwardRemotePort`, forwards this local port to the remote
    /// one, so a dev server in the remote worktree can be previewed here.
    public var portForwardLocalPort: Int?
    public var portForwardRemotePort: Int?
    public var isConnected: Bool

    public init(id: UUID = UUID(), label: String, sshHost: String, sshUser: String = "",
                remoteWorkspacePath: String = "", portForwardLocalPort: Int? = nil,
                portForwardRemotePort: Int? = nil, isConnected: Bool = false) {
        self.id = id
        self.label = label
        self.sshHost = sshHost
        self.sshUser = sshUser
        self.remoteWorkspacePath = remoteWorkspacePath
        self.portForwardLocalPort = portForwardLocalPort
        self.portForwardRemotePort = portForwardRemotePort
        self.isConnected = isConnected
    }

    /// `user@host`, or the host alone when no user is set.
    public var destination: String {
        let user = sshUser.trimmingCharacters(in: .whitespaces)
        return user.isEmpty ? sshHost : "\(user)@\(sshHost)"
    }
}

/// One session as the mobile companion shows it.
public struct NexusAgentMobileSessionSnapshot: Identifiable, Equatable, Sendable, Codable {
    public var sessionID: String
    public var title: String
    public var providerName: String
    public var status: String
    public var workingDirectory: String
    public var worktreeBranch: String?
    public var pendingApprovalSummary: String?
    public var updatedAt: Date

    public var id: String { sessionID }

    public init(sessionID: String, title: String, providerName: String, status: String,
                workingDirectory: String, worktreeBranch: String? = nil,
                pendingApprovalSummary: String? = nil, updatedAt: Date) {
        self.sessionID = sessionID
        self.title = title
        self.providerName = providerName
        self.status = status
        self.workingDirectory = workingDirectory
        self.worktreeBranch = worktreeBranch
        self.pendingApprovalSummary = pendingApprovalSummary
        self.updatedAt = updatedAt
    }
}

/// What the mobile companion can ask a session to do.
public enum NexusAgentMobileQuickAction: String, Equatable, Sendable, Codable, CaseIterable {
    case approve
    case deny
    case stop
    case sendPrompt = "send_prompt"
    case switchAccount = "switch_account"
}

/// One quick action from the phone.
public struct NexusAgentMobileCommand: Equatable, Sendable, Codable {
    public var action: NexusAgentMobileQuickAction
    public var sessionID: String
    /// The prompt (`send_prompt`).
    public var text: String?
    /// The account to switch to (`switch_account`).
    public var accountID: String?

    public init(action: NexusAgentMobileQuickAction, sessionID: String,
                text: String? = nil, accountID: String? = nil) {
        self.action = action
        self.sessionID = sessionID
        self.text = text
        self.accountID = accountID
    }
}

/// Builds SSH invocations for remote hosts and moves session state to and
/// from the mobile companion.
public enum NexusAgentRemoteAndMobileBridge {
    public enum BridgeError: Error, Equatable, Sendable {
        case emptyHost
        case emptySessionID
        case missingText
        case missingAccount
    }

    /// The arguments to `ssh` that run `remoteCommand` in the host's remote
    /// workspace, forwarding the preview port if one is set. An empty
    /// command only holds the port forward open (`-N`).
    public static func sshArguments(for host: NexusAgentRemoteHost, remoteCommand: String) -> [String] {
        var arguments = ["-o", "BatchMode=yes", "-o", "ServerAliveInterval=30"]
        arguments += portForwardArguments(for: host)
        let command = remoteCommand.trimmingCharacters(in: .whitespacesAndNewlines)
        if command.isEmpty {
            arguments.append("-N")
            arguments.append(host.destination)
            return arguments
        }
        arguments.append(host.destination)
        let path = host.remoteWorkspacePath.trimmingCharacters(in: .whitespaces)
        arguments.append(path.isEmpty ? command : "cd \(shellQuote(path)) && \(command)")
        return arguments
    }

    /// `-L local:localhost:remote` when both ports are set and valid.
    public static func portForwardArguments(for host: NexusAgentRemoteHost) -> [String] {
        guard let local = host.portForwardLocalPort, let remote = host.portForwardRemotePort,
              (1...65535).contains(local), (1...65535).contains(remote) else { return [] }
        return ["-L", "\(local):localhost:\(remote)"]
    }

    /// Quotes `text` for a POSIX shell.
    public static func shellQuote(_ text: String) -> String {
        "'" + text.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }

    public static func exportSnapshots(_ snapshots: [NexusAgentMobileSessionSnapshot]) throws -> Data {
        try JSONEncoder.nexusAgentControl.encode(snapshots)
    }

    public static func importSnapshots(_ data: Data) throws -> [NexusAgentMobileSessionSnapshot] {
        try JSONDecoder.nexusAgentControl.decode([NexusAgentMobileSessionSnapshot].self, from: data)
    }

    public static func encodeCommand(_ command: NexusAgentMobileCommand) throws -> Data {
        try validate(command)
        return try JSONEncoder.nexusAgentControl.encode(command)
    }

    /// Reads a quick action, refusing one missing what it needs.
    public static func decodeCommand(_ data: Data) throws -> NexusAgentMobileCommand {
        let command = try JSONDecoder.nexusAgentControl.decode(NexusAgentMobileCommand.self, from: data)
        try validate(command)
        return command
    }

    public static func validate(_ command: NexusAgentMobileCommand) throws {
        if command.sessionID.trimmingCharacters(in: .whitespaces).isEmpty { throw BridgeError.emptySessionID }
        switch command.action {
        case .sendPrompt:
            if (command.text ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                throw BridgeError.missingText
            }
        case .switchAccount:
            if (command.accountID ?? "").trimmingCharacters(in: .whitespaces).isEmpty {
                throw BridgeError.missingAccount
            }
        case .approve, .deny, .stop:
            break
        }
    }
}
