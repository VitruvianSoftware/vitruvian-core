// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 VitruvianSoftware

import Foundation

// The values behind the GitHub tool: which repositories, their checks on
// the default branch, the pull requests that concern the signed-in person,
// and the colour each comes to. Plain values; nothing here reads the clock
// or the network. They came from the Vitruvian app's GitHub feature
// (`Core/GitHub/GitHubModels.swift` and the verdict rules of
// `GitHubReducer.swift`), without the relay events the app no longer used.

/// A repository, `owner/name`. GitHub treats both parts without case, so two
/// keys that differ only in case are the same key; the spelling given first is
/// the one shown.
public struct RepoKey: Hashable, Sendable, Comparable, CustomStringConvertible {
    public let owner: String
    public let name: String

    public init(owner: String, name: String) {
        self.owner = owner
        self.name = name
    }

    /// `owner/name`, trimmed: exactly one slash with text on both sides.
    public init?(fullName: String) {
        let parts = fullName.trimmingCharacters(in: .whitespacesAndNewlines)
            .split(separator: "/", omittingEmptySubsequences: false)
        guard parts.count == 2, !parts[0].isEmpty, !parts[1].isEmpty,
              !parts.contains(where: { $0.contains(where: \.isWhitespace) }) else { return nil }
        self.init(owner: String(parts[0]), name: String(parts[1]))
    }

    public var fullName: String { "\(owner)/\(name)" }
    public var description: String { fullName }

    private var folded: String { fullName.lowercased() }

    public static func == (lhs: RepoKey, rhs: RepoKey) -> Bool { lhs.folded == rhs.folded }
    public func hash(into hasher: inout Hasher) { hasher.combine(folded) }
    public static func < (lhs: RepoKey, rhs: RepoKey) -> Bool { lhs.folded < rhs.folded }
}

/// Who is signed in: their login and the teams they belong to, each written
/// `org/team-slug`. Both are compared without case.
public struct GitHubIdentity: Sendable, Equatable {
    public let login: String
    public let teams: Set<String>

    public init(login: String, teams: Set<String>) {
        self.login = login.lowercased()
        self.teams = Set(teams.map { $0.lowercased() })
    }
}

/// Where a check run, a workflow run or a commit status stands. GitHub's raw
/// spellings, so a value the rules do not name survives as `.other`.
public enum CheckStatus: Sendable, Equatable {
    case queued, inProgress, completed, waiting, requested, pending
    case other(String)

    public init(raw: String) {
        switch raw.lowercased() {
        case "queued": self = .queued
        case "in_progress": self = .inProgress
        case "completed": self = .completed
        case "waiting": self = .waiting
        case "requested": self = .requested
        case "pending": self = .pending
        default: self = .other(raw)
        }
    }

    /// Still to run or running: amber when nothing is red.
    public var isRunning: Bool {
        switch self {
        case .queued, .inProgress, .waiting, .requested, .pending: true
        case .completed, .other: false
        }
    }

    /// Paused until someone lets it go on: a deployment protection rule
    /// holds the run back. It still counts as running, so the verdict stays
    /// amber; the mouse puts it first.
    public var isAwaitingApproval: Bool { self == .waiting }
}

/// How a finished check ended.
public enum CheckConclusion: Sendable, Equatable {
    case success, neutral, skipped
    case failure, timedOut, cancelled, actionRequired, stale, startupFailure
    case other(String)

    public init(raw: String) {
        switch raw.lowercased() {
        case "success": self = .success
        case "neutral": self = .neutral
        case "skipped": self = .skipped
        case "failure": self = .failure
        case "timed_out": self = .timedOut
        case "cancelled": self = .cancelled
        case "action_required": self = .actionRequired
        case "stale": self = .stale
        case "startup_failure": self = .startupFailure
        default: self = .other(raw)
        }
    }

    /// Red: cancelled counts as failed, and so does a workflow that could
    /// not start.
    public var isFailing: Bool {
        switch self {
        case .failure, .timedOut, .cancelled, .actionRequired, .stale, .startupFailure: true
        case .success, .neutral, .skipped, .other: false
        }
    }

    /// Counts toward green.
    public var isPassing: Bool {
        switch self {
        case .success, .neutral, .skipped: true
        default: false
        }
    }
}

/// One check on a commit: a check run or a workflow run. `key` is unique per
/// commit and source.
public struct CheckRun: Sendable, Equatable {
    public let key: String
    public var name: String
    public var headSHA: String
    public var status: CheckStatus
    public var conclusion: CheckConclusion?
    public var htmlURL: URL?
    /// For a workflow run, its id, which `rerun-failed-jobs` takes.
    public var workflowRunID: Int64?

