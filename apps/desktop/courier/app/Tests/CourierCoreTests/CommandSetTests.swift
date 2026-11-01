// Copyright 2026 VitruvianSoftware
// SPDX-License-Identifier: AGPL-3.0-or-later

import XCTest

@testable import CourierCore

/// The inbox's commands, which the command bar (part 4.7) will list.
@MainActor
final class CommandSetTests: XCTestCase {
    private var harnesses: [InboxHarness] = []
    private var searchHarnesses: [SearchHarness] = []
    private var conversations: [ConversationHarness] = []

    override func tearDown() async throws {
        for harness in harnesses {
            await harness.app.stop()
            harness.cleanUp()
        }
        harnesses = []
        for harness in searchHarnesses {
            await harness.app.stop()
            harness.cleanUp()
        }
        searchHarnesses = []
        for harness in conversations { await harness.stop() }
        conversations = []
    }

    /// The ledger's names (docs/superpowers/specs/2026-10-15-beeper-desktop-inventory/ledger.tsv, "command"
    /// rows), in the order they are registered.
    private let ledger = [
        "Archive all chats", "Archive all chats older than a week", "Archive all read chats",
        "Mark all chats as read", "Next Chat", "Show message requests", "Toggle space bar", "Edit spaces",
        "Filter Chats", "Filter by folder type", "Filter by type", "Filter by account",
        "Toggle chat selection mode",
    ]

    private func start(rooms: [[String: Any]]? = nil) async throws -> (InboxHarness, SpacesModel, [CourierCommand]) {
        let h = try await startInbox(
            rooms: rooms ?? [room("!a", ts: 200), room("!b", ts: 100, unread: 2), room("!c", ts: 50)],
            autoRelease: true)
        harnesses.append(h)
        h.script.spaces = [
            spaceJSON("inbox", chats: 3, unread: 1), spaceJSON("requests"), spaceJSON("archive"),
            spaceJSON("account:whatsapp", kind: "account", title: "WhatsApp", network: "whatsapp", showInInbox: "all"),
            spaceJSON("account:signal", kind: "account", title: "Signal", network: "signal", showInInbox: "all"),
        ]
        let spaces = SpacesModel(appModel: h.app, inbox: h.inbox, sleep: { _ in })
        try await waitUntil { !spaces.spaces.isEmpty }
        return (h, spaces, CommandSet.inbox(h.inbox, spaces))
    }

    private func command(_ commands: [CourierCommand], _ id: String) throws -> CourierCommand {
        try XCTUnwrap(commands.first { $0.id == id }, id)
    }

    func testEveryCommandHasALedgerNameAndRuns() async throws {
        let (h, spaces, commands) = try await start()
        XCTAssertEqual(commands.map(\.id), ledger, "exactly the ledger's 13, once each")
        XCTAssertEqual(Set(commands.map(\.id)).count, 13)
        // The four bulk commands ask first, in words that say what happens; the other nine just run.
        let bulk: Set<String> = ["Archive all chats", "Archive all chats older than a week",
                                 "Archive all read chats", "Mark all chats as read"]
        XCTAssertEqual(Set(commands.filter { $0.confirmation != nil }.map(\.id)), bulk)
        for command in commands where bulk.contains(command.id) {
            XCTAssertFalse(command.confirmation?.isEmpty ?? true, command.id)
        }
        for id in bulk.subtracting(["Mark all chats as read"]) {
            XCTAssertTrue(try command(commands, id).confirmation?.contains("Pinned chats stay") ?? false, id)
        }
        XCTAssertTrue(try command(commands, "Mark all chats as read").confirmation?.contains("can’t be undone") ?? false)
        for command in commands {
            XCTAssertEqual(command.title, command.id, "the title is the ledger's name (in English)")
            XCTAssertTrue(command.isEnabled(), command.id)
        }

        // The sweeps ask the engine, for the space that is shown.
        try command(commands, "Archive all chats").run()
        try await waitUntil { h.count("inbox.archiveMatching") == 1 }
        try command(commands, "Archive all chats older than a week").run()
        try await waitUntil { h.count("inbox.archiveMatching") == 2 }
        try command(commands, "Archive all read chats").run()
        try await waitUntil { h.count("inbox.archiveMatching") == 3 }
        XCTAssertEqual(dicts(h.server.receivedParams("inbox.archiveMatching")), dicts([
            ["read_only": false, "older_than_ms": 0, "dry_run": false],
            ["read_only": false, "older_than_ms": 604_800_000, "dry_run": false],
            ["read_only": true, "older_than_ms": 0, "dry_run": false],
        ]))

        try command(commands, "Mark all chats as read").run()
        try await waitUntil { h.count("inbox.markAllRead") == 1 }
        XCTAssertEqual(dicts(h.server.receivedParams("inbox.markAllRead")), dicts([[String: Any]()]),
                       "the inbox: no space named")

        // Next Chat opens the first chat.
        XCTAssertNil(h.inbox.selectedRoomID)
        try command(commands, "Next Chat").run()
        XCTAssertNotNil(h.inbox.selectedRoomID)

        try command(commands, "Toggle space bar").run()
        XCTAssertFalse(h.preferences.showSpaceBar, "it was on")
        try command(commands, "Toggle space bar").run()
        XCTAssertTrue(h.preferences.showSpaceBar)

        try command(commands, "Edit spaces").run()
        XCTAssertTrue(spaces.isEditing)

        try command(commands, "Toggle chat selection mode").run()
        XCTAssertTrue(h.inbox.isSelecting)
        try command(commands, "Toggle chat selection mode").run()
        XCTAssertFalse(h.inbox.isSelecting)

        try command(commands, "Show message requests").run()
        XCTAssertEqual(h.inbox.query.space, "requests")

        try command(commands, "Filter by account").run()
        XCTAssertEqual(h.inbox.query.space, "account:whatsapp", "the next account after the space shown")
    }

