// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 VitruvianSoftware

import Foundation

/// One HTTP exchange, answered before it returns. The tool sends through
/// `URLSession`; tests answer themselves, so no test reaches the network.
public protocol Transport {
    func send(_ request: URLRequest) throws -> (Data, HTTPURLResponse)
}

/// Why a request could not be made or read.
public enum APIError: Error, Equatable, Sendable {
    /// No answer at all.
    case unreachable
    /// An answer that was not HTTP, or not the JSON asked for.
    case malformed
    /// GitHub answered with this status.
    case refused(status: Int)
}

/// `URLSession`, waited on. The tool works on one thread and a poll is the
/// only thing it does while it waits, so waiting is the simple and right
/// thing; `timeout` bounds it.
public struct URLSessionTransport: Transport {
    private let session: URLSession
    private let timeout: TimeInterval

    public init(session: URLSession = .shared, timeout: TimeInterval = 15) {
        self.session = session
        self.timeout = timeout
    }

    public func send(_ request: URLRequest) throws -> (Data, HTTPURLResponse) {
        var request = request
        request.timeoutInterval = timeout
        let done = DispatchSemaphore(value: 0)
        // Written by the session's queue, read after the semaphore: the
        // semaphore orders the two.
        nonisolated(unsafe) var answer: (Data, URLResponse)?
        nonisolated(unsafe) var failure: Error?
        session.dataTask(with: request) { data, response, error in
            if let data, let response { answer = (data, response) } else { failure = error }
            done.signal()
        }.resume()
        _ = done.wait(timeout: .now() + timeout + 5)
        guard let answer else { throw failure.map { _ in APIError.unreachable } ?? APIError.unreachable }
        guard let http = answer.1 as? HTTPURLResponse else { throw APIError.malformed }
        return (answer.0, http)
    }
}

/// GitHub's REST API, read with conditional requests (ETags), and the two
/// device-flow requests. Every call waits for its answer.
public final class GitHubAPI {
    public static let defaultAPIURL = URL(string: "https://api.github.com")!
    public static let defaultWebURL = URL(string: "https://github.com")!
    public static let deviceGrantType = "urn:ietf:params:oauth:grant-type:device_code"
    /// The newest concerning pull requests per repository whose check runs
    /// and reviews are fetched on each poll, bounding the request budget.
    public static let maxDetailedPulls = 10
    /// The most conditional-GET responses kept in memory before the cache is
    /// cleared and refilled.
    public static let maxCachedResponses = 512

    private struct Run: Decodable {
        let id: Int64
        let name: String
        let head_sha: String
        let status: String
        let conclusion: String?
        let html_url: String?
    }

    private let transport: any Transport
    private let apiURL: URL
    private let webURL: URL
    private var cached: [URL: (etag: String, data: Data)] = [:]

    public init(transport: any Transport = URLSessionTransport(), apiURL: URL = defaultAPIURL,
                webURL: URL = defaultWebURL) {
        self.transport = transport
        self.apiURL = apiURL
        self.webURL = webURL
    }

    /// How many conditional-GET responses are currently cached.
    var cachedResponseCount: Int { cached.count }

    // MARK: Who

    /// `GET /user`, and the teams when the token may read them.
    public func identity(token: String) throws -> GitHubIdentity {
        let (data, response) = try send(url: apiURL.appendingPathComponent("user"), token: token)
        guard response.statusCode == 200 else { throw APIError.refused(status: response.statusCode) }
        struct User: Decodable { let login: String }
        guard let user = try? JSONDecoder().decode(User.self, from: data) else { throw APIError.malformed }
        var teams: Set<String> = []
        if let (teamData, teamResponse) = try? send(url: apiURL.appendingPathComponent("user/teams"), token: token),
           teamResponse.statusCode == 200 {
            struct Team: Decodable {
                let slug: String
                let organization: Org?
                struct Org: Decodable { let login: String }
            }
            for team in (try? JSONDecoder().decode([Team].self, from: teamData)) ?? [] {
                teams.insert(team.organization.map { "\($0.login)/\(team.slug)" } ?? team.slug)
            }
        }
        return GitHubIdentity(login: user.login, teams: teams)
    }

