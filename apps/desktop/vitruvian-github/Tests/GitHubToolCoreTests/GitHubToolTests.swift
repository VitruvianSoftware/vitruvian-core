// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 VitruvianSoftware

import XCTest

import VitruvianToolKit
import VitruvianToolProtocol
@testable import GitHubToolCore

/// The app, recording. Preferences are a dictionary; pages and messages are
/// kept as they come.
final class FakeHost: ToolHost {
    var language = "en-US"
    var values: [String: JSONValue] = [:]
    var messages: [String] = []
    var opened: [String] = []
    var logs: [String] = []
    var badges: [Int?] = []
    var statuses: [IslandStatus] = []
    var rendered: [(panel: String, tree: UITree)] = []
    var features: Set<ProtocolFeature> = []
    var copied: [String] = []
    var clipboardTakes = true

    func value(_ key: String) -> JSONValue? { values[key] }
    func setValue(_ value: JSONValue, for key: String) { values[key] = value }
    func showMessage(_ message: String, icon: String) { messages.append(message) }
    func open(_ url: String) -> Bool { opened.append(url); return true }
    func log(_ message: String) { logs.append(message) }
    func badge(count: Int?, dot: Bool) { badges.append(count) }
    func status(_ status: IslandStatus) { statuses.append(status) }
    func render(panel: String, _ tree: UITree) { rendered.append((panel, tree)) }
    func supports(_ feature: ProtocolFeature) -> Bool { features.contains(feature) }
    func copyText(_ text: String) -> Bool {
        guard clipboardTakes else { return false }
        copied.append(text)
        return true
    }
}

final class GitHubToolTests: XCTestCase {
    private var folder: URL!
    private let host = FakeHost()
    private let transport = FakeTransport()
    private var mouse: [[String]] = []
    private var now = Date(timeIntervalSince1970: 1_000_000)
    private var tool: GitHubTool!
    private var secrets: SecretStore!
    private var hosts: URL!

