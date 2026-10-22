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

// MARK: - Formatting, editing, undo send and send later (4.3)

/// The 4.3 composer: formatting ranges, mentions, quick replies, editing, threads, undo send and send later, against
/// a sender that writes down what it was asked and answers as the test says. Settings live in a suite-named
/// UserDefaults of the test's own. Every wait is on a gate the test opens, never on time.
extension ComposerModelTests {
    /// When the timeline's messages were sent, and "now" a minute later.
    private static let sentAt: Int64 = 1_760_600_000_000
    private var now: Date { Date(timeIntervalSince1970: Double(Self.sentAt + 60_000) / 1000) }
    private var me: String { Timeline.meUserID }

    private var whatsApp: ChatFeatures {
        ChatFeatures(reply: true, edit: true, editMaxAgeMS: 15 * 60 * 1000, unsend: true,
                     formatting: [.bold, .italic, .link, .mention], maxTextLength: 65536, source: .stored)
    }

    private var slack: ChatFeatures {
        ChatFeatures(reply: false, thread: true, replyIsThread: true, edit: true, unsend: true,
                     formatting: [.bold, .mention], mentionRoom: true, source: .stored)
    }

    private struct Denies: EntitlementProvider {
        let denied: Set<Feature>
        func isEntitled(_ feature: Feature) -> Bool { !denied.contains(feature) }
    }

    private struct Made {
        let composer: ComposerModel
        let sender: FakeSender
        let preferences: ComposerPreferences
        let replies: QuickReplies
        let clock: MovableClock
    }

    private func makeComposer(undoMillis: Int = 0, denied: Set<Feature> = [], features: ChatFeatures? = nil,
                      network: String = "whatsapp", now: Date? = nil, sizes: [String: Int64] = [:]) -> Made {
        let store = TestDefaults()
        addTeardownBlock { store.remove() }
        let preferences = ComposerPreferences(defaults: store.defaults)
        preferences.undoSendMillis = undoMillis
        let replies = QuickReplies(defaults: store.defaults)
        let sender = FakeSender()
        let clock = MovableClock(now ?? self.now)
        let composer = ComposerModel(sender: sender, fileInfo: { url in
            sizes[url.lastPathComponent].map { ComposerFileInfo(size: $0, isRegularFile: true) }
        }, draftDelay: 0, sleep: { _ in }, preferences: preferences, entitlement: Denies(denied: denied),
        quickReplies: replies, now: { clock.now })
        composer.open("!a")
        composer.features = features ?? whatsApp // after open: a chat's features are set once it is open
        composer.network = network
        return Made(composer: composer, sender: sender, preferences: preferences, replies: replies, clock: clock)
    }

    /// Types `text` at the caret, as the text view reports it.
    private func type(_ text: String, into composer: ComposerModel, at location: Int? = nil) {
        let current = composer.text as NSString
        let at = location ?? current.length
        composer.textChanged(to: current.replacingCharacters(in: NSRange(location: at, length: 0), with: text),
                             replacing: NSRange(location: at, length: 0), with: (text as NSString).length)
    }

    private func bold(_ offset: Int, _ length: Int) -> TextEntity { TextEntity(kind: .bold, offset: offset, length: length) }

    private func json(_ text: String) -> JSONValue {
        try! JSONDecoder().decode(JSONValue.self, from: Data(text.utf8))
    }

