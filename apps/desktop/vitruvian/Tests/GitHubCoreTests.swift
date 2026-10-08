// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 VitruvianSoftware

import Foundation
import VitruvianCore
import VitruvianDesign
import VitruvianServices
import VitruvianUI

/// GitHub in the notch, Core layer: the relay's wire format, the reducer's
/// rules (design spec §5,
/// `docs/superpowers/specs/2026-10-07-notch-github-feature-design.md`), the
/// OAuth verifier/state and the device flow, and the preferences.
enum GitHubCoreTests {
    static func run(_ suite: TestSuite) {
        // §5 Verdict
        cancelledCheckOnMainIsRedNotGreen(suite)
        everyFailingConclusionIsRed(suite)
        redWinsOverRunningChecks(suite)
        everyRunningStatusIsAmber(suite)
        greenNeedsAtLeastOneCheckAllPassing(suite)
        noChecksOrUnknownRepositoryIsGrey(suite)
        unknownConclusionIsNeverGreen(suite)
        commitStatusesMapOntoTheSameRules(suite)
        checkSuitesNeverHoldTheVerdictAmber(suite)
        // §5 Aggregate
        aggregateRanksRedAmberGreenGrey(suite)
        // §5 Scope of main
        onlyChecksOnTheDefaultBranchHeadCount(suite)
        pushToDefaultBranchResetsChecksToNoData(suite)
        pushToAnotherBranchKeepsChecks(suite)
        pushOfTheKnownHeadKeepsChecks(suite)
        // §5 Ordering
        lateCheckForSupersededHeadIsDropped(suite)
        eventsApplyInRelayIdOrder(suite)
        eventForAnotherRepositoryIsIgnored(suite)
        // §5 PR set
        prSetIsAuthoredOrReviewRequestedOrTeamRequested(suite)
        prLeavesTheSetWhenNoLongerRelevant(suite)
        closedRemovesThePullRequestRow(suite)
        prRowCarriesItsOwnCheckVerdict(suite)
        prNewHeadResetsItsChecks(suite)
        reviewEventsUpdateTheReviewState(suite)
        // §5 Clock
        reducerTakesNowAsAnArgument(suite)
        // Summary
        summaryCoversEveryWatchedRepository(suite)
        // Wire format
        decodesEveryEventKind(suite)
        decodesResyncAndPing(suite)
        sseFramesParseIntoMessages(suite)
        malformedAndUnknownPayloadsAreSafe(suite)
        // OAuth
        oauthStateIsSha256OfVerifier(suite)
        oauthCallbackChecksState(suite)
        deviceFlowStateMachine(suite)
        // Preferences
        preferences(suite)
        // Frictionless Auth & Peripherals
        frictionlessAuthParsing(suite)
        peripheralSignalMapping(suite)
        // Notch Module & Quick Access
        notchModuleProperties(suite)
        notchContentEditorStyling(suite)
    }

    // MARK: - Fixtures

    static let repo = RepoKey(owner: "VitruvianSoftware", name: "vitruvian-core")
    static let me = GitHubIdentity(login: "james", teams: ["vitruviansoftware/platform"])
    static let t0 = Date(timeIntervalSince1970: 1_800_000_000)
    static let head = "aaaa"

    static func state(head: String? = head) -> RepoState {
        RepoState(repo: repo, defaultBranch: "main", headSHA: head)
    }

    static func check(_ id: Int64, sha: String = head, status: String = "completed",
                      conclusion: String? = "success", name: String = "build") -> GitHubEvent.Kind {
        .checkRun(.init(id: id, name: name, headSHA: sha, status: status, conclusion: conclusion, htmlURL: nil))
    }

    static func event(_ id: UInt64, _ kind: GitHubEvent.Kind, repo: RepoKey = repo) -> GitHubEvent {
        GitHubEvent(id: id, repo: repo, kind: kind)
    }

    /// Applies the kinds in order, numbering them from 1.
    static func reduce(_ kinds: [GitHubEvent.Kind], from start: RepoState = state(),
                       now: Date = t0) -> RepoState {
        var current = start
        for (index, kind) in kinds.enumerated() {
            current = GitHubReducer.apply(event(UInt64(index + 1), kind), to: current, identity: me, now: now)
        }
        return current
    }

    static func pr(_ number: Int, action: String = "opened", author: String = "someone",
                   sha: String = "pr-sha", reviewers: [String] = [], teams: [String] = [],
                   draft: Bool = false) -> GitHubEvent.Kind {
        .pullRequest(.init(action: action, number: number, title: "PR \(number)", author: author,
                           headSHA: sha, isDraft: draft, requestedReviewers: reviewers,
                           requestedTeams: teams, htmlURL: URL(string: "https://github.com/x/y/pull/\(number)")))
    }

    // MARK: - Verdict

