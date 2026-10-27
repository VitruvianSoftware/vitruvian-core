// Copyright 2026 VitruvianSoftware
// SPDX-License-Identifier: AGPL-3.0-or-later

import AppKit
import CourierCore
import SwiftUI
import UserNotifications
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
        let actions = actions ?? Courier.MessageActions(now: { Fixture.now })
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

    private func composer(
        text: String,
        entities: [TextEntity] = [],
        voiceRecorder: VoiceRecorderModel? = nil
    ) -> ComposerModel {
        let composer = ComposerModel(
            sender: SnapshotMessageSender(),
            draftDelay: 0,
            sleep: { _ in },
            now: { Fixture.now },
            voiceRecorder: voiceRecorder
        )
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
            BlastItemResult(roomID: "!dm-dan-tg:courier.local", eventID: "", status: "failed", error: BlastItemResult.localizeStatusReason("network_refused")),
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

        // 4. Merged inbox row: collapsed from member rows with stacked network badges, newest preview, and summed unread count.
        let collapsedRows = InboxModel.collapseMergedRows(
            [directRows[0], directRows[1], directRows[3]],
            mergedChats: [merged.mergeID: merged]
        )
        XCTAssertEqual(collapsedRows.count, 2)
        XCTAssertEqual(collapsedRows[0].unread, 3)
        check(try Snapshot.render("merged-inbox-row", width: 340) {
            VStack(spacing: 0) {
                InboxRowView(
                    row: collapsedRows[0],
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
                    row: collapsedRows[1],
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

    // MARK: - Part 4.5a Task 13: Calendar Right Pane & Detected Dates

    func testCalendarPaneAuthorizedAndDeniedLightAndDark() async throws {
        // 1. Authorized (.fullAccess) with 2 events (one with a Join button).
        let authorizedStore = FakeCalendarStore(status: .fullAccess, events: Fixture.calendarEvents())
        let authorizedBridge = CalendarBridge(store: authorizedStore, now: { Fixture.now })
        await authorizedBridge.loadSelectedDay()
        check(try Snapshot.render("calendar-pane-events", width: 280, height: 520) {
            CalendarPane(bridge: authorizedBridge)
        })

        // 2. Denied (.denied) showing "Calendar access is turned off in System Settings." and Open System Settings button.
        let deniedStore = FakeCalendarStore(status: .denied, events: [])
        let deniedBridge = CalendarBridge(store: deniedStore, now: { Fixture.now })
        await deniedBridge.loadSelectedDay()
        check(try Snapshot.render("calendar-pane-denied", width: 280, height: 520) {
            CalendarPane(bridge: deniedBridge)
        })

        // 3. Message with a dashed-underlined future date ("Lunch tomorrow at 1pm") plus AddCalendarEventPopover,
        //    and verify "I was born in 1990" is not underlined while "lunch tomorrow at 1pm" is.
        let pastAttributed = LinkedText.attributed("I was born in 1990", now: Fixture.now)
        let hasPastUnderline = pastAttributed.runs.contains { $0.underlineStyle != nil }
        XCTAssertFalse(hasPastUnderline, "'I was born in 1990' must not be underlined")

        let futureAttributed = LinkedText.attributed("lunch tomorrow at 1pm", now: Fixture.now)
        let hasFutureDashUnderline = futureAttributed.runs.contains {
            $0.underlineStyle == Text.LineStyle(pattern: .dash)
        }
        XCTAssertTrue(hasFutureDashUnderline, "'lunch tomorrow at 1pm' must have a dashed underline")

        let dateEvent = Fixture.text(
            "$m-date",
            "Lunch tomorrow at 1pm to review the trail map?",
            mine: false,
            ts: 5,
            name: "Alice Example"
        )
        let detected = try XCTUnwrap(
            CalendarBridge.detectDates(in: "Lunch tomorrow at 1pm to review the trail map?", referenceDate: Fixture.now).first
        )
        check(try Snapshot.render("message-detected-date-popover", width: 420) {
            VStack(alignment: .leading, spacing: 12) {
                timeline(Fixture.items([dateEvent], isDirect: true))
                AddCalendarEventPopover(
                    bridge: authorizedBridge,
                    defaultTitle: "Lunch tomorrow at 1pm to review the trail map?",
                    detectedDate: detected
                )
                .background(
                    RoundedRectangle(cornerRadius: 10)
                        .fill(Color(nsColor: .windowBackgroundColor))
                        .shadow(color: .black.opacity(0.16), radius: 6, y: 2)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 10)
                        .strokeBorder(.quaternary)
                )
                .padding(.leading, 36)
            }
            .padding(14)
        })
    }

    // MARK: - Part 4.5b Task 5: Inline Images, BlurHash, Galleries, Broken-Image Card & View-Once Viewer

    func testEnhancedImageBlurHashErrorGalleryAndViewOnceLightAndDark() throws {
        let blurhash = "LEHV6nWB2yk8pyo0adR*.7kCMdnj"
        let validImagePath = try makeTestPNG(width: 320, height: 200)

        // 1. Single image with a BlurHash placeholder (before decode finishes) and loaded state (with transcoded badge).
        var placeholderEvent = Fixture.event(
            "$img-blur",
            mine: false,
            ts: 10,
            content: [
                "msgtype": .string("m.image"),
                "body": .string("Alpine ridge.jpg"),
                "filename": .string("Alpine ridge.jpg"),
                "info": .object([
                    "mimetype": .string("image/jpeg"),
                    "w": .int(640),
                    "h": .int(400),
                    "size": .int(184_320),
                    "xyz.amorgan.blurhash": .string(blurhash),
                ]),
            ],
            name: "Alice Example"
        )
        placeholderEvent.blurhash = blurhash
        placeholderEvent.mediaPath = validImagePath
        let placeholderMsg = try XCTUnwrap(Fixture.messages([placeholderEvent]).first)

        check(try Snapshot.render("image-blurhash-placeholder", width: 420) {
            EnhancedImageView(
                message: placeholderMsg,
                forceBlurHashPlaceholder: true,
                onOpenLightbox: { _ in }
            )
            .padding(14)
        })

        var loadedEvent = placeholderEvent
        loadedEvent.eventID = "$img-loaded"
        loadedEvent.content = .object([
            "msgtype": .string("m.image"),
            "body": .string("Look at this view from the pass"),
            "filename": .string("Alpine ridge.heic"),
            "info": .object([
                "mimetype": .string("image/jpeg"),
                "w": .int(640),
                "h": .int(400),
                "size": .int(184_320),
                "xyz.amorgan.blurhash": .string(blurhash),
                "fi.courier.transcoded": .bool(true),
            ]),
        ])
        let loadedMsg = try XCTUnwrap(Fixture.messages([loadedEvent]).first)
        let preloadedImage = try XCTUnwrap(NSImage(contentsOfFile: validImagePath))

        check(try Snapshot.render("image-enhanced-loaded", width: 420) {
            EnhancedImageView(
                message: loadedMsg,
                preloadedImage: preloadedImage,
                onOpenLightbox: { _ in }
            )
            .padding(14)
        })

        // 2. Gallery of 4 consecutive media items (including a video tile with GalleryVideoPoster play badge & duration pill).
        let galleryEvents: [Event] = [
            makeGalleryEvent("$gal-1", body: "photo1.jpg", filename: "photo1.jpg", msgtype: "m.image", offsetMS: 0, seq: 1, path: validImagePath, blurhash: blurhash),
            makeGalleryEvent("$gal-2", body: "photo2.jpg", filename: "photo2.jpg", msgtype: "m.image", offsetMS: 3_000, seq: 2, path: validImagePath, blurhash: blurhash),
            makeGalleryEvent("$gal-3", body: "clip.mp4", filename: "clip.mp4", msgtype: "m.video", offsetMS: 6_000, seq: 3, path: validImagePath, blurhash: blurhash, durationMS: 83_000),
            makeGalleryEvent("$gal-4", body: "Trailhead at dawn", filename: "photo4.jpg", msgtype: "m.image", offsetMS: 9_000, seq: 4, path: validImagePath, blurhash: blurhash),
        ]
        let galleryMessages = Fixture.messages(galleryEvents)
        XCTAssertEqual(galleryMessages.count, 1)
        let galleryMessage = try XCTUnwrap(galleryMessages.first)
        XCTAssertEqual(galleryMessage.galleryItems.count, 4)

        check(try Snapshot.render("gallery-grid-4", width: 460) {
            GalleryGridView(
                message: galleryMessage,
                preloadedImages: [
                    "$gal-1": preloadedImage,
                    "$gal-2": preloadedImage,
                    "$gal-3": preloadedImage,
                    "$gal-4": preloadedImage,
                ],
                onOpenLightbox: { _ in }
            )
            .padding(14)
        })

        // 3. Broken-image card (missing or corrupt image shows ImageErrorCard, not a crash).
        var brokenEvent = placeholderEvent
        brokenEvent.eventID = "$img-broken"
        brokenEvent.mediaPath = "/nonexistent/courier-missing-image.jpg"
        brokenEvent.thumbnailPath = nil
        let brokenMsg = try XCTUnwrap(Fixture.messages([brokenEvent]).first)

        check(try Snapshot.render("image-error-card", width: 420) {
            EnhancedImageView(
                message: brokenMsg,
                forceErrorState: true,
                onOpenLightbox: { _ in }
            )
            .padding(14)
        })

        // 4. View-once pill & ViewOnceSheet viewer (before and after opening), plus NSWindow.sharingType == .none check.
        var viewOnceUnopenedEvent = placeholderEvent
        viewOnceUnopenedEvent.eventID = "$vo-before"
        viewOnceUnopenedEvent.viewOnce = true
        viewOnceUnopenedEvent.played = false
        let viewOnceUnopenedMsg = try XCTUnwrap(Fixture.messages([viewOnceUnopenedEvent]).first)

        var viewOnceOpenedEvent = placeholderEvent
        viewOnceOpenedEvent.eventID = "$vo-after"
        viewOnceOpenedEvent.viewOnce = true
        viewOnceOpenedEvent.played = true
        let viewOnceOpenedMsg = try XCTUnwrap(Fixture.messages([viewOnceOpenedEvent]).first)

        check(try Snapshot.render("view-once-before", width: 420) {
            VStack(alignment: .leading, spacing: 10) {
                ViewOnceChip(message: viewOnceUnopenedMsg, onOpen: {})
                ViewOnceSheet(
                    message: viewOnceUnopenedMsg,
                    preloadedImage: preloadedImage,
                    onMarkPlayed: {},
                    onDismiss: {}
                )
            }
            .padding(14)
        })

        check(try Snapshot.render("view-once-after", width: 420) {
            VStack(alignment: .leading, spacing: 10) {
                ViewOnceChip(message: viewOnceOpenedMsg, onOpen: {})
                ViewOnceSheet(
                    message: viewOnceOpenedMsg,
                    preloadedImage: nil,
                    onMarkPlayed: {},
                    onDismiss: {}
                )
            }
            .padding(14)
        })

        // Verify screenshot protection sets NSWindow.sharingType = .none and honest notice is non-empty.
        let testWindow = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 320, height: 240),
            styleMask: [.titled],
            backing: .buffered,
            defer: true
        )
        XCTAssertTrue(ViewOnceSheet.applyScreenshotProtection(to: testWindow))
        XCTAssertEqual(testWindow.sharingType, .none)
        XCTAssertTrue(ViewOnceSheet.screenshotNoticeText.contains("blocked where macOS allows it"))
        XCTAssertFalse(ViewOnceSheet.screenshotNoticeText.contains("sharingType"), "no API names in text people read")
    }

    // MARK: - Part 4.5b Task 6: Inline Video Player & Floating Picture-in-Picture Window

    func testInlineVideoPlayerAndPiPViewLightAndDark() throws {
        let blurhash = "LEHV6nWB2yk8pyo0adR*.7kCMdnj"
        let posterPath = try makeTestPNG(width: 640, height: 360)
        let preloadedPoster = try XCTUnwrap(NSImage(contentsOfFile: posterPath))

        // 1. Local-only media rule: only local media store paths resolve to a file URL; remote URLs are refused.
        XCTAssertNotNil(InlineVideoPlayer.localMediaURL(for: posterPath))
        XCTAssertNil(InlineVideoPlayer.localMediaURL(for: "https://example.com/clip.mp4"))
        XCTAssertNil(InlineVideoPlayer.localMediaURL(for: "http://example.com/clip.mp4"))
        XCTAssertNil(InlineVideoPlayer.localMediaURL(for: "mxc://courier.local/sha256"))
        XCTAssertNil(InlineVideoPlayer.localMediaURL(for: ""))

        // 2. Autoplay rule: muted autoplay only for GIF-style videos (fi.mau.gif); real videos never autoplay.
        XCTAssertTrue(InlineVideoPlayer.shouldAutoplayMuted(isGIF: true))
        XCTAssertFalse(InlineVideoPlayer.shouldAutoplayMuted(isGIF: false))
        XCTAssertEqual(
            InlineVideoPlayer.Speed.allCases.map(\.label),
            ["0.25×", "0.5×", "1×", "1.25×", "1.5×", "2×"]
        )

        // 3. Snapshot: InlineVideoPlayer paused with poster and duration pill.
        check(try Snapshot.render("inline-video-poster", width: 420) {
            InlineVideoPlayer(
                messageID: "$vid-1",
                roomID: Fixture.room,
                mediaPath: posterPath,
                thumbnailPath: posterPath,
                blurhash: blurhash,
                width: 640,
                height: 360,
                durationMS: 83_000,
                isGIF: false,
                onPopOutPiP: {},
                onOpenLightbox: {},
                preloadedPoster: preloadedPoster
            )
            .padding(14)
        })

        // 4. Snapshot: InlineVideoPlayer in playing state with custom transport bar controls.
        check(try Snapshot.render("inline-video-playing-controls", width: 420) {
            InlineVideoPlayer(
                messageID: "$vid-1",
                roomID: Fixture.room,
                mediaPath: posterPath,
                thumbnailPath: posterPath,
                blurhash: blurhash,
                width: 640,
                height: 360,
                durationMS: 83_000,
                isGIF: false,
                onPopOutPiP: {},
                onOpenLightbox: {},
                preloadedPoster: preloadedPoster,
                initialIsPlaying: true,
                initialElapsedMS: 28_000,
                initialSpeed: .onePointTwoFive,
                initialShowsControls: true
            )
            .padding(14)
        })

        // 5. Snapshot: PictureInPictureView floating window content in light and dark mode.
        let pipItem = PiPVideoItem(
            messageID: "$vid-1",
            roomID: Fixture.room,
            mediaPath: posterPath,
            thumbnailPath: posterPath,
            blurhash: blurhash,
            title: "Alpine descent.mp4",
            width: 640,
            height: 360,
            durationMS: 83_000,
            elapsedMS: 28_000,
            isPlaying: true
        )
        check(try Snapshot.render("pip-video-window", width: 360) {
            PictureInPictureView(
                item: pipItem,
                preloadedPoster: preloadedPoster,
                onTogglePlayPause: {},
                onSeek: { _ in },
                onReturnToChat: {},
                onClose: {}
            )
            .padding(10)
        })

        // 6. Verify PictureInPictureController.shared.show(...) / close() state transitions,
        //    chat-close survival, and quit termination.
        let controller = PictureInPictureController.shared
        controller.close()
        XCTAssertNil(controller.activeItem)

        // Remote URLs are rejected by PictureInPictureController.show(_:).
        controller.show(
            PiPVideoItem(
                messageID: "$remote",
                roomID: Fixture.room,
                mediaPath: "https://example.com/remote.mp4"
            )
        )
        XCTAssertNil(controller.activeItem, "PiP must never play a remote URL")

        controller.show(pipItem)
        XCTAssertEqual(controller.activeItem?.messageID, "$vid-1")
        XCTAssertEqual(controller.activeItem?.roomID, Fixture.room)
        let panel = try XCTUnwrap(controller.panel)
        XCTAssertEqual(panel.level, .floating)
        XCTAssertTrue(panel.collectionBehavior.contains(.canJoinAllSpaces))
        XCTAssertTrue(panel.collectionBehavior.contains(.fullScreenAuxiliary))

        // Closing or switching away from the chat must NOT kill a PiP video the person is watching.
        controller.handleChatClosed(roomID: Fixture.room)
        XCTAssertEqual(controller.activeItem?.messageID, "$vid-1", "closing the chat must not stop PiP")

        // Return to Chat routes back to the video's room and message.
        var returnedTarget: (String, String)?
        controller.onReturnToChat = { roomID, messageID in
            returnedTarget = (roomID, messageID)
        }
        controller.returnToChat()
        XCTAssertEqual(returnedTarget?.0, Fixture.room)
        XCTAssertEqual(returnedTarget?.1, "$vid-1")

        // Quitting stops and closes PiP.
        controller.stopForApplicationTermination()
        XCTAssertNil(controller.activeItem)

        // Re-show and verify explicit close().
        controller.show(pipItem)
        XCTAssertNotNil(controller.activeItem)
        controller.close()
        XCTAssertNil(controller.activeItem)

        // 7. Plain-words check: user-facing strings never expose API names.
        for text in InlineVideoPlayer.userVisibleStrings + PictureInPictureView.userVisibleStrings {
            XCTAssertFalse(text.contains("AVPlayer"), "no API names in text people read: \(text)")
            XCTAssertFalse(text.contains("NSPanel"), "no API names in text people read: \(text)")
            XCTAssertFalse(text.contains("fi.mau.gif"), "no API names in text people read: \(text)")
        }
    }

    // MARK: - Part 4.5b Task 7: Inline Voice-Note & Audio Player and GlobalAudioPlayerBar

    func testVoiceNoteViewAndGlobalAudioPlayerBarLightAndDark() throws {
        let waveform = [14, 28, 52, 85, 64, 40, 72, 96, 80, 48, 30, 62, 88, 70, 44, 22, 56, 78, 50, 26, 38, 66, 42, 18]
        let audioPath = FileManager.default.temporaryDirectory
            .appendingPathComponent("courier-snapshot-voice.ogg").path
        try Data("OggS-snapshot".utf8).write(to: URL(fileURLWithPath: audioPath), options: .atomic)

        var unplayedEvent = Fixture.event(
            "$vn-unplayed",
            mine: false,
            ts: 12,
            content: [
                "msgtype": .string("m.audio"),
                "body": .string("Voice message.ogg"),
                "filename": .string("Voice message.ogg"),
                "org.matrix.msc3245.voice": .object([:]),
                "org.matrix.msc1767.audio": .object([
                    "duration": .int(24_000),
                    "waveform": .array(waveform.map { .int(Int64($0)) }),
                ]),
                "info": .object([
                    "mimetype": .string("audio/ogg"),
                    "duration": .int(24_000),
                    "size": .int(32_768),
                ]),
            ],
            name: "Alice Example"
        )
        unplayedEvent.mediaPath = audioPath
        unplayedEvent.durationMS = 24_000
        unplayedEvent.waveform = waveform
        unplayedEvent.played = false
        let unplayedMsg = try XCTUnwrap(Fixture.messages([unplayedEvent]).first)
        XCTAssertEqual(unplayedMsg.kind, .voiceNote)
        XCTAssertFalse(unplayedMsg.played)

        var playedEvent = unplayedEvent
        playedEvent.eventID = "$vn-played"
        playedEvent.played = true
        let playedMsg = try XCTUnwrap(Fixture.messages([playedEvent]).first)
        XCTAssertTrue(playedMsg.played)

        // 1. VoiceNoteView unplayed with waveform bars and unplayed dot.
        let idlePlayer = AudioPlayerModel(defaults: defaults())
        check(try Snapshot.render("voice-note-unplayed", width: 380) {
            VoiceNoteView(
                message: unplayedMsg,
                chatTitle: "Saturday Hike",
                audioPlayer: idlePlayer,
                queueInRoom: []
            )
            .padding(14)
        })

        // 2. VoiceNoteView playing at 1.5× at 45% progress (mid-waveform).
        let playingPlayer = AudioPlayerModel(defaults: defaults())
        let activeTrack = AudioPlayerModel.Track(
            eventID: unplayedMsg.id,
            roomID: unplayedMsg.roomID,
            mediaPath: audioPath,
            senderName: "Alice Example",
            chatTitle: "Saturday Hike",
            durationMS: 24_000,
            waveform: waveform
        )
        playingPlayer.setPreviewState(
            track: activeTrack,
            isPlaying: true,
            progress: 0.45,
            elapsedMS: 10_800,
            speed: .onePointFive
        )
        check(try Snapshot.render("voice-note-playing", width: 380) {
            VoiceNoteView(
                message: unplayedMsg,
                chatTitle: "Saturday Hike",
                audioPlayer: playingPlayer,
                queueInRoom: [activeTrack]
            )
            .padding(14)
        })

        // 3. VoiceNoteView played.
        check(try Snapshot.render("voice-note-played", width: 380) {
            VoiceNoteView(
                message: playedMsg,
                chatTitle: "Saturday Hike",
                audioPlayer: idlePlayer,
                queueInRoom: []
            )
            .padding(14)
        })

        // 4. GlobalAudioPlayerBar persistent floating audio bar.
        check(try Snapshot.render("global-audio-player-bar", width: 620) {
            GlobalAudioPlayerBar(
                audioPlayer: playingPlayer,
                onJumpToMessage: { _, _ in }
            )
            .padding(10)
        })

        // 5. Plain-words check: user-facing strings never expose API names.
        for text in VoiceNoteView.userVisibleStrings + GlobalAudioPlayerBar.userVisibleStrings {
            XCTAssertFalse(text.contains("AVAudioPlayer"), "no API names in text people read: \(text)")
            XCTAssertFalse(text.contains("AVPlayer"), "no API names in text people read: \(text)")
            XCTAssertFalse(text.contains("MSC1767"), "no API names in text people read: \(text)")
            XCTAssertFalse(text.contains("MSC3245"), "no API names in text people read: \(text)")
            XCTAssertFalse(text.contains("markPlayed"), "no API names in text people read: \(text)")
        }
    }

    func testComposerVoiceRecordingBarAndMicrophonePickerLightAndDark() async throws {
        let store = defaults()
        let preferences = ComposerPreferences(defaults: store)
        let devices = [
            AudioInputDevice(uid: "built-in-mic", name: "MacBook Pro Microphone"),
            AudioInputDevice(uid: "studio-mic", name: "Studio USB Microphone"),
        ]

        // 1. Idle composer with microphone record button.
        let idleComposer = composer(text: "")
        check(try Snapshot.render("composer-voice-idle", width: 620) {
            ComposerView(
                composer: idleComposer,
                preferences: preferences,
                textHeight: .constant(ComposerTextView.minimumHeight),
                menus: ComposerMenus(sendLater: {}, createPoll: {}, pollsUnavailable: nil)
            )
        })

        // 2. Active voice recording bar with timer, live waveform levels, BrandStopButton, cancel, and send.
        let startTime = Date(timeIntervalSince1970: 1_700_000_000)
        var currentTime = startTime
        let recordingBackend = SnapshotVoiceBackend(
            devices: devices,
            authStatus: .authorized,
            meterLevels: [0.18, 0.42, 0.76, 0.92, 0.64, 0.35, 0.55, 0.88, 0.72, 0.48, 0.25, 0.62],
            durationMS: 14_000
        )
        let recordingRecorder = VoiceRecorderModel(backend: recordingBackend, now: { currentTime })
        let recordingComposer = composer(text: "", voiceRecorder: recordingRecorder)
        await recordingRecorder.start()
        for step in 1 ... 12 {
            currentTime = startTime.addingTimeInterval(Double(step) * 1.16)
            recordingRecorder.sampleMeter()
        }
        check(try Snapshot.render("composer-voice-recording", width: 620) {
            ComposerView(
                composer: recordingComposer,
                preferences: preferences,
                textHeight: .constant(ComposerTextView.minimumHeight),
                menus: ComposerMenus(sendLater: {}, createPoll: {}, pollsUnavailable: nil)
            )
        })

        // 3. Review-before-send state after pressing BrandStopButton.
        await recordingRecorder.stopForReview()
        check(try Snapshot.render("composer-voice-review", width: 620) {
            ComposerView(
                composer: recordingComposer,
                preferences: preferences,
                textHeight: .constant(ComposerTextView.minimumHeight),
                menus: ComposerMenus(sendLater: {}, createPoll: {}, pollsUnavailable: nil)
            )
        })

        // 4. Permission-denied state with plain words and Open System Settings.
        let deniedBackend = SnapshotVoiceBackend(devices: devices, authStatus: .denied)
        let deniedRecorder = VoiceRecorderModel(backend: deniedBackend)
        let deniedComposer = composer(text: "", voiceRecorder: deniedRecorder)
        await deniedRecorder.start()
        check(try Snapshot.render("composer-voice-permission-denied", width: 620) {
            ComposerView(
                composer: deniedComposer,
                preferences: preferences,
                textHeight: .constant(ComposerTextView.minimumHeight),
                menus: ComposerMenus(sendLater: {}, createPoll: {}, pollsUnavailable: nil)
            )
        })

        // 5. MessagesSettingsPane showing the Microphone picker.
        preferences.preferredMicrophoneUID = "studio-mic"
        let replies = QuickReplies(defaults: store)
        check(try Snapshot.render("settings-messages-microphone", width: 560, height: 1040) {
            MessagesSettingsPane(
                preferences: preferences,
                quickReplies: replies,
                isEntitled: { _ in true },
                conversation: conversation(preferences, entitled: true),
                voiceRecorder: recordingRecorder
            )
        })

        // Plain-words check: user-visible strings never expose API or protocol names.
        for text in ComposerView.voiceUserVisibleStrings {
            XCTAssertFalse(text.contains("AVAudioRecorder"), "no API names in text people read: \(text)")
            XCTAssertFalse(text.contains("AVCaptureDevice"), "no API names in text people read: \(text)")
            XCTAssertFalse(text.contains("NSMicrophoneUsageDescription"), "no API names in text people read: \(text)")
            XCTAssertFalse(text.contains("sendVoice"), "no API names in text people read: \(text)")
            XCTAssertFalse(text.contains("MSC3245"), "no API names in text people read: \(text)")
        }
    }

    // MARK: - Part 4.5b Task 9: Inline PDFs, Rich File Cards, PendingAttachmentsStrip & FileDropOverlayView

    func testInlinePDFViewFilePlaceholderAndDropOverlayLightAndDark() throws {
        let pdfPath = try makeTwoPagePDF()
        let imagePath = try makeTestPNG(width: 240, height: 160)

        // 1. Local-only PDF rule: InlinePDFView only loads local media store files, never remote URLs.
        XCTAssertNotNil(InlinePDFView.localPDFURL(for: pdfPath))
        XCTAssertNil(InlinePDFView.localPDFURL(for: "https://example.com/spec.pdf"))
        XCTAssertNil(InlinePDFView.localPDFURL(for: "mxc://courier.local/spec"))
        XCTAssertNil(InlinePDFView.localPDFURL(for: ""))

        var pdfEvent = Fixture.event(
            "$pdf-1",
            mine: false,
            ts: 20,
            content: [
                "msgtype": .string("m.file"),
                "body": .string("Trail-Permit-2026.pdf"),
                "filename": .string("Trail-Permit-2026.pdf"),
                "info": .object([
                    "mimetype": .string("application/pdf"),
                    "size": .int(248_576),
                ]),
            ],
            name: "Alice Example"
        )
        pdfEvent.mediaPath = pdfPath
        let pdfMessage = try XCTUnwrap(Fixture.messages([pdfEvent]).first)

        // 2. Snapshot: InlinePDFView on Page 1 of 2 and Page 2 of 2.
        check(try Snapshot.render("pdf-card-page-1", width: 420) {
            InlinePDFView(message: pdfMessage, initialPageIndex: 0)
                .padding(14)
        })
        check(try Snapshot.render("pdf-card-page-2", width: 420) {
            InlinePDFView(message: pdfMessage, initialPageIndex: 1)
                .padding(14)
        })

        // 3. Snapshot: FileAttachmentChip rich file cards (Audio, Archive, Text placeholders + local Document card).
        let audioEvent = makeFileEvent(
            "$file-audio",
            filename: "Campfire-Session.flac",
            mimeType: "audio/flac",
            size: 14_680_064,
            mediaPath: ""
        )
        let archiveEvent = makeFileEvent(
            "$file-archive",
            filename: "Topographic-Maps.zip",
            mimeType: "application/zip",
            size: 8_388_608,
            mediaPath: ""
        )
        let textEvent = makeFileEvent(
            "$file-text",
            filename: "Packing-Checklist.txt",
            mimeType: "text/plain",
            size: 4_096,
            mediaPath: pdfPath
        )
        let fileMessages = Fixture.messages([audioEvent, archiveEvent, textEvent])
        XCTAssertEqual(fileMessages.count, 3)
        XCTAssertEqual(FileAttachmentChip.Category.classify(fileName: "Campfire-Session.flac", mimeType: "audio/flac"), .audio)
        XCTAssertEqual(FileAttachmentChip.Category.classify(fileName: "Topographic-Maps.zip", mimeType: "application/zip"), .archive)
        XCTAssertEqual(FileAttachmentChip.Category.classify(fileName: "Packing-Checklist.txt", mimeType: "text/plain"), .text)
        XCTAssertEqual(FileAttachmentChip.Category.classify(fileName: "Trail-Permit-2026.pdf", mimeType: "application/pdf"), .pdf)

        check(try Snapshot.render("file-card", width: 420) {
            VStack(alignment: .leading, spacing: 10) {
                ForEach(fileMessages) { msg in
                    FileAttachmentChip(message: msg)
                }
            }
            .padding(14)
        })

        // 4. Snapshot: FileAttachmentChip showing a download in progress.
        check(try Snapshot.render("file-card-downloading", width: 420) {
            FileAttachmentChip(
                message: fileMessages[2],
                isDownloading: true
            )
            .padding(14)
        })

        // 5. Snapshot: PendingAttachmentsStrip including thumbnail preview and an over-limit size warning.
        let smallAttachment = ComposerAttachment(
            id: UUID(),
            url: URL(fileURLWithPath: imagePath),
            size: 184_320
        )
        let overLimitAttachment = ComposerAttachment(
            id: UUID(),
            url: URL(fileURLWithPath: pdfPath),
            size: 30 * 1024 * 1024
        )
        let gmessagesFeatures = ChatFeatures(
            reply: true,
            source: .stored,
            imageFeatures: FileKindFeatures(supported: true, caption: true, maxSize: 100 * 1024 * 1024),
            fileFeatures: FileKindFeatures(supported: true, caption: true, maxSize: 25 * 1024 * 1024)
        )
        check(try Snapshot.render("pending-attachments-strip", width: 540) {
            PendingAttachmentsStrip(
                attachments: [smallAttachment, overLimitAttachment],
                features: gmessagesFeatures,
                network: "gmessages",
                onRemove: { _ in }
            )
            .padding(14)
        })

        // 6. Snapshot: FileDropOverlayView (normal + Shift-held).
        check(try Snapshot.render("file-drop-overlay", width: 480) {
            VStack(spacing: 14) {
                FileDropOverlayView(isShiftHeld: false)
                    .frame(height: 150)
                FileDropOverlayView(isShiftHeld: true)
                    .frame(height: 150)
            }
            .padding(14)
        })

        // 7. Plain-words check: user-facing strings never expose API names.
        let allStrings = InlinePDFView.userVisibleStrings
            + FileAttachmentChip.userVisibleStrings
            + FileDropOverlayView.userVisibleStrings
        for text in allStrings {
            XCTAssertFalse(text.contains("PDFKit"), "no API names in text people read: \(text)")
            XCTAssertFalse(text.contains("PDFDocument"), "no API names in text people read: \(text)")
            XCTAssertFalse(text.contains("NSWorkspace"), "no API names in text people read: \(text)")
            XCTAssertFalse(text.contains("kLSQuarantine"), "no API names in text people read: \(text)")
            XCTAssertFalse(text.contains("FileFeatures"), "no API names in text people read: \(text)")
        }
    }

    func testLocationCardLinkPreviewAndEmbedConsentLightAndDark() throws {
        let localThumbPath = try makeTestPNG(width: 240, height: 140)

        // 1. Snapshot: LocationCardView with coordinate and place name.
        let coordinate = try XCTUnwrap(
            GeoCoordinate.parse("geo:37.7749,-122.4194;u=15", fallbackLabel: "Ferry Building, San Francisco")
        )
        check(try Snapshot.render("location-card", width: 360) {
            LocationCardView(coordinate: coordinate)
                .padding(14)
        })

        // 2. Snapshot: LinkPreviewCardView with local thumbnail.
        let previewWithThumb = LinkPreviewItem(
            matchedURL: "https://example.org/architecture",
            url: "https://example.org/architecture",
            title: "On-Device Messaging Architecture",
            siteName: "Example Engineering",
            description: "How local bridges deliver rich media and link previews without external requests.",
            imagePath: localThumbPath,
            imageWidth: 240,
            imageHeight: 140,
            blurhash: "LEHV6nWB2yk8pyo0adR*.7kCMdnj"
        )
        check(try Snapshot.render("link-preview-with-thumbnail", width: 360) {
            LinkPreviewCardView(preview: previewWithThumb)
                .padding(14)
        })

        // 3. Snapshot: LinkPreviewCardView without thumbnail (and rejecting any remote imagePath).
        let previewWithoutThumb = LinkPreviewItem(
            matchedURL: "https://example.org/notes",
            url: "https://example.org/notes",
            title: "Release Notes — Autumn Update",
            siteName: "example.org",
            description: "Summary of offline-first privacy controls, location cards, and link preview rendering.",
            imagePath: nil
        )
        check(try Snapshot.render("link-preview-without-thumbnail", width: 360) {
            LinkPreviewCardView(preview: previewWithoutThumb)
                .padding(14)
        })

        // 4. Snapshot: EmbedConsentCard placeholder before click.
        let descriptor = try XCTUnwrap(
            ExternalEmbedDescriptor.match(urlString: "https://www.youtube.com/watch?v=dQw4w9WgXcQ")
        )
        XCTAssertEqual(descriptor.host, "youtube.com")
        check(try Snapshot.render("embed-consent-card", width: 360) {
            EmbedConsentCard(
                messageID: "$embed-1",
                descriptor: descriptor,
                isLoaded: false,
                onLoadEmbed: {}
            )
            .padding(14)
        })

        // 5. Verify no WKWebView is created at all while isLoaded == false, and verify non-persistent store config.
        let consentHosting = NSHostingView(
            rootView: EmbedConsentCard(
                messageID: "$embed-1",
                descriptor: descriptor,
                isLoaded: false,
                onLoadEmbed: {}
            )
        )
        consentHosting.frame = NSRect(x: 0, y: 0, width: 360, height: 180)
        consentHosting.layoutSubtreeIfNeeded()
        XCTAssertFalse(
            EmbedConsentCard.containsWebView(in: consentHosting),
            "No WKWebView may exist in the view hierarchy before the user clicks Load Embed"
        )
        let webConfig = SandboxedEmbedWebView.makeConfiguration()
        XCTAssertFalse(webConfig.websiteDataStore.isPersistent, "Embed WKWebView must use a non-persistent data store")
        XCTAssertFalse(
            SandboxedEmbedWebView.shouldAllowNavigation(
                targetURL: URL(string: "https://evil.example.com/phish"),
                embedURL: descriptor.embedURL
            ),
            "Embed WKWebView must block navigation away from the embed URL"
        )
        XCTAssertTrue(
            SandboxedEmbedWebView.shouldAllowNavigation(
                targetURL: descriptor.embedURL,
                embedURL: descriptor.embedURL
            )
        )

        // 6. Plain-words check: user-facing strings never expose API names.
        let strings = LocationCardView.userVisibleStrings
            + LinkPreviewCardView.userVisibleStrings
            + EmbedConsentCard.userVisibleStrings
        for text in strings {
            XCTAssertFalse(text.contains("MKMapSnapshotter"), "no API names in text people read: \(text)")
            XCTAssertFalse(text.contains("WKWebView"), "no API names in text people read: \(text)")
            XCTAssertFalse(text.contains("BeeperLinkPreview"), "no API names in text people read: \(text)")
            XCTAssertFalse(text.contains("MessageIFrame"), "no API names in text people read: \(text)")
            XCTAssertFalse(text.contains("m.location"), "no API names in text people read: \(text)")
        }
    }

    private func makeFileEvent(
        _ id: String,
        filename: String,
        mimeType: String,
        size: Int64,
        mediaPath: String
    ) -> Event {
        var event = Fixture.event(
            id,
            mine: false,
            ts: 25,
            content: [
                "msgtype": .string("m.file"),
                "body": .string(filename),
                "filename": .string(filename),
                "info": .object([
                    "mimetype": .string(mimeType),
                    "size": .int(size),
                ]),
            ],
            name: "Alice Example"
        )
        event.mediaPath = mediaPath
        return event
    }

    private func makeTwoPagePDF() throws -> String {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("courier-snapshot-2page-\(UUID().uuidString).pdf")
        var mediaBox = CGRect(x: 0, y: 0, width: 360, height: 240)
        guard let consumer = CGDataConsumer(url: url as CFURL),
              let context = CGContext(consumer: consumer, mediaBox: &mediaBox, nil)
        else {
            throw SnapshotError.noBitmap("two-page-pdf")
        }

        for pageNumber in 1 ... 2 {
            context.beginPDFPage(nil)
            context.setFillColor(
                pageNumber == 1
                    ? CGColor(red: 0.94, green: 0.97, blue: 1.0, alpha: 1.0)
                    : CGColor(red: 0.95, green: 0.99, blue: 0.95, alpha: 1.0)
            )
            context.fill(mediaBox)

            context.setStrokeColor(CGColor(red: 0.20, green: 0.45, blue: 0.78, alpha: 1.0))
            context.setLineWidth(4)
            context.stroke(mediaBox.insetBy(dx: 16, dy: 16))

            context.setFillColor(
                pageNumber == 1
                    ? CGColor(red: 0.18, green: 0.42, blue: 0.76, alpha: 1.0)
                    : CGColor(red: 0.18, green: 0.62, blue: 0.36, alpha: 1.0)
            )
            if pageNumber == 1 {
                context.fill(CGRect(x: 40, y: 120, width: 280, height: 64))
                context.fill(CGRect(x: 40, y: 56, width: 180, height: 32))
            } else {
                context.fillEllipse(in: CGRect(x: 120, y: 60, width: 120, height: 120))
            }
            context.endPDFPage()
        }
        context.closePDF()
        return url.path
    }

    private func makeGalleryEvent(
        _ id: String,
        body: String,
        filename: String,
        msgtype: String,
        offsetMS: Int64,
        seq: Int64,
        path: String,
        blurhash: String,
        durationMS: Int64? = nil
    ) -> Event {
        let baseTS = Fixture.millis(15)
        var info: [String: JSONValue] = [
            "mimetype": .string(msgtype == "m.video" ? "video/mp4" : "image/jpeg"),
            "w": .int(640),
            "h": .int(480),
            "size": .int(120_000),
            "xyz.amorgan.blurhash": .string(blurhash),
        ]
        if let durationMS {
            info["duration"] = .int(durationMS)
        }
        return Event(
            eventID: id,
            roomID: Fixture.room,
            sender: "@alice:courier.local",
            senderName: "Alice Example",
            mine: false,
            type: "m.room.message",
            content: .object([
                "msgtype": .string(msgtype),
                "body": .string(body),
                "filename": .string(filename),
                "info": .object(info),
            ]),
            ts: baseTS + offsetMS,
            seq: seq,
            status: .sent,
            mediaPath: path,
            thumbnailPath: path,
            blurhash: blurhash,
            durationMS: durationMS
        )
    }

    private func makeTestPNG(width: Int, height: Int) throws -> String {
        let image = NSImage(size: NSSize(width: width, height: height), flipped: false) { rect in
            NSColor.systemTeal.setFill()
            rect.fill()
            NSColor.white.withAlphaComponent(0.25).setFill()
            NSBezierPath(ovalIn: rect.insetBy(dx: 24, dy: 24)).fill()
            return true
        }
        let tiff = try XCTUnwrap(image.tiffRepresentation)
        let rep = try XCTUnwrap(NSBitmapImageRep(data: tiff))
        let png = try XCTUnwrap(rep.representation(using: .png, properties: [:]))
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("courier-snapshot-\(width)x\(height).png")
        try png.write(to: url, options: .atomic)
        return url.path
    }

    func testAttachmentCarouselAndMediaViewerWindowLightAndDark() throws {
        let photoPath = try makeTestPNG(width: 640, height: 420)
        let pdfPath = try makeTwoPagePDF()

        let carouselItems = [
            CarouselItem(
                eventID: "$c1",
                roomID: Fixture.room,
                kind: .image,
                mediaPath: photoPath,
                thumbnailPath: photoPath,
                fileName: "Trail map.jpg",
                mimeType: "image/jpeg",
                width: 640,
                height: 420,
                sender: "@alice:courier.local",
                senderName: "Alice Example",
                mine: false,
                ts: Fixture.millis(20),
                caption: "Morning view from the ridge"
            ),
            CarouselItem(
                eventID: "$c2",
                roomID: Fixture.room,
                kind: .video,
                mediaPath: photoPath,
                thumbnailPath: photoPath,
                fileName: "Campfire.mp4",
                mimeType: "video/mp4",
                width: 640,
                height: 420,
                durationMS: 14_000,
                sender: Timeline.meUserID,
                senderName: "You",
                mine: true,
                ts: Fixture.millis(10),
                caption: "Campfire clip"
            ),
        ]

        let carouselModel = AttachmentCarouselModel()
        carouselModel.open(items: carouselItems, selectedEventID: "$c1")
        carouselModel.zoomIn()
        carouselModel.zoomIn()
        XCTAssertEqual(carouselModel.zoomScale, 1.5, accuracy: 0.001)

        try Snapshot.render("attachment-carousel-lightbox", width: 820, height: 560) {
            AttachmentCarouselOverlay(
                model: carouselModel,
                now: { Fixture.now },
                onGoToMessage: { _ in },
                onReact: { _, _ in },
                onReply: { _ in },
                onCopyImage: { _ in },
                onQuickLook: { _ in },
                onDownload: { _ in },
                onClose: {}
            )
        }

        let mediaHits = [
            MediaHit(
                eventID: "$mv-1",
                roomID: Fixture.room,
                roomName: "Weekend Trail Crew",
                network: "whatsapp",
                isDirect: false,
                place: .inbox,
                sender: "@alice:courier.local",
                senderName: "Alice Example",
                mine: false,
                ts: Fixture.millis(12),
                seq: 12,
                kind: .image,
                snippet: "Trail map.jpg",
                mediaPath: photoPath
            ),
            MediaHit(
                eventID: "$mv-2",
                roomID: Fixture.room,
                roomName: "Weekend Trail Crew",
                network: "whatsapp",
                isDirect: false,
                place: .inbox,
                sender: Timeline.meUserID,
                senderName: "You",
                mine: true,
                ts: Fixture.millis(8),
                seq: 13,
                kind: .video,
                snippet: "Campfire.mp4",
                mediaPath: photoPath
            ),
        ]

        let linkHits = [
            MediaHit(
                eventID: "$mv-link-1",
                roomID: Fixture.room,
                roomName: "Weekend Trail Crew",
                network: "whatsapp",
                isDirect: false,
                place: .inbox,
                sender: "@alice:courier.local",
                senderName: "Alice Example",
                mine: false,
                ts: Fixture.millis(15),
                seq: 10,
                kind: .text,
                snippet: "Trail Conditions & Permit Guide https://example.com/trail-guide",
                mediaPath: ""
            ),
        ]

        let docHits = [
            MediaHit(
                eventID: "$mv-doc-1",
                roomID: Fixture.room,
                roomName: "Weekend Trail Crew",
                network: "whatsapp",
                isDirect: false,
                place: .inbox,
                sender: "@alice:courier.local",
                senderName: "Alice Example",
                mine: false,
                ts: Fixture.millis(18),
                seq: 9,
                kind: .file,
                snippet: "Itinerary.pdf",
                mediaPath: pdfPath
            ),
            MediaHit(
                eventID: "$mv-doc-2",
                roomID: Fixture.room,
                roomName: "Weekend Trail Crew",
                network: "whatsapp",
                isDirect: false,
                place: .inbox,
                sender: Timeline.meUserID,
                senderName: "You",
                mine: true,
                ts: Fixture.millis(5),
                seq: 14,
                kind: .audio,
                snippet: "Trailhead directions.m4a",
                mediaPath: pdfPath
            ),
        ]

        let appModel = offlineApp()

        let mediaTabViewer = MediaViewerModel(appModel: appModel, roomID: Fixture.room, initialItems: mediaHits)
        try Snapshot.render("media-viewer-media-tab", width: 760, height: 520) {
            MediaViewerView(
                model: mediaTabViewer,
                chatTitle: "Weekend Trail Crew",
                now: { Fixture.now },
                onOpenLightbox: { _ in },
                onGoToMessage: { _ in },
                onDownloadSelected: {},
                onDeleteSelected: { _ in }
            )
        }

        let linksTabViewer = MediaViewerModel(appModel: appModel, roomID: Fixture.room, initialItems: linkHits)
        linksTabViewer.tab = .links
        try Snapshot.render("media-viewer-links-tab", width: 760, height: 520) {
            MediaViewerView(
                model: linksTabViewer,
                chatTitle: "Weekend Trail Crew",
                now: { Fixture.now },
                onOpenLightbox: { _ in },
                onGoToMessage: { _ in },
                onDownloadSelected: {},
                onDeleteSelected: { _ in }
            )
        }

        let docsTabViewer = MediaViewerModel(appModel: appModel, roomID: Fixture.room, initialItems: docHits)
        docsTabViewer.tab = .docs
        docsTabViewer.toggleSelected("$mv-doc-1")
        try Snapshot.render("media-viewer-docs-tab", width: 760, height: 520) {
            MediaViewerView(
                model: docsTabViewer,
                chatTitle: "Weekend Trail Crew",
                now: { Fixture.now },
                onOpenLightbox: { _ in },
                onGoToMessage: { _ in },
                onDownloadSelected: {},
                onDeleteSelected: { _ in }
            )
        }

        // Plain-words check: user-facing labels must never contain protocol/API identifiers.
        let visibleStrings = (
            MediaViewerModel.Tab.allCases.map(\.rawValue)
                + MediaViewerModel.SentByFilter.allCases.map(\.rawValue)
                + MediaViewerModel.SortOrder.allCases.map(\.rawValue)
                + AttachmentCarouselOverlay.actionTitles
                + MediaViewerView.actionTitles
        ).joined(separator: " ")
        for forbidden in ["m.room", "m.image", "m.video", "m.file", "search.query", "message.deleteForMe", "com.beeper"] {
            XCTAssertFalse(visibleStrings.contains(forbidden), "User-facing text must not expose API name \(forbidden)")
        }
    }

    func testViewOnceSheetPlaysVideoAndVoiceAndNeverMarksPlayedOnLoadFailure() throws {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("courier-vo-test-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let videoFile = tempDir.appendingPathComponent("clip.mp4")
        try Data([0x00, 0x00, 0x00, 0x18, 0x66, 0x74, 0x79, 0x70, 0x6D, 0x70, 0x34, 0x32]).write(to: videoFile)
        let voiceFile = tempDir.appendingPathComponent("note.m4a")
        try Data([0x00, 0x00, 0x00, 0x1C, 0x66, 0x74, 0x79, 0x70, 0x4D, 0x34, 0x41, 0x20]).write(to: voiceFile)

        var videoEvent = Fixture.event(
            "$vo-video",
            mine: false,
            ts: 10,
            content: [
                "msgtype": .string("m.video"),
                "body": .string("clip.mp4"),
                "info": .object(["mimetype": .string("video/mp4")]),
            ],
            name: "Alice Example"
        )
        videoEvent.mediaPath = videoFile.path
        videoEvent.durationMS = 4_000
        videoEvent.viewOnce = true
        let videoMsg = try XCTUnwrap(Fixture.messages([videoEvent]).first)

        var voiceEvent = Fixture.event(
            "$vo-voice",
            mine: false,
            ts: 20,
            content: [
                "msgtype": .string("m.audio"),
                "body": .string("note.m4a"),
                "org.matrix.msc3245.voice": .object([:]),
                "info": .object(["mimetype": .string("audio/mp4")]),
            ],
            name: "Alice Example"
        )
        voiceEvent.mediaPath = voiceFile.path
        voiceEvent.durationMS = 3_000
        voiceEvent.waveform = [20, 50, 80, 40]
        voiceEvent.viewOnce = true
        let voiceMsg = try XCTUnwrap(Fixture.messages([voiceEvent]).first)

        var missingEvent = Fixture.event(
            "$vo-missing",
            mine: false,
            ts: 30,
            content: [
                "msgtype": .string("m.image"),
                "body": .string("gone.jpg"),
                "info": .object(["mimetype": .string("image/jpeg")]),
            ],
            name: "Alice Example"
        )
        missingEvent.mediaPath = tempDir.appendingPathComponent("does-not-exist.jpg").path
        missingEvent.viewOnce = true
        let missingMsg = try XCTUnwrap(Fixture.messages([missingEvent]).first)

        XCTAssertTrue(ViewOnceSheet.canLoadMedia(for: videoMsg), "ViewOnceSheet must support view-once video")
        XCTAssertTrue(ViewOnceSheet.canLoadMedia(for: voiceMsg), "ViewOnceSheet must support view-once voice note")
        XCTAssertFalse(ViewOnceSheet.canLoadMedia(for: missingMsg), "missing file must fail to load")
        XCTAssertFalse(
            ViewOnceSheet.shouldMarkPlayed(message: missingMsg, didLoadMedia: false),
            "ViewOnceSheet must NEVER mark played when media failed to load"
        )
        XCTAssertTrue(
            ViewOnceSheet.shouldMarkPlayed(message: videoMsg, didLoadMedia: true),
            "ViewOnceSheet marks played after media loaded"
        )
    }

    func testInlinePDFViewCachesParsedDocumentPerPath() throws {
        let pdfPath = try makeTwoPagePDF()
        defer { try? FileManager.default.removeItem(atPath: pdfPath) }

        InlinePDFDocumentCache.shared.resetForTests()
        let first = InlinePDFDocumentCache.shared.document(atPath: pdfPath)
        let second = InlinePDFDocumentCache.shared.document(atPath: pdfPath)
        XCTAssertNotNil(first)
        XCTAssertTrue(first === second, "repeated lookups for the same path must return the cached PDFDocument instance")
        XCTAssertEqual(InlinePDFDocumentCache.shared.parseCount, 1, "PDF must be parsed only once per path")
    }

    func testNotifierAttachmentSetsTypeHintFromMIMEAndCleansUpTempDirectory() throws {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("courier-notif-src-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        // Content-addressed blob path with NO file extension, matching media.Store on disk.
        let extensionlessBlob = tempDir.appendingPathComponent("ab12cd34ef56")
        let pngRep = try XCTUnwrap(
            NSBitmapImageRep(
                bitmapDataPlanes: nil,
                pixelsWide: 8,
                pixelsHigh: 8,
                bitsPerSample: 8,
                samplesPerPixel: 4,
                hasAlpha: true,
                isPlanar: false,
                colorSpaceName: .deviceRGB,
                bytesPerRow: 0,
                bitsPerPixel: 0
            )
        )
        let pngData = try XCTUnwrap(pngRep.representation(using: .png, properties: [:]))
        try pngData.write(to: extensionlessBlob)

        let prepared = try XCTUnwrap(
            Notifier.prepareAttachment(
                from: extensionlessBlob.path,
                identifier: "$evt-png",
                mimeType: "image/png"
            )
        )
        let typeHint = prepared.options[UNNotificationAttachmentOptionsTypeHintKey] as? String
        XCTAssertEqual(typeHint, "public.png", "type hint must be derived from PNG MIME / magic rather than assuming JPEG")
        XCTAssertTrue(FileManager.default.fileExists(atPath: prepared.tempDirectory.path))

        prepared.cleanup()
        XCTAssertFalse(
            FileManager.default.fileExists(atPath: prepared.tempDirectory.path),
            "cleanup must remove the courier-notif-* temporary directory"
        )
    }

    // MARK: - Milestone 4.5c Task 6: EmojiAutocompletePicker snapshots and keyboard routing

    func testEmojiAutocompletePickerSnapshotsAndKeyboardRouting() throws {
        let preferences = ComposerPreferences(defaults: defaults())
        let model = composer(text: "")
        model.preferences = preferences
        model.customEmojis = [
            EmojiCandidate(
                id: "imported:partyblob",
                shortcode: "party_smile",
                glyph: nil,
                mediaURL: "courier://media/0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef",
                isCustom: true
            ),
        ]
        model.textChanged(to: "hello :smi", replacing: NSRange(location: 0, length: 0), with: 10)
        XCTAssertEqual(model.emojiQuery, "smi")
        XCTAssertTrue(model.emojiCandidates.contains(where: { $0.isCustom && $0.shortcode == "party_smile" }))

        var addedShortcode: String?
        check(try Snapshot.render("emoji-autocomplete-picker", width: 280) {
            EmojiAutocompletePicker(composer: model) { code in
                addedShortcode = code
            }
            .padding(10)
        })
        XCTAssertNil(addedShortcode)

        // Verify ComposerView mounts EmojiAutocompletePicker and routes ↑/↓/Return/Tab/Escape through Coordinator.
        check(try Snapshot.render("composer-emoji-autocomplete", width: 620, prepare: { host in
            guard let textView = host.first(PlainTextView.self),
                  let delegate = textView.delegate else {
                XCTFail("Expected PlainTextView and delegate in ComposerView")
                return
            }
            XCTAssertEqual(model.selectedEmojiIndex, 0)
            XCTAssertTrue(delegate.textView?(textView, doCommandBy: #selector(NSResponder.moveDown(_:))) ?? false)
            XCTAssertEqual(model.selectedEmojiIndex, 1)
            XCTAssertTrue(delegate.textView?(textView, doCommandBy: #selector(NSResponder.moveUp(_:))) ?? false)
            XCTAssertEqual(model.selectedEmojiIndex, 0)
        }) {
            ComposerView(
                composer: model,
                preferences: preferences,
                textHeight: .constant(ComposerTextView.minimumHeight),
                menus: ComposerMenus(sendLater: {}, createPoll: {}, pollsUnavailable: nil)
            )
        })

        // Verify Tab accepts the selected emoji candidate and Escape dismisses when open.
        let hostView = NSHostingView(
            rootView: ComposerView(
                composer: model,
                preferences: preferences,
                textHeight: .constant(ComposerTextView.minimumHeight),
                menus: ComposerMenus(sendLater: {}, createPoll: {}, pollsUnavailable: nil)
            )
        )
        hostView.frame = NSRect(x: 0, y: 0, width: 620, height: 120)
        hostView.layoutSubtreeIfNeeded()
        let textView = try XCTUnwrap(hostView.first(PlainTextView.self))
        let delegate = try XCTUnwrap(textView.delegate)
        XCTAssertTrue(delegate.textView?(textView, doCommandBy: #selector(NSResponder.insertTab(_:))) ?? false)
        XCTAssertNil(model.emojiQuery)
        XCTAssertTrue(model.text.hasPrefix("hello "))
        XCTAssertNotEqual(model.text, "hello :smi")

        model.textChanged(to: "again :smi", replacing: NSRange(location: 0, length: (model.text as NSString).length), with: 10)
        XCTAssertEqual(model.emojiQuery, "smi")
        XCTAssertTrue(delegate.textView?(textView, doCommandBy: #selector(NSResponder.cancelOperation(_:))) ?? false)
        XCTAssertNil(model.emojiQuery)
    }

    // MARK: - Milestone 4.5c Task 7: StickerPickerPopover empty and populated snapshots

    func testStickerPickerPopoverEmptyAndPopulatedSnapshots() throws {
        let emptyModel = composer(text: "")
        check(try Snapshot.render("sticker-picker-empty", width: 340) {
            StickerPickerPopover(composer: emptyModel)
        })

        let populatedModel = composer(text: "")
        populatedModel.setStickerCatalogForTesting(
            packs: [
                StickerPackWire(
                    id: "recent",
                    title: "Recent",
                    source: "recent",
                    items: [
                        StickerItemWire(
                            id: "recent:1",
                            packID: "recent",
                            name: "Smiling Cat",
                            emoji: "😺",
                            mediaURL: "courier://media/0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef",
                            mimeType: "image/webp"
                        ),
                        StickerItemWire(
                            id: "recent:2",
                            packID: "recent",
                            name: "Party Parrot",
                            emoji: "🦜",
                            mediaURL: "courier://media/fedcba9876543210fedcba9876543210fedcba9876543210fedcba9876543210",
                            mimeType: "image/gif"
                        ),
                        StickerItemWire(
                            id: "recent:3",
                            packID: "recent",
                            name: "Rocket Launch",
                            emoji: "🚀",
                            mediaURL: "courier://media/1111111111111111111111111111111111111111111111111111111111111111",
                            mimeType: "image/png"
                        ),
                        StickerItemWire(
                            id: "recent:4",
                            packID: "recent",
                            name: "Thumbs Up",
                            emoji: "👍",
                            mediaURL: "courier://media/2222222222222222222222222222222222222222222222222222222222222222",
                            mimeType: "image/webp"
                        ),
                    ]
                ),
                StickerPackWire(id: "imported", title: "Imported", source: "imported", items: []),
                StickerPackWire(id: "bridge:telegram:cats", title: "Cats", source: "bridge", network: "telegram", items: []),
            ]
        )
        check(try Snapshot.render("sticker-picker-populated", width: 340) {
            StickerPickerPopover(composer: populatedModel)
        })
    }

    // MARK: - Milestone 4.5c Task 8: GIFPickerPopover and pending GIF pill snapshots

    func testGIFPickerPopoverAndPendingGIFSnapshots() throws {
        let emptyModel = composer(text: "")
        check(try Snapshot.render("gif-picker-empty", width: 340) {
            GIFPickerPopover(composer: emptyModel)
        })

        let populatedModel = composer(text: "")
        populatedModel.setStickerCatalogForTesting(
            packs: [],
            recentGIFs: [
                StickerItemWire(
                    id: "gif:1",
                    packID: "recent_gifs",
                    name: "Party Parrot",
                    emoji: "🦜",
                    mediaURL: "courier://media/fedcba9876543210fedcba9876543210fedcba9876543210fedcba9876543210",
                    mimeType: "image/gif",
                    width: 320,
                    height: 240,
                    usage: ["gif"]
                ),
                StickerItemWire(
                    id: "gif:2",
                    packID: "recent_gifs",
                    name: "Mind Blown",
                    emoji: "🤯",
                    mediaURL: "courier://media/1122334455667788112233445566778811223344556677881122334455667788",
                    mimeType: "video/mp4",
                    width: 480,
                    height: 270,
                    usage: ["gif"]
                ),
            ]
        )
        check(try Snapshot.render("gif-picker-populated", width: 340) {
            GIFPickerPopover(composer: populatedModel)
        })

        let preferences = ComposerPreferences(defaults: defaults())
        let stagedModel = composer(text: "Check out this loop")
        stagedModel.preferences = preferences
        stagedModel.pendingGIF = StickerItemWire(
            id: "gif:1",
            packID: "recent_gifs",
            name: "Party Parrot",
            emoji: "🦜",
            mediaURL: "courier://media/fedcba9876543210fedcba9876543210fedcba9876543210fedcba9876543210",
            mimeType: "image/gif",
            width: 320,
            height: 240,
            usage: ["gif"]
        )
        check(try Snapshot.render("composer-pending-gif", width: 620) {
            ComposerView(
                composer: stagedModel,
                preferences: preferences,
                textHeight: .constant(ComposerTextView.minimumHeight),
                menus: ComposerMenus(sendLater: {}, createPoll: {}, pollsUnavailable: nil)
            )
        })
    }

    // MARK: - Milestone 4.5c Task 9: Composer + menu and toolbar sticker/GIF/emoji entry points

    func testComposerToolbarAndPlusMenuStickerGIFAndEmojiEntryPoints() throws {
        let preferences = ComposerPreferences(defaults: defaults())
        let model = composer(text: "Weekend trail crew!")
        model.preferences = preferences
        XCTAssertTrue(
            model.canSend,
            "composer in an open room with text must have canSend == true so the send arrow is active in the snapshot"
        )
        XCTAssertTrue(ComposerView.plusMenuMediaTitles.contains("Add Emoji…"))
        XCTAssertEqual(model.addGIFMenuTitle, "Add GIF…")
        XCTAssertEqual(model.addStickerMenuTitle, "Add Sticker…")
        check(try Snapshot.render("composer-toolbar-media", width: 620) {
            ComposerView(
                composer: model,
                preferences: preferences,
                textHeight: .constant(ComposerTextView.minimumHeight),
                menus: ComposerMenus(sendLater: {}, createPoll: {}, pollsUnavailable: nil)
            )
        })
    }

    func testEmojiAutocompletePublicInterfaceThumbnailLoaderAndStickerEmoticonFilter() async throws {
        let loader = ThumbnailLoader()
        let customCandidate = EmojiCandidate(
            id: "mxc://courier.local/0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef",
            shortcode: "party_smile",
            glyph: nil,
            mediaURL: "mxc://courier.local/0123456789abcdef0123456789abcdef0123456789abcdef",
            isCustom: true
        )
        let row = EmojiItemRow(
            candidate: customCandidate,
            isSelected: true,
            thumbnailLoader: loader
        )
        XCTAssertEqual(row.candidate, customCandidate)
        XCTAssertTrue(row.isSelected)
        XCTAssertNotNil(row.thumbnailLoader)

        var selectedCandidate: EmojiCandidate?
        var addedShortcode: String?
        let picker = EmojiAutocompletePicker(
            query: "smi",
            candidates: [customCandidate],
            selectedIndex: 0,
            thumbnailLoader: loader,
            onSelect: { selectedCandidate = $0 },
            onAddCustomEmoji: { addedShortcode = $0 }
        )
        XCTAssertEqual(picker.query, "smi")
        XCTAssertEqual(picker.candidates, [customCandidate])
        XCTAssertEqual(picker.selectedIndex, 0)
        XCTAssertNotNil(picker.thumbnailLoader)
        picker.onSelect(customCandidate)
        XCTAssertEqual(selectedCandidate, customCandidate)
        picker.onAddCustomEmoji("smi")
        XCTAssertEqual(addedShortcode, "smi")

        // Emoticon-only items (usage == ["emoticon"]) must be filtered out of StickerPickerPopover.
        let emoticonOnly = StickerItemWire(
            id: "imported:emo_only",
            packID: "imported",
            shortcode: "emo_only",
            name: "emo_only",
            mediaURL: "mxc://courier.local/aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa",
            mimeType: "image/png",
            usage: ["emoticon"]
        )
        let stickerAndEmoticon = StickerItemWire(
            id: "imported:both",
            packID: "imported",
            shortcode: "both",
            name: "both",
            mediaURL: "mxc://courier.local/bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb",
            mimeType: "image/png",
            usage: ["emoticon", "sticker"]
        )
        let pack = StickerPackWire(
            id: "imported",
            title: "Imported",
            source: "imported",
            items: [emoticonOnly, stickerAndEmoticon]
        )
        XCTAssertEqual(
            StickerPickerPopover.stickerItems(in: pack).map(\.id),
            ["imported:both"]
        )
    }

    // MARK: - Milestone 4.5c Task 10: Sticker and GIF timeline rendering and light/dark PNG snapshot tests

    private func findNSImageView(in view: NSView) -> NSImageView? {
        if let imageView = view as? NSImageView { return imageView }
        for subview in view.subviews {
            if let found = findNSImageView(in: subview) { return found }
        }
        return nil
    }

    private func makeTestStickerPNG(width: Int = 160, height: Int = 160) throws -> String {
        let image = NSImage(size: NSSize(width: width, height: height), flipped: false) { rect in
            NSColor.clear.setFill()
            rect.fill()
            let circleRect = rect.insetBy(dx: 12, dy: 12)
            NSColor.systemOrange.setFill()
            NSBezierPath(ovalIn: circleRect).fill()
            let innerStar = circleRect.insetBy(dx: 30, dy: 30)
            NSColor.systemYellow.setFill()
            NSBezierPath(roundedRect: innerStar, xRadius: 16, yRadius: 16).fill()
            return true
        }
        let tiff = try XCTUnwrap(image.tiffRepresentation)
        let rep = try XCTUnwrap(NSBitmapImageRep(data: tiff))
        let png = try XCTUnwrap(rep.representation(using: .png, properties: [:]))
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("courier-snapshot-sticker-\(width)x\(height).png")
        try png.write(to: url, options: .atomic)
        return url.path
    }

    func testStickerAndGIFReduceMotionAndFallbackAspectRatio() async throws {
        let stickerPath = try makeTestStickerPNG(width: 150, height: 150)
        let wideGIFPath = try makeTestPNG(width: 300, height: 150)

        let receivedStickerEvent = Fixture.sticker(
            "$sticker-rm",
            name: "Party Parrot",
            emoji: "🦜",
            mine: false,
            ts: 15,
            mediaPath: stickerPath,
            width: 150,
            height: 150
        )
        let receivedStickerMsg = try XCTUnwrap(Fixture.messages([receivedStickerEvent]).first)
        let receivedSticker = try XCTUnwrap(receivedStickerMsg.sticker)

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 400, height: 400),
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        let stickerHost = NSHostingView(
            rootView: StickerAttachmentView(message: receivedStickerMsg, sticker: receivedSticker)
        )
        stickerHost.frame = NSRect(x: 0, y: 0, width: 200, height: 200)
        // Initialize environment while NSWorkspace Reduce Motion is false so @Environment(\.accessibilityReduceMotion) is false.
        stickerHost.layoutSubtreeIfNeeded()

        // #4: When NSWorkspace.shared.accessibilityDisplayShouldReduceMotion becomes true while SwiftUI's
        // @Environment(\.accessibilityReduceMotion) is false, StickerAttachmentView must still pause animation.
        let origMethod = try XCTUnwrap(
            class_getInstanceMethod(NSWorkspace.self, #selector(getter: NSWorkspace.accessibilityDisplayShouldReduceMotion))
        )
        let stubMethod = try XCTUnwrap(
            class_getInstanceMethod(NSWorkspace.self, #selector(getter: NSWorkspace.courierTest_reduceMotionTrue))
        )
        method_exchangeImplementations(origMethod, stubMethod)
        defer { method_exchangeImplementations(origMethod, stubMethod) }
        XCTAssertTrue(NSWorkspace.shared.accessibilityDisplayShouldReduceMotion)

        stickerHost.rootView = StickerAttachmentView(message: receivedStickerMsg, sticker: receivedSticker)
        window.contentView = stickerHost
        stickerHost.layoutSubtreeIfNeeded()
        let stickerImageView = try XCTUnwrap(findNSImageView(in: stickerHost))
        XCTAssertFalse(
            stickerImageView.animates,
            "StickerAttachmentView must pause animation when NSWorkspace Reduce Motion is enabled"
        )

        // #5a: When NSImage(contentsOfFile:) succeeds, StickerAttachmentView and GIFAttachmentView must not
        // run an unused async ThumbnailLoader.shared.thumbnail(atPath:) decode.
        for _ in 0..<50 { await Task.yield() }
        let cachedAfterSticker = await ThumbnailLoader.shared.cachedPaths
        XCTAssertFalse(
            cachedAfterSticker.contains(stickerPath),
            "StickerAttachmentView must skip async ThumbnailLoader decode when NSImage(contentsOfFile:) succeeded"
        )

        // #5b: When GIF width/height metadata is missing, GIFAttachmentView must preserve the image's aspect ratio
        // and use .scaleProportionallyUpOrDown rather than .scaleAxesIndependently.
        var unindexedGIFEvent = Fixture.gif(
            "$gif-no-dims",
            msgtype: "m.image",
            fileName: "wide.gif",
            caption: nil,
            mine: false,
            ts: 7,
            mediaPath: wideGIFPath,
            mimeType: "image/gif",
            width: 0,
            height: 0
        )
        if case var .object(c) = unindexedGIFEvent.content,
           case var .object(info) = c["info"] {
            info.removeValue(forKey: "w")
            info.removeValue(forKey: "h")
            c["info"] = .object(info)
            unindexedGIFEvent.content = .object(c)
        }
        let unindexedGIFMsg = try XCTUnwrap(Fixture.messages([unindexedGIFEvent]).first)
        let unindexedGIF = try XCTUnwrap(unindexedGIFMsg.gif)
        XCTAssertNil(unindexedGIF.width)
        XCTAssertNil(unindexedGIF.height)

        let gifHost = NSHostingView(
            rootView: GIFAttachmentView(message: unindexedGIFMsg, gif: unindexedGIF)
        )
        gifHost.frame = NSRect(x: 0, y: 0, width: 400, height: 400)
        window.contentView = gifHost
        gifHost.layoutSubtreeIfNeeded()
        let gifImageView = try XCTUnwrap(findNSImageView(in: gifHost))
        XCTAssertEqual(
            gifImageView.imageScaling,
            .scaleProportionallyUpOrDown,
            "GIFAttachmentView must scale proportionally, not .scaleAxesIndependently"
        )
        XCTAssertEqual(
            gifImageView.frame.size,
            CGSize(width: 300, height: 150),
            "GIFAttachmentView fallback must preserve nsImage aspect ratio when w/h metadata is absent"
        )
        for _ in 0..<50 { await Task.yield() }
        let cachedAfterGIF = await ThumbnailLoader.shared.cachedPaths
        XCTAssertFalse(
            cachedAfterGIF.contains(wideGIFPath),
            "GIFAttachmentView must skip async ThumbnailLoader decode when NSImage(contentsOfFile:) succeeded"
        )
    }

    func testStickerAndGIFTimelineRenderingAndComposingSnapshots() throws {
        let stickerPath = try makeTestStickerPNG(width: 160, height: 160)
        let gifFramePath = try makeTestPNG(width: 280, height: 180)

        // Verify StickerAttachmentView and GIFAttachmentView sizing, ThumbnailLoader resolution, and Reduce Motion pause.
        XCTAssertEqual(
            StickerAttachmentView.displaySize(width: 320, height: 160),
            CGSize(width: 160, height: 80),
            "StickerAttachmentView constrains stickers up to 160×160 pt preserving aspect ratio"
        )
        XCTAssertTrue(StickerAttachmentView.shouldAnimate(reduceMotion: false))
        XCTAssertFalse(StickerAttachmentView.shouldAnimate(reduceMotion: true))
        XCTAssertTrue(GIFAttachmentView.shouldAnimate(reduceMotion: false))
        XCTAssertFalse(GIFAttachmentView.shouldAnimate(reduceMotion: true))
        XCTAssertEqual(GIFAttachmentView.cornerRadius, 12)

        // 1. Received sticker (light and dark PNGs)
        let receivedStickerEvent = Fixture.sticker(
            "$sticker-recv",
            name: "Party Parrot",
            emoji: "🦜",
            mine: false,
            ts: 15,
            mediaPath: stickerPath,
            width: 160,
            height: 160
        )
        let receivedStickerMsg = try XCTUnwrap(Fixture.messages([receivedStickerEvent]).first)
        XCTAssertNotNil(receivedStickerMsg.sticker)
        XCTAssertTrue(receivedStickerMsg.suppressesBubbleBackground)
        XCTAssertEqual(
            StickerAttachmentView.resolveLocalPath(message: receivedStickerMsg, sticker: try XCTUnwrap(receivedStickerMsg.sticker)),
            stickerPath
        )
        check(try Snapshot.render("sticker-received", width: 520) {
            timeline(Fixture.items([receivedStickerEvent], isDirect: true))
        })

        // 2. Sent sticker (light and dark PNGs)
        let sentStickerEvent = Fixture.sticker(
            "$sticker-sent",
            name: "Rocket Launch",
            emoji: "🚀",
            mine: true,
            ts: 10,
            mediaPath: stickerPath,
            width: 160,
            height: 160
        )
        let sentStickerMsg = try XCTUnwrap(Fixture.messages([sentStickerEvent]).first)
        XCTAssertNotNil(sentStickerMsg.sticker)
        XCTAssertTrue(sentStickerMsg.suppressesBubbleBackground)
        check(try Snapshot.render("sticker-sent", width: 520) {
            timeline(Fixture.items([sentStickerEvent], isDirect: true), sent: "$sticker-sent")
        })

        // 3. Looping GIF (first frame, rounded 12 pt frame, top-leading "GIF" pill badge)
        let loopingGIFEvent = Fixture.gif(
            "$gif-loop",
            msgtype: "m.image",
            fileName: "animation.gif",
            caption: nil,
            mine: false,
            ts: 8,
            mediaPath: gifFramePath,
            mimeType: "image/gif",
            width: 280,
            height: 180
        )
        let loopingGIFMsg = try XCTUnwrap(Fixture.messages([loopingGIFEvent]).first)
        XCTAssertNotNil(loopingGIFMsg.gif)
        XCTAssertNil(loopingGIFMsg.gif?.caption)
        XCTAssertEqual(
            GIFAttachmentView.resolveLocalPath(message: loopingGIFMsg, gif: try XCTUnwrap(loopingGIFMsg.gif)),
            gifFramePath
        )
        check(try Snapshot.render("gif-looping", width: 520) {
            timeline(Fixture.items([loopingGIFEvent], isDirect: true))
        })

        // 4. GIF with a caption rendered below the frame
        let captionedGIFEvent = Fixture.gif(
            "$gif-captioned",
            msgtype: "m.image",
            fileName: "animation.gif",
            caption: "Summit view celebration!",
            mine: true,
            ts: 5,
            mediaPath: gifFramePath,
            mimeType: "image/gif",
            width: 280,
            height: 180
        )
        let captionedGIFMsg = try XCTUnwrap(Fixture.messages([captionedGIFEvent]).first)
        XCTAssertEqual(captionedGIFMsg.gif?.caption, "Summit view celebration!")
        check(try Snapshot.render("gif-with-caption", width: 520) {
            timeline(Fixture.items([captionedGIFEvent], isDirect: true), sent: "$gif-captioned")
        })

        // 5. Sticker in a reply (sticker replying to a message, and a message replying to the sticker)
        let promptEvent = Fixture.text("$prompt-1", "Ready for the morning climb?", mine: false, ts: 20, name: "Ann Example")
        let replyStickerEvent = Fixture.sticker(
            "$sticker-reply",
            name: "Party Parrot",
            emoji: "🦜",
            mine: true,
            ts: 18,
            mediaPath: stickerPath,
            width: 160,
            height: 160,
            replyTo: "$prompt-1"
        )
        var textReplyToSticker = Fixture.text("$reply-to-sticker", "Love that sticker!", mine: false, ts: 16, name: "Ann Example")
        if case var .object(content) = textReplyToSticker.content {
            content["m.relates_to"] = .object([
                "m.in_reply_to": .object(["event_id": .string("$sticker-reply")]),
            ])
            textReplyToSticker.content = .object(content)
        }
        check(try Snapshot.render("sticker-in-reply", width: 520) {
            timeline(Fixture.items([promptEvent, replyStickerEvent, textReplyToSticker], isDirect: true), sent: "$sticker-reply")
        })

        // 6. EmojiAutocompletePicker with ":party_parrot:" footer and GIFPickerPopover with search query
        let emojiModel = composer(text: "")
        emojiModel.setStickerCatalogForTesting(
            packs: [
                StickerPackWire(
                    id: "imported",
                    title: "Imported",
                    source: "imported",
                    items: [
                        StickerItemWire(
                            id: "imported:party_parrot_wave",
                            packID: "imported",
                            shortcode: "party_parrot_wave",
                            name: "Party Parrot Wave",
                            emoji: "🦜",
                            mediaURL: stickerPath,
                            mimeType: "image/png",
                            width: 160,
                            height: 160,
                            usage: ["emoticon", "sticker"]
                        ),
                    ]
                ),
            ]
        )
        emojiModel.textChanged(to: "let's go :party_parrot", replacing: NSRange(location: 0, length: 0), with: 22)
        XCTAssertEqual(emojiModel.emojiQuery, "party_parrot")
        check(try Snapshot.render("emoji-autocomplete-party-parrot", width: 320) {
            EmojiAutocompletePicker(composer: emojiModel) { _ in }
                .padding(10)
        })

        let gifQueryModel = composer(text: "")
        gifQueryModel.setStickerCatalogForTesting(
            packs: [],
            recentGIFs: [
                StickerItemWire(
                    id: "gif:1",
                    packID: "recent_gifs",
                    name: "Celebration Loop",
                    emoji: "🎉",
                    mediaURL: gifFramePath,
                    mimeType: "image/gif",
                    width: 280,
                    height: 180,
                    usage: ["gif"]
                ),
            ]
        )
        gifQueryModel.gifSearchQuery = "Celebration"
        check(try Snapshot.render("gif-picker-search-query", width: 340) {
            GIFPickerPopover(composer: gifQueryModel)
        })
    }
}

/// A sign-in caller whose every sign-in finishes at once with `finish`.
extension NSWorkspace {
    @objc fileprivate var courierTest_reduceMotionTrue: Bool { true }
}

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

private final class SnapshotMessageSender: MessageSending, @unchecked Sendable {
    func sendText(roomID _: String, text _: String, replyTo _: String?) async throws {}
    func sendFile(roomID _: String, url _: URL, size _: Int64, replyTo _: String?) async throws {}
    func send(roomID _: String, rich _: RichText, replyTo _: String?, threadRoot _: String?, holdMillis _: Int) async throws -> String { "$snap" }
    func sendFile(roomID _: String, url _: URL, size _: Int64, replyTo _: String?, threadRoot _: String?, holdMillis _: Int) async throws -> String { "$snap" }
    func edit(eventID _: String, rich _: RichText) async throws {}
    func schedule(roomID _: String, rich _: RichText, replyTo _: String?, threadRoot _: String?, due _: Date, condition _: SendLaterCondition) async throws {}
    func undo(eventID _: String) async throws -> Draft { Draft(text: "", entities: [], replyTo: nil, threadRoot: nil) }
    func sendHeld(roomID _: String?) async throws {}
    func members(roomID _: String, query _: String) async throws -> [Member] { [] }
    func status(of _: String, in _: String, thread _: String?) async throws -> StatusLine? { nil }
    func setTyping(roomID _: String, typing _: Bool) async throws {}
    func setUnreadFrom(eventID _: String) async throws {}
    func directChat(roomID _: String, userID _: String) async throws -> String { "!dm" }
}

private final class SnapshotVoiceBackend: VoiceRecordingBackend, @unchecked Sendable {
    private let devices: [AudioInputDevice]
    private let authStatus: MicrophoneAuthStatus
    private let meterLevels: [Float]
    private let durationMS: Int
    private var index = 0
    private let tempURL = FileManager.default.temporaryDirectory.appendingPathComponent("snapshot-voice.m4a")

    init(
        devices: [AudioInputDevice] = [],
        authStatus: MicrophoneAuthStatus = .authorized,
        meterLevels: [Float] = [0.4],
        durationMS: Int = 5000
    ) {
        self.devices = devices
        self.authStatus = authStatus
        self.meterLevels = meterLevels
        self.durationMS = durationMS
    }

    func availableDevices() -> [AudioInputDevice] { devices }
    func authorizationStatus() -> MicrophoneAuthStatus { authStatus }
    func requestAccess() async -> Bool { authStatus == .authorized }
    func startRecording(deviceUID: String?) async throws -> URL {
        index = 0
        return tempURL
    }
    func currentMeterLevel() -> Float {
        guard !meterLevels.isEmpty else { return 0 }
        let level = meterLevels[min(index, meterLevels.count - 1)]
        index += 1
        return level
    }
    func stopRecording() async throws -> RecordedVoiceNote {
        RecordedVoiceNote(url: tempURL, durationMS: durationMS, waveform: [])
    }
    func cancelRecording() async {}
}