    func testFilterCommandsStepThroughTheirChoices() async throws {
        let (h, _, commands) = try await start()
        let filter = try command(commands, "Filter Chats")
        let folder = try command(commands, "Filter by folder type")
        let type = try command(commands, "Filter by type")
        let account = try command(commands, "Filter by account")

        // Filter by account steps through the accounts only, and wraps.
        account.run()
        XCTAssertEqual(h.inbox.query.space, "account:whatsapp")
        account.run()
        XCTAssertEqual(h.inbox.query.space, "account:signal")
        account.run()
        XCTAssertEqual(h.inbox.query.space, "account:whatsapp")

        // Filter Chats is Cycle Filters: Unread, Drafts, Unanswered, DMs, Groups, then All.
        filter.run()
        XCTAssertEqual(h.inbox.query.filters, [.unread])
        filter.run()
        XCTAssertEqual(h.inbox.query.filters, [.drafts])
        h.inbox.query.filters = []

        // Folder type steps through the place filters and back to none, keeping the other filters.
        h.inbox.query.filters = [.unread]
        var seen: [Set<InboxFilter>] = []
        for _ in 0 ..< 7 {
            folder.run()
            seen.append(h.inbox.query.filters)
        }
        XCTAssertEqual(seen, [
            [.unread, .archived], [.unread, .lowPriority], [.unread, .hidden], [.unread, .requests],
            [.unread, .reminders], [.unread, .sendLater], [.unread],
        ])

        // Type: DMs, Groups, neither.
        h.inbox.query.filters = [.unread, .archived]
        type.run()
        XCTAssertEqual(h.inbox.query.filters, [.unread, .archived, .dms])
        type.run()
        XCTAssertEqual(h.inbox.query.filters, [.unread, .archived, .groups])
        type.run()
        XCTAssertEqual(h.inbox.query.filters, [.unread, .archived])
    }

    func testSweepsAreOffWhereTheEngineWouldRefuse() async throws {
        let (_, spaces, commands) = try await start()
        let sweeps = ["Archive all chats", "Archive all chats older than a week", "Archive all read chats"]
        for id in sweeps { XCTAssertTrue(try command(commands, id).isEnabled(), id) }
        spaces.select("account:signal")
        for id in sweeps { XCTAssertTrue(try command(commands, id).isEnabled(), id) }
        spaces.select("archive")
        for id in sweeps { XCTAssertFalse(try command(commands, id).isEnabled(), id) }
    }

    func testCommandsThatNeedChatsAreOffWithoutThem() async throws {
        let (h, spaces, commands) = try await start(rooms: [room("!a", ts: 200)])
        h.script.spaces = [spaceJSON("inbox", chats: 1, unread: 0)]
        h.server.notify(["kind": "spaces"])
        try await waitUntil { spaces.spaces.count == 1 && spaces.spaces[0].unreadChats == 0 }
        XCTAssertFalse(try command(commands, "Mark all chats as read").isEnabled(), "nothing is unread")
        XCTAssertTrue(try command(commands, "Next Chat").isEnabled())

        h.script.spaces = [spaceJSON("inbox", chats: 1, unread: 1)]
        h.server.notify(["kind": "spaces"])
        try await waitUntil { spaces.spaces.first?.unreadChats == 1 }
        XCTAssertTrue(try command(commands, "Mark all chats as read").isEnabled())

        h.script.rooms = []
        h.server.notify(["kind": "room"])
        try await waitUntil { h.inbox.rows.isEmpty }
        XCTAssertFalse(try command(commands, "Next Chat").isEnabled())
        XCTAssertFalse(try command(commands, "Toggle chat selection mode").isEnabled())
    }

    func testMarkAllReadFollowsTheSpacesCountNotTheFirstPage() async throws {
        // The first page holds no unread chat, but the space says 40 are unread further down.
        let (h, spaces, commands) = try await start(rooms: [room("!a", ts: 200), room("!b", ts: 100)])
        h.script.spaces = [spaceJSON("inbox", chats: 500, unread: 40)]
        h.server.notify(["kind": "spaces"])
        try await waitUntil { spaces.spaces.first?.unreadChats == 40 }
        XCTAssertTrue(h.inbox.rows.allSatisfy { !$0.isUnread })
        XCTAssertTrue(try command(commands, "Mark all chats as read").isEnabled())

        // A space the bar doesn't know falls back to the chats loaded.
        spaces.select("label:9")
        XCTAssertFalse(try command(commands, "Mark all chats as read").isEnabled())
    }

    func testKeysAreTheLedgersWhereItGivesOne() async throws {
        let (_, _, commands) = try await start()
        let keys = Dictionary(uniqueKeysWithValues: commands.map { ($0.id, $0.keys) })
        XCTAssertEqual(keys["Archive all read chats"], "⌘⇧E")
        XCTAssertEqual(keys["Next Chat"], "⌘]")
        XCTAssertEqual(keys["Filter by account"], "⌘⌥A")
        XCTAssertEqual(keys["Toggle space bar"], "⌘S")
        XCTAssertNil(keys["Edit spaces"] ?? nil)
    }

