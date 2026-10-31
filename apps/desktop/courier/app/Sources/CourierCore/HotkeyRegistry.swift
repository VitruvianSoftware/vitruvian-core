// Copyright 2026 VitruvianSoftware
// SPDX-License-Identifier: AGPL-3.0-or-later

import AppKit
import Combine
import Foundation

/// A single keyboard shortcut chord (key + modifier flags) in the hotkey registry (`02` §2.1).
public struct KeyChord: Codable, Equatable, Hashable, Sendable {
    public var key: String
    public var command: Bool
    public var shift: Bool
    public var option: Bool
    public var control: Bool

    public init(
        key: String,
        command: Bool = false,
        shift: Bool = false,
        option: Bool = false,
        control: Bool = false
    ) {
        self.key = key.lowercased()
        self.command = command
        self.shift = shift
        self.option = option
        self.control = control
    }

    /// Formats as macOS symbols (e.g. `"⌘⇧E"`, `"⌃⌥→"`, `"⌘,"`) per inventory `02` §2.1.
    public var symbols: String {
        var out = ""
        if command { out += "⌘" }
        if control { out += "⌃" }
        if option { out += "⌥" }
        if shift { out += "⇧" }
        out += Self.displayKey(for: key)
        return out
    }

    /// Individual keycap labels for rendering in `KeyView` (e.g. `["⌘", "⇧", "E"]` or `["⌃", "Tab"]`).
    public var keycapTokens: [String] {
        var tokens: [String] = []
        if command { tokens.append("⌘") }
        if control { tokens.append("⌃") }
        if option { tokens.append("⌥") }
        if shift { tokens.append("⇧") }
        let keyLabel = Self.displayKey(for: key)
        if !keyLabel.isEmpty {
            tokens.append(keyLabel)
        }
        return tokens
    }

    /// True when at least one of command, control, option, or shift is set (or key is F1–F12).
    public var hasRequiredModifier: Bool {
        command || control || option || shift || Self.functionKeys.contains(key.lowercased())
    }

    private static let functionKeys: Set<String> = Set((1...12).map { "f\($0)" })

    /// Maps macOS virtual key codes (or `NSF1FunctionKey`–`NSF12FunctionKey` scalars) to `"f1"`–`"f12"`.
    public static func functionKeyName(forKeyCode keyCode: UInt16, charactersIgnoringModifiers: String? = nil) -> String? {
        switch keyCode {
        case 122: return "f1"
        case 120: return "f2"
        case 99: return "f3"
        case 118: return "f4"
        case 96: return "f5"
        case 97: return "f6"
        case 98: return "f7"
        case 100: return "f8"
        case 101: return "f9"
        case 109: return "f10"
        case 103: return "f11"
        case 111: return "f12"
        default:
            if let scalar = charactersIgnoringModifiers?.unicodeScalars.first,
               (0xF704...0xF70F).contains(scalar.value) {
                let index = Int(scalar.value - 0xF704) + 1
                return "f\(index)"
            }
            return nil
        }
    }

    /// Resolves a single-character key or function key (`"f1"`–`"f12"`) to its SwiftUI `KeyEquivalent` character.
    public static func keyEquivalentCharacter(for rawKey: String) -> Character? {
        let lower = rawKey.lowercased()
        if lower.hasPrefix("f"),
           let n = Int(lower.dropFirst()),
           (1...12).contains(n),
           let scalar = UnicodeScalar(0xF704 + n - 1) {
            return Character(scalar)
        }
        guard lower.count == 1 else { return nil }
        return lower.first
    }

    /// Builds a modifier-only chord (`key == ""`) when at least one primary modifier (`⌘`, `⌥`, `⌃`) is pressed.
    public static func modifierOnlyChord(
        command: Bool,
        shift: Bool,
        option: Bool,
        control: Bool
    ) -> KeyChord? {
        guard command || option || control else { return nil }
        return KeyChord(key: "", command: command, shift: shift, option: option, control: control)
    }

    private static func displayKey(for rawKey: String) -> String {
        let lower = rawKey.lowercased()
        switch lower {
        case "": return ""
        case "up", "uparrow": return "↑"
        case "down", "downarrow": return "↓"
        case "left", "leftarrow": return "←"
        case "right", "rightarrow": return "→"
        case "enter", "return": return "Enter"
        case "tab": return "Tab"
        case "escape", "esc": return "Escape"
        case "space", " ": return "Space"
        case "backspace", "delete": return "⌫"
        default:
            return lower.uppercased()
        }
    }
}

/// Validation or conflict error returned when recording a shortcut in `HotkeyRegistry`.
public enum HotkeyConflictError: Error, Equatable, Sendable {
    case missingModifier(String)
    case alreadyUsed(chord: String, existingAction: String, message: String)
    case systemReserved(chord: String, systemAction: String, message: String)
    case appLocked

    public var message: String {
        switch self {
        case let .missingModifier(msg):
            return msg
        case let .alreadyUsed(_, _, msg):
            return msg
        case let .systemReserved(_, _, msg):
            return msg
        case .appLocked:
            return "Unlock Courier before recording a keyboard shortcut."
        }
    }
}

/// Definition of a customizable or displayable keyboard shortcut (`02` §2.2).
public struct HotkeyDefinition: Equatable, Sendable, Identifiable {
    public let id: String          // ledger item name, e.g. "Chat: Toggle Archive"
    public let title: String
    public let category: String    // "General", "Navigation", "Chat", "Message", "Composer"
    public let defaultChords: [KeyChord]
    public let supportsGlobal: Bool // true for "Focus App" and "Focus App and Command Bar"

    public init(
        id: String,
        title: String,
        category: String,
        defaultChords: [KeyChord],
        supportsGlobal: Bool = false
    ) {
        self.id = id
        self.title = title
        self.category = category
        self.defaultChords = defaultChords
        self.supportsGlobal = supportsGlobal
    }
}

/// Single source of truth for Courier's keyboard shortcuts, read by the macOS menu bar, the `⌘/` Keyboard
/// Shortcuts sheet, and the Settings ▸ Shortcuts recorder (`01` §17, `02` §1.6, §2.1–2.2).
@MainActor
public final class HotkeyRegistry: ObservableObject {
    public static let categories: [String] = [
        "General",
        "Navigation",
        "Chat",
        "Message",
        "Composer",
    ]

