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

    // MARK: - The ACP client

    /// agy 1.5.16's real exchange (ids and titles replaced): `session/list` needs
    /// sign-in first, the list comes back with folders, titles and times, and no
    /// session is opened to get it.
    func testAgyListsItsSessionsWithoutOpeningOneAndSignsInWhenAsked() async throws {
        let agent = ScriptedACPAgent()
        let connection = AntigravityACPConnection(
            launchSpec: Self.agentSpec,
            modeProvider: { (.standard, false) },
            processFactory: agent.makeProcessFactory()
        )
        let steps = ACPFixtureLoader.loadSteps(named: "session-list-agy.ndjson")
        let driver = Task { try await agent.playSteps(steps) }

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
        XCTAssertTrue(connection.capabilities.listSessions)

        let methods = await agent.allClientMessages().compactMap { $0.objectValue?["method"]?.stringValue }
        XCTAssertEqual(methods, ["initialize", "session/list", "authenticate", "session/list"])
        let listParams = try await agent.clientMessage(at: 1).objectValue?["params"]?.objectValue
        XCTAssertEqual(listParams?["cwd"]?.stringValue, "/workspace/app")
        XCTAssertNil(listParams?["cursor"])
        let authParams = try await agent.clientMessage(at: 2).objectValue?["params"]?.objectValue
        XCTAssertEqual(authParams?["methodId"]?.stringValue, AntigravityACPSupport.authMethodID)
        await connection.stop()
    }

    func testCursorIsSentAndNextCursorReturned() async throws {
        let agent = ScriptedACPAgent()
        let connection = ACPConnection(launchSpec: Self.agentSpec, processFactory: agent.makeProcessFactory())
        let driver = Task {
            try await agent.playSteps([
                .expectClientRequest(method: "initialize"),
                .agentSend(Self.initializeResult(list: true)),
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
        let page = try await withACPTestTimeout(seconds: 3.0) {
            try await connection.listSessionPage(cwd: nil, cursor: "page-2")
        }
        try await withACPTestTimeout(seconds: 3.0) { try await driver.value }
        // The entry without an id is dropped, not the page.
        XCTAssertEqual(page, AgentSessionPage(sessions: [AgentListedSession(id: "s-2", cwd: "/w")],
                                              nextCursor: "page-3"))
        let params = try await agent.clientMessage(at: 1).objectValue?["params"]?.objectValue
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
            ])
        }
        do {
            _ = try await withACPTestTimeout(seconds: 3.0) {
                try await connection.listSessionPage(cwd: "/w", cursor: nil)
            }
            XCTFail("Expected sessionListNotAdvertised")
        } catch ACPConnectionError.sessionListNotAdvertised {
            // expected
        }
        try await withACPTestTimeout(seconds: 3.0) { try await driver.value }
        try? await Task.sleep(nanoseconds: 50_000_000)
        let methods = await agent.allClientMessages().compactMap { $0.objectValue?["method"]?.stringValue }
        XCTAssertEqual(methods, ["initialize"])
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

    private func makeSession(rig: ComposerRig,
                             lister: (@MainActor (AgentConnectionSpec) -> (any AgentSessionListing)?)?,
                             makeConnection: ((AgentConnectionSpec) -> any AgentConnection)? = nil)
        -> VitruvianCodeQuickPromptSession {
        var environment = rig.environment
        if let lister { environment.makeSessionLister = lister }
        if let makeConnection { environment.makeConnection = makeConnection }
        environment.fileExists = { _ in true }
        environment.isExecutable = { _ in true }
        let session = VitruvianCodeQuickPromptSession(environment: environment, host: rig.host)
        session.takeCheckpoint = { _ in nil }
        return session
    }

    private func waitUntil(_ description: String, condition: @escaping @MainActor () -> Bool) async throws {
        try await withACPTestTimeout(seconds: 4.0, description: description) { @MainActor in
            while !condition() { try? await Task.sleep(nanoseconds: 5_000_000) }
        }
    }

    func testListComesFromTheAgentWhenAdvertisedAndAReopenedChatKeepsItsFolder() async throws {
        let rig = ComposerRig()
        rig.sessions = transcriptRows
        let lister = FakeSessionLister(pages: [nil: AgentSessionPage(sessions: [
            AgentListedSession(id: "t-2", cwd: "/projects/app/web", title: "Agent's own title",
                               updatedAt: "2026-11-24T08:00:00Z"),
            AgentListedSession(id: "a-9", cwd: "/projects/app", title: "Only the agent knows",
                               updatedAt: "2026-11-24T09:00:00Z"),
        ])])
        var specs: [AgentConnectionSpec] = []
        let session = makeSession(rig: rig, lister: { spec in specs.append(spec); return lister })
        let config = VitruvianCodeConfiguration(workingDirectory: "/projects/app", activeProvider: Self.agyACPProvider)

        session.refreshSessions(configuration: config)
        // Today's list shows at once; the agent's replaces it when it answers.
        XCTAssertEqual(session.sessions.map(\.id), ["t-2", "t-1"])
        try await waitUntil("agent list shown") { session.sessions.map(\.id) == ["a-9", "t-2"] }
        XCTAssertEqual(session.sessions.map(\.title), ["Only the agent knows", "Agent's own title"])
        XCTAssertEqual(session.sessions.map(\.workspace), ["/projects/app", "/projects/app/web"])
        XCTAssertEqual(session.sessions[1].preview, "hello")
        XCTAssertEqual(lister.requests.map(\.cwd), ["/projects/app"])
        XCTAssertEqual(specs.first?.provider.id, Self.agyACPProvider.id)
        // A connection started only for the list is stopped after it.
        XCTAssertEqual(lister.stopCount, 1)

        // The listed folder feeds the reopened chat's folder.
        session.resume(session.sessions[1], configuration: config)
        XCTAssertEqual(session.workingDirectory(for: config), "/projects/app/web")
        XCTAssertEqual(session.sessionTitle, "Agent's own title")
    }

    func testWithoutAListerTheListIsTodays() {
        let rig = ComposerRig()
        rig.sessions = transcriptRows
        let session = makeSession(rig: rig, lister: nil)
        session.refreshSessions(configuration: VitruvianCodeConfiguration(activeProvider: Self.agyACPProvider))
        XCTAssertEqual(session.sessions, transcriptRows)
    }

    func testAnAgentWithoutTheListFallsBackAndIsNotAskedAgain() async throws {
        let rig = ComposerRig()
        rig.sessions = transcriptRows
        let lister = FakeSessionLister(pages: [:], error: ACPConnectionError.sessionListNotAdvertised)
        var made = 0
        let session = makeSession(rig: rig, lister: { _ in made += 1; return lister })
        let config = VitruvianCodeConfiguration(activeProvider: Self.agyACPProvider)

        session.refreshSessions(configuration: config)
        try await waitUntil("lister stopped") { lister.stopCount == 1 }
        XCTAssertEqual(session.sessions, transcriptRows)
        session.refreshSessions(configuration: config)
        try? await Task.sleep(nanoseconds: 50_000_000)
        XCTAssertEqual(made, 1)
        XCTAssertEqual(session.sessions, transcriptRows)
    }

    func testAFailedListKeepsTodaysListAndAsksAgainNextTime() async throws {
        let rig = ComposerRig()
        rig.sessions = transcriptRows
        let lister = FakeSessionLister(pages: [:], error: ACPTransportError.connectionClosed("agent exited"))
        var made = 0
        let session = makeSession(rig: rig, lister: { _ in made += 1; return lister })
        let config = VitruvianCodeConfiguration(activeProvider: Self.agyACPProvider)

        session.refreshSessions(configuration: config)
        try await waitUntil("first lister stopped") { lister.stopCount == 1 }
        XCTAssertEqual(session.sessions, transcriptRows)
        session.refreshSessions(configuration: config)
        try await waitUntil("second lister stopped") { lister.stopCount == 2 }
        XCTAssertEqual(made, 2)
        XCTAssertEqual(session.sessions, transcriptRows)
    }

    func testALateAnswerForAnOlderRefreshIsDropped() async throws {
        let rig = ComposerRig()
        rig.sessions = transcriptRows
        let slow = FakeSessionLister(pages: [nil: AgentSessionPage(sessions: [AgentListedSession(id: "stale")])])
        slow.hold = true
        let fast = FakeSessionLister(pages: [nil: AgentSessionPage(sessions: [AgentListedSession(id: "fresh")])])
        var listers = [slow, fast]
        let session = makeSession(rig: rig, lister: { _ in listers.removeFirst() })
        let config = VitruvianCodeConfiguration(activeProvider: Self.agyACPProvider)

        session.refreshSessions(configuration: config)
        try await waitUntil("slow asked") { slow.requests.count == 1 }
        session.refreshSessions(configuration: config)
        try await waitUntil("fresh shown") { session.sessions.map(\.id) == ["fresh"] }
        slow.release()
        try await waitUntil("slow stopped") { slow.stopCount == 1 }
        XCTAssertEqual(session.sessions.map(\.id), ["fresh"])
    }

    func testSessionInfoFromTheOpenChatUpdatesItsRow() async throws {
        let rig = ComposerRig()
        rig.sessions = transcriptRows
        let connections = HistoryMockBox()
        let session = makeSession(rig: rig, lister: nil, makeConnection: { spec in
            let connection = HistoryMockConnection()
            connections.items.append(connection)
            return connection
        })
        let config = VitruvianCodeConfiguration(activeProvider: Self.agyACPProvider)
        session.refreshSessions(configuration: config)
        session.resume(transcriptRows[1], configuration: config)
        session.send("Continue", configuration: config, agentPath: "/fake/agy")
        try await waitUntil("prompt sent") { connections.items.first?.promptCount == 1 }

        connections.items[0].emit(.sessionInfo(title: "Live title from agy", updatedAt: "2026-11-24T11:00:00Z"))
        try await waitUntil("row retitled") {
            session.sessions.first(where: { $0.id == "t-1" })?.title == "Live title from agy"
        }
        XCTAssertEqual(session.sessions.first(where: { $0.id == "t-1" })?.modified,
                       AgentSessionHistory.parseDate("2026-11-24T11:00:00Z"))
        XCTAssertEqual(session.sessions.first(where: { $0.id == "t-2" })?.title, "From transcript two")
        connections.items[0].finish()
    }
}

