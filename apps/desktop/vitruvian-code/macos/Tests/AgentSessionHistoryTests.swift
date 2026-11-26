// Copyright (c) 2026 VitruvianSoftware
//
// Permission is hereby granted, free of charge, to any person obtaining a copy
// of this software and associated documentation files (the "Software"), to deal
// in the Software without restriction, including without limitation the rights
// to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
// copies of the Software, and to permit persons to whom the Software is
// furnished to do so, subject to the following conditions:
//
// The above copyright notice and this permission notice shall be included in
// all copies or substantial portions of the Software.
//
// THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
// IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
// FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
// AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
// LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
// OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
// SOFTWARE.

import Foundation
@testable import VitruvianCodeCore
import XCTest

/// The chat's "Recent sessions" list read from the agent's own `session/list`
/// where its connection advertises it, with the transcript readers as the
/// fallback (`AgentSessionHistory`).
@MainActor
final class AgentSessionHistoryTests: XCTestCase {
    private static let agentSpec = AgentProcessLaunchSpec(
        executable: "/fake/agy",
        arguments: ["acp"],
        environment: [:],
        workingDirectory: "/workspace"
    )

    private static var agyACPProvider: VitruvianCodeCLIProvider {
        var provider = VitruvianCodeCLIProvider.antigravity
        provider.connection = .acp
        return provider
    }

    private static func initializeResult(list: Bool) -> ACPJSONValue {
        var sessionCaps: [String: ACPJSONValue] = ["resume": .object([:]), "close": .object([:])]
        if list { sessionCaps["list"] = .object([:]) }
        return .object([
            "jsonrpc": .string("2.0"),
            "id": .string("$id"),
            "result": .object([
                "protocolVersion": .int(1),
                "agentCapabilities": .object(["sessionCapabilities": .object(sessionCaps)]),
            ]),
        ])
    }

    private static func reply(_ result: ACPJSONValue) -> ACPJSONValue {
        .object(["jsonrpc": .string("2.0"), "id": .string("$id"), "result": result])
    }


    private static let newSessionSteps: [ACPFixtureStep] = [
        .expectClientRequest(method: "session/new"),
        .agentSend(reply(.object(["sessionId": .string("s-open")]))),
    ]

    // MARK: - The ACP client

    /// agy 1.5.16's real `session/list` exchange (ids and titles replaced), asked
    /// over an open chat connection: agy wants `authenticate` first, then lists
    /// folders, titles and times.
    func testAgyListsOverAnOpenConnectionAndSignsInWhenAsked() async throws {
        let agent = ScriptedACPAgent()
        let connection = ACPConnection(
            launchSpec: Self.agentSpec,
            hooks: ACPConnection.Hooks(authMethodID: AntigravityACPSupport.authMethodID),
            processFactory: agent.makeProcessFactory()
        )
        let steps = ACPFixtureLoader.loadSteps(named: "session-list-agy.ndjson")
        let driver = Task { try await agent.playSteps(steps) }
        _ = try await withACPTestTimeout(seconds: 5.0) {
            try await connection.start(AgentSessionRequest(workingDirectory: "/workspace/app"))
        }
        let page = try await withACPTestTimeout(seconds: 5.0) {
            try await connection.listSessionPage(cwd: "/workspace/app", cursor: nil)
        }
        try await withACPTestTimeout(seconds: 5.0) { try await driver.value }

        XCTAssertEqual(page.sessions.map(\.id), [
            "0b7f3c1e-1111-4a5b-9c6d-000000000001",
            "0b7f3c1e-2222-4a5b-9c6d-000000000002",
            "0b7f3c1e-3333-4a5b-9c6d-000000000003",
        ])
        XCTAssertEqual(page.sessions.first?.cwd, "/workspace/app")
        XCTAssertEqual(page.sessions.first?.title, "Fix the login redirect")
        XCTAssertEqual(page.sessions.first?.updatedAt, "2026-11-23T17:01:24Z")
        XCTAssertNil(page.nextCursor)

        let methods = await agent.allClientMessages().compactMap { $0.objectValue?["method"]?.stringValue }
        XCTAssertEqual(methods, ["initialize", "session/new", "session/list", "authenticate", "session/list"])
        let listParams = try await agent.clientMessage(at: 2).objectValue?["params"]?.objectValue
        XCTAssertEqual(listParams?["cwd"]?.stringValue, "/workspace/app")
        XCTAssertNil(listParams?["cursor"])
        let authParams = try await agent.clientMessage(at: 3).objectValue?["params"]?.objectValue
        XCTAssertEqual(authParams?["methodId"]?.stringValue, AntigravityACPSupport.authMethodID)
        await connection.stop()
    }