    public static let allDefinitions: [HotkeyDefinition] = [
        // General
        HotkeyDefinition(
            id: "Focus App",
            title: "Focus Courier",
            category: "General",
            defaultChords: [],
            supportsGlobal: true
        ),
        HotkeyDefinition(
            id: "Focus App and Command Bar",
            title: "Focus Courier and Command Bar",
            category: "General",
            defaultChords: [],
            supportsGlobal: true
        ),
        HotkeyDefinition(
            id: "Search",
            title: "Search",
            category: "General",
            defaultChords: [KeyChord(key: "k", command: true)]
        ),
        HotkeyDefinition(
            id: "Search: Room",
            title: "Search in Chat",
            category: "General",
            defaultChords: [KeyChord(key: "f", command: true)]
        ),
        HotkeyDefinition(
            id: "Keyboard Shortcuts",
            title: "Keyboard Shortcuts",
            category: "General",
            defaultChords: [KeyChord(key: "/", command: true)]
        ),
        HotkeyDefinition(
            id: "Settings",
            title: "Settings",
            category: "General",
            defaultChords: [KeyChord(key: ",", command: true)]
        ),
        HotkeyDefinition(
            id: "Minimize To Menu Bar",
            title: "Minimize to Menu Bar",
            category: "General",
            defaultChords: [KeyChord(key: "q", command: true, option: true)]
        ),
        HotkeyDefinition(
            id: "Quit App",
            title: "Quit Courier",
            category: "General",
            defaultChords: [KeyChord(key: "q", command: true)]
        ),
        HotkeyDefinition(
            id: "Report a Problem",
            title: "Report a Problem",
            category: "General",
            defaultChords: [KeyChord(key: "p", command: true, shift: true)]
        ),
        HotkeyDefinition(
            id: "Toggle Incognito Mode",
            title: "Toggle Incognito Mode",
            category: "General",
            defaultChords: []
        ),

        // Navigation
        HotkeyDefinition(
            id: "Toggle Sidebar",
            title: "Toggle Sidebar",
            category: "Navigation",
            defaultChords: [KeyChord(key: "s", command: true, option: true)]
        ),
        HotkeyDefinition(
            id: "Toggle Space Bar",
            title: "Toggle Space Bar",
            category: "Navigation",
            defaultChords: [KeyChord(key: "s", command: true)]
        ),
        HotkeyDefinition(
            id: "Cycle Filters",
            title: "Cycle Filters",
            category: "Navigation",
            defaultChords: [KeyChord(key: "tab", option: true)]
        ),
        HotkeyDefinition(
            id: "Filter By Account",
            title: "Filter by Account",
            category: "Navigation",
            defaultChords: [KeyChord(key: "a", command: true, option: true)]
        ),
        HotkeyDefinition(
            id: "Filter: All",
            title: "Filter: All",
            category: "Navigation",
            defaultChords: []
        ),
        HotkeyDefinition(
            id: "Filter: Unread",
            title: "Filter: Unread",
            category: "Navigation",
            defaultChords: [KeyChord(key: "y", command: true, shift: true)]
        ),
        HotkeyDefinition(
            id: "Filter: Drafts",
            title: "Filter: Drafts",
            category: "Navigation",
            defaultChords: []
        ),
        HotkeyDefinition(
            id: "Filter: Unanswered",
            title: "Filter: Unanswered",
            category: "Navigation",
            defaultChords: []
        ),
        HotkeyDefinition(
            id: "Filter: DMs",
            title: "Filter: DMs",
            category: "Navigation",
            defaultChords: []
        ),
        HotkeyDefinition(
            id: "Filter: Groups",
            title: "Filter: Groups",
            category: "Navigation",
            defaultChords: []
        ),
        HotkeyDefinition(
            id: "Select Next Account",
            title: "Select Next Account",
            category: "Navigation",
            defaultChords: [KeyChord(key: "]", command: true, shift: true)]
        ),
        HotkeyDefinition(
            id: "Select Previous Account",
            title: "Select Previous Account",
            category: "Navigation",
            defaultChords: [KeyChord(key: "[", command: true, shift: true)]
        ),
        HotkeyDefinition(
            id: "Switch First 9 Spaces Modifier",
            title: "Switch First 9 Spaces Modifier",
            category: "Navigation",
            defaultChords: [KeyChord(key: "", command: true)]
        ),
        HotkeyDefinition(
            id: "Switch First 9 Chats Modifier",
            title: "Switch First 9 Chats Modifier",
            category: "Navigation",
            defaultChords: [KeyChord(key: "", control: true)]
        ),
        HotkeyDefinition(
            id: "Select Next Chat",
            title: "Select Next Chat",
            category: "Navigation",
            defaultChords: [
                KeyChord(key: "]", command: true),
                KeyChord(key: "down", command: true, option: true),
            ]
        ),
        HotkeyDefinition(
            id: "Select Previous Chat",
            title: "Select Previous Chat",
            category: "Navigation",
            defaultChords: [
                KeyChord(key: "[", command: true),
                KeyChord(key: "up", command: true, option: true),
            ]
        ),
        HotkeyDefinition(
            id: "Select Next Unread Chat",
            title: "Select Next Unread Chat",
            category: "Navigation",
            defaultChords: [KeyChord(key: "u", command: true)]
        ),
        HotkeyDefinition(
            id: "History: Next Chat",
            title: "History: Next Chat",
            category: "Navigation",
            defaultChords: [KeyChord(key: "right", option: true, control: true)]
        ),
        HotkeyDefinition(
            id: "History: Previous Chat",
            title: "History: Previous Chat",
            category: "Navigation",
            defaultChords: [KeyChord(key: "left", option: true, control: true)]
        ),
        HotkeyDefinition(
            id: "Cycle Chats (hold shift to reverse)",
            title: "Cycle Chats",
            category: "Navigation",
            defaultChords: [KeyChord(key: "tab", control: true)]
        ),
        HotkeyDefinition(
            id: "Scroll to the bottom of a chat",
            title: "Jump to Newest Message",
            category: "Navigation",
            defaultChords: [KeyChord(key: "down", command: true)]
        ),

        // Chat
        HotkeyDefinition(
            id: "Chat: Start New",
            title: "New Chat",
            category: "Chat",
            defaultChords: [KeyChord(key: "n", command: true)]
        ),
        HotkeyDefinition(
            id: "Chat: Create New Group",
            title: "New Group or Blast",
            category: "Chat",
            defaultChords: [KeyChord(key: "n", command: true, shift: true)]
        ),
        HotkeyDefinition(
            id: "Chat: Toggle Archive",
            title: "Archive or Unarchive Chat",
            category: "Chat",
            defaultChords: [KeyChord(key: "e", command: true)]
        ),
        HotkeyDefinition(
            id: "Chat: Archive All Read",
            title: "Archive All Read Chats",
            category: "Chat",
            defaultChords: [KeyChord(key: "e", command: true, shift: true)]
        ),
        HotkeyDefinition(
            id: "Chat: Toggle Mark As Read",
            title: "Mark Chat Read or Unread",
            category: "Chat",
            defaultChords: [KeyChord(key: "u", command: true, shift: true)]
        ),
        HotkeyDefinition(
            id: "Chat: Toggle Mute",
            title: "Mute or Unmute Chat",
            category: "Chat",
            defaultChords: [KeyChord(key: "m", command: true, shift: true)]
        ),
        HotkeyDefinition(
            id: "Chat: Toggle Pin",
            title: "Pin or Unpin Chat",
            category: "Chat",
            defaultChords: [KeyChord(key: "p", command: true)]
        ),
        HotkeyDefinition(
            id: "Remind Later",
            title: "Remind Me Later",
            category: "Chat",
            defaultChords: [KeyChord(key: "l", command: true)]
        ),
        HotkeyDefinition(
            id: "Chat: Send File",
            title: "Attach Files",
            category: "Chat",
            defaultChords: [KeyChord(key: "o", command: true)]
        ),
        HotkeyDefinition(
            id: "Toggle Chat Info",
            title: "Toggle Chat Info",
            category: "Chat",
            defaultChords: [KeyChord(key: "i", command: true, shift: true)]
        ),
        HotkeyDefinition(
            id: "Open User Profile",
            title: "Show Sender Profile",
            category: "Chat",
            defaultChords: [KeyChord(key: "o", command: true, shift: true)]
        ),
        HotkeyDefinition(
            id: "Chat: Delete",
            title: "Delete Chat",
            category: "Chat",
            defaultChords: []
        ),

        // Message
        HotkeyDefinition(
            id: "Message: Quote & Reply",
            title: "Reply to Message",
            category: "Message",
            defaultChords: [KeyChord(key: "r", command: true)]
        ),
        HotkeyDefinition(
            id: "Message: Quote or Edit Selected Message",
            title: "Quote or Edit Selected Message",
            category: "Message",
            defaultChords: [KeyChord(key: "enter")]
        ),
        HotkeyDefinition(
            id: "Message: Edit",
            title: "Edit Message",
            category: "Message",
            defaultChords: [KeyChord(key: "t", command: true)]
        ),
        HotkeyDefinition(
            id: "Message: Quick React",
            title: "Quick React",
            category: "Message",
            defaultChords: [KeyChord(key: "r", command: true, shift: true)]
        ),
        HotkeyDefinition(
            id: "Message: Forward",
            title: "Forward Message",
            category: "Message",
            defaultChords: [KeyChord(key: "f", command: true, shift: true)]
        ),
        HotkeyDefinition(
            id: "Message: Open First Link",
            title: "Open First Link in Message",
            category: "Message",
            defaultChords: [KeyChord(key: "h", command: true, shift: true)]
        ),
        HotkeyDefinition(
            id: "Download Attachments",
            title: "Download Attachments",
            category: "Message",
            defaultChords: [KeyChord(key: "d", command: true)]
        ),
        HotkeyDefinition(
            id: "Show Replies",
            title: "Show Replies",
            category: "Message",
            defaultChords: [KeyChord(key: "down", command: true)]
        ),
        HotkeyDefinition(
            id: "Message: Send Later",
            title: "Send Later",
            category: "Message",
            defaultChords: [KeyChord(key: "l", command: true, shift: true)]
        ),
        HotkeyDefinition(
            id: "Message: Send Message and Archive",
            title: "Send Message and Archive",
            category: "Message",
            defaultChords: [KeyChord(key: "enter", command: true)]
        ),
        HotkeyDefinition(
            id: "Message: Record Audio",
            title: "Record Voice Note",
            category: "Message",
            defaultChords: [KeyChord(key: "a", command: true, shift: true)]
        ),
        HotkeyDefinition(
            id: "Message: Send GIF",
            title: "Send GIF",
            category: "Message",
            defaultChords: [KeyChord(key: "g", command: true, shift: true)]
        ),
        HotkeyDefinition(
            id: "Message: Send Sticker",
            title: "Send Sticker",
            category: "Message",
            defaultChords: [KeyChord(key: "s", command: true, shift: true, option: true)]
        ),
        // Composer
        HotkeyDefinition(
            id: "Undo Pending Send",
            title: "Undo Pending Send",
            category: "Composer",
            defaultChords: [KeyChord(key: "z", command: true)]
        ),
        HotkeyDefinition(
            id: "Send Message",
            title: "Send Message",
            category: "Composer",
            defaultChords: [KeyChord(key: "enter")]
        ),
        HotkeyDefinition(
            id: "Insert New Line",
            title: "Insert New Line",
            category: "Composer",
            defaultChords: [
                KeyChord(key: "enter", option: true),
                KeyChord(key: "enter", control: true),
                KeyChord(key: "enter", shift: true),
            ]
        ),
    ]

