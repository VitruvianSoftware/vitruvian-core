// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 VitruvianSoftware

import XCTest

import VitruvianToolKit
import VitruvianToolProtocol
@testable import GitHubToolCore

/// What the Vitruvian app's own GitHub view had and the tool did not, until
/// now: the branch and head on a repository's row, a repository's own check
/// list, the merge queue, the repository picker and Open in GitHub, the
/// time of the last read, Copy and the token link in Settings, and the
/// mouse's test buttons.
final class ParityTests: XCTestCase {
    static let web = RepoKey(owner: "acme", name: "web")
    static let api = RepoKey(owner: "acme", name: "api")

    private func check(_ key: String, _ name: String, status: CheckStatus = .completed,
                       conclusion: CheckConclusion? = .success, url: String? = nil) -> CheckRun {
        CheckRun(key: key, name: name, headSHA: "h", status: status, conclusion: conclusion,
                 htmlURL: url.flatMap(URL.init(string:)))
    }

    private func state(_ repo: RepoKey = web, head: String? = "a1b2c3d4e5f60718", checks: [CheckRun] = [],
                       queue: MergeQueue? = nil) -> RepoState {
        RepoState(repo: repo, defaultBranch: "main", headSHA: head,
                  checks: Dictionary(uniqueKeysWithValues: checks.map { ($0.key, $0) }), mergeQueue: queue)
    }

    private func entry(_ number: Int, position: Int?, state: MergeQueueEntryState = .queued,
                       author: String = "ana") -> MergeQueueEntry {
        MergeQueueEntry(position: position, number: number, title: "Change \(number)", author: author, state: state,
                        htmlURL: URL(string: "https://github.com/acme/web/pull/\(number)"))
    }

    private func assertTranslated(_ text: UIText?, file: StaticString = #filePath, line: UInt = #line) {
        guard let text else { return XCTFail("no text", file: file, line: line) }
        guard case .languages(let localized) = text else { return XCTFail("\(text) is plain", file: file, line: line) }
        XCTAssertEqual(Set(localized.byLanguage.keys), Set(Words.languages), file: file, line: line)
    }

    private func assertTheAppReads(_ page: UITree, _ name: String, file: StaticString = #filePath, line: UInt = #line) {
        guard let sent = try? JSONEncoder().encode(page) else { return XCTFail(name, file: file, line: line) }
        XCTAssertNoThrow(try JSONDecoder().decode(UITree.self, from: sent), name, file: file, line: line)
        XCTAssertLessThanOrEqual(sent.count, UILimits.maxTreeBytes, name, file: file, line: line)
        XCTAssertLessThanOrEqual(page.blocks.count, UILimits.maxBlocks, name, file: file, line: line)
    }

    // MARK: 1. The branch and head on a repository's row

    func testARepositoryRowNamesItsDefaultBranchAndShortHead() {
        let summary = GitHubSummary(states: [Self.web: state()], watched: [Self.web, Self.api])
        XCTAssertEqual(summary.repositories[0].branchAndHead, "main · a1b2c3d", "seven characters of the head")
        XCTAssertNil(summary.repositories[1].branchAndHead, "a repository not read yet names nothing")
        let headless = GitHubSummary(states: [Self.web: state(head: nil)], watched: [Self.web])
        XCTAssertEqual(headless.repositories[0].branchAndHead, "main", "the branch alone before the head is known")

        let page = Pages.island(summary: summary, auth: .signedIn(login: "me"))
        guard case .row(let known) = page.blocks[0].content, case .row(let unknown) = page.blocks[1].content
        else { return XCTFail() }
        XCTAssertEqual(known.trailing, .plain("main · a1b2c3d"))
        XCTAssertNil(unknown.trailing)
    }

    // MARK: 2. A repository's own check list

