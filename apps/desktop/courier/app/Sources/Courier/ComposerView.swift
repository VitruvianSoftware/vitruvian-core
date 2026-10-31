// Copyright 2026 VitruvianSoftware
// SPDX-License-Identifier: AGPL-3.0-or-later

import AppKit
import CourierCore
import SwiftUI
import UniformTypeIdentifiers

/// Picks files for the composer. ⌘O and the plus menu both come here.
@MainActor
enum AttachmentPicker {
    static func run(into composer: ComposerModel) {
        guard let urls = AppLockGate.shared.runOpenPanel(action: .send, lifecycle: composer.lifecycle, configure: { panel in
            panel.allowsMultipleSelection = true
            panel.canChooseFiles = true
            panel.canChooseDirectories = false
            panel.message = String(localized: "Choose files to send")
            panel.prompt = String(localized: "Attach")
        }) else { return }
        composer.attach(urls)
    }
}

/// What the composer's menus ask of the chat around it: the chat's composer offers Send Later and polls; the thread
/// pane's leaves them out.
struct ComposerMenus {
    var sendLater: (() -> Void)?
    var createPoll: (() -> Void)?
    /// Why Create Poll is greyed in this chat; nil when the chat takes polls.
    var pollsUnavailable: String?
}

/// What the composer's views share that is no model's: the selection (for the formatting bar), the picker row the
/// arrows are on, the members found for "@", a picker closed with Esc, and the link being written.
@MainActor
final class ComposerUI: ObservableObject {
    @Published var selection = NSRange(location: 0, length: 0)
    @Published var pickerIndex = 0
    @Published var members: [Member] = []
    /// A picker closed with Esc stays closed until what is typed after "@" or ";" changes.
    @Published var dismissedQuery: NSRange?
    @Published var link: LinkRequest?
    private var lockObserver: NSObjectProtocol?

    init() {
        lockObserver = NotificationCenter.default.addObserver(
            forName: SystemLifecycleModel.didLockNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.link = nil
            }
        }
    }

    deinit {
        if let lockObserver {
            NotificationCenter.default.removeObserver(lockObserver)
        }
    }
}

/// The bottom of a chat (01 §6's ComposeMessage): what is being replied to or edited, files waiting to go, the
/// formatting bar over a selection, the mention and quick-reply pickers, and the box with its plus and send menus.
struct ComposerView: View {
    @ObservedObject var composer: ComposerModel
    @ObservedObject var preferences: ComposerPreferences
    @Binding var textHeight: CGFloat
    /// Incognito is on and "Show the incognito mark in the message box" is too: the mark sits beside the box.
    var showsIncognitoMark = false
    /// When the open chat is a merged chat (`openMergedChat`), its definition; nil in a single-room chat.
    var mergedChat: MergedChat? = nil
    /// In a merged chat, the underlying room ID where replies are sent (Ruling 4).
    var activeReplyRoomID: String? = nil
    /// In a merged chat, the network ID of `activeReplyRoomID`.
    var activeReplyNetwork: String? = nil
    /// Optional account display label for `activeReplyRoomID` (e.g. phone number or handle).
    var activeReplyAccountName: String = ""
    /// Cycles `activeReplyRoomID` to the next room in `mergedChat` when the person clicks the reply-network pill.
    var onCycleReplyNetwork: () -> Void = {}
    var placeholder = String(localized: "Type a message…")
    var menus = ComposerMenus()
    /// Esc's use outside the composer, after the composer's own (leaving selection mode, closing the thread pane);
    /// true when it was used.
    var escapeFirst: () -> Bool = { false }
    var escapeLast: () -> Bool = { false }
    /// ↑ in an empty composer: edit my last message or move to the messages, as Settings ▸ Messages says. True when
    /// it was used.
    var upArrow: () -> Bool = { false }
    @StateObject private var ui = ComposerUI()