    func testFilterByAccountIsOffWithoutAccounts() async throws {
        let h = try await startInbox(rooms: [room("!a", ts: 100)], autoRelease: true)
        harnesses.append(h)
        h.script.spaces = [spaceJSON("inbox"), spaceJSON("archive")]
        let spaces = SpacesModel(appModel: h.app, inbox: h.inbox, sleep: { _ in })
        try await waitUntil { !spaces.spaces.isEmpty }
        let account = try command(CommandSet.inbox(h.inbox, spaces), "Filter by account")
        XCTAssertFalse(account.isEnabled())
        account.run()
        XCTAssertEqual(h.inbox.query.space, "inbox")
    }

    // MARK: - Search

    func testSearchCommandsHaveLedgerNamesAndRun() async throws {
        let h = try await startSearch(rooms: [room("!a", ts: 1, name: "Picnic planning")])
        searchHarnesses.append(h)
        let open = OpenRoom()
        let commands = CommandSet.search(h.search, openRoomID: { open.id })
        // The ledger's two ("command" rows), and 02 §4's "Search messages in current chat".
        XCTAssertEqual(commands.map(\.id),
                       ["Search chats", "Search messages in all chats", "Search messages in current chat"])
        XCTAssertEqual(commands.map(\.keys), ["⌘K", "⌘K", "⌘F"])
        for command in commands {
            XCTAssertEqual(command.title, command.id, "the title is the ledger's name (in English)")
            XCTAssertNil(command.confirmation, "searching changes nothing, so nothing asks first")
        }
        let inbox = ["Archive all chats", "Next Chat", "Toggle space bar"]
        XCTAssertTrue(Set(commands.map(\.id)).isDisjoint(with: inbox + ledger), "no id is the inbox's too")

        let chats = try command(commands, "Search chats")
        let messages = try command(commands, "Search messages in all chats")
        let here = try command(commands, "Search messages in current chat")
        XCTAssertTrue(chats.isEnabled())
        XCTAssertTrue(messages.isEnabled())
        XCTAssertFalse(here.isEnabled(), "no chat is open")
        here.run()
        XCTAssertEqual(h.search.phase, .closed, "with no chat open it does nothing")

        chats.run()
        XCTAssertEqual(h.search.phase, .home)
        XCTAssertNil(h.search.scope)
        h.search.close()
        messages.run()
        XCTAssertEqual(h.search.phase, .home)
        XCTAssertNil(h.search.scope)
        h.search.close()

        open.id = "!a"
        XCTAssertTrue(here.isEnabled())
        here.run()
        XCTAssertEqual(h.search.phase, .home)
        try await waitUntil { h.search.scope?.roomID == "!a" }

        // Over a panel searching in a chat, the other two search every chat again.
        chats.run()
        XCTAssertNil(h.search.scope)
    }

    // MARK: - Messages

    /// The message commands of the ledger's command bar (02 §3.3): registered for ⌘J (part 4.7), each on only when
    /// `MessageActions.available` offers it for the selected message.
    func testMessageCommandsHaveLedgerNamesAndFollowAvailability() async throws {
        let h = try await startConversation(
            ["!a": [textEvent(id: "$1", room: "!a", at: 1, body: "Theirs"),
                    textEvent(id: "$2", room: "!a", at: 2, body: "Mine", mine: true)]],
            features: ["!a": featuresJSON()], rows: ["!a": chatRow("!a", name: "Ann")])
        conversations.append(h)
        try await h.open("!a")
        let actions = MessageActionsModel(conversation: h.conversation, appModel: h.app, preferences: h.preferences,
                                          pasteboard: FakePasteboard())
        actions.quickReplies = h.quickReplies
        let commands = CommandSet.message(actions, h.conversation)
        XCTAssertEqual(commands.map(\.id), ["Send later", "Create quick reply from draft", "Edit", "Forward", "Unsend",
                                            "Delete for me", "Reply in thread", "Reply privately", "Mark as unread"])
        XCTAssertEqual(commands.map(\.keys), ["⌘⇧L", nil, "⌘T", "⌘⇧F", nil, nil, "⌘↓", nil, nil])
        XCTAssertTrue(commands.allSatisfy { $0.confirmation == nil }, "Unsend and Delete for Me ask in their own words")
        func enabled() throws -> [String] { commands.filter { $0.isEnabled() }.map(\.id) }

        // Nothing selected, nothing typed: nothing to act on.
        XCTAssertEqual(try enabled(), [])

        // My message: everything the chat allows.
        h.conversation.selectedMessageID = "$2"
        XCTAssertEqual(try enabled(), ["Edit", "Forward", "Unsend", "Delete for me", "Reply in thread", "Mark as unread"])
        // Someone else's: no Edit, no Unsend.
        h.conversation.selectedMessageID = "$1"
        XCTAssertEqual(try enabled(), ["Forward", "Delete for me", "Reply in thread", "Mark as unread"])

        // Text in the composer: Send later and a quick reply made from it.
        h.conversation.composer.text = "See you at 6"
        XCTAssertEqual(try enabled(), ["Send later", "Create quick reply from draft", "Forward", "Delete for me",
                                       "Reply in thread", "Mark as unread"])

        // In a chat that can't, its commands go off with the menu's items.
        h.script.features["!a"] = featuresJSON(thread: false, unsend: false)
        h.server.notify(["kind": "room", "room_id": "!a"])
        try await waitUntil { !h.conversation.features.unsend }
        h.conversation.selectedMessageID = "$2"
        XCTAssertEqual(try enabled(), ["Send later", "Create quick reply from draft", "Edit", "Forward", "Delete for me",
                                       "Mark as unread"])

        // Running one does what the menu's item does.
        try XCTUnwrap(commands.first { $0.id == "Edit" }).run()
        XCTAssertEqual(h.conversation.composer.mode, .editing(eventID: "$2", original: RichText(text: "Mine")))
        _ = h.conversation.composer.escape()
        try XCTUnwrap(commands.first { $0.id == "Forward" }).run()
        try await waitUntil { actions.request == .forward(messageID: "$2") }
        try XCTUnwrap(commands.first { $0.id == "Delete for me" }).run()
        try await waitUntil {
            if case .confirm(.deleteForMe, "$2", _)? = actions.request { return true }
            return false
        }
        try XCTUnwrap(commands.first { $0.id == "Send later" }).run()
        XCTAssertEqual(actions.request, .sendLater)
        try XCTUnwrap(commands.first { $0.id == "Create quick reply from draft" }).run()
        XCTAssertEqual(actions.request, .quickReplyTitle)
        XCTAssertTrue(actions.createQuickReply(title: "six"))
        XCTAssertEqual(h.quickReplies.all.map(\.title), ["six"])
        XCTAssertEqual(h.quickReplies.all.first?.text, "See you at 6")
        XCTAssertNil(actions.request)
    }

