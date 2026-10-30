// Copyright 2026 VitruvianSoftware
// SPDX-License-Identifier: AGPL-3.0-or-later

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
        HotkeyDefinition(
            id: "Undo Pending Send",
            title: "Undo Pending Send",
            category: "Message",
            defaultChords: [KeyChord(key: "z", command: true)]
        ),

        // Composer
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
    }

    public func definition(for id: String) -> HotkeyDefinition? {
        Self.allDefinitions.first { $0.id == id }
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
