// Copyright 2026 VitruvianSoftware
// SPDX-License-Identifier: AGPL-3.0-or-later

import Combine
import Foundation

/// Top-level pane in Courier's two-column Settings window (`⌘,`, `PrefsPanes.tsx`).
public enum SettingsPaneID: String, CaseIterable, Codable, Sendable, Identifiable {
    case general
    case appearance
    case notifications
    case accounts
    case hotkeys
    case quickReplies
    case bridges
    case storage
    case about

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .general: String(localized: "General")
        case .appearance: String(localized: "Appearance")
        case .notifications: String(localized: "Notifications")
        case .accounts: String(localized: "Accounts")
        case .hotkeys: String(localized: "Hotkeys")
        case .quickReplies: String(localized: "Quick Replies")
        case .bridges: String(localized: "Bridges")
        case .storage: String(localized: "Storage")
        case .about: String(localized: "About")
        }
    }

    public var symbolName: String {
        switch self {
        case .general: "gearshape"
        case .appearance: "paintbrush"
        case .notifications: "bell.badge"
        case .accounts: "person.2.crop.square.stack"
        case .hotkeys: "command"
        case .quickReplies: "text.bubble"
        case .bridges: "point.3.connected.trianglepath.dotted"
        case .storage: "internaldrive"
        case .about: "info.circle"
        }
    }
}

/// Optional tag pill shown beside experimental settings (`PreferenceTags.tsx`).
public enum SettingBadge: String, Codable, Equatable, Sendable {
    case labs

    public var label: String {
        switch self {
        case .labs: String(localized: "Labs")
        }
    }

    public var tooltip: String {
        switch self {
        case .labs: String(localized: "Experimental and subject to change")
        }
    }
}

/// Metadata entry for a single setting in Courier's Settings catalog (`preference-definitions.tsx`).
public struct SettingDefinition: Equatable, Sendable, Identifiable {
    public let id: String
    public let pane: SettingsPaneID
    public let section: String
    public let title: String
    public let keywords: [String]
    public let badge: SettingBadge?

    public init(
        id: String,
        pane: SettingsPaneID,
        section: String,
        title: String,
        keywords: [String],
        badge: SettingBadge? = nil
    ) {
        self.id = id
        self.pane = pane
        self.section = section
        self.title = title
        self.keywords = keywords
        self.badge = badge
    }

    /// Breadcrumb string shown in `SearchSuggestions` (`"Pane → Setting"`).
    public var breadcrumbTitle: String {
        "\(pane.title) → \(title)"
    }
}

/// Single source of truth for Settings navigation, search suggestions (`SearchSuggestions.tsx`), and deep-linking to controls.
@MainActor
public final class SettingsNavigationModel: ObservableObject {
    @Published public var selectedPane: SettingsPaneID = .general
    @Published public var searchQuery: String = ""
    @Published public var highlightedSettingID: String?
    @Published public var selectedAccountKey: String?
    @Published public var isPresentingProblemReport: Bool = false

    private weak var boundAccountsAndBridges: AccountsAndBridgesModel?

    public init(selectedPane: SettingsPaneID = .general) {
        self.selectedPane = selectedPane
    }

    public func bind(accountsAndBridges: AccountsAndBridgesModel) {
        boundAccountsAndBridges = accountsAndBridges
        if let selectedAccountKey {
            accountsAndBridges.selectedAccountKey = selectedAccountKey
        }
    }