    /// A message event; `ago` is how long before `sentAt + 60 s` ("now") it was sent, in seconds.
    private func event(_ id: String, mine: Bool = true, body: String = "text", msgtype: String = "m.text",
                       status: EventStatus = .sent, reason: String = "", at offset: Int64) -> Event {
        let encoded = String(decoding: try! JSONEncoder().encode(body), as: UTF8.self)
        return Event(eventID: id, roomID: "!a", sender: mine ? me : "@ann:example.test", senderName: mine ? "me" : "Ann",
                     mine: mine, type: "m.room.message",
                     content: json(#"{"msgtype":"\#(msgtype)","body":\#(encoded)}"#), ts: Self.sentAt + offset,
                     seq: offset, status: status, statusReason: reason)
    }

    private func items(_ events: [Event]) -> [TimelineItem] {
        Timeline.build(events: events, me: me, now: now)
    }

    private func message(_ id: String, in items: [TimelineItem]) -> TimelineMessage {
        for case let .message(found) in items where found.id == id { return found }
        fatalError("no message \(id)")
    }

    // MARK: Sending

    func testSendCarriesEntitiesAndHold() async throws {
        let made = makeComposer(undoMillis: 2000)
        let composer = made.composer
        type("hello world", into: composer)
        composer.toggle(.bold, in: NSRange(location: 0, length: 5))
        XCTAssertEqual(composer.entities, [bold(0, 5)])
        await composer.submit()?.value

        XCTAssertEqual(made.sender.sends, [.init(room: "!a", rich: RichText(text: "hello world", entities: [bold(0, 5)]),
                                                 replyTo: nil, threadRoot: nil, holdMillis: 2000)])
        XCTAssertEqual(composer.heldIDs, ["$sent1"], "a held message can be undone")
        XCTAssertEqual(composer.text, "")
        XCTAssertEqual(composer.entities, [], "the formatting goes with the text")

        // The ranges move with the spaces cut from either end.
        type("\n  hi there  \n", into: composer)
        composer.toggle(.bold, in: NSRange(location: 3, length: 2))
        await composer.submit()?.value
        XCTAssertEqual(made.sender.sends.last?.rich, RichText(text: "hi there", entities: [bold(0, 2)]))

        // On the wire: hold_ms and the ranges, as protocol 4 has them.
        let params = EngineMessageSender.sendParams(roomID: "!a", rich: RichText(text: "hello", entities: [bold(0, 5)]),
                                                    replyTo: "$r", threadRoot: "$t", holdMillis: 2000)
        let wire = try JSONSerialization.jsonObject(with: JSONEncoder().encode(params)) as! [String: Any]
        XCTAssertEqual(wire["hold_ms"] as? Int, 2000)
        XCTAssertEqual(wire["thread_root"] as? String, "$t")
        XCTAssertEqual(wire["reply_to"] as? String, "$r")
        XCTAssertEqual((wire["entities"] as? [[String: Any]])?.first?["type"] as? String, "bold")
        let unheld = EngineMessageSender.sendParams(roomID: "!a", rich: RichText(text: "x"), replyTo: nil,
                                                    threadRoot: nil, holdMillis: 0)
        let plain = try JSONSerialization.jsonObject(with: JSONEncoder().encode(unheld)) as! [String: Any]
        XCTAssertNil(plain["hold_ms"], "not held: no hold_ms, as before undo send")
        XCTAssertNil(plain["entities"], "no ranges: none on the wire")
    }

    func testHoldIsZeroWhenNotEntitled() async {
        let made = makeComposer(undoMillis: 5000, denied: [.undoSend], sizes: ["a.bin": 10])
        type("not held", into: made.composer)
        made.composer.attach([URL(fileURLWithPath: "/tmp/courier-composer-test/a.bin")])
        await made.composer.submit()?.value
        XCTAssertEqual(made.sender.sends.map(\.holdMillis), [0])
        XCTAssertEqual(made.sender.fileSends.map(\.holdMillis), [0], "files are held as text is, or not at all")
        XCTAssertEqual(made.composer.heldIDs, [])

        // With the plan, files are held too.
        let entitled = makeComposer(undoMillis: 5000, sizes: ["a.bin": 10])
        entitled.composer.attach([URL(fileURLWithPath: "/tmp/courier-composer-test/a.bin")])
        await entitled.composer.submit()?.value
        XCTAssertEqual(entitled.sender.fileSends.map(\.holdMillis), [5000])
        XCTAssertEqual(entitled.composer.heldIDs, ["$sent1"])
    }

    func testOverTheChatsLimitIsRefusedInBytes() async {
        var features = whatsApp
        features.maxTextLength = 10
        let made = makeComposer(features: features)
        let composer = made.composer

        composer.text = "ééééé" // 5 characters, 10 bytes: fits
        await composer.submit()?.value
        XCTAssertEqual(made.sender.sends.map(\.rich.text), ["ééééé"])

        for over in ["éééééé", "😀😀😀"] { // 6 characters, 12 bytes; 3 characters, 12 bytes
            composer.text = over
            XCTAssertNil(composer.submit(), "nothing is sent")
            XCTAssertEqual(composer.text, over, "what was typed stays")
            XCTAssertEqual(composer.notice, .textTooLong, "and the composer says why")
        }
        XCTAssertEqual(made.sender.sends.count, 1)

        // The engine's own limit holds where the chat gives none.
        let unlimited = makeComposer(features: ChatFeatures(reply: true, source: .stored))
        unlimited.composer.text = String(repeating: "x", count: SendParams.maxTextBytes + 1)
        XCTAssertNil(unlimited.composer.submit())
        XCTAssertEqual(unlimited.composer.notice, .textTooLong)
    }

    func testRangesTheEngineRefusesAreNotSent() async {
        let made = makeComposer()
        let composer = made.composer
        composer.text = "see here\nand there"
        composer.entities = [
            TextEntity(kind: .link, offset: 0, length: 3, url: "javascript:alert(1)"), // not an address it takes
            TextEntity(kind: .blockquote, offset: 2, length: 3), // part of a line
            TextEntity(kind: .link, offset: 4, length: 4, url: "https://example.test/a_b"),
            TextEntity(kind: .link, offset: 6, length: 5, url: "https://example.test/c"), // overlaps the one before
            TextEntity(kind: .bold, offset: 9, length: 3),
        ]
        await composer.submit()?.value
        XCTAssertEqual(made.sender.sends.first?.rich.entities, [
            TextEntity(kind: .link, offset: 4, length: 4, url: "https://example.test/a_b"),
            TextEntity(kind: .bold, offset: 9, length: 3),
        ])
    }

    func testThreadModeSendsThreadRoot() async {
        let made = makeComposer(features: slack, network: "slack", sizes: ["a.bin": 10])
        let composer = made.composer
        composer.startThread("$root")
        XCTAssertEqual(composer.mode, .thread(rootID: "$root"))
        type("in the thread", into: composer)
        composer.attach([URL(fileURLWithPath: "/tmp/courier-composer-test/a.bin")])
        await composer.submit()?.value
        XCTAssertEqual(made.sender.sends.map(\.threadRoot), ["$root"])
        XCTAssertEqual(made.sender.fileSends.map(\.threadRoot), ["$root"])
        XCTAssertEqual(composer.mode, .thread(rootID: "$root"), "the thread's composer stays in the thread")

        composer.endThread()
        type("in the chat", into: composer)
        await composer.submit()?.value
        XCTAssertNil(made.sender.sends.last?.threadRoot)
    }

    func testSendAndArchive() async {
        let made = makeComposer()
        var archived: [String] = []
        // The inbox archives (pinned chats, its toast with Undo, what opens next): the composer only asks it to.
        made.composer.onArchive = { room in archived.append("\(room) after \(made.sender.sends.count) send") }
        type("bye", into: made.composer)
        await made.composer.submit(archive: true)?.value
        XCTAssertEqual(archived, ["!a after 1 send"], "archived once the message is sent")

        made.sender.failures = [.rpc(.notLinked, message: "no", reason: nil)]
        type("not sent", into: made.composer)
        await made.composer.submit(archive: true)?.value
        XCTAssertEqual(archived, ["!a after 1 send"], "a refused message keeps its chat in view")
        XCTAssertEqual(made.composer.text, "not sent")

        made.sender.failures = [.timedOut]
        await made.composer.submit(archive: true)?.value
        XCTAssertEqual(archived, ["!a after 1 send"], "nor one that may not have gone")

        await made.composer.submit()?.value
        XCTAssertEqual(archived.count, 1, "Return alone doesn't archive")
    }

    // MARK: Formatting

    func testAKeyWithNoSelectionFormatsWhatIsTypedNext() async {
        let made = makeComposer()
        let composer = made.composer
        type("plain ", into: composer)
        composer.toggle(.bold, in: NSRange(location: 6, length: 0))
        XCTAssertEqual(composer.pendingKinds, [.bold])
        type("strong", into: composer)
        XCTAssertEqual(composer.entities, [bold(6, 6)])
        type("er", into: composer)
        XCTAssertEqual(composer.entities, [bold(6, 8)], "it carries on while typing goes on there")

        composer.selectionChanged(to: NSRange(location: 0, length: 0))
        XCTAssertEqual(composer.pendingKinds, [], "moving the caret ends it")
        composer.toggle(.bold, in: NSRange(location: 14, length: 0))
        composer.toggle(.bold, in: NSRange(location: 14, length: 0))
        XCTAssertEqual(composer.pendingKinds, [], "the key again takes it back")

        // A block on an empty line applies once the line has text.
        composer.text = ""
        composer.toggle(.blockquote, in: NSRange(location: 0, length: 0))
        type("quoted", into: composer)
        XCTAssertEqual(composer.entities, [TextEntity(kind: .blockquote, offset: 0, length: 6)])
    }

    func testBackspaceJoiningAQuotedLineLeavesNoHalfBlock() async {
        let made = makeComposer()
        let composer = made.composer
        type("plain\nquote", into: composer)
        composer.toggle(.blockquote, in: NSRange(location: 8, length: 0))
        XCTAssertEqual(composer.entities, [TextEntity(kind: .blockquote, offset: 6, length: 5)])
        composer.textChanged(to: "plainquote", replacing: NSRange(location: 5, length: 1), with: 0)
        XCTAssertEqual(composer.entities, [], "the joined line is plain, as its first line was: nothing half-quoted")
        await composer.submit()?.value
        XCTAssertEqual(made.sender.sends.first?.rich, RichText(text: "plainquote"))
    }

    func testFormattingStaysWithTheChatsDraft() {
        let made = makeComposer()
        let composer = made.composer
        type("keep this", into: composer)
        composer.toggle(.italic, in: NSRange(location: 0, length: 4))
        composer.open("!b")
        XCTAssertEqual(composer.entities, [])
        composer.open("!a")
        XCTAssertEqual(composer.text, "keep this")
        XCTAssertEqual(composer.entities, [TextEntity(kind: .italic, offset: 0, length: 4)])

        // Text set straight (a paste the view reports as a whole) keeps the ranges where they belong.
        composer.text = ">> keep this"
        XCTAssertEqual(composer.entities, [TextEntity(kind: .italic, offset: 3, length: 4)])
    }

    func testSetLinkAddsAndRemovesALink() {
        let made = makeComposer()
        let composer = made.composer
        type("read this now", into: composer)
        let url = URL(string: "https://example.test/doc")!
        composer.setLink(url, text: "this", in: NSRange(location: 5, length: 4))
        XCTAssertEqual(composer.entities, [TextEntity(kind: .link, offset: 5, length: 4, url: url.absoluteString)])

        composer.setLink(url, text: "the doc", in: NSRange(location: 5, length: 4))
        XCTAssertEqual(composer.text, "read the doc now", "the link's words replace the selection")
        XCTAssertEqual(composer.entities, [TextEntity(kind: .link, offset: 5, length: 7, url: url.absoluteString)])

        composer.setLink(nil, text: "the doc", in: NSRange(location: 5, length: 7))
        XCTAssertEqual(composer.entities, [])
        XCTAssertEqual(composer.text, "read the doc now", "removing a link keeps its words")

        composer.setLink(URL(string: "javascript:alert(1)")!, text: "x", in: NSRange(location: 0, length: 4))
        XCTAssertEqual(composer.entities, [], "an address the engine wouldn't take is never made a link")
    }

    // MARK: Mentions and quick replies

    func testMentionQueryAndInsert() async {
        let made = makeComposer()
        let composer = made.composer
        let ann = Member(userID: "@ann:example.test", name: "Ann Example")
        made.sender.members = [ann]

        type("Hi @an", into: composer)
        XCTAssertEqual(composer.mentionQuery?.range, NSRange(location: 3, length: 3))
        XCTAssertEqual(composer.mentionQuery?.text, "an")
        let candidates = await composer.mentionCandidates()
        XCTAssertEqual(candidates, [ann])
        XCTAssertEqual(made.sender.memberQueries, ["!a an"])

        composer.insertMention(ann, replacing: composer.mentionQuery!.range)
        XCTAssertEqual(composer.text, "Hi @Ann Example ")
        XCTAssertEqual(composer.entities, [TextEntity(kind: .mention, offset: 3, length: 12, userID: ann.userID)])
        XCTAssertNil(composer.mentionQuery)

        await composer.submit()?.value
        XCTAssertEqual(made.sender.sends.first?.rich,
                       RichText(text: "Hi @Ann Example", entities: [TextEntity(kind: .mention, offset: 3, length: 12,
                                                                               userID: ann.userID)]))

        // An address is not a mention.
        type("mail me at ann@ex", into: composer)
        XCTAssertNil(composer.mentionQuery)
        composer.text = ""
        type("@", into: composer)
        XCTAssertEqual(composer.mentionQuery?.text, "", "a lone @ lists everyone")
    }

    func testRoomMentionOnlyWhereTheChatHasIt() async {
        let made = makeComposer(features: whatsApp)
        made.sender.members = [Member(userID: "@rob:example.test", name: "Rob")]
        type("@ro", into: made.composer)
        var candidates = await made.composer.mentionCandidates()
        XCTAssertEqual(candidates.map(\.userID), ["@rob:example.test"], "@room is plain text in WhatsApp")

        made.composer.features = slack
        candidates = await made.composer.mentionCandidates()
        XCTAssertEqual(candidates.map(\.userID), ["@room", "@rob:example.test"], "Slack's @room reaches everyone")
        made.composer.insertMention(candidates[0], replacing: made.composer.mentionQuery!.range)
        XCTAssertEqual(made.composer.text, "@room ")
        XCTAssertEqual(made.composer.entities, [TextEntity(kind: .mention, offset: 0, length: 5, userID: "@room")])

        // Only when what was typed could be "room".
        made.composer.text = ""
        type("@rob", into: made.composer)
        candidates = await made.composer.mentionCandidates()
        XCTAssertEqual(candidates.map(\.userID), ["@rob:example.test"])
    }

    func testQuickReplyQueryAndFill() throws {
        let made = makeComposer()
        let composer = made.composer
        try made.replies.add(title: "omw", text: "On my way, {first_name}! {day}")

        type("Sure. ;om", into: composer)
        XCTAssertEqual(composer.quickReplyQuery?.range, NSRange(location: 6, length: 3))
        XCTAssertEqual(composer.quickReplyQuery?.text, "om")
        XCTAssertEqual(composer.quickReplyMatches.map(\.title), ["omw"])

        composer.insertQuickReply(made.replies.all[0], replacing: composer.quickReplyQuery!.range,
                                  otherPerson: "Ada Lovelace")
        XCTAssertEqual(composer.text, "Sure. On my way, Ada! {day}")
        XCTAssertNil(composer.quickReplyQuery)

        composer.text = ""
        type("a;om", into: composer)
        XCTAssertNil(composer.quickReplyQuery, "a semicolon inside a word is punctuation")
    }

    // MARK: Editing

    func testEditModeSendsAnEditAndEscapeRestores() async {
        let made = makeComposer(undoMillis: 1000)
        let composer = made.composer
        let timeline = items([event("$m", body: "old words", at: 0)])
        let original = message("$m", in: timeline)

        type("held", into: composer)
        await composer.submit()?.value
        XCTAssertEqual(composer.heldIDs, ["$sent1"])

        type("half typed", into: composer)
        composer.toggle(.bold, in: NSRange(location: 0, length: 4))
        composer.startReply(to: QuotedMessage(eventID: "$q", senderName: "Ann", mine: false, text: "q", kind: .text))
        composer.startEditing(original)
        XCTAssertEqual(composer.mode, .editing(eventID: "$m", original: original.rich))
        XCTAssertEqual(composer.text, "old words")
        XCTAssertEqual(composer.entities, [])
        XCTAssertNil(composer.replyTarget, "an edit is not a reply")

        // Escape: what was there comes back, formatting and reply chip too.
        XCTAssertTrue(composer.escape())
        XCTAssertEqual(composer.mode, .new)
        XCTAssertEqual(composer.text, "half typed")
        XCTAssertEqual(composer.entities, [bold(0, 4)])
        XCTAssertEqual(composer.replyTarget?.eventID, "$q")

        // Unchanged: nothing is sent.
        composer.startEditing(original)
        await composer.submit()?.value
        XCTAssertEqual(made.sender.edits, [])
        XCTAssertEqual(composer.mode, .new)
        XCTAssertEqual(composer.text, "half typed")

        // Changed: an edit, never a new message, and the composer is as it was.
        composer.startEditing(original)
        composer.text = "new words"
        await composer.submit()?.value
        XCTAssertEqual(made.sender.edits, [.init(eventID: "$m", rich: RichText(text: "new words"))])
        XCTAssertEqual(made.sender.sends.count, 1, "only the held message was ever sent")
        XCTAssertEqual(composer.mode, .new)
        XCTAssertEqual(composer.text, "half typed")
        XCTAssertEqual(composer.heldIDs, ["$sent1"], "an edit leaves held messages alone")

        // The edit's text is never kept as the chat's draft.
        composer.startEditing(original)
        composer.text = "not a draft"
        for _ in 0 ..< 50 { await Task.yield() }
        XCTAssertTrue(made.sender.savedDrafts.contains("half typed"), "what is typed outside an edit is kept")
        XCTAssertFalse(made.sender.savedDrafts.contains("not a draft"))
        XCTAssertTrue(composer.escape())

        // An edit the engine refuses comes back to be fixed, still an edit.
        made.sender.failures = [.rpc(.tooOld, message: "too old", reason: nil)]
        composer.text = ""
        composer.startEditing(original)
        composer.text = "late words"
        await composer.submit()?.value
        XCTAssertEqual(composer.mode, .editing(eventID: "$m", original: original.rich))
        XCTAssertEqual(composer.text, "late words")
        XCTAssertEqual(composer.notice, .sendFailed(reason: "That message can’t be changed any more."))
    }

    func testUpArrowEditsTheLastMessage() {
        let timeline = items([
            event("$1", body: "first", at: 0),
            event("$2", body: "second", at: 1000),
            event("$3", mine: false, body: "theirs", at: 2000),
            event("$4", body: "photo", msgtype: "m.image", at: 3000),
            event("$5", body: "held", status: .queued, at: 4000),
        ])

        let made = makeComposer()
        made.preferences.upArrow = .editLast
        XCTAssertTrue(made.composer.editLast(in: timeline))
        XCTAssertEqual(made.composer.mode, .editing(eventID: "$2", original: RichText(text: "second")),
                       "my newest text message that can be edited: not theirs, a photo or a held one")

        // Not with something typed, nor with the setting off, nor past the network's limit.
        let typed = makeComposer()
        typed.preferences.upArrow = .editLast
        typed.composer.text = "typing"
        XCTAssertFalse(typed.composer.editLast(in: timeline))
        XCTAssertEqual(typed.composer.mode, .new)

        let off = makeComposer()
        XCTAssertFalse(off.composer.editLast(in: timeline), "↑ moves to the messages by default")

        let late = makeComposer(now: Date(timeIntervalSince1970: Double(Self.sentAt + 20 * 60 * 1000) / 1000))
        late.preferences.upArrow = .editLast
        XCTAssertFalse(late.composer.editLast(in: timeline), "WhatsApp only lets you edit for 15 minutes")
    }

    func testReturnOnASelectedMessage() async {
        let timeline = items([event("$mine", body: "mine", at: 0), event("$theirs", mine: false, body: "theirs", at: 1000)])
        let made = makeComposer()
        let composer = made.composer
        var selected: TimelineMessage?
        composer.selectedMessage = { selected }

        selected = message("$mine", in: timeline)
        XCTAssertEqual(composer.handleReturn(modifiers: []), .send)
        XCTAssertEqual(composer.mode, .editing(eventID: "$mine", original: RichText(text: "mine")), "mine: edit it")
        XCTAssertTrue(composer.escape())

        selected = message("$theirs", in: timeline)
        composer.handleReturn(modifiers: [])
        XCTAssertEqual(composer.replyTarget?.eventID, "$theirs", "someone else's: reply to it")
        composer.cancelReply()

        // In a chat whose replies are thread replies, the reply opens its thread.
        composer.features = slack
        composer.handleReturn(modifiers: [])
        XCTAssertEqual(composer.mode, .thread(rootID: "$theirs"))
        composer.endThread()

        // With something typed, Return sends it.
        composer.features = whatsApp
        composer.text = "typed"
        composer.handleReturn(modifiers: [])
        await composer.settle()
        XCTAssertEqual(made.sender.sends.map(\.rich.text), ["typed"])
        XCTAssertEqual(made.sender.edits, [])
    }

    // MARK: Undo send

    func testUndoPutsTheTextBack() async {
        let made = makeComposer(undoMillis: 2000)
        let composer = made.composer
        composer.quote = { id in QuotedMessage(eventID: id, senderName: "Ann", mine: false, text: "q", kind: .text) }
        type("first", into: composer)
        await composer.submit()?.value
        XCTAssertEqual(composer.heldIDs, ["$sent1"])
        made.sender.undoResults["$sent1"] = .success(Draft(text: "first", entities: [bold(0, 5)], replyTo: "$r",
                                                          threadRoot: nil))

        type("new", into: composer)
        let undone = await composer.undoNewestHeld()
        XCTAssertTrue(undone)
        XCTAssertEqual(made.sender.undos, ["$sent1"])
        XCTAssertEqual(composer.text, "new\n\nfirst", "below what was typed since, after a blank line")
        XCTAssertEqual(composer.entities, [bold(5, 5)])
        XCTAssertEqual(composer.replyTarget?.eventID, "$r", "the reply comes back with it")
        XCTAssertEqual(composer.heldIDs, [])
        XCTAssertEqual(composer.toast?.message, "Message unsent from Courier")

        let again = await composer.undoNewestHeld()
        XCTAssertFalse(again, "nothing held: ⌘Z is the text view's again")
        XCTAssertEqual(made.sender.undos, ["$sent1"])
    }

    func testUndoBringsAFileBack() async {
        let made = makeComposer(undoMillis: 2000, sizes: ["a.bin": 10])
        let composer = made.composer
        let file = URL(fileURLWithPath: "/tmp/courier-composer-test/a.bin")
        composer.attach([file])
        await composer.submit()?.value
        XCTAssertEqual(composer.heldIDs, ["$sent1"])
        made.sender.undoResults["$sent1"] = .success(Draft(text: "a.bin", entities: [], replyTo: nil, threadRoot: nil))

        let undone = await composer.undoNewestHeld()
        XCTAssertTrue(undone)
        XCTAssertEqual(composer.attachments.map(\.url), [file], "the file is back, to send again")
        XCTAssertEqual(composer.text, "", "its name is not text")

        // A file sent as a reply comes back with its reply chip.
        let quoted = QuotedMessage(eventID: "$q", senderName: "Ann", mine: false, text: "q", kind: .text)
        composer.startReply(to: quoted)
        await composer.submit()?.value
        XCTAssertEqual(made.sender.fileSends.count, 2)
        made.sender.undoResults["$sent2"] = .success(Draft(text: "a.bin", entities: [], replyTo: "$q", threadRoot: nil))
        let again = await composer.undoNewestHeld()
        XCTAssertTrue(again)
        XCTAssertEqual(composer.attachments.map(\.url), [file])
        XCTAssertEqual(composer.replyTarget, quoted)
    }

    func testUndoWithNoAnswerFindsOutWhatHappened() async {
        let quoted = QuotedMessage(eventID: "$q", senderName: "Ann", mine: false, text: "q", kind: .text)
        /// One held message, "kept", bold and a reply; ⌘Z's call is gated, and its answer lost or refused.
        func held(_ failure: EngineError, status: StatusLine?) async -> Made {
            let made = makeComposer(undoMillis: 5000)
            made.composer.startReply(to: quoted)
            made.composer.text = "kept"
            made.composer.toggle(.bold, in: NSRange(location: 0, length: 4))
            await made.composer.submit()?.value
            made.sender.undoResults["$sent1"] = .failure(failure)
            if let status { made.sender.statuses["$sent1"] = status }
            made.sender.undoGate.close()
            let undo = Task { await made.composer.undoNewestHeld() }
            await made.sender.undoGate.arrived(1)
            XCTAssertEqual(made.composer.heldIDs, [])
            made.sender.undoGate.open()
            _ = await undo.value
            XCTAssertEqual(made.sender.statusLookups, ["$sent1"], "it asks what happened to it")
            return made
        }

        // The engine undid it, but the answer was lost: it is gone, so the copy kept here comes back.
        var made = await held(.timedOut, status: nil)
        XCTAssertEqual(made.composer.text, "kept")
        XCTAssertEqual(made.composer.entities, [bold(0, 4)])
        XCTAssertEqual(made.composer.replyTarget, quoted)
        XCTAssertEqual(made.composer.toast?.message, "Message unsent from Courier")
        XCTAssertEqual(made.composer.heldIDs, [])

        // Not found when undone: the same.
        made = await held(.rpc(.notFound, message: "gone", reason: nil), status: nil)
        XCTAssertEqual(made.composer.text, "kept")
        XCTAssertEqual(made.composer.toast?.message, "Message unsent from Courier")

        // Still held: it can be undone again.
        made = await held(.disconnected, status: .queued)
        XCTAssertEqual(made.composer.text, "")
        XCTAssertEqual(made.composer.heldIDs, ["$sent1"])
        XCTAssertEqual(made.composer.toast?.message, "Courier’s engine didn’t answer. The message is still queued: undo it again.")
        made.sender.undoResults["$sent1"] = .success(Draft(text: "kept", entities: [], replyTo: nil, threadRoot: nil))
        let retried = await made.composer.undoNewestHeld()
        XCTAssertTrue(retried)
        XCTAssertEqual(made.composer.text, "kept")

        // It went, or it failed: said as Ruling 32 says it, and nothing comes back.
        made = await held(.timedOut, status: .sent)
        XCTAssertEqual(made.composer.toast?.message, "Already sent")
        XCTAssertEqual(made.composer.text, "")
        made = await held(.timedOut, status: .notSent(.notConnected))
        XCTAssertEqual(made.composer.toast?.message, "Too late to undo, and it wasn’t sent. Retry it in the chat.")
        XCTAssertEqual(made.composer.text, "")
        XCTAssertEqual(made.composer.heldIDs, [])
    }

    func testUndoWhoseOutcomeCantBeToldYetSettlesOnTheNextRead() async {
        // The answer is lost and so is the lookup: nothing is restored or claimed yet.
        let made = makeComposer(undoMillis: 5000)
        made.composer.text = "kept"
        await made.composer.submit()?.value
        made.sender.undoResults["$sent1"] = .failure(.timedOut)
        made.sender.statusErrors = ["$sent1"]
        _ = await made.composer.undoNewestHeld()
        XCTAssertEqual(made.composer.text, "")
        XCTAssertEqual(made.composer.toast?.message, "Courier’s engine did not answer in time.")
        XCTAssertEqual(made.composer.heldIDs, [])

        // The next timeline read shows it still queued: it is held again.
        made.composer.updateHeld(from: items([event("$sent1", body: "kept", status: .queued, at: 0)]))
        XCTAssertEqual(made.composer.heldIDs, ["$sent1"])

        // Again, and this time the timeline no longer has it: a lookup finds it gone, and the text comes back.
        _ = await made.composer.undoNewestHeld()
        XCTAssertEqual(made.composer.heldIDs, [])
        made.sender.statusErrors = []
        made.composer.updateHeld(from: items([event("$other", body: "x", at: 0)]))
        await made.composer.waitForHeldChecks()
        XCTAssertEqual(made.composer.text, "kept")
        XCTAssertEqual(made.composer.toast?.message, "Message unsent from Courier")

        // Shown sent by a later read: settled, and nothing comes back.
        let sent = makeComposer(undoMillis: 5000)
        sent.composer.text = "went"
        await sent.composer.submit()?.value
        sent.sender.undoResults["$sent1"] = .failure(.timedOut)
        sent.sender.statusErrors = ["$sent1"]
        _ = await sent.composer.undoNewestHeld()
        sent.composer.updateHeld(from: items([event("$sent1", body: "went", status: .sent, at: 0)]))
        XCTAssertEqual(sent.composer.toast?.message, "Already sent")
        XCTAssertEqual(sent.composer.text, "")
        XCTAssertEqual(sent.composer.heldIDs, [])
    }

    func testHeldThreadRepliesLeaveWhenTheirWindowEnds() async {
        let made = makeComposer(undoMillis: 2000, features: slack, network: "slack")
        let composer = made.composer
        composer.startThread("$root")
        composer.text = "in the thread"
        await composer.submit()?.value
        XCTAssertEqual(composer.heldIDs, ["$sent1"])

        // The chat's timeline leaves thread replies out: that says nothing about it.
        composer.updateHeld(from: items([event("$root", mine: false, body: "root", at: 0)]))
        XCTAssertEqual(composer.heldIDs, ["$sent1"], "still in its window")

        // Past its window (and a margin), it has gone: ⌘Z is the text view's again.
        made.clock.now = made.clock.now.addingTimeInterval(10)
        composer.updateHeld(from: items([event("$root", mine: false, body: "root", at: 0)]))
        XCTAssertEqual(composer.heldIDs, [])
        let undone = await composer.undoNewestHeld()
        XCTAssertFalse(undone)
        XCTAssertEqual(made.sender.undos, [])

        // Within its window, too late anyway: its status is read in its thread (Ruling 32).
        composer.text = "another"
        await composer.submit()?.value
        made.sender.undoResults["$sent2"] = .failure(.rpc(.alreadySent, message: "already sent", reason: nil))
        made.sender.statuses["$sent2"] = .sent
        _ = await composer.undoNewestHeld()
        XCTAssertEqual(made.sender.statusThreads, ["$root"])
        XCTAssertEqual(composer.toast?.message, "Already sent")
    }

    func testUndoAfterItWentSaysSo() async {
        let made = makeComposer(undoMillis: 2000)
        let composer = made.composer
        for word in ["one", "two", "three"] {
            composer.text = word
            await composer.submit()?.value
        }
        XCTAssertEqual(composer.heldIDs, ["$sent1", "$sent2", "$sent3"])
        let late = EngineError.rpc(.alreadySent, message: "already sent", reason: nil)
        for id in composer.heldIDs { made.sender.undoResults[id] = .failure(late) }
        made.sender.statuses = ["$sent3": .sent, "$sent2": .notSent(.notConnected), "$sent1": .sending]
        type("typing on", into: composer)

        // It went: "Already sent", and nothing changes.
        var undone = await composer.undoNewestHeld()
        XCTAssertTrue(undone)
        XCTAssertEqual(composer.toast?.message, "Already sent")
        XCTAssertEqual(composer.text, "typing on")
        XCTAssertEqual(composer.heldIDs, ["$sent1", "$sent2"])

        // It didn't go (Ruling 32): never "Already sent"; the chat's Retry stands.
        undone = await composer.undoNewestHeld()
        XCTAssertTrue(undone)
        XCTAssertEqual(composer.toast?.message, "Too late to undo, and it wasn’t sent. Retry it in the chat.")
        XCTAssertEqual(composer.text, "typing on")

        // On its way: neither.
        undone = await composer.undoNewestHeld()
        XCTAssertEqual(composer.toast?.message, "Too late to undo. Check the message in the chat.")
        XCTAssertEqual(composer.text, "typing on")
        XCTAssertEqual(composer.heldIDs, [])
        XCTAssertEqual(made.sender.statusLookups, ["$sent3", "$sent2", "$sent1"])
    }

    func testUndoRacingTheHoldsEndEndsOneWay() async {
        // The undo wins: the text comes back once, however the timeline and ⌘Z move meanwhile.
        let won = makeComposer(undoMillis: 2000)
        won.composer.text = "mine"
        await won.composer.submit()?.value
        won.sender.undoResults["$sent1"] = .success(Draft(text: "mine", entities: [], replyTo: nil, threadRoot: nil))
        won.sender.undoGate.close()
        let first = Task { await won.composer.undoNewestHeld() }
        await won.sender.undoGate.arrived(1)
        XCTAssertEqual(won.composer.heldIDs, [], "the one being undone can't be undone twice")
        won.composer.updateHeld(from: items([event("$sent1", body: "mine", status: .queued, at: 0)]))
        XCTAssertEqual(won.composer.heldIDs, [], "a timeline read before the answer doesn't bring it back")
        if !won.composer.heldIDs.isEmpty { won.sender.undoGate.open() } // fail, rather than wait at the gate
        let second = await won.composer.undoNewestHeld()
        XCTAssertFalse(second, "a second ⌘Z finds nothing held")
        won.sender.undoGate.open()
        let firstUndone = await first.value
        XCTAssertTrue(firstUndone)
        won.composer.updateHeld(from: items([event("$sent1", body: "mine", status: .queued, at: 0)]))
        XCTAssertEqual(won.composer.heldIDs, [], "nor one read after it")
        XCTAssertEqual(won.composer.text, "mine", "back exactly once")
        XCTAssertEqual(won.sender.undos, ["$sent1"])

        // The hold's end wins: the engine says it already went, and nothing comes back.
        let lost = makeComposer(undoMillis: 2000)
        lost.composer.text = "gone"
        await lost.composer.submit()?.value
        lost.sender.undoResults["$sent1"] = .failure(.rpc(.alreadySent, message: "already sent", reason: nil))
        lost.sender.statuses = ["$sent1": .sent]
        lost.sender.undoGate.close()
        let racing = Task { await lost.composer.undoNewestHeld() }
        await lost.sender.undoGate.arrived(1)
        lost.composer.updateHeld(from: items([event("$sent1", body: "gone", status: .sent, at: 0)]))
        lost.sender.undoGate.open()
        _ = await racing.value
        XCTAssertEqual(lost.composer.text, "", "never both: it went, so it is not back")
        XCTAssertEqual(lost.composer.toast?.message, "Already sent")
        XCTAssertEqual(lost.composer.heldIDs, [])
    }

    func testHeldIDsFollowTheTimeline() {
        let made = makeComposer(undoMillis: 2000)
        made.composer.updateHeld(from: items([
            event("$1", status: .queued, at: 0), event("$2", mine: false, at: 500), event("$3", status: .queued, at: 1000),
        ]))
        XCTAssertEqual(made.composer.heldIDs, ["$1", "$3"], "held after a restart: from the timeline, newest last")
        made.composer.updateHeld(from: items([event("$1", status: .sent, at: 0), event("$3", status: .queued, at: 1000)]))
        XCTAssertEqual(made.composer.heldIDs, ["$3"], "one that went is no longer held")
        made.composer.open("!b")
        XCTAssertEqual(made.composer.heldIDs, [], "another chat's")
        made.composer.open("!a")
        XCTAssertEqual(made.composer.heldIDs, ["$3"])
    }

    func testSendHeldNowWaitsForTheAnswer() async {
        let made = makeComposer(undoMillis: 10000)
        made.composer.text = "soon"
        await made.composer.submit()?.value
        made.sender.sendHeldGate.close()
        let sending = Task { await made.composer.sendHeldNow() }
        await made.sender.sendHeldGate.arrived(1)
        XCTAssertEqual(made.sender.heldSends, ["!a"])
        XCTAssertEqual(made.composer.heldIDs, ["$sent1"], "still held until the engine answers")
        made.sender.sendHeldGate.open()
        await sending.value
        XCTAssertEqual(made.composer.heldIDs, [])

        // A failed call leaves them held: they go when their windows end.
        made.composer.text = "later"
        await made.composer.submit()?.value
        made.sender.failures = [.disconnected]
        await made.composer.sendHeldNow()
        XCTAssertEqual(made.composer.heldIDs, ["$sent2"])
    }

    // MARK: Send later

    func testScheduleSendsDueAndCondition() async throws {
        let made = makeComposer()
        let composer = made.composer
        let due = now.addingTimeInterval(3600)
        type("tomorrow's news", into: composer)
        composer.toggle(.bold, in: NSRange(location: 0, length: 8))
        composer.startReply(to: QuotedMessage(eventID: "$q", senderName: "Ann", mine: false, text: "q", kind: .text))
        try await composer.schedule(at: due, condition: .always)
        XCTAssertEqual(made.sender.schedules, [.init(room: "!a", rich: RichText(text: "tomorrow's news",
                                                                                entities: [bold(0, 8)]),
                                                     replyTo: "$q", threadRoot: nil, due: due, condition: .always)])
        XCTAssertEqual(composer.text, "")
        XCTAssertNil(composer.replyTarget)
        XCTAssertEqual(made.sender.sends, [], "scheduled, not sent")

        // Without the plan: "Available with a plan", and nothing goes.
        let denied = makeComposer(denied: [.sendLater])
        denied.composer.text = "later"
        try await denied.composer.schedule(at: due, condition: .ifNoReply)
        XCTAssertEqual(denied.sender.schedules, [])
        XCTAssertEqual(denied.composer.toast?.message, "Available with a plan")
        XCTAssertEqual(denied.composer.text, "later")

        // Too long for the chat: refused here, with why.
        var short = whatsApp
        short.maxTextLength = 4
        let long = makeComposer(features: short)
        long.composer.text = "too long"
        try await long.composer.schedule(at: due, condition: .ifNoReply)
        XCTAssertEqual(long.sender.schedules, [])
        XCTAssertEqual(long.composer.notice, .textTooLong)

        // Refused by the engine: the text stays, and the caller hears why.
        made.sender.failures = [.rpc(.badValue, message: "due_at", reason: nil)]
        composer.text = "bad time"
        do {
            try await composer.schedule(at: due, condition: .ifNoReply)
            XCTFail("the refusal is thrown")
        } catch {}
        XCTAssertEqual(composer.text, "bad time")
    }
}

extension ComposerModelTests {
    func testScheduleIsOneAtATime() async throws {
        let sender = FakeSender()
        let composer = ComposerModel(sender: sender, entitlement: AlwaysEntitled())
        composer.open("!a")
        composer.text = "later"
        let due = Date(timeIntervalSince1970: 1_900_000_000)
        sender.scheduleGate.close()
        let first = Task { try await composer.schedule(at: due, condition: .ifNoReply) }
        await sender.scheduleGate.arrived(1)
        XCTAssertTrue(composer.isScheduling)
        XCTAssertNil(composer.submit(), "Return while it is being scheduled sends nothing")
        XCTAssertEqual(composer.handleReturn(modifiers: []), .send)
        try await composer.schedule(at: due, condition: .always)
        sender.scheduleGate.open()
        try await first.value
        await composer.settle()
        XCTAssertEqual(sender.schedules.count, 1, "scheduled once")
        XCTAssertEqual(sender.sends, [], "and never also sent")
        XCTAssertFalse(composer.isScheduling)
        XCTAssertEqual(composer.text, "")
    }

