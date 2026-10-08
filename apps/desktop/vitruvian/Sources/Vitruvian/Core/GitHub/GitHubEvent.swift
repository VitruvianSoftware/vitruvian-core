// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 VitruvianSoftware

import Foundation

// MARK: - Wire format (the relay's contract)
//
// `GET /events` on github-relay is a Server-Sent Events stream. This file is
// the contract the relay writes to; change both ends together.
//
// Frames
//
//     : ping                          comment, every 25 s; keeps the tunnel open
//
//     id: 42                          the relay id, also in the JSON
//     event: github                   may be left out (SSE's default "message")
//     data: {"id":"42","repo":"owner/name","kind":"…","payload":{…}}
//
//     event: resync                   Last-Event-ID is older than the buffer, or
//     data: {}                        the relay restarted: take a new snapshot
//
//     event: ping                     optional; the same as the comment
//     data: {}
//
// `id` is a decimal integer in a JSON string, strictly increasing across all
// repositories for the life of one relay process. A client applies events in id
// order and drops an id it has already passed. Ids restart with the relay, which
// is why the relay answers an id it does not hold with `resync`.
//
// `repo` is GitHub's `repository.full_name`. `kind` is the webhook's
// `X-GitHub-Event`. `payload` is a flat subset of the webhook, with GitHub's own
// field names and values; every listed field is present on every event of that
// kind (null where GitHub has none). Fields not listed are ignored.
//
//     check_run            id, name, head_sha, status, conclusion, html_url
//                          (check_run.*)
//     check_suite          id, head_sha, status, conclusion (check_suite.*)
//     workflow_run         id, name, head_sha, status, conclusion, html_url
//                          (workflow_run.*)
//     status               sha, context, state, target_url
//     push                 ref, before, after
//     pull_request         action, number, title, author (= user.login),
//                          head_sha (= head.sha), draft, html_url,
//                          requested_reviewers (logins), requested_teams (slugs)
//     pull_request_review  action, number, reviewer (= review.user.login),
//                          state (= review.state, lowercased)
//
// A kind not listed decodes as `.unknown` and changes nothing.

/// One normalised webhook from the relay.
package struct GitHubEvent: Sendable, Equatable {
    package let id: UInt64
    package let repo: RepoKey
    package let kind: Kind

    package init(id: UInt64, repo: RepoKey, kind: Kind) {
        self.id = id
        self.repo = repo
        self.kind = kind
    }

    package enum Kind: Sendable, Equatable {
        case checkRun(Run)
        case checkSuite(Suite)
        case workflowRun(Run)
        case status(Status)
        case push(Push)
        case pullRequest(PullRequestChange)
        case pullRequestReview(Review)
        case unknown(String)
    }

    /// A check run or a workflow run.
    package struct Run: Sendable, Equatable, Decodable {
        package let id: Int64
        package let name: String
        package let headSHA: String
        package let status: String
        package let conclusion: String?
        package let htmlURL: URL?

        package init(id: Int64, name: String, headSHA: String, status: String, conclusion: String?, htmlURL: URL?) {
            self.id = id
            self.name = name
            self.headSHA = headSHA
            self.status = status
            self.conclusion = conclusion
            self.htmlURL = htmlURL
        }

        enum CodingKeys: String, CodingKey {
            case id, name, status, conclusion
            case headSHA = "head_sha", htmlURL = "html_url"
        }
    }

    package struct Suite: Sendable, Equatable, Decodable {
        package let id: Int64
        package let headSHA: String
        package let status: String
        package let conclusion: String?

        package init(id: Int64, headSHA: String, status: String, conclusion: String?) {
            self.id = id
            self.headSHA = headSHA
            self.status = status
            self.conclusion = conclusion
        }

        enum CodingKeys: String, CodingKey {
            case id, status, conclusion
            case headSHA = "head_sha"
        }
    }

    /// A commit status: `success`, `pending`, `failure` or `error`.
    package struct Status: Sendable, Equatable, Decodable {
        package let sha: String
        package let context: String
        package let state: String
        package let targetURL: URL?

        package init(sha: String, context: String, state: String, targetURL: URL?) {
            self.sha = sha
            self.context = context
            self.state = state
            self.targetURL = targetURL
        }

        enum CodingKeys: String, CodingKey {
            case sha, context, state
            case targetURL = "target_url"
        }
    }

    package struct Push: Sendable, Equatable, Decodable {
        package let ref: String
        package let before: String
        package let after: String

        package init(ref: String, before: String, after: String) {
            self.ref = ref
            self.before = before
            self.after = after
        }
    }

    package struct PullRequestChange: Sendable, Equatable, Decodable {
        package let action: String
        package let number: Int
        package let title: String
        package let author: String
        package let headSHA: String
        package let isDraft: Bool
        package let requestedReviewers: [String]
        package let requestedTeams: [String]
        package let htmlURL: URL?

        package init(action: String, number: Int, title: String, author: String, headSHA: String,
                     isDraft: Bool, requestedReviewers: [String], requestedTeams: [String], htmlURL: URL?) {
            self.action = action
            self.number = number
            self.title = title
            self.author = author
            self.headSHA = headSHA
            self.isDraft = isDraft
            self.requestedReviewers = requestedReviewers
            self.requestedTeams = requestedTeams
            self.htmlURL = htmlURL
        }

        enum CodingKeys: String, CodingKey {
            case action, number, title, author
            case headSHA = "head_sha", isDraft = "draft", htmlURL = "html_url"
            case requestedReviewers = "requested_reviewers", requestedTeams = "requested_teams"
        }
    }

    package struct Review: Sendable, Equatable, Decodable {
        package let action: String
        package let number: Int
        package let reviewer: String
        package let state: String

        package init(action: String, number: Int, reviewer: String, state: String) {
            self.action = action
            self.number = number
            self.reviewer = reviewer
            self.state = state
        }
    }
}

