// Copyright 2026 VitruvianSoftware
// SPDX-License-Identifier: AGPL-3.0-or-later

import AppKit
import CourierCore
import SwiftUI
import XCTest

@testable import Courier

/// A render harness for Task 12's views: each is drawn light and dark to PNGs for a person to look at
/// (Snapshot.directory). The asserts check only that the view drew something of a sensible size; how it looks is for
/// the eye, and nothing here fails on a broken layout.
@MainActor
final class ViewSnapshotTests: XCTestCase {
    private var suites: [String] = []

    override func tearDown() async throws {
        for suite in suites { UserDefaults.standard.removePersistentDomain(forName: suite) }
        suites = []
    }

    private func defaults() -> UserDefaults {
        let name = "courier.snapshots.\(UUID().uuidString)"
        suites.append(name)
        return UserDefaults(suiteName: name)!
    }

    /// An app model whose engine never starts: the models it feeds read nothing.
    private func offlineApp() -> AppModel {
        AppModel(supervisor: EngineSupervisor(
            enginePath: "/nonexistent/courier-engine",
            dataDir: FileManager.default.temporaryDirectory.appendingPathComponent("courier-snapshots"),
            environment: [:], launcher: FoundationProcessLauncher()))
    }

    private func timeline(_ items: [TimelineItem], ui: MessageUI? = nil, actions: Courier.MessageActions? = nil,
                          sent: String? = nil) -> some View {
        let ui = ui ?? MessageUI()
        let actions = actions ?? Courier.MessageActions()
        return VStack(spacing: 0) {
            ForEach(items) { item in
                TimelineItemView(item: item, isSelected: false, showsSent: item.id == sent, actions: actions, ui: ui)
            }
        }
        .padding(14)
    }

    private func check(_ sizes: [NSSize], file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertEqual(sizes.count, 2, file: file, line: line)
        for size in sizes {
            XCTAssertGreaterThan(size.width, 100, file: file, line: line)
            XCTAssertGreaterThan(size.height, 30, file: file, line: line)
        }
    }

    // MARK: Bubbles

    func testBubblesWithEveryFormattingKind() throws {
        let events = [
            Fixture.text("$1", "fallback", mine: false, ts: 30, html: Fixture.formattedHTML),
            Fixture.text("$2", "fallback", mine: true, ts: 20, html: Fixture.formattedHTML, bookmarked: true),
        ]
        let ui = MessageUI()
        ui.revealed = ["$2"] // the second's spoiler was clicked
        check(try Snapshot.render("bubble-formatting", width: 620) { timeline(Fixture.items(events), ui: ui, sent: "$2") })
    }

    func testPolls() throws {
        let one = PollTally(question: "Where shall we eat on Friday?", options: [
            PollOption(id: "a", text: "The noodle place", votes: 3), PollOption(id: "b", text: "Pizza", votes: 1),
            PollOption(id: "c", text: "Somewhere new", votes: 0),
        ], maxSelections: 1, voters: 4, mine: ["a"], ended: false)
        let many = PollTally(question: "Which days work?", options: [
            PollOption(id: "m", text: "Monday", votes: 2), PollOption(id: "t", text: "Tuesday", votes: 1),
            PollOption(id: "w", text: "Wednesday", votes: 2),
        ], maxSelections: 3, voters: 3, mine: ["m", "w"], ended: true)
        let events = [Fixture.poll("$p1", mine: false, ts: 40, tally: one),
                      Fixture.poll("$p2", mine: true, ts: 30, tally: many)]
        check(try Snapshot.render("poll", width: 560) { timeline(Fixture.items(events)) })
    }

