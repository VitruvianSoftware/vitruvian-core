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

import AppKit
import Foundation
import os
import SwiftUI
@testable import VitruvianCodeCore
@testable import VitruvianCodeUI
import XCTest

@MainActor
final class ApprovalAndQuestionCardTests: XCTestCase {
    private static let agyACPProvider = VitruvianCodeCLIProvider(
        id: VitruvianCodeCLIProvider.antigravity.id,
        name: "Antigravity CLI",
        commandTemplate: VitruvianCodeCLIProvider.antigravity.commandTemplate,
        isBuiltIn: true,
        connection: .acp
    )

    private var scratchSuites: [(UserDefaults, String)] = []

    override func tearDown() {
        for (defaults, domain) in scratchSuites {
            defaults.removePersistentDomain(forName: domain)
        }
        scratchSuites.removeAll()
        super.tearDown()
    }

    // MARK: - Approval Options

    func testDecideApprovalWithOptionIDHandlesAllFourKindsOnceAndTracksSessionAllowed() async throws {
        let options: [AgentPermissionOption] = [
            AgentPermissionOption(id: "opt-allow-once", name: "Allow Once", kind: .allowOnce),
            AgentPermissionOption(id: "opt-allow-always", name: "Always Allow", kind: .allowAlways),
            AgentPermissionOption(id: "opt-reject-once", name: "Reject Once", kind: .rejectOnce),
            AgentPermissionOption(id: "opt-reject-always", name: "Reject Always", kind: .rejectAlways),
        ]
        let expected: [(optionID: String, status: VitruvianCodeApprovalRequest.Status, addsTool: Bool)] = [
            ("opt-allow-once", .approved, false),
            ("opt-allow-always", .sessionAllowed, true),
            ("opt-reject-once", .denied, false),
            ("opt-reject-always", .denied, false),
        ]

        for (idx, item) in expected.enumerated() {
            let connections = LockedCardBox<[CardMockPersistentConnection]>([])
            let env = makeSessionEnvironment(makeConnection: { spec in
                let conn = CardMockPersistentConnection(spec: spec)
                connections.withValue { $0.append(conn) }
                return conn
            })
            let session = VitruvianCodeQuickPromptSession(environment: env, host: CardMockSessionHost())
            session.takeCheckpoint = { _ in nil }
            let config = VitruvianCodeConfiguration(approvalMode: .standard, activeProvider: Self.agyACPProvider)

            session.send("Run \(idx)", configuration: config, agentPath: "/fake/agy")
            try await waitUntil("prompt started \(idx)") { connections.value.first?.promptCalls.count == 1 }
            let conn = connections.value[0]

            let reqID = "perm-\(idx)"
            let toolName = "tool-\(idx)"
            conn.emit(.approval(VitruvianCodeApprovalRequest(
                id: "call-\(idx)",
                toolName: toolName,
                commandOrPath: "cmd \(idx)",
                requestID: reqID,
                options: options
            )))
            try await waitUntil("approval card \(idx)") {
                session.hasPendingApproval && session.messages.contains { $0.approvalRequest?.requestID == reqID }
            }
            let cardMsg = try XCTUnwrap(session.messages.first { $0.approvalRequest?.requestID == reqID })
            session.decideApproval(messageID: cardMsg.id, optionID: item.optionID)
            try await waitUntil("answer sent \(idx)") { conn.answers.count == 1 }

            XCTAssertEqual(conn.answers.count, 1)
            XCTAssertEqual(conn.answers[0].0, reqID)
            XCTAssertEqual(conn.answers[0].1, .option(item.optionID))

            let updated = try XCTUnwrap(session.messages.first { $0.id == cardMsg.id }?.approvalRequest)
            XCTAssertEqual(updated.status, item.status)
            XCTAssertEqual(updated.chosenOptionID, item.optionID)
            XCTAssertFalse(session.hasPendingApproval)
            XCTAssertEqual(session.sessionAllowedTools.contains(toolName), item.addsTool)

            // Second click must do nothing and send nothing.
            let alternateID = options.first(where: { $0.id != item.optionID })!.id
            session.decideApproval(messageID: cardMsg.id, optionID: alternateID)
            try? await Task.sleep(nanoseconds: 25_000_000)
            XCTAssertEqual(conn.answers.count, 1, "second click on decided card must send nothing")
            XCTAssertEqual(
                session.messages.first { $0.id == cardMsg.id }?.approvalRequest?.chosenOptionID,
                item.optionID
            )

            conn.emit(.finished(status: "completed", response: "Done", error: nil, conversationID: "s-\(idx)"))
            conn.finishPrompt(with: .endTurn)
            try await waitUntil("finished \(idx)") { !session.isRunning }
            await session.stopAll()
        }
    }

    func testEmptyOptionsApprovalStillUsesLegacyMapping() {
        XCTAssertEqual(VitruvianCodeQuickPromptSession.approvalAnswer(for: [], decision: .approved), .option("allow"))
        XCTAssertEqual(VitruvianCodeQuickPromptSession.approvalAnswer(for: [], decision: .sessionAllowed), .option("allow_always"))
        XCTAssertEqual(VitruvianCodeQuickPromptSession.approvalAnswer(for: [], decision: .denied), .cancelled)
        XCTAssertEqual(VitruvianCodeQuickPromptSession.approvalAnswer(for: [], decision: .pending), .cancelled)
    }

    func testApprovalCardPartitioningOrdersRejectOnceBeforeAllowOnceAndMovesExtrasToMore() {
        let strings = VitruvianCodeChatStrings()
        let options: [AgentPermissionOption] = [
            AgentPermissionOption(id: "allow-once-1", name: "Yes", kind: .allowOnce),
            AgentPermissionOption(id: "allow-always-1", name: "Always", kind: .allowAlways),
            AgentPermissionOption(id: "reject-once-1", name: "No", kind: .rejectOnce),
            AgentPermissionOption(id: "reject-always-1", name: "Never", kind: .rejectAlways),
        ]
        let partitioned = VitruvianCodeApprovalCardView.partitionOptions(options)
        XCTAssertEqual(partitioned.primary.map(\.id), ["reject-once-1", "allow-once-1"])
        XCTAssertEqual(partitioned.more.map(\.id), ["allow-always-1", "reject-always-1"])

        let blankAllow = AgentPermissionOption(id: "a", name: "   ", kind: .allowOnce)
        let blankDeny = AgentPermissionOption(id: "r", name: "", kind: .rejectOnce)
        let blankAlways = AgentPermissionOption(id: "s", name: "\n", kind: .allowAlways)
        XCTAssertEqual(VitruvianCodeApprovalCardView.optionLabel(blankAllow, strings: strings), strings.allow)
        XCTAssertEqual(VitruvianCodeApprovalCardView.optionLabel(blankDeny, strings: strings), strings.deny)
        XCTAssertEqual(VitruvianCodeApprovalCardView.optionLabel(blankAlways, strings: strings), strings.allowForSession)
    }