    /// Listing never starts the agent: a connection with no process throws and launches nothing.
    func testListingANotStartedConnectionStartsNoProcess() async throws {
        let launches = HistoryCounter()
        let connection = ACPConnection(launchSpec: Self.agentSpec, processFactory: { _ in
            launches.increment()
            throw ACPConnectionError.notStarted
        })
        do {
            _ = try await connection.listSessionPage(cwd: "/w", cursor: nil)
            XCTFail("Expected notStarted")
        } catch ACPConnectionError.notStarted {
            // expected
        }
        XCTAssertEqual(launches.value, 0)
    }

    func testCursorIsSentAndNextCursorReturned() async throws {
        let agent = ScriptedACPAgent()
        let connection = ACPConnection(launchSpec: Self.agentSpec, processFactory: agent.makeProcessFactory())
        let driver = Task {
            try await agent.playSteps([
                .expectClientRequest(method: "initialize"),
                .agentSend(Self.initializeResult(list: true)),
            ] + Self.newSessionSteps + [
                .expectClientRequest(method: "session/list"),
                .agentSend(Self.reply(.object([
                    "sessions": .array([
                        .object(["sessionId": .string("s-2"), "cwd": .string("/w"), "title": .null]),
                        .object(["cwd": .string("/no-id")]),
                    ]),
                    "nextCursor": .string("page-3"),
                ]))),
            ])
        }
        _ = try await withACPTestTimeout(seconds: 3.0) {
            try await connection.start(AgentSessionRequest(workingDirectory: "/w"))
        }
        let page = try await withACPTestTimeout(seconds: 3.0) {
            try await connection.listSessionPage(cwd: nil, cursor: "page-2")
        }
        try await withACPTestTimeout(seconds: 3.0) { try await driver.value }
        // The entry without an id is dropped, not the page.
        XCTAssertEqual(page, AgentSessionPage(sessions: [AgentListedSession(id: "s-2", cwd: "/w")],
                                              nextCursor: "page-3"))
        let params = try await agent.clientMessage(at: 2).objectValue?["params"]?.objectValue
        XCTAssertEqual(params?["cursor"]?.stringValue, "page-2")
        XCTAssertNil(params?["cwd"])
        await connection.stop()
    }

    func testAgentWithoutListIsNotAskedAndSaysSo() async throws {
        let agent = ScriptedACPAgent()
        let connection = ACPConnection(launchSpec: Self.agentSpec, processFactory: agent.makeProcessFactory())
        let driver = Task {
            try await agent.playSteps([
                .expectClientRequest(method: "initialize"),
                .agentSend(Self.initializeResult(list: false)),
            ] + Self.newSessionSteps)
        }
        _ = try await withACPTestTimeout(seconds: 3.0) {
            try await connection.start(AgentSessionRequest(workingDirectory: "/w"))
        }
        try await withACPTestTimeout(seconds: 3.0) { try await driver.value }
        do {
            _ = try await connection.listSessionPage(cwd: "/w", cursor: nil)
            XCTFail("Expected sessionListNotAdvertised")
        } catch ACPConnectionError.sessionListNotAdvertised {
            // expected
        }
        try? await Task.sleep(nanoseconds: 50_000_000)
        let methods = await agent.allClientMessages().compactMap { $0.objectValue?["method"]?.stringValue }
        XCTAssertEqual(methods, ["initialize", "session/new"])
        await connection.stop()
    }

