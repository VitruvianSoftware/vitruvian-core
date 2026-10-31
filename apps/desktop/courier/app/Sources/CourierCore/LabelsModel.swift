// Copyright 2026 VitruvianSoftware
// SPDX-License-Identifier: AGPL-3.0-or-later

import Combine
import Foundation

/// Making, changing and deleting labels, and the auto-archive rules that go with spaces.
///
/// A label is a title, one of twelve system colours and one of 24 SF Symbols. The model checks all three before it
/// asks the engine, so a mistake reaches the person as a refusal at once and never as a failed call. A label's
/// place on the spaces bar is the engine's (`SpacesModel` reads it when a `spaces` change says it moved).
@MainActor
public final class LabelsModel: ObservableObject {
    /// The longest title, in characters.
    public static let maxTitle = 40
    /// Indexes into the system colours: red, orange, yellow, green, mint, teal, cyan, blue, indigo, purple, pink,
    /// brown.
    public static let colors = 0 ..< 12
    /// The SF Symbols a label can wear, in the order the picker shows them.
    public static let icons: [String] = [
        "tag", "star", "heart", "bolt", "flag", "bookmark", "briefcase", "house", "person.2", "cart", "airplane",
        "car", "book", "graduationcap", "gamecontroller", "music.note", "camera", "leaf", "pawprint",
        "cup.and.saucer", "fork.knife", "gift", "bell", "moon",
    ]

    /// Every auto-archive rule the engine has, as last read.
    @Published public private(set) var autoArchiveRules: [AutoArchiveRule] = []

    private let appModel: AppModel
    private let entitlement: any EntitlementProvider
    private weak var observedLifecycle: SystemLifecycleModel?
    private var lockObserver: AnyCancellable?
    /// Goes up with each read: an answer older than the newest read is dropped.
    private var readGeneration = 0

    /// - Parameter entitlement: what the person's plan includes. A rule is never asked of the engine without it.
    public init(
        appModel: AppModel,
        entitlement: any EntitlementProvider = AlwaysEntitled(),
        lifecycle: SystemLifecycleModel? = nil
    ) {
        self.appModel = appModel
        self.entitlement = entitlement
        self.observedLifecycle = lifecycle
        self.lockObserver = NotificationCenter.default
            .publisher(for: SystemLifecycleModel.didLockNotification)
            .sink { [weak self] notification in
                self?.observedLifecycle = notification.object as? SystemLifecycleModel
            }
        appModel.onConnect { [weak self] _ in self?.readRules() }
        appModel.onChange { [weak self] change in
            // Deleting a label takes its rule with it.
            if change == .spaces { self?.readRules() }
        }
        if appModel.client != nil { readRules() }
    }

    private var isLocked: Bool {
        observedLifecycle?.isLocked == true
    }

    private func ensureUnlocked() throws {
        guard !isLocked else {
            throw EngineError.rpc(.badValue, message: "Courier is locked", reason: "locked")
        }
    }

    /// Rules are part of a plan: the view shows "Available with a plan" in place of the controls when this is false.
    public var canAutoArchive: Bool { entitlement.isEntitled(.autoArchive) }

    // MARK: - Labels