    func testToastGoesToTheHookWhenSet() async {
        var said: [String] = []
        let denied = ComposerModel(sender: FakeSender())
        denied.open("!a")
        denied.text = "later"
        denied.onToast = { said.append($0) }
        try? await denied.schedule(at: Date(timeIntervalSince1970: 1_900_000_000), condition: .always)
        XCTAssertEqual(said, ["Available with a plan"], "the inbox's toast, the one place toasts show")
        XCTAssertNil(denied.toast)
    }

    func testThePlanIsDeniedUntilGiven() async {
        // A composer made without a plan holds nothing and schedules nothing: it fails closed.
        let store = TestDefaults()
        defer { store.remove() }
        let preferences = ComposerPreferences(defaults: store.defaults)
        preferences.undoSendMillis = 2000
        let sender = FakeSender()
        let composer = ComposerModel(sender: sender, preferences: preferences)
        composer.open("!a")
        composer.text = "not held"
        await composer.submit()?.value
        XCTAssertEqual(sender.sends.map(\.holdMillis), [0])
        composer.entitlement = AlwaysEntitled()
        composer.text = "held"
        await composer.submit()?.value
        XCTAssertEqual(sender.sends.map(\.holdMillis), [0, 2000])
    }

    func testOpeningAChatForgetsTheLastChatsFeatures() {
        let composer = ComposerModel(sender: FakeSender())
        composer.open("!a")
        composer.features = ChatFeatures(reply: true, mentionRoom: true, maxTextLength: 10, source: .stored)
        composer.network = "slack"
        composer.open("!b")
        XCTAssertEqual(composer.features, .noFeatures)
        XCTAssertEqual(composer.network, "")
    }
}

/// A clock a test moves.
final class MovableClock: @unchecked Sendable {
    var now: Date
    init(_ now: Date) { self.now = now }
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