    func testARepositoryPageListsItsChecksRedAmberGreenGreyWithBackAndActions() {
        let checks = [
            check("check_run:1", "z-pass", url: "https://x/1"),
            check("check_run:2", "b-fail", conclusion: .failure, url: "https://x/2"),
            check("check_run:3", "a-run", status: .inProgress, conclusion: nil),
            check("workflow_run:4", "a-fail", conclusion: .startupFailure),
            check("check_run:5", "c-unknown", conclusion: .other("unknown")),
            check("check_run:6", "a-wait", status: .waiting, conclusion: nil),
        ]
        let page = Pages.repoDetail(repo: Self.web, state: state(checks: checks))
        XCTAssertEqual(page.kinds, ["button", "row", "heading", "list"])
        XCTAssertEqual(page.ids, ["back", "repodetail.acme.web", "branchChecks"])
        XCTAssertEqual(page.english(0), "Back")
        guard case .row(let header) = page.blocks[1].content else { return XCTFail() }
        XCTAssertEqual(header.title, .plain("acme/web"))
        XCTAssertEqual(header.subtitle, .plain("main · a1b2c3d"))
        XCTAssertEqual(header.icon, "xmark.circle.fill", "the header carries the branch's colour")
        XCTAssertEqual(header.trailing?.text(for: "en"), "Open in GitHub")
        guard case .list(let list) = page.blocks[3].content else { return XCTFail() }
        XCTAssertEqual(list.rows.map { $0.title.text(for: "en") },
                       ["a-fail", "b-fail", "a-run", "a-wait", "z-pass", "c-unknown"],
                       "red, then amber, then green, then grey; by name within each")
        XCTAssertEqual(list.rows.map { $0.trailing?.text(for: "en") }, ["Failed", "Failed", "Running", "Running", "Passed", nil])
        XCTAssertEqual(list.rows.map(\.icon), ["xmark.circle.fill", "xmark.circle.fill", "clock.fill", "clock.fill",
                                               "checkmark.circle.fill", "circle.dashed"])
        XCTAssertEqual(list.rows[0].id, "branchcheck.acme.web.workflow__run_c4")
        XCTAssertEqual(Pages.branchCheck(ofRow: list.rows[0].id)?.runID, "workflow_run:4")
        assertTheAppReads(page, "a repository's page")
        for block in page.blocks {
            if case .button(let button) = block.content { assertTranslated(button.title) }
            if case .heading(let heading) = block.content { assertTranslated(heading.text) }
        }
    }

    func testARepositoryPageWithNoChecksOrNoStateYetAndTooManyChecks() throws {
        let empty = Pages.repoDetail(repo: Self.web, state: state())
        XCTAssertEqual(empty.kinds, ["button", "row", "heading", "text"])
        XCTAssertEqual(empty.english(3), "No checks yet")
        let unread = Pages.repoDetail(repo: Self.web, state: nil)
        XCTAssertEqual(unread.kinds, ["button", "row", "heading", "text"])
        guard case .row(let header) = unread.blocks[1].content else { return XCTFail() }
        XCTAssertNil(header.subtitle, "nothing to say about a branch not read yet")
        XCTAssertEqual(header.icon, "circle.dashed")

        let many = (1...(Pages.maxCheckRows + 3)).map { check("check_run:\($0)", String(format: "check-%03d", $0)) }
        let page = Pages.repoDetail(repo: Self.web, state: state(checks: many))
        guard case .list(let list) = page.blocks[3].content else { return XCTFail() }
        XCTAssertEqual(list.rows.count, Pages.maxCheckRows + 1)
        XCTAssertEqual(list.rows.last?.id, "repodetail.acme.web", "the overflow row opens the Actions page")
        XCTAssertEqual(list.rows.last?.title.text(for: "en"), "+3 more on GitHub")
        assertTheAppReads(page, "a repository with many checks")
    }