    /// System-wide macOS shortcuts that cannot be claimed by app actions.
    public static let reservedSystemShortcuts: [KeyChord: String] = [
        KeyChord(key: "h", command: true): "Hide Window",
        KeyChord(key: "h", command: true, option: true): "Hide Others",
        KeyChord(key: "m", command: true): "Minimize Window",
        KeyChord(key: "tab", command: true): "App Switcher",
        KeyChord(key: "space", command: true): "Spotlight",
        KeyChord(key: "q", command: true, control: true): "Lock Screen",
        KeyChord(key: "escape", command: true, option: true): "Force Quit",
    ]

    @Published public var searchQuery: String = ""
    @Published public private(set) var overrides: [String: [KeyChord]]
    @Published public private(set) var disabledIDs: Set<String>
    @Published public private(set) var globalIDs: Set<String>
    /// Whether the `⌘/` Keyboard Shortcuts sheet is currently presented.
    @Published public var isShortcutsSheetPresented: Bool = false
    /// Which shortcut row is currently waiting for a key press in the recorder (`nil` when idle).
    @Published public private(set) var recordingHotkeyID: String?
    /// Most recent validation/conflict error for a shortcut row.
    @Published public private(set) var conflictErrors: [String: HotkeyConflictError] = [:]

    private let defaults: UserDefaults
    private let isAppLocked: @MainActor () -> Bool
    private var lockObserver: AnyCancellable?

    private static let overridesKey = "courier.hotkeys.overrides"
    private static let disabledKey = "courier.hotkeys.disabled"
    private static let globalKey = "courier.hotkeys.global"

    public init(
        defaults: UserDefaults = .standard,
        isAppLocked: @escaping @MainActor () -> Bool = { false }
    ) {
        self.defaults = defaults
        self.isAppLocked = isAppLocked
        if let data = defaults.data(forKey: Self.overridesKey),
           let decoded = try? JSONDecoder().decode([String: [KeyChord]].self, from: data) {
            self.overrides = decoded
        } else {
            self.overrides = [:]
        }
        if let savedDisabled = defaults.stringArray(forKey: Self.disabledKey) {
            self.disabledIDs = Set(savedDisabled)
        } else {
            self.disabledIDs = []
        }
        if let savedGlobal = defaults.stringArray(forKey: Self.globalKey) {
            self.globalIDs = Set(savedGlobal)
        } else {
            self.globalIDs = []
        }
        self.lockObserver = NotificationCenter.default
            .publisher(for: SystemLifecycleModel.didLockNotification)
            .sink { [weak self] _ in
                self?.dismissAllPresentations()
            }
    }

    public func dismissAllPresentations() {
        isShortcutsSheetPresented = false
        cancelRecording()
    }

    public func definition(for id: String) -> HotkeyDefinition? {
        Self.allDefinitions.first { $0.id == id }
    }

    /// True when the app lock is active (`SystemLifecycleModel.isLocked`).
    public var isLocked: Bool {
        isAppLocked()
    }

    public func isEnabled(_ id: String) -> Bool {
        !disabledIDs.contains(id)
    }

    /// Active chords for `id` (empty when the shortcut is disabled).
    public func chords(for id: String) -> [KeyChord] {
        guard !disabledIDs.contains(id) else { return [] }
        if let custom = overrides[id] {
            return custom
        }
        return definition(for: id)?.defaultChords ?? []
    }

    /// Configured chords for `id` (even when disabled, for display in Settings ▸ Shortcuts).
    public func configuredChords(for id: String) -> [KeyChord] {
        if let custom = overrides[id] {
            return custom
        }
        return definition(for: id)?.defaultChords ?? []
    }

    /// Primary active chord for `id`, used by menu bar items.
    public func primaryChord(for id: String) -> KeyChord? {
        chords(for: id).first
    }

    /// Definitions matching `query` across title, ledger ID, category, or formatted key symbols.
    public func filteredDefinitions(matching rawQuery: String) -> [HotkeyDefinition] {
        let query = rawQuery.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !query.isEmpty else { return Self.allDefinitions }
        return Self.allDefinitions.filter { def in
            if def.title.lowercased().contains(query) || def.id.lowercased().contains(query) || def.category.lowercased().contains(query) {
                return true
            }
            let activeSymbols = configuredChords(for: def.id).map { $0.symbols.lowercased() }
            return activeSymbols.contains { $0.contains(query) }
        }
    }

    /// Definitions matching `searchQuery` across title, ledger ID, category, or formatted key symbols.
    public var filteredDefinitions: [HotkeyDefinition] {
        filteredDefinitions(matching: searchQuery)
    }

    /// Starts recording a shortcut for `id`, unless the app is locked.
    public func beginRecording(for id: String) {
        guard !isAppLocked() else {
            recordingHotkeyID = nil
            return
        }
        conflictErrors[id] = nil
        recordingHotkeyID = id
    }

    /// Cancels any active shortcut recording.
    public func cancelRecording() {
        if let id = recordingHotkeyID {
            conflictErrors[id] = nil
        }
        recordingHotkeyID = nil
    }