    /// Every visible setting across all 8 Settings panes. Panes read titles and anchor IDs from this catalog so search and UI stay in lockstep.
    public static let allSettings: [SettingDefinition] = [
        // MARK: General
        SettingDefinition(
            id: "general.incognito",
            pane: .general,
            section: "Privacy",
            title: "Incognito mode",
            keywords: ["incognito", "read receipts", "unread", "privacy"]
        ),
        SettingDefinition(
            id: "general.showTyping",
            pane: .general,
            section: "Privacy",
            title: "Show recipients I’m typing",
            keywords: ["typing", "indicator", "privacy", "recipients"]
        ),
        SettingDefinition(
            id: "general.showIncognitoMark",
            pane: .general,
            section: "Privacy",
            title: "Show the incognito mark in the message box",
            keywords: ["incognito", "mark", "indicator", "composer"]
        ),
        SettingDefinition(
            id: "general.remindDefault",
            pane: .general,
            section: "Reminders",
            title: "Remind me",
            keywords: ["reminder", "if no reply", "always"]
        ),
        SettingDefinition(
            id: "general.archiveAfterReminder",
            pane: .general,
            section: "Reminders",
            title: "Archive a chat when I set a reminder on it",
            keywords: ["reminder", "archive"]
        ),
        SettingDefinition(
            id: "general.timeSuggestions",
            pane: .general,
            section: "Reminders",
            title: "Time suggestions",
            keywords: ["time suggestions", "presets", "remind me", "send later", "tomorrow", "evening"]
        ),
        SettingDefinition(
            id: "general.markReadOnArchive",
            pane: .general,
            section: "Archiving",
            title: "Mark chats read when I archive them",
            keywords: ["archive", "mark read", "unread"]
        ),
        SettingDefinition(
            id: "general.afterArchive",
            pane: .general,
            section: "Archiving",
            title: "After archiving the open chat",
            keywords: ["after archive", "next chat", "previous chat", "close"]
        ),
        SettingDefinition(
            id: "general.afterToggleRead",
            pane: .general,
            section: "Archiving",
            title: "After marking the open chat read or unread",
            keywords: ["after mark as read", "unread", "next chat"]
        ),
        SettingDefinition(
            id: "general.autoArchive",
            pane: .general,
            section: "Archiving",
            title: "Archive chats by themselves",
            keywords: ["auto-archive", "automatic", "after reply", "after read"]
        ),
        SettingDefinition(
            id: "general.bulkArchive",
            pane: .general,
            section: "Archiving",
            title: "Archive older chats",
            keywords: ["bulk archive", "sweep", "older chats", "archive all"]
        ),
        SettingDefinition(
            id: "general.doubleClickMessage",
            pane: .general,
            section: "Messages & Composer",
            title: "On double-clicking a message",
            keywords: ["double-click", "message", "reply", "react", "forward"]
        ),
        SettingDefinition(
            id: "general.undoSend",
            pane: .general,
            section: "Messages & Composer",
            title: "Allow undo send (⌘Z) for",
            keywords: ["undo send", "hold", "delay", "pending"]
        ),
        SettingDefinition(
            id: "general.clickPendingToUndo",
            pane: .general,
            section: "Messages & Composer",
            title: "Click pending messages to undo send",
            keywords: ["undo send", "pending", "click"]
        ),
        SettingDefinition(
            id: "general.sendLaterDefault",
            pane: .general,
            section: "Messages & Composer",
            title: "Default for send later",
            keywords: ["send later", "scheduled", "if no reply"]
        ),
        SettingDefinition(
            id: "general.upArrow",
            pane: .general,
            section: "Messages & Composer",
            title: "Press ↑ in the composer to",
            keywords: ["up arrow", "edit last", "focus messages", "composer"]
        ),
        SettingDefinition(
            id: "general.copyWithTimestamps",
            pane: .general,
            section: "Messages & Composer",
            title: "Include timestamps when copying messages with ⌘C",
            keywords: ["copy", "timestamps", "clipboard"]
        ),
        SettingDefinition(
            id: "general.enableEmojiAutocomplete",
            pane: .general,
            section: "Messages & Composer",
            title: "Enable emoji autocomplete",
            keywords: ["emoji", "autocomplete", "colon", "composer"]
        ),
        SettingDefinition(
            id: "general.disableEmoticonReplacement",
            pane: .general,
            section: "Messages & Composer",
            title: "Disable automatic replacement of emoticons with emojis",
            keywords: ["emoticon", "emoji", "replacement", "composer"]
        ),
        SettingDefinition(
            id: "general.autoSendGIFs",
            pane: .general,
            section: "Messages & Composer",
            title: "Automatically send GIFs after selection",
            keywords: ["gif", "automatically send", "composer"]
        ),
        SettingDefinition(
            id: "general.autoPlayNextVoiceNote",
            pane: .general,
            section: "Messages & Composer",
            title: "Automatically play the next voice note",
            keywords: ["voice note", "audio", "autoplay"]
        ),
        SettingDefinition(
            id: "general.preferredMicrophone",
            pane: .general,
            section: "Messages & Composer",
            title: "Microphone",
            keywords: ["microphone", "audio", "input", "voice note"]
        ),
        SettingDefinition(
            id: "general.autoCopyOTP",
            pane: .general,
            section: "Messages & Composer",
            title: "Auto copy OTP/2FA codes",
            keywords: ["otp", "2fa", "verification code", "auto copy", "passcode"]
        ),
        SettingDefinition(
            id: "general.downloadsLocation",
            pane: .general,
            section: "Downloads",
            title: "Downloads location",
            keywords: ["downloads", "folder", "save", "location", "path"]
        ),
        SettingDefinition(
            id: "general.alwaysAskWhereToSave",
            pane: .general,
            section: "Downloads",
            title: "Always ask where to save files before downloading",
            keywords: ["downloads", "save", "ask", "files"]
        ),
        SettingDefinition(
            id: "general.openAtLogin",
            pane: .general,
            section: "Startup & Security",
            title: "Open Courier at login",
            keywords: ["login item", "launch at login", "startup", "open at login"]
        ),
        SettingDefinition(
            id: "general.keepMinimizedOnLaunch",
            pane: .general,
            section: "Startup & Security",
            title: "Keep Courier minimized on launch",
            keywords: ["minimized", "launch", "startup", "hidden"]
        ),
        SettingDefinition(
            id: "general.quitOnClose",
            pane: .general,
            section: "Startup & Security",
            title: "Quit Courier when closing the main window",
            keywords: ["quit", "close window", "tray", "minimize"]
        ),
        SettingDefinition(
            id: "general.requireTouchID",
            pane: .general,
            section: "Startup & Security",
            title: "Require Touch ID authentication on launch",
            keywords: ["touch id", "lock", "biometric", "password", "security", "auto-lock"]
        ),
        SettingDefinition(
            id: "general.lockTimeout",
            pane: .general,
            section: "Startup & Security",
            title: "Lock Courier after",
            keywords: ["touch id", "lock timeout", "idle", "auto-lock"]
        ),
        SettingDefinition(
            id: "general.timeFormat",
            pane: .general,
            section: "Startup & Security",
            title: "Time Format",
            keywords: ["time format", "12-hour", "24-hour", "clock"]
        ),

        // MARK: Appearance
        SettingDefinition(
            id: "appearance.themeMode",
            pane: .appearance,
            section: "Theme & Wallpaper",
            title: "Theme",
            keywords: ["theme", "dark mode", "light mode", "system", "auto", "colour scheme"]
        ),
        SettingDefinition(
            id: "appearance.themePreset",
            pane: .appearance,
            section: "Theme & Wallpaper",
            title: "Chat colour theme",
            keywords: ["chat theme", "theme", "preset", "colour", "color", "bubbles", "accent", "browse"]
        ),
        SettingDefinition(
            id: "appearance.wallpaper",
            pane: .appearance,
            section: "Theme & Wallpaper",
            title: "Chat wallpaper",
            keywords: ["wallpaper", "chat background", "background", "pattern", "opacity", "blur", "honeycomb"]
        ),
        SettingDefinition(
            id: "appearance.appIcon",
            pane: .appearance,
            section: "App Icon",
            title: "App icon",
            keywords: ["app icon", "dock icon", "icon", "badge", "classic", "midnight", "pride", "oled"]
        ),
        SettingDefinition(
            id: "appearance.fontSize",
            pane: .appearance,
            section: "Display & Typography",
            title: "Font size",
            keywords: ["font size", "text size", "typography", "small", "default", "large", "extra large"]
        ),
        SettingDefinition(
            id: "appearance.zoomLevel",
            pane: .appearance,
            section: "Display & Typography",
            title: "Zoom level",
            keywords: ["zoom", "scale", "zoom in", "zoom out", "actual size"]
        ),
        SettingDefinition(
            id: "appearance.reduceTransparency",
            pane: .appearance,
            section: "Display & Typography",
            title: "Reduce transparency",
            keywords: ["reduce transparency", "transparency", "blur", "vibrancy", "contrast"]
        ),
        SettingDefinition(
            id: "appearance.enableMessageAnimations",
            pane: .appearance,
            section: "Display & Typography",
            title: "Enable message animations",
            keywords: ["message animations", "animations", "effects", "motion"]
        ),
        SettingDefinition(
            id: "appearance.balanceMessageText",
            pane: .appearance,
            section: "Display & Typography",
            title: "Balance message text",
            keywords: ["balance message text", "text wrap", "balanced", "widows"]
        ),
        SettingDefinition(
            id: "appearance.usePointerCursor",
            pane: .appearance,
            section: "Display & Typography",
            title: "Use pointer cursor on interactive elements",
            keywords: ["pointer cursor", "cursor", "hand", "hover"]
        ),
        SettingDefinition(
            id: "appearance.showFeedbackWidget",
            pane: .appearance,
            section: "Display & Typography",
            title: "Show feedback button in sidebar",
            keywords: ["feedback widget", "feedback", "button", "report"]
        ),
        SettingDefinition(
            id: "appearance.redactNamesAndPictures",
            pane: .appearance,
            section: "Privacy & Screenshots",
            title: "Redact names and pictures",
            keywords: ["redact", "privacy", "blur avatars", "screenshots", "demo mode", "hide names"]
        ),
        SettingDefinition(
            id: "appearance.customCSS",
            pane: .appearance,
            section: "Custom CSS",
            title: "Custom CSS",
            keywords: ["custom css", "stylesheet", "css", "theme file"]
        ),
        SettingDefinition(
            id: "appearance.showSpaceBar",
            pane: .appearance,
            section: "Chat list",
            title: "Show the space bar",
            keywords: ["space bar", "sidebar", "spaces"]
        ),
        SettingDefinition(
            id: "appearance.regularPinnedRows",
            pane: .appearance,
            section: "Chat list",
            title: "Use regular style for pinned chats",
            keywords: ["pinned chats", "regular style", "rows", "pin"]
        ),
        SettingDefinition(
            id: "appearance.showUnreadCounts",
            pane: .appearance,
            section: "Chat list",
            title: "Show number of unread messages",
            keywords: ["unread", "counts", "badge"]
        ),
        SettingDefinition(
            id: "appearance.showPreviews",
            pane: .appearance,
            section: "Chat list",
            title: "Show message previews",
            keywords: ["previews", "chat list", "snippet"]
        ),
        SettingDefinition(
            id: "appearance.compactList",
            pane: .appearance,
            section: "Chat list",
            title: "Compact chat list",
            keywords: ["compact", "density", "chat list"]
        ),
        SettingDefinition(
            id: "appearance.showNetworkIcons",
            pane: .appearance,
            section: "Chat list",
            title: "Show network icons",
            keywords: ["network icons", "badge", "logo"]
        ),
        SettingDefinition(
            id: "appearance.colorNetworkIcons",
            pane: .appearance,
            section: "Chat list",
            title: "Colorize network icons",
            keywords: ["colorize", "colour", "network icons"]
        ),
        SettingDefinition(
            id: "appearance.hoverAction",
            pane: .appearance,
            section: "Chat list",
            title: "Button on a chat you point at",
            keywords: ["hover", "archive", "mark read", "menu"]
        ),
        SettingDefinition(
            id: "appearance.doubleClickChat",
            pane: .appearance,
            section: "Chat list",
            title: "On double-clicking a chat",
            keywords: ["double-click", "open in new window", "archive", "mute", "low priority"]
        ),
        SettingDefinition(
            id: "appearance.showMessageTimestamps",
            pane: .appearance,
            section: "Conversation",
            title: "Show message timestamps",
            keywords: ["timestamps", "time", "messages", "conversation"]
        ),
        SettingDefinition(
            id: "appearance.hideDeletedMessages",
            pane: .appearance,
            section: "Conversation",
            title: "Hide deleted messages",
            keywords: ["deleted messages", "redacted", "hide"]
        ),
        SettingDefinition(
            id: "appearance.showMembershipEvents",
            pane: .appearance,
            section: "Conversation",
            title: "Show membership events",
            keywords: ["membership", "chat updates", "joined", "left", "timeline"]
        ),
        SettingDefinition(
            id: "appearance.loadExternalEmbeds",
            pane: .appearance,
            section: "Conversation",
            title: "Load external embeds automatically",
            keywords: ["embeds", "link previews", "external"]
        ),
        SettingDefinition(
            id: "appearance.quickReaction",
            pane: .appearance,
            section: "Conversation",
            title: "Quick reaction emoji",
            keywords: ["quick reaction", "emoji", "react"]
        ),
        SettingDefinition(
            id: "appearance.enableSpellcheck",
            pane: .appearance,
            section: "Composer",
            title: "Enable spellcheck",
            keywords: ["spellcheck", "spelling", "composer"]
        ),
        SettingDefinition(
            id: "appearance.showFormattingMenu",
            pane: .appearance,
            section: "Composer",
            title: "Show formatting menu",
            keywords: ["formatting", "bold", "italic", "composer"]
        ),
        SettingDefinition(
            id: "appearance.disableOutgoingLinkPreviews",
            pane: .appearance,
            section: "Composer",
            title: "Disable link previews in outgoing messages",
            keywords: ["link previews", "outgoing", "composer"]
        ),
        SettingDefinition(
            id: "appearance.primaryComposerButton",
            pane: .appearance,
            section: "Composer",
            title: "Primary composer button",
            keywords: ["primary composer button", "composer", "emoji", "gif", "attachment", "send later"]
        ),
        SettingDefinition(
            id: "appearance.secondaryComposerButton",
            pane: .appearance,
            section: "Composer",
            title: "Secondary composer button",
            keywords: ["secondary composer button", "composer", "voice", "record audio", "gif", "attachment"]
        ),
        SettingDefinition(
            id: "appearance.showMenuBarIcon",
            pane: .appearance,
            section: "System",
            title: "Show menu bar icon",
            keywords: ["menu bar", "tray", "status item", "icon"]
        ),
        SettingDefinition(
            id: "appearance.dockBadgeCount",
            pane: .appearance,
            section: "System",
            title: "Dock badge count",
            keywords: ["dock", "badge", "unread chats", "all chats", "count"]
        ),

        // MARK: Notifications
        SettingDefinition(
            id: "notifications.messages",
            pane: .notifications,
            section: "Alert Types",
            title: "Message notifications",
            keywords: ["direct messages", "dm", "alerts", "sound"]
        ),
        SettingDefinition(
            id: "notifications.groups",
            pane: .notifications,
            section: "Alert Types",
            title: "Group notifications",
            keywords: ["groups", "group chat", "alerts", "sound"]
        ),
        SettingDefinition(
            id: "notifications.requests",
            pane: .notifications,
            section: "Alert Types",
            title: "Notify me about message requests",
            keywords: ["message requests", "strangers", "requests"]
        ),
        SettingDefinition(
            id: "notifications.reactions",
            pane: .notifications,
            section: "Alert Types",
            title: "Notify on reactions",
            keywords: ["reactions", "emoji", "likes"]
        ),
        SettingDefinition(
            id: "notifications.typing",
            pane: .notifications,
            section: "Alert Types",
            title: "Notify when someone starts typing",
            keywords: ["typing", "starts typing"],
            badge: .labs
        ),
        SettingDefinition(
            id: "notifications.inFocus",
            pane: .notifications,
            section: "Alert Types",
            title: "Notify even when chat is in focus",
            keywords: ["in focus", "active", "foreground"]
        ),
        SettingDefinition(
            id: "notifications.delay",
            pane: .notifications,
            section: "Timing & Codes",
            title: "Delay notifications for",
            keywords: ["delay", "hold", "wait", "batch"],
            badge: .labs
        ),
        SettingDefinition(
            id: "notifications.repeatUnread",
            pane: .notifications,
            section: "Timing & Codes",
            title: "Repeat unread notifications",
            keywords: ["repeat", "unread", "remind"]
        ),
        SettingDefinition(
            id: "notifications.autoCopyOTP",
            pane: .notifications,
            section: "Timing & Codes",
            title: "Auto copy OTP/2FA codes",
            keywords: ["otp", "2fa", "verification", "copy code"]
        ),
        SettingDefinition(
            id: "notifications.soundEffectsMode",
            pane: .notifications,
            section: "Sound Effects",
            title: "Play sound effects",
            keywords: ["sound effects", "sent", "received", "audio"]
        ),
        SettingDefinition(
            id: "notifications.soundEffectsVolume",
            pane: .notifications,
            section: "Sound Effects",
            title: "Sound effects volume",
            keywords: ["volume", "sound effects", "loudness"]
        ),
        SettingDefinition(
            id: "notifications.accountOverrides",
            pane: .notifications,
            section: "Per-Account Overrides",
            title: "Account notification settings",
            keywords: ["account", "per-account", "previews", "mute account"]
        ),
        SettingDefinition(
            id: "notifications.systemSettings",
            pane: .notifications,
            section: "System Notification Center",
            title: "Open Notifications in System Settings",
            keywords: ["system settings", "macos", "permissions"]
        ),
        SettingDefinition(
            id: "notifications.restartCenter",
            pane: .notifications,
            section: "System Notification Center",
            title: "Restart Notification Center",
            keywords: ["restart notification center", "fix notifications", "reset"]
        ),

        // MARK: Accounts
        SettingDefinition(
            id: "accounts.connectedNetworks",
            pane: .accounts,
            section: "Accounts",
            title: "Connected accounts",
            keywords: ["accounts", "networks", "whatsapp", "signal", "telegram", "slack", "google messages", "remove account", "reconnect"]
        ),
        SettingDefinition(
            id: "accounts.subAccounts",
            pane: .accounts,
            section: "Sub-Accounts",
            title: "Slack channels, WhatsApp Communities, and Telegram Topics",
            keywords: ["sub-accounts", "channels", "communities", "topics", "spaces"]
        ),
        SettingDefinition(
            id: "accounts.dockCleanup",
            pane: .accounts,
            section: "System",
            title: "Remove official app from Dock",
            keywords: ["dock", "official app", "remove from dock"]
        ),

        // MARK: Hotkeys
        SettingDefinition(
            id: "hotkeys.shortcuts",
            pane: .hotkeys,
            section: "Shortcuts",
            title: "Keyboard shortcuts",
            keywords: ["hotkeys", "shortcuts", "keybindings", "record shortcut", "global"]
        ),
        SettingDefinition(
            id: "hotkeys.textsPreset",
            pane: .hotkeys,
            section: "Shortcuts",
            title: "Switch to Texts.app keybindings",
            keywords: ["texts.app", "preset", "keybindings", "revert"]
        ),

        // MARK: Quick Replies
        SettingDefinition(
            id: "quickReplies.savedReplies",
            pane: .quickReplies,
            section: "Quick Replies",
            title: "Saved quick replies",
            keywords: ["quick replies", "templates", "canned responses", "semicolon"]
        ),
        SettingDefinition(
            id: "quickReplies.variables",
            pane: .quickReplies,
            section: "Quick Replies",
            title: "Template variables",
            keywords: ["variables", "first_name", "last_name", "full_name", "username", "phone_number", "email"]
        ),

        // MARK: Bridges
        SettingDefinition(
            id: "bridges.status",
            pane: .bridges,
            section: "Bridges",
            title: "On-device bridges",
            keywords: ["bridges", "mautrix", "restart bridge", "copy info as json", "version", "state"]
        ),

        // MARK: Storage
        SettingDefinition(
            id: "storage.overview",
            pane: .storage,
            section: "Disk Usage on This Mac",
            title: "Local disk usage",
            keywords: ["storage", "disk", "space", "usage", "bytes", "database", "photos", "videos", "audio", "files"]
        ),
        SettingDefinition(
            id: "storage.cleanupByAge",
            pane: .storage,
            section: "Free Up Space",
            title: "Delete media older than",
            keywords: ["delete media", "cleanup", "clear cache", "older than", "free up space", "1 week", "1 month", "3 months", "1 year"]
        ),
        SettingDefinition(
            id: "storage.byRoom",
            pane: .storage,
            section: "Storage by Chat",
            title: "Storage by chat",
            keywords: ["storage by chat", "delete media in this chat", "per chat", "room storage"]
        ),

        // MARK: About
        SettingDefinition(
            id: "about.version",
            pane: .about,
            section: "About Courier",
            title: "Courier version & build",
            keywords: ["version", "build", "about courier"]
        ),
        SettingDefinition(
            id: "about.changelog",
            pane: .about,
            section: "About Courier",
            title: "View Changelog",
            keywords: ["changelog", "release notes", "what's new"]
        ),
        SettingDefinition(
            id: "about.reportProblem",
            pane: .about,
            section: "Diagnostics",
            title: "Report a Problem…",
            keywords: ["report a problem", "diagnostics", "logs", "bug"]
        ),
        SettingDefinition(
            id: "about.keyboardShortcuts",
            pane: .about,
            section: "Reference",
            title: "Keyboard Shortcuts",
            keywords: ["keyboard shortcuts", "reference", "cheat sheet"]
        ),
        SettingDefinition(
            id: "about.privacy",
            pane: .about,
            section: "Privacy & Legal",
            title: "Privacy & Security",
            keywords: ["privacy", "security", "on-device", "local"]
        ),
        SettingDefinition(
            id: "about.legalNotices",
            pane: .about,
            section: "Privacy & Legal",
            title: "Legal Notices",
            keywords: ["legal", "licenses", "open source", "mit", "mpl", "agpl"]
        ),
    ]

