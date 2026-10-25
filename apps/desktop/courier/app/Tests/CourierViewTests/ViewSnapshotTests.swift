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
        // One-to-one: no name beside a call (the default actions name no one).
        check(try Snapshot.render("call-notes", width: 560) {
            timeline(Fixture.items(events), sent: "$1")
        })
        // In a group: the caller's name beside theirs.
        var group = Courier.MessageActions()
        group.callCaller = { CallNote.caller(of: $0, direct: false) }
        check(try Snapshot.render("call-notes-group", width: 560) {
            timeline(Fixture.items(events), actions: group, sent: "$1")
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
        check(try Snapshot.render("settings-messages", width: 560, height: 980) {
            MessagesSettingsPane(preferences: preferences, quickReplies: replies, isEntitled: { _ in true },
                                 conversation: conversation(preferences, entitled: true))
        })
        let none = ComposerPreferences(defaults: defaults())
        check(try Snapshot.render("settings-messages-no-plan", width: 560, height: 980) {
            MessagesSettingsPane(preferences: none, quickReplies: QuickReplies(defaults: defaults()),
                                 isEntitled: { _ in false }, conversation: conversation(none, entitled: false))
        })
    }

    // MARK: Receipts, typing, Incognito and accounts (4.4)

    /// A conversation that reads its settings from `preferences` and has the plan or not, for the views that ask it
    /// whether Incognito is on.
    private func conversation(_ preferences: ComposerPreferences, entitled: Bool) -> ConversationModel {
        let conversation = ConversationModel(appModel: offlineApp(), now: { Fixture.now },
                                             locale: Locale(identifier: "en_US"))
        conversation.preferences = preferences
        conversation.isEntitled = { _ in entitled }
        return conversation
    }

    private static let bo = "@bo:courier.local"

    /// The line under my newest message: Delivered and Seen with its time one-to-one; Seen by one, and by one and
    /// others, in a group; and on every waiting message, "Waiting to send" or the no-account line, with Don't Send.
    func testStatusLines() throws {
        func chat(_ mine: Event) -> [Event] {
            [Fixture.text("$1", "Are we still on for Friday?", mine: false, ts: 20),
             Fixture.text("$2", "Yes! See you at the noodle place", mine: true, ts: 12),
             mine]
        }
        let delivered = Fixture.text("$3", "I’ll book a table for four", mine: true, ts: 10, delivered: true)
        check(try Snapshot.render("status-delivered", width: 560) {
            timeline(Fixture.items(chat(delivered), isDirect: true), sent: "$3")
        })
        let seenAt = Fixture.text("$3", "I’ll book a table for four", mine: true, ts: 10, delivered: true,
                                  readBy: [Reader(userID: Fixture.ann, name: "Ann Example", ts: Fixture.millis(4))])
        check(try Snapshot.render("status-seen-time", width: 560) {
            timeline(Fixture.items(chat(seenAt), isDirect: true), sent: "$3")
        })
        let seenByOne = Fixture.text("$3", "I’ll book a table for four", mine: true, ts: 10,
                                     readBy: [Reader(userID: Fixture.ann, name: "Ana", ts: Fixture.millis(4))])
        check(try Snapshot.render("status-seen-by-one", width: 560) {
            timeline(Fixture.items(chat(seenByOne)), sent: "$3")
        })
        let seenByMany = Fixture.text("$3", "I’ll book a table for four", mine: true, ts: 10, readBy: [
            Reader(userID: Fixture.ann, name: "Ana", ts: Fixture.millis(3)),
            Reader(userID: Self.bo, name: "Bo Example", ts: Fixture.millis(4)),
            Reader(userID: "@cy:courier.local", name: "Cy Example", ts: Fixture.millis(5)),
        ])
        check(try Snapshot.render("status-seen-by-many", width: 560) {
            timeline(Fixture.items(chat(seenByMany)), sent: "$3")
        })

        var actions = Courier.MessageActions()
        actions.dontSend = { _ in }
        actions.waitingHelp = { StatusLine.waitingHelp(network: "whatsapp") }
        let waiting = [
            Fixture.text("$1", "Landing at six", mine: false, ts: 30),
            Fixture.text("$2", "Great, I’ll pick you up", mine: true, ts: 20, readBy: [
                Reader(userID: Fixture.ann, name: "Ann Example", ts: Fixture.millis(15))]),
            Fixture.text("$w1", "Running ten minutes late", mine: true, ts: 6, status: .waiting),
            Fixture.text("$w2", "Parked by the north door", mine: true, ts: 2, status: .waiting,
                         reason: StatusLine.noAccountReason),
        ]
        check(try Snapshot.render("status-waiting", width: 560) {
            timeline(Fixture.items(waiting, isDirect: true), actions: actions, sent: "$2")
        })
    }

    /// Who is typing, above the composer: one person by name, more as a count; nothing when no one is.
    func testTypingLine() throws {
        let preferences = ComposerPreferences(defaults: defaults())
        for (name, line) in [("typing-one", "Ana is typing…"), ("typing-many", "3 people are typing…")] {
            let model = composer(text: "")
            check(try Snapshot.render(name, width: 620) {
                VStack(spacing: 0) {
                    TypingLine(text: line)
                    ComposerView(composer: model, preferences: preferences,
                                 textHeight: .constant(ComposerTextView.minimumHeight))
                }
            })
        }
        // A long name is cut in the middle, on one line, keeping "is typing…".
        let model = composer(text: "")
        check(try Snapshot.render("typing-long-name", width: 300) {
            VStack(spacing: 0) {
                TypingLine(text: "Annabelle Example-Featherstonehaugh of the Hiking and Climbing Club is typing…")
                ComposerView(composer: model, preferences: preferences,
                             textHeight: .constant(ComposerTextView.minimumHeight))
            }
        })
    }

    /// VoiceOver hears the line when someone starts typing in the window in front, not on later changes.
    func testTypingLineIsAnnouncedOnlyWhenItAppearsInTheKeyWindow() {
        XCTAssertEqual(TypingLine.announcement(from: nil, to: "Ana is typing…", isKey: true), "Ana is typing…")
        XCTAssertNil(TypingLine.announcement(from: nil, to: "Ana is typing…", isKey: false), "a window behind")
        XCTAssertNil(TypingLine.announcement(from: "Ana is typing…", to: "2 people are typing…", isKey: true))
        XCTAssertNil(TypingLine.announcement(from: "Ana is typing…", to: nil, isKey: true), "stopping says nothing")
    }

    func testComposerWithTheIncognitoMark() throws {
        let preferences = ComposerPreferences(defaults: defaults())
        let model = composer(text: "Back in five")
        check(try Snapshot.render("composer-incognito", width: 620) {
            ComposerView(composer: model, preferences: preferences,
                         textHeight: .constant(ComposerTextView.minimumHeight), showsIncognitoMark: true)
        })
        // A narrow window: the box gives way, the mark keeps its words.
        let narrow = composer(text: "")
        check(try Snapshot.render("composer-incognito-narrow", width: 360) {
            ComposerView(composer: narrow, preferences: preferences,
                         textHeight: .constant(ComposerTextView.minimumHeight), showsIncognitoMark: true)
        })
    }

    /// Rows whose newest message is mine say how far it got (one tick sent, two delivered, two in colour seen); a
    /// chat on one of two accounts carries the account's tag.
    func testInboxRowWithTicksAndAccountTag() throws {
        let style = RowStyle(InboxPreferences(defaults: defaults()))
        let rows = [
            Fixture.row("!1", "Ann Example", ts: 2, preview: "See you at nine", mine: true, status: .seen),
            Fixture.row("!2", "Bo Example", ts: 15, preview: "I’ll bring the projector", mine: true, status: .delivered,
                        login: "+1 555 0102"),
            Fixture.row("!3", "Weekend Hikers", network: "signal", direct: false, ts: 60,
                        preview: "Who has the map?", mine: true, status: .sent),
            Fixture.row("!4", "Cy Example-Longname With A Very Long Name Indeed", ts: 90,
                        preview: "Thanks, that really helps", mine: true, status: .seen, login: "Work workspace"),
            Fixture.row("!5", "Dee Example", ts: 120, preview: "Sounds good", unread: 2, status: .seen,
                        login: "+1 555 0101"),
            Fixture.row("!6", "Eve Example", network: "telegram", ts: 200, preview: "Running late", mine: true),
        ]
        func list(_ rows: [InboxRow]) -> some View {
            VStack(spacing: 0) {
                ForEach(rows, id: \.roomID) { row in
                    InboxRowView(row: row, networkName: row.network, now: Fixture.now, style: style,
                                 isSelecting: false, isSelected: false, isHovered: false, hoverAct: {}, accept: {},
                                 decline: {}) { EmptyView() }
                        .padding(.horizontal, 10)
                        .padding(.vertical, 3)
                    Divider()
                }
            }
        }
        check(try Snapshot.render("inbox-rows-ticks", width: 340) { list(rows) })
        // The list at its narrowest (260 pt): names keep their room first, and a long account tag gives way.
        let narrow = rows + [
            Fixture.row("!7", "Fay Example", network: "slack", direct: false, ts: 300, preview: "Lunch?", mine: true,
                        status: .sent, login: "Hiking and Climbing Club of the Northern Valleys"),
        ]
        check(try Snapshot.render("inbox-rows-ticks-narrow", width: 260) { list(narrow) })
    }

    /// A banner names the account that needs the person when its network has two; the strip says "Starting…" for
    /// a network the engine hasn't started and names the account in its tooltip.
    func testAccountBannerAndStatusStrip() throws {
        let banners = [
            AccountBanner(network: "whatsapp", displayName: "WhatsApp", reason: .loggedOut, detail: "", action: .reconnect,
                          accountID: "a2", accountName: "+1 555 0102"),
            AccountBanner(network: "slack", displayName: "Slack", reason: .badCredentials, detail: "",
                          action: .reconnect, accountID: "s1"),
        ]
        let items = [
            AccountStatusItem(network: "signal", displayName: "Signal", isReconnecting: false, isStarting: true),
            AccountStatusItem(network: "whatsapp", displayName: "WhatsApp", isReconnecting: true, accountID: "a1",
                              accountName: "+1 555 0101"),
            AccountStatusItem(network: "whatsapp", displayName: "WhatsApp", isReconnecting: false, accountID: "a2",
                              accountName: "+1 555 0102"),
            AccountStatusItem(network: "telegram", displayName: "Telegram", isReconnecting: false),
        ]
        check(try Snapshot.render("account-banners-strip", width: 340) {
            VStack(spacing: 0) {
                AccountStatusStrip(items: items)
                ForEach(banners) { banner in AccountBannerView(banner: banner) {} }
            }
        })
    }

    /// Add a Network with WhatsApp linked twice, Google Messages once, Slack three times, Signal still starting and
    /// Telegram not linked: who each is linked as, Add Another Account…, and "Starting…" that can't be picked.
    func testAddNetworkWithTwoAccountsAndOneStarting() async throws {
        let accounts = [
            Account(network: "whatsapp", displayName: "WhatsApp", flows: ["qr", "phone"], state: .connected,
                    logins: [Login(accountID: "a1", remoteName: "+1 555 0101", state: .connected),
                             Login(accountID: "a2", remoteName: "+1 555 0102", state: .connected)]),
            Account(network: "signal", displayName: "Signal", flows: ["qr"], state: .starting,
                    logins: [Login(accountID: "s1", remoteName: "+1 555 0103", state: .starting)]),
            Account(network: "telegram", displayName: "Telegram", flows: ["phone", "qr"], state: .unconfigured),
            Account(network: "gmessages", displayName: "Google Messages", flows: ["google", "qr"], state: .connected,
                    logins: [Login(accountID: "g1", remoteName: "Pixel", state: .connected)]),
            Account(network: "slack", displayName: "Slack", flows: ["token"], state: .connected,
                    logins: [Login(accountID: "w1", remoteName: "Example Co", state: .connected),
                             Login(accountID: "w2", remoteName: "Hiking Club", state: .connected),
                             Login(accountID: "w3", remoteName: "", state: .connected)]),
        ]
        let caller = SnapshotLoginCaller()
        let login = LoginFlowModel(caller: caller, accounts: { accounts }, reloadAccounts: {},
                                   credentials: SnapshotCredentials(), builtInCredentials: { nil },
                                   restartEngine: {})
        login.showPicker()
        check(try Snapshot.render("add-network-accounts", width: 460) { AddNetworkView(login: login) })

        // Reconnect on one WhatsApp account signed in another (Ruling 11): the linked screen says both are kept.
        caller.finish = try JSONDecoder().decode(LoginStep.self, from: Data("""
        {"login_id": "l1", "step_id": "done", "type": "complete", "remote_name": "+1 555 0104",
         "account_id": "a4", "other_account": true}
        """.utf8))
        login.begin(network: "whatsapp", accountID: "a2")
        for _ in 0 ..< 200 where login.linkedNote == nil { await Task.yield() }
        XCTAssertNotNil(login.linkedNote, "the sign-in finished as another account")
        check(try Snapshot.render("add-network-linked-other", width: 460) { AddNetworkView(login: login) })
    }

    /// Settings ▸ Messages ▸ Privacy with Incognito on, and Settings ▸ Inbox with the typing notification.
    func testPrivacySettings() throws {
        let preferences = ComposerPreferences(defaults: defaults())
        preferences.incognito = true
        let on = conversation(preferences, entitled: true)
        XCTAssertTrue(on.incognitoIsOn)
        check(try Snapshot.render("settings-privacy", width: 560, height: 980) {
            MessagesSettingsPane(preferences: preferences, quickReplies: QuickReplies(defaults: defaults()),
                                 isEntitled: { _ in true }, conversation: on)
        })
        let app = offlineApp()
        let inboxPreferences = InboxPreferences(defaults: defaults())
        inboxPreferences.typingNotifications = true
        let inbox = InboxModel(appModel: app, preferences: inboxPreferences)
        check(try Snapshot.render("settings-inbox", width: 560, height: 1200) {
            InboxSettingsPane(preferences: inboxPreferences, labels: LabelsModel(appModel: app), inbox: inbox)
        })
    }

    /// Someone else's message in a group offers Reply Privately… after Reply in Thread…, and Mark as Unread in its
    /// own section after Bookmark, with its help.
    func testMessageMenuWithReplyPrivatelyAndMarkAsUnread() throws {
        let message = try XCTUnwrap(Fixture.messages([
            Fixture.text("$1", "Who can bring the projector?", mine: false, ts: 30),
        ]).first)
        let sections = MessageMenu.sections(
            for: message, available: CourierCore.MessageActions.available(
                for: message, in: Fixture.features, network: "whatsapp", now: Fixture.now, isDirect: false,
                networkRunning: true),
            features: Fixture.features, disappearsIn: nil, time: { _ in "Oct 20, 1:30 PM" })
        let titles = sections.flatMap { $0.map(\.title) }
        XCTAssertTrue(titles.contains("Reply Privately…"), "\(titles)")
        XCTAssertTrue(titles.contains("Mark as Unread"), "\(titles)")
        check(try Snapshot.render("message-menu-group", width: 320) {
            MessageMenuList(sections: sections) { _ in }
                .background(RoundedRectangle(cornerRadius: 8).fill(.background))
                .padding(10)
        })
    }

    // MARK: - Part 4.5a: Chat Info pane and membership rows

    func testChatInfoPaneDirectChatLightAndDark() throws {
        let info = Fixture.directChatInfo()
        let bookmarks = Fixture.chatInfoBookmarks()
        XCTAssertEqual(
            ChatInfoPane.localTimeText(for: "America/Los_Angeles", now: Fixture.now, locale: Locale(identifier: "en_US")),
            "7:00 AM local time"
        )
        XCTAssertNil(ChatInfoPane.localTimeText(for: "Invalid/Timezone", now: Fixture.now))
        XCTAssertNil(ChatInfoPane.localTimeText(for: "", now: Fixture.now))
        let sizes = try Snapshot.render("chat-info-direct", width: 280, height: 760) {
            ChatInfoPane(info: info, bookmarks: bookmarks, now: { Fixture.now })
        }
        XCTAssertEqual(sizes.count, 2)
        for size in sizes {
            XCTAssertGreaterThanOrEqual(size.width, 280)
        }
    }

    func testChatInfoPaneGroupWithAdminsLightAndDark() throws {
        let info = Fixture.groupChatInfoWithAdmins()
        let sizes = try Snapshot.render("chat-info-group-admins", width: 280, height: 640) {
            ChatInfoPane(info: info, bookmarks: [], now: { Fixture.now })
        }
        XCTAssertEqual(sizes.count, 2)
        for size in sizes {
            XCTAssertGreaterThanOrEqual(size.width, 280)
        }
    }

    func testTimelineMembershipRunRowLightAndDark() throws {
        let item = TimelineItem.membershipRun(
            id: "mrun-1",
            events: [],
            summary: "Alice and 2 others joined the group"
        )
        let sizes = try Snapshot.render("timeline-membership-run", width: 520, height: 120) {
            TimelineItemView(
                item: item, isSelected: false, isHighlighted: false, showsSent: false,
                actions: Courier.MessageActions(), ui: MessageUI()
            )
            .padding(16)
        }
        XCTAssertEqual(sizes.count, 2)
        let rowSizes = try Snapshot.render("timeline-membership-run", width: 520, height: 120) {
            MembershipRunRow(summary: "Alice and 2 others joined the group", isSelected: false)
                .padding(16)
        }
        XCTAssertEqual(rowSizes.count, 2)
    }

    func testEditGroupSheetAndReportSpamSheetLightAndDark() throws {
        let editableInfo = Fixture.groupChatInfoWithAdmins()
        let everyoneDraft = EditGroupDraft(info: editableInfo, initialScope: .forEveryone)
        check(try Snapshot.render("edit-group-for-everyone", width: 420, height: 380) {
            EditGroupSheet(draft: everyoneDraft, onSave: { _ in }, onResetLocalOverride: {}, onCancel: {})
        })

        let lockedInfo = Fixture.groupChatInfoJustForMeOnly()
        let justForMeDraft = EditGroupDraft(info: lockedInfo)
        XCTAssertEqual(justForMeDraft.scope, .justForMe)
        XCTAssertFalse(justForMeDraft.canEditForEveryone)
        check(try Snapshot.render("edit-group-just-for-me", width: 420, height: 340) {
            EditGroupSheet(draft: justForMeDraft, onSave: { _ in }, onResetLocalOverride: {}, onCancel: {})
        })

        let spamLeaveDraft = ReportSpamDraft(
            roomID: editableInfo.roomID,
            canLeave: true,
            canDelete: false,
            network: "whatsapp"
        )
        XCTAssertFalse(spamLeaveDraft.alsoLeaveOrDelete)
        check(try Snapshot.render("report-spam-leave-group", width: 380, height: 210) {
            ReportSpamSheet(draft: spamLeaveDraft, onReport: { _ in }, onCancel: {})
        })

        let spamDeleteDraft = ReportSpamDraft(
            roomID: "!dm-alice:courier.local",
            canLeave: false,
            canDelete: true,
            network: "whatsapp"
        )
        check(try Snapshot.render("report-spam-delete-chat", width: 380, height: 210) {
            ReportSpamSheet(draft: spamDeleteDraft, onReport: { _ in }, onCancel: {})
        })

        let candidates = Fixture.inviteCandidates()
        check(try Snapshot.render("add-participants-sheet", width: 420, height: 380) {
            AddParticipantsSheet(
                roomName: editableInfo.name,
                initialCandidates: candidates,
                initialSelectedIDs: ["@wa_carol:courier.local"],
                onSearch: { _ in candidates },
                onInvite: { _ in },
                onCancel: {}
            )
        })

        let bob = editableInfo.members[1]
        check(try Snapshot.render("participant-context-menu", width: 260, height: 180) {
            VStack(alignment: .leading, spacing: 4) {
                ParticipantContextMenu(
                    member: bob,
                    features: editableInfo.features,
                    onMessage: {},
                    onToggleAdmin: {},
                    onRemoveFromGroup: {},
                    onCopyUserID: {}
                )
            }
            .buttonStyle(.plain)
            .padding(12)
            .frame(width: 240, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: 8).fill(.background))
            .padding(10)
        })

        let aliceAdmin = editableInfo.members[0]
        check(try Snapshot.render("participant-context-menu-admin", width: 260, height: 180) {
            VStack(alignment: .leading, spacing: 4) {
                ParticipantContextMenu(
                    member: aliceAdmin,
                    features: editableInfo.features,
                    onMessage: {},
                    onToggleAdmin: {},
                    onRemoveFromGroup: {},
                    onCopyUserID: {}
                )
            }
            .buttonStyle(.plain)
            .padding(12)
            .frame(width: 240, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: 8).fill(.background))
            .padding(10)
        })

        let groupRow = InboxRow(
            roomID: editableInfo.roomID,
            network: editableInfo.network,
            name: editableInfo.name,
            avatarPath: "",
            isDirect: false,
            lastTS: Fixture.millis(1),
            preview: "See you at the trailhead",
            previewKind: .text,
            previewMine: false,
            unread: 0,
            muted: false
        )
        check(try Snapshot.render("chat-context-menu-group", width: 260, height: 180) {
            VStack(alignment: .leading, spacing: 6) {
                ChatRoomManagementMenuSection(row: groupRow, features: editableInfo.features)
            }
            .buttonStyle(.plain)
            .padding(12)
            .frame(width: 240, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: 8).fill(.background))
            .padding(10)
        })
    }

    // MARK: - Part 4.5a Task 11: Start New Chat, New Group, Blasts, and Merged Chats UI

    func testStartNewChatAndBlastViewLightAndDark() throws {
        let accounts = Fixture.startNewChatAccounts()
        let candidates = Fixture.startNewChatCandidates()

        // 1. New Chat (1:1 mode) with search results and "Look up <query> on <Network>" rows.
        var lookupDraft = StartNewChatDraft(accounts: accounts, candidates: candidates)
        lookupDraft.query = "+1 555-010-0199"
        check(try Snapshot.render("start-new-chat-results", width: 520, height: 480) {
            StartNewChatView(draft: lookupDraft)
        })

        // 2. Multi-select in New Group mode (2 recipients on the same WhatsApp account).
        var groupDraft = StartNewChatDraft(accounts: accounts, candidates: candidates, startsInMultiSelect: true)
        groupDraft.toggleRecipient(candidates[0])
        groupDraft.toggleRecipient(candidates[1])
        groupDraft.groupName = "Weekend Trail Crew"
        XCTAssertEqual(groupDraft.mode, .newGroup)
        XCTAssertTrue(groupDraft.isNewGroupEnabled)
        check(try Snapshot.render("start-new-chat-group", width: 520, height: 480) {
            StartNewChatView(draft: groupDraft)
        })

        // 3. Blast mode with the confirmation ("Send to 5 people on 3 networks?") and per-person results.
        var blastDraft = StartNewChatDraft(accounts: accounts, candidates: candidates, startsInMultiSelect: true)
        for candidate in candidates {
            blastDraft.toggleRecipient(candidate)
        }
        blastDraft.blastText = "Hey {recipient.firstName}, trail starts at 8 AM!"
        blastDraft.isConfirmingBlast = true
        blastDraft.applyBlastResults([
            BlastItemResult(roomID: "!dm-alice-wa:courier.local", eventID: "$1", status: "sent", error: ""),
            BlastItemResult(roomID: "!dm-bob-wa:courier.local", eventID: "$2", status: "sent", error: ""),
            BlastItemResult(roomID: "!dm-carol-sig:courier.local", eventID: "$3", status: "waiting", error: ""),
            BlastItemResult(roomID: "!dm-dan-tg:courier.local", eventID: "", status: "failed", error: "User blocked bot"),
            BlastItemResult(roomID: "!dm-erin-tg:courier.local", eventID: "$5", status: "sent", error: ""),
        ])
        XCTAssertEqual(blastDraft.mode, .blast)
        XCTAssertEqual(blastDraft.blastConfirmationText, "Send to 5 people on 3 networks?")
        check(try Snapshot.render("start-new-chat-blast-confirm", width: 520, height: 660) {
            StartNewChatView(draft: blastDraft)
        })
    }

    func testMergedChatInboxRowComposerAndEditorLightAndDark() throws {
        let style = RowStyle(InboxPreferences(defaults: defaults()))
        let merged = Fixture.mergedAlice()
        let directRows = Fixture.mergeableDirectRows()

        // 4. Merged inbox row with stacked network badges for each member network.
        check(try Snapshot.render("merged-inbox-row", width: 340) {
            VStack(spacing: 0) {
                InboxRowView(
                    row: directRows[0],
                    networkName: "WhatsApp",
                    mergedNetworks: merged.networks,
                    now: Fixture.now,
                    style: style,
                    isSelecting: false,
                    isSelected: true,
                    isHovered: false,
                    hoverAct: {},
                    accept: {},
                    decline: {}
                ) { EmptyView() }
                .padding(.horizontal, 10)
                .padding(.vertical, 3)
                Divider()
                InboxRowView(
                    row: directRows[3],
                    networkName: "WhatsApp",
                    now: Fixture.now,
                    style: style,
                    isSelecting: false,
                    isSelected: false,
                    isHovered: false,
                    hoverAct: {},
                    accept: {},
                    decline: {}
                ) { EmptyView() }
                .padding(.horizontal, 10)
                .padding(.vertical, 3)
            }
        })

        // 5. Merged composer pill showing active reply network and account, plus merged message bubbles with network badges.
        let preferences = ComposerPreferences(defaults: defaults())
        let model = composer(text: "See you at 8 AM!")
        check(try Snapshot.render("merged-composer-pill", width: 620) {
            ComposerView(
                composer: model,
                preferences: preferences,
                textHeight: .constant(ComposerTextView.minimumHeight),
                mergedChat: merged,
                activeReplyRoomID: "!dm-alice-wa:courier.local",
                activeReplyNetwork: "whatsapp",
                activeReplyAccountName: "+1 555-010-0101",
                onCycleReplyNetwork: {}
            )
        })

        var waEvent = Fixture.text("$m-wa", "Are we still on for Saturday?", mine: false, ts: 20, name: "Alice Example")
        waEvent.roomID = "!dm-alice-wa:courier.local"
        var sigEvent = Fixture.text("$m-sig", "Sent you the GPX track on Signal", mine: false, ts: 10, name: "Alice Example")
        sigEvent.roomID = "!dm-alice-sig:courier.local"
        var myReply = Fixture.text("$m-me", "Got it, replying on WhatsApp!", mine: true, ts: 5)
        myReply.roomID = "!dm-alice-wa:courier.local"
        var mergedActions = Courier.MessageActions()
        mergedActions.messageNetwork = { msg in
            switch msg.roomID {
            case "!dm-alice-wa:courier.local": "whatsapp"
            case "!dm-alice-sig:courier.local": "signal"
            default: "telegram"
            }
        }
        check(try Snapshot.render("merged-chat-bubbles", width: 560) {
            timeline(Fixture.items([waEvent, sigEvent, myReply], isDirect: true), actions: mergedActions, sent: "$m-me")
        })

        // 6. Merged chat editor sheet with automatic suggestion.
        let editorDraft = MergedChatEditorDraft(
            existingMerge: merged,
            suggestions: Fixture.mergeSuggestions(),
            availableDirectRooms: directRows
        )
        check(try Snapshot.render("merged-chat-editor-sheet", width: 480, height: 460) {
            MergedChatEditorSheet(draft: editorDraft)
        })
    }

    // MARK: - Part 4.5a Task 12: Sender Hover Card and Contacts Integration

    func testUserHoverCardAuthorizedAndDeniedLightAndDark() async throws {
        let member = Fixture.hoverCardMember()
        let sharedGroups = Fixture.hoverCardSharedGroups()

        // 1. Authorized + matched contact.
        let matchedStore = FakeContactsStore(status: .authorized, contacts: [Fixture.matchedAliceContact()])
        let matchedBridge = ContactsBridge(store: matchedStore)
        await matchedBridge.loadMatch(identifiers: member.identifiers, fallbackName: member.name)
        check(try Snapshot.render("user-hover-card-matched", width: 320) {
            UserHoverCard(
                member: member,
                network: "signal",
                sharedGroups: sharedGroups,
                contactsBridge: matchedBridge,
                now: Fixture.now
            )
        })

        // 2. Authorized + unmatched with Save to Contacts form.
        let unmatchedStore = FakeContactsStore(status: .authorized, contacts: [])
        let unmatchedBridge = ContactsBridge(store: unmatchedStore)
        await unmatchedBridge.loadMatch(identifiers: member.identifiers, fallbackName: member.name)
        check(try Snapshot.render("user-hover-card-unmatched", width: 320) {
            UserHoverCard(
                member: member,
                network: "signal",
                sharedGroups: sharedGroups,
                contactsBridge: unmatchedBridge,
                now: Fixture.now,
                initialShowSaveForm: true
            )
        })

        // 3. Denied state showing System Settings line and button.
        let deniedStore = FakeContactsStore(status: .denied, contacts: [])
        let deniedBridge = ContactsBridge(store: deniedStore)
        await deniedBridge.loadMatch(identifiers: member.identifiers, fallbackName: member.name)
        check(try Snapshot.render("user-hover-card-denied", width: 320) {
            UserHoverCard(
                member: member,
                network: "signal",
                sharedGroups: sharedGroups,
                contactsBridge: deniedBridge,
                now: Fixture.now
            )
        })
    }
}

/// A sign-in caller whose every sign-in finishes at once with `finish`.
private final class SnapshotLoginCaller: LoginCalling, @unchecked Sendable {
    var finish: LoginStep?

    func start(network: String, flow: String, another: Bool, accountID: String?) async throws -> LoginStep {
        guard let finish else { throw CancellationError() }
        return finish
    }

    func submit(loginID: String, values: [String: String]) async throws -> LoginStep { throw CancellationError() }
    func wait(loginID: String) async throws -> LoginStep { throw CancellationError() }
    func cancel(loginID: String) async throws {}
}

/// Nothing is kept: no snapshot touches the Keychain.
private struct SnapshotCredentials: CredentialStore {
    func read(account: String) throws -> String? { nil }
    func write(_ value: String, account: String) throws {}
    func delete(account: String) throws {}
}