    /// Incognito's and the accounts' commands, by their ledger names (02 §2.6 "Turn on incognito mode", "Add
    /// Account", "Accounts"). "Turn off incognito mode" is the same row's other state: only the one that applies is
    /// on. The ledger's "Account" (its pane is 4.6's) is not registered here, so Task 11's list must not claim it.
    func testNewCommandsHaveLedgerNames() async throws {
        let h = try await startConversation(
            ["!g": [textEvent(id: "$1", room: "!g", at: 1, body: "Theirs"),
                    textEvent(id: "$2", room: "!g", at: 2, body: "Mine", mine: true)]],
            features: ["!g": featuresJSON()], rows: ["!g": chatRow("!g", name: "Picnic", direct: false)])
        conversations.append(h)
        h.script.accounts = [account("whatsapp", "CONNECTED")]
        await h.app.refreshAccounts()
        try await h.open("!g")
        let login = LoginFlowModel(caller: ScriptedLoginCaller(), accounts: { [] }, reloadAccounts: {},
                                   credentials: InMemoryCredentialStore(), builtInCredentials: { nil },
                                   restartEngine: {})
        let commands = CommandSet.accounts(login, h.conversation)
        XCTAssertEqual(commands.map(\.id), ["Turn on incognito mode", "Turn off incognito mode", "Add Account",
                                            "Accounts"])
        XCTAssertEqual(commands.map(\.title), ["Turn on incognito mode", "Turn off incognito mode", "Add Account",
                                               "Accounts"])
        XCTAssertTrue(commands.allSatisfy { $0.confirmation == nil && $0.keys == nil })
        func enabled() -> [String] { commands.filter { $0.isEnabled() }.map(\.id) }

        // Without the plan, Incognito can't be turned on.
        XCTAssertEqual(enabled(), ["Add Account", "Accounts"])
        h.conversation.isEntitled = { _ in true }
        XCTAssertEqual(enabled(), ["Turn on incognito mode", "Add Account", "Accounts"])
        try XCTUnwrap(commands.first { $0.id == "Turn on incognito mode" }).run()
        XCTAssertTrue(h.preferences.incognito)
        XCTAssertTrue(h.conversation.asksToHideTyping, "turning it on asks about typing, as Settings does")
        XCTAssertEqual(enabled(), ["Turn off incognito mode", "Add Account", "Accounts"])
        try XCTUnwrap(commands.first { $0.id == "Turn off incognito mode" }).run()
        XCTAssertFalse(h.preferences.incognito)

        // Add Account and Accounts open Add a Network (the Accounts pane is 4.6's).
        try XCTUnwrap(commands.first { $0.id == "Add Account" }).run()
        XCTAssertEqual(login.screen, .picker)
        login.close()
        try XCTUnwrap(commands.first { $0.id == "Accounts" }).run()
        XCTAssertEqual(login.screen, .picker)

    }

    /// Reply privately and Mark as unread (02 §3.4.2 items 5 and 8, the message menu's): they have no ledger row, so
    /// they are named as the menu's items are. They act on the selected message, as those items do.
    func testReplyPrivatelyAndMarkAsUnreadCommandsFollowTheMenu() async throws {
        let h = try await startConversation(
            ["!g": [textEvent(id: "$1", room: "!g", at: 1, body: "Theirs"),
                    textEvent(id: "$2", room: "!g", at: 2, body: "Mine", mine: true)]],
            features: ["!g": featuresJSON()], rows: ["!g": chatRow("!g", name: "Picnic", direct: false)])
        conversations.append(h)
        h.script.accounts = [account("whatsapp", "CONNECTED")]
        await h.app.refreshAccounts()
        try await h.open("!g")
        let actions = MessageActionsModel(conversation: h.conversation, appModel: h.app, preferences: h.preferences,
                                          pasteboard: FakePasteboard())
        let message = CommandSet.message(actions, h.conversation)
        let privately = try XCTUnwrap(message.first { $0.id == "Reply privately" })
        let unread = try XCTUnwrap(message.first { $0.id == "Mark as unread" })
        XCTAssertEqual(privately.title, "Reply privately")
        XCTAssertEqual(unread.title, "Mark as unread")
        XCTAssertFalse(privately.isEnabled())
        XCTAssertFalse(unread.isEnabled())
        h.conversation.selectedMessageID = "$2"
        XCTAssertFalse(privately.isEnabled(), "not on my own message")
        XCTAssertTrue(unread.isEnabled())
        h.conversation.selectedMessageID = "$1"
        XCTAssertTrue(privately.isEnabled())
        unread.run()
        try await waitUntil { h.count("room.setUnreadFrom") == 1 }
        XCTAssertEqual(h.server.receivedParams("room.setUnreadFrom").first as? [String: String], ["event_id": "$1"])
        h.conversation.selectedMessageID = "$1"
        privately.run()
        try await waitUntil { h.count("room.directChat") == 1 }
    }