    // MARK: - Paging

    func testFetchAllFollowsCursorsAndStopsWhenOneRepeats() async throws {
        let lister = FakeSessionLister(pages: [
            nil: AgentSessionPage(sessions: [AgentListedSession(id: "a")], nextCursor: "c1"),
            "c1": AgentSessionPage(sessions: [AgentListedSession(id: "b"), AgentListedSession(id: "a")],
                                   nextCursor: "c2"),
            "c2": AgentSessionPage(sessions: [AgentListedSession(id: "c")], nextCursor: "c1"),
        ])
        let listed = try await AgentSessionHistory.fetchAll(from: lister, cwd: "/w")
        XCTAssertEqual(listed.map(\.id), ["a", "b", "c"])
        XCTAssertEqual(lister.requests.map(\.cursor), [nil, "c1", "c2"])
        XCTAssertEqual(lister.requests.map(\.cwd), ["/w", "/w", "/w"])
    }

    func testFetchAllStopsAtThePageLimit() async throws {
        var pages: [String?: AgentSessionPage] = [:]
        for index in 0..<20 {
            pages[index == 0 ? nil : "c\(index)"] = AgentSessionPage(
                sessions: [AgentListedSession(id: "s\(index)")], nextCursor: "c\(index + 1)")
        }
        let lister = FakeSessionLister(pages: pages)
        let listed = try await AgentSessionHistory.fetchAll(from: lister, cwd: nil, maxPages: 3)
        XCTAssertEqual(listed.map(\.id), ["s0", "s1", "s2"])
        XCTAssertEqual(lister.requests.count, 3)
    }

    // MARK: - Rows

    func testRowsTakeTheAgentsTitlesTimesAndFoldersAndKeepTheFolderRule() {
        let transcriptRows = [
            VitruvianCodeSessionSummary(id: "s-1", title: "Old title", preview: "first prompt", steps: 7,
                                        modified: Date(timeIntervalSince1970: 0), isArchived: true,
                                        workspace: "/old/folder"),
        ]
        let listed = [
            AgentListedSession(id: "s-1", cwd: "/workspace/app", title: "Agent title\nsecond line",
                               updatedAt: "2026-11-23T17:01:24Z"),
            AgentListedSession(id: "s-2", cwd: "/elsewhere", title: "Other folder",
                               updatedAt: "2026-11-24T17:02:02Z"),
            AgentListedSession(id: "s-3", cwd: "/workspace/app/packages/ui/", title: "Inside",
                               updatedAt: "2026-11-24T09:15:00.250Z"),
            AgentListedSession(id: "s-4", cwd: "", title: nil, updatedAt: nil),
        ]
        let rows = AgentSessionHistory.summaries(listed: listed, directory: "/workspace/app", home: "/Users/me",
                                                 transcriptRows: transcriptRows,
                                                 now: Date(timeIntervalSince1970: 2_000_000_000))
        // Newest first; another folder is left out; a session with no folder stays.
        XCTAssertEqual(rows.map(\.id), ["s-3", "s-1", "s-4"])
        XCTAssertEqual(rows.map(\.title), ["Inside", "Agent title", ""])
        XCTAssertEqual(rows.map(\.workspace), ["/workspace/app/packages/ui", "/workspace/app", ""])
        XCTAssertEqual(rows[1].modified, AgentSessionHistory.parseDate("2026-11-23T17:01:24Z"))
        XCTAssertNotNil(rows[0].modified)
        // What session/list does not carry comes from the agent's own transcript index.
        XCTAssertEqual(rows[1].preview, "first prompt")
        XCTAssertEqual(rows[1].steps, 7)
        XCTAssertTrue(rows[1].isArchived)

        // An empty folder setting, or home, keeps every workspace.
        let all = AgentSessionHistory.summaries(listed: listed, directory: "", home: "/Users/me",
                                                transcriptRows: [])
        XCTAssertEqual(all.map(\.id), ["s-2", "s-3", "s-1", "s-4"])
        let home = AgentSessionHistory.summaries(listed: listed, directory: "/Users/me", home: "/Users/me",
                                                 transcriptRows: [])
        XCTAssertEqual(home.count, 4)
    }

