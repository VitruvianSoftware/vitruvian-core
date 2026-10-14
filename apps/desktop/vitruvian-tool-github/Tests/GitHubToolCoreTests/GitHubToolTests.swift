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

    func value(_ key: String) -> JSONValue? { values[key] }
    func setValue(_ value: JSONValue, for key: String) { values[key] = value }
    func showMessage(_ message: String, icon: String) { messages.append(message) }
    func open(_ url: String) -> Bool { opened.append(url); return true }
    func log(_ message: String) { logs.append(message) }
    func badge(count: Int?, dot: Bool) { badges.append(count) }
    func status(_ status: IslandStatus) { statuses.append(status) }
    func render(panel: String, _ tree: UITree) { rendered.append((panel, tree)) }
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
        transport.answers["/repos/VitruvianSoftware/vitruvian-core/commits/h1/check-runs"] = (200, #"{"check_runs": []}"#)
        transport.answers["/repos/VitruvianSoftware/vitruvian-core/actions/runs?branch=main&per_page=10"] =
            (200, #"{"workflow_runs": [{"id": 9, "name": "ci", "head_sha": "h1", "status": "completed", "conclusion": "\#(conclusion)", "html_url": null}]}"#)
        transport.answers["/repos/VitruvianSoftware/vitruvian-core/actions/runs?branch=main&per_page=10&status=waiting"] =
            (200, #"{"workflow_runs": []}"#)
        transport.answers["/repos/VitruvianSoftware/vitruvian-core/pulls?state=open&per_page=20"] =
            (200, #"[{"number": 3, "title": "Fix", "draft": false, "html_url": "https://github.com/VitruvianSoftware/vitruvian-core/pull/3", "user": {"login": "james"}, "head": {"sha": "p3"}, "requested_reviewers": [], "requested_teams": []}]"#)
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
        XCTAssertEqual(tool.summary.pullRequests.map(\.pullRequest.number), [3])
        XCTAssertEqual(host.badges, [1], "one red default branch")
        XCTAssertEqual(mouse, [["/usr/bin/gravastar-mouse", "breathe", "red"]], "the first snapshot writes the mouse")
        XCTAssertEqual(host.rendered.map(\.panel), ["settings", "status", "settings"],
                       "the Settings panel while checking, the island after the poll, then Settings signed in")
        XCTAssertEqual(tool.islandPage().ids, ["repo.VitruvianSoftware.vitruvian-core", "pulls", "refresh", "rerun"])
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
        XCTAssertEqual(tool.islandEvent(PanelEvent(block: "pulls", kind: .tap, value: .string("pr.VitruvianSoftware.vitruvian-core.3"))),
                       .keep)
        XCTAssertEqual(host.opened, ["https://github.com/VitruvianSoftware/vitruvian-core/pull/3"])
        XCTAssertEqual(tool.islandEvent(PanelEvent(block: "repo.VitruvianSoftware.vitruvian-core", kind: .tap)), .keep)
        XCTAssertEqual(host.opened.last, "https://github.com/VitruvianSoftware/vitruvian-core/actions")
        XCTAssertEqual(tool.islandEvent(PanelEvent(block: "rerun", kind: .tap)), .keep)
        XCTAssertEqual(host.messages.last, "Re-running 1 failed runs")
        XCTAssertEqual(tool.nextPollAt, now, "a poll is due after a re-run")
        guard case .page(let page) = tool.islandEvent(PanelEvent(block: "refresh", kind: .tap)) else { return XCTFail() }
        XCTAssertEqual(page.ids.first, "repo.VitruvianSoftware.vitruvian-core")
        XCTAssertEqual(tool.islandEvent(PanelEvent(block: "pulls", kind: .tap, value: .string("pr.nobody.x.1"))), .keep)
        XCTAssertEqual(host.opened.count, 2, "a row the tool does not know opens nothing")
        tool.openPulls()
        XCTAssertEqual(host.opened.last, "https://github.com/pulls")
    }

    // MARK: Settings

    func testSigningInWithATokenAndOut() {
        tool.start()
        guard case .page(let page) = tool.settingsEvent(PanelEvent(block: "token", kind: .submit, value: .string(" gho_typed "))) else {
            return XCTFail()
        }
        XCTAssertEqual(tool.auth, .signedIn(login: "james"))
        XCTAssertEqual(page.ids, ["signOut"])
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
}