    /// Records `chord` for `id` after validating required modifiers, system conflicts, and existing app shortcuts.
    /// Never captures or persists anything while the app is locked (`isAppLocked() == true`).
    @discardableResult
    public func record(_ chord: KeyChord, for id: String) -> Result<Void, HotkeyConflictError> {
        if isAppLocked() {
            recordingHotkeyID = nil
            return .failure(.appLocked)
        }

        let allowsSingleEnter = (id == "Send Message" || id == "Message: Quote or Edit Selected Message")
            && chord.key.lowercased() == "enter"
        let isModifierOnlyAction = (id == "Switch First 9 Spaces Modifier" || id == "Switch First 9 Chats Modifier")
            && chord.key.isEmpty && (chord.command || chord.control || chord.option)

        if !chord.hasRequiredModifier && !allowsSingleEnter && !isModifierOnlyAction {
            let error = HotkeyConflictError.missingModifier(
                "You must use a modifier key like Ctrl, Shift or Option/Alt"
            )
            conflictErrors[id] = error
            return .failure(error)
        }

        if let systemAction = Self.reservedSystemShortcuts[chord] {
            let symbol = chord.symbols
            let error = HotkeyConflictError.systemReserved(
                chord: symbol,
                systemAction: systemAction,
                message: "\(symbol) is reserved by macOS for \(systemAction)"
            )
            conflictErrors[id] = error
            return .failure(error)
        }

        // Check conflicts against all other enabled actions in the registry.
        for other in Self.allDefinitions where other.id != id && isEnabled(other.id) {
            if Self.isContextualPair(id, other.id) { continue }

            let existingChords = chords(for: other.id)
            if existingChords.contains(chord) {
                let symbol = chord.symbols
                let error = HotkeyConflictError.alreadyUsed(
                    chord: symbol,
                    existingAction: other.title,
                    message: "\(symbol) is already used by \(other.title)"
                )
                conflictErrors[id] = error
                return .failure(error)
            }
        }

        conflictErrors[id] = nil
        overrides[id] = [chord]
        disabledIDs.remove(id)
        if recordingHotkeyID == id {
            recordingHotkeyID = nil
        }
        persist()
        return .success(())
    }

    public func setEnabled(_ enabled: Bool, for id: String) {
        guard !isAppLocked() else { return }
        if enabled {
            disabledIDs.remove(id)
        } else {
            disabledIDs.insert(id)
        }
        conflictErrors[id] = nil
        persist()
    }

    public func setGlobal(_ global: Bool, for id: String) {
        guard !isAppLocked(),
              let def = definition(for: id),
              def.supportsGlobal
        else { return }
        if global {
            globalIDs.insert(id)
        } else {
            globalIDs.remove(id)
        }
        persist()
    }

    public func revert(id: String) {
        guard !isAppLocked() else { return }
        overrides.removeValue(forKey: id)
        disabledIDs.remove(id)
        globalIDs.remove(id)
        conflictErrors[id] = nil
        if recordingHotkeyID == id {
            recordingHotkeyID = nil
        }
        persist()
    }

    public func revertAll() {
        guard !isAppLocked() else { return }
        overrides.removeAll()
        disabledIDs.removeAll()
        globalIDs.removeAll()
        conflictErrors.removeAll()
        recordingHotkeyID = nil
        persist()
    }

    /// Applies the Texts.app keybinding preset (`02` §1.6):
    /// - Edit Message = `⌘I`
    /// - Toggle Mark As Read = `⌘U`
    /// - Toggle Archive = `⌘E` or `⌘⇧E`
    /// - Archive All Read = disabled
    /// - Select Previous Chat = `⌘[`, `⌘⌥↑`, `⌃⇧Tab`
    /// - Select Next Chat = `⌘]`, `⌘⌥↓`, `⌃Tab`
    /// - Switch First 9 Chats Modifier = `⌘`
    /// - Switch First 9 Spaces Modifier = `⌃`
    /// - History Previous / Next = `⌃⌥←` / `⌃⌥→`
    public func applyTextsAppPreset() {
        guard !isAppLocked() else { return }
        conflictErrors.removeAll()
        recordingHotkeyID = nil

        overrides["Message: Edit"] = [KeyChord(key: "i", command: true)]
        overrides["Chat: Toggle Mark As Read"] = [KeyChord(key: "u", command: true)]
        disabledIDs.insert("Select Next Unread Chat")
        overrides["Chat: Toggle Archive"] = [
            KeyChord(key: "e", command: true),
            KeyChord(key: "e", command: true, shift: true),
        ]
        disabledIDs.insert("Chat: Archive All Read")
        overrides["Select Previous Chat"] = [
            KeyChord(key: "[", command: true),
            KeyChord(key: "up", command: true, option: true),
            KeyChord(key: "tab", shift: true, control: true),
        ]
        overrides["Select Next Chat"] = [
            KeyChord(key: "]", command: true),
            KeyChord(key: "down", command: true, option: true),
            KeyChord(key: "tab", control: true),
        ]
        disabledIDs.insert("Cycle Chats (hold shift to reverse)")
        overrides["Switch First 9 Chats Modifier"] = [KeyChord(key: "", command: true)]
        overrides["Switch First 9 Spaces Modifier"] = [KeyChord(key: "", control: true)]
        overrides["History: Previous Chat"] = [KeyChord(key: "left", option: true, control: true)]
        overrides["History: Next Chat"] = [KeyChord(key: "right", option: true, control: true)]
        persist()
    }

    /// For snapshot testing: sets recording state and optional conflict error directly.
    public func setRecorderStateForTesting(recordingID: String?, conflict: (id: String, error: HotkeyConflictError)? = nil) {
        self.recordingHotkeyID = recordingID
        if let conflict {
            self.conflictErrors[conflict.id] = conflict.error
        }
    }

    public static func isModifierOnlyDefinition(_ id: String) -> Bool {
        id == "Switch First 9 Spaces Modifier" || id == "Switch First 9 Chats Modifier"
    }

    private static func isContextualPair(_ firstID: String, _ secondID: String) -> Bool {
        let pair = Set([firstID, secondID])
        return pair == Set(["Scroll to the bottom of a chat", "Show Replies"])
            || pair == Set(["Message: Quote or Edit Selected Message", "Send Message"])
    }

    public func activeConflicts() -> [(firstID: String, secondID: String, chord: KeyChord)] {
        var result: [(firstID: String, secondID: String, chord: KeyChord)] = []
        let enabled = Self.allDefinitions.filter { isEnabled($0.id) }
        for i in 0..<enabled.count {
            for j in (i + 1)..<enabled.count {
                let first = enabled[i]
                let second = enabled[j]
                if Self.isContextualPair(first.id, second.id) {
                    continue
                }
                let firstChords = chords(for: first.id)
                for chord in chords(for: second.id) where firstChords.contains(chord) {
                    result.append((first.id, second.id, chord))
                }
            }
        }
        return result
    }

    private func persist() {
        if overrides.isEmpty {
            defaults.removeObject(forKey: Self.overridesKey)
        } else if let data = try? JSONEncoder().encode(overrides) {
            defaults.set(data, forKey: Self.overridesKey)
        }
        if disabledIDs.isEmpty {
            defaults.removeObject(forKey: Self.disabledKey)
        } else {
            defaults.set(Array(disabledIDs).sorted(), forKey: Self.disabledKey)
        }
        if globalIDs.isEmpty {
            defaults.removeObject(forKey: Self.globalKey)
        } else {
            defaults.set(Array(globalIDs).sorted(), forKey: Self.globalKey)
        }
    }
}

/// Identifies a single window-level keyboard shortcut binding in `MainWindow.alternateShortcuts`.
public struct WindowShortcutBinding: Identifiable, Equatable, Sendable {
    public let id: String
    public let hotkeyID: String
    public let chordIndex: Int
    public let reversesCycle: Bool

