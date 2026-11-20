// Copyright 2026 VitruvianSoftware
// SPDX-License-Identifier: AGPL-3.0-or-later

import AppKit
import VitruvianCourierCore
import SwiftUI

/// Full-window attachment lightbox (`AttachmentCarousel.tsx`).
///
/// Displays images, videos, and stickers from the engine's local media store with:
/// - Top action bar: sender attribution, timestamp, filename, **Go to Message**, **React**, **Reply**,
///   **Copy Image** (`⌘C`), **Quick Look** (`Space`), **Download** (`⌘D`), and **Close** (`Esc`).
/// - Center stage: zoomable/pannable/rotatable/flippable image or Task 6's `InlineVideoPlayer` with
///   `←` / `→` arrow navigation and `Space` play/pause for video (or Quick Look for images).
/// - Bottom bar: transform controls (**Zoom Out**, **100%**, **Zoom In**, **Rotate 90°**, **Flip H**, **Flip V**)
///   and a horizontal thumbnail filmstrip of all non-view-once media in the chat.
public struct AttachmentCarouselOverlay: View {
    public static let actionTitles: [String] = [
        String(localized: "Go to Message"),
        String(localized: "React"),
        String(localized: "Reply"),
        String(localized: "Copy Image"),
        String(localized: "Quick Look"),
        String(localized: "Download"),
        String(localized: "Close"),
        String(localized: "Zoom Out"),
        String(localized: "Reset Zoom"),
        String(localized: "Zoom In"),
        String(localized: "Rotate 90°"),
        String(localized: "Flip Horizontally"),
        String(localized: "Flip Vertically"),
    ]

    private static let quickReactions = ["👍", "❤️", "😂", "😮", "😢", "🙏"]

    @ObservedObject public var model: AttachmentCarouselModel
    public var now: () -> Date
    public var onGoToMessage: (CarouselItem) -> Void
    public var onReact: (CarouselItem, String) -> Void
    public var onReply: (CarouselItem) -> Void
    public var onCopyImage: (CarouselItem) -> Void
    public var onQuickLook: (CarouselItem) -> Void
    public var onDownload: (CarouselItem) -> Void
    public var onClose: () -> Void

    @Environment(\.redactNamesAndPictures) private var isRedacted
    @State private var panOffset: CGSize = .zero
    @State private var dragStartOffset: CGSize = .zero
    @State private var showReactionPopover = false

    public init(
        model: AttachmentCarouselModel,
        now: @escaping () -> Date = { Date() },
        onGoToMessage: @escaping (CarouselItem) -> Void = { _ in },
        onReact: @escaping (CarouselItem, String) -> Void = { _, _ in },
        onReply: @escaping (CarouselItem) -> Void = { _ in },
        onCopyImage: @escaping (CarouselItem) -> Void = { _ in },
        onQuickLook: @escaping (CarouselItem) -> Void = { _ in },
        onDownload: @escaping (CarouselItem) -> Void = { _ in },
        onClose: @escaping () -> Void = {}
    ) {
        self.model = model
        self.now = now
        self.onGoToMessage = onGoToMessage
        self.onReact = onReact
        self.onReply = onReply
        self.onCopyImage = onCopyImage
        self.onQuickLook = onQuickLook
        self.onDownload = onDownload
        self.onClose = onClose
    }

