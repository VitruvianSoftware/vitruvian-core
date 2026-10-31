// Copyright 2026 VitruvianSoftware
// SPDX-License-Identifier: AGPL-3.0-or-later

import CourierCore
import Foundation
import XCTest

@MainActor
final class HotkeyRegistryTests: XCTestCase {
    private var suiteName: String!
    private var defaults: UserDefaults!

    override func setUp() async throws {
        suiteName = "HotkeyRegistryTests.\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)!
    }

    override func tearDown() async throws {
        AppLockGate.shared.resetForTesting()
        if let suiteName {
            UserDefaults.standard.removePersistentDomain(forName: suiteName)
        }
        defaults = nil
        suiteName = nil
    }

    func testHotkeyChordSymbolFormatting() {
        XCTAssertEqual(KeyChord(key: "e", command: true, shift: true).symbols, "⌘⇧E")
        XCTAssertEqual(KeyChord(key: "right", option: true, control: true).symbols, "⌃⌥→")
        XCTAssertEqual(KeyChord(key: "tab", control: true).symbols, "⌃Tab")
        XCTAssertEqual(KeyChord(key: "/", command: true).symbols, "⌘/")
        XCTAssertEqual(KeyChord(key: ",", command: true).symbols, "⌘,")
        XCTAssertEqual(KeyChord(key: "enter", command: true).symbols, "⌘Enter")

        XCTAssertFalse(KeyChord(key: "e").hasRequiredModifier)
        XCTAssertTrue(KeyChord(key: "e", command: true).hasRequiredModifier)
        XCTAssertTrue(KeyChord(key: "f5").hasRequiredModifier)
    }

    func testHotkeyRegistryRejectsUnmodifiedKeyAndDetectsConflicts() {
        let registry = HotkeyRegistry(defaults: defaults)

        // 1. Bare single-character key without modifier is refused and not persisted.
        let bareResult = registry.record(KeyChord(key: "a"), for: "Chat: Toggle Archive")
        switch bareResult {
        case .success:
            XCTFail("Expected bare single-character key without modifier to be rejected")
        case let .failure(error):
            XCTAssertEqual(
                error.message,
                "You must use a modifier key like Ctrl, Shift or Option/Alt"
            )
        }
        XCTAssertNil(registry.overrides["Chat: Toggle Archive"])

        // 2. Chord already used by another enabled action is refused with plain message.
        let appConflict = registry.record(
            KeyChord(key: "k", command: true),
            for: "Chat: Toggle Archive"
        )
        switch appConflict {
        case .success:
            XCTFail("Expected conflict with Search (⌘K) to be rejected")
        case let .failure(error):
            XCTAssertEqual(error.message, "⌘K is already used by Search")
        }
        XCTAssertNil(registry.overrides["Chat: Toggle Archive"])

        // 3. Chord reserved by macOS system shortcuts (e.g. ⌘H Hide) is refused.
        let systemConflict = registry.record(
            KeyChord(key: "h", command: true),
            for: "Chat: Toggle Archive"
        )
        switch systemConflict {
        case .success:
            XCTFail("Expected system shortcut conflict (⌘H) to be rejected")
        case let .failure(error):
            XCTAssertTrue(
                error.message.contains("⌘H"),
                "Expected plain-English message naming ⌘H, got: \(error.message)"
            )
        }
        XCTAssertNil(registry.overrides["Chat: Toggle Archive"])

        // 4. Disabling Search allows binding ⌘K to another action.
        registry.setEnabled(false, for: "Search")
        let afterDisable = registry.record(
            KeyChord(key: "k", command: true),
            for: "Chat: Toggle Archive"
        )
        if case let .failure(error) = afterDisable {
            XCTFail("Expected ⌘K to succeed after disabling Search, got \(error)")
        }
        XCTAssertEqual(
            registry.chords(for: "Chat: Toggle Archive"),
            [KeyChord(key: "k", command: true)]
        )
    }

    func testHotkeyRegistryIgnoresRecorderCaptureWhileAppIsLocked() {
        var locked = true
        let registry = HotkeyRegistry(defaults: defaults, isAppLocked: { locked })

        registry.beginRecording(for: "Chat: Toggle Archive")
        XCTAssertNil(registry.recordingHotkeyID, "Recorder must not start while app is locked")

        let result = registry.record(
            KeyChord(key: "b", command: true, shift: true),
            for: "Chat: Toggle Archive"
        )
        switch result {
        case .success:
            XCTFail("Expected shortcut recording to be refused while app is locked")
        case let .failure(error):
            XCTAssertEqual(error, .appLocked)
        }
        XCTAssertNil(registry.overrides["Chat: Toggle Archive"])

        // Once unlocked, recording works.
        locked = false
        registry.beginRecording(for: "Chat: Toggle Archive")
        XCTAssertEqual(registry.recordingHotkeyID, "Chat: Toggle Archive")
        let unlockedResult = registry.record(
            KeyChord(key: "b", command: true, shift: true),
            for: "Chat: Toggle Archive"
        )
        if case let .failure(error) = unlockedResult {
            XCTFail("Expected unlocked shortcut recording to succeed, got \(error)")
        }
        XCTAssertNil(registry.recordingHotkeyID)
    }

    func testHotkeyRegistrySearchFiltersByTitleAndKeySymbols() {
        let registry = HotkeyRegistry(defaults: defaults)

        registry.searchQuery = "archive"
        let archiveMatches = registry.filteredDefinitions.map(\.id)
        XCTAssertTrue(archiveMatches.contains("Chat: Toggle Archive"))
        XCTAssertTrue(archiveMatches.contains("Chat: Archive All Read"))
        XCTAssertTrue(archiveMatches.contains("Message: Send Message and Archive"))
        XCTAssertFalse(archiveMatches.contains("Keyboard Shortcuts"))

        registry.searchQuery = "⌘/"
        let symbolMatches = registry.filteredDefinitions.map(\.id)
        XCTAssertEqual(symbolMatches, ["Keyboard Shortcuts"])
    }

    func testHotkeyRegistryPersistsRevertsAndAppliesTextsPreset() {
        let registry = HotkeyRegistry(defaults: defaults)
        let customChord = KeyChord(key: "j", command: true, option: true)

        if case let .failure(error) = registry.record(customChord, for: "Chat: Toggle Pin") {
            XCTFail("Expected custom chord to succeed, got \(error)")
        }
        registry.setEnabled(false, for: "Chat: Toggle Mute")
        registry.setGlobal(true, for: "Focus App")

        // Changes survive relaunch via UserDefaults.
        let relaunched = HotkeyRegistry(defaults: defaults)
        XCTAssertEqual(relaunched.chords(for: "Chat: Toggle Pin"), [customChord])
        XCTAssertFalse(relaunched.isEnabled("Chat: Toggle Mute"))
        XCTAssertTrue(relaunched.chords(for: "Chat: Toggle Mute").isEmpty)
        XCTAssertTrue(relaunched.globalIDs.contains("Focus App"))

        // Single-item revert restores default and persists.
        relaunched.revert(id: "Chat: Toggle Pin")
        XCTAssertEqual(
            relaunched.chords(for: "Chat: Toggle Pin"),
            [KeyChord(key: "p", command: true)]
        )

        // Texts.app preset applies expected bindings and persists.
        relaunched.applyTextsAppPreset()
        XCTAssertEqual(
            relaunched.chords(for: "Message: Edit"),
            [KeyChord(key: "i", command: true)]
        )
        XCTAssertEqual(
            relaunched.chords(for: "Chat: Toggle Mark As Read"),
            [KeyChord(key: "u", command: true)]
        )
        XCTAssertFalse(relaunched.isEnabled("Chat: Archive All Read"))
        XCTAssertTrue(
            relaunched.chords(for: "Select Next Chat").contains(
                KeyChord(key: "tab", control: true)
            )
        )
        XCTAssertTrue(
            relaunched.chords(for: "Select Previous Chat").contains(
                KeyChord(key: "tab", shift: true, control: true)
            )
        )

        let afterPresetRelaunch = HotkeyRegistry(defaults: defaults)
        XCTAssertEqual(
            afterPresetRelaunch.chords(for: "Message: Edit"),
            [KeyChord(key: "i", command: true)]
        )
        XCTAssertFalse(afterPresetRelaunch.isEnabled("Chat: Archive All Read"))

        // Revert all restores factory defaults and persists.
        afterPresetRelaunch.revertAll()
        XCTAssertTrue(afterPresetRelaunch.overrides.isEmpty)
        XCTAssertTrue(afterPresetRelaunch.disabledIDs.isEmpty)
        XCTAssertTrue(afterPresetRelaunch.globalIDs.isEmpty)

        let afterRevertAllRelaunch = HotkeyRegistry(defaults: defaults)
        XCTAssertEqual(
            afterRevertAllRelaunch.chords(for: "Message: Edit"),
            [KeyChord(key: "t", command: true)]
        )
        XCTAssertTrue(afterRevertAllRelaunch.isEnabled("Chat: Archive All Read"))
    }

