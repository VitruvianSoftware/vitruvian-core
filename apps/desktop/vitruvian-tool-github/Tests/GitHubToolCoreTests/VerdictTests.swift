// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 VitruvianSoftware

import XCTest

@testable import GitHubToolCore

/// The colour rules, as the app's `GitHubCoreTests` held them.
final class VerdictTests: XCTestCase {
    static let repo = RepoKey(owner: "VitruvianSoftware", name: "vitruvian-core")
    static let head = "abc123"

    func check(_ id: Int64, sha: String = head, status: String = "completed", conclusion: String? = "success",
               runID: Int64? = nil) -> CheckRun {
        CheckRun(key: "check_run:\(id)", name: "ci", headSHA: sha, status: CheckStatus(raw: status),
                 conclusion: conclusion.map(CheckConclusion.init(raw:)), htmlURL: nil, workflowRunID: runID)
    }

    func state(_ checks: [CheckRun]) -> RepoState {
        RepoState(repo: Self.repo, defaultBranch: "main", headSHA: Self.head,
                  checks: Dictionary(uniqueKeysWithValues: checks.map { ($0.key, $0) }))
    }

    func testCancelledOnMainIsRedNotGreen() {
        XCTAssertEqual(Verdicts.verdict(for: [check(1), check(2, conclusion: "cancelled")]), .red)
    }

    func testEveryFailingConclusionIsRed() {
        for raw in ["failure", "timed_out", "cancelled", "action_required", "stale", "startup_failure"] {
            XCTAssertEqual(Verdicts.verdict(for: [check(1, conclusion: raw)]), .red, raw)
        }
    }

    func testRedWinsOverRunning() {
        XCTAssertEqual(Verdicts.verdict(for: [check(1, status: "in_progress", conclusion: nil),
                                              check(2, conclusion: "failure")]), .red)
    }

    func testEveryRunningStatusIsAmber() {
        for raw in ["queued", "in_progress", "waiting", "requested", "pending"] {
            XCTAssertEqual(Verdicts.verdict(for: [check(1), check(2, status: raw, conclusion: nil)]), .amber, raw)
        }
    }

    func testGreenNeedsAtLeastOneCheckAllPassing() {
        XCTAssertEqual(Verdicts.verdict(for: [CheckRun]()), .grey)
        XCTAssertEqual(Verdicts.verdict(for: [check(1), check(2, conclusion: "neutral"), check(3, conclusion: "skipped")]),
                       .green)
        XCTAssertEqual(Verdicts.verdict(for: [check(1, conclusion: "surprise")]), .grey, "an unknown conclusion is never green")
    }

    func testNoStateIsGrey() {
        XCTAssertEqual(Verdicts.verdict(for: nil as RepoState?), .grey)
        XCTAssertFalse(Verdicts.awaitsApproval(nil as RepoState?))
    }

    func testAggregateRanksRedAmberGreenGrey() {
        XCTAssertEqual(Verdicts.aggregate([.green, .amber, .red]), .red)
        XCTAssertEqual(Verdicts.aggregate([.green, .amber]), .amber)
        XCTAssertEqual(Verdicts.aggregate([.green, .green]), .green)
        XCTAssertEqual(Verdicts.aggregate([.green, .grey]), .grey)
        XCTAssertEqual(Verdicts.aggregate([]), .grey)
    }

    func testWaitingIsAwaitingApprovalAndApartFromTheVerdict() {
        let waiting = state([check(1, status: "waiting", conclusion: nil), check(2, conclusion: "failure")])
        XCTAssertTrue(Verdicts.awaitsApproval(waiting))
        XCTAssertEqual(Verdicts.verdict(for: waiting), .red, "a failed check beside the wait still makes it red")
        var pr = state([check(1)])
        pr.pullRequests[7] = PullRequest(number: 7, title: "t", author: "a", headSHA: "pr7", isDraft: false, htmlURL: nil,
                                         requestedReviewers: [], requestedTeams: [],
                                         checks: ["w": check(9, sha: "pr7", status: "waiting", conclusion: nil)])
        XCTAssertTrue(Verdicts.awaitsApproval(pr), "a pull request's wait counts too")
    }

