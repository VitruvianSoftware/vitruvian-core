// Copyright 2026 VitruvianSoftware
// SPDX-License-Identifier: AGPL-3.0-or-later

import AppKit
import VitruvianCourierCore
import SwiftUI
import UserNotifications
import WebKit
import XCTest

@testable import VitruvianCourier

/// A render harness for Task 12's views: each is drawn light and dark to PNGs for a person to look at
/// (Snapshot.directory). The asserts check only that the view drew something of a sensible size; how it looks is for
/// the eye, and nothing here fails on a broken layout.
@MainActor
final class ViewSnapshotTests: XCTestCase {
    private var suites: [String] = []

    override func tearDown() async throws {
        AppLockGate.shared.resetForTesting()
        for suite in suites { UserDefaults.standard.removePersistentDomain(forName: suite) }
        suites = []
    }

    private func defaults() -> UserDefaults {
        let name = "courier.snapshots.\(UUID().uuidString)"
        suites.append(name)
        return ScratchDefaults.suite(named: name)!
    }

    /// An app model whose engine never starts: the models it feeds read nothing.
    private func offlineApp() -> AppModel {
        AppModel(supervisor: EngineSupervisor(
            enginePath: "/nonexistent/vitruvian-courier-engine",
            dataDir: FileManager.default.temporaryDirectory.appendingPathComponent("vitruvian-courier-snapshots"),
            environment: [:], launcher: FoundationProcessLauncher()))
    }

    private func collectAccessibilityIdentifiers(in root: NSView) -> Set<String> {
        func walk(_ element: AnyObject) -> [AnyObject] {
            [element] + (element.accessibilityChildren?() ?? []).flatMap { walk($0 as AnyObject) }
        }
        var ids: Set<String> = []
        // AppKit-backed controls (the tool row's buttons) are views, not accessibility children of the host.
        for node in walk(root) + root.descendants(where: { _ in true }) {
            if let id = node.accessibilityIdentifier?(), !id.isEmpty {
                ids.insert(id)
            }
        }
        return ids
    }

    /// The accessibility element with this identifier (SwiftUI controls are not views of their own).
    private func accessibilityNode(_ identifier: String, in root: NSView) -> AnyObject? {
        func walk(_ element: AnyObject) -> AnyObject? {
            if element.accessibilityIdentifier?() == identifier { return element }
            for child in element.accessibilityChildren?() ?? [] {
                if let found = walk(child as AnyObject) { return found }
            }
            return nil
        }
        return walk(root)
    }

    /// An accessibility element's frame in `host`'s coordinates.
    private func hostFrame(of node: AnyObject, in host: NSView) -> CGRect {
        let screen = node.accessibilityFrame?() ?? .zero
        guard let window = host.window else { return screen }
        return host.convert(window.convertFromScreen(screen), from: nil)
    }

