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
        let coordinator = AppMenuCoordinator(inbox: inbox, lifecycle: lifecycle)
        let registry = HotkeyRegistry(defaults: defaults)

        XCTAssertFalse(HotkeyRegistry.allDefinitions.isEmpty)
        for definition in HotkeyRegistry.allDefinitions {
            let cmd = CommandSet.hotkeyCommand(
                for: definition.id,
                hotkeys: registry,
                inbox: inbox,
                spaces: spaces,
                search: search,
                conversation: conversation,
                messageActions: messageActions,
                menuCoordinator: coordinator
            )
            XCTAssertNotNil(cmd, "HotkeyDefinition '\(definition.id)' must resolve to a wired CourierCommand handler")
            XCTAssertEqual(cmd?.id, definition.id)
        }

        // Verify wired command handlers execute their model actions.
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
                unread: 0,
                muted: false
            ),
            InboxRow(
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
            ),
        ])
        inbox.select("!r1")
        inbox.select("!r2")
        XCTAssertEqual(inbox.selectedRoomID, "!r2")

        CommandSet.hotkeyCommand(
            for: "History: Previous Chat",
            hotkeys: registry,
            inbox: inbox,
            spaces: spaces,
            search: search,
            conversation: conversation,
            messageActions: messageActions,
            menuCoordinator: coordinator
        )?.run()
        XCTAssertEqual(inbox.selectedRoomID, "!r1")

        CommandSet.hotkeyCommand(
            for: "History: Next Chat",
            hotkeys: registry,
            inbox: inbox,
            spaces: spaces,
            search: search,
            conversation: conversation,
            messageActions: messageActions,
            menuCoordinator: coordinator
        )?.run()
        XCTAssertEqual(inbox.selectedRoomID, "!r2")

        CommandSet.hotkeyCommand(
            for: "Cycle Chats (hold shift to reverse)",
            hotkeys: registry,
            inbox: inbox,
            spaces: spaces,
            search: search,
            conversation: conversation,
            messageActions: messageActions,
            menuCoordinator: coordinator
        )?.run()
        XCTAssertEqual(inbox.selectedRoomID, "!r1")

        CommandSet.hotkeyCommand(
            for: "Focus App",
            hotkeys: registry,
            inbox: inbox,
            spaces: spaces,
            search: search,
            conversation: conversation,
            messageActions: messageActions,
            menuCoordinator: coordinator
        )?.run()
        XCTAssertEqual(coordinator.focusCount, 1)

        CommandSet.hotkeyCommand(
            for: "Quit App",
            hotkeys: registry,
            inbox: inbox,
            spaces: spaces,
            search: search,
            conversation: conversation,
            messageActions: messageActions,
            menuCoordinator: coordinator
        )?.run()
        XCTAssertEqual(coordinator.quitRequestedCount, 1)

        CommandSet.hotkeyCommand(
            for: "Chat: Create New Group",
            hotkeys: registry,
            inbox: inbox,
            spaces: spaces,
            search: search,
            conversation: conversation,
            messageActions: messageActions,
            menuCoordinator: coordinator
        )?.run()
        XCTAssertNotNil(inbox.startNewChatDraft)
    }
}