    public init(key: String, name: String, headSHA: String, status: CheckStatus,
                conclusion: CheckConclusion?, htmlURL: URL?, workflowRunID: Int64? = nil) {
        self.key = key
        self.name = name
        self.headSHA = headSHA
        self.status = status
        self.conclusion = conclusion
        self.htmlURL = htmlURL
        self.workflowRunID = workflowRunID
    }
}

/// A pull request's review standing.
public enum ReviewState: Sendable, Equatable {
    case approved, changesRequested, pending
}

/// Where a pull request stands in the merge queue.
public struct MergeQueueState: Sendable, Equatable {
    /// Its 1-based position in the queue when GitHub gives one; nil when
    /// queued without a position.
    public var position: Int?

    public init(position: Int? = nil) {
        self.position = position
    }
}

/// An open pull request the signed-in person wrote or was asked to review.
public struct PullRequest: Sendable, Equatable {
    public let number: Int
    public var title: String
    public var author: String
    public var headSHA: String
    public var isDraft: Bool
    public var htmlURL: URL?
    /// Logins, lowercased.
    public var requestedReviewers: Set<String>
    /// Team slugs in the repository's organisation, lowercased.
    public var requestedTeams: Set<String>
    /// Each reviewer's latest approval or change request, by lowercased login.
    public var reviews: [String: ReviewState]
    /// The checks on `headSHA`, by `CheckRun.key`.
    public var checks: [String: CheckRun]
    /// Its standing in the merge queue; nil when it is not queued.
    public var mergeQueue: MergeQueueState?

    public init(number: Int, title: String, author: String, headSHA: String, isDraft: Bool,
                htmlURL: URL?, requestedReviewers: Set<String>, requestedTeams: Set<String>,
                reviews: [String: ReviewState] = [:], checks: [String: CheckRun] = [:],
                mergeQueue: MergeQueueState? = nil) {
        self.number = number
        self.title = title
        self.author = author
        self.headSHA = headSHA
        self.isDraft = isDraft
        self.htmlURL = htmlURL
        self.requestedReviewers = Set(requestedReviewers.map { $0.lowercased() })
        self.requestedTeams = Set(requestedTeams.map { $0.lowercased() })
        self.reviews = reviews
        self.checks = checks
        self.mergeQueue = mergeQueue
    }

    /// Changes requested by anyone outranks approvals; with neither, pending.
    public var reviewState: ReviewState {
        if reviews.values.contains(.changesRequested) { return .changesRequested }
        if reviews.values.contains(.approved) { return .approved }
        return .pending
    }
}

/// The colour a repository, a pull request or everything together comes to.
public enum Verdict: Sendable, Equatable, CaseIterable {
    case red, amber, green, grey
}

/// One watched repository: its default branch's head and that head's checks,
/// and the pull requests that concern the person. The REST snapshot builds it.
public struct RepoState: Sendable, Equatable {
    public let repo: RepoKey
    public var defaultBranch: String
    /// The default branch's head. Nil until a snapshot names it.
    public var headSHA: String?
    /// The checks on `headSHA`, by `CheckRun.key`.
    public var checks: [String: CheckRun]
    public var pullRequests: [Int: PullRequest]
    /// When the snapshot was taken, by the clock the caller gave.
    public var updatedAt: Date?

    public init(repo: RepoKey, defaultBranch: String, headSHA: String?,
                checks: [String: CheckRun] = [:], pullRequests: [Int: PullRequest] = [:],
                updatedAt: Date? = nil) {
        self.repo = repo
        self.defaultBranch = defaultBranch
        self.headSHA = headSHA
        self.checks = checks
        self.pullRequests = pullRequests
        self.updatedAt = updatedAt
    }
}

/// The rules that turn checks into a colour. Pure functions.
public enum Verdicts {
    /// Red if any check failed, timed out, was cancelled, needs action or went
    /// stale; else amber if any is queued, running, waiting, requested or
    /// pending; else green if there is at least one and all passed (success,
    /// neutral or skipped); else grey.
    public static func verdict(for checks: some Sequence<CheckRun>) -> Verdict {
        var any = false
        var running = false
        var allPassed = true
        for check in checks {
            any = true
            if check.conclusion?.isFailing == true { return .red }
            if check.status.isRunning {
                running = true
                allPassed = false
            } else if !(check.status == .completed && check.conclusion?.isPassing == true) {
                allPassed = false
            }
        }
        if running { return .amber }
        return any && allPassed ? .green : .grey
    }

    /// The colour of the default branch; grey for a repository with no state.
    public static func verdict(for state: RepoState?) -> Verdict {
        guard let state else { return .grey }
        return verdict(for: state.checks.values)
    }

    /// The colour of a pull request's own head.
    public static func verdict(for pullRequest: PullRequest) -> Verdict {
        verdict(for: pullRequest.checks.values)
    }