    public var body: some View {
        ZStack {
            // Dark enough that nothing behind it reads, and under the toolbar as well.
            Color.black.opacity(0.94)
                .ignoresSafeArea()
                .onTapGesture {
                    onClose()
                }

            if let item = model.currentItem {
                VStack(spacing: 0) {
                    topBar(for: item)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 10)
                        .background(Color.black.opacity(0.55))

                    Divider()
                        .overlay(Color.white.opacity(0.12))

                    centerStage(for: item)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)

                    let captionText = PhotoViewerPresentation.displayCaption(
                        caption: item.caption,
                        fileName: item.fileName
                    )
                    let reactionChips = item.reactions.filter { !$0.key.isEmpty && $0.count > 0 }
                    if captionText != nil || !reactionChips.isEmpty {
                        VStack(spacing: 6) {
                            if let captionText {
                                Text(verbatim: captionText)
                                    .font(.callout)
                                    .foregroundStyle(.white.opacity(0.92))
                                    .lineLimit(2)
                                    .multilineTextAlignment(.center)
                            }
                            if !reactionChips.isEmpty {
                                PhotoViewerReactionChips(chips: reactionChips)
                            }
                        }
                        .padding(.horizontal, 24)
                        .padding(.vertical, 6)
                    }

                    Divider()
                        .overlay(Color.white.opacity(0.12))

                    bottomBar
                        .padding(.horizontal, 16)
                        .padding(.vertical, 10)
                        .background(Color.black.opacity(0.65))
                }
            }
        }
        .background(keyboardHandlingButtons)
        .onChange(of: model.currentIndex) { _, _ in
            panOffset = .zero
            dragStartOffset = .zero
        }
        .onChange(of: model.zoomScale) { _, newScale in
            if abs(newScale - 1.0) < 0.001 {
                panOffset = .zero
                dragStartOffset = .zero
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel(String(localized: "Attachment Lightbox"))
    }

    // MARK: - Top Bar

    private func topBar(for item: CarouselItem) -> some View {
        HStack(spacing: 10) {
            let displaySender = PhotoViewerPresentation.displaySender(
                sender: item.sender,
                senderName: item.senderName,
                mine: item.mine,
                redacted: isRedacted
            )
            let headerText = PhotoViewerPresentation.headerText(for: item, redacted: isRedacted)
            let avatarIdentity = isRedacted
                ? AvatarColor.identity(id: displaySender, fallbackName: displaySender)
                : AvatarColor.identity(id: item.sender, fallbackName: displaySender)
            AvatarView(
                path: isRedacted ? "" : item.senderAvatarPath,
                initials: Self.initials(of: displaySender),
                identity: avatarIdentity
            )
            .frame(width: 28, height: 28)

            VStack(alignment: .leading, spacing: 2) {
                Text(verbatim: headerText)
                    .font(.callout.weight(.semibold))
                    .foregroundStyle(.white)
                    .lineLimit(1)

                Text(verbatim: model.positionLabel)
                    .font(.caption2.weight(.medium))
                    .foregroundStyle(.white.opacity(0.75))
                    .padding(.horizontal, 6)
                    .padding(.vertical, 1)
                    .background(Capsule().fill(Color.white.opacity(0.16)))
                    .fixedSize()
            }

            Spacer(minLength: 12)

            HStack(spacing: 6) {
                carouselActionButton(
                    title: String(localized: "Go to Message"),
                    systemImage: "arrow.turn.up.left"
                ) {
                    onGoToMessage(item)
                }

                Button {
                    showReactionPopover.toggle()
                } label: {
                    Label(String(localized: "React"), systemImage: "face.smiling")
                        .font(.caption.weight(.medium))
                        .lineLimit(1)
                        .foregroundStyle(.white)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 5)
                        .background(RoundedRectangle(cornerRadius: 6).fill(Color.white.opacity(0.14)))
                }
                .buttonStyle(.plain)
                .fixedSize(horizontal: true, vertical: false)
                .help(String(localized: "React"))
                .popover(isPresented: $showReactionPopover, arrowEdge: .bottom) {
                    HStack(spacing: 6) {
                        ForEach(Self.quickReactions, id: \.self) { emoji in
                            Button {
                                showReactionPopover = false
                                onReact(item, emoji)
                            } label: {
                                Text(verbatim: emoji)
                                    .font(.title3)
                                    .padding(4)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(8)
                }

                carouselActionButton(
                    title: String(localized: "Reply"),
                    systemImage: "arrowshape.turn.up.left"
                ) {
                    onReply(item)
                }

                if item.kind != .video {
                    carouselActionButton(
                        title: String(localized: "Copy Image"),
                        systemImage: "doc.on.doc"
                    ) {
                        onCopyImage(item)
                    }
                }

                carouselActionButton(
                    title: String(localized: "Quick Look"),
                    systemImage: "eye"
                ) {
                    onQuickLook(item)
                }

                carouselActionButton(
                    title: String(localized: "Download"),
                    systemImage: "arrow.down.circle"
                ) {
                    onDownload(item)
                }

                Button(action: onClose) {
                    Image(systemName: "xmark")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(.white)
                        .frame(width: 28, height: 28)
                        .background(Circle().fill(Color.white.opacity(0.18)))
                }
                .buttonStyle(.plain)
                .help(String(localized: "Close (Esc)"))
                .accessibilityLabel(String(localized: "Close"))
            }
        }
    }

    private func carouselActionButton(
        title: String,
        systemImage: String,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Label(title, systemImage: systemImage)
                .font(.caption.weight(.medium))
                .lineLimit(1)
                .foregroundStyle(.white)
                .padding(.horizontal, 8)
                .padding(.vertical, 5)
                .background(RoundedRectangle(cornerRadius: 6).fill(Color.white.opacity(0.14)))
        }
        .buttonStyle(.plain)
        .fixedSize(horizontal: true, vertical: false)
        .help(title)
    }

    // MARK: - Center Stage

    private func centerStage(for item: CarouselItem) -> some View {
        HStack(spacing: 12) {
            Button {
                model.previous()
            } label: {
                Image(systemName: "chevron.left")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(width: 36, height: 36)
                    .background(Circle().fill(Color.white.opacity(model.canGoPrevious ? 0.2 : 0.06)))
            }
            .buttonStyle(.plain)
            .disabled(!model.canGoPrevious)
            .opacity(model.canGoPrevious ? 1.0 : 0.35)
            .padding(.leading, 12)
            .help(String(localized: "Previous"))
            .accessibilityLabel(String(localized: "Previous"))

            ZStack {
                if item.kind == .video {
                    videoStage(for: item)
                } else {
                    imageStage(for: item)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .clipped()

            Button {
                model.next()
            } label: {
                Image(systemName: "chevron.right")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(width: 36, height: 36)
                    .background(
                        Circle().fill(Color.white.opacity(model.canGoNext ? 0.2 : 0.06))
                    )
            }
            .buttonStyle(.plain)
            .disabled(!model.canGoNext)
            .opacity(model.canGoNext ? 1.0 : 0.35)
            .padding(.trailing, 12)
            .help(String(localized: "Next"))
            .accessibilityLabel(String(localized: "Next"))
        }
    }

    @ViewBuilder
    private func imageStage(for item: CarouselItem) -> some View {
        if !item.viewOnce,
           isLocalMediaStorePath(item.mediaPath),
           let nsImage = NSImage(contentsOfFile: item.mediaPath) {
            Image(nsImage: nsImage)
                .resizable()
                .scaledToFit()
                .scaleEffect(
                    x: (model.isFlippedHorizontally ? -1.0 : 1.0) * model.zoomScale,
                    y: (model.isFlippedVertically ? -1.0 : 1.0) * model.zoomScale
                )
                .rotationEffect(.degrees(Double(model.rotationDegrees)))
                .offset(panOffset)
                .gesture(
                    DragGesture()
                        .onChanged { value in
                            guard model.zoomScale > 1.0 else { return }
                            panOffset = CGSize(
                                width: dragStartOffset.width + value.translation.width,
                                height: dragStartOffset.height + value.translation.height
                            )
                        }
                        .onEnded { _ in
                            dragStartOffset = panOffset
                        }
                )
                .padding(16)
        } else {
            missingMediaPlaceholder(for: item)
        }
    }

    @ViewBuilder
    private func videoStage(for item: CarouselItem) -> some View {
        if !item.viewOnce, isLocalMediaStorePath(item.mediaPath) {
            InlineVideoPlayer(
                messageID: item.eventID,
                roomID: item.roomID,
                mediaPath: item.mediaPath,
                thumbnailPath: item.thumbnailPath,
                blurhash: item.blurhash.isEmpty ? nil : item.blurhash,
                width: item.width,
                height: item.height,
                durationMS: item.durationMS,
                isGIF: item.isGIF,
                onPopOutPiP: {
                    PictureInPictureController.shared.show(
                        PiPVideoItem(
                            messageID: item.eventID,
                            roomID: item.roomID,
                            mediaPath: item.mediaPath,
                            thumbnailPath: item.thumbnailPath,
                            blurhash: item.blurhash.isEmpty ? nil : item.blurhash,
                            title: item.fileName.isEmpty ? item.senderName : item.fileName,
                            width: item.width,
                            height: item.height,
                            durationMS: item.durationMS,
                            elapsedMS: 0,
                            isPlaying: model.isPlayingVideo
                        )
                    )
                },
                onOpenLightbox: {},
                initialIsPlaying: model.isPlayingVideo
            )
            .id("\(item.eventID)-\(model.isPlayingVideo)")
            .scaleEffect(
                x: (model.isFlippedHorizontally ? -1.0 : 1.0) * model.zoomScale,
                y: (model.isFlippedVertically ? -1.0 : 1.0) * model.zoomScale
            )
            .rotationEffect(.degrees(Double(model.rotationDegrees)))
            .padding(16)
        } else {
            missingMediaPlaceholder(for: item)
        }
    }

    private func missingMediaPlaceholder(for item: CarouselItem) -> some View {
        // An item with no local file yet is just not downloaded; only a file that will not open is an error.
        let notDownloaded = !item.viewOnce && item.mediaPath.isEmpty
        return VStack(spacing: 8) {
            Image(systemName: notDownloaded ? "photo" : "exclamationmark.triangle")
                .font(.system(size: 26, weight: .semibold))
                .foregroundStyle(.white.opacity(0.75))
            Text(
                notDownloaded
                    ? String(localized: "Not downloaded yet")
                    : String(localized: "Unable to load attachment")
            )
            .font(.callout.weight(.medium))
            .foregroundStyle(.white)
            if !item.fileName.isEmpty {
                Text(verbatim: item.fileName)
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.65))
                    .lineLimit(1)
            }
        }
        .frame(width: 280, height: 180)
        .background(RoundedRectangle(cornerRadius: 12).fill(Color.white.opacity(0.1)))
    }

    // MARK: - Bottom Bar (Transform Controls + Filmstrip)

    private var bottomBar: some View {
        VStack(spacing: 10) {
            HStack(spacing: 8) {
                transformButton(
                    label: String(localized: "Zoom Out"),
                    systemImage: "minus.magnifyingglass",
                    action: model.zoomOut
                )

                Button(action: model.resetTransform) {
                    Text(verbatim: "\(Int((model.zoomScale * 100).rounded()))%")
                        .font(.caption.monospacedDigit().weight(.semibold))
                        .foregroundStyle(.white)
                        .frame(minWidth: 48)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(RoundedRectangle(cornerRadius: 6).fill(Color.white.opacity(0.16)))
                }
                .buttonStyle(.plain)
                .help(String(localized: "Reset Zoom (100%)"))

                transformButton(
                    label: String(localized: "Zoom In"),
                    systemImage: "plus.magnifyingglass",
                    action: model.zoomIn
                )

                Divider()
                    .frame(height: 16)
                    .overlay(Color.white.opacity(0.25))

                transformButton(
                    label: String(localized: "Rotate 90°"),
                    systemImage: "rotate.right",
                    action: model.rotateClockwise
                )

                transformButton(
                    label: String(localized: "Flip Horizontally"),
                    systemImage: "arrow.left.and.right.righttriangle.left.righttriangle.right",
                    isActive: model.isFlippedHorizontally,
                    action: model.flipHorizontal
                )

                transformButton(
                    label: String(localized: "Flip Vertically"),
                    systemImage: "arrow.up.and.down.righttriangle.up.righttriangle.down",
                    isActive: model.isFlippedVertically,
                    action: model.flipVertical
                )
            }

            if model.items.count > 1 || model.isLoadingOlderItems {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        // The oldest end is the left: a spinner there until the next older page arrives.
                        if model.isLoadingOlderItems {
                            ProgressView()
                                .controlSize(.small)
                                .frame(width: 48, height: 48)
                                .accessibilityLabel(String(localized: "Loading older media"))
                        }
                        ForEach(Array(model.items.enumerated()), id: \.element.id) { index, thumbItem in
                            CarouselFilmstripTile(
                                item: thumbItem,
                                isSelected: index == model.currentIndex
                            ) {
                                model.select(index: index)
                            }
                        }
                    }
                    .padding(.horizontal, 8)
                }
                .frame(height: 54)
            }
        }
    }

    private func transformButton(
        label: String,
        systemImage: String,
        isActive: Bool = false,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: 28, height: 26)
                .background(
                    RoundedRectangle(cornerRadius: 6)
                        .fill(isActive ? Color.accentColor.opacity(0.75) : Color.white.opacity(0.14))
                )
        }
        .buttonStyle(.plain)
        .help(label)
        .accessibilityLabel(label)
    }

    // MARK: - Keyboard Shortcuts

    private var keyboardHandlingButtons: some View {
        Group {
            Button("", action: onClose)
                .keyboardShortcut(.cancelAction)
            Button("", action: model.previous)
                .keyboardShortcut(.leftArrow, modifiers: [])
            Button("", action: model.next)
                .keyboardShortcut(.rightArrow, modifiers: [])
            Button("") {
                guard let item = model.currentItem else { return }
                if item.kind == .video {
                    model.toggleVideoPlayback()
                } else {
                    onQuickLook(item)
                }
            }
            .keyboardShortcut(.space, modifiers: [])
            Button("", action: model.zoomIn)
                .keyboardShortcut("+", modifiers: [])
            Button("", action: model.zoomIn)
                .keyboardShortcut("=", modifiers: [])
            Button("", action: model.zoomOut)
                .keyboardShortcut("-", modifiers: [])
            Button("", action: model.resetTransform)
                .keyboardShortcut("0", modifiers: [])
            Button("") {
                if let item = model.currentItem {
                    onDownload(item)
                }
            }
            .keyboardShortcut("d", modifiers: [])
        }
        .opacity(0)
        .frame(width: 0, height: 0)
        .accessibilityHidden(true)
    }

    private static func initials(of name: String) -> String {
        let letters = name.split(whereSeparator: \.isWhitespace).prefix(2).compactMap {
            $0.first(where: { $0.isLetter || $0.isNumber })
        }
        guard !letters.isEmpty else { return "?" }
        return String(letters).uppercased()
    }
}