    override func setUp() {
        folder = FileManager.default.temporaryDirectory.appendingPathComponent("github-tool-\(UUID().uuidString)", isDirectory: true)
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        secrets = SecretStore(folder: folder.appendingPathComponent("data", isDirectory: true))
        hosts = folder.appendingPathComponent("hosts.yml")
        answerGitHub()
        tool = make()
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: folder)
    }

    private func make() -> GitHubTool {
        GitHubTool(parts: .init(host: host, api: GitHubAPI(transport: transport, apiURL: URL(string: "https://api.test")!,
                                                            webURL: URL(string: "https://web.test")!),
                                secrets: secrets, cliHosts: hosts, now: { [unowned self] in now },
                                environment: ["PATH": "/usr/bin"], home: "/Users/me",
                                isExecutable: { $0 == "/usr/bin/gravastar-mouse" },
                                runMouse: { [unowned self] binary, arguments in mouse.append([binary] + arguments) }))
    }

    /// GitHub as a fake: one repository, green, with one pull request.
    private func answerGitHub(login: String = "james", conclusion: String = "success") {
        transport.answers["/user"] = (200, #"{"login": "\#(login)"}"#)
        transport.answers["/user/teams"] = (200, "[]")
        transport.answers["/repos/VitruvianSoftware/vitruvian-core"] = (200, #"{"default_branch": "main"}"#)
        transport.answers["/repos/VitruvianSoftware/vitruvian-core/commits/main"] = (200, #"{"sha": "h1"}"#)
        transport.answers["/repos/VitruvianSoftware/vitruvian-core/commits/h1/check-runs?per_page=100"] = (200, #"{"check_runs": []}"#)
        transport.answers["/repos/VitruvianSoftware/vitruvian-core/actions/runs?branch=main&per_page=10"] =
            (200, #"{"workflow_runs": [{"id": 9, "name": "ci", "head_sha": "h1", "status": "completed", "conclusion": "\#(conclusion)", "html_url": null}]}"#)
        transport.answers["/repos/VitruvianSoftware/vitruvian-core/actions/runs?branch=main&per_page=10&status=waiting"] =
            (200, #"{"workflow_runs": []}"#)
        transport.answers["/repos/VitruvianSoftware/vitruvian-core/pulls?state=open&per_page=100"] =
            (200, #"[{"number": 3, "title": "Fix", "draft": false, "html_url": "https://github.com/VitruvianSoftware/vitruvian-core/pull/3", "user": {"login": "james"}, "head": {"sha": "p3"}, "requested_reviewers": [], "requested_teams": []}, {"number": 4, "title": "Someone else's", "draft": false, "html_url": "https://github.com/VitruvianSoftware/vitruvian-core/pull/4", "user": {"login": "stranger"}, "head": {"sha": "p4"}, "requested_reviewers": [], "requested_teams": []}]"#)
        transport.answers["/repos/VitruvianSoftware/vitruvian-core/commits/p3/check-runs?per_page=100"] =
            (200, #"{"check_runs": [{"id": 30, "name": "unit", "head_sha": "p3", "status": "completed", "conclusion": "success", "html_url": "https://github.com/VitruvianSoftware/vitruvian-core/runs/30"}]}"#)
        transport.answers["/repos/VitruvianSoftware/vitruvian-core/pulls/3/reviews?per_page=100"] =
            (200, #"[{"user": {"login": "ana"}, "state": "APPROVED"}]"#)
    }

    private func pathsAsked() -> [String] { transport.requests.map { $0.url!.path } }

    // MARK: Starting

    func testAStartWithNothingSavedAndNoCLIStaysSignedOut() {
        tool.start()
        XCTAssertEqual(tool.auth, .signedOut)
        XCTAssertEqual(pathsAsked(), [], "nothing is asked of GitHub without a token")
        XCTAssertEqual(tool.islandPage().kinds, ["text"])
    }

    func testTheTokenTheAppHandedOverIsTakenKeptAndCleared() {
        host.values[GitHubTool.Preference.migratedToken] = .string("gho_fromapp")
        tool.start()
        XCTAssertEqual(secrets.token(), "gho_fromapp", "kept in the tool's own file")
        XCTAssertEqual(host.values[GitHubTool.Preference.migratedToken], .string(""), "and cleared where the app put it")
        XCTAssertEqual(tool.auth, .signedIn(login: "james"))
        XCTAssertEqual(transport.requests.first?.value(forHTTPHeaderField: "Authorization"), "Bearer gho_fromapp")
        XCTAssertTrue(host.logs.contains { $0.contains("handed over") })
    }

    func testAHandedTokenNeverReplacesOneTheToolAlreadyKeeps() throws {
        try secrets.save(token: "gho_mine")
        host.values[GitHubTool.Preference.migratedToken] = .string("gho_fromapp")
        tool.start()
        XCTAssertEqual(secrets.token(), "gho_mine")
        XCTAssertEqual(host.values[GitHubTool.Preference.migratedToken], .string(""), "the handed copy is cleared all the same")
    }

    func testASavedTokenSignsInAndPollsAndSetsTheBadgeAndTheMouse() throws {
        try secrets.save(token: "gho_saved")
        answerGitHub(conclusion: "failure")
        tool.start()
        XCTAssertEqual(tool.auth, .signedIn(login: "james"))
        XCTAssertEqual(tool.summary.repositories.map(\.verdict), [.red])
        XCTAssertEqual(tool.summary.pullRequests.map(\.pullRequest.number), [3],
                       "only pull requests that concern the signed-in person are kept")
        XCTAssertEqual(tool.summary.pullRequests.map(\.verdict), [.green],
                       "the pull request's own check runs set its colour")
        XCTAssertEqual(tool.summary.pullRequests.map(\.pullRequest.reviewState), [.approved],
                       "the pull request's reviews set its standing")
        XCTAssertEqual(host.badges, [1], "one red default branch")
        XCTAssertEqual(mouse, [["/usr/bin/gravastar-mouse", "breathe", "red"]], "the first snapshot writes the mouse")
        XCTAssertEqual(host.rendered.map(\.panel), ["settings", "status", "settings"],
                       "the Settings panel while checking, the island after the poll, then Settings signed in")
        XCTAssertEqual(tool.islandPage().ids, ["repo.VitruvianSoftware.vitruvian-core", "pulls", "openPulls", "refresh", "openRepo", "rerun"])
    }

    func testTheCLIsLoginSignsInWhenNothingIsSaved() throws {
        try "github.com:\n    user: james\n    oauth_token: gho_cli\n".write(to: hosts, atomically: true, encoding: .utf8)
        tool.start()
        XCTAssertEqual(tool.auth, .signedIn(login: "james"))
        XCTAssertEqual(secrets.token(), "gho_cli", "a login GitHub confirmed is kept")
    }

    func testARejectedSavedTokenIsDroppedAndTheCLIsIsNotRetriedOnceRejected() throws {
        try secrets.save(token: "gho_dead")
        transport.answers["/user"] = (401, "{}")
        tool.start()
        XCTAssertEqual(tool.auth, .failed(.tokenRejected))
        XCTAssertNil(secrets.token(), "a dead token is forgotten")
        XCTAssertEqual(host.badges, [])
        try "github.com:\n    oauth_token: gho_dead\n".write(to: hosts, atomically: true, encoding: .utf8)
        tool = make()
        tool.start()
        XCTAssertEqual(tool.auth, .failed(.tokenRejected))
    }

    func testAnUnreachableGitHubKeepsTheTokenAndTriesAgainWhenDue() throws {
        try secrets.save(token: "gho_saved")
        transport.fails = true
        tool.start()
        XCTAssertEqual(tool.auth, .failed(.unreachable))
        XCTAssertEqual(secrets.token(), "gho_saved")
        transport.fails = false
        tool.tick()
        XCTAssertEqual(tool.auth, .failed(.unreachable), "not before the poll is due")
        now = now.addingTimeInterval(31)
        tool.tick()
        XCTAssertEqual(tool.auth, .signedIn(login: "james"))
    }

    // MARK: Polling

    func testPollsArePacedByThePreferencesAndFasterWhileChecksRun() throws {
        try secrets.save(token: "gho_saved")
        host.values[GitHubTool.Preference.pollInterval] = .number(60)
        host.values[GitHubTool.Preference.pollActiveInterval] = .number(7)
        tool.start()
        XCTAssertEqual(tool.nextPollAt, now.addingTimeInterval(60))
        let asked = transport.requests.count
        now = now.addingTimeInterval(59)
        tool.tick()
        XCTAssertEqual(transport.requests.count, asked, "not yet")
        transport.answers["/repos/VitruvianSoftware/vitruvian-core/actions/runs?branch=main&per_page=10"] =
            (200, #"{"workflow_runs": [{"id": 9, "name": "ci", "head_sha": "h1", "status": "in_progress", "conclusion": null, "html_url": null}]}"#)
        now = now.addingTimeInterval(1)
        tool.tick()
        XCTAssertGreaterThan(transport.requests.count, asked)
        XCTAssertEqual(tool.summary.repositories.first?.verdict, .amber)
        XCTAssertEqual(tool.nextPollAt, now.addingTimeInterval(7), "the active pace while something runs")
        XCTAssertEqual(mouse.last, ["/usr/bin/gravastar-mouse", "breathe", "orange"])
        host.values[GitHubTool.Preference.pollActiveInterval] = .number(1)
        now = now.addingTimeInterval(7)
        tool.tick()
        XCTAssertEqual(tool.nextPollAt, now.addingTimeInterval(5), "never faster than five seconds")
    }

    func testUnsetPreferencesPollEveryFifteenSecondsAndEveryFiveWhileChecksRun() throws {
        try secrets.save(token: "gho_saved")
        tool.start()
        XCTAssertEqual(tool.nextPollAt, now.addingTimeInterval(15))
        transport.answers["/repos/VitruvianSoftware/vitruvian-core/actions/runs?branch=main&per_page=10"] =
            (200, #"{"workflow_runs": [{"id": 9, "name": "ci", "head_sha": "h1", "status": "in_progress", "conclusion": null, "html_url": null}]}"#)
        now = now.addingTimeInterval(15)
        tool.tick()
        XCTAssertEqual(tool.nextPollAt, now.addingTimeInterval(5), "the active pace while something runs")
    }

    func testTheManifestDefaultsAreTheIntervalsTheToolFallsBackTo() throws {
        let preferences = try XCTUnwrap(ToolFiles.manifest()?.preferences)
        let defaults = Dictionary(uniqueKeysWithValues: preferences.map { ($0.id, $0.default) })
        XCTAssertEqual(defaults[GitHubTool.Preference.pollInterval], .number(Double(GitHubTool.defaultPollSeconds)))
        XCTAssertEqual(defaults[GitHubTool.Preference.pollActiveInterval], .number(Double(GitHubTool.defaultActivePollSeconds)))
    }

    func testRefreshAsksNowAndSaysSo() throws {
        try secrets.save(token: "gho_saved")
        tool.start()
        let asked = transport.requests.count
        tool.refresh()
        XCTAssertGreaterThan(transport.requests.count, asked)
        XCTAssertEqual(host.messages, ["GitHub refreshed"])
        tool.signOut()
        tool.refresh()
        XCTAssertEqual(host.messages.count, 1, "nothing to refresh when signed out")
    }

    func testA401WhilePollingSignsOutWithoutTheCLIJumpingBackIn() throws {
        try secrets.save(token: "gho_saved")
        tool.start()
        transport.answers["/repos/VitruvianSoftware/vitruvian-core/commits/main"] = (401, "{}")
        now = now.addingTimeInterval(31)
        tool.tick()
        XCTAssertEqual(tool.auth, .failed(.tokenRejected))
        XCTAssertNil(secrets.token())
        XCTAssertNil(tool.nextPollAt)
    }

    func testTheWatchlistAndTheMousePreferencesAreReadWhenTheyChange() throws {
        try secrets.save(token: "gho_saved")
        host.values[GitHubTool.Preference.watchlist] = .string("  ")
        tool.start()
        XCTAssertEqual(tool.watched, [Watchlist.defaultRepository], "an empty watchlist watches the default")
        host.values[GitHubTool.Preference.watchlist] = .string("acme/web")
        transport.answers["/repos/acme/web"] = (404, "{}")
        tool.preferencesChanged([GitHubTool.Preference.watchlist])
        XCTAssertEqual(tool.summary.repositories.map(\.repo.fullName), ["acme/web"], "the list follows the preference at once")
        XCTAssertEqual(tool.summary.repositories.first?.verdict, .grey)
        XCTAssertEqual(tool.nextPollAt, now, "and a poll is due")
        tool.tick()
        XCTAssertTrue(host.logs.contains { $0.contains("could not read acme/web") })
        host.values[GitHubTool.Preference.mouseIndicator] = .bool(false)
        tool.preferencesChanged([GitHubTool.Preference.mouseIndicator])
        XCTAssertEqual(mouse.last, ["/usr/bin/gravastar-mouse", "restore"], "off puts the person's light back")
        host.values[GitHubTool.Preference.mouseIndicator] = .bool(true)
        host.values[GitHubTool.Preference.mouseIdle] = .string("off")
        tool.preferencesChanged([GitHubTool.Preference.mouseIdle])
        XCTAssertEqual(mouse.last, ["/usr/bin/gravastar-mouse", "off"])
    }

    // MARK: The status on the closed island

    func testTheStatusFollowsTheMouse() {
        func state(_ verdict: Verdict, approval: Bool = false, signedIn: Bool = true) -> StatusState {
            GitHubTool.status(verdict: verdict, awaitingApproval: approval, signedIn: signedIn).state
        }
        XCTAssertEqual(state(.green), .ok)
        XCTAssertEqual(state(.amber), .busy)
        XCTAssertEqual(state(.red), .failure)
        XCTAssertEqual(state(.grey), StatusState.none, "nothing read yet, or nothing watched")
        XCTAssertEqual(state(.green, approval: true), .attention)
        XCTAssertEqual(state(.amber, approval: true), .attention)
        XCTAssertEqual(state(.red, approval: true), .attention, "a wait for approval outranks red, as on the mouse")
        XCTAssertEqual(state(.grey, approval: true), .attention)
        XCTAssertEqual(state(.red, approval: true, signedIn: false), StatusState.none, "signed out shows no mark")
        XCTAssertEqual(GitHubTool.status(verdict: .amber, awaitingApproval: false, signedIn: true).icon,
                       "arrow.triangle.branch", "busy keeps the branch glyph")
        XCTAssertEqual(GitHubTool.status(verdict: .red, awaitingApproval: true, signedIn: true).icon, "hand.raised.fill")
        XCTAssertNil(GitHubTool.status(verdict: .red, awaitingApproval: false, signedIn: true).icon)
        XCTAssertNil(GitHubTool.status(verdict: .green, awaitingApproval: false, signedIn: true).icon)
        XCTAssertEqual(GitHubTool.status(verdict: .red, awaitingApproval: false, signedIn: true).text?.text(for: "en"),
                       "A check failed")
        XCTAssertEqual(GitHubTool.status(verdict: .green, awaitingApproval: false, signedIn: true).text?.text(for: "de"),
                       "Alle Prüfungen bestanden", "the words are the tool's, in the person's language")
        XCTAssertEqual(GitHubTool.status(verdict: .grey, awaitingApproval: false, signedIn: true), .noMark)
        var summary = GitHubSummary(states: [:], watched: [])
        XCTAssertEqual(GitHubTool.status(for: summary, signedIn: true), .noMark, "nothing watched")
        summary = GitHubSummary(states: [:], watched: [Watchlist.defaultRepository])
        XCTAssertEqual(GitHubTool.status(for: summary, signedIn: true), .noMark, "a watched repository not read yet is grey")
    }

    /// Watched repositories with `running` checks each, as a snapshot reads
    /// them; a repository with none is green.
    private func summary(running counts: [Int]) -> GitHubSummary {
        var states: [RepoKey: RepoState] = [:]
        var watched: [RepoKey] = []
        for (index, count) in counts.enumerated() {
            let repo = RepoKey(owner: "acme", name: "r\(index)")
            var checks = ["done": CheckRun(key: "done", name: "lint", headSHA: "h", status: .completed,
                                           conclusion: .success, htmlURL: nil)]
            for run in 0..<count {
                checks["run\(run)"] = CheckRun(key: "run\(run)", name: "ci \(run)", headSHA: "h", status: .inProgress,
                                               conclusion: nil, htmlURL: nil)
            }
            states[repo] = RepoState(repo: repo, defaultBranch: "main", headSHA: "h", checks: checks)
            watched.append(repo)
        }
        return GitHubSummary(states: states, watched: watched)
    }

    func testBusyCarriesHowManyRun() {
        func busy(_ running: Int) -> IslandStatus {
            GitHubTool.status(verdict: .amber, awaitingApproval: false, running: running, signedIn: true)
        }
        XCTAssertEqual(busy(1).activity, .plain("1"))
        XCTAssertEqual(busy(3).activity, .plain("3"), "the number, as digits")
        XCTAssertEqual(busy(99).activity, .plain("99"))
        XCTAssertEqual(busy(100).activity, .plain("99+"), "over 99 is 99+")
        XCTAssertEqual(busy(4_321).activity, .plain("99+"))
        XCTAssertNil(busy(0).activity, "busy with none counted has no words, so the percent shows")
        XCTAssertEqual(busy(3).state, .busy)
        XCTAssertEqual(busy(3).text?.text(for: "en"), "Checks are running", "the text stays what VoiceOver reads")
        XCTAssertEqual(busy(3).icon, "arrow.triangle.branch")
        XCTAssertEqual(GitHubTool.status(for: summary(running: [2, 0, 1]), signedIn: true).activity, .plain("3"),
                       "the sum across the watched repositories")
        XCTAssertEqual(GitHubTool.status(for: summary(running: [60, 41]), signedIn: true).activity, .plain("99+"))
    }

    func testNoOtherStateCarriesWords() {
        for verdict in [Verdict.green, .red, .grey] {
            XCTAssertNil(GitHubTool.status(verdict: verdict, awaitingApproval: false, running: 5, signedIn: true).activity,
                         "\(verdict) carries no words")
        }
        for verdict in [Verdict.green, .amber, .red, .grey] {
            XCTAssertNil(GitHubTool.status(verdict: verdict, awaitingApproval: true, running: 5, signedIn: true).activity,
                         "waiting for approval with \(verdict) carries no words")
        }
        XCTAssertEqual(GitHubTool.status(verdict: .amber, awaitingApproval: false, running: 5, signedIn: false), .noMark,
                       "signed out shows no mark and no words")
        XCTAssertNil(IslandStatus.noMark.activity)
    }

    func testTheManifestSaysTheStatusCarriesWords() {
        XCTAssertEqual(ToolFiles.manifest()?.contributes?.status?.activity, true,
                       "busy sends a count, so contributes.status says \"activity\": true, or the app leaves it out")
    }

    func testAChangeOfCountIsSentAndTheSameCountIsNot() throws {
        func runs(_ ids: [Int]) -> (Int, String) {
            let items = ids.map {
                #"{"id": \#($0), "name": "ci \#($0)", "head_sha": "h1", "status": "in_progress", "conclusion": null, "html_url": null}"#
            }
            return (200, #"{"workflow_runs": [\#(items.joined(separator: ", "))]}"#)
        }
        let path = "/repos/VitruvianSoftware/vitruvian-core/actions/runs?branch=main&per_page=10"
        try secrets.save(token: "gho_saved")
        transport.answers[path] = runs([9])
        tool.start()
        XCTAssertEqual(host.statuses.map(\.state), [.busy])
        XCTAssertEqual(host.statuses.last?.activity, .plain("1"))
        now = now.addingTimeInterval(31)
        tool.tick()
        XCTAssertEqual(host.statuses.count, 1, "the same count is not sent again")
        transport.answers[path] = runs([9, 10])
        now = now.addingTimeInterval(31)
        tool.tick()
        XCTAssertEqual(host.statuses.map(\.state), [.busy, .busy], "a new count is sent, in the same state")
        XCTAssertEqual(host.statuses.last?.activity, .plain("2"))
        answerGitHub(conclusion: "success")
        now = now.addingTimeInterval(31)
        tool.tick()
        XCTAssertEqual(host.statuses.map(\.state), [.busy, .busy, .ok])
        XCTAssertNil(host.statuses.last?.activity, "green takes the words away")
    }

    func testTheStatusIsSentWithTheBadgeAndNotTwice() throws {
        try secrets.save(token: "gho_saved")
        answerGitHub(conclusion: "failure")
        tool.start()
        XCTAssertEqual(host.badges, [1])
        XCTAssertEqual(host.statuses.map(\.state), [.failure], "set where the badge is")
        XCTAssertEqual(host.statuses.last?.text?.text(for: "en"), "A check failed")
        now = now.addingTimeInterval(31)
        tool.tick()
        XCTAssertEqual(host.badges.count, 2, "the badge is set again")
        XCTAssertEqual(host.statuses.count, 1, "but the same status is not sent twice")
        answerGitHub(conclusion: "success")
        now = now.addingTimeInterval(31)
        tool.tick()
        XCTAssertEqual(host.statuses.map(\.state), [.failure, .ok])
        transport.answers["/repos/VitruvianSoftware/vitruvian-core/actions/runs?branch=main&per_page=10&status=waiting"] =
            (200, #"{"workflow_runs": [{"id": 10, "name": "deploy", "head_sha": "h1", "status": "waiting", "conclusion": null, "html_url": null}]}"#)
        now = now.addingTimeInterval(31)
        tool.tick()
        XCTAssertTrue(tool.summary.awaitingApproval)
        XCTAssertEqual(host.statuses.last, GitHubTool.status(for: tool.summary, signedIn: true))
        XCTAssertEqual(host.statuses.map(\.state), [.failure, .ok, .attention])
        XCTAssertEqual(host.statuses.last?.icon, "hand.raised.fill")
        XCTAssertEqual(mouse.last, ["/usr/bin/gravastar-mouse", "breathe", "blue", "--speed", "9"],
                       "the island and the mouse say the same")
    }

    func testSigningOutTakesTheStatusAway() throws {
        tool.start()
        XCTAssertEqual(host.statuses, [], "signed out from the start: nothing is shown, so nothing is sent")
        try secrets.save(token: "gho_saved")
        tool = make()
        tool.start()
        XCTAssertEqual(host.statuses.map(\.state), [.ok])
        tool.signOut()
        XCTAssertEqual(host.statuses.last, .noMark, "sign-out takes the mark away")
        XCTAssertEqual(host.badges.last ?? 0, nil, "with the badge")
        tool.signOut()
        XCTAssertEqual(host.statuses.count, 2, "and does not send it twice")
    }

    // MARK: The island

    func testIslandEventsOpenRefreshAndRerun() throws {
        try secrets.save(token: "gho_saved")
        answerGitHub(conclusion: "failure")
        transport.answers["/repos/VitruvianSoftware/vitruvian-core/actions/runs/9/rerun-failed-jobs"] = (201, "")
        tool.start()
        // Tapping a pull request row drills into its check list instead of opening the browser immediately.
        guard case .page(let detailPage) = tool.islandEvent(
            PanelEvent(block: "pulls", kind: .tap, value: .string("pr.VitruvianSoftware.vitruvian-core.3"))
        ) else { return XCTFail() }
        XCTAssertEqual(detailPage.ids, ["back", "prdetail.VitruvianSoftware.vitruvian-core.3", "checks"])
        XCTAssertEqual(host.opened, [], "drilling in does not open a browser tab")

        // Tapping a check row in the detail page opens the check run's htmlURL.
        XCTAssertEqual(tool.islandEvent(
            PanelEvent(block: "checks", kind: .tap, value: .string("check.VitruvianSoftware.vitruvian-core.3.check__run_c30"))
        ), .keep)
        XCTAssertEqual(host.opened, ["https://github.com/VitruvianSoftware/vitruvian-core/runs/30"])

        // Tapping the pull request header row (or the "+N more on GitHub" overflow row) opens the PR's htmlURL.
        XCTAssertEqual(tool.islandEvent(
            PanelEvent(block: "prdetail.VitruvianSoftware.vitruvian-core.3", kind: .tap)
        ), .keep)
        XCTAssertEqual(host.opened.last, "https://github.com/VitruvianSoftware/vitruvian-core/pull/3")
        host.opened.removeAll()
        XCTAssertEqual(tool.islandEvent(
            PanelEvent(block: "checks", kind: .tap, value: .string("prdetail.VitruvianSoftware.vitruvian-core.3"))
        ), .keep)
        XCTAssertEqual(host.opened, ["https://github.com/VitruvianSoftware/vitruvian-core/pull/3"])

        // Tapping Back returns to the main island page.
        guard case .page(let mainPage) = tool.islandEvent(PanelEvent(block: "back", kind: .tap)) else { return XCTFail() }
        XCTAssertEqual(mainPage.ids.first, "repo.VitruvianSoftware.vitruvian-core")
        XCTAssertNil(tool.selectedPull)

        // If a PR disappears while its detail page is open, the next poll returns to the main island page automatically.
        _ = tool.islandEvent(PanelEvent(block: "pulls", kind: .tap, value: .string("pr.VitruvianSoftware.vitruvian-core.3")))
        XCTAssertNotNil(tool.selectedPull)
        transport.answers["/repos/VitruvianSoftware/vitruvian-core/pulls?state=open&per_page=100"] = (200, "[]")
        now = now.addingTimeInterval(31)
        tool.tick()
        XCTAssertNil(tool.selectedPull, "a pull request that closed or merged clears selectedPull on the next poll")
        XCTAssertEqual(tool.islandPage().ids.first, "repo.VitruvianSoftware.vitruvian-core")

        XCTAssertEqual(tool.islandEvent(PanelEvent(block: "rerun", kind: .tap)), .keep)
        XCTAssertEqual(host.messages.last, "Re-running 1 failed runs")
        XCTAssertEqual(tool.nextPollAt, now, "a poll is due after a re-run")
        guard case .page(let page) = tool.islandEvent(PanelEvent(block: "refresh", kind: .tap)) else { return XCTFail() }
        XCTAssertEqual(page.ids.first, "repo.VitruvianSoftware.vitruvian-core")
        XCTAssertEqual(tool.islandEvent(PanelEvent(block: "pulls", kind: .tap, value: .string("pr.nobody.x.1"))), .keep)
        XCTAssertEqual(host.opened.count, 1, "a row the tool does not know opens nothing")
        tool.openPulls()
        XCTAssertEqual(host.opened.last, "https://github.com/pulls")
        let opened = host.opened.count
        XCTAssertEqual(tool.islandEvent(PanelEvent(block: "openPulls", kind: .tap)), .keep, "the island's page stays")
        XCTAssertEqual(host.opened.count, opened + 1)
        XCTAssertEqual(host.opened.last, "https://github.com/pulls", "the island's button opens what the openPulls command opens")
    }

    // MARK: Settings

    func testSigningInWithATokenAndOut() {
        tool.start()
        guard case .page(let page) = tool.settingsEvent(PanelEvent(block: "token", kind: .submit, value: .string(" gho_typed "))) else {
            return XCTFail()
        }
        XCTAssertEqual(tool.auth, .signedIn(login: "james"))
        XCTAssertEqual(page.ids, ["signOut", "testApproval", "testSuccess", "testRunning", "testFailure", "testIdle"])
        XCTAssertEqual(secrets.token(), "gho_typed")
        XCTAssertEqual(tool.settingsEvent(PanelEvent(block: "token", kind: .submit, value: .string("  "))), .keep,
                       "an empty token is nothing")
        _ = tool.settingsEvent(PanelEvent(block: "signOut", kind: .tap))
        XCTAssertEqual(tool.auth, .signedOut)
        XCTAssertNil(secrets.token())
        XCTAssertEqual(host.badges.last ?? 0, nil, "the badge goes")
        XCTAssertEqual(mouse.last, ["/usr/bin/gravastar-mouse", "restore"])
        XCTAssertEqual(tool.islandPage().kinds, ["text"])
    }

    func testSignedOutOnPurposeTheCLIDoesNotSignBackInUntilAsked() throws {
        try "github.com:\n    user: james\n    oauth_token: gho_cli\n".write(to: hosts, atomically: true, encoding: .utf8)
        tool.start()
        tool.signOut()
        tool.start()
        XCTAssertEqual(tool.auth, .signedOut, "not by itself")
        XCTAssertEqual(tool.settingsInput().cliLogin, "james", "but the button is offered")
        _ = tool.settingsEvent(PanelEvent(block: "useCLI", kind: .tap))
        XCTAssertEqual(tool.auth, .signedIn(login: "james"))
    }

    func testSigningInWithACode() {
        host.values[GitHubTool.Preference.clientID] = .string("Iv1.app")
        transport.answers["/login/device/code"] = (200, #"{"device_code": "d", "user_code": "ABCD-1234", "verification_uri": "https://github.com/login/device", "expires_in": 900, "interval": 5}"#)
        transport.answers["/login/oauth/access_token"] = (200, #"{"error": "authorization_pending"}"#)
        tool.start()
        guard case .page(let page) = tool.settingsEvent(PanelEvent(block: "useCode", kind: .tap)) else { return XCTFail() }
        XCTAssertEqual(tool.auth, .deviceFlow(userCode: "ABCD-1234", verificationURL: URL(string: "https://github.com/login/device")!))
        XCTAssertEqual(page.english(2), "ABCD-1234")
        let asked = transport.requests.count
        tool.tick()
        XCTAssertEqual(transport.requests.count, asked, "no poll before the interval")
        now = now.addingTimeInterval(5)
        tool.tick()
        XCTAssertEqual(transport.requests.count, asked + 1)
        transport.answers["/login/oauth/access_token"] = (200, #"{"access_token": "gho_code"}"#)
        now = now.addingTimeInterval(5)
        tool.tick()
        XCTAssertEqual(tool.auth, .signedIn(login: "james"))
        XCTAssertEqual(secrets.token(), "gho_code")
        XCTAssertEqual(host.rendered.last?.panel, "settings", "the panel is drawn again when the sign-in lands")
    }

    func testACodeNeedsAClientIDAndCanBeCancelledOrDenied() {
        tool.start()
        _ = tool.settingsEvent(PanelEvent(block: "useCode", kind: .tap))
        XCTAssertEqual(tool.auth, .failed(.notConfigured))
        host.values[GitHubTool.Preference.clientID] = .string("Iv1.app")
        transport.answers["/login/device/code"] = (200, #"{"device_code": "d", "user_code": "ABCD-1234", "verification_uri": "https://github.com/login/device", "expires_in": 900, "interval": 5}"#)
        _ = tool.settingsEvent(PanelEvent(block: "useCode", kind: .tap))
        _ = tool.settingsEvent(PanelEvent(block: "cancel", kind: .tap))
        XCTAssertEqual(tool.auth, .signedOut)
        _ = tool.settingsEvent(PanelEvent(block: "useCode", kind: .tap))
        transport.answers["/login/oauth/access_token"] = (200, #"{"error": "access_denied"}"#)
        now = now.addingTimeInterval(5)
        tool.tick()
        XCTAssertEqual(tool.auth, .failed(.deviceFlow(.denied)))
        transport.answers["/login/device/code"] = (200, #"{"error": "device_flow_disabled"}"#)
        _ = tool.settingsEvent(PanelEvent(block: "useCode", kind: .tap))
        XCTAssertEqual(tool.auth, .failed(.deviceFlow(.other("device_flow_disabled"))))
    }

    func testTheSettingsInputNamesTheMouseCommandInUse() {
        XCTAssertEqual(tool.settingsInput().mouseCommand, "/usr/bin/gravastar-mouse")
        host.values[GitHubTool.Preference.mouseCommand] = .string("/nope")
        XCTAssertEqual(tool.settingsInput().mouseCommand, "/usr/bin/gravastar-mouse")
        XCTAssertTrue(tool.settingsInput().mouseConfiguredIgnored)
    }

    // MARK: What the app's own GitHub view had

    func testTappingARepositoryOpensItsBranchChecksAndBackReturns() throws {
        try secrets.save(token: "gho_saved")
        answerGitHub(conclusion: "failure")
        transport.answers["/repos/VitruvianSoftware/vitruvian-core/commits/h1/check-runs?per_page=100"] =
            (200, #"{"check_runs": [{"id": 5, "name": "lint", "head_sha": "h1", "status": "completed", "conclusion": "success", "html_url": "https://github.com/VitruvianSoftware/vitruvian-core/runs/5"}]}"#)
        tool.start()
        guard case .page(let page) = tool.islandEvent(PanelEvent(block: "repo.VitruvianSoftware.vitruvian-core", kind: .tap))
        else { return XCTFail("a repository row drills in") }
        XCTAssertEqual(tool.selectedRepo, Watchlist.defaultRepository)
        XCTAssertEqual(page.ids, ["back", "repodetail.VitruvianSoftware.vitruvian-core", "branchChecks"])
        XCTAssertEqual(tool.islandPage(), page, "the page the next render draws too")
        XCTAssertEqual(host.opened, [], "drilling in opens no browser tab")
        guard case .list(let list) = page.blocks[3].content else { return XCTFail() }
        XCTAssertEqual(list.rows.map { $0.title.text(for: "en") }, ["ci", "lint"], "the failed run first")

        // A check with a page opens it; one without opens the Actions page.
        _ = tool.islandEvent(PanelEvent(block: "branchChecks", kind: .tap,
                                        value: .string("branchcheck.VitruvianSoftware.vitruvian-core.check__run_c5")))
        XCTAssertEqual(host.opened.last, "https://github.com/VitruvianSoftware/vitruvian-core/runs/5")
        _ = tool.islandEvent(PanelEvent(block: "branchChecks", kind: .tap,
                                        value: .string("branchcheck.VitruvianSoftware.vitruvian-core.workflow__run_c9")))
        XCTAssertEqual(host.opened.last, "https://github.com/VitruvianSoftware/vitruvian-core/actions")
        host.opened.removeAll()
        XCTAssertEqual(tool.islandEvent(PanelEvent(block: "repodetail.VitruvianSoftware.vitruvian-core", kind: .tap)), .keep)
        XCTAssertEqual(host.opened, ["https://github.com/VitruvianSoftware/vitruvian-core/actions"],
                       "the header row opens the repository's Actions page")
        _ = tool.islandEvent(PanelEvent(block: "branchChecks", kind: .tap, value: .string("branchcheck.nobody.x.check__run_c1")))
        XCTAssertEqual(host.opened.count, 1, "a row the tool does not know opens nothing")

        // A poll keeps the page; Back returns to the main page.
        now = now.addingTimeInterval(31)
        tool.tick()
        XCTAssertEqual(host.rendered.last?.tree.ids.first, "back", "a poll redraws the repository's page")
        guard case .page(let main) = tool.islandEvent(PanelEvent(block: "back", kind: .tap)) else { return XCTFail() }
        XCTAssertNil(tool.selectedRepo)
        XCTAssertEqual(main.ids.first, "repo.VitruvianSoftware.vitruvian-core")

        // A pull request outranks a repository; a repository no longer watched closes its page.
        _ = tool.islandEvent(PanelEvent(block: "repo.VitruvianSoftware.vitruvian-core", kind: .tap))
        guard case .page(let pull) = tool.islandEvent(
            PanelEvent(block: "pulls", kind: .tap, value: .string("pr.VitruvianSoftware.vitruvian-core.3"))) else {
            return XCTFail()
        }
        XCTAssertEqual(pull.ids.first, "back")
        XCTAssertNil(tool.selectedRepo, "opening a pull request leaves the repository's page")
        _ = tool.islandEvent(PanelEvent(block: "back", kind: .tap))
        _ = tool.islandEvent(PanelEvent(block: "repo.VitruvianSoftware.vitruvian-core", kind: .tap))
        host.values[GitHubTool.Preference.watchlist] = .string("acme/web")
        tool.preferencesChanged([GitHubTool.Preference.watchlist])
        XCTAssertNil(tool.selectedRepo)
        XCTAssertEqual(tool.islandPage().ids.first, "repo.acme.web")
        XCTAssertEqual(tool.islandEvent(PanelEvent(block: "repo.nobody.x", kind: .tap)), .keep,
                       "a repository not watched does not drill in")
        tool.signOut()
        XCTAssertNil(tool.selectedRepo)
    }

    func testThePickerFocusesARepositoryAndOpenInGitHubOpensIt() throws {
        try secrets.save(token: "gho_saved")
        host.values[GitHubTool.Preference.watchlist] = .string("VitruvianSoftware/vitruvian-core, acme/web")
        transport.answers["/repos/acme/web"] = (404, "{}")
        tool.start()
        XCTAssertFalse(tool.islandPage().kinds.contains("choice"), "an app without choice is sent no picker")
        XCTAssertEqual(tool.islandEvent(PanelEvent(block: "openRepo", kind: .tap)), .keep)
        XCTAssertEqual(host.opened.last, "https://github.com/VitruvianSoftware/vitruvian-core", "the first, by default")

        host.features = [.choice]
        XCTAssertEqual(tool.islandPage().ids.first, "repoPicker")
        guard case .page(let picked) = tool.islandEvent(PanelEvent(block: "repoPicker", kind: .change,
                                                                    value: .string("acme/web"))) else { return XCTFail() }
        XCTAssertEqual(tool.focusedRepository, RepoKey(owner: "acme", name: "web"))
        guard case .choice(let choice) = picked.blocks[0].content else { return XCTFail() }
        XCTAssertEqual(choice.value, "acme/web")
        _ = tool.islandEvent(PanelEvent(block: "openRepo", kind: .tap))
        XCTAssertEqual(host.opened.last, "https://github.com/acme/web")
        XCTAssertEqual(tool.islandEvent(PanelEvent(block: "repoPicker", kind: .change, value: .string("not/watched"))), .keep)
        XCTAssertEqual(tool.islandEvent(PanelEvent(block: "repoPicker", kind: .change, value: .string("nonsense"))), .keep)
        XCTAssertEqual(tool.focusedRepository, RepoKey(owner: "acme", name: "web"), "a pick that is no repository changes nothing")

        host.values[GitHubTool.Preference.watchlist] = .string("VitruvianSoftware/vitruvian-core")
        tool.preferencesChanged([GitHubTool.Preference.watchlist])
        XCTAssertEqual(tool.focusedRepository, Watchlist.defaultRepository, "a focus no longer watched falls back")
        XCTAssertFalse(tool.islandPage().kinds.contains("choice"), "and one repository needs no picker")
    }

    func testTheIslandSaysWhenGitHubWasLastRead() throws {
        tool = GitHubTool(parts: .init(host: host, api: GitHubAPI(transport: transport, apiURL: URL(string: "https://api.test")!,
                                                                  webURL: URL(string: "https://web.test")!),
                                       secrets: secrets, cliHosts: hosts, now: { [unowned self] in now },
                                       environment: ["PATH": "/usr/bin"], home: "/Users/me",
                                       isExecutable: { $0 == "/usr/bin/gravastar-mouse" },
                                       runMouse: { _, _ in }, timeZone: TimeZone(identifier: "UTC")!))
        host.language = "de"
        XCTAssertNil(tool.lastUpdatedAt)
        try secrets.save(token: "gho_saved")
        tool.start()
        XCTAssertEqual(tool.lastUpdatedAt, now)
        let page = tool.islandPage()
        XCTAssertEqual(page.kinds.last, "text")
        guard case .text(let caption) = page.blocks.last?.content else { return XCTFail() }
        XCTAssertEqual(caption.text.text(for: "de"), "Aktualisiert um 13:46:40")
        now = now.addingTimeInterval(31)
        tool.tick()
        XCTAssertEqual(tool.lastUpdatedAt, now, "each poll stamps it")
        guard case .text(let later) = tool.islandPage().blocks.last?.content else { return XCTFail() }
        XCTAssertEqual(later.text.text(for: "de"), "Aktualisiert um 13:47:11")
        tool.signOut()
        XCTAssertNil(tool.lastUpdatedAt, "signing out forgets it")
    }

    func testCopyPutsTheCodeOnTheClipboard() {
        host.values[GitHubTool.Preference.clientID] = .string("Iv1.app")
        transport.answers["/login/device/code"] = (200, #"{"device_code": "d", "user_code": "ABCD-1234", "verification_uri": "https://github.com/login/device", "expires_in": 900, "interval": 5}"#)
        tool.start()
        XCTAssertEqual(tool.settingsEvent(PanelEvent(block: "copyCode", kind: .tap)), .keep)
        XCTAssertEqual(host.copied, [], "no code yet, nothing copied")
        _ = tool.settingsEvent(PanelEvent(block: "useCode", kind: .tap))
        XCTAssertEqual(tool.settingsEvent(PanelEvent(block: "copyCode", kind: .tap)), .keep, "the page stays as it is")
        XCTAssertEqual(host.copied, ["ABCD-1234"])
        XCTAssertEqual(host.messages.last, "Code copied")
        host.language = "fr"
        host.clipboardTakes = false
        _ = tool.settingsEvent(PanelEvent(block: "copyCode", kind: .tap))
        XCTAssertEqual(host.copied, ["ABCD-1234"])
        XCTAssertEqual(host.messages, ["Code copied"], "no word of a copy that did not happen")
        XCTAssertTrue(host.logs.contains { $0.contains("clipboard") })
    }

    func testTheMouseTestButtonsFireEachLightAndAPollPutsTheRealOneBack() throws {
        try secrets.save(token: "gho_saved")
        tool.start()
        XCTAssertEqual(mouse, [["/usr/bin/gravastar-mouse", "color", "green"]])
        XCTAssertEqual(tool.settingsPage().ids.suffix(5), ["testApproval", "testSuccess", "testRunning", "testFailure", "testIdle"])
        XCTAssertEqual(tool.settingsEvent(PanelEvent(block: "testFailure", kind: .tap)), .keep)
        XCTAssertEqual(mouse.last, ["/usr/bin/gravastar-mouse", "breathe", "red"])
        _ = tool.settingsEvent(PanelEvent(block: "testApproval", kind: .tap))
        XCTAssertEqual(mouse.last, ["/usr/bin/gravastar-mouse", "breathe", "blue", "--speed", "9"])
        _ = tool.settingsEvent(PanelEvent(block: "testRunning", kind: .tap))
        XCTAssertEqual(mouse.last, ["/usr/bin/gravastar-mouse", "breathe", "orange"])
        _ = tool.settingsEvent(PanelEvent(block: "testSuccess", kind: .tap))
        XCTAssertEqual(mouse.last, ["/usr/bin/gravastar-mouse", "color", "green"])
        host.values[GitHubTool.Preference.mouseIdle] = .string("off")
        _ = tool.settingsEvent(PanelEvent(block: "testIdle", kind: .tap))
        XCTAssertEqual(mouse.last, ["/usr/bin/gravastar-mouse", "off"], "the person's idle choice")
        host.values[GitHubTool.Preference.mouseFailure] = .string("purple")
        _ = tool.settingsEvent(PanelEvent(block: "testFailure", kind: .tap))
        XCTAssertEqual(mouse.last, ["/usr/bin/gravastar-mouse", "color", "purple"], "the person's red, not the default")
        let tried = mouse.count
        now = now.addingTimeInterval(31)
        tool.tick()
        XCTAssertEqual(mouse.count, tried + 1)
        XCTAssertEqual(mouse.last, ["/usr/bin/gravastar-mouse", "color", "green"], "the next poll writes the real state back")

        host.values[GitHubTool.Preference.mouseIndicator] = .bool(false)
        XCTAssertFalse(tool.settingsPage().ids.contains("testFailure"), "hidden with the mouse not showing the status")
        let before = mouse.count
        _ = tool.settingsEvent(PanelEvent(block: "testFailure", kind: .tap))
        XCTAssertEqual(mouse.count, before, "and a stale tap does nothing")
        XCTAssertEqual(tool.settingsEvent(PanelEvent(block: "nothing", kind: .tap)), .keep)
    }

    func testTheMergeQueueIsOnTheIslandAndItsRowsOpenThePullRequest() throws {
        try secrets.save(token: "gho_saved")
        transport.answers["/graphql"] = (200, #"{"data": {"repository": {"mergeQueue": {"url": "https://github.com/VitruvianSoftware/vitruvian-core/queue/main", "entries": {"nodes": [{"position": 1, "state": "AWAITING_CHECKS", "pullRequest": {"number": 3, "title": "Fix", "url": "https://github.com/VitruvianSoftware/vitruvian-core/pull/3", "author": {"login": "james"}}}, {"position": 2, "state": "QUEUED", "pullRequest": {"number": 40, "title": "Theirs", "url": null, "author": {"login": "bo"}}}]}}}}}"#)
        tool.start()
        let page = tool.islandPage()
        XCTAssertEqual(page.ids, ["repo.VitruvianSoftware.vitruvian-core", "queue", "pulls", "openPulls", "refresh", "openRepo"])
        XCTAssertEqual(tool.summary.pullRequests.first?.pullRequest.mergeQueue, MergeQueueState(position: 1))
        _ = tool.islandEvent(PanelEvent(block: "queue", kind: .tap, value: .string("queue.VitruvianSoftware.vitruvian-core.3")))
        XCTAssertEqual(host.opened.last, "https://github.com/VitruvianSoftware/vitruvian-core/pull/3")
        _ = tool.islandEvent(PanelEvent(block: "queue", kind: .tap, value: .string("queue.VitruvianSoftware.vitruvian-core.40")))
        XCTAssertEqual(host.opened.last, "https://github.com/VitruvianSoftware/vitruvian-core/pull/40",
                       "an entry without a link opens the pull request's page")
        _ = tool.islandEvent(PanelEvent(block: "queue", kind: .tap, value: .string("mergequeue.VitruvianSoftware.vitruvian-core")))
        XCTAssertEqual(host.opened.last, "https://github.com/VitruvianSoftware/vitruvian-core/queue/main")
        _ = tool.islandEvent(PanelEvent(block: "queue", kind: .tap, value: .string("queue.VitruvianSoftware.vitruvian-core.99")))
        XCTAssertEqual(host.opened.count, 3, "an entry no longer queued opens nothing")
    }
}