    func testTheNewRowIdsAreWellFormedAndReadBack() {
        for fullName in ["acme/web", "acme/.github", "acme/a.b", "acme/a_b", "a-b/c-d", "acme/x_dy", "acme/v1.2.3"] {
            guard let repo = RepoKey(fullName: fullName) else { return XCTFail(fullName) }
            let detail = Pages.repoDetailRow(repo)
            XCTAssertTrue(ManifestRules.isWellFormedName(detail), detail)
            XCTAssertEqual(Pages.repoDetail(ofRow: detail), repo)
            XCTAssertNil(Pages.repo(ofRow: detail), "a header row is not a repository row")
            XCTAssertNil(Pages.repoDetail(ofRow: Pages.repoRow(repo)), "a repository row is not a header row")
            for key in ["check_run:70", "workflow_run:12", "check_run:a_b.c:d"] {
                let row = Pages.branchCheckRow(repo, key)
                XCTAssertTrue(ManifestRules.isWellFormedName(row), row)
                XCTAssertEqual(Pages.branchCheck(ofRow: row)?.repo, repo)
                XCTAssertEqual(Pages.branchCheck(ofRow: row)?.runID, key)
                XCTAssertNil(Pages.check(ofRow: row), "a branch check is not a pull request's")
            }
            let queue = Pages.queueRow(repo, 42)
            XCTAssertTrue(ManifestRules.isWellFormedName(queue), queue)
            XCTAssertEqual(Pages.queueEntry(ofRow: queue)?.repo, repo)
            XCTAssertEqual(Pages.queueEntry(ofRow: queue)?.number, 42)
            XCTAssertNil(Pages.pull(ofRow: queue))
            let queuePage = Pages.queuePageRow(repo)
            XCTAssertTrue(ManifestRules.isWellFormedName(queuePage), queuePage)
            XCTAssertEqual(Pages.queuePage(ofRow: queuePage), repo)
        }
        let long = RepoKey(owner: "acme", name: String(repeating: "n", count: 200))
        for row in [Pages.repoDetailRow(long), Pages.branchCheckRow(long, "check_run:1"), Pages.queueRow(long, 1),
                    Pages.queuePageRow(long)] {
            XCTAssertTrue(ManifestRules.isWellFormedName(row), "a name too long still gives a page the app reads")
        }
        XCTAssertNil(Pages.repoDetail(ofRow: Pages.repoDetailRow(long)), "and its row names nothing")
        XCTAssertNotEqual(Pages.branchCheckRow(long, "check_run:1"), Pages.branchCheckRow(long, "check_run:2"))
    }

    // MARK: 3. The merge queue

    func testTheQueueIsOrderedByPositionWithoutOneLast() {
        let queue = MergeQueue(entries: [entry(9, position: 3), entry(4, position: nil), entry(7, position: 1),
                                         entry(2, position: nil), entry(8, position: 2)])
        XCTAssertEqual(queue.ordered.map(\.number), [7, 8, 9, 2, 4])
    }

    func testTheIslandShowsTheFocusedRepositorysMergeQueue() {
        let queue = MergeQueue(entries: [
            entry(12, position: 2, state: .awaitingChecks),
            entry(11, position: 1, state: .mergeable),
            entry(13, position: 3, state: .unmergeable, author: ""),
            entry(14, position: nil, state: .locked),
            entry(15, position: nil, state: .other("NEW_STATE"), author: ""),
        ])
        let summary = GitHubSummary(states: [Self.web: state(queue: queue), Self.api: state(Self.api)],
                                    watched: [Self.web, Self.api])
        let page = Pages.island(summary: summary, auth: .signedIn(login: "me"))
        XCTAssertEqual(page.kinds, ["row", "row", "heading", "list", "heading", "text", "button", "button", "button"])
        XCTAssertEqual(page.ids, ["repo.acme.web", "repo.acme.api", "queue", "openPulls", "refresh", "openRepo"])
        XCTAssertEqual(page.english(2), "Merge queue")
        guard case .list(let list) = page.blocks[3].content else { return XCTFail() }
        XCTAssertEqual(list.rows.map(\.id), ["queue.acme.web.11", "queue.acme.web.12", "queue.acme.web.13",
                                             "queue.acme.web.14", "queue.acme.web.15"], "in queue order")
        XCTAssertEqual(list.rows[0].title, .plain("#11 Change 11"))
        XCTAssertEqual(list.rows.map { $0.subtitle?.text(for: "en") },
                       ["Position 1 · @ana", "Position 2 · @ana", "In merge queue (#3)", "@ana", nil])
        XCTAssertEqual(list.rows.map { $0.trailing?.text(for: "en") },
                       ["Ready to merge", "Checks running", "Can’t merge", "Locked", "Queued"])
        XCTAssertEqual(list.rows.map(\.icon), ["checkmark.circle.fill", "clock.fill", "xmark.circle.fill", "lock.fill",
                                               "circle.dashed"])
        for row in list.rows { assertTranslated(row.trailing) }
        assertTranslated(list.rows[0].subtitle)

        let other = Pages.island(summary: summary, auth: .signedIn(login: "me"), focus: Self.api)
        XCTAssertFalse(other.ids.contains("queue"), "acme/api has no queue, so its focus shows none")
        XCTAssertEqual(other.kinds.filter { $0 == "heading" }.count, 1, "only the pull requests' heading")
    }

