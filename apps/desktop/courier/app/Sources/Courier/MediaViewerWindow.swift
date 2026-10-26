// Copyright 2026 VitruvianSoftware
// SPDX-License-Identifier: AGPL-3.0-or-later

import AppKit
import CourierCore
import SwiftUI

/// Media tile with sender attribution (`MediaWithSender.tsx`) rendered in the **Media** tab of `MediaViewerView`.
public struct MediaWithSender: View {
    public let hit: MediaHit
    public let isSelected: Bool
    public let now: () -> Date
    public let onOpen: () -> Void
    public let onToggleSelect: () -> Void
    public let onGoToMessage: () -> Void

    @State private var asyncThumbnail: CGImage?

    public init(
        hit: MediaHit,
        isSelected: Bool,
        now: @escaping () -> Date = { Date() },
        onOpen: @escaping () -> Void,
        onToggleSelect: @escaping () -> Void,
        onGoToMessage: @escaping () -> Void
    ) {
        self.hit = hit
        self.isSelected = isSelected
        self.now = now
        self.onOpen = onOpen
        self.onToggleSelect = onToggleSelect
        self.onGoToMessage = onGoToMessage
    }

    private var senderDisplayName: String {
        if hit.mine { return String(localized: "You") }
        return hit.senderName.isEmpty ? hit.sender : hit.senderName
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            ZStack(alignment: .topLeading) {
                Button(action: onOpen) {
                    Color.primary.opacity(0.07)
                        .frame(maxWidth: .infinity)
                        .frame(height: 128)
                        .overlay {
                            ZStack {
                                if let asyncThumbnail {
                                    Image(decorative: asyncThumbnail, scale: 1)
                                        .resizable()
                                        .scaledToFill()
                                } else {
                                    Image(systemName: hit.kind == .video ? "film" : "photo")
                                        .font(.title2)
                                        .foregroundStyle(.secondary)
                                }

                                if hit.kind == .video {
                                    Image(systemName: "play.circle.fill")
                                        .font(.system(size: 28))
                                        .foregroundStyle(.white)
                                        .shadow(radius: 3)
                                }
                            }
                        }
                        .clipped()
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                        .overlay(
                            RoundedRectangle(cornerRadius: 8)
                                .strokeBorder(
                                    isSelected ? Color.accentColor : Color.primary.opacity(0.1),
                                    lineWidth: isSelected ? 2 : 1
                                )
                        )
                }
                .buttonStyle(.plain)

                Button(action: onToggleSelect) {
                    Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(isSelected ? Color.accentColor : .white)
                        .padding(4)
                        .background(Circle().fill(Color.black.opacity(0.45)))
                }
                .buttonStyle(.plain)
                .padding(6)
                .help(String(localized: "Select item"))
                .accessibilityLabel(String(localized: "Select \(hit.fileName)"))
            }

            HStack(spacing: 6) {
                AvatarView(
                    path: "",
                    initials: String(Self.initials(of: senderDisplayName).prefix(1)),
                    seed: senderDisplayName
                )
                .frame(width: 22, height: 22)

                VStack(alignment: .leading, spacing: 1) {
                    Text(verbatim: senderDisplayName)
                        .font(.caption.weight(.semibold))
                        .lineLimit(1)
                    Text(verbatim: hit.fileName)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }

                Spacer(minLength: 4)

                Button(action: onGoToMessage) {
                    Image(systemName: "arrow.turn.up.left")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .help(String(localized: "Go to Message"))
            }
            .padding(.horizontal, 2)
        }
        .padding(6)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(isSelected ? Color.accentColor.opacity(0.10) : Color.primary.opacity(0.03))
        )
        .task(id: hit.mediaPath) {
            guard !hit.viewOnce, isLocalMediaStorePath(hit.mediaPath) else {
                return
            }
            asyncThumbnail = await ThumbnailLoader.shared.thumbnail(atPath: hit.mediaPath)?.image
        }
    }

    private static func initials(of name: String) -> String {
        let letters = name.split(whereSeparator: \.isWhitespace).prefix(2).compactMap {
            $0.first(where: { $0.isLetter || $0.isNumber })
        }
        guard !letters.isEmpty else { return "?" }
        return String(letters).uppercased()
    }
}