    static let voiceUserVisibleStrings: [String] = [
        String(localized: "Record Voice Note (⌘⇧A)"),
        String(localized: "Record voice note"),
        String(localized: "Stop recording"),
        String(localized: "Cancel recording"),
        String(localized: "Send voice note"),
        String(localized: "Voice note ready"),
        String(localized: "Discard recording"),
        String(localized: "Microphone access is turned off for Courier. Allow microphone access in System Settings to record voice notes."),
        String(localized: "Open System Settings"),
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach(Array(composer.notices.enumerated()), id: \.offset) { _, notice in
                NoticeBar(text: noticeText(notice)) { composer.dismissNotice() }
            }
            ComposerVoiceStatusBanner(voiceRecorder: composer.voiceRecorder)
            if let mergedChat, let activeNetwork = activeReplyNetwork, !activeNetwork.isEmpty {
                mergedReplyNetworkPill(mergedChat: mergedChat, activeNetwork: activeNetwork)
            }
            if case .editing = composer.mode {
                EditBar { _ = composer.escape() }
            }
            if let reply = composer.replyTarget {
                ReplyChip(quote: reply) { composer.cancelReply() }
            }
            if let pendingGIF = composer.pendingGIF {
                PendingGIFPillView(item: pendingGIF, thumbnailLoader: composer.thumbnailLoader) {
                    composer.removePendingGIF()
                }
            }
            if !composer.attachments.isEmpty {
                PendingAttachmentsStrip(
                    attachments: composer.attachments,
                    features: composer.features,
                    network: activeReplyNetwork ?? composer.network
                ) { id in
                    composer.removeAttachment(id)
                }
            }
            picker
            if showsFormattingBar {
                FormattingBarView(items: FormattingBar.items(features: composer.features, network: composer.network)) {
                    format($0)
                }
            }
            ComposerInputOrVoiceRow(
                composer: composer,
                preferences: preferences,
                voiceRecorder: composer.voiceRecorder
            ) {
                HStack(alignment: .bottom, spacing: 8) {
                    plusMenu
                    ComposerTextView(
                        composer: composer,
                        ui: ui,
                        height: $textHeight,
                        placeholder: placeholder,
                        focusToken: "\(composer.roomID ?? "")|\(composer.replyTarget?.eventID ?? "")|\(modeToken)",
                        isSpellcheckEnabled: preferences.enableSpellcheck,
                        onEscape: { escapeFirst() || composer.escape() || escapeLast() },
                        onUpArrow: upArrow,
                        onPasteFiles: { urls in
                            composer.attach(urls)
                            return true
                        })
                        .frame(height: textHeight)
                        .background(RoundedRectangle(cornerRadius: 10).fill(Color.primary.opacity(0.06)))
                        .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(.quaternary))

                    if showsIncognitoMark { IncognitoMark() }

                    if case .editing = composer.mode {
                        EmptyView()
                    } else {
                        secondaryActionButton
                        if preferences.primaryComposerButton != .gifPicker && preferences.secondaryComposerButton != .gifPicker {
                            gifToolbarButton
                        }
                        stickerToolbarButton
                    }

                    primaryActionButton

                    sendButton
                }
            }
        }
        .padding(10)
        .background(.bar)
        .sheet(item: $ui.link) { request in LinkDialog(request: request) }
        .onChange(of: composer.mentionQuery?.text) { _, _ in findMembers() }
        // ⌘⇧K, the bar's Link, or the Message menu's Link…: the dialog, over the range asked for.
        .onChange(of: composer.linkRequest) { _, request in
            if let request {
                ui.link = LinkRequest(composer: composer, range: request.range)
            } else {
                ui.link = nil
            }
        }
        .onChange(of: pickerToken) { _, _ in ui.pickerIndex = 0 }
    }

    // MARK: Parts

    private func mergedReplyNetworkPill(mergedChat: MergedChat, activeNetwork: String) -> some View {
        let displayName = NetworkNames.displayName(of: activeNetwork) ?? activeNetwork
        return HStack(spacing: 8) {
            Text(String(localized: "Replying via"))
                .font(.caption2)
                .foregroundStyle(.secondary)
            Button(action: onCycleReplyNetwork) {
                HStack(spacing: 5) {
                    NetworkBadge(network: activeNetwork, name: displayName, size: 13)
                    Text(displayName)
                        .font(.caption.weight(.semibold))
                    if !activeReplyAccountName.isEmpty {
                        Text(verbatim: "· \(activeReplyAccountName)")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                    Image(systemName: "chevron.up.chevron.down")
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundStyle(.secondary)
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 3)
                .background(Capsule().fill(Color.accentColor.opacity(0.14)))
                .overlay(Capsule().strokeBorder(Color.accentColor.opacity(0.45), lineWidth: 1))
            }
            .buttonStyle(.plain)
            .help(String(localized: "Switch the network your reply is sent on"))

            Spacer(minLength: 0)

            HStack(spacing: 4) {
                ForEach(Array(mergedChat.networks.enumerated()), id: \.offset) { _, net in
                    NetworkBadge(
                        network: net,
                        name: NetworkNames.displayName(of: net) ?? net,
                        size: 12
                    )
                    .opacity(net == activeNetwork ? 1.0 : 0.45)
                }
            }
        }
        .padding(.horizontal, 4)
    }

    private var modeToken: String {
        switch composer.mode {
        case .new: "new"
        case let .editing(id, _): "edit:\(id)"
        case let .thread(root): "thread:\(root)"
        }
    }

    private var showsFormattingBar: Bool {
        preferences.showFormattingMenu && ui.selection.length > 0 && ui.selection.location != NSNotFound
    }

    static let plusMenuMediaTitles = [
        String(localized: "Add Emoji…"),
        String(localized: "Add GIF…"),
        String(localized: "Add Sticker…"),
    ]

    /// The plus menu: Emoji, GIF (⌘⇧G), Sticker (⌘⌥⇧S), Add Attachment (⌘O), and in a chat Send Later… and Create Poll….
    private var plusMenu: some View {
        Menu {
            Button(String(localized: "Add Emoji…")) {
                composer.openEmojiAutocomplete()
                if composer.emojiQuery == nil {
                    NSApp.orderFrontCharacterPalette(nil)
                }
            }
            .disabled(composer.roomID == nil)
            Button(composer.addGIFMenuTitle) {
                if let dispatcher = composer.hotkeyDispatcher {
                    _ = dispatcher.perform("Message: Send GIF")
                } else {
                    _ = composer.openGIFPicker()
                }
            }
            .registryShortcut("Message: Send GIF", in: composer.hotkeyDispatcher?.hotkeys ?? HotkeyRegistry())
            .disabled(!composer.canSendGIF || composer.hotkeyDispatcher?.lifecycle.isLocked == true)
            .help(composer.canSendGIF ? "" : composer.sendGIFMenuTitle)
            Button(composer.addStickerMenuTitle) {
                if let dispatcher = composer.hotkeyDispatcher {
                    _ = dispatcher.perform("Message: Send Sticker")
                } else {
                    _ = composer.openStickerPicker()
                }
            }
            .registryShortcut("Message: Send Sticker", in: composer.hotkeyDispatcher?.hotkeys ?? HotkeyRegistry())
            .disabled(!composer.canSendSticker || composer.hotkeyDispatcher?.lifecycle.isLocked == true)
            .help(composer.canSendSticker ? "" : composer.sendStickerMenuTitle)
            Divider()
            Button(String(localized: "Add Attachment…")) { AttachmentPicker.run(into: composer) }
            if let sendLater = menus.sendLater { sendLaterItem(sendLater) }
            if let createPoll = menus.createPoll {
                Button(String(localized: "Create Poll…"), action: createPoll)
                    .disabled(menus.pollsUnavailable != nil || composer.roomID == nil)
                    .help(menus.pollsUnavailable ?? "")
            }
        } label: {
            Image(systemName: "plus.circle")
                .font(.title3)
                .frame(width: 28, height: 28)
        }
        .menuStyle(.button)
        .buttonStyle(.plain)
        .menuIndicator(.hidden)
        .fixedSize()
        .help(String(localized: "Attach files, send later, or create a poll"))
        .accessibilityLabel(String(localized: "More"))
    }

    /// Send Later…, or without a plan that has it, greyed with "Available with a plan".
    @ViewBuilder
    private func sendLaterItem(_ sendLater: @escaping () -> Void) -> some View {
        if composer.entitlement.isEntitled(.sendLater) {
            Button(String(localized: "Send Later…"), action: sendLater)
                .disabled(!composer.canSchedule)
        } else {
            Button(String(localized: "Send Later…")) {}
                .disabled(true)
            Button(String(localized: "Available with a plan")) {}
                .disabled(true)
        }
    }

    /// Send, with a menu (a right click) of Send Later… and Send and Archive (⌘↩).
    private var sendButton: some View {
        Button {
            composer.submit()
        } label: {
            Image(systemName: "arrow.up.circle.fill")
                .font(.system(size: 26))
                .foregroundStyle(composer.canSend ? Color.accentColor : Color.secondary.opacity(0.5))
        }
        .buttonStyle(.plain)
        .disabled(!composer.canSend)
        .contextMenu {
            if let sendLater = menus.sendLater { sendLaterItem(sendLater) }
            Button(String(localized: "Send and Archive")) { composer.submit(archive: true) }
                .disabled(!composer.canSend)
        }
        .help(String(localized: "Send (Return). Right-click for Send Later and Send and Archive."))
        .accessibilityLabel(String(localized: "Send"))
    }

    @ViewBuilder
    private var primaryActionButton: some View {
        switch preferences.primaryComposerButton {
        case .emojiPicker:
            emojiToolbarButton
        case .gifPicker:
            gifToolbarButton
        case .addAttachment:
            attachmentToolbarButton
        case .sendLater:
            sendLaterToolbarButton
        case .none:
            EmptyView()
        }
    }

    @ViewBuilder
    private var secondaryActionButton: some View {
        switch preferences.secondaryComposerButton {
        case .recordAudio:
            recordAudioToolbarButton
        case .gifPicker:
            gifToolbarButton
        case .addAttachment:
            attachmentToolbarButton
        case .sendLater:
            sendLaterToolbarButton
        case .none:
            EmptyView()
        }
    }

    private var emojiToolbarButton: some View {
        Button {
            composer.openEmojiAutocomplete()
            NSApp.orderFrontCharacterPalette(nil)
        } label: {
            Image(systemName: "face.smiling")
                .font(.title3)
                .frame(width: 28, height: 28)
        }
        .buttonStyle(.plain)
        .help(String(localized: "Emoji & Symbols (⌃⌘Space)"))
        .accessibilityLabel(String(localized: "Emoji and symbols"))
    }

    private var recordAudioToolbarButton: some View {
        Button {
            composer.preferences = preferences
            Task { await composer.startVoiceRecording() }
        } label: {
            Image(systemName: "mic")
                .font(.title3)
                .frame(width: 28, height: 28)
        }
        .buttonStyle(.plain)
        .disabled(composer.roomID == nil)
        .help(String(localized: "Record Voice Note (⌘⇧A)"))
        .accessibilityLabel(String(localized: "Record voice note"))
    }

    private var gifToolbarButton: some View {
        Button {
            _ = composer.openGIFPicker()
        } label: {
            Text(verbatim: "GIF")
                .font(.system(size: 9.5, weight: .bold, design: .rounded))
                .padding(.horizontal, 4)
                .padding(.vertical, 2)
                .overlay(
                    RoundedRectangle(cornerRadius: 4)
                        .strokeBorder(Color.primary.opacity(0.65), lineWidth: 1.2)
                )
                .frame(width: 28, height: 28)
        }
        .buttonStyle(.plain)
        .disabled(!composer.canSendGIF)
        .help(composer.canSendGIF ? String(localized: "Send GIF (⌘⇧G)") : composer.sendGIFMenuTitle)
        .accessibilityLabel(String(localized: "Send GIF"))
        .popover(isPresented: $composer.isGIFPickerPresented, arrowEdge: .top) {
            GIFPickerPopover(composer: composer)
        }
    }

    private var stickerToolbarButton: some View {
        Button {
            _ = composer.openStickerPicker()
        } label: {
            Image(systemName: "sparkles.rectangle.stack")
                .font(.title3)
                .frame(width: 28, height: 28)
        }
        .buttonStyle(.plain)
        .disabled(!composer.canSendSticker)
        .help(composer.canSendSticker ? String(localized: "Send Sticker (⌘⌥⇧S)") : composer.sendStickerMenuTitle)
        .accessibilityLabel(String(localized: "Send Sticker"))
        .popover(isPresented: $composer.isStickerPickerPresented, arrowEdge: .top) {
            StickerPickerPopover(composer: composer)
        }
    }

    private var attachmentToolbarButton: some View {
        Button {
            AttachmentPicker.run(into: composer)
        } label: {
            Image(systemName: "paperclip")
                .font(.title3)
                .frame(width: 28, height: 28)
        }
        .buttonStyle(.plain)
        .disabled(composer.roomID == nil)
        .help(String(localized: "Add Attachment (⌘O)"))
        .accessibilityLabel(String(localized: "Add Attachment"))
    }

    private var sendLaterToolbarButton: some View {
        Button {
            menus.sendLater?()
        } label: {
            Image(systemName: "clock.arrow.circlepath")
                .font(.title3)
                .frame(width: 28, height: 28)
        }
        .buttonStyle(.plain)
        .disabled(!composer.canSchedule || menus.sendLater == nil)
        .help(String(localized: "Send Later (⌘⇧L)"))
        .accessibilityLabel(String(localized: "Send Later"))
    }

    // MARK: Pickers

    /// Changes when the list a picker shows does.
    private var pickerToken: String {
        "\(composer.mentionQuery?.text ?? "")|\(composer.quickReplyQuery?.text ?? "")|\(ui.members.count)"
    }

    @ViewBuilder
    private var picker: some View {
        if let query = composer.mentionQuery, ui.dismissedQuery != query.range, !ui.members.isEmpty {
            MentionPicker(members: ui.members, index: ui.pickerIndex) { member in
                composer.insertMention(member, replacing: query.range)
            }
        } else if let query = composer.quickReplyQuery, ui.dismissedQuery != query.range,
                  !composer.quickReplyMatches.isEmpty {
            QuickReplyPicker(replies: composer.quickReplyMatches, index: ui.pickerIndex) { reply in
                composer.insertQuickReply(reply, replacing: query.range)
            }
        } else if composer.emojiQuery != nil {
            EmojiAutocompletePicker(composer: composer) { shortcode in
                composer.dismissEmojiAutocomplete()
                presentCustomEmojiImportPanel(shortcode: shortcode)
            }
        }
    }

    private func presentCustomEmojiImportPanel(shortcode: String) {
        StickerImportPicker.run(into: composer, shortcode: shortcode)
    }

    /// The people for what follows "@", once looked up; an answer for something typed since is dropped.
    private func findMembers() {
        guard let typed = composer.mentionQuery?.text else {
            ui.members = []
            return
        }
        Task {
            let found = await composer.mentionCandidates()
            if composer.mentionQuery?.text == typed { ui.members = found }
        }
    }

    // MARK: Keys

    private func format(_ kind: TextEntity.Kind) {
        composer.formattingKey(kind, in: ui.selection)
    }

    private func noticeText(_ notice: ComposerNotice) -> String {
        notice.displayText
    }
}