    func testChatInfoAndNewChatCommandsRegistered() {
        let commands = CommandSet.chatInfo()
        let byID = Dictionary(uniqueKeysWithValues: commands.map { ($0.id, $0) })

        XCTAssertNotNil(byID["conversation.toggleChatInfo"])
        XCTAssertEqual(byID["conversation.toggleChatInfo"]?.keys, "⌘⇧I")
        XCTAssertNil(byID["conversation.searchChatInfo"]?.keys)
        XCTAssertEqual(byID["conversation.toggleCalendar"]?.keys, "⌘⌥K")
        XCTAssertEqual(byID["conversation.showSenderCard"]?.keys, "⌘⇧O")
        XCTAssertEqual(byID["inbox.newGroupOrBlast"]?.keys, "⌘⇧N")
    }

    func testMediaViewerCommandRegistered() {
        var didOpenMediaViewer = false
        let commands = CommandSet.chatInfo(openMediaViewer: {
            didOpenMediaViewer = true
        })
        let command = commands.first { $0.id == "media.viewer" || $0.title == "Media viewer" }
        XCTAssertNotNil(command)
        XCTAssertEqual(command?.id, "media.viewer")
        XCTAssertEqual(command?.title, "Media viewer")
        XCTAssertTrue(command?.isEnabled() ?? false)
        command?.run()
        XCTAssertTrue(didOpenMediaViewer)
    }

    func testRecordAudioCommandEnabledOnlyWhenChatSupportsVoice() {
        let composer = ComposerModel(sender: nil)
        let cmd = CommandSet.recordAudio(composer)
        XCTAssertEqual(cmd.id, "hotkey Message: Record Audio")
        XCTAssertEqual(cmd.keys, "⌘⇧A")
        XCTAssertFalse(cmd.isEnabled(), "disabled when no chat is open")

        composer.open("!a")
        composer.features = .noFeatures
        XCTAssertFalse(cmd.isEnabled(), "disabled when open chat does not support voice notes")

        var voiceFeatures = ChatFeatures.noFeatures
        voiceFeatures.voiceFeatures = FileKindFeatures(supported: true, caption: false)
        composer.features = voiceFeatures
        XCTAssertTrue(cmd.isEnabled(), "enabled when open chat supports voice notes")
    }

    func testSendGIFAndSendStickerCommandsRegisteredUnderMessageCategory() {
        let composer = ComposerModel(sender: nil)
        let gifCmd = CommandSet.sendGIF(composer)
        let stickerCmd = CommandSet.sendSticker(composer)
        let mediaCmds = CommandSet.composerMedia(composer)
        XCTAssertEqual(mediaCmds.map(\.id), ["message.sendGIF", "message.sendSticker"])

        XCTAssertEqual(gifCmd.id, "message.sendGIF")
        XCTAssertEqual(gifCmd.title, "Send GIF")
        XCTAssertEqual(gifCmd.keys, "⌘⇧G")
        XCTAssertEqual(gifCmd.key, "g")
        XCTAssertEqual(gifCmd.modifiers, [.command, .shift])
        XCTAssertEqual(gifCmd.category, .message)
        XCTAssertFalse(gifCmd.isEnabled(), "disabled when no chat is open")

        XCTAssertEqual(stickerCmd.id, "message.sendSticker")
        XCTAssertEqual(stickerCmd.title, "Send Sticker")
        XCTAssertEqual(stickerCmd.keys, "⌘⌥⇧S")
        XCTAssertEqual(stickerCmd.key, "s")
        XCTAssertEqual(stickerCmd.modifiers, [.command, .option, .shift])
        XCTAssertEqual(stickerCmd.category, .message)
        XCTAssertFalse(stickerCmd.isEnabled(), "disabled when no chat is open")

        composer.open("!a")
        var unsupported = ChatFeatures(source: .stored)
        unsupported.gif = .unsupported
        unsupported.sticker = .unsupported
        composer.features = unsupported
        XCTAssertFalse(gifCmd.isEnabled())
        XCTAssertFalse(stickerCmd.isEnabled())

        var supported = ChatFeatures(source: .stored)
        supported.gif = MediaCapFeature(supported: true, mimeTypes: ["image/gif", "video/mp4"], captions: true)
        supported.sticker = MediaCapFeature(supported: true, mimeTypes: ["image/png", "image/webp"])
        composer.features = supported
        XCTAssertTrue(gifCmd.isEnabled())
        XCTAssertTrue(stickerCmd.isEnabled())

        gifCmd.run()
        XCTAssertTrue(composer.isGIFPickerPresented)
        XCTAssertFalse(composer.isStickerPickerPresented)

        stickerCmd.run()
        XCTAssertTrue(composer.isStickerPickerPresented)
        XCTAssertFalse(composer.isGIFPickerPresented)
    }