    func testAnEmptyQueueSaysSoAndALongOneEndsInALinkToIt() {
        let empty = GitHubSummary(states: [Self.web: state(queue: MergeQueue())], watched: [Self.web])
        let page = Pages.island(summary: empty, auth: .signedIn(login: "me"))
        XCTAssertEqual(Array(page.kinds.prefix(4)), ["row", "heading", "text", "heading"])
        XCTAssertEqual(page.english(2), "The merge queue is empty.")
        assertTranslated({ if case .text(let t) = page.blocks[2].content { return t.text }; return nil }())

        let long = MergeQueue(entries: (1...(Pages.maxQueueRows + 4)).map { entry($0, position: $0) })
        let rows = Pages.queueRows(Self.web, long)
        XCTAssertEqual(rows.count, Pages.maxQueueRows + 1)
        XCTAssertEqual(rows.last?.id, "mergequeue.acme.web")
        XCTAssertEqual(rows.last?.title.text(for: "en"), "+4 more on GitHub")
        let full = GitHubSummary(states: [Self.web: state(queue: long)], watched: [Self.web])
        assertTheAppReads(Pages.island(summary: full, auth: .signedIn(login: "me")), "a long queue")

        let none = GitHubSummary(states: [Self.web: state(queue: nil)], watched: [Self.web])
        XCTAssertFalse(Pages.island(summary: none, auth: .signedIn(login: "me")).ids.contains("queue"))
        XCTAssertEqual(Pages.island(summary: none, auth: .signedIn(login: "me")).kinds.filter { $0 == "heading" }.count, 1,
                       "a branch with no queue shows no queue heading")
    }

    func testTheRepositoryPageShowsItsQueueToo() {
        let page = Pages.repoDetail(repo: Self.web, state: state(queue: MergeQueue(entries: [entry(5, position: 1)])))
        XCTAssertEqual(page.kinds, ["button", "row", "heading", "list", "heading", "text"])
        XCTAssertEqual(page.ids, ["back", "repodetail.acme.web", "queue"])
        XCTAssertEqual(page.english(2), "Merge queue")
    }

    func testMergeQueueEntryStatesReadGitHubsWords() {
        XCTAssertEqual(MergeQueueEntryState(raw: "QUEUED"), .queued)
        XCTAssertEqual(MergeQueueEntryState(raw: "AWAITING_CHECKS"), .awaitingChecks)
        XCTAssertEqual(MergeQueueEntryState(raw: "mergeable"), .mergeable)
        XCTAssertEqual(MergeQueueEntryState(raw: "UNMERGEABLE"), .unmergeable)
        XCTAssertEqual(MergeQueueEntryState(raw: "LOCKED"), .locked)
        XCTAssertEqual(MergeQueueEntryState(raw: "SOMETHING_NEW"), .other("SOMETHING_NEW"))
    }

    // MARK: 4. The picker and Open in GitHub

