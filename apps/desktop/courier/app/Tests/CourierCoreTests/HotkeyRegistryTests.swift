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
            var allowed: Set<Feature> = [.incognito, .reminders]
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
        lifecycle.lockApp()
        XCTAssertTrue(lifecycle.isLocked)

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
        XCTAssertFalse(dispatcher.canPerform("Toggle Incognito Mode"))
        XCTAssertFalse(dispatcher.perform("Toggle Incognito Mode"))
        XCTAssertFalse(conversation.incognitoIsOn)

        XCTAssertFalse(dispatcher.canPerform("Remind Later"))
        XCTAssertFalse(dispatcher.perform("Remind Later"))
        XCTAssertEqual(dispatcher.remindLaterInvocationCount, 0)

        entitlements.allowed.insert(.incognito)
        entitlements.allowed.insert(.reminders)
        XCTAssertTrue(dispatcher.canPerform("Toggle Incognito Mode"))
        XCTAssertTrue(dispatcher.perform("Toggle Incognito Mode"))
        XCTAssertTrue(conversation.incognitoIsOn)

        XCTAssertTrue(dispatcher.canPerform("Remind Later"))
        XCTAssertTrue(dispatcher.perform("Remind Later"))
        XCTAssertEqual(dispatcher.remindLaterInvocationCount, 1)
    }
}