    /// The PoC daemon (`tools/pipeline-status/pipeline-mouse-daemon.sh`) only
    /// counted "failed" and "in-flight", so a cancelled run fell through to
    /// solid green. Decision 4: cancelled is red.
    private static func cancelledCheckOnMainIsRedNotGreen(_ suite: TestSuite) {
        let result = reduce([check(1), check(2, conclusion: "cancelled", name: "deploy")])
        suite.expect(GitHubReducer.verdict(for: result) == .red,
                     "a cancelled check on main is red, not green: \(GitHubReducer.verdict(for: result))")
    }

    private static func everyFailingConclusionIsRed(_ suite: TestSuite) {
        for conclusion in ["failure", "timed_out", "cancelled", "action_required", "stale", "startup_failure"] {
            let result = reduce([check(1), check(2, conclusion: conclusion)])
            suite.expect(GitHubReducer.verdict(for: result) == .red, "\(conclusion) is red")
        }
    }

    private static func redWinsOverRunningChecks(_ suite: TestSuite) {
        let result = reduce([check(1, status: "in_progress", conclusion: nil), check(2, conclusion: "failure")])
        suite.expect(GitHubReducer.verdict(for: result) == .red, "a failure is red even while others still run")
    }

    private static func everyRunningStatusIsAmber(_ suite: TestSuite) {
        for status in ["queued", "in_progress", "waiting", "requested", "pending"] {
            let result = reduce([check(1), check(2, status: status, conclusion: nil)])
            suite.expect(GitHubReducer.verdict(for: result) == .amber, "\(status) with no failure is amber")
        }
    }

    private static func greenNeedsAtLeastOneCheckAllPassing(_ suite: TestSuite) {
        let result = reduce([check(1), check(2, conclusion: "neutral"), check(3, conclusion: "skipped")])
        suite.expect(GitHubReducer.verdict(for: result) == .green,
                     "success, neutral and skipped together are green")
        suite.expect(GitHubReducer.verdict(for: reduce([check(1)])) == .green, "one passing check is green")
    }

    private static func noChecksOrUnknownRepositoryIsGrey(_ suite: TestSuite) {
        suite.expect(GitHubReducer.verdict(for: state()) == .grey, "a repository with no checks yet is grey")
        suite.expect(GitHubReducer.verdict(for: nil as RepoState?) == .grey, "an unknown repository is grey")
        suite.expect(GitHubReducer.verdict(for: [CheckRun]()) == .grey, "no checks is grey")
    }

    private static func unknownConclusionIsNeverGreen(_ suite: TestSuite) {
        let result = reduce([check(1), check(2, conclusion: "something_new")])
        suite.expect(GitHubReducer.verdict(for: result) == .grey,
                     "a conclusion the rules do not name falls to grey, never green")
        let missing = reduce([check(1), check(2, status: "completed", conclusion: nil)])
        suite.expect(GitHubReducer.verdict(for: missing) == .grey, "a completed check without a conclusion is grey")
    }

    private static func commitStatusesMapOntoTheSameRules(_ suite: TestSuite) {
        func status(_ id: Int64, _ context: String, _ value: String) -> GitHubEvent.Kind {
            .status(.init(sha: head, context: context, state: value, targetURL: nil))
        }
        suite.expect(GitHubReducer.verdict(for: reduce([status(1, "ci", "success")])) == .green, "status success is green")
        suite.expect(GitHubReducer.verdict(for: reduce([status(1, "ci", "pending")])) == .amber, "status pending is amber")
        suite.expect(GitHubReducer.verdict(for: reduce([status(1, "ci", "failure")])) == .red, "status failure is red")
        suite.expect(GitHubReducer.verdict(for: reduce([status(1, "ci", "error")])) == .red, "status error is red")
        let latest = reduce([status(1, "ci", "failure"), status(2, "ci", "success")])
        suite.expect(GitHubReducer.verdict(for: latest) == .green && latest.checks.count == 1,
                     "the latest status per context replaces the earlier one")
    }

    private static func checkSuitesNeverHoldTheVerdictAmber(_ suite: TestSuite) {
        func checkSuite(_ status: String, _ conclusion: String?) -> GitHubEvent.Kind {
            .checkSuite(.init(id: 9, headSHA: head, status: status, conclusion: conclusion))
        }
        let queued = reduce([check(1), checkSuite("queued", nil)])
        suite.expect(GitHubReducer.verdict(for: queued) == .green,
                     "a check suite that never starts (an app that reports nothing) does not hold main amber")
        let failed = reduce([check(1), checkSuite("completed", "failure")])
        suite.expect(GitHubReducer.verdict(for: failed) == .red, "a completed failed check suite is red")
    }

    private static func aggregateRanksRedAmberGreenGrey(_ suite: TestSuite) {
        suite.expect(GitHubReducer.aggregate([.green, .grey, .amber, .red]) == .red, "any red makes the aggregate red")
        suite.expect(GitHubReducer.aggregate([.green, .grey, .amber]) == .amber, "else any amber makes it amber")
        suite.expect(GitHubReducer.aggregate([.green, .green]) == .green, "all green is green")
        suite.expect(GitHubReducer.aggregate([.green, .grey]) == .grey, "green with grey is grey")
        suite.expect(GitHubReducer.aggregate([]) == .grey, "nothing watched is grey")
    }