    func testThePickerIsOfferedOnlyToAnAppWithChoiceAndMoreThanOneRepository() throws {
        let two = GitHubSummary(states: [Self.web: state()], watched: [Self.web, Self.api])
        let page = Pages.island(summary: two, auth: .signedIn(login: "me"), focus: Self.api, offersPicker: true)
        XCTAssertEqual(page.kinds.first, "choice")
        XCTAssertEqual(page.ids.first, "repoPicker")
        guard case .choice(let choice) = page.blocks[0].content else { return XCTFail() }
        XCTAssertEqual(choice.value, "acme/api", "the picked repository is the selected one")
        XCTAssertEqual(choice.options.map(\.value), ["acme/web", "acme/api"], "in watch order")
        XCTAssertEqual(choice.title?.text(for: "en"), "Repository")
        assertTranslated(choice.title)
        XCTAssertEqual(page.blocks[0].fallback?.text(for: "en"), "Repository: acme/api",
                       "what an app without choice would draw")
        assertTheAppReads(page, "the island with a picker")

        XCTAssertFalse(Pages.island(summary: two, auth: .signedIn(login: "me"), offersPicker: false).kinds.contains("choice"),
                       "an app before 3.48 is not sent a menu it cannot change")
        let one = GitHubSummary(states: [Self.web: state()], watched: [Self.web])
        XCTAssertFalse(Pages.island(summary: one, auth: .signedIn(login: "me"), offersPicker: true).kinds.contains("choice"),
                       "one repository needs no picker")
        let unknown = Pages.island(summary: two, auth: .signedIn(login: "me"), focus: RepoKey(owner: "x", name: "y"),
                                   offersPicker: true)
        guard case .choice(let fallback) = unknown.blocks[0].content else { return XCTFail() }
        XCTAssertEqual(fallback.value, "acme/web", "a focus no longer watched falls back to the first")
    }

    func testThePickerStaysWithinWhatAChoiceMayHold() throws {
        let long = RepoKey(owner: String(repeating: "o", count: 39), name: String(repeating: "n", count: 100))
        var watched = [long]
        watched += (0..<(UILimits.maxChoiceOptions + 6)).map { RepoKey(owner: "acme", name: "r\($0)") }
        let summary = GitHubSummary(states: [:], watched: watched)
        let page = Pages.island(summary: summary, auth: .signedIn(login: "me"), offersPicker: true)
        guard case .choice(let choice) = page.blocks[0].content else { return XCTFail() }
        XCTAssertEqual(choice.options.count, UILimits.maxChoiceOptions)
        XCTAssertFalse(choice.options.contains { $0.value == long.fullName }, "a name longer than a choice's value is left out")
        XCTAssertEqual(choice.value.unicodeScalars.count, UILimits.maxChoiceValueLength,
                       "and, focused, it is shown cut rather than costing the page")
        XCTAssertTrue(choice.value.hasSuffix("…"))
        XCTAssertEqual(Pages.pickerValue(Self.web), "acme/web")
        assertTheAppReads(page, "a picker of many")
    }

    func testFocusedIsThePickedRepositoryOrTheFirst() {
        let summary = GitHubSummary(states: [:], watched: [Self.web, Self.api])
        XCTAssertEqual(Pages.focused(summary, focus: Self.api)?.repo, Self.api)
        XCTAssertEqual(Pages.focused(summary, focus: nil)?.repo, Self.web)
        XCTAssertEqual(Pages.focused(summary, focus: RepoKey(owner: "gone", name: "x"))?.repo, Self.web)
        XCTAssertNil(Pages.focused(GitHubSummary(states: [:], watched: []), focus: Self.web))
        XCTAssertEqual(Pages.webURL(Self.web), "https://github.com/acme/web")
    }

    // MARK: 6. When GitHub was last read

    func testTheLastReadIsWrittenInEachLanguagesOwnTime() {
        let when = Date(timeIntervalSince1970: 1_000_000)
        let utc = TimeZone(identifier: "UTC")!
        let text = Pages.lastUpdatedText(when, timeZone: utc)
        assertTranslated(text)
        XCTAssertEqual(text.text(for: "de"), "Aktualisiert um 13:46:40")
        XCTAssertEqual(text.text(for: "fr"), "Mis à jour à 13:46:40")
        XCTAssertTrue(text.text(for: "en").hasPrefix("Updated at 1:46:40"), text.text(for: "en"))
        XCTAssertTrue(text.text(for: "en").hasSuffix("PM"), "English writes a twelve-hour time")
        XCTAssertTrue(text.text(for: "ja").contains("13:46:40"), text.text(for: "ja"))
        let tokyo = Pages.lastUpdatedText(when, timeZone: TimeZone(identifier: "Asia/Tokyo")!)
        XCTAssertEqual(tokyo.text(for: "de"), "Aktualisiert um 22:46:40", "in the zone given")

        let summary = GitHubSummary(states: [Self.web: state()], watched: [Self.web])
        let page = Pages.island(summary: summary, auth: .signedIn(login: "me"), lastUpdated: when, timeZone: utc)
        XCTAssertEqual(page.kinds.last, "text")
        XCTAssertEqual(page.english(page.blocks.count - 1), text.text(for: "en"))
        guard case .text(let caption) = page.blocks.last?.content else { return XCTFail() }
        XCTAssertEqual(caption.style, .caption)
        XCTAssertNotEqual(Pages.island(summary: summary, auth: .signedIn(login: "me")).kinds.last, "text",
                          "nothing read yet, no time")
    }