    func testRowsAreCappedLikeTheTranscriptReader() {
        let listed = (0..<250).map { AgentListedSession(id: "s\($0)", cwd: "/w") }
        let rows = AgentSessionHistory.summaries(listed: listed, directory: "", home: "/h", transcriptRows: [])
        XCTAssertEqual(rows.count, AgentSessionHistory.maxSessions)
        XCTAssertEqual(rows.first?.id, "s0")
    }

    func testSessionInfoUpdatesOnlyItsRow() {
        let rows = [
            VitruvianCodeSessionSummary(id: "a", title: "A", preview: "p", steps: 2, modified: nil,
                                        workspace: "/w", isPinned: true),
            VitruvianCodeSessionSummary(id: "b", title: "B", steps: 1, modified: nil),
        ]
        let updated = AgentSessionHistory.applyingSessionInfo(
            title: "  Renamed by agent ", updatedAt: "2026-11-24T10:00:00Z", sessionID: "a", to: rows)
        XCTAssertEqual(updated.map(\.title), ["Renamed by agent", "B"])
        XCTAssertEqual(updated[0].modified, AgentSessionHistory.parseDate("2026-11-24T10:00:00Z"))
        XCTAssertEqual(updated[0].workspace, "/w")
        XCTAssertEqual(updated[0].preview, "p")
        XCTAssertTrue(updated[0].isPinned)
        XCTAssertEqual(updated[1], rows[1])
        // Nothing usable changes nothing.
        XCTAssertEqual(AgentSessionHistory.applyingSessionInfo(title: " ", updatedAt: nil, sessionID: "a", to: rows),
                       rows)
    }

    // MARK: - The chat's list

    private let transcriptRows = [
        VitruvianCodeSessionSummary(id: "t-2", title: "From transcript two", preview: "hello", steps: 3,
                                    modified: Date(timeIntervalSince1970: 1_800_000_200), workspace: "/projects/app"),
        VitruvianCodeSessionSummary(id: "t-1", title: "From transcript one", steps: 1,
                                    modified: Date(timeIntervalSince1970: 1_800_000_100)),
    ]

    /// A session whose live connections are `HistoryMockConnection`s, counted in `box`.
    private func makeSession(rig: ComposerRig, box: HistoryMockBox,
                             configure: @escaping @MainActor (HistoryMockConnection) -> Void = { _ in })
        -> VitruvianCodeQuickPromptSession {
        var environment = rig.environment
        environment.makeConnection = { _ in
            MainActor.assumeIsolated {
                let connection = HistoryMockConnection()
                configure(connection)
                box.items.append(connection)
                return connection
            }
        }
        environment.fileExists = { _ in true }
        environment.isExecutable = { _ in true }
        let session = VitruvianCodeQuickPromptSession(environment: environment, host: rig.host)
        session.takeCheckpoint = { _ in nil }
        return session
    }

    /// Opens a live chat and lets its first turn end, so the connection stays open.
    private func openLiveChat(_ session: VitruvianCodeQuickPromptSession, box: HistoryMockBox,
                              config: VitruvianCodeConfiguration) async throws -> HistoryMockConnection {
        session.send("Hello", configuration: config, agentPath: "/fake/agy")
        try await waitUntil("prompt sent") { box.items.first?.promptCount == 1 }
        let connection = box.items[0]
        connection.emit(.finished(status: "completed", response: "Hi", error: nil, conversationID: "new-1"))
        connection.finish()
        try await waitUntil("turn done") { !session.isRunning }
        return connection
    }

