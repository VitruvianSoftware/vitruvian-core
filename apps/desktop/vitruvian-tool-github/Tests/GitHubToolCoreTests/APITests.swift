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
        transport.answers["/repos/acme/web/commits/head1/check-runs"] = (200, #"{"check_runs": [{"id": 1, "name": "lint", "head_sha": "head1", "status": "completed", "conclusion": "success", "html_url": "https://x/1"}]}"#)
        transport.answers["/repos/acme/web/actions/runs?branch=trunk&per_page=10"] = (200, #"{"workflow_runs": [{"id": 50, "name": "ci", "head_sha": "head1", "status": "completed", "conclusion": "failure", "html_url": null}, {"id": 51, "name": "old", "head_sha": "head0", "status": "completed", "conclusion": "success", "html_url": null}]}"#)
        transport.answers["/repos/acme/web/actions/runs?branch=trunk&per_page=10&status=waiting"] = (200, #"{"workflow_runs": [{"id": 52, "name": "deploy", "head_sha": "head0", "status": "waiting", "conclusion": null, "html_url": null}]}"#)
        transport.answers["/repos/acme/web/pulls?state=open&per_page=20"] = (200, #"[{"number": 7, "title": "Fix", "draft": true, "html_url": "https://x/pull/7", "user": {"login": "Ana"}, "head": {"sha": "p7"}, "requested_reviewers": [{"login": "James"}], "requested_teams": [{"slug": "Platform-Team"}]}]"#)
        let now = Date(timeIntervalSince1970: 5)
        let state = try XCTUnwrap(try api.snapshot(repo: repo, token: "t", now: now))
        XCTAssertEqual(state.defaultBranch, "trunk")
        XCTAssertEqual(state.headSHA, "head1")
        XCTAssertEqual(Set(state.checks.keys), ["check_run:1", "workflow_run:50", "workflow_run:52"],
                       "the head's runs and the one waiting on an older commit, not the old finished one")
        XCTAssertEqual(state.checks["workflow_run:50"]?.workflowRunID, 50)
        XCTAssertEqual(state.checks["workflow_run:52"]?.status, .waiting)
        XCTAssertEqual(state.pullRequests[7]?.author, "Ana")
        XCTAssertEqual(state.pullRequests[7]?.requestedReviewers, ["james"])
        XCTAssertEqual(state.pullRequests[7]?.requestedTeams, ["platform-team"])
        XCTAssertEqual(state.pullRequests[7]?.isDraft, true)
        XCTAssertEqual(state.updatedAt, now)
        XCTAssertEqual(Verdicts.verdict(for: state), .red)

        // Known: the repository is not asked for its branch again.
        transport.requests.removeAll()
        _ = try api.snapshot(repo: repo, token: "t", known: state, now: now)
        XCTAssertFalse(transport.requests.contains { $0.url?.path == "/repos/acme/web" })
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

    func testETagsAreSentBackOnGETs() throws {
        transport.etag = "W/\"1\""
        transport.answers["/user"] = (200, #"{"login": "me"}"#)
        _ = try api.identity(token: "t")
        _ = try api.identity(token: "t")
        XCTAssertNil(transport.requests[0].value(forHTTPHeaderField: "If-None-Match"))
        XCTAssertEqual(transport.requests[2].value(forHTTPHeaderField: "If-None-Match"), "W/\"1\"")
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