    func testFormatEachFillsEachLanguageWithItsOwnWords() {
        let text = Words.format("lastUpdatedFormat") { "<\($0)>" }
        XCTAssertEqual(text.text(for: "en"), "Updated at <en>")
        XCTAssertEqual(text.text(for: "zh-TW"), "更新於 <zh-TW>")
        XCTAssertEqual(Words.format("no-such-key") { $0 }, .plain("no-such-key"))
    }

    // MARK: 5. Settings: Copy and the token link

    func testSettingsOffersTheTokenPageAndCopiesTheCode() {
        let out = Pages.settings(.init(auth: .signedOut))
        guard let linkBlock = out.blocks.first(where: { $0.type == "link" }), case .link(let link) = linkBlock.content
        else { return XCTFail("a link to make a token") }
        XCTAssertEqual(link.url, "https://github.com/settings/tokens/new?description=Vitruvian%20Desktop&scopes=repo,workflow,read:org")
        XCTAssertEqual(link.title.text(for: "en"), "Create a token on GitHub")
        assertTranslated(link.title)
        let failed = Pages.settings(.init(auth: .failed(.tokenRejected)))
        XCTAssertTrue(failed.kinds.contains("link"), "offered again after a failure")
        XCTAssertFalse(Pages.settings(.init(auth: .signedIn(login: "me"))).kinds.contains("link"),
                       "not offered once signed in")

        let code = Pages.settings(.init(auth: .deviceFlow(userCode: "ABCD-1234",
                                                          verificationURL: URL(string: "https://github.com/login/device")!)))
        XCTAssertEqual(code.ids.first, "copyCode")
        guard let copy = code.blocks.first(where: { $0.id == "copyCode" }), case .button(let button) = copy.content
        else { return XCTFail() }
        assertTranslated(button.title)
        XCTAssertFalse(Pages.settings(.init(auth: .signedOut)).ids.contains("copyCode"), "no code, nothing to copy")
    }

    func testTheManifestAsksForTheClipboard() throws {
        let uses = try XCTUnwrap(ToolFiles.manifest()?.uses)
        XCTAssertTrue(uses.contains("clipboard.write"), "the app refuses clipboard/writeText without it")
        XCTAssertFalse(uses.contains("clipboard.read"), "the tool only writes")
        XCTAssertEqual(ToolFiles.manifest()?.problems() ?? [], [], "and the manifest is still one the app will add")
    }

    // MARK: 7. The mouse's test buttons

