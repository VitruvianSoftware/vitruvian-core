// Copyright 2026 VitruvianSoftware
// SPDX-License-Identifier: AGPL-3.0-or-later

import Combine
import Foundation

public enum CommandBarMode: String, Equatable, Sendable {
    case commands
    case recentChats
}

@MainActor
public final class CommandBarModel: ObservableObject {
    public static let maxRecentCommands = 8
    private static let recentCommandsDefaultsKey = "courier.commandBar.recentCommandIDs"

    @Published public private(set) var isPresented: Bool = false
    @Published public var query: String = "" {
        didSet {
            selectedIndex = 0
        }
    }
    @Published public private(set) var mode: CommandBarMode = .commands
    @Published public private(set) var breadcrumb: [CourierCommand] = []
    @Published public var selectedIndex: Int = 0
    @Published public private(set) var recentCommandIDs: [String]
    @Published public var pendingConfirmation: CourierCommand?
    @Published public var statusBanner: String?

    private let defaults: UserDefaults
    private var lifecycle: SystemLifecycleModel?
    public var commandsProvider: @MainActor () -> [CourierCommand]
    public var recentChatsProvider: @MainActor () -> [InboxRow]
    public var onSelectRecentChat: @MainActor (String) -> Void
    private var lockCancellable: AnyCancellable?

    public init(
        defaults: UserDefaults = .standard,
        lifecycle: SystemLifecycleModel? = nil,
        commandsProvider: @escaping @MainActor () -> [CourierCommand] = { [] },
        recentChatsProvider: @escaping @MainActor () -> [InboxRow] = { [] },
        onSelectRecentChat: @escaping @MainActor (String) -> Void = { _ in }
    ) {
        self.defaults = defaults
        self.lifecycle = lifecycle
        self.commandsProvider = commandsProvider
        self.recentChatsProvider = recentChatsProvider
        self.onSelectRecentChat = onSelectRecentChat

        if let saved = defaults.stringArray(forKey: Self.recentCommandsDefaultsKey) {
            self.recentCommandIDs = Array(saved.prefix(Self.maxRecentCommands))
        } else {
            self.recentCommandIDs = []
        }

        lifecycle?.onLock { [weak self] in
            self?.close()
        }

        self.lockCancellable = NotificationCenter.default
            .publisher(for: SystemLifecycleModel.didLockNotification)
            .sink { [weak self] notification in
                guard let self else { return }
                if let lockedLifecycle = notification.object as? SystemLifecycleModel {
                    self.lifecycle = lockedLifecycle
                }
                self.close()
            }
    }

    public var isLocked: Bool {
        if let lifecycle, lifecycle.isLocked {
            return true
        }
        return !AppLockGate.shared.canPerform(.other, lifecycle: lifecycle)
    }

    public func open(initialQuery: String = "") {
        guard !isLocked else { return }
        mode = .commands
        breadcrumb = []
        pendingConfirmation = nil
        statusBanner = nil
        query = initialQuery
        selectedIndex = 0
        isPresented = true
    }

    public func openInRecentChatsMode(initialQuery: String = "") {
        guard !isLocked else { return }
        mode = .recentChats
        breadcrumb = []
        pendingConfirmation = nil
        statusBanner = nil
        query = initialQuery
        selectedIndex = 0
        isPresented = true
    }

    public func toggle() {
        if isPresented {
            close()
        } else {
            open()
        }
    }

    public func close() {
        isPresented = false
        query = ""
        mode = .commands
        breadcrumb = []
        selectedIndex = 0
        pendingConfirmation = nil
        statusBanner = nil
    }

    @discardableResult
    public func handleBackspaceOnEmptyQuery() -> Bool {
        guard query.isEmpty else { return false }
        if mode == .recentChats {
            mode = .commands
            selectedIndex = 0
            return true
        }
        guard !breadcrumb.isEmpty else { return false }
        breadcrumb.removeLast()
        selectedIndex = 0
        return true
    }

    public func popBreadcrumbToRoot() {
        mode = .commands
        breadcrumb = []
        query = ""
        selectedIndex = 0
    }

    public func popBreadcrumb(to index: Int) {
        guard index >= 0, index < breadcrumb.count else { return }
        breadcrumb = Array(breadcrumb.prefix(index + 1))
        query = ""
        selectedIndex = 0
    }

    public func moveSelection(delta: Int) {
        let count = mode == .recentChats ? displayedRecentChats.count : displayedCommands.count
        guard count > 0 else {
            selectedIndex = 0
            return
        }
        selectedIndex = (selectedIndex + delta + count) % count
    }

    public var activeCommandPool: [CourierCommand] {
        if let currentParent = breadcrumb.last {
            return currentParent.children
        }
        return commandsProvider()
    }