/// Incognito is on: an eye with a slash and "Incognito", beside the box, so the person knows nothing they read is
/// being told (02 §1.2's "Show incognito mode indicator").
private struct IncognitoMark: View {
    var body: some View {
        Label(String(localized: "Incognito"), systemImage: "eye.slash")
            .font(.caption.weight(.medium))
            .foregroundStyle(.secondary)
            .padding(.horizontal, 7)
            .padding(.vertical, 3)
            .background(Capsule().fill(Color.primary.opacity(0.07)))
            .fixedSize()
            .frame(height: 28)
            .help(String(localized: "Read receipts are off until you reply."))
            .accessibilityElement(children: .combine)
    }
}

private struct NoticeBar: View {
    let text: String
    let dismiss: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.orange)
            Text(text)
                .font(.callout)
                .frame(maxWidth: .infinity, alignment: .leading)
            Button(action: dismiss) {
                Image(systemName: "xmark")
            }
            .buttonStyle(.plain)
            .help(String(localized: "Dismiss"))
            .accessibilityLabel(String(localized: "Dismiss"))
        }
        .padding(8)
        .background(RoundedRectangle(cornerRadius: 8).fill(Color.orange.opacity(0.12)))
        .accessibilityElement(children: .combine)
    }
}

/// While a message is being edited: "Edit Message", and ✕ (or Esc) to stop, which puts back what was typed before.
struct EditBar: View {
    let cancel: () -> Void

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "pencil")
                .foregroundStyle(Color.accentColor)
            Text(String(localized: "Edit Message"))
                .font(.caption.weight(.semibold))
            Spacer(minLength: 0)
            Button(action: cancel) {
                Image(systemName: "xmark.circle.fill")
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
            .help(String(localized: "Cancel editing (Esc)"))
            .accessibilityLabel(String(localized: "Cancel editing"))
        }
        .accessibilityElement(children: .contain)
    }
}