    private func waitUntil(_ description: String, condition: @escaping @MainActor () -> Bool) async throws {
        try await withACPTestTimeout(seconds: 4.0, description: description) { @MainActor in
            while !condition() { try? await Task.sleep(nanoseconds: 5_000_000) }
        }
    }

    private static func config(_ folder: String = "/projects/app") -> VitruvianCodeConfiguration {
        VitruvianCodeConfiguration(workingDirectory: folder, activeProvider: agyACPProvider)
    }

    func testWithNoLiveConnectionNoProcessStartsAndTheListIsTodays() async throws {
        let rig = ComposerRig()
        rig.sessions = transcriptRows
        let box = HistoryMockBox()
        let session = makeSession(rig: rig, box: box)
        session.refreshSessions(configuration: Self.config())
        session.toggleSessions(configuration: Self.config())
        try? await Task.sleep(nanoseconds: 50_000_000)
        XCTAssertTrue(box.items.isEmpty)
        XCTAssertEqual(session.sessions, transcriptRows)
    }

    func testTheLiveConnectionsListIsUsedAndAReopenedChatKeepsItsFolder() async throws {
        let rig = ComposerRig()
        rig.sessions = transcriptRows
        let box = HistoryMockBox()
        let session = makeSession(rig: rig, box: box) { connection in
            connection.pages = [nil: AgentSessionPage(sessions: [
                AgentListedSession(id: "t-2", cwd: "/projects/app/web", title: "Agent's own title",
                                   updatedAt: "2026-11-24T08:00:00Z"),
                AgentListedSession(id: "a-9", cwd: "/projects/app", title: "Only the agent knows",
                                   updatedAt: "2026-11-24T09:00:00Z"),
            ])]
        }
        let live = try await openLiveChat(session, box: box, config: Self.config())

        session.refreshSessions(configuration: Self.config())
        // Today's list shows at once; the agent's replaces it when it answers.
        XCTAssertEqual(session.sessions.map(\.id), ["t-2", "t-1"])
        try await waitUntil("agent list shown") { session.sessions.map(\.id) == ["a-9", "t-2"] }
        XCTAssertEqual(session.sessions.map(\.title), ["Only the agent knows", "Agent's own title"])
        XCTAssertEqual(session.sessions.map(\.workspace), ["/projects/app", "/projects/app/web"])
        XCTAssertEqual(session.sessions[1].preview, "hello")
        XCTAssertEqual(live.listRequests.map(\.cwd), ["/projects/app"])
        // Asked over the chat's own connection: none started, and it stays open.
        XCTAssertEqual(box.items.count, 1)
        XCTAssertTrue(live.isConnected)

        session.resume(session.sessions[1], configuration: Self.config())
        XCTAssertEqual(session.workingDirectory(for: Self.config()), "/projects/app/web")
        XCTAssertEqual(session.sessionTitle, "Agent's own title")
    }

    func testALiveConnectionWithoutTheListIsNotAsked() async throws {
        let rig = ComposerRig()
        rig.sessions = transcriptRows
        let box = HistoryMockBox()
        let session = makeSession(rig: rig, box: box) { $0.capabilities.listSessions = false }
        let live = try await openLiveChat(session, box: box, config: Self.config())
        session.refreshSessions(configuration: Self.config())
        try? await Task.sleep(nanoseconds: 50_000_000)
        XCTAssertTrue(live.listRequests.isEmpty)
        XCTAssertEqual(session.sessions, transcriptRows)
    }

    func testAnotherAgentsLiveConnectionIsNotAsked() async throws {
        let rig = ComposerRig()
        rig.sessions = transcriptRows
        let box = HistoryMockBox()
        let session = makeSession(rig: rig, box: box)
        let live = try await openLiveChat(session, box: box, config: Self.config())
        session.refreshSessions(configuration: VitruvianCodeConfiguration(workingDirectory: "/projects/app",
                                                                          activeProvider: .claude))
        try? await Task.sleep(nanoseconds: 50_000_000)
        XCTAssertTrue(live.listRequests.isEmpty)
        XCTAssertEqual(session.sessions, transcriptRows)
    }