    struct Send: Equatable {
        var room: String
        var rich: RichText
        var replyTo: String?
        var threadRoot: String?
        var holdMillis: Int
    }

    struct FileSend: Equatable {
        var room: String
        var name: String
        var threadRoot: String?
        var holdMillis: Int
    }

    struct Edit: Equatable {
        var eventID: String
        var rich: RichText
    }

    struct Schedule: Equatable {
        var room: String
        var rich: RichText
        var replyTo: String?
        var threadRoot: String?
        var due: Date
        var condition: SendLaterCondition
    }

    private let lock = NSLock()
    private var _calls: [Call] = []
    private var _sends: [Send] = []
    private var _fileSends: [FileSend] = []
    private var _edits: [Edit] = []
    private var _schedules: [Schedule] = []
    private var _undos: [String] = []
    private var _heldSends: [String?] = []
    private var _memberQueries: [String] = []
    private var _statusLookups: [String] = []
    private var _statusThreads: [String?] = []
    private var _statusErrors: Set<String> = []
    private var _savedDrafts: [String] = []
    private var _log: [String] = []
    private var _failures: [EngineError] = []
    private var _members: [Member] = []
    private var _undoResults: [String: Result<Draft, EngineError>] = [:]
    private var _statuses: [String: StatusLine] = [:]
    private var nextID = 0
    private var gate: CheckedContinuation<Void, Never>?
    private var gatedRoom: String?
    private var gateOpen = false
    /// message.undo waits here while it is closed.
    let undoGate = CallGate()
    /// message.sendHeld waits here while it is closed.
    let sendHeldGate = CallGate()
    /// message.schedule waits here while it is closed.
    let scheduleGate = CallGate()

