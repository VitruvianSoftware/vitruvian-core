// Copyright 2026 VitruvianSoftware
// SPDX-License-Identifier: AGPL-3.0-or-later

import XCTest

@testable import CourierCore

/// The composer's state: keys, drafts, the reply chip, attachments and sending, against a sender that only writes
/// down what it was asked. All data here is made up.
@MainActor
final class ComposerModelTests: XCTestCase {
    private static let megabyte: Int64 = 1024 * 1024

    private func file(_ name: String) -> URL { URL(fileURLWithPath: "/tmp/courier-composer-test/\(name)") }

    /// A composer on a fake sender, where each file is as big as the test says (and a name ending in `/` is a folder).
    private func make(sizes: [String: Int64] = [:]) -> (ComposerModel, FakeSender) {
        let sender = FakeSender()
        let composer = ComposerModel(sender: sender, fileInfo: { url in
            let name = url.lastPathComponent
            if name == "folder" { return ComposerFileInfo(size: 0, isRegularFile: false) }
            guard let size = sizes[name] else { return nil }
            return ComposerFileInfo(size: size, isRegularFile: true)
        })
        return (composer, sender)
    }

    private func quote(_ id: String = "$1", name: String = "Ann", text: String = "Lunch?") -> QuotedMessage {
        QuotedMessage(eventID: id, senderName: name, mine: false, text: text, kind: .text)
    }

    // MARK: - Keys

    func testEnterSendsShiftEnterNewlines() async {
        let (composer, sender) = make()
        composer.open("!a")
        composer.text = "Hello"

        XCTAssertEqual(ComposerModel.action(forReturn: []), .send)
        XCTAssertEqual(ComposerModel.action(forReturn: [.command]), .send)
        for modifier: KeyModifiers in [.shift, .option, .control] {
            XCTAssertEqual(ComposerModel.action(forReturn: [modifier]), .newline, "\(modifier)")
        }

        // A newline key sends nothing and leaves the text for the view to add a line to.
        XCTAssertEqual(composer.handleReturn(modifiers: .shift), .newline)
        XCTAssertEqual(composer.handleReturn(modifiers: .option), .newline)
        XCTAssertEqual(composer.handleReturn(modifiers: .control), .newline)
        XCTAssertEqual(sender.calls, [])
        XCTAssertEqual(composer.text, "Hello")

        XCTAssertEqual(composer.handleReturn(modifiers: []), .send)
        await composer.settle()
        XCTAssertEqual(sender.calls, [.text(room: "!a", text: "Hello", replyTo: nil)])
        XCTAssertEqual(composer.text, "", "the box is empty at once")
    }

    func testEmptyOrWhitespaceDoesNotSend() async {
        let (composer, sender) = make()
        composer.open("!a")
        for text in ["", "   ", "\n\n", " \t\n "] {
            composer.text = text
            XCTAssertFalse(composer.canSend)
            XCTAssertNil(composer.submit())
        }
        await composer.settle()
        XCTAssertEqual(sender.calls, [])

        // What is sent has no blank lines or spaces at either end, and keeps the ones inside.
        composer.text = "  line one\n\nline two \n"
        XCTAssertTrue(composer.canSend)
        await composer.submit()?.value
        XCTAssertEqual(sender.calls, [.text(room: "!a", text: "line one\n\nline two", replyTo: nil)])
    }

    func testNothingSendsWithNoChatOpen() {
        let (composer, sender) = make()
        composer.text = "Hello"
        XCTAssertFalse(composer.canSend)
        XCTAssertNil(composer.submit())
        XCTAssertEqual(sender.calls, [])
    }

    // MARK: - Attachments

    func testOver90MBIsRefusedBeforeSending() async {
        let (composer, sender) = make(sizes: [
            "a.bin": 50 * Self.megabyte, "b.bin": 40 * Self.megabyte, "c.bin": 1, "huge.bin": 91 * Self.megabyte,
        ])
        composer.open("!a")

        composer.attach([file("huge.bin")])
        XCTAssertTrue(composer.attachments.isEmpty)
        XCTAssertEqual(composer.notice, .attachmentTooLarge(fileName: "huge.bin"))

        composer.attach([file("a.bin"), file("b.bin")])
        XCTAssertEqual(composer.attachments.map(\.fileName), ["a.bin", "b.bin"], "90 MB exactly fits")
        XCTAssertNil(composer.notice)

        composer.attach([file("c.bin")])
        XCTAssertEqual(composer.attachments.map(\.fileName), ["a.bin", "b.bin"], "one byte more does not")
        XCTAssertEqual(composer.notice, .attachmentTooLarge(fileName: "c.bin"))

        // Refused files never reach the engine; the accepted ones go one call each.
        await composer.submit()?.value
        XCTAssertEqual(sender.calls, [
            .file(room: "!a", name: "a.bin", size: 50 * Self.megabyte, replyTo: nil),
            .file(room: "!a", name: "b.bin", size: 40 * Self.megabyte, replyTo: nil),
        ])
        XCTAssertTrue(composer.attachments.isEmpty)
    }