    func testSettingsAndSystemCommandsRouteToHandlers() async throws {
        struct AlwaysBiometric: BiometricAuthService {
            func canEvaluateBiometricsOrWatch() -> Bool { true }
            func canEvaluateDeviceOwnerAuthentication() -> Bool { true }
            func authenticate(reason _: String) async throws -> Bool { true }
        }
        struct StubLoginItem: LoginItemService {
            func status() -> LoginItemRegistrationStatus { .notRegistered }
            func register() throws {}
            func unregister() throws {}
        }

        let (h, _, _) = try await start()
        let testStore = TestDefaults()
        defer {
            AppLockGate.shared.resetForTesting()
            testStore.remove()
        }
        let lifecycle = SystemLifecycleModel(
            loginItemService: StubLoginItem(),
            biometricService: AlwaysBiometric(),
            defaults: testStore.defaults
        )
        let navigation = SettingsNavigationModel()
        let hotkeys = HotkeyRegistry(defaults: testStore.defaults)
        let detached = DetachedWindowRegistry(
            appModel: h.app,
            mainInbox: h.inbox,
            lifecycle: lifecycle,
            inboxPreferences: h.preferences,
            composerPreferences: ComposerPreferences(defaults: testStore.defaults),
            quickReplies: QuickReplies(defaults: testStore.defaults),
            entitlement: AlwaysEntitled(),
            makePasteboard: { FakePasteboard() },
            openURL: { _ in },
            hotkeys: hotkeys
        )
        var openedSettingsWindowCount = 0
        var didReportProblem = false
        var didRestartNotificationCenter = false

        let cmds = CommandSet.settingsAndSystem(
            navigation: navigation,
            inbox: h.inbox,
            lifecycle: lifecycle,
            hotkeys: hotkeys,
            detachedRegistry: detached,
            openSettingsWindow: { openedSettingsWindowCount += 1 },
            presentReportProblem: { didReportProblem = true },
            restartNotificationCenter: { didRestartNotificationCenter = true }
        )
        let byID = Dictionary(uniqueKeysWithValues: cmds.map { ($0.id, $0) })

        let expectedPanes: [(String, SettingsPaneID)] = [
            ("Settings", .general),
            ("General", .general),
            ("Appearance", .appearance),
            ("Notifications", .notifications),
            ("Accounts", .accounts),
            ("Account", .accounts),
            ("Hotkeys", .hotkeys),
            ("Quick Replies", .quickReplies),
            ("Bridges", .bridges),
            ("About", .about),
            ("Help", .about),
        ]

        for (commandID, expectedPane) in expectedPanes {
            let cmd = try XCTUnwrap(byID[commandID], "Missing command \(commandID)")
            XCTAssertTrue(cmd.isEnabled())
            cmd.run()
            XCTAssertEqual(navigation.selectedPane, expectedPane, "Command \(commandID) did not select \(expectedPane)")
        }
        XCTAssertEqual(openedSettingsWindowCount, expectedPanes.count)

        let reportCmd = try XCTUnwrap(byID["Report a problem"])
        reportCmd.run()
        XCTAssertTrue(didReportProblem)

        let restartNotifCmd = try XCTUnwrap(byID["Restart Notification Center"])
        restartNotifCmd.run()
        XCTAssertTrue(didRestartNotificationCenter)

        let openSpaceCmd = try XCTUnwrap(byID["Open space in new window"])
        openSpaceCmd.run()
        XCTAssertTrue(detached.openTargets.contains(.space(spaceID: "inbox")))

        let shortcutsCmd = try XCTUnwrap(byID["Show keyboard shortcuts"])
        shortcutsCmd.run()
        XCTAssertTrue(hotkeys.isShortcutsSheetPresented)

        let lockCmd = try XCTUnwrap(byID["Lock app"])
        lockCmd.run()
        XCTAssertTrue(lifecycle.isLocked)
        XCTAssertFalse(try XCTUnwrap(byID["Settings"]).isEnabled(), "commands are disabled while locked")
    }

    func testDeleteMediaCommandAndCopyAvoidCacheWording() {
        XCTAssertEqual(CommandSet.deleteMediaTitle, "Delete Media…")
        XCTAssertEqual(CommandSet.deleteMediaOlderThanTitle("1 month"), "Delete media older than 1 month")
        XCTAssertEqual(CommandSet.deleteMediaInThisChatTitle, "Delete media in this chat")
        XCTAssertEqual(
            CommandSet.deleteMediaConfirmation,
            "This deletes photos, videos and files from this Mac. Messages stay, but the media can't be brought back."
        )

        var didDelete = false
        let cmd = CommandSet.deleteMedia(performDelete: { didDelete = true })
        XCTAssertEqual(cmd.id, "Delete Media…")
        XCTAssertEqual(cmd.title, "Delete Media…")
        XCTAssertEqual(
            cmd.confirmation,
            "This deletes photos, videos and files from this Mac. Messages stay, but the media can't be brought back."
        )
        XCTAssertFalse(cmd.title.localizedCaseInsensitiveContains("cache"))
        XCTAssertFalse((cmd.confirmation ?? "").localizedCaseInsensitiveContains("cache"))
        XCTAssertTrue(cmd.isEnabled())
        cmd.run()
        XCTAssertTrue(didDelete)
    }

