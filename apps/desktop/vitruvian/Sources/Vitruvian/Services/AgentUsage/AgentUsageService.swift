// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Combine
import Foundation
import Network
import VitruvianCore
import VitruvianDesign

/// Reads Claude Code, Codex and GitHub Copilot usage from local session logs, and
/// OpenCode usage from its database, while the AI section is on, along with
/// the plan limits the Claude app saves. The files are read where they are,
/// incrementally, and nothing is copied or sent: only counters are kept, in
/// memory and in the app's private folder so the next launch reads only what
/// the agents wrote meanwhile. OpenCode's stay in memory only, and its
/// database is read again at each launch. Claude Code checks account-wide
/// limits through its own CLI, including use on other machines. The public
/// price list is fetched only when the person keeps prices up to date.
///
/// Reading happens on a private queue; the main thread and that queue hand
/// work to each other asynchronously, except that a stop waits for progress
/// to be saved. The queue never waits for the main thread.
@MainActor
package final class AgentUsageService: ObservableObject {
    package static let shared = AgentUsageService()

    @Published package private(set) var snapshot = AgentUsageSnapshot()
    /// When the Claude app last saved the plan's limits; nil when it never has.
    @Published package private(set) var claudeAppChecked: Date?
    @Published package private(set) var claudeAccountChecking = false
    @Published package private(set) var claudeAccountFailure: AgentClaudeServer.Failure?
    /// The day of the price list in use.
    @Published package private(set) var pricesUpdated: Date?
    package let events = PassthroughSubject<AgentUsageEvent, Never>()

    /// The history the island can show: thirteen weeks for the activity map.
    nonisolated package static let horizon = TimeInterval(AgentUsageSnapshot.dayCount) * 86_400
    private static let tick: TimeInterval = 30
    /// File events report a written file only once it closes, and some
    /// agents keep their log open for the whole session: logs written in the
    /// last half hour, or holding a turn, are checked this often instead.
    nonisolated private static let poll: TimeInterval = 2
    nonisolated private static let pollWindow: TimeInterval = 30 * 60
    /// Coalesce a live log's bursts into one history and display update.
    nonisolated private static let publishDelay: TimeInterval = 1
    /// How often progress is saved while agents write, besides on quit and
    /// pause; a launch after a crash reads again only what came after.
    nonisolated private static let saveInterval: TimeInterval = 5 * 60

    private let queue = DispatchQueue(label: "com.vitruviansoftware.vitruvian.agent-usage", qos: .utility, autoreleaseFrequency: .workItem)
    private let home = FileManager.default.homeDirectoryForCurrentUser

    /// Lets a stop end a first read that is still going on the queue.
    // Its flag is behind the lock.
    private final class Cancellation: @unchecked Sendable {
        private let lock = NSLock()
        private var cancelled = false
        var isCancelled: Bool { lock.withLock { cancelled } }
        func cancel() { lock.withLock { cancelled = true } }
    }

    // Main thread.
    private var running = false
    /// Reading waits while the island is away; what was read stays.
    private var paused = false
    private var session = 0
    private var cancellation = Cancellation()
    private var timer: Timer?
    private var providers: [AgentProvider] = []
    private var pricesInFlight = false
    private var pricesAttempted = Date.distantPast
    private var pricesFailed = false
    /// When the list on disk was downloaded; nil until the queue has looked.
    private var pricesSaved: Date?
    private let claudeAccountQueue = DispatchQueue(label: "com.vitruviansoftware.vitruvian.claude-limits", qos: .utility)
    private var claudeAccountRequest: AgentClaudeServer.Request?
    private var claudeAccountAttempted = Date.distantPast
    /// The AI page is on the island, which asks Claude Code more often.
    private var pageVisible = false

    // Confined to `queue`.
    nonisolated(unsafe) private var readerSession = -1
    nonisolated(unsafe) private var readerCancellation: Cancellation?
    nonisolated(unsafe) private var enabled: Set<AgentProvider> = []
    nonisolated(unsafe) private var store = AgentUsageStore()
    nonisolated(unsafe) private var cursors: [String: AgentLogCursor] = [:]
    nonisolated(unsafe) private var watcher: AgentLogWatcher?
    nonisolated(unsafe) private var watchedRoots: [AgentLogRoot] = []
    nonisolated(unsafe) private var poller: DispatchSourceTimer?
    nonisolated(unsafe) private var polling = false
    nonisolated(unsafe) private var network: NWPathMonitor?
    /// When the Mac lost its network, and the uptime then, which leaves out
    /// sleep; nil while it has one.
    nonisolated(unsafe) private var offlineSince: (date: Date, uptime: TimeInterval)?
    nonisolated(unsafe) private var publishScheduled = false
    /// The last snapshot handed over, to tell when time alone changes it.
    nonisolated(unsafe) private var published = AgentUsageSnapshot()
    nonisolated(unsafe) private var claudePlan: AgentPlan?
    /// The organization Claude Code signs in to, when its profile says.
    nonisolated(unsafe) private var claudeOrganization: String?
    nonisolated(unsafe) private var claudeProfileModified: Date?
    nonisolated(unsafe) private var claudeAppModified: Date?
    nonisolated(unsafe) private var claudeAppSamples: [AgentClaudeAppUsage.Sample] = []
    nonisolated(unsafe) private var shippedPrices: AgentPriceList?
    nonisolated(unsafe) private var previousLimits: [AgentProvider: AgentLimits] = [:]
    /// Warned windows, each waiting for its renewal.
    nonisolated(unsafe) private var warned: [String: (provider: AgentProvider, window: AgentLimitWindow)] = [:]
    nonisolated(unsafe) private var budgetDay: Date?
    nonisolated(unsafe) private var lastRootCheck = Date.distantPast
    /// Tells whether reading moved on since progress was last saved.
    /// Nil until this reading saved or resumed progress: the first save
    /// always replaces what is on disk, which may hold agents now off.
    nonisolated(unsafe) private var savedMark: Int?
    nonisolated(unsafe) private var lastSave = Date.distantPast
    nonisolated(unsafe) private var identities: [AgentProvider: AgentIdentity] = [:]
    nonisolated(unsafe) private var cachedCredits: [AgentProvider: Double] = [:]
    nonisolated(unsafe) private var cachedCostMetrics: [AgentProvider: AgentCostMetrics] = [:]
    nonisolated(unsafe) private var cachedDailySpend: [AgentProvider: [AgentDailyCost]] = [:]
    nonisolated(unsafe) private var lastCodexBarProbe = Date.distantPast
    nonisolated(unsafe) private var isProbingCodexBar = false
    /// Claude's limits as CodexBar last read them from the account.
    nonisolated(unsafe) private var claudeAccountLimits: AgentLimits?

    private init() {}

    package func syncWithPreferences() {
        CodexProfileLimitsService.shared.synchronize()
        guard NotchAgentSupport.isEnabled() else { stop(); return }
        let wanted = NotchAgentSupport.providers()
        // An agent turned off is no longer read at all, and one turned on is
        // read from its start: both take a fresh reading, which would not
        // resume progress saved for the old set, so it goes at once. Codex
        // accounts keep their checks: they read no log.
        if running, wanted != providers { stop(keepingProgress: false, pausingAccounts: false) }
        if !running {
            running = true
            session += 1
            cancellation = Cancellation()
            providers = wanted
            start(session: session, providers: Set(wanted), cancellation: cancellation)
        } else if paused {
            resume()
        }
        syncPrices()
        refreshClaudeLimits()
    }

    /// Stops reading while the island is away, as with the display asleep or
    /// the Mac locked, and keeps what was read: reading every log again on the
    /// way back costs far more than the pause saves.
    package func pause() {
        CodexProfileLimitsService.shared.pause()
        guard running, !paused else { return }
        paused = true
        cancelClaudeLimits()
        timer?.invalidate()
        timer = nil
        queue.async { [self] in
            poller?.cancel()
            poller = nil
            watcher?.stop()
            saveProgress()
        }
    }

    /// Reads what the agents wrote meanwhile, from where each log stopped.
    private func resume() {
        paused = false
        startTimer()
        queue.async { [self] in
            guard readerSession >= 0 else { return }
            watch(AgentLogRoot.all(home: home).filter { enabled.contains($0.provider) })
            filesChanged([], rescan: true)
            startPolling()
            // Time went by meanwhile: a window or the day may have moved on.
            schedulePublish()
        }
    }

    package func stop(keepingProgress keeps: Bool = true, pausingAccounts: Bool = true) {
        if pausingAccounts { CodexProfileLimitsService.shared.pause() }
        // A first read still going stops at its next chunk, so the wait
        // below is short.
        if running { cancellation.cancel() }
        settleArchive(keeping: keeps && NotchAgentSupport.isEnabled())
        guard running else { return }
        running = false
        cancelClaudeLimits()
        claudeAccountAttempted = .distantPast
        claudeAccountFailure = nil
        paused = false
        session += 1
        timer?.invalidate()
        timer = nil
        providers = []
        pricesInFlight = false
        pricesSaved = nil
        snapshot = AgentUsageSnapshot()
        claudeAppChecked = nil
        queue.async { [self] in
            readerSession = -1
            readerCancellation = nil
            poller?.cancel()
            poller = nil
            watcher?.stop()
            watcher = nil
            watchedRoots = []
            network?.cancel()
            network = nil
            offlineSince = nil
            store = AgentUsageStore()
            claudeAccountLimits = nil
            // The next start asks CodexBar at once.
            lastCodexBarProbe = .distantPast
            cursors.removeAll()
            published = AgentUsageSnapshot()
            previousLimits.removeAll()
            warned.removeAll()
            budgetDay = nil
            claudePlan = nil
            claudeOrganization = nil
            claudeProfileModified = nil
            claudeAppModified = nil
            claudeAppSamples = []
            claudeAccountLimits = nil
            savedMark = nil
            lastSave = .distantPast
        }
    }

    /// Limits an agent read from the account on request, newer than its
    /// logs until it writes again: after a banked reset, right away.
    package func noteLimits(_ reading: AgentLimits) {
        guard running else { return }
        queue.async { [self] in
            guard readerSession >= 0, enabled.contains(reading.provider) else { return }
            store.updateLimits(reading)
            checkLimits()
            schedulePublish()
        }
    }

    /// Reads local fallbacks immediately and asks Claude for fresh account
    /// limits. A Settings preview reads too, without counting as the page.
    package func pageDidAppear(preview: Bool = false) {
        if !preview { pageVisible = true }
        guard running else { return }
        refreshClaudeLimits()
        queue.async { [self] in
            guard readerSession >= 0 else { return }
            let now = Date()
            readClaudePlan()
            readClaudeApp(now: now)
            readAntigravityQuota(now: now, force: true)
            readCodexBarMetrics(now: now)
            checkLimits()
            publish()
        }
    }

    package func pageDidDisappear() {
        pageVisible = false
    }

    // MARK: Reading

    private func startTimer() {
        let timer = Timer(timeInterval: Self.tick, repeats: true) { [weak self] _ in
            // Added to the main run loop below, so it fires on the main thread.
            MainActor.assumeIsolated { self?.tickTimer() }
        }
        timer.tolerance = 10
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    private func start(session: Int, providers: Set<AgentProvider>, cancellation: Cancellation) {
        startTimer()
        queue.async { [self] in
            readerSession = session
            readerCancellation = cancellation
            enabled = providers
            store = AgentUsageStore()
            cursors.removeAll()
            // Prices first, so the first read is already priced.
            loadPrices()
            // Keep the loading state until all initial history has been read.
            let horizon = Date().addingTimeInterval(-Self.horizon)
            let roots = AgentLogRoot.all(home: home).filter { providers.contains($0.provider) }
            let files = AgentLogReader.discover(roots, since: horizon)
            // Resumes where the last launch stopped, among the logs there now.
            if let saved = AgentUsageArchive.load(), saved.providers == providers {
                let resumed = AgentUsageArchive.resume(saved, logs: Set(files.map(\.path)), since: horizon)
                (store, cursors) = (resumed.store, resumed.cursors)
                // What the resume took back leaves the disk at the next save.
                if resumed.unchanged { savedMark = progressMark }
            }
            for file in files {
                // A stop while reading leaves the rest for the next start.
                guard !cancellation.isCancelled else { return }
                read(file.path, provider: file.provider)
            }
            guard !cancellation.isCancelled else { return }
            let now = Date()
            if providers.contains(.antigravity) {
                _ = AgentAntigravityReader.read(store: store, enabled: providers, home: home, now: now)
                readAntigravityQuota(now: now, force: true)
            }
            // A turn left open by a crash would otherwise stay working.
            store.closeIdleTurns(now: now, after: NotchAgentSupport.idleTurn)
            closeEndedTurns(roots, atLaunch: true)
            // The account Claude Code uses picks the Claude app's readings.
            readClaudePlan()
            readClaudeApp(now: now)
            // The account's exact renewals arrive soon after, not a tick later.
            readCodexBarMetrics(now: now)
            store.reportsTransitions = true
            previousLimits = store.limits
            // A budget already passed before launch is history, not news.
            let today = Calendar.autoupdatingCurrent.startOfDay(for: now)
            if let budget = NotchAgentSupport.dailyBudget(),
               store.records.lazy.filter({ $0.date >= today }).reduce(0.0, { $0 + ($1.cost ?? 0) }) >= budget {
                budgetDay = today
            }
            watch(roots)
            startPolling()
            watchNetwork()
            publish()
            saveProgress()
        }
    }

    /// Saves progress, or removes it once the section is off, even what an
    /// earlier launch saved. Quitting stops the service too and ends the
    /// process right after, so this returns only once the file is settled.
    /// Main thread.
    private func settleArchive(keeping keeps: Bool) {
        Self.settleArchive(on: queue, keeping: keeps, save: { saveProgress() })
    }

    /// Settles the file on `queue`, behind any reading still going there.
    nonisolated package static func settleArchive(on queue: DispatchQueue, keeping keeps: Bool, save: () -> Void,
                                                  remove: () -> Void = AgentUsageArchive.remove) {
        queue.sync {
            if keeps { save() } else { remove() }
        }
    }

    /// Saves what was read, when reading moved on since the last save. Runs
    /// on `queue`.
    nonisolated
    private func saveProgress() {
        guard readerSession >= 0 else { return }
        lastSave = Date()
        Self.saveProgress(mark: progressMark, savedMark: &savedMark, providers: enabled, store: store, cursors: cursors)
    }

    /// Writes progress unless `mark` says it is already saved; the first save
    /// of a reading, with `savedMark` nil, always writes.
    nonisolated package static func saveProgress(mark: Int, savedMark: inout Int?, providers: Set<AgentProvider>,
                                                 store: AgentUsageStore, cursors: [String: AgentLogCursor],
                                                 save: (AgentUsageArchive.Contents) -> Bool = AgentUsageArchive.save) {
        guard mark != savedMark else { return }
        // A log that started over while running still counts what its old
        // contents gave. Left out, the next launch reads it as rewritten.
        // Nothing from OpenCode's database is saved. Its open replies and
        // sessions live only in memory, so each launch reads it again.
        let kept = cursors.values.filter { !$0.restarted && $0.provider != .opencode }
        let contents = AgentUsageArchive.Contents(providers: providers, store: store.saved, cursors: kept.map(\.saved))
        if save(contents) { savedMark = mark }
    }

    /// Changes whenever a log is read further, replaced or let go. OpenCode,
    /// which is never saved, leaves it alone.
    nonisolated private var progressMark: Int {
        let records = store.records.reduce(0) { $1.provider == .opencode ? $0 : $0 + 1 }
        return cursors.values.reduce(records) { mark, cursor in
            guard cursor.provider != .opencode else { return mark }
            var hasher = Hasher()
            hasher.combine(cursor.path)
            hasher.combine(cursor.offset)
            hasher.combine(cursor.identity)
            return mark &+ hasher.finalize()
        }
    }

    /// Runs on `queue`.
    nonisolated private func startPolling() {
        poller?.cancel()
        let timer = DispatchSource.makeTimerSource(queue: queue)
        timer.schedule(deadline: .distantFuture)
        timer.setEventHandler { [weak self] in
            guard let self else { return }
            defer { self.syncPolling() }
            let read = self.pollOpenLogs(within: Self.pollWindow)
            var stopped = self.store.closeSettledTurns(now: Date())
            // After the logs too, which can hold a reply or a command's
            // result written meanwhile.
            if let offline = self.offlineSince,
               self.store.closeOfflineTurns(since: offline.date,
                                            lasting: ProcessInfo.processInfo.systemUptime - offline.uptime,
                                            keeping: self.runningCommands) {
                stopped = true
            }
            // After the logs, so a turn its last lines ended ends as usual.
            guard self.closeEndedTurns(self.watchedRoots) || read || stopped else { return }
            self.checkLimits()
            self.schedulePublish()
        }
        poller = timer
        polling = false
        syncPolling()
        timer.resume()
    }

    /// The fast timer has no work once recent logs and active turns are gone.
    /// File events and the existing thirty-second sweep can arm it again.
    /// Never create a timer here: late work after pause or stop must stay idle.
    nonisolated private func syncPolling(now: Date = Date()) {
        guard let poller else { return }
        let wanted = !store.turns.isEmpty || !store.waiting.isEmpty
            || cursors.values.contains { now.timeIntervalSince($0.modified) < Self.pollWindow }
        guard wanted != polling else { return }
        polling = wanted
        if wanted {
            poller.schedule(deadline: .now() + Self.poll, repeating: Self.poll, leeway: .milliseconds(500))
        } else {
            poller.schedule(deadline: .distantFuture)
        }
    }

    /// Reads the logs that grew, were replaced or disappeared since the last
    /// look, among those an agent may still be writing. True when that
    /// changed what is stored.
    nonisolated private func pollOpenLogs(within window: TimeInterval) -> Bool {
        guard readerSession >= 0 else { return false }
        let now = Date()
        // A turn gone quiet, as while it waits for an approval, is noticed
        // as soon as its work resumes.
        var working = Set(store.turns.keys).union(store.waiting.keys)
        // An OpenCode turn is kept by database and session.
        for key in working {
            if let mark = key.firstIndex(of: "#") { working.insert(String(key[..<mark])) }
        }
        var changed = false
        for (path, cursor) in cursors
        where working.contains(path) || now.timeIntervalSince(cursor.modified) < window {
            if cursor.provider == .opencode {
                // A database changes in place: its write-ahead log grows instead.
                if let modified = AgentOpenCodeReader.modified(path), modified <= cursor.modified { continue }
                if read(path, provider: cursor.provider) { changed = true }
                continue
            }
            var info = stat()
            let exists = stat(path, &info) == 0
            guard !exists || UInt64(max(0, info.st_size)) != cursor.offset
                    || UInt64(info.st_ino) != cursor.identity else { continue }
            if read(path, provider: cursor.provider) { changed = true }
        }
        if enabled.contains(.antigravity) {
            if AgentAntigravityReader.read(store: store, enabled: enabled, home: home, now: now) {
                changed = true
            }
        }
        return changed
    }

    /// Claude Code retries for minutes without a word while the Mac is
    /// offline, then gives up; until it does, its turn would count on.
    /// Only notes when the network went: the poller, which reads the logs
    /// first and waits while the island is away, ends the turns once the
    /// Mac stays offline. Runs on `queue`.
    nonisolated private func watchNetwork() {
        guard network == nil else { return }
        let monitor = NWPathMonitor()
        monitor.pathUpdateHandler = { [weak self] path in
            guard let self, self.readerSession >= 0 else { return }
            if path.status == .satisfied {
                self.offlineSince = nil
            } else if self.offlineSince == nil {
                self.offlineSince = (Date(), ProcessInfo.processInfo.systemUptime)
            }
        }
        monitor.start(queue: queue)
        network = monitor
    }

    /// The logs whose turn waits on a shell command of its own; a subagent's
    /// commands are not counted. Runs on `queue`.
    nonisolated private var runningCommands: Set<String> {
        Set(cursors.filter { !$0.value.state.runningCommands.isEmpty }.keys)
    }

    /// Ends the Claude turns whose process is gone. True when one was showing.
    @discardableResult
    nonisolated private func closeEndedTurns(_ roots: [AgentLogRoot], atLaunch: Bool = false) -> Bool {
        guard store.showsClaudeTurn else { return false }
        let folders = roots.filter { $0.provider == .claude }
            .map { $0.url.deletingLastPathComponent().appending(path: "sessions", directoryHint: .isDirectory) }
        return store.closeEndedTurns(AgentSessionRegistry.read(folders), atLaunch: atLaunch)
    }

    /// True when the log had entries to apply, or was gone and took a
    /// working turn with it.
    @discardableResult
    nonisolated
    private func read(_ path: String, provider: AgentProvider) -> Bool {
        guard let cancellation = readerCancellation else { return false }
        return Self.read(path, provider: provider, cursors: &cursors, store: store,
                         isCancelled: { cancellation.isCancelled }, report: { self.report($0) })
    }

    /// Applies what a log gained since the last read to `store`, line by
    /// line, and reports the turns that ended. `lines` reads the log, and
    /// `history` a Copilot log's first read; the closures they call back into
    /// must be escaping to be handed to them.
    nonisolated package static func read(_ path: String, provider: AgentProvider,
                                         cursors: inout [String: AgentLogCursor], store: AgentUsageStore,
                                         isCancelled: @escaping () -> Bool, report: @escaping (AgentUsageEvent) -> Void,
                                         lines: (AgentLogCursor, Date, () -> Bool, (Data) -> Void) -> Void
                                             = { AgentLogReader.readAppended($0, since: $1, shouldContinue: $2, line: $3) },
                                         history: (AgentLogCursor, () -> Bool, (Data) -> Void) -> Void
                                             = { AgentLogReader.readCopilotHistory($0, shouldContinue: $1, line: $2) })
        -> Bool {
        guard !isCancelled() else { return false }
        guard FileManager.default.fileExists(atPath: path) else {
            cursors[path] = nil
            return store.forget(file: path)
        }
        let cursor = cursors[path] ?? AgentLogCursor(path: path, provider: provider)
        cursors[path] = cursor
        var changed = false
        let now = Date()
        let consume: (Data) -> Void = { line in
            // Apply in log order while the chunk is alive instead of retaining
            // every parsed entry until a potentially multi-gigabyte file ends.
            let entries: [AgentLogEntry]
            switch provider {
            case .claude: entries = AgentLogParser.parseClaude(line, state: &cursor.state, now: now)
            case .codex: entries = AgentLogParser.parseCodex(line, state: &cursor.state, now: now)
            case .opencode: entries = AgentLogParser.parseOpenCode(line, state: &cursor.state, now: now)
            case .copilot: entries = AgentLogParser.parseCopilot(line, state: &cursor.state, now: now)
            case .antigravity: entries = []
            }
            guard !entries.isEmpty else { return }
            changed = true
            let isSubagent = provider == .opencode && !cursor.state.parentSession.isEmpty
            let turnFile = provider == .opencode && !cursor.state.session.isEmpty ? "\(path)#\(cursor.state.session)" : path
            let tracksTurns = isSubagent ? false : cursor.tracksTurns
            let parent = isSubagent ? "\(path)#\(cursor.state.parentSession)"
                : cursor.parent ?? cursor.codexParent(among: cursors)
            let finished = store.apply(entries, file: turnFile, provider: provider, tracksTurns: tracksTurns,
                                       parent: parent, modified: cursor.modified, now: now)
            finished.forEach(report)
        }
        if provider == .copilot && cursor.offset == 0 {
            history(cursor, { !isCancelled() }, consume)
        } else {
            lines(cursor, now.addingTimeInterval(-horizon), { !isCancelled() }, consume)
        }
        return changed
    }

    nonisolated private func watch(_ roots: [AgentLogRoot]) {
        let existing = roots.filter(\.exists)
        watchedRoots = existing
        lastRootCheck = Date()
        if watcher == nil {
            watcher = AgentLogWatcher(queue: queue) { [weak self] paths, rescan in
                self?.filesChanged(paths, rescan: rescan)
            }
        }
        if existing.isEmpty { watcher?.stop() } else { watcher?.start(existing.map(\.url.path)) }
    }

    nonisolated private func filesChanged(_ paths: [String], rescan: Bool) {
        guard readerSession >= 0, !watchedRoots.isEmpty else { return }
        defer { syncPolling() }
        var changed = false
        if rescan {
            for file in AgentLogReader.discover(watchedRoots, since: Date().addingTimeInterval(-Self.horizon)) {
                if read(file.path, provider: file.provider) { changed = true }
            }
        } else {
            for path in Set(paths) where AgentLogReader.isLog(path) {
                let actualPath = path.hasSuffix("-wal") ? String(path.dropLast(4)) : path
                guard let root = watchedRoots.first(where: { $0.accepts(actualPath) }) else { continue }
                if read(actualPath, provider: root.provider) { changed = true }
            }
        }
        // Saved tool output and lines with nothing to keep do not change the
        // summary or require a display update.
        guard changed else { return }
        checkLimits()
        schedulePublish()
    }

    /// Bursts of writes publish once.
    nonisolated private func schedulePublish() {
        guard !publishScheduled else { return }
        publishScheduled = true
        queue.asyncAfter(deadline: .now() + Self.publishDelay) { [self] in
            publishScheduled = false
            publish()
        }
    }

    private func tickTimer() {
        guard running else { return }
        syncPrices()
        refreshClaudeLimits()
        queue.async { [self] in
            guard readerSession >= 0 else { return }
            let now = Date()
            defer { syncPolling(now: now) }
            let before = inputs
            store.closeIdleTurns(now: now, after: NotchAgentSupport.idleTurn)
            store.dropRecords(before: now.addingTimeInterval(-Self.horizon))
            // A log kept open through a long pause reports nothing when work
            // resumes; the day's logs are looked at less often than recent ones.
            var changed = pollOpenLogs(within: 86_400)
            // A folder that appears later, like a first Codex session, is
            // picked up without a restart.
            if now.timeIntervalSince(lastRootCheck) > 300 {
                let roots = AgentLogRoot.all(home: home).filter { enabled.contains($0.provider) }
                if roots.filter(\.exists) != watchedRoots {
                    for file in AgentLogReader.discover(roots, since: now.addingTimeInterval(-Self.horizon)) {
                        if read(file.path, provider: file.provider) { changed = true }
                    }
                    watch(roots)
                }
                lastRootCheck = now
            }
            readClaudePlan()
            readClaudeApp(now: now)
            readAntigravityQuota(now: now)
            readCodexBarMetrics(now: now)
            checkLimits()
            reportRenewals(now: now)
            if now.timeIntervalSince(lastSave) >= Self.saveInterval { saveProgress() }
            // Publish only when stored values or sliding time windows change.
            if changed || inputs != before || AgentUsageSummary.movesWithClock(published, now: now) {
                schedulePublish()
            }
        }
    }

    /// The stored state a snapshot is made from, compared across a tick.
    private struct Inputs: Equatable {
        let records: Int
        let turns: [String: AgentLiveSession]
        let limits: [AgentProvider: AgentLimits]
        let codexPlan: String?
        let claudePlan: AgentPlan?
        let claudeOrganization: String?
        let claudeApp: [AgentClaudeAppUsage.Sample]
        let identities: [AgentProvider: AgentIdentity]
        let costMetrics: [AgentProvider: AgentCostMetrics]
        let credits: [AgentProvider: Double]
        let dailySpend: [AgentProvider: [AgentDailyCost]]
    }

    /// Runs on `queue`.
    nonisolated private var inputs: Inputs {
        Inputs(records: store.records.count, turns: store.turns, limits: store.limits, codexPlan: store.codexPlan,
               claudePlan: claudePlan, claudeOrganization: claudeOrganization, claudeApp: claudeAppSamples,
               identities: identities, costMetrics: cachedCostMetrics,
               credits: cachedCredits, dailySpend: cachedDailySpend)
    }

    /// Runs on `queue` and hands the finished snapshot to the main thread.
    nonisolated private func publish() {
        let session = readerSession
        guard session >= 0 else { return }
        var plans: [AgentProvider: AgentPlan] = [:]
        if let claudePlan { plans[.claude] = claudePlan }
        if let codex = AgentPlans.codex(planType: store.codexPlan) { plans[.codex] = codex }
        var next = store.snapshot(plans: plans, providers: enabled, now: Date())
        next.identities = identities
        next.credits = cachedCredits
        next.costMetrics = cachedCostMetrics
        next.dailySpend = cachedDailySpend
        published = next
        checkBudget(next)
        let checked = enabled.contains(.claude) ? claudeAppSamples.last(where: {
            claudeOrganization == nil || $0.organization == nil || $0.organization == claudeOrganization
        })?.date : nil
        let listed = AgentPricing.list.updated
        let prices = listed == AgentPriceList.empty.updated ? nil : listed
        DispatchQueue.main.async { [weak self] in
            guard let self, self.running, self.session == session else { return }
            if self.claudeAppChecked != checked { self.claudeAppChecked = checked }
            if self.pricesUpdated != prices { self.pricesUpdated = prices }
            if self.snapshot != next { self.snapshot = next }
        }
    }

    // MARK: Alerts

    /// Filters by the person's choices on the main thread, where they live.
    nonisolated
    private func report(_ event: AgentUsageEvent) {
        let session = readerSession
        DispatchQueue.main.async { [weak self] in
            guard let self, Self.delivers(event, queuedIn: session, running: self.running, session: self.session,
                                          providers: self.providers) else { return }
            self.events.send(event)
        }
    }

    /// Whether an event queued during reading `queued` still goes out: not
    /// after a stop or restart, nor past the person's choices.
    package static func delivers(_ event: AgentUsageEvent, queuedIn queued: Int, running: Bool, session: Int,
                                 providers: [AgentProvider], in defaults: UserDefaults = .standard) -> Bool {
        guard running, session == queued else { return false }
        switch event {
        case .finished(let provider, let duration, _, _, _):
            guard providers.contains(provider), let minimum = NotchAgentSupport.finishMinimum(in: defaults) else {
                return false
            }
            return duration >= minimum
        case .limitWarning(let provider, _), .limitReset(let provider, _):
            return providers.contains(provider) && NotchAgentSupport.limitThreshold(in: defaults) != nil
        case .budgetReached:
            return NotchAgentSupport.dailyBudget(in: defaults) != nil
        }
    }

    /// Runs on `queue` whenever limits may have changed.
    nonisolated private func checkLimits() {
        guard store.reportsTransitions else { return }
        let threshold = NotchAgentSupport.limitThreshold() ?? NotchAgentSupport.defaultLimitThreshold
        for (provider, limits) in store.limits {
            for window in AgentLimitSupport.crossings(previous: previousLimits[provider], current: limits,
                                                      threshold: threshold) {
                warned[window.id] = (provider, window)
                report(.limitWarning(provider: provider, window: window))
            }
        }
        // A banked reset renews a warned window before its time, which is
        // news now rather than at the renewal it replaced.
        for (id, entry) in warned {
            guard let window = store.limits[entry.provider]?.windows.first(where: { $0.id == id }),
                  let was = entry.window.resetsAt, let resets = window.resetsAt,
                  resets.timeIntervalSince(was) > 60, window.usedPercent < threshold else { continue }
            warned[id] = nil
            report(.limitReset(provider: entry.provider, window: window))
        }
        previousLimits = store.limits
    }

    /// A warned window that renews brings its agent back: worth a word.
    nonisolated private func reportRenewals(now: Date) {
        for (id, entry) in warned {
            guard let resets = entry.window.resetsAt, resets <= now else { continue }
            warned[id] = nil
            report(.limitReset(provider: entry.provider, window: entry.window))
        }
    }

    nonisolated private func checkBudget(_ snapshot: AgentUsageSnapshot) {
        guard store.reportsTransitions, let budget = NotchAgentSupport.dailyBudget() else { return }
        let today = Calendar.autoupdatingCurrent.startOfDay(for: snapshot.now)
        let spent = snapshot.usage(.today).total.cost
        guard spent >= budget, budgetDay != today else { return }
        budgetDay = today
        report(.budgetReached(spent: spent, budget: budget))
    }

    // MARK: Plans and limits

    /// The plan comes from the account profile Claude Code caches; nothing
    /// else in that file is kept.
    nonisolated private func readClaudePlan() {
        guard enabled.contains(.claude) else { return }
        let url = home.appending(path: ".claude.json")
        let modified = (try? url.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate
        guard modified != claudeProfileModified else { return }
        claudeProfileModified = modified
        guard let data = try? Data(contentsOf: url, options: .mappedIfSafe),
              let json = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
              let account = json["oauthAccount"] as? [String: Any] else {
            claudePlan = nil
            claudeOrganization = nil
            claudeAccountLimits = nil
            store.clearLimits(.claude)
            return
        }
        let organization = account["organizationUuid"] as? String
        if organization != claudeOrganization {
            claudeAccountLimits = nil
            store.clearLimits(.claude)
        }
        claudeOrganization = organization
        claudePlan = AgentPlans.claude(organizationType: account["organizationType"] as? String,
                                       rateLimitTier: account["organizationRateLimitTier"] as? String
                                        ?? account["userRateLimitTier"] as? String)
    }

    /// Reads the limits the Claude app saved when the file changes, and
    /// places them at `now` on every call, since a session ages out between
    /// saves. Runs on `queue`.
    nonisolated private func readClaudeApp(now: Date) {
        guard enabled.contains(.claude) else {
            store.clearLimits(.claude)
            claudeAccountLimits = nil
            claudeAppModified = nil
            claudeAppSamples = []
            return
        }
        let url = AgentClaudeAppUsage.historyURL(home: home)
        let modified = (try? url.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate
        if modified != claudeAppModified {
            claudeAppModified = modified
            claudeAppSamples = modified == nil ? []
                : (try? Data(contentsOf: url)).flatMap(AgentClaudeAppUsage.samples) ?? []
        }
        // Claude Code's own first request can place the session's start.
        let start = AgentClaudeAppUsage.sessionStart(store.records, samples: claudeAppSamples,
                                                     organization: claudeOrganization)
        identities[.claude] = AgentClaudeAppUsage.readIdentity(home: home)
        let desktop = AgentClaudeAppUsage.limits(from: claudeAppSamples, now: now, sessionStart: start,
                                                 organization: claudeOrganization)
        if let limits = Self.claudeLimits(desktop: desktop, account: claudeAccountLimits, now: now) {
            store.setLimits(limits)
        } else {
            store.clearLimits(.claude)
        }
    }

    /// Which Claude reading the page shows: the account's while it is
    /// recent, else the newer of it and the Claude app's history. The app's
    /// session renewal is the latest the session can end, so trading places
    /// with the exact one at each save the app makes would read as a new
    /// window and warn again. A newer app reading still keeps the account's
    /// exact renewals.
    nonisolated package static func claudeLimits(desktop: AgentLimits?, account: AgentLimits?, now: Date) -> AgentLimits? {
        let account = AgentClaudeServer.current(account, now: now)
        let recent = account.flatMap { now.timeIntervalSince($0.observedAt) < AgentClaudeAppUsage.freshness ? $0 : nil }
        guard let latest = recent ?? [desktop, account].compactMap({ $0 }).max(by: { $0.observedAt < $1.observedAt })
        else { return nil }
        return latest.source == .claudeApp ? AgentClaudeAppUsage.merged(latest, with: account, now: now) : latest
    }

    /// Probes live quota limits for Antigravity from the local daemon.
    /// Runs on `queue`.
    nonisolated private func readAntigravityQuota(now: Date, force: Bool = false) {
        guard enabled.contains(.antigravity) else { return }
        identities[.antigravity] = AgentAntigravityReader.probeIdentity(
            email: identities[.antigravity]?.email,
            planTier: identities[.antigravity]?.planTier ?? "Google AI Ultra"
        )
        if let limits = AgentAntigravityReader.probeQuota(force: force) {
            if store.limits[.antigravity] != limits {
                store.updateLimits(limits)
                checkLimits()
                schedulePublish()
            }
        }
    }

    nonisolated private static func findCodexBarPath() -> String? {
        let candidates = ["/opt/homebrew/bin/codexbar", "/usr/local/bin/codexbar"]
        for p in candidates {
            if FileManager.default.isExecutableFile(atPath: p) { return p }
        }
        return nil
    }

    /// Reads Claude and Antigravity cost metrics, credits, and live limits via CodexBar when present.
    /// Runs asynchronously on a background utility queue with single-flight guard to avoid stalling `queue`.
    nonisolated private func readCodexBarMetrics(now: Date) {
        guard enabled.contains(.claude) || enabled.contains(.antigravity) else { return }
        guard now.timeIntervalSince(lastCodexBarProbe) >= 300 || lastCodexBarProbe == .distantPast else { return }
        guard !isProbingCodexBar else { return }
        guard let codexbarPath = Self.findCodexBarPath() else { return }

        isProbingCodexBar = true
        lastCodexBarProbe = now
        let currentSession = readerSession
        let wantsClaude = enabled.contains(.claude)
        let wantsAntigravity = enabled.contains(.antigravity)

        DispatchQueue.global(qos: .utility).async { [weak self] in
            guard let self else { return }
            var newCostMetrics: [AgentProvider: AgentCostMetrics] = [:]
            var newDailySpend: [AgentProvider: [AgentDailyCost]] = [:]
            var newIdentities: [AgentProvider: AgentIdentity] = [:]
            var newClaudeLimits: AgentLimits? = nil
            var newAntigravityLimits: AgentLimits? = nil

            func runProcess(args: [String]) -> Data? {
                let proc = Process()
                proc.executableURL = URL(fileURLWithPath: codexbarPath)
                proc.arguments = args
                let pipe = Pipe()
                proc.standardOutput = pipe
                proc.standardError = FileHandle.nullDevice
                do {
                    try proc.run()
                    let data = pipe.fileHandleForReading.readDataToEndOfFile()
                    proc.waitUntilExit()
                    return proc.terminationStatus == 0 ? data : nil
                } catch {
                    return nil
                }
            }

            // 1. Claude cost and 30-day spend
            if wantsClaude, let data = runProcess(args: ["cost", "--provider", "claude", "--format", "json"]),
               let json = (try? JSONSerialization.jsonObject(with: data)) as? [[String: Any]],
               let first = json.first {
                let costUSD = (first["last30DaysCostUSD"] as? NSNumber)?.doubleValue ?? 0.0
                let tokens = (first["last30DaysTokens"] as? NSNumber)?.intValue ?? 0
                let sessionTokens = (first["sessionTokens"] as? NSNumber)?.intValue ?? 0
                let sessionCost = (first["sessionCostUSD"] as? NSNumber)?.doubleValue ?? 0.0
                var dailyCosts: [AgentDailyCost] = []
                var peakCost = 0.0
                var modelTokenTotals: [String: Int] = [:]

                if let daily = first["daily"] as? [[String: Any]] {
                    for day in daily {
                        guard let date = day["date"] as? String else { continue }
                        let dayCost = (day["totalCost"] as? NSNumber)?.doubleValue ?? 0.0
                        let dayTokens = (day["totalTokens"] as? NSNumber)?.intValue ?? 0
                        if dayCost > peakCost { peakCost = dayCost }

                        var dayTopModel: String? = nil
                        var dayTopCost = 0.0
                        if let breakdowns = day["modelBreakdowns"] as? [[String: Any]] {
                            for b in breakdowns {
                                let mName = (b["modelName"] as? String) ?? ""
                                let mTokens = (b["totalTokens"] as? NSNumber)?.intValue ?? 0
                                let mCost = (b["cost"] as? NSNumber)?.doubleValue ?? 0.0
                                if !mName.isEmpty {
                                    modelTokenTotals[mName, default: 0] += mTokens
                                    if mCost > dayTopCost {
                                        dayTopCost = mCost
                                        dayTopModel = mName
                                    }
                                }
                            }
                        }
                        dailyCosts.append(AgentDailyCost(date: date, cost: dayCost, tokens: dayTokens, topModel: dayTopModel))
                    }
                }

                let topModelName = modelTokenTotals.max { $0.value < $1.value }?.key
                let todayCost = sessionCost > 0 ? sessionCost : (dailyCosts.last?.cost ?? 0.0)

                newCostMetrics[.claude] = AgentCostMetrics(
                    todayCost: todayCost,
                    thirtyDayCost: costUSD,
                    latestTokens: sessionTokens,
                    thirtyDayTokens: tokens,
                    topModel: topModelName,
                    peakDayCost: peakCost > 0 ? peakCost : nil
                )
                if !dailyCosts.isEmpty {
                    newDailySpend[.claude] = dailyCosts
                }
            }

            // 2. Claude usage (for Fable & rate limits)
            if wantsClaude, let uData = runProcess(args: ["usage", "--provider", "claude", "--format", "json"]),
               let uJson = (try? JSONSerialization.jsonObject(with: uData)) as? [[String: Any]],
               let uFirst = uJson.first,
               let usageObj = uFirst["usage"] as? [String: Any] {
                var windows: [AgentLimitWindow] = []
                if let primary = usageObj["primary"] as? [String: Any] {
                    let used = (primary["usedPercent"] as? NSNumber)?.doubleValue ?? 0
                    let minutes = (primary["windowMinutes"] as? NSNumber)?.intValue ?? 300
                    let resetStr = (primary["resetsAt"] as? String) ?? ""
                    windows.append(AgentLimitWindow(id: "claude.fh", kind: .session, minutes: minutes, scope: nil, usedPercent: used, resetsAt: AgentTimestamp.parse(resetStr)))
                }
                if let secondary = usageObj["secondary"] as? [String: Any] {
                    let used = (secondary["usedPercent"] as? NSNumber)?.doubleValue ?? 0
                    let minutes = (secondary["windowMinutes"] as? NSNumber)?.intValue ?? 10080
                    let resetStr = (secondary["resetsAt"] as? String) ?? ""
                    windows.append(AgentLimitWindow(id: "claude.sd", kind: .weekly, minutes: minutes, scope: nil, usedPercent: used, resetsAt: AgentTimestamp.parse(resetStr)))
                }
                if let extras = usageObj["extraRateWindows"] as? [[String: Any]] {
                    for extra in extras {
                        let eId = (extra["id"] as? String) ?? ""
                        let title = (extra["title"] as? String) ?? ""
                        if let wObj = extra["window"] as? [String: Any] {
                            let used = (wObj["usedPercent"] as? NSNumber)?.doubleValue ?? 0
                            let minutes = (wObj["windowMinutes"] as? NSNumber)?.intValue ?? 10080
                            let resetStr = (wObj["resetsAt"] as? String) ?? ""
                            let kind: AgentLimitWindow.Kind = minutes <= 300 ? .session : .weekly
                            let scope = title.contains("Fable") ? "Fable" : (title.isEmpty ? nil : title)
                            windows.append(AgentLimitWindow(id: eId, kind: kind, minutes: minutes, scope: scope, usedPercent: used, resetsAt: AgentTimestamp.parse(resetStr)))
                        }
                    }
                }
                if !windows.isEmpty {
                    newClaudeLimits = AgentLimits(provider: .claude, windows: windows, observedAt: now, source: .account)
                }

                if let ident = (usageObj["identity"] as? [String: Any]) ?? (uFirst["identity"] as? [String: Any]) {
                    let email = (ident["accountEmail"] as? String) ?? (usageObj["accountEmail"] as? String)
                    let method = (ident["loginMethod"] as? String) ?? (usageObj["loginMethod"] as? String)
                    if email != nil || method != nil {
                        newIdentities[.claude] = AgentIdentity(email: email, planTier: method)
                    }
                }
            }

            // 3. Antigravity usage (for all 4 rate windows and identity)
            if wantsAntigravity, let agData = runProcess(args: ["usage", "--provider", "antigravity", "--format", "json"]),
               let agJson = (try? JSONSerialization.jsonObject(with: agData)) as? [[String: Any]],
               let agFirst = agJson.first,
               let agUsageObj = agFirst["usage"] as? [String: Any] {
                let email = (agUsageObj["accountEmail"] as? String)
                    ?? ((agUsageObj["identity"] as? [String: Any])?["accountEmail"] as? String)
                let loginMethod = (agUsageObj["loginMethod"] as? String)
                    ?? ((agUsageObj["identity"] as? [String: Any])?["loginMethod"] as? String)
                if email != nil || loginMethod != nil {
                    newIdentities[.antigravity] = AgentIdentity(email: email, planTier: loginMethod)
                }

                if let extras = agUsageObj["extraRateWindows"] as? [[String: Any]], !extras.isEmpty {
                    var windows: [AgentLimitWindow] = []
                    for extra in extras {
                        let eId = (extra["id"] as? String) ?? ""
                        let title = (extra["title"] as? String) ?? ""
                        if let wObj = extra["window"] as? [String: Any] {
                            let used = (wObj["usedPercent"] as? NSNumber)?.doubleValue ?? 0
                            let minutes = (wObj["windowMinutes"] as? NSNumber)?.intValue ?? 300
                            let resetStr = (wObj["resetsAt"] as? String) ?? ""
                            let kind: AgentLimitWindow.Kind = minutes <= 300 ? .session : .weekly
                            let scope: String? = (eId.contains("3p") || title.contains("Claude/GPT")) ? "Claude/GPT" : nil
                            windows.append(AgentLimitWindow(id: eId, kind: kind, minutes: minutes, scope: scope, usedPercent: used, resetsAt: AgentTimestamp.parse(resetStr)))
                        }
                    }
                    if !windows.isEmpty {
                        windows.sort { a, b in
                            func rank(_ id: String) -> Int {
                                if id.contains("gemini-5h") { return 0 }
                                if id.contains("gemini-weekly") { return 1 }
                                if id.contains("3p-5h") { return 2 }
                                if id.contains("3p-weekly") { return 3 }
                                return 4
                            }
                            let ra = rank(a.id), rb = rank(b.id)
                            return ra != rb ? ra < rb : a.id < b.id
                        }
                        newAntigravityLimits = AgentLimits(provider: .antigravity, windows: windows, observedAt: now, source: .account)
                    }
                }
            }

            let costMetrics = newCostMetrics
            let dailySpend = newDailySpend
            let identities = newIdentities
            let claudeLimits = newClaudeLimits
            let antigravityLimits = newAntigravityLimits

            self.queue.async {
                defer { self.isProbingCodexBar = false }
                guard self.readerSession == currentSession, currentSession >= 0 else { return }

                for (p, m) in costMetrics { self.cachedCostMetrics[p] = m }
                for (p, s) in dailySpend { self.cachedDailySpend[p] = s }
                for (p, id) in identities { self.identities[p] = id }

                if let cl = claudeLimits {
                    self.claudeAccountLimits = cl
                    var merged = cl.windows
                    if let existing = self.store.limits[.claude] {
                        for w in existing.windows {
                            if !merged.contains(where: { $0.id == w.id }) {
                                if let resets = w.resetsAt, resets > now {
                                    merged.append(w)
                                }
                            }
                        }
                    }
                    self.store.setLimits(AgentLimits(provider: .claude, windows: merged, observedAt: cl.observedAt, source: cl.source))
                }

                if let ag = antigravityLimits {
                    if (self.store.limits[.antigravity]?.windows ?? []).isEmpty {
                        self.store.setLimits(ag)
                    }
                }

                self.schedulePublish()
            }
        }
    }


    // Main thread. Never query while the feature is off, asleep or already
    // checking. Every minute only while the page shows; failures back off,
    // and looking at the page does not bypass that.
    func refreshClaudeLimits(now: Date = Date()) {
        guard running, !paused, providers.contains(.claude), claudeAccountRequest == nil else { return }
        let interval = AgentClaudeServer.interval(after: claudeAccountFailure, pageVisible: pageVisible)
        guard now.timeIntervalSince(claudeAccountAttempted) >= interval else { return }
        claudeAccountAttempted = now
        claudeAccountChecking = true
        let request = AgentClaudeServer.Request()
        claudeAccountRequest = request
        let session = self.session
        let home = self.home
        claudeAccountQueue.async { [weak self] in
            let result: Result<AgentClaudeServer.Summary, AgentClaudeServer.Failure>
            if let executable = AgentClaudeServer.executable(home: home, searchPath: ProcessInfo.processInfo.environment["PATH"]) {
                result = request.run(executable, home: home,
                    environment: AgentCodexServer.environment(for: executable, searchPath: nil))
            } else { result = .failure(.missing) }
            DispatchQueue.main.async {
                guard let self, self.running, !self.paused, self.session == session,
                      self.claudeAccountRequest === request else { return }
                self.claudeAccountRequest = nil
                self.claudeAccountChecking = false
                switch result {
                case .failure(let failure): self.claudeAccountFailure = failure
                case .success(let summary):
                    self.claudeAccountFailure = nil
                    self.queue.async {
                        guard self.readerSession == session, self.enabled.contains(.claude) else { return }
                        self.readClaudePlan()
                        guard self.claudeOrganization == summary.organization else { return }
                        self.claudeAccountLimits = summary.limits
                        self.readClaudeApp(now: Date())
                        self.checkLimits()
                        self.schedulePublish()
                    }
                }
            }
        }
    }

    private func cancelClaudeLimits() {
        guard let request = claudeAccountRequest else { return }
        request.cancel()
        claudeAccountRequest = nil
        claudeAccountChecking = false
        // Resume asks again instead of waiting out a cancelled check; with
        // none in flight, the wait after a failure still holds.
        claudeAccountAttempted = .distantPast
    }

    // MARK: Prices

    /// The newer of the list inside the app and the last one downloaded.
    /// Runs on `queue`.
    nonisolated private func loadPrices() {
        if shippedPrices == nil { shippedPrices = AgentPriceSource.bundled() }
        let cached = AgentPriceSource.cached()
        AgentPricing.install(AgentPriceList.newer(shippedPrices, cached?.list) ?? .empty)
        let saved = cached?.saved ?? .distantPast
        let session = readerSession
        DispatchQueue.main.async { [weak self] in
            guard let self, self.running, self.session == session else { return }
            self.pricesSaved = saved
            self.syncPrices()
        }
    }

    /// Looks for a newer price list at most once a day, and again a few hours
    /// after a failure. The last good list stays in use meanwhile.
    private func syncPrices() {
        guard running, NotchAgentSupport.updatesPrices(), !pricesInFlight, let saved = pricesSaved else { return }
        let now = Date()
        let wait = pricesFailed ? AgentPriceSource.retryInterval : AgentPriceSource.refreshInterval
        guard now.timeIntervalSince(saved) >= AgentPriceSource.refreshInterval,
              now.timeIntervalSince(pricesAttempted) >= wait else { return }
        pricesInFlight = true
        pricesAttempted = now
        let session = self.session
        AgentPriceSource.download { [weak self] result in
            DispatchQueue.main.async {
                guard let self, self.session == session else { return }
                self.pricesInFlight = false
                guard let result else {
                    self.pricesFailed = true
                    return
                }
                let (data, list) = result
                self.pricesFailed = false
                self.pricesSaved = Date()
                self.queue.async {
                    AgentPriceSource.save(data)
                    guard self.readerSession == session,
                          AgentPricing.install(AgentPriceList.newer(self.shippedPrices, list) ?? list) else { return }
                    self.store.reprice()
                    self.publish()
                }
            }
        }
    }
}