/// Inner content view for `MediaViewerWindow` (`MediaViewerBrowserWindow.tsx`), testable in snapshots.
public struct MediaViewerView: View {
    public static let actionTitles: [String] = [
        String(localized: "Media"),
        String(localized: "Links"),
        String(localized: "Docs"),
        String(localized: "Sent By"),
        String(localized: "Sort"),
        String(localized: "Download Selected"),
        String(localized: "Delete Selected"),
        String(localized: "Go to Message"),
        String(localized: "Clear Selection"),
    ]

    @ObservedObject public var model: MediaViewerModel
    public var chatTitle: String
    public var now: () -> Date
    public var onOpenLightbox: (MediaHit) -> Void
    public var onGoToMessage: (MediaHit) -> Void
    public var onDownloadSelected: () -> Void
    public var onDeleteSelected: (Bool) -> Void

    public init(
        model: MediaViewerModel,
        chatTitle: String = "",
        now: @escaping () -> Date = { Date() },
        onOpenLightbox: @escaping (MediaHit) -> Void = { _ in },
        onGoToMessage: @escaping (MediaHit) -> Void = { _ in },
        onDownloadSelected: @escaping () -> Void = {},
        onDeleteSelected: @escaping (Bool) -> Void = { _ in }
    ) {
        self.model = model
        self.chatTitle = chatTitle
        self.now = now
        self.onOpenLightbox = onOpenLightbox
        self.onGoToMessage = onGoToMessage
        self.onDownloadSelected = onDownloadSelected
        self.onDeleteSelected = onDeleteSelected
    }

