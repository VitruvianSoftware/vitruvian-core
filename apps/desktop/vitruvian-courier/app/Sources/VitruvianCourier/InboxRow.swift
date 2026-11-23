// Copyright 2026 VitruvianSoftware
// SPDX-License-Identifier: AGPL-3.0-or-later

import AppKit
import VitruvianCourierCore
import SwiftUI

/// How the settings shape a row (Settings ▸ Inbox ▸ Chat list), read once per list draw.
struct RowStyle: Equatable {
    var showPreviews = true
    var showUnreadCounts = true
    var compact = false
    var showNetworkIcons = true
    var colorNetworkIcons = true
    var hoverAction = HoverAction.archive
    var timeFormat = TimeFormatPreference.system
    var redactNamesAndPictures = false
    var fontSizeScale = FontSizeScale.default

    init(
        _ preferences: InboxPreferences,
        timeFormat: TimeFormatPreference = .system,
        redactNamesAndPictures: Bool = false,
        fontSizeScale: FontSizeScale = .default
    ) {
        showPreviews = preferences.showPreviews
        showUnreadCounts = preferences.showUnreadCounts
        compact = preferences.compactList
        showNetworkIcons = preferences.showNetworkIcons
        colorNetworkIcons = preferences.colorNetworkIcons
        hoverAction = preferences.hoverAction
        self.timeFormat = timeFormat
        self.redactNamesAndPictures = redactNamesAndPictures
        self.fontSizeScale = fontSizeScale
    }

    init(
        _ preferences: InboxPreferences,
        composerPreferences: ComposerPreferences,
        redactNamesAndPictures: Bool = false,
        fontSizeScale: FontSizeScale = .default
    ) {
        self.init(
            preferences,
            timeFormat: composerPreferences.timeFormat,
            redactNamesAndPictures: redactNamesAndPictures,
            fontSizeScale: fontSizeScale
        )
    }
}

/// One chat in the inbox: avatar with its network badge, name, time, a preview (or who is typing, or the draft)
/// and what marks it: unread, a mention, a reminder that came due, muted, a message request.
struct InboxRowView<HoverMenu: View>: View {
    let row: InboxRow
    var displayTitleOverride: String? = nil
    /// A request's sender handle from the engine, when it has one: tells apart strangers the bridge could not name.
    var requestHandle: String = ""
    let networkName: String
    /// When this row represents a merged chat, the networks of its member rooms (`>= 2`).
    var mergedNetworks: [String] = []
    /// The moment the time is read against; the list moves it on every minute.
    let now: Date
    let style: RowStyle
    let isSelecting: Bool
    let isSelected: Bool
    var isHovered: Bool? = nil
    /// Reports pointer enter/exit to the parent list without forcing a full-list `@State` invalidation.
    var onHoverChange: ((Bool) -> Void)? = nil
    /// Called on mouseDown of the row hover button so the list suppresses selecting/opening the chat.
    var onWillHoverAct: (() -> Void)? = nil
    /// The hover button, when the setting is Archive or Mark Read/Unread.
    let hoverAct: () -> Void
    let accept: () -> Void
    let decline: () -> Void
    /// The hover button's menu, when the setting is Menu.
    @ViewBuilder let hoverMenu: () -> HoverMenu
    @State private var localHovered = false
    @State private var isHoverButtonHovered = false
    @Environment(\.appearancePreferences) private var appearanceEnv
    @Environment(\.themeAccentColor) private var themeAccent
    @Environment(\.redactNamesAndPictures) private var redactsNamesAndPictures
    @Environment(\.accessibilityReduceMotion) private var accessibilityReduceMotion

    @Environment(\.courierZoomMultiplier) private var zoom

    private var reduceMotionEnabled: Bool {
        accessibilityReduceMotion || NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
    }

    private var effectiveHovered: Bool {
        isHovered ?? localHovered
    }

    /// The button (Settings ▸ Inbox ▸ "Button on a chat you point at") is there while the pointer is on the row,
    /// except while choosing chats.
    private var showsHoverButton: Bool {
        InboxRowHoverMotion.showsHoverAction(
            isHovered: effectiveHovered,
            isSelecting: isSelecting,
            hoverAction: style.hoverAction
        )
    }

    private var showsIndicators: Bool {
        InboxRowHoverMotion.showsIndicators(
            isHovered: effectiveHovered,
            isSelecting: isSelecting,
            hoverAction: style.hoverAction
        )
    }