/// Staged GIF pill shown above the composer text field when `preferences.autoSendGIFs == false`.
private struct PendingGIFPillView: View {
    let item: StickerItemWire
    let thumbnailLoader: ThumbnailLoader?
    let onRemove: () -> Void
    @State private var loadedThumbnail: CGImage?

    var body: some View {
        HStack(spacing: 8) {
            ZStack {
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(Color.primary.opacity(0.08))
                    .frame(width: 40, height: 40)

                if let cgImage = loadedThumbnail {
                    Image(decorative: cgImage, scale: 2.0, orientation: .up)
                        .resizable()
                        .scaledToFill()
                        .frame(width: 40, height: 40)
                        .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                } else if let emoji = item.emoji, !emoji.isEmpty {
                    Text(verbatim: emoji)
                        .font(.system(size: 20))
                } else {
                    Image(systemName: "play.rectangle.fill")
                        .font(.system(size: 16))
                        .foregroundStyle(.secondary)
                }
            }

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 5) {
                    Text(verbatim: "GIF")
                        .font(.system(size: 9, weight: .bold, design: .rounded))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 5)
                        .padding(.vertical, 1)
                        .background(Capsule().fill(Color.accentColor))
                    Text(item.name)
                        .font(.caption.weight(.semibold))
                        .lineLimit(1)
                }
                Text(String(localized: "Press Return to send with your caption"))
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer(minLength: 4)

            Button(action: onRemove) {
                Image(systemName: "xmark.circle.fill")
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
            .help(String(localized: "Remove GIF"))
            .accessibilityLabel(String(localized: "Remove GIF"))
        }
        .padding(6)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(Color.primary.opacity(0.05))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .strokeBorder(Color.primary.opacity(0.12), lineWidth: 1)
        )
        .task(id: item.mediaURL) {
            guard loadedThumbnail == nil,
                  let path = ThumbnailLoader.resolveMediaPath(item.mediaURL)
            else { return }
            let loader = thumbnailLoader ?? .shared
            loadedThumbnail = await loader.thumbnail(atPath: path)?.image
        }
    }
}

/// The message being replied to, above the box. Esc or the button clears it.
private struct ReplyChip: View {
    let quote: QuotedMessage
    let clear: () -> Void

