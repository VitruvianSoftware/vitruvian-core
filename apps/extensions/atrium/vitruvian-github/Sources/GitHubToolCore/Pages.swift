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
    public static let backButton = "back"
    public static let refreshButton = "refresh"
    public static let rerunButton = "rerun"
    public static let pullsList = "pulls"
    public static let checksList = "checks"
    public static let useCLIButton = "useCLI"
    public static let tokenField = "token"
    public static let useCodeButton = "useCode"
    public static let cancelButton = "cancel"
    public static let signOutButton = "signOut"
    public static let repoPicker = "repoPicker"
    public static let openRepoButton = "openRepo"
    /// Opens the person's pull requests on GitHub, as the `openPulls`
    /// command does: the island's Tools grid leaves an extension's commands
    /// to its own page.
    public static let openPullsButton = "openPulls"
    public static let queueList = "queue"
    public static let branchChecksList = "branchChecks"
    public static let copyCodeButton = "copyCode"
    /// Where a classic token is made, with what the tool reads filled in:
    /// `repo` and `workflow`, as the app's GitHub feature asked, and
    /// `read:org`, without which `GET /user/teams` is refused and a review
    /// asked of the person's team is missed.
    public static let newTokenURL =
        "https://github.com/settings/tokens/new?description=Vitruvian%20Desktop&scopes=repo,workflow,read:org"
    /// The newest pull requests a page lists, the most checks a pull request
    /// page lists, and the most of a title it shows: a page is at most
    /// 256 KB and a list 200 rows, and each row's standing is in fifteen
    /// languages.
    public static let maxPullRows = 100
    public static let maxCheckRows = 150
    public static let maxTitleLength = 120
    /// The most merge-queue entries a page lists, and the most repositories
    /// the picker offers (the protocol's limit on a choice).
    public static let maxQueueRows = 50
    public static let maxPickerOptions = UILimits.maxChoiceOptions

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
    // and the island page was a spinner for ever). So an owner, a name and a
    // check key are each written with `_` as `__`, `.` as `_d` and `:` as
    // `_c`, which leaves no dot or colon in a part and reads back exactly.

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

    /// A pull request detail row's id, and what it names.
    public static func pullDetailRow(_ repo: RepoKey, _ number: Int) -> String {
        named("prdetail.\(part(repo.owner)).\(part(repo.name)).\(number)",
              else: "prdetail.x\(mark(repo.fullName)).\(number)")
    }

    public static func pullDetail(ofRow id: String) -> (repo: RepoKey, number: Int)? {
        let parts = id.split(separator: ".", omittingEmptySubsequences: false)
        guard parts.count == 4, parts[0] == "prdetail", let owner = written(parts[1]), let name = written(parts[2]),
              let repo = RepoKey(fullName: "\(owner)/\(name)"), let number = Int(parts[3]) else { return nil }
        return (repo, number)
    }

    /// A check run row's id, and what it names.
    public static func checkRow(_ repo: RepoKey, _ number: Int, _ runID: String) -> String {
        named("check.\(part(repo.owner)).\(part(repo.name)).\(number).\(part(runID))",
              else: "check.x\(mark(repo.fullName)).\(number).x\(mark(runID))")
    }

    public static func check(ofRow id: String) -> (repo: RepoKey, number: Int, runID: String)? {
        let parts = id.split(separator: ".", omittingEmptySubsequences: false)
        guard parts.count == 5, parts[0] == "check", let owner = written(parts[1]), let name = written(parts[2]),
              let repo = RepoKey(fullName: "\(owner)/\(name)"), let number = Int(parts[3]),
              let runID = written(parts[4]) else { return nil }
        return (repo, number, runID)
    }

    /// A repository's header row on its own page, and the repository it names.
    public static func repoDetailRow(_ repo: RepoKey) -> String {
        named("repodetail.\(part(repo.owner)).\(part(repo.name))", else: "repodetail.x\(mark(repo.fullName))")
    }

    public static func repoDetail(ofRow id: String) -> RepoKey? {
        let parts = id.split(separator: ".", omittingEmptySubsequences: false)
        guard parts.count == 3, parts[0] == "repodetail", let owner = written(parts[1]), let name = written(parts[2])
        else { return nil }
        return RepoKey(fullName: "\(owner)/\(name)")
    }

    /// A default-branch check row's id, and what it names.
    public static func branchCheckRow(_ repo: RepoKey, _ runID: String) -> String {
        named("branchcheck.\(part(repo.owner)).\(part(repo.name)).\(part(runID))",
              else: "branchcheck.x\(mark(repo.fullName)).x\(mark(runID))")
    }

    public static func branchCheck(ofRow id: String) -> (repo: RepoKey, runID: String)? {
        let parts = id.split(separator: ".", omittingEmptySubsequences: false)
        guard parts.count == 4, parts[0] == "branchcheck", let owner = written(parts[1]), let name = written(parts[2]),
              let repo = RepoKey(fullName: "\(owner)/\(name)"), let runID = written(parts[3]) else { return nil }
        return (repo, runID)
    }

    /// A merge-queue entry's row id, and what it names.
    public static func queueRow(_ repo: RepoKey, _ number: Int) -> String {
        named("queue.\(part(repo.owner)).\(part(repo.name)).\(number)", else: "queue.x\(mark(repo.fullName)).\(number)")
    }

    public static func queueEntry(ofRow id: String) -> (repo: RepoKey, number: Int)? {
        let parts = id.split(separator: ".", omittingEmptySubsequences: false)
        guard parts.count == 4, parts[0] == "queue", let owner = written(parts[1]), let name = written(parts[2]),
              let repo = RepoKey(fullName: "\(owner)/\(name)"), let number = Int(parts[3]) else { return nil }
        return (repo, number)
    }

    /// The row under a long merge queue that opens the queue on GitHub.
    public static func queuePageRow(_ repo: RepoKey) -> String {
        named("mergequeue.\(part(repo.owner)).\(part(repo.name))", else: "mergequeue.x\(mark(repo.fullName))")
    }

    public static func queuePage(ofRow id: String) -> RepoKey? {
        let parts = id.split(separator: ".", omittingEmptySubsequences: false)
        guard parts.count == 3, parts[0] == "mergequeue", let owner = written(parts[1]), let name = written(parts[2])
        else { return nil }
        return RepoKey(fullName: "\(owner)/\(name)")
    }

    /// `id` when the protocol will read it, or `short`: a repository whose
    /// name is too long for an id still has a row, and a tap on it does
    /// nothing, where an id that is not well formed would cost the page.
    private static func named(_ id: String, else short: String) -> String {
        ManifestRules.isWellFormedName(id) ? id : short
    }

    /// One part of an id, from an owner, a name or a check key.
    private static func part(_ name: String) -> String {
        name.replacingOccurrences(of: "_", with: "__")
            .replacingOccurrences(of: ".", with: "_d")
            .replacingOccurrences(of: ":", with: "_c")
    }

    /// The owner, name or check key a part was written from, or nil when it is none.
    private static func written(_ part: Substring) -> String? {
        var name = ""
        var escaped = false
        for character in part {
            if escaped {
                switch character {
                case "_": name.append("_")
                case "d": name.append(".")
                case "c": name.append(":")
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

    private static func reviewStanding(for state: ReviewState) -> String {
        switch state {
        case .approved: return "approved"
        case .changesRequested: return "changesRequested"
        case .pending: return "reviewPending"
        }
    }

    private static func checkStanding(for verdict: Verdict) -> String? {
        switch verdict {
        case .red: return "checkFailed"
        case .amber: return "checkRunning"
        case .green: return "checkPassed"
        case .grey: return nil
        }
    }

    private static func checkOrder(_ verdict: Verdict) -> Int {
        switch verdict {
        case .red: return 0
        case .amber: return 1
        case .green: return 2
        case .grey: return 3
        }
    }

    /// Failing first, then running, then passed, then grey; by name, then key.
    public static func sortedChecks(_ checks: some Sequence<CheckRun>) -> [CheckRun] {
        checks.sorted { lhs, rhs in
            let leftOrder = checkOrder(Verdicts.verdict(for: [lhs]))
            let rightOrder = checkOrder(Verdicts.verdict(for: [rhs]))
            if leftOrder != rightOrder { return leftOrder < rightOrder }
            if lhs.name != rhs.name { return lhs.name < rhs.name }
            return lhs.key < rhs.key
        }
    }

    /// The watched repository the island's picker, its merge queue and its
    /// Open in GitHub button are about: `focus` when it is watched, else
    /// the first.
    public static func focused(_ summary: GitHubSummary, focus: RepoKey?) -> GitHubSummary.Repository? {
        summary.repositories.first { $0.repo == focus } ?? summary.repositories.first
    }

    /// `https://github.com/owner/name`.
    public static func webURL(_ repo: RepoKey) -> String { "https://github.com/\(repo.fullName)" }

    /// `Updated at 13:46:40`, the time written as each language writes it,
    /// with seconds, in `timeZone`.
    public static func lastUpdatedText(_ date: Date, timeZone: TimeZone = .current) -> UIText {
        Words.format("lastUpdatedFormat") { language in
            let formatter = DateFormatter()
            formatter.locale = Locale(identifier: language)
            formatter.timeZone = timeZone
            formatter.dateStyle = .none
            formatter.timeStyle = .medium
            return formatter.string(from: date)
        }
    }

    /// The island page. `focus` is the repository picked; `offersPicker`
    /// says the app draws a `choice` (3.48 and later), and with more than
    /// one repository watched the page offers one. `lastUpdated` is when
    /// GitHub was last read.
    public static func island(summary: GitHubSummary, auth: AuthState, focus: RepoKey? = nil,
                              offersPicker: Bool = false, lastUpdated: Date? = nil,
                              timeZone: TimeZone = .current) -> UITree {
        guard auth.isSignedIn else {
            return UITree {
                text(Words.text("notSignedInIsland"), style: .secondary)
                if case .failed(let failure) = auth { text(failureText(failure), style: .caption) }
            }
        }
        let focused = focused(summary, focus: focus)
        let pickable = summary.repositories.map(\.repo)
            .filter { $0.fullName.unicodeScalars.count <= UILimits.maxChoiceValueLength }
            .prefix(maxPickerOptions)
        return UITree {
            if offersPicker, let focused, pickable.count > 1 {
                // A value past the choice's limit would cost the whole page,
                // so a name that long is shown cut, as a row nobody picks.
                choice(repoPicker, title: Words.text("repository"), value: pickerValue(focused.repo),
                       options: pickable.map { UIChoiceOption(value: $0.fullName, title: .plain($0.fullName)) })
            }
            for repository in summary.repositories {
                row(repoRow(repository.repo), .plain(repository.repo.fullName),
                    subtitle: repository.passed + repository.failed + repository.running == 0
                        ? Words.text("noChecks")
                        : Words.format("checksFormat", String(repository.passed), String(repository.failed),
                                       String(repository.running)),
                    icon: icon(for: repository.verdict),
                    trailing: repository.branchAndHead.map { .plain(String($0.prefix(maxTitleLength))) })
            }
            if summary.awaitingApproval { text(Words.text("awaitingApproval"), style: .caption) }
            if let focused { mergeQueueBlocks(focused.repo, focused.mergeQueue) }
            heading(Words.text("pullRequests"))
            if summary.pullRequests.isEmpty {
                text(Words.text("noPulls"), style: .secondary)
            } else {
                list(pullsList, summary.pullRequests.prefix(maxPullRows).map { row in
                    let pull = row.pullRequest
                    let standing = reviewStanding(for: pull.reviewState)
                    return UIListRow(id: pullRow(row.repo, pull.number),
                                     title: .plain("#\(pull.number) \(pull.title.prefix(maxTitleLength))"),
                                     subtitle: .plain("\(row.repo.fullName) · @\(pull.author)"),
                                     icon: icon(for: row.verdict),
                                     trailing: Words.text(pull.isDraft ? "draft" : standing))
                })
            }
            button(openPullsButton, Words.text("openMyPulls"))
            button(refreshButton, Words.text("refresh"))
            if focused != nil { button(openRepoButton, Words.text("openInGitHub")) }
            if summary.repositories.contains(where: { !$0.failedRunIDs.isEmpty }) {
                button(rerunButton, Words.text("rerunFailed"), style: .destructive)
            }
            if let lastUpdated { text(lastUpdatedText(lastUpdated, timeZone: timeZone), style: .caption) }
        }
    }

    /// The picker's value for a repository: its name, or, past what a
    /// choice's value may hold, the name cut short with an ellipsis.
    static func pickerValue(_ repo: RepoKey) -> String {
        let name = repo.fullName
        guard name.unicodeScalars.count > UILimits.maxChoiceValueLength else { return name }
        return String(String.UnicodeScalarView(name.unicodeScalars.prefix(UILimits.maxChoiceValueLength - 1))) + "…"
    }

    private static func queueStanding(for state: MergeQueueEntryState) -> (word: String, icon: String) {
        switch state {
        case .queued: return ("queueQueued", "clock")
        case .awaitingChecks: return ("queueAwaitingChecks", "clock.fill")
        case .mergeable: return ("queueMergeable", "checkmark.circle.fill")
        case .unmergeable: return ("queueUnmergeable", "xmark.circle.fill")
        case .locked: return ("queueLocked", "lock.fill")
        case .other: return ("queueQueued", "circle.dashed")
        }
    }

    /// A repository's merge queue: a heading, then its entries in queue
    /// order or a line that it is empty; nothing when the branch has no
    /// queue, or GitHub did not say.
    @UITreeBuilder
    static func mergeQueueBlocks(_ repo: RepoKey, _ queue: MergeQueue?) -> [UIBlock] {
        if let queue {
            heading(Words.text("mergeQueue"))
            if queue.entries.isEmpty {
                text(Words.text("mergeQueueEmpty"), style: .secondary)
            } else {
                list(queueList, queueRows(repo, queue))
            }
        }
    }

    static func queueRows(_ repo: RepoKey, _ queue: MergeQueue) -> [UIListRow] {
        let ordered = queue.ordered
        var rows = ordered.prefix(maxQueueRows).map { entry -> UIListRow in
            let standing = queueStanding(for: entry.state)
            let subtitle: UIText?
            switch (entry.position, entry.author.isEmpty) {
            case (let position?, false):
                subtitle = Words.format("queueEntryFormat", String(position), entry.author)
            case (let position?, true):
                subtitle = Words.format("mergeQueuePositionFormat", String(position))
            case (nil, false):
                subtitle = .plain("@\(entry.author)")
            case (nil, true):
                subtitle = nil
            }
            return UIListRow(id: queueRow(repo, entry.number),
                             title: .plain("#\(entry.number) \(entry.title.prefix(maxTitleLength))"),
                             subtitle: subtitle, icon: standing.icon, trailing: Words.text(standing.word))
        }
        let overflow = ordered.count - maxQueueRows
        if overflow > 0 {
            rows.append(UIListRow(id: queuePageRow(repo),
                                  title: Words.format("moreChecksOnGitHubFormat", String(overflow)),
                                  icon: "arrow.up.right"))
        }
        return rows
    }

    /// One repository's default branch, one step in from the island page:
    /// its head, its merge queue, and its checks, failing first. The header
    /// row opens the repository's Actions page.
    public static func repoDetail(repo: RepoKey, state: RepoState?) -> UITree {
        let summary = GitHubSummary(states: state.map { [repo: $0] } ?? [:], watched: [repo]).repositories.first
        let sorted = sortedChecks(state.map { Array($0.checks.values) } ?? [])
        var rows = sorted.prefix(maxCheckRows).map { check in
            let verdict = Verdicts.verdict(for: [check])
            return UIListRow(id: branchCheckRow(repo, check.key),
                             title: .plain(String(check.name.prefix(maxTitleLength))),
                             icon: icon(for: verdict),
                             trailing: checkStanding(for: verdict).map(Words.text))
        }
        let overflow = sorted.count - maxCheckRows
        if overflow > 0 {
            rows.append(UIListRow(id: repoDetailRow(repo),
                                  title: Words.format("moreChecksOnGitHubFormat", String(overflow)),
                                  icon: "arrow.up.right"))
        }
        return UITree {
            button(backButton, Words.text("back"))
            row(repoDetailRow(repo), .plain(repo.fullName),
                subtitle: summary?.branchAndHead.map { .plain(String($0.prefix(maxTitleLength))) },
                icon: icon(for: summary?.verdict ?? .grey),
                trailing: Words.text("openInGitHub"))
            mergeQueueBlocks(repo, state?.mergeQueue)
            heading(Words.text("checks"))
            if rows.isEmpty {
                text(Words.text("noChecks"), style: .secondary)
            } else {
                list(branchChecksList, rows)
            }
        }
    }

    /// One pull request's check list, one step in from the island page.
    public static func pullDetail(repo: RepoKey, pull: PullRequest) -> UITree {
        let ordered = sortedChecks(pull.checks.values)
        var rows = ordered.prefix(maxCheckRows).map { check in
            let verdict = Verdicts.verdict(for: [check])
            return UIListRow(id: checkRow(repo, pull.number, check.key),
                             title: .plain(String(check.name.prefix(maxTitleLength))),
                             icon: icon(for: verdict),
                             trailing: checkStanding(for: verdict).map(Words.text))
        }
        let overflow = ordered.count - maxCheckRows
        if overflow > 0 {
            rows.append(UIListRow(id: pullDetailRow(repo, pull.number),
                                  title: Words.format("moreChecksOnGitHubFormat", String(overflow)),
                                  icon: "arrow.up.right"))
        }
        let standing = reviewStanding(for: pull.reviewState)
        return UITree {
            button(backButton, Words.text("back"))
            row(pullDetailRow(repo, pull.number),
                .plain("#\(pull.number) \(pull.title.prefix(maxTitleLength))"),
                subtitle: .plain("\(repo.fullName) · @\(pull.author)"),
                icon: icon(for: Verdicts.verdict(for: pull)),
                trailing: Words.text(pull.isDraft ? "draft" : standing))
            if let queue = pull.mergeQueue {
                row(nil,
                    queue.position.map { Words.format("mergeQueuePositionFormat", String($0)) }
                        ?? Words.text("mergeQueueQueued"),
                    icon: "arrow.triangle.merge")
            }
            heading(Words.text("checks"))
            if rows.isEmpty {
                text(Words.text("noChecks"), style: .secondary)
            } else {
                list(checksList, rows)
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
        /// The person shows the status on the mouse.
        public var mouseIndicator: Bool

        public init(auth: AuthState, cliLogin: String? = nil, mouseCommand: String? = nil,
                    mouseConfiguredIgnored: Bool = false, mouseIndicator: Bool = true) {
            self.auth = auth
            self.cliLogin = cliLogin
            self.mouseCommand = mouseCommand
            self.mouseConfiguredIgnored = mouseConfiguredIgnored
            self.mouseIndicator = mouseIndicator
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
                button(copyCodeButton, Words.text("copy"))
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
            // Each light on demand, as the app's GitHub feature had a Test
            // button beside each: only with a mouse command to run, and the
            // mouse showing the status.
            if input.mouseCommand != nil, input.mouseIndicator {
                text(Words.text("mouseTestHint"), style: .caption)
                for test in MouseTest.allCases { button(test.rawValue, Words.text(test.wordKey)) }
            }
        }
    }

    @UITreeBuilder
    private static func signInControls(_ input: SettingsInput) -> [UIBlock] {
        if let login = input.cliLogin {
            button(useCLIButton, Words.format("useCLIFormat", login), style: .prominent)
        }
        field(tokenField, title: Words.text("token"), placeholder: Words.text("tokenPlaceholder"), kind: .secret)
        link(Words.text("createToken"), url: newTokenURL)
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