    /// The chat's name, preview, and time font sizes, scaled together so the name is always larger than the preview.
    private var pointSizes: (title: CGFloat, preview: CGFloat, time: CGFloat) {
        FontSizeScale.inboxRowPointSizes(
            scale: appearanceEnv?.fontSizeScale ?? style.fontSizeScale,
            zoom: zoom
        )
    }

    private var isRedacted: Bool {
        style.redactNamesAndPictures || redactsNamesAndPictures
    }

    private var displayTitle: String {
        var formatted = PhoneNumberFormat.display(displayTitleOverride ?? row.displayTitle)
        // A request from a stranger the bridge could not name: say who it is from, not "Facebook user" twice.
        if row.request, RequestPresentation.isPlaceholderName(formatted) {
            formatted = RequestPresentation.title(name: formatted, handle: requestHandle, networkName: networkName)
        }
        let raw = formatted.isEmpty ? String(localized: "Unnamed chat") : formatted
        return isRedacted ? AppearancePreferences.redactedText(raw, kind: .chatTitle) : raw
    }

    var body: some View {
        let rowSpacing: CGFloat = style.compact ? 8 : 10
        let selectionTiming = InboxSelectionMotion.timing(entering: isSelecting, reduceMotion: reduceMotionEnabled)
        let hoverAnimation: Animation = .easeInOut(duration: InboxRowHoverMotion.duration)
        let hoverScale = max(
            InboxRowHoverMotion.scale(isVisible: showsHoverButton, reduceMotion: reduceMotionEnabled),
            0.001
        )
        let hoverOpacity = InboxRowHoverMotion.opacity(isVisible: showsHoverButton)
        let minIndicatorHeight = round(pointSizes.preview * 1.25)

        HStack(spacing: 0) {
            Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                .font(.title3)
                .foregroundStyle(isSelected ? themeAccent : Color.secondary)
                .frame(width: InboxSelectionMotion.checkboxSlotWidth, alignment: .leading)
                .padding(.trailing, rowSpacing)
                .opacity(InboxSelectionMotion.checkboxOpacity(isSelecting: isSelecting))
                .animation(
                    .easeInOut(duration: selectionTiming.opacityDuration).delay(selectionTiming.opacityDelay),
                    value: isSelecting
                )
                .frame(
                    width: InboxSelectionMotion.checkboxWidth(isSelecting: isSelecting, rowSpacing: rowSpacing),
                    alignment: .leading
                )
                .clipped()
                .animation(
                    selectionTiming.animatesWidth
                        ? .easeInOut(duration: selectionTiming.widthDuration).delay(selectionTiming.widthDelay)
                        : nil,
                    value: isSelecting
                )
                .accessibilityHidden(!isSelecting)
                .accessibilityLabel(
                    isSelecting
                        ? (isSelected ? String(localized: "Selected") : String(localized: "Not selected"))
                        : ""
                )

            HStack(spacing: rowSpacing) {
                avatar
                VStack(alignment: .leading, spacing: style.compact ? 1 : 3) {
                    HStack(alignment: .firstTextBaseline, spacing: 4) {
                        Text(displayTitle)
                            .font(.system(size: pointSizes.title, weight: .semibold))
                            .foregroundStyle(.primary)
                            .lineLimit(1)
                            // The name keeps its room first; the account tag gives way before it.
                            .layoutPriority(1)
                        if let tag = row.accountTag { AccountTag(name: tag) }
                        Spacer(minLength: 4)
                        HStack(spacing: 3) {
                            Text(RelativeTime.text(forMillis: row.lastTS, now: now, timeFormat: style.timeFormat))
                                .font(.system(size: pointSizes.time))
                                .foregroundStyle(.tertiary)
                            if let tick = row.previewTick { PreviewTickMark(tick: tick) }
                        }
                        .fixedSize()
                        .frame(minWidth: 24, alignment: .trailing)
                    }
                    HStack(alignment: .top, spacing: 6) {
                        secondLine
                            .font(.system(size: pointSizes.preview))
                            .foregroundStyle(.secondary)
                            // Two lines, as Beeper's rows; compact rows stay at one.
                            .lineLimit(style.compact ? 1 : 2)
                            .fixedSize(horizontal: false, vertical: true)
                            .frame(maxWidth: .infinity, alignment: .leading)
                        if style.hoverAction != .nothing || !isSelecting {
                            InboxRowCollapsingSlot(reveal: isSelecting ? 0 : 1) {
                                ZStack(alignment: .trailing) {
                                    HStack(alignment: .center, spacing: 5) {
                                        marks
                                    }
                                    .opacity(showsIndicators ? 1 : 0)
                                    .animation(hoverAnimation, value: showsHoverButton)
                                    .accessibilityHidden(!showsIndicators)

                                    if style.hoverAction != .nothing {
                                        hoverButton
                                            .scaleEffect(hoverScale, anchor: .center)
                                            .opacity(hoverOpacity)
                                            .animation(hoverAnimation, value: showsHoverButton)
                                            .allowsHitTesting(showsHoverButton)
                                            .accessibilityHidden(!showsHoverButton)
                                    }
                                }
                                .frame(minWidth: showsHoverButton ? 24 : 0, minHeight: minIndicatorHeight, alignment: .trailing)
                                .animation(hoverAnimation, value: showsHoverButton)
                            }
                            .opacity(isSelecting ? 0 : 1)
                            .animation(
                                .easeInOut(duration: selectionTiming.opacityDuration).delay(selectionTiming.opacityDelay),
                                value: isSelecting
                            )
                            .animation(
                                selectionTiming.animatesWidth
                                    ? .easeInOut(duration: selectionTiming.widthDuration).delay(selectionTiming.widthDelay)
                                    : nil,
                                value: isSelecting
                            )
                            .clipped()
                            .accessibilityHidden(isSelecting)
                        }
                    }
                    if row.request {
                        HStack(spacing: 6) {
                            Button(String(localized: "Accept"), action: accept)
                                .buttonStyle(.borderedProminent)
                            Button(String(localized: "Decline"), action: decline)
                                .buttonStyle(.borderless)
                                .foregroundStyle(.secondary)
                                .help(String(localized: "Hides the chat on this Mac. The person isn’t told."))
                        }
                        .controlSize(.small)
                        .padding(.top, 2)
                    }
                    if let muted = row.mutedLine, !style.compact {
                        Label(muted, systemImage: "bell.slash")
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                            .labelStyle(.titleAndIcon)
                            .lineLimit(1)
                    }
                }
                if style.showPreviews, !row.previewMediaPath.isEmpty, row.typing.isEmpty, row.draft.isEmpty {
                    PreviewThumbnail(path: row.previewMediaPath)
                        .frame(width: style.compact ? 26 : 36, height: style.compact ? 26 : 36)
                }
            }
        }
        .padding(.vertical, style.compact ? 1 : 4)
        .contentShape(Rectangle())
        .onHover { inside in
            localHovered = inside
            if !inside { isHoverButtonHovered = false }
            onHoverChange?(inside)
        }
        .accessibilityElement(children: .combine)
        .modifier(RequestRowLabel(label: requestAccessibilityLabel))
    }

