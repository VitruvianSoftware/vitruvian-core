// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 VitruvianSoftware

import Foundation
import VitruvianToolKit
import VitruvianToolProtocol

/// The two pages the app draws for the tool, as pure functions of what the
/// tool knows. The island page lists the watched repositories and the
/// person's pull requests; the Settings panel is the account. Every word
/// is `Words`, so the app draws the person's language.
public enum Pages {
    // The ids the events name.
    public static let refreshButton = "refresh"
    public static let rerunButton = "rerun"
    public static let pullsList = "pulls"
    public static let useCLIButton = "useCLI"
    public static let tokenField = "token"
    public static let useCodeButton = "useCode"
    public static let cancelButton = "cancel"
    public static let signOutButton = "signOut"
    /// The newest pull requests a page lists, and the most of a title it
    /// shows: a page is at most 256 KB and a list 200 rows, and each row's
    /// standing is in fifteen languages.
    public static let maxPullRows = 100
    public static let maxTitleLength = 120

    /// The SF Symbol for a colour.
    public static func icon(for verdict: Verdict) -> String {
        switch verdict {
        case .green: return "checkmark.circle.fill"
        case .amber: return "clock.fill"
        case .red: return "xmark.circle.fill"
        case .grey: return "circle.dashed"
        }
    }

    /// A repository row's id, and the repository it names.
    public static func repoRow(_ repo: RepoKey) -> String { "repo:\(repo.fullName)" }
    public static func repo(ofRow id: String) -> RepoKey? {
        guard id.hasPrefix("repo:") else { return nil }
        return RepoKey(fullName: String(id.dropFirst("repo:".count)))
    }

    /// A pull request row's id, and what it names.
    public static func pullRow(_ repo: RepoKey, _ number: Int) -> String { "pr:\(repo.fullName)#\(number)" }
    public static func pull(ofRow id: String) -> (repo: RepoKey, number: Int)? {
        guard id.hasPrefix("pr:"), let hash = id.lastIndex(of: "#"),
              let repo = RepoKey(fullName: String(id[id.index(id.startIndex, offsetBy: 3)..<hash])),
              let number = Int(id[id.index(after: hash)...]) else { return nil }
        return (repo, number)
    }

    // MARK: The island

    public static func island(summary: GitHubSummary, auth: AuthState) -> UITree {
        guard auth.isSignedIn else {
            return UITree {
                text(Words.text("notSignedInIsland"), style: .secondary)
                if case .failed(let failure) = auth { text(failureText(failure), style: .caption) }
            }
        }
        return UITree {
            for repository in summary.repositories {
                row(repoRow(repository.repo), .plain(repository.repo.fullName),
                    subtitle: repository.passed + repository.failed + repository.running == 0
                        ? Words.text("noChecks")
                        : Words.format("checksFormat", String(repository.passed), String(repository.failed),
                                       String(repository.running)),
                    icon: icon(for: repository.verdict))
            }
            if summary.awaitingApproval { text(Words.text("awaitingApproval"), style: .caption) }
            heading(Words.text("pullRequests"))
            if summary.pullRequests.isEmpty {
                text(Words.text("noPulls"), style: .secondary)
            } else {
                list(pullsList, summary.pullRequests.prefix(maxPullRows).map { row in
                    let pull = row.pullRequest
                    let standing: String
                    switch pull.reviewState {
                    case .approved: standing = "approved"
                    case .changesRequested: standing = "changesRequested"
                    case .pending: standing = "reviewPending"
                    }
                    return UIListRow(id: pullRow(row.repo, pull.number),
                                     title: .plain("#\(pull.number) \(pull.title.prefix(maxTitleLength))"),
                                     subtitle: .plain("\(row.repo.fullName) · @\(pull.author)"),
                                     icon: icon(for: row.verdict),
                                     trailing: Words.text(pull.isDraft ? "draft" : standing))
                })
            }
            button(refreshButton, Words.text("refresh"))
            if summary.repositories.contains(where: { !$0.failedRunIDs.isEmpty }) {
                button(rerunButton, Words.text("rerunFailed"), style: .destructive)
            }
        }
    }

    // MARK: Settings

    /// What the Settings panel is drawn from.
    public struct SettingsInput: Equatable, Sendable {
        public var auth: AuthState
        /// The GitHub CLI's login, when it has one.
        public var cliLogin: String?
        /// The mouse command in use, or nil when none was found.
        public var mouseCommand: String?
        /// The path the person set does not run.
        public var mouseConfiguredIgnored: Bool

        public init(auth: AuthState, cliLogin: String? = nil, mouseCommand: String? = nil,
                    mouseConfiguredIgnored: Bool = false) {
            self.auth = auth
            self.cliLogin = cliLogin
            self.mouseCommand = mouseCommand
            self.mouseConfiguredIgnored = mouseConfiguredIgnored
        }
    }

    public static func settings(_ input: SettingsInput) -> UITree {
        UITree {
            heading(Words.text("account"))
            switch input.auth {
            case .signedOut:
                text(Words.text("notConnected"), style: .secondary)
                signInControls(input)
            case .checking:
                text(Words.text("connecting"), style: .secondary)
                progress()
            case .deviceFlow(let userCode, let verificationURL):
                text(Words.text("codeHint"))
                text(.plain(userCode), style: .monospaced)
                link(Words.text("openDevicePage"), url: verificationURL.absoluteString)
                button(cancelButton, Words.text("cancel"))
            case .signedIn(let login):
                text(Words.format("connectedAsFormat", login))
                button(signOutButton, Words.text("disconnect"), style: .destructive)
            case .failed(let failure):
                text(failureText(failure), style: .secondary)
                signInControls(input)
            }
            text(Words.text("browserStays"), style: .caption)
            divider()
            if let command = input.mouseCommand {
                text(Words.format("mouseFoundFormat", command), style: .caption)
            } else {
                text(Words.text("mouseMissingHomebrew"), style: .caption)
            }
            if input.mouseConfiguredIgnored { text(Words.text("mouseCommandIgnored"), style: .caption) }
        }
    }

    @UITreeBuilder
    private static func signInControls(_ input: SettingsInput) -> [UIBlock] {
        if let login = input.cliLogin {
            button(useCLIButton, Words.format("useCLIFormat", login), style: .prominent)
        }
        field(tokenField, title: Words.text("token"), placeholder: Words.text("tokenPlaceholder"), kind: .secret)
        button(useCodeButton, Words.text("useCode"))
    }

    /// What Settings says about a sign-in that did not finish.
    public static func failureText(_ failure: AuthFailure) -> UIText {
        switch failure {
        case .notConfigured: return Words.text("notConfiguredHint")
        case .unreachable: return Words.text("gitHubUnreachable")
        case .refused(let status): return Words.format("gitHubRefusedFormat", String(status))
        case .tokenRejected: return Words.text("tokenRejected")
        case .deviceFlow(.denied): return Words.text("denied")
        case .deviceFlow(.expired): return Words.text("codeExpired")
        case .deviceFlow(.other(let reason)): return Words.format("deviceFlowFormat", reason)
        }
    }
}