    public static let definitionsByID: [String: SettingDefinition] = Dictionary(
        uniqueKeysWithValues: allSettings.map { ($0.id, $0) }
    )

    /// Every `.settingAnchor(...)` identifier attached to a view across the 8 Settings panes.
    public static let anchoredSettingIDs: Set<String> = [
        // GeneralSettingsPane
        "general.incognito",
        "general.showTyping",
        "general.showIncognitoMark",
        "general.remindDefault",
        "general.archiveAfterReminder",
        "general.timeSuggestions",
        "general.markReadOnArchive",
        "general.afterArchive",
        "general.afterToggleRead",
        "general.autoArchive",
        "general.bulkArchive",
        "general.doubleClickMessage",
        "general.undoSend",
        "general.clickPendingToUndo",
        "general.sendLaterDefault",
        "general.upArrow",
        "general.copyWithTimestamps",
        "general.enableEmojiAutocomplete",
        "general.disableEmoticonReplacement",
        "general.autoSendGIFs",
        "general.autoPlayNextVoiceNote",
        "general.preferredMicrophone",
        "general.autoCopyOTP",
        "general.downloadsLocation",
        "general.alwaysAskWhereToSave",
        "general.openAtLogin",
        "general.keepMinimizedOnLaunch",
        "general.quitOnClose",
        "general.requireTouchID",
        "general.lockTimeout",
        "general.timeFormat",
        // AppearanceSettingsPane
        "appearance.themeMode",
        "appearance.themePreset",
        "appearance.wallpaper",
        "appearance.appIcon",
        "appearance.fontSize",
        "appearance.zoomLevel",
        "appearance.reduceTransparency",
        "appearance.enableMessageAnimations",
        "appearance.balanceMessageText",
        "appearance.usePointerCursor",
        "appearance.showFeedbackWidget",
        "appearance.redactNamesAndPictures",
        "appearance.customCSS",
        "appearance.showSpaceBar",
        "appearance.regularPinnedRows",
        "appearance.showUnreadCounts",
        "appearance.showPreviews",
        "appearance.compactList",
        "appearance.showNetworkIcons",
        "appearance.colorNetworkIcons",
        "appearance.hoverAction",
        "appearance.doubleClickChat",
        "appearance.showMessageTimestamps",
        "appearance.hideDeletedMessages",
        "appearance.showMembershipEvents",
        "appearance.loadExternalEmbeds",
        "appearance.quickReaction",
        "appearance.enableSpellcheck",
        "appearance.showFormattingMenu",
        "appearance.disableOutgoingLinkPreviews",
        "appearance.primaryComposerButton",
        "appearance.secondaryComposerButton",
        "appearance.showMenuBarIcon",
        "appearance.dockBadgeCount",
        // NotificationsSettingsPane
        "notifications.messages",
        "notifications.groups",
        "notifications.requests",
        "notifications.reactions",
        "notifications.typing",
        "notifications.inFocus",
        "notifications.delay",
        "notifications.repeatUnread",
        "notifications.autoCopyOTP",
        "notifications.soundEffectsMode",
        "notifications.soundEffectsVolume",
        "notifications.accountOverrides",
        "notifications.systemSettings",
        "notifications.restartCenter",
        // AccountsSettingsPane
        "accounts.connectedNetworks",
        "accounts.subAccounts",
        "accounts.dockCleanup",
        // HotkeysSettingsPane
        "hotkeys.shortcuts",
        "hotkeys.textsPreset",
        // QuickRepliesSettingsPane
        "quickReplies.savedReplies",
        "quickReplies.variables",
        // BridgesSettingsPane
        "bridges.status",
        // StorageSettingsPane
        "storage.overview",
        "storage.cleanupByAge",
        "storage.byRoom",
        // AboutSettingsPane
        "about.version",
        "about.changelog",
        "about.reportProblem",
        "about.keyboardShortcuts",
        "about.privacy",
        "about.legalNotices",
    ]