    private var avatar: some View {
        let size: CGFloat = style.compact ? 28 : 40
        let badgeSize: CGFloat = style.compact ? 11 : 14
        return ChatAvatar(row: row, size: size)
            .blur(radius: isRedacted ? 6 : 0)
            // The frame's square, not a circle: a group's small circles reach its corners.
            .clipShape(Rectangle())
            .frame(width: size, height: size)
            .overlay(alignment: .bottomTrailing) {
                if style.showNetworkIcons {
                    if mergedNetworks.count > 1 {
                        HStack(spacing: -4) {
                            ForEach(Array(mergedNetworks.prefix(3).enumerated()), id: \.offset) { _, net in
                                NetworkBadge(
                                    network: net,
                                    name: NetworkNames.displayName(of: net) ?? net,
                                    size: badgeSize,
                                    tinted: style.colorNetworkIcons,
                                    ringed: true
                                )
                            }
                        }
                        .offset(x: 4, y: 3)
                    } else {
                        NetworkBadge(network: row.network, name: networkName, size: style.compact ? 13 : 16,
                                     tinted: style.colorNetworkIcons, ringed: true)
                            .offset(x: 4, y: 4)
                    }
                }
            }
    }

    /// Who is typing, else the draft, else the newest message (when previews are on).
    @ViewBuilder
    private var secondLine: some View {
        if let typing = row.typingLine {
            HStack(spacing: 3) {
                Image(systemName: "ellipsis")
                    .symbolEffect(.variableColor.iterative, options: .repeating)
                Text(typing)
            }
            .foregroundStyle(themeAccent)
        } else if row.request, case let .text(line) = requestDetail {
            Text(line)
                .foregroundStyle(themeAccent)
        } else if !row.draft.isEmpty {
            Text(String(localized: "Draft:")).foregroundStyle(.red) + Text(verbatim: " " + MarkdownConverter.visibleDraft(row.draft))
        } else if style.showPreviews {
            preview
        }
    }

    private var preview: Text { ChatPreview.text(row) }

