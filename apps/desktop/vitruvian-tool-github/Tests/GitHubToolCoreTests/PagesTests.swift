// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 VitruvianSoftware

import XCTest

import VitruvianToolProtocol
@testable import GitHubToolCore

/// What a page holds, read back as the app reads it: the kinds in order,
/// and the ids the events will name.
extension UITree {
    var kinds: [String] { blocks.map(\.type) }
    var ids: [String] { blocks.compactMap(\.id) }
    func english(_ index: Int) -> String? {
        switch blocks[index].content {
        case .text(let block): return block.text.text(for: "en")
        case .heading(let block): return block.text.text(for: "en")
        case .button(let block): return block.title.text(for: "en")
        case .row(let block): return block.title.text(for: "en")
        case .link(let block): return block.title.text(for: "en")
        default: return nil
        }
    }
}

final class PagesTests: XCTestCase {
    static let repo = RepoKey(owner: "acme", name: "web")

    func summary(red: Bool = false, pulls: Int = 0, failedRun: Bool = false) -> GitHubSummary {
        var checks: [String: CheckRun] = ["a": CheckRun(key: "a", name: "ci", headSHA: "h", status: .completed,
                                                         conclusion: .success, htmlURL: nil)]
        if red {
            checks["b"] = CheckRun(key: "b", name: "deploy", headSHA: "h", status: .completed, conclusion: .failure,
                                   htmlURL: nil, workflowRunID: failedRun ? 77 : nil)
        }
        var state = RepoState(repo: Self.repo, defaultBranch: "main", headSHA: "h", checks: checks)
        for number in 0..<pulls {
            state.pullRequests[number + 1] = PullRequest(
                number: number + 1, title: "Change \(number + 1)", author: "ana", headSHA: "p\(number)", isDraft: number == 0,
                htmlURL: URL(string: "https://github.com/acme/web/pull/\(number + 1)"), requestedReviewers: [],
                requestedTeams: [], reviews: number == 1 ? ["bo": .approved] : [:])
        }
        return GitHubSummary(states: [Self.repo: state], watched: [Self.repo])
    }

    func testTheIslandPageWhenSignedOut() {
        let page = Pages.island(summary: summary(), auth: .signedOut)
        XCTAssertEqual(page.kinds, ["text"])
        XCTAssertEqual(page.english(0), Words.table["notSignedInIsland"]?["en"])
        let failed = Pages.island(summary: summary(), auth: .failed(.unreachable))
        XCTAssertEqual(failed.kinds, ["text", "text"], "a failure is said under it")
    }

    func testTheIslandPageListsRepositoriesThenPullRequestsThenButtons() {
        let page = Pages.island(summary: summary(red: true, pulls: 2, failedRun: true), auth: .signedIn(login: "me"))
        XCTAssertEqual(page.kinds, ["row", "heading", "list", "button", "button"])
        XCTAssertEqual(page.ids, ["repo.acme.web", "pulls", "refresh", "rerun"])
        XCTAssertEqual(page.english(0), "acme/web")
        guard case .row(let row) = page.blocks[0].content else { return XCTFail() }
        XCTAssertEqual(row.subtitle?.text(for: "en"), "1 passed, 1 failed, 0 running")
        XCTAssertEqual(row.icon, "xmark.circle.fill")
        guard case .list(let list) = page.blocks[2].content else { return XCTFail() }
        XCTAssertEqual(list.rows.map(\.id), ["pr.acme.web.2", "pr.acme.web.1"], "newest first")
        XCTAssertEqual(list.rows[0].title.text(for: "en"), "#2 Change 2")
        XCTAssertEqual(list.rows[0].subtitle?.text(for: "en"), "acme/web · @ana")
        XCTAssertEqual(list.rows[0].trailing?.text(for: "en"), "Approved")
        XCTAssertEqual(list.rows[1].trailing?.text(for: "en"), "Draft", "a draft says so before its review")
        XCTAssertEqual(list.rows[0].icon, "circle.dashed", "a pull request with no checks is grey")
        guard case .button(let rerun) = page.blocks[4].content else { return XCTFail() }
        XCTAssertEqual(rerun.style, .destructive)
        XCTAssertEqual(Pages.pull(ofRow: "pr.acme.web.2")?.number, 2)
        XCTAssertEqual(Pages.pull(ofRow: "pr.acme.web.2")?.repo, Self.repo)
        XCTAssertNil(Pages.pull(ofRow: "repo.acme.web"))
        XCTAssertEqual(Pages.repo(ofRow: "repo.acme.web"), Self.repo)
    }