    /// For the mouse and the badge: red if any is red, else amber if any is
    /// amber, else green if all are green, else grey.
    public static func aggregate(_ verdicts: [Verdict]) -> Verdict {
        if verdicts.contains(.red) { return .red }
        if verdicts.contains(.amber) { return .amber }
        if !verdicts.isEmpty, verdicts.allSatisfy({ $0 == .green }) { return .green }
        return .grey
    }

    /// Whether any of the checks is paused for approval (`waiting`). Asked
    /// apart from the verdict, which a failed check beside it still makes red.
    public static func awaitsApproval(_ checks: some Sequence<CheckRun>) -> Bool {
        checks.contains { $0.status.isAwaitingApproval }
    }

    /// Whether the default branch's head or a pull request's head has a check
    /// paused for approval; false for a repository with no state.
    public static func awaitsApproval(_ state: RepoState?) -> Bool {
        guard let state else { return false }
        return awaitsApproval(state.checks.values)
            || state.pullRequests.values.contains { awaitsApproval($0.checks.values) }
    }

    /// Whether a pull request is the person's: written by them, or their
    /// review or one of their teams' (in this repository's organisation) is
    /// requested.
    public static func concerns(_ pullRequest: PullRequest, in repo: RepoKey, identity: GitHubIdentity) -> Bool {
        if pullRequest.author.lowercased() == identity.login { return true }
        if pullRequest.requestedReviewers.contains(identity.login) { return true }
        let owner = repo.owner.lowercased()
        return pullRequest.requestedTeams.contains { identity.teams.contains("\(owner)/\($0)") }
    }
}

/// What the island page, the badge and the mouse show: each watched
/// repository's colour and counts, the pull request rows, and the aggregate.
public struct GitHubSummary: Sendable, Equatable {
    public struct Repository: Sendable, Equatable {
        public let repo: RepoKey
        public let verdict: Verdict
        public let passed: Int
        public let failed: Int
        public let running: Int
        public let updatedAt: Date?
        /// The ids of the workflow runs that failed, for re-running them.
        public let failedRunIDs: [Int64]

        public init(repo: RepoKey, verdict: Verdict, passed: Int, failed: Int, running: Int, updatedAt: Date?,
                    failedRunIDs: [Int64]) {
            self.repo = repo
            self.verdict = verdict
            self.passed = passed
            self.failed = failed
            self.running = running
            self.updatedAt = updatedAt
            self.failedRunIDs = failedRunIDs
        }
    }

    public struct PullRequestRow: Sendable, Equatable {
        public let repo: RepoKey
        public let pullRequest: PullRequest
        public let verdict: Verdict

        public init(repo: RepoKey, pullRequest: PullRequest, verdict: Verdict) {
            self.repo = repo
            self.pullRequest = pullRequest
            self.verdict = verdict
        }
    }

    public let repositories: [Repository]
    /// Newest number first within a repository, repositories in watch order.
    public let pullRequests: [PullRequestRow]
    public let aggregate: Verdict
    /// Whether a check on a watched repository's default branch, or on one of
    /// the pull request rows, is paused for approval.
    public let awaitingApproval: Bool

    /// `watched` gives the order and the set; a watched repository with no
    /// state yet is grey, and a state for an unwatched one is left out.
    public init(states: [RepoKey: RepoState], watched: [RepoKey]) {
        var repositories: [Repository] = []
        var rows: [PullRequestRow] = []
        var awaitingApproval = false
        for repo in watched {
            let state = states[repo]
            if Verdicts.awaitsApproval(state) { awaitingApproval = true }
            let checks = state.map { Array($0.checks.values) } ?? []
            repositories.append(Repository(
                repo: repo,
                verdict: Verdicts.verdict(for: state),
                passed: checks.filter { $0.status == .completed && $0.conclusion?.isPassing == true }.count,
                failed: checks.filter { $0.conclusion?.isFailing == true }.count,
                running: checks.filter { $0.status.isRunning && $0.conclusion?.isFailing != true }.count,
                updatedAt: state?.updatedAt,
                failedRunIDs: checks.filter { $0.conclusion?.isFailing == true }.compactMap(\.workflowRunID).sorted()))
            for pr in (state?.pullRequests.values.sorted { $0.number > $1.number } ?? []) {
                rows.append(PullRequestRow(repo: repo, pullRequest: pr, verdict: Verdicts.verdict(for: pr)))
            }
        }
        self.repositories = repositories
        self.pullRequests = rows
        self.aggregate = Verdicts.aggregate(repositories.map(\.verdict))
        self.awaitingApproval = awaitingApproval
    }

    /// What the badge shows: the number of pull requests whose checks are
    /// red, plus the watched repositories whose default branch is red.
    public var badgeCount: Int {
        pullRequests.filter { $0.verdict == .red }.count + repositories.filter { $0.verdict == .red }.count
    }
}