    private func locked<T>(_ body: () -> T) -> T { lock.withLock(body) }

    var calls: [Call] {
        get { locked { _calls } }
        set { locked { _calls = newValue } }
    }

    var sends: [Send] { locked { _sends } }
    var fileSends: [FileSend] { locked { _fileSends } }
    var edits: [Edit] { locked { _edits } }
    var schedules: [Schedule] { locked { _schedules } }
    var undos: [String] { locked { _undos } }
    var heldSends: [String?] { locked { _heldSends } }
    var memberQueries: [String] { locked { _memberQueries } }
    var statusLookups: [String] { locked { _statusLookups } }
    /// The thread each status lookup read in, nil for the chat's own timeline.
    var statusThreads: [String?] { locked { _statusThreads } }

    /// Status lookups of these events fail as unanswered.
    var statusErrors: Set<String> {
        get { locked { _statusErrors } }
        set { locked { _statusErrors = newValue } }
    }
    var savedDrafts: [String] { locked { _savedDrafts } }
    /// Every call of the 4.3 methods, in order.
    var log: [String] { locked { _log } }

    /// The next calls fail with these errors, one each, in order.
    var failures: [EngineError] {
        get { locked { _failures } }
        set { locked { _failures = newValue } }
    }

    /// What room.members answers.
    var members: [Member] {
        get { locked { _members } }
        set { locked { _members = newValue } }
    }