    func testFoldersUnreadableAndRepeatedFilesAreNotAttached() {
        let (composer, _) = make(sizes: ["note.txt": 10])
        composer.open("!a")
        composer.attach([file("folder")])
        XCTAssertEqual(composer.notice, .notAFile(fileName: "folder"))
        composer.attach([file("missing.txt")])
        XCTAssertEqual(composer.notice, .cannotRead(fileName: "missing.txt"), "a file it cannot read is not a folder")
        XCTAssertTrue(composer.attachments.isEmpty)

        composer.attach([file("note.txt"), file("note.txt")])
        XCTAssertEqual(composer.attachments.count, 1, "the same file twice is one attachment")
    }

    func testRemovingAnAttachmentFreesItsSize() {
        let (composer, _) = make(sizes: ["a.bin": 80 * Self.megabyte, "b.bin": 20 * Self.megabyte])
        composer.open("!a")
        composer.attach([file("a.bin")])
        composer.attach([file("b.bin")])
        XCTAssertEqual(composer.attachments.count, 1)
        composer.removeAttachment(composer.attachments[0].id)
        composer.attach([file("b.bin")])
        XCTAssertEqual(composer.attachments.map(\.fileName), ["b.bin"])
    }

    func testFilesAloneCanBeSent() async {
        let (composer, sender) = make(sizes: ["a.bin": 10])
        composer.open("!a")
        composer.attach([file("a.bin")])
        XCTAssertTrue(composer.canSend, "an attachment is enough")
        await composer.submit()?.value
        XCTAssertEqual(sender.calls, [.file(room: "!a", name: "a.bin", size: 10, replyTo: nil)])
    }

    func testTextGoesFirstThenFilesAndOnlyTheFirstIsAReply() async {
        let (composer, sender) = make(sizes: ["a.bin": 10, "b.bin": 20])
        composer.open("!a")
        composer.startReply(to: quote("$1"))
        composer.text = "Here you go"
        composer.attach([file("a.bin"), file("b.bin")])
        await composer.submit()?.value
        XCTAssertEqual(sender.calls, [
            .text(room: "!a", text: "Here you go", replyTo: "$1"),
            .file(room: "!a", name: "a.bin", size: 10, replyTo: nil),
            .file(room: "!a", name: "b.bin", size: 20, replyTo: nil),
        ])

        // With no text, the first file carries the reply.
        sender.calls = []
        composer.startReply(to: quote("$2"))
        composer.attach([file("a.bin")])
        await composer.submit()?.value
        XCTAssertEqual(sender.calls, [.file(room: "!a", name: "a.bin", size: 10, replyTo: "$2")])
    }

    // MARK: - Replies

    func testReplyChipClearsOnSendAndEscape() async {
        let (composer, sender) = make()
        composer.open("!a")
        composer.startReply(to: quote("$1", name: "Ann"))
        XCTAssertEqual(composer.replyTarget?.eventID, "$1")

        // Escape clears the chip, and says it did, so the window keeps its other Escape jobs for later.
        XCTAssertTrue(composer.escape())
        XCTAssertNil(composer.replyTarget)
        XCTAssertFalse(composer.escape(), "nothing left to clear")

        composer.startReply(to: quote("$2"))
        composer.text = "Sure"
        await composer.submit()?.value
        XCTAssertEqual(sender.calls, [.text(room: "!a", text: "Sure", replyTo: "$2")])
        XCTAssertNil(composer.replyTarget, "the chip goes with the message")

        composer.text = "Next"
        await composer.submit()?.value
        XCTAssertEqual(sender.calls.last, .text(room: "!a", text: "Next", replyTo: nil))
    }

    // MARK: - Drafts

