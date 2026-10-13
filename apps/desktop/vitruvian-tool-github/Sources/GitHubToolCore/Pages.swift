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

    // A row's id is a name the protocol will read: letters, digits, hyphen
    // and underscore in parts joined by dots, at most
    // `ManifestLimits.maxNameLength` long. The app draws none of a page with
    // one id that is not (1.0.0 sent `repo:acme/web` and `pr:acme/web#2`,
    // and the island page was a spinner for ever). So an owner and a name
    // are each written with `_` as `__` and `.` as `_d`, which leaves no dot
    // in a part and reads back exactly.

    /// A repository row's id, and the repository it names.
    public static func repoRow(_ repo: RepoKey) -> String {
        named("repo.\(part(repo.owner)).\(part(repo.name))", else: "repo.x\(mark(repo.fullName))")
    }

    public static func repo(ofRow id: String) -> RepoKey? {
        let parts = id.split(separator: ".", omittingEmptySubsequences: false)
        guard parts.count == 3, parts[0] == "repo", let owner = written(parts[1]), let name = written(parts[2])
        else { return nil }
        return RepoKey(fullName: "\(owner)/\(name)")
    }

    /// A pull request row's id, and what it names.
    public static func pullRow(_ repo: RepoKey, _ number: Int) -> String {
        named("pr.\(part(repo.owner)).\(part(repo.name)).\(number)", else: "pr.x\(mark(repo.fullName)).\(number)")
    }

    public static func pull(ofRow id: String) -> (repo: RepoKey, number: Int)? {
        let parts = id.split(separator: ".", omittingEmptySubsequences: false)
        guard parts.count == 4, parts[0] == "pr", let owner = written(parts[1]), let name = written(parts[2]),
              let repo = RepoKey(fullName: "\(owner)/\(name)"), let number = Int(parts[3]) else { return nil }
        return (repo, number)
    }

    /// `id` when the protocol will read it, or `short`: a repository whose
    /// name is too long for an id still has a row, and a tap on it does
    /// nothing, where an id that is not well formed would cost the page.
    private static func named(_ id: String, else short: String) -> String {
        ManifestRules.isWellFormedName(id) ? id : short
    }

    /// One part of an id, from an owner or a name.
    private static func part(_ name: String) -> String {
        name.replacingOccurrences(of: "_", with: "__").replacingOccurrences(of: ".", with: "_d")
    }

    /// The owner or name a part was written from, or nil when it is none.
    private static func written(_ part: Substring) -> String? {
        var name = ""
        var escaped = false
        for character in part {
            if escaped {
                switch character {
                case "_": name.append("_")
                case "d": name.append(".")
                default: return nil
                }
                escaped = false
            } else if character == "_" {
                escaped = true
            } else {
                name.append(character)
            }
        }
        return escaped || name.isEmpty ? nil : name
    }

    /// Sixteen hex digits that stand for a name too long to write out: the
    /// same for the same name every time, so a row keeps its id from page to
    /// page (FNV-1a, 64 bits).
    private static func mark(_ name: String) -> String {
        var hash: UInt64 = 0xcbf2_9ce4_8422_2325
        for byte in name.utf8 {
            hash ^= UInt64(byte)
            hash = hash &* 0x0000_0100_0000_01b3
        }
        let digits = String(hash, radix: 16)
        return String(repeating: "0", count: 16 - digits.count) + digits
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