    func testAnAgentThatSaysItHasNoListFallsBackAndIsNotAskedAgain() async throws {
        let rig = ComposerRig()
        rig.sessions = transcriptRows
        let box = HistoryMockBox()
        let session = makeSession(rig: rig, box: box) { $0.listError = ACPConnectionError.sessionListNotAdvertised }
        let live = try await openLiveChat(session, box: box, config: Self.config())
        session.refreshSessions(configuration: Self.config())
        try await waitUntil("asked once") { live.listRequests.count == 1 }
        try? await Task.sleep(nanoseconds: 30_000_000)
        session.refreshSessions(configuration: Self.config())
        try? await Task.sleep(nanoseconds: 30_000_000)
        XCTAssertEqual(live.listRequests.count, 1)
        XCTAssertEqual(session.sessions, transcriptRows)
    }

    func testAFailedListKeepsTodaysListAndAsksAgainNextTime() async throws {
        let rig = ComposerRig()
        rig.sessions = transcriptRows
        let box = HistoryMockBox()
        let session = makeSession(rig: rig, box: box) { $0.listError = ACPTransportError.connectionClosed("gone") }
        let live = try await openLiveChat(session, box: box, config: Self.config())
        session.refreshSessions(configuration: Self.config())
        try await waitUntil("asked once") { live.listRequests.count == 1 }
        try? await Task.sleep(nanoseconds: 30_000_000)
        XCTAssertEqual(session.sessions, transcriptRows)
        session.refreshSessions(configuration: Self.config())
        try await waitUntil("asked again") { live.listRequests.count == 2 }
        try? await Task.sleep(nanoseconds: 30_000_000)
        XCTAssertEqual(session.sessions, transcriptRows)
    }

    func testOneRequestAtATimeAndItsAnswerIsUsed() async throws {
        let rig = ComposerRig()
        rig.sessions = transcriptRows
        let box = HistoryMockBox()
        let session = makeSession(rig: rig, box: box) { connection in
            connection.pages = [nil: AgentSessionPage(sessions: [AgentListedSession(id: "agent-1")])]
            connection.holdList = true
        }
        let live = try await openLiveChat(session, box: box, config: Self.config())
        session.refreshSessions(configuration: Self.config())
        try await waitUntil("asked") { live.listRequests.count == 1 }
        session.refreshSessions(configuration: Self.config())
        session.refreshSessions(configuration: Self.config())
        try? await Task.sleep(nanoseconds: 50_000_000)
        XCTAssertEqual(live.listRequests.count, 1)
        live.releaseList()
        try await waitUntil("answer shown") { session.sessions.map(\.id) == ["agent-1"] }
    }

    func testAnAnswerForAnotherFolderIsDropped() async throws {
        let rig = ComposerRig()
        rig.sessions = transcriptRows
        let box = HistoryMockBox()
        let session = makeSession(rig: rig, box: box) { connection in
            connection.pages = [nil: AgentSessionPage(sessions: [AgentListedSession(id: "stale")])]
            connection.holdList = true
        }
        let live = try await openLiveChat(session, box: box, config: Self.config("/one"))
        session.refreshSessions(configuration: Self.config("/one"))
        try await waitUntil("asked") { live.listRequests.count == 1 }
        session.refreshSessions(configuration: Self.config("/two"))
        live.releaseList()
        try? await Task.sleep(nanoseconds: 50_000_000)
        XCTAssertEqual(session.sessions, transcriptRows)
    }