    /// What message.undo answers, by event; one not here is not found.
    var undoResults: [String: Result<Draft, EngineError>] {
        get { locked { _undoResults } }
        set { locked { _undoResults = newValue } }
    }

    /// The status each event has now, as a timeline read would find it.
    var statuses: [String: StatusLine] {
        get { locked { _statuses } }
        set { locked { _statuses = newValue } }
    }

    /// The first text to `room` waits (after it is written down) until `openGate`. Named by chat, not "the first
    /// call", since sends to two chats may start in either order.
    func gateFirstText(in room: String) { locked { gatedRoom = room } }

    func openGate() {
        let waiting = locked { () -> CheckedContinuation<Void, Never>? in
            gateOpen = true
            defer { gate = nil }
            return gate
        }
        waiting?.resume()
    }

    private func nextFailure() -> EngineError? {
        locked { _failures.isEmpty ? nil : _failures.removeFirst() }
    }

    private func newID() -> String {
        locked {
            nextID += 1
            return "$sent\(nextID)"
        }
    }

    private func waitAtTextGate(_ roomID: String) async {
        let holds = locked { () -> Bool in
            guard gatedRoom == roomID else { return false }
            gatedRoom = nil
            return !gateOpen
        }
        guard holds else { return }
        await withCheckedContinuation { continuation in
            let resume = locked { () -> Bool in
                if gateOpen { return true }
                gate = continuation
                return false
            }
            if resume { continuation.resume() }
        }
    }