    var body: some View {
        HStack(spacing: 8) {
            Rectangle().fill(Color.accentColor).frame(width: 3)
            VStack(alignment: .leading, spacing: 1) {
                Text(quote.mine ? String(localized: "Replying to yourself")
                    : String(localized: "Replying to \(quote.senderName)"))
                    .font(.caption.weight(.semibold))
                Text(summary)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer(minLength: 0)
            Button(action: clear) {
                Image(systemName: "xmark.circle.fill")
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
            .help(String(localized: "Clear quoted message (Esc)"))
            .accessibilityLabel(String(localized: "Clear quoted message"))
        }
        .fixedSize(horizontal: false, vertical: true)
        .accessibilityElement(children: .contain)
    }

    private var summary: String {
        if !quote.text.isEmpty { return quote.text }
        switch quote.kind {
        case .image: return String(localized: "Image")
        case .video: return String(localized: "Video")
        case .voiceNote: return String(localized: "Voice note")
        case .file: return String(localized: "File")
        case .sticker: return String(localized: "Sticker")
        default: return ""
        }
    }
}

// MARK: - The text box

/// The composer's box (01 §6's Bubble): plain text that the formatting ranges are drawn over (bold, italic, code on
/// a tint, a quote's bar, a list's bullets, links, mention chips, spoilers on a tint). Return sends; Shift, Option or
/// Control with it adds a line, which in a quote or list goes on in it. The formatting keys work here, never ⌘K or
/// ⌘F (search's). With a picker open, ↑ ↓ move in it, Return or Tab choose, and Esc closes it. It grows with its text
/// up to a limit, and scrolls past that.
struct ComposerTextView: NSViewRepresentable {
    static let minimumHeight: CGFloat = 34
    private static let maximumHeight: CGFloat = 180

    let composer: ComposerModel
    @ObservedObject var ui: ComposerUI
    @Binding var height: CGFloat
    let placeholder: String
    /// Changes whenever the box should take the keyboard: another chat, a reply or an edit started.
    let focusToken: String
    var isSpellcheckEnabled: Bool = true
    let onEscape: () -> Bool
    /// ↑ in an empty box; true when it was used.
    let onUpArrow: () -> Bool
    let onPasteFiles: ([URL]) -> Bool

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeNSView(context: Context) -> NSScrollView {
        let scroll = NSScrollView()
        scroll.drawsBackground = false
        scroll.hasVerticalScroller = true
        scroll.autohidesScrollers = true
        scroll.borderType = .noBorder

        let textView = PlainTextView()
        textView.delegate = context.coordinator
        textView.isRichText = false
        textView.importsGraphics = false
        textView.usesFontPanel = false
        // ⌘F belongs to search (InboxCommands, MainWindow), so the box has no Find bar or panel of its own.
        textView.usesFindBar = false
        textView.usesFindPanel = false
        textView.allowsUndo = true
        textView.drawsBackground = false
        textView.isAutomaticQuoteSubstitutionEnabled = false
        textView.isAutomaticDashSubstitutionEnabled = false
        textView.isAutomaticLinkDetectionEnabled = false
        textView.isContinuousSpellCheckingEnabled = isSpellcheckEnabled
        textView.font = PlainTextView.baseFont
        textView.textColor = .labelColor
        textView.typingAttributes = PlainTextView.baseAttributes
        textView.textContainerInset = NSSize(width: 6, height: 7)
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = false
        textView.autoresizingMask = [.width]
        textView.textContainer?.widthTracksTextView = true
        textView.textContainer?.containerSize = NSSize(width: 0, height: CGFloat.greatestFiniteMagnitude)
        textView.placeholder = placeholder
        textView.onPasteFiles = { context.coordinator.parent.onPasteFiles($0) }
        textView.onFormat = { context.coordinator.format($0, typed: $1) }
        textView.onKeyboard = { [weak composer] has in
            if composer?.hasKeyboard != has { composer?.hasKeyboard = has }
        }
        textView.setAccessibilityLabel(placeholder)
        scroll.documentView = textView
        context.coordinator.textView = textView
        context.coordinator.sync()
        return scroll
    }

    func updateNSView(_ scroll: NSScrollView, context: Context) {
        context.coordinator.parent = self
        guard let textView = context.coordinator.textView else { return }
        if textView.isContinuousSpellCheckingEnabled != isSpellcheckEnabled {
            textView.isContinuousSpellCheckingEnabled = isSpellcheckEnabled
        }
        context.coordinator.sync()
        textView.placeholder = placeholder
        context.coordinator.updateHeight()
        if context.coordinator.lastFocusToken != focusToken {
            context.coordinator.lastFocusToken = focusToken
            DispatchQueue.main.async { textView.window?.makeFirstResponder(textView) }
        }
    }

    @MainActor
    final class Coordinator: NSObject, NSTextViewDelegate {
        var parent: ComposerTextView
        weak var textView: PlainTextView?
        var lastFocusToken: String?
        /// The edit the text view is making, between its "should change" and "did change": the caret moves before
        /// the text changes, and the model hears of the move only after the change, so a pending format holds.
        private var editing: (range: NSRange, length: Int)?
        private var inEdit = false
        /// The model's text is being put into the view: the view's own notices of it are not news.
        private var applying = false
        private var styled: (text: String, entities: [TextEntity])?
        private var caretSerial = 0

        init(_ parent: ComposerTextView) {
            self.parent = parent
        }

        private var composer: ComposerModel { parent.composer }

        /// The model's text, formatting and caret, into the view, when they differ from what it shows.
        func sync() {
            guard let textView else { return }
            if textView.string != composer.text, !textView.hasMarkedText() {
                applying = true
                textView.string = composer.text
                textView.undoManager?.removeAllActions()
                applying = false
                report(selection: textView.selectedRange())
            }
            if let request = composer.caretRequest, request.serial != caretSerial {
                caretSerial = request.serial
                let location = min(request.location, (textView.string as NSString).length)
                applying = true
                textView.setSelectedRange(NSRange(location: location, length: 0))
                applying = false
                report(selection: textView.selectedRange())
            }
            restyle()
        }

        /// Draws the formatting ranges over the text, when they or the text changed.
        private func restyle() {
            guard let textView, !textView.hasMarkedText() else { return }
            if let styled, styled.text == textView.string, styled.entities == composer.entities { return }
            styled = (textView.string, composer.entities)
            textView.apply(composer.entities)
        }

        private func report(selection: NSRange) {
            composer.selectionChanged(to: selection)
            if parent.ui.selection != selection { parent.ui.selection = selection }
        }

        func textView(_ textView: NSTextView, shouldChangeTextIn range: NSRange, replacementString: String?) -> Bool {
            if !applying {
                inEdit = true
                editing = (range, (replacementString as NSString?)?.length ?? 0)
            }
            return true
        }

        func textDidChange(_ notification: Notification) {
            guard let textView, !applying else { return }
            if let edit = editing {
                composer.textChanged(to: textView.string, replacing: edit.range, with: edit.length)
            } else if composer.text != textView.string {
                composer.text = textView.string
            }
            editing = nil
            inEdit = false
            report(selection: textView.selectedRange())
            restyle()
            updateHeight()
        }

        func textViewDidChangeSelection(_ notification: Notification) {
            guard let textView, !applying, !inEdit else { return }
            report(selection: textView.selectedRange())
        }

        func updateHeight() {
            guard let textView, let layout = textView.layoutManager, let container = textView.textContainer else { return }
            layout.ensureLayout(for: container)
            let content = layout.usedRect(for: container).height + textView.textContainerInset.height * 2
            let wanted = min(ComposerTextView.maximumHeight, max(ComposerTextView.minimumHeight, content.rounded(.up)))
            if abs(parent.height - wanted) > 0.5 {
                let binding = parent.$height
                DispatchQueue.main.async { binding.wrappedValue = wanted }
            }
        }

        /// A formatting key on the text view's selection. A kind the chat doesn't keep says why (a toast); the link
        /// key asks for the dialog. ` is a key only where code is kept: elsewhere it types `.
        func format(_ kind: TextEntity.Kind, typed: Bool) -> Bool {
            guard composer.hotkeyDispatcher?.lifecycle.isLocked != true else { return false }
            guard let textView else { return false }
            if typed, !composer.features.keeps(kind) { return false }
            composer.formattingKey(kind, in: textView.selectedRange())
            restyle()
            return true
        }

        // MARK: Pickers

        private var openPicker: (count: Int, choose: (Int) -> Void, range: NSRange)? {
            let ui = parent.ui
            if let query = composer.mentionQuery, ui.dismissedQuery != query.range, !ui.members.isEmpty {
                let members = ui.members
                return (members.count, { [composer] in composer.insertMention(members[$0], replacing: query.range) },
                        query.range)
            }
            if let query = composer.quickReplyQuery, ui.dismissedQuery != query.range {
                let replies = composer.quickReplyMatches
                guard !replies.isEmpty else { return nil }
                return (replies.count, { [composer] in composer.insertQuickReply(replies[$0], replacing: query.range) },
                        query.range)
            }
            return nil
        }

        func textView(_ textView: NSTextView, doCommandBy selector: Selector) -> Bool {
            guard composer.hotkeyDispatcher?.lifecycle.isLocked != true else { return true }
            if composer.emojiQuery != nil {
                switch selector {
                case #selector(NSResponder.moveUp(_:)):
                    guard !composer.emojiCandidates.isEmpty else { break }
                    composer.moveEmojiSelection(-1)
                    return true
                case #selector(NSResponder.moveDown(_:)):
                    guard !composer.emojiCandidates.isEmpty else { break }
                    composer.moveEmojiSelection(1)
                    return true
                case #selector(NSResponder.insertNewline(_:)), #selector(NSResponder.insertTab(_:)):
                    guard !composer.emojiCandidates.isEmpty else { break }
                    let idx = min(max(composer.selectedEmojiIndex, 0), composer.emojiCandidates.count - 1)
                    composer.pickEmoji(composer.emojiCandidates[idx])
                    return true
                case #selector(NSResponder.cancelOperation(_:)):
                    composer.dismissEmojiAutocomplete()
                    return true
                default:
                    break
                }
            }
            if let picker = openPicker {
                let ui = parent.ui
                switch selector {
                case #selector(NSResponder.moveUp(_:)):
                    ui.pickerIndex = (ui.pickerIndex - 1 + picker.count) % picker.count
                    return true
                case #selector(NSResponder.moveDown(_:)):
                    ui.pickerIndex = (ui.pickerIndex + 1) % picker.count
                    return true
                case #selector(NSResponder.insertNewline(_:)), #selector(NSResponder.insertTab(_:)):
                    picker.choose(min(ui.pickerIndex, picker.count - 1))
                    return true
                case #selector(NSResponder.cancelOperation(_:)):
                    ui.dismissedQuery = picker.range
                    return true
                default:
                    break
                }
            }
            switch selector {
            case #selector(NSResponder.insertNewline(_:)),
                 #selector(NSResponder.insertNewlineIgnoringFieldEditor(_:)),
                 #selector(NSResponder.insertLineBreak(_:)):
                // While a character is still being composed, Return belongs to the input method.
                guard !textView.hasMarkedText() else { return false }
                // The key's modifiers decide: Return sends, with Shift, Option or Control it adds a line. The
                // system maps some of those to the other two commands itself, which are always a line.
                let flags = NSApp.currentEvent?.modifierFlags ?? []
                var modifiers: KeyModifiers = []
                if flags.contains(.shift) { modifiers.insert(.shift) }
                if flags.contains(.option) { modifiers.insert(.option) }
                if flags.contains(.control) { modifiers.insert(.control) }
                if flags.contains(.command) { modifiers.insert(.command) }
                if selector != #selector(NSResponder.insertNewline(_:)) { modifiers.insert(.option) }
                if composer.handleReturn(modifiers: modifiers) == .newline,
                   composer.beginNewline(at: textView.selectedRange()) {
                    textView.insertText("\n", replacementRange: textView.selectedRange())
                }
                return true
            case #selector(NSResponder.moveUp(_:)):
                // ↑ in an empty box: edit my last message, or move to the messages (Settings ▸ Messages).
                guard textView.string.isEmpty else { return false }
                return parent.onUpArrow()
            case #selector(NSResponder.cancelOperation(_:)):
                // Esc closes what is open, in order. Either way it is handled here: left to the text view, it
                // would open the word-completion list.
                _ = parent.onEscape()
                return true
            default:
                return false
            }
        }
    }
}

/// An NSTextView that shows a placeholder when empty, takes files that are pasted, draws formatting ranges over
/// plain text, and takes the formatting keys.
final class PlainTextView: NSTextView {
    static let baseFont = NSFont.preferredFont(forTextStyle: .body)
    static var baseAttributes: [NSAttributedString.Key: Any] {
        [.font: baseFont, .foregroundColor: NSColor.labelColor]
    }

    var placeholder = "" {
        didSet { needsDisplay = true }
    }
    var onPasteFiles: ([URL]) -> Bool = { _ in false }
    /// A formatting key was pressed (`typed` for `, which is also a character); false lets the key do what it
    /// otherwise does.
    var onFormat: (TextEntity.Kind, _ typed: Bool) -> Bool = { _, _ in false }
    /// The box has the keyboard in the key window, or no longer has it.
    var onKeyboard: (Bool) -> Void = { _ in }
    /// The quotes and lists, whose bars and bullets are drawn in the margin.
    private var decorations: [TextEntity] = []
    private var windowObservers: [NSObjectProtocol] = []

    override func becomeFirstResponder() -> Bool {
        let became = super.becomeFirstResponder()
        DispatchQueue.main.async { [weak self] in self?.tellKeyboard() }
        return became
    }

    override func resignFirstResponder() -> Bool {
        let resigned = super.resignFirstResponder()
        DispatchQueue.main.async { [weak self] in self?.tellKeyboard() }
        return resigned
    }

    /// Its window becoming key or not changes whether it has the keyboard too.
    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        for observer in windowObservers { NotificationCenter.default.removeObserver(observer) }
        windowObservers = []
        guard let window else {
            onKeyboard(false)
            return
        }
        for name in [NSWindow.didBecomeKeyNotification, NSWindow.didResignKeyNotification] {
            windowObservers.append(NotificationCenter.default.addObserver(
                forName: name, object: window, queue: .main) { [weak self] _ in
                Task { @MainActor in self?.tellKeyboard() }
            })
        }
        tellKeyboard()
    }

    private func tellKeyboard() {
        onKeyboard(window?.isKeyWindow == true && window?.firstResponder === self)
    }
    private static let indent: CGFloat = 16

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        drawDecorations()
        guard string.isEmpty, !placeholder.isEmpty, !hasMarkedText() else { return }
        let origin = NSPoint(x: textContainerInset.width + (textContainer?.lineFragmentPadding ?? 0),
                             y: textContainerInset.height)
        (placeholder as NSString).draw(at: origin, withAttributes: [
            .font: font ?? Self.baseFont,
            .foregroundColor: NSColor.placeholderTextColor,
        ])
    }