    func testDraftKeptPerChat() {
        let (composer, _) = make(sizes: ["a.bin": 5])
        composer.open("!a")
        composer.text = "half a thought"
        composer.attach([file("a.bin")])
        composer.startReply(to: quote("$1"))

        composer.open("!b")
        XCTAssertEqual(composer.text, "", "another chat starts empty")
        XCTAssertTrue(composer.attachments.isEmpty)
        XCTAssertNil(composer.replyTarget)
        composer.text = "something else"

        composer.open("!a")
        XCTAssertEqual(composer.text, "half a thought")
        XCTAssertEqual(composer.attachments.map(\.fileName), ["a.bin"])
        XCTAssertEqual(composer.replyTarget?.eventID, "$1")

        composer.open("!b")
        XCTAssertEqual(composer.text, "something else")

        composer.open(nil)
        XCTAssertEqual(composer.text, "")
        composer.open("!a")
        XCTAssertEqual(composer.text, "half a thought", "closing a chat keeps its draft too")
    }

    func testASentDraftIsNotKept() async {
        let (composer, _) = make()
        composer.open("!a")
        composer.text = "gone"
        await composer.submit()?.value
        composer.open("!b")
        composer.open("!a")
        XCTAssertEqual(composer.text, "")
    }

    // MARK: - Sending

    func testSendsInOrderAChatAtATime() async {
        let (composer, sender) = make()
        sender.gateFirstText(in: "!a")
        composer.open("!a")
        composer.text = "one"
        let first = composer.submit()
        composer.text = "two"
        let second = composer.submit()
        composer.open("!b")
        composer.text = "other chat"
        let third = composer.submit()

        await third?.value
        XCTAssertEqual(sender.calls.filter { $0.room == "!b" }.count, 1, "another chat does not wait")
        for _ in 0 ..< 20 { await Task.yield() }
        XCTAssertEqual(sender.calls.filter { $0.room == "!a" }.count, 1, "the second waits for the first's answer")

        sender.openGate()
        await first?.value
        await second?.value
        XCTAssertEqual(sender.calls.filter { $0.room == "!a" }.map(\.text), ["one", "two"])
    }

    func testTimedOutSendIsNeverResent() async {
        let (composer, sender) = make(sizes: ["a.bin": 5, "b.bin": 5])
        sender.failures = [.timedOut]
        var settled = 0
        composer.onSettled = { settled += 1 }
        composer.open("!a")
        composer.text = "maybe sent"
        composer.attach([file("a.bin"), file("b.bin")])
        await composer.submit()?.value

        XCTAssertEqual(sender.calls.count, 1, "no second try, and the files behind it wait for the person")
        XCTAssertEqual(composer.text, "", "the text may have gone, so it is not put back")
        XCTAssertEqual(composer.attachments.map(\.fileName), ["a.bin", "b.bin"], "what was never tried is put back")
        XCTAssertEqual(composer.notice, .noAnswer)
        XCTAssertEqual(settled, 1, "the timeline is told to read again, and shows what the store has")
    }

    func testRefusedSendPutsTheDraftBack() async {
        let (composer, sender) = make()
        sender.failures = [.rpc(.notLinked, message: "that network isn't linked", reason: nil)]
        composer.open("!a")
        composer.startReply(to: quote("$1"))
        composer.text = "Hello"
        await composer.submit()?.value

        XCTAssertEqual(composer.text, "Hello", "the engine refused it, so it was not sent")
        XCTAssertEqual(composer.replyTarget?.eventID, "$1")
        XCTAssertEqual(composer.notice, .sendFailed(reason: "This chat’s network isn’t linked."),
                       "the engine's own English is not shown")

        // Typing something new meanwhile is not overwritten.
        sender.failures = [.rpc(.notLinked, message: "no", reason: nil)]
        composer.text = "first"
        let task = composer.submit()
        composer.text = "second"
        await task?.value
        XCTAssertEqual(composer.text, "first\n\nsecond", "the refused text goes back above what was typed since")
    }

    func testARefusalWithACodeTheAppDoesNotKnowGivesGeneralWords() async {
        let (composer, sender) = make()
        sender.failures = [.rpc(.other(-32099), message: "something only the engine understands", reason: nil)]
        composer.open("!a")
        composer.text = "Hello"
        await composer.submit()?.value
        XCTAssertEqual(composer.notice, .sendFailed(reason: "The message could not be sent."))

        sender.failures = [.rpc(.tooLarge, message: "the file is too large to send (the limit is 90 MB)", reason: nil)]
        await composer.submit()?.value
        XCTAssertEqual(composer.notice, .sendFailed(reason: "A file is over 90 MB."))
    }

