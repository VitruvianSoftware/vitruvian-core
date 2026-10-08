// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 VitruvianSoftware

import Foundation
import VitruvianCore

/// A client that reads GitHub's REST API directly using conditional requests (ETags).
/// Takes a transport so unit tests never hit the network.
@MainActor
package final class GitHubAPIClient {
    private let transport: any GitHubAuthTransport
    private let apiURL: URL
    private var etags: [URL: String] = [:]

    package init(transport: any GitHubAuthTransport = URLSessionGitHubAuthTransport(),
                 apiURL: URL = URL(string: "https://api.github.com")!) {
        self.transport = transport
        self.apiURL = apiURL
    }

    /// Fetches the authenticated user's login and teams.
    package func fetchIdentity(token: String) async throws -> GitHubIdentity {
        let userURL = apiURL.appendingPathComponent("user")
        let (data, response) = try await send(url: userURL, token: token)
        guard response.statusCode == 200 else {
            throw GitHubAuthError.gitHubRefused(status: response.statusCode)
        }
        struct GitHubUserResponse: Decodable {
            let login: String
        }
        let user = try JSONDecoder().decode(GitHubUserResponse.self, from: data)

        // Teams are optional; ignore errors if user has no org access or token lacks read:org
        var teams: Set<String> = []
        let teamsURL = apiURL.appendingPathComponent("user/teams")
        if let (teamData, teamResponse) = try? await send(url: teamsURL, token: token), teamResponse.statusCode == 200 {
            struct TeamResponse: Decodable {
                let slug: String
                let organization: OrgResponse?
                struct OrgResponse: Decodable {
                    let login: String
                }
            }
            if let list = try? JSONDecoder().decode([TeamResponse].self, from: teamData) {
                for item in list {
                    if let org = item.organization?.login {
                        teams.insert("\(org)/\(item.slug)")
                    } else {
                        teams.insert(item.slug)
                    }
                }
            }
        }
        return GitHubIdentity(login: user.login, teams: teams)
    }

    /// Fetches a full snapshot of the default branch, its checks and open pull requests.
    /// If none of the endpoints changed (all 304), returns nil.
    package func fetchSnapshot(repo: RepoKey, token: String,
                              knownState: RepoState? = nil) async throws -> RepoState? {
        let repoBase = apiURL.appendingPathComponent("repos/\(repo.owner)/\(repo.name)")

        // 1. Repository metadata to determine default branch
        struct RepoInfo: Decodable {
            let default_branch: String
        }
        let defaultBranch: String
        if let known = knownState {
            defaultBranch = known.defaultBranch
        } else {
            let (data, response) = try await send(url: repoBase, token: token)
            guard response.statusCode == 200 else {
                if response.statusCode == 401 { throw GitHubAuthError.gitHubRefused(status: 401) }
                return nil
            }
            let info = try JSONDecoder().decode(RepoInfo.self, from: data)
            defaultBranch = info.default_branch
        }

        // 2. Head commit of default branch
        let commitURL = repoBase.appendingPathComponent("commits/\(defaultBranch)")
        struct CommitResponse: Decodable {
            let sha: String
        }
        let (commitData, commitResponse) = try await send(url: commitURL, token: token)
        guard commitResponse.statusCode == 200 else { return nil }
        let headSHA = try JSONDecoder().decode(CommitResponse.self, from: commitData).sha

        var checks: [String: CheckRun] = [:]

        // 3. Check runs on head commit
        let checkRunsURL = repoBase.appendingPathComponent("commits/\(headSHA)/check-runs")
        if let (checkData, checkResp) = try? await send(url: checkRunsURL, token: token), checkResp.statusCode == 200 {
            struct CheckRunsResponse: Decodable {
                struct Item: Decodable {
                    let id: Int64
                    let name: String
                    let head_sha: String
                    let status: String
                    let conclusion: String?
                    let html_url: String?
                }
                let check_runs: [Item]
            }
            if let decoded = try? JSONDecoder().decode(CheckRunsResponse.self, from: checkData) {
                for item in decoded.check_runs {
                    let run = CheckRun(
                        key: "check_run:\(item.id)",
                        name: item.name,
                        headSHA: item.head_sha,
                        status: CheckStatus(raw: item.status),
                        conclusion: item.conclusion.map(CheckConclusion.init(raw:)),
                        htmlURL: item.html_url.flatMap(URL.init(string:))
                    )
                    checks[run.key] = run
                }
            }
        }

        // 4. Workflow runs on default branch
        var runsComponents = URLComponents(url: repoBase.appendingPathComponent("actions/runs"), resolvingAgainstBaseURL: false)
        runsComponents?.queryItems = [
            URLQueryItem(name: "branch", value: defaultBranch),
            URLQueryItem(name: "per_page", value: "10")
        ]
        if let runsURL = runsComponents?.url,
           let (runData, runResp) = try? await send(url: runsURL, token: token), runResp.statusCode == 200 {
            struct WorkflowRunsResponse: Decodable {
                struct Item: Decodable {
                    let id: Int64
                    let name: String
                    let head_sha: String
                    let status: String
                    let conclusion: String?
                    let html_url: String?
                }
                let workflow_runs: [Item]
            }
            if let decoded = try? JSONDecoder().decode(WorkflowRunsResponse.self, from: runData) {
                for item in decoded.workflow_runs where item.head_sha == headSHA {
                    let run = CheckRun(
                        key: "workflow_run:\(item.id)",
                        name: item.name,
                        headSHA: item.head_sha,
                        status: CheckStatus(raw: item.status),
                        conclusion: item.conclusion.map(CheckConclusion.init(raw:)),
                        htmlURL: item.html_url.flatMap(URL.init(string:))
                    )
                    checks[run.key] = run
                }
            }
        }

        // 5. Open Pull Requests
        var prs: [Int: PullRequest] = [:]
        var prComponents = URLComponents(url: repoBase.appendingPathComponent("pulls"), resolvingAgainstBaseURL: false)
        prComponents?.queryItems = [
            URLQueryItem(name: "state", value: "open"),
            URLQueryItem(name: "per_page", value: "20")
        ]
        if let prURL = prComponents?.url,
           let (prData, prResp) = try? await send(url: prURL, token: token), prResp.statusCode == 200 {
            struct PRItem: Decodable {
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
            if let decoded = try? JSONDecoder().decode([PRItem].self, from: prData) {
                for item in decoded {
                    let author = item.user?.login ?? ""
                    let prHeadSHA = item.head?.sha ?? ""
                    let reviewers = Set((item.requested_reviewers ?? []).map(\.login))
                    let teams = Set((item.requested_teams ?? []).map(\.slug))
                    let pr = PullRequest(
                        number: item.number,
                        title: item.title,
                        author: author,
                        headSHA: prHeadSHA,
                        isDraft: item.draft ?? false,
                        htmlURL: item.html_url.flatMap(URL.init(string:)),
                        requestedReviewers: reviewers,
                        requestedTeams: teams
                    )
                    prs[pr.number] = pr
                }
            }
        }

        return RepoState(
            repo: repo,
            defaultBranch: defaultBranch,
            headSHA: headSHA,
            checks: checks,
            pullRequests: prs,
            lastEventID: nil,
            updatedAt: Date()
        )
    }

    private func send(url: URL, token: String) async throws -> (Data, HTTPURLResponse) {
        var request = URLRequest(url: url)
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.setValue("2022-11-28", forHTTPHeaderField: "X-GitHub-Api-Version")
        if let etag = etags[url] {
            request.setValue(etag, forHTTPHeaderField: "If-None-Match")
        }
        let (data, response) = try await transport.send(request)
        if let newEtag = response.value(forHTTPHeaderField: "ETag") {
            etags[url] = newEtag
        }
        return (data, response)
    }
}