    // MARK: - Question Lifecycle Through Session

    func testQuestionWaitsWithoutAutoAnsweringAndSupportsAnswerSkipAndURLModes() async throws {
        let connections = LockedCardBox<[CardMockPersistentConnection]>([])
        let env = makeSessionEnvironment(makeConnection: { spec in
            let conn = CardMockPersistentConnection(spec: spec)
            connections.withValue { $0.append(conn) }
            return conn
        })
        let host = CardMockSessionHost()
        let session = VitruvianCodeQuickPromptSession(environment: env, host: host)
        session.takeCheckpoint = { _ in nil }
        let config = VitruvianCodeConfiguration(approvalMode: .standard, activeProvider: Self.agyACPProvider)

        session.send("Ask questions", configuration: config, agentPath: "/fake/agy")
        try await waitUntil("prompt started") { connections.value.first?.promptCalls.count == 1 }
        let conn = connections.value[0]

        // 1. Form question stays pending and sends NO answer initially.
        let formQuestion = AgentQuestion(
            requestID: "q-form-1",
            title: "Target",
            message: "Choose branch",
            fields: [AgentQuestion.Field(id: "branch", type: .choice, label: "Branch", required: true, options: [
                AgentQuestion.Option(value: "main", label: "Main"),
            ])]
        )
        conn.emit(.question(formQuestion))
        try await waitUntil("form question pending") {
            session.hasPendingApproval && session.messages.contains { $0.question?.requestID == "q-form-1" }
        }
        try? await Task.sleep(nanoseconds: 25_000_000)
        XCTAssertTrue(conn.answers.isEmpty, "question must wait for user input")
        XCTAssertEqual(host.approvals.count, 1)

        let q1Msg = try XCTUnwrap(session.messages.first { $0.question?.requestID == "q-form-1" })
        XCTAssertEqual(q1Msg.questionStatus, .pending)
        XCTAssertTrue(VitruvianCodeTimeline.isShown(q1Msg))

        session.answerQuestion(messageID: q1Msg.id, answers: ["branch": "main"])
        try await waitUntil("form answer sent") { conn.answers.count == 1 }
        XCTAssertEqual(conn.answers[0].0, "q-form-1")
        XCTAssertEqual(conn.answers[0].1, .form(["branch": "main"]))
        XCTAssertEqual(session.messages.first { $0.id == q1Msg.id }?.questionStatus, .answered(["branch": "main"]))
        XCTAssertFalse(session.hasPendingApproval)

        // Second answer sends nothing.
        session.answerQuestion(messageID: q1Msg.id, answers: ["branch": "other"])
        session.skipQuestion(messageID: q1Msg.id)
        try? await Task.sleep(nanoseconds: 20_000_000)
        XCTAssertEqual(conn.answers.count, 1)

        // 2. Skip sends `.cancelled` once.
        conn.emit(.question(AgentQuestion(requestID: "q-skip-1", title: "Skip me", message: "Optional")))
        try await waitUntil("skip question pending") {
            session.hasPendingApproval && session.messages.contains { $0.question?.requestID == "q-skip-1" }
        }
        let qSkipMsg = try XCTUnwrap(session.messages.first { $0.question?.requestID == "q-skip-1" })
        session.skipQuestion(messageID: qSkipMsg.id)
        try await waitUntil("skip sent") { conn.answers.count == 2 }
        XCTAssertEqual(conn.answers[1].0, "q-skip-1")
        XCTAssertEqual(conn.answers[1].1, .cancelled)
        XCTAssertEqual(session.messages.first { $0.id == qSkipMsg.id }?.questionStatus, .skipped)
        XCTAssertFalse(session.hasPendingApproval)

        session.skipQuestion(messageID: qSkipMsg.id)
        try? await Task.sleep(nanoseconds: 20_000_000)
        XCTAssertEqual(conn.answers.count, 2)

        // 3. URL accept & decline send `.option("accept")` and `.option("decline")`.
        conn.emit(.question(AgentQuestion(
            requestID: "q-url-accept",
            title: "Sign in",
            message: "Open browser to authenticate",
            url: "https://auth.example.com/login"
        )))
        try await waitUntil("url accept pending") {
            session.messages.contains { $0.question?.requestID == "q-url-accept" && $0.questionStatus == .pending }
        }
        let qUrlAccept = try XCTUnwrap(session.messages.first { $0.question?.requestID == "q-url-accept" })
        session.answerQuestion(messageID: qUrlAccept.id, answers: [AgentQuestionForm.urlDecisionKey: "accept"])
        try await waitUntil("url accept sent") { conn.answers.count == 3 }
        XCTAssertEqual(conn.answers[2].0, "q-url-accept")
        XCTAssertEqual(conn.answers[2].1, .option("accept"))

        conn.emit(.question(AgentQuestion(
            requestID: "q-url-decline",
            title: "Sign in",
            message: "Open browser",
            url: "https://auth.example.com/login"
        )))
        try await waitUntil("url decline pending") {
            session.messages.contains { $0.question?.requestID == "q-url-decline" && $0.questionStatus == .pending }
        }
        let qUrlDecline = try XCTUnwrap(session.messages.first { $0.question?.requestID == "q-url-decline" })
        session.answerQuestion(messageID: qUrlDecline.id, answers: [AgentQuestionForm.urlDecisionKey: "decline"])
        try await waitUntil("url decline sent") { conn.answers.count == 4 }
        XCTAssertEqual(conn.answers[3].0, "q-url-decline")
        XCTAssertEqual(conn.answers[3].1, .option("decline"))

        conn.emit(.finished(status: "completed", response: "All done", error: nil, conversationID: "sess-q-1"))
        conn.finishPrompt(with: .endTurn)
        try await waitUntil("done") { !session.isRunning }
        await session.stopAll()
    }