    func testTheMouseTestButtonsShowOnlyWithACommandAndTheMouseOn() {
        let ids = MouseTest.allCases.map(\.rawValue)
        XCTAssertEqual(ids, ["testApproval", "testSuccess", "testRunning", "testFailure", "testIdle"])
        let on = Pages.settings(.init(auth: .signedIn(login: "me"), mouseCommand: "/usr/bin/gravastar-mouse"))
        XCTAssertEqual(Array(on.ids.suffix(5)), ids)
        let hint = on.blocks.firstIndex { $0.id == "testApproval" }! - 1
        XCTAssertEqual(on.english(hint), "Try each light on the mouse now.")
        XCTAssertEqual(MouseTest.allCases.map { test in on.english(on.blocks.firstIndex { $0.id == test.rawValue }!) },
                       ["Waiting for approval", "Passed", "Running", "Failed", "Idle"])
        for block in on.blocks where ids.contains(block.id ?? "") {
            if case .button(let button) = block.content { assertTranslated(button.title) }
        }

        let missing = Pages.settings(.init(auth: .signedIn(login: "me"), mouseCommand: nil))
        XCTAssertFalse(missing.ids.contains { ids.contains($0) }, "no command to run, no buttons")
        XCTAssertFalse(missing.kinds.suffix(1).contains("button"))
        let off = Pages.settings(.init(auth: .signedIn(login: "me"), mouseCommand: "/usr/bin/gravastar-mouse",
                                       mouseIndicator: false))
        XCTAssertFalse(off.ids.contains { ids.contains($0) }, "the mouse not showing the status, no buttons")
        let signedOut = Pages.settings(.init(auth: .signedOut, mouseCommand: "/usr/bin/gravastar-mouse"))
        XCTAssertEqual(Array(signedOut.ids.suffix(5)), ids, "the mouse can be tried before signing in")
    }

    func testEachTestFiresTheConfiguredLight() {
        let defaults = MouseSettings.defaults
        XCTAssertEqual(MouseTest.approval.arguments(settings: defaults), ["breathe", "blue", "--speed", "9"])
        XCTAssertEqual(MouseTest.success.arguments(settings: defaults), ["color", "green"])
        XCTAssertEqual(MouseTest.running.arguments(settings: defaults), ["breathe", "orange"])
        XCTAssertEqual(MouseTest.failure.arguments(settings: defaults), ["breathe", "red"])
        XCTAssertEqual(MouseTest.idle.arguments(settings: defaults), ["restore"])
        let mine = MouseSettings(success: "breathe cyan", running: "yellow", failure: "pink", approval: "white",
                                 idle: "off")
        XCTAssertEqual(MouseTest.approval.arguments(settings: mine), ["color", "white"])
        XCTAssertEqual(MouseTest.success.arguments(settings: mine), ["breathe", "cyan"])
        XCTAssertEqual(MouseTest.running.arguments(settings: mine), ["color", "yellow"])
        XCTAssertEqual(MouseTest.failure.arguments(settings: mine), ["color", "pink"])
        XCTAssertEqual(MouseTest.idle.arguments(settings: mine), ["off"])
    }

    func testATestIsForgottenSoTheNextSnapshotWritesTheRealLight() {
        var sent: [[String]] = []
        let driver = MouseDriver { sent.append($0) }
        driver.update(verdict: .green, settings: .defaults)
        driver.update(verdict: .green, settings: .defaults)
        XCTAssertEqual(sent, [["color", "green"]], "a repeated state writes nothing")
        driver.test(.failure, settings: .defaults)
        XCTAssertEqual(sent.last, ["breathe", "red"])
        driver.update(verdict: .green, settings: .defaults)
        XCTAssertEqual(sent.last, ["color", "green"], "the real light goes back on the next snapshot")
        XCTAssertEqual(sent.count, 3)
    }

    // MARK: The API: the merge queue