    /// The formatting ranges as attributes of the text (the text itself never changes). Lists and quotes are
    /// indented, and their bullets, numbers and bars drawn beside them.
    func apply(_ entities: [TextEntity]) {
        guard let storage = textStorage else { return }
        let length = storage.length
        storage.beginEditing()
        storage.setAttributes(Self.baseAttributes, range: NSRange(location: 0, length: length))
        let manager = NSFontManager.shared
        for entity in entities where entity.offset >= 0 && entity.offset + entity.length <= length {
            let range = entity.range
            switch entity.kind {
            case .bold, .italic:
                let trait: NSFontTraitMask = entity.kind == .bold ? .boldFontMask : .italicFontMask
                storage.enumerateAttribute(.font, in: range) { value, part, _ in
                    let font = value as? NSFont ?? Self.baseFont
                    storage.addAttribute(.font, value: manager.convert(font, toHaveTrait: trait), range: part)
                }
            case .strikethrough:
                storage.addAttribute(.strikethroughStyle, value: NSUnderlineStyle.single.rawValue, range: range)
            case .code, .pre:
                storage.addAttribute(.font, value: NSFont.monospacedSystemFont(ofSize: Self.baseFont.pointSize,
                                                                               weight: .regular), range: range)
                storage.addAttribute(.backgroundColor, value: NSColor.quaternaryLabelColor, range: range)
            case .blockquote:
                storage.addAttribute(.foregroundColor, value: NSColor.secondaryLabelColor, range: range)
                storage.addAttribute(.paragraphStyle, value: Self.indented, range: range)
            case .bulletList, .orderedList:
                storage.addAttribute(.paragraphStyle, value: Self.indented, range: range)
            case .link:
                storage.addAttribute(.foregroundColor, value: NSColor.linkColor, range: range)
                storage.addAttribute(.underlineStyle, value: NSUnderlineStyle.single.rawValue, range: range)
            case .mention:
                storage.addAttribute(.foregroundColor, value: NSColor.controlAccentColor, range: range)
                storage.addAttribute(.backgroundColor, value: NSColor.controlAccentColor.withAlphaComponent(0.16),
                                     range: range)
            case .spoiler:
                storage.addAttribute(.backgroundColor, value: NSColor.tertiaryLabelColor, range: range)
            }
        }
        storage.endEditing()
        typingAttributes = Self.baseAttributes
        decorations = entities.filter { [.blockquote, .bulletList, .orderedList].contains($0.kind) }
        needsDisplay = true
    }