    public var displayedCommands: [CourierCommand] {
        let pool = activeCommandPool
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()

        if trimmed.isEmpty {
            guard breadcrumb.isEmpty else { return pool }
            var recentRank: [String: Int] = [:]
            for (idx, id) in recentCommandIDs.enumerated() {
                recentRank[id] = idx
            }
            return pool.enumerated().sorted { lhs, rhs in
                let lRecent = recentRank[lhs.element.id]
                let rRecent = recentRank[rhs.element.id]
                switch (lRecent, rRecent) {
                case let (l?, r?):
                    return l < r
                case (_?, nil):
                    return true
                case (nil, _?):
                    return false
                case (nil, nil):
                    return lhs.offset < rhs.offset
                }
            }.map(\.element)
        }

        var scored: [(command: CourierCommand, score: Int, index: Int)] = []
        for (idx, cmd) in pool.enumerated() {
            if let score = Self.matchScore(for: cmd, query: trimmed, recentIDs: recentCommandIDs) {
                scored.append((cmd, score, idx))
            }
        }
        return scored.sorted { lhs, rhs in
            if lhs.score != rhs.score {
                return lhs.score > rhs.score
            }
            return lhs.index < rhs.index
        }.map(\.command)
    }

    public var displayedRecentChats: [InboxRow] {
        let all = recentChatsProvider()
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !trimmed.isEmpty else { return all }
        return all.filter { row in
            row.name.lowercased().contains(trimmed)
                || row.network.lowercased().contains(trimmed)
                || row.preview.lowercased().contains(trimmed)
        }
    }

    public func executeSelected() {
        guard !isLocked else { return }
        if mode == .recentChats {
            let chats = displayedRecentChats
            guard selectedIndex >= 0, selectedIndex < chats.count else { return }
            let chosen = chats[selectedIndex]
            close()
            onSelectRecentChat(chosen.roomID)
            return
        }

        let commands = displayedCommands
        guard selectedIndex >= 0, selectedIndex < commands.count else { return }
        execute(commands[selectedIndex])
    }

    public func execute(_ command: CourierCommand) {
        guard !isLocked else { return }
        guard command.isEnabled() else {
            statusBanner = command.subtitle ?? String(localized: "This command isn’t available right now.")
            return
        }

        if !command.children.isEmpty {
            breadcrumb.append(command)
            query = ""
            selectedIndex = 0
            statusBanner = nil
            return
        }

        if command.id == "recent.openRecentlyViewedChats" {
            recordRecentCommand(command.id)
            mode = .recentChats
            query = ""
            selectedIndex = 0
            statusBanner = nil
            return
        }

        if command.confirmation != nil {
            pendingConfirmation = command
            return
        }

        recordRecentCommand(command.id)
        close()
        command.run()
    }

    public func confirmPendingCommand() {
        guard !isLocked, let cmd = pendingConfirmation else {
            pendingConfirmation = nil
            return
        }
        pendingConfirmation = nil
        recordRecentCommand(cmd.id)
        close()
        cmd.run()
    }

    public func cancelPendingConfirmation() {
        pendingConfirmation = nil
    }

    private func recordRecentCommand(_ id: String) {
        var updated = recentCommandIDs.filter { $0 != id }
        updated.insert(id, at: 0)
        if updated.count > Self.maxRecentCommands {
            updated = Array(updated.prefix(Self.maxRecentCommands))
        }
        recentCommandIDs = updated
        defaults.set(updated, forKey: Self.recentCommandsDefaultsKey)
    }

    private static func matchScore(
        for command: CourierCommand,
        query: String,
        recentIDs: [String]
    ) -> Int? {
        let titleLower = command.title.lowercased()
        let categoryLower = command.category.title.lowercased()
        let subtitleLower = (command.subtitle ?? "").lowercased()
        let keywordsLower = command.keywords.map { $0.lowercased() }

        var baseScore: Int?
        if titleLower == query {
            baseScore = 400
        } else if titleLower.hasPrefix(query) {
            baseScore = 300
        } else if titleLower.split(whereSeparator: { !$0.isLetter && !$0.isNumber }).contains(where: { $0.hasPrefix(query) }) {
            baseScore = 220
        } else if titleLower.contains(query) {
            baseScore = 160
        } else if keywordsLower.contains(where: { $0 == query || $0.hasPrefix(query) }) {
            baseScore = 130
        } else if keywordsLower.contains(where: { $0.contains(query) }) || categoryLower.contains(query) || subtitleLower.contains(query) {
            baseScore = 90
        }

        guard var score = baseScore else { return nil }
        if let recentIdx = recentIDs.firstIndex(of: command.id) {
            score += max(5, 25 - recentIdx * 3)
        }
        return score
    }
}