    func testThreadRootAndQueuedAndEditedBubbles() throws {
        let events = [
            Fixture.text("$root", "Who can bring the projector?", mine: false, ts: 60,
                         thread: ThreadSummary(replies: 3, lastTS: Fixture.millis(5),
                                               lastSenders: ["Bo Example", "Cy Example", "Ann Example"])),
            Fixture.text("$edited", "Meet at nine", mine: true, ts: 50),
            Fixture.edit("$e1", of: "$edited", "Meet at half past nine", ts: 45),
            Fixture.edit("$e2", of: "$edited", "Meet at ten", ts: 40, status: .failed),
            Fixture.text("$late", "This one never went", mine: true, ts: 10, status: .failed, reason: "not sent"),
            Fixture.text("$held", "On my way!", mine: true, ts: 1, status: .queued),
        ]
        let ui = MessageUI()
        ui.historyOpen = ["$edited"]
        ui.versions["$edited"] = [Version(body: "Meet at nine", ts: Fixture.millis(50)),
                                  Version(body: "Meet at half past nine", ts: Fixture.millis(45))]
        var actions = Courier.MessageActions()
        actions.undoHeld = { _ in }
        actions.openThread = { _ in }
        check(try Snapshot.render("thread-queued-edited", width: 560) {
            timeline(Fixture.items(events), ui: ui, actions: actions)
        })
    }

    func testTimerNoteAndCountdown() throws {
        let conversation = ConversationModel(appModel: offlineApp(), now: { Fixture.now },
                                             locale: Locale(identifier: "en_US"))
        let events = [
            Fixture.text("$1", "This goes in an hour and a half", mine: true, ts: 3,
                         expiresAt: Fixture.millis(-90)),
            Fixture.timerNote("$n", mine: true, ts: 2, timerMS: 86_400_000),
            Fixture.timerNote("$m", mine: false, ts: 1, timerMS: 0),
        ]
        var actions = Courier.MessageActions()
        actions.timerNote = { conversation.timerChangeNote(for: $0) }
        actions.disappearsIn = { conversation.disappearsIn($0) }
        check(try Snapshot.render("timer-note", width: 560) {
            timeline(Fixture.items(events), actions: actions, sent: "$1")
        })
    }

    func testCallNotes() throws {
        let events = [
            Fixture.text("$1", "Sorry, call you back in five", mine: true, ts: 1),
            Fixture.callNote("$c4", mine: true, ts: 2, body: "Call missed", state: "missed", media: "voice"),
            Fixture.callNote("$c3", mine: false, ts: 3, body: "Call ended", state: "ended", media: ""),
            Fixture.callNote("$c2", mine: false, ts: 4, body: "Video call missed", state: "missed", media: "video"),
            Fixture.callNote("$c1", mine: false, ts: 5, body: "Incoming call. Use the WhatsApp app to answer.",
                             state: "ringing", media: ""),
        ]
        check(try Snapshot.render("call-notes", width: 560) {
            timeline(Fixture.items(events), sent: "$1")
        })
    }

    // MARK: The menu

    func testMessageMenu() throws {
        let messages = Fixture.messages([
            Fixture.text("$1", "Meet at nine, see https://example.test", mine: true, ts: 30),
            Fixture.edit("$e", of: "$1", "Meet at ten, see https://example.test", ts: 25),
        ])
        let message = try XCTUnwrap(messages.first)
        let sections = MessageMenu.sections(
            for: message, available: CourierCore.MessageActions.available(for: message, in: Fixture.features,
                                                              network: "whatsapp", now: Fixture.now),
            features: Fixture.features, disappearsIn: "Disappears in 6 days, 23 hours", time: { _ in "Oct 20, 1:30 PM" })
        check(try Snapshot.render("message-menu", width: 320) {
            MessageMenuList(sections: sections) { _ in }
                .background(RoundedRectangle(cornerRadius: 8).fill(.background))
                .padding(10)
        })
    }

    // MARK: The composer

    private func composer(text: String, entities: [TextEntity] = []) -> ComposerModel {
        let composer = ComposerModel(draftDelay: 0, sleep: { _ in }, now: { Fixture.now })
        composer.open(Fixture.room)
        composer.features = Fixture.features
        composer.network = "whatsapp"
        composer.text = text
        composer.entities = entities
        return composer
    }