    func testFilesPutBackAfterARefusalNeverTakeTheTotalPast90MB() async {
        let (composer, sender) = make(sizes: ["a.bin": 60 * Self.megabyte, "b.bin": 50 * Self.megabyte])
        sender.failures = [.rpc(.notLinked, message: "x", reason: nil)]
        composer.open("!a")
        composer.attach([file("a.bin")])
        let task = composer.submit()
        composer.attach([file("b.bin")]) // typed in while the send was out: 60 + 50 would be too much
        await task?.value
        XCTAssertEqual(composer.attachments.map(\.fileName), ["a.bin"], "what was refused comes back; what no longer fits does not")
        XCTAssertEqual(composer.notices, [.sendFailed(reason: "This chat’s network isn’t linked."),
                                          .attachmentsLeftOut(fileNames: ["b.bin"])],
                       "the refusal first, then what did not fit")
        XCTAssertLessThanOrEqual(composer.attachments.reduce(Int64(0)) { $0 + $1.size }, ComposerModel.maxAttachmentBytes)
    }

    func testTheNoAnswerWarningIsNeverReplacedByTheTooLargeNotice() async {
        let (composer, sender) = make(sizes: ["a.bin": 60 * Self.megabyte, "b.bin": 50 * Self.megabyte])
        sender.failures = [.timedOut]
        composer.open("!a")
        composer.text = "maybe sent"
        composer.attach([file("a.bin")])
        let task = composer.submit() // the text times out; the file was never tried and goes back
        composer.attach([file("b.bin")]) // 60 + 50 does not fit
        await task?.value
        XCTAssertEqual(composer.notices, [.noAnswer, .attachmentsLeftOut(fileNames: ["b.bin"])],
                       "check the chat before sending again comes first, and stays")
        XCTAssertEqual(composer.attachments.map(\.fileName), ["a.bin"])
    }

    func testEveryFileLeftOutIsNamedAndTheNoticeWaitsForAChatThatIsNotOpen() async {
        let (composer, sender) = make(sizes: [
            "a.bin": 60 * Self.megabyte, "b.bin": 40 * Self.megabyte, "c.bin": 35 * Self.megabyte,
        ])
        sender.failures = [.rpc(.notLinked, message: "x", reason: nil)]
        composer.open("!a")
        composer.attach([file("a.bin")])
        let task = composer.submit() // refused once it runs
        composer.attach([file("b.bin"), file("c.bin")]) // 75 MB, fine on their own
        composer.open("!b") // the person has moved on
        await task?.value
        XCTAssertTrue(composer.notices.isEmpty, "this is chat b's composer, and the news is about chat a")

        composer.open("!a")
        XCTAssertEqual(composer.attachments.map(\.fileName), ["a.bin"], "60 + 40 and 60 + 35 are both over 90")
        XCTAssertEqual(composer.notices, [.sendFailed(reason: "This chat’s network isn’t linked."),
                                          .attachmentsLeftOut(fileNames: ["b.bin", "c.bin"])],
                       "every file left out is named, and nothing was lost silently")
        composer.open("!b")
        composer.open("!a")
        XCTAssertTrue(composer.notices.isEmpty, "shown once")
    }

    func testARefusalIsPutBackIntoThatChatsDraftEvenIfAnotherIsOpen() async {
        let (composer, sender) = make()
        sender.failures = [.rpc(.notLinked, message: "no", reason: nil)]
        sender.gateFirstText(in: "!a")
        composer.open("!a")
        composer.text = "for a"
        let task = composer.submit()
        composer.open("!b")
        sender.openGate()
        await task?.value
        XCTAssertEqual(composer.text, "")
        composer.open("!a")
        XCTAssertEqual(composer.text, "for a")
    }

    func testTextThatCouldNotBeSentFromOutsideTheWindowWaitsInThatChat() {
        let (composer, _) = make()
        // The chat is not open: the text waits in its draft and is there when it opens.
        composer.open("!b")
        composer.restoreUnsent(text: "on my way", in: "!a")
        XCTAssertEqual(composer.text, "")
        composer.open("!a")
        XCTAssertEqual(composer.text, "on my way")

        // The chat is open: it goes straight in, above what has been typed since.
        composer.text = "and also"
        composer.restoreUnsent(text: "see you", in: "!a")
        XCTAssertEqual(composer.text, "see you\n\nand also")
    }