    // MARK: A repository

    /// A snapshot of the default branch, its checks and the open pull
    /// requests that concern `identity` (or all when `identity` is nil); nil
    /// when the repository could not be read (a status other than 200 and
    /// 401). A 401 is thrown: the token is dead.
    public func snapshot(repo: RepoKey, token: String, identity: GitHubIdentity? = nil,
                         known: RepoState? = nil, now: Date = Date()) throws -> RepoState? {
        let base = apiURL.appendingPathComponent("repos/\(repo.owner)/\(repo.name)")
        let defaultBranch: String
        if let known {
            defaultBranch = known.defaultBranch
        } else {
            let (data, response) = try send(url: base, token: token)
            guard response.statusCode == 200 else {
                if response.statusCode == 401 { throw APIError.refused(status: 401) }
                return nil
            }
            struct Info: Decodable { let default_branch: String }
            guard let info = try? JSONDecoder().decode(Info.self, from: data) else { return nil }
            defaultBranch = info.default_branch
        }

        let (commitData, commitResponse) = try send(url: base.appendingPathComponent("commits/\(defaultBranch)"), token: token)
        guard commitResponse.statusCode == 200 else {
            if commitResponse.statusCode == 401 { throw APIError.refused(status: 401) }
            return nil
        }
        struct Commit: Decodable { let sha: String }
        guard let headSHA = (try? JSONDecoder().decode(Commit.self, from: commitData))?.sha else { return nil }

        var checks = checkRuns(base: base, sha: headSHA, token: token) ?? [:]
        // The head commit's workflow runs, plus any paused for approval on
        // an earlier commit: a deploy often still waits at its gate after
        // the next push has moved the branch on.
        struct WorkflowRuns: Decodable { let workflow_runs: [Run] }
        for status in [nil, "waiting"] {
            var parts = URLComponents(url: base.appendingPathComponent("actions/runs"), resolvingAgainstBaseURL: false)
            parts?.queryItems = [URLQueryItem(name: "branch", value: defaultBranch), URLQueryItem(name: "per_page", value: "10")]
                + (status.map { [URLQueryItem(name: "status", value: $0)] } ?? [])
            guard let url = parts?.url, let (data, response) = try? send(url: url, token: token), response.statusCode == 200,
                  let decoded = try? JSONDecoder().decode(WorkflowRuns.self, from: data) else { continue }
            for run in decoded.workflow_runs
            where run.head_sha == headSHA || CheckStatus(raw: run.status).isAwaitingApproval {
                checks["workflow_run:\(run.id)"] = CheckRun(
                    key: "workflow_run:\(run.id)", name: run.name, headSHA: run.head_sha,
                    status: CheckStatus(raw: run.status), conclusion: run.conclusion.map(CheckConclusion.init(raw:)),
                    htmlURL: run.html_url.flatMap(URL.init(string:)), workflowRunID: run.id)
            }
        }

        var pulls: [Int: PullRequest] = [:]
        var pullParts = URLComponents(url: base.appendingPathComponent("pulls"), resolvingAgainstBaseURL: false)
        pullParts?.queryItems = [URLQueryItem(name: "state", value: "open"), URLQueryItem(name: "per_page", value: "100")]
        if let url = pullParts?.url, let (data, response) = try? send(url: url, token: token), response.statusCode == 200 {
            struct Pull: Decodable {
                let number: Int
                let title: String
                let draft: Bool?
                let html_url: String?
                struct User: Decodable { let login: String }
                let user: User?
                struct Head: Decodable { let sha: String }
                let head: Head?
                struct Reviewer: Decodable { let login: String }
                let requested_reviewers: [Reviewer]?
                struct Team: Decodable { let slug: String }
                let requested_teams: [Team]?
            }
            var candidates: [PullRequest] = []
            for pull in (try? JSONDecoder().decode([Pull].self, from: data)) ?? [] {
                let candidate = PullRequest(
                    number: pull.number, title: pull.title, author: pull.user?.login ?? "",
                    headSHA: pull.head?.sha ?? "", isDraft: pull.draft ?? false,
                    htmlURL: pull.html_url.flatMap(URL.init(string:)),
                    requestedReviewers: Set((pull.requested_reviewers ?? []).map(\.login)),
                    requestedTeams: Set((pull.requested_teams ?? []).map(\.slug)))
                if let identity, !Verdicts.concerns(candidate, in: repo, identity: identity) { continue }
                candidates.append(candidate)
            }
            candidates.sort { $0.number > $1.number }
            for (index, var candidate) in candidates.enumerated() {
                let previous = known?.pullRequests[candidate.number]
                let sameHead = previous?.headSHA == candidate.headSHA
                if index < Self.maxDetailedPulls {
                    candidate.checks = checkRuns(base: base, sha: candidate.headSHA, token: token)
                        ?? (sameHead ? previous?.checks ?? [:] : [:])
                    candidate.reviews = pullReviews(base: base, number: candidate.number, token: token)
                        ?? previous?.reviews ?? [:]
                } else {
                    candidate.checks = sameHead ? previous?.checks ?? [:] : [:]
                    candidate.reviews = previous?.reviews ?? [:]
                }
                pulls[candidate.number] = candidate
            }
        }
        return RepoState(repo: repo, defaultBranch: defaultBranch, headSHA: headSHA, checks: checks,
                         pullRequests: pulls, updatedAt: now)
    }