    // MARK: - Scope of main

    private static func onlyChecksOnTheDefaultBranchHeadCount(_ suite: TestSuite) {
        let result = reduce([check(1), check(2, sha: "feature-branch-sha", conclusion: "failure")])
        suite.expect(result.checks.count == 1 && GitHubReducer.verdict(for: result) == .green,
                     "a check on a sha that is neither main's head nor a tracked PR's is dropped")
        let unknownHead = reduce([check(1)], from: state(head: nil))
        suite.expect(unknownHead.checks.isEmpty, "before the snapshot names the head, no check counts")
    }

    private static func pushToDefaultBranchResetsChecksToNoData(_ suite: TestSuite) {
        let result = reduce([check(1, conclusion: "failure"),
                             .push(.init(ref: "refs/heads/main", before: head, after: "bbbb"))])
        suite.expect(result.headSHA == "bbbb" && result.checks.isEmpty
                     && GitHubReducer.verdict(for: result) == .grey,
                     "a push to main replaces the head and resets the checks to no data")
        let next = GitHubReducer.apply(event(9, check(5, sha: "bbbb", status: "queued", conclusion: nil)),
                                       to: result, identity: me, now: t0)
        suite.expect(GitHubReducer.verdict(for: next) == .amber, "the first event for the new head counts")
    }

    private static func pushToAnotherBranchKeepsChecks(_ suite: TestSuite) {
        let result = reduce([check(1), .push(.init(ref: "refs/heads/feature", before: "x", after: "y"))])
        suite.expect(result.headSHA == head && result.checks.count == 1, "a push to another branch changes nothing")
        let tag = reduce([check(1), .push(.init(ref: "refs/tags/main", before: "x", after: "y"))])
        suite.expect(tag.headSHA == head, "a tag named like the branch is not the branch")
        let deleted = reduce([check(1), .push(.init(ref: "refs/heads/main", before: head,
                                                     after: String(repeating: "0", count: 40)))])
        suite.expect(deleted.headSHA == head && deleted.checks.count == 1,
                     "a branch-deletion push (all-zero sha) is not a new head")
    }

    private static func pushOfTheKnownHeadKeepsChecks(_ suite: TestSuite) {
        let result = reduce([check(1), .push(.init(ref: "refs/heads/main", before: "zzzz", after: head))])
        suite.expect(result.checks.count == 1,
                     "a push whose head the snapshot already has does not wipe that snapshot's checks")
    }

    // MARK: - Ordering

    private static func lateCheckForSupersededHeadIsDropped(_ suite: TestSuite) {
        let result = reduce([.push(.init(ref: "refs/heads/main", before: head, after: "bbbb")),
                             check(1, sha: head, conclusion: "failure")])
        suite.expect(result.checks.isEmpty && GitHubReducer.verdict(for: result) == .grey,
                     "a late check for the superseded head is dropped")
    }

    private static func eventsApplyInRelayIdOrder(_ suite: TestSuite) {
        var current = GitHubReducer.apply(event(5, check(1, status: "completed", conclusion: "success")),
                                          to: state(), identity: me, now: t0)
        current = GitHubReducer.apply(event(5, check(1, status: "in_progress", conclusion: nil)),
                                      to: current, identity: me, now: t0)
        current = GitHubReducer.apply(event(4, check(1, status: "in_progress", conclusion: nil)),
                                      to: current, identity: me, now: t0)
        suite.expect(current.lastEventID == 5 && GitHubReducer.verdict(for: current) == .green,
                     "an id at or below the last applied one (a replayed duplicate) is dropped")
        current = GitHubReducer.apply(event(6, check(1, status: "in_progress", conclusion: nil)),
                                      to: current, identity: me, now: t0)
        suite.expect(current.lastEventID == 6 && GitHubReducer.verdict(for: current) == .amber,
                     "a later id for the same check replaces it (a re-run)")
    }

    private static func eventForAnotherRepositoryIsIgnored(_ suite: TestSuite) {
        let other = RepoKey(owner: "someone", name: "else")
        let result = GitHubReducer.apply(event(1, check(1, conclusion: "failure"), repo: other),
                                         to: state(), identity: me, now: t0)
        suite.expect(result == state(), "an event for another repository leaves this state untouched")
    }

    // MARK: - PR set

    private static func prSetIsAuthoredOrReviewRequestedOrTeamRequested(_ suite: TestSuite) {
        let result = reduce([pr(1, author: "James"),
                             pr(2, reviewers: ["james"]),
                             pr(3, teams: ["platform"]),
                             pr(4),
                             pr(5, teams: ["design"])])
        suite.expect(Set(result.pullRequests.keys) == [1, 2, 3],
                     "authored ∪ review requested ∪ team requested, nothing else: \(result.pullRequests.keys.sorted())")
        let foreign = GitHubReducer.apply(
            GitHubEvent(id: 1, repo: RepoKey(owner: "elsewhere", name: "r"), kind: pr(6, teams: ["platform"])),
            to: RepoState(repo: RepoKey(owner: "elsewhere", name: "r"), defaultBranch: "main", headSHA: head),
            identity: me, now: t0)
        suite.expect(foreign.pullRequests.isEmpty,
                     "a team is matched within the repository's own organisation, not by slug alone")
    }