    /// A request's second line: the message when previews are on, else what still tells requests apart.
    private var requestDetail: RequestPresentation.Detail {
        RequestPresentation.detail(showPreviews: style.showPreviews, handle: requestHandle, lastTS: row.lastTS)
    }

    /// VoiceOver's label for a request: its own, so two strangers on one network are not read alike.
    private var requestAccessibilityLabel: String? {
        guard row.request else { return nil }
        var detail = ""
        switch requestDetail {
        case .text(let line): detail = line
        case .preview: detail = [row.previewLabel?.title ?? "", row.previewBody].filter { !$0.isEmpty }.joined(separator: " ")
        }
        return RequestPresentation.accessibilityLabel(title: displayTitle, networkName: networkName, detail: detail)
    }

    /// "@", "Reminder", muted, and the unread count or dot.
    @ViewBuilder
    private var marks: some View {
        if row.unreadMentions > 0 {
            Text(verbatim: "@")
                .font(.caption.weight(.bold))
                .foregroundStyle(.white)
                .frame(width: 18, height: 18)
                .background(Circle().fill(themeAccent))
                .help(String(localized: "You were mentioned"))
                .accessibilityLabel(String(localized: "You were mentioned"))
        }
        if row.reminderFired {
            Text(String(localized: "Reminder"))
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.orange)
                .padding(.horizontal, 5)
                .padding(.vertical, 1)
                .background(Capsule().strokeBorder(Color.orange))
                .help(String(localized: "A reminder you set brought this chat back."))
        }
        if row.muted {
            Image(systemName: "bell.slash.fill")
                .font(.caption)
                .foregroundStyle(.secondary)
                .help(String(localized: "Muted"))
                .accessibilityLabel(String(localized: "Muted"))
        }
        if style.showUnreadCounts, let badge = row.unreadBadge {
            Text(badge)
                .font(.caption.weight(.semibold))
                .monospacedDigit()
                .foregroundStyle(.white)
                .padding(.horizontal, 6)
                .padding(.vertical, 1)
                .background(Capsule().fill(row.muted || row.mutedBy != .none ? Color.gray.opacity(0.55) : themeAccent))
                .accessibilityLabel(String(localized: "\(row.unread) unread"))
        } else if row.showsUnreadDot || (!style.showUnreadCounts && row.isUnread) {
            Circle()
                .fill(row.muted || row.mutedBy != .none ? Color.gray.opacity(0.55) : themeAccent)
                .frame(width: 9, height: 9)
                .help(row.markedUnread ? String(localized: "Marked as unread") : String(localized: "Unread"))
                .accessibilityLabel(String(localized: "Unread"))
        }
    }

    @ViewBuilder
    private var hoverButton: some View {
        switch style.hoverAction {
        case .archive:
            let enabled = InboxRowHoverMotion.isHoverActionEnabled(
                isPinned: row.pinned,
                isArchived: row.archived,
                hoverAction: .archive
            )
            let label = row.archived ? String(localized: "Unarchive") : String(localized: "Archive")
            let tip = row.archived ? String(localized: "Unarchive")
                : row.pinned ? String(localized: "Unpin a chat to archive it") : String(localized: "Archive")
            let symbol = InboxRowHoverMotion.hoverActionSymbol(
                isArchived: row.archived,
                isUnread: row.isUnread,
                hoverAction: .archive
            ) ?? "archivebox"
            hoverActionBadge(
                symbol: symbol,
                label: label,
                tooltip: tip,
                isEnabled: enabled
            )
        case .toggleRead:
            let label = row.isUnread ? String(localized: "Mark as Read") : String(localized: "Mark as Unread")
            let symbol = InboxRowHoverMotion.hoverActionSymbol(
                isArchived: row.archived,
                isUnread: row.isUnread,
                hoverAction: .toggleRead
            ) ?? "envelope.badge"
            hoverActionBadge(
                symbol: symbol,
                label: label,
                tooltip: label,
                isEnabled: true
            )
        case .menu:
            if showsHoverButton {
                Menu(content: hoverMenu) {
                    Image(systemName: "ellipsis.circle")
                        .frame(width: 22, height: 22)
                        .background(
                            RoundedRectangle(cornerRadius: 5, style: .continuous)
                                .fill(isHoverButtonHovered ? Color.primary.opacity(0.08) : .clear)
                                .animation(
                                    reduceMotionEnabled ? nil : .easeInOut(duration: HoverFillMotion.duration),
                                    value: isHoverButtonHovered
                                )
                        )
                }
                .menuStyle(.borderlessButton)
                .menuIndicator(.hidden)
                .fixedSize()
                .onHover { isHoverButtonHovered = $0 }
                .help(String(localized: "More"))
                .accessibilityLabel(String(localized: "More"))
            } else {
                Image(systemName: "ellipsis.circle")
                    .frame(width: 22, height: 22)
                    .accessibilityHidden(true)
            }
        default:
            EmptyView()
        }
    }

    private func hoverActionBadge(
        symbol: String,
        label: String,
        tooltip: String,
        isEnabled: Bool
    ) -> some View {
        Image(systemName: symbol)
            .font(.system(size: 13))
            .foregroundStyle(isEnabled ? .secondary : .quaternary)
            .frame(width: 22, height: 22)
            .background(
                RoundedRectangle(cornerRadius: 5, style: .continuous)
                    .fill(isHoverButtonHovered && isEnabled ? Color.primary.opacity(0.08) : .clear)
                    .animation(
                        reduceMotionEnabled ? nil : .easeInOut(duration: HoverFillMotion.duration),
                        value: isHoverButtonHovered
                    )
            )
            .contentShape(RoundedRectangle(cornerRadius: 5, style: .continuous))
            .overlay {
                if showsHoverButton {
                    RowHoverClickCatcher(
                        isEnabled: isEnabled,
                        label: label,
                        tooltip: tooltip,
                        accessibilityID: "inbox.row.hoverAction.\(row.id)",
                        onHoverChange: { isHoverButtonHovered = $0 },
                        onWillAct: { onWillHoverAct?() },
                        onAct: hoverAct
                    )
                }
            }
            .accessibilityLabel(label)
    }
}