    func testTheMergeQueueIsReadFromGraphQL() throws {
        let answer = #"""
            {"data": {"repository": {"mergeQueue": {"url": "https://github.com/acme/web/queue/main", "entries": {"nodes": [
              {"position": 2, "state": "AWAITING_CHECKS", "pullRequest": {"number": 12, "title": "Two", "url": "https://github.com/acme/web/pull/12", "author": {"login": "ana"}}},
              {"position": 1, "state": "MERGEABLE", "pullRequest": {"number": 11, "title": "One", "url": "https://github.com/acme/web/pull/11", "author": null}},
              null,
              {"position": 3, "state": "QUEUED", "pullRequest": null}
            ]}}}}}
            """#
        let queue = try XCTUnwrap(GitHubAPI.mergeQueue(from: Data(answer.utf8)))
        XCTAssertEqual(queue.htmlURL, URL(string: "https://github.com/acme/web/queue/main"))
        XCTAssertEqual(queue.entries, [
            MergeQueueEntry(position: 2, number: 12, title: "Two", author: "ana", state: .awaitingChecks,
                            htmlURL: URL(string: "https://github.com/acme/web/pull/12")),
            MergeQueueEntry(position: 1, number: 11, title: "One", author: "", state: .mergeable,
                            htmlURL: URL(string: "https://github.com/acme/web/pull/11")),
        ], "an empty node and an entry with no pull request are left out")
        XCTAssertEqual(GitHubAPI.mergeQueue(from: Data(#"{"data": {"repository": {"mergeQueue": {"entries": {"nodes": []}}}}}"#.utf8)),
                       MergeQueue(), "a queue with nothing in it is empty, not missing")
        XCTAssertNil(GitHubAPI.mergeQueue(from: Data(#"{"data": {"repository": {"mergeQueue": null}}}"#.utf8)),
                     "a branch without a merge queue")
        XCTAssertNil(GitHubAPI.mergeQueue(from: Data(#"{"data": null, "errors": [{"message": "no"}]}"#.utf8)))
        XCTAssertNil(GitHubAPI.mergeQueue(from: Data("not json".utf8)))
    }

    func testTheSnapshotCarriesTheQueueAndTakesPositionsFromIt() throws {
        let transport = FakeTransport()
        let api = GitHubAPI(transport: transport, apiURL: URL(string: "https://api.test")!,
                            webURL: URL(string: "https://web.test")!)
        transport.answers["/repos/acme/web"] = (200, #"{"default_branch": "main"}"#)
        transport.answers["/repos/acme/web/commits/main"] = (200, #"{"sha": "head1"}"#)
        transport.answers["/repos/acme/web/pulls?state=open&per_page=100"] = (200, #"[{"number": 11, "title": "Mine", "draft": false, "html_url": null, "user": {"login": "james"}, "head": {"sha": "p11"}, "requested_reviewers": [], "requested_teams": []}]"#)
        transport.answers["/graphql"] = (200, #"{"data": {"repository": {"mergeQueue": {"url": null, "entries": {"nodes": [{"position": 1, "state": "MERGEABLE", "pullRequest": {"number": 30, "title": "Someone's", "url": null, "author": {"login": "bo"}}}, {"position": 2, "state": "QUEUED", "pullRequest": {"number": 11, "title": "Mine", "url": null, "author": {"login": "james"}}}]}}}}}"#)
        let me = GitHubIdentity(login: "james", teams: [])
        let state = try XCTUnwrap(try api.snapshot(repo: Self.web, token: "t", identity: me))
        XCTAssertEqual(state.mergeQueue?.entries.map(\.number), [30, 11], "the whole queue, whoever wrote each")
        XCTAssertEqual(state.pullRequests[11]?.mergeQueue, MergeQueueState(position: 2))
        let request = try XCTUnwrap(transport.requests.first { $0.url?.path == "/graphql" })
        XCTAssertEqual(request.httpMethod, "POST")
        XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer t")
        XCTAssertNil(request.value(forHTTPHeaderField: "If-None-Match"), "a POST is never conditional")
        let body = String(decoding: request.httpBody ?? Data(), as: UTF8.self)
        for field in ["mergeQueue(branch: $branch)", "state", "title", "author", "url", #""branch":"main""#] {
            XCTAssertTrue(body.contains(field), "the query asks for \(field)")
        }

        // With no pull request of the person's, the queue is still read.
        transport.requests.removeAll()
        transport.answers["/repos/acme/web/pulls?state=open&per_page=100"] = (200, "[]")
        let quiet = try XCTUnwrap(try api.snapshot(repo: Self.web, token: "t", identity: me, known: state))
        XCTAssertEqual(quiet.mergeQueue?.entries.count, 2)
        XCTAssertEqual(transport.requests.filter { $0.url?.path == "/graphql" }.count, 1, "one query a poll")

        // GitHub refusing the query leaves the queue unknown, not empty.
        transport.answers["/graphql"] = (502, "{}")
        XCTAssertNil(try api.snapshot(repo: Self.web, token: "t", identity: me, known: state)?.mergeQueue)
        XCTAssertNil(api.mergeQueue(repo: Self.web, branch: "main", token: "t"))
    }
}