    /// The app reads a page with the protocol's own reader and draws none of
    /// it when one id is not a well-formed name. Version 1.0.0 sent
    /// `repo:acme/web` and `pr:acme/web#2`: signed in, the island page was a
    /// spinner for ever, and no test read a page back.
    func testEveryPageIsOneTheAppWillRead() throws {
        let pages: [(String, UITree)] = [
            ("the island, signed in", Pages.island(summary: summary(red: true, pulls: 2, failedRun: true),
                                                   auth: .signedIn(login: "me"))),
            ("the island, signed out", Pages.island(summary: summary(), auth: .signedOut)),
            ("the settings, signed in", Pages.settings(.init(auth: .signedIn(login: "me"), cliLogin: "me"))),
            ("the settings, signed out", Pages.settings(.init(auth: .signedOut))),
        ]
        for (name, page) in pages {
            let sent = try JSONEncoder().encode(page)
            XCTAssertNoThrow(try JSONDecoder().decode(UITree.self, from: sent), name)
        }
    }

    func testARowsIdIsAWellFormedNameWhateverTheRepositoryIsCalled() {
        let odd = ["acme/web", "acme/.github", "acme/a.b", "acme/a_b", "acme/a__d", "a-b/c-d", "acme/x_dy",
                   "acme/v1.2.3", "acme/a..b", "acme/trailing."]
        for fullName in odd {
            guard let repo = RepoKey(fullName: fullName) else { return XCTFail(fullName) }
            let row = Pages.repoRow(repo)
            XCTAssertTrue(ManifestRules.isWellFormedName(row), "\(fullName) gives \(row)")
            XCTAssertEqual(Pages.repo(ofRow: row), repo, "\(fullName) comes back from \(row)")
            let pull = Pages.pullRow(repo, 42)
            XCTAssertTrue(ManifestRules.isWellFormedName(pull), "\(fullName) gives \(pull)")
            XCTAssertEqual(Pages.pull(ofRow: pull)?.repo, repo, "\(fullName) comes back from \(pull)")
            XCTAssertEqual(Pages.pull(ofRow: pull)?.number, 42)
            XCTAssertNil(Pages.repo(ofRow: pull), "a pull request's row is not a repository's")
            XCTAssertNil(Pages.pull(ofRow: row), "a repository's row is not a pull request's")
        }
        // A name too long for an id still gives a page the app reads; its row
        // names nothing, so a tap on it does nothing.
        let long = RepoKey(owner: "acme", name: String(repeating: "n", count: 200))
        XCTAssertTrue(ManifestRules.isWellFormedName(Pages.repoRow(long)))
        XCTAssertNil(Pages.repo(ofRow: Pages.repoRow(long)))
        XCTAssertTrue(ManifestRules.isWellFormedName(Pages.pullRow(long, 7)))
        XCTAssertNil(Pages.pull(ofRow: Pages.pullRow(long, 7)))
        XCTAssertNotEqual(Pages.pullRow(long, 7), Pages.pullRow(long, 8), "two rows of one list never share an id")
    }

    func testTheIslandPageWithoutPullRequestsOrFailures() {
        let page = Pages.island(summary: summary(), auth: .signedIn(login: "me"))
        XCTAssertEqual(page.kinds, ["row", "heading", "text", "button"])
        XCTAssertEqual(page.english(2), "No pull requests need you.")
        XCTAssertEqual(page.ids, ["repo.acme.web", "refresh"], "no re-run button without a failed run")
        let green = Pages.island(summary: summary(red: true), auth: .signedIn(login: "me"))
        XCTAssertEqual(green.ids, ["repo.acme.web", "refresh"], "a failed check run, not a workflow run, cannot be re-run")
    }

    func testThePageStaysWithinTheProtocolsLimits() throws {
        var state = RepoState(repo: Self.repo, defaultBranch: "main", headSHA: "h")
        for number in 1...300 {
            state.pullRequests[number] = PullRequest(number: number, title: String(repeating: "x", count: 200), author: "a",
                                                     headSHA: "p", isDraft: false, htmlURL: nil, requestedReviewers: [],
                                                     requestedTeams: [])
        }
        let page = Pages.island(summary: GitHubSummary(states: [Self.repo: state], watched: [Self.repo]), auth: .signedIn(login: "me"))
        XCTAssertLessThanOrEqual(page.blocks.count, UILimits.maxBlocks)
        guard case .list(let list) = page.blocks[2].content else { return XCTFail() }
        XCTAssertEqual(list.rows.count, Pages.maxPullRows, "the list is cut to the newest a page may hold")
        XCTAssertEqual(list.rows.first?.id, "pr.acme.web.300", "the newest come first")
        XCTAssertEqual(list.rows.first?.title.text(for: "en").count, "#300 ".count + Pages.maxTitleLength)
        let bytes = try JSONEncoder().encode(page).count
        XCTAssertLessThanOrEqual(bytes, UILimits.maxTreeBytes)
    }