    public var body: some View {
        VStack(spacing: 0) {
            headerControls
                .padding(.horizontal, 14)
                .padding(.vertical, 10)

            Divider()

            Group {
                if model.items.isEmpty && !model.isLoading {
                    emptyStateView
                } else {
                    switch model.tab {
                    case .media:
                        mediaGridView
                    case .links:
                        linksListView
                    case .docs:
                        docsListView
                    }
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            if !model.selectedEventIDs.isEmpty {
                Divider()
                multiSelectBar
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)
                    .background(Color(nsColor: .controlBackgroundColor))
            }
        }
    }

    // MARK: - Header Controls

    private var headerControls: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 12) {
                if !chatTitle.isEmpty {
                    Text(verbatim: chatTitle)
                        .font(.headline)
                        .lineLimit(1)
                } else {
                    Text(String(localized: "Media Viewer"))
                        .font(.headline)
                }

                Spacer(minLength: 8)

                Picker(String(localized: "Tab"), selection: $model.tab) {
                    ForEach(MediaViewerModel.Tab.allCases, id: \.self) { tab in
                        Text(tab.rawValue).tag(tab)
                    }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .frame(width: 220)
            }

            HStack(spacing: 10) {
                HStack(spacing: 6) {
                    Image(systemName: "magnifyingglass")
                        .foregroundStyle(.secondary)
                        .font(.caption)
                    TextField(
                        String(localized: "Search captions, links, or filenames…"),
                        text: $model.query
                    )
                    .textFieldStyle(.plain)
                    .font(.callout)
                    .onSubmit {
                        Task { await model.refresh() }
                    }
                    if !model.query.isEmpty {
                        Button {
                            model.query = ""
                            Task { await model.refresh() }
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                                .foregroundStyle(.secondary)
                                .font(.caption)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 5)
                .background(RoundedRectangle(cornerRadius: 6).fill(Color.primary.opacity(0.06)))

                HStack(spacing: 4) {
                    Text(String(localized: "Sent By:"))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Picker(String(localized: "Sent By"), selection: $model.sentBy) {
                        ForEach(MediaViewerModel.SentByFilter.allCases, id: \.self) { filter in
                            Text(filter.rawValue).tag(filter)
                        }
                    }
                    .labelsHidden()
                    .frame(width: 96)
                }

                HStack(spacing: 4) {
                    Text(String(localized: "Sort:"))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Picker(String(localized: "Sort"), selection: $model.sortOrder) {
                        ForEach(MediaViewerModel.SortOrder.allCases, id: \.self) { order in
                            Text(order.rawValue).tag(order)
                        }
                    }
                    .labelsHidden()
                    .frame(width: 96)
                }
            }
        }
    }

    // MARK: - Media Tab

    private var mediaGridView: some View {
        ScrollView {
            let columns = [GridItem(.adaptive(minimum: 165, maximum: 220), spacing: 10)]
            LazyVGrid(columns: columns, spacing: 10) {
                ForEach(model.items) { hit in
                    MediaWithSender(
                        hit: hit,
                        isSelected: model.selectedEventIDs.contains(hit.eventID),
                        now: now,
                        onOpen: { onOpenLightbox(hit) },
                        onToggleSelect: { model.toggleSelected(hit.eventID) },
                        onGoToMessage: { onGoToMessage(hit) }
                    )
                    .onAppear {
                        if hit.eventID == model.items.last?.eventID, model.hasMore {
                            Task { await model.loadNextPage() }
                        }
                    }
                }
            }
            .padding(14)
        }
    }

    // MARK: - Links Tab

    private var linksListView: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 8) {
                ForEach(model.items) { hit in
                    let isSelected = model.selectedEventIDs.contains(hit.eventID)
                    let urlString = hit.extractedURL ?? hit.snippet
                    let hostString = hit.extractedHost ?? urlString
                    let senderName = hit.mine ? String(localized: "You") : (hit.senderName.isEmpty ? hit.sender : hit.senderName)

                    HStack(spacing: 10) {
                        Button {
                            model.toggleSelected(hit.eventID)
                        } label: {
                            Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                                .foregroundStyle(isSelected ? Color.accentColor : .secondary)
                        }
                        .buttonStyle(.plain)

                        Image(systemName: "link")
                            .font(.callout.weight(.semibold))
                            .foregroundStyle(Color.accentColor)
                            .frame(width: 28, height: 28)
                            .background(RoundedRectangle(cornerRadius: 6).fill(Color.accentColor.opacity(0.12)))

                        VStack(alignment: .leading, spacing: 2) {
                            Text(verbatim: hostString)
                                .font(.callout.weight(.semibold))
                                .lineLimit(1)
                            Text(verbatim: urlString)
                                .font(.caption)
                                .foregroundStyle(Color.accentColor)
                                .lineLimit(1)
                            HStack(spacing: 6) {
                                Text(verbatim: senderName)
                                    .font(.caption2.weight(.medium))
                                    .foregroundStyle(.secondary)
                                if hit.ts > 0 {
                                    Text(verbatim: "•")
                                        .font(.caption2)
                                        .foregroundStyle(.tertiary)
                                    Text(
                                        Date(timeIntervalSince1970: Double(hit.ts) / 1000.0)
                                            .formatted(date: .abbreviated, time: .shortened)
                                    )
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                                }
                            }
                        }

                        Spacer(minLength: 8)

                        if let rawURL = hit.extractedURL, let parsed = URL(string: rawURL) {
                            Button(String(localized: "Open Link")) {
                                NSWorkspace.shared.open(parsed)
                            }
                            .buttonStyle(.bordered)
                            .controlSize(.small)
                        }

                        Button(String(localized: "Go to Message")) {
                            onGoToMessage(hit)
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                    }
                    .padding(10)
                    .background(
                        RoundedRectangle(cornerRadius: 8)
                            .fill(isSelected ? Color.accentColor.opacity(0.10) : Color.primary.opacity(0.04))
                    )
                    .onAppear {
                        if hit.eventID == model.items.last?.eventID, model.hasMore {
                            Task { await model.loadNextPage() }
                        }
                    }
                }
            }
            .padding(14)
        }
    }

    // MARK: - Docs Tab

    private var docsListView: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 8) {
                ForEach(model.items) { hit in
                    let isSelected = model.selectedEventIDs.contains(hit.eventID)
                    let senderName = hit.mine ? String(localized: "You") : (hit.senderName.isEmpty ? hit.sender : hit.senderName)

                    HStack(spacing: 10) {
                        Button {
                            model.toggleSelected(hit.eventID)
                        } label: {
                            Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                                .foregroundStyle(isSelected ? Color.accentColor : .secondary)
                        }
                        .buttonStyle(.plain)

                        Image(systemName: hit.kind == .audio ? "waveform" : "doc.fill")
                            .font(.callout.weight(.semibold))
                            .foregroundStyle(.secondary)
                            .frame(width: 28, height: 28)
                            .background(RoundedRectangle(cornerRadius: 6).fill(Color.primary.opacity(0.08)))

                        VStack(alignment: .leading, spacing: 2) {
                            Text(verbatim: hit.fileName)
                                .font(.callout.weight(.medium))
                                .lineLimit(1)
                            HStack(spacing: 6) {
                                Text(verbatim: senderName)
                                    .font(.caption2.weight(.medium))
                                    .foregroundStyle(.secondary)
                                if hit.ts > 0 {
                                    Text(verbatim: "•")
                                        .font(.caption2)
                                        .foregroundStyle(.tertiary)
                                    Text(
                                        Date(timeIntervalSince1970: Double(hit.ts) / 1000.0)
                                            .formatted(date: .abbreviated, time: .shortened)
                                    )
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                                }
                            }
                        }

                        Spacer(minLength: 8)

                        if isLocalMediaStorePath(hit.mediaPath) {
                            Button(String(localized: "Quick Look")) {
                                QuickLookPreviewCoordinator.shared.preview(
                                    fileAtPath: hit.mediaPath,
                                    suggestedName: hit.fileName
                                )
                            }
                            .buttonStyle(.bordered)
                            .controlSize(.small)
                        }

                        Button(String(localized: "Go to Message")) {
                            onGoToMessage(hit)
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                    }
                    .padding(10)
                    .background(
                        RoundedRectangle(cornerRadius: 8)
                            .fill(isSelected ? Color.accentColor.opacity(0.10) : Color.primary.opacity(0.04))
                    )
                    .onAppear {
                        if hit.eventID == model.items.last?.eventID, model.hasMore {
                            Task { await model.loadNextPage() }
                        }
                    }
                }
            }
            .padding(14)
        }
    }

    // MARK: - Empty State

    private var emptyStateView: some View {
        VStack(spacing: 8) {
            Image(
                systemName: model.tab == .media
                    ? "photo.on.rectangle.angled"
                    : (model.tab == .links ? "link" : "doc")
            )
            .font(.system(size: 32))
            .foregroundStyle(.secondary)

            Text(
                model.tab == .media
                    ? String(localized: "No media found")
                    : (model.tab == .links ? String(localized: "No links found") : String(localized: "No documents found"))
            )
            .font(.headline)
            .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Multi-select Bar

    private var multiSelectBar: some View {
        let count = model.selectedEventIDs.count
        let selectedHits = model.items.filter { model.selectedEventIDs.contains($0.eventID) }
        let anyMine = selectedHits.contains(where: \.mine)

        return HStack(spacing: 10) {
            Text(
                count == 1
                    ? String(localized: "1 item selected")
                    : String(localized: "\(count) items selected")
            )
            .font(.callout.weight(.semibold))

            Button(String(localized: "Clear Selection")) {
                model.clearSelection()
            }
            .buttonStyle(.plain)
            .font(.caption)
            .foregroundStyle(.secondary)

            Spacer(minLength: 8)

            if count == 1, let single = selectedHits.first {
                Button {
                    onGoToMessage(single)
                } label: {
                    Label(String(localized: "Go to Message"), systemImage: "arrow.turn.up.left")
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            }

            if model.tab != .links {
                Button(action: onDownloadSelected) {
                    Label(String(localized: "Download Selected"), systemImage: "arrow.down.circle")
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            }

            if anyMine {
                Menu {
                    Button(String(localized: "Delete for Me"), role: .destructive) {
                        onDeleteSelected(false)
                    }
                    Button(String(localized: "Unsend for Everyone"), role: .destructive) {
                        onDeleteSelected(true)
                    }
                } label: {
                    Label(String(localized: "Delete Selected"), systemImage: "trash")
                }
                .menuStyle(.borderedButton)
                .controlSize(.small)
                .fixedSize()
            } else {
                Button(role: .destructive) {
                    onDeleteSelected(false)
                } label: {
                    Label(String(localized: "Delete Selected"), systemImage: "trash")
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            }
        }
    }
}

/// Standalone `WindowGroup(id: "media-viewer", for: MediaViewerTarget.self)` scene content.
public struct MediaViewerWindow: View {
    public let target: MediaViewerTarget
    @ObservedObject public var appModel: AppModel
    @ObservedObject public var conversation: ConversationModel
    @ObservedObject public var preferences: ComposerPreferences

    @StateObject private var viewerModel: MediaViewerModel

    public init(
        target: MediaViewerTarget,
        appModel: AppModel,
        conversation: ConversationModel,
        preferences: ComposerPreferences
    ) {
        self.target = target
        self.appModel = appModel
        self.conversation = conversation
        self.preferences = preferences
        let initialRoomID = target.roomID ?? appModel.selectedRoomID
        let model = MediaViewerModel(
            appModel: appModel,
            roomID: initialRoomID,
            conversation: conversation
        )
        model.tab = target.resolvedTab
        _viewerModel = StateObject(wrappedValue: model)
    }

    private var resolvedChatTitle: String {
        let effectiveRoom = viewerModel.roomID ?? appModel.selectedRoomID
        guard let effectiveRoom else { return "" }
        if let merged = appModel.mergedChats[effectiveRoom] {
            return merged.name
        }
        if conversation.roomID == effectiveRoom {
            return conversation.otherPerson ?? conversation.chatInfo?.name ?? ""
        }
        return ""
    }

    public var body: some View {
        MediaViewerView(
            model: viewerModel,
            chatTitle: resolvedChatTitle,
            onOpenLightbox: { hit in
                let carouselItems = viewerModel.items.compactMap(CarouselItem.init(hit:))
                if !carouselItems.isEmpty {
                    conversation.carousel.open(items: carouselItems, selectedEventID: hit.eventID)
                    conversation.activeLightboxMessageID = hit.eventID
                } else {
                    conversation.openLightbox(hit.eventID)
                }
            },
            onGoToMessage: { hit in
                appModel.open(.message(roomID: hit.roomID, eventID: hit.eventID))
            },
            onDownloadSelected: {
                let downloader = AttachmentDownloader(preferences: preferences)
                let saved = viewerModel.downloadSelected(using: downloader)
                if !saved.isEmpty {
                    conversation.onToast(
                        saved.count == 1
                            ? String(localized: "Saved \(saved[0].lastPathComponent)")
                            : String(localized: "Saved \(saved.count) files")
                    )
                }
            },
            onDeleteSelected: { forEveryone in
                Task { await viewerModel.deleteSelected(forEveryone: forEveryone) }
            }
        )
        .frame(minWidth: 640, idealWidth: 780, minHeight: 460, idealHeight: 560)
        .task(id: "\(viewerModel.roomID ?? "")-\(viewerModel.tab.rawValue)-\(viewerModel.sentBy.rawValue)") {
            await viewerModel.refresh()
        }
    }
}