    private static func prLeavesTheSetWhenNoLongerRelevant(_ suite: TestSuite) {
        let result = reduce([pr(2, reviewers: ["james"]), pr(2, action: "review_request_removed")])
        suite.expect(result.pullRequests.isEmpty, "a PR I neither wrote nor was asked to review leaves the set")
    }

    private static func closedRemovesThePullRequestRow(_ suite: TestSuite) {
        let result = reduce([pr(1, author: "james"), pr(1, action: "closed", author: "james")])
        suite.expect(result.pullRequests.isEmpty, "closed removes the row")
    }

    private static func prRowCarriesItsOwnCheckVerdict(_ suite: TestSuite) {
        let result = reduce([check(1), pr(1, author: "james", sha: "pr-sha"),
                             check(2, sha: "pr-sha", conclusion: "cancelled")])
        suite.expect(GitHubReducer.verdict(for: result) == .green, "a PR's check does not touch main's verdict")
        suite.expect(result.pullRequests[1].map(GitHubReducer.verdict(for:)) == .red,
                     "the PR row's verdict follows its own head's checks, with the same rules")
    }

    private static func prNewHeadResetsItsChecks(_ suite: TestSuite) {
        let result = reduce([pr(1, author: "james", sha: "old"), check(2, sha: "old", conclusion: "failure"),
                             pr(1, action: "synchronize", author: "james", sha: "new"),
                             check(3, sha: "old", conclusion: "failure")])
        suite.expect(result.pullRequests[1]?.headSHA == "new" && result.pullRequests[1]?.checks.isEmpty == true,
                     "a new PR head resets its checks and drops the old head's late checks")
    }

    private static func reviewEventsUpdateTheReviewState(_ suite: TestSuite) {
        func review(_ reviewer: String, _ state: String, action: String = "submitted") -> GitHubEvent.Kind {
            .pullRequestReview(.init(action: action, number: 1, reviewer: reviewer, state: state))
        }
        let opened = reduce([pr(1, author: "james")])
        suite.expect(opened.pullRequests[1]?.reviewState == .pending, "a new PR's review is pending")
        let approved = reduce([pr(1, author: "james"), review("ana", "approved")])
        suite.expect(approved.pullRequests[1]?.reviewState == .approved, "an approval makes it approved")
        let changes = reduce([pr(1, author: "james"), review("ana", "approved"), review("bo", "changes_requested")])
        suite.expect(changes.pullRequests[1]?.reviewState == .changesRequested,
                     "any reviewer's requested changes outrank another's approval")
        let commented = reduce([pr(1, author: "james"), review("ana", "approved"), review("ana", "commented")])
        suite.expect(commented.pullRequests[1]?.reviewState == .approved, "a comment does not undo an approval")
        let dismissed = reduce([pr(1, author: "james"), review("ana", "approved"),
                                review("ana", "dismissed", action: "dismissed")])
        suite.expect(dismissed.pullRequests[1]?.reviewState == .pending, "a dismissed review goes back to pending")
        let draft = reduce([pr(1, author: "james", draft: true)])
        suite.expect(draft.pullRequests[1]?.isDraft == true, "the row carries draft")
        let untracked = reduce([review("ana", "approved")])
        suite.expect(untracked.pullRequests.isEmpty, "a review on an untracked PR adds no row")
    }

    private static func reducerTakesNowAsAnArgument(_ suite: TestSuite) {
        let later = t0.addingTimeInterval(90)
        let result = reduce([check(1)], now: later)
        suite.expect(result.updatedAt == later, "the reducer stamps the time it is given, not the wall clock")
        let unchanged = GitHubReducer.apply(event(1, check(1, sha: "nope")), to: state(), identity: me, now: later)
        suite.expect(unchanged.updatedAt == nil, "a dropped event changes no time")
    }

    // MARK: - Summary

    private static func summaryCoversEveryWatchedRepository(_ suite: TestSuite) {
        let other = RepoKey(owner: "VitruvianSoftware", name: "other")
        let core = reduce([check(1), check(2, status: "in_progress", conclusion: nil),
                           pr(7, author: "james"), check(3, sha: "pr-sha", conclusion: "failure")])
        let summary = GitHubSummary(states: [repo: core], watched: [repo, other])
        suite.expect(summary.repositories.map(\.repo) == [repo, other], "one entry per watched repository, in order")
        suite.expect(summary.repositories.first?.verdict == .amber
                     && summary.repositories.first?.passed == 1 && summary.repositories.first?.running == 1
                     && summary.repositories.first?.failed == 0,
                     "each entry carries its verdict and check counts")
        suite.expect(summary.repositories.last?.verdict == .grey, "a watched repository with no state is grey")
        suite.expect(summary.aggregate == .amber, "the aggregate follows the repositories' verdicts")
        suite.expect(summary.pullRequests.map(\.pullRequest.number) == [7]
                     && summary.pullRequests.first?.verdict == .red, "PR rows carry their own verdict")
        let unwatched = GitHubSummary(states: [repo: core], watched: [other])
        suite.expect(unwatched.pullRequests.isEmpty, "an unwatched repository's state is not shown")
    }