    func testPendingQuestionsExpireOnTurnEndStopConnectionAndNewChatAndIgnoreLateAnswers() async throws {
        // Case A: `.finished` expires pending question, late answer sends nothing.
        do {
            let connections = LockedCardBox<[CardMockPersistentConnection]>([])
            let env = makeSessionEnvironment(makeConnection: { spec in
                let conn = CardMockPersistentConnection(spec: spec)
                connections.withValue { $0.append(conn) }
                return conn
            })
            let session = VitruvianCodeQuickPromptSession(environment: env, host: CardMockSessionHost())
            session.takeCheckpoint = { _ in nil }
            let config = VitruvianCodeConfiguration(approvalMode: .standard, activeProvider: Self.agyACPProvider)

            session.send("Turn end expiry", configuration: config, agentPath: "/fake/agy")
            try await waitUntil("prompt A") { connections.value.first?.promptCalls.count == 1 }
            let conn = connections.value[0]
            conn.emit(.question(AgentQuestion(requestID: "q-exp-finish", message: "Still waiting?")))
            try await waitUntil("q pending A") { session.hasPendingApproval }
            let qMsg = try XCTUnwrap(session.messages.first { $0.question?.requestID == "q-exp-finish" })

            conn.emit(.finished(status: "completed", response: "Finished", error: nil, conversationID: "s-a"))
            conn.finishPrompt(with: .endTurn)
            try await waitUntil("finished A") { !session.isRunning }

            XCTAssertFalse(session.hasPendingApproval)
            XCTAssertEqual(session.messages.first { $0.id == qMsg.id }?.questionStatus, .expired)
            session.awaitingAnswers.insert("q-exp-finish")
            session.answerQuestion(messageID: qMsg.id, answers: ["k": "v"])
            session.awaitingAnswers.insert("q-exp-finish")
            session.skipQuestion(messageID: qMsg.id)
            try? await Task.sleep(nanoseconds: 25_000_000)
            XCTAssertTrue(
                conn.answers.isEmpty,
                "answering or skipping an expired question must send nothing even when awaitingAnswers holds its requestID"
            )
            XCTAssertEqual(session.messages.first { $0.id == qMsg.id }?.questionStatus, .expired)
            await session.stopAll()
        }

        // Case B: `stopConnection()` expires pending question and sends nothing.
        do {
            let connections = LockedCardBox<[CardMockPersistentConnection]>([])
            let env = makeSessionEnvironment(makeConnection: { spec in
                let conn = CardMockPersistentConnection(spec: spec)
                connections.withValue { $0.append(conn) }
                return conn
            })
            let session = VitruvianCodeQuickPromptSession(environment: env, host: CardMockSessionHost())
            session.takeCheckpoint = { _ in nil }
            let config = VitruvianCodeConfiguration(approvalMode: .standard, activeProvider: Self.agyACPProvider)

            session.send("Stop expiry", configuration: config, agentPath: "/fake/agy")
            try await waitUntil("prompt B") { connections.value.first?.promptCalls.count == 1 }
            let conn = connections.value[0]
            conn.emit(.question(AgentQuestion(requestID: "q-exp-stop", message: "Question before stop")))
            try await waitUntil("q pending B") { session.hasPendingApproval }
            let qMsg = try XCTUnwrap(session.messages.first { $0.question?.requestID == "q-exp-stop" })

            session.stopConnection()
            XCTAssertFalse(session.hasPendingApproval)
            XCTAssertEqual(session.messages.first { $0.id == qMsg.id }?.questionStatus, .expired)
            session.answerQuestion(messageID: qMsg.id, answers: ["k": "v"])
            try? await Task.sleep(nanoseconds: 20_000_000)
            XCTAssertTrue(conn.answers.isEmpty)
            await session.stopAll()
        }

        // Case C: `newChat()` expires/clears pending state and sends nothing.
        do {
            let connections = LockedCardBox<[CardMockPersistentConnection]>([])
            let env = makeSessionEnvironment(makeConnection: { spec in
                let conn = CardMockPersistentConnection(spec: spec)
                connections.withValue { $0.append(conn) }
                return conn
            })
            let session = VitruvianCodeQuickPromptSession(environment: env, host: CardMockSessionHost())
            session.takeCheckpoint = { _ in nil }
            let config = VitruvianCodeConfiguration(approvalMode: .standard, activeProvider: Self.agyACPProvider)

            session.send("New chat expiry", configuration: config, agentPath: "/fake/agy")
            try await waitUntil("prompt C") { connections.value.first?.promptCalls.count == 1 }
            let conn = connections.value[0]
            conn.emit(.question(AgentQuestion(requestID: "q-exp-new", message: "Question before newChat")))
            try await waitUntil("q pending C") { session.hasPendingApproval }

            session.newChat()
            XCTAssertFalse(session.hasPendingApproval)
            XCTAssertTrue(session.messages.isEmpty)
            try? await Task.sleep(nanoseconds: 20_000_000)
            XCTAssertTrue(conn.answers.isEmpty)
            await session.stopAll()
        }
    }

    func testTurnCompletionEventExpiresPendingQuestionWhileConnectionStaysAlive() async throws {
        let connections = LockedCardBox<[CardMockPersistentConnection]>([])
        let env = makeSessionEnvironment(makeConnection: { spec in
            let conn = CardMockPersistentConnection(spec: spec)
            connections.withValue { $0.append(conn) }
            return conn
        })
        let session = VitruvianCodeQuickPromptSession(environment: env, host: CardMockSessionHost())
        session.takeCheckpoint = { _ in nil }
        let config = VitruvianCodeConfiguration(approvalMode: .standard, activeProvider: Self.agyACPProvider)

        session.send("Turn completion event while alive", configuration: config, agentPath: "/fake/agy")
        try await waitUntil("prompt started") { connections.value.first?.promptCalls.count == 1 }
        let conn = connections.value[0]

        conn.emit(.question(AgentQuestion(requestID: "q-exp-turn-event", message: "Still waiting?")))
        try await waitUntil("question pending") {
            session.hasPendingApproval && session.messages.contains { $0.question?.requestID == "q-exp-turn-event" }
        }
        let qMsg = try XCTUnwrap(session.messages.first { $0.question?.requestID == "q-exp-turn-event" })

        conn.emit(.finished(status: "completed", response: "Turn finished", error: nil, conversationID: "s-live"))
        try await waitUntil("finished event processed") {
            session.messages.contains { $0.stopReason == "completed" }
        }

        XCTAssertTrue(session.isRunning, "agentDidExit must not have run while prompt RPC stays open")
        XCTAssertTrue(conn.isConnected)
        XCTAssertFalse(session.hasPendingApproval)
        XCTAssertEqual(session.messages.first { $0.id == qMsg.id }?.questionStatus, .expired)

        session.answerQuestion(messageID: qMsg.id, answers: ["k": "v"])
        session.skipQuestion(messageID: qMsg.id)
        try? await Task.sleep(nanoseconds: 25_000_000)
        XCTAssertTrue(conn.answers.isEmpty)
        XCTAssertEqual(session.messages.first { $0.id == qMsg.id }?.questionStatus, .expired)

        conn.finishPrompt(with: .endTurn)
        try await waitUntil("turn exited") { !session.isRunning }
        await session.stopAll()
    }