/// Collapses the right-side indicators/hover slot cleanly to zero width when entering multi-select.
private struct InboxRowCollapsingSlot: Layout {
    var reveal: CGFloat

    var animatableData: CGFloat {
        get { reveal }
        set { reveal = newValue }
    }

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache _: inout ()) -> CGSize {
        guard let subview = subviews.first else { return .zero }
        let natural = subview.sizeThatFits(.unspecified)
        let clamped = min(max(reveal, 0), 1)
        return CGSize(width: natural.width * clamped, height: natural.height)
    }

    func placeSubviews(in bounds: CGRect, proposal _: ProposedViewSize, subviews: Subviews, cache _: inout ()) {
        guard let subview = subviews.first else { return }
        let natural = subview.sizeThatFits(.unspecified)
        subview.place(
            at: CGPoint(x: bounds.maxX, y: bounds.midY),
            anchor: .trailing,
            proposal: ProposedViewSize(natural)
        )
    }
}

/// AppKit mouse catcher for the row's hover action button so clicking it archives/toggles without forwarding `mouseDown`
/// to the enclosing `NSTableView` (never opening or selecting the chat).
private struct RowHoverClickCatcher: NSViewRepresentable {
    let isEnabled: Bool
    let label: String
    let tooltip: String
    let accessibilityID: String
    let onHoverChange: (Bool) -> Void
    let onWillAct: () -> Void
    let onAct: () -> Void

    func makeNSView(context _: Context) -> ClickCatcherNSView {
        ClickCatcherNSView()
    }

    func updateNSView(_ view: ClickCatcherNSView, context _: Context) {
        view.isEnabled = isEnabled
        view.onHoverChange = onHoverChange
        view.onWillAct = onWillAct
        view.onAct = onAct
        view.toolTip = tooltip
        view.setAccessibilityElement(true)
        view.setAccessibilityRole(.button)
        view.setAccessibilityLabel(label)
        view.setAccessibilityEnabled(isEnabled)
        view.setAccessibilityIdentifier(accessibilityID)
    }

    final class ClickCatcherNSView: NSView {
        var isEnabled = true
        var onHoverChange: ((Bool) -> Void)?
        var onWillAct: (() -> Void)?
        var onAct: (() -> Void)?
        private var isTrackingMouseDown = false

        override func hitTest(_ point: NSPoint) -> NSView? {
            guard !isHidden, !isHiddenOrHasHiddenAncestor else { return nil }
            let local = convert(point, from: superview)
            return bounds.contains(local) ? self : nil
        }

        override func acceptsFirstMouse(for _: NSEvent?) -> Bool { true }

        override func updateTrackingAreas() {
            super.updateTrackingAreas()
            for area in trackingAreas { removeTrackingArea(area) }
            guard !bounds.isEmpty else { return }
            addTrackingArea(
                NSTrackingArea(
                    rect: bounds,
                    options: [.mouseEnteredAndExited, .activeInKeyWindow, .inVisibleRect],
                    owner: self,
                    userInfo: nil
                )
            )
        }