    func testFunctionKeysModifierOnlyAndPresetZeroConflicts() {
        let registry = HotkeyRegistry(defaults: defaults)

        // 1. Function keys F1–F12 map from macOS virtual keyCodes and resolve to NSF1..NSF12FunctionKey scalars (not "f").
        XCTAssertEqual(KeyChord.functionKeyName(forKeyCode: 122), "f1")
        XCTAssertEqual(KeyChord.functionKeyName(forKeyCode: 96), "f5")
        XCTAssertEqual(KeyChord.functionKeyName(forKeyCode: 111), "f12")
        XCTAssertEqual(KeyChord.keyEquivalentCharacter(for: "f5"), Character(UnicodeScalar(0xF708)!))
        XCTAssertNotEqual(KeyChord.keyEquivalentCharacter(for: "f5"), Character("f"))

        // 2. Modifier-only shortcut capture for "Switch First 9 Spaces Modifier" and "Switch First 9 Chats Modifier".
        XCTAssertTrue(HotkeyRegistry.isModifierOnlyDefinition("Switch First 9 Spaces Modifier"))
        XCTAssertTrue(HotkeyRegistry.isModifierOnlyDefinition("Switch First 9 Chats Modifier"))
        let modChord = KeyChord.modifierOnlyChord(command: false, shift: false, option: true, control: false)
        XCTAssertEqual(modChord, KeyChord(key: "", option: true))
        if let modChord {
            if case let .failure(error) = registry.record(modChord, for: "Switch First 9 Spaces Modifier") {
                XCTFail("Expected modifier-only chord to succeed, got \(error)")
            }
            XCTAssertEqual(registry.chords(for: "Switch First 9 Spaces Modifier"), [KeyChord(key: "", option: true)])
        }

        // 3. Conflict error message uses the human-readable title (other.title) rather than raw ledger ID.
        let conflict = registry.record(
            KeyChord(key: "u", command: true, shift: true),
            for: "Chat: Toggle Archive"
        )
        switch conflict {
        case .success:
            XCTFail("Expected conflict with Mark Chat Read or Unread (⌘⇧U) to be rejected")
        case let .failure(error):
            XCTAssertEqual(error.message, "⌘⇧U is already used by Mark Chat Read or Unread")
        }

        // 4. Default bindings and Texts.app preset must leave zero active chord conflicts across enabled shortcuts.
        registry.revertAll()
        XCTAssertTrue(
            registry.activeConflicts().isEmpty,
            "Expected zero conflicts in default bindings, got: \(registry.activeConflicts())"
        )
        registry.applyTextsAppPreset()
        XCTAssertTrue(
            registry.activeConflicts().isEmpty,
            "Expected zero conflicts after applying Texts.app preset, got: \(registry.activeConflicts())"
        )
    }

    func testEveryHotkeyDefinitionResolvesToWiredCommandHandler() {
        let supervisor = EngineSupervisor(
            enginePath: "/Applications/Courier.app/Contents/Helpers/courier-engine",
            dataDir: URL(fileURLWithPath: "/tmp/courier-test-hotkeys"),
            environment: [:],
            launcher: FakeLauncher { _, _ in }
        )
        let appModel = AppModel(supervisor: supervisor)
        let inboxPrefs = InboxPreferences(defaults: defaults)
        let composerPrefs = ComposerPreferences(defaults: defaults)
        let inbox = InboxModel(appModel: appModel, preferences: inboxPrefs)
        let spaces = SpacesModel(appModel: appModel, inbox: inbox)
        let search = SearchModel(appModel: appModel, recents: RecentSearches(defaults: defaults), open: { _ in })
        let conversation = ConversationModel(appModel: appModel, preferences: composerPrefs)
        for composer in [conversation.composer, conversation.thread.composer] {
            composer.entitlement = AlwaysEntitled()
        }
        final class NoopPasteboard: TextPasteboard {
            func setString(_ text: String) {}
        }
        let messageActions = MessageActionsModel(
            conversation: conversation,
            appModel: appModel,
            preferences: composerPrefs,
            pasteboard: NoopPasteboard()
        )
        let lifecycle = SystemLifecycleModel(
            defaults: defaults,
            loginItem: FakeLoginItemService(currentStatus: .notRegistered),
            biometrics: FakeBiometricAuthService(available: true, result: .success(true))
        )
        var hideAppCount = 0
        let coordinator = AppMenuCoordinator(
            inbox: inbox,
            lifecycle: lifecycle,
            hideApp: { hideAppCount += 1 }
        )
        let registry = HotkeyRegistry(defaults: defaults, isAppLocked: { lifecycle.isLocked })
        let dispatcher = HotkeyDispatcher(
            inbox: inbox,
            spaces: spaces,
            conversation: conversation,
            messageActions: messageActions,
            search: search,
            lifecycle: lifecycle,
            menuCoordinator: coordinator,
            hotkeys: registry
        )

        let definedIDs = Set(HotkeyRegistry.allDefinitions.map(\.id))
        XCTAssertFalse(definedIDs.isEmpty)
        XCTAssertEqual(
            HotkeyDispatcher.allLiveWiredShortcutIDs,
            definedIDs,
            "Every HotkeyDefinition in HotkeyRegistry.allDefinitions must be wired in the live menu/window/composer bindings"
        )

        // Verify wired command handlers execute their real model actions via HotkeyDispatcher.
        appModel.setAccountsForTesting([
            Account(network: "signal", displayName: "Signal", flows: ["qr"], state: .connected),
            Account(network: "whatsapp", displayName: "WhatsApp", flows: ["qr"], state: .connected),
        ])
        spaces.setSpacesForTesting([
            Space(spaceID: "inbox", kind: .builtin, title: "Inbox"),
            Space(spaceID: "account:signal", kind: .account, title: "Signal", network: "signal"),
            Space(spaceID: "account:whatsapp", kind: .account, title: "WhatsApp", network: "whatsapp"),
        ])
        let aliceRow = InboxRow(
            roomID: "!r1",
            network: "signal",
            name: "Alice",
            avatarPath: "",
            isDirect: true,
            lastTS: 100,
            preview: "Hi",
            previewKind: .text,
            previewMine: false,
            unread: 1,
            muted: false
        )
        let bobRow = InboxRow(
            roomID: "!r2",
            network: "signal",
            name: "Bob",
            avatarPath: "",
            isDirect: true,
            lastTS: 90,
            preview: "Yo",
            previewKind: .text,
            previewMine: false,
            unread: 0,
            muted: false
        )
        inbox.setSnapshotRowsForTesting([aliceRow, bobRow])
        inbox.select("!r1")
        inbox.select("!r2")
        XCTAssertEqual(inbox.selectedRoomID, "!r2")

        XCTAssertTrue(dispatcher.perform("History: Previous Chat"))
        XCTAssertEqual(inbox.selectedRoomID, "!r1")

        XCTAssertTrue(dispatcher.perform("History: Next Chat"))
        XCTAssertEqual(inbox.selectedRoomID, "!r2")

        let forwardCycleBinding = WindowShortcutBinding(
            hotkeyID: "Cycle Chats (hold shift to reverse)",
            chordIndex: 0,
            reversesCycle: false
        )
        let reverseCycleBinding = WindowShortcutBinding(
            hotkeyID: "Cycle Chats (hold shift to reverse)",
            chordIndex: 0,
            reversesCycle: true
        )
        XCTAssertTrue(dispatcher.perform(forwardCycleBinding))
        XCTAssertEqual(inbox.selectedRoomID, "!r1")
        XCTAssertTrue(dispatcher.perform(reverseCycleBinding))
        XCTAssertEqual(inbox.selectedRoomID, "!r2")

        XCTAssertTrue(dispatcher.perform("Focus App"))
        XCTAssertEqual(coordinator.focusCount, 1)

        XCTAssertTrue(dispatcher.perform("Minimize To Menu Bar"))
        XCTAssertEqual(hideAppCount, 1)

        XCTAssertTrue(dispatcher.perform("Quit App"))
        XCTAssertEqual(coordinator.quitRequestedCount, 1)

        XCTAssertTrue(dispatcher.perform("Chat: Create New Group"))
        XCTAssertNotNil(inbox.startNewChatDraft)

        // Verify "Chat: Send File" invokes the attachment picker callback on the active composer.
        appModel.selectedRoomID = nil
        conversation.openDetachedRoom(nil)
        XCTAssertFalse(dispatcher.canPerform("Chat: Send File")) // No room open yet

        // Verify "Download Attachments" actually downloads the selected message's attachment (no empty {} closure).
        let tempRoot = FileManager.default.temporaryDirectory.appendingPathComponent("courier-hotkey-dl-\(UUID().uuidString)")
        let sourceDir = tempRoot.appendingPathComponent("store", isDirectory: true)
        let downloadsDir = tempRoot.appendingPathComponent("downloads", isDirectory: true)
        try? FileManager.default.createDirectory(at: sourceDir, withIntermediateDirectories: true)
        try? FileManager.default.createDirectory(at: downloadsDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempRoot) }
        let sourceFile = sourceDir.appendingPathComponent("blob123")
        try? Data("attachment-bytes".utf8).write(to: sourceFile)
        composerPrefs.downloadsDirectoryPath = downloadsDir.path
        composerPrefs.alwaysAskWhereToSaveFiles = false

