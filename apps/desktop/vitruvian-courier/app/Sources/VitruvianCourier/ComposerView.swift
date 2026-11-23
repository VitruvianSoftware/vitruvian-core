// Copyright 2026 VitruvianSoftware
// SPDX-License-Identifier: AGPL-3.0-or-later

import AppKit
import VitruvianCourierCore
import SwiftUI
import UniformTypeIdentifiers

/// Picks files or photos for the composer. ⌘O and the inline `+` tool row both come here.
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

    static func runPhotos(into composer: ComposerModel) {
        guard let urls = AppLockGate.shared.runOpenPanel(action: .send, lifecycle: composer.lifecycle, configure: { panel in
            panel.allowsMultipleSelection = true
            panel.canChooseFiles = true
            panel.canChooseDirectories = false
            panel.allowedContentTypes = [.image]
            panel.message = String(localized: "Choose photos to send")
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
        String(localized: "Microphone access is turned off for Vitruvian Courier. Allow microphone access in System Settings to record voice notes."),
        String(localized: "Open System Settings"),
    ]

    @Environment(\.drawsLiquidGlass) private var drawsLiquidGlass
    @Environment(\.themeAccentColor) private var themeAccent
    @Environment(\.accessibilityReduceMotion) private var accessibilityReduceMotion
    @State private var isPlusHovering = false
    /// The tool row's buttons exist while it is open and while it slides closed.
    @State private var isToolRowMounted = false
    /// Set when the row is opened by keyboard, until the first tool has taken focus.
    @State private var focusFirstTool = false
    /// Counts up to give the text box the keyboard when the row closes.
    @State private var textFocusRequest = 0
    @StateObject private var emojiHover = EmojiPickerHoverCoordinator()
    @State private var emojiAnchorView: NSView?
    /// "It's late — send this later?" is dismissed for the rest of the session, in every chat.
    @ObservedObject private var nudgeSession = SendLaterNudgeSession.shared

    private var reduceMotionEnabled: Bool {
        accessibilityReduceMotion || NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
    }

    private var toolRowAnimation: Animation {
        .easeOut(duration: ComposerToolRowMotion.duration)
    }

    /// What the row's layout (and so the text field) animates with: nothing under Reduce Motion, where the field
    /// snaps and only the row's opacity fades.
    private var toolRowLayoutAnimation: Animation? {
        ComposerToolRowMotion.fieldGlides(reduceMotion: reduceMotionEnabled) ? toolRowAnimation : nil
    }

    /// Opens or closes the row. Keyboard opening moves focus to the first tool; closing hands it back to the text.
    private func setToolRow(open: Bool, byKeyboard: Bool = false, refocusText: Bool = true) {
        composer.isToolRowOpen = open
        if open {
            if byKeyboard { focusFirstTool = true }
        } else {
            focusFirstTool = false
            if refocusText { textFocusRequest += 1 }
        }
    }

    private var toolRowNaturalWidth: CGFloat {
        ComposerToolRowMetrics.toolsWidth(count: toolRowItems.count) + 12
    }

    private var effectiveNetwork: String {
        (activeReplyNetwork?.isEmpty == false ? activeReplyNetwork : nil) ?? composer.network
    }

    private var toolRowItems: [ComposerToolItem] {
        composer.toolRowItems(
            offersSendLater: menus.sendLater != nil || composer.hotkeyDispatcher != nil,
            offersPoll: menus.createPoll != nil
        )
    }

    /// Late at night, with a message that can be scheduled in the box, and Send Later on offer.
    private var showsSendLaterNudge: Bool {
        menus.sendLater != nil && composer.entitlement.isEntitled(.sendLater)
            && SendLaterNudge.shows(hasText: composer.canSchedule, now: Date(), dismissed: nudgeSession.dismissed)
    }

    /// The message box's height at one line, with glass: the text's height and the field's padding above and below.
    static let floatingFieldPadding: CGFloat = 4
    static var floatingSingleLineHeight: CGFloat { ComposerTextView.minimumHeight + 2 * floatingFieldPadding }

    var body: some View {
        // The GIF picker is a strip in the chat, just above the message box (with glass, the box's own side margins).
        VStack(spacing: 0) {
            if composer.isGIFPickerPresented {
                GIFPickerStrip(composer: composer)
                    .padding(.horizontal, drawsLiquidGlass ? 12 : 0)
                    .padding(.top, drawsLiquidGlass ? 6 : 0)
                    .transition(.opacity)
            }
            Group {
                if drawsLiquidGlass { floating } else { bar }
            }
        }
        .onChange(of: composer.isGIFPickerPresented) { _, open in if !open { textFocusRequest += 1 } }
        .onChange(of: composer.isEmojiPickerPresented) { _, open in
            let restoreFocus = !open && emojiHover.shouldRestoreTextFocusOnClose
            emojiHover.syncPresented(open, composer: composer, anchor: emojiAnchorView)
            if restoreFocus { textFocusRequest += 1 }
        }
        .onDisappear { emojiHover.dismiss() }
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

    /// Without glass: a bar under the messages, across the pane, the look before the option.
    private var bar: some View {
        VStack(alignment: .leading, spacing: 8) {
            extras
            inputRow(floating: false)
        }
        .padding(10)
        .courierSurface(.composerBar)
    }

    /// With glass, as Messages draws it: the box (its text, its buttons and what sits above them) in one glass shape,
    /// and the plus a round glass button just left of it, together floating 12 points in from the pane's sides and
    /// bottom, over the messages that scroll under them.
    private var floating: some View {
        CourierGlassGroup(spacing: 8) {
            ComposerToolRowLayout(
                reveal: composer.isToolRowOpen ? 1 : 0,
                rowNatural: toolRowNaturalWidth,
                gap: 8,
                rowHeight: Self.floatingSingleLineHeight
            ) {
                ComposerIdleOnly(voiceRecorder: composer.voiceRecorder) {
                    plusToggleButton(floating: true)
                        .courierSurface(.composerButton)
                        .layoutValue(key: ComposerRowRoleKey.self, value: .plus)
                    toolRowSlot(floating: true)
                        .layoutValue(key: ComposerRowRoleKey.self, value: .row)
                }
                VStack(alignment: .leading, spacing: 8) {
                    extras
                    inputRow(floating: true)
                }
                .padding(.leading, isEditingMessage ? 12 : 10)
                .padding(.trailing, Self.floatingFieldPadding + 1)
                .padding(.vertical, Self.floatingFieldPadding)
                .courierSurface(.composerField(singleLineHeight: Self.floatingSingleLineHeight))
                .layoutValue(key: ComposerRowRoleKey.self, value: .field)
            }
            .animation(toolRowLayoutAnimation, value: composer.isToolRowOpen)
        }
        .padding(.horizontal, 12)
        .padding(.top, 6)
        .padding(.bottom, 12)
        .onChange(of: composer.isToolRowOpen, initial: true) { _, open in syncToolRowMount(open: open) }
    }

    /// Keeps the row's buttons in the view while it slides closed, then drops them (and their key views).
    private func syncToolRowMount(open: Bool) {
        if open {
            isToolRowMounted = true
        } else {
            Task { @MainActor in
                try? await Task.sleep(for: .seconds(ComposerToolRowMotion.duration + 0.05))
                if !composer.isToolRowOpen { isToolRowMounted = false }
            }
        }
    }

    private func toolRowSlot(floating: Bool) -> some View {
        let height = floating ? Self.floatingSingleLineHeight : ComposerTextView.minimumHeight
        return ComposerToolRowSlot(
            isOpen: composer.isToolRowOpen,
            isMounted: isToolRowMounted || composer.isToolRowOpen,
            natural: toolRowNaturalWidth,
            height: height,
            fade: toolRowAnimation
        ) {
            inlineToolRow(floating: floating)
                .padding(.horizontal, 6)
                .frame(height: height)
        }
        .modifier(ToolRowSurface(isFloating: floating, isMounted: isToolRowMounted || composer.isToolRowOpen))
    }

    /// What sits above the text: notices, the voice note's state, the network a merged chat replies on, the edit or
    /// the reply, files and a GIF waiting to go, a picker, and the formatting bar.
    @ViewBuilder
    private var extras: some View {
        ForEach(Array(composer.notices.enumerated()), id: \.offset) { _, notice in
            NoticeBar(text: noticeText(notice)) { composer.dismissNotice() }
        }
        if composer.isAIWriting {
            aiWritingRow
        }
        if let aiResult = composer.aiResult {
            aiResultStrip(aiResult)
        }
        if let aiError = composer.aiError {
            aiErrorStrip(aiError)
        }
        ComposerTalkToTypeBanner(talkToType: composer.talkToType)
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
        if showsSendLaterNudge, let sendLater = menus.sendLater {
            SendLaterNudgeBar(sendLater: sendLater) { nudgeSession.dismissed = true }
        }
        picker
        if showsFormattingBar {
            FormattingBarView(items: FormattingBar.items(features: composer.features, network: composer.network)) {
                format($0)
            }
        }
    }

    /// The text and its buttons, or while a voice note is recorded, its bar. Without glass, "+" and its inline
    /// tool row sit beside the field; with glass, "+" and the expanded tool row float beside the box (`floating`).
    private func inputRow(floating: Bool) -> some View {
        ComposerInputOrVoiceRow(
            composer: composer,
            preferences: preferences,
            voiceRecorder: composer.voiceRecorder
        ) {
            if floating {
                fieldRow(floating: true)
            } else {
                ComposerToolRowLayout(
                    reveal: composer.isToolRowOpen ? 1 : 0,
                    rowNatural: toolRowNaturalWidth,
                    gap: 6,
                    rowHeight: ComposerTextView.minimumHeight
                ) {
                    plusToggleButton(floating: false)
                        .layoutValue(key: ComposerRowRoleKey.self, value: .plus)
                    toolRowSlot(floating: false)
                        .layoutValue(key: ComposerRowRoleKey.self, value: .row)
                    fieldRow(floating: false)
                        .layoutValue(key: ComposerRowRoleKey.self, value: .field)
                }
                .animation(toolRowLayoutAnimation, value: composer.isToolRowOpen)
                .onChange(of: composer.isToolRowOpen, initial: true) { _, open in syncToolRowMount(open: open) }
            }
        }
    }

    /// The text, its badge and the buttons that sit with it, ending in Send, which never leaves the row.
    private func fieldRow(floating: Bool) -> some View {
        HStack(alignment: .bottom, spacing: 6) {
            textView(floating: floating)

            if showsIncognitoMark { IncognitoMark() }

            primaryActionButton

            if !isEditingMessage {
                secondaryActionButton
            }

            sendButton(floating: floating)
        }
    }

    @ViewBuilder
    private var networkFieldBadge: some View {
        if !effectiveNetwork.isEmpty {
            let displayName = NetworkNames.displayName(of: effectiveNetwork) ?? effectiveNetwork
            NetworkBadge(
                network: effectiveNetwork,
                name: displayName,
                size: 16,
                showsTooltip: true,
                ringed: false
            )
            .accessibilityIdentifier("composer.field.networkBadge")
        }
    }

    /// The text with the network badge at its leading edge: in its own rounded box without glass; with glass the
    /// glass shape around it is the box.
    @ViewBuilder
    private func textView(floating: Bool) -> some View {
        let field = HStack(alignment: .top, spacing: 0) {
            if !effectiveNetwork.isEmpty {
                networkFieldBadge
                    .padding(.leading, floating ? 2 : 8)
                    .frame(height: ComposerTextView.minimumHeight)
            }
            ComposerTextView(
                composer: composer,
                ui: ui,
                height: $textHeight,
                placeholder: placeholder,
                focusToken: "\(composer.roomID ?? "")|\(composer.replyTarget?.eventID ?? "")|\(modeToken)|\(textFocusRequest)",
                isSpellcheckEnabled: preferences.enableSpellcheck,
                onEscape: { escapeFirst() || composer.escape() || escapeLast() },
                onUpArrow: upArrow,
                onPasteFiles: { urls in
                    composer.attach(urls)
                    return true
                })
                .frame(minWidth: ComposerToolRowMetrics.fieldHardMinimumWidth)
                .frame(height: textHeight)
        }
        if floating {
            field
        } else {
            field
                .background(RoundedRectangle(cornerRadius: 10).fill(Color.primary.opacity(0.06)))
                .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(.quaternary))
        }
    }

    // MARK: Parts

    private var aiWritingRow: some View {
        HStack(spacing: 8) {
            ProgressView()
                .controlSize(.small)
            Text(String(localized: "Writing…"))
                .font(.caption)
                .foregroundStyle(.secondary)
            Spacer(minLength: 0)
            Button(String(localized: "Cancel")) {
                composer.cancelAI()
            }
            .buttonStyle(.borderless)
            .font(.caption)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(Color.secondary.opacity(0.11))
        )
    }

    private func aiResultStrip(_ result: ComposerAIResult) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(AIOutputFormatter.attributed(result.text))
                .font(.callout)
                .foregroundStyle(.primary)
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)

            HStack(spacing: 10) {
                Text(result.provenance)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                Spacer(minLength: 0)
                Button(String(localized: "Replace")) {
                    composer.replaceWithAIResult()
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
                Button(String(localized: "Insert")) {
                    composer.insertAIResult()
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                Button(String(localized: "Discard")) {
                    composer.discardAIResult()
                }
                .buttonStyle(.borderless)
                .font(.caption)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(Color.secondary.opacity(0.11))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .strokeBorder(Color.secondary.opacity(0.22), lineWidth: 0.5)
        )
    }

    private func aiErrorStrip(_ errorText: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.caption)
                .foregroundStyle(.orange)
            Text(errorText)
                .font(.caption)
                .foregroundStyle(.primary)
                .lineLimit(2)
            Spacer(minLength: 0)
            Button(String(localized: "Retry")) {
                composer.retryLastAI()
            }
            .buttonStyle(.borderless)
            .font(.caption.weight(.medium))
            Button(String(localized: "Open AI Settings")) {
                composer.onOpenAISettings()
            }
            .buttonStyle(.borderless)
            .font(.caption)
            Button {
                composer.dismissAIError()
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
            .courierTooltip(String(localized: "Dismiss"), edge: .top)
            .accessibilityLabel(String(localized: "Dismiss"))
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(Color.orange.opacity(0.12))
        )
    }

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
                .background(Capsule().fill(themeAccent.opacity(0.14)))
                .overlay(Capsule().strokeBorder(themeAccent.opacity(0.45), lineWidth: 1))
            }
            .buttonStyle(.plain)
            .courierTooltip(String(localized: "Switch the network your reply is sent on"), edge: .top)

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

    private var isEditingMessage: Bool {
        if case .editing = composer.mode { return true }
        return false
    }

    /// Toggles the inline tool row beside the text field; rotates 45° into ✕ (or cross-fades under Reduce Motion).
    /// An AppKit key view behind it puts it in the Tab loop; Space or Return there opens the row and moves focus
    /// to its first tool.
    private func plusToggleButton(floating: Bool) -> some View {
        let usesMotion = ComposerToolRowMotion.usesSlideAndRotation(reduceMotion: reduceMotionEnabled)
        let side = floating ? Self.floatingSingleLineHeight : 28
        return Button {
            setToolRow(open: !composer.isToolRowOpen, refocusText: false)
        } label: {
            Group {
                if usesMotion {
                    Image(systemName: "plus")
                        .rotationEffect(
                            .degrees(
                                ComposerToolRowMotion.plusRotationDegrees(
                                    isOpen: composer.isToolRowOpen,
                                    reduceMotion: reduceMotionEnabled
                                )
                            )
                        )
                } else {
                    ZStack {
                        Image(systemName: "plus").opacity(composer.isToolRowOpen ? 0 : 1)
                        Image(systemName: "xmark").opacity(composer.isToolRowOpen ? 1 : 0)
                    }
                    .animation(toolRowAnimation, value: composer.isToolRowOpen)
                }
            }
            .font(floating ? .title3.weight(.medium) : .system(size: 15))
            .foregroundStyle(floating ? .primary : .secondary)
            .frame(width: side, height: side)
            .background {
                if !floating {
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .fill(isPlusHovering ? Color.primary.opacity(0.08) : .clear)
                        .animation(
                            reduceMotionEnabled ? nil : .easeInOut(duration: HoverFillMotion.duration),
                            value: isPlusHovering
                        )
                }
            }
            .contentShape(floating ? AnyShape(Circle()) : AnyShape(Rectangle()))
            .frame(
                width: side,
                height: floating ? Self.floatingSingleLineHeight : ComposerTextView.minimumHeight
            )
            .onHover { isPlusHovering = $0 }
        }
        .buttonStyle(.plain)
        .courierTooltip(
            composer.isToolRowOpen ? String(localized: "Close tools") : String(localized: "More tools"),
            edge: .top
        )
        .accessibilityLabel(composer.isToolRowOpen ? String(localized: "Close tools") : String(localized: "More tools"))
        .accessibilityIdentifier("composer.plus")
        .background(
            ComposerKeyProxy(
                accessibilityID: "composer.plus",
                isCircle: floating,
                onActivate: { setToolRow(open: !composer.isToolRowOpen, byKeyboard: true, refocusText: false) },
                onEscape: { if composer.isToolRowOpen { setToolRow(open: false) } }
            )
            .frame(
                width: side,
                height: floating ? Self.floatingSingleLineHeight : ComposerTextView.minimumHeight
            )
        )
        .overlay(
            Color.clear
                .allowsHitTesting(false)
                .popover(isPresented: $composer.isStickerPickerPresented, arrowEdge: .top) {
                    StickerPickerPopover(composer: composer)
                }
        )
    }

    /// The single inline home for composer tools: Attach file, Photo, GIF, Sticker, Voice note, Send Later, Poll,
    /// Location, AI.
    private func inlineToolRow(floating: Bool) -> some View {
        let height = floating ? Self.floatingSingleLineHeight : ComposerTextView.minimumHeight
        let items = toolRowItems
        return HStack(alignment: .center, spacing: ComposerToolRowMetrics.toolSpacing) {
            ForEach(Array(items.enumerated()), id: \.element.id) { index, item in
                toolRowButton(for: item, height: height, isFirst: index == 0)
            }
        }
    }

    private func closeToolRowFromTool(refocusText: Bool = true) {
        setToolRow(open: false, refocusText: refocusText)
    }

    /// One icon in the tool row, as a real key view: reachable by Tab, Space or Return presses it, Escape closes.
    private func toolKeyButton(
        _ item: ComposerToolItem,
        symbolName: String,
        tooltip: String,
        tooltipShortcut: String? = nil,
        tooltipDetail: String? = nil,
        accessibilityTitle: String,
        height: CGFloat,
        isFirst: Bool,
        refocusText: Bool = true,
        action: @escaping () -> Void
    ) -> some View {
        ComposerToolKeyButton(
            symbolName: symbolName,
            tooltip: tooltip,
            tooltipShortcut: tooltipShortcut,
            tooltipDetail: tooltipDetail,
            accessibilityTitle: accessibilityTitle,
            accessibilityID: item.kind.accessibilityIdentifier,
            isEnabled: item.isEnabled,
            disabledHint: item.disabledReason,
            height: height,
            wantsFocus: isFirst && focusFirstTool,
            onFocused: { focusFirstTool = false },
            onEscape: { closeToolRowFromTool() }
        ) {
            closeToolRowFromTool(refocusText: refocusText)
            action()
        }
    }

    @ViewBuilder
    private func toolRowButton(for item: ComposerToolItem, height: CGFloat, isFirst: Bool) -> some View {
        switch item.kind {
        case .attachFile:
            toolKeyButton(
                item, symbolName: "paperclip", tooltip: String(localized: "Attach File"),
                tooltipShortcut: "⌘O",
                accessibilityTitle: String(localized: "Attach File"), height: height, isFirst: isFirst
            ) { AttachmentPicker.run(into: composer) }
        case .photo:
            toolKeyButton(
                item, symbolName: "photo", tooltip: String(localized: "Photo"),
                accessibilityTitle: String(localized: "Photo"), height: height, isFirst: isFirst
            ) { AttachmentPicker.runPhotos(into: composer) }
        case .gif:
            toolKeyButton(
                item, symbolName: "play.rectangle", tooltip: String(localized: "Send GIF"),
                tooltipShortcut: "⌘⇧G",
                accessibilityTitle: String(localized: "Send GIF"), height: height, isFirst: isFirst,
                refocusText: false
            ) {
                if let dispatcher = composer.hotkeyDispatcher {
                    _ = dispatcher.perform("Message: Send GIF")
                } else {
                    _ = composer.openGIFPicker()
                }
            }
        case .sticker:
            toolKeyButton(
                item, symbolName: "face.dashed", tooltip: String(localized: "Send Sticker"),
                tooltipShortcut: "⌘⌥⇧S",
                accessibilityTitle: String(localized: "Send Sticker"), height: height, isFirst: isFirst,
                refocusText: false
            ) {
                if let dispatcher = composer.hotkeyDispatcher {
                    _ = dispatcher.perform("Message: Send Sticker")
                } else {
                    _ = composer.openStickerPicker()
                }
            }
        case .voiceNote:
            toolKeyButton(
                item, symbolName: "mic", tooltip: String(localized: "Record Voice Note"),
                tooltipShortcut: "⌘⇧A",
                accessibilityTitle: String(localized: "Record voice note"), height: height, isFirst: isFirst
            ) {
                composer.preferences = preferences
                Task { await composer.startVoiceRecording() }
            }
        case .sendLater:
            toolKeyButton(
                item, symbolName: "clock.arrow.circlepath",
                tooltip: String(localized: "Send Later"),
                tooltipShortcut: "⌘⇧L",
                tooltipDetail: item.disabledReason,
                accessibilityTitle: String(localized: "Send Later"), height: height, isFirst: isFirst
            ) {
                if let sendLater = menus.sendLater {
                    sendLater()
                } else {
                    _ = composer.hotkeyDispatcher?.perform("Message: Send Later")
                }
            }
        case .poll:
            toolKeyButton(
                item, symbolName: "chart.bar", tooltip: String(localized: "Create Poll"),
                accessibilityTitle: String(localized: "Create Poll"), height: height, isFirst: isFirst
            ) { menus.createPoll?() }
        case .location:
            toolKeyButton(
                item, symbolName: "location", tooltip: String(localized: "Share Location"),
                accessibilityTitle: String(localized: "Share Location"), height: height, isFirst: isFirst
            ) {
                if composer.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    composer.text = "/location "
                }
            }
        case .ai:
            ComposerToolKeyButton(
                symbolName: "sparkles",
                tooltip: String(localized: "AI & Dictation"),
                accessibilityTitle: String(localized: "AI & Dictation"),
                accessibilityID: item.kind.accessibilityIdentifier,
                isEnabled: item.isEnabled,
                height: height,
                wantsFocus: isFirst && focusFirstTool,
                onFocused: { focusFirstTool = false },
                menuProvider: { aiNSMenu() },
                onEscape: { closeToolRowFromTool() },
                action: {}
            )
        }
    }

    /// Talk to Type / Draft a reply / Rewrite, as a menu the AI tool pops up (by mouse or keyboard).
    private func aiNSMenu() -> NSMenu {
        let locked = composer.isLocked || composer.hotkeyDispatcher?.lifecycle.isLocked == true
        let aiAvailable = composer.aiProvider.isAvailable
        let menu = NSMenu()
        menu.autoenablesItems = false

        let talk = ComposerClosureMenuItem(title: String(localized: "Talk to Type")) {
            closeToolRowFromTool()
            composer.triggerTalkToType()
        }
        talk.isEnabled = composer.roomID != nil && !locked
        menu.addItem(talk)

        let draft = ComposerClosureMenuItem(title: String(localized: "Draft a reply")) {
            closeToolRowFromTool()
            if composer.aiProvider.isAvailable {
                composer.draftWithAI(tone: nil)
            } else {
                composer.onOpenAISettings()
            }
        }
        draft.isEnabled = composer.roomID != nil && !locked && aiAvailable
        if !aiAvailable { draft.toolTip = String(localized: "Set up AI in Settings") }
        menu.addItem(draft)

        let rewrite = NSMenuItem(title: String(localized: "Rewrite…"), action: nil, keyEquivalent: "")
        let tones = NSMenu()
        tones.autoenablesItems = false
        for tone in AIRewriteTone.allCases {
            tones.addItem(
                ComposerClosureMenuItem(title: tone.label) {
                    closeToolRowFromTool()
                    if composer.aiProvider.isAvailable {
                        composer.draftWithAI(tone: tone)
                    } else {
                        composer.onOpenAISettings()
                    }
                })
        }
        rewrite.submenu = tones
        rewrite.isEnabled = composer.roomID != nil && !locked && aiAvailable
        if !aiAvailable { rewrite.toolTip = String(localized: "Set up AI in Settings") }
        menu.addItem(rewrite)
        return menu
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

    /// Always-visible circular send button: quiet grey + muted arrow when empty, solid accent + white arrow when sendable,
    /// easing over 0.12 s. Right-click opens Send Later… and Send and Archive (⌘↩).
    @ViewBuilder
    private func sendButton(floating _: Bool) -> some View {
        let appearance = composer.sendButtonAppearance
        let fillColor: Color = appearance.fillStyle == .solidAccent
            ? themeAccent
            : Color(nsColor: .systemGray).opacity(appearance.fillOpacity)
        let arrowColor: Color = appearance.arrowStyle == .white ? .white : .secondary
        let colorDuration = ComposerSendButtonAppearance.colorAnimationDuration(reduceMotion: reduceMotionEnabled)
        let colorAnimation: Animation? = colorDuration > 0 ? .easeInOut(duration: colorDuration) : nil

        Button {
            composer.submit()
        } label: {
            ZStack {
                Circle()
                    .fill(fillColor)
                    .frame(width: 28, height: 28)
                Image(systemName: "arrow.up")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(arrowColor)
            }
            .animation(colorAnimation, value: appearance)
            .frame(width: 28, height: ComposerTextView.minimumHeight)
            .contentShape(Circle())
        }
        .courierSendButtonStyle()
        .disabled(!composer.canSend)
        .contextMenu {
            if let sendLater = menus.sendLater { sendLaterItem(sendLater) }
            Button(String(localized: "Send and Archive")) { composer.submit(archive: true) }
                .disabled(!composer.canSend)
        }
        .courierTooltip(
            String(localized: "Send"),
            shortcut: "Return",
            detail: String(localized: "Right-click for Send Later and Send and Archive."),
            edge: .top
        )
        .accessibilityLabel(String(localized: "Send"))
        .accessibilityHint(composer.canSend ? "" : String(localized: "Write a message first"))
        .accessibilityIdentifier("composer.send")
    }

    @ViewBuilder
    private var primaryActionButton: some View {
        switch preferences.primaryComposerButton {
        case .emojiPicker:
            emojiToolbarButton
        case .sendLater:
            sendLaterToolbarButton
        case .none:
            EmptyView()
        }
    }

    @ViewBuilder
    private var secondaryActionButton: some View {
        switch preferences.effectiveSecondaryComposerButton {
        case .emojiPicker:
            emojiToolbarButton
        case .sendLater:
            sendLaterToolbarButton
        case .none:
            EmptyView()
        }
    }

    private var emojiToolbarButton: some View {
        let isAccented = emojiHover.isIconAccented || composer.isEmojiPickerPresented
        return ComposerToolbarIconButton(
            symbolName: "face.smiling",
            tooltipTitle: String(localized: "Emoji"),
            tooltipShortcut: "⌃⌘Space",
            tooltipDetail: String(localized: "Opens Emoji & Symbols"),
            showsTooltip: !composer.isEmojiPickerPresented,
            accessibilityTitle: String(localized: "Emoji and symbols"),
            accessibilityID: "composer.toolbar.emoji",
            isEnabled: true,
            isActive: isAccented,
            height: ComposerTextView.minimumHeight,
            onHoverChange: { inside in
                emojiHover.buttonHoverChanged(inside, composer: composer, anchor: emojiAnchorView)
            }
        ) {
            emojiHover.buttonClicked(composer: composer, anchor: emojiAnchorView)
        }
        .background(EmojiButtonAnchorProbe { emojiAnchorView = $0 })
    }

    private var sendLaterToolbarButton: some View {
        let reason = composer.sendLaterDisabledReason
        let canUse = composer.canSchedule && menus.sendLater != nil
        return ComposerToolbarIconButton(
            symbolName: "clock.arrow.circlepath",
            tooltipTitle: String(localized: "Send Later"),
            tooltipShortcut: "⌘⇧L",
            tooltipDetail: reason,
            accessibilityTitle: String(localized: "Send Later"),
            accessibilityID: "composer.toolbar.sendLater",
            isEnabled: canUse,
            disabledHint: reason,
            height: ComposerTextView.minimumHeight
        ) {
            menus.sendLater?()
        }
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
        } else if !composer.isAIWriting, composer.aiResult == nil, !composer.slashCommandSuggestions.isEmpty {
            HStack(spacing: 8) {
                ForEach(composer.slashCommandSuggestions) { cmd in
                    Button {
                        composer.executeSlashCommand(cmd.trigger)
                    } label: {
                        HStack(spacing: 5) {
                            Text(cmd.trigger)
                                .font(.system(.caption, design: .monospaced).weight(.semibold))
                            Text(cmd.title)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(
                            Capsule()
                                .fill(Color.secondary.opacity(0.12))
                        )
                    }
                    .buttonStyle(.plain)
                    .courierTooltip(cmd.summary, edge: .top)
                }
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 4)
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

/// Zero-hit-test NSView probe capturing the anchor view for the floating emoji picker panel.
private struct EmojiButtonAnchorProbe: NSViewRepresentable {
    let onView: (NSView) -> Void

    func makeNSView(context _: Context) -> ProbeNSView {
        let view = ProbeNSView()
        view.onView = onView
        return view
    }

    func updateNSView(_ view: ProbeNSView, context _: Context) {
        view.onView = onView
        DispatchQueue.main.async { onView(view) }
    }

    final class ProbeNSView: NSView {
        var onView: ((NSView) -> Void)?

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            if window != nil { onView?(self) }
        }

        override func hitTest(_: NSPoint) -> NSView? { nil }
    }
}

/// A 15pt outline SF Symbol icon button inside a 28pt hit area, with secondary colour and subtle eased hover highlight.
/// When `disabledHint` is non-nil while disabled, `.disabled` is omitted so the tooltip and hint remain available.
private struct ComposerToolbarIconButton: View {
    let symbolName: String
    let tooltipTitle: String
    var tooltipShortcut: String? = nil
    var tooltipDetail: String? = nil
    var showsTooltip: Bool = true
    let accessibilityTitle: String
    let accessibilityID: String
    var isEnabled: Bool = true
    var isActive: Bool = false
    var disabledHint: String? = nil
    var height: CGFloat = ComposerTextView.minimumHeight
    var onHoverChange: ((Bool) -> Void)? = nil
    let action: () -> Void
    @State private var isHovering = false
    @Environment(\.accessibilityReduceMotion) private var accessibilityReduceMotion
    @Environment(\.themeAccentColor) private var themeAccent

    private var reduceMotionEnabled: Bool {
        accessibilityReduceMotion || NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
    }

    var body: some View {
        let shouldSystemDisable = !isEnabled && disabledHint == nil
        Button {
            guard isEnabled else { return }
            action()
        } label: {
            Image(systemName: symbolName)
                .symbolVariant(.none)
                .font(.system(size: 15))
                .foregroundStyle(isActive ? themeAccent : Color.secondary)
                .animation(
                    reduceMotionEnabled ? nil : .easeInOut(duration: EmojiPickerHoverMotion.iconTintDuration),
                    value: isActive
                )
                .opacity(isEnabled ? 1 : 0.42)
                .frame(width: 28, height: 28)
                .background(
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .fill(isHovering && isEnabled ? Color.primary.opacity(0.08) : .clear)
                        .animation(
                            reduceMotionEnabled ? nil : .easeInOut(duration: HoverFillMotion.duration),
                            value: isHovering
                        )
                )
                .contentShape(Rectangle())
                .frame(width: 28, height: height)
        }
        .buttonStyle(.plain)
        .disabled(shouldSystemDisable)
        .onHover { inside in
            isHovering = inside
            onHoverChange?(inside)
        }
        .courierTooltip(
            tooltipTitle,
            shortcut: tooltipShortcut,
            detail: tooltipDetail,
            edge: .top,
            isEnabled: showsTooltip
        )
        .accessibilityLabel(accessibilityTitle)
        .accessibilityHint(disabledHint ?? "")
        .accessibilityIdentifier(accessibilityID)
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
            .courierTooltip(String(localized: "Dismiss"), edge: .top)
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
            .courierTooltip(String(localized: "Cancel editing"), shortcut: "Esc", edge: .top)
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
            .courierTooltip(String(localized: "Remove GIF"), edge: .top)
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
            .courierTooltip(String(localized: "Clear quoted message"), shortcut: "Esc", edge: .top)
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
        textView.textContainerInset = NSSize(width: 6, height: 8)
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = false
        textView.autoresizingMask = [.width]
        textView.textContainer?.widthTracksTextView = true
        textView.textContainer?.containerSize = NSSize(width: 0, height: CGFloat.greatestFiniteMagnitude)
        textView.placeholder = placeholder
        textView.registerForDraggedTypes(
            textView.acceptableDragTypes + [
                .fileURL,
                .png,
                .tiff,
                NSPasteboard.PasteboardType(UTType.gif.identifier),
                NSPasteboard.PasteboardType(UTType.jpeg.identifier),
                NSPasteboard.PasteboardType(UTType.webP.identifier),
            ]
        )
        textView.onPasteFiles = { context.coordinator.parent.onPasteFiles($0) }
        textView.canAcceptWindowPaste = { [weak composer] in
            guard let composer else { return false }
            return !composer.isLocked
                && composer.roomID != nil
                && !composer.voiceRecorder.isRecordingOrReviewing
                && !composer.isThreadPaneComposer
        }
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
        private var conversionSerial = 0

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
            // Typed markdown that just became formatting: Undo puts its markers back. (The text came in from the
            // model above, which clears the view's own undo history, so this is the one step it holds.)
            if let conversion = composer.lastMarkdownConversion, conversion.serial != conversionSerial {
                conversionSerial = conversion.serial
                if textView.string == conversion.afterText, let undo = textView.undoManager {
                    undo.registerUndo(withTarget: self) { target in
                        MainActor.assumeIsolated { target.composer.undoMarkdownConversion(conversion) }
                    }
                    undo.setActionName(String(localized: "Formatting"))
                }
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
                composer.textChanged(to: textView.string, replacing: edit.range, with: edit.length,
                                     composing: textView.hasMarkedText())
            } else if composer.text != textView.string {
                composer.text = textView.string
            }
            editing = nil
            inEdit = false
            report(selection: textView.selectedRange())
            // Typed markdown that became formatting changed the model's text (markers gone): the view takes it now,
            // with the caret where the model put it, not a moment later.
            if composer.text != textView.string { sync() } else { restyle() }
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

        private func currentKeyModifiers() -> KeyModifiers {
            guard let event = NSApp.currentEvent, event.type == .keyDown else { return [] }
            let flags = event.modifierFlags
            var modifiers: KeyModifiers = []
            if flags.contains(.shift) { modifiers.insert(.shift) }
            if flags.contains(.option) { modifiers.insert(.option) }
            if flags.contains(.control) { modifiers.insert(.control) }
            if flags.contains(.command) { modifiers.insert(.command) }
            return modifiers
        }

        private func moveFocus(from textView: NSTextView, forward: Bool) {
            guard let window = textView.window else { return }
            let before = window.firstResponder
            if forward {
                window.selectNextKeyView(textView)
            } else {
                window.selectPreviousKeyView(textView)
            }
            if window.firstResponder === before, let scroll = textView.enclosingScrollView {
                if forward {
                    window.selectNextKeyView(scroll)
                } else {
                    window.selectPreviousKeyView(scroll)
                }
            }
            if window.firstResponder === before {
                window.recalculateKeyViewLoop()
                if forward {
                    window.selectNextKeyView(textView)
                } else {
                    window.selectPreviousKeyView(textView)
                }
            }
        }

        func textView(_ textView: NSTextView, doCommandBy selector: Selector) -> Bool {
            guard composer.hotkeyDispatcher?.lifecycle.isLocked != true else { return true }
            if selector == #selector(NSResponder.insertTab(_:))
                || selector == #selector(NSResponder.insertBacktab(_:))
                || selector == #selector(NSResponder.insertTabIgnoringFieldEditor(_:)) {
                guard !textView.hasMarkedText() else { return false }
                let hasEmojiPicker = composer.emojiQuery != nil && !composer.emojiCandidates.isEmpty
                let activePicker = openPicker
                let action = ComposerModel.action(
                    forTab: currentKeyModifiers(),
                    isBacktab: selector == #selector(NSResponder.insertBacktab(_:)),
                    ignoresFieldEditor: selector == #selector(NSResponder.insertTabIgnoringFieldEditor(_:)),
                    hasOpenAutocomplete: hasEmojiPicker || activePicker != nil
                )
                switch action {
                case .acceptAutocomplete:
                    if hasEmojiPicker {
                        let idx = min(max(composer.selectedEmojiIndex, 0), composer.emojiCandidates.count - 1)
                        composer.pickEmoji(composer.emojiCandidates[idx])
                    } else if let activePicker {
                        activePicker.choose(min(parent.ui.pickerIndex, activePicker.count - 1))
                    }
                    return true
                case .insertLiteralTab:
                    textView.insertText("\t", replacementRange: textView.selectedRange())
                    return true
                case .focusNext:
                    moveFocus(from: textView, forward: true)
                    return true
                case .focusPrevious:
                    moveFocus(from: textView, forward: false)
                    return true
                }
            }
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
                case #selector(NSResponder.insertNewline(_:)):
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
                case #selector(NSResponder.insertNewline(_:)):
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
                var modifiers = currentKeyModifiers()
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
    var canAcceptWindowPaste: () -> Bool = { false }
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
        if Self.isPasteShortcut(event) {
            if window?.firstResponder === self {
                paste(nil)
                return true
            }
            if window?.isKeyWindow == true,
               window?.attachedSheet == nil,
               !(window?.firstResponder is NSText),
               canAcceptWindowPaste() {
                window?.makeFirstResponder(self)
                paste(nil)
                return true
            }
        }
        guard window?.firstResponder === self, let kind = Self.formatKind(for: event) else {
            return super.performKeyEquivalent(with: event)
        }
        // ⌘E is Archive everywhere else: here it is Code only over a selection, and with none it stays Archive.
        if kind == .code, event.modifierFlags.intersection(.deviceIndependentFlagsMask) == [.command],
           selectedRange().length == 0 {
            return super.performKeyEquivalent(with: event)
        }
        return onFormat(kind, false) || super.performKeyEquivalent(with: event)
    }

    static func isPasteShortcut(_ event: NSEvent) -> Bool {
        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
            .subtracting([.capsLock, .numericPad, .function])
        let key = event.charactersIgnoringModifiers?.lowercased() ?? ""
        return flags == [.command] && key == "v"
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
            case "e": return .code
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

    /// Files or clipboard images dropped on the box are attached; left to the text view, their paths would be typed into the text.
    override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation {
        PasteboardAttachmentExtractor.hasFilesOrImage(on: sender.draggingPasteboard)
            ? .copy
            : super.draggingEntered(sender)
    }

    override func draggingUpdated(_ sender: NSDraggingInfo) -> NSDragOperation {
        PasteboardAttachmentExtractor.hasFilesOrImage(on: sender.draggingPasteboard)
            ? .copy
            : super.draggingUpdated(sender)
    }

    override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
        let files = PasteboardAttachmentExtractor.extractFiles(from: sender.draggingPasteboard)
        if !files.isEmpty, onPasteFiles(files) { return true }
        return super.performDragOperation(sender)
    }

    @discardableResult
    func paste(from pasteboard: NSPasteboard) -> Bool {
        let files = PasteboardAttachmentExtractor.extractFiles(from: pasteboard)
        if !files.isEmpty, onPasteFiles(files) {
            return true
        }
        return false
    }

    override func paste(_ sender: Any?) {
        if paste(from: .general) { return }
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
        .courierTooltip(String(localized: "Stop recording to review"), edge: .top)
        .accessibilityLabel(String(localized: "Stop recording"))
    }
}

private struct ComposerTalkToTypeBanner: View {
    @ObservedObject var talkToType: TalkToTypeModel

    var body: some View {
        if let notice = talkToType.permissionNotice {
            HStack(spacing: 10) {
                Image(systemName: "mic.slash.fill")
                    .foregroundStyle(.orange)
                Text(notice.message)
                    .font(.callout)
                    .foregroundStyle(.primary)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 4)
                Button(String(localized: "Open System Settings")) {
                    if let url = notice.systemSettingsURL {
                        NSWorkspace.shared.open(url)
                    }
                }
                .controlSize(.small)
                Button {
                    talkToType.dismissPermissionNotice()
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
        }

        switch talkToType.state {
        case .idle:
            EmptyView()
        case .askingPermission:
            stripContainer {
                HStack(spacing: 8) {
                    ProgressView()
                        .controlSize(.small)
                    Text(String(localized: "Waiting for permission…"))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Spacer(minLength: 0)
                }
            }
        case let .listening(partialText, level, provenance, statusMessage):
            stripContainer {
                VStack(alignment: .leading, spacing: partialText.isEmpty ? 0 : 6) {
                    if !partialText.isEmpty {
                        Text(partialText)
                            .font(.callout)
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .lineLimit(3)
                    }
                    HStack(spacing: 10) {
                        Image(systemName: "mic.fill")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(Color.accentColor)
                            .symbolEffect(.pulse)
                        TalkToTypeLevelMeter(level: level)
                        Text(statusMessage ?? String(localized: "Listening…"))
                            .font(.caption.weight(.medium))
                            .foregroundStyle(statusMessage == nil ? .primary : .secondary)
                            .lineLimit(1)
                        Spacer(minLength: 0)
                        Text(provenance.liveStripLabel)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                        Button(String(localized: "Stop")) {
                            talkToType.stop()
                        }
                        .buttonStyle(.borderedProminent)
                        .controlSize(.small)
                    }
                }
            }
        case let .finishing(partialText, provenance, statusMessage):
            stripContainer {
                VStack(alignment: .leading, spacing: partialText.isEmpty ? 0 : 6) {
                    if !partialText.isEmpty {
                        Text(partialText)
                            .font(.callout)
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .lineLimit(3)
                    }
                    HStack(spacing: 10) {
                        ProgressView()
                            .controlSize(.small)
                        Text(statusMessage ?? String(localized: "Finishing…"))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                        Spacer(minLength: 0)
                        Text(provenance.liveStripLabel)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                }
            }
        }
    }

    private func stripContainer<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        content()
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(Color.secondary.opacity(0.11))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .strokeBorder(Color.secondary.opacity(0.22), lineWidth: 0.5)
            )
    }
}

private struct TalkToTypeLevelMeter: View {
    let level: Float
    private static let multipliers: [CGFloat] = [0.45, 0.85, 1.0, 0.75, 0.5]

    var body: some View {
        let clamped = CGFloat(min(max(level, 0), 1))
        HStack(alignment: .center, spacing: 2) {
            ForEach(Array(Self.multipliers.enumerated()), id: \.offset) { _, mult in
                let barHeight = max(3, min(14, 3 + clamped * 11 * mult))
                Capsule(style: .continuous)
                    .fill(Color.accentColor.opacity(clamped > 0.02 ? 0.85 : 0.35))
                    .frame(width: 2.5, height: barHeight)
            }
        }
        .frame(height: 14)
        .accessibilityHidden(true)
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
                Text(String(localized: "Microphone access is turned off for Vitruvian Courier. Allow microphone access in System Settings to record voice notes."))
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

/// Its content only while no voice note is being recorded or reviewed: with glass, the plus beside the message box,
/// which the recording bar takes the place of.
private struct ComposerIdleOnly<Content: View>: View {
    @ObservedObject var voiceRecorder: VoiceRecorderModel
    @ViewBuilder let content: () -> Content

    var body: some View {
        switch voiceRecorder.state {
        case .recording, .reviewing: EmptyView()
        case .idle, .permissionDenied, .failed: content()
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
            .courierTooltip(String(localized: "Cancel recording"), shortcut: "Esc", edge: .top)
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
            .courierTooltip(String(localized: "Send voice note"), shortcut: "Return", edge: .top)
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
            .courierTooltip(String(localized: "Discard recording"), shortcut: "Esc", edge: .top)
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
            .courierTooltip(String(localized: "Send voice note"), shortcut: "Return", edge: .top)
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

/// Whether the late-night nudge was dismissed this session (a launch of the app).
@MainActor
final class SendLaterNudgeSession: ObservableObject {
    static let shared = SendLaterNudgeSession()
    @Published var dismissed = false
}

/// The gentle line above the message box at night: "It's late — send this later?", with the link to the picker.
private struct SendLaterNudgeBar: View {
    let sendLater: () -> Void
    let dismiss: () -> Void

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "moon.stars")
                .foregroundStyle(.secondary)
                .accessibilityHidden(true)
            Text(String(localized: "It’s late — send this later?"))
                .font(.callout)
                .foregroundStyle(.secondary)
            Button(String(localized: "Send Later…"), action: sendLater)
                .buttonStyle(.link)
                .font(.callout)
            Spacer(minLength: 0)
            Button(action: dismiss) {
                Image(systemName: "xmark")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .frame(width: 20, height: 20)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .courierTooltip(
                String(localized: "Dismiss"),
                detail: String(localized: "Don’t suggest this again until Vitruvian Courier restarts"),
                edge: .top
            )
            .accessibilityLabel(String(localized: "Dismiss"))
        }
        .padding(.horizontal, 4)
    }
}