    public init(
        hotkeyID: String,
        chordIndex: Int = 0,
        reversesCycle: Bool = false
    ) {
        self.hotkeyID = hotkeyID
        self.chordIndex = chordIndex
        self.reversesCycle = reversesCycle
        self.id = "\(hotkeyID)#\(chordIndex)#\(reversesCycle ? "rev" : "fwd")"
    }
}

/// Single live dispatcher for every shortcut in `HotkeyRegistry.allDefinitions`.
/// All menu commands (`InboxCommands`, `ConversationCommands`), window-level alternate shortcuts
/// (`MainWindow.alternateShortcuts`), composer Return handling (`ComposerModel.handleReturn`), and
/// global hotkeys (`GlobalHotkeyMonitor`) route through this dispatcher so lock and entitlement
/// checks (`!lifecycle.isLocked`, `.incognito`, `.reminders`) are enforced in one place.
@MainActor
public final class HotkeyDispatcher: ObservableObject {
    public let inbox: InboxModel
    public let spaces: SpacesModel
    public let conversation: ConversationModel
    public let messageActions: MessageActionsModel
    public let search: SearchModel
    public let lifecycle: SystemLifecycleModel
    public let menuCoordinator: AppMenuCoordinator
    public let focus: MessageFocus
    public let hotkeys: HotkeyRegistry

    /// Brings the main window forward when a shortcut needs it; returns true when it was already key.
    public var bringMainWindowForward: @MainActor () -> Bool
    /// Opens the Filter by Account popover (`⌘⌥A`).
    public var onFilterByAccount: @MainActor () -> Void
    /// Opens the Remind Me popover (`⌘L`).
    public var onRemindLater: @MainActor () -> Void
    /// Opens the file attachment picker (`⌘O`) for the active composer.
    public var onAttachFiles: @MainActor (ComposerModel) -> Void
    /// Runs the Archive All Read Chats confirmation flow (`⌘⇧E`).
    public var onArchiveAllRead: @MainActor () async -> Void
    /// Performs the responder-chain undo when neither a held send nor an undoable toast is active (`⌘Z`).
    public var onFallbackUndo: @MainActor () -> Void

    @Published public private(set) var attachFilesInvocationCount: Int = 0
    @Published public private(set) var remindLaterInvocationCount: Int = 0
    @Published public private(set) var filterByAccountInvocationCount: Int = 0
    @Published public private(set) var archiveAllReadInvocationCount: Int = 0
    @Published public private(set) var fallbackUndoInvocationCount: Int = 0

    /// Shortcut IDs bound in `InboxCommands`.
    public static let inboxMenuShortcutIDs: [String] = [
        "Focus App",
        "Focus App and Command Bar",
        "Settings",
        "Search",
        "Minimize To Menu Bar",
        "Quit App",
        "Chat: Start New",
        "Chat: Create New Group",
        "Undo Pending Send",
        "Toggle Space Bar",
        "Toggle Sidebar",
        "Toggle Incognito Mode",
        "Select Next Chat",
        "Select Previous Chat",
        "Select Next Unread Chat",
        "History: Previous Chat",
        "History: Next Chat",
        "Switch First 9 Chats Modifier",
        "Search: Room",
        "Chat: Toggle Archive",
        "Chat: Toggle Mark As Read",
        "Chat: Toggle Mute",
        "Chat: Toggle Pin",
        "Remind Later",
        "Chat: Archive All Read",
        "Cycle Filters",
        "Filter: All",
        "Filter: Unread",
        "Filter: Drafts",
        "Filter: Unanswered",
        "Filter: DMs",
        "Filter: Groups",
        "Filter By Account",
        "Select Next Account",
        "Select Previous Account",
        "Switch First 9 Spaces Modifier",
        "Report a Problem",
        "Keyboard Shortcuts",
    ]

    /// Shortcut IDs bound in `ConversationCommands`.
    public static let conversationMenuShortcutIDs: [String] = [
        "Message: Edit",
        "Message: Quote & Reply",
        "Scroll to the bottom of a chat",
        "Show Replies",
        "Message: Quick React",
        "Message: Forward",
        "Message: Open First Link",
        "Message: Send Later",
        "Message: Send Message and Archive",
        "Chat: Send File",
        "Download Attachments",
        "Message: Record Audio",
        "Message: Send GIF",
        "Message: Send Sticker",
        "Toggle Chat Info",
        "Open User Profile",
        "Chat: Delete",
    ]

    /// Window-level shortcut bindings rendered in `MainWindow.alternateShortcuts`.
    public static let windowShortcutBindings: [WindowShortcutBinding] = [
        WindowShortcutBinding(hotkeyID: "Select Next Chat", chordIndex: 1),
        WindowShortcutBinding(hotkeyID: "Select Next Chat", chordIndex: 2),
        WindowShortcutBinding(hotkeyID: "Select Previous Chat", chordIndex: 1),
        WindowShortcutBinding(hotkeyID: "Select Previous Chat", chordIndex: 2),
        WindowShortcutBinding(hotkeyID: "Chat: Toggle Archive", chordIndex: 1),
        WindowShortcutBinding(hotkeyID: "Cycle Chats (hold shift to reverse)", chordIndex: 0, reversesCycle: false),
        WindowShortcutBinding(hotkeyID: "Cycle Chats (hold shift to reverse)", chordIndex: 0, reversesCycle: true),
        WindowShortcutBinding(hotkeyID: "Search: Room", chordIndex: 0),
        WindowShortcutBinding(hotkeyID: "Focus App", chordIndex: 0),
        WindowShortcutBinding(hotkeyID: "Focus App and Command Bar", chordIndex: 0),
        WindowShortcutBinding(hotkeyID: "Toggle Incognito Mode", chordIndex: 0),
        WindowShortcutBinding(hotkeyID: "Filter: All", chordIndex: 0),
        WindowShortcutBinding(hotkeyID: "Filter: Drafts", chordIndex: 0),
        WindowShortcutBinding(hotkeyID: "Filter: Unanswered", chordIndex: 0),
        WindowShortcutBinding(hotkeyID: "Filter: DMs", chordIndex: 0),
        WindowShortcutBinding(hotkeyID: "Filter: Groups", chordIndex: 0),
        WindowShortcutBinding(hotkeyID: "Chat: Delete", chordIndex: 0),
    ]

    /// Shortcut IDs consulted directly by `ComposerModel.handleReturn(modifiers:)`.
    public static let composerShortcutIDs: [String] = [
        "Send Message",
        "Insert New Line",
        "Message: Quote or Edit Selected Message",
    ]

    /// Union of every shortcut ID wired into the live menus, window shortcuts, and composer Return handler.
    public static var allLiveWiredShortcutIDs: Set<String> {
        var ids = Set(inboxMenuShortcutIDs)
        ids.formUnion(conversationMenuShortcutIDs)
        ids.formUnion(windowShortcutBindings.map(\.hotkeyID))
        ids.formUnion(composerShortcutIDs)
        return ids
    }

    public init(
        inbox: InboxModel,
        spaces: SpacesModel,
        conversation: ConversationModel,
        messageActions: MessageActionsModel,
        search: SearchModel,
        lifecycle: SystemLifecycleModel,
        menuCoordinator: AppMenuCoordinator,
        focus: MessageFocus? = nil,
        hotkeys: HotkeyRegistry,
        bringMainWindowForward: @escaping @MainActor () -> Bool = { true },
        onFilterByAccount: @escaping @MainActor () -> Void = {},
        onRemindLater: @escaping @MainActor () -> Void = {},
        onAttachFiles: @escaping @MainActor (ComposerModel) -> Void = { _ in },
        onArchiveAllRead: (@MainActor () async -> Void)? = nil,
        onFallbackUndo: @escaping @MainActor () -> Void = {
            NSApp?.sendAction(Selector(("undo:")), to: nil, from: nil)
        }
    ) {
        self.inbox = inbox
        self.spaces = spaces
        self.conversation = conversation
        self.messageActions = messageActions
        self.search = search
        self.lifecycle = lifecycle
        self.menuCoordinator = menuCoordinator
        self.focus = focus ?? MessageFocus()
        self.hotkeys = hotkeys
        self.bringMainWindowForward = bringMainWindowForward
        self.onFilterByAccount = onFilterByAccount
        self.onRemindLater = onRemindLater
        self.onAttachFiles = onAttachFiles
        self.onArchiveAllRead = onArchiveAllRead ?? { [weak inbox] in
            _ = await inbox?.archiveAllRead()
        }
        self.onFallbackUndo = onFallbackUndo

        conversation.composer.hotkeyDispatcher = self
        conversation.composer.hotkeys = hotkeys
        conversation.thread.composer.hotkeyDispatcher = self
        conversation.thread.composer.hotkeys = hotkeys
    }

