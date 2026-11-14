// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 VitruvianSoftware

import XCTest

@testable import GitHubToolCore

/// A transport that answers from a table by the request's path, and keeps
/// every request it was given.
final class FakeTransport: Transport {
    var answers: [String: (Int, String)] = [:]
    var etag: String?
    var requests: [URLRequest] = []
    var fails = false

    func send(_ request: URLRequest) throws -> (Data, HTTPURLResponse) {
        requests.append(request)
        if fails { throw URLError(.notConnectedToInternet) }
        let path = request.url!.path + (request.url!.query.map { "?" + $0 } ?? "")
        let (status, body) = answers[path] ?? answers[request.url!.path] ?? (404, "{}")
        var headers: [String: String] = [:]
        if let etag { headers["ETag"] = etag }
        let response = HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: nil, headerFields: headers)!
        return (Data(body.utf8), response)
    }
}

final class APITests: XCTestCase {
    let repo = RepoKey(owner: "acme", name: "web")
    let transport = FakeTransport()
    lazy var api = GitHubAPI(transport: transport, apiURL: URL(string: "https://api.test")!, webURL: URL(string: "https://web.test")!)

    func testIdentityReadsTheLoginAndTheTeamsAndRefusesA401() throws {
        transport.answers["/user"] = (200, #"{"login": "James"}"#)
        transport.answers["/user/teams"] = (200, #"[{"slug": "platform-team", "organization": {"login": "VitruvianSoftware"}}, {"slug": "lone"}]"#)
        let me = try api.identity(token: "t")
        XCTAssertEqual(me.login, "james")
        XCTAssertEqual(me.teams, ["vitruviansoftware/platform-team", "lone"])
        XCTAssertEqual(transport.requests.first?.value(forHTTPHeaderField: "Authorization"), "Bearer t")
        XCTAssertEqual(transport.requests.first?.value(forHTTPHeaderField: "X-GitHub-Api-Version"), "2022-11-28")
        transport.answers["/user"] = (401, "{}")
        XCTAssertThrowsError(try api.identity(token: "dead")) { XCTAssertEqual($0 as? APIError, .refused(status: 401)) }
        transport.fails = true
        XCTAssertThrowsError(try api.identity(token: "t")) { XCTAssertEqual($0 as? APIError, .unreachable) }
    }

    func testSnapshotReadsTheBranchItsChecksAndThePullRequests() throws {
        transport.answers["/repos/acme/web"] = (200, #"{"default_branch": "trunk"}"#)
        transport.answers["/repos/acme/web/commits/trunk"] = (200, #"{"sha": "head1"}"#)
        transport.answers["/repos/acme/web/commits/head1/check-runs?per_page=100"] = (200, #"{"check_runs": [{"id": 1, "name": "lint", "head_sha": "head1", "status": "completed", "conclusion": "success", "html_url": "https://x/1"}]}"#)
        transport.answers["/repos/acme/web/actions/runs?branch=trunk&per_page=10"] = (200, #"{"workflow_runs": [{"id": 50, "name": "ci", "head_sha": "head1", "status": "completed", "conclusion": "failure", "html_url": null}, {"id": 51, "name": "old", "head_sha": "head0", "status": "completed", "conclusion": "success", "html_url": null}]}"#)
        transport.answers["/repos/acme/web/actions/runs?branch=trunk&per_page=10&status=waiting"] = (200, #"{"workflow_runs": [{"id": 52, "name": "deploy", "head_sha": "head0", "status": "waiting", "conclusion": null, "html_url": null}]}"#)
        transport.answers["/repos/acme/web/pulls?state=open&per_page=100"] = (200, #"[{"number": 7, "title": "Fix", "draft": true, "html_url": "https://x/pull/7", "user": {"login": "Ana"}, "head": {"sha": "p7"}, "requested_reviewers": [{"login": "James"}], "requested_teams": [{"slug": "Platform-Team"}]}, {"number": 8, "title": "Stranger", "draft": false, "html_url": "https://x/pull/8", "user": {"login": "Bob"}, "head": {"sha": "p8"}, "requested_reviewers": [], "requested_teams": []}, {"number": 9, "title": "Auto", "draft": false, "html_url": "https://x/pull/9", "user": {"login": "James"}, "head": {"sha": "p9"}, "requested_reviewers": [], "requested_teams": [], "auto_merge": {}}]"#)
        transport.answers["/graphql"] = (200, #"{"data": {"repository": {"mergeQueue": {"entries": {"nodes": [{"position": 4, "pullRequest": {"number": 7}}]}}}}}"#)
        transport.answers["/repos/acme/web/commits/p7/check-runs?per_page=100"] = (200, #"{"check_runs": [{"id": 70, "name": "test", "head_sha": "p7", "status": "completed", "conclusion": "success", "html_url": "https://x/70"}]}"#)
        transport.answers["/repos/acme/web/pulls/7/reviews?per_page=100"] = (200, #"[{"user": {"login": "James"}, "state": "CHANGES_REQUESTED"}, {"user": {"login": "James"}, "state": "COMMENTED"}, {"user": {"login": "James"}, "state": "APPROVED"}, {"user": {"login": "Bo"}, "state": "CHANGES_REQUESTED"}, {"user": {"login": "Bo"}, "state": "DISMISSED"}]"#)
        transport.answers["/repos/acme/web/commits/p9/check-runs?per_page=100"] = (200, #"{"check_runs": []}"#)
        transport.answers["/repos/acme/web/pulls/9/reviews?per_page=100"] = (200, "[]")
        let me = GitHubIdentity(login: "james", teams: ["acme/platform-team"])
        let now = Date(timeIntervalSince1970: 5)
        let state = try XCTUnwrap(try api.snapshot(repo: repo, token: "t", identity: me, now: now))
        XCTAssertEqual(state.defaultBranch, "trunk")
        XCTAssertEqual(state.headSHA, "head1")
        XCTAssertEqual(Set(state.checks.keys), ["check_run:1", "workflow_run:50", "workflow_run:52"],
                       "the head's runs and the one waiting on an older commit, not the old finished one")
        XCTAssertEqual(state.checks["workflow_run:50"]?.workflowRunID, 50)
        XCTAssertEqual(state.checks["workflow_run:52"]?.status, .waiting)
        XCTAssertEqual(Set(state.pullRequests.keys), [7, 9], "only pull requests that concern the signed-in person")
        XCTAssertTrue(transport.requests.contains {
            $0.url?.path == "/repos/acme/web/commits/p7/check-runs" && $0.url?.query == "per_page=100"
        }, "check-runs asks for 100 items per page")
        XCTAssertFalse(transport.requests.contains { $0.url?.path == "/repos/acme/web/commits/p8/check-runs" },
                       "a stranger's pull request costs no extra requests")
        XCTAssertEqual(state.pullRequests[7]?.author, "Ana")
        XCTAssertEqual(state.pullRequests[7]?.requestedReviewers, ["james"])
        XCTAssertEqual(state.pullRequests[7]?.requestedTeams, ["platform-team"])
        XCTAssertEqual(state.pullRequests[7]?.isDraft, true)
        XCTAssertEqual(state.pullRequests[7]?.mergeQueue, MergeQueueState(position: 4),
                       "merge-queue position comes from the repository's mergeQueue in GraphQL")
        XCTAssertNil(state.pullRequests[9]?.mergeQueue,
                     "auto_merge alone does not mean a pull request has entered the merge queue")
        let graphqlRequest = try XCTUnwrap(transport.requests.first { $0.url?.path == "/graphql" })
        let graphqlBody = String(decoding: graphqlRequest.httpBody ?? Data(), as: UTF8.self)
        XCTAssertTrue(graphqlBody.contains(#""branch":"trunk""#), "GraphQL mergeQueue query asks for the default branch")
        XCTAssertEqual(state.pullRequests[7]?.checks["check_run:70"]?.conclusion, .success)
        XCTAssertEqual(Verdicts.verdict(for: try XCTUnwrap(state.pullRequests[7])), .green)
        XCTAssertEqual(state.pullRequests[7]?.reviews, ["james": .approved],
                       "latest approve or request-changes per reviewer; comments do not count and dismissed drops out")
        XCTAssertEqual(state.pullRequests[7]?.reviewState, .approved)
        XCTAssertEqual(state.updatedAt, now)
        XCTAssertEqual(Verdicts.verdict(for: state), .red)

        // Known: the repository is not asked for its branch again.
        transport.requests.removeAll()
        _ = try api.snapshot(repo: repo, token: "t", identity: me, known: state, now: now)
        XCTAssertFalse(transport.requests.contains { $0.url?.path == "/repos/acme/web" })
    }

    func testPullRequestDetailFetchesAreCappedByTheRequestBudget() throws {
        transport.answers["/repos/acme/web"] = (200, #"{"default_branch": "main"}"#)
        transport.answers["/repos/acme/web/commits/main"] = (200, #"{"sha": "head1"}"#)
        transport.answers["/repos/acme/web/commits/head1/check-runs?per_page=100"] = (200, #"{"check_runs": []}"#)
        transport.answers["/repos/acme/web/actions/runs?branch=main&per_page=10"] = (200, #"{"workflow_runs": []}"#)
        transport.answers["/repos/acme/web/actions/runs?branch=main&per_page=10&status=waiting"] = (200, #"{"workflow_runs": []}"#)
        let items = (1...15).map { n in
            #"{"number": \#(n), "title": "PR \#(n)", "draft": false, "html_url": null, "user": {"login": "james"}, "head": {"sha": "sha\#(n)"}, "requested_reviewers": [], "requested_teams": []}"#
        }.joined(separator: ",")
        transport.answers["/repos/acme/web/pulls?state=open&per_page=100"] = (200, "[\(items)]")
        for n in 1...15 {
            transport.answers["/repos/acme/web/commits/sha\(n)/check-runs?per_page=100"] = (200, #"{"check_runs": [{"id": \#(n), "name": "ci", "head_sha": "sha\#(n)", "status": "completed", "conclusion": "success", "html_url": null}]}"#)
            transport.answers["/repos/acme/web/pulls/\(n)/reviews?per_page=100"] = (200, #"[{"user": {"login": "bo"}, "state": "APPROVED"}]"#)
        }
        let oldCheck = CheckRun(key: "check_run:99", name: "ci", headSHA: "sha1", status: .completed,
                                conclusion: .success, htmlURL: nil)
        let staleCheck = CheckRun(key: "check_run:98", name: "ci", headSHA: "old_sha2", status: .completed,
                                  conclusion: .failure, htmlURL: nil)
        var prior = RepoState(repo: repo, defaultBranch: "main", headSHA: "head1")
        prior.pullRequests[1] = PullRequest(number: 1, title: "PR 1", author: "james", headSHA: "sha1", isDraft: false,
                                            htmlURL: nil, requestedReviewers: [], requestedTeams: [],
                                            reviews: ["ana": .changesRequested],
                                            checks: ["check_run:99": oldCheck])
        prior.pullRequests[2] = PullRequest(number: 2, title: "PR 2", author: "james", headSHA: "old_sha2", isDraft: false,
                                            htmlURL: nil, requestedReviewers: [], requestedTeams: [],
                                            reviews: ["ana": .approved],
                                            checks: ["check_run:98": staleCheck])
        let me = GitHubIdentity(login: "james", teams: [])
        let state = try XCTUnwrap(try api.snapshot(repo: repo, token: "t", identity: me, known: prior))
        XCTAssertEqual(state.pullRequests.count, 15, "every concerning pull request is kept in the state")
        let checkPaths = transport.requests.compactMap { $0.url?.path }.filter { $0.hasSuffix("/check-runs") && !$0.contains("/head1/") }
        let reviewPaths = transport.requests.compactMap { $0.url?.path }.filter { $0.hasSuffix("/reviews") }
        XCTAssertEqual(checkPaths.count, GitHubAPI.maxDetailedPulls)
        XCTAssertEqual(reviewPaths.count, GitHubAPI.maxDetailedPulls)
        XCTAssertEqual(state.pullRequests[15]?.reviewState, .approved, "newest ten get fresh checks and reviews")
        XCTAssertEqual(state.pullRequests[6]?.reviewState, .approved)
        XCTAssertFalse(checkPaths.contains("/repos/acme/web/commits/sha5/check-runs"))
        XCTAssertEqual(state.pullRequests[1]?.checks, ["check_run:99": oldCheck],
                       "checks carry over past the cap when the head commit has not changed")
        XCTAssertEqual(state.pullRequests[1]?.reviewState, .changesRequested,
                       "reviews carry over past the cap")
        XCTAssertEqual(state.pullRequests[2]?.checks, [:],
                       "a pull request past the cap whose head changed drops stale checks instead of keeping them")
        XCTAssertEqual(state.pullRequests[2]?.reviewState, .approved,
                       "reviews carry over even when the head commit changed")
    }

    func testSnapshotIsNilWhenTheRepositoryCannotBeReadAndThrowsOn401() throws {
        transport.answers["/repos/acme/web"] = (404, "{}")
        XCTAssertNil(try api.snapshot(repo: repo, token: "t"))
        transport.answers["/repos/acme/web"] = (401, "{}")
        XCTAssertThrowsError(try api.snapshot(repo: repo, token: "t")) { XCTAssertEqual($0 as? APIError, .refused(status: 401)) }
        transport.answers["/repos/acme/web"] = (200, #"{"default_branch": "main"}"#)
        transport.answers["/repos/acme/web/commits/main"] = (401, "{}")
        XCTAssertThrowsError(try api.snapshot(repo: repo, token: "t"))
    }

    func testETagsAreSentBackOnGETsAndA304ReplaysTheCachedBody() throws {
        transport.etag = "W/\"1\""
        transport.answers["/user"] = (200, #"{"login": "me"}"#)
        transport.answers["/user/teams"] = (200, #"[{"slug": "core", "organization": {"login": "acme"}}]"#)
        _ = try api.identity(token: "t")
        transport.answers["/user"] = (304, "")
        transport.answers["/user/teams"] = (304, "")
        let second = try api.identity(token: "t")
        XCTAssertEqual(second.login, "me")
        XCTAssertEqual(second.teams, ["acme/core"], "a 304 Not Modified replays the cached 200 body")
        XCTAssertNil(transport.requests[0].value(forHTTPHeaderField: "If-None-Match"))
        XCTAssertEqual(transport.requests[2].value(forHTTPHeaderField: "If-None-Match"), "W/\"1\"")

        // Storing more than maxCachedResponses clears the cache so it stays bounded.
        for i in 0..<(GitHubAPI.maxCachedResponses + 5) {
            let key = RepoKey(owner: "acme", name: "repo-\(i)")
            transport.answers["/repos/acme/repo-\(i)"] = (200, #"{"default_branch": "main"}"#)
            transport.answers["/repos/acme/repo-\(i)/commits/main"] = (404, "{}")
            _ = try api.snapshot(repo: key, token: "t")
        }
        XCTAssertLessThanOrEqual(api.cachedResponseCount, GitHubAPI.maxCachedResponses,
                                 "the conditional-GET response cache stays bounded at maxCachedResponses")
    }

    func testRerunFailedJobsPostsForEachRunAndKeepsTheAccepted() {
        transport.answers["/repos/acme/web/actions/runs/50/rerun-failed-jobs"] = (201, "")
        transport.answers["/repos/acme/web/actions/runs/51/rerun-failed-jobs"] = (403, "{}")
        XCTAssertEqual(api.rerunFailedJobs(repo: repo, runIDs: [50, 51], token: "t"), [50])
        XCTAssertEqual(transport.requests.map(\.httpMethod), ["POST", "POST"])
        XCTAssertNil(transport.requests[0].value(forHTTPHeaderField: "If-None-Match"))
    }

    func testTheDeviceFlowRequestsAreForms() throws {
        transport.answers["/login/device/code"] = (200, #"{"device_code": "d", "user_code": "ABCD-1234", "verification_uri": "https://github.com/login/device", "expires_in": 899, "interval": 5}"#)
        let code = try api.deviceCode(clientID: "Iv1.app")
        XCTAssertEqual(code.userCode, "ABCD-1234")
        XCTAssertEqual(code.expiresIn, 899)
        let request = try XCTUnwrap(transport.requests.last)
        XCTAssertEqual(request.httpMethod, "POST")
        XCTAssertEqual(request.value(forHTTPHeaderField: "Content-Type"), "application/x-www-form-urlencoded")
        XCTAssertEqual(String(decoding: request.httpBody ?? Data(), as: UTF8.self), "client_id=Iv1.app")

        transport.answers["/login/oauth/access_token"] = (200, #"{"error": "authorization_pending"}"#)
        XCTAssertEqual(api.pollDeviceCode(clientID: "Iv1.app", deviceCode: "d"), .pending)
        XCTAssertEqual(String(decoding: transport.requests.last?.httpBody ?? Data(), as: UTF8.self),
                       "client_id=Iv1.app&device_code=d&grant_type=urn:ietf:params:oauth:grant-type:device_code")
        transport.answers["/login/oauth/access_token"] = (200, #"{"access_token": "gho_new"}"#)
        XCTAssertEqual(api.pollDeviceCode(clientID: "Iv1.app", deviceCode: "d"), .token(AccessToken("gho_new")))
        transport.fails = true
        XCTAssertEqual(api.pollDeviceCode(clientID: "Iv1.app", deviceCode: "d"), .pending, "a blip is still waiting")
        XCTAssertThrowsError(try api.deviceCode(clientID: "Iv1.app")) { XCTAssertEqual($0 as? APIError, .unreachable) }
        transport.fails = false
        transport.answers["/login/device/code"] = (200, #"{"error": "device_flow_disabled"}"#)
        XCTAssertThrowsError(try api.deviceCode(clientID: "Iv1.app")) {
            XCTAssertEqual($0 as? GitHubAPI.DeviceCodeRefused, GitHubAPI.DeviceCodeRefused(reason: "device_flow_disabled"))
        }
    }
}