    // MARK: - Wire format

    private static func decode(_ json: String, event: String? = "github") -> GitHubStreamMessage? {
        GitHubStreamMessage.decode(event: event, data: json)
    }

    private static func decodesEveryEventKind(_ suite: TestSuite) {
        let fixtures: [(String, GitHubEvent.Kind)] = [
            (#"{"id":"1","repo":"VitruvianSoftware/vitruvian-core","kind":"check_run","payload":{"id":11,"name":"build","head_sha":"aaaa","status":"completed","conclusion":"cancelled","html_url":"https://github.com/x/y/runs/11"}}"#,
             .checkRun(.init(id: 11, name: "build", headSHA: "aaaa", status: "completed", conclusion: "cancelled",
                             htmlURL: URL(string: "https://github.com/x/y/runs/11")))),
            (#"{"id":"2","repo":"VitruvianSoftware/vitruvian-core","kind":"check_suite","payload":{"id":12,"head_sha":"aaaa","status":"queued","conclusion":null}}"#,
             .checkSuite(.init(id: 12, headSHA: "aaaa", status: "queued", conclusion: nil))),
            (#"{"id":"3","repo":"VitruvianSoftware/vitruvian-core","kind":"workflow_run","payload":{"id":13,"name":"CI","head_sha":"aaaa","status":"in_progress","conclusion":null,"html_url":null}}"#,
             .workflowRun(.init(id: 13, name: "CI", headSHA: "aaaa", status: "in_progress", conclusion: nil, htmlURL: nil))),
            (#"{"id":"4","repo":"VitruvianSoftware/vitruvian-core","kind":"pull_request","payload":{"action":"opened","number":7,"title":"Add x","author":"james","head_sha":"bbbb","draft":true,"requested_reviewers":["ana"],"requested_teams":["platform"],"html_url":"https://github.com/x/y/pull/7"}}"#,
             .pullRequest(.init(action: "opened", number: 7, title: "Add x", author: "james", headSHA: "bbbb",
                                isDraft: true, requestedReviewers: ["ana"], requestedTeams: ["platform"],
                                htmlURL: URL(string: "https://github.com/x/y/pull/7")))),
            (#"{"id":"5","repo":"VitruvianSoftware/vitruvian-core","kind":"pull_request_review","payload":{"action":"submitted","number":7,"reviewer":"ana","state":"approved"}}"#,
             .pullRequestReview(.init(action: "submitted", number: 7, reviewer: "ana", state: "approved"))),
            (#"{"id":"6","repo":"VitruvianSoftware/vitruvian-core","kind":"status","payload":{"sha":"aaaa","context":"ci/x","state":"error","target_url":null}}"#,
             .status(.init(sha: "aaaa", context: "ci/x", state: "error", targetURL: nil))),
            (#"{"id":"7","repo":"VitruvianSoftware/vitruvian-core","kind":"push","payload":{"ref":"refs/heads/main","before":"aaaa","after":"bbbb"}}"#,
             .push(.init(ref: "refs/heads/main", before: "aaaa", after: "bbbb"))),
        ]
        for (index, (json, kind)) in fixtures.enumerated() {
            let expected = GitHubStreamMessage.event(GitHubEvent(id: UInt64(index + 1), repo: repo, kind: kind))
            let decoded = decode(json)
            suite.expect(decoded == expected, "fixture \(index + 1) decodes: \(String(describing: decoded))")
        }
        suite.expect(decode(fixtures[0].0, event: nil) != nil, "a frame without an event name is a GitHub event")
    }

    private static func decodesResyncAndPing(_ suite: TestSuite) {
        suite.expect(decode("{}", event: "resync") == .resync, "event: resync is a resync")
        suite.expect(decode("", event: "resync") == .resync, "a resync needs no data")
        suite.expect(decode("", event: "ping") == .ping, "event: ping is a ping")
    }