        override func mouseEntered(with _: NSEvent) {
            onHoverChange?(true)
        }

        override func mouseExited(with _: NSEvent) {
            onHoverChange?(false)
        }

        override func mouseDown(with _: NSEvent) {
            guard isEnabled else { return }
            isTrackingMouseDown = true
            onWillAct?()
        }

        override func mouseUp(with event: NSEvent) {
            guard isTrackingMouseDown else { return }
            isTrackingMouseDown = false
            guard isEnabled else { return }
            let point = convert(event.locationInWindow, from: nil)
            if bounds.contains(point) {
                onAct?()
            }
        }

        override func accessibilityPerformPress() -> Bool {
            guard isEnabled else { return false }
            onWillAct?()
            onAct?()
            return true
        }
    }
}

/// The account a chat is on, while its network has more than one: a small tag after the chat's name.
private struct AccountTag: View {
    let name: String

    var body: some View {
        Text(verbatim: name)
            .font(.caption2)
            .foregroundStyle(.secondary)
            .lineLimit(1)
            .truncationMode(.middle)
            .padding(.horizontal, 5)
            .padding(.vertical, 1)
            .background(Capsule().strokeBorder(Color.secondary.opacity(0.45)))
            .frame(minWidth: 24, maxWidth: 96, alignment: .leading)
            .help(String(localized: "On your \(name) account"))
            .accessibilityLabel(String(localized: "On your \(name) account"))
    }
}

/// How far my newest message has got, after the row's time (01 §4's ThreadListReadIcon): one tick for sent, two for
/// delivered, two in the accent colour for seen.
struct PreviewTickMark: View {
    let tick: PreviewTick
    @Environment(\.themeAccentColor) private var themeAccent

    var body: some View {
        ZStack(alignment: .leading) {
            ForEach(0 ..< tick.marks, id: \.self) { index in
                Image(systemName: "checkmark")
                    .offset(x: CGFloat(index) * 4)
            }
        }
        .font(.system(size: 9, weight: tick == .seen ? .heavy : .semibold))
        .foregroundStyle(tick == .seen ? themeAccent : Color.secondary)
        .frame(width: tick.marks == 1 ? 10 : 14, alignment: .leading)
        .help(tick.label)
        .accessibilityElement()
        .accessibilityLabel(tick.label)
    }
}

/// A chat's newest message as its row shows it; search's chat rows show it the same way.
enum ChatPreview {
    /// A small thread mark (then "<Name>: ", or "You: ") when the newest message stays in its thread, "You: " when it
    /// is mine outside a thread, then the kind's label if it is not text, then the text.
    static func text(_ row: InboxRow) -> Text {
        var text = Text(verbatim: "")
        if let lead = row.reactionPreviewLead {
            return text + Text(verbatim: lead + row.previewBody)
        }
        if row.previewInThread {
            text = text + Text(Image(systemName: "arrowshape.turn.up.left"))
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(.tertiary) + Text(verbatim: " ")
            if let sender = row.previewThreadSender { text = text + Text(sender) }
        } else if row.previewMine {
            text = text + Text(String(localized: "You: "))
        }
        if let label = row.previewLabel { text = text + Text(label.title).italic() }
        let body = row.previewBody
        if !body.isEmpty {
            text = text + Text(verbatim: row.previewLabel == nil ? body : " " + body)
        }
        return text
    }
}

/// A chat's picture: its own, else a group's composite (a channel's "#" tile, or a few of its people), else "?" for a
/// chat with no name, else its initials. `members` are a group's people; with none given, a group whose name lists
/// people ("Eddie Stecker, Kent Hua, GitHub") is drawn from the name.
struct ChatAvatar: View {
    let row: InboxRow
    var size: CGFloat = 40
    var members: [(name: String, avatarPath: String?, identity: String)] = []

    var body: some View {
        if !row.avatarPath.isEmpty {
            AvatarView(path: row.avatarPath, initials: row.initials, identity: row.avatarIdentity, size: size)
        } else if row.name.isEmpty {
            UnknownAvatar()
        } else if !row.isDirect {
            GroupCompositeAvatar(name: row.name, members: groupMembers, size: size)
        } else {
            AvatarView(path: "", initials: row.initials, identity: row.avatarIdentity, size: size)
        }
    }

    private var groupMembers: [(name: String, avatarPath: String?, identity: String)] {
        if !members.isEmpty { return members }
        if case let .people(people) = row.groupAvatarStyle { return people.map { ($0.name, $0.avatarPath, $0.identity) } }
        return []
    }
}