    public static func title(for id: String) -> String {
        definitionsByID[id]?.title ?? id
    }

    public static func definition(for id: String) -> SettingDefinition? {
        definitionsByID[id]
    }

    /// Matching settings for `searchQuery`, matching against `title`, `section`, `pane.title`, and `keywords`.
    public var suggestions: [SettingDefinition] {
        let trimmed = searchQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return [] }
        let foldedQuery = Self.fold(trimmed)
        let queryWords = foldedQuery.split(whereSeparator: \.isWhitespace).map(String.init)
        guard !queryWords.isEmpty else { return [] }

        return Self.allSettings.filter { setting in
            let haystack = Self.fold(
                ([setting.title, setting.section, setting.pane.title] + setting.keywords)
                    .joined(separator: " ")
            )
            if haystack.contains(foldedQuery) {
                return true
            }
            return queryWords.allSatisfy { haystack.contains($0) }
        }
    }

    public func jump(to setting: SettingDefinition) {
        guard AppLockGate.shared.canPerform(.settingsChange) else { return }
        selectedPane = setting.pane
        highlightedSettingID = setting.id
        searchQuery = ""
    }

    public func openPane(_ pane: SettingsPaneID, accountKey: String? = nil) {
        guard AppLockGate.shared.canPerform(.settingsChange) else { return }
        selectedPane = pane
        if let accountKey {
            selectedAccountKey = accountKey
            boundAccountsAndBridges?.selectedAccountKey = accountKey
        }
    }

    private static func fold(_ text: String) -> String {
        text.folding(options: [.caseInsensitive, .diacriticInsensitive, .widthInsensitive], locale: nil)
    }
}