    private static func sseFramesParseIntoMessages(_ suite: TestSuite) {
        var parser = GitHubSSEParser()
        let lines = [
            ": ping",
            "id: 41",
            "event: github",
            #"data: {"id":"41","repo":"VitruvianSoftware/vitruvian-core","#,
            #"data: "kind":"push","payload":{"ref":"refs/heads/main","before":"a","after":"b"}}"#,
            "",
            "event: resync",
            "data: {}",
            "",
        ]
        let messages = lines.compactMap { parser.feed(line: $0) }
        suite.expect(messages.count == 3 && messages[0] == .ping, "a comment line is a ping: \(messages)")
        if messages.count == 3 {
            suite.expect(messages[1] == .event(GitHubEvent(id: 41, repo: repo,
                                                           kind: .push(.init(ref: "refs/heads/main", before: "a", after: "b")))),
                         "multi-line data joins with a newline and decodes on the blank line")
            suite.expect(messages[2] == .resync, "a resync frame decodes")
        }
        suite.expect(parser.lastEventID == "41", "the parser keeps the last id for Last-Event-ID")
        var crlf = GitHubSSEParser()
        _ = crlf.feed(line: "event: resync\r")
        suite.expect(crlf.feed(line: "\r") == .resync, "CRLF line endings parse")
    }