    // MARK: - Form Pure Logic (`AgentQuestionForm`)

    func testFormValidationMultiChoiceEncodingNumbersShortcutsAndSummaryLabels() {
        let question = AgentQuestion(
            requestID: "form-logic-1",
            title: "Deploy",
            message: "Configure release",
            fields: [
                AgentQuestion.Field(
                    id: "env",
                    type: .choice,
                    label: "Environment",
                    required: true,
                    options: [
                        AgentQuestion.Option(value: "env_dev", label: "Development", description: "Local sandbox"),
                        AgentQuestion.Option(value: "env_prod", label: "Production", description: "Live cluster"),
                    ]
                ),
                AgentQuestion.Field(
                    id: "regions",
                    type: .multiChoice,
                    label: "Regions",
                    required: true,
                    options: [
                        AgentQuestion.Option(value: "us_east", label: "US East"),
                        AgentQuestion.Option(value: "eu_west", label: "EU West"),
                    ]
                ),
                AgentQuestion.Field(id: "dry_run", type: .boolean, label: "Dry Run", required: false),
                AgentQuestion.Field(id: "replicas", type: .integer, label: "Replicas", required: true),
                AgentQuestion.Field(id: "ratio", type: .number, label: "Rollout Ratio", required: false),
                AgentQuestion.Field(id: "note", type: .text, label: "Note", required: false),
            ]
        )

        var form = AgentQuestionForm(question: question)
        XCTAssertFalse(form.canSubmit)
        XCTAssertNil(form.buildAnswers())
        XCTAssertEqual(form.shortcutFieldID, "env")

        // Digit shortcut picks from first choice/multi_choice field.
        XCTAssertTrue(form.applyDigitShortcut(2))
        XCTAssertEqual(form.selectedChoice(for: "env"), "env_prod")
        XCTAssertFalse(form.applyDigitShortcut(9), "out-of-range digit does nothing")

        // Multi-choice keeps field option order and encodes as JSON array.
        form.toggleMultiChoice(fieldID: "regions", value: "eu_west")
        form.toggleMultiChoice(fieldID: "regions", value: "us_east")
        XCTAssertEqual(form.selectedMultiChoice(for: "regions"), ["us_east", "eu_west"])
        XCTAssertEqual(AgentQuestionForm.encodeMultiChoice(["us_east", "eu_west"]), #"["us_east","eu_west"]"#)

        // Integer validation rejects decimals and garbage, outlines red, disables send.
        form.setText(fieldID: "replicas", value: "2.5")
        XCTAssertTrue(form.hasParseError(fieldID: "replicas"))
        XCTAssertFalse(form.canSubmit)

        form.setText(fieldID: "replicas", value: "abc")
        XCTAssertTrue(form.hasParseError(fieldID: "replicas"))
        XCTAssertFalse(form.canSubmit)

        form.setText(fieldID: "replicas", value: "4")
        XCTAssertFalse(form.hasParseError(fieldID: "replicas"))
        XCTAssertTrue(form.canSubmit)

        // Optional number field still blocks send when non-empty & unparseable.
        form.setText(fieldID: "ratio", value: "NaN")
        XCTAssertTrue(form.hasParseError(fieldID: "ratio"))
        XCTAssertFalse(form.canSubmit)

        form.setText(fieldID: "ratio", value: "0.75")
        XCTAssertFalse(form.hasParseError(fieldID: "ratio"))
        form.setBoolean(fieldID: "dry_run", value: true)

        let answers = form.buildAnswers()
        XCTAssertEqual(
            answers,
            [
                "env": "env_prod",
                "regions": #"["us_east","eu_west"]"#,
                "dry_run": "true",
                "replicas": "4",
                "ratio": "0.75",
            ]
        )

        // Summary labels map raw IDs to human labels.
        let strings = VitruvianCodeChatStrings()
        let summary = AgentQuestionForm.summaryRows(for: question, answers: answers ?? [:], strings: strings)
        XCTAssertEqual(
            summary,
            [
                AgentQuestionForm.SummaryRow(label: "Environment", value: "Production"),
                AgentQuestionForm.SummaryRow(label: "Regions", value: "US East, EU West"),
                AgentQuestionForm.SummaryRow(label: "Dry Run", value: "Yes"),
                AgentQuestionForm.SummaryRow(label: "Replicas", value: "4"),
                AgentQuestionForm.SummaryRow(label: "Rollout Ratio", value: "0.75"),
            ]
        )
    }

    func testURLFormHostExtractionSummaryAndNoUnwantedOpen() {
        let strings = VitruvianCodeChatStrings()
        let urlQ = AgentQuestion(
            requestID: "url-q",
            title: "Authenticate",
            message: "Sign in at provider",
            url: "https://accounts.example.com/oauth/authorize?client=1"
        )
        XCTAssertEqual(AgentQuestionForm.urlHost(for: urlQ.url!), "accounts.example.com")
        XCTAssertEqual(
            AgentQuestionForm.summaryRows(for: urlQ, answers: [AgentQuestionForm.urlDecisionKey: "accept"], strings: strings),
            [AgentQuestionForm.SummaryRow(label: nil, value: strings.openLink)]
        )
        XCTAssertEqual(
            AgentQuestionForm.summaryRows(for: urlQ, answers: [AgentQuestionForm.urlDecisionKey: "decline"], strings: strings),
            [AgentQuestionForm.SummaryRow(label: nil, value: strings.declineLink)]
        )

        var didAppear = false
        var openedURLs: [URL] = []
        let card = AgentFormCard(
            question: urlQ,
            status: .pending,
            strings: strings,
            openURL: { openedURLs.append($0) }
        )
        let size = CGSize(width: 480, height: 220)
        let host = NSHostingView(
            rootView: card
                .frame(width: size.width, height: size.height)
                .onAppear { didAppear = true }
        )
        host.frame = CGRect(origin: .zero, size: size)
        let window = NSWindow(
            contentRect: CGRect(x: -10_000, y: -10_000, width: size.width, height: size.height),
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        window.isReleasedWhenClosed = false
        defer {
            window.contentView = nil
            window.close()
        }
        window.contentView = host
        host.layoutSubtreeIfNeeded()
        RunLoop.main.run(until: Date().addingTimeInterval(0.1))
        host.layoutSubtreeIfNeeded()
        XCTAssertTrue(didAppear, "hosted URL form card must mount and trigger onAppear")
        XCTAssertTrue(openedURLs.isEmpty, "rendering a pending URL question card must never open the URL automatically")
    }

    func testEveryChatStringsFieldHasNonEmptyDefault() {
        let fields = Mirror(reflecting: VitruvianCodeChatStrings()).children
        XCTAssertFalse(fields.isEmpty)
        for field in fields {
            guard let value = field.value as? String else {
                XCTFail("\(field.label ?? "?") is not String")
                continue
            }
            XCTAssertFalse(value.isEmpty, "\(field.label ?? "?") must have a non-empty English default")
        }
    }

    // MARK: - Round-1 QA Fixes

    func testIntegerOverflowBoundsRejectedInFormAndElicitation() throws {
        let schema: ACPJSONValue = .object([
            "type": .string("object"),
            "required": .array([.string("count")]),
            "properties": .object([
                "count": .object([
                    "type": .string("integer"),
                    "title": .string("Count"),
                ]),
            ]),
        ])
        let params = ACPElicitationCreateParams(
            sessionId: "s-int",
            mode: "form",
            title: "Integer bounds",
            message: "Enter count",
            requestedSchema: schema
        )
        let elicitation = try XCTUnwrap(ACPElicitationForm.parse(requestID: "req-int", params: params))

        for bad in ["9223372036854775808", "-9223372036854775809"] {
            XCTAssertFalse(AgentQuestionForm.isValidNumber(bad, integer: true), "\(bad) must be rejected by form")
            var cardForm = AgentQuestionForm(question: elicitation.question)
            cardForm.setText(fieldID: "count", value: bad)
            XCTAssertTrue(cardForm.hasParseError(fieldID: "count"), "\(bad) must flag parse error")
            XCTAssertNil(cardForm.buildAnswers(), "\(bad) must fail buildAnswers")
            XCTAssertEqual(
                elicitation.resolve(answer: .form(["count": bad])).action,
                .decline,
                "\(bad) must be declined by ACPElicitationForm"
            )
        }

        let safeValues: [(String, Int)] = [
            ("9007199254740991", 9_007_199_254_740_991),
            ("-9007199254740991", -9_007_199_254_740_991),
            ("-9223372036854775808", Int.min),
            ("42", 42),
        ]
        for (raw, expected) in safeValues {
            XCTAssertTrue(AgentQuestionForm.isValidNumber(raw, integer: true), "\(raw) must be accepted by form")
            var cardForm = AgentQuestionForm(question: elicitation.question)
            cardForm.setText(fieldID: "count", value: raw)
            XCTAssertFalse(cardForm.hasParseError(fieldID: "count"))
            let built = try XCTUnwrap(cardForm.buildAnswers())
            let resolved = elicitation.resolve(answer: .form(built))
            XCTAssertEqual(resolved.action, .accept, "\(raw) must be accepted by ACPElicitationForm")
            XCTAssertEqual(resolved.content?["count"], .int(expected))
        }
    }

    func testMultiChoiceMinAndMaxItemsEnforcedEndToEndAndLegacyFieldDecodes() throws {
        func makeMultiChoiceSchema(required: Bool) -> ACPJSONValue {
            .object([
                "type": .string("object"),
                "required": .array(required ? [.string("items")] : []),
                "properties": .object([
                    "items": .object([
                        "type": .string("array"),
                        "title": .string("Items"),
                        "minItems": .int(2),
                        "maxItems": .int(3),
                        "items": .object([
                            "type": .string("string"),
                            "enum": .array([.string("a"), .string("b"), .string("c"), .string("d")]),
                        ]),
                    ]),
                ]),
            ])
        }

        let requiredParams = ACPElicitationCreateParams(
            sessionId: "s-mc",
            mode: "form",
            title: "Pick items",
            message: "Choose 2 to 3 items",
            requestedSchema: makeMultiChoiceSchema(required: true)
        )
        let elicitation = try XCTUnwrap(ACPElicitationForm.parse(requestID: "req-mc", params: requiredParams))
        XCTAssertEqual(elicitation.question.fields.first?.minItems, 2)
        XCTAssertEqual(elicitation.question.fields.first?.maxItems, 3)

        let allOptions = ["a", "b", "c", "d"]
        for count in 0 ... 4 {
            var cardForm = AgentQuestionForm(question: elicitation.question)
            let chosen = Array(allOptions.prefix(count))
            for value in chosen {
                cardForm.toggleMultiChoice(fieldID: "items", value: value)
            }
            let rawAnswer = ["items": AgentQuestionForm.encodeMultiChoice(chosen)]
            if (2 ... 3).contains(count) {
                XCTAssertTrue(cardForm.canSubmit, "count \(count) within 2...3 must enable Send")
                let built = try XCTUnwrap(cardForm.buildAnswers())
                let resolved = elicitation.resolve(answer: .form(built))
                XCTAssertEqual(resolved.action, .accept, "count \(count) must be accepted by resolve")
                XCTAssertEqual(resolved.content?["items"], .array(chosen.map(ACPJSONValue.string)))
            } else {
                XCTAssertFalse(cardForm.canSubmit, "count \(count) outside 2...3 must disable Send")
                XCTAssertNil(cardForm.buildAnswers(), "count \(count) outside 2...3 must return nil from buildAnswers")
                XCTAssertEqual(
                    elicitation.resolve(answer: .form(rawAnswer)).action,
                    .decline,
                    "count \(count) outside 2...3 must be declined by resolve"
                )
            }
        }

        // Optional multi_choice enforces minItems/maxItems when any items are chosen.
        let optionalParams = ACPElicitationCreateParams(
            sessionId: "s-mc-opt",
            mode: "form",
            message: "Optionally pick 2 to 3",
            requestedSchema: makeMultiChoiceSchema(required: false)
        )
        let optionalElicitation = try XCTUnwrap(ACPElicitationForm.parse(requestID: "req-mc-opt", params: optionalParams))
        for count in [1, 4] {
            var cardForm = AgentQuestionForm(question: optionalElicitation.question)
            let chosen = Array(allOptions.prefix(count))
            for value in chosen {
                cardForm.toggleMultiChoice(fieldID: "items", value: value)
            }
            XCTAssertFalse(cardForm.canSubmit)
            XCTAssertNil(cardForm.buildAnswers())
            XCTAssertEqual(
                optionalElicitation.resolve(answer: .form(["items": AgentQuestionForm.encodeMultiChoice(chosen)])).action,
                .decline
            )
        }
        let emptyOptionalForm = AgentQuestionForm(question: optionalElicitation.question)
        XCTAssertTrue(emptyOptionalForm.canSubmit)
        XCTAssertEqual(emptyOptionalForm.buildAnswers(), [:])
        XCTAssertEqual(optionalElicitation.resolve(answer: .form([:])).action, .accept)

        // Legacy serialized field data without minItems/maxItems still decodes cleanly.
        let legacyJSON = #"{"id":"tags","type":"multi_choice","label":"Tags","required":true,"options":[{"value":"x","label":"X"}]}"#
        let decodedLegacy = try JSONDecoder().decode(AgentQuestion.Field.self, from: Data(legacyJSON.utf8))
        XCTAssertNil(decodedLegacy.minItems)
        XCTAssertNil(decodedLegacy.maxItems)
        XCTAssertEqual(decodedLegacy.id, "tags")
    }

    func testStopExpiresPendingQuestionsAndIgnoresLateAnswerOrSkip() async throws {
        let connections = LockedCardBox<[CardMockPersistentConnection]>([])
        let env = makeSessionEnvironment(makeConnection: { spec in
            let conn = CardMockPersistentConnection(spec: spec)
            connections.withValue { $0.append(conn) }
            return conn
        })
        let session = VitruvianCodeQuickPromptSession(environment: env, host: CardMockSessionHost())
        session.takeCheckpoint = { _ in nil }
        let config = VitruvianCodeConfiguration(approvalMode: .standard, activeProvider: Self.agyACPProvider)

        session.send("Ask before stop", configuration: config, agentPath: "/fake/agy")
        try await waitUntil("prompt started for stop test") { connections.value.first?.promptCalls.count == 1 }
        let conn = connections.value[0]

        conn.emit(.question(AgentQuestion(requestID: "q-stop-1", message: "Should I proceed?")))
        try await waitUntil("question pending before stop") {
            session.hasPendingApproval && session.messages.contains { $0.question?.requestID == "q-stop-1" }
        }
        let qMsg = try XCTUnwrap(session.messages.first { $0.question?.requestID == "q-stop-1" })

        session.stop()

        XCTAssertFalse(session.hasPendingApproval)
        XCTAssertTrue(session.awaitingAnswers.isEmpty)
        XCTAssertEqual(session.messages.first { $0.id == qMsg.id }?.questionStatus, .expired)

        session.answerQuestion(messageID: qMsg.id, answers: ["k": "v"])
        session.skipQuestion(messageID: qMsg.id)
        try? await Task.sleep(nanoseconds: 25_000_000)
        XCTAssertTrue(conn.answers.isEmpty, "late answer/skip after stop() must send nothing")
        XCTAssertEqual(session.messages.first { $0.id == qMsg.id }?.questionStatus, .expired)

        conn.emit(.finished(status: "cancelled", response: nil, error: nil, conversationID: "s-stop"))
        conn.finishPrompt(with: .cancelled)
        try await waitUntil("turn ended after stop") { !session.isRunning }
        await session.stopAll()
    }

    /// Stop cancels the agent's turn, which cancels any approval it waits on,
    /// so the card must read as denied and a later click must not look like
    /// it did something (scout round 2: the card stayed clickable and showed
    /// "Approved" while nothing was sent).
    @MainActor
    func testStopDeniesPendingApprovalCardsAndIgnoresLateClicks() async throws {
        let connections = LockedCardBox<[CardMockPersistentConnection]>([])
        let env = makeSessionEnvironment(makeConnection: { spec in
            let conn = CardMockPersistentConnection(spec: spec)
            connections.withValue { $0.append(conn) }
            return conn
        })
        let session = VitruvianCodeQuickPromptSession(environment: env, host: CardMockSessionHost())
        session.takeCheckpoint = { _ in nil }
        let config = VitruvianCodeConfiguration(approvalMode: .standard, activeProvider: Self.agyACPProvider)

        session.send("Approve before stop", configuration: config, agentPath: "/fake/agy")
        try await waitUntil("prompt started for approval stop test") { connections.value.first?.promptCalls.count == 1 }
        let conn = connections.value[0]

        conn.emit(.approval(VitruvianCodeApprovalRequest(
            id: "call-stop",
            toolName: "Bash",
            commandOrPath: "rm -rf build",
            requestID: "perm-stop",
            options: [
                AgentPermissionOption(id: "allow-once", name: "Allow once", kind: .allowOnce),
                AgentPermissionOption(id: "reject-once", name: "Reject", kind: .rejectOnce),
            ]
        )))
        try await waitUntil("approval pending before stop") {
            session.hasPendingApproval && session.messages.contains { $0.approvalRequest?.requestID == "perm-stop" }
        }
        let cardMsg = try XCTUnwrap(session.messages.first { $0.approvalRequest?.requestID == "perm-stop" })

        session.stop()

        XCTAssertFalse(session.hasPendingApproval)
        XCTAssertEqual(session.messages.first { $0.id == cardMsg.id }?.approvalRequest?.status, .denied)

        session.decideApproval(messageID: cardMsg.id, optionID: "allow-once")
        session.decideApproval(messageID: cardMsg.id, decision: .approved)
        try? await Task.sleep(nanoseconds: 25_000_000)
        XCTAssertTrue(conn.answers.isEmpty, "a click after Stop must send nothing")
        XCTAssertEqual(
            session.messages.first { $0.id == cardMsg.id }?.approvalRequest?.status, .denied,
            "a click after Stop must not change the card"
        )

        conn.emit(.finished(status: "cancelled", response: nil, error: nil, conversationID: "s-stop"))
        conn.finishPrompt(with: .cancelled)
        try await waitUntil("turn ended after approval stop") { !session.isRunning }
        await session.stopAll()
    }

    /// A required multi-choice needs at least one pick whether or not the
    /// agent gave minItems (scout round 2: an explicit minItems of 0 let an
    /// empty answer through while the same field without it did not).
    func testRequiredMultiChoiceNeedsOnePickWithOrWithoutMinItems() {
        let options = [
            AgentQuestion.Option(value: "a", label: "A"),
            AgentQuestion.Option(value: "b", label: "B"),
        ]
        for minItems in [nil, 0] as [Int?] {
            let question = AgentQuestion(requestID: "mc-\(String(describing: minItems))", message: "Pick", fields: [
                AgentQuestion.Field(id: "tags", type: .multiChoice, label: "Tags", required: true,
                                    options: options, minItems: minItems),
            ])
            var form = AgentQuestionForm(question: question)
            XCTAssertNil(form.buildAnswers(), "empty required pick must not send (minItems \(String(describing: minItems)))")
            form.toggleMultiChoice(fieldID: "tags", value: "a")
            XCTAssertEqual(form.buildAnswers(), ["tags": #"["a"]"#])
        }
        let optional = AgentQuestion(requestID: "mc-opt", message: "Pick", fields: [
            AgentQuestion.Field(id: "tags", type: .multiChoice, label: "Tags", required: false,
                                options: options, minItems: 0),
        ])
        XCTAssertEqual(AgentQuestionForm(question: optional).buildAnswers(), [:],
                       "an optional pick left empty is not sent")
    }

    func testURLCanOpenAllowsOnlyHTTPAndHTTPSWithHostAndDisablesUnsafeOpen() {
        for allowed in [
            "https://auth.example.com/oauth/start?x=1",
            "http://localhost:8080/callback",
            "HTTPS://EXAMPLE.COM/path",
            "Http://sub.domain.org",
        ] {
            XCTAssertTrue(AgentQuestionForm.canOpen(allowed), "\(allowed) must be allowed")
        }

        for rejected in [
            "javascript:alert(1)",
            "javascript://evil.com/%0aalert(1)",
            "file:///etc/passwd",
            "file://localhost/etc/passwd",
            "vitruvian://open",
            "mailto:user@example.com",
            "http://",
            "https:///path-only",
            "http:example.com",
            "https://bad host.com",
            "not a url",
            "",
            "   ",
        ] {
            XCTAssertFalse(AgentQuestionForm.canOpen(rejected), "\(rejected) must be rejected")
        }
    }

    func testSingleRequiredFieldShowsRequiredMarkAndDistinctDescription() {
        let singleRequired = AgentQuestion.Field(
            id: "branch",
            type: .text,
            label: "Branch",
            description: "Git ref to deploy",
            required: true
        )
        XCTAssertTrue(AgentQuestionForm.showsRequiredMark(field: singleRequired, fieldCount: 1))
        XCTAssertEqual(
            AgentQuestionForm.fieldDescriptionToShow(field: singleRequired, message: "Enter deployment details"),
            "Git ref to deploy"
        )
        XCTAssertNil(AgentQuestionForm.fieldDescriptionToShow(field: singleRequired, message: "Git ref to deploy"))
        XCTAssertNil(
            AgentQuestionForm.fieldDescriptionToShow(
                field: AgentQuestion.Field(id: "b", type: .text, label: "Branch", description: "Branch", required: true),
                message: "Other"
            )
        )
        XCTAssertNil(
            AgentQuestionForm.fieldDescriptionToShow(
                field: AgentQuestion.Field(id: "b", type: .text, label: "Branch", description: "   ", required: true),
                message: "Other"
            )
        )

        let singleAlreadyLabeled = AgentQuestion.Field(
            id: "branch",
            type: .text,
            label: "Branch (Required)",
            required: true
        )
        XCTAssertFalse(AgentQuestionForm.showsRequiredMark(field: singleAlreadyLabeled, fieldCount: 1))
        XCTAssertTrue(
            AgentQuestionForm.showsRequiredMark(field: singleAlreadyLabeled, fieldCount: 1, hasOptionalField: true),
            "required mark stays visible whenever an optional field exists"
        )
        XCTAssertTrue(
            AgentQuestionForm.showsRequiredMark(field: singleAlreadyLabeled, fieldCount: 2),
            "required mark stays visible whenever multiple fields exist"
        )

        let singleOptional = AgentQuestion.Field(id: "note", type: .text, label: "Note", required: false)
        XCTAssertFalse(AgentQuestionForm.showsRequiredMark(field: singleOptional, fieldCount: 1))
        XCTAssertFalse(AgentQuestionForm.showsRequiredMark(field: singleOptional, fieldCount: 2))
    }

    func testDigitKeyActionOnlyConsumesValidOptionWhenComposerUnfocused() {
        XCTAssertFalse(AgentQuestionForm.digitKeyAction(digit: 1, optionCount: 0, composerFocused: false))
        XCTAssertFalse(AgentQuestionForm.digitKeyAction(digit: 4, optionCount: 2, composerFocused: false))
        XCTAssertFalse(AgentQuestionForm.digitKeyAction(digit: 1, optionCount: 3, composerFocused: true))
        XCTAssertTrue(AgentQuestionForm.digitKeyAction(digit: 1, optionCount: 3, composerFocused: false))
        XCTAssertTrue(AgentQuestionForm.digitKeyAction(digit: 3, optionCount: 3, composerFocused: false))
    }

    // MARK: - End-to-End Synthetic Fixture (`agy-question-synthetic.ndjson`)

    func testAgyQuestionSyntheticFixtureAnswersSelectedOptionIdThroughSession() async throws {
        let steps = ACPFixtureLoader.loadSteps(named: "agy-question-synthetic.ndjson")
        let agent = ScriptedACPAgent()
        let env = makeSessionEnvironment(makeConnection: { spec in
            AntigravityACPConnection(
                launchSpec: AgentProcessLaunchSpec(
                    executable: "/fake/agy",
                    arguments: ["acp"],
                    workingDirectory: spec.workingDirectory
                ),
                modeProvider: spec.liveModeProvider ?? { (.fullAccessForTest, false) },
                sessionSetupTimeout: 1.0,
                processFactory: agent.makeProcessFactory()
            )
        })
        let session = VitruvianCodeQuickPromptSession(environment: env, host: CardMockSessionHost())
        session.takeCheckpoint = { _ in nil }
        let config = VitruvianCodeConfiguration(
            workingDirectory: "/workspace",
            approvalMode: .standard,
            activeProvider: Self.agyACPProvider
        )

        // Play the synthetic fixture script in one pass so `lastRequestID` is preserved across `session/prompt`
        // (`$id`), pause on `expectClientResponse` until the user answers through the session, and verify the
        // `client_response` payload carries `selected` + `"blue"`.
        let playTask = Task {
            try await agent.playSteps(steps)
        }

        session.send("Ask me which color I prefer.", configuration: config, agentPath: "/fake/agy")

        try await waitUntil("synthetic question card pending") {
            session.hasPendingApproval && session.messages.contains { $0.question?.fields.first?.id == "interaction_1" }
        }
        let qMsg = try XCTUnwrap(session.messages.first { $0.question?.fields.first?.id == "interaction_1" })
        session.answerQuestion(messageID: qMsg.id, answers: ["interaction_1": "blue"])

        // Message index 3 is the response to `q-agy-1` (`initialize`=0, `session/new`=1, `session/prompt`=2, response=3).
        let response = try await agent.clientMessage(at: 3, timeout: 4.0)
        XCTAssertEqual(response.objectValue?["id"]?.stringValue, "q-agy-1")
        let outcome = response.objectValue?["result"]?.objectValue?["outcome"]?.objectValue
        XCTAssertEqual(outcome?["outcome"]?.stringValue, "selected")
        XCTAssertEqual(outcome?["optionId"]?.stringValue, "blue")

        try await withACPTestTimeout(seconds: 4.0) { try await playTask.value }
        try await waitUntil("synthetic fixture turn completed") { !session.isRunning }

        XCTAssertEqual(session.messages.first { $0.id == qMsg.id }?.questionStatus, .answered(["interaction_1": "blue"]))
        XCTAssertFalse(session.hasPendingApproval)
        await session.stopAll()
    }

    // MARK: - Test Support

    private func waitUntil(
        _ description: String,
        timeout: TimeInterval = 3.0,
        condition: @escaping @MainActor () -> Bool
    ) async throws {
        try await withACPTestTimeout(seconds: timeout, description: description) { @MainActor in
            while !condition() {
                try? await Task.sleep(nanoseconds: 5_000_000)
            }
        }
    }

    private func makeSessionEnvironment(
        makeConnection: @escaping (AgentConnectionSpec) -> any AgentConnection
    ) -> VitruvianCodeEngine.Environment {
        let domain = "com.vitruviansoftware.vitruvian-code.tests.cards.\(UUID().uuidString)"
        let defaults = ScratchDefaults.suite(named: domain)!
        defaults.removePersistentDomain(forName: domain)
        scratchSuites.append((defaults, domain))
        return VitruvianCodeEngine.Environment(
            defaults: defaults,
            home: "/tmp",
            processEnvironment: [:],
            stateDirectory: "/tmp/vitruvian-code-test-state",
            isExecutable: { _ in true },
            fileExists: { _ in true },
            readFile: { _ in nil },
            readTail: { _, _ in nil },
            writePrivateFile: { _, _ in true },
            removeFile: { _ in },
            isBotProcess: { _ in false },
            signal: { _, _ in },
            launchBot: { _, _, _, _, _ in 1 },
            schedule: { _, _ in },
            openFile: { _ in },
            launchAgent: { _, _, _, _, _, _ in throw CocoaError(.featureUnsupported) },
            makeConnection: makeConnection,
            readTranscript: { _, _ in nil },
            transcriptPath: { _, _ in nil },
            readTranscriptRaw: { _, _ in nil },
            runProgram: { _, _ in nil }
        )
    }
}

private extension VitruvianCodeApprovalMode {
    static var fullAccessForTest: VitruvianCodeApprovalMode { .standard }
}

private final class LockedCardBox<Value>: @unchecked Sendable {
    private let lock = NSLock()
    private var rawValue: Value

    init(_ initial: Value) {
        self.rawValue = initial
    }

    var value: Value {
        lock.withLock { rawValue }
    }

    func withValue(_ body: (inout Value) -> Void) {
        lock.withLock { body(&rawValue) }
    }
}

@MainActor
private final class CardMockPersistentConnection: PersistentAgentConnection {
    let spec: AgentConnectionSpec
    var capabilities = AgentCapabilities(resumeSession: true, closeSession: true)
    let events: AsyncStream<AgentEvent>
    private let continuation: AsyncStream<AgentEvent>.Continuation

    private(set) var promptCalls: [[PromptBlock]] = []
    private(set) var answers: [(String, AgentAnswer)] = []
    private var isStopped = false
    var isConnected: Bool { !isStopped }
    private var promptContinuation: CheckedContinuation<AgentStopReason, any Error>?

    init(spec: AgentConnectionSpec) {
        self.spec = spec
        var captured: AsyncStream<AgentEvent>.Continuation!
        self.events = AsyncStream { captured = $0 }
        self.continuation = captured
    }

    func start(_ request: AgentSessionRequest) async throws -> String {
        request.resumeSessionID ?? "mock-session"
    }

    func prompt(_ blocks: [PromptBlock]) async throws -> AgentStopReason {
        promptCalls.append(blocks)
        return try await withCheckedThrowingContinuation { cont in
            self.promptContinuation = cont
        }
    }

    func cancel() async {}

    func answer(_ requestID: String, _ choice: AgentAnswer) async throws {
        answers.append((requestID, choice))
    }

    func setConfigOption(_ id: String, _ value: AgentConfigValue) async throws -> [AgentConfigOption] {
        []
    }

    func syncPlanMode(_ planSwitch: Bool) async throws {}

    func stop() async {
        isStopped = true
        continuation.finish()
    }

    func emit(_ event: AgentEvent) {
        continuation.yield(event)
    }

    func finishPrompt(with reason: AgentStopReason) {
        let cont = promptContinuation
        promptContinuation = nil
        cont?.resume(returning: reason)
    }
}

@MainActor
private final class CardMockSessionHost: VitruvianCodeHost {
    var configuredBotDirectory = ""
    var startsBotAtLaunch = false
    var planMode = false
    var hiddenClaudeSessionIDs: [String] = []
    var chosenProviderID: UUID? = VitruvianCodeCLIProvider.antigravity.id
    var chosenModels: [UUID: String] = [:]
    var savedProviders: [VitruvianCodeCLIProvider] = []
    var promptHistory: [String] = []
    var worktreeMode = false
    var timelineOnLeft = true
    var sessionPreferences = VitruvianCodeSessionPreferences()
    var chatModes: [String: String] = [:]
    var strings = VitruvianCodeHostStrings()
    var approvals: [VitruvianCodeTurnNotice] = []

    func turnNeedsApproval(_ notice: VitruvianCodeTurnNotice) {
        approvals.append(notice)
    }

    func turnFinished(_ notice: VitruvianCodeTurnNotice, isChatVisible: Bool) {}
}