/// One thumbnail in the viewer's filmstrip. Until its thumbnail loads (a photo or video that is not downloaded yet) it
/// shows the symbol the main viewer's "not downloaded" placeholder uses for that kind, centred on the dark tile.
struct CarouselFilmstripTile: View {
    static let tileSize: CGFloat = 48
    /// The placeholder symbol is this fraction of the tile.
    static let placeholderSymbolFraction: CGFloat = 0.4

    let item: CarouselItem
    let isSelected: Bool
    let action: () -> Void

    /// The SF Symbol for media with nothing to show yet: `video` for a video, `photo` for an image or sticker.
    static func placeholderSymbol(for kind: MessageKind) -> String {
        kind == .video ? "video" : "photo"
    }

    private var thumbnail: NSImage? {
        guard !item.viewOnce, isLocalMediaStorePath(item.thumbnailPath) else { return nil }
        return NSImage(contentsOfFile: item.thumbnailPath)
    }

    var body: some View {
        Button(action: action) {
            ZStack {
                // A dark tile whatever the app's appearance, so the symbol is drawn for a dark background.
                Color(white: 0.16)
                if let nsImage = thumbnail {
                    Image(nsImage: nsImage)
                        .resizable()
                        .scaledToFill()
                    if item.kind == .video {
                        Image(systemName: "play.fill")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundStyle(.white)
                            .padding(4)
                            .background(Circle().fill(Color.black.opacity(0.6)))
                    }
                } else {
                    Image(systemName: Self.placeholderSymbol(for: item.kind))
                        .font(.system(size: Self.tileSize * Self.placeholderSymbolFraction))
                        .foregroundStyle(.secondary)
                        .accessibilityHidden(true)
                }
            }
            .environment(\.colorScheme, .dark)
            .frame(width: Self.tileSize, height: Self.tileSize)
            .clipShape(RoundedRectangle(cornerRadius: 6))
            .overlay(
                RoundedRectangle(cornerRadius: 6)
                    .strokeBorder(isSelected ? Color.accentColor : Color.white.opacity(0.2), lineWidth: isSelected ? 2 : 1)
            )
        }
        .buttonStyle(.plain)
    }
}