/// What one SSE frame from the relay means.
package enum GitHubStreamMessage: Sendable, Equatable {
    case event(GitHubEvent)
    /// Drop the buffered position and take a new snapshot.
    case resync
    /// The stream is alive; nothing changed.
    case ping

    /// The message a frame carries, or nil when it is malformed (the stream
    /// skips it). `event` is the frame's `event:` field, nil when absent.
    package static func decode(event: String?, data: String) -> GitHubStreamMessage? {
        switch event {
        case "resync": return .resync
        case "ping": return .ping
        case nil, "github", "message": break
        default: return nil
        }
        let bytes = Data(data.utf8)
        guard let envelope = try? JSONDecoder().decode(Envelope.self, from: bytes),
              let id = UInt64(envelope.id), let repo = RepoKey(fullName: envelope.repo) else { return nil }
        func payload<T: Decodable>(_ type: T.Type) -> T? {
            try? JSONDecoder().decode(Typed<T>.self, from: bytes).payload
        }
        let kind: GitHubEvent.Kind?
        switch envelope.kind {
        case "check_run": kind = payload(GitHubEvent.Run.self).map { .checkRun($0) }
        case "check_suite": kind = payload(GitHubEvent.Suite.self).map { .checkSuite($0) }
        case "workflow_run": kind = payload(GitHubEvent.Run.self).map { .workflowRun($0) }
        case "status": kind = payload(GitHubEvent.Status.self).map { .status($0) }
        case "push": kind = payload(GitHubEvent.Push.self).map { .push($0) }
        case "pull_request": kind = payload(GitHubEvent.PullRequestChange.self).map { .pullRequest($0) }
        case "pull_request_review": kind = payload(GitHubEvent.Review.self).map { .pullRequestReview($0) }
        default: kind = .unknown(envelope.kind)
        }
        return kind.map { .event(GitHubEvent(id: id, repo: repo, kind: $0)) }
    }

    private struct Envelope: Decodable {
        let id: String
        let repo: String
        let kind: String
    }

    /// The same frame again, its payload decoded as the kind says.
    private struct Typed<T: Decodable>: Decodable {
        let payload: T
    }
}

/// Turns the stream's lines into messages, by the SSE rules this relay uses:
/// `field: value` lines, `:` comments, a blank line ending a frame, multi-line
/// `data` joined with newlines. Fed one line at a time, without its newline.
package struct GitHubSSEParser: Sendable {
    /// The last `id:` seen, for the `Last-Event-ID` header on reconnect.
    package private(set) var lastEventID: String?
    private var event: String?
    private var data: [String] = []
    private var hasFields = false

    package init() {}

    package mutating func feed(line raw: String) -> GitHubStreamMessage? {
        let line = raw.hasSuffix("\r") ? String(raw.dropLast()) : raw
        if line.isEmpty {
            defer { event = nil; data = []; hasFields = false }
            guard hasFields else { return nil }
            return GitHubStreamMessage.decode(event: event, data: data.joined(separator: "\n"))
        }
        if line.hasPrefix(":") {
            return line.dropFirst().trimmingCharacters(in: .whitespaces) == "ping" ? .ping : nil
        }
        let field: Substring
        var value: Substring
        if let colon = line.firstIndex(of: ":") {
            field = line[..<colon]
            value = line[line.index(after: colon)...]
            if value.hasPrefix(" ") { value = value.dropFirst() }
        } else {
            field = Substring(line)
            value = ""
        }
        switch field {
        case "event": event = String(value); hasFields = true
        case "data": data.append(String(value)); hasFields = true
        case "id": lastEventID = String(value)
        default: break
        }
        return nil
    }
}