        let attachmentEvent = Event(
            eventID: "$att1",
            roomID: "!r2",
            sender: "@alice:courier.local",
            senderName: "Alice Example",
            mine: false,
            type: "m.room.message",
            content: .object([
                "msgtype": .string("m.file"),
                "body": .string("report.txt"),
                "filename": .string("report.txt"),
                "url": .string(sourceFile.path),
                "info": .object([
                    "mimetype": .string("text/plain"),
                ]),
            ]),
            ts: 1_761_400_000_000,
            seq: 1,
            status: .sent,
            mediaPath: sourceFile.path,
            thread: ThreadSummary(replies: 2, lastTS: 1_761_400_000_000, lastSenders: ["Alice Example"])
        )
        let items = Timeline.build(
            events: [attachmentEvent],
            me: "@me:courier.local",
            now: Date(timeIntervalSince1970: 1_761_400_100)
        )
        let fullFeatures = ChatFeatures(
            reply: true,
            thread: true,
            edit: true,
            unsend: true,
            source: .stored,
            canDelete: true,
            voiceFeatures: FileKindFeatures(supported: true),
            gifFeatures: FileKindFeatures(supported: true),
            stickerFeatures: FileKindFeatures(supported: true)
        )
        conversation.setSnapshotStateForTesting(roomID: "!r2", items: items, row: bobRow, features: fullFeatures)
        conversation.selectedMessageID = "$att1"

        XCTAssertTrue(dispatcher.perform("Chat: Send File"))
        XCTAssertEqual(dispatcher.attachFilesInvocationCount, 1)

        XCTAssertTrue(dispatcher.perform("Download Attachments"))
        let downloadedFile = downloadsDir.appendingPathComponent("report.txt")
        XCTAssertTrue(
            FileManager.default.fileExists(atPath: downloadedFile.path),
            "Expected 'Download Attachments' shortcut handler to save report.txt to downloads directory"
        )

        // Verify every single HotkeyDefinition in allDefinitions can be performed through HotkeyDispatcher when its state is ready.
        for definition in HotkeyRegistry.allDefinitions {
            inbox.setSnapshotRowsForTesting([aliceRow, bobRow])
            inbox.select("!r1")
            inbox.select("!r2")
            conversation.setSnapshotStateForTesting(roomID: "!r2", items: items, row: bobRow, features: fullFeatures)
            conversation.selectedMessageID = "$att1"
            conversation.composer.text = "Draft for \(definition.id)"
            XCTAssertTrue(
                dispatcher.canPerform(definition.id),
                "HotkeyDefinition '\(definition.id)' must be enabled in HotkeyDispatcher when state is ready"
            )
            XCTAssertTrue(
                dispatcher.perform(definition.id),
                "HotkeyDefinition '\(definition.id)' must execute a real handler in HotkeyDispatcher"
            )
        }

        // Verify ComposerModel.handleReturn consults HotkeyRegistry for "Send Message".
        registry.setEnabled(false, for: "Send Message")
        conversation.setSnapshotStateForTesting(roomID: "!r2", items: items, row: bobRow, features: fullFeatures)
        conversation.composer.text = "Keep draft when Send Message is disabled"
        _ = conversation.composer.handleReturn(modifiers: [])
        XCTAssertEqual(
            conversation.composer.text,
            "Keep draft when Send Message is disabled",
            "Disabling 'Send Message' in HotkeyRegistry must prevent Return from submitting the composer draft"
        )
        registry.setEnabled(true, for: "Send Message")