    /// A title as the engine takes it: spaces at either end trimmed, and cut to `maxTitle` characters. The engine
    /// counts code points, so the cut keeps whole letters and goes under rather than over; trimming again leaves no
    /// space at the end of the cut.
    public static func clean(_ title: String) -> String {
        var kept = ""
        var scalars = 0
        for character in title.trimmingCharacters(in: .whitespacesAndNewlines) {
            let next = scalars + character.unicodeScalars.count
            guard next <= maxTitle else { break }
            kept.append(character)
            scalars = next
        }
        return kept.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Makes a label and answers its id. Its space joins the bar at the end.
    public func create(title: String, color: Int, icon: String) async throws -> Int64 {
        try ensureUnlocked()
        let title = try Self.checkedTitle(title)
        try Self.check(color: color)
        try Self.check(icon: icon)
        let result: LabelResult = try await call("labels.create", LabelParams(title: title, color: color, icon: icon))
        return result.labelID
    }

    /// Changes what is given; what is nil stays. With nothing to change, nothing is asked.
    public func update(_ id: Int64, title: String?, color: Int?, icon: String?) async throws {
        try ensureUnlocked()
        let title = try title.map(Self.checkedTitle)
        if let color { try Self.check(color: color) }
        if let icon { try Self.check(icon: icon) }
        guard title != nil || color != nil || icon != nil else { return }
        let _: Empty = try await call("labels.update", LabelUpdateParams(labelID: id, title: title, color: color, icon: icon))
    }

    /// Deletes a label: it comes off every chat, and its space and rule go with it. The view confirms first.
    public func delete(_ id: Int64) async throws {
        try ensureUnlocked()
        let _: Empty = try await call("labels.delete", LabelIDParams(labelID: id))
    }

    private static func checkedTitle(_ title: String) throws -> String {
        let cleaned = clean(title)
        guard !cleaned.isEmpty else { throw invalid("title") }
        return cleaned
    }

    private static func check(color: Int) throws {
        guard colors.contains(color) else { throw invalid("color") }
    }

    private static func check(icon: String) throws {
        guard icons.contains(icon) else { throw invalid("icon") }
    }

    /// The error the engine itself would answer, so a view has one kind of refusal to show.
    private static func invalid(_ parameter: String) -> EngineError {
        .rpc(.badValue, message: "invalid \(parameter)", reason: parameter)
    }

    // MARK: - Auto-archive rules

    /// The rule that sweeps a space: its "older than" rule. The inbox's has the scope "all". The General settings
    /// (after a reply, after a read) are rules of scope "all" too, but they are not a space's.
    public func rules(for spaceID: String) -> AutoArchiveRule? {
        let scope = spaceID == "inbox" ? "all" : spaceID
        return autoArchiveRules.first { $0.trigger == .olderThan && $0.scope == scope }
    }

    /// The ages an "older than" rule and the archive-all tool take, in days: 3 days to a year.
    public static let sweepAges = [3, 7, 14, 28, 90, 365]
    /// The age offered that is closest to `days` (the shorter one on a tie): how a rule stored with another age
    /// is shown, without changing it.
    public static func nearestSweepAge(_ days: Int) -> Int {
        sweepAges.min { abs($0 - days) < abs($1 - days) } ?? 28
    }

    /// The delays the General auto-archive rule (after I reply, after I read) takes, in minutes: none to a week.
    public static let generalDelays = [0, 1, 5, 10, 30, 60, 240, 1440, 10080]

    /// The General setting: one "after I reply" or "after I read" rule, scope "all". Nil is Never.
    public var generalRule: AutoArchiveRule? {
        autoArchiveRules.first { $0.scope == "all" && ($0.trigger == .afterReply || $0.trigger == .afterRead) }
    }

    /// Sets the General setting: after I reply or after I read, `minutes` later; nil is Never, which deletes the
    /// rule and the archives it had scheduled. After I read archives only chats left with nothing unread.
    public func setGeneral(_ trigger: AutoArchiveTrigger?, minutes: Int) async throws {
        let current = generalRule
        guard let trigger else {
            if let current { try await deleteRule(current.ruleID) }
            return
        }
        try await setRule(AutoArchiveRule(
            ruleID: current?.ruleID ?? 0, scope: "all", trigger: trigger,
            chatType: trigger == .afterRead ? .read : .all, durationMS: Int64(minutes) * 60_000, enabled: true))
    }

    /// Sets a space's "older than" rule: archive its chats (all, or only read ones) once their newest message is
    /// `days` old, or stop (`enabled` false; the rule is kept, so its choices are too).
    public func setSweep(for spaceID: String, chatType: AutoArchiveChatType, days: Int, enabled: Bool) async throws {
        try await setRule(AutoArchiveRule(
            ruleID: rules(for: spaceID)?.ruleID ?? 0, scope: spaceID == "inbox" ? "all" : spaceID, trigger: .olderThan,
            chatType: chatType, durationMS: Int64(days) * 86_400_000, enabled: enabled))
    }

    /// Saves a rule, new (rule id 0) or changed, and keeps it as the engine stored it. Part of a plan.
    public func setRule(_ rule: AutoArchiveRule) async throws {
        try ensureUnlocked()
        guard entitlement.isEntitled(.autoArchive) else {
            throw EngineError.rpc(.notEntitled, message: "auto-archive is not part of the plan", reason: nil)
        }
        let stored: AutoArchiveRule = try await call("autoArchive.set", rule)
        if let index = autoArchiveRules.firstIndex(where: { $0.ruleID == stored.ruleID }) {
            autoArchiveRules[index] = stored
        } else {
            autoArchiveRules.append(stored)
        }
    }

    /// Deletes a rule, and the archives it had scheduled.
    public func deleteRule(_ ruleID: Int64) async throws {
        try ensureUnlocked()
        let _: Empty = try await call("autoArchive.delete", RuleIDParams(ruleID: ruleID))
        autoArchiveRules.removeAll { $0.ruleID == ruleID }
    }

    /// How many chats the rule would archive right now: the engine's dry run of the same sweep. Only an "older than"
    /// rule sweeps what is there; "after a reply" and "after a read" act on what happens next, so for those it is 0.
    /// Nil when the count could not be had (the engine refused or did not answer): "couldn't check", not "0 chats".
    public func matchCount(for rule: AutoArchiveRule) async -> Int? {
        guard rule.trigger == .olderThan else { return 0 }
        guard let client = appModel.client else { return nil }
        let params = ArchiveMatchingParams(
            space: rule.scope == "all" ? nil : rule.scope, readOnly: rule.chatType == .read,
            olderThanMS: rule.durationMS, dryRun: true)
        let result: RoomsChanged? = try? await client.call("inbox.archiveMatching", params)
        return result?.roomIDs.count
    }

    private func readRules() {
        guard let client = appModel.client else { return }
        readGeneration += 1
        let generation = readGeneration
        Task { [weak self] in
            guard let result: RulesResult = try? await client.call("autoArchive.list", Empty()),
                  let self, client === self.appModel.client, generation == self.readGeneration else { return }
            self.autoArchiveRules = result.rules
        }
    }

    private func call<P: ProtocolType, R: ProtocolType>(_ method: String, _ params: P) async throws -> R {
        guard let client = appModel.client else { throw EngineError.notConnected }
        return try await client.call(method, params)
    }
}