    func testUnifiedCommandSetCoversEveryAcceptanceAndLedgerCommand() async throws {
        let (h, spaces, inboxCommands) = try await start()
        let searchH = try await startSearch(rooms: [room("!a", ts: 1, name: "Picnic planning")])
        searchHarnesses.append(searchH)
        let convH = try await startConversation(
            ["!a": [textEvent(id: "$1", room: "!a", at: 1, body: "Theirs"),
                    textEvent(id: "$2", room: "!a", at: 2, body: "Mine", mine: true)]],
            features: ["!a": featuresJSON()],
            rows: ["!a": chatRow("!a", name: "Ann")]
        )
        conversations.append(convH)
        try await convH.open("!a")
        let actions = MessageActionsModel(
            conversation: convH.conversation,
            appModel: convH.app,
            preferences: convH.preferences,
            pasteboard: FakePasteboard()
        )
        let login = LoginFlowModel(
            caller: ScriptedLoginCaller(),
            accounts: { [] },
            reloadAccounts: {},
            credentials: InMemoryCredentialStore(),
            builtInCredentials: { nil },
            restartEngine: {}
        )
        let testStore = TestDefaults()
        defer { testStore.remove() }
        let appearance = AppearancePreferences(defaults: testStore.defaults)
        let navigation = SettingsNavigationModel()
        let hotkeys = HotkeyRegistry(defaults: testStore.defaults)

        let all = CommandSet.all(
            inbox: h.inbox,
            spaces: spaces,
            search: searchH.search,
            actions: actions,
            conversation: convH.conversation,
            composer: convH.conversation.composer,
            login: login,
            appearance: appearance,
            navigation: navigation,
            hotkeys: hotkeys
        )
        let ids = Set(all.map(\.id))
        let titles = Set(all.map(\.title))

        // 1. Every existing CommandSet group must be reachable in CommandSet.all (no second independent registry).
        for cmd in inboxCommands {
            XCTAssertTrue(ids.contains(cmd.id), "Missing CommandSet.inbox command: \(cmd.id)")
        }
        for cmd in CommandSet.search(searchH.search, openRoomID: { convH.conversation.roomID }) {
            XCTAssertTrue(ids.contains(cmd.id), "Missing CommandSet.search command: \(cmd.id)")
        }
        for cmd in CommandSet.message(actions, convH.conversation) {
            XCTAssertTrue(ids.contains(cmd.id), "Missing CommandSet.message command: \(cmd.id)")
        }
        for cmd in CommandSet.accounts(login, convH.conversation) {
            XCTAssertTrue(ids.contains(cmd.id), "Missing CommandSet.accounts command: \(cmd.id)")
        }
        for cmd in CommandSet.chatInfo(conversation: convH.conversation, inbox: h.inbox) {
            XCTAssertTrue(ids.contains(cmd.id), "Missing CommandSet.chatInfo command: \(cmd.id)")
        }
        XCTAssertTrue(ids.contains(CommandSet.recordAudio(convH.conversation.composer).id))
        for cmd in CommandSet.composerMedia(convH.conversation.composer) {
            XCTAssertTrue(ids.contains(cmd.id), "Missing CommandSet.composerMedia command: \(cmd.id)")
        }
        for cmd in CommandSet.settingsAndSystem(navigation: navigation, inbox: h.inbox, hotkeys: hotkeys) {
            XCTAssertTrue(ids.contains(cmd.id), "Missing CommandSet.settingsAndSystem command: \(cmd.id)")
        }

        // 2. Every required 4.1–4.7 command bar title/id must be present.
        let requiredTitles: [String] = [
            "Open recently viewed chats",
            "Archive all chats",
            "Archive all chats older than a week",
            "Archive all read chats",
            "Mark all chats as read",
            "Filter Chats",
            "Create new chat",
            "Merge chats",
            "Attach file",
            "Download attachments",
            "Toggle sidebar",
            "Focus Courier",
            "Load Custom Theme",
            "Reload Custom Theme",
            "Zoom In",
            "Zoom Out",
            "Reset Zoom",
            "Fire Confetti 🎉",
            "Delete Media…",
            "Clear Cache",
            "AI: Summarize Thread",
            "AI: Draft Reply",
            "AI: Translate Message",
            "Message: Talk to Type",
            "Manage Subscription / Plan",
            "Import from Beeper / Matrix",
        ]
        for required in requiredTitles {
            XCTAssertTrue(
                titles.contains(required),
                "Unified CommandSet is missing required command '\(required)'"
            )
        }

        // 3. Nested sub-command trees must be populated.
        let filterCmd = try XCTUnwrap(all.first { $0.title == "Filter Chats" })
        XCTAssertFalse(filterCmd.children.isEmpty, "Filter Chats must have nested sub-commands")
        let remindCmd = try XCTUnwrap(all.first { $0.id == "chat.remindLater" })
        XCTAssertFalse(remindCmd.children.isEmpty, "Remind Later must have nested preset sub-commands")
        let goToSpaceCmd = try XCTUnwrap(all.first { $0.id == "nav.goToSpace" })
        XCTAssertFalse(goToSpaceCmd.children.isEmpty, "Go to Space must have nested space sub-commands")
        let setThemeCmd = try XCTUnwrap(all.first { $0.id == "appearance.setTheme" })
        XCTAssertFalse(setThemeCmd.children.isEmpty, "Set Theme must have nested theme preset sub-commands")
        let disappearingCmd = try XCTUnwrap(all.first { $0.id == "chat.disappearingMessages" })
        XCTAssertFalse(disappearingCmd.children.isEmpty, "Disappearing Messages must have nested timer sub-commands")

        // 4. Destructive commands must require confirmation, and Delete Media… must use CommandSet.deleteMediaConfirmation.
        let deleteMediaCmd = try XCTUnwrap(all.first { $0.id == "Delete Media…" })
        XCTAssertEqual(deleteMediaCmd.confirmation, CommandSet.deleteMediaConfirmation)
        let leaveGroupCmd = try XCTUnwrap(all.first { $0.id == "chat.leaveGroup" })
        XCTAssertNotNil(leaveGroupCmd.confirmation)
        let deleteChatCmd = try XCTUnwrap(all.first { $0.id == "chat.deleteChat" })
        XCTAssertNotNil(deleteChatCmd.confirmation)
    }