    func testTextThatMayHaveGoneCarriesTheMayHaveBeenSentNotice() {
        let (composer, _) = make()
        // A chat that is not open: the notice waits with the draft and shows when it opens.
        composer.open("!b")
        composer.restoreUnsent(text: "on my way", in: "!a", mayHaveBeenSent: true)
        XCTAssertNil(composer.notice)
        composer.open("!a")
        XCTAssertEqual(composer.text, "on my way")
        XCTAssertEqual(composer.notice, .noAnswer)

        // The chat is open: the text and the notice show at once. Plain failures carry no notice.
        composer.open("!b")
        composer.restoreUnsent(text: "see you", in: "!b", mayHaveBeenSent: true)
        XCTAssertEqual(composer.text, "see you")
        XCTAssertEqual(composer.notice, .noAnswer)
        composer.open("!c")
        composer.restoreUnsent(text: "plain", in: "!c", mayHaveBeenSent: false)
        XCTAssertNil(composer.notice)
    }

    func testTheNoticeGoesWhenTheChatChanges() {
        let (composer, _) = make()
        composer.open("!a")
        composer.attach([file("missing")])
        XCTAssertNotNil(composer.notice)
        composer.open("!b")
        XCTAssertNil(composer.notice)
    }

    // MARK: - The file call's time limit

    func testFileTimeoutIsThirtySecondsPlusOnePerMB() {
        XCTAssertEqual(EngineMessageSender.fileTimeout(forBytes: 0), 30)
        XCTAssertEqual(EngineMessageSender.fileTimeout(forBytes: 1), 31, "a part of a megabyte counts as one")
        XCTAssertEqual(EngineMessageSender.fileTimeout(forBytes: Self.megabyte), 31)
        XCTAssertEqual(EngineMessageSender.fileTimeout(forBytes: 50 * Self.megabyte), 80)
        XCTAssertEqual(EngineMessageSender.fileTimeout(forBytes: 90 * Self.megabyte), 120)
    }
}

// MARK: - Fixtures

/// A sender that writes down what it is asked to send, can fail as the test says, and can hold the first text.
final class FakeSender: MessageSending, @unchecked Sendable {
    enum Call: Equatable {
        case text(room: String, text: String, replyTo: String?)
        case file(room: String, name: String, size: Int64, replyTo: String?)

        var room: String {
            switch self {
            case let .text(room, _, _), let .file(room, _, _, _): room
            }
        }

        var text: String? {
            if case let .text(_, text, _) = self { text } else { nil }
        }
    }

    private let lock = NSLock()
    private var _calls: [Call] = []
    private var _failures: [EngineError] = []
    private var gate: CheckedContinuation<Void, Never>?
    private var gatedRoom: String?
    private var gateOpen = false

    var calls: [Call] {
        get { lock.withLock { _calls } }
        set { lock.withLock { _calls = newValue } }
    }

    /// The next calls fail with these errors, one each, in order.
    var failures: [EngineError] {
        get { lock.withLock { _failures } }
        set { lock.withLock { _failures = newValue } }
    }

    /// The first text to `room` waits (after it is written down) until `openGate`. Named by chat, not "the first
    /// call", since sends to two chats may start in either order.
    func gateFirstText(in room: String) { lock.withLock { gatedRoom = room } }

    func openGate() {
        let waiting = lock.withLock { () -> CheckedContinuation<Void, Never>? in
            gateOpen = true
            defer { gate = nil }
            return gate
        }
        waiting?.resume()
    }

    private func nextFailure() -> EngineError? {
        lock.withLock { _failures.isEmpty ? nil : _failures.removeFirst() }
    }

    func sendText(roomID: String, text: String, replyTo: String?) async throws {
        lock.withLock { _calls.append(.text(room: roomID, text: text, replyTo: replyTo)) }
        let holds = lock.withLock { () -> Bool in
            guard gatedRoom == roomID else { return false }
            gatedRoom = nil
            return !gateOpen
        }
        if holds {
            await withCheckedContinuation { continuation in
                let resume = lock.withLock { () -> Bool in
                    if gateOpen { return true }
                    gate = continuation
                    return false
                }
                if resume { continuation.resume() }
            }
        }
        if let failure = nextFailure() { throw failure }
    }

    func sendFile(roomID: String, url: URL, size: Int64, replyTo: String?) async throws {
        lock.withLock { _calls.append(.file(room: roomID, name: url.lastPathComponent, size: size, replyTo: replyTo)) }
        if let failure = nextFailure() { throw failure }
    }
}