    private func timeline(_ items: [TimelineItem], ui: MessageUI? = nil, actions: VitruvianCourier.MessageActions? = nil,
                          sent: String? = nil) -> some View {
        let ui = ui ?? MessageUI()
        let actions = actions ?? VitruvianCourier.MessageActions(now: { Fixture.now })
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

    private func assertLightAndDarkSnapshot<V: View>(
        _ name: String,
        width: CGFloat,
        height: CGFloat? = nil,
        prepare: @MainActor (NSView) -> Void = { _ in },
        file: StaticString = #filePath,
        line: UInt = #line,
        @ViewBuilder _ view: () -> V
    ) throws {
        let sizes = try Snapshot.render(name, width: width, height: height, prepare: prepare, view)
        check(sizes, file: file, line: line)
        let lightURL = Snapshot.directory.appendingPathComponent("\(name)-light.png")
        let darkURL = Snapshot.directory.appendingPathComponent("\(name)-dark.png")
        XCTAssertTrue(
            FileManager.default.fileExists(atPath: lightURL.path),
            "Expected light snapshot PNG \(name)-light.png to be rendered",
            file: file,
            line: line
        )
        XCTAssertTrue(
            FileManager.default.fileExists(atPath: darkURL.path),
            "Expected dark snapshot PNG \(name)-dark.png to be rendered",
            file: file,
            line: line
        )
        let lightData = try Data(contentsOf: lightURL)
        let darkData = try Data(contentsOf: darkURL)
        XCTAssertFalse(lightData.isEmpty, "Light snapshot PNG \(name)-light.png must not be empty", file: file, line: line)
        XCTAssertFalse(darkData.isEmpty, "Dark snapshot PNG \(name)-dark.png must not be empty", file: file, line: line)
        XCTAssertNotEqual(lightData, darkData, "Light and dark snapshots for \(name) must differ in appearance", file: file, line: line)
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
        var actions = VitruvianCourier.MessageActions()
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
        var actions = VitruvianCourier.MessageActions()
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
        var group = VitruvianCourier.MessageActions()
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
            for: message, available: VitruvianCourierCore.MessageActions.available(for: message, in: Fixture.features,
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

        var actions = VitruvianCourier.MessageActions()
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
            for: message, available: VitruvianCourierCore.MessageActions.available(
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
        let sizes = try Snapshot.render("chat-info-direct", width: 280, height: 900) {
            ChatInfoPane(info: info, bookmarks: bookmarks, now: { Fixture.now })
        }
        XCTAssertEqual(sizes.count, 2)
        for size in sizes {
            XCTAssertGreaterThanOrEqual(size.width, 280)
        }
    }

    func testChatInfoPaneGroupWithAdminsLightAndDark() throws {
        let info = Fixture.groupChatInfoWithAdmins()
        let sizes = try Snapshot.render("chat-info-group-admins", width: 280, height: 760) {
            ChatInfoPane(info: info, bookmarks: [], now: { Fixture.now })
        }
        XCTAssertEqual(sizes.count, 2)
        for size in sizes {
            XCTAssertGreaterThanOrEqual(size.width, 280)
        }
    }

    func testChatInfoPaneMediaGridLinksAndUnencryptedStates() throws {
        let tmpDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("chat-info-media-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tmpDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tmpDir) }

        func writeTestPNG(name: String, width: Int, height: Int, color: NSColor) throws -> String {
            let rep = try XCTUnwrap(NSBitmapImageRep(
                bitmapDataPlanes: nil,
                pixelsWide: width,
                pixelsHigh: height,
                bitsPerSample: 8,
                samplesPerPixel: 4,
                hasAlpha: true,
                isPlanar: false,
                colorSpaceName: .deviceRGB,
                bytesPerRow: 0,
                bitsPerPixel: 0
            ))
            NSGraphicsContext.saveGraphicsState()
            NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
            color.setFill()
            NSRect(x: 0, y: 0, width: width, height: height).fill()
            NSGraphicsContext.restoreGraphicsState()
            let data = try XCTUnwrap(rep.representation(using: .png, properties: [:]))
            let url = tmpDir.appendingPathComponent(name)
            try data.write(to: url)
            return url.path
        }

        let widePath = try writeTestPNG(name: "wide.png", width: 400, height: 100, color: .systemTeal)
        let tallPath = try writeTestPNG(name: "tall.png", width: 100, height: 400, color: .systemIndigo)

        var mediaEvents: [Event] = []
        for idx in 1...10 {
            var ev = Fixture.mediaEvent(
                "$m-\(idx)",
                msgtype: idx.isMultiple(of: 3) ? "m.video" : "m.image",
                body: "Photo \(idx).jpg",
                ts: idx
            )
            ev.mediaPath = idx.isMultiple(of: 2) ? widePath : tallPath
            ev.sender = idx == 1 ? "@wa_alice:courier.local" : (idx == 2 ? "" : Timeline.meUserID)
            ev.senderName = idx == 1 ? "Alice Example" : ""
            ev.mine = idx > 2
            mediaEvents.append(ev)
        }
        // Non-media link-preview message that must be filtered out of the Shared Media grid.
        var linkPreviewMsg = Fixture.text(
            "$lp-1",
            "https://vitruviansoftware.dev/courier",
            mine: false,
            ts: 11,
            sender: "@wa_alice:courier.local",
            name: "Alice Example"
        )
        linkPreviewMsg.linkPreviews = [LinkPreviewItem(matchedURL: "https://vitruviansoftware.dev/courier")]
        mediaEvents.insert(linkPreviewMsg, at: 0)

        let allAdmins = [
            Member(userID: "@wa_alice:courier.local", name: "Alice Example", isAdmin: true),
            Member(userID: "@wa_bob:courier.local", name: "Bob Example", isAdmin: true),
        ]
        XCTAssertFalse(ChatInfoPresentation.showsAdminBadge(for: allAdmins[0], in: allAdmins))
        XCTAssertEqual(ChatInfoPresentation.sharedMediaEvents(mediaEvents).count, 10)

        let dupOld = RoomLink(
            eventID: "$l1",
            sender: "@wa_alice:courier.local",
            ts: Fixture.millis(20),
            url: "https://vitruviansoftware.dev/very/long/path/to/release-notes/2026/courier",
            host: "vitruviansoftware.dev"
        )
        let dupNew = RoomLink(
            eventID: "$l2",
            sender: "@wa_bob:courier.local",
            ts: Fixture.millis(2),
            url: "https://vitruviansoftware.dev/very/long/path/to/release-notes/2026/courier",
            host: "vitruviansoftware.dev"
        )
        XCTAssertEqual(RoomLink.deduplicated([dupOld, dupNew]), [dupNew])

        var groupFeatures = Fixture.features
        groupFeatures.canLeave = true
        groupFeatures.canDelete = true

        let info = RoomInfoResult(
            roomID: "!grp-media:courier.local",
            name: "Design & Media",
            remoteName: "Design & Media",
            network: "slack",
            isDirect: false,
            encrypted: false,
            members: allAdmins,
            sharedMedia: mediaEvents,
            sharedLinks: [dupOld, dupNew],
            features: groupFeatures
        )

        let sizes = try Snapshot.render("chat-info-media-unencrypted", width: 280, height: 960) {
            ChatInfoPane(
                info: info,
                bookmarks: [],
                isMuted: true,
                isPinned: true,
                now: { Fixture.now }
            )
        }
        XCTAssertEqual(sizes.count, 2)
        for size in sizes {
            XCTAssertEqual(size.width, sizes[0].width)
            XCTAssertGreaterThanOrEqual(size.width, 280)
            XCTAssertLessThanOrEqual(size.width, 560)
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
                actions: VitruvianCourier.MessageActions(), ui: MessageUI()
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

        // 0. Empty-query mode with overflowing network chips (24pt fade), Recent chats, and A-Z Contacts.
        let overflowingAccounts = accounts + [
            Account(network: "slack", displayName: "Slack", flows: ["oauth"], state: .connected),
            Account(network: "discord", displayName: "Discord", flows: ["qr"], state: .connected),
            Account(network: "instagram", displayName: "Instagram", flows: ["cookie"], state: .connected),
            Account(network: "facebook", displayName: "Facebook Messenger", flows: ["cookie"], state: .connected),
        ]
        let sampleRecentRows = [
            Fixture.row("!dm-alice-wa:courier.local", "Alice Example", network: "whatsapp", ts: 2, preview: "Trail map?"),
            Fixture.row("!dm-carol-sig:courier.local", "Carol Example", network: "signal", ts: 5, preview: "See you at 8"),
            Fixture.row("!dm-dan-tg:courier.local", "Dan Example", network: "telegram", ts: 10, preview: "On my way"),
        ]
        let emptyDraft = StartNewChatDraft(
            accounts: overflowingAccounts,
            candidates: candidates
        )
        check(try Snapshot.render("start-new-chat-empty", width: 520, height: 520) {
            StartNewChatView(draft: emptyDraft, recentRows: sampleRecentRows)
        })

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

    func testStartNewChatPresentationEmptyQueryShowMoreAndConfirmAction() throws {
        let accounts = [
            Account(
                network: "whatsapp",
                displayName: "WhatsApp",
                flows: ["qr"],
                state: .connected,
                logins: [Login(accountID: "wa-1", remoteName: "+15550001", state: .connected)],
                canCreateGroup: true,
                canLookupEmail: false
            ),
            Account(
                network: "signal",
                displayName: "Signal",
                flows: ["qr"],
                state: .connected,
                logins: [Login(accountID: "sig-1", remoteName: "+15550002", state: .connected)],
                canCreateGroup: true,
                canLookupEmail: false
            ),
            Account(
                network: "gchat",
                displayName: "Google Chat",
                flows: ["google"],
                state: .connected,
                logins: [Login(accountID: "gc-1", remoteName: "me@example.com", state: .connected, canLookupEmail: true)],
                canCreateGroup: false,
                canLookupEmail: true
            ),
        ]

        var rows: [InboxRow] = [
            Fixture.row("!group:courier.local", "Group Chat", network: "whatsapp", direct: false, ts: 1, preview: "Hi"),
            InboxRow(
                roomID: "!hidden:courier.local",
                network: "signal",
                name: "Hidden DM",
                avatarPath: "",
                isDirect: true,
                lastTS: Fixture.millis(1),
                preview: "Hi",
                previewKind: .text,
                previewMine: false,
                unread: 0,
                muted: false,
                hidden: true
            ),
            Fixture.row("merge:alice", "Merged Alice", network: "whatsapp", direct: true, ts: 1, preview: "Hi"),
        ]
        let networks = ["whatsapp", "signal", "gchat"]
        for i in 0 ..< 10 {
            rows.append(
                Fixture.row(
                    "!dm-\(i):courier.local",
                    "Recent \(i)",
                    network: networks[i % networks.count],
                    direct: true,
                    ts: 100 - i * 5,
                    preview: "Last message"
                )
            )
        }

        let recent = StartNewChatPresentation.recentDirectChats(from: rows, accounts: accounts)
        XCTAssertEqual(recent.count, 8, "Recent section must cap at 8 most recent 1:1 chats")
        XCTAssertEqual(
            recent.compactMap(\.roomID),
            (2 ... 9).reversed().map { "!dm-\($0):courier.local" },
            "Recent chats must exclude groups, hidden chats, and merge rows, sorted newest first"
        )

        var contacts: [ContactCandidate] = [
            ContactCandidate(
                userID: "@zara:courier.local",
                name: "Zara",
                network: "whatsapp",
                accountID: "wa-1",
                identifiers: ["+1 555-019-9999"],
                roomID: "!zara:courier.local"
            ),
            ContactCandidate(
                userID: "@adam:courier.local",
                name: "adam",
                network: "signal",
                accountID: "sig-1",
                identifiers: ["+1 555-010-0001"],
                roomID: "!adam:courier.local"
            ),
        ]
        for i in (1 ... 53).reversed() {
            let padded = String(format: "%02d", i)
            contacts.append(
                ContactCandidate(
                    userID: "@p\(padded):courier.local",
                    name: "Person \(padded)",
                    network: "whatsapp",
                    accountID: "wa-1",
                    identifiers: ["+1 555-010-10\(padded)"],
                    roomID: "!p\(padded):courier.local"
                )
            )
        }

        var draft = StartNewChatDraft(accounts: accounts, candidates: contacts)
        XCTAssertFalse(StartNewChatPresentation.hasTypedQuery(draft.query))
        XCTAssertFalse(draft.showsNoMatchingContacts)

        let sorted = StartNewChatPresentation.sortedContacts(contacts, filter: nil)
        XCTAssertEqual(sorted.first?.name, "adam")
        XCTAssertEqual(sorted.last?.name, "Zara")
        XCTAssertEqual(sorted.prefix(StartNewChatPresentation.initialContactsLimit).count, 50)
        XCTAssertGreaterThan(sorted.count, 50)

        let navigable = StartNewChatPresentation.navigableRowIDs(draft: draft, recentRows: rows)
        XCTAssertEqual(navigable.filter { $0.hasPrefix("recent:") }.count, 8)
        XCTAssertEqual(navigable.filter { $0.hasPrefix("contact:") }.count, 50, "Contacts stop at 50 until Show more")
        XCTAssertTrue(navigable.first?.hasPrefix("recent:") == true, "Recent rows come before Contacts")

        XCTAssertNil(
            StartNewChatPresentation.confirmAction(draft: draft, recentRows: rows, selectedRowID: nil)
        )
        let firstRecent = try XCTUnwrap(recent.first)
        XCTAssertEqual(
            StartNewChatPresentation.confirmAction(
                draft: draft,
                recentRows: rows,
                selectedRowID: "recent:\(firstRecent.id)"
            ),
            .openDirectChat(firstRecent)
        )
        let firstContact = try XCTUnwrap(sorted.first)
        XCTAssertEqual(
            StartNewChatPresentation.confirmAction(
                draft: draft,
                recentRows: rows,
                selectedRowID: "contact:\(firstContact.id)"
            ),
            .openDirectChat(firstContact)
        )

        // Typed, and the engine's answer is empty: now (and only now) "No matching contacts found" shows.
        draft.query = "no-such-person-xyz"
        draft.candidates = []
        XCTAssertTrue(draft.showsNoMatchingContacts)
        XCTAssertNil(
            StartNewChatPresentation.confirmAction(draft: draft, recentRows: rows, selectedRowID: nil)
        )

        draft.query = "grace@example.com"
        XCTAssertFalse(draft.showsNoMatchingContacts)
        if case let .lookup(action)? = StartNewChatPresentation.confirmAction(
            draft: draft,
            recentRows: rows,
            selectedRowID: nil
        ) {
            XCTAssertEqual(action.network, "gchat")
            XCTAssertEqual(action.query, "grace@example.com")
        } else {
            XCTFail("Expected Start Chat confirm action to resolve to lookup for valid email query")
        }
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
        var mergedActions = VitruvianCourier.MessageActions()
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
            .appendingPathComponent("vitruvian-courier-snapshot-voice.ogg").path
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

        // 4b. The placeholder is a card with a 16:9 picture area, not the old tall "blocked" box: its title can come from a preview the
        // network sent, and the privacy note lives in the tooltip, not the body.
        check(try Snapshot.render("embed-consent-card-titled", width: 360) {
            EmbedConsentCard(
                messageID: "$embed-2",
                descriptor: descriptor,
                isLoaded: false,
                title: "Never Gonna Give You Up (Official Video)",
                onLoadEmbed: {}
            )
            .padding(14)
        })
        let compact = NSHostingView(
            rootView: EmbedConsentCard(messageID: "$embed-1", descriptor: descriptor, isLoaded: false, onLoadEmbed: {})
                .frame(width: 320)
        )
        // A 16:9 picture the width of the card (320 -> 180 high) with the title and site under it.
        XCTAssertGreaterThanOrEqual(compact.fittingSize.height, 320 * 9 / 16, "the card holds a 16:9 picture")
        XCTAssertLessThanOrEqual(compact.fittingSize.height, 320 * 9 / 16 + 64, "and one title row under it")
        XCTAssertEqual(descriptor.siteName, "YouTube")
        XCTAssertEqual(descriptor.fallbackTitle, "Watch on YouTube")

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
            + LinkPreviewCardView<EmptyView>.userVisibleStrings
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
            .appendingPathComponent("vitruvian-courier-snapshot-2page-\(UUID().uuidString).pdf")
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
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("vitruvian-courier-snapshot-\(width)x\(height).png")
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
            CarouselItem(
                eventID: "$c3",
                roomID: Fixture.room,
                kind: .image,
                mediaPath: "",
                thumbnailPath: "",
                fileName: "Uncached.jpg",
                mimeType: "image/jpeg",
                sender: "@alice:courier.local",
                senderName: "Alice Example",
                mine: false,
                ts: Fixture.millis(5),
                caption: ""
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
            .appendingPathComponent("vitruvian-courier-vo-test-\(UUID().uuidString)", isDirectory: true)
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
        // A lookup never reads the file on the calling thread; it is read ahead (what `LocalFileFacts.warm` does).
        XCTAssertNil(InlinePDFDocumentCache.shared.document(atPath: pdfPath), "a cold lookup does not parse on the caller")
        XCTAssertEqual(InlinePDFDocumentCache.shared.parseCount, 0)
        InlinePDFDocumentCache.shared.parse(path: pdfPath)
        let first = InlinePDFDocumentCache.shared.document(atPath: pdfPath)
        let second = InlinePDFDocumentCache.shared.document(atPath: pdfPath)
        XCTAssertNotNil(first)
        XCTAssertTrue(first === second, "repeated lookups for the same path must return the cached PDFDocument instance")
        XCTAssertEqual(InlinePDFDocumentCache.shared.parseCount, 1, "PDF must be parsed only once per path")
    }

    func testNotifierAttachmentSetsTypeHintFromMIMEAndCleansUpTempDirectory() throws {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("vitruvian-courier-notif-src-\(UUID().uuidString)", isDirectory: true)
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
            "cleanup must remove the vitruvian-courier-notif-* temporary directory"
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

    // MARK: - Milestone 4.5c Task 8: GIFPickerStrip and pending GIF pill snapshots

    func testGIFPickerPopoverAndPendingGIFSnapshots() throws {
        let emptyModel = composer(text: "")
        check(try Snapshot.render("gif-picker-empty", width: 620) {
            GIFPickerStrip(composer: emptyModel)
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
        check(try Snapshot.render("gif-picker-populated", width: 620) {
            GIFPickerStrip(composer: populatedModel)
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

    // MARK: - Milestone 4.5c Task 9 & Batch 6 Package A: Inline tool row, network badge, visible send, Tab focus

    func testComposerToolbarAndPlusMenuStickerGIFAndEmojiEntryPoints() throws {
        _ = NSApplication.shared
        let attribute = "AXEnhancedUserInterface"
        let getter = NSSelectorFromString("accessibilityAttributeValue:")
        let setter = NSSelectorFromString("accessibilitySetValue:forAttribute:")
        let previousAX = NSApp.perform(getter, with: attribute)?.takeUnretainedValue() as? NSNumber ?? false
        NSApp.perform(setter, with: true, with: attribute)
        defer { NSApp.perform(setter, with: previousAX, with: attribute) }

        let preferences = ComposerPreferences(defaults: defaults())
        let model = composer(text: "Weekend trail crew!")
        model.entitlement = AlwaysEntitled()
        model.preferences = preferences
        XCTAssertTrue(
            model.canSend,
            "composer in an open room with text must have canSend == true so the send arrow is active in the snapshot"
        )
        XCTAssertEqual(model.addGIFMenuTitle, "Add GIF…")
        XCTAssertEqual(model.addStickerMenuTitle, "Add Sticker…")

        // Closed state: duplicate inline attach/GIF/voice icons inside the text box are gone;
        // '+' toggle, leading network badge, outline emoji button, and send button are present.
        var collapsedIDs: Set<String> = []
        check(try Snapshot.render("composer-toolbar-media", width: 620, prepare: { host in
            collapsedIDs = self.collectAccessibilityIdentifiers(in: host)
        }) {
            ComposerView(
                composer: model,
                preferences: preferences,
                textHeight: .constant(ComposerTextView.minimumHeight),
                menus: ComposerMenus(sendLater: {}, createPoll: {}, pollsUnavailable: nil)
            )
        })
        XCTAssertFalse(collapsedIDs.contains("composer.leading.attach"))
        XCTAssertFalse(collapsedIDs.contains("composer.leading.gif"))
        XCTAssertFalse(collapsedIDs.contains("composer.leading.voiceNote"))
        XCTAssertTrue(collapsedIDs.contains("composer.plus"))
        XCTAssertTrue(collapsedIDs.contains("composer.field.networkBadge"))
        XCTAssertTrue(collapsedIDs.contains("composer.toolbar.emoji"))
        XCTAssertTrue(collapsedIDs.contains("composer.send"))

        // Expanded state: all tools appear inline in order when the network supports them.
        model.features.locationSupported = true
        model.isToolRowOpen = true
        var expandedIDs: Set<String> = []
        check(try Snapshot.render("composer-toolbar-expanded", width: 620, prepare: { host in
            expandedIDs = self.collectAccessibilityIdentifiers(in: host)
        }) {
            ComposerView(
                composer: model,
                preferences: preferences,
                textHeight: .constant(ComposerTextView.minimumHeight),
                menus: ComposerMenus(sendLater: {}, createPoll: {}, pollsUnavailable: nil)
            )
        })
        for kind in ComposerToolKind.allCases {
            XCTAssertTrue(expandedIDs.contains(kind.accessibilityIdentifier), "Missing \(kind.accessibilityIdentifier)")
        }

        // Network without GIF, Photo, or Poll omits those tools instead of showing greyed placeholders.
        let noGIFModel = composer(text: "No GIF button on networks without GIF support")
        noGIFModel.entitlement = AlwaysEntitled()
        noGIFModel.preferences = preferences
        noGIFModel.network = "gchat"
        noGIFModel.features = ChatFeatures(
            reply: true,
            formatting: [.bold, .italic, .link],
            source: .stored,
            imageFeatures: FileKindFeatures(supported: false, mimeTypes: []),
            voiceFeatures: FileKindFeatures(supported: true, mimeTypes: ["audio/mp4"]),
            fileFeatures: FileKindFeatures(supported: true, mimeTypes: ["*/*"])
        )
        noGIFModel.isToolRowOpen = true
        XCTAssertFalse(noGIFModel.canSendGIF)
        var noGIFToolbarIDs: Set<String> = []
        check(try Snapshot.render("composer-toolbar-no-gif", width: 620, prepare: { host in
            noGIFToolbarIDs = self.collectAccessibilityIdentifiers(in: host)
        }) {
            ComposerView(
                composer: noGIFModel,
                preferences: preferences,
                textHeight: .constant(ComposerTextView.minimumHeight),
                menus: ComposerMenus(sendLater: {}, createPoll: {}, pollsUnavailable: nil)
            )
        })
        XCTAssertTrue(noGIFToolbarIDs.contains(ComposerToolKind.attachFile.accessibilityIdentifier))
        XCTAssertTrue(noGIFToolbarIDs.contains(ComposerToolKind.voiceNote.accessibilityIdentifier))
        XCTAssertTrue(noGIFToolbarIDs.contains(ComposerToolKind.sendLater.accessibilityIdentifier))
        XCTAssertTrue(noGIFToolbarIDs.contains(ComposerToolKind.ai.accessibilityIdentifier))
        XCTAssertFalse(noGIFToolbarIDs.contains(ComposerToolKind.gif.accessibilityIdentifier))
        XCTAssertFalse(noGIFToolbarIDs.contains(ComposerToolKind.photo.accessibilityIdentifier))
        XCTAssertFalse(noGIFToolbarIDs.contains(ComposerToolKind.poll.accessibilityIdentifier))
    }

    func testComposerNetworkBadgeVisibleSendAndTabFocus() throws {
        _ = NSApplication.shared
        let attribute = "AXEnhancedUserInterface"
        let getter = NSSelectorFromString("accessibilityAttributeValue:")
        let setter = NSSelectorFromString("accessibilitySetValue:forAttribute:")
        let previousAX = NSApp.perform(getter, with: attribute)?.takeUnretainedValue() as? NSNumber ?? false
        NSApp.perform(setter, with: true, with: attribute)
        defer { NSApp.perform(setter, with: previousAX, with: attribute) }

        let preferences = ComposerPreferences(defaults: defaults())

        // A3 + A4: Empty draft still displays network badge and a visible neutral-grey circle + white arrow send button.
        let emptyModel = composer(text: "")
        emptyModel.preferences = preferences
        emptyModel.network = "whatsapp"
        var emptyIDs: Set<String> = []
        check(try Snapshot.render("composer-empty-visible-send", width: 620, prepare: { host in
            emptyIDs = self.collectAccessibilityIdentifiers(in: host)
        }) {
            ComposerView(
                composer: emptyModel,
                preferences: preferences,
                textHeight: .constant(ComposerTextView.minimumHeight),
                menus: ComposerMenus(sendLater: {}, createPoll: {}, pollsUnavailable: nil)
            )
        })
        XCTAssertTrue(emptyIDs.contains("composer.field.networkBadge"))
        XCTAssertTrue(emptyIDs.contains("composer.send"))

        // Render light bitmap for empty send button and verify neutral grey circle + white arrow are actually drawn.
        func renderLightBitmap(for model: ComposerModel) throws -> NSBitmapImageRep {
            let size = NSSize(width: 480, height: 60)
            let root = ComposerView(
                composer: model,
                preferences: preferences,
                textHeight: .constant(ComposerTextView.minimumHeight),
                menus: ComposerMenus(sendLater: {}, createPoll: {}, pollsUnavailable: nil)
            )
            .frame(width: size.width, height: size.height)
            .background(Color(nsColor: .windowBackgroundColor))
            .environment(\.themeAccentHex, "#0A84FF")
            let host = NSHostingView(rootView: root)
            host.appearance = NSAppearance(named: .aqua)
            let window = NSWindow(
                contentRect: NSRect(origin: .zero, size: size),
                styleMask: [.borderless],
                backing: .buffered,
                defer: false
            )
            window.appearance = NSAppearance(named: .aqua)
            window.contentView = host
            host.frame = NSRect(origin: .zero, size: size)
            host.layoutSubtreeIfNeeded()
            for _ in 0 ..< 20 {
                RunLoop.main.run(mode: .default, before: Date(timeIntervalSinceNow: 0.004))
                host.layoutSubtreeIfNeeded()
            }
            window.displayIfNeeded()
            let bitmap = try XCTUnwrap(host.bitmapImageRepForCachingDisplay(in: host.bounds))
            host.cacheDisplay(in: host.bounds, to: bitmap)
            window.contentView = nil
            return bitmap
        }

        let emptyBitmap = try renderLightBitmap(for: emptyModel)
        let scale = max(1, emptyBitmap.pixelsWide / 480)
        let xStart = max(0, emptyBitmap.pixelsWide - 48 * scale)
        var foundWhiteInsideGreyCircle = false
        for y in 0 ..< emptyBitmap.pixelsHigh {
            var greyLeft = false
            var whiteMid = false
            for x in xStart ..< emptyBitmap.pixelsWide {
                guard let color = emptyBitmap.colorAt(x: x, y: y)?.usingColorSpace(.sRGB) else { continue }
                let spread = max(color.redComponent, max(color.greenComponent, color.blueComponent))
                    - min(color.redComponent, min(color.greenComponent, color.blueComponent))
                let isNeutralGrey = spread < 0.08 && color.redComponent > 0.35 && color.redComponent < 0.75
                let isWhite = color.redComponent > 0.88 && color.greenComponent > 0.88 && color.blueComponent > 0.88
                if isNeutralGrey {
                    if whiteMid {
                        foundWhiteInsideGreyCircle = true
                        break
                    }
                    greyLeft = true
                } else if greyLeft, isWhite {
                    whiteMid = true
                } else {
                    greyLeft = false
                    whiteMid = false
                }
            }
            if foundWhiteInsideGreyCircle { break }
        }
        XCTAssertTrue(
            foundWhiteInsideGreyCircle,
            "Empty composer send button must draw a clearly visible neutral grey filled circle with a white arrow"
        )

        // When draft has text, send circle switches to accent color (non-neutral) with white arrow.
        let sendableModel = composer(text: "Hello")
        sendableModel.preferences = preferences
        sendableModel.network = "whatsapp"
        let sendableBitmap = try renderLightBitmap(for: sendableModel)
        var foundWhiteInsideAccentCircle = false
        for y in 0 ..< sendableBitmap.pixelsHigh {
            var accentLeft = false
            var whiteMid = false
            for x in xStart ..< sendableBitmap.pixelsWide {
                guard let color = sendableBitmap.colorAt(x: x, y: y)?.usingColorSpace(.sRGB) else { continue }
                let isBlueAccent = color.blueComponent - color.redComponent > 0.25
                let isWhite = color.redComponent > 0.88 && color.greenComponent > 0.88 && color.blueComponent > 0.88
                if isBlueAccent {
                    if whiteMid {
                        foundWhiteInsideAccentCircle = true
                        break
                    }
                    accentLeft = true
                } else if accentLeft, isWhite {
                    whiteMid = true
                } else {
                    accentLeft = false
                    whiteMid = false
                }
            }
            if foundWhiteInsideAccentCircle { break }
        }
        XCTAssertTrue(
            foundWhiteInsideAccentCircle,
            "Sendable composer send button must draw an accent-colored filled circle with a white arrow"
        )

        // A5: Tab moves focus to next control, Shift-Tab to previous, Option-Tab inserts a literal tab.
        let focusModel = composer(text: "")
        focusModel.preferences = preferences
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 640, height: 180),
            styleMask: [.titled],
            backing: .buffered,
            defer: false
        )
        let container = NSView(frame: NSRect(x: 0, y: 0, width: 640, height: 180))
        let prevField = NSTextField(frame: NSRect(x: 16, y: 120, width: 200, height: 24))
        let host = NSHostingView(
            rootView: ComposerView(
                composer: focusModel,
                preferences: preferences,
                textHeight: .constant(ComposerTextView.minimumHeight),
                menus: ComposerMenus(sendLater: {}, createPoll: {}, pollsUnavailable: nil)
            )
        )
        host.frame = NSRect(x: 16, y: 50, width: 608, height: 60)
        let nextField = NSTextField(frame: NSRect(x: 16, y: 16, width: 200, height: 24))
        container.addSubview(prevField)
        container.addSubview(host)
        container.addSubview(nextField)
        window.contentView = container
        container.layoutSubtreeIfNeeded()
        host.layoutSubtreeIfNeeded()
        for _ in 0 ..< 15 {
            RunLoop.main.run(mode: .default, before: Date(timeIntervalSinceNow: 0.004))
            host.layoutSubtreeIfNeeded()
        }
        let textView = try XCTUnwrap(host.first(PlainTextView.self))
        prevField.nextKeyView = textView
        textView.nextKeyView = nextField

        XCTAssertTrue(window.makeFirstResponder(textView))
        textView.doCommand(by: #selector(NSResponder.insertTab(_:)))
        XCTAssertEqual(textView.string, "", "Plain Tab must never insert whitespace")
        XCTAssertTrue(window.firstResponder !== textView, "Plain Tab must move focus out of message box")

        XCTAssertTrue(window.makeFirstResponder(textView))
        textView.doCommand(by: #selector(NSResponder.insertBacktab(_:)))
        XCTAssertEqual(textView.string, "", "Shift-Tab must never insert whitespace")
        XCTAssertTrue(window.firstResponder !== textView, "Shift-Tab must move focus to previous control")

        XCTAssertTrue(window.makeFirstResponder(textView))
        textView.doCommand(by: #selector(NSResponder.insertTabIgnoringFieldEditor(_:)))
        XCTAssertEqual(textView.string, "\t", "Option-Tab must insert a literal tab")
        XCTAssertEqual(focusModel.text, "\t")
        window.contentView = nil
    }

    /// A narrow composer (the thread pane) with every tool open must still leave the text box usable, and an
    /// unknown network id must still get a badge in the field (A1, A3).
    func testComposerNarrowExpandedToolRowKeepsFieldUsableAndUnknownNetworkBadge() throws {
        _ = NSApplication.shared
        let attribute = "AXEnhancedUserInterface"
        let getter = NSSelectorFromString("accessibilityAttributeValue:")
        let setter = NSSelectorFromString("accessibilitySetValue:forAttribute:")
        let previousAX = NSApp.perform(getter, with: attribute)?.takeUnretainedValue() as? NSNumber ?? false
        NSApp.perform(setter, with: true, with: attribute)
        defer { NSApp.perform(setter, with: previousAX, with: attribute) }

        let preferences = ComposerPreferences(defaults: defaults())
        let model = composer(text: "")
        model.entitlement = AlwaysEntitled()
        model.preferences = preferences
        model.network = "some-future-network"
        model.features.locationSupported = true
        model.isToolRowOpen = true
        check(try Snapshot.render("composer-toolbar-expanded-narrow", width: 340) {
            ComposerView(
                composer: model,
                preferences: preferences,
                textHeight: .constant(ComposerTextView.minimumHeight),
                menus: ComposerMenus(sendLater: {}, createPoll: {}, pollsUnavailable: nil)
            )
        })

        // The text box keeps real room beside the open tool row at the narrowest widths a composer gets
        // (the thread pane, and the main window's 480pt minimum), and still fits inside its own width.
        for width in [340.0, 480.0] {
            let window = NSWindow(
                contentRect: NSRect(x: 0, y: 0, width: width, height: 120),
                styleMask: [.titled],
                backing: .buffered,
                defer: false
            )
            let host = NSHostingView(
                rootView: ComposerView(
                    composer: model,
                    preferences: preferences,
                    textHeight: .constant(ComposerTextView.minimumHeight),
                    menus: ComposerMenus(sendLater: {}, createPoll: {}, pollsUnavailable: nil)
                )
                .frame(width: width)
            )
            host.frame = NSRect(x: 0, y: 0, width: width, height: 60)
            window.contentView = host
            host.layoutSubtreeIfNeeded()
            for _ in 0 ..< 25 {
                RunLoop.main.run(mode: .default, before: Date(timeIntervalSinceNow: 0.004))
                host.layoutSubtreeIfNeeded()
            }
            let ids = collectAccessibilityIdentifiers(in: host)
            XCTAssertTrue(ids.contains("composer.field.networkBadge"), "an unknown network id still gets a field badge")
            let textView = try XCTUnwrap(host.first(PlainTextView.self))
            let frame = textView.convert(textView.bounds, to: host)
            let minimum = width >= 480
                ? ComposerToolRowMetrics.fieldMinimumWidth : ComposerToolRowMetrics.fieldHardMinimumWidth
            XCTAssertGreaterThanOrEqual(
                frame.width, minimum - 0.5, "text box too narrow with tools open at \(width)pt: \(frame)")
            XCTAssertLessThanOrEqual(frame.maxX, width, "text box runs past the composer at \(width)pt: \(frame)")
            // ✕ and Send stay on screen, and the row (clipped, scrolling) never pushes past the composer.
            let plus = try XCTUnwrap(host.firstDescendant { $0 is ComposerKeyProxyButton })
            let send = try XCTUnwrap(accessibilityNode("composer.send", in: host))
            let plusFrame = plus.convert(plus.bounds, to: host)
            let sendFrame = hostFrame(of: send, in: host)
            XCTAssertGreaterThanOrEqual(plusFrame.minX, 0, "✕ off screen at \(width)pt")
            XCTAssertLessThanOrEqual(sendFrame.maxX, width + 0.5, "Send off screen at \(width)pt: \(sendFrame)")
            let firstTool = try XCTUnwrap(
                host.firstDescendant { $0.accessibilityIdentifier() == ComposerToolKind.attachFile.accessibilityIdentifier })
            let toolFrame = firstTool.convert(firstTool.bounds, to: host)
            XCTAssertLessThanOrEqual(toolFrame.minX, frame.minX, "the row sits before the text box at \(width)pt")
            window.contentView = nil
        }
    }

    /// Hosts the composer in a window with the tool row open and returns what the keyboard tests need.
    private func hostOpenToolRow(
        model: ComposerModel, preferences: ComposerPreferences, width: CGFloat = 640
    ) -> (window: NSWindow, host: NSHostingView<some View>) {
        _ = NSApplication.shared
        let attribute = "AXEnhancedUserInterface"
        let setter = NSSelectorFromString("accessibilitySetValue:forAttribute:")
        NSApp.perform(setter, with: true, with: attribute)
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: width, height: 140),
            styleMask: [.titled], backing: .buffered, defer: false)
        let host = NSHostingView(
            rootView: ComposerView(
                composer: model,
                preferences: preferences,
                textHeight: .constant(ComposerTextView.minimumHeight),
                menus: ComposerMenus(sendLater: {}, createPoll: {}, pollsUnavailable: nil)
            ).frame(width: width))
        host.frame = NSRect(x: 0, y: 0, width: width, height: 60)
        window.contentView = host
        pump(host, times: 25)
        return (window, host)
    }

    private func pump(_ host: NSView, times: Int = 15) {
        host.layoutSubtreeIfNeeded()
        for _ in 0 ..< times {
            RunLoop.main.run(mode: .default, before: Date(timeIntervalSinceNow: 0.01))
            host.layoutSubtreeIfNeeded()
        }
    }

    private func keyEvent(_ code: UInt16, characters: String, modifiers: NSEvent.ModifierFlags = []) -> NSEvent {
        NSEvent.keyEvent(
            with: .keyDown, location: .zero, modifierFlags: modifiers, timestamp: 0, windowNumber: 0, context: nil,
            characters: characters, charactersIgnoringModifiers: characters, isARepeat: false, keyCode: code)!
    }

    func testToolRowIsReachableByKeyboardAndEscapeClosesItFromAnyTool() throws {
        _ = NSApplication.shared
        let preferences = ComposerPreferences(defaults: defaults())
        let model = composer(text: "")
        model.entitlement = AlwaysEntitled()
        model.preferences = preferences
        model.features.locationSupported = true
        let (window, host) = hostOpenToolRow(model: model, preferences: preferences)
        defer { window.contentView = nil }
        let textView = try XCTUnwrap(host.first(PlainTextView.self))
        let proxy = try XCTUnwrap(host.firstDescendant { $0 is ComposerKeyProxyButton } as? ComposerKeyProxyButton)

        // The + is a key view (Tab reaches it with no system keyboard-navigation setting) and Space opens the row
        // and moves focus to its first tool.
        XCTAssertTrue(proxy.canBecomeKeyView)
        XCTAssertTrue(window.makeFirstResponder(proxy))
        proxy.keyDown(with: keyEvent(49, characters: " "))
        pump(host)
        XCTAssertTrue(model.isToolRowOpen)
        let tools = host.descendants { $0 is ComposerToolNSButton }.compactMap { $0 as? ComposerToolNSButton }
        XCTAssertGreaterThanOrEqual(tools.count, 7)
        let first = try XCTUnwrap(tools.first { $0.accessibilityIdentifier() == ComposerToolKind.attachFile.accessibilityIdentifier })
        XCTAssertTrue(window.firstResponder === first, "opening by keyboard focuses the first tool")

        // Every tool is a key view, so Tab walks the row.
        XCTAssertTrue(tools.allSatisfy(\.canBecomeKeyView))
        var visited: Set<String> = []
        XCTAssertTrue(window.makeFirstResponder(textView))
        for _ in 0 ..< 40 {
            window.selectNextKeyView(nil)
            if let button = window.firstResponder as? ComposerToolNSButton {
                visited.insert(button.accessibilityIdentifier())
            }
        }
        for kind in [ComposerToolKind.attachFile, .photo, .gif, .sticker, .voiceNote, .sendLater, .poll, .location, .ai] {
            XCTAssertTrue(visited.contains(kind.accessibilityIdentifier), "Tab never reached \(kind)")
        }

        // Escape from any tool (not only the text box) closes the row and returns focus to the text.
        for button in tools {
            model.isToolRowOpen = true
            pump(host, times: 5)
            XCTAssertTrue(window.makeFirstResponder(button))
            button.keyDown(with: keyEvent(53, characters: "\u{1B}"))
            pump(host)
            XCTAssertFalse(model.isToolRowOpen, "Escape from \(button.accessibilityIdentifier()) left the row open")
            XCTAssertTrue(
                window.firstResponder === textView,
                "Escape from \(button.accessibilityIdentifier()) did not return focus to the text")
        }

        // The + toggled again by keyboard closes the row too.
        XCTAssertTrue(window.makeFirstResponder(proxy))
        proxy.keyDown(with: keyEvent(36, characters: "\r"))
        pump(host)
        XCTAssertTrue(model.isToolRowOpen)
        let closeProxy = try XCTUnwrap(host.firstDescendant { $0 is ComposerKeyProxyButton } as? ComposerKeyProxyButton)
        closeProxy.keyDown(with: keyEvent(53, characters: "\u{1B}"))
        pump(host)
        XCTAssertFalse(model.isToolRowOpen)
    }

    func testTabAcceptsAnOpenEmojiSuggestionInsteadOfMovingFocus() throws {
        _ = NSApplication.shared
        let preferences = ComposerPreferences(defaults: defaults())
        let model = composer(text: "")
        model.preferences = preferences
        let (window, host) = hostOpenToolRow(model: model, preferences: preferences)
        defer { window.contentView = nil }
        let textView = try XCTUnwrap(host.first(PlainTextView.self))
        XCTAssertTrue(window.makeFirstResponder(textView))

        textView.insertText("hello :smi", replacementRange: textView.selectedRange())
        pump(host)
        XCTAssertEqual(model.emojiQuery, "smi", "the emoji picker should be open")
        XCTAssertFalse(model.emojiCandidates.isEmpty)

        textView.doCommand(by: #selector(NSResponder.insertTab(_:)))
        pump(host)
        XCTAssertNil(model.emojiQuery, "Tab accepts the suggestion and closes the picker")
        XCTAssertFalse(model.text.contains(":smi"), "the :smi shortcode was replaced: \(model.text)")
        XCTAssertFalse(model.text.contains("\t"), "Tab must not insert whitespace: \(model.text)")
        XCTAssertTrue(window.firstResponder === textView, "accepting a suggestion keeps focus in the text")
    }

    func testDisabledSendIsReportedUnavailableAndEnabledSendIsNot() throws {
        _ = NSApplication.shared
        let preferences = ComposerPreferences(defaults: defaults())
        let empty = composer(text: "")
        empty.preferences = preferences
        let (emptyWindow, emptyHost) = hostOpenToolRow(model: empty, preferences: preferences)
        defer { emptyWindow.contentView = nil }
        let sendEmpty = try XCTUnwrap(accessibilityNode("composer.send", in: emptyHost))
        XCTAssertEqual(
            sendEmpty.isAccessibilityEnabled?(), false, "an empty draft's Send must be unavailable to VoiceOver")

        let full = composer(text: "Hello")
        full.preferences = preferences
        let (fullWindow, fullHost) = hostOpenToolRow(model: full, preferences: preferences)
        defer { fullWindow.contentView = nil }
        let sendFull = try XCTUnwrap(accessibilityNode("composer.send", in: fullHost))
        XCTAssertEqual(sendFull.isAccessibilityEnabled?(), true)
    }

    func testReactionPillAvatarsAndOverflowSnapshot() throws {
        var events = [
            Fixture.text("$rx0", "Who is in for dinner on Friday?", mine: false, ts: 20, name: "Kent Hua"),
            Fixture.text("$rx1", "Count me in!", mine: true, ts: 15),
        ]
        // 1 known reactor ("Kent Hua")
        events.append(Fixture.event("$r-one", type: "m.reaction", mine: false, ts: 14, content: [
            "m.relates_to": .object(["rel_type": .string("m.annotation"), "event_id": .string("$rx0"), "key": .string("❤️")]),
        ], sender: "@kent:courier.local", name: "Kent Hua"))
        // 5 known reactors -> 3 avatars + "+2", including me (own reaction highlight)
        let reactors = ["Kent Hua", "Eddie Stecker", "Ann Example", "Bo Example", "Cy Example"]
        for (idx, name) in reactors.enumerated() {
            events.append(Fixture.event("$r-many-\(idx)", type: "m.reaction", mine: idx == 1, ts: 13 - idx, content: [
                "m.relates_to": .object(["rel_type": .string("m.annotation"), "event_id": .string("$rx0"), "key": .string("👍")]),
            ], sender: idx == 1 ? nil : "@u\(idx):courier.local", name: name))
        }
        let ui = MessageUI()
        let actions = VitruvianCourier.MessageActions(now: { Fixture.now })
        let builtFirst = Fixture.messages(events).first
        let unknownReactorMsg = TimelineMessage(
            id: "$rx1",
            roomID: Fixture.room,
            sender: Timeline.meUserID,
            senderName: "",
            senderAvatarPath: "",
            mine: true,
            ts: Fixture.millis(15),
            kind: .text,
            body: "Count me in!",
            rich: RichText(text: "Count me in!"),
            isEdited: false,
            editCount: 0,
            editFailed: nil,
            failedEditID: nil,
            fileName: "",
            mimeType: "",
            byteSize: nil,
            width: nil,
            height: nil,
            mediaPath: "",
            statusLine: .sent,
            countsAsUnread: false,
            poll: nil,
            thread: nil,
            bookmarked: false,
            expiresAt: nil,
            timerChange: nil,
            call: nil,
            reply: nil,
            reactions: [ReactionChip(key: "🔥", count: 4, mine: false)],
            startsGroup: true
        )
        let items: [TimelineItem] = (builtFirst.map { [.message($0)] } ?? []) + [.message(unknownReactorMsg)]
        try assertLightAndDarkSnapshot("reaction-pills-avatars", width: 620) {
            timeline(items, ui: ui, actions: actions)
        }

        let redactedAppearance = AppearancePreferences(defaults: defaults())
        redactedAppearance.redactNamesAndPictures = true
        var redactedActions = VitruvianCourier.MessageActions(now: { Fixture.now })
        redactedActions.appearance = redactedAppearance
        try assertLightAndDarkSnapshot("reaction-pills-redacted-card", width: 620) {
            timeline(items, ui: ui, actions: redactedActions)
                .environment(\.appearancePreferences, redactedAppearance)
                .environment(\.redactNamesAndPictures, true)
                .environment(\.reactionCardOverride, ReactionCardOverride(messageID: "$rx0", reactionKey: "👍"))
        }

        let senderItems = Fixture.items([
            Fixture.text("$sa1", "On my way!", mine: false, ts: 20, sender: "@kent:courier.local", name: "Kent Hua"),
        ], isDirect: false)
        let defaultActions = VitruvianCourier.MessageActions(now: { Fixture.now })
        try assertLightAndDarkSnapshot("sender-avatar-unredacted", width: 560) {
            timeline(senderItems, ui: ui, actions: defaultActions)
        }
        try assertLightAndDarkSnapshot("sender-avatar-redacted", width: 560) {
            timeline(senderItems, ui: ui, actions: defaultActions)
                .environment(\.redactNamesAndPictures, true)
        }
        let unredactedLight = try Data(contentsOf: Snapshot.directory.appendingPathComponent("sender-avatar-unredacted-light.png"))
        let redactedLight = try Data(contentsOf: Snapshot.directory.appendingPathComponent("sender-avatar-redacted-light.png"))
        XCTAssertNotEqual(
            redactedLight,
            unredactedLight,
            "Redacting via redactNamesAndPictures environment must change the rendered sender avatar and name"
        )
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
            .appendingPathComponent("vitruvian-courier-snapshot-sticker-\(width)x\(height).png")
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
        for _ in 0 ..< 50 {
            try await Task.sleep(nanoseconds: 2_000_000)
            stickerHost.layoutSubtreeIfNeeded()
            if findNSImageView(in: stickerHost) != nil { break }
        }
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
        for _ in 0 ..< 50 {
            try await Task.sleep(nanoseconds: 2_000_000)
            gifHost.layoutSubtreeIfNeeded()
            if findNSImageView(in: gifHost) != nil { break }
        }
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
        check(try Snapshot.render("gif-picker-search-query", width: 620) {
            GIFPickerStrip(composer: gifQueryModel)
        })
    }

    func testStickerAndGIFViewsLoadAsynchronouslyInTaskNotBody() async throws {
        let stickerPath = try makeTestStickerPNG(width: 140, height: 140)
        let gifPath = try makeTestPNG(width: 240, height: 140)

        let stickerEvent = Fixture.sticker(
            "$sticker-async",
            name: "Async Parrot",
            emoji: "🦜",
            mine: false,
            ts: 15,
            mediaPath: stickerPath,
            width: 140,
            height: 140
        )
        let stickerMsg = try XCTUnwrap(Fixture.messages([stickerEvent]).first)
        let sticker = try XCTUnwrap(stickerMsg.sticker)

        let gifEvent = Fixture.gif(
            "$gif-async",
            msgtype: "m.image",
            fileName: "async.gif",
            caption: nil,
            mine: false,
            ts: 16,
            mediaPath: gifPath,
            mimeType: "image/gif",
            width: 240,
            height: 140
        )
        let gifMsg = try XCTUnwrap(Fixture.messages([gifEvent]).first)
        let gif = try XCTUnwrap(gifMsg.gif)

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 400, height: 400),
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        let stickerHost = NSHostingView(
            rootView: StickerAttachmentView(message: stickerMsg, sticker: sticker)
        )
        stickerHost.frame = NSRect(x: 0, y: 0, width: 200, height: 200)
        window.contentView = stickerHost
        stickerHost.layoutSubtreeIfNeeded()

        XCTAssertNil(
            findNSImageView(in: stickerHost),
            "StickerAttachmentView must not synchronously read or decode files inside body before .task(id:) runs"
        )
        for _ in 0 ..< 50 {
            try await Task.sleep(nanoseconds: 2_000_000)
            stickerHost.layoutSubtreeIfNeeded()
            if findNSImageView(in: stickerHost) != nil { break }
        }
        XCTAssertNotNil(
            findNSImageView(in: stickerHost),
            "StickerAttachmentView must populate @State image once .task(id:) completes"
        )

        let gifHost = NSHostingView(
            rootView: GIFAttachmentView(message: gifMsg, gif: gif)
        )
        gifHost.frame = NSRect(x: 0, y: 0, width: 300, height: 200)
        window.contentView = gifHost
        gifHost.layoutSubtreeIfNeeded()

        XCTAssertNil(
            findNSImageView(in: gifHost),
            "GIFAttachmentView must not synchronously read or decode files inside body before .task(id:) runs"
        )
        for _ in 0 ..< 50 {
            try await Task.sleep(nanoseconds: 2_000_000)
            gifHost.layoutSubtreeIfNeeded()
            if findNSImageView(in: gifHost) != nil { break }
        }
        XCTAssertNotNil(
            findNSImageView(in: gifHost),
            "GIFAttachmentView must populate @State image once .task(id:) completes"
        )
    }

    // MARK: - Part 4.6 Task 6: App Lock Overlay

    func testAppLockOverlayLightAndDark() async throws {
        let model = SystemLifecycleModel(
            loginItemService: SnapshotLoginItemService(),
            biometricService: SnapshotBiometricService(),
            defaults: defaults()
        )
        model.autoLockEnabled = true
        model.lockNow()
        check(try Snapshot.render("app-lock-overlay", width: 520, height: 360) {
            AppLockOverlay(model: model)
        })
    }

    func testNotifierRestartNotificationCenterClearsDeliveredKillsDaemonAndReRequestsSettings() {
        let notifier = Notifier()
        var openedURLs: [URL] = []
        var removedAllCount = 0
        var killedProcesses: [(URL, [String])] = []
        var requestedSettingsCount = 0

        notifier.openURLHandler = { openedURLs.append($0) }
        notifier.removeAllDeliveredHandler = { removedAllCount += 1 }
        notifier.runProcessHandler = { url, args in killedProcesses.append((url, args)) }
        notifier.requestSettingsHandler = { requestedSettingsCount += 1 }

        notifier.openSystemNotificationSettings()
        XCTAssertEqual(
            openedURLs.map(\.absoluteString),
            ["x-apple.systempreferences:com.apple.Notifications-Settings.extension"]
        )

        notifier.restartNotificationCenter()
        XCTAssertEqual(removedAllCount, 1, "restartNotificationCenter must remove all delivered notifications")
        XCTAssertEqual(killedProcesses.count, 1, "restartNotificationCenter must invoke /usr/bin/killall NotificationCenter")
        XCTAssertEqual(killedProcesses.first?.0.path, "/usr/bin/killall")
        XCTAssertEqual(killedProcesses.first?.1, ["NotificationCenter"])
        XCTAssertEqual(requestedSettingsCount, 1, "restartNotificationCenter must re-request notification settings")
    }

    // MARK: - Part 4.6 Task 8: Detached Chat Window Light & Dark Snapshots and Lock Overlay

    func testDetachedChatWindowLightAndDarkAndLockOverlay() throws {
        let app = offlineApp()
        let inboxPrefs = InboxPreferences(defaults: defaults())
        let composerPrefs = ComposerPreferences(defaults: defaults())
        let mainInbox = InboxModel(appModel: app, preferences: inboxPrefs)
        let row = Fixture.row(
            "!dm-ann:courier.local",
            "Ann Example",
            network: "signal",
            direct: true,
            ts: 5,
            preview: "See you at the trailhead at eight!",
            mine: false
        )
        mainInbox.setSnapshotRowsForTesting([row])

        let lifecycle = SystemLifecycleModel(
            loginItemService: SnapshotLoginItemService(),
            biometricService: SnapshotBiometricService(),
            defaults: defaults()
        )
        let registry = DetachedWindowRegistry(
            appModel: app,
            mainInbox: mainInbox,
            lifecycle: lifecycle,
            inboxPreferences: inboxPrefs,
            composerPreferences: composerPrefs
        )
        let target = DetachedWindowTarget.chat(roomID: row.roomID)
        registry.open(target)
        let session = try XCTUnwrap(registry.session(for: target))

        let events = [
            Fixture.text("$1", "Morning! Are we still meeting at the trailhead?", mine: true, ts: 15, delivered: true),
            Fixture.text("$2", "See you at the trailhead at eight!", mine: false, ts: 5, name: "Ann Example"),
        ]
        session.conversation.setSnapshotStateForTesting(
            roomID: row.roomID,
            items: Fixture.items(events, isDirect: true),
            row: row,
            features: Fixture.features,
            lastOutgoingID: "$1"
        )
        session.conversation.composer.sender = SnapshotMessageSender()
        session.conversation.composer.text = "On my way with coffee!"

        check(try Snapshot.render("detached-chat-window", width: 640, height: 480) {
            DetachedChatWindowView(session: session, lifecycle: lifecycle)
        })

        // Verify locking the app covers the detached chat window with AppLockOverlay.
        XCTAssertFalse(registry.showsLockOverlay(for: target))
        lifecycle.lockApp()
        XCTAssertTrue(registry.showsLockOverlay(for: target))
        check(try Snapshot.render("detached-chat-window-locked", width: 640, height: 480) {
            DetachedChatWindowView(session: session, lifecycle: lifecycle)
        })
    }

    // MARK: - Part 4.6 Task 9: Shortcuts Sheet (`⌘/`) and Recorder Recording & Conflict Snapshots

    func testHotkeysPaneAndShortcutsSheetSnapshots() throws {
        let lifecycle = SystemLifecycleModel(
            loginItemService: SnapshotLoginItemService(),
            biometricService: SnapshotBiometricService(),
            defaults: defaults()
        )

        // 1. Keyboard Shortcuts reference sheet (⌘/)
        let sheetRegistry = HotkeyRegistry(defaults: defaults())
        try assertLightAndDarkSnapshot("keyboard-shortcuts-sheet", width: 760, height: 540) {
            KeyboardShortcutsSheet(registry: sheetRegistry)
        }

        // 2. Shortcut recorder in recording state ("Press keys…")
        let recordingRegistry = HotkeyRegistry(defaults: defaults())
        try assertLightAndDarkSnapshot("hotkeys-recorder-recording", width: 620, height: 520) {
            let _ = recordingRegistry.beginRecording(for: "Search: Room")
            HotkeysSettingsPane(registry: recordingRegistry, lifecycle: lifecycle)
        }

        // 3. Shortcut recorder in conflict state ("⌘K is already used by Search")
        let conflictRegistry = HotkeyRegistry(defaults: defaults())
        _ = conflictRegistry.record(KeyChord(key: "k", command: true), for: "Search: Room")
        try assertLightAndDarkSnapshot("hotkeys-recorder-conflict", width: 620, height: 520) {
            HotkeysSettingsPane(registry: conflictRegistry, lifecycle: lifecycle)
        }
    }

    func testPictureInPictureAndQuickLookCloseOnAppLock() throws {
        final class SpyQuickLookPanel: QuickLookPanelControlling {
            var isVisible = false
            var presentCount = 0
            var closeCount = 0
            func presentPreview(for _: AnyObject) {
                isVisible = true
                presentCount += 1
            }
            func closePreview() {
                isVisible = false
                closeCount += 1
            }
        }

        final class SpyPiPController: PictureInPictureControlling {
            var isPresentingPiP = true
            var pauseAndCloseCount = 0
            func pauseAndCloseForAppLock() {
                isPresentingPiP = false
                pauseAndCloseCount += 1
            }
        }

        let tempMediaURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("vitruvian-courier-lock-pip-\(UUID().uuidString).mp4")
        try Data("fake-mp4".utf8).write(to: tempMediaURL)
        defer { try? FileManager.default.removeItem(at: tempMediaURL) }

        let pipController = PictureInPictureController.shared
        pipController.show(
            PiPVideoItem(
                messageID: "$pip-lock",
                roomID: "!r1",
                mediaPath: tempMediaURL.path,
                title: "Private Video",
                durationMS: 10000,
                elapsedMS: 2000,
                isPlaying: true
            )
        )
        XCTAssertNotNil(pipController.activeItem, "PiP must be active before locking")

        let spyQLPanel = SpyQuickLookPanel()
        let quickLook = QuickLookPreviewCoordinator(panelController: spyQLPanel)
        quickLook.preview(url: tempMediaURL)
        XCTAssertTrue(spyQLPanel.isVisible, "Quick Look panel must be visible before locking")
        XCTAssertEqual(quickLook.numberOfPreviewItems(in: nil), 1)

        let spyPiP = SpyPiPController()
        _ = spyPiP

        let lifecycle = SystemLifecycleModel(
            defaults: defaults(),
            loginItem: SnapshotLoginItemService(),
            biometrics: SnapshotBiometricService()
        )
        lifecycle.lockNow()
        XCTAssertTrue(lifecycle.isLocked)

        XCTAssertNil(pipController.activeItem, "PictureInPictureController must pause and close on app lock")
        XCTAssertFalse(spyQLPanel.isVisible, "QuickLookPreviewCoordinator must close QLPreviewPanel on app lock")
        XCTAssertEqual(spyQLPanel.closeCount, 1, "QuickLookPreviewCoordinator must invoke closePreview() on app lock")
        XCTAssertEqual(quickLook.numberOfPreviewItems(in: nil), 0, "QuickLookPreviewCoordinator must clear previewURL on app lock")
    }

    func testWindowTitlesMenuItemTitlesAndNotifierClearAllWhileLocked() async throws {
        final class AlwaysPassBiometrics: BiometricAuthService {
            func canEvaluateBiometricsOrWatch() -> Bool { true }
            func authenticate(reason _: String) async throws -> Bool { true }
        }
        final class FakeLoginCaller: LoginCalling, @unchecked Sendable {
            func start(network _: String, flow _: String, another _: Bool, accountID _: String?) async throws -> LoginStep {
                throw EngineError.notConnected
            }
            func submit(loginID _: String, values _: [String: String]) async throws -> LoginStep {
                throw EngineError.notConnected
            }
            func wait(loginID _: String) async throws -> LoginStep {
                throw EngineError.notConnected
            }
            func cancel(loginID _: String) async throws {}
        }
        final class MemoryCredentials: CredentialStore, @unchecked Sendable {
            var data: [String: String] = [:]
            func read(account: String) throws -> String? { data[account] }
            func write(_ value: String, account: String) throws { data[account] = value }
            func delete(account: String) throws { data.removeValue(forKey: account) }
        }

        let testDefaults = defaults()
        let lifecycle = SystemLifecycleModel(
            defaults: testDefaults,
            loginItem: SnapshotLoginItemService(),
            biometrics: AlwaysPassBiometrics()
        )
        let appModel = offlineApp()
        let inboxPrefs = InboxPreferences(defaults: testDefaults)
        let composerPrefs = ComposerPreferences(defaults: testDefaults)
        let inbox = InboxModel(appModel: appModel, preferences: inboxPrefs)
        var row = Fixture.row(
            "!r1",
            "Alice Secret",
            network: "signal",
            direct: true,
            ts: 5,
            preview: "Confidential",
            mine: false
        )
        row.pinned = true
        row.muted = true
        row.archived = true
        row.unread = 0
        inbox.setSnapshotRowsForTesting([row])

        let spaces = SpacesModel(appModel: appModel, inbox: inbox, lifecycle: lifecycle)
        spaces.setSpacesForTesting([
            Space(spaceID: "inbox", kind: .builtin, title: "Inbox"),
            Space(spaceID: "work", kind: .account, title: "Secret Work Space", network: "signal"),
        ])

        final class NoopPasteboard: TextPasteboard {
            func setString(_: String) {}
        }
        let labels = LabelsModel(appModel: appModel, lifecycle: lifecycle)
        let conversation = ConversationModel(appModel: appModel, preferences: composerPrefs)
        let messageActions = MessageActionsModel(
            conversation: conversation,
            appModel: appModel,
            preferences: composerPrefs,
            pasteboard: NoopPasteboard()
        )
        let focus = MessageFocus()
        let ui = InboxUI()
        let search = SearchModel(
            appModel: appModel,
            recents: RecentSearches(defaults: testDefaults),
            open: { _ in }
        )
        let login = LoginFlowModel(
            caller: FakeLoginCaller(),
            accounts: { appModel.accounts },
            reloadAccounts: {},
            credentials: MemoryCredentials(),
            builtInCredentials: { nil },
            restartEngine: {}
        )
        let hotkeys = HotkeyRegistry(defaults: testDefaults, isAppLocked: { lifecycle.isLocked })
        let menuCoordinator = AppMenuCoordinator(inbox: inbox, lifecycle: lifecycle)

        let detachedRegistry = DetachedWindowRegistry(
            appModel: appModel,
            mainInbox: inbox,
            lifecycle: lifecycle,
            inboxPreferences: inboxPrefs,
            composerPreferences: composerPrefs
        )
        let detachedManager = DetachedWindowManager(
            registry: detachedRegistry,
            appModel: appModel,
            mainInbox: inbox,
            spaces: spaces,
            lifecycle: lifecycle
        )
        detachedRegistry.open(.chat(roomID: "!r1"))
        detachedRegistry.open(.space(spaceID: "work"))
        detachedRegistry.open(.thread(roomID: "!r1", rootEventID: "$root1"))

        guard let chatWindow = detachedManager.windows[.chat(roomID: "!r1")] else {
            return XCTFail("Missing detached chat window")
        }
        guard let spaceWindow = detachedManager.windows[.space(spaceID: "work")] else {
            return XCTFail("Missing detached space window")
        }
        guard let threadWindow = detachedManager.windows[.thread(roomID: "!r1", rootEventID: "$root1")] else {
            return XCTFail("Missing detached thread window")
        }

        XCTAssertEqual(chatWindow.title, "Alice Secret")
        XCTAssertEqual(spaceWindow.title, "Secret Work Space")
        XCTAssertEqual(threadWindow.title, "Thread — Alice Secret")

        // Create auxiliary NSWindows hosting LockableWindowContent for MainWindow, ChatInfoWindow, and LabelEditorWindow.
        let mainNSWindow = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 800, height: 600),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        mainNSWindow.isReleasedWhenClosed = false
        mainNSWindow.contentViewController = NSHostingController(
            rootView: LockableWindowContent(lifecycle: lifecycle) {
                Text("Main")
            }
        )
        mainNSWindow.contentView?.layoutSubtreeIfNeeded()
        mainNSWindow.title = "Vitruvian Courier"
        mainNSWindow.subtitle = "Connected"

        let chatInfoNSWindow = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 340, height: 620),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        chatInfoNSWindow.isReleasedWhenClosed = false
        chatInfoNSWindow.contentViewController = NSHostingController(
            rootView: LockableWindowContent(lifecycle: lifecycle) {
                ChatInfoWindow(roomID: "!r1", conversation: conversation)
            }
        )
        chatInfoNSWindow.contentView?.layoutSubtreeIfNeeded()
        chatInfoNSWindow.title = "Chat Info — Alice Secret"

        let labelEditorNSWindow = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 400, height: 320),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        labelEditorNSWindow.isReleasedWhenClosed = false
        labelEditorNSWindow.contentViewController = NSHostingController(
            rootView: LockableWindowContent(lifecycle: lifecycle) {
                LabelEditorWindow(target: .new(applyTo: []), labels: labels, spaces: spaces, inbox: inbox)
            }
        )
        labelEditorNSWindow.contentView?.layoutSubtreeIfNeeded()
        defer {
            detachedRegistry.closeAll()
            mainNSWindow.close()
            chatInfoNSWindow.close()
            labelEditorNSWindow.close()
        }

        // Configure active chat/inbox state before locking to test LEAK-3 menu item titles.
        inbox.select("!r1")
        inbox.beginSelecting()
        inbox.toggleUnreadFilter()
        inboxPrefs.showSpaceBar = true
        menuCoordinator.isSidebarVisible = true
        conversation.isEntitled = { _ in true }
        conversation.isShowingChatInfo = true
        conversation.isShowingCalendar = true
        let rootEvent = Fixture.text(
            "$root1",
            "Thread root",
            mine: false,
            ts: 60,
            thread: ThreadSummary(replies: 2, lastTS: Fixture.millis(5), lastSenders: ["Bob"])
        )
        let restrictedFeatures = ChatFeatures(
            reply: true,
            thread: true,
            edit: true,
            unsend: true,
            source: .stored,
            canDelete: true,
            gifFeatures: FileKindFeatures(supported: false),
            stickerFeatures: FileKindFeatures(supported: false)
        )
        conversation.setSnapshotStateForTesting(
            roomID: "!r1",
            items: Fixture.items([rootEvent], isDirect: true),
            row: row,
            features: restrictedFeatures
        )
        conversation.composer.open("!r1")
        conversation.composer.network = "signal"
        conversation.composer.features = restrictedFeatures
        conversation.selectedMessageID = "$root1"

        let dispatcher = HotkeyDispatcher(
            inbox: inbox,
            spaces: spaces,
            conversation: conversation,
            messageActions: messageActions,
            search: search,
            lifecycle: lifecycle,
            menuCoordinator: menuCoordinator,
            focus: focus,
            hotkeys: hotkeys
        )
        _ = dispatcher.perform("Toggle Incognito Mode")
        let inboxCommands = InboxCommands(
            inbox: inbox,
            login: login,
            spaces: spaces,
            preferences: inboxPrefs,
            ui: ui,
            search: search,
            conversation: conversation,
            lifecycle: lifecycle,
            menuCoordinator: menuCoordinator,
            minimizeToMenuBar: {},
            hotkeys: hotkeys,
            hotkeyDispatcher: dispatcher,
            updates: UpdateModel(currentVersion: "0.7.0", appURL: URL(fileURLWithPath: "/Applications/Vitruvian Courier.app"),
                                 environment: SystemUpdateEnvironment(), quit: {}),
            windowOpener: MainWindowOpener()
        )
        let conversationCommands = ConversationCommands(
            conversation: conversation,
            chatComposer: conversation.composer,
            paneComposer: conversation.thread.composer,
            messageActions: messageActions,
            focus: focus,
            hotkeys: hotkeys,
            hotkeyDispatcher: dispatcher,
            lifecycle: lifecycle
        )

        // LEAK-2: Verify Notifier.clearAll() invokes removeAllDeliveredHandler.
        let notifier = Notifier()
        var removeAllDeliveredCalled = 0
        notifier.removeAllDeliveredHandler = {
            removeAllDeliveredCalled += 1
        }
        notifier.clearAll()
        XCTAssertEqual(
            removeAllDeliveredCalled,
            1,
            "Notifier.clearAll() must invoke removeAllDeliveredHandler (UNUserNotificationCenter.removeAllDeliveredNotifications)"
        )

        // Lock the app and verify LEAK-1 (window titles) and LEAK-3 (menu item titles).
        lifecycle.lockNow()
        try await Task.sleep(nanoseconds: 20_000_000)

        // LEAK-1 assertions: every window title while locked must be plain "Vitruvian Courier" with empty subtitle.
        XCTAssertEqual(mainNSWindow.title, "Vitruvian Courier", "Main window title must be 'Vitruvian Courier' while locked")
        XCTAssertEqual(mainNSWindow.subtitle, "", "Main window subtitle must be empty while locked")
        XCTAssertEqual(chatWindow.title, "Vitruvian Courier", "Detached chat window title must be 'Vitruvian Courier' while locked")
        XCTAssertEqual(spaceWindow.title, "Vitruvian Courier", "Detached space window title must be 'Vitruvian Courier' while locked")
        XCTAssertEqual(threadWindow.title, "Vitruvian Courier", "Detached thread window title must be 'Vitruvian Courier' while locked")
        XCTAssertEqual(chatInfoNSWindow.title, "Vitruvian Courier", "Chat Info window title must be 'Vitruvian Courier' while locked")
        XCTAssertEqual(labelEditorNSWindow.title, "Vitruvian Courier", "Label Editor window title must be 'Vitruvian Courier' while locked")

        // LEAK-3 assertions: menu item titles while locked must not reveal chat or inbox state.
        XCTAssertEqual(inboxCommands.spaceBarMenuTitle, "Show Space Bar", "Space Bar menu item title must not leak state while locked")
        XCTAssertEqual(inboxCommands.sidebarMenuTitle, "Show Sidebar", "Sidebar menu item title must not leak state while locked")
        XCTAssertEqual(inboxCommands.incognitoMenuTitle, "Turn On Incognito Mode", "Incognito menu item title must not leak state while locked")
        XCTAssertEqual(inboxCommands.archiveMenuTitle, "Archive", "Archive menu item title must not leak chat archived state while locked")
        XCTAssertEqual(inboxCommands.markReadMenuTitle, "Mark as Read", "Mark as Read menu item title must not leak chat read state while locked")
        XCTAssertEqual(inboxCommands.muteMenuTitle, "Mute Chat", "Mute menu item title must not leak chat muted state while locked")
        XCTAssertEqual(inboxCommands.pinMenuTitle, "Pin", "Pin menu item title must not leak chat pinned state while locked")
        XCTAssertEqual(inboxCommands.selectingMenuTitle, "Begin Selecting", "Selecting menu item title must not leak selection state while locked")
        XCTAssertEqual(inboxCommands.unreadFilterMenuTitle, "Show Only Unread Chats", "Unread filter menu item title must not leak filter state while locked")
        XCTAssertEqual(conversationCommands.showRepliesOrJumpMenuTitle, "Jump to Newest Message", "Show Replies menu item title must not leak thread selection while locked")
        XCTAssertEqual(conversationCommands.sendGIFMenuTitle, "Send GIF…", "Send GIF menu item title must not leak chat network while locked")
        XCTAssertEqual(conversationCommands.sendStickerMenuTitle, "Send Sticker…", "Send Sticker menu item title must not leak chat network while locked")
        XCTAssertEqual(conversationCommands.chatInfoMenuTitle, "Show Chat Info", "Chat Info menu item title must not leak pane state while locked")
        XCTAssertEqual(conversationCommands.calendarMenuTitle, "Show Calendar", "Calendar menu item title must not leak pane state while locked")

        // Unlock and verify LEAK-1 window titles come back.
        _ = await lifecycle.unlockWithTouchID()
        try await Task.sleep(nanoseconds: 20_000_000)
        XCTAssertEqual(chatWindow.title, "Alice Secret", "Detached chat window title must be restored on unlock")
        XCTAssertEqual(spaceWindow.title, "Secret Work Space", "Detached space window title must be restored on unlock")
        XCTAssertEqual(threadWindow.title, "Thread — Alice Secret", "Detached thread window title must be restored on unlock")
        XCTAssertEqual(chatInfoNSWindow.title, "Chat Info — Alice Secret", "Chat Info window title must be restored on unlock")
        XCTAssertEqual(labelEditorNSWindow.title, "New Label", "Label Editor window title must be restored on unlock")
    }

    // MARK: - Milestone 4.6 Tasks 10, 11, 12: Accounts, Bridges, Problem Report, and Settings Shell with Search

    func testMilestone46SettingsAccountsBridgesProblemReportAndSearchLightAndDark() throws {
        struct StubDockTile: DockTileService {
            func isAppInDock(bundleIdentifier: String) -> Bool {
                bundleIdentifier == "net.whatsapp.WhatsApp" || bundleIdentifier == "ru.keepcoder.Telegram"
            }
            func removeAppFromDock(bundleIdentifier _: String) -> Bool { true }
        }
        final class StubPasteboard: TextPasteboard {
            func setString(_: String) {}
        }

        let testDefaults = defaults()
        let app = offlineApp()
        let lifecycle = SystemLifecycleModel(
            loginItemService: SnapshotLoginItemService(),
            biometricService: SnapshotBiometricService(),
            defaults: testDefaults
        )
        let inboxPrefs = InboxPreferences(defaults: testDefaults)
        let composerPrefs = ComposerPreferences(defaults: testDefaults)
        let notificationPrefs = NotificationPreferences(defaults: testDefaults)
        let dockPrefs = DockAndTrayPreferences(defaults: testDefaults)
        let quickReplies = QuickReplies(defaults: testDefaults)
        try quickReplies.add(title: "omw", text: "On my way, {first_name}!")
        try quickReplies.add(title: "intro", text: "Hi {full_name} ({username}), my number is {phone_number}.")
        let hotkeys = HotkeyRegistry(defaults: testDefaults, isAppLocked: { lifecycle.isLocked })
        let inbox = InboxModel(appModel: app, preferences: inboxPrefs, lifecycle: lifecycle)
        let spaces = SpacesModel(appModel: app, inbox: inbox, lifecycle: lifecycle)
        let labels = LabelsModel(appModel: app, lifecycle: lifecycle)
        let conv = conversation(composerPrefs, entitled: true)
        let login = LoginFlowModel(
            caller: SnapshotLoginCaller(),
            accounts: { app.accounts },
            reloadAccounts: {},
            credentials: SnapshotCredentials(),
            builtInCredentials: { nil },
            restartEngine: {}
        )

        let bridgesFixtureJSON = """
        [
          {
            "network": "telegram",
            "display_name": "Telegram",
            "bridge_id": "telegram",
            "module_path": "go.mau.fi/mautrix-telegram",
            "version": "v0.2609.0",
            "mautrix_version": "v0.31.0",
            "state": "CONNECTED",
            "started_at": 1761400000000,
            "accounts": [
              {
                "network": "telegram",
                "display_name": "Telegram",
                "flows": ["phone", "qr"],
                "state": "CONNECTED",
                "error": "",
                "remote_name": "@alice_example",
                "not_started": "",
                "syncs": ["messages"],
                "logins": [
                  {
                    "account_id": "tg-1",
                    "remote_name": "@alice_example",
                    "state": "CONNECTED",
                    "error": ""
                  }
                ]
              }
            ]
          },
          {
            "network": "whatsapp",
            "display_name": "WhatsApp",
            "bridge_id": "whatsapp",
            "module_path": "go.mau.fi/mautrix-whatsapp",
            "version": "v0.2609.0",
            "mautrix_version": "v0.31.0",
            "state": "CONNECTED",
            "started_at": 1761400000000,
            "accounts": [
              {
                "network": "whatsapp",
                "display_name": "WhatsApp",
                "flows": ["qr", "phone"],
                "state": "CONNECTED",
                "error": "",
                "remote_name": "+1 555 010 0101",
                "not_started": "",
                "syncs": ["messages"],
                "logins": [
                  {
                    "account_id": "wa-1",
                    "remote_name": "+1 555 010 0101",
                    "state": "CONNECTED",
                    "error": ""
                  }
                ]
              }
            ]
          },
          {
            "network": "slack",
            "display_name": "Slack",
            "bridge_id": "slack",
            "module_path": "go.mau.fi/mautrix-slack",
            "version": "v0.2609.1",
            "mautrix_version": "v0.31.0",
            "state": "BAD_CREDENTIALS",
            "error": "token_revoked",
            "message": "Your Slack session expired. Reconnect to continue receiving messages.",
            "started_at": 1761400000000,
            "accounts": [
              {
                "network": "slack",
                "display_name": "Slack",
                "flows": ["token"],
                "state": "BAD_CREDENTIALS",
                "error": "token_revoked",
                "message": "Your Slack session expired.",
                "remote_name": "Example Workspace",
                "not_started": "",
                "syncs": ["messages"],
                "logins": [
                  {
                    "account_id": "sl-1",
                    "remote_name": "Example Workspace",
                    "state": "BAD_CREDENTIALS",
                    "error": "token_revoked",
                    "message": "Your Slack session expired."
                  }
                ]
              }
            ]
          }
        ]
        """
        let bridges = try JSONDecoder().decode([BridgeInfo].self, from: Data(bridgesFixtureJSON.utf8))
        let subAccountsJSON = """
        [
          {
            "network": "telegram",
            "account_id": "tg-1",
            "sub_id": "!folder1:courier.local",
            "title": "Work Chats",
            "avatar_uri": "",
            "kind": "space",
            "enabled": true,
            "show_in_inbox": "all"
          },
          {
            "network": "telegram",
            "account_id": "tg-1",
            "sub_id": "!folder2:courier.local",
            "title": "Muted Channels",
            "avatar_uri": "",
            "kind": "space",
            "enabled": false,
            "show_in_inbox": "none"
          },
          {
            "network": "telegram",
            "account_id": "tg-1",
            "sub_id": "!bot1:courier.local",
            "title": "Vitruvian Courier Helper Bot",
            "avatar_uri": "",
            "kind": "bot",
            "enabled": true,
            "show_in_inbox": "dms"
          }
        ]
        """
        let subAccounts = try JSONDecoder().decode([SubAccountItem].self, from: Data(subAccountsJSON.utf8))

        let accountsModel = AccountsAndBridgesModel(
            appModel: app,
            dockTileService: StubDockTile(),
            pasteboard: StubPasteboard(),
            lifecycle: lifecycle
        )
        accountsModel.setSnapshotStateForTesting(
            bridges: bridges,
            subAccountsByKey: ["telegram:tg-1": subAccounts],
            selectedAccountKey: "telegram:tg-1",
            expandedBridgeNetworks: ["whatsapp", "slack"]
        )

        // 1. Accounts pane (Telegram selected with Folders & Bots + Dock cleanup + Space settings)
        check(try Snapshot.render("settings-accounts", width: 760, height: 640) {
            AccountsSettingsPane(
                model: accountsModel,
                spaces: spaces,
                notifications: notificationPrefs,
                onAddAccount: {},
                onReconnect: { _, _ in }
            )
        })

        // 2. Remove Account confirmation dialog sheet
        accountsModel.requestRemoveAccount(
            network: "whatsapp",
            accountID: "wa-1",
            remoteName: "+1 555 010 0101",
            displayName: "WhatsApp"
        )
        if let removal = accountsModel.pendingRemoval {
            check(try Snapshot.render("settings-accounts-remove-confirm", width: 440) {
                RemoveAccountConfirmationSheet(
                    confirmation: .constant(removal),
                    onConfirm: {},
                    onCancel: {}
                )
            })
        }
        accountsModel.cancelRemoveAccount()

        // 3. Bridges pane (connected + error state + expanded details)
        check(try Snapshot.render("settings-bridges", width: 720, height: 620) {
            BridgesSettingsPane(
                model: accountsModel,
                onOpenAccountSettings: { _, _ in },
                onAddAccount: { _ in }
            )
        })

        // 4. Problem Report sheet (with scrubbed JSON + stderr preview & Include Message Details toggle)
        let diagJSON = """
        {
          "protocol_version": 9,
          "schema_version": 10,
          "go_version": "go1.26.2",
          "bridges": \(bridgesFixtureJSON),
          "scrubbed_stderr": [
            "{\\"level\\":\\"warn\\",\\"network\\":\\"whatsapp\\",\\"message\\":\\"websocket closed\\",\\"retry_in\\":5}",
            "panic: runtime error: index out of range",
            "goroutine 42 [running]:",
            "apps/desktop/vitruvian-courier/engine/internal/host.(*Manager).Run()",
            "\\tapps/desktop/vitruvian-courier/engine/internal/host/manager.go:188 +0x120"
          ],
          "room_details": {
            "room_id": "!room1:courier.local",
            "network": "whatsapp",
            "is_direct": true
          },
          "message_details": {
            "event_id": "$evt1",
            "room_id": "!room1:courier.local",
            "network": "whatsapp",
            "type": "m.room.message",
            "ts": 1761401234000,
            "status": "failed",
            "status_reason": "[id] not reachable",
            "has_media": false,
            "is_redacted": false
          }
        }
        """
        let exportedDiag = try JSONDecoder().decode(DiagnosticsExportResult.self, from: Data(diagJSON.utf8))
        let reportModel = ProblemReportModel(
            appModel: app,
            contextRoomID: "!room1:courier.local",
            contextEventID: "$evt1"
        )
        reportModel.descriptionText = "Sending a message in WhatsApp failed right after waking my Mac from sleep."
        reportModel.includeMessageDetails = true
        reportModel.setSnapshotStateForTesting(diagnostics: exportedDiag)

        check(try Snapshot.render("problem-report-sheet", width: 580, height: 620) {
            ProblemReportSheet(model: reportModel, pasteboard: StubPasteboard(), onDismiss: {})
        })

        // 5. Two-column Settings shell with active search results ("delay" matching suggestions) and highlighted target
        let nav = SettingsNavigationModel(selectedPane: .notifications)
        nav.searchQuery = "delay"
        nav.highlightedSettingID = "notifications.delay"
        check(try Snapshot.render("settings-window-search", width: 980, height: 640) {
            SettingsWindow(
                navigation: nav,
                app: app,
                inbox: inbox,
                spaces: spaces,
                labels: labels,
                conversation: conv,
                inboxPreferences: inboxPrefs,
                composerPreferences: composerPrefs,
                notificationPreferences: notificationPrefs,
                quickReplies: quickReplies,
                hotkeys: hotkeys,
                lifecycle: lifecycle,
                dockPreferences: dockPrefs,
                accountsAndBridges: accountsModel,
                loginFlow: login,
                problemReport: reportModel
            )
        })

        // 6. Settings shell showing Appearance, Notifications, Quick Replies, and About panes
        let appearanceNav = SettingsNavigationModel(selectedPane: .appearance)
        check(try Snapshot.render("settings-appearance", width: 980, height: 640) {
            SettingsWindow(
                navigation: appearanceNav,
                app: app,
                inbox: inbox,
                spaces: spaces,
                labels: labels,
                conversation: conv,
                inboxPreferences: inboxPrefs,
                composerPreferences: composerPrefs,
                notificationPreferences: notificationPrefs,
                quickReplies: quickReplies,
                hotkeys: hotkeys,
                lifecycle: lifecycle,
                dockPreferences: dockPrefs,
                accountsAndBridges: accountsModel,
                loginFlow: login,
                problemReport: reportModel
            )
        })

        let notifNav = SettingsNavigationModel(selectedPane: .notifications)
        check(try Snapshot.render("settings-notifications", width: 980, height: 640) {
            SettingsWindow(
                navigation: notifNav,
                app: app,
                inbox: inbox,
                spaces: spaces,
                labels: labels,
                conversation: conv,
                inboxPreferences: inboxPrefs,
                composerPreferences: composerPrefs,
                notificationPreferences: notificationPrefs,
                quickReplies: quickReplies,
                hotkeys: hotkeys,
                lifecycle: lifecycle,
                dockPreferences: dockPrefs,
                accountsAndBridges: accountsModel,
                loginFlow: login,
                problemReport: reportModel
            )
        })

        let quickRepliesNav = SettingsNavigationModel(selectedPane: .quickReplies)
        check(try Snapshot.render("settings-quick-replies", width: 980, height: 580) {
            SettingsWindow(
                navigation: quickRepliesNav,
                app: app,
                inbox: inbox,
                spaces: spaces,
                labels: labels,
                conversation: conv,
                inboxPreferences: inboxPrefs,
                composerPreferences: composerPrefs,
                notificationPreferences: notificationPrefs,
                quickReplies: quickReplies,
                hotkeys: hotkeys,
                lifecycle: lifecycle,
                dockPreferences: dockPrefs,
                accountsAndBridges: accountsModel,
                loginFlow: login,
                problemReport: reportModel
            )
        })

        let aboutNav = SettingsNavigationModel(selectedPane: .about)
        check(try Snapshot.render("settings-about", width: 980, height: 600) {
            SettingsWindow(
                navigation: aboutNav,
                app: app,
                inbox: inbox,
                spaces: spaces,
                labels: labels,
                conversation: conv,
                inboxPreferences: inboxPrefs,
                composerPreferences: composerPrefs,
                notificationPreferences: notificationPrefs,
                quickReplies: quickReplies,
                hotkeys: hotkeys,
                lifecycle: lifecycle,
                dockPreferences: dockPrefs,
                accountsAndBridges: accountsModel,
                loginFlow: login,
                problemReport: reportModel
            )
        })
    }

    func testInboxListAndSearchRowsObserveComposerPreferencesTimeFormat() throws {
        let testDefaults = defaults()
        let app = offlineApp()
        let lifecycle = SystemLifecycleModel(
            loginItemService: SnapshotLoginItemService(),
            biometricService: SnapshotBiometricService(),
            defaults: testDefaults
        )
        let inboxPrefs = InboxPreferences(defaults: testDefaults)
        let composerPrefs = ComposerPreferences(defaults: testDefaults)
        let inbox = InboxModel(appModel: app, preferences: inboxPrefs, lifecycle: lifecycle)
        let spaces = SpacesModel(appModel: app, inbox: inbox, lifecycle: lifecycle)
        let ui = InboxUI()

        let utc = TimeZone(secondsFromGMT: 0)!
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = utc
        let ukLocale = Locale(identifier: "en_GB")
        let afternoonMillis = Int64(1_700_055_000_000) // 2023-11-15 13:30:00 UTC
        let sameDayNow = Date(timeIntervalSince1970: 1_700_060_000)

        let row = Fixture.row("!r1", "Alice Example", ts: 5, preview: "Hello", mine: false)
        var timedRow = row
        timedRow.lastTS = afternoonMillis

        let hit = MessageHit(
            eventID: "$hit1",
            roomID: "!r1",
            roomName: "Alice Example",
            network: "whatsapp",
            isDirect: true,
            place: .inbox,
            sender: "@alice:courier.local",
            senderName: "Alice Example",
            mine: false,
            ts: afternoonMillis,
            seq: 1,
            kind: .video,
            snippet: "Hello there"
        )

        composerPrefs.timeFormat = .twelveHour
        let inboxList = InboxList(
            inbox: inbox,
            spaces: spaces,
            preferences: inboxPrefs,
            composerPreferences: composerPrefs,
            ui: ui
        )
        let searchRow = SearchRowView(
            item: .message(hit),
            isSelected: false,
            networkName: { $0 },
            composerPreferences: composerPrefs
        )
        let mediaCell = MediaCell(
            hit: hit,
            isSelected: false,
            composerPreferences: composerPrefs
        )

        XCTAssertTrue(inboxList.composerPreferences === composerPrefs)
        XCTAssertTrue(searchRow.composerPreferences === composerPrefs)
        XCTAssertTrue(mediaCell.composerPreferences === composerPrefs)

        XCTAssertEqual(inboxList.rowStyle.timeFormat, .twelveHour)
        XCTAssertEqual(
            inboxList.formattedRowTimestamp(timedRow, now: sameDayNow, calendar: calendar, locale: ukLocale),
            "1:30 PM"
        )
        XCTAssertEqual(
            searchRow.formattedTimestamp(now: sameDayNow, calendar: calendar, locale: ukLocale),
            "1:30 PM"
        )
        XCTAssertTrue(
            mediaCell.helpText(now: sameDayNow, calendar: calendar, locale: ukLocale).hasSuffix("· 1:30 PM")
        )

        // Changing composerPrefs.timeFormat immediately updates InboxList, SearchRowView, and MediaCell timestamps
        // without touching UserDefaults.standard.
        composerPrefs.timeFormat = .twentyFourHour
        XCTAssertEqual(inboxList.rowStyle.timeFormat, .twentyFourHour)
        XCTAssertEqual(
            inboxList.formattedRowTimestamp(timedRow, now: sameDayNow, calendar: calendar, locale: ukLocale),
            "13:30"
        )
        XCTAssertEqual(
            searchRow.formattedTimestamp(now: sameDayNow, calendar: calendar, locale: ukLocale),
            "13:30"
        )
        XCTAssertTrue(
            mediaCell.helpText(now: sameDayNow, calendar: calendar, locale: ukLocale).hasSuffix("· 13:30")
        )
    }

    func testEverySearchResultHighlightsItsOwnControlIncludingAccountsEmptyState() throws {
        let testDefaults = defaults()
        let app = offlineApp()
        let lifecycle = SystemLifecycleModel(
            loginItemService: SnapshotLoginItemService(),
            biometricService: SnapshotBiometricService(),
            defaults: testDefaults
        )
        let inboxPrefs = InboxPreferences(defaults: testDefaults)
        let composerPrefs = ComposerPreferences(defaults: testDefaults)
        let notificationPrefs = inboxPrefs.notifications
        let dockPrefs = DockAndTrayPreferences(defaults: testDefaults)
        let quickReplies = QuickReplies(defaults: testDefaults)
        let hotkeys = HotkeyRegistry(defaults: testDefaults, isAppLocked: { lifecycle.isLocked })
        let inbox = InboxModel(appModel: app, preferences: inboxPrefs, lifecycle: lifecycle)
        let spaces = SpacesModel(appModel: app, inbox: inbox, lifecycle: lifecycle)
        let labels = LabelsModel(appModel: app, lifecycle: lifecycle)
        let conv = conversation(composerPrefs, entitled: true)
        let login = LoginFlowModel(
            caller: SnapshotLoginCaller(),
            accounts: { app.accounts },
            reloadAccounts: {},
            credentials: SnapshotCredentials(),
            builtInCredentials: { nil },
            restartEngine: {}
        )

        let populatedBridgesJSON = """
        [
          {
            "network": "telegram",
            "display_name": "Telegram",
            "bridge_id": "telegram",
            "module_path": "go.mau.fi/mautrix-telegram",
            "version": "v0.2609.2",
            "mautrix_version": "v0.31.0",
            "state": "CONNECTED",
            "error": "",
            "message": "Connected",
            "started_at": 1761400000000,
            "supports_sub_accounts": true,
            "accounts": [
              {
                "network": "telegram",
                "display_name": "Telegram",
                "flows": ["phone"],
                "state": "CONNECTED",
                "error": "",
                "message": "Connected",
                "remote_name": "@alice_tg (Alice Example)",
                "not_started": "",
                "syncs": ["messages", "spaces"],
                "supports_sub_accounts": true,
                "logins": [
                  {
                    "account_id": "tg-1",
                    "remote_name": "@alice_tg (Alice Example)",
                    "state": "CONNECTED",
                    "error": "",
                    "message": "Connected"
                  }
                ]
              }
            ]
          }
        ]
        """
        let populatedBridges = try JSONDecoder().decode([BridgeInfo].self, from: Data(populatedBridgesJSON.utf8))
        let populatedAccountsModel = AccountsAndBridgesModel(appModel: app, lifecycle: lifecycle)
        populatedAccountsModel.setSnapshotStateForTesting(
            bridges: populatedBridges,
            subAccountsByKey: [:],
            selectedAccountKey: "telegram:tg-1"
        )
        let emptyAccountsModel = AccountsAndBridgesModel(appModel: app, lifecycle: lifecycle)
        emptyAccountsModel.setSnapshotStateForTesting(bridges: [], subAccountsByKey: [:], selectedAccountKey: nil)
        let reportModel = ProblemReportModel(appModel: app)
        let nav = SettingsNavigationModel()

        SettingAnchorTracker.isTracking = true
        defer {
            SettingAnchorTracker.isTracking = false
            SettingAnchorTracker.reset()
        }

        for (stateLabel, accountsModel) in [("populated accounts state", populatedAccountsModel), ("empty accounts state", emptyAccountsModel)] {
            nav.bind(accountsAndBridges: accountsModel)
            for setting in SettingsNavigationModel.allSettings {
                SettingAnchorTracker.reset()
                nav.jump(to: setting)
                let windowView = SettingsWindow(
                    navigation: nav,
                    app: app,
                    inbox: inbox,
                    spaces: spaces,
                    labels: labels,
                    conversation: conv,
                    inboxPreferences: inboxPrefs,
                    composerPreferences: composerPrefs,
                    notificationPreferences: notificationPrefs,
                    quickReplies: quickReplies,
                    hotkeys: hotkeys,
                    lifecycle: lifecycle,
                    dockPreferences: dockPrefs,
                    accountsAndBridges: accountsModel,
                    loginFlow: login,
                    problemReport: reportModel
                )
                let host = NSHostingView(rootView: windowView)
                host.frame = NSRect(x: 0, y: 0, width: 980, height: 4200)
                host.layoutSubtreeIfNeeded()
                _ = host.fittingSize

                XCTAssertTrue(
                    SettingAnchorTracker.renderedIDs.contains(setting.id),
                    "Expected settingAnchor \(setting.id) to be rendered in pane \(setting.pane.rawValue) (\(stateLabel))"
                )
                XCTAssertEqual(
                    SettingAnchorTracker.highlightedIDs,
                    [setting.id],
                    "Expected settingAnchor \(setting.id) to be highlighted in pane \(setting.pane.rawValue) (\(stateLabel))"
                )
            }
        }
    }

    // MARK: - Milestone 4.6 Task 13: Light & Dark View Snapshot Suite

    private func makeMilestone46SnapshotFixture() throws -> (
        app: AppModel,
        lifecycle: SystemLifecycleModel,
        inboxPrefs: InboxPreferences,
        composerPrefs: ComposerPreferences,
        notificationPrefs: NotificationPreferences,
        dockPrefs: DockAndTrayPreferences,
        quickReplies: QuickReplies,
        hotkeys: HotkeyRegistry,
        inbox: InboxModel,
        spaces: SpacesModel,
        labels: LabelsModel,
        conversation: ConversationModel,
        login: LoginFlowModel,
        accountsModel: AccountsAndBridgesModel,
        reportModel: ProblemReportModel
    ) {
        struct StubDockTile: DockTileService {
            func isAppInDock(bundleIdentifier: String) -> Bool {
                bundleIdentifier == "net.whatsapp.WhatsApp" || bundleIdentifier == "ru.keepcoder.Telegram"
            }
            func removeAppFromDock(bundleIdentifier _: String) -> Bool { true }
        }
        final class StubPasteboard: TextPasteboard {
            func setString(_: String) {}
        }

        let testDefaults = defaults()
        testDefaults.set(true, forKey: SystemLifecycleModel.key("requireTouchID"))
        testDefaults.set(15, forKey: SystemLifecycleModel.key("lockTimeoutMinutes"))
        let app = offlineApp()
        let lifecycle = SystemLifecycleModel(
            loginItemService: SnapshotLoginItemService(),
            biometricService: SnapshotBiometricService(),
            defaults: testDefaults
        )
        let inboxPrefs = InboxPreferences(defaults: testDefaults)
        let composerPrefs = ComposerPreferences(defaults: testDefaults)
        let notificationPrefs = inboxPrefs.notifications
        notificationPrefs.autoCopyOTP = true
        notificationPrefs.soundEffectsMode = .always
        notificationPrefs.soundEffectsVolume = 0.8
        notificationPrefs.delaySeconds = 5
        notificationPrefs.repeatUnreadMinutes = 5
        notificationPrefs.accountOverrides["telegram:tg-1"] = AccountNotificationOverride(
            enabled: true,
            showPreviews: true,
            sound: .default
        )
        notificationPrefs.accountOverrides["slack:sl-1"] = AccountNotificationOverride(
            enabled: true,
            showPreviews: false,
            sound: NotificationSoundChoice.none
        )
        let dockPrefs = DockAndTrayPreferences(defaults: testDefaults)
        let quickReplies = QuickReplies(defaults: testDefaults)
        try quickReplies.add(title: "omw", text: "On my way, {first_name}!")
        try quickReplies.add(title: "intro", text: "Hi {full_name} ({username}), my number is {phone_number} and email is {email}.")
        let hotkeys = HotkeyRegistry(defaults: testDefaults, isAppLocked: { lifecycle.isLocked })
        let inbox = InboxModel(appModel: app, preferences: inboxPrefs, lifecycle: lifecycle)
        let spaces = SpacesModel(appModel: app, inbox: inbox, lifecycle: lifecycle)
        let labels = LabelsModel(appModel: app, lifecycle: lifecycle)
        let conv = conversation(composerPrefs, entitled: true)
        let login = LoginFlowModel(
            caller: SnapshotLoginCaller(),
            accounts: { app.accounts },
            reloadAccounts: {},
            credentials: SnapshotCredentials(),
            builtInCredentials: { nil },
            restartEngine: {}
        )

        let bridgesFixtureJSON = """
        [
          {
            "network": "telegram",
            "display_name": "Telegram",
            "bridge_id": "telegram",
            "module_path": "go.mau.fi/mautrix-telegram",
            "version": "v0.2609.0",
            "mautrix_version": "v0.31.0",
            "state": "CONNECTED",
            "started_at": 1761400000000,
            "supports_sub_accounts": true,
            "accounts": [
              {
                "network": "telegram",
                "display_name": "Telegram",
                "flows": ["phone", "qr"],
                "state": "CONNECTED",
                "error": "",
                "remote_name": "@alice_example",
                "not_started": "",
                "syncs": ["messages", "spaces"],
                "supports_sub_accounts": true,
                "logins": [
                  {
                    "account_id": "tg-1",
                    "remote_name": "@alice_example",
                    "state": "CONNECTED",
                    "error": ""
                  }
                ]
              }
            ]
          },
          {
            "network": "whatsapp",
            "display_name": "WhatsApp",
            "bridge_id": "whatsapp",
            "module_path": "go.mau.fi/mautrix-whatsapp",
            "version": "v0.2609.0",
            "mautrix_version": "v0.31.0",
            "state": "CONNECTED",
            "started_at": 1761400000000,
            "accounts": [
              {
                "network": "whatsapp",
                "display_name": "WhatsApp",
                "flows": ["qr", "phone"],
                "state": "CONNECTED",
                "error": "",
                "remote_name": "+1 555 010 0101",
                "not_started": "",
                "syncs": ["messages"],
                "logins": [
                  {
                    "account_id": "wa-1",
                    "remote_name": "+1 555 010 0101",
                    "state": "CONNECTED",
                    "error": ""
                  }
                ]
              }
            ]
          },
          {
            "network": "slack",
            "display_name": "Slack",
            "bridge_id": "slack",
            "module_path": "go.mau.fi/mautrix-slack",
            "version": "v0.2609.1",
            "mautrix_version": "v0.31.0",
            "state": "BAD_CREDENTIALS",
            "error": "token_revoked",
            "message": "Your Slack session expired. Reconnect to continue receiving messages.",
            "started_at": 1761400000000,
            "accounts": [
              {
                "network": "slack",
                "display_name": "Slack",
                "flows": ["token"],
                "state": "BAD_CREDENTIALS",
                "error": "token_revoked",
                "message": "Your Slack session expired. Reconnect to continue receiving messages.",
                "remote_name": "Example Workspace",
                "not_started": "",
                "syncs": ["messages"],
                "logins": [
                  {
                    "account_id": "sl-1",
                    "remote_name": "Example Workspace",
                    "state": "BAD_CREDENTIALS",
                    "error": "token_revoked",
                    "message": "Your Slack session expired. Reconnect to continue receiving messages."
                  }
                ]
              }
            ]
          }
        ]
        """
        let bridges = try JSONDecoder().decode([BridgeInfo].self, from: Data(bridgesFixtureJSON.utf8))
        app.setAccountsForTesting(bridges.flatMap(\.accounts))

        let spacesJSON = """
        [
          {
            "space_id": "inbox",
            "kind": "builtin",
            "title": "Inbox",
            "network": "",
            "label_id": 0,
            "color": 0,
            "icon": "",
            "hidden": false,
            "muted": false,
            "show_in_inbox": "",
            "chats": 8,
            "unread_chats": 3,
            "attention_chats": 2
          },
          {
            "space_id": "account:telegram",
            "kind": "account",
            "title": "Telegram",
            "network": "telegram",
            "label_id": 0,
            "color": 0,
            "icon": "",
            "hidden": false,
            "muted": false,
            "show_in_inbox": "all",
            "chats": 4,
            "unread_chats": 2,
            "attention_chats": 0
          },
          {
            "space_id": "account:whatsapp",
            "kind": "account",
            "title": "WhatsApp",
            "network": "whatsapp",
            "label_id": 0,
            "color": 0,
            "icon": "",
            "hidden": false,
            "muted": false,
            "show_in_inbox": "all",
            "chats": 3,
            "unread_chats": 1,
            "attention_chats": 0
          },
          {
            "space_id": "account:slack",
            "kind": "account",
            "title": "Slack",
            "network": "slack",
            "label_id": 0,
            "color": 0,
            "icon": "",
            "hidden": false,
            "muted": false,
            "show_in_inbox": "dms",
            "chats": 1,
            "unread_chats": 0,
            "attention_chats": 0
          }
        ]
        """
        let decodedSpaces = try JSONDecoder().decode([Space].self, from: Data(spacesJSON.utf8))
        spaces.setSpacesForTesting(decodedSpaces)

        let subAccountsJSON = """
        [
          {
            "network": "telegram",
            "account_id": "tg-1",
            "sub_id": "!folder1:courier.local",
            "title": "Work Chats",
            "avatar_uri": "",
            "kind": "space",
            "enabled": true,
            "show_in_inbox": "all"
          },
          {
            "network": "telegram",
            "account_id": "tg-1",
            "sub_id": "!folder2:courier.local",
            "title": "Muted Channels",
            "avatar_uri": "",
            "kind": "space",
            "enabled": false,
            "show_in_inbox": "none"
          },
          {
            "network": "telegram",
            "account_id": "tg-1",
            "sub_id": "!bot1:courier.local",
            "title": "Vitruvian Courier Helper Bot",
            "avatar_uri": "",
            "kind": "bot",
            "enabled": true,
            "show_in_inbox": "dms"
          }
        ]
        """
        let subAccounts = try JSONDecoder().decode([SubAccountItem].self, from: Data(subAccountsJSON.utf8))

        let accountsModel = AccountsAndBridgesModel(
            appModel: app,
            dockTileService: StubDockTile(),
            pasteboard: StubPasteboard(),
            lifecycle: lifecycle
        )
        accountsModel.setSnapshotStateForTesting(
            bridges: bridges,
            subAccountsByKey: ["telegram:tg-1": subAccounts],
            selectedAccountKey: "telegram:tg-1",
            expandedBridgeNetworks: ["whatsapp", "slack"]
        )

        let diagJSON = """
        {
          "protocol_version": 9,
          "schema_version": 10,
          "go_version": "go1.26.2",
          "bridges": \(bridgesFixtureJSON),
          "scrubbed_stderr": [
            "{\\"level\\":\\"warn\\",\\"network\\":\\"whatsapp\\",\\"message\\":\\"websocket closed\\",\\"retry_in\\":5}",
            "panic: [redacted]",
            "goroutine 42 [running]:",
            "apps/desktop/vitruvian-courier/engine/internal/host.(*Manager).Run(...)",
            "\\t~/Workspace/courier/engine/internal/host/manager.go:188 +0x120"
          ],
          "room_details": {
            "room_id": "!room1:courier.local",
            "network": "whatsapp",
            "is_direct": true
          },
          "message_details": {
            "event_id": "$evt1",
            "room_id": "!room1:courier.local",
            "network": "whatsapp",
            "type": "m.room.message",
            "ts": 1761401234000,
            "status": "failed",
            "status_reason": "[id] not reachable",
            "has_media": false,
            "is_redacted": false
          }
        }
        """
        let exportedDiag = try JSONDecoder().decode(DiagnosticsExportResult.self, from: Data(diagJSON.utf8))
        let reportModel = ProblemReportModel(
            appModel: app,
            contextRoomID: "!room1:courier.local",
            contextEventID: "$evt1"
        )
        reportModel.descriptionText = "Sending a message in WhatsApp failed right after waking my Mac from sleep."
        reportModel.includeMessageDetails = true
        reportModel.setSnapshotStateForTesting(diagnostics: exportedDiag)

        return (
            app,
            lifecycle,
            inboxPrefs,
            composerPrefs,
            notificationPrefs,
            dockPrefs,
            quickReplies,
            hotkeys,
            inbox,
            spaces,
            labels,
            conv,
            login,
            accountsModel,
            reportModel
        )
    }

    func testSettingsWindowGeneralAndSearchSnapshots() throws {
        let f = try makeMilestone46SnapshotFixture()

        let generalNav = SettingsNavigationModel(selectedPane: .general)
        try assertLightAndDarkSnapshot("settings-window-general", width: 980, height: 1580) {
            SettingsWindow(
                navigation: generalNav,
                app: f.app,
                inbox: f.inbox,
                spaces: f.spaces,
                labels: f.labels,
                conversation: f.conversation,
                inboxPreferences: f.inboxPrefs,
                composerPreferences: f.composerPrefs,
                notificationPreferences: f.notificationPrefs,
                quickReplies: f.quickReplies,
                hotkeys: f.hotkeys,
                lifecycle: f.lifecycle,
                dockPreferences: f.dockPrefs,
                accountsAndBridges: f.accountsModel,
                loginFlow: f.login,
                problemReport: f.reportModel
            )
        }

        let searchNav = SettingsNavigationModel(selectedPane: .general)
        searchNav.searchQuery = "Touch ID"
        searchNav.highlightedSettingID = "general.requireTouchID"
        try assertLightAndDarkSnapshot("settings-window-search-suggestions", width: 980, height: 680) {
            SettingsWindow(
                navigation: searchNav,
                app: f.app,
                inbox: f.inbox,
                spaces: f.spaces,
                labels: f.labels,
                conversation: f.conversation,
                inboxPreferences: f.inboxPrefs,
                composerPreferences: f.composerPrefs,
                notificationPreferences: f.notificationPrefs,
                quickReplies: f.quickReplies,
                hotkeys: f.hotkeys,
                lifecycle: f.lifecycle,
                dockPreferences: f.dockPrefs,
                accountsAndBridges: f.accountsModel,
                loginFlow: f.login,
                problemReport: f.reportModel
            )
        }
    }

    func testSettingsWindowAppearanceAndNotificationsSnapshots() throws {
        let f = try makeMilestone46SnapshotFixture()

        let appearanceNav = SettingsNavigationModel(selectedPane: .appearance)
        try assertLightAndDarkSnapshot("settings-window-appearance", width: 980, height: 1020) {
            SettingsWindow(
                navigation: appearanceNav,
                app: f.app,
                inbox: f.inbox,
                spaces: f.spaces,
                labels: f.labels,
                conversation: f.conversation,
                inboxPreferences: f.inboxPrefs,
                composerPreferences: f.composerPrefs,
                notificationPreferences: f.notificationPrefs,
                quickReplies: f.quickReplies,
                hotkeys: f.hotkeys,
                lifecycle: f.lifecycle,
                dockPreferences: f.dockPrefs,
                accountsAndBridges: f.accountsModel,
                loginFlow: f.login,
                problemReport: f.reportModel
            )
        }

        let notificationsNav = SettingsNavigationModel(selectedPane: .notifications)
        try assertLightAndDarkSnapshot("settings-window-notifications", width: 980, height: 920) {
            SettingsWindow(
                navigation: notificationsNav,
                app: f.app,
                inbox: f.inbox,
                spaces: f.spaces,
                labels: f.labels,
                conversation: f.conversation,
                inboxPreferences: f.inboxPrefs,
                composerPreferences: f.composerPrefs,
                notificationPreferences: f.notificationPrefs,
                quickReplies: f.quickReplies,
                hotkeys: f.hotkeys,
                lifecycle: f.lifecycle,
                dockPreferences: f.dockPrefs,
                accountsAndBridges: f.accountsModel,
                loginFlow: f.login,
                problemReport: f.reportModel
            )
        }
    }

    func testAccountsAndAccountDetailPaneSnapshots() throws {
        let f = try makeMilestone46SnapshotFixture()

        // 0. Full 3-column Settings window on the Accounts pane (sidebar badge + 200pt accounts list + detail pane).
        let accountsNav = SettingsNavigationModel(selectedPane: .accounts)
        f.accountsModel.selectedAccountKey = "telegram:tg-1"
        try assertLightAndDarkSnapshot("settings-window-accounts", width: 980, height: 920) {
            SettingsWindow(
                navigation: accountsNav,
                app: f.app,
                inbox: f.inbox,
                spaces: f.spaces,
                labels: f.labels,
                conversation: f.conversation,
                inboxPreferences: f.inboxPrefs,
                composerPreferences: f.composerPrefs,
                notificationPreferences: f.notificationPrefs,
                quickReplies: f.quickReplies,
                hotkeys: f.hotkeys,
                lifecycle: f.lifecycle,
                dockPreferences: f.dockPrefs,
                accountsAndBridges: f.accountsModel,
                loginFlow: f.login,
                problemReport: f.reportModel
            )
        }

        // 1. Connected account detail (Telegram with Space & Inbox, Notifications override, Spaces & Communities, Dock cleanup, and bottom Remove Account)
        f.accountsModel.selectedAccountKey = "telegram:tg-1"
        try assertLightAndDarkSnapshot("settings-accounts-connected", width: 780, height: 920) {
            AccountsSettingsPane(
                model: f.accountsModel,
                spaces: f.spaces,
                notifications: f.notificationPrefs,
                onAddAccount: {},
                onReconnect: { _, _ in }
            )
        }

        // 2. Disconnected account detail (Slack in BAD_CREDENTIALS state showing "Signed out — reconnect", error banner, and "Reconnect…" button)
        f.accountsModel.selectedAccountKey = "slack:sl-1"
        try assertLightAndDarkSnapshot("settings-accounts-disconnected", width: 780, height: 740) {
            AccountsSettingsPane(
                model: f.accountsModel,
                spaces: f.spaces,
                notifications: f.notificationPrefs,
                onAddAccount: {},
                onReconnect: { _, _ in }
            )
        }

        // 3. Remove Account confirmation sheet
        f.accountsModel.requestRemoveAccount(
            network: "whatsapp",
            accountID: "wa-1",
            remoteName: "+1 555 010 0101",
            displayName: "WhatsApp"
        )
        let removal = try XCTUnwrap(f.accountsModel.pendingRemoval)
        try assertLightAndDarkSnapshot("settings-accounts-remove-sheet", width: 440) {
            RemoveAccountConfirmationSheet(
                confirmation: .constant(removal),
                onConfirm: {},
                onCancel: {}
            )
        }
        f.accountsModel.cancelRemoveAccount()
    }

    func testBridgesSettingsPaneSnapshots() throws {
        let f = try makeMilestone46SnapshotFixture()
        f.accountsModel.expandedBridgeNetworks = ["whatsapp", "slack"]

        try assertLightAndDarkSnapshot("settings-bridges-expanded", width: 760, height: 660) {
            BridgesSettingsPane(
                model: f.accountsModel,
                onOpenAccountSettings: { _, _ in },
                onAddAccount: { _ in }
            )
        }
    }

    func testQuickRepliesAndAboutPanesSnapshots() throws {
        let f = try makeMilestone46SnapshotFixture()

        let quickRepliesNav = SettingsNavigationModel(selectedPane: .quickReplies)
        try assertLightAndDarkSnapshot("settings-window-quick-replies", width: 980, height: 600) {
            SettingsWindow(
                navigation: quickRepliesNav,
                app: f.app,
                inbox: f.inbox,
                spaces: f.spaces,
                labels: f.labels,
                conversation: f.conversation,
                inboxPreferences: f.inboxPrefs,
                composerPreferences: f.composerPrefs,
                notificationPreferences: f.notificationPrefs,
                quickReplies: f.quickReplies,
                hotkeys: f.hotkeys,
                lifecycle: f.lifecycle,
                dockPreferences: f.dockPrefs,
                accountsAndBridges: f.accountsModel,
                loginFlow: f.login,
                problemReport: f.reportModel
            )
        }

        try assertLightAndDarkSnapshot("settings-about-expanded", width: 760, height: 1120) {
            AboutSettingsPane(
                lifecycle: f.lifecycle,
                highlightedSettingID: "about.changelog",
                showChangelog: true,
                showPrivacyDetails: true,
                showLegalNotices: true
            )
        }
    }

    func testProblemReportSheetAndAppLockOverlaySnapshots() throws {
        let f = try makeMilestone46SnapshotFixture()

        try assertLightAndDarkSnapshot("problem-report-sheet-preview", width: 580, height: 620) {
            ProblemReportSheet(model: f.reportModel, onDismiss: {})
        }

        f.lifecycle.lockApp()
        try assertLightAndDarkSnapshot("app-lock-overlay-screen", width: 640, height: 440) {
            AppLockOverlay(model: f.lifecycle)
        }
    }

    func testAccountsAndBridgesSettingsPanesRenderLastError() throws {
        let f = try makeMilestone46SnapshotFixture()
        f.accountsModel.selectedAccountKey = "telegram:tg-1"
        f.lifecycle.lockNow()
        XCTAssertNil(f.accountsModel.lastError)

        _ = try Snapshot.render("accounts-error-check-clean", width: 780, height: 960) {
            AccountsSettingsPane(
                model: f.accountsModel,
                spaces: f.spaces,
                notifications: f.notificationPrefs,
                onAddAccount: {},
                onReconnect: { _, _ in }
            )
        }
        let cleanAccountsData = try Data(contentsOf: Snapshot.directory.appendingPathComponent("accounts-error-check-clean-light.png"))

        _ = try Snapshot.render("bridges-error-check-clean", width: 760, height: 720) {
            BridgesSettingsPane(
                model: f.accountsModel,
                onOpenAccountSettings: { _, _ in },
                onAddAccount: { _ in }
            )
        }
        let cleanBridgesData = try Data(contentsOf: Snapshot.directory.appendingPathComponent("bridges-error-check-clean-light.png"))

        f.accountsModel.requestRestartBridge(network: "telegram")
        XCTAssertNotNil(f.accountsModel.lastError)

        _ = try Snapshot.render("accounts-error-check-shown", width: 780, height: 960) {
            AccountsSettingsPane(
                model: f.accountsModel,
                spaces: f.spaces,
                notifications: f.notificationPrefs,
                onAddAccount: {},
                onReconnect: { _, _ in }
            )
        }
        let errorAccountsData = try Data(contentsOf: Snapshot.directory.appendingPathComponent("accounts-error-check-shown-light.png"))

        _ = try Snapshot.render("bridges-error-check-shown", width: 760, height: 720) {
            BridgesSettingsPane(
                model: f.accountsModel,
                onOpenAccountSettings: { _, _ in },
                onAddAccount: { _ in }
            )
        }
        let errorBridgesData = try Data(contentsOf: Snapshot.directory.appendingPathComponent("bridges-error-check-shown-light.png"))

        XCTAssertNotEqual(
            cleanAccountsData,
            errorAccountsData,
            "AccountsSettingsPane must visibly render model.lastError when non-nil"
        )
        XCTAssertNotEqual(
            cleanBridgesData,
            errorBridgesData,
            "BridgesSettingsPane must visibly render model.lastError when non-nil"
        )
    }

    func testGoogleChatSignInWindowAndChatSnapshotsLightAndDark() async throws {
        // 1. Google Chat sign-in window (AddNetworkView in .signIn state + SignInWindowContent bar)
        let accounts = [
            Account(network: "gchat", displayName: "Google Chat", flows: ["cookies"], state: .unconfigured),
        ]
        let caller = SnapshotLoginCaller()
        caller.finish = try JSONDecoder().decode(LoginStep.self, from: Data("""
        {"login_id": "gchat-login-1", "step_id": "fi.mau.gchat.login.cookies", "type": "cookies",
         "instructions": "Sign in to your Google account to link Google Chat.",
         "cookies": {
           "url": "https://accounts.google.com/ServiceLogin?continue=https://chat.google.com/",
           "user_agent": "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/18.3 Safari/605.1.15",
           "wait_for_url": "^https://chat\\\\.google\\\\.com/",
           "fields": [
             {"id": "COMPASS", "required": true, "sources": [{"type": "cookie", "name": "COMPASS", "cookie_domain": "chat.google.com"}]},
             {"id": "SSID", "required": true, "sources": [{"type": "cookie", "name": "SSID", "cookie_domain": "google.com"}]},
             {"id": "SID", "required": true, "sources": [{"type": "cookie", "name": "SID", "cookie_domain": "google.com"}]},
             {"id": "OSID", "required": true, "sources": [{"type": "cookie", "name": "OSID", "cookie_domain": "chat.google.com"}]},
             {"id": "HSID", "required": true, "sources": [{"type": "cookie", "name": "HSID", "cookie_domain": "google.com"}]}
           ]
         }}
        """.utf8))
        let login = LoginFlowModel(
            caller: caller,
            accounts: { accounts },
            reloadAccounts: {},
            credentials: SnapshotCredentials(),
            builtInCredentials: { nil },
            restartEngine: {}
        )
        login.begin(network: "gchat", flow: "cookies")
        for _ in 0 ..< 200 {
            if case .signIn = login.screen { break }
            await Task.yield()
        }
        var reachedSignIn = false
        if case .signIn = login.screen { reachedSignIn = true }
        XCTAssertTrue(reachedSignIn, "login flow must enter .signIn for gchat cookies step")

        let signInState = SignInWindowState()
        signInState.bar.shown(URL(string: "https://chat.google.com/u/0/"))
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = .nonPersistent()
        let webView = WKWebView(frame: NSRect(x: 0, y: 0, width: 640, height: 320), configuration: configuration)

        try assertLightAndDarkSnapshot("gchat-signin-window", width: 640, height: 640) {
            VStack(spacing: 0) {
                AddNetworkView(login: login)
                Divider()
                SignInWindowContent(
                    state: signInState,
                    webView: webView,
                    networkName: "Google Chat",
                    signedIn: {}
                )
            }
        }

        // 2. Google Chat conversation view (from synthetic fixtures: Space row + rich timeline + composer)
        let style = RowStyle(InboxPreferences(defaults: defaults()))
        let spaceRow = Fixture.row(
            "!gchat_space:courier.local",
            "Platform Reliability Space",
            network: "gchat",
            direct: false,
            ts: 2,
            preview: "All checks green on the rollout.",
            mine: true,
            status: .seen,
            login: "alice.example@gmail.com"
        )
        let dmRow = Fixture.row(
            "!gchat_dm:courier.local",
            "Bob Example",
            network: "gchat",
            direct: true,
            ts: 5,
            preview: "Can we review the design doc?",
            unread: 1,
            status: .delivered,
            login: "alice.example@gmail.com"
        )
        let gchatEvents = [
            Fixture.text(
                "$gc1",
                "Morning team — who is on call for the Google Chat bridge rollout?",
                mine: false,
                ts: 40,
                html: "Morning team — who is on call for the <strong>Google Chat</strong> bridge rollout?",
                thread: ThreadSummary(
                    replies: 2,
                    lastTS: Fixture.millis(15),
                    lastSenders: ["Bob Example", "Alice Example"]
                )
            ),
            Fixture.text(
                "$gc2",
                "I am covering today. Read receipts, threads, and reactions are live.",
                mine: true,
                ts: 10,
                html: "I am covering today. <em>Read receipts</em>, <code>threads</code>, and reactions are live.",
                delivered: true,
                readBy: [Reader(userID: Fixture.ann, name: "Bob Example", ts: Fixture.millis(4))]
            ),
        ]
        let preferences = ComposerPreferences(defaults: defaults())
        let gchatComposer = composer(text: "Sounds great, thanks @Bob Example!")
        gchatComposer.network = "gchat"

        try assertLightAndDarkSnapshot("gchat-chat", width: 680) {
            VStack(spacing: 0) {
                InboxRowView(
                    row: spaceRow,
                    networkName: "Google Chat",
                    now: Fixture.now,
                    style: style,
                    isSelecting: false,
                    isSelected: true,
                    isHovered: false,
                    hoverAct: {},
                    accept: {},
                    decline: {}
                ) { EmptyView() }
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                Divider()
                InboxRowView(
                    row: dmRow,
                    networkName: "Google Chat",
                    now: Fixture.now,
                    style: style,
                    isSelecting: false,
                    isSelected: false,
                    isHovered: false,
                    hoverAct: {},
                    accept: {},
                    decline: {}
                ) { EmptyView() }
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                Divider()
                timeline(Fixture.items(gchatEvents), sent: "$gc2")
                Divider()
                ComposerView(
                    composer: gchatComposer,
                    preferences: preferences,
                    textHeight: .constant(ComposerTextView.minimumHeight),
                    menus: ComposerMenus(sendLater: {}, createPoll: {}, pollsUnavailable: "Google Chat doesn’t support polls.")
                )
            }
        }
    }

    /// The colour and icon picker fits the label window it sits in. Its colour row once asked for ~456pt in a
    /// 360pt window, and SwiftUI centred the overflow, clipping the text, the colours and the icons on both sides.
    func testLabelPickerFitsTheLabelWindow() throws {
        let available = LabelEditorWindow.width - 40 // the window's 20pt padding each side
        let picker = NSHostingView(rootView: IconColorPicker(color: .constant(7), icon: .constant(LabelsModel.icons[0])))
        XCTAssertLessThanOrEqual(picker.fittingSize.width, available,
                                 "The colour and icon picker must fit the label window's \(available)pt")
        try assertLightAndDarkSnapshot("label-picker-in-window-width", width: available) {
            IconColorPicker(color: .constant(7), icon: .constant(LabelsModel.icons[0]))
        }
        // The whole New Label window, at the width it opens at: read the PNG for clipping before a change ships.
        let app = offlineApp()
        let store = defaults()
        let inbox = InboxModel(appModel: app, preferences: InboxPreferences(defaults: store))
        let lifecycle = SystemLifecycleModel(loginItemService: SnapshotLoginItemService(),
                                             biometricService: SnapshotBiometricService(), defaults: store)
        let spaces = SpacesModel(appModel: app, inbox: inbox, lifecycle: lifecycle)
        let labels = LabelsModel(appModel: app, lifecycle: lifecycle)
        try assertLightAndDarkSnapshot("label-editor-new", width: LabelEditorWindow.width) {
            LabelEditorWindow(target: .new(applyTo: []), labels: labels, spaces: spaces, inbox: inbox)
        }
    }

    func testSection22IconCatalogPickerAndRemovedMediaSnapshotsLightAndDark() throws {
        try assertLightAndDarkSnapshot("m47-icon-color-picker-catalog", width: 500) {
            VStack(alignment: .leading, spacing: 16) {
                IconColorPicker(
                    color: .constant(5),
                    icon: .constant("snowflake"),
                    showsAllIconsInitially: true,
                    initialSearchQuery: "",
                    initialCategory: .all
                )
                Divider()
                HStack(spacing: 12) {
                    CreateLabelNudgeIcon()
                    RemovedMediaPlaceholderView(
                        message: TimelineMessage(
                            id: "$removed",
                            roomID: Fixture.room,
                            sender: "@alice:courier.local",
                            senderName: "Alice Example",
                            senderAvatarPath: "",
                            mine: false,
                            ts: Fixture.millis(5),
                            kind: .image,
                            body: "Photo from trip",
                            rich: RichText(text: "Photo from trip"),
                            isEdited: false,
                            editCount: 0,
                            editFailed: nil,
                            failedEditID: nil,
                            fileName: "vacation.jpg",
                            mimeType: "image/jpeg",
                            byteSize: 42_000,
                            width: 640,
                            height: 480,
                            mediaPath: "",
                            statusLine: nil,
                            countsAsUnread: false,
                            poll: nil,
                            thread: nil,
                            bookmarked: false,
                            expiresAt: nil,
                            timerChange: nil,
                            call: nil,
                            reply: nil,
                            reactions: [],
                            startsGroup: true,
                            mediaRemoved: true
                        )
                    )
                }
            }
            .padding(16)
            .background(Color(nsColor: .windowBackgroundColor))
        }
    }

    func testCommandBarOverlaySnapshotsLightAndDark() throws {
        XCTAssertEqual(CommandBarFooterView.closeKeyLabel, "esc", "Footer Close key must show 'esc' like macOS, not '⎋'")
        let suite = defaults()
        let app = offlineApp()
        let inbox = InboxModel(appModel: app, preferences: InboxPreferences(defaults: suite))
        inbox.select(Fixture.room)
        let spaces = SpacesModel(appModel: app, inbox: inbox)
        let appearance = AppearancePreferences(defaults: suite)

        let makeModel = { () -> CommandBarModel in
            let model = CommandBarModel(defaults: suite)
            model.commandsProvider = {
                CommandSet.all(inbox: inbox, spaces: spaces, appearance: appearance)
            }
            model.recentChatsProvider = {
                [
                    Fixture.row("!dm-alice:courier.local", "Alice Example", network: "signal", ts: 5, preview: "See you at 8 AM"),
                    Fixture.row("!grp-trail:courier.local", "Weekend Trail Crew", network: "whatsapp", direct: false, ts: 15, preview: "Bob: Packing snacks"),
                    Fixture.row("!dm-carol:courier.local", "Carol Chen", network: "telegram", ts: 30, preview: "Sent a photo"),
                ]
            }
            return model
        }

        // 1. Empty query with recent commands & categories
        let emptyModel = makeModel()
        emptyModel.open()
        if let sidebarCmd = emptyModel.displayedCommands.first(where: { $0.id == "nav.toggleSidebar" }) {
            emptyModel.execute(sidebarCmd)
        }
        emptyModel.open()
        try assertLightAndDarkSnapshot("m47-command-bar-empty", width: 640, height: 480) {
            CommandBarOverlay(model: emptyModel)
                .frame(width: 640, height: 480)
                .background(Color(nsColor: .windowBackgroundColor))
        }

        // 2. Filtered query ("archive")
        let filteredModel = makeModel()
        filteredModel.open(initialQuery: "archive")
        try assertLightAndDarkSnapshot("m47-command-bar-filtered", width: 640, height: 420) {
            CommandBarOverlay(model: filteredModel)
                .frame(width: 640, height: 420)
                .background(Color(nsColor: .windowBackgroundColor))
        }

        // 3. Drilled into sub-commands ("Filter Chats")
        let drilledModel = makeModel()
        drilledModel.open()
        guard let filterCmd = drilledModel.displayedCommands.first(where: { $0.id == "Filter Chats" }) else {
            XCTFail("Missing Filter Chats")
            return
        }
        drilledModel.execute(filterCmd)
        XCTAssertEqual(drilledModel.breadcrumb.map(\.title), ["Filter Chats"])
        try assertLightAndDarkSnapshot("m47-command-bar-drilled-subcommands", width: 640, height: 420) {
            CommandBarOverlay(model: drilledModel)
                .frame(width: 640, height: 420)
                .background(Color(nsColor: .windowBackgroundColor))
        }

        // 4. Recently viewed chats mode + destructive confirmation banner
        let recentChatsModel = makeModel()
        recentChatsModel.open()
        guard let deleteMedia = recentChatsModel.displayedCommands.first(where: { $0.id == "Delete Media…" }),
              let recentChatsCmd = recentChatsModel.displayedCommands.first(where: { $0.id == "recent.openRecentlyViewedChats" }) else {
            XCTFail("Missing Delete Media… or recent.openRecentlyViewedChats")
            return
        }
        recentChatsModel.execute(recentChatsCmd)
        recentChatsModel.pendingConfirmation = deleteMedia
        try assertLightAndDarkSnapshot("m47-command-bar-recent-chats", width: 640, height: 440) {
            CommandBarOverlay(model: recentChatsModel)
                .frame(width: 640, height: 440)
                .background(Color(nsColor: .windowBackgroundColor))
        }

        // 5. SearchPanel with "Commands ⌘J" switch button
        let searchModel = SearchModel(appModel: app, recents: RecentSearches(defaults: suite), open: { _ in })
        searchModel.show()
        searchModel.text = "mountain"
        var switchedQuery: String?
        try assertLightAndDarkSnapshot("m47-search-panel-commands-switch", width: 680, height: 260) {
            SearchPanel(
                search: searchModel,
                inbox: inbox,
                maxHeight: 220,
                onOpenCommandBar: { query in switchedQuery = query }
            )
            .padding(16)
            .background(Color(nsColor: .windowBackgroundColor))
        }
        XCTAssertNil(switchedQuery)
    }

    func testAppearanceSettingsAndAppIconPickerSnapshotsLightAndDark() throws {
        let suite = defaults()
        let inboxPrefs = InboxPreferences(defaults: suite)
        let composerPrefs = ComposerPreferences(defaults: suite)
        let dockPrefs = DockAndTrayPreferences(defaults: suite)
        let lifecycle = SystemLifecycleModel(
            loginItemService: SnapshotLoginItemService(),
            biometricService: SnapshotBiometricService(),
            defaults: suite
        )
        let appearance = AppearancePreferences(defaults: suite)
        appearance.themePreset = .midnightIndigo
        appearance.defaultWallpaper = .topographicLines
        appearance.fontSizeScale = .large
        appearance.zoomPercent = 110

        try assertLightAndDarkSnapshot("m47-appearance-settings-pane", width: 680, height: 860) {
            AppearanceSettingsPane(
                inboxPreferences: inboxPrefs,
                composerPreferences: composerPrefs,
                dockPreferences: dockPrefs,
                lifecycle: lifecycle,
                appearance: appearance
            )
            .frame(width: 680, height: 860)
            .background(Color(nsColor: .windowBackgroundColor))
        }

        try assertLightAndDarkSnapshot("m47-app-icon-picker", width: 560, height: 340) {
            AppIconPickerView(appearance: appearance)
                .padding(16)
                .frame(width: 560, height: 340)
                .background(Color(nsColor: .windowBackgroundColor))
        }
    }

    func testChatThemeWindowAndBrowserSnapshotsLightAndDark() throws {
        let suite = defaults()
        let appearance = AppearancePreferences(defaults: suite)
        appearance.themePreset = .midnightIndigo
        appearance.defaultWallpaper = .topographicLines
        appearance.setChatTheme(
            ChatThemeOverride(
                preset: .evergreen,
                outgoingBubbleColorHex: "#059669",
                wallpaper: .subtleGrid,
                wallpaperOpacity: 0.45,
                wallpaperBlur: false
            ),
            for: Fixture.room
        )

        try assertLightAndDarkSnapshot("m47-chat-theme-window", width: 540, height: 640) {
            ChatThemeWindow(
                roomID: Fixture.room,
                chatTitle: "Weekend Trail Crew",
                appearance: appearance
            )
            .frame(width: 540, height: 640)
            .background(Color(nsColor: .windowBackgroundColor))
        }

        try assertLightAndDarkSnapshot("m47-chat-theme-browser", width: 780, height: 580) {
            ChatThemeBrowserWindow(
                appearance: appearance,
                activeRoomID: Fixture.room,
                activeChatTitle: "Weekend Trail Crew"
            )
            .frame(width: 780, height: 580)
            .background(Color(nsColor: .windowBackgroundColor))
        }

        // Conversation bubbles with Topographic Lines wallpaper, Midnight Indigo preset, Extra Large font size, and Redact mode enabled
        let redactedAppearance = AppearancePreferences(defaults: suite)
        redactedAppearance.themePreset = .midnightIndigo
        redactedAppearance.defaultWallpaper = .topographicLines
        redactedAppearance.fontSizeScale = .extraLarge
        redactedAppearance.redactNamesAndPictures = true

        let ui = MessageUI()
        var actions = MessageActions()
        actions.appearance = redactedAppearance
        let messages = [
            Fixture.text("$m1", "Are we meeting at the trailhead at 8 AM?", mine: false, ts: 5, sender: "@alice:courier.local", name: "Alice Example"),
            Fixture.text("$m2", "Yes! Bringing coffee and trail mix for everyone.", mine: true, ts: 6),
        ]
        try assertLightAndDarkSnapshot("m47-themed-redacted-conversation", width: 580, height: 320) {
            ZStack {
                ChatWallpaperCanvasView(
                    preset: .topographicLines,
                    customImagePath: nil,
                    opacity: 0.45,
                    blur: false,
                    reduceTransparency: false
                )
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(Fixture.items(messages, isDirect: false)) { item in
                        TimelineItemView(item: item, isSelected: false, showsSent: true, actions: actions, ui: ui)
                    }
                }
                .padding(16)
            }
            .environment(\.appearancePreferences, redactedAppearance)
            .frame(width: 580, height: 320)
            .background(Color(nsColor: .windowBackgroundColor))
        }
    }

    /// Zoom (⌘= / ⌘- / ⌘0, or the Settings stepper) makes the conversation's text larger: at 125% the same messages
    /// render taller than at 100%. Look at m47-zoom-100-conversation and m47-zoom-125-conversation side by side.
    func testZoomEnlargesConversationTextSnapshots() throws {
        let suite = defaults()
        let ui = MessageUI()
        let messages = [
            Fixture.text("$z1", "Are we still on for the walk on Saturday?", mine: false, ts: 5,
                         sender: "@someone:courier.local", name: "Sample Person"),
            Fixture.text("$z2", "Yes, see you at the trailhead at nine.", mine: true, ts: 6),
        ]
        func render(_ percent: Int) throws -> [NSSize] {
            let appearance = AppearancePreferences(defaults: suite)
            appearance.zoomPercent = percent
            var actions = MessageActions()
            actions.appearance = appearance
            return try Snapshot.render("m47-zoom-\(percent)-conversation", width: 480) {
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(Fixture.items(messages, isDirect: false)) { item in
                        TimelineItemView(item: item, isSelected: false, showsSent: true, actions: actions, ui: ui)
                    }
                }
                .padding(16)
                .environment(\.appearancePreferences, appearance)
                .courierTextZoom(appearance)
            }
        }
        let normal = try render(100)
        let zoomed = try render(125)
        // Only the message text grows (captions and times keep their size): two lines, each about 3.5 pt taller.
        XCTAssertGreaterThanOrEqual(zoomed[0].height, normal[0].height + 6, "125% must render visibly larger text")
    }

    func testStorageSettingsPaneSnapshotsLightAndDark() throws {
        let suite = defaults()
        let app = offlineApp()
        let lifecycle = SystemLifecycleModel(
            loginItemService: SnapshotLoginItemService(),
            biometricService: SnapshotBiometricService(),
            defaults: suite
        )
        let model = StorageModel(appModel: app, lifecycle: lifecycle)
        model.setUsageForTesting(
            StorageUsageResult(
                totalBytes: 245_366_784,
                databaseBytes: 18_874_368,
                photosAndVideosBytes: 174_063_616,
                audioBytes: 14_680_064,
                filesBytes: 31_457_280,
                stickersBytes: 6_291_456,
                otherMediaBytes: 0,
                rooms: [
                    RoomStorageUsage(
                        roomID: "!wa:1",
                        name: "Weekend Trail Crew",
                        network: "whatsapp",
                        mediaBytes: 142_606_336,
                        itemCount: 84
                    ),
                    RoomStorageUsage(
                        roomID: "!sig:2",
                        name: "Alice Example",
                        network: "signal",
                        mediaBytes: 52_428_800,
                        itemCount: 31
                    ),
                    RoomStorageUsage(
                        roomID: "!tg:3",
                        name: "Design Systems Guild",
                        network: "telegram",
                        mediaBytes: 31_457_280,
                        itemCount: 19
                    ),
                ]
            )
        )

        try assertLightAndDarkSnapshot("m47-storage-settings-pane", width: 660, height: 640) {
            StorageSettingsPane(model: model, lifecycle: lifecycle)
                .frame(width: 660, height: 640)
                .background(Color(nsColor: .windowBackgroundColor))
        }
    }

    func testAISettingsAIPaneTranslationAndPlusSettingsSnapshotsLightAndDark() throws {
        let suite = defaults()
        let lifecycle = SystemLifecycleModel(
            loginItemService: SnapshotLoginItemService(),
            biometricService: SnapshotBiometricService(),
            defaults: suite
        )
        let aiPrefs = AIPreferences(defaults: suite)
        aiPrefs.translationLanguages = ["English", "Arabic", "Spanish"]

        try assertLightAndDarkSnapshot("m47-ai-settings-pane", width: 660, height: 720) {
            AISettingsPane(preferences: aiPrefs, lifecycle: lifecycle)
                .frame(width: 660, height: 720)
                .background(Color(nsColor: .windowBackgroundColor))
        }

        try assertLightAndDarkSnapshot("m47-ai-pane-and-translation-row", width: 640, height: 480) {
            HStack(spacing: 0) {
                VStack(alignment: .leading, spacing: 12) {
                    Text("Inline Message Translation Stub")
                        .font(.headline)
                    MessageTranslationRowView(
                        targetLanguage: "Spanish",
                        disposition: .unavailable(reason: "Message translation isn’t available yet in Vitruvian Courier.")
                    )
                    Spacer()
                }
                .padding(16)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                Divider()
                AIPane(chatTitle: "Weekend Trail Crew", preferences: aiPrefs)
            }
            .frame(width: 640, height: 480)
            .background(Color(nsColor: .windowBackgroundColor))
        }

        try assertLightAndDarkSnapshot("m47-plus-settings-included-and-noplan", width: 680, height: 760) {
            VStack(spacing: 0) {
                PlusSettingsPane(entitlement: AlwaysEntitled())
                    .frame(height: 380)
                Divider()
                PlusSettingsPane(entitlement: NoPlan())
                    .frame(height: 380)
            }
            .frame(width: 680, height: 760)
            .background(Color(nsColor: .windowBackgroundColor))
        }

        try assertLightAndDarkSnapshot("m47-integrations-settings-pane", width: 640, height: 440) {
            IntegrationsSettingsPane(model: IntegrationsModel(appModel: nil, enginePath: "/nonexistent/vitruvian-courier-engine"))
                .frame(width: 640, height: 440)
                .background(Color(nsColor: .windowBackgroundColor))
        }
    }

    func testSection22IconCatalogPickerAndEmptyStateCardsSnapshotsLightAndDark() throws {
        XCTAssertEqual(EmptyStateUnreadCardsView.featuredHeaderTitle, "Unread Highlights")
        let unreadRows = [
            Fixture.row("!dm-alice:courier.local", "Alice Example", network: "signal", ts: 5, preview: "Can you review the trail map before tomorrow?", unread: 3),
            Fixture.row("!grp-trail:courier.local", "Weekend Trail Crew", network: "whatsapp", direct: false, ts: 12, preview: "Bob: Bringing extra headlamps", unread: 7),
            Fixture.row("!dm-carol:courier.local", "Carol Chen", network: "telegram", ts: 25, preview: "Shared 4 photos from Half Dome", unread: 1),
        ]

        try assertLightAndDarkSnapshot("m47-empty-state-unread-cards", width: 640, height: 440) {
            ZStack {
                ChatWallpaperCanvasView(
                    preset: .auroraGlow,
                    customImagePath: nil,
                    opacity: 0.45,
                    blur: false,
                    reduceTransparency: false
                )
                EmptyStateUnreadCardsView(unreadRows: unreadRows) { _ in }
                    .padding(24)
            }
            .frame(width: 640, height: 440)
            .background(Color(nsColor: .windowBackgroundColor))
        }
    }

    func testTalkToTypeAndVoiceNoteTranscriptSnapshotsLightAndDark() throws {
        let preferences = ComposerPreferences(defaults: defaults())
        let listeningComposer = composer(text: "Hey Alice,")
        listeningComposer.talkToType.setStateForTesting(
            .listening(
                partialText: "running five minutes late to the trailhead",
                level: 0.65,
                provenance: .onThisMac,
                statusMessage: nil
            )
        )

        let deniedComposer = composer(text: "Existing draft stays safe")
        deniedComposer.talkToType.setStateForTesting(
            .idle,
            permissionNotice: TalkToTypePermissionNotice(
                kind: .microphone,
                message: SpeechError.microphoneAccessDenied.message
            )
        )

        try assertLightAndDarkSnapshot("speech-talk-to-type-composer", width: 620) {
            VStack(spacing: 14) {
                ComposerView(
                    composer: listeningComposer,
                    preferences: preferences,
                    textHeight: .constant(ComposerTextView.minimumHeight),
                    menus: ComposerMenus(sendLater: {}, createPoll: {}, pollsUnavailable: nil)
                )
                ComposerView(
                    composer: deniedComposer,
                    preferences: preferences,
                    textHeight: .constant(ComposerTextView.minimumHeight),
                    menus: ComposerMenus(sendLater: {}, createPoll: {}, pollsUnavailable: nil)
                )
            }
            .padding(14)
            .background(Color(nsColor: .windowBackgroundColor))
        }

        var incomingVoice = Fixture.event(
            "$vn-speech-1",
            type: "m.room.message",
            mine: false,
            ts: 12,
            content: [
                "msgtype": .string("m.audio"),
                "body": .string("Voice message"),
                "org.matrix.msc3245.voice": .object([:]),
                "info": .object(["duration": .int(18_000), "size": .int(24_576)]),
            ],
            name: "Alice Example"
        )
        incomingVoice.mediaPath = "/tmp/fake-voice.ogg"
        incomingVoice.durationMS = 18_000
        incomingVoice.waveform = [20, 48, 76, 62, 34, 80, 52, 28, 66, 40]
        incomingVoice.played = false

        var collapsedVoice = incomingVoice
        collapsedVoice.eventID = "$vn-speech-2"
        collapsedVoice.played = true

        let voiceMessages = Fixture.messages([incomingVoice, collapsedVoice])
        let transcriptStore = VoiceNoteTranscriptStore()
        transcriptStore.setEntryForTesting(
            .transcribed(
                text: "Let’s meet by the north entrance at nine thirty.",
                provenance: .onThisMac,
                isCollapsed: false
            ),
            for: "$vn-speech-1"
        )
        transcriptStore.setEntryForTesting(
            .transcribed(
                text: "Short collapsed transcript.",
                provenance: .openAIWhisper,
                isCollapsed: true
            ),
            for: "$vn-speech-2"
        )

        let player = AudioPlayerModel(defaults: defaults())
        try assertLightAndDarkSnapshot("speech-voice-note-transcripts", width: 400) {
            VStack(alignment: .leading, spacing: 12) {
                ForEach(voiceMessages) { msg in
                    VoiceNoteView(
                        message: msg,
                        chatTitle: "Saturday Hike",
                        audioPlayer: player,
                        queueInRoom: [],
                        transcriptStore: transcriptStore
                    )
                }
            }
            .padding(16)
            .background(Color(nsColor: .windowBackgroundColor))
        }
    }

    // MARK: - Chat Info panel & detached ChatInfoWindow (Round 2)

    private final class QuickActionProbeBox {
        var rects: [String: NSRect] = [:]

        func record(_ title: String, _ rect: NSRect?) {
            if let rect, !rect.isEmpty {
                rects[title] = rect
            } else {
                rects.removeValue(forKey: title)
            }
        }
    }

    private func settleChatInfoHost(_ host: NSView, passes: Int = 60, until condition: (() -> Bool)? = nil) {
        for _ in 0 ..< passes {
            RunLoop.main.run(mode: .default, before: Date(timeIntervalSinceNow: 0.005))
            host.window?.displayIfNeeded()
            host.layoutSubtreeIfNeeded()
            if condition?() == true { break }
        }
    }

    private func clickQuickAction(
        labeled label: String,
        window: NSWindow,
        host: NSView,
        probe: QuickActionProbeBox,
        clickIndex: inout Int
    ) throws {
        settleChatInfoHost(host) { probe.rects[label] != nil }
        let rect = try XCTUnwrap(probe.rects[label], "Missing quick-action button \(label)")
        clickIndex += 1
        let timestamp = ProcessInfo.processInfo.systemUptime + Double(clickIndex) * (NSEvent.doubleClickInterval + 0.1)
        let location = NSPoint(x: rect.midX, y: rect.midY)
        for type in [NSEvent.EventType.leftMouseDown, .leftMouseUp] {
            let event = try XCTUnwrap(NSEvent.mouseEvent(
                with: type,
                location: location,
                modifierFlags: [],
                timestamp: timestamp,
                windowNumber: window.windowNumber,
                context: nil,
                eventNumber: clickIndex,
                clickCount: 1,
                pressure: 1
            ))
            NSApp.sendEvent(event)
        }
        settleChatInfoHost(host, passes: 20)
    }

    private func hostChatInfoWindow<V: View>(_ view: V, size: NSSize) -> (NSWindow, NSView) {
        let host = NSHostingView(rootView: view.frame(width: size.width, height: size.height))
        let window = NSWindow(
            contentRect: NSRect(origin: .zero, size: size),
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        window.contentView = host
        host.frame = NSRect(origin: .zero, size: size)
        window.setFrameOrigin(NSPoint(x: -10_000, y: -10_000))
        window.orderFrontRegardless()
        settleChatInfoHost(host)
        return (window, host)
    }

    /// Quick actions in both the inline ChatInfoPane (ConversationView), detached ChatInfoWindow,
    /// and a detached chat session act strictly on `info.roomID` (never falling back to inbox selection
    /// or multi-select), and Search works from ChatInfoWindow and detached windows too.
    func testChatInfoQuickActionsActOnPanelRoomAndDetachedSearchWorks() throws {
        _ = NSApplication.shared
        let folder = FileManager.default.temporaryDirectory
            .appendingPathComponent("vitruvian-courier-chatinfo-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        setenv(EngineLocation.dataDirectoryVariable, folder.path, 1)
        defer {
            unsetenv(EngineLocation.dataDirectoryVariable)
            try? FileManager.default.removeItem(at: folder)
        }

        let delegate = AppDelegate()
        var mainWindowOpens = 0
        delegate.windowOpener.register { mainWindowOpens += 1 }

        let panelRoom = "!panel-room:courier.local"
        let selectedRoom = "!selected-room:courier.local"
        let multiRoom = "!multi-room:courier.local"

        let rowPanel = InboxRow(
            roomID: panelRoom, network: "whatsapp", name: "Panel Chat", avatarPath: "", isDirect: true,
            lastTS: 100, preview: "Hi", previewKind: .text, previewMine: false, unread: 0, muted: false
        )
        let rowSelected = InboxRow(
            roomID: selectedRoom, network: "whatsapp", name: "Selected Chat", avatarPath: "", isDirect: true,
            lastTS: 90, preview: "Yo", previewKind: .text, previewMine: false, unread: 0, muted: false
        )
        let rowMulti = InboxRow(
            roomID: multiRoom, network: "whatsapp", name: "Multi Chat", avatarPath: "", isDirect: true,
            lastTS: 80, preview: "Hey", previewKind: .text, previewMine: false, unread: 0, muted: false
        )
        delegate.inbox.setSnapshotRowsForTesting([rowPanel, rowSelected, rowMulti])
        delegate.inbox.select(selectedRoom)
        delegate.inbox.beginSelecting()
        delegate.inbox.toggleSelected(multiRoom)

        let info = RoomInfoResult(
            roomID: panelRoom,
            name: "Panel Chat",
            remoteName: "Panel Chat",
            network: "whatsapp",
            isDirect: true,
            features: Fixture.features
        )
        delegate.conversation.setSnapshotStateForTesting(roomID: panelRoom, items: [], row: rowPanel)
        delegate.conversation.setChatInfoForTesting(info)

        // 1. Detached ChatInfoWindow initialized with 2 args (matching App.swift).
        let detachedProbe = QuickActionProbeBox()
        let (detachedWin, detachedHost) = hostChatInfoWindow(
            ChatInfoWindow(roomID: panelRoom, conversation: delegate.conversation)
                .environment(\.chatInfoQuickActionProbe) { title, rect in
                    detachedProbe.record(title, rect)
                },
            size: NSSize(width: 340, height: 640)
        )
        defer {
            detachedWin.orderOut(nil)
            detachedWin.contentView = nil
        }

        var clickIndex = 0
        let openedBefore = mainWindowOpens
        try clickQuickAction(
            labeled: String(localized: "Search"),
            window: detachedWin,
            host: detachedHost,
            probe: detachedProbe,
            clickIndex: &clickIndex
        )
        try XCTSkipIf(
            delegate.search.phase == .closed && mainWindowOpens == openedBefore,
            "the window got no clicks (no window server for it here)"
        )
        XCTAssertEqual(mainWindowOpens, openedBefore + 1, "Detached Search must bring the main window forward")
        XCTAssertNotEqual(delegate.search.phase, .closed, "Detached Search must open SearchModel")
        delegate.search.close()

        try clickQuickAction(
            labeled: String(localized: "Remind…"),
            window: detachedWin,
            host: detachedHost,
            probe: detachedProbe,
            clickIndex: &clickIndex
        )
        XCTAssertEqual(
            delegate.inbox.customReminder?.ids,
            [panelRoom],
            "Detached Remind must target info.roomID, not inbox selection or multi-select"
        )
        delegate.inbox.customReminder = nil
        delegate.inboxUI.customReminder = nil

        // 2. Detached chat session from DetachedWindowRegistry has onSearchInChat wired.
        let detachedTarget = DetachedWindowTarget.chat(roomID: panelRoom)
        delegate.detachedWindows.open(detachedTarget)
        defer { delegate.detachedWindows.close(detachedTarget) }
        let detachedSession = try XCTUnwrap(delegate.detachedWindows.session(for: detachedTarget))
        let opensBeforeDetachedSession = mainWindowOpens
        XCTAssertTrue(detachedSession.conversation.performSearchInChat(panelRoom))
        XCTAssertEqual(mainWindowOpens, opensBeforeDetachedSession + 1)
        XCTAssertNotEqual(delegate.search.phase, .closed, "Detached session Search must open SearchModel")
        delegate.search.close()

        // 3. Spy handlers on delegate.conversation verify all 5 actions pass info.roomID from BOTH
        //    ChatInfoWindow and inline ConversationView ChatInfoPane.
        var muteRooms: [String] = []
        var pinRooms: [String] = []
        var archiveRooms: [String] = []
        var remindRooms: [String] = []
        var searchRooms: [String] = []
        delegate.conversation.onToggleMute = { muteRooms.append($0) }
        delegate.conversation.onTogglePin = { pinRooms.append($0) }
        delegate.conversation.onToggleArchive = { archiveRooms.append($0) }
        delegate.conversation.onRemindLater = { remindRooms.append($0); return true }
        delegate.conversation.onSearchInChat = { searchRooms.append($0) }

        for (label, verify) in [
            (String(localized: "Mute"), { XCTAssertEqual(muteRooms, [panelRoom]) }),
            (String(localized: "Pin"), { XCTAssertEqual(pinRooms, [panelRoom]) }),
            (String(localized: "Archive"), { XCTAssertEqual(archiveRooms, [panelRoom]) }),
            (String(localized: "Remind…"), { XCTAssertEqual(remindRooms, [panelRoom]) }),
            (String(localized: "Search"), { XCTAssertEqual(searchRooms, [panelRoom]) }),
        ] {
            try clickQuickAction(
                labeled: label,
                window: detachedWin,
                host: detachedHost,
                probe: detachedProbe,
                clickIndex: &clickIndex
            )
            verify()
        }

        muteRooms.removeAll()
        pinRooms.removeAll()
        archiveRooms.removeAll()
        remindRooms.removeAll()
        searchRooms.removeAll()

        let inlineProbe = QuickActionProbeBox()
        let (inlineWin, inlineHost) = hostChatInfoWindow(
            ConversationView(
                conversation: delegate.conversation,
                composer: delegate.conversation.composer,
                inbox: delegate.inbox,
                messageActions: delegate.messageActions,
                scheduled: delegate.scheduled,
                preferences: delegate.composerPreferences,
                thread: delegate.conversation.thread,
                focus: delegate.messageFocus,
                appModel: delegate.model
            )
            .environment(\.chatInfoQuickActionProbe) { title, rect in
                inlineProbe.record(title, rect)
            },
            size: NSSize(width: 900, height: 640)
        )
        defer {
            inlineWin.orderOut(nil)
            inlineWin.contentView = nil
        }

        for (label, verify) in [
            (String(localized: "Mute"), { XCTAssertEqual(muteRooms, [panelRoom]) }),
            (String(localized: "Pin"), { XCTAssertEqual(pinRooms, [panelRoom]) }),
            (String(localized: "Archive"), { XCTAssertEqual(archiveRooms, [panelRoom]) }),
            (String(localized: "Remind…"), { XCTAssertEqual(remindRooms, [panelRoom]) }),
            (String(localized: "Search"), { XCTAssertEqual(searchRooms, [panelRoom]) }),
        ] {
            try clickQuickAction(
                labeled: label,
                window: inlineWin,
                host: inlineHost,
                probe: inlineProbe,
                clickIndex: &clickIndex
            )
            verify()
        }
    }

    /// Mute and Pin labels flip immediately in both the inline pane and detached ChatInfoWindow
    /// when the inbox row's `muted` / `pinned` flags update.
    func testChatInfoMuteAndPinLabelsFlipInInlinePaneAndDetachedWindow() throws {
        _ = NSApplication.shared
        let folder = FileManager.default.temporaryDirectory
            .appendingPathComponent("vitruvian-courier-flip-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        setenv(EngineLocation.dataDirectoryVariable, folder.path, 1)
        defer {
            unsetenv(EngineLocation.dataDirectoryVariable)
            try? FileManager.default.removeItem(at: folder)
        }

        let delegate = AppDelegate()
        let roomID = "!flip-room:courier.local"

        func makeRow(muted: Bool, pinned: Bool) -> InboxRow {
            InboxRow(
                roomID: roomID, network: "signal", name: "Flip Chat", avatarPath: "", isDirect: true,
                lastTS: 100, preview: "Hi", previewKind: .text, previewMine: false, unread: 0,
                muted: muted, pinned: pinned
            )
        }

        let initial = makeRow(muted: false, pinned: false)
        delegate.inbox.setSnapshotRowsForTesting([initial])
        let info = RoomInfoResult(
            roomID: roomID,
            name: "Flip Chat",
            remoteName: "Flip Chat",
            network: "signal",
            isDirect: true,
            features: Fixture.features
        )
        delegate.conversation.setSnapshotStateForTesting(roomID: roomID, items: [], row: initial)
        delegate.conversation.setChatInfoForTesting(info)

        let inlineProbe = QuickActionProbeBox()
        let (inlineWin, inlineHost) = hostChatInfoWindow(
            ConversationView(
                conversation: delegate.conversation,
                composer: delegate.conversation.composer,
                inbox: delegate.inbox,
                messageActions: delegate.messageActions,
                scheduled: delegate.scheduled,
                preferences: delegate.composerPreferences,
                thread: delegate.conversation.thread,
                focus: delegate.messageFocus,
                appModel: delegate.model
            )
            .environment(\.chatInfoQuickActionProbe) { title, rect in
                inlineProbe.record(title, rect)
            },
            size: NSSize(width: 900, height: 640)
        )
        let detachedProbe = QuickActionProbeBox()
        let (detachedWin, detachedHost) = hostChatInfoWindow(
            ChatInfoWindow(roomID: roomID, conversation: delegate.conversation)
                .environment(\.chatInfoQuickActionProbe) { title, rect in
                    detachedProbe.record(title, rect)
                },
            size: NSSize(width: 340, height: 640)
        )
        defer {
            inlineWin.orderOut(nil)
            inlineWin.contentView = nil
            detachedWin.orderOut(nil)
            detachedWin.contentView = nil
        }

        let mute = String(localized: "Mute")
        let unmute = String(localized: "Unmute")
        let pin = String(localized: "Pin")
        let unpin = String(localized: "Unpin")

        settleChatInfoHost(inlineHost) { inlineProbe.rects[mute] != nil && inlineProbe.rects[pin] != nil }
        settleChatInfoHost(detachedHost) { detachedProbe.rects[mute] != nil && detachedProbe.rects[pin] != nil }

        XCTAssertNotNil(inlineProbe.rects[mute])
        XCTAssertNotNil(inlineProbe.rects[pin])
        XCTAssertNil(inlineProbe.rects[unmute])
        XCTAssertNil(inlineProbe.rects[unpin])
        XCTAssertNotNil(detachedProbe.rects[mute])
        XCTAssertNotNil(detachedProbe.rects[pin])
        XCTAssertNil(detachedProbe.rects[unmute])
        XCTAssertNil(detachedProbe.rects[unpin])

        delegate.inbox.setSnapshotRowsForTesting([makeRow(muted: true, pinned: true)])
        settleChatInfoHost(inlineHost) { inlineProbe.rects[unmute] != nil && inlineProbe.rects[unpin] != nil }
        settleChatInfoHost(detachedHost) { detachedProbe.rects[unmute] != nil && detachedProbe.rects[unpin] != nil }

        XCTAssertNotNil(inlineProbe.rects[unmute], "Inline ChatInfoPane must flip Mute -> Unmute when inbox row updates")
        XCTAssertNotNil(inlineProbe.rects[unpin], "Inline ChatInfoPane must flip Pin -> Unpin when inbox row updates")
        XCTAssertNil(inlineProbe.rects[mute])
        XCTAssertNil(inlineProbe.rects[pin])
        XCTAssertNotNil(detachedProbe.rects[unmute], "Detached ChatInfoWindow must flip Mute -> Unmute when inbox row updates")
        XCTAssertNotNil(detachedProbe.rects[unpin], "Detached ChatInfoWindow must flip Pin -> Unpin when inbox row updates")
        XCTAssertNil(detachedProbe.rects[mute])
        XCTAssertNil(detachedProbe.rects[pin])

        delegate.inbox.setSnapshotRowsForTesting([makeRow(muted: false, pinned: false)])
        settleChatInfoHost(inlineHost) { inlineProbe.rects[mute] != nil && inlineProbe.rects[pin] != nil }
        settleChatInfoHost(detachedHost) { detachedProbe.rects[mute] != nil && detachedProbe.rects[pin] != nil }

        XCTAssertNotNil(inlineProbe.rects[mute])
        XCTAssertNotNil(inlineProbe.rects[pin])
        XCTAssertNil(inlineProbe.rects[unmute])
        XCTAssertNil(inlineProbe.rects[unpin])
        XCTAssertNotNil(detachedProbe.rects[mute])
        XCTAssertNotNil(detachedProbe.rects[pin])
        XCTAssertNil(detachedProbe.rects[unmute])
        XCTAssertNil(detachedProbe.rects[unpin])
    }

    /// Chat Info has a Notification sound row (with its footnote) and a Notes field holding the saved note; the
    /// note a person wrote for this chat shows again, and another chat's does not.
    func testChatInfoPaneShowsNotificationSoundAndSavedNotes() throws {
        let suite = "courier.test.chatinfo-notes.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(ScratchDefaults.suite(named: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let store = ChatNotesStore(fileURL: nil, saveDelay: .seconds(30), notificationCenter: NotificationCenter())
        store.setNote("Gate code 4417", for: "!notes:courier.local")
        store.setNote("Somebody else's", for: "!other:courier.local")
        let prefs = NotificationPreferences(defaults: defaults)
        prefs.setChatSound(.harp, for: "!notes:courier.local")

        let info = RoomInfoResult(
            roomID: "!notes:courier.local", name: "Notes Chat", remoteName: "Notes Chat", network: "whatsapp",
            isDirect: true, members: [Member(userID: "@a:courier.local", name: "Alice")], features: Fixture.features
        )
        var seen: [String] = []
        try Snapshot.render("chat-info-sound-notes", width: 320) {
            ChatInfoPane(info: info, now: { Fixture.now }, notesStore: store, notificationPreferences: prefs)
                .environment(\.chatInfoRowProbe) { seen.append($0) }
        }
        XCTAssertTrue(seen.contains("sound:harp"), "Notification sound row is missing or not on this chat's sound: \(seen)")
        XCTAssertTrue(seen.contains("notes:Gate code 4417"), "Notes field is missing or lost the saved note: \(seen)")
        XCTAssertEqual(ChatInfoSoundRow.title(.default), "Default")
        XCTAssertEqual(ChatInfoSoundRow.title(.harp), NotificationsSettingsPane.soundLabel(.harp))
        XCTAssertEqual(store.note(for: "!notes:courier.local"), "Gate code 4417")
        XCTAssertEqual(store.note(for: "!other:courier.local"), "Somebody else's")
    }

    /// In a narrow info pane the Notification sound row keeps its label whole and puts the picker on its own line,
    /// instead of squeezing the label to "…"; with room to spare it stays on one line.
    func testChatInfoSoundRowWrapsInsteadOfTruncatingTheLabel() throws {
        let suite = "courier.test.chatinfo-sound-wrap.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(ScratchDefaults.suite(named: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let prefs = NotificationPreferences(defaults: defaults)
        func height(atWidth width: CGFloat) -> CGFloat {
            let host = NSHostingView(rootView: ChatInfoSoundRow(roomID: "!wrap:courier.local", preferences: prefs)
                .frame(width: width))
            host.layoutSubtreeIfNeeded()
            return host.fittingSize.height
        }
        let wide = height(atWidth: 360)
        let narrow = height(atWidth: 150)
        XCTAssertGreaterThan(narrow, wide + 10, "narrow row should wrap the picker onto its own line")
    }

    private final class NotesRoom: ObservableObject {
        @Published var roomID: String
        init(_ roomID: String) { self.roomID = roomID }
    }

    private struct NotesFieldHost: View {
        @ObservedObject var room: NotesRoom
        var body: some View { ChatInfoNotesField(roomID: room.roomID).padding(8) }
    }

    private func notesFile(_ url: URL) -> [String: String]? {
        (try? Data(contentsOf: url)).flatMap { try? JSONDecoder().decode([String: String].self, from: $0) }
    }

    /// Two Notes fields on one chat (two windows) read and write the one app store, and see each other's edits.
    func testChatInfoNotesFieldsShareTheAppStore() throws {
        let store = ChatNotesStore(fileURL: nil, schedule: { _, _ in {} }, notificationCenter: NotificationCenter())
        ChatNotesStore.useSharedStoreForTesting(store)
        defer { ChatNotesStore.useSharedStoreForTesting(nil) }
        let first = ChatInfoNotesField(roomID: "!a")
        let second = ChatInfoNotesField(roomID: "!a")
        XCTAssertTrue(first.store === ChatNotesStore.shared)
        XCTAssertTrue(second.store === ChatNotesStore.shared)
        first.text.wrappedValue = "typed in the first window"
        XCTAssertEqual(second.text.wrappedValue, "typed in the first window")
        second.text.wrappedValue = "then the second"
        XCTAssertEqual(first.text.wrappedValue, "then the second")
        XCTAssertEqual(ChatNotesStore.shared.note(for: "!a"), "then the second")
        XCTAssertEqual(ChatInfoNotesField(roomID: "!b").text.wrappedValue, "", "another chat has its own note")
    }

    /// Switching to another chat saves the note being typed under the chat it was typed in.
    func testChatInfoNotesSavesWhenTheChatSwitches() async throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("notes-switch-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: dir) }
        let url = dir.appendingPathComponent(ChatNotesStore.fileName)
        let store = ChatNotesStore(fileURL: url, schedule: { _, _ in {} }, notificationCenter: NotificationCenter())
        ChatNotesStore.useSharedStoreForTesting(store)
        defer { ChatNotesStore.useSharedStoreForTesting(nil) }
        let room = NotesRoom("!a")
        let (window, host) = hostChatInfoWindow(NotesFieldHost(room: room), size: NSSize(width: 300, height: 160))
        defer {
            window.orderOut(nil)
            window.contentView = nil
        }
        store.setNote("About A", for: "!a")
        XCTAssertNil(notesFile(url), "the pause hasn't ended: nothing written yet")
        room.roomID = "!b"
        settleChatInfoHost(host)
        await store.waitForFileWork()
        XCTAssertEqual(notesFile(url), ["!a": "About A"])
    }

    /// Closing the pane saves the note.
    func testChatInfoNotesSavesWhenThePaneCloses() async throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("notes-close-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: dir) }
        let url = dir.appendingPathComponent(ChatNotesStore.fileName)
        let store = ChatNotesStore(fileURL: url, schedule: { _, _ in {} }, notificationCenter: NotificationCenter())
        ChatNotesStore.useSharedStoreForTesting(store)
        defer { ChatNotesStore.useSharedStoreForTesting(nil) }
        let (window, host) = hostChatInfoWindow(NotesFieldHost(room: NotesRoom("!a")), size: NSSize(width: 300, height: 160))
        store.setNote("Typed, then closed", for: "!a")
        XCTAssertNil(notesFile(url))
        window.contentView = nil
        settleChatInfoHost(host)
        window.orderOut(nil)
        await store.waitForFileWork()
        XCTAssertEqual(notesFile(url), ["!a": "Typed, then closed"])
    }

    /// The Labels row shows this chat's labels as chips and offers Add to a Label.
    func testChatInfoLabelsSectionShowsAssignedLabelsAndAddMenu() throws {
        let work = Space(spaceID: "label:1", kind: .label, title: "Work", labelID: 1, color: 7, icon: "briefcase")
        let family = Space(spaceID: "label:2", kind: .label, title: "Family", labelID: 2, color: 0, icon: "heart")
        var assigned: [Int64] = [1]
        var expanded = true
        let section = ChatInfoLabelsSection(
            labels: [work, family], assignedIDs: assigned,
            isExpanded: Binding(get: { expanded }, set: { expanded = $0 }),
            onSet: { label, on in
                assigned.removeAll { $0 == label.labelID }
                if on { assigned.append(label.labelID) }
            },
            onNewLabel: {}
        )
        var seen: [String] = []
        try Snapshot.render("chat-info-labels", width: 300) {
            section.padding(8).environment(\.chatInfoRowProbe) { seen.append($0) }
        }
        XCTAssertTrue(seen.contains("add-label"), "Add to a Label is missing: \(seen)")
        XCTAssertTrue(seen.contains("chip:Work"), "the Work chip is missing: \(seen)")
        XCTAssertFalse(seen.contains("chip:Family"), "Family is not on this chat")

        // Ticking Family in the menu puts it on the chat; the x on Work's chip takes Work off.
        section.menuBinding(for: family).wrappedValue = true
        XCTAssertEqual(Set(assigned), [1, 2])
        section.removeChip(work)
        XCTAssertEqual(assigned, [2])
        section.menuBinding(for: family).wrappedValue = false
        XCTAssertTrue(assigned.isEmpty)
    }

    /// Local avatar override (`localAvatarURI`) must win over network `avatarPath` in ChatInfoPane header.
    func testChatInfoPaneLocalAvatarWinsOverNetworkAvatar() throws {
        let tmpDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("chat-info-avatar-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tmpDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tmpDir) }

        func writeSolidPNG(name: String, color: NSColor) throws -> String {
            let side = 64
            let rep = try XCTUnwrap(NSBitmapImageRep(
                bitmapDataPlanes: nil, pixelsWide: side, pixelsHigh: side, bitsPerSample: 8, samplesPerPixel: 4,
                hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0
            ))
            NSGraphicsContext.saveGraphicsState()
            NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
            color.setFill()
            NSRect(x: 0, y: 0, width: side, height: side).fill()
            NSGraphicsContext.restoreGraphicsState()
            let data = try XCTUnwrap(rep.representation(using: .png, properties: [:]))
            let url = tmpDir.appendingPathComponent(name)
            try data.write(to: url)
            return url.path
        }

        let localPath = try writeSolidPNG(name: "local-red.png", color: NSColor(calibratedRed: 1, green: 0, blue: 0, alpha: 1))
        let networkPath = try writeSolidPNG(name: "network-blue.png", color: NSColor(calibratedRed: 0, green: 0, blue: 1, alpha: 1))

        let info = RoomInfoResult(
            roomID: "!avatar-precedence:courier.local",
            name: "Group With Local Avatar",
            remoteName: "Group",
            avatarPath: networkPath,
            localAvatarURI: localPath,
            network: "whatsapp",
            isDirect: false,
            members: [
                Member(userID: "@a:courier.local", name: "Alice"),
                Member(userID: "@b:courier.local", name: "Bob"),
            ],
            features: Fixture.features
        )

        let size = NSSize(width: 280, height: 220)
        let (window, host) = hostChatInfoWindow(ChatInfoPane(info: info, now: { Fixture.now }), size: size)
        defer {
            window.orderOut(nil)
            window.contentView = nil
        }
        // Let AvatarView's async image task finish loading from disk.
        for _ in 0 ..< 40 {
            if AvatarCache.shared.cachedImage(atPath: localPath) != nil { break }
            RunLoop.main.run(mode: .default, before: Date(timeIntervalSinceNow: 0.01))
        }
        settleChatInfoHost(host)
        window.displayIfNeeded()

        let bitmap = try XCTUnwrap(host.bitmapImageRepForCachingDisplay(in: host.bounds))
        host.cacheDisplay(in: host.bounds, to: bitmap)

        // Sample the top-center avatar region (centered at x = 50% width, y ~ 50pt from top in flipped AppKit coords).
        var foundRed = false
        var foundBlue = false
        for px in stride(from: bitmap.pixelsWide / 2 - 12, through: bitmap.pixelsWide / 2 + 12, by: 4) {
            for py in stride(from: 30, through: min(90, bitmap.pixelsHigh - 1), by: 4) {
                if let sample = bitmap.colorAt(x: px, y: py)?.usingColorSpace(.sRGB) {
                    if sample.redComponent > 0.75 && sample.blueComponent < 0.25 {
                        foundRed = true
                    }
                    if sample.blueComponent > 0.75 && sample.redComponent < 0.25 {
                        foundBlue = true
                    }
                }
            }
        }
        XCTAssertTrue(foundRed, "Header avatar must draw the local override avatar (red)")
        XCTAssertFalse(foundBlue, "Header avatar must not draw the network avatar (blue) when localAvatarURI is set")
    }
}

struct SnapshotLoginItemService: LoginItemService {
    func status() -> LoginItemRegistrationStatus { .notRegistered }
    func register() throws {}
    func unregister() throws {}
}

struct SnapshotBiometricService: BiometricAuthService {
    func canEvaluateBiometricsOrWatch() -> Bool { true }
    func authenticate(reason: String) async throws -> Bool { false }
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

/// A sender that sends nothing, for the composers the snapshots draw.
final class SnapshotMessageSender: MessageSending, @unchecked Sendable {
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