    func testTheSettingsPanelInEachState() {
        let out = Pages.settings(.init(auth: .signedOut, cliLogin: "james", mouseCommand: "/opt/homebrew/bin/gravastar-mouse"))
        XCTAssertEqual(out.kinds, ["heading", "text", "button", "field", "button", "text", "divider", "text"])
        XCTAssertEqual(out.ids, ["useCLI", "token", "useCode"])
        XCTAssertEqual(out.english(2), "Use the GitHub CLI login (@james)")
        guard case .field(let field) = out.blocks[3].content else { return XCTFail() }
        XCTAssertEqual(field.kind, .secret)
        XCTAssertEqual(out.english(7), "Mouse command: /opt/homebrew/bin/gravastar-mouse")

        let noCLI = Pages.settings(.init(auth: .signedOut, mouseConfiguredIgnored: true))
        XCTAssertEqual(noCLI.ids, ["token", "useCode"])
        XCTAssertEqual(noCLI.kinds.last, "text")
        XCTAssertEqual(noCLI.english(noCLI.blocks.count - 2), Words.table["mouseMissingHomebrew"]?["en"])
        XCTAssertEqual(noCLI.english(noCLI.blocks.count - 1), Words.table["mouseCommandIgnored"]?["en"])

        let checking = Pages.settings(.init(auth: .checking))
        XCTAssertEqual(checking.kinds, ["heading", "text", "progress", "text", "divider", "text"])

        let code = Pages.settings(.init(auth: .deviceFlow(userCode: "ABCD-1234", verificationURL: URL(string: "https://github.com/login/device")!)))
        XCTAssertEqual(code.kinds, ["heading", "text", "text", "link", "button", "text", "divider", "text"])
        XCTAssertEqual(code.english(2), "ABCD-1234")
        XCTAssertEqual(code.ids, ["cancel"])
        guard case .link(let link) = code.blocks[3].content else { return XCTFail() }
        XCTAssertEqual(link.url, "https://github.com/login/device")

        let signedIn = Pages.settings(.init(auth: .signedIn(login: "james")))
        XCTAssertEqual(signedIn.kinds, ["heading", "text", "button", "text", "divider", "text"])
        XCTAssertEqual(signedIn.english(1), "Connected as @james")
        XCTAssertEqual(signedIn.ids, ["signOut"])

        let failed = Pages.settings(.init(auth: .failed(.refused(status: 403)), cliLogin: "james"))
        XCTAssertEqual(failed.english(1), "GitHub refused the request (HTTP 403).")
        XCTAssertEqual(failed.ids, ["useCLI", "token", "useCode"], "a failure offers the ways in again")
        XCTAssertEqual(Pages.failureText(.notConfigured).text(for: "en"), Words.table["notConfiguredHint"]?["en"])
        XCTAssertEqual(Pages.failureText(.deviceFlow(.other("device_flow_disabled"))).text(for: "en"),
                       "GitHub couldn’t start the code sign-in (device_flow_disabled).")
    }

    func testEveryWordOnAPageIsInFifteenLanguagesOrThePersonsOwn() {
        let page = Pages.island(summary: summary(red: true, pulls: 1, failedRun: true), auth: .signedIn(login: "me"))
        for block in page.blocks {
            switch block.content {
            case .heading(let b): assertTranslated(b.text)
            case .button(let b): assertTranslated(b.title)
            case .text(let b): assertTranslated(b.text)
            case .list(let b): for row in b.rows { assertTranslated(row.trailing) }
            default: break
            }
        }
    }

    private func assertTranslated(_ text: UIText?, file: StaticString = #filePath, line: UInt = #line) {
        guard let text else { return }
        guard case .languages(let localized) = text else { return XCTFail("\(text) is plain", file: file, line: line) }
        XCTAssertEqual(Set(localized.byLanguage.keys), Set(Words.languages), file: file, line: line)
    }
}
