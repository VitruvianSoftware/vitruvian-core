// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 VitruvianSoftware

import Foundation

/// The rules of design spec §5, as pure functions: how one relay event moves a
/// repository's state, and what colour a set of checks comes to. Nothing here
/// reads the clock; the caller passes `now`.
package enum GitHubReducer {
    /// A push's `after` when it deletes the branch.
    private static let zeroSHA = String(repeating: "0", count: 40)

    /// `state` after `event`.
    ///
    /// - An event for another repository, or with an id at or below the last
    ///   applied one, returns `state` unchanged.
    /// - A check, workflow run or status counts only on `main`'s current head
    ///   or a tracked PR's current head; for any other sha (a superseded push,
    ///   an untracked branch) it is dropped.
    /// - A push to the default branch with a new head resets the checks to no
    ///   data.
    /// - A pull request joins the set when the user wrote it, or the user or
    ///   one of their teams is a requested reviewer; it leaves when closed or
    ///   no longer any of those.
    package static func apply(_ event: GitHubEvent, to state: RepoState,
                              identity: GitHubIdentity, now: Date) -> RepoState {
        guard event.repo == state.repo else { return state }
        if let last = state.lastEventID, event.id <= last { return state }
        var next = state
        switch event.kind {
        case .checkRun(let run):
            record(CheckRun(key: "check_run:\(run.id)", name: run.name, headSHA: run.headSHA,
                            status: CheckStatus(raw: run.status), conclusion: run.conclusion.map(CheckConclusion.init(raw:)),
                            htmlURL: run.htmlURL), in: &next)
        case .workflowRun(let run):
            record(CheckRun(key: "workflow_run:\(run.id)", name: run.name, headSHA: run.headSHA,
                            status: CheckStatus(raw: run.status), conclusion: run.conclusion.map(CheckConclusion.init(raw:)),
                            htmlURL: run.htmlURL), in: &next)
        case .checkSuite(let suite):
            // A suite exists for every app with checks access, including ones
            // that never report, and stays queued forever; and its runs are
            // counted already. So only a finished suite's conclusion counts.
            if CheckStatus(raw: suite.status) == .completed, let conclusion = suite.conclusion {
                record(CheckRun(key: "check_suite:\(suite.id)", name: "check suite", headSHA: suite.headSHA,
                                status: .completed, conclusion: CheckConclusion(raw: conclusion), htmlURL: nil),
                       in: &next)
            }
        case .status(let status):
            let (checkStatus, conclusion) = mapCommitStatus(status.state)
            record(CheckRun(key: "status:\(status.context)", name: status.context, headSHA: status.sha,
                            status: checkStatus, conclusion: conclusion, htmlURL: status.targetURL), in: &next)
        case .push(let push):
            if push.ref == "refs/heads/\(state.defaultBranch)", push.after != zeroSHA, push.after != state.headSHA {
                next.headSHA = push.after
                next.checks = [:]
            }
        case .pullRequest(let change):
            applyPullRequest(change, to: &next, identity: identity)
        case .pullRequestReview(let review):
            applyReview(review, to: &next)
        case .unknown:
            break
        }
        next.lastEventID = event.id
        // `lastEventID` alone moving is not a change anyone sees.
        var compared = next
        compared.lastEventID = state.lastEventID
        if compared != state { next.updatedAt = now }
        return next
    }

    // MARK: - Verdicts

    /// Red if any check failed, timed out, was cancelled, needs action or went
    /// stale; else amber if any is queued, running, waiting, requested or
    /// pending; else green if there is at least one and all passed (success,
    /// neutral or skipped); else grey.
    package static func verdict(for checks: some Sequence<CheckRun>) -> Verdict {
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

    /// The colour of `main`; grey for a repository with no state.
    package static func verdict(for state: RepoState?) -> Verdict {
        guard let state else { return .grey }
        return verdict(for: state.checks.values)
    }

    /// The colour of a PR's own head.
    package static func verdict(for pullRequest: PullRequest) -> Verdict {
        verdict(for: pullRequest.checks.values)
    }

    /// For the mouse and the collapsed strip: red if any is red, else amber if
    /// any is amber, else green if all are green, else grey.
    package static func aggregate(_ verdicts: [Verdict]) -> Verdict {
        if verdicts.contains(.red) { return .red }
        if verdicts.contains(.amber) { return .amber }
        if !verdicts.isEmpty, verdicts.allSatisfy({ $0 == .green }) { return .green }
        return .grey
    }

    /// Whether any of the checks is paused for approval (`waiting`). Asked
    /// apart from the verdict, which a failed check beside it still makes red.
    package static func awaitsApproval(_ checks: some Sequence<CheckRun>) -> Bool {
        checks.contains { $0.status.isAwaitingApproval }
    }

    /// Whether `main`'s head or a tracked pull request's head has a check
    /// paused for approval; false for a repository with no state.
    package static func awaitsApproval(_ state: RepoState?) -> Bool {
        guard let state else { return false }
        return awaitsApproval(state.checks.values)
            || state.pullRequests.values.contains { awaitsApproval($0.checks.values) }
    }

    /// Whether a pull request is in the user's set: written by them, or their
    /// review or one of their teams' (in this repository's organisation) is
    /// requested.
    package static func concerns(_ pullRequest: PullRequest, in repo: RepoKey, identity: GitHubIdentity) -> Bool {
        if pullRequest.author.lowercased() == identity.login { return true }
        if pullRequest.requestedReviewers.contains(identity.login) { return true }
        let owner = repo.owner.lowercased()
        return pullRequest.requestedTeams.contains { identity.teams.contains("\(owner)/\($0)") }
    }

    // MARK: - Steps

    /// Puts a check on `main` and on each tracked PR whose head it is for.
    private static func record(_ check: CheckRun, in state: inout RepoState) {
        if let head = state.headSHA, check.headSHA == head {
            state.checks[check.key] = check
        }
        for (number, pr) in state.pullRequests where pr.headSHA == check.headSHA {
            state.pullRequests[number]?.checks[check.key] = check
        }
    }

    private static func mapCommitStatus(_ state: String) -> (CheckStatus, CheckConclusion?) {
        switch state.lowercased() {
        case "success": (.completed, .success)
        case "failure", "error": (.completed, .failure)
        case "pending": (.pending, nil)
        default: (.other(state), nil)
        }
    }

    private static func applyPullRequest(_ change: GitHubEvent.PullRequestChange, to state: inout RepoState,
                                         identity: GitHubIdentity) {
        if change.action == "closed" {
            state.pullRequests[change.number] = nil
            return
        }
        let existing = state.pullRequests[change.number]
        let sameHead = existing?.headSHA == change.headSHA
        let row = PullRequest(number: change.number, title: change.title, author: change.author,
                              headSHA: change.headSHA, isDraft: change.isDraft, htmlURL: change.htmlURL,
                              requestedReviewers: Set(change.requestedReviewers),
                              requestedTeams: Set(change.requestedTeams),
                              reviews: existing?.reviews ?? [:],
                              checks: sameHead ? existing?.checks ?? [:] : [:])
        state.pullRequests[change.number] = concerns(row, in: state.repo, identity: identity) ? row : nil
    }

    private static func applyReview(_ review: GitHubEvent.Review, to state: inout RepoState) {
        guard state.pullRequests[review.number] != nil else { return }
        let reviewer = review.reviewer.lowercased()
        if review.action == "dismissed" || review.state.lowercased() == "dismissed" {
            state.pullRequests[review.number]?.reviews[reviewer] = nil
            return
        }
        switch review.state.lowercased() {
        case "approved": state.pullRequests[review.number]?.reviews[reviewer] = .approved
        case "changes_requested": state.pullRequests[review.number]?.reviews[reviewer] = .changesRequested
        default: break // a comment changes no standing
        }
    }
}