/// The photo's reactions in the viewer (emoji and count), read-only; reacting stays in the toolbar.
struct PhotoViewerReactionChips: View {
    let chips: [ReactionChip]
    @Environment(\.redactNamesAndPictures) private var isRedacted

    var body: some View {
        ViewThatFits(in: .horizontal) {
            row
            ScrollView(.horizontal, showsIndicators: false) { row }
        }
    }

    private var row: some View {
        HStack(spacing: 6) {
            ForEach(chips) { chip in
                HStack(spacing: 4) {
                    ReactionKeyView(chip: chip, size: 13)
                    Text(verbatim: "\(chip.count)")
                        .font(.caption.monospacedDigit())
                }
                .foregroundStyle(.white)
                .padding(.horizontal, 8)
                .padding(.vertical, 3)
                .background(Capsule().fill(chip.mine ? Color.accentColor.opacity(0.32) : Color.white.opacity(0.14)))
                .overlay(
                    Capsule().strokeBorder(
                        chip.mine ? Color.accentColor.opacity(0.75) : Color.white.opacity(0.18),
                        lineWidth: 1
                    )
                )
                .help(chip.tooltipText(redacted: isRedacted))
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(chip.summary(redacted: isRedacted))
                .accessibilityValue(String(chip.count))
            }
        }
    }
}