    /// Active composer that keyboard shortcuts target (thread pane when focused, otherwise main chat).
    public var activeComposer: ComposerModel {
        focus.inPane && conversation.thread.roomID != nil ? conversation.thread.composer : conversation.composer
    }

    /// Composer holding pending undo-send messages in the open room, if any.
    public var heldComposer: ComposerModel? {
        [conversation.composer, conversation.thread.composer].first {
            !$0.heldIDs.isEmpty && $0.roomID != nil && $0.roomID == conversation.roomID
        }
    }

    /// Selected message and its source (`.chat` or `.thread`).
    public var selectedMessage: (id: String, source: MessageSource)? {
        focus.target(chatSelection: conversation.selectedMessageID)
    }

    /// Thread root message ID when the selected chat message has replies (`Show Replies` target).
    public var showRepliesTarget: String? {
        guard let selectedMessage,
              selectedMessage.source == .chat,
              conversation.message(selectedMessage.id, from: .chat)?.thread != nil
        else { return nil }
        return selectedMessage.id
    }

    /// Whether the selected message (or active lightbox item) has local media attachments that can be downloaded.
    public var canDownloadAttachments: Bool {
        if let lightboxID = conversation.activeLightboxMessageID {
            return hasDownloadableAttachment(forLightboxID: lightboxID)
        }
        guard let selectedMessage,
              let message = conversation.message(selectedMessage.id, from: selectedMessage.source),
              !message.viewOnce
        else {
            return false
        }
        if !message.galleryItems.isEmpty {
            return message.galleryItems.contains { isLocalMediaStorePath($0.mediaPath) }
        }
        return isLocalMediaStorePath(message.mediaPath)
    }

    /// Returns true only when the app is unlocked, the shortcut is enabled in `HotkeyRegistry`,
    /// any required entitlement (`.incognito`, `.reminders`) is granted, and the action's state precondition holds.
    public func canPerform(_ id: String) -> Bool {
        guard !lifecycle.isLocked,
              hotkeys.isEnabled(id),
              hotkeys.definition(for: id) != nil
        else {
            return false
        }

        switch id {
        case "Focus App",
             "Focus App and Command Bar",
             "Search",
             "Search: Room",
             "Keyboard Shortcuts",
             "Settings",
             "Minimize To Menu Bar",
             "Quit App",
             "Report a Problem",
             "Toggle Sidebar",
             "Toggle Space Bar",
             "Cycle Filters",
             "Filter: All",
             "Filter: Unread",
             "Filter: Drafts",
             "Filter: Unanswered",
             "Filter: DMs",
             "Filter: Groups",
             "Undo Pending Send":
            return true

        case "Toggle Incognito Mode":
            return inbox.isEntitled(.incognito)

        case "Filter By Account":
            return spaces.spaces.contains { $0.kind == .account }

        case "Select Next Account", "Select Previous Account":
            return spaces.spaces.filter { $0.kind == .account }.count > 1

        case "Switch First 9 Spaces Modifier":
            return !spaces.visible.isEmpty

        case "Switch First 9 Chats Modifier",
             "Select Next Chat",
             "Select Previous Chat",
             "Cycle Chats (hold shift to reverse)":
            return !inbox.rows.isEmpty

        case "Select Next Unread Chat":
            return inbox.rows.contains { $0.unread > 0 }

        case "History: Next Chat", "History: Previous Chat":
            return inbox.recentlyViewedRoomIDs.count > 1

        case "Scroll to the bottom of a chat",
             "Chat: Send File",
             "Toggle Chat Info",
             "Open User Profile",
             "Message: Edit",
             "Message: Forward",
             "Message: Send Message and Archive",
             "Insert New Line":
            return conversation.roomID != nil

        case "Message: Send Later":
            return conversation.roomID != nil
                && inbox.isEntitled(.sendLater)
                && activeComposer.entitlement.isEntitled(.sendLater)
                && activeComposer.canSchedule

        case "Chat: Start New", "Chat: Create New Group":
            return !inbox.accounts.isEmpty

        case "Chat: Toggle Archive":
            let rows = inbox.targetRows()
            let allArchived = !rows.isEmpty && rows.allSatisfy(\.archived)
            let allPinned = !rows.isEmpty && rows.allSatisfy(\.pinned)
            return !inbox.targets.isEmpty && (allArchived || !allPinned)

        case "Chat: Archive All Read":
            return inbox.canArchiveAll

        case "Chat: Toggle Mark As Read":
            return inbox.canToggleRead

        case "Chat: Toggle Mute", "Chat: Toggle Pin":
            return !inbox.targets.isEmpty

        case "Remind Later":
            return !inbox.targets.isEmpty && inbox.isEntitled(.reminders)

        case "Chat: Delete":
            return conversation.roomID != nil

        case "Message: Quote & Reply",
             "Message: Quick React",
             "Message: Open First Link":
            return selectedMessage != nil

        case "Message: Quote or Edit Selected Message":
            return selectedMessage != nil || conversation.roomID != nil

        case "Download Attachments":
            return canDownloadAttachments

        case "Show Replies":
            return showRepliesTarget != nil

        case "Message: Record Audio":
            return conversation.roomID != nil && (
                activeComposer.voiceRecorder.isRecordingOrReviewing || activeComposer.features.supportsVoiceSend
            )

        case "Message: Send GIF":
            return activeComposer.canSendGIF

        case "Message: Send Sticker":
            return activeComposer.canSendSticker

        case "Send Message":
            return conversation.roomID != nil
                && !activeComposer.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty

        default:
            return false
        }
    }

    /// Executes a window-level shortcut binding if `canPerform(binding.hotkeyID)` is true.
    @discardableResult
    public func perform(_ binding: WindowShortcutBinding) -> Bool {
        perform(binding.hotkeyID, reverse: binding.reversesCycle)
    }

    /// Executes the Switch First 9 Spaces action for `number` (`1...9`) if unlocked and enabled.
    @discardableResult
    public func performSwitchSpace(number: Int) -> Bool {
        guard canPerform("Switch First 9 Spaces Modifier"), (1...9).contains(number) else { return false }
        spaces.selectNumber(number)
        return true
    }

    /// Executes the Switch First 9 Chats action for `number` (`1...9`) if unlocked and enabled.
    @discardableResult
    public func performSwitchChat(number: Int) -> Bool {
        guard canPerform("Switch First 9 Chats Modifier"), (1...9).contains(number) else { return false }
        inbox.selectChat(number: number)
        return true
    }