        // Verify GlobalHotkeyMonitor starts monitoring when a global shortcut is enabled and dispatches through HotkeyDispatcher.
        final class FakeGlobalEventMonitor: GlobalKeyEventMonitoring {
            var isStarted = false
            var handler: (@MainActor (KeyChord) -> Void)?
            func start(handler: @escaping @MainActor (KeyChord) -> Void) {
                isStarted = true
                self.handler = handler
            }
            func stop() {
                isStarted = false
                handler = nil
            }
        }
        let fakeGlobalMonitor = FakeGlobalEventMonitor()
        let globalMonitor = GlobalHotkeyMonitor(
            registry: registry,
            dispatcher: dispatcher,
            eventMonitor: fakeGlobalMonitor
        )
        XCTAssertFalse(fakeGlobalMonitor.isStarted)
        let focusChord = KeyChord(key: "space", command: true, shift: true, option: true)
        if case let .failure(error) = registry.record(focusChord, for: "Focus App") {
            XCTFail("Unexpected error recording Focus App chord: \(error)")
        }
        registry.setGlobal(true, for: "Focus App")
        XCTAssertTrue(fakeGlobalMonitor.isStarted)
        let focusBefore = coordinator.focusCount
        XCTAssertTrue(globalMonitor.handleKeyChord(focusChord))
        XCTAssertEqual(coordinator.focusCount, focusBefore + 1)
    }

    func testEveryHotkeyShortcutIsNoOpWhileLockedAndRespectsEntitlements() async {
        final class MutableEntitlements: EntitlementProvider, @unchecked Sendable {
            var allowed: Set<Feature> = [.incognito, .reminders, .sendLater]
            func isEntitled(_ feature: Feature) -> Bool {
                allowed.contains(feature)
            }
        }
        let entitlements = MutableEntitlements()
        let supervisor = EngineSupervisor(
            enginePath: "/Applications/Courier.app/Contents/Helpers/courier-engine",
            dataDir: URL(fileURLWithPath: "/tmp/courier-test-hotkeys-locked"),
            environment: [:],
            launcher: FakeLauncher { _, _ in }
        )
        let appModel = AppModel(supervisor: supervisor)
        let inboxPrefs = InboxPreferences(defaults: defaults)
        let composerPrefs = ComposerPreferences(defaults: defaults)
        let inbox = InboxModel(appModel: appModel, preferences: inboxPrefs, entitlement: entitlements)
        let spaces = SpacesModel(appModel: appModel, inbox: inbox)
        let search = SearchModel(appModel: appModel, recents: RecentSearches(defaults: defaults), open: { _ in })
        let conversation = ConversationModel(appModel: appModel, preferences: composerPrefs)
        conversation.isEntitled = { [weak inbox] feature in inbox?.isEntitled(feature) ?? false }
        for composer in [conversation.composer, conversation.thread.composer] {
            composer.entitlement = entitlements
        }
        final class NoopPasteboard: TextPasteboard {
            func setString(_ text: String) {}
        }
        let messageActions = MessageActionsModel(
            conversation: conversation,
            appModel: appModel,
            preferences: composerPrefs,
            pasteboard: NoopPasteboard()
        )
        let lifecycle = SystemLifecycleModel(
            defaults: defaults,
            loginItem: FakeLoginItemService(currentStatus: .notRegistered),
            biometrics: FakeBiometricAuthService(available: true, result: .success(true))
        )

        var hideAppCount = 0
        let coordinator = AppMenuCoordinator(
            inbox: inbox,
            lifecycle: lifecycle,
            hideApp: { hideAppCount += 1 }
        )
        let registry = HotkeyRegistry(defaults: defaults, isAppLocked: { lifecycle.isLocked })
        let dispatcher = HotkeyDispatcher(
            inbox: inbox,
            spaces: spaces,
            conversation: conversation,
            messageActions: messageActions,
            search: search,
            lifecycle: lifecycle,
            menuCoordinator: coordinator,
            hotkeys: registry
        )
        appModel.setAccountsForTesting([
            Account(network: "signal", displayName: "Signal", flows: ["qr"], state: .connected),
        ])
        inbox.setSnapshotRowsForTesting([
            InboxRow(
                roomID: "!r1",
                network: "signal",
                name: "Alice",
                avatarPath: "",
                isDirect: true,
                lastTS: 100,
                preview: "Hi",
                previewKind: .text,
                previewMine: false,
                unread: 1,
                muted: false
            ),
        ])
        inbox.select("!r1")
        conversation.setSnapshotStateForTesting(roomID: "!r1", items: [])
        conversation.composer.text = "Locked draft"
        lifecycle.lockApp()
        XCTAssertTrue(lifecycle.isLocked)

        for definition in HotkeyRegistry.allDefinitions {
            XCTAssertFalse(
                dispatcher.canPerform(definition.id),
                "Shortcut '\(definition.id)' must be disabled while app is locked"
            )
            XCTAssertFalse(
                dispatcher.perform(definition.id),
                "Shortcut '\(definition.id)' must be a no-op while app is locked"
            )
        }
        for binding in HotkeyDispatcher.windowShortcutBindings {
            XCTAssertFalse(
                dispatcher.canPerform(binding.hotkeyID),
                "Window shortcut '\(binding.id)' must be disabled while app is locked"
            )
            XCTAssertFalse(
                dispatcher.perform(binding),
                "Window shortcut '\(binding.id)' must be a no-op while app is locked"
            )
        }
        XCTAssertFalse(dispatcher.performSwitchSpace(number: 1))
        XCTAssertFalse(dispatcher.performSwitchChat(number: 1))
        _ = conversation.composer.handleReturn(modifiers: [])
        _ = conversation.composer.handleReturn(modifiers: [.shift])

        XCTAssertEqual(coordinator.focusCount, 0)
        XCTAssertEqual(hideAppCount, 0)
        XCTAssertEqual(coordinator.quitRequestedCount, 0)
        XCTAssertFalse(conversation.isShowingChatInfo)
        XCTAssertFalse(conversation.incognitoIsOn)
        XCTAssertEqual(dispatcher.attachFilesInvocationCount, 0)
        XCTAssertEqual(dispatcher.remindLaterInvocationCount, 0)
        XCTAssertEqual(conversation.composer.text, "Locked draft")

        // Unlock and verify entitlement gates (.incognito and .reminders) are enforced by HotkeyDispatcher.
        _ = await lifecycle.unlockWithTouchID()
        XCTAssertFalse(lifecycle.isLocked)

        entitlements.allowed.remove(.incognito)
        entitlements.allowed.remove(.reminders)
        entitlements.allowed.remove(.sendLater)
        XCTAssertFalse(dispatcher.canPerform("Toggle Incognito Mode"))
        XCTAssertFalse(dispatcher.perform("Toggle Incognito Mode"))
        XCTAssertFalse(conversation.incognitoIsOn)

        XCTAssertFalse(dispatcher.canPerform("Remind Later"))
        XCTAssertFalse(dispatcher.perform("Remind Later"))
        XCTAssertEqual(dispatcher.remindLaterInvocationCount, 0)

        XCTAssertFalse(dispatcher.canPerform("Message: Send Later"))
        XCTAssertFalse(dispatcher.perform("Message: Send Later"))
        XCTAssertNil(messageActions.request)

        entitlements.allowed.insert(.incognito)
        entitlements.allowed.insert(.reminders)
        entitlements.allowed.insert(.sendLater)
        XCTAssertTrue(dispatcher.canPerform("Toggle Incognito Mode"))
        XCTAssertTrue(dispatcher.perform("Toggle Incognito Mode"))
        XCTAssertTrue(conversation.incognitoIsOn)

        XCTAssertTrue(dispatcher.canPerform("Remind Later"))
        XCTAssertTrue(dispatcher.perform("Remind Later"))
        XCTAssertEqual(dispatcher.remindLaterInvocationCount, 1)

        XCTAssertTrue(dispatcher.canPerform("Message: Send Later"))
        XCTAssertTrue(dispatcher.perform("Message: Send Later"))
        XCTAssertEqual(messageActions.request, .sendLater)
    }

    func testLockingAppDismissesAllOpenSheetsPopoversAndAlertsAndBlocksActions() async throws {
        let suiteName = "courier.test.hotkeys.lockdismiss.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }

        final class RecordingSender: MessageSending, @unchecked Sendable {
            var scheduledCount = 0
            func sendText(roomID _: String, text _: String, replyTo _: String?) async throws {}
            func sendFile(roomID _: String, url _: URL, size _: Int64, replyTo _: String?) async throws {}
            func send(
                roomID _: String,
                rich _: RichText,
                replyTo _: String?,
                threadRoot _: String?,
                holdMillis _: Int
            ) async throws -> String { "$sent" }
            func sendFile(
                roomID _: String,
                url _: URL,
                size _: Int64,
                replyTo _: String?,
                threadRoot _: String?,
                holdMillis _: Int
            ) async throws -> String { "$file" }
            func edit(eventID _: String, rich _: RichText) async throws {}
            func schedule(
                roomID _: String,
                rich _: RichText,
                replyTo _: String?,
                threadRoot _: String?,
                due _: Date,
                condition _: SendLaterCondition
            ) async throws {
                scheduledCount += 1
            }
            func undo(eventID _: String) async throws -> Draft {
                Draft(text: "", entities: [], replyTo: nil, threadRoot: nil)
            }
            func sendHeld(roomID _: String?) async throws {}
            func members(roomID _: String, query _: String) async throws -> [Member] { [] }
            func status(of _: String, in _: String, thread _: String?) async throws -> StatusLine? { nil }
            func setTyping(roomID _: String, typing _: Bool) async throws {}
            func setUnreadFrom(eventID _: String) async throws {}
            func directChat(roomID _: String, userID _: String) async throws -> String { "!dm" }
        }

        final class FakeLoginCaller: LoginCalling, @unchecked Sendable {
            var startCount = 0
            func start(network _: String, flow _: String, another _: Bool, accountID _: String?) async throws -> LoginStep {
                startCount += 1
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

        final class NoopPasteboard: TextPasteboard {
            func setString(_ text: String) {}
        }

        let supervisor = EngineSupervisor(
            enginePath: "/Applications/Courier.app/Contents/Helpers/courier-engine",
            dataDir: URL(fileURLWithPath: "/tmp/courier-test-hotkeys-dismiss"),
            environment: [:],
            launcher: FakeLauncher { _, _ in }
        )
        let appModel = AppModel(supervisor: supervisor)
        let inboxPrefs = InboxPreferences(defaults: defaults)
        let composerPrefs = ComposerPreferences(defaults: defaults)
        let quickReplies = QuickReplies(defaults: defaults)
        let inbox = InboxModel(appModel: appModel, preferences: inboxPrefs)
        let spaces = SpacesModel(appModel: appModel, inbox: inbox)
        let conversation = ConversationModel(
            appModel: appModel,
            unreadCount: { _ in 0 },
            chat: { _ in nil }
        )
        let sender = RecordingSender()
        conversation.composer.sender = sender
        conversation.composer.entitlement = AlwaysEntitled()
        conversation.composer.quickReplies = quickReplies
        conversation.preferences = composerPrefs
        let scheduled = ScheduledModel(appModel: appModel)
        let messageActions = MessageActionsModel(
            conversation: conversation,
            appModel: appModel,
            preferences: composerPrefs,
            pasteboard: NoopPasteboard()
        )
        messageActions.quickReplies = quickReplies
        let search = SearchModel(
            appModel: appModel,
            recents: RecentSearches(defaults: defaults),
            open: { _ in }
        )
        let loginCaller = FakeLoginCaller()
        let login = LoginFlowModel(
            caller: loginCaller,
            accounts: { appModel.accounts },
            reloadAccounts: {},
            credentials: MemoryCredentials(),
            builtInCredentials: { nil },
            restartEngine: {}
        )
        let lifecycle = SystemLifecycleModel(
            defaults: defaults,
            loginItem: FakeLoginItemService(currentStatus: .notRegistered),
            biometrics: FakeBiometricAuthService(available: true, result: .success(true))
        )
        let coordinator = AppMenuCoordinator(inbox: inbox, lifecycle: lifecycle)
        let registry = HotkeyRegistry(defaults: defaults, isAppLocked: { lifecycle.isLocked })
        let detachedWindows = DetachedWindowRegistry(
            appModel: appModel,
            mainInbox: inbox,
            lifecycle: lifecycle,
            inboxPreferences: inboxPrefs,
            composerPreferences: composerPrefs,
            quickReplies: quickReplies
        )
        _ = HotkeyDispatcher(
            inbox: inbox,
            spaces: spaces,
            conversation: conversation,
            messageActions: messageActions,
            search: search,
            lifecycle: lifecycle,
            menuCoordinator: coordinator,
            hotkeys: registry
        )

        appModel.setAccountsForTesting([
            Account(network: "gmessages", displayName: "Google Messages", flows: ["google"], state: .connected),
        ])
        let items = Timeline.build(
            events: [
                Event(
                    eventID: "$m1",
                    roomID: "!r1",
                    sender: "@me:courier.local",
                    senderName: "Me",
                    mine: true,
                    type: "m.room.message",
                    content: .object([
                        "msgtype": .string("m.text"),
                        "body": .string("Hello https://example.com"),
                    ]),
                    ts: 1_761_400_000_000,
                    seq: 1,
                    status: .sent
                ),
                Event(
                    eventID: "$vo1",
                    roomID: "!r1",
                    sender: "@alice:courier.local",
                    senderName: "Alice",
                    mine: false,
                    type: "m.room.message",
                    content: .object([
                        "msgtype": .string("m.image"),
                        "body": .string("photo.jpg"),
                    ]),
                    ts: 1_761_400_001_000,
                    seq: 2,
                    status: .sent,
                    mediaPath: "/tmp/photo.jpg",
                    viewOnce: true
                ),
            ],
            me: "@me:courier.local",
            now: Date(timeIntervalSince1970: 1_761_400_100)
        )
        let fullFeatures = ChatFeatures(
            reply: true,
            thread: true,
            edit: true,
            unsend: true,
            formatting: [.link],
            source: .stored,
            canDelete: true
        )
        conversation.setSnapshotStateForTesting(roomID: "!r1", items: items, features: fullFeatures)
        conversation.composer.open("!r1")
        conversation.composer.features = fullFeatures
        conversation.composer.text = "Draft to schedule"

        // 1. SendLaterPicker sheet
        messageActions.requestSendLater()
        XCTAssertEqual(messageActions.request, MessageActionRequest.sendLater)
        lifecycle.lockApp()
        XCTAssertNil(messageActions.request, "SendLaterPicker must be dismissed when app locks")
        try await conversation.composer.schedule(at: Date().addingTimeInterval(3600), condition: .always)
        XCTAssertEqual(sender.scheduledCount, 0, "SendLaterPicker schedule must be a no-op while locked")

        // 2. ForwardPicker sheet
        _ = await lifecycle.unlockWithTouchID()
        await messageActions.perform(.forward, on: "$m1", from: .chat)
        XCTAssertEqual(messageActions.request, MessageActionRequest.forward(messageID: "$m1"))
        lifecycle.lockApp()
        XCTAssertNil(messageActions.request, "ForwardPicker must be dismissed when app locks")

        // 3. ReactionPicker sheet
        _ = await lifecycle.unlockWithTouchID()
        await messageActions.perform(.react, on: "$m1", from: .chat)
        XCTAssertEqual(messageActions.request, MessageActionRequest.reactionPicker(messageID: "$m1"))
        lifecycle.lockApp()
        XCTAssertNil(messageActions.request, "ReactionPicker must be dismissed when app locks")

        // 4. QuickReplyTitleSheet
        _ = await lifecycle.unlockWithTouchID()
        conversation.composer.text = "Draft for quick reply"
        messageActions.requestQuickReplyFromDraft()
        XCTAssertEqual(messageActions.request, MessageActionRequest.quickReplyTitle)
        lifecycle.lockApp()
        XCTAssertNil(messageActions.request, "QuickReplyTitleSheet must be dismissed when app locks")
        XCTAssertFalse(messageActions.createQuickReply(title: "locked"), "QuickReplyTitleSheet cannot save while locked")
        XCTAssertTrue(quickReplies.all.isEmpty)

        // 5. MessageActionRequest.confirm alert
        _ = await lifecycle.unlockWithTouchID()
        await messageActions.perform(.deleteForMe, on: "$m1", from: .chat)
        XCTAssertNotNil(messageActions.request)
        lifecycle.lockApp()
        XCTAssertNil(messageActions.request, "Message confirm alert must be dismissed when app locks")

        // 6. All remaining sheets, popovers, alerts, and detached window presentations
        _ = await lifecycle.unlockWithTouchID()
        let c1 = ContactCandidate(userID: "@u1:local", name: "Bob", network: "gmessages", accountID: "a1")
        let c2 = ContactCandidate(userID: "@u2:local", name: "Carol", network: "gmessages", accountID: "a1")
        inbox.startNewChatDraft = StartNewChatDraft(
            accounts: appModel.accounts,
            candidates: [c1, c2],
            selectedRecipients: [c1, c2],
            mode: .blast,
            blastText: "Blast while locked",
            isConfirmingBlast: true
        )
        let row1 = InboxRow(
            roomID: "!r1",
            network: "gmessages",
            name: "Alice",
            avatarPath: "",
            isDirect: true,
            lastTS: 100,
            preview: "Hi",
            previewKind: .text,
            previewMine: false,
            unread: 0,
            muted: false
        )
        let row2 = InboxRow(
            roomID: "!r2",
            network: "gmessages",
            name: "Bob",
            avatarPath: "",
            isDirect: true,
            lastTS: 90,
            preview: "Yo",
            previewKind: .text,
            previewMine: false,
            unread: 0,
            muted: false
        )
        inbox.mergedChatEditorDraft = MergedChatEditorDraft(initialRows: [row1, row2])
        inbox.customReminder = ReminderRequest(ids: ["!r1"])
        inbox.isRemindPopoverPresented = true
        inbox.isAccountPopoverPresented = true
        inbox.beginSelecting()
        login.begin(network: "gmessages")
        XCTAssertEqual(login.screen, .googleWarning(network: "gmessages", flow: "google"))

        let viewOnceMsg = try XCTUnwrap(conversation.message("$vo1", from: .chat))
        conversation.openViewOnce(viewOnceMsg)
        XCTAssertNotNil(conversation.activeViewOnceMessage)
        let roomInfo = RoomInfoResult(
            roomID: "!r1",
            name: "Team",
            remoteName: "Team",
            network: "gmessages",
            isDirect: false,
            features: .noFeatures
        )
        conversation.activeEditGroupDraft = EditGroupDraft(info: roomInfo)
        conversation.activeAddParticipantsRoom = roomInfo
        conversation.activeReportSpamDraft = ReportSpamDraft(roomID: "!r1", canLeave: true, canDelete: true)
        conversation.pendingRoomConfirmation = .leaveGroup(roomID: "!r1", groupName: "Team", network: "gmessages")
        conversation.isCreatingPoll = true
        conversation.carousel.open(
            items: [
                CarouselItem(
                    eventID: "$m1",
                    roomID: "!r1",
                    kind: .image,
                    mediaPath: "/tmp/img.png",
                    fileName: "img.png",
                    senderName: "Me"
                ),
            ],
            selectedEventID: "$m1"
        )
        XCTAssertTrue(conversation.carousel.isPresented)
        conversation.composer.isGIFPickerPresented = true
        conversation.composer.isStickerPickerPresented = true
        _ = conversation.composer.formattingKey(.link, in: NSRange(location: 0, length: 5))
        XCTAssertNotNil(conversation.composer.linkRequest)

        let scheduledMsg = ScheduledMessage(
            outboxID: 1,
            roomID: "!r1",
            text: "Later",
            dueAt: 1_761_500_000_000,
            condition: .always,
            state: .waiting,
            setAt: 1_761_400_000_000
        )
        scheduled.editingMessage = scheduledMsg
        scheduled.reschedulingMessage = scheduledMsg
        quickReplies.editing = QuickReplyEdit(reply: nil)
        registry.isShortcutsSheetPresented = true
        registry.beginRecording(for: "Search")
        search.toggle(visible: true)
        XCTAssertNotEqual(search.phase, .closed)

        detachedWindows.open(.chat(roomID: "!r1"))
        let detachedSession = try XCTUnwrap(detachedWindows.session(for: DetachedWindowTarget.chat(roomID: "!r1")))
        detachedSession.conversation.setSnapshotStateForTesting(roomID: "!r1", items: items, features: fullFeatures)
        detachedSession.conversation.composer.open("!r1")
        detachedSession.conversation.composer.sender = sender
        detachedSession.conversation.composer.text = "Detached draft"
        detachedSession.messageActions.requestSendLater()
        detachedSession.conversation.openViewOnce(viewOnceMsg)
        detachedSession.scheduled.editingMessage = scheduledMsg
        XCTAssertEqual(detachedSession.messageActions.request, MessageActionRequest.sendLater)
        XCTAssertNotNil(detachedSession.conversation.activeViewOnceMessage)
        XCTAssertNotNil(detachedSession.scheduled.editingMessage)

        lifecycle.lockApp()

        XCTAssertNil(inbox.startNewChatDraft, "StartNewChatView (including blast) must be dismissed on lock")
        XCTAssertNil(inbox.mergedChatEditorDraft, "MergedChatEditorSheet must be dismissed on lock")
        XCTAssertNil(inbox.customReminder, "CustomReminderSheet must be dismissed on lock")
        XCTAssertFalse(inbox.isRemindPopoverPresented, "Remind Me popover must be dismissed on lock")
        XCTAssertFalse(inbox.isAccountPopoverPresented, "Account filter popover must be dismissed on lock")
        XCTAssertFalse(inbox.isSelecting, "Inbox selection mode must end on lock")
        XCTAssertEqual(login.screen, .closed, "AddNetworkView must be closed on lock")
        XCTAssertNil(conversation.activeViewOnceMessage, "ViewOnceSheet must be dismissed on lock")
        XCTAssertNil(conversation.activeEditGroupDraft, "EditGroupSheet must be dismissed on lock")
        XCTAssertNil(conversation.activeAddParticipantsRoom, "AddParticipantsSheet must be dismissed on lock")
        XCTAssertNil(conversation.activeReportSpamDraft, "ReportSpamSheet must be dismissed on lock")
        XCTAssertNil(conversation.pendingRoomConfirmation, "Room confirmation alert must be dismissed on lock")
        XCTAssertFalse(conversation.isCreatingPoll, "PollCreatorWindow must be dismissed on lock")
        XCTAssertFalse(conversation.carousel.isPresented, "AttachmentCarouselOverlay must be dismissed on lock")
        XCTAssertFalse(conversation.composer.isGIFPickerPresented, "GIFPickerPopover must be dismissed on lock")
        XCTAssertFalse(conversation.composer.isStickerPickerPresented, "StickerPickerPopover must be dismissed on lock")
        XCTAssertNil(conversation.composer.linkRequest, "LinkDialog must be dismissed on lock")
        XCTAssertNil(scheduled.editingMessage, "ScheduledEditSheet must be dismissed on lock")
        XCTAssertNil(scheduled.reschedulingMessage, "ScheduledRescheduleSheet must be dismissed on lock")
        XCTAssertNil(quickReplies.editing, "QuickReplyEditor must be dismissed on lock")
        XCTAssertFalse(registry.isShortcutsSheetPresented, "KeyboardShortcutsSheet must be dismissed on lock")
        XCTAssertNil(registry.recordingHotkeyID, "Hotkey recorder must cancel on lock")
        XCTAssertEqual(search.phase, .closed, "SearchOverlay must close on lock")

        XCTAssertNil(detachedSession.messageActions.request, "Detached window sheet must be dismissed on lock")
        XCTAssertNil(detachedSession.conversation.activeViewOnceMessage, "Detached ViewOnceSheet must be dismissed on lock")
        XCTAssertNil(detachedSession.scheduled.editingMessage, "Detached ScheduledEditSheet must be dismissed on lock")

        // Attempting sheet actions while locked must not invoke their side effects.
        login.continueAfterWarning()
        XCTAssertEqual(loginCaller.startCount, 0, "AddNetworkView continueAfterWarning must not start login while locked")
        await conversation.markPlayed("$vo1", roomID: "!r1")
        XCTAssertEqual(conversation.message("$vo1", from: .chat)?.played, false, "ViewOnceSheet markPlayed must be a no-op while locked")
        try? quickReplies.add(title: "locked", text: "locked")
        XCTAssertTrue(quickReplies.all.isEmpty, "QuickReplyEditor cannot add replies while locked")
    }

    func testLabelEditorCannotSaveWhileLocked() async throws {
        let suiteName = "courier.test.hotkeys.labels.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let supervisor = EngineSupervisor(
            enginePath: "/Applications/Courier.app/Contents/Helpers/courier-engine",
            dataDir: URL(fileURLWithPath: "/tmp/courier-test-hotkeys-labels"),
            environment: [:],
            launcher: FakeLauncher { _, _ in }
        )
        let appModel = AppModel(supervisor: supervisor)
        let lifecycle = SystemLifecycleModel(
            defaults: defaults,
            loginItem: FakeLoginItemService(currentStatus: .notRegistered),
            biometrics: FakeBiometricAuthService(available: true, result: .success(true))
        )
        let labels = LabelsModel(appModel: appModel)
        lifecycle.lockApp()
        XCTAssertTrue(lifecycle.isLocked)

        do {
            _ = try await labels.create(title: "Work", color: 1, icon: "tag")
            XCTFail("LabelsModel.create must throw while app is locked")
        } catch let error as EngineError {
            XCTAssertEqual(error, .rpc(.badValue, message: "Courier is locked", reason: "locked"))
        }

        do {
            try await labels.update(1, title: "Personal", color: 2, icon: "star")
            XCTFail("LabelsModel.update must throw while app is locked")
        } catch let error as EngineError {
            XCTAssertEqual(error, .rpc(.badValue, message: "Courier is locked", reason: "locked"))
        }

        do {
            try await labels.delete(1)
            XCTFail("LabelsModel.delete must throw while app is locked")
        } catch let error as EngineError {
            XCTAssertEqual(error, .rpc(.badValue, message: "Courier is locked", reason: "locked"))
        }
    }

    func testMessageMenuShortcutsRouteThroughHotkeyDispatcherAndAreNoOpWhileLocked() async throws {
        let suiteName = "courier.test.hotkeys.messagemenu.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }

        final class SpyPasteboard: TextPasteboard {
            var copied: String?
            func setString(_ text: String) { copied = text }
        }
        final class MutableEntitlements: EntitlementProvider, @unchecked Sendable {
            var allowed: Set<Feature> = Set(Feature.allCases)
            func isEntitled(_ feature: Feature) -> Bool { allowed.contains(feature) }
        }

        let pasteboard = SpyPasteboard()
        let entitlements = MutableEntitlements()
        var openedURLs: [URL] = []

        let supervisor = EngineSupervisor(
            enginePath: "/Applications/Courier.app/Contents/Helpers/courier-engine",
            dataDir: URL(fileURLWithPath: "/tmp/courier-test-hotkeys-msgmenu"),
            environment: [:],
            launcher: FakeLauncher { _, _ in }
        )
        let appModel = AppModel(supervisor: supervisor)
        let inbox = InboxModel(
            appModel: appModel,
            preferences: InboxPreferences(defaults: defaults),
            entitlement: entitlements
        )
        let spaces = SpacesModel(appModel: appModel, inbox: inbox)
        let conversation = ConversationModel(
            appModel: appModel,
            unreadCount: { _ in 0 },
            chat: { _ in nil }
        )
        conversation.composer.entitlement = entitlements
        let messageActions = MessageActionsModel(
            conversation: conversation,
            appModel: appModel,
            preferences: ComposerPreferences(defaults: defaults),
            pasteboard: pasteboard
        )
        messageActions.openURL = { openedURLs.append($0) }
        let search = SearchModel(
            appModel: appModel,
            recents: RecentSearches(defaults: defaults),
            open: { _ in }
        )
        let lifecycle = SystemLifecycleModel(
            defaults: defaults,
            loginItem: FakeLoginItemService(currentStatus: .notRegistered),
            biometrics: FakeBiometricAuthService(available: true, result: .success(true))
        )
        let coordinator = AppMenuCoordinator(inbox: inbox, lifecycle: lifecycle)
        let registry = HotkeyRegistry(defaults: defaults, isAppLocked: { lifecycle.isLocked })
        let dispatcher = HotkeyDispatcher(
            inbox: inbox,
            spaces: spaces,
            conversation: conversation,
            messageActions: messageActions,
            search: search,
            lifecycle: lifecycle,
            menuCoordinator: coordinator,
            hotkeys: registry
        )

        XCTAssertEqual(MenuKey.commandT.hotkeyID, "Message: Edit")
        XCTAssertEqual(MenuKey.commandR.hotkeyID, "Message: Quote & Reply")
        XCTAssertEqual(MenuKey.commandDown.hotkeyID, "Show Replies")
        XCTAssertNil(MenuKey.commandC.hotkeyID)
        XCTAssertEqual(MenuKey.commandShiftH.hotkeyID, "Message: Open First Link")
        XCTAssertEqual(MenuKey.commandShiftF.hotkeyID, "Message: Forward")

        let items = Timeline.build(
            events: [
                Event(
                    eventID: "$m1",
                    roomID: "!r1",
                    sender: "@me:courier.local",
                    senderName: "Me",
                    mine: true,
                    type: "m.room.message",
                    content: .object([
                        "msgtype": .string("m.text"),
                        "body": .string("Visit https://example.com"),
                        "format": .string("org.matrix.custom.html"),
                        "formatted_body": .string("<a href=\"https://example.com\">Visit https://example.com</a>"),
                    ]),
                    ts: 1_761_400_000_000,
                    seq: 1,
                    status: .sent,
                    thread: ThreadSummary(replies: 2, lastTS: 1_761_400_005_000, lastSenders: ["Alice"])
                ),
            ],
            me: "@me:courier.local",
            now: Date(timeIntervalSince1970: 1_761_400_100)
        )
        let fullFeatures = ChatFeatures(
            reply: true,
            thread: true,
            edit: true,
            unsend: true,
            source: .stored,
            canDelete: true
        )
        conversation.setSnapshotStateForTesting(roomID: "!r1", items: items, features: fullFeatures)
        conversation.selectedMessageID = "$m1"

        lifecycle.lockApp()
        XCTAssertTrue(lifecycle.isLocked)

        await messageActions.perform(.edit, on: "$m1", from: .chat)
        XCTAssertEqual(conversation.composer.mode, .new, "MessageMenu .commandT (Edit) must be a no-op while locked")
        await messageActions.perform(.reply, on: "$m1", from: .chat)
        XCTAssertNil(conversation.composer.replyTarget, "MessageMenu .commandR (Reply) must be a no-op while locked")
        conversation.openThread("$m1")
        XCTAssertNil(conversation.thread.rootID, "MessageMenu .commandDown (Show Replies) must be a no-op while locked")
        await messageActions.perform(.copy, on: "$m1", from: .chat)
        XCTAssertNil(pasteboard.copied, "MessageMenu .commandC (Copy) must be a no-op while locked")
        await messageActions.perform(.openFirstLink, on: "$m1", from: .chat)
        XCTAssertTrue(openedURLs.isEmpty, "MessageMenu .commandShiftH (Open Link) must be a no-op while locked")
        await messageActions.perform(.forward, on: "$m1", from: .chat)
        XCTAssertNil(messageActions.request, "MessageMenu .commandShiftF (Forward) must be a no-op while locked")

        // Also verify Message: Send Later (⌘⇧L) checks .sendLater entitlement when unlocked.
        _ = await lifecycle.unlockWithTouchID()
        conversation.composer.open("!r1")
        conversation.composer.text = "Scheduled text"
        entitlements.allowed.remove(.sendLater)
        XCTAssertFalse(dispatcher.canPerform("Message: Send Later"))
        XCTAssertFalse(dispatcher.perform("Message: Send Later"))
        XCTAssertNil(messageActions.request)
    }

    func testLaunchingWithLockOnEveryModelAndDetachedSessionReportsLockedAndRefusesActions() async throws {
        let suiteName = "courier.test.hotkeys.launchlocked.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }

        final class SpyPasteboard: TextPasteboard {
            var copied: String?
            func setString(_ text: String) { copied = text }
        }
        final class FakeLoginCaller: LoginCalling, @unchecked Sendable {
            var startCount = 0
            func start(network _: String, flow _: String, another _: Bool, accountID _: String?) async throws -> LoginStep {
                startCount += 1
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

        // Persist autoLockEnabled = true BEFORE launch so SystemLifecycleModel starts locked in init
        // without any subsequent lockNow() / didLockNotification call.
        defaults.set(true, forKey: SystemLifecycleModel.key("autoLockEnabled"))
        defaults.set(true, forKey: SystemLifecycleModel.key("requireTouchIDOnLaunch"))
        let lifecycle = SystemLifecycleModel(
            defaults: defaults,
            loginItem: FakeLoginItemService(currentStatus: .notRegistered),
            biometrics: FakeBiometricAuthService(available: true, result: .success(false))
        )
        XCTAssertTrue(lifecycle.isLocked, "SystemLifecycleModel must start locked when autoLockEnabled is stored on launch")

        let supervisor = EngineSupervisor(
            enginePath: "/Applications/Courier.app/Contents/Helpers/courier-engine",
            dataDir: URL(fileURLWithPath: "/tmp/courier-test-launchlocked"),
            environment: [:],
            launcher: FakeLauncher { _, _ in }
        )
        let appModel = AppModel(supervisor: supervisor)
        let inboxPrefs = InboxPreferences(defaults: defaults)
        let composerPrefs = ComposerPreferences(defaults: defaults)
        let quickReplies = QuickReplies(defaults: defaults)
        let inbox = InboxModel(appModel: appModel, preferences: inboxPrefs)
        let spaces = SpacesModel(appModel: appModel, inbox: inbox)
        let labels = LabelsModel(appModel: appModel, lifecycle: lifecycle)
        let conversation = ConversationModel(appModel: appModel, preferences: composerPrefs)
        let mainPasteboard = SpyPasteboard()
        let messageActions = MessageActionsModel(
            conversation: conversation,
            appModel: appModel,
            preferences: composerPrefs,
            pasteboard: mainPasteboard
        )
        let scheduled = ScheduledModel(appModel: appModel)
        let search = SearchModel(appModel: appModel, recents: RecentSearches(defaults: defaults), open: { _ in })
        let login = LoginFlowModel(
            caller: FakeLoginCaller(),
            accounts: { appModel.accounts },
            reloadAccounts: {},
            credentials: MemoryCredentials(),
            builtInCredentials: { nil },
            restartEngine: {}
        )
        let detachedPasteboard = SpyPasteboard()
        let detachedRegistry = DetachedWindowRegistry(
            appModel: appModel,
            mainInbox: inbox,
            lifecycle: lifecycle,
            inboxPreferences: inboxPrefs,
            composerPreferences: composerPrefs,
            quickReplies: quickReplies,
            makePasteboard: { detachedPasteboard }
        )

        let items = Timeline.build(
            events: [
                Event(
                    eventID: "$m1",
                    roomID: "!r1",
                    sender: "@alice:courier.local",
                    senderName: "Alice",
                    mine: false,
                    type: "m.room.message",
                    content: .object(["msgtype": .string("m.text"), "body": .string("Secret code 123456")]),
                    ts: 1_761_400_000_000,
                    seq: 1,
                    status: .sent
                ),
            ],
            me: "@me:courier.local",
            now: Date(timeIntervalSince1970: 1_761_400_100)
        )
        conversation.setSnapshotStateForTesting(roomID: "!r1", items: items)

        // Open detached windows while launch-locked (or verify sessions created from registry).
        let chatTarget = DetachedWindowTarget.chat(roomID: "!r1")
        let spaceTarget = DetachedWindowTarget.space(spaceID: "work")
        let threadTarget = DetachedWindowTarget.thread(roomID: "!r1", rootEventID: "$m1")
        let detachedChatSession = DetachedWindowSession(
            target: chatTarget,
            appModel: appModel,
            inboxPreferences: inboxPrefs,
            composerPreferences: composerPrefs,
            mainInbox: inbox,
            quickReplies: quickReplies,
            pasteboard: detachedPasteboard
        )
        detachedChatSession.conversation.setSnapshotStateForTesting(roomID: "!r1", items: items)
        let detachedSpaceSession = DetachedWindowSession(
            target: spaceTarget,
            appModel: appModel,
            inboxPreferences: inboxPrefs,
            composerPreferences: composerPrefs,
            mainInbox: inbox,
            quickReplies: quickReplies,
            pasteboard: detachedPasteboard
        )
        let detachedThreadSession = DetachedWindowSession(
            target: threadTarget,
            appModel: appModel,
            inboxPreferences: inboxPrefs,
            composerPreferences: composerPrefs,
            mainInbox: inbox,
            quickReplies: quickReplies,
            pasteboard: detachedPasteboard
        )

        // Every model and detached session must report isLocked == true at launch AND refuse actions while launch-locked.
        XCTAssertTrue(appModel.isLocked, "AppModel must report isLocked == true when launched with lock on")
        XCTAssertTrue(inbox.isLocked, "InboxModel must report isLocked == true when launched with lock on")
        XCTAssertTrue(spaces.isLocked, "SpacesModel must report isLocked == true when launched with lock on")
        XCTAssertTrue(conversation.isLocked, "ConversationModel must report isLocked == true when launched with lock on")
        XCTAssertTrue(conversation.composer.isLocked, "ComposerModel must report isLocked == true when launched with lock on")
        XCTAssertTrue(messageActions.isLocked, "MessageActionsModel must report isLocked == true when launched with lock on")
        XCTAssertTrue(scheduled.isLocked, "ScheduledModel must report isLocked == true when launched with lock on")
        XCTAssertTrue(search.isLocked, "SearchModel must report isLocked == true when launched with lock on")
        XCTAssertTrue(login.isLocked, "LoginFlowModel must report isLocked == true when launched with lock on")
        XCTAssertTrue(quickReplies.isLocked, "QuickReplies must report isLocked == true when launched with lock on")
        XCTAssertTrue(labels.isLocked, "LabelsModel must report isLocked == true when launched with lock on")
        XCTAssertTrue(detachedChatSession.isLocked, "Detached chat session must report isLocked == true when launched with lock on")
        XCTAssertTrue(detachedSpaceSession.isLocked, "Detached space session must report isLocked == true when launched with lock on")
        XCTAssertTrue(detachedThreadSession.isLocked, "Detached thread session must report isLocked == true when launched with lock on")
        XCTAssertTrue(detachedChatSession.conversation.isLocked, "Detached chat ConversationModel must report isLocked == true when launched with lock on")
        XCTAssertTrue(detachedSpaceSession.conversation.isLocked, "Detached space ConversationModel must report isLocked == true when launched with lock on")
        XCTAssertTrue(detachedThreadSession.conversation.isLocked, "Detached thread ConversationModel must report isLocked == true when launched with lock on")

        inbox.select("!r1")
        XCTAssertNil(appModel.selectedRoomID, "InboxModel.select must be refused when launched locked")
        spaces.select("work")
        XCTAssertEqual(inbox.query.space, "inbox", "SpacesModel.select must be refused when launched locked")
        search.show()
        XCTAssertEqual(search.phase, .closed, "SearchModel.show must be refused when launched locked")
        login.showPicker()
        XCTAssertEqual(login.screen, .closed, "LoginFlowModel.showPicker must be refused when launched locked")
        try? quickReplies.add(title: "locked", text: "locked")
        XCTAssertTrue(quickReplies.all.isEmpty, "QuickReplies.add must be refused when launched locked")
        conversation.setSnapshotStateForTesting(roomID: "!r1", items: items)
        await messageActions.perform(.copy, on: "$m1", from: .chat)
        XCTAssertNil(mainPasteboard.copied, "MessageActionsModel.perform(.copy) must be refused when launched locked")
        await detachedChatSession.messageActions.perform(.copy, on: "$m1", from: .chat)
        XCTAssertNil(detachedPasteboard.copied, "DetachedWindowSession.messageActions.perform(.copy) must be refused when launched locked")
        detachedSpaceSession.inbox?.select("!r1")
        XCTAssertNil(detachedSpaceSession.inbox?.selectedRoomID, "Detached space InboxModel.select must be refused when launched locked")
        let audioPlayer = AudioPlayerModel(appModel: appModel, conversation: conversation, preferences: composerPrefs, defaults: defaults)
        audioPlayer.cycleSpeed()
        XCTAssertEqual(audioPlayer.speed, .one, "AudioPlayerModel.cycleSpeed must be refused when launched locked")
        _ = detachedRegistry

        let exportURL = FileManager.default.temporaryDirectory.appendingPathComponent("locked-export-\(UUID().uuidString).txt")
        defer { try? FileManager.default.removeItem(at: exportURL) }
        do {
            _ = try await conversation.exportChat(roomID: "!r1", to: exportURL)
            XCTFail("ConversationModel.exportChat must throw while locked")
        } catch let error as EngineError {
            XCTAssertEqual(error, .rpc(.badValue, message: "Courier is locked", reason: "locked"))
        }
    }

    func testLocalSettingsWritesAndRemainingActionEntrypointsAreRefusedWhileLocked() async throws {
        let suiteName = "courier.test.hotkeys.localsettings.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let loginItem = FakeLoginItemService(currentStatus: .notRegistered)
        let lifecycle = SystemLifecycleModel(
            defaults: defaults,
            loginItem: loginItem,
            biometrics: FakeBiometricAuthService(available: true, result: .success(true))
        )
        let inboxPrefs = InboxPreferences(defaults: defaults)
        let composerPrefs = ComposerPreferences(defaults: defaults)
        let dockPrefs = DockAndTrayPreferences(defaults: defaults)

        // Lock the app and verify every UserDefaults-backed setting write is refused by the gate.
        lifecycle.lockNow()
        XCTAssertTrue(lifecycle.isLocked)

        lifecycle.lockTimeout = .fifteenMinutes
        XCTAssertEqual(lifecycle.lockTimeout, .fiveMinutes, "SystemLifecycleModel.lockTimeout write while locked must be refused")
        lifecycle.launchAtLogin = true
        XCTAssertFalse(lifecycle.launchAtLogin, "SystemLifecycleModel.launchAtLogin write while locked must be refused")
        lifecycle.startMinimized = true
        XCTAssertFalse(lifecycle.startMinimized, "SystemLifecycleModel.startMinimized write while locked must be refused")
        lifecycle.minimizeToTrayOnClose = false
        XCTAssertTrue(lifecycle.minimizeToTrayOnClose, "SystemLifecycleModel.minimizeToTrayOnClose write while locked must be refused")

        inboxPrefs.compactList = true
        XCTAssertFalse(inboxPrefs.compactList, "InboxPreferences.compactList write while locked must be refused")
        inboxPrefs.showSpaceBar = false
        XCTAssertTrue(inboxPrefs.showSpaceBar, "InboxPreferences.showSpaceBar write while locked must be refused")
        inboxPrefs.typingNotifications = true
        XCTAssertFalse(inboxPrefs.typingNotifications, "InboxPreferences.typingNotifications write while locked must be refused")
        inboxPrefs.notifications.delaySeconds = 30
        XCTAssertEqual(inboxPrefs.notifications.delaySeconds, 0, "InboxPreferences.notifications write while locked must be refused")
        inboxPrefs.notifications.autoCopyOTP = true
        XCTAssertFalse(inboxPrefs.notifications.autoCopyOTP, "NotificationPreferences.autoCopyOTP write while locked must be refused")

        composerPrefs.undoSendMillis = 5000
        XCTAssertEqual(composerPrefs.undoSendMillis, 0, "ComposerPreferences.undoSendMillis write while locked must be refused")
        composerPrefs.showFormattingMenu = false
        XCTAssertTrue(composerPrefs.showFormattingMenu, "ComposerPreferences.showFormattingMenu write while locked must be refused")
        composerPrefs.copyWithTimestamps = true
        XCTAssertFalse(composerPrefs.copyWithTimestamps, "ComposerPreferences.copyWithTimestamps write while locked must be refused")
        composerPrefs.alwaysAskWhereToSaveFiles = true
        XCTAssertFalse(composerPrefs.alwaysAskWhereToSaveFiles, "ComposerPreferences.alwaysAskWhereToSaveFiles write while locked must be refused")

        dockPrefs.showMenuBarIcon = false
        XCTAssertTrue(dockPrefs.showMenuBarIcon, "DockAndTrayPreferences.showMenuBarIcon write while locked must be refused")
        dockPrefs.badgeMode = .none
        XCTAssertEqual(dockPrefs.badgeMode, .unreadChats, "DockAndTrayPreferences.badgeMode write while locked must be refused")

        // Verify remaining action entrypoints (CalendarBridge, ContactsBridge, MediaViewerModel, SearchModel, ConversationModel, ComposerModel) are refused while locked.
        final class SpyCalendarStore: CalendarStoreProtocol, @unchecked Sendable {
            var requestAccessCount = 0
            func authorizationStatus() -> CalendarAuthStatus { .notDetermined }
            func requestFullAccess() async -> Bool {
                requestAccessCount += 1
                return true
            }
            func events(forDay _: Date) async -> [CalendarEventItem] { [] }
            func createEvent(title _: String, startDate: Date, endDate: Date, notes _: String?) async throws -> CalendarEventItem {
                CalendarEventItem(id: "1", title: "T", startDate: startDate, endDate: endDate)
            }
        }
        let calStore = SpyCalendarStore()
        let calBridge = CalendarBridge(store: calStore)
        await calBridge.loadSelectedDay()
        XCTAssertEqual(calStore.requestAccessCount, 0, "CalendarBridge.loadSelectedDay must be refused while locked")

        final class SpyContactsStore: ContactsStoreProtocol, @unchecked Sendable {
            var requestAccessCount = 0
            func authorizationStatus() -> ContactsAuthStatus { .notDetermined }
            func requestAccess() async -> Bool {
                requestAccessCount += 1
                return true
            }
            func match(identifiers _: [String], fallbackName _: String) async -> MatchedContact? { nil }
            func saveNewContact(givenName: String, familyName: String, phone _: String?, email _: String?) async throws -> MatchedContact {
                MatchedContact(contactIdentifier: "1", fullName: "\(givenName) \(familyName)")
            }
        }
        let contactsStore = SpyContactsStore()
        let contactsBridge = ContactsBridge(store: contactsStore)
        await contactsBridge.loadMatch(identifiers: ["+15550100101"], fallbackName: "Alice")
        XCTAssertEqual(contactsStore.requestAccessCount, 0, "ContactsBridge.loadMatch must be refused while locked")

        let supervisor = EngineSupervisor(
            enginePath: "/Applications/Courier.app/Contents/Helpers/courier-engine",
            dataDir: URL(fileURLWithPath: "/tmp/courier-test-localsettings"),
            environment: [:],
            launcher: FakeLauncher { _, _ in }
        )
        let appModel = AppModel(supervisor: supervisor)
        let initialHit = MediaHit(
            eventID: "$initial-media",
            roomID: "!r1",
            sender: "@alice",
            senderName: "Alice",
            mine: false,
            ts: 1000,
            seq: 1
        )
        let mediaViewer = MediaViewerModel(appModel: appModel, initialItems: [initialHit])
        mediaViewer.toggleSelected("$initial-media")
        XCTAssertTrue(mediaViewer.selectedEventIDs.isEmpty, "MediaViewerModel.toggleSelected must be refused while locked")
        await mediaViewer.refresh()
        XCTAssertEqual(
            mediaViewer.items.map(\.eventID),
            ["$initial-media"],
            "MediaViewerModel.refresh must be refused by AppLockGate while locked"
        )
        await mediaViewer.loadNextPage()
        XCTAssertEqual(
            mediaViewer.items.map(\.eventID),
            ["$initial-media"],
            "MediaViewerModel.loadNextPage must be refused by AppLockGate while locked"
        )

        let inbox = InboxModel(appModel: appModel, preferences: inboxPrefs)
        _ = await lifecycle.unlock()
        inbox.startNewChatDraft = StartNewChatDraft(query: "initial")
        lifecycle.lockNow()
        inbox.updateStartNewChatQuery("mutated-while-locked")
        XCTAssertNotEqual(
            inbox.startNewChatDraft?.query,
            "mutated-while-locked",
            "InboxModel.updateStartNewChatQuery must be refused while locked"
        )
        inbox.updateStartNewChatDraft(StartNewChatDraft(query: "draft-while-locked"))
        XCTAssertNotEqual(
            inbox.startNewChatDraft?.query,
            "draft-while-locked",
            "InboxModel.updateStartNewChatDraft must be refused while locked"
        )

        let recents = RecentSearches(defaults: defaults)
        _ = await lifecycle.unlock()
        recents.addSearch("alice")
        XCTAssertEqual(recents.searches, ["alice"])
        lifecycle.lockNow()

        let search = SearchModel(appModel: appModel, recents: recents, open: { _ in })
        search.clearRecentSearches()
        XCTAssertEqual(recents.searches, ["alice"], "SearchModel.clearRecentSearches must be refused while locked")

        let conversation = ConversationModel(appModel: appModel, preferences: composerPrefs)
        conversation.toggleChatInfo()
        XCTAssertFalse(conversation.isShowingChatInfo, "ConversationModel.toggleChatInfo must be refused while locked")
        conversation.toggleCalendar()
        XCTAssertFalse(conversation.isShowingCalendar, "ConversationModel.toggleCalendar must be refused while locked")
        conversation.composer.insertAsDraft(RichText(text: "locked draft", entities: []))
        XCTAssertEqual(conversation.composer.text, "", "ComposerModel.insertAsDraft must be refused while locked")
    }
}