    func sendText(roomID: String, text: String, replyTo: String?) async throws {
        locked { _calls.append(.text(room: roomID, text: text, replyTo: replyTo)) }
        await waitAtTextGate(roomID)
        if let failure = nextFailure() { throw failure }
    }

    func sendFile(roomID: String, url: URL, size: Int64, replyTo: String?) async throws {
        locked { _calls.append(.file(room: roomID, name: url.lastPathComponent, size: size, replyTo: replyTo)) }
        if let failure = nextFailure() { throw failure }
    }

    func saveDraft(roomID: String, text: String) async throws {
        locked { _savedDrafts.append(text) }
    }

    func send(roomID: String, rich: RichText, replyTo: String?, threadRoot: String?, holdMillis: Int) async throws
        -> String {
        locked {
            _calls.append(.text(room: roomID, text: rich.text, replyTo: replyTo))
            _sends.append(Send(room: roomID, rich: rich, replyTo: replyTo, threadRoot: threadRoot, holdMillis: holdMillis))
            _log.append("send")
        }
        await waitAtTextGate(roomID)
        if let failure = nextFailure() { throw failure }
        return newID()
    }

    func sendFile(roomID: String, url: URL, size: Int64, replyTo: String?, threadRoot: String?, holdMillis: Int)
        async throws -> String {
        locked {
            _calls.append(.file(room: roomID, name: url.lastPathComponent, size: size, replyTo: replyTo))
            _fileSends.append(FileSend(room: roomID, name: url.lastPathComponent, threadRoot: threadRoot,
                                       holdMillis: holdMillis))
            _log.append("sendFile")
        }
        if let failure = nextFailure() { throw failure }
        return newID()
    }

    func edit(eventID: String, rich: RichText) async throws {
        locked {
            _edits.append(Edit(eventID: eventID, rich: rich))
            _log.append("edit")
        }
        if let failure = nextFailure() { throw failure }
    }