    private func checkRuns(base: URL, sha: String, token: String) -> [String: CheckRun]? {
        struct CheckRuns: Decodable { let check_runs: [Run] }
        var parts = URLComponents(url: base.appendingPathComponent("commits/\(sha)/check-runs"), resolvingAgainstBaseURL: false)
        parts?.queryItems = [URLQueryItem(name: "per_page", value: "100")]
        guard !sha.isEmpty, let url = parts?.url,
              let (data, response) = try? send(url: url, token: token),
              response.statusCode == 200,
              let decoded = try? JSONDecoder().decode(CheckRuns.self, from: data) else { return nil }
        var checks: [String: CheckRun] = [:]
        for run in decoded.check_runs {
            checks["check_run:\(run.id)"] = CheckRun(
                key: "check_run:\(run.id)", name: run.name, headSHA: run.head_sha,
                status: CheckStatus(raw: run.status), conclusion: run.conclusion.map(CheckConclusion.init(raw:)),
                htmlURL: run.html_url.flatMap(URL.init(string:)))
        }
        return checks
    }

    private func pullReviews(base: URL, number: Int, token: String) -> [String: ReviewState]? {
        struct Review: Decodable {
            struct User: Decodable { let login: String }
            let user: User?
            let state: String?
        }
        var parts = URLComponents(url: base.appendingPathComponent("pulls/\(number)/reviews"), resolvingAgainstBaseURL: false)
        parts?.queryItems = [URLQueryItem(name: "per_page", value: "100")]
        guard let url = parts?.url,
              let (data, response) = try? send(url: url, token: token),
              response.statusCode == 200,
              let decoded = try? JSONDecoder().decode([Review].self, from: data) else { return nil }
        return Self.reviews(from: decoded.map { ($0.user?.login ?? "", $0.state ?? "") })
    }

    /// Each reviewer's latest approval or change request, in the order
    /// GitHub returned them; comments do not change standing, and a
    /// dismissed review drops out.
    public static func reviews(from entries: [(reviewer: String, state: String)]) -> [String: ReviewState] {
        var out: [String: ReviewState] = [:]
        for entry in entries {
            let reviewer = entry.reviewer.lowercased()
            guard !reviewer.isEmpty else { continue }
            switch entry.state.lowercased() {
            case "approved": out[reviewer] = .approved
            case "changes_requested": out[reviewer] = .changesRequested
            case "dismissed": out[reviewer] = nil
            default: break
            }
        }
        return out
    }