    func testComposerWithTheFormattingBar() throws {
        let preferences = ComposerPreferences(defaults: defaults())
        let model = composer(text: "Ship it on Friday, then celebrate",
                             entities: [TextEntity(kind: .bold, offset: 11, length: 6)])
        check(try Snapshot.render("composer-formatting", width: 620, prepare: { host in
            // Select "Friday", as a person would, so the bar shows.
            host.first(PlainTextView.self)?.setSelectedRange(NSRange(location: 11, length: 6))
        }) {
            ComposerView(composer: model, preferences: preferences, textHeight: .constant(ComposerTextView.minimumHeight),
                         menus: ComposerMenus(sendLater: {}, createPoll: {}, pollsUnavailable: nil))
        })
    }

    func testComposerEditingAList() throws {
        let preferences = ComposerPreferences(defaults: defaults())
        let model = composer(text: "")
        let original = Fixture.messages([Fixture.text("$1", "Bring:\nplates\ncups", mine: true, ts: 2)])[0]
        model.startEditing(original)
        model.entities = [TextEntity(kind: .bulletList, offset: 7, length: 11),
                          TextEntity(kind: .link, offset: 0, length: 5, url: "https://example.test")]
        check(try Snapshot.render("composer-editing", width: 620) {
            ComposerView(composer: model, preferences: preferences, textHeight: .constant(84),
                         menus: ComposerMenus(sendLater: {}, createPoll: {}, pollsUnavailable: nil))
        })
    }

    func testMentionPicker() throws {
        check(try Snapshot.render("mention-picker", width: 400) {
            MentionPicker(members: [Member(userID: "@room", name: "room"),
                                    Member(userID: "@ann:courier.local", name: "Ann Example"),
                                    Member(userID: "@bo:courier.local", name: "Bo Example")], index: 1) { _ in }
                .padding(10)
        })
    }

    // MARK: Pickers and panes

    func testSendLaterPicker() throws {
        let preferences = ComposerPreferences(defaults: defaults())
        let model = composer(text: "See you there")
        check(try Snapshot.render("send-later", width: 340) {
            SendLaterPicker(composer: model, preferences: preferences, done: {}, now: Fixture.now)
        })
    }

    func testScheduledStrip() throws {
        let due = Fixture.millis(-24 * 60)
        let messages = [
            ScheduledMessage(outboxID: 1, roomID: Fixture.room, text: "Happy birthday!", dueAt: due,
                             condition: .always, state: .waiting, setAt: Fixture.millis(10)),
            ScheduledMessage(outboxID: 2, roomID: Fixture.room, text: "Did you get a chance to look?",
                             dueAt: Fixture.millis(30), condition: .ifNoReply, state: .canceled,
                             setAt: Fixture.millis(600)),
            ScheduledMessage(outboxID: 3, roomID: Fixture.room, text: "Good morning", dueAt: Fixture.millis(300),
                             condition: .always, state: .missed, setAt: Fixture.millis(900)),
        ]
        check(try Snapshot.render("scheduled-strip", width: 620) {
            ScheduledList(messages: messages, actions: ScheduledActions(), isOpen: true)
        })
    }

    func testPollCreator() throws {
        var draft = PollDraft()
        draft.question = "Where shall we eat?"
        draft.options = ["Noodles", "Pizza", ""]
        check(try Snapshot.render("poll-creator", width: 380) {
            PollCreatorWindow(features: PollFeatures(maxOptions: 12, optionMaxLength: 100), create: { _ in true },
                              close: {}, draft: draft)
        })
    }

    func testMessagesSettingsPane() throws {
        let store = defaults()
        let preferences = ComposerPreferences(defaults: store)
        preferences.undoSendMillis = 5000
        let replies = QuickReplies(defaults: store)
        try replies.add(title: "omw", text: "On my way, {first_name}!")
        try replies.add(title: "thanks", text: "Thank you so much, that really helps.")
        check(try Snapshot.render("settings-messages", width: 560, height: 780) {
            MessagesSettingsPane(preferences: preferences, quickReplies: replies, isEntitled: { _ in true })
        })
        check(try Snapshot.render("settings-messages-no-plan", width: 560, height: 780) {
            MessagesSettingsPane(preferences: ComposerPreferences(defaults: defaults()),
                                 quickReplies: QuickReplies(defaults: defaults()), isEntitled: { _ in false })
        })
    }
}