    /// Executes the shortcut `id` (with optional `reverse` for `Cycle Chats (hold shift to reverse)`).
    /// Returns `true` when the shortcut was allowed and dispatched, or `false` when blocked by lock,
    /// entitlement, disabled state, or unsatisfied precondition.
    @discardableResult
    public func perform(_ id: String, reverse: Bool = false) -> Bool {
        guard canPerform(id) else { return false }

        switch id {
        case "Focus App":
            menuCoordinator.focusApp()
            return true

        case "Focus App and Command Bar":
            menuCoordinator.focusApp()
            let visible = bringMainWindowForward()
            search.toggle(visible: visible)
            return true

        case "Search":
            let visible = bringMainWindowForward()
            search.toggle(visible: visible)
            return true

        case "Search: Room":
            _ = bringMainWindowForward()
            search.show(in: inbox.selectedRoomID)
            return true

        case "Keyboard Shortcuts":
            _ = bringMainWindowForward()
            hotkeys.isShortcutsSheetPresented.toggle()
            return true

        case "Settings":
            menuCoordinator.openSettings(.inbox)
            return true

        case "Minimize To Menu Bar":
            menuCoordinator.minimizeToMenuBar()
            return true

        case "Quit App":
            menuCoordinator.quitApp()
            return true

        case "Report a Problem":
            menuCoordinator.openSettings(.reportProblem)
            return true

        case "Toggle Incognito Mode":
            conversation.setIncognito(!conversation.incognitoIsOn)
            return true

        case "Toggle Sidebar":
            menuCoordinator.toggleSidebar()
            return true

        case "Toggle Space Bar":
            menuCoordinator.toggleSpaceBar()
            return true

        case "Cycle Filters":
            inbox.cycleFilter()
            return true

        case "Filter By Account":
            filterByAccountInvocationCount += 1
            onFilterByAccount()
            return true

        case "Filter: All":
            inbox.query.filters.removeAll()
            return true

        case "Filter: Unread":
            inbox.toggleUnreadFilter()
            return true

        case "Filter: Drafts":
            var filters = inbox.query.filters
            if filters.remove(.drafts) == nil { filters.insert(.drafts) }
            inbox.query.filters = filters
            return true

        case "Filter: Unanswered":
            var filters = inbox.query.filters
            if filters.remove(.unanswered) == nil { filters.insert(.unanswered) }
            inbox.query.filters = filters
            return true

        case "Filter: DMs":
            var filters = inbox.query.filters
            if filters.remove(.dms) == nil {
                filters.remove(.groups)
                filters.insert(.dms)
            }
            inbox.query.filters = filters
            return true

        case "Filter: Groups":
            var filters = inbox.query.filters
            if filters.remove(.groups) == nil {
                filters.remove(.dms)
                filters.insert(.groups)
            }
            inbox.query.filters = filters
            return true

        case "Select Next Account":
            spaces.selectNextAccount()
            return true

        case "Select Previous Account":
            spaces.selectPreviousAccount()
            return true

        case "Switch First 9 Spaces Modifier":
            spaces.selectNumber(1)
            return true

        case "Switch First 9 Chats Modifier":
            inbox.selectChat(number: 1)
            return true

        case "Select Next Chat":
            inbox.selectNext()
            return true

        case "Select Previous Chat":
            inbox.selectPrevious()
            return true

        case "Select Next Unread Chat":
            inbox.selectNextUnread()
            return true

        case "History: Next Chat":
            inbox.selectNextRecentChat()
            return true

        case "History: Previous Chat":
            inbox.selectPreviousRecentChat()
            return true

        case "Cycle Chats (hold shift to reverse)":
            inbox.cycleChat(reverse: reverse)
            return true

        case "Scroll to the bottom of a chat":
            conversation.jumpToBottom()
            return true

        case "Chat: Start New":
            _ = bringMainWindowForward()
            menuCoordinator.newChat()
            return true

        case "Chat: Create New Group":
            _ = bringMainWindowForward()
            inbox.openStartNewChat(multiSelect: true)
            return true

        case "Chat: Toggle Archive":
            let rows = inbox.targetRows()
            let allArchived = !rows.isEmpty && rows.allSatisfy(\.archived)
            Task { await inbox.archive(!allArchived) }
            return true

        case "Chat: Archive All Read":
            archiveAllReadInvocationCount += 1
            Task { await onArchiveAllRead() }
            return true

        case "Chat: Toggle Mark As Read":
            Task { await inbox.toggleRead() }
            return true

        case "Chat: Toggle Mute":
            Task { await inbox.toggleMute() }
            return true

        case "Chat: Toggle Pin":
            Task { await inbox.togglePin() }
            return true

        case "Remind Later":
            remindLaterInvocationCount += 1
            onRemindLater()
            return true

        case "Chat: Send File":
            attachFilesInvocationCount += 1
            onAttachFiles(activeComposer)
            return true

        case "Toggle Chat Info":
            conversation.toggleChatInfo()
            return true

        case "Open User Profile":
            Task { await conversation.showSenderCardForSelectedMessage() }
            return true

        case "Chat: Delete":
            guard conversation.roomID != nil else { return false }
            conversation.requestDeleteChat(info: conversation.chatInfo)
            return true

        case "Message: Quote & Reply":
            guard let selectedMessage,
                  let message = conversation.message(selectedMessage.id, from: selectedMessage.source),
                  let action = conversation.replyAction(for: message)
            else { return false }
            Task { await messageActions.perform(action, on: selectedMessage.id, from: selectedMessage.source) }
            return true

        case "Message: Quote or Edit Selected Message":
            if let selectedMessage,
               let message = conversation.message(selectedMessage.id, from: selectedMessage.source) {
                if message.mine, conversation.availableActions(for: message).actions.contains(.edit) {
                    Task { await messageActions.perform(.edit, on: selectedMessage.id, from: selectedMessage.source) }
                    return true
                }
                if let action = conversation.replyAction(for: message) {
                    Task { await messageActions.perform(action, on: selectedMessage.id, from: selectedMessage.source) }
                    return true
                }
            }
            conversation.editSelectedOrLast()
            return true

        case "Message: Edit":
            if let selectedMessage, selectedMessage.source == .thread {
                Task { await messageActions.perform(.edit, on: selectedMessage.id, from: .thread) }
            } else {
                conversation.editSelectedOrLast()
            }
            return true

        case "Message: Quick React":
            guard let selectedMessage else { return false }
            if selectedMessage.source == .chat {
                Task { await conversation.quickReactToSelected() }
            } else if let message = conversation.message(selectedMessage.id, from: selectedMessage.source),
                      conversation.availableActions(for: message).actions.contains(.react) {
                let key = conversation.preferences?.quickReaction ?? "❤️"
                Task { await conversation.react(to: selectedMessage.id, key: key) }
            }
            return true

        case "Message: Forward":
            if let selectedMessage, selectedMessage.source == .thread {
                Task { await messageActions.perform(.forward, on: selectedMessage.id, from: .thread) }
            } else {
                messageActions.forwardSelected()
            }
            return true

        case "Message: Open First Link":
            guard let selectedMessage else { return false }
            Task { await messageActions.perform(.openFirstLink, on: selectedMessage.id, from: selectedMessage.source) }
            return true

        case "Download Attachments":
            return downloadSelectedAttachments()

        case "Show Replies":
            guard let root = showRepliesTarget else { return false }
            conversation.openThread(root)
            return true

        case "Message: Send Later":
            messageActions.requestSendLater()
            return true

        case "Message: Send Message and Archive":
            activeComposer.submit(archive: true)
            return true

        case "Message: Record Audio":
            Task { await activeComposer.startVoiceRecording() }
            return true

        case "Message: Send GIF":
            return activeComposer.openGIFPicker()

        case "Message: Send Sticker":
            return activeComposer.openStickerPicker()

        case "Undo Pending Send":
            if let composer = heldComposer {
                Task { await composer.undoNewestHeld() }
            } else if inbox.toast?.canUndo == true {
                Task { await inbox.undo() }
            } else {
                fallbackUndoInvocationCount += 1
                onFallbackUndo()
            }
            return true

        case "Send Message":
            activeComposer.submit()
            return true

        case "Insert New Line":
            activeComposer.text.append("\n")
            return true

        default:
            return false
        }
    }