/// A lister that answers from a table of pages, or fails, and counts its stops.
@MainActor
private final class FakeSessionLister: AgentSessionListing {
    let pages: [String?: AgentSessionPage]
    let error: (any Error)?
    var requests: [(cwd: String?, cursor: String?)] = []
    var stopCount = 0
    var hold = false
    private var held: CheckedContinuation<Void, Never>?

    init(pages: [String?: AgentSessionPage], error: (any Error)? = nil) {
        self.pages = pages
        self.error = error
    }

    func listSessionPage(cwd: String?, cursor: String?) async throws -> AgentSessionPage {
        requests.append((cwd, cursor))
        if hold { await withCheckedContinuation { held = $0 } }
        if let error { throw error }
        return pages[cursor] ?? AgentSessionPage()
    }

    func release() {
        held?.resume()
        held = nil
    }

    func stop() async { stopCount += 1 }
}

@MainActor
private final class HistoryMockBox {
    var items: [HistoryMockConnection] = []
}

@MainActor
private final class HistoryMockConnection: PersistentAgentConnection {
    var capabilities = AgentCapabilities(resumeSession: true)
    let events: AsyncStream<AgentEvent>
    private let continuation: AsyncStream<AgentEvent>.Continuation
    private var promptContinuation: CheckedContinuation<AgentStopReason, any Error>?
    private(set) var promptCount = 0
    private var stopped = false
    var isConnected: Bool { !stopped }

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
}