    private static func malformedAndUnknownPayloadsAreSafe(_ suite: TestSuite) {
        suite.expect(decode("not json") == nil, "malformed JSON decodes to nothing")
        suite.expect(decode(#"{"id":"1","repo":"nope","kind":"push","payload":{}}"#) == nil,
                     "a repository that is not owner/repo decodes to nothing")
        suite.expect(decode(#"{"id":"x","repo":"a/b","kind":"push","payload":{"ref":"r","before":"a","after":"b"}}"#) == nil,
                     "a non-numeric id decodes to nothing")
        let future = decode(#"{"id":"2","repo":"a/b","kind":"discussion","payload":{"x":1}}"#)
        suite.expect(future == .event(GitHubEvent(id: 2, repo: RepoKey(owner: "a", name: "b"), kind: .unknown("discussion"))),
                     "an unknown kind decodes as unknown, for the reducer to ignore")
        if case .event(let unknown)? = future {
            let after = GitHubReducer.apply(unknown, to: RepoState(repo: RepoKey(owner: "a", name: "b"),
                                                                   defaultBranch: "main", headSHA: "h"),
                                            identity: me, now: t0)
            suite.expect(after.checks.isEmpty && after.pullRequests.isEmpty && after.lastEventID == 2,
                         "an unknown kind changes nothing but the last id")
        }
        suite.expect(RepoKey(fullName: "a/b/c") == nil && RepoKey(fullName: "/b") == nil
                     && RepoKey(fullName: " Owner/Repo ") == RepoKey(owner: "owner", name: "repo"),
                     "owner/repo parses strictly, trims, and compares without case")
    }

    // MARK: - OAuth

    private static func oauthStateIsSha256OfVerifier(_ suite: TestSuite) {
        // RFC 7636 appendix B: these 32 bytes give this verifier and challenge.
        let rfcBytes: [UInt8] = [116, 24, 223, 180, 151, 153, 224, 37, 79, 250, 96, 125, 216, 173,
                                 187, 186, 22, 212, 37, 77, 105, 214, 191, 240, 91, 88, 5, 88, 83,
                                 132, 141, 121]
        var requested: [Int] = []
        let oauth = GitHubOAuthState.generate { count in requested.append(count); return rfcBytes }
        suite.expect(requested == [32], "the verifier is 32 random bytes")
        suite.expect(oauth.verifier == "dBjftJeZ4CVP-mB92K27uhbUJU1p1r_wW1gFWFOEjXk", // gitleaks:allow
                     "the verifier is base64url without padding: \(oauth.verifier)")
        suite.expect(oauth.state == "E9Melhoa2OwvFrEMTJguCHaoeK1t8URWbuGJSstw-cM", // gitleaks:allow
                     "state = base64url(sha256(verifier)), the RFC 7636 S256 challenge: \(oauth.state)")
        suite.expect(GitHubOAuthState.challenge(for: oauth.verifier) == oauth.state, "the relay's check holds")
        let random = GitHubOAuthState.generate()
        suite.expect(random.verifier.count == 43 && random != GitHubOAuthState.generate(),
                     "the system source gives a fresh 43-character verifier each time")
        let url = oauth.authorizeURL(clientID: "Iv1.abc", redirectURI: GitHubOAuthState.redirectURI)
        let items = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? []
        suite.expect(url.host == "github.com" && url.path == "/login/oauth/authorize"
                     && items.contains(URLQueryItem(name: "client_id", value: "Iv1.abc"))
                     && items.contains(URLQueryItem(name: "state", value: oauth.state))
                     && items.contains(URLQueryItem(name: "redirect_uri", value: "vitruvian://github/callback"))
                     && !items.contains { $0.name == "code_challenge" },
                     "the authorize URL carries client id, state and the callback, and no PKCE unless asked: \(url)")
        let pkce = oauth.authorizeURL(clientID: "Iv1.abc", redirectURI: GitHubOAuthState.redirectURI, pkce: true)
        let pkceItems = URLComponents(url: pkce, resolvingAgainstBaseURL: false)?.queryItems ?? []
        suite.expect(pkceItems.contains(URLQueryItem(name: "code_challenge", value: oauth.state))
                     && pkceItems.contains(URLQueryItem(name: "code_challenge_method", value: "S256")),
                     "with PKCE on, the state doubles as GitHub's S256 code challenge")
    }

    private static func oauthCallbackChecksState(_ suite: TestSuite) {
        let oauth = GitHubOAuthState.generate { _ in [UInt8](repeating: 7, count: 32) }
        func callback(_ query: String) -> Result<String, GitHubOAuthError> {
            oauth.code(fromCallback: URL(string: "vitruvian://github/callback?\(query)")!)
        }
        suite.expect(callback("code=abc&state=\(oauth.state)") == .success("abc"), "a matching state yields the code")
        suite.expect(callback("code=abc&state=forged") == .failure(.stateMismatch), "a forged state is refused")
        suite.expect(callback("state=\(oauth.state)") == .failure(.missingCode), "no code is an error")
        suite.expect(callback("error=access_denied&state=\(oauth.state)") == .failure(.denied),
                     "the user saying no is its own outcome")
        suite.expect(oauth.code(fromCallback: URL(string: "https://evil.example/github/callback?code=a&state=\(oauth.state)")!)
                     == .failure(.wrongCallback), "a callback on another URL is refused")
        suite.expect("\(GitHubAccessToken("gho_secret"))".contains("gho_secret") == false,
                     "a token never prints its value")
    }

    private static func deviceFlowStateMachine(_ suite: TestSuite) {
        let code = GitHubDeviceCode(deviceCode: "dev", userCode: "WDJB-MJHT",
                                    verificationURI: URL(string: "https://github.com/login/device")!,
                                    expiresIn: 900, interval: 5)
        var flow = GitHubDeviceFlowState.idle.next(.start, now: t0)
        suite.expect(flow == .requestingCode, "start asks for a code")
        flow = flow.next(.codeIssued(code), now: t0)
        guard case .awaitingUser(let waiting) = flow else {
            suite.expect(false, "a code waits for the user: \(flow)"); return
        }
        suite.expect(waiting.userCode == "WDJB-MJHT" && waiting.nextPollAt == t0.addingTimeInterval(5)
                     && waiting.expiresAt == t0.addingTimeInterval(900), "the first poll waits one interval")
        suite.expect(!flow.shouldPoll(now: t0.addingTimeInterval(4)) && flow.shouldPoll(now: t0.addingTimeInterval(5)),
                     "polling waits for the interval")
        flow = flow.next(.poll(GitHubDeviceFlowPollResult(errorCode: "authorization_pending")), now: t0.addingTimeInterval(5))
        if case .awaitingUser(let pending) = flow {
            suite.expect(pending.nextPollAt == t0.addingTimeInterval(10), "pending polls again after the interval")
        } else { suite.expect(false, "pending keeps waiting: \(flow)") }
        flow = flow.next(.poll(GitHubDeviceFlowPollResult(errorCode: "slow_down")), now: t0.addingTimeInterval(10))
        if case .awaitingUser(let slowed) = flow {
            suite.expect(slowed.interval == 10 && slowed.nextPollAt == t0.addingTimeInterval(20),
                         "slow_down adds 5 s to the interval (RFC 8628 §3.5)")
        } else { suite.expect(false, "slow_down keeps waiting: \(flow)") }
        let authorized = flow.next(.poll(.token(GitHubAccessToken("gho_x"))), now: t0.addingTimeInterval(20))
        suite.expect(authorized == .authorized(GitHubAccessToken("gho_x")), "a token ends the flow")
        suite.expect(flow.next(.poll(GitHubDeviceFlowPollResult(errorCode: "access_denied")), now: t0) == .failed(.denied),
                     "access_denied fails as denied")
        suite.expect(flow.next(.poll(GitHubDeviceFlowPollResult(errorCode: "expired_token")), now: t0) == .failed(.expired),
                     "expired_token fails as expired")
        suite.expect(flow.next(.tick, now: t0.addingTimeInterval(900)) == .failed(.expired)
                     && !flow.shouldPoll(now: t0.addingTimeInterval(900)),
                     "the code expires on our own clock too")
        suite.expect(flow.next(.poll(GitHubDeviceFlowPollResult(errorCode: "device_flow_disabled")), now: t0)
                     == .failed(.other("device_flow_disabled")), "any other error fails with its code")
        suite.expect(flow.next(.cancel, now: t0) == .idle, "cancel returns to idle")
        suite.expect(GitHubDeviceFlowState.requestingCode.next(.codeRequestFailed("offline"), now: t0)
                     == .failed(.other("offline")), "a failed code request fails")
        suite.expect(GitHubDeviceFlowState.idle.next(.poll(.pending), now: t0) == .idle,
                     "an input that does not fit the state is ignored")
    }

    // MARK: - Preferences

    private static func preferences(_ suite: TestSuite) {
        let registered = Defaults.registeredDefaults
        let watched = Preferences.githubWatchedRepositories
        suite.expect(registered[watched.key] as? String == watched.defaultValue
                     && GitHubWatchlist.decode(watched.defaultValue) == [repo],
                     "the watchlist defaults to this repository, JSON-encoded")
        suite.expect(registered[Preferences.githubRelayURL.key] as? String == "https://github-relay.ipv1337.dev",
                     "the relay URL defaults to the homelab relay")
        suite.expect(registered[Preferences.githubMouseIndicator.key] as? Bool == true,
                     "the mouse indicator is on (the sink does nothing without a mouse)")
        suite.expect(GitHubWatchlist.decode(#"["b/c"," B/C ","bad","a/b"]"#)
                     == [RepoKey(owner: "b", name: "c"), RepoKey(owner: "a", name: "b")],
                     "decoding drops bad and duplicate entries and keeps order")
        suite.expect(GitHubWatchlist.decode("[]") == [], "an emptied watchlist stays empty")
        suite.expect(GitHubWatchlist.decode("garbage") == [repo], "an unreadable value falls back to the default")
        suite.expect(GitHubWatchlist.decode(GitHubWatchlist.encode([repo, RepoKey(owner: "a", name: "b")]))
                     == [repo, RepoKey(owner: "a", name: "b")], "encode and decode round-trip")
        suite.expect(!SettingsBackupSupport.machineStateKeys.contains(watched.key)
                     && !SettingsBackupSupport.machineStateKeys.contains(Preferences.githubMouseIndicator.key),
                     "the watchlist and the mouse switch are portable settings, so a backup carries them")
        suite.expect(!registered.keys.contains { $0.lowercased().contains("github") && $0.lowercased().contains("token") },
                     "the GitHub token never lives in preferences")
    }

    // MARK: - Frictionless Auth & Peripherals

    private static func frictionlessAuthParsing(_ suite: TestSuite) {
        let tokenPrefix = "gho_"
        let mockToken = tokenPrefix + "testMockToken1234567890"
        let sampleYAML = """
        github.com:
            git_protocol: https
            users:
                testuser:
                    oauth_token: \(mockToken)
            user: testuser
            oauth_token: \(mockToken)
        """
        var user: String?
        var token: String?
        for line in sampleYAML.components(separatedBy: .newlines) {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.hasPrefix("user:") {
                user = trimmed.replacingOccurrences(of: "user:", with: "").trimmingCharacters(in: .whitespaces)
            } else if trimmed.hasPrefix("oauth_token:") {
                let raw = trimmed.replacingOccurrences(of: "oauth_token:", with: "").trimmingCharacters(in: .whitespaces)
                token = raw.components(separatedBy: "#").first?.trimmingCharacters(in: .whitespaces) ?? raw
            }
        }
        suite.expect(user == "testuser", "parses user from CLI hosts.yml")
        suite.expect(token == mockToken, "parses oauth_token from CLI hosts.yml")
    }

    private static func peripheralSignalMapping(_ suite: TestSuite) {
        func command(for verdict: Verdict, color: String, mode: String, idleBehavior: String) -> [String] {
            switch verdict {
            case .green, .amber, .red:
                return mode == "breathe" ? ["breathe", color] : ["color", color]
            case .grey:
                return idleBehavior == "off" ? ["off"] : ["restore"]
            }
        }
        suite.expect(command(for: .green, color: "green", mode: "fixed", idleBehavior: "restore") == ["color", "green"],
                     "solid green command matches fixed color")
        suite.expect(command(for: .amber, color: "orange", mode: "breathe", idleBehavior: "restore") == ["breathe", "orange"],
                     "pulsing orange command matches breathe")
        suite.expect(command(for: .red, color: "red", mode: "breathe", idleBehavior: "restore") == ["breathe", "red"],
                     "pulsing red command matches breathe")
        suite.expect(command(for: .grey, color: "", mode: "", idleBehavior: "off") == ["off"],
                     "idle behavior off maps to off command")
        suite.expect(command(for: .grey, color: "", mode: "", idleBehavior: "restore") == ["restore"],
                     "idle behavior restore maps to restore command")
    }

    private static func notchModuleProperties(_ suite: TestSuite) {
        let module = NotchModule.github
        suite.expect(module.symbol == "arrow.triangle.branch", "github module uses arrow.triangle.branch symbol")
        suite.expect(module.shortcutKey == "h", "github module uses shortcut key h (⌥⌘H)")
        suite.expect(module.title(.enUS) == "GitHub", "github module title is GitHub in enUS")
        let defaults = UserDefaults.standard
        suite.expect(module.isAvailable(in: defaults) == AppFeature.notchGitHub.isAvailable(in: defaults),
                     "github module availability maps to AppFeature.notchGitHub")
        let strings = FeatureStrings.notchEditor(.enUS)
        suite.expect(strings.summary(.github) == "GitHub workflow runs, presubmit checks, and merge queue status.",
                     "editor summary describes github pipeline metrics")
    }

    private static func notchContentEditorStyling(_ suite: TestSuite) {
        let module = NotchModule.github
        suite.expect(module.settingsTint != nil, "github module has settingsTint defined")
    }
}