/// A group with no picture of its own, as Beeper draws it: two or three small overlapping member circles (a photo,
/// else initials on the member's colour); a rounded "#" tile for a channel; the group's initials on its colour when
/// the name says nothing more.
struct GroupCompositeAvatar: View {
    let name: String
    let members: [(name: String, avatarPath: String?, identity: String)]
    var size: CGFloat = 40

    /// Lays itself out in whatever square its caller gives it (`size` is only the fallback).
    var body: some View {
        GeometryReader { proxy in
            let side = min(proxy.size.width, proxy.size.height)
            content(side: side > 0 ? side : size)
                .frame(width: proxy.size.width, height: proxy.size.height, alignment: .topLeading)
        }
        .accessibilityHidden(true)
    }

    @ViewBuilder
    private func content(side: CGFloat) -> some View {
        if case let .channel(channel) = GroupAvatarStyle.of(name: name), members.isEmpty {
            ZStack {
                RoundedRectangle(cornerRadius: side * 0.28, style: .continuous)
                    .fill(Self.channelColor(channel))
                Text(verbatim: "#")
                    .font(.system(size: side * 0.56, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)
            }
            .frame(width: side, height: side)
        } else if members.count >= 2 {
            composite(Array(members.prefix(GroupAvatarStyle.maxMembers)), side: side)
        } else {
            AvatarView(path: members.first?.avatarPath ?? "", initials: InboxRow.initials(of: members.first?.name ?? name),
                       identity: members.first?.identity ?? name, size: side)
                .frame(width: side, height: side)
        }
    }

    /// A channel's colour: one of twelve well-spread hues picked by a hash of its name, so neighbouring channels
    /// ("#general", "#data-science") are told apart where the plain hash gives similar browns.
    static func channelColor(_ channel: String) -> Color {
        var hash: UInt32 = 2_166_136_261
        for byte in channel.utf8 { hash = (hash ^ UInt32(byte)) &* 16_777_619 }
        hash ^= hash >> 15
        return Color(hue: Double(hash % 12) / 12, saturation: 0.55, brightness: 0.68)
    }

    private func composite(_ people: [(name: String, avatarPath: String?, identity: String)], side: CGFloat) -> some View {
        let three = people.count >= 3
        let diameter = side * (three ? 0.56 : 0.66)
        // The bottom-right corner is left to the network badge.
        let spots: [CGPoint] = three
            ? [CGPoint(x: 0, y: 0), CGPoint(x: side - diameter, y: 0), CGPoint(x: side * 0.2, y: side - diameter)]
            : [CGPoint(x: side - diameter, y: 0), CGPoint(x: 0, y: side - diameter)]
        return ZStack(alignment: .topLeading) {
            ForEach(Array(people.enumerated()), id: \.offset) { index, person in
                AvatarView(path: person.avatarPath ?? "", initials: InboxRow.initials(of: person.name),
                           identity: person.identity, size: diameter)
                    .frame(width: diameter, height: diameter)
                    // A ring in the list's colour keeps overlapping circles apart.
                    .overlay(Circle().strokeBorder(Color(nsColor: .windowBackgroundColor), lineWidth: max(1, side * 0.04)))
                    .offset(x: spots[index].x, y: spots[index].y)
            }
        }
        .frame(width: side, height: side, alignment: .topLeading)
    }
}

/// A group with no picture: people on its colour.
struct GroupAvatar: View {
    let identity: String

    var body: some View {
        GeometryReader { proxy in
            ZStack {
                Circle().fill(AvatarView.color(for: identity))
                Image(systemName: "person.2.fill")
                    .font(.system(size: proxy.size.width * 0.38))
                    .foregroundStyle(.white)
            }
        }
        .accessibilityHidden(true)
    }
}

/// A chat with no name: "?".
struct UnknownAvatar: View {
    var body: some View {
        GeometryReader { proxy in
            ZStack {
                Circle().fill(Color.gray.opacity(0.5))
                Text(verbatim: "?")
                    .font(.system(size: proxy.size.width * 0.42, weight: .semibold))
                    .foregroundStyle(.white)
            }
        }
        .accessibilityHidden(true)
    }
}

/// The newest message's picture, small, beside the preview.
private struct PreviewThumbnail: View {
    let path: String
    @State private var image: CGImage?

