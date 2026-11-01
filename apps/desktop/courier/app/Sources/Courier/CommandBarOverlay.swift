// Copyright 2026 VitruvianSoftware
// SPDX-License-Identifier: AGPL-3.0-or-later

import AppKit
import CourierCore
import SwiftUI

public struct CommandBarOverlay: View {
    @ObservedObject public var model: CommandBarModel
    @FocusState private var isSearchFocused: Bool

    public init(model: CommandBarModel) {
        self.model = model
    }

    public var body: some View {
        ZStack(alignment: .top) {
            Color.black.opacity(0.28)
                .ignoresSafeArea()
                .onTapGesture {
                    model.close()
                }
                .accessibilityHidden(true)

            VStack(spacing: 0) {
                searchHeader
                Divider()

                if let banner = model.statusBanner {
                    statusBannerRow(banner)
                    Divider()
                }

                if let pending = model.pendingConfirmation {
                    confirmationRow(pending)
                    Divider()
                }

                if model.mode == .recentChats {
                    recentChatsList
                } else {
                    commandsList
                }

                Divider()
                CommandBarFooterView()
            }
            .frame(width: 560)
            .frame(maxHeight: 440)
            .background(
                ZStack {
                    Color(nsColor: .windowBackgroundColor)
                    Rectangle().fill(.ultraThinMaterial)
                }
            )
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .strokeBorder(Color.primary.opacity(0.14), lineWidth: 1)
            )
            .shadow(color: .black.opacity(0.28), radius: 24, x: 0, y: 12)
            .padding(.top, 28)
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("commandBar.overlay")
        .onAppear {
            isSearchFocused = true
        }
        .onKeyPress(.upArrow) {
            model.moveSelection(delta: -1)
            return .handled
        }
        .onKeyPress(.downArrow) {
            model.moveSelection(delta: 1)
            return .handled
        }
        .onKeyPress(.escape) {
            if model.pendingConfirmation != nil {
                model.cancelPendingConfirmation()
            } else if !model.breadcrumb.isEmpty || model.mode == .recentChats {
                model.popBreadcrumbToRoot()
            } else {
                model.close()
            }
            return .handled
        }
        .onKeyPress(.return) {
            model.executeSelected()
            return .handled
        }
        .onKeyPress(.delete) {
            if model.query.isEmpty, !model.breadcrumb.isEmpty || model.mode == .recentChats {
                _ = model.handleBackspaceOnEmptyQuery()
                return .handled
            }
            return .ignored
        }
    }

    private var searchHeader: some View {
        HStack(spacing: 8) {
            Image(systemName: "command")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(.secondary)

            if !model.breadcrumb.isEmpty {
                ForEach(Array(model.breadcrumb.enumerated()), id: \.offset) { index, crumb in
                    Button {
                        if index == 0 {
                            model.popBreadcrumbToRoot()
                        } else {
                            model.popBreadcrumb(to: index - 1)
                        }
                    } label: {
                        HStack(spacing: 4) {
                            Text(crumb.title)
                                .font(.caption.weight(.semibold))
                            Image(systemName: "chevron.right")
                                .font(.system(size: 9, weight: .bold))
                        }
                        .padding(.horizontal, 7)
                        .padding(.vertical, 3)
                        .background(
                            Capsule()
                                .fill(Color.accentColor.opacity(0.16))
                        )
                        .foregroundStyle(Color.accentColor)
                    }
                    .buttonStyle(.plain)
                }
            } else if model.mode == .recentChats {
                HStack(spacing: 4) {
                    Image(systemName: "clock.arrow.circlepath")
                        .font(.system(size: 10, weight: .semibold))
                    Text("Recent Chats")
                        .font(.caption.weight(.semibold))
                }
                .padding(.horizontal, 7)
                .padding(.vertical, 3)
                .background(
                    Capsule()
                        .fill(Color.accentColor.opacity(0.16))
                )
                .foregroundStyle(Color.accentColor)
            }

            TextField(
                "",
                text: $model.query,
                prompt: Text(model.searchPlaceholder)
            )
            .labelsHidden()
            .textFieldStyle(.plain)
            .font(.system(size: 15))
            .focused($isSearchFocused)
            .accessibilityIdentifier("commandBar.searchField")
            .onSubmit {
                model.executeSelected()
            }

            if !model.query.isEmpty {
                Button {
                    model.query = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Clear command search")
            } else {
                Text("⌘J")
                    .font(.system(size: 11, weight: .medium, design: .rounded))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(
                        RoundedRectangle(cornerRadius: 4, style: .continuous)
                            .fill(Color.primary.opacity(0.07))
                    )
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 11)
    }

    private func statusBannerRow(_ message: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: "info.circle.fill")
                .foregroundStyle(Color.accentColor)
            Text(message)
                .font(.caption)
                .foregroundStyle(.primary)
            Spacer()
            Button("Dismiss") {
                model.statusBanner = nil
            }
            .buttonStyle(.borderless)
            .font(.caption.weight(.semibold))
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .background(Color.accentColor.opacity(0.08))
    }

    private func confirmationRow(_ command: CourierCommand) -> some View {
        HStack(spacing: 10) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.orange)
            Text(command.confirmation ?? "Run \(command.title)?")
                .font(.caption.weight(.medium))
                .lineLimit(2)
            Spacer()
            Button("Cancel") {
                model.cancelPendingConfirmation()
            }
            .controlSize(.small)
            Button("Confirm") {
                model.confirmPendingCommand()
            }
            .buttonStyle(.borderedProminent)
            .tint(.red)
            .controlSize(.small)
            .accessibilityIdentifier("commandBar.confirmButton")
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .background(Color.orange.opacity(0.10))
    }