    /// `POST /repos/{owner}/{repo}/actions/runs/{id}/rerun-failed-jobs` for
    /// each run. The ids of the runs GitHub accepted.
    @discardableResult
    public func rerunFailedJobs(repo: RepoKey, runIDs: [Int64], token: String) -> [Int64] {
        runIDs.filter { id in
            let url = apiURL.appendingPathComponent("repos/\(repo.owner)/\(repo.name)/actions/runs/\(id)/rerun-failed-jobs")
            guard let (_, response) = try? send(url: url, token: token, method: "POST") else { return false }
            return response.statusCode == 201
        }
    }

    // MARK: A code

    /// `POST https://github.com/login/device/code`.
    public func deviceCode(clientID: String) throws -> DeviceCode {
        let request = Self.form(webURL.appendingPathComponent("login/device/code"), ["client_id": clientID])
        let data: Data
        do { (data, _) = try transport.send(request) } catch { throw APIError.unreachable }
        struct Answer: Decodable {
            let device_code: String?
            let user_code: String?
            let verification_uri: String?
            let expires_in: Int?
            let interval: Int?
            let error: String?
        }
        let answer = try? JSONDecoder().decode(Answer.self, from: data)
        guard let answer, let deviceCode = answer.device_code, let userCode = answer.user_code,
              let uri = answer.verification_uri.flatMap(URL.init(string:)) else {
            throw DeviceCodeRefused(reason: answer?.error ?? "no_device_code")
        }
        return DeviceCode(deviceCode: deviceCode, userCode: userCode, verificationURI: uri,
                          expiresIn: TimeInterval(answer.expires_in ?? 900), interval: TimeInterval(answer.interval ?? 5))
    }

    /// GitHub would not start the code sign-in; `reason` is its `error`.
    public struct DeviceCodeRefused: Error, Equatable, Sendable {
        public let reason: String
    }

    /// One `POST https://github.com/login/oauth/access_token`. A network
    /// blip is read as "still waiting", so the code stays usable until it
    /// expires.
    public func pollDeviceCode(clientID: String, deviceCode: String) -> DevicePollResult {
        let request = Self.form(webURL.appendingPathComponent("login/oauth/access_token"),
                                ["client_id": clientID, "device_code": deviceCode, "grant_type": Self.deviceGrantType])
        guard let (data, _) = try? transport.send(request) else { return .pending }
        struct Answer: Decodable {
            let access_token: String?
            let error: String?
        }
        guard let answer = try? JSONDecoder().decode(Answer.self, from: data) else { return .failure("unreadable_response") }
        if let token = answer.access_token, !token.isEmpty { return .token(AccessToken(token)) }
        return DevicePollResult(errorCode: answer.error ?? "no_token")
    }

    // MARK: Plumbing

    private func send(url: URL, token: String, method: String = "GET") throws -> (Data, HTTPURLResponse) {
        var request = URLRequest(url: url)
        request.httpMethod = method
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.setValue("2022-11-28", forHTTPHeaderField: "X-GitHub-Api-Version")
        if method == "GET", let entry = cached[url] {
            request.setValue(entry.etag, forHTTPHeaderField: "If-None-Match")
        }
        let (data, response): (Data, HTTPURLResponse)
        do { (data, response) = try transport.send(request) } catch { throw APIError.unreachable }
        if method == "GET" {
            if response.statusCode == 304, let entry = cached[url] {
                let etag = response.value(forHTTPHeaderField: "ETag") ?? entry.etag
                cached[url] = (etag, entry.data)
                let replayed = HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil, headerFields: ["ETag": etag])!
                return (entry.data, replayed)
            }
            if response.statusCode == 200, let etag = response.value(forHTTPHeaderField: "ETag") {
                if cached[url] == nil, cached.count >= Self.maxCachedResponses {
                    cached.removeAll()
                }
                cached[url] = (etag, data)
            }
        }
        return (data, response)
    }

    static func form(_ url: URL, _ fields: [String: String]) -> URLRequest {
        var components = URLComponents()
        components.queryItems = fields.sorted { $0.key < $1.key }.map { URLQueryItem(name: $0.key, value: $0.value) }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.httpBody = Data((components.percentEncodedQuery ?? "").utf8)
        return request
    }
}