    private static let indented: NSParagraphStyle = {
        let style = NSMutableParagraphStyle()
        style.firstLineHeadIndent = indent
        style.headIndent = indent
        return style
    }()

    /// A quote's bar and a list's bullets or numbers, in the indent beside each line.
    private func drawDecorations() {
        guard !decorations.isEmpty, let layout = layoutManager, let container = textContainer else { return }
        let text = string as NSString
        let x = textContainerInset.width + container.lineFragmentPadding
        for block in decorations where block.offset + block.length <= text.length {
            var number = 0
            var start = block.offset
            while start <= block.offset + block.length {
                let line = text.lineRange(for: NSRange(location: start, length: 0))
                let glyph = layout.glyphIndexForCharacter(at: min(line.location, max(text.length - 1, 0)))
                var rect = layout.lineFragmentRect(forGlyphAt: glyph, effectiveRange: nil)
                rect.origin.y += textContainerInset.height
                if block.kind == .blockquote {
                    NSColor.tertiaryLabelColor.setFill()
                    NSBezierPath(roundedRect: NSRect(x: x + 2, y: rect.minY + 2, width: 3, height: rect.height - 4),
                                 xRadius: 1.5, yRadius: 1.5).fill()
                } else {
                    number += 1
                    let mark = block.kind == .bulletList ? "•" : "\(number)."
                    (mark as NSString).draw(at: NSPoint(x: x, y: rect.minY), withAttributes: [
                        .font: Self.baseFont, .foregroundColor: NSColor.secondaryLabelColor,
                    ])
                }
                let next = line.location + line.length
                guard next > start else { break }
                start = next
                if start >= block.offset + block.length { break }
            }
        }
    }

    /// The formatting keys (Task 12's table): ⌘B, ⌘I, ⌘⇧X, ⌘⌥C, ⌘⇧9, ⌘⇧8, ⌘⇧7, ⌘⇧K. Never ⌘K or ⌘F.
    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        guard window?.firstResponder === self, let kind = Self.formatKind(for: event) else {
            return super.performKeyEquivalent(with: event)
        }
        return onFormat(kind, false) || super.performKeyEquivalent(with: event)
    }

    static func formatKind(for event: NSEvent) -> TextEntity.Kind? {
        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask).subtracting([.capsLock, .numericPad,
                                                                                              .function])
        let key = event.charactersIgnoringModifiers?.lowercased() ?? ""
        switch flags {
        case [.command]:
            switch key {
            case "b": return .bold
            case "i": return .italic
            default: return nil
            }
        case [.command, .shift]:
            // The digits by where they are: ⇧ turns their characters into symbols.
            switch event.keyCode {
            case 0x19: return .blockquote // 9
            case 0x1C: return .bulletList // 8
            case 0x1A: return .orderedList // 7
            default: break
            }
            switch key {
            case "x": return .strikethrough
            case "k": return .link
            default: return nil
            }
        case [.command, .option]:
            return event.keyCode == 0x08 ? .pre : nil // C
        default:
            return nil
        }
    }

    /// ` over a selection makes it code; with none, it types `.
    override func keyDown(with event: NSEvent) {
        let flags = event.modifierFlags.intersection([.command, .control, .option])
        if flags.isEmpty, event.characters == "`", selectedRange().length > 0, !hasMarkedText(), onFormat(.code, true) {
            return
        }
        super.keyDown(with: event)
    }

    private static func files(on pasteboard: NSPasteboard) -> [URL] {
        (pasteboard.readObjects(forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true]) as? [URL]) ?? []
    }

    /// Files dropped on the box are attached; left to the text view, their paths would be typed into the text.
    override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation {
        Self.files(on: sender.draggingPasteboard).isEmpty ? super.draggingEntered(sender) : .copy
    }

    override func draggingUpdated(_ sender: NSDraggingInfo) -> NSDragOperation {
        Self.files(on: sender.draggingPasteboard).isEmpty ? super.draggingUpdated(sender) : .copy
    }

    override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
        let files = Self.files(on: sender.draggingPasteboard)
        if !files.isEmpty, onPasteFiles(files) { return true }
        return super.performDragOperation(sender)
    }

    override func paste(_ sender: Any?) {
        let files = Self.files(on: NSPasteboard.general)
        if !files.isEmpty, onPasteFiles(files) { return }
        // Plain text only: formatting from the other app is left behind.
        pasteAsPlainText(sender)
    }
}

// MARK: - Voice Recording UI

struct BrandStopButton: View {
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            ZStack {
                Circle()
                    .fill(Color.red.opacity(0.16))
                    .frame(width: 30, height: 30)
                Circle()
                    .strokeBorder(Color.red.opacity(0.55), lineWidth: 1.5)
                    .frame(width: 30, height: 30)
                RoundedRectangle(cornerRadius: 3, style: .continuous)
                    .fill(Color.red)
                    .frame(width: 11, height: 11)
            }
        }
        .buttonStyle(.plain)
        .help(String(localized: "Stop recording to review"))
        .accessibilityLabel(String(localized: "Stop recording"))
    }
}

private struct ComposerVoiceStatusBanner: View {
    @ObservedObject var voiceRecorder: VoiceRecorderModel