    private var commandsList: some View {
        let filtered = model.displayedCommands
        let isRootEmptyQuery = model.query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && model.breadcrumb.isEmpty
        let recentIDSet = Set(model.recentCommandIDs)

        return ScrollViewReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: 2) {
                    if filtered.isEmpty {
                        HStack {
                            Spacer()
                            VStack(spacing: 6) {
                                Image(systemName: "magnifyingglass")
                                    .font(.title3)
                                    .foregroundStyle(.secondary)
                                Text("No matching commands")
                                    .font(.callout)
                                    .foregroundStyle(.secondary)
                            }
                            .padding(.vertical, 32)
                            Spacer()
                        }
                    } else {
                        ForEach(Array(filtered.enumerated()), id: \.element.id) { index, cmd in
                            if isRootEmptyQuery,
                               let header = sectionHeaderTitle(at: index, in: filtered, recentIDSet: recentIDSet) {
                                sectionHeader(header)
                            }
                            commandRow(
                                cmd,
                                isSelected: index == model.selectedIndex,
                                idPrefix: "cmd"
                            )
                            .id(cmd.id)
                            .onTapGesture {
                                model.selectedIndex = index
                                model.execute(cmd)
                            }
                        }
                    }
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 6)
            }
            .onChange(of: model.selectedIndex) { _, newIndex in
                guard filtered.indices.contains(newIndex) else { return }
                withAnimation(.easeInOut(duration: 0.12)) {
                    proxy.scrollTo(filtered[newIndex].id, anchor: .center)
                }
            }
        }
    }

    private func sectionHeaderTitle(
        at index: Int,
        in commands: [CourierCommand],
        recentIDSet: Set<String>
    ) -> String? {
        guard commands.indices.contains(index) else { return nil }
        let current = commands[index]
        let isCurrentRecent = recentIDSet.contains(current.id) || current.category == .recent
        if index == 0 {
            return isCurrentRecent ? "Recent" : current.category.title
        }
        let previous = commands[index - 1]
        let isPreviousRecent = recentIDSet.contains(previous.id) || previous.category == .recent
        if isCurrentRecent {
            return isPreviousRecent ? nil : "Recent"
        }
        if isPreviousRecent || previous.category != current.category {
            return current.category.title
        }
        return nil
    }

    private func sectionHeader(_ title: String) -> some View {
        Text(title.uppercased())
            .font(.system(size: 10, weight: .semibold))
            .foregroundStyle(.secondary)
            .padding(.horizontal, 10)
            .padding(.top, 6)
            .padding(.bottom, 2)
    }

    private func commandRow(
        _ command: CourierCommand,
        isSelected: Bool,
        idPrefix: String
    ) -> some View {
        let enabled = command.enabled
        return HStack(spacing: 10) {
            Image(systemName: command.icon)
                .font(.system(size: 13, weight: .medium))
                .frame(width: 20, alignment: .center)
                .foregroundStyle(isSelected ? Color.accentColor : .secondary)

            VStack(alignment: .leading, spacing: 1) {
                Text(command.title)
                    .font(.system(size: 13, weight: isSelected ? .semibold : .regular))
                    .foregroundStyle(enabled ? .primary : .secondary)
                    .lineLimit(1)
                if let subtitle = command.subtitle, !subtitle.isEmpty {
                    Text(subtitle)
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }

            Spacer(minLength: 8)

            if !model.query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
               model.breadcrumb.isEmpty {
                Text(command.category.title)
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(
                        Capsule()
                            .fill(Color.primary.opacity(0.06))
                    )
            }

            if let shortcut = command.shortcut, !shortcut.isEmpty {
                shortcutBadge(shortcut)
            }

            if !command.children.isEmpty {
                Image(systemName: "chevron.right")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .background(
            RoundedRectangle(cornerRadius: 7, style: .continuous)
                .fill(isSelected ? Color.accentColor.opacity(0.16) : Color.clear)
        )
        .opacity(enabled ? 1.0 : 0.48)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("commandBar.\(idPrefix).\(command.id)")
    }

    private func shortcutBadge(_ shortcut: String) -> some View {
        Text(shortcut)
            .font(.system(size: 11, weight: .medium, design: .rounded))
            .foregroundStyle(.secondary)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(
                RoundedRectangle(cornerRadius: 4, style: .continuous)
                    .fill(Color.primary.opacity(0.08))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 4, style: .continuous)
                    .strokeBorder(Color.primary.opacity(0.10), lineWidth: 0.5)
            )
    }

    private var recentChatsList: some View {
        let rows = model.displayedRecentChats
        return ScrollView {
            VStack(alignment: .leading, spacing: 2) {
                if rows.isEmpty {
                    HStack {
                        Spacer()
                        Text("No recently viewed chats")
                            .font(.callout)
                            .foregroundStyle(.secondary)
                            .padding(.vertical, 28)
                        Spacer()
                    }
                } else {
                    sectionHeader("Recently Viewed Chats")
                    ForEach(Array(rows.enumerated()), id: \.element.roomID) { index, row in
                        let isSelected = index == model.selectedIndex
                        HStack(spacing: 10) {
                            Image(systemName: row.isDirect ? "person.crop.circle.fill" : "person.2.circle.fill")
                                .font(.system(size: 16))
                                .foregroundStyle(isSelected ? Color.accentColor : .secondary)
                                .frame(width: 22)

                            VStack(alignment: .leading, spacing: 1) {
                                HStack(spacing: 6) {
                                    Text(row.name)
                                        .font(.system(size: 13, weight: isSelected ? .semibold : .medium))
                                        .lineLimit(1)
                                    Text(row.network.capitalized)
                                        .font(.system(size: 10, weight: .semibold))
                                        .foregroundStyle(.secondary)
                                        .padding(.horizontal, 5)
                                        .padding(.vertical, 1)
                                        .background(
                                            Capsule().fill(Color.primary.opacity(0.08))
                                        )
                                }
                                if !row.preview.isEmpty {
                                    Text(row.preview)
                                        .font(.system(size: 11))
                                        .foregroundStyle(.secondary)
                                        .lineLimit(1)
                                }
                            }
                            Spacer()
                            Image(systemName: "arrow.turn.down.left")
                                .font(.system(size: 11))
                                .foregroundStyle(.secondary)
                        }
                        .padding(.horizontal, 10)
                        .padding(.vertical, 7)
                        .background(
                            RoundedRectangle(cornerRadius: 7, style: .continuous)
                                .fill(isSelected ? Color.accentColor.opacity(0.16) : Color.clear)
                        )
                        .contentShape(Rectangle())
                        .onTapGesture {
                            model.selectedIndex = index
                            model.close()
                            model.onSelectRecentChat(row.roomID)
                        }
                        .accessibilityIdentifier("commandBar.recentChat.\(row.roomID)")
                    }
                }
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 6)
        }
    }
}

public struct CommandBarFooterView: View {
    public static let closeKeyLabel = "esc"

    public init() {}

    public var body: some View {
        HStack(spacing: 14) {
            footerHint(key: "↑↓", label: "Navigate")
            footerHint(key: "↵", label: "Run")
            footerHint(key: "⌫", label: "Back")
            footerHint(key: Self.closeKeyLabel, label: "Close")
            Spacer()
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .background(Color.primary.opacity(0.03))
    }

    private func footerHint(key: String, label: String) -> some View {
        HStack(spacing: 4) {
            Text(key)
                .font(.system(size: 10, weight: .semibold, design: .rounded))
                .foregroundStyle(.secondary)
                .padding(.horizontal, 5)
                .padding(.vertical, 1.5)
                .background(
                    RoundedRectangle(cornerRadius: 3.5, style: .continuous)
                        .fill(Color.primary.opacity(0.08))
                )
            Text(label)
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
        }
    }
}

public struct ConfettiOverlayView: View {
    public let triggerCount: Int
    @State private var isAnimating = false

    public init(triggerCount: Int) {
        self.triggerCount = triggerCount
    }

    private static let palette: [Color] = [
        .red, .orange, .yellow, .green, .mint, .cyan, .blue, .purple, .pink,
    ]

    public var body: some View {
        GeometryReader { geo in
            if isAnimating, !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion {
                ZStack {
                    ForEach(0..<28, id: \.self) { index in
                        let xFraction = CGFloat((index * 37) % 100) / 100.0
                        let delay = Double(index % 7) * 0.04
                        Circle()
                            .fill(Self.palette[index % Self.palette.count])
                            .frame(width: 8, height: 8)
                            .position(
                                x: geo.size.width * xFraction,
                                y: isAnimating ? geo.size.height + 20 : -20
                            )
                            .animation(.easeOut(duration: 1.1).delay(delay), value: isAnimating)
                    }
                }
            }
        }
        .allowsHitTesting(false)
        .onChange(of: triggerCount) { _, _ in
            guard !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion else { return }
            isAnimating = true
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.4) {
                isAnimating = false
            }
        }
    }
}