    func schedule(roomID: String, rich: RichText, replyTo: String?, threadRoot: String?, due: Date,
                  condition: SendLaterCondition) async throws {
        await scheduleGate.pass()
        if let failure = nextFailure() { throw failure }
        locked {
            _schedules.append(Schedule(room: roomID, rich: rich, replyTo: replyTo, threadRoot: threadRoot, due: due,
                                       condition: condition))
            _log.append("schedule")
        }
    }

    func undo(eventID: String) async throws -> Draft {
        locked {
            _undos.append(eventID)
            _log.append("undo")
        }
        await undoGate.pass()
        let result = locked { _undoResults[eventID] }
        switch result {
        case let .success(draft): return draft
        case let .failure(error): throw error
        case nil: throw EngineError.rpc(.notFound, message: "not found", reason: nil)
        }
    }

    func sendHeld(roomID: String?) async throws {
        locked {
            _heldSends.append(roomID)
            _log.append("sendHeld")
        }
        await sendHeldGate.pass()
        if let failure = nextFailure() { throw failure }
    }

    func members(roomID: String, query: String) async throws -> [Member] {
        locked {
            _memberQueries.append("\(roomID) \(query)")
            return _members
        }
    }

    func status(of eventID: String, in roomID: String, thread: String?) async throws -> StatusLine? {
        let fails = locked { () -> Bool in
            _statusLookups.append(eventID)
            _statusThreads.append(thread)
            return _statusErrors.contains(eventID)
        }
        if fails { throw EngineError.timedOut }
        return locked { _statuses[eventID] }
    }
}

/// A gate a fake's call waits at while it is closed (it starts open). The test learns a call has reached it with
/// `arrived`, so it acts while the call is in flight with no sleep.
final class CallGate: @unchecked Sendable {
    private let lock = NSLock()
    private var isOpen = true
    private var waiting: [CheckedContinuation<Void, Never>] = []
    private var arrivals = 0
    private var watchers: [(count: Int, continuation: CheckedContinuation<Void, Never>)] = []

    func close() { lock.withLock { isOpen = false } }

    func open() {
        let resumed = lock.withLock { () -> [CheckedContinuation<Void, Never>] in
            isOpen = true
            defer { waiting = [] }
            return waiting
        }
        for continuation in resumed { continuation.resume() }
    }

    /// Called by the fake: counts the arrival, then waits while the gate is closed.
    func pass() async {
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            let (proceed, ready) = lock.withLock { () -> (Bool, [CheckedContinuation<Void, Never>]) in
                arrivals += 1
                let ready = watchers.filter { $0.count <= arrivals }.map(\.continuation)
                watchers.removeAll { $0.count <= arrivals }
                if isOpen { return (true, ready) }
                waiting.append(continuation)
                return (false, ready)
            }
            for watcher in ready { watcher.resume() }
            if proceed { continuation.resume() }
        }
    }

    /// Returns once `count` calls have reached the gate.
    func arrived(_ count: Int) async {
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            let now = lock.withLock { () -> Bool in
                if arrivals >= count { return true }
                watchers.append((count, continuation))
                return false
            }
            if now { continuation.resume() }
        }
    }
}

// MARK: - Task 12: a line at a block's edge, and a click on a held message

extension ComposerModelTests {
    /// Shift-Return as the text view does it: asks first, then types the break (or not), then the caret moves.
    private func newline(_ composer: ComposerModel) {
        let at = (composer.text as NSString).length
        guard composer.beginNewline(at: NSRange(location: at, length: 0)) else { return }
        type("\n", into: composer, at: at)
        composer.selectionChanged(to: NSRange(location: at + 1, length: 0))
    }

    func testANewLineAtTheEndOfAListGoesOnInIt() {
        let composer = makeComposer().composer
        type("milk", into: composer)
        composer.toggle(.bulletList, in: NSRange(location: 0, length: 0))
        XCTAssertEqual(composer.entities, [TextEntity(kind: .bulletList, offset: 0, length: 4)])

        newline(composer)
        type("eggs", into: composer)
        XCTAssertEqual(composer.text, "milk\neggs")
        XCTAssertEqual(composer.entities, [TextEntity(kind: .bulletList, offset: 0, length: 9)],
                       "the second item is in the list")
    }

    func testTwoNewLinesOnAnEmptyItemLeaveTheList() {
        let composer = makeComposer().composer
        type("milk", into: composer)
        composer.toggle(.bulletList, in: NSRange(location: 0, length: 0))
        newline(composer)
        newline(composer) // on the empty item: leaves the list, and adds no line
        XCTAssertEqual(composer.text, "milk\n", "the second Return types nothing")
        type("Thanks", into: composer)
        XCTAssertEqual(composer.text, "milk\nThanks")
        XCTAssertEqual(composer.entities, [TextEntity(kind: .bulletList, offset: 0, length: 4)],
                       "the line after the list is plain")
    }

    func testANewLineInAQuoteOrCodeBlockGoesOnInItAndPlainTextStaysPlain() {
        let composer = makeComposer().composer
        type("said", into: composer)
        composer.toggle(.blockquote, in: NSRange(location: 0, length: 4))
        newline(composer)
        type("so", into: composer)
        XCTAssertEqual(composer.entities, [TextEntity(kind: .blockquote, offset: 0, length: 7)])

        let plain = makeComposer().composer
        type("hello", into: plain)
        newline(plain)
        type("there", into: plain)
        XCTAssertEqual(plain.entities, [], "no block, nothing goes on")

        // In the middle of a block's line, the break splits it and both halves stay in.
        let middle = makeComposer().composer
        type("ab", into: middle)
        middle.toggle(.pre, in: NSRange(location: 0, length: 2))
        XCTAssertTrue(middle.beginNewline(at: NSRange(location: 1, length: 0)))
        type("\n", into: middle, at: 1)
        XCTAssertEqual(middle.entities, [TextEntity(kind: .pre, offset: 0, length: 3)])
    }

    func testClickingAHeldMessageUndoesThatOne() async {
        let made = makeComposer(undoMillis: 5000)
        let composer = made.composer
        type("first", into: composer)
        await composer.submit()?.value
        type("second", into: composer)
        await composer.submit()?.value
        XCTAssertEqual(composer.heldIDs, ["$sent1", "$sent2"])
        made.sender.undoResults["$sent1"] = .success(Draft(text: "first", entities: [], replyTo: nil, threadRoot: nil))

        let undone = await composer.undoHeld("$sent1")
        XCTAssertTrue(undone)
        XCTAssertEqual(made.sender.undos, ["$sent1"], "the one clicked, not the newest")
        XCTAssertEqual(composer.heldIDs, ["$sent2"])
        XCTAssertEqual(composer.text, "first")
        let unknown = await composer.undoHeld("$nope")
        XCTAssertFalse(unknown, "a message that isn't held undoes nothing")
        XCTAssertEqual(made.sender.undos, ["$sent1"])
    }

    func testAMentionPutInMovesTheCaretAfterIt() {
        let composer = makeComposer().composer
        type("hi @an and more", into: composer)
        composer.insertMention(Member(userID: "@ann:example.test", name: "Ann"), replacing: NSRange(location: 3, length: 3))
        XCTAssertEqual(composer.text, "hi @Ann and more")
        XCTAssertEqual(composer.caretRequest?.location, 7, "after the mention, where typing goes on")
    }
}