    func testConcernsIsAuthoredOrReviewRequestedOrTeamRequested() {
        let me = GitHubIdentity(login: "James", teams: ["VitruvianSoftware/platform-team"])
        func pr(author: String = "someone", reviewers: Set<String> = [], teams: Set<String> = []) -> PullRequest {
            PullRequest(number: 1, title: "t", author: author, headSHA: "s", isDraft: false, htmlURL: nil,
                        requestedReviewers: reviewers, requestedTeams: teams)
        }
        XCTAssertTrue(Verdicts.concerns(pr(author: "james"), in: Self.repo, identity: me))
        XCTAssertTrue(Verdicts.concerns(pr(reviewers: ["JAMES"]), in: Self.repo, identity: me))
        XCTAssertTrue(Verdicts.concerns(pr(teams: ["Platform-Team"]), in: Self.repo, identity: me))
        XCTAssertFalse(Verdicts.concerns(pr(teams: ["platform-team"]), in: RepoKey(owner: "other", name: "x"), identity: me),
                       "a team is the repository's organisation's")
        XCTAssertFalse(Verdicts.concerns(pr(), in: Self.repo, identity: me))
    }

    func testSummaryCoversEveryWatchedRepositoryInOrderAndCountsTheBadge() {
        let other = RepoKey(owner: "acme", name: "web")
        var red = state([check(1, conclusion: "failure", runID: 500), check(2, status: "in_progress", conclusion: nil)])
        red.pullRequests[3] = PullRequest(number: 3, title: "t", author: "a", headSHA: "p3", isDraft: false, htmlURL: nil,
                                          requestedReviewers: [], requestedTeams: [],
                                          checks: ["f": check(8, sha: "p3", conclusion: "failure")])
        red.pullRequests[9] = PullRequest(number: 9, title: "u", author: "a", headSHA: "p9", isDraft: true, htmlURL: nil,
                                          requestedReviewers: [], requestedTeams: [])
        let summary = GitHubSummary(states: [Self.repo: red], watched: [other, Self.repo])
        XCTAssertEqual(summary.repositories.map(\.repo), [other, Self.repo])
        XCTAssertEqual(summary.repositories.map(\.verdict), [.grey, .red])
        XCTAssertEqual(summary.repositories[1].failed, 1)
        XCTAssertEqual(summary.repositories[1].running, 1)
        XCTAssertEqual(summary.repositories[1].failedRunIDs, [500])
        XCTAssertEqual(summary.pullRequests.map(\.pullRequest.number), [9, 3], "newest first")
        XCTAssertEqual(summary.pullRequests.map(\.verdict), [.grey, .red])
        XCTAssertEqual(summary.aggregate, .red)
        XCTAssertEqual(summary.badgeCount, 2, "one red pull request and one red default branch")
    }

    func testRepoKeyIsCaseless() {
        XCTAssertEqual(RepoKey(fullName: "Acme/Web"), RepoKey(owner: "acme", name: "web"))
        XCTAssertNil(RepoKey(fullName: "acme"))
        XCTAssertNil(RepoKey(fullName: "acme/"))
        XCTAssertNil(RepoKey(fullName: "a cme/web"))
        XCTAssertEqual(RepoKey(fullName: " acme/web ")?.fullName, "acme/web")
    }

    func testReviewStateChangesRequestedOutranksApproval() {
        var pr = PullRequest(number: 1, title: "t", author: "a", headSHA: "s", isDraft: false, htmlURL: nil,
                             requestedReviewers: [], requestedTeams: [])
        XCTAssertEqual(pr.reviewState, .pending)
        pr.reviews["b"] = .approved
        XCTAssertEqual(pr.reviewState, .approved)
        pr.reviews["c"] = .changesRequested
        XCTAssertEqual(pr.reviewState, .changesRequested)
    }
}