    var body: some View {
        switch voiceRecorder.state {
        case .permissionDenied:
            HStack(spacing: 10) {
                Image(systemName: "mic.slash.fill")
                    .foregroundStyle(.orange)
                Text(String(localized: "Microphone access is turned off for Courier. Allow microphone access in System Settings to record voice notes."))
                    .font(.callout)
                    .foregroundStyle(.primary)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 4)
                Button(String(localized: "Open System Settings")) {
                    if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Microphone") {
                        NSWorkspace.shared.open(url)
                    }
                }
                .controlSize(.small)
                Button {
                    voiceRecorder.dismissBanner()
                } label: {
                    Image(systemName: "xmark")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(String(localized: "Dismiss"))
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .background(RoundedRectangle(cornerRadius: 8).fill(Color.orange.opacity(0.12)))
            .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(Color.orange.opacity(0.35), lineWidth: 1))
        case let .failed(reason):
            NoticeBar(text: reason) {
                voiceRecorder.dismissBanner()
            }
        case .idle, .recording, .reviewing:
            EmptyView()
        }
    }
}

private struct ComposerInputOrVoiceRow<IdleContent: View>: View {
    @ObservedObject var composer: ComposerModel
    @ObservedObject var preferences: ComposerPreferences
    @ObservedObject var voiceRecorder: VoiceRecorderModel
    @ViewBuilder let idleContent: () -> IdleContent

    var body: some View {
        switch voiceRecorder.state {
        case let .recording(_, elapsedMS, levels):
            ComposerVoiceRecordingBar(
                elapsedMS: elapsedMS,
                levels: levels,
                onCancel: {
                    Task { await voiceRecorder.cancel() }
                },
                onStopForReview: {
                    Task { await voiceRecorder.stopForReview() }
                },
                onSend: {
                    Task { await voiceRecorder.stopAndSend(using: composer) }
                }
            )
        case let .reviewing(_, durationMS, waveform):
            ComposerVoiceReviewBar(
                durationMS: durationMS,
                waveform: waveform,
                onCancel: {
                    Task { await voiceRecorder.cancel() }
                },
                onSend: {
                    Task { await voiceRecorder.stopAndSend(using: composer) }
                }
            )
        case .idle, .permissionDenied, .failed:
            idleContent()
        }
    }
}

private struct ComposerVoiceRecordingBar: View {
    let elapsedMS: Int
    let levels: [Int]
    let onCancel: () -> Void
    let onStopForReview: () -> Void
    let onSend: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            Button(action: onCancel) {
                Image(systemName: "trash")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(.secondary)
                    .frame(width: 28, height: 28)
                    .background(Circle().fill(Color.primary.opacity(0.08)))
            }
            .buttonStyle(.plain)
            .keyboardShortcut(.escape, modifiers: [])
            .help(String(localized: "Cancel recording (Esc)"))
            .accessibilityLabel(String(localized: "Cancel recording"))

            HStack(spacing: 6) {
                Circle()
                    .fill(Color.red)
                    .frame(width: 8, height: 8)
                Text(Self.formatElapsed(elapsedMS))
                    .font(.system(.callout, design: .monospaced).weight(.semibold))
                    .monospacedDigit()
                    .foregroundStyle(.primary)
            }

            ComposerLiveWaveformStrip(levels: levels, tint: .red)
                .frame(maxWidth: .infinity, minHeight: 26, maxHeight: 26)

            BrandStopButton(action: onStopForReview)

            Button(action: onSend) {
                Image(systemName: "arrow.up.circle.fill")
                    .font(.system(size: 26))
                    .foregroundStyle(Color.accentColor)
            }
            .buttonStyle(.plain)
            .keyboardShortcut(.return, modifiers: [])
            .help(String(localized: "Send voice note (Return)"))
            .accessibilityLabel(String(localized: "Send voice note"))
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(RoundedRectangle(cornerRadius: 10).fill(Color.primary.opacity(0.06)))
        .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(Color.red.opacity(0.35), lineWidth: 1))
    }

    static func formatElapsed(_ milliseconds: Int) -> String {
        let totalSeconds = max(0, milliseconds / 1000)
        let minutes = totalSeconds / 60
        let seconds = totalSeconds % 60
        return String(format: "%d:%02d", minutes, seconds)
    }
}

private struct ComposerVoiceReviewBar: View {
    let durationMS: Int
    let waveform: [Int]
    let onCancel: () -> Void
    let onSend: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            Button(action: onCancel) {
                Image(systemName: "trash")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(.secondary)
                    .frame(width: 28, height: 28)
                    .background(Circle().fill(Color.primary.opacity(0.08)))
            }
            .buttonStyle(.plain)
            .keyboardShortcut(.escape, modifiers: [])
            .help(String(localized: "Discard recording (Esc)"))
            .accessibilityLabel(String(localized: "Discard recording"))

            HStack(spacing: 6) {
                Image(systemName: "waveform")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(Color.accentColor)
                Text(String(localized: "Voice note ready"))
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.primary)
                Text(ComposerVoiceRecordingBar.formatElapsed(durationMS))
                    .font(.system(.caption, design: .monospaced))
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
            }

            ComposerLiveWaveformStrip(levels: waveform, tint: .accentColor)
                .frame(maxWidth: .infinity, minHeight: 26, maxHeight: 26)

            Button(action: onSend) {
                HStack(spacing: 4) {
                    Text(String(localized: "Send"))
                        .font(.callout.weight(.semibold))
                    Image(systemName: "arrow.up.circle.fill")
                        .font(.system(size: 20))
                }
                .foregroundStyle(.white)
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .background(Capsule().fill(Color.accentColor))
            }
            .buttonStyle(.plain)
            .keyboardShortcut(.return, modifiers: [])
            .help(String(localized: "Send voice note (Return)"))
            .accessibilityLabel(String(localized: "Send voice note"))
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(RoundedRectangle(cornerRadius: 10).fill(Color.primary.opacity(0.06)))
        .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(Color.accentColor.opacity(0.35), lineWidth: 1))
    }
}

private struct ComposerLiveWaveformStrip: View {
    let levels: [Int]
    let tint: Color

    private static let displayBars = 36

    var body: some View {
        let visible = Array(levels.suffix(Self.displayBars))
        HStack(alignment: .center, spacing: 3) {
            ForEach(0 ..< Self.displayBars, id: \.self) { index in
                let sampleIndex = index - (Self.displayBars - visible.count)
                let hasSample = sampleIndex >= 0 && sampleIndex < visible.count
                let level = hasSample ? max(0, min(100, visible[sampleIndex])) : 10
                let normalized = CGFloat(level) / 100.0
                let height = max(4, 4 + normalized * 18)
                Capsule(style: .continuous)
                    .fill(hasSample ? tint.opacity(0.85) : Color.secondary.opacity(0.22))
                    .frame(width: 3, height: height)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
