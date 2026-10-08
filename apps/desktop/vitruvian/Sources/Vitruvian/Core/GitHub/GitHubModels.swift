// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 VitruvianSoftware

import Foundation

// The values behind GitHub in the notch: which repositories, their checks on
// `main`, the pull requests that concern the signed-in user, and the colour
// each comes to. Plain values; `GitHubReducer` changes them, nothing here
// reads the clock or the network. Design: `docs/superpowers/specs/
// 2026-10-07-notch-github-feature-design.md`.

/// A repository, `owner/name`. GitHub treats both parts without case, so two
/// keys that differ only in case are the same key; the spelling given first is
/// the one shown.
package struct RepoKey: Hashable, Sendable, Comparable, CustomStringConvertible {
    package let owner: String
    package let name: String

    package init(owner: String, name: String) {
        self.owner = owner
        self.name = name
    }

    /// `owner/name`, trimmed: exactly one slash with text on both sides.
    package init?(fullName: String) {
        let parts = fullName.trimmingCharacters(in: .whitespacesAndNewlines)
            .split(separator: "/", omittingEmptySubsequences: false)
        guard parts.count == 2, !parts[0].isEmpty, !parts[1].isEmpty,
              !parts.contains(where: { $0.contains(where: \.isWhitespace) }) else { return nil }
        self.init(owner: String(parts[0]), name: String(parts[1]))
    }

    package var fullName: String { "\(owner)/\(name)" }
    package var description: String { fullName }

    private var folded: String { fullName.lowercased() }

    package static func == (lhs: RepoKey, rhs: RepoKey) -> Bool { lhs.folded == rhs.folded }
    package func hash(into hasher: inout Hasher) { hasher.combine(folded) }
    package static func < (lhs: RepoKey, rhs: RepoKey) -> Bool { lhs.folded < rhs.folded }
}

/// Who is signed in: their login and the teams they belong to, each written
/// `org/team-slug`. Both are compared without case.
package struct GitHubIdentity: Sendable, Equatable {
    package let login: String
    package let teams: Set<String>

    package init(login: String, teams: Set<String>) {
        self.login = login.lowercased()
        self.teams = Set(teams.map { $0.lowercased() })
    }
}