    func testSessionInfoFromTheOpenChatUpdatesItsRow() async throws {
        let rig = ComposerRig()
        rig.sessions = transcriptRows
        let box = HistoryMockBox()
        let session = makeSession(rig: rig, box: box) { $0.capabilities.listSessions = false }
        let config = Self.config()
        session.refreshSessions(configuration: config)
        session.resume(transcriptRows[1], configuration: config)
        session.send("Continue", configuration: config, agentPath: "/fake/agy")
        try await waitUntil("prompt sent") { box.items.first?.promptCount == 1 }

        box.items[0].emit(.sessionInfo(title: "Live title from agy", updatedAt: "2026-11-24T11:00:00Z"))
        try await waitUntil("row retitled") {
            session.sessions.first(where: { $0.id == "t-1" })?.title == "Live title from agy"
        }
        XCTAssertEqual(session.sessions.first(where: { $0.id == "t-1" })?.modified,
                       AgentSessionHistory.parseDate("2026-11-24T11:00:00Z"))
        XCTAssertEqual(session.sessions.first(where: { $0.id == "t-2" })?.title, "From transcript two")
        box.items[0].finish()
    }
}

/// A lister that answers from a table of pages (for `fetchAll`).
@MainActor
private final class FakeSessionLister: AgentSessionListing {
    let pages: [String?: AgentSessionPage]
    var requests: [(cwd: String?, cursor: String?)] = []

    init(pages: [String?: AgentSessionPage]) {
        self.pages = pages
    }

    func listSessionPage(cwd: String?, cursor: String?) async throws -> AgentSessionPage {
        requests.append((cwd, cursor))
        return pages[cursor] ?? AgentSessionPage()
    }
}

private final class HistoryCounter: @unchecked Sendable {
    private let lock = NSLock()
    private var count = 0
    var value: Int { lock.withLock { count } }
    func increment() { lock.withLock { count += 1 } }
}

@MainActor
private final class HistoryMockBox {
    var items: [HistoryMockConnection] = []
}

/// A chat's live connection that can also answer `session/list`.
@MainActor
private final class HistoryMockConnection: PersistentAgentConnection, AgentSessionListing {
    var capabilities = AgentCapabilities(resumeSession: true, listSessions: true)
    let events: AsyncStream<AgentEvent>
    private let continuation: AsyncStream<AgentEvent>.Continuation
    private var promptContinuation: CheckedContinuation<AgentStopReason, any Error>?
    private(set) var promptCount = 0
    private var stopped = false
    var isConnected: Bool { !stopped }

    var pages: [String?: AgentSessionPage] = [:]
    var listError: (any Error)?
    var holdList = false
    private var heldList: CheckedContinuation<Void, Never>?
    private(set) var listRequests: [(cwd: String?, cursor: String?)] = []

    init() {
        var captured: AsyncStream<AgentEvent>.Continuation!
        self.events = AsyncStream { captured = $0 }
        self.continuation = captured
    }

    func start(_ request: AgentSessionRequest) async throws -> String { request.resumeSessionID ?? "new-1" }
    func syncPlanMode(_ planSwitch: Bool) async throws {}
    func syncMode(approvalMode: VitruvianCodeApprovalMode, planSwitch: Bool) async throws {}
    func prompt(_ blocks: [PromptBlock]) async throws -> AgentStopReason {
        promptCount += 1
        return try await withCheckedThrowingContinuation { promptContinuation = $0 }
    }
    func cancel() async {}
    func answer(_ requestID: String, _ choice: AgentAnswer) async throws {}
    func setConfigOption(_ id: String, _ value: AgentConfigValue) async throws -> [AgentConfigOption] { [] }
    func stop() async {
        stopped = true
        continuation.finish()
    }
    func emit(_ event: AgentEvent) { continuation.yield(event) }
    func finish() {
        promptContinuation?.resume(returning: .endTurn)
        promptContinuation = nil
    }

    func listSessionPage(cwd: String?, cursor: String?) async throws -> AgentSessionPage {
        listRequests.append((cwd, cursor))
        if holdList { await withCheckedContinuation { heldList = $0 } }
        if let listError { throw listError }
        return pages[cursor] ?? AgentSessionPage()
    }

    func releaseList() {
        heldList?.resume()
        heldList = nil
    }
}