    func testEveryCommandChipMatchesItsCommandSetGroup() async throws {
        let (h, spaces, inboxGroup) = try await start()
        let searchH = try await startSearch(rooms: [room("!a", ts: 1, name: "Picnic planning")])
        searchHarnesses.append(searchH)
        let convH = try await startConversation(
            ["!a": [textEvent(id: "$1", room: "!a", at: 1, body: "Theirs"),
                    textEvent(id: "$2", room: "!a", at: 2, body: "Mine", mine: true)]],
            features: ["!a": featuresJSON()],
            rows: ["!a": chatRow("!a", name: "Ann")]
        )
        conversations.append(convH)
        try await convH.open("!a")
        let actions = MessageActionsModel(
            conversation: convH.conversation,
            appModel: convH.app,
            preferences: convH.preferences,
            pasteboard: FakePasteboard()
        )
        let login = LoginFlowModel(
            caller: ScriptedLoginCaller(),
            accounts: { [] },
            reloadAccounts: {},
            credentials: InMemoryCredentialStore(),
            builtInCredentials: { nil },
            restartEngine: {}
        )
        let testStore = TestDefaults()
        defer { testStore.remove() }
        let appearance = AppearancePreferences(defaults: testStore.defaults)
        let navigation = SettingsNavigationModel()
        let hotkeys = HotkeyRegistry(defaults: testStore.defaults)

        let searchGroup = CommandSet.search(searchH.search, openRoomID: { convH.conversation.roomID })
        let messageGroup = CommandSet.message(actions, convH.conversation)
            + [CommandSet.recordAudio(convH.conversation.composer)]
            + CommandSet.composerMedia(convH.conversation.composer)
        let accountsGroup = CommandSet.accounts(login, convH.conversation)
        let chatInfoGroup = CommandSet.chatInfo(conversation: convH.conversation, inbox: h.inbox)
        let settingsGroup = CommandSet.settingsAndSystem(
            navigation: navigation,
            inbox: h.inbox,
            hotkeys: hotkeys
        )

        for cmd in inboxGroup {
            XCTAssertEqual(cmd.category, .inbox, "CommandSet.inbox command '\(cmd.id)' must have chip 'Inbox', got '\(cmd.category.title)'")
            XCTAssertEqual(cmd.category.title, "Inbox", "CommandSet.inbox command '\(cmd.id)' chip mismatch")
        }
        for cmd in searchGroup {
            XCTAssertEqual(cmd.category, .search, "CommandSet.search command '\(cmd.id)' must have chip 'Search', got '\(cmd.category.title)'")
            XCTAssertEqual(cmd.category.title, "Search", "CommandSet.search command '\(cmd.id)' chip mismatch")
        }
        for cmd in messageGroup {
            XCTAssertEqual(cmd.category, .message, "CommandSet.message command '\(cmd.id)' must have chip 'Message', got '\(cmd.category.title)'")
            XCTAssertEqual(cmd.category.title, "Message", "CommandSet.message command '\(cmd.id)' chip mismatch")
        }
        for cmd in accountsGroup {
            XCTAssertEqual(cmd.category, .accounts, "CommandSet.accounts command '\(cmd.id)' must have chip 'Accounts', got '\(cmd.category.title)'")
            XCTAssertEqual(cmd.category.title, "Accounts", "CommandSet.accounts command '\(cmd.id)' chip mismatch")
        }
        for cmd in chatInfoGroup {
            XCTAssertEqual(cmd.category, .chatInfo, "CommandSet.chatInfo command '\(cmd.id)' must have chip 'Chat Info', got '\(cmd.category.title)'")
            XCTAssertEqual(cmd.category.title, "Chat Info", "CommandSet.chatInfo command '\(cmd.id)' chip mismatch")
        }
        for cmd in settingsGroup {
            XCTAssertEqual(cmd.category, .settings, "CommandSet.settingsAndSystem command '\(cmd.id)' must have chip 'Settings', got '\(cmd.category.title)'")
            XCTAssertEqual(cmd.category.title, "Settings", "CommandSet.settingsAndSystem command '\(cmd.id)' chip mismatch")
        }

        let all = CommandSet.all(
            inbox: h.inbox,
            spaces: spaces,
            search: searchH.search,
            actions: actions,
            conversation: convH.conversation,
            composer: convH.conversation.composer,
            login: login,
            appearance: appearance,
            navigation: navigation,
            hotkeys: hotkeys
        )

        var expectedByID: [String: CourierCommand.Category] = [:]
        // Order matches CommandSet.all deduplication order:
        for cmd in inboxGroup { expectedByID[cmd.id] = .inbox }
        for cmd in searchGroup { expectedByID[cmd.id] = .search }
        for cmd in messageGroup { expectedByID[cmd.id] = .message }
        for cmd in accountsGroup { expectedByID[cmd.id] = .accounts }
        for cmd in chatInfoGroup { expectedByID[cmd.id] = .chatInfo }
        for cmd in settingsGroup where expectedByID[cmd.id] == nil {
            expectedByID[cmd.id] = .settings
        }

        for cmd in all {
            if let expected = expectedByID[cmd.id] {
                XCTAssertEqual(cmd.category, expected, "Unified command '\(cmd.id)' chip must match its group (\(expected.title))")
            }
            for child in cmd.children {
                XCTAssertEqual(child.category, cmd.category, "Sub-command '\(child.id)' chip must match parent '\(cmd.id)'")
            }
        }
    }
}

/// The open chat, as the commands read it when they run.
@MainActor
private final class OpenRoom {
    var id: String?
}