    var body: some View {
        ZStack {
            if let image {
                Image(decorative: image, scale: 1)
                    .resizable()
                    .scaledToFill()
            } else {
                Color.primary.opacity(0.06)
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 5))
        .accessibilityHidden(true)
        .task(id: path) { image = await ThumbnailLoader.shared.thumbnail(atPath: path)?.image }
    }
}

/// A network's mark: a rounded app-icon tile in the network's brand colour with a white glyph (grey with "Colour
/// network icons" off), named by its tooltip and accessibility label. Colours and SF Symbols only, not the
/// networks' own artwork. `ringed` puts a ring in the window's colour round it, so it reads on top of an avatar.
struct NetworkBadge: View {
    let network: String
    let name: String
    let size: CGFloat
    var tinted = true
    var showsTooltip = true
    var ringed = false

    var body: some View {
        let image = NetworkTileView(network: network, size: size, tinted: tinted)
            .padding(ringed ? max(1.5, size * 0.1) : 0)
            .background {
                if ringed {
                    RoundedRectangle(cornerRadius: size * 0.28 + 2, style: .continuous).fill(.background)
                }
            }
            .accessibilityLabel(name)
        if showsTooltip, !name.isEmpty {
            image.help(name)
        } else {
            image
        }
    }
}

/// The tile itself.
struct NetworkTileView: View {
    let network: String
    let size: CGFloat
    var tinted = true

    var body: some View {
        let tile = NetworkTile.of(network)
        let shape = RoundedRectangle(cornerRadius: size * 0.26, style: .continuous)
        ZStack {
            if tinted {
                shape.fill(LinearGradient(colors: [Self.color(tile.top), Self.color(tile.bottom)],
                                          startPoint: .topLeading, endPoint: .bottomTrailing))
            } else {
                shape.fill(Color.secondary)
            }
            Image(systemName: tile.glyph)
                .font(.system(size: size * 0.54, weight: .bold))
                .foregroundStyle(.white)
        }
        .frame(width: size, height: size)
    }

    static func color(_ rgb: NetworkTile.RGB) -> Color {
        Color(red: rgb.red, green: rgb.green, blue: rgb.blue)
    }
}

/// A picture, or initials on a colour. The colour comes from `identity` (a user or room ID, see `AvatarColor`), never
/// from the name, so one person has one colour on every screen.
struct AvatarView: View {
    private struct LoadedImage {
        let path: String
        let image: NSImage
    }

    let path: String
    let initials: String
    let identity: String
    var size: CGFloat = 40
    @State private var loaded: LoadedImage?

    private var effectiveImage: NSImage? {
        guard !path.isEmpty else { return nil }
        let matched = loaded?.path == path ? loaded?.image : nil
        return matched ?? AvatarCache.shared.cachedImage(atPath: path)
    }

    var body: some View {
        ZStack {
            if let effectiveImage {
                Image(nsImage: effectiveImage)
                    .resizable()
                    .scaledToFill()
            } else {
                Circle().fill(Self.color(for: identity))
                if !initials.isEmpty {
                    Text(initials)
                        .font(.system(size: max(10, round(size * 0.38)), weight: .semibold))
                        .foregroundStyle(.white)
                }
            }
        }
        .clipShape(Circle())
        .accessibilityHidden(true)
        .task(id: path) {
            guard !path.isEmpty else {
                if loaded != nil { loaded = nil }
                return
            }
            if let cached = AvatarCache.shared.cachedImage(atPath: path) {
                loaded = LoadedImage(path: path, image: cached)
            } else if let fetched = await AvatarCache.shared.image(atPath: path) {
                loaded = LoadedImage(path: path, image: fetched)
            }
        }
    }

    /// The one placeholder colour for an identity, the same in every run and on every screen.
    static func color(for identity: String) -> Color {
        let hsb = AvatarColor.hsb(forIdentity: identity)
        return Color(hue: hsb.hue, saturation: hsb.saturation, brightness: hsb.brightness)
    }
}

/// Pictures already read from disk, so scrolling back does not read them again.
final class AvatarCache: @unchecked Sendable {
    static let shared = AvatarCache()
    private let cache = NSCache<NSString, NSImage>()

    init() { cache.countLimit = 400 }

    func cachedImage(atPath path: String) -> NSImage? {
        guard !path.isEmpty else { return nil }
        return cache.object(forKey: path as NSString)
    }

    func image(atPath path: String) async -> NSImage? {
        guard !path.isEmpty else { return nil }
        if let cached = cache.object(forKey: path as NSString) { return cached }
        let image = await Task.detached(priority: .utility) { NSImage(contentsOfFile: path) }.value
        if let image { cache.setObject(image, forKey: path as NSString) }
        return image
    }
}


/// A request row's own VoiceOver label; other rows keep the one their parts make.
private struct RequestRowLabel: ViewModifier {
    let label: String?

    func body(content: Content) -> some View {
        if let label { content.accessibilityLabel(label) } else { content }
    }
}