    @discardableResult
    public func downloadSelectedAttachments() -> Bool {
        let prefs = conversation.preferences ?? ComposerPreferences()
        let downloader = AttachmentDownloader(preferences: prefs)

        func downloadMessageAttachments(_ message: TimelineMessage) -> Bool {
            guard !message.viewOnce else { return false }
            var savedCount = 0
            var lastSavedName: String?
            if !message.galleryItems.isEmpty {
                for item in message.galleryItems where isLocalMediaStorePath(item.mediaPath) {
                    if let saved = try? downloader.download(
                        sourcePath: item.mediaPath,
                        suggestedName: item.fileName.isEmpty ? "attachment" : item.fileName,
                        mimeType: item.mimeType
                    ) {
                        savedCount += 1
                        lastSavedName = saved.lastPathComponent
                    }
                }
            } else if isLocalMediaStorePath(message.mediaPath) {
                if let saved = try? downloader.download(
                    sourcePath: message.mediaPath,
                    suggestedName: message.fileName.isEmpty ? "attachment" : message.fileName,
                    mimeType: message.mimeType
                ) {
                    savedCount += 1
                    lastSavedName = saved.lastPathComponent
                }
            }
            if savedCount == 1, let lastSavedName {
                conversation.onToast(String(localized: "Saved \(lastSavedName)"))
            } else if savedCount > 1 {
                conversation.onToast(String(localized: "Saved \(savedCount) files"))
            }
            return savedCount > 0
        }

        if let lightboxID = conversation.activeLightboxMessageID {
            for case let .message(msg) in conversation.items {
                if msg.id == lightboxID {
                    return downloadMessageAttachments(msg)
                }
                if let item = msg.galleryItems.first(where: { $0.id == lightboxID }),
                   !msg.viewOnce,
                   isLocalMediaStorePath(item.mediaPath),
                   let saved = try? downloader.download(
                       sourcePath: item.mediaPath,
                       suggestedName: item.fileName.isEmpty ? "attachment" : item.fileName,
                       mimeType: item.mimeType
                   ) {
                    conversation.onToast(String(localized: "Saved \(saved.lastPathComponent)"))
                    return true
                }
            }
        }
        guard let selectedMessage,
              let message = conversation.message(selectedMessage.id, from: selectedMessage.source)
        else {
            return false
        }
        return downloadMessageAttachments(message)
    }

    private func hasDownloadableAttachment(forLightboxID lightboxID: String) -> Bool {
        for case let .message(msg) in conversation.items where !msg.viewOnce {
            if msg.id == lightboxID {
                if !msg.galleryItems.isEmpty {
                    return msg.galleryItems.contains { isLocalMediaStorePath($0.mediaPath) }
                }
                return isLocalMediaStorePath(msg.mediaPath)
            }
            if let item = msg.galleryItems.first(where: { $0.id == lightboxID }) {
                return isLocalMediaStorePath(item.mediaPath)
            }
        }
        return false
    }
}

/// Injectable global key-down event monitor so tests can verify global shortcut registration without OS permissions.
@MainActor
public protocol GlobalKeyEventMonitoring: AnyObject {
    func start(handler: @escaping @MainActor (KeyChord) -> Void)
    func stop()
}

/// Production `NSEvent.addGlobalMonitorForEvents(matching: .keyDown)` adapter for `GlobalHotkeyMonitor`.
@MainActor
public final class AppKitGlobalKeyEventMonitor: GlobalKeyEventMonitoring {
    private var monitor: Any?

    public init() {}

    public func start(handler: @escaping @MainActor (KeyChord) -> Void) {
        guard monitor == nil else { return }
        monitor = NSEvent.addGlobalMonitorForEvents(matching: .keyDown) { event in
            guard let chord = Self.chord(from: event) else { return }
            Task { @MainActor in
                handler(chord)
            }
        }
    }

    public func stop() {
        if let monitor {
            NSEvent.removeMonitor(monitor)
            self.monitor = nil
        }
    }

    public static func chord(from event: NSEvent) -> KeyChord? {
        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        let keyName: String
        switch event.keyCode {
        case 36, 76: keyName = "enter"
        case 48: keyName = "tab"
        case 49: keyName = "space"
        case 51, 117: keyName = "backspace"
        case 53: keyName = "escape"
        case 123: keyName = "left"
        case 124: keyName = "right"
        case 125: keyName = "down"
        case 126: keyName = "up"
        default:
            if let fnKey = KeyChord.functionKeyName(
                forKeyCode: event.keyCode,
                charactersIgnoringModifiers: event.charactersIgnoringModifiers
            ) {
                keyName = fnKey
            } else {
                guard let chars = event.charactersIgnoringModifiers?.lowercased(), !chars.isEmpty else {
                    return nil
                }
                keyName = chars
            }
        }
        return KeyChord(
            key: keyName,
            command: flags.contains(.command),
            shift: flags.contains(.shift),
            option: flags.contains(.option),
            control: flags.contains(.control)
        )
    }
}

/// Watches `HotkeyRegistry.globalIDs` (`"Focus App"` and `"Focus App and Command Bar"`) and dispatches matching
/// global key chords through `HotkeyDispatcher` when enabled and unlocked (`02` §2.2).
@MainActor
public final class GlobalHotkeyMonitor {
    private let registry: HotkeyRegistry
    private let dispatcher: HotkeyDispatcher
    private let eventMonitor: any GlobalKeyEventMonitoring
    private var cancellables: Set<AnyCancellable> = []
    public private(set) var isMonitoring: Bool = false

    public init(
        registry: HotkeyRegistry,
        dispatcher: HotkeyDispatcher,
        eventMonitor: (any GlobalKeyEventMonitoring)? = nil
    ) {
        self.registry = registry
        self.dispatcher = dispatcher
        self.eventMonitor = eventMonitor ?? AppKitGlobalKeyEventMonitor()

        Publishers.CombineLatest3(
            registry.$globalIDs,
            registry.$overrides,
            registry.$disabledIDs
        )
        .sink { [weak self] globalIDs, overrides, disabledIDs in
            self?.refreshMonitoringState(
                globalIDs: globalIDs,
                overrides: overrides,
                disabledIDs: disabledIDs
            )
        }
        .store(in: &cancellables)

        refreshMonitoringState(
            globalIDs: registry.globalIDs,
            overrides: registry.overrides,
            disabledIDs: registry.disabledIDs
        )
    }

    public func stop() {
        if isMonitoring {
            eventMonitor.stop()
            isMonitoring = false
        }
    }

    @discardableResult
    public func handleKeyChord(_ chord: KeyChord) -> Bool {
        guard !registry.isLocked else { return false }
        for id in registry.globalIDs.sorted() {
            guard let def = registry.definition(for: id),
                  def.supportsGlobal,
                  registry.isEnabled(id),
                  registry.chords(for: id).contains(chord)
            else { continue }
            return dispatcher.perform(id)
        }
        return false
    }

    private func refreshMonitoringState(
        globalIDs: Set<String>,
        overrides: [String: [KeyChord]],
        disabledIDs: Set<String>
    ) {
        let hasActiveGlobal = globalIDs.contains { id in
            guard !disabledIDs.contains(id),
                  let def = registry.definition(for: id),
                  def.supportsGlobal
            else { return false }
            let chords = overrides[id] ?? def.defaultChords
            return !chords.isEmpty
        }
        if hasActiveGlobal && !isMonitoring {
            isMonitoring = true
            eventMonitor.start { [weak self] chord in
                _ = self?.handleKeyChord(chord)
            }
        } else if !hasActiveGlobal && isMonitoring {
            stop()
        }
    }
}