/// Where a check run, a workflow run or a commit status stands. GitHub's raw
/// spellings, so a value the rules do not name survives as `.other`.
package enum CheckStatus: Sendable, Equatable {
    case queued, inProgress, completed, waiting, requested, pending
    case other(String)

    package init(raw: String) {
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
    package var isRunning: Bool {
        switch self {
        case .queued, .inProgress, .waiting, .requested, .pending: true
        case .completed, .other: false
        }
    }
}

/// How a finished check ended.
package enum CheckConclusion: Sendable, Equatable {
    case success, neutral, skipped
    case failure, timedOut, cancelled, actionRequired, stale, startupFailure
    case other(String)

    package init(raw: String) {
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

    /// Red (decision 4: cancelled counts as failed). `startup_failure`, a
    /// workflow that could not start, is a failure too, though §5 does not
    /// list it.
    package var isFailing: Bool {
        switch self {
        case .failure, .timedOut, .cancelled, .actionRequired, .stale, .startupFailure: true
        case .success, .neutral, .skipped, .other: false
        }
    }

    /// Counts toward green.
    package var isPassing: Bool {
        switch self {
        case .success, .neutral, .skipped: true
        default: false
        }
    }
}

/// One check on a commit: a check run, a completed check suite, a workflow
/// run or a commit status. `key` is unique per commit and source (a status is
/// keyed by its context, so the latest per context wins).
package struct CheckRun: Sendable, Equatable {
    package let key: String
    package var name: String
    package var headSHA: String
    package var status: CheckStatus
    package var conclusion: CheckConclusion?
    package var htmlURL: URL?

    package init(key: String, name: String, headSHA: String, status: CheckStatus,
                 conclusion: CheckConclusion?, htmlURL: URL?) {
        self.key = key
        self.name = name
        self.headSHA = headSHA
        self.status = status
        self.conclusion = conclusion
        self.htmlURL = htmlURL
    }
}

/// A pull request's review standing, as the notch shows it.
package enum ReviewState: Sendable, Equatable {
    case approved, changesRequested, pending
}

/// An open pull request the signed-in user wrote or was asked to review.
package struct PullRequest: Sendable, Equatable {
    package let number: Int
    package var title: String
    package var author: String
    package var headSHA: String
    package var isDraft: Bool
    package var htmlURL: URL?
    /// Logins, lowercased.
    package var requestedReviewers: Set<String>
    /// Team slugs in the repository's organisation, lowercased.
    package var requestedTeams: Set<String>
    /// Each reviewer's latest approval or change request, by lowercased login.
    package var reviews: [String: ReviewState]
    /// The checks on `headSHA`, by `CheckRun.key`.
    package var checks: [String: CheckRun]

    package init(number: Int, title: String, author: String, headSHA: String, isDraft: Bool,
                 htmlURL: URL?, requestedReviewers: Set<String>, requestedTeams: Set<String>,
                 reviews: [String: ReviewState] = [:], checks: [String: CheckRun] = [:]) {
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
    }

    /// Changes requested by anyone outranks approvals; with neither, pending.
    package var reviewState: ReviewState {
        if reviews.values.contains(.changesRequested) { return .changesRequested }
        if reviews.values.contains(.approved) { return .approved }
        return .pending
    }
}

/// The colour a repository, a pull request or everything together comes to.
package enum Verdict: Sendable, Equatable, CaseIterable {
    case red, amber, green, grey
}

/// One watched repository: its default branch's head and that head's checks,
/// and the pull requests that concern the user. The REST snapshot builds it;
/// `GitHubReducer.apply` moves it forward one relay event at a time.
package struct RepoState: Sendable, Equatable {
    package let repo: RepoKey
    package var defaultBranch: String
    /// The default branch's head. Nil until a snapshot names it; no check
    /// counts before then.
    package var headSHA: String?
    /// The checks on `headSHA`, by `CheckRun.key`.
    package var checks: [String: CheckRun]
    package var pullRequests: [Int: PullRequest]
    /// The relay id of the last event applied; nil after a snapshot.
    package var lastEventID: UInt64?
    /// When the reducer last changed this state, by the clock it was given.
    package var updatedAt: Date?

    package init(repo: RepoKey, defaultBranch: String, headSHA: String?,
                 checks: [String: CheckRun] = [:], pullRequests: [Int: PullRequest] = [:],
                 lastEventID: UInt64? = nil, updatedAt: Date? = nil) {
        self.repo = repo
        self.defaultBranch = defaultBranch
        self.headSHA = headSHA
        self.checks = checks
        self.pullRequests = pullRequests
        self.lastEventID = lastEventID
        self.updatedAt = updatedAt
    }
}

/// What the notch and the mouse show: each watched repository's colour and
/// counts, the pull request rows, and the aggregate colour.
package struct GitHubSummary: Sendable, Equatable {
    package struct Repository: Sendable, Equatable {
        package let repo: RepoKey
        package let verdict: Verdict
        package let passed: Int
        package let failed: Int
        package let running: Int
        package let updatedAt: Date?
    }

    package struct PullRequestRow: Sendable, Equatable {
        package let repo: RepoKey
        package let pullRequest: PullRequest
        package let verdict: Verdict
    }

    package let repositories: [Repository]
    /// Newest number first within a repository, repositories in watch order.
    package let pullRequests: [PullRequestRow]
    package let aggregate: Verdict

    /// `watched` gives the order and the set; a watched repository with no
    /// state yet is grey, and a state for an unwatched one is left out.
    package init(states: [RepoKey: RepoState], watched: [RepoKey]) {
        var repositories: [Repository] = []
        var rows: [PullRequestRow] = []
        for repo in watched {
            let state = states[repo]
            let checks = state.map { Array($0.checks.values) } ?? []
            repositories.append(Repository(
                repo: repo,
                verdict: GitHubReducer.verdict(for: state),
                passed: checks.filter { $0.status == .completed && $0.conclusion?.isPassing == true }.count,
                failed: checks.filter { $0.conclusion?.isFailing == true }.count,
                running: checks.filter { $0.status.isRunning && $0.conclusion?.isFailing != true }.count,
                updatedAt: state?.updatedAt))
            for pr in (state?.pullRequests.values.sorted { $0.number > $1.number } ?? []) {
                rows.append(PullRequestRow(repo: repo, pullRequest: pr, verdict: GitHubReducer.verdict(for: pr)))
            }
        }
        self.repositories = repositories
        self.pullRequests = rows
        self.aggregate = GitHubReducer.aggregate(repositories.map(\.verdict))
    }
}
