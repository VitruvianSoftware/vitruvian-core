// Copyright 2026 VitruvianSoftware
// SPDX-License-Identifier: AGPL-3.0-or-later

import AppKit
import Combine
import SwiftUI
import VitruvianCourierCore

enum TimelineTableMetrics {
    static let horizontalPadding: CGFloat = 14
    static let raisedOverhangPadding: CGFloat = 96
    static let resizeDebounceInterval: TimeInterval = 0.10
    static let initialPrewarmBatchSize = 128
    static let lazyHeightInvalidationBatchSize = 200
    static let topTriggerScreenMultiplier: CGFloat = 1.0
    static let minimumTopTriggerMargin: CGFloat = 300
    static let userScrollGraceSeconds: TimeInterval = 0.6
    static let leavingBottomConfirmDelayNanoseconds: UInt64 = 150_000_000
}

enum TimelineRowKind: String, CaseIterable {
    case message
    case divider
    case notice
    case topControl

    var identifier: NSUserInterfaceItemIdentifier {
        switch self {
        case .message: NSUserInterfaceItemIdentifier("timeline.message")
        case .divider: NSUserInterfaceItemIdentifier("timeline.divider")
        case .notice: NSUserInterfaceItemIdentifier("timeline.notice")
        case .topControl: NSUserInterfaceItemIdentifier("timeline.topControl")
        }
    }

    init(item: TimelineItem) {
        switch item {
        case .dateSeparator, .newDivider:
            self = .divider
        case .membershipRun:
            self = .notice
        case let .message(message):
            self = message.isNote ? .notice : .message
        }
    }
}

enum TimelineTopControlState: Equatable, Hashable {
    case none
    case olderRetry
    case olderSpinner
    case earlierLoading
    case earlierSentinel

    static let rowID = "timeline-top-control"
}

struct TimelineRowEnvironment: Equatable {
    let appearance: AppearancePreferences?
    let themeRoomID: String?
    let themeAccentHex: String
    let redactNamesAndPictures: Bool
    let liquidGlass: Bool
    let timelineCovered: Bool
    let messagePointSize: CGFloat
    let zoomMultiplier: CGFloat
    let colorScheme: ColorScheme
    let reactionCardOverride: ReactionCardOverride?
    let clickTargetProbe: ((String, CGRect) -> Void)?

    static func == (lhs: TimelineRowEnvironment, rhs: TimelineRowEnvironment) -> Bool {
        lhs.appearance === rhs.appearance
            && lhs.themeRoomID == rhs.themeRoomID
            && lhs.themeAccentHex == rhs.themeAccentHex
            && lhs.redactNamesAndPictures == rhs.redactNamesAndPictures
            && lhs.liquidGlass == rhs.liquidGlass
            && lhs.timelineCovered == rhs.timelineCovered
            && lhs.messagePointSize == rhs.messagePointSize
            && lhs.zoomMultiplier == rhs.zoomMultiplier
            && lhs.colorScheme == rhs.colorScheme
            && lhs.reactionCardOverride == rhs.reactionCardOverride
            && (lhs.clickTargetProbe == nil) == (rhs.clickTargetProbe == nil)
    }

    var heightSignature: Int {
        var hasher = Hasher()
        hasher.combine(Int((messagePointSize * 2).rounded()))
        hasher.combine(Int((zoomMultiplier * 100).rounded()))
        hasher.combine(redactNamesAndPictures)
        hasher.combine(liquidGlass)
        return hasher.finalize()
    }

    @MainActor
    var visualSignature: Int {
        var hasher = Hasher()
        hasher.combine(heightSignature)
        hasher.combine(themeRoomID)
        hasher.combine(themeAccentHex)
        hasher.combine(timelineCovered)
        hasher.combine(colorScheme == .dark)
        hasher.combine(reactionCardOverride?.messageID)
        hasher.combine(reactionCardOverride?.reactionKey)
        if let appearance {
            hasher.combine(appearance.perParticipantBubbleColors)
            let theme = appearance.effectiveTheme(for: themeRoomID)
            hasher.combine(theme.preset)
            hasher.combine(theme.accentColorHex)
            hasher.combine(theme.outgoingBubbleHexLight)
            hasher.combine(theme.outgoingBubbleHexDark)
            hasher.combine(theme.incomingBubbleHexLight)
            hasher.combine(theme.incomingBubbleHexDark)
        }
        return hasher.finalize()
    }
}

/// Keyed row height cache (`(id, contentRevision, width)`). Width is quantized to 0.5 pt (half-point Retina grid).
@MainActor
final class RowHeightCache {
    struct Key: Hashable {
        let id: String
        let contentRevision: Int
        let quantizedWidth: Int
    }

    private var storage: [Key: CGFloat] = [:]
    private(set) var hits = 0
    private(set) var misses = 0

    static func quantize(_ width: CGFloat) -> Int {
        Int((width * 2).rounded())
    }

    func height(for id: String, contentRevision: Int, width: CGFloat) -> CGFloat? {
        let key = Key(id: id, contentRevision: contentRevision, quantizedWidth: Self.quantize(width))
        if let cached = storage[key] {
            hits += 1
            return cached
        }
        misses += 1
        return nil
    }

    func contains(id: String, contentRevision: Int, width: CGFloat) -> Bool {
        let key = Key(id: id, contentRevision: contentRevision, quantizedWidth: Self.quantize(width))
        return storage[key] != nil
    }

    func insert(_ height: CGFloat, for id: String, contentRevision: Int, width: CGFloat) {
        let key = Key(id: id, contentRevision: contentRevision, quantizedWidth: Self.quantize(width))
        storage[key] = height
    }

    func invalidateWidth(keeping width: CGFloat) {
        let keep = Self.quantize(width)
        storage = storage.filter { $0.key.quantizedWidth == keep }
    }

    func invalidateItem(id: String) {
        storage = storage.filter { $0.key.id != id }
    }

    func invalidateItems(ids: Set<String>) {
        guard !ids.isEmpty else { return }
        storage = storage.filter { !ids.contains($0.key.id) }
    }

    func removeAll() {
        storage.removeAll(keepingCapacity: true)
    }

    func resetCounters() {
        hits = 0
        misses = 0
    }
}

enum TimelineContentRevision {
    private static func hashMessageKind(_ kind: MessageKind, into hasher: inout Hasher) {
        switch kind {
        case .text: hasher.combine(0)
        case .notice: hasher.combine(1)
        case .emote: hasher.combine(2)
        case .image: hasher.combine(3)
        case .video: hasher.combine(4)
        case .file: hasher.combine(5)
        case .sticker: hasher.combine(6)
        case .voiceNote: hasher.combine(7)
        case .location: hasher.combine(8)
        case .deleted: hasher.combine(9)
        case .undecryptable: hasher.combine(10)
        case .poll: hasher.combine(11)
        }
    }

    /// Computes a hash of every field that can affect a row's measured height.
    /// Selection (`isSelected`) and highlight (`isHighlighted`) intentionally do NOT alter this revision.
    @MainActor
    static func compute(
        item: TimelineItem,
        showsSent: Bool,
        actions: MessageActions,
        ui: MessageUI,
        messageActions: MessageActionsModel,
        voiceNoteTranscripts: VoiceNoteTranscriptStore,
        timerChoicesCount: Int,
        envHeightSignature: Int
    ) -> Int {
        var hasher = Hasher()
        hasher.combine(envHeightSignature)
        hasher.combine(actions.showMessageTimestamps)
        hasher.combine(actions.timeFormat.rawValue)
        hasher.combine(actions.loadExternalEmbedsAutomatically)
        hasher.combine(actions.showLinkPreviews)

        switch item {
        case let .dateSeparator(day):
            hasher.combine(0)
            hasher.combine(Int64(day.timeIntervalSince1970 * 1000))
        case .newDivider:
            hasher.combine(1)
        case let .membershipRun(id, _, summary):
            hasher.combine(2)
            hasher.combine(id)
            hasher.combine(summary)
        case let .message(message):
            hasher.combine(3)
            hasher.combine(message.id)
            hashMessageKind(message.kind, into: &hasher)
            hasher.combine(message.mine)
            hasher.combine(message.isDirect)
            hasher.combine(message.startsGroup)
            hasher.combine(message.showsTime)
            hasher.combine(message.bookmarked)
            hasher.combine(message.body)
            hasher.combine(message.rich)
            hasher.combine(message.isEdited)
            hasher.combine(message.editCount)
            hasher.combine(message.changedEditCount)
            hasher.combine(message.failedEditID)
            hasher.combine(message.editFailed != nil)
            if message.startsGroup {
                hasher.combine(message.senderName)
                hasher.combine(actions.messageNetwork(message))
            }
            if message.timerChange != nil {
                hasher.combine(actions.timerNote(message))
                hasher.combine(timerChoicesCount > 0)
            }
            if message.call != nil {
                hasher.combine(actions.callCaller(message))
            }
            if message.expiresAt != nil {
                hasher.combine(actions.disappearsIn(message))
            }
            if let reply = message.reply {
                switch reply {
                case let .quoted(q):
                    hasher.combine(1)
                    hasher.combine(q.senderName)
                    hasher.combine(q.mine)
                    hasher.combine(q.text)
                    hashMessageKind(q.kind, into: &hasher)
                case let .notLoaded(eid):
                    hasher.combine(2)
                    hasher.combine(eid)
                }
            } else {
                hasher.combine(0)
            }

            hasher.combine(message.width)
            hasher.combine(message.height)
            hasher.combine(message.mediaPath)
            hasher.combine(message.thumbnailPath)
            hasher.combine(message.fileName)
            hasher.combine(message.mimeType)
            hasher.combine(message.byteSize)
            hasher.combine(message.viewOnce)
            hasher.combine(message.played)
            hasher.combine(message.mediaRemoved)
            hasher.combine(message.isGIF)
            hasher.combine(message.isTranscoded)
            hasher.combine(message.geoURI)
            if (message.width ?? 0) <= 0 || (message.height ?? 0) <= 0 {
                if let cached = ImagePixelSizeReader.cachedSize(ofFirstReadable: [message.mediaPath, message.thumbnailPath]) {
                    hasher.combine(Int(cached.width.rounded()))
                    hasher.combine(Int(cached.height.rounded()))
                }
            }
            if let sticker = message.sticker {
                hasher.combine(sticker.name)
                hasher.combine(sticker.emoji)
                hasher.combine(sticker.width)
                hasher.combine(sticker.height)
                hasher.combine(sticker.mediaURL)
            }
            if let gif = message.gif {
                hasher.combine(gif.caption)
                hasher.combine(gif.mimeType)
                hasher.combine(gif.width)
                hasher.combine(gif.height)
                hasher.combine(gif.mediaURL)
            }
            hasher.combine(message.galleryItems.count)
            for tile in message.galleryItems {
                hasher.combine(tile.id)
                hasher.combine(tile.width)
                hasher.combine(tile.height)
                hasher.combine(tile.mediaPath)
                hasher.combine(tile.mediaRemoved)
                if (tile.width ?? 0) <= 0 || (tile.height ?? 0) <= 0 {
                    if let cached = ImagePixelSizeReader.cachedSize(ofFirstReadable: [tile.mediaPath, tile.thumbnailPath]) {
                        hasher.combine(Int(cached.width.rounded()))
                        hasher.combine(Int(cached.height.rounded()))
                    }
                }
            }
            hasher.combine(message.linkPreviews)
            // Whether the local files its cards draw are known to be there (`LocalFileFacts`): a card is another height
            // once its file turns up (a link preview's picture, a PDF's pages, a file chip).
            hasher.combine(LocalFileFacts.cachedExists(message.mediaPath) ?? false)
            hasher.combine(InlinePDFDocumentCache.shared.hasDocument(atPath: message.mediaPath))
            for preview in message.linkPreviews {
                // The picture the network's preview saved, else the one fetched for the page (`linkPreview.image`).
                if let path = preview.imagePath ?? preview.pageURL.flatMap({ actions.showLinkPreviews ? actions.linkPreviewImages?.cached(for: $0)?.path : nil }) {
                    hasher.combine(LocalFileFacts.cachedExists(path) ?? false)
                    if let size = ImagePixelSizeReader.cachedSize(ofFirstReadable: [path]) {
                        hasher.combine(Int(size.width.rounded()))
                        hasher.combine(Int(size.height.rounded()))
                    }
                }
            }
            hasher.combine(ui.loadedEmbeds.contains(message.id))
            hasher.combine(message.poll)
            hasher.combine(message.thread)

            hasher.combine(message.reactions.count)
            for chip in message.reactions {
                hasher.combine(chip.key)
                hasher.combine(chip.count)
                hasher.combine(chip.reactors.count)
            }

            // Status / readers line height changes only when visible status line changes.
            if message.mine {
                switch message.statusLine {
                case .sent:
                    hasher.combine(showsSent)
                    if showsSent { hasher.combine(0) }
                case .delivered:
                    hasher.combine(showsSent)
                    if showsSent { hasher.combine(1) }
                case let .seen(by, at):
                    hasher.combine(showsSent)
                    if showsSent {
                        hasher.combine(2)
                        hasher.combine(by)
                        hasher.combine(at)
                    }
                case let .failed(reason):
                    hasher.combine("failed")
                    hasher.combine(reason)
                case .queued:
                    hasher.combine("queued")
                case .waiting:
                    hasher.combine("waiting")
                case .noAccount:
                    hasher.combine("noAccount")
                case .sending:
                    hasher.combine("sending")
                case .mayHaveBeenSent:
                    hasher.combine("mayHaveBeenSent")
                case let .notSent(cause):
                    hasher.combine("notSent")
                    hasher.combine(cause == .appClosed)
                case nil:
                    hasher.combine("none")
                }
            }

            let historyOpen = ui.historyOpen.contains(message.id)
            hasher.combine(historyOpen)
            if historyOpen {
                hasher.combine(ui.versions[message.id]?.count ?? -1)
            }

            let isTranslating = messageActions.translatingEventIDs.contains(message.id)
            hasher.combine(isTranslating)
            if let disposition = messageActions.translations[message.id] {
                switch disposition {
                case let .text(t):
                    hasher.combine(1)
                    hasher.combine(t)
                case let .unavailable(reason):
                    hasher.combine(2)
                    hasher.combine(reason)
                }
                hasher.combine(messageActions.translationTargetLanguages[message.id])
                hasher.combine(messageActions.translationProvenance[message.id])
            }

            if message.kind == .voiceNote, let entry = voiceNoteTranscripts.entry(for: message.id) {
                switch entry {
                case .transcribing:
                    hasher.combine(1)
                case let .transcribed(text, _, isCollapsed):
                    hasher.combine(2)
                    hasher.combine(isCollapsed)
                    if !isCollapsed { hasher.combine(text) }
                case let .failed(err):
                    hasher.combine(3)
                    hasher.combine(err)
                }
            }
        }
        return hasher.finalize()
    }
}

struct TimelineRowEntry {
    let id: String
    let kind: TimelineRowKind
    let item: TimelineItem?
    let topControl: TimelineTopControlState?
    let isSelected: Bool
    let isHighlighted: Bool
    let showsSent: Bool
    let isRaised: Bool
    let contentRevision: Int
    let visualHash: Int

    static func topControl(_ state: TimelineTopControlState) -> TimelineRowEntry {
        var hasher = Hasher()
        hasher.combine("topControl")
        hasher.combine(state)
        let rev = hasher.finalize()
        return TimelineRowEntry(
            id: TimelineTopControlState.rowID,
            kind: .topControl,
            item: nil,
            topControl: state,
            isSelected: false,
            isHighlighted: false,
            showsSent: false,
            isRaised: false,
            contentRevision: rev,
            visualHash: rev
        )
    }

    @MainActor
    static func item(
        _ item: TimelineItem,
        isSelected: Bool,
        isHighlighted: Bool,
        showsSent: Bool,
        actions: MessageActions,
        ui: MessageUI,
        messageActions: MessageActionsModel,
        voiceNoteTranscripts: VoiceNoteTranscriptStore,
        timerChoicesCount: Int,
        env: TimelineRowEnvironment,
        isPickingReaction: Bool
    ) -> TimelineRowEntry {
        let rev = TimelineContentRevision.compute(
            item: item,
            showsSent: showsSent,
            actions: actions,
            ui: ui,
            messageActions: messageActions,
            voiceNoteTranscripts: voiceNoteTranscripts,
            timerChoicesCount: timerChoicesCount,
            envHeightSignature: env.heightSignature
        )
        var visualHasher = Hasher()
        visualHasher.combine(rev)
        visualHasher.combine(isSelected)
        visualHasher.combine(isHighlighted)
        visualHasher.combine(showsSent)
        visualHasher.combine(isPickingReaction)
        visualHasher.combine(env.visualSignature)
        if case let .message(msg) = item {
            visualHasher.combine(ui.revealed.contains(msg.id))
            visualHasher.combine(ui.versions[msg.id]?.count ?? 0)
        }
        let raised = isSelected || isPickingReaction || (env.reactionCardOverride?.messageID == item.id)
        return TimelineRowEntry(
            id: item.id,
            kind: TimelineRowKind(item: item),
            item: item,
            topControl: nil,
            isSelected: isSelected,
            isHighlighted: isHighlighted,
            showsSent: showsSent,
            isRaised: raised,
            contentRevision: rev,
            visualHash: visualHasher.finalize()
        )
    }
}

struct TimelineHostedRow: View {
    let item: TimelineItem
    let isSelected: Bool
    let isHighlighted: Bool
    let showsSent: Bool
    let actions: MessageActions
    let ui: MessageUI
    let env: TimelineRowEnvironment
    let onEmptyClick: () -> Void
    /// Told where the selected message's action bar is (nil: none), in the row's space.
    var onActionBar: ((CGRect?) -> Void)?
    /// Room above the row for an action bar that overhangs it: the hosting view reaches that far above the row (the
    /// cell positions it so), so SwiftUI can take clicks there; the row itself does not move.
    var topExtension: CGFloat = 0
    /// Changes when something a card reads from memory (a file's presence, a learned size) did; views that read
    /// `timelineContentRevision` draw again, which SwiftUI would otherwise skip for unchanged inputs.
    var contentRevision = 0

    var body: some View {
        TimelineItemView(
            item: item,
            isSelected: isSelected,
            isHighlighted: isHighlighted,
            showsSent: showsSent,
            actions: actions,
            ui: ui
        )
        .padding(.horizontal, TimelineTableMetrics.horizontalPadding)
        .deselectsOnEmptyClick(onEmptyClick)
        .font(.system(size: env.messagePointSize))
        .transformEnvironment(\.self) { values in
            values.appearancePreferences = env.appearance
            values.themeRoomID = env.themeRoomID
            values.themeAccentHex = env.themeAccentHex
            values.redactNamesAndPictures = env.redactNamesAndPictures
            values.liquidGlass = env.liquidGlass
            values.timelineCovered = env.timelineCovered
            values.courierMessagePointSize = env.messagePointSize
            values.courierZoomMultiplier = env.zoomMultiplier
            values.reactionCardOverride = env.reactionCardOverride
            values.clickTargetProbe = env.clickTargetProbe
            values.actionBarFrameProbe = onActionBar
            values.timelineTopExtension = topExtension
            values.timelineContentRevision = contentRevision
        }
        .coordinateSpace(.named(TimelineRowSpace.name))
    }
}

struct TimelineTopControlView: View {
    let state: TimelineTopControlState
    let onRetryOlder: () -> Void

    var body: some View {
        HStack {
            Spacer(minLength: 0)
            switch state {
            case .none:
                EmptyView()
            case .olderRetry:
                Button(String(localized: "Load older messages"), action: onRetryOlder)
                    .padding(10)
            case .olderSpinner:
                ProgressView()
                    .controlSize(.small)
                    .padding(10)
            case .earlierLoading:
                HStack(spacing: 6) {
                    ProgressView().controlSize(.small)
                    Text(String(localized: "Loading earlier messages…"))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .padding(10)
                .accessibilityElement(children: .combine)
            case .earlierSentinel:
                Color.clear.frame(height: 1)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, TimelineTableMetrics.horizontalPadding)
    }
}

private struct TimelineSizingView: View {
    let row: TimelineHostedRow
    let width: CGFloat

    var body: some View {
        row
            .frame(width: width, alignment: .leading)
            .fixedSize(horizontal: false, vertical: true)
    }
}

private struct TimelineTopControlSizingView: View {
    let control: TimelineTopControlView
    let width: CGFloat

    var body: some View {
        control
            .frame(width: width)
            .fixedSize(horizontal: false, vertical: true)
    }
}

private struct SenderHoverPopoverContent: View {
    let card: SenderHoverCardState
    let sharedGroups: [PersonHit]
    let contactsBridge: ContactsBridge
    let now: Date
    let showsMessageButton: Bool
    let appearance: AppearancePreferences?
    let themeRoomID: String?
    let themeAccentHex: String
    let messagePointSize: CGFloat
    let zoomMultiplier: CGFloat
    let colorScheme: ColorScheme
    let onMessage: () -> Void
    let onSelectRoom: (String) -> Void
    let onHover: (Bool) -> Void

    var body: some View {
        UserHoverCard(
            member: card.member,
            network: card.network,
            sharedGroups: sharedGroups,
            contactsBridge: contactsBridge,
            now: now,
            showsMessageButton: showsMessageButton,
            onMessage: onMessage,
            onSelectRoom: onSelectRoom
        )
        .onHover(perform: onHover)
        .font(.system(size: messagePointSize))
        .environment(\.appearancePreferences, appearance)
        .environment(\.themeRoomID, themeRoomID)
        .environment(\.themeAccentHex, themeAccentHex)
        .environment(\.courierMessagePointSize, messagePointSize)
        .environment(\.courierZoomMultiplier, zoomMultiplier)
        .environment(\.colorScheme, colorScheme)
    }
}

final class TimelineHostingView: NSHostingView<TimelineHostedRow> {
    override func menu(for event: NSEvent) -> NSMenu? {
        if let childMenu = super.menu(for: event) {
            childMenu.allowsContextMenuPlugIns = false
            return childMenu
        }
        guard case let .message(message) = rootView.item else { return nil }
        return MessageContextMenuBuilder.buildNSMenu(for: message, actions: rootView.actions)
    }
}

final class TimelineCell: NSTableCellView {
    let hostingView: TimelineHostingView

    init(identifier: NSUserInterfaceItemIdentifier, rootView: TimelineHostedRow) {
        self.hostingView = TimelineHostingView(rootView: rootView)
        super.init(frame: .zero)
        self.identifier = identifier
        clipsToBounds = false
        hostingView.sizingOptions = []
        hostingView.translatesAutoresizingMaskIntoConstraints = true
        hostingView.autoresizingMask = [.width, .height]
        hostingView.clipsToBounds = false
        addSubview(hostingView)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { nil }

    private var topExtension: CGFloat = 0

    func configure(with rootView: TimelineHostedRow, size: NSSize) {
        topExtension = rootView.topExtension
        if frame.size != size {
            frame = NSRect(origin: frame.origin, size: size)
        }
        hostingView.frame = hostingFrame
        hostingView.rootView = rootView
    }

    /// The cell's bounds, taller by `topExtension` above the row's top edge.
    private var hostingFrame: NSRect {
        NSRect(x: 0, y: isFlipped ? -topExtension : 0, width: bounds.width, height: bounds.height + topExtension)
    }

    override func layout() {
        super.layout()
        hostingView.frame = hostingFrame
    }

    override func isAccessibilityElement() -> Bool { false }
}

final class TimelineTopControlCell: NSTableCellView {
    let hostingView: NSHostingView<TimelineTopControlView>

    init(identifier: NSUserInterfaceItemIdentifier, rootView: TimelineTopControlView) {
        self.hostingView = NSHostingView(rootView: rootView)
        super.init(frame: .zero)
        self.identifier = identifier
        clipsToBounds = false
        hostingView.sizingOptions = []
        hostingView.translatesAutoresizingMaskIntoConstraints = true
        hostingView.autoresizingMask = [.width, .height]
        hostingView.clipsToBounds = false
        addSubview(hostingView)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { nil }

    func configure(with rootView: TimelineTopControlView, size: NSSize) {
        if frame.size != size {
            frame = NSRect(origin: frame.origin, size: size)
            hostingView.frame = bounds
        }
        hostingView.rootView = rootView
    }

    override func layout() {
        super.layout()
        hostingView.frame = bounds
    }

    override func isAccessibilityElement() -> Bool { false }
}

final class TimelineTableRowView: NSTableRowView {
    static let reuseIdentifier = NSUserInterfaceItemIdentifier("timeline.rowView")

    private var rowTrackingArea: NSTrackingArea?

    /// The selected message's action bar, in this row's coordinates, when it reaches outside the row (a wide
    /// continuation bubble's bar sits over its top corner). SwiftUI reports it; a click there goes to the row's
    /// hosting view, which a plain hit test would not do outside its bounds.
    var overhangingBarFrame: CGRect? {
        didSet {
            if (overhangingBarFrame != nil) != (oldValue != nil) {
                updateZPosition()
            }
        }
    }

    var isRaisedRow = false {
        didSet {
            if isRaisedRow != oldValue {
                updateZPosition()
            }
        }
    }

    var isHoveredRow = false {
        didSet {
            if isHoveredRow != oldValue {
                updateZPosition()
            }
        }
    }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        clipsToBounds = false
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { nil }

    override func prepareForReuse() {
        super.prepareForReuse()
        isRaisedRow = false
        isHoveredRow = false
        overhangingBarFrame = nil
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let rowTrackingArea {
            removeTrackingArea(rowTrackingArea)
        }
        let area = NSTrackingArea(
            rect: .zero,
            options: [.mouseEnteredAndExited, .activeInActiveApp, .inVisibleRect],
            owner: self,
            userInfo: nil
        )
        addTrackingArea(area)
        rowTrackingArea = area
    }

    override func mouseEntered(with event: NSEvent) {
        super.mouseEntered(with: event)
        isHoveredRow = true
    }

    override func mouseExited(with event: NSEvent) {
        super.mouseExited(with: event)
        isHoveredRow = false
    }

    private func updateZPosition() {
        layer?.zPosition = isRaisedRow ? 10 : ((isHoveredRow || overhangingBarFrame != nil) ? 5 : 0)
    }

    override func drawSelection(in _: NSRect) {}
    override func drawBackground(in _: NSRect) {}

    override func hitTest(_ point: NSPoint) -> NSView? {
        if let hit = super.hitTest(point) {
            return hit
        }
        guard isRaisedRow || isHoveredRow || overhangingBarFrame != nil,
              let bar = overhangingBarFrame,
              let superview else { return nil }
        let local = convert(point, from: superview)
        guard bar.insetBy(dx: -2, dy: -2).contains(local) else { return nil }
        return subviews.lazy.compactMap { $0 as? TimelineCell }.first?.hostingView
    }
}

final class TimelineNSTableView: NSTableView {
    var onEmptySpaceClick: (() -> Void)?

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        style = .plain
        headerView = nil
        selectionHighlightStyle = .none
        intercellSpacing = .zero
        usesAutomaticRowHeights = false
        rowSizeStyle = .custom
        rowHeight = 64
        floatsGroupRows = false
        backgroundColor = .clear
        gridStyleMask = []
        focusRingType = .none
        allowsTypeSelect = false
        allowsMultipleSelection = false
        allowsEmptySelection = true
        allowsColumnSelection = false
        allowsColumnReordering = false
        allowsColumnResizing = false
        clipsToBounds = false
        wantsLayer = true
        refusesFirstResponder = true
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { nil }

    override func validateProposedFirstResponder(_: NSResponder, for _: NSEvent?) -> Bool {
        true
    }

    override func hitTest(_ point: NSPoint) -> NSView? {
        // Raised or hovered rows (with an action bar or hover pill overhanging above their top edge) get first crack at overhanging clicks.
        for subview in subviews {
            guard let rowView = subview as? TimelineTableRowView,
                  rowView.isRaisedRow || rowView.isHoveredRow || rowView.overhangingBarFrame != nil else { continue }
            let overhang = rowView.frame.insetBy(dx: 0, dy: -TimelineTableMetrics.raisedOverhangPadding)
            if overhang.contains(point), let hit = rowView.hitTest(point) {
                return hit
            }
        }
        return super.hitTest(point)
    }

    /// The hosting view a click is handed to instead of the table's own handling (see `mouseDown`), until its mouse up.
    private var forwardedMouseTarget: NSView?

    override func mouseDown(with event: NSEvent) {
        let local = convert(event.locationInWindow, from: nil)
        // A selected message's action bar overhanging its row: the click is the bar's (a row view's hit test finds the
        // hosting view). It is handed to that view, whole, so the table's own tracking (which would wait here for
        // the mouse up and take the click for the row above) never starts.
        if forwardedMouseTarget != nil { return } // the hosting view passed it back: it is not the bar's
        if let target = overhangingBarTarget(at: local) {
            forwardedMouseTarget = target
            target.mouseDown(with: event)
            return
        }
        if row(at: local) == -1 {
            onEmptySpaceClick?()
            return
        }
        super.mouseDown(with: event)
    }

    override func mouseDragged(with event: NSEvent) {
        if let target = forwardedMouseTarget {
            target.mouseDragged(with: event)
        } else {
            super.mouseDragged(with: event)
        }
    }

    override func mouseUp(with event: NSEvent) {
        if let target = forwardedMouseTarget {
            forwardedMouseTarget = nil
            target.mouseUp(with: event)
        } else {
            super.mouseUp(with: event)
        }
    }

    private func overhangingBarTarget(at local: NSPoint) -> NSView? {
        for subview in subviews {
            guard let rowView = subview as? TimelineTableRowView,
                  rowView.isRaisedRow || rowView.isHoveredRow || rowView.overhangingBarFrame != nil,
                  rowView.overhangingBarFrame != nil,
                  let hit = rowView.hitTest(local) else { continue }
            return hit
        }
        return nil
    }
}

/// The timeline's scroll view. It tells the timeline when a wheel or trackpad event reaches it, so that only scrolling
/// this timeline counts as the person scrolling it (a wheel event over the inbox, or any other pane, does not).
final class TimelineScrollView: NSScrollView {
    var onWheel: (() -> Void)?

    override func scrollWheel(with event: NSEvent) {
        onWheel?()
        super.scrollWheel(with: event)
    }
}

final class TimelineContainerView: NSView {
    let scrollView = TimelineScrollView()
    var onLayout: ((CGSize) -> Void)?
    /// Told when the view enters a window (true) or leaves one (false); not for the first, windowless, state.
    var onWindowPresence: ((Bool) -> Void)?
    private var hadWindow = false
    /// The date capsule that floats under the chat's header while the person scrolls (`FloatingDayController`).
    let floatingDay = FloatingDayController()

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        if window != nil {
            hadWindow = true
            onWindowPresence?(true)
        } else if hadWindow {
            onWindowPresence?(false)
        }
    }

    override var isFlipped: Bool { true }

    override var intrinsicContentSize: NSSize {
        NSSize(width: NSView.noIntrinsicMetric, height: NSView.noIntrinsicMetric)
    }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        scrollView.drawsBackground = false
        scrollView.borderType = .noBorder
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = false
        scrollView.autohidesScrollers = true
        scrollView.automaticallyAdjustsContentInsets = false
        scrollView.translatesAutoresizingMaskIntoConstraints = true
        addSubview(scrollView)
        addSubview(floatingDay.hostingView)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { nil }

    override func layout() {
        super.layout()
        if scrollView.frame != bounds {
            scrollView.frame = bounds
        }
        // Centred just under the chat's header: the scroll view's top inset is the header and the timeline's own
        // padding, and the capsule sits that padding's width less than a gap below the header.
        let capsuleFrame = NSRect(
            x: 0,
            y: max(0, scrollView.contentInsets.top - ConversationView.timelineVerticalPadding + 6),
            width: bounds.width,
            height: FloatingDayHostingView.height
        )
        if floatingDay.hostingView.frame != capsuleFrame {
            floatingDay.hostingView.frame = capsuleFrame
        }
        onLayout?(bounds.size)
    }
}

struct TimelineTableView: NSViewRepresentable {
    let conversation: ConversationModel
    let messageActions: MessageActionsModel
    let preferences: ComposerPreferences
    let ui: MessageUI
    let appModel: AppModel
    let actions: MessageActions
    let effectiveHeaderInset: CGFloat
    let bottomSafeAreaInset: CGFloat
    let bottomBarSignature: [String]
    let resolvedAppearance: AppearancePreferences?
    let redact: Bool
    let themeAccentHex: String
    let drawsLiquidGlass: Bool
    let timelineCovered: Bool

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    func makeNSView(context: Context) -> TimelineContainerView {
        let coordinator = context.coordinator
        coordinator.syncEnvironment(from: self, environment: context.environment)
        coordinator.setup()
        coordinator.applyUpdates(from: self, environment: context.environment)
        return coordinator.containerView
    }

    static func dismantleNSView(_ nsView: TimelineContainerView, coordinator: Coordinator) {
        coordinator.shutDown()
    }

    func updateNSView(_ nsView: TimelineContainerView, context: Context) {
        let coordinator = context.coordinator
        coordinator.parent = self
        coordinator.syncEnvironment(from: self, environment: context.environment)
        coordinator.applyUpdates(from: self, environment: context.environment)
    }

    @MainActor
    final class Coordinator: NSObject, NSTableViewDataSource, NSTableViewDelegate, NSPopoverDelegate {
        var parent: TimelineTableView
        let containerView = TimelineContainerView()
        let tableView = TimelineNSTableView()
        let column = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("timeline.column"))
        let heightCache = RowHeightCache()

        private(set) var entries: [TimelineRowEntry] = []
        private(set) var createdCellCount = 0
        private(set) var reusedCellCount = 0
        private var rowByID: [String: Int] = [:]
        /// How far above its row each selected message's action bar reaches (`TimelineHostedRow.topExtension`).
        private var topExtensions: [String: CGFloat] = [:]
        private var rowEnvironment: TimelineRowEnvironment!
        private var sizingActions: MessageActions!
        private var sizingHosts: [TimelineRowKind: NSHostingView<TimelineSizingView>] = [:]
        private var topControlSizingHost: NSHostingView<TimelineTopControlSizingView>!

        private var measuredWidth: CGFloat = 0
        private var pendingResizeWidth: CGFloat = 0
        private var resizeDebounceWorkItem: DispatchWorkItem?
        private var heightPassGeneration = 0

        private var hasPositionedInitially = false
        private var isApplyingProgrammaticUpdate = false
        private var lastAtBottom = true
        private var lastObservedClipOriginY: CGFloat = 0
        private var topInView = false
        private var earlierTopInView = false
        private var restoreAnchor: String?
        private var leavingBottomTask: Task<Void, Never>?
        private var pinToBottomUntil: Date?
        private var lastUserScroll = Date.distantPast
        private var lastScrollGesture = Date.distantPast
        /// When the person last scrolled with the wheel, the trackpad or by dragging (not a key or a click): what
        /// lets the floating date capsule show (`FloatingDay.showsForScroll`).
        private var lastPointerScroll = Date.distantPast
        /// The mouse button went down in this timeline and has not come up: its drags can scroll it.
        private var dragBeganInTimeline = false
        /// The row at the top when the floating date was last looked up, and the day found for it.
        private var floatingDayRow = -1
        private var floatingDayRowID: String?
        private var floatingDayValue: Date?
        private var scrolledToMessageSerial: Int?

        private var lastHandledScrollSerial: Int?
        private var lastJumpToBottomRequest = 0
        private var lastBottomBarSignature: [String] = []
        private var lastItems: [TimelineItem] = []
        private var lastTopControl: TimelineTopControlState = .none
        private var lastSelectedID: String?
        private var lastHighlightedID: String?
        private var lastLastOutgoingID: String?
        private var lastHeightEnvSignature = 0
        private var lastVisualEnvSignature = 0
        private var lastActionsHeightSignature = 0
        private var lastPickingReactionID: String?
        private var lastUIStateSignature = 0
        private var lastTranslationsSignature = 0
        private var lastTranscriptsSignature = 0

        private var clipBoundsObserver: NSObjectProtocol?
        private var liveScrollObserver: NSObjectProtocol?
        private var sizeLearnedObserver: NSObjectProtocol?
        private var lockObserver: NSObjectProtocol?
        private var transcriptCancellable: AnyCancellable?
        private var userScrollMonitor: Any?
        private var pinScrollMonitor: Any?

        private lazy var senderPopover: NSPopover = {
            let popover = NSPopover()
            popover.behavior = .semitransient
            popover.animates = false
            popover.delegate = self
            return popover
        }()
        private var senderPopoverController: NSHostingController<SenderHoverPopoverContent>?
        private var presentedSenderCardMessageID: String?
        private var suppressPopoverCloseCallback = false

        var isSenderPopoverShownForTesting: Bool {
            senderPopover.isShown
        }

        #if DEBUG
        /// What the scroll-wheel monitor records for a person's scroll, for tests that scroll the clip view directly.
        func noteUserScrollForTesting() {
            lastUserScroll = Date()
            lastScrollGesture = Date()
            lastPointerScroll = Date()
            stopPinningToBottom()
        }
        #endif

        init(_ parent: TimelineTableView) {
            self.parent = parent
            super.init()
        }

        /// The table is out of its window for good: pending height pre-warms, lazy re-measures, the resize debounce and
        /// the pin-to-bottom timers stop, and nothing measures a row again. (Without this they ran on the main run loop
        /// after the view was gone, evaluating rows and costing whatever else was on screen.)
        private(set) var isShutDown = false

        func shutDown() {
            guard !isShutDown else { return }
            isShutDown = true
            heightPassGeneration += 1
            resizeDebounceWorkItem?.cancel()
            resizeDebounceWorkItem = nil
            leavingBottomTask?.cancel()
            leavingBottomTask = nil
            stopPinningToBottom()
            pinToBottomUntil = nil
            containerView.floatingDay.reset()
            dismissSenderPopover()
            if let userScrollMonitor {
                NSEvent.removeMonitor(userScrollMonitor)
                self.userScrollMonitor = nil
            }
        }

        /// The table is in a window again (it was moved, not removed): measuring resumes.
        func resume() {
            guard isShutDown else { return }
            isShutDown = false
            installUserScrollMonitor()
            guard hasPositionedInitially, !entries.isEmpty else { return }
            tableView.noteHeightOfRows(withIndexesChanged: IndexSet(integersIn: 0 ..< entries.count))
            heightPassGeneration += 1
            scheduleHeightPrewarm(generation: heightPassGeneration)
        }

        deinit {
            resizeDebounceWorkItem?.cancel()
            leavingBottomTask?.cancel()
            if let clipBoundsObserver {
                NotificationCenter.default.removeObserver(clipBoundsObserver)
            }
            if let liveScrollObserver {
                NotificationCenter.default.removeObserver(liveScrollObserver)
            }
            if let sizeLearnedObserver {
                NotificationCenter.default.removeObserver(sizeLearnedObserver)
            }
            if let lockObserver {
                NotificationCenter.default.removeObserver(lockObserver)
            }
            if let userScrollMonitor {
                NSEvent.removeMonitor(userScrollMonitor)
            }
            if let pinScrollMonitor {
                NSEvent.removeMonitor(pinScrollMonitor)
            }
        }

        func setup() {
            InlinePDFDocumentCache.installWarmer()
            containerView.scrollView.documentView = tableView
            column.resizingMask = .autoresizingMask
            column.isEditable = false
            tableView.addTableColumn(column)
            tableView.dataSource = self
            tableView.delegate = self
            tableView.onEmptySpaceClick = { [weak self] in
                self?.parent.conversation.deselectMessage()
            }

            containerView.scrollView.contentView.postsBoundsChangedNotifications = true
            clipBoundsObserver = NotificationCenter.default.addObserver(
                forName: NSView.boundsDidChangeNotification,
                object: containerView.scrollView.contentView,
                queue: .main
            ) { [weak self] _ in
                MainActor.assumeIsolated {
                    self?.handleBoundsDidChange()
                }
            }

            liveScrollObserver = NotificationCenter.default.addObserver(
                forName: NSScrollView.willStartLiveScrollNotification,
                object: containerView.scrollView,
                queue: .main
            ) { [weak self] _ in
                MainActor.assumeIsolated {
                    guard let self else { return }
                    self.lastUserScroll = Date()
                    self.lastScrollGesture = Date()
                    self.lastPointerScroll = Date()
                    self.stopPinningToBottom()
                }
            }

            sizeLearnedObserver = NotificationCenter.default.addObserver(
                forName: ImagePixelSizeReader.didLearnSizeNotification,
                object: nil,
                queue: .main
            ) { [weak self] note in
                let path = note.userInfo?[ImagePixelSizeReader.pathUserInfoKey] as? String
                MainActor.assumeIsolated {
                    self?.handleLearnedImageSize(forPath: path)
                }
            }

            lockObserver = NotificationCenter.default.addObserver(
                forName: SystemLifecycleModel.didLockNotification,
                object: nil,
                queue: .main
            ) { [weak self] _ in
                MainActor.assumeIsolated {
                    self?.dismissSenderPopover()
                }
            }

            transcriptCancellable = parent.conversation.voiceNoteTranscripts.$entries
                .dropFirst()
                .sink { [weak self] _ in
                    DispatchQueue.main.async { [weak self] in
                        self?.handleVoiceNoteTranscriptChange()
                    }
                }

            installUserScrollMonitor()
            containerView.scrollView.onWheel = { [weak self] in
                MainActor.assumeIsolated { self?.lastPointerScroll = Date() }
            }

            containerView.onLayout = { [weak self] size in
                self?.handleContainerLayout(size: size)
            }
            containerView.onWindowPresence = { [weak self] present in
                MainActor.assumeIsolated {
                    if present { self?.resume() } else { self?.shutDown() }
                }
            }

            updateScrollInsets(adjustScrollPosition: false)
        }

        private func installUserScrollMonitor() {
            userScrollMonitor = NSEvent.addLocalMonitorForEvents(
                matching: [.scrollWheel, .keyDown, .leftMouseDown, .leftMouseDragged, .leftMouseUp]
            ) { [weak self] event in
                MainActor.assumeIsolated {
                    guard let self else { return }
                    if event.type == .leftMouseUp {
                        self.dragBeganInTimeline = false
                        return
                    }
                    self.lastUserScroll = Date()
                    if event.type == .leftMouseDown {
                        // A drag that began in this timeline (its scroller, or a selection) can scroll it; a drag in
                        // another pane cannot.
                        let point = self.containerView.convert(event.locationInWindow, from: nil)
                        self.dragBeganInTimeline = event.window != nil
                            && event.window === self.containerView.window
                            && self.containerView.bounds.contains(point)
                    }
                    if event.type == .leftMouseDragged, self.dragBeganInTimeline {
                        self.lastPointerScroll = Date()
                    }
                    if event.type != .leftMouseDown {
                        self.lastScrollGesture = Date()
                        if self.earlierTopInView, event.type != .scrollWheel || event.scrollingDeltaY > 0 {
                            self.parent.conversation.loadEarlier()
                        }
                    }
                }
                return event
            }
        }

        func syncEnvironment(from view: TimelineTableView, environment: EnvironmentValues) {
            storedProbe = environment.conversationLayoutProbe
            let env = TimelineRowEnvironment(
                appearance: view.resolvedAppearance ?? environment.appearancePreferences,
                themeRoomID: view.conversation.roomID,
                themeAccentHex: view.themeAccentHex,
                redactNamesAndPictures: view.redact,
                liquidGlass: view.drawsLiquidGlass,
                timelineCovered: view.timelineCovered,
                messagePointSize: environment.courierMessagePointSize,
                zoomMultiplier: environment.courierZoomMultiplier,
                colorScheme: environment.colorScheme,
                reactionCardOverride: environment.reactionCardOverride,
                clickTargetProbe: environment.clickTargetProbe
            )
            rowEnvironment = env

            var lightweightActions = view.actions
            lightweightActions.menu = { _ in [] }
            sizingActions = lightweightActions

            if topControlSizingHost == nil {
                topControlSizingHost = NSHostingView(
                    rootView: TimelineTopControlSizingView(
                        control: TimelineTopControlView(state: .olderSpinner, onRetryOlder: {}),
                        width: 300
                    )
                )
                topControlSizingHost.sizingOptions = [.intrinsicContentSize]
            }
            let targetAppearance = containerView.effectiveAppearance
            for host in sizingHosts.values {
                host.appearance = targetAppearance
            }
            topControlSizingHost.appearance = targetAppearance
        }

        // MARK: - NSTableViewDataSource / NSTableViewDelegate

        func numberOfRows(in _: NSTableView) -> Int {
            entries.count
        }

        func tableView(_: NSTableView, shouldSelectRow _: Int) -> Bool {
            false
        }

        func tableView(_: NSTableView, heightOfRow row: Int) -> CGFloat {
            guard row >= 0, row < entries.count else { return 1 }
            let width = effectiveMeasureWidth
            guard width > 1 else { return 44 }
            let entry = entries[row]
            if let cached = heightCache.height(for: entry.id, contentRevision: entry.contentRevision, width: width) {
                return cached
            }
            // Out of its window nothing is measured: a placeholder that is not remembered (`resume` re-measures).
            if isShutDown { return 44 }
            let measured = measureEntryHeight(entry, width: width)
            heightCache.insert(measured, for: entry.id, contentRevision: entry.contentRevision, width: width)
            return measured
        }

        func tableView(_ tableView: NSTableView, viewFor _: NSTableColumn?, row: Int) -> NSView? {
            guard row >= 0, row < entries.count else { return nil }
            let entry = entries[row]
            let targetWidth = effectiveMeasureWidth > 1 ? effectiveMeasureWidth : column.width
            let targetHeight = self.tableView(tableView, heightOfRow: row)
            let targetSize = NSSize(width: max(1, targetWidth), height: max(1, targetHeight))
            if entry.kind == .topControl {
                let control = makeTopControlView(for: entry.topControl ?? .none)
                if let reused = tableView.makeView(withIdentifier: entry.kind.identifier, owner: self) as? TimelineTopControlCell {
                    reusedCellCount += 1
                    reused.configure(with: control, size: targetSize)
                    return reused
                }
                createdCellCount += 1
                let cell = TimelineTopControlCell(identifier: entry.kind.identifier, rootView: control)
                cell.frame = NSRect(origin: .zero, size: targetSize)
                cell.hostingView.frame = cell.bounds
                return cell
            }
            guard let item = entry.item else { return nil }
            let hosted = makeHostedRow(for: entry, item: item)
            if let reused = tableView.makeView(withIdentifier: entry.kind.identifier, owner: self) as? TimelineCell {
                reusedCellCount += 1
                reused.configure(with: hosted, size: targetSize)
                return reused
            }
            createdCellCount += 1
            let cell = TimelineCell(identifier: entry.kind.identifier, rootView: hosted)
            cell.frame = NSRect(origin: .zero, size: targetSize)
            cell.configure(with: hosted, size: targetSize)
            return cell
        }

        func tableView(_ tableView: NSTableView, rowViewForRow row: Int) -> NSTableRowView? {
            let rowView: TimelineTableRowView
            if let reused = tableView.makeView(withIdentifier: TimelineTableRowView.reuseIdentifier, owner: self) as? TimelineTableRowView {
                rowView = reused
            } else {
                rowView = TimelineTableRowView()
                rowView.identifier = TimelineTableRowView.reuseIdentifier
            }
            if row >= 0, row < entries.count {
                rowView.isRaisedRow = entries[row].isRaised
            }
            return rowView
        }

        // MARK: - Measuring & Cell Factories

        private var effectiveMeasureWidth: CGFloat {
            if measuredWidth > 1 { return measuredWidth }
            let clipW = containerView.scrollView.contentView.bounds.width
            if clipW > 1 { return clipW }
            return containerView.bounds.width
        }

        private func sizingHost(for kind: TimelineRowKind, initialRow: TimelineHostedRow, width: CGFloat) -> NSHostingView<TimelineSizingView> {
            if let existing = sizingHosts[kind] {
                return existing
            }
            let host = NSHostingView(rootView: TimelineSizingView(row: initialRow, width: width))
            host.sizingOptions = [.intrinsicContentSize]
            host.appearance = containerView.effectiveAppearance
            sizingHosts[kind] = host
            return host
        }

        private func measureEntryHeight(_ entry: TimelineRowEntry, width: CGFloat) -> CGFloat {
            if isShutDown { return 44 }
            if entry.kind == .topControl {
                let control = makeTopControlView(for: entry.topControl ?? .none)
                topControlSizingHost.rootView = TimelineTopControlSizingView(control: control, width: width)
                topControlSizingHost.invalidateIntrinsicContentSize()
                let raw = topControlSizingHost.fittingSize.height
                return max(1, (raw * 2).rounded(.up) / 2)
            }
            guard let item = entry.item else { return 1 }
            let row = makeHostedRow(for: entry, item: item, actions: sizingActions ?? parent.actions)
            let host = sizingHost(for: entry.kind, initialRow: row, width: width)
            host.rootView = TimelineSizingView(row: row, width: width)
            host.invalidateIntrinsicContentSize()
            let raw = host.fittingSize.height
            return max(1, (raw * 2).rounded(.up) / 2)
        }

        private func makeHostedRow(
            for entry: TimelineRowEntry,
            item: TimelineItem,
            actions overrideActions: MessageActions? = nil
        ) -> TimelineHostedRow {
            var env = rowEnvironment!
            if overrideActions != nil {
                // Off-screen sizing never emits click target probes.
                env = TimelineRowEnvironment(
                    appearance: env.appearance,
                    themeRoomID: env.themeRoomID,
                    themeAccentHex: env.themeAccentHex,
                    redactNamesAndPictures: env.redactNamesAndPictures,
                    liquidGlass: env.liquidGlass,
                    timelineCovered: env.timelineCovered,
                    messagePointSize: env.messagePointSize,
                    zoomMultiplier: env.zoomMultiplier,
                    colorScheme: env.colorScheme,
                    reactionCardOverride: env.reactionCardOverride,
                    clickTargetProbe: nil
                )
            }
            return TimelineHostedRow(
                item: item,
                isSelected: entry.isSelected,
                isHighlighted: entry.isHighlighted,
                showsSent: entry.showsSent,
                actions: overrideActions ?? parent.actions,
                ui: parent.ui,
                env: env,
                onEmptyClick: { [weak self] in
                    self?.parent.conversation.deselectMessage()
                },
                onActionBar: overrideActions != nil ? nil : { [weak self] rect in
                    self?.actionBarChanged(rect, forRowID: entry.id)
                },
                topExtension: overrideActions != nil ? 0 : (topExtensions[entry.id] ?? 0),
                contentRevision: entry.contentRevision
            )
        }

        /// A selected message's action bar moved: its row view keeps the frame for hit testing.
        private func actionBarChanged(_ rect: CGRect?, forRowID id: String) {
            guard let row = rowByID[id],
                  let rowView = tableView.rowView(atRow: row, makeIfNecessary: false) as? TimelineTableRowView
            else { return }
            // Reported in the hosting view's space, which starts `topExtensions[id]` above the row.
            let rowRect = rect?.offsetBy(dx: 0, dy: -(topExtensions[id] ?? 0))
            rowView.overhangingBarFrame = rowRect
            let needed = rowRect.map { max(0, ceil(-$0.minY)) } ?? 0
            guard abs(needed - (topExtensions[id] ?? 0)) > 0.5 else { return }
            topExtensions[id] = needed == 0 ? nil : needed
            // Not inside the view update that reported it.
            DispatchQueue.main.async { [weak self] in
                guard let self, !self.isShutDown, let row = self.rowByID[id] else { return }
                self.reconfigureVisibleRow(at: row)
            }
        }

        private func makeTopControlView(for state: TimelineTopControlState) -> TimelineTopControlView {
            TimelineTopControlView(state: state) { [weak self] in
                self?.requestOlder()
            }
        }

        // MARK: - Layout & Resize Debounce

        private func handleContainerLayout(size: CGSize) {
            let scrollView = containerView.scrollView
            let clipWidth = scrollView.contentView.bounds.width > 0 ? scrollView.contentView.bounds.width : size.width
            guard clipWidth > 1 else { return }

            if abs(column.width - clipWidth) > 0.5 {
                column.width = clipWidth
            }

            if measuredWidth <= 1 {
                measuredWidth = clipWidth
                pendingResizeWidth = clipWidth
                performInitialLayoutIfReady()
                return
            }

            if abs(clipWidth - pendingResizeWidth) > 0.5 {
                pendingResizeWidth = clipWidth
                scheduleWidthResize(to: clipWidth)
            } else if !hasPositionedInitially {
                performInitialLayoutIfReady()
            }
        }

        private func performInitialLayoutIfReady() {
            guard !hasPositionedInitially, measuredWidth > 1 else { return }
            isApplyingProgrammaticUpdate = true
            tableView.reloadData()
            tableView.layoutSubtreeIfNeeded()

            if let request = parent.conversation.scrollToMessageRequest {
                lastHandledScrollSerial = request.serial
                scrollToRow(id: request.messageID, preferCenter: true)
                scrollToMessage(request)
            } else if !parent.conversation.isAwayFromLatest, !parent.conversation.isHeldAwayFromLatest {
                scrollToBottom(animated: false)
                startPinningToBottom()
            } else {
                scrollToTop(animated: false)
            }
            hasPositionedInitially = true
            isApplyingProgrammaticUpdate = false
            lastObservedClipOriginY = containerView.scrollView.contentView.bounds.origin.y
            lastAtBottom = isScrolledToBottom()
            parent.conversation.scrolled(toBottom: lastAtBottom)
            evaluateScrollPosition()
            reportVisibleProbes()
            heightPassGeneration += 1
            scheduleHeightPrewarm(generation: heightPassGeneration)
        }

        private func scheduleWidthResize(to targetWidth: CGFloat) {
            resizeDebounceWorkItem?.cancel()
            let item = DispatchWorkItem { [weak self] in
                MainActor.assumeIsolated {
                    self?.applyWidthChange(to: targetWidth)
                }
            }
            resizeDebounceWorkItem = item
            DispatchQueue.main.asyncAfter(deadline: .now() + TimelineTableMetrics.resizeDebounceInterval, execute: item)
        }

        private func applyWidthChange(to newWidth: CGFloat) {
            guard newWidth > 1, abs(newWidth - measuredWidth) > 0.5 else { return }
            let wasAtBottom = isScrolledToBottom()
            let anchor = wasAtBottom ? nil : visibleAnchor(preferMessage: true)

            measuredWidth = newWidth
            heightCache.invalidateWidth(keeping: newWidth)
            heightPassGeneration += 1
            let generation = heightPassGeneration

            guard !entries.isEmpty else { return }
            let visibleRange = tableView.rows(in: tableView.visibleRect)
            let start = max(0, min(entries.count - 1, visibleRange.location))
            let end = max(start, min(entries.count, visibleRange.location + max(visibleRange.length, 1)))
            let visibleSet = IndexSet(integersIn: start ..< end)

            isApplyingProgrammaticUpdate = true
            NSAnimationContext.runAnimationGroup { ctx in
                ctx.duration = 0
                ctx.allowsImplicitAnimation = false
                tableView.noteHeightOfRows(withIndexesChanged: visibleSet)
                tableView.layoutSubtreeIfNeeded()
                restoreScrollAfterHeightChange(wasAtBottom: wasAtBottom, anchor: anchor)
            }
            isApplyingProgrammaticUpdate = false
            // The new width moved the bottom (and every row): the bottom flag and the layout probes follow it.
            evaluateScrollPosition()
            reportVisibleProbes()

            // Remaining off-screen rows re-measure lazily in bounded batches.
            var remaining = IndexSet(integersIn: 0 ..< entries.count)
            remaining.subtract(visibleSet)
            if !remaining.isEmpty {
                scheduleLazyHeightInvalidation(remaining: Array(remaining), generation: generation)
            }
        }

        private func scheduleLazyHeightInvalidation(remaining: [Int], generation: Int) {
            guard generation == heightPassGeneration, !remaining.isEmpty else { return }
            let batchCount = min(TimelineTableMetrics.lazyHeightInvalidationBatchSize, remaining.count)
            let batch = IndexSet(remaining.prefix(batchCount))
            let rest = Array(remaining.dropFirst(batchCount))
            DispatchQueue.main.async { [weak self] in
                guard let self, generation == self.heightPassGeneration else { return }
                let wasAtBottom = self.isScrolledToBottom()
                let anchor = wasAtBottom ? nil : self.visibleAnchor(preferMessage: true)
                self.isApplyingProgrammaticUpdate = true
                NSAnimationContext.runAnimationGroup { ctx in
                    ctx.duration = 0
                    ctx.allowsImplicitAnimation = false
                    self.tableView.noteHeightOfRows(withIndexesChanged: batch)
                    self.tableView.layoutSubtreeIfNeeded()
                    self.restoreScrollAfterHeightChange(wasAtBottom: wasAtBottom, anchor: anchor)
                }
                self.isApplyingProgrammaticUpdate = false
                if !rest.isEmpty {
                    self.scheduleLazyHeightInvalidation(remaining: rest, generation: generation)
                }
            }
        }

        private func scheduleHeightPrewarm(generation: Int) {
            guard generation == heightPassGeneration, !entries.isEmpty, measuredWidth > 1 else { return }
            let width = measuredWidth
            let visibleRange = tableView.rows(in: tableView.visibleRect)
            let visStart = max(0, min(entries.count, visibleRange.location))
            let visEnd = max(visStart, min(entries.count, visibleRange.location + visibleRange.length))
            var missing: [Int] = []
            if visStart > 0 {
                for row in stride(from: visStart - 1, through: 0, by: -1) {
                    let entry = entries[row]
                    if !heightCache.contains(id: entry.id, contentRevision: entry.contentRevision, width: width) {
                        missing.append(row)
                    }
                }
            }
            if visEnd < entries.count {
                for row in visEnd ..< entries.count {
                    let entry = entries[row]
                    if !heightCache.contains(id: entry.id, contentRevision: entry.contentRevision, width: width) {
                        missing.append(row)
                    }
                }
            }
            guard !missing.isEmpty else { return }
            scheduleHeightPrewarmBatch(rows: missing, width: width, generation: generation)
        }

        private func scheduleHeightPrewarmBatch(rows: [Int], width: CGFloat, generation: Int) {
            guard generation == heightPassGeneration, !rows.isEmpty else { return }
            let batchCount = min(TimelineTableMetrics.initialPrewarmBatchSize, rows.count)
            let slice = Array(rows.prefix(batchCount))
            let rest = Array(rows.dropFirst(batchCount))
            DispatchQueue.main.async { [weak self] in
                guard let self, generation == self.heightPassGeneration, abs(self.measuredWidth - width) <= 0.5 else { return }
                let wasAtBottom = self.isScrolledToBottom()
                let anchor = wasAtBottom ? nil : self.visibleAnchor(preferMessage: true)
                var changed = IndexSet()
                for row in slice where row < self.entries.count {
                    let entry = self.entries[row]
                    if !self.heightCache.contains(id: entry.id, contentRevision: entry.contentRevision, width: width) {
                        let measured = self.measureEntryHeight(entry, width: width)
                        self.heightCache.insert(measured, for: entry.id, contentRevision: entry.contentRevision, width: width)
                    }
                    changed.insert(row)
                }
                if !changed.isEmpty {
                    self.isApplyingProgrammaticUpdate = true
                    NSAnimationContext.runAnimationGroup { ctx in
                        ctx.duration = 0
                        ctx.allowsImplicitAnimation = false
                        self.tableView.noteHeightOfRows(withIndexesChanged: changed)
                        self.tableView.layoutSubtreeIfNeeded()
                        self.restoreScrollAfterHeightChange(wasAtBottom: wasAtBottom, anchor: anchor)
                    }
                    self.isApplyingProgrammaticUpdate = false
                }
                if !rest.isEmpty {
                    self.scheduleHeightPrewarmBatch(rows: rest, width: width, generation: generation)
                }
            }
        }

        private func restoreScrollAfterHeightChange(wasAtBottom: Bool, anchor: (id: String, screenMinY: CGFloat)?) {
            if wasAtBottom, !parent.conversation.isAwayFromLatest {
                scrollToBottom(animated: false)
            } else if let anchor, let row = rowByID[anchor.id] {
                let targetOriginY = tableView.rect(ofRow: row).minY - anchor.screenMinY
                scrollClipView(toY: targetOriginY)
            }
        }

        // MARK: - Updates & CollectionDifference

        func applyUpdates(from view: TimelineTableView, environment: EnvironmentValues) {
            let conversation = view.conversation
            let items = conversation.items
            let topControl = currentTopControl(conversation: conversation)
            let selectedID = conversation.selectedMessageID
            let highlightedID = conversation.highlightedMessageID
            let lastOutgoingID = conversation.lastOutgoingID
            let actionsHeightSig = computeActionsHeightSignature(view: view, items: items)
            let pickingID = reactionPickerMessageID(view.messageActions.request)
            let uiSig = computeUISignature(view.ui)
            let translationsSig = computeTranslationsSignature(view.messageActions)
            let transcriptsSig = computeTranscriptsSignature(conversation.voiceNoteTranscripts)

            let insetsChanged = updateScrollInsets(adjustScrollPosition: hasPositionedInitially)

            let dataOrHeightChanged = items != lastItems
                || topControl != lastTopControl
                || rowEnvironment.heightSignature != lastHeightEnvSignature
                || actionsHeightSig != lastActionsHeightSignature
                || uiSig != lastUIStateSignature
                || translationsSig != lastTranslationsSignature
                || transcriptsSig != lastTranscriptsSignature

            let selectionOrVisualChanged = selectedID != lastSelectedID
                || highlightedID != lastHighlightedID
                || lastOutgoingID != lastLastOutgoingID
                || pickingID != lastPickingReactionID
                || rowEnvironment.visualSignature != lastVisualEnvSignature

            if dataOrHeightChanged {
                let newEntries = buildEntries(
                    items: items,
                    topControl: topControl,
                    selectedID: selectedID,
                    highlightedID: highlightedID,
                    lastOutgoingID: lastOutgoingID,
                    pickingID: pickingID,
                    view: view
                )
                applyDiffedEntries(newEntries, view: view, oldItems: lastItems)
            } else if selectionOrVisualChanged {
                applyTargetedRowUpdates(
                    items: items,
                    topControl: topControl,
                    selectedID: selectedID,
                    highlightedID: highlightedID,
                    lastOutgoingID: lastOutgoingID,
                    pickingID: pickingID,
                    view: view
                )
            }

            lastItems = items
            lastTopControl = topControl
            lastSelectedID = selectedID
            lastHighlightedID = highlightedID
            lastLastOutgoingID = lastOutgoingID
            lastHeightEnvSignature = rowEnvironment.heightSignature
            lastVisualEnvSignature = rowEnvironment.visualSignature
            lastActionsHeightSignature = actionsHeightSig
            lastPickingReactionID = pickingID
            lastUIStateSignature = uiSig
            lastTranslationsSignature = translationsSig
            lastTranscriptsSignature = transcriptsSig

            handleRequests(view: view, insetsChanged: insetsChanged)
            syncSenderCardPopover(view: view, environment: environment)

            if storedProbe != nil {
                reportVisibleProbes()
            }
        }

        private func buildEntries(
            items: [TimelineItem],
            topControl: TimelineTopControlState,
            selectedID: String?,
            highlightedID: String?,
            lastOutgoingID: String?,
            pickingID: String?,
            view: TimelineTableView
        ) -> [TimelineRowEntry] {
            var result: [TimelineRowEntry] = []
            result.reserveCapacity(items.count + (topControl == .none ? 0 : 1))
            if topControl != .none {
                result.append(.topControl(topControl))
            }
            let timerCount = view.conversation.timerChoices.count
            for item in items {
                let id = item.id
                result.append(
                    .item(
                        item,
                        isSelected: selectedID == id,
                        isHighlighted: highlightedID == id,
                        showsSent: lastOutgoingID == id,
                        actions: view.actions,
                        ui: view.ui,
                        messageActions: view.messageActions,
                        voiceNoteTranscripts: view.conversation.voiceNoteTranscripts,
                        timerChoicesCount: timerCount,
                        env: rowEnvironment,
                        isPickingReaction: pickingID == id
                    )
                )
            }
            return result
        }

        private func applyDiffedEntries(
            _ newEntries: [TimelineRowEntry],
            view: TimelineTableView,
            oldItems: [TimelineItem]
        ) {
            let oldEntries = self.entries
            guard hasPositionedInitially, measuredWidth > 1 else {
                self.entries = newEntries
                rebuildRowIndexMap()
                if measuredWidth > 1 {
                    performInitialLayoutIfReady()
                }
                return
            }

            let conversation = view.conversation
            let wasAtBottom = isScrolledToBottom()
            let arrivedEarlierAnchor = conversation.takeEarlierAnchor()
            let prependAnchor = computePrependAnchorIfNeeded(
                oldEntries: oldEntries,
                newEntries: newEntries,
                oldItems: oldItems,
                newItems: conversation.items,
                explicitAnchorID: restoreAnchor ?? arrivedEarlierAnchor
            )
            if prependAnchor != nil {
                restoreAnchor = nil
            }

            let oldIDs = oldEntries.map(\.id)
            let newIDs = newEntries.map(\.id)
            let diff = newIDs.difference(from: oldIDs)

            var removedIndexes = IndexSet()
            var insertedIndexes = IndexSet()
            for change in diff {
                switch change {
                case let .remove(offset, _, _):
                    removedIndexes.insert(offset)
                case let .insert(offset, _, _):
                    insertedIndexes.insert(offset)
                }
            }

            // Pair surviving indices in lockstep to find content/visual changes without quadratic lookups.
            var heightChangedNewIndexes = IndexSet()
            var reconfigureNewIndexes: [Int] = []
            var reloadNewIndexes = IndexSet()
            var oldIdx = 0
            var newIdx = 0
            while oldIdx < oldEntries.count && newIdx < newEntries.count {
                if removedIndexes.contains(oldIdx) {
                    oldIdx += 1
                    continue
                }
                if insertedIndexes.contains(newIdx) {
                    newIdx += 1
                    continue
                }
                let oldEntry = oldEntries[oldIdx]
                let newEntry = newEntries[newIdx]
                if oldEntry.contentRevision != newEntry.contentRevision {
                    heightChangedNewIndexes.insert(newIdx)
                }
                if oldEntry.kind != newEntry.kind {
                    reloadNewIndexes.insert(newIdx)
                } else if oldEntry.visualHash != newEntry.visualHash || oldEntry.item != newEntry.item || oldEntry.topControl != newEntry.topControl {
                    reconfigureNewIndexes.append(newIdx)
                }
                oldIdx += 1
                newIdx += 1
            }

            if !removedIndexes.isEmpty {
                let removedIDs = Set(removedIndexes.map { oldEntries[$0].id })
                let retainedIDs = Set(newEntries.map(\.id))
                heightCache.invalidateItems(ids: removedIDs.subtracting(retainedIDs))
            }

            let hasStructuralOrHeightChanges = !removedIndexes.isEmpty
                || !insertedIndexes.isEmpty
                || !heightChangedNewIndexes.isEmpty
                || !reloadNewIndexes.isEmpty
            let scrollAnchor: (id: String, screenMinY: CGFloat)? =
                (prependAnchor == nil && !wasAtBottom && !isPinningToBottom && restoreAnchor == nil && hasStructuralOrHeightChanges)
                ? visibleAnchor(preferMessage: false, allowedIDs: Set(newIDs))
                : nil

            isApplyingProgrammaticUpdate = true
            NSAnimationContext.runAnimationGroup { ctx in
                ctx.duration = 0
                ctx.allowsImplicitAnimation = false

                self.entries = newEntries
                rebuildRowIndexMap()

                if hasStructuralOrHeightChanges {
                    tableView.beginUpdates()
                    if !removedIndexes.isEmpty {
                        tableView.removeRows(at: removedIndexes, withAnimation: [])
                    }
                    if !insertedIndexes.isEmpty {
                        tableView.insertRows(at: insertedIndexes, withAnimation: [])
                    }
                    if !heightChangedNewIndexes.isEmpty {
                        tableView.noteHeightOfRows(withIndexesChanged: heightChangedNewIndexes)
                    }
                    if !reloadNewIndexes.isEmpty {
                        tableView.reloadData(forRowIndexes: reloadNewIndexes, columnIndexes: IndexSet(integer: 0))
                    }
                    tableView.endUpdates()
                }

                for row in reconfigureNewIndexes {
                    reconfigureVisibleRow(at: row)
                }

                tableView.layoutSubtreeIfNeeded()

                if let prependAnchor, let targetRow = rowByID[prependAnchor.id] {
                    let newRowRect = tableView.rect(ofRow: targetRow)
                    scrollClipView(toY: newRowRect.minY - prependAnchor.screenMinY)
                } else if (wasAtBottom || isPinningToBottom),
                          !conversation.isAwayFromLatest,
                          restoreAnchor == nil {
                    scrollToBottom(animated: false)
                } else if let scrollAnchor, let targetRow = rowByID[scrollAnchor.id] {
                    let newRowRect = tableView.rect(ofRow: targetRow)
                    scrollClipView(toY: newRowRect.minY - scrollAnchor.screenMinY)
                }
            }
            isApplyingProgrammaticUpdate = false
            lastObservedClipOriginY = containerView.scrollView.contentView.bounds.origin.y
            evaluateScrollPosition()
            heightPassGeneration += 1
            scheduleHeightPrewarm(generation: heightPassGeneration)
        }

        private func applyTargetedRowUpdates(
            items: [TimelineItem],
            topControl: TimelineTopControlState,
            selectedID: String?,
            highlightedID: String?,
            lastOutgoingID: String?,
            pickingID: String?,
            view: TimelineTableView
        ) {
            let nonHeightVisualGlobalChanged = lastVisualEnvSignature != rowEnvironment.visualSignature

            var targetIDs = Set<String>()
            for id in [lastSelectedID, selectedID, lastHighlightedID, highlightedID,
                       lastLastOutgoingID, lastOutgoingID, lastPickingReactionID, pickingID].compactMap({ $0 }) {
                targetIDs.insert(id)
            }

            // If a global theme/cover/colorScheme setting changed, update currently visible rows cleanly.
            if nonHeightVisualGlobalChanged {
                let visibleRange = tableView.rows(in: tableView.visibleRect)
                if visibleRange.length > 0 {
                    for row in visibleRange.location ..< (visibleRange.location + visibleRange.length) {
                        if row < entries.count { targetIDs.insert(entries[row].id) }
                    }
                }
            }

            guard !targetIDs.isEmpty else { return }

            let timerCount = view.conversation.timerChoices.count
            let itemOffset = topControl == .none ? 0 : 1
            var heightChanged = IndexSet()
            var updatedRows: [Int] = []

            for id in targetIDs {
                guard let row = rowByID[id] else { continue }
                let itemIndex = row - itemOffset
                guard itemIndex >= 0, itemIndex < items.count else { continue }
                let item = items[itemIndex]
                let oldEntry = entries[row]
                let newEntry = TimelineRowEntry.item(
                    item,
                    isSelected: selectedID == id,
                    isHighlighted: highlightedID == id,
                    showsSent: lastOutgoingID == id,
                    actions: view.actions,
                    ui: view.ui,
                    messageActions: view.messageActions,
                    voiceNoteTranscripts: view.conversation.voiceNoteTranscripts,
                    timerChoicesCount: timerCount,
                    env: rowEnvironment,
                    isPickingReaction: pickingID == id
                )
                entries[row] = newEntry
                if oldEntry.contentRevision != newEntry.contentRevision {
                    heightChanged.insert(row)
                }
                if oldEntry.visualHash != newEntry.visualHash {
                    updatedRows.append(row)
                }
            }

            // Before the first load the table has no rows to update (asking it for one raises): the new entries are all
            // `performInitialLayoutIfReady` needs.
            guard hasPositionedInitially, tableView.numberOfRows == entries.count else { return }

            if !heightChanged.isEmpty {
                let wasAtBottom = isScrolledToBottom()
                let anchor = wasAtBottom ? nil : visibleAnchor(preferMessage: false)
                isApplyingProgrammaticUpdate = true
                NSAnimationContext.runAnimationGroup { ctx in
                    ctx.duration = 0
                    ctx.allowsImplicitAnimation = false
                    tableView.noteHeightOfRows(withIndexesChanged: heightChanged)
                    for row in updatedRows {
                        reconfigureVisibleRow(at: row)
                    }
                    tableView.layoutSubtreeIfNeeded()
                    restoreScrollAfterHeightChange(wasAtBottom: wasAtBottom, anchor: anchor)
                }
                isApplyingProgrammaticUpdate = false
                lastObservedClipOriginY = containerView.scrollView.contentView.bounds.origin.y
            } else {
                for row in updatedRows {
                    reconfigureVisibleRow(at: row)
                }
            }
        }

        private func reconfigureVisibleRow(at row: Int) {
            guard row >= 0, row < entries.count else { return }
            let entry = entries[row]
            if let rowView = tableView.rowView(atRow: row, makeIfNecessary: false) as? TimelineTableRowView {
                rowView.isRaisedRow = entry.isRaised
            }
            guard let existingView = tableView.view(atColumn: 0, row: row, makeIfNecessary: false) else { return }
            let width = existingView.frame.width > 1 ? existingView.frame.width : max(1, effectiveMeasureWidth)
            let height = tableView(tableView, heightOfRow: row)
            let targetSize = NSSize(width: width, height: max(1, height))
            if entry.kind == .topControl, let cell = existingView as? TimelineTopControlCell {
                cell.configure(with: makeTopControlView(for: entry.topControl ?? .none), size: targetSize)
            } else if let item = entry.item, let cell = existingView as? TimelineCell {
                cell.configure(with: makeHostedRow(for: entry, item: item), size: targetSize)
            }
        }

        private func rebuildRowIndexMap() {
            rowByID.removeAll(keepingCapacity: true)
            rowByID.reserveCapacity(entries.count)
            for (idx, entry) in entries.enumerated() {
                rowByID[entry.id] = idx
            }
        }

        private func computePrependAnchorIfNeeded(
            oldEntries: [TimelineRowEntry],
            newEntries: [TimelineRowEntry],
            oldItems: [TimelineItem],
            newItems: [TimelineItem],
            explicitAnchorID: String?
        ) -> (id: String, screenMinY: CGFloat)? {
            let oldFirstMsgID = firstMessageID(in: oldItems)
            guard let oldFirstMsgID,
                  let oldMsgIdx = oldEntries.firstIndex(where: { $0.id == oldFirstMsgID }),
                  let newMsgIdx = newEntries.firstIndex(where: { $0.id == oldFirstMsgID })
            else {
                return nil
            }
            // Check whether at least one older non-top-control item was prepended before the old first message.
            let oldContentBefore = oldEntries[..<oldMsgIdx].filter { $0.kind != .topControl }.count
            let newContentBefore = newEntries[..<newMsgIdx].filter { $0.kind != .topControl }.count
            guard newContentBefore > oldContentBefore || newItems.first?.id != oldItems.first?.id && newMsgIdx > oldMsgIdx else {
                return nil
            }

            if let explicitAnchorID, let row = rowByID[explicitAnchorID] {
                let rowRect = tableView.rect(ofRow: row)
                let screenMinY = rowRect.minY - containerView.scrollView.contentView.bounds.origin.y
                // Where it is, even above the top of the view (a late page arriving while scrolled down): clamping it
                // to the top inset would move the viewport.
                return (explicitAnchorID, screenMinY)
            }

            if let visible = visibleAnchor(preferMessage: false) {
                return visible
            }

            let rowRect = tableView.rect(ofRow: oldMsgIdx)
            let screenMinY = rowRect.minY - containerView.scrollView.contentView.bounds.origin.y
            return (oldFirstMsgID, screenMinY)
        }

        private func visibleAnchor(
            preferMessage: Bool,
            allowedIDs: Set<String>? = nil
        ) -> (id: String, screenMinY: CGFloat)? {
            let visibleRange = tableView.rows(in: tableView.visibleRect)
            guard visibleRange.length > 0 else { return nil }
            let clipOriginY = containerView.scrollView.contentView.bounds.origin.y
            let topInset = containerView.scrollView.contentInsets.top

            var fallback: (id: String, screenMinY: CGFloat)?
            for row in visibleRange.location ..< (visibleRange.location + visibleRange.length) {
                guard row >= 0, row < entries.count else { continue }
                let entry = entries[row]
                guard entry.kind != .topControl else { continue }
                if let allowedIDs, !allowedIDs.contains(entry.id) { continue }
                if preferMessage, case .message? = entry.item {} else if preferMessage { continue }
                let screenMinY = tableView.rect(ofRow: row).minY - clipOriginY
                if screenMinY >= topInset - 1 {
                    return (entry.id, screenMinY)
                }
                if fallback == nil {
                    fallback = (entry.id, screenMinY)
                }
            }
            return fallback
        }

        // MARK: - Scroll State, Insets & Requests

        @discardableResult
        private func updateScrollInsets(adjustScrollPosition: Bool) -> Bool {
            let scrollView = containerView.scrollView
            let topInset = parent.effectiveHeaderInset + ConversationView.timelineVerticalPadding
            let bottomInset = parent.bottomSafeAreaInset + ConversationView.timelineVerticalPadding
            let oldTop = scrollView.contentInsets.top
            let oldBottom = scrollView.contentInsets.bottom
            guard abs(topInset - oldTop) > 0.25 || abs(bottomInset - oldBottom) > 0.25 else {
                return false
            }

            let wasAtTop = abs(scrollView.contentView.bounds.origin.y + oldTop) <= 1.0
            let wasAtBottom = isScrolledToBottom()

            scrollView.contentInsets = NSEdgeInsets(top: topInset, left: 0, bottom: bottomInset, right: 0)
            scrollView.scrollerInsets = NSEdgeInsets(
                top: -ConversationView.timelineVerticalPadding,
                left: 0,
                bottom: parent.bottomSafeAreaInset > 0 ? 0 : -ConversationView.timelineVerticalPadding,
                right: 0
            )

            if adjustScrollPosition {
                isApplyingProgrammaticUpdate = true
                if wasAtBottom, !parent.conversation.isAwayFromLatest {
                    scrollToBottom(animated: false)
                } else if wasAtTop {
                    scrollClipView(toY: -topInset)
                }
                isApplyingProgrammaticUpdate = false
            }
            return true
        }

        private func handleRequests(view: TimelineTableView, insetsChanged: Bool) {
            let conversation = view.conversation

            if let request = conversation.scrollToMessageRequest,
               request.serial != lastHandledScrollSerial,
               hasPositionedInitially, measuredWidth > 1 {
                lastHandledScrollSerial = request.serial
                scrollToMessage(request)
            }

            if conversation.jumpToBottomRequest != lastJumpToBottomRequest {
                lastJumpToBottomRequest = conversation.jumpToBottomRequest
                if hasPositionedInitially {
                    scrollToBottom(animated: true)
                }
            }

            if view.bottomBarSignature != lastBottomBarSignature {
                lastBottomBarSignature = view.bottomBarSignature
                if hasPositionedInitially, isScrolledToBottom(), !conversation.isAwayFromLatest {
                    let scrollStamp = lastUserScroll
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) { [weak self] in
                        guard let self, !self.isShutDown,
                              self.lastUserScroll == scrollStamp,
                              self.lastAtBottom,
                              !self.parent.conversation.isAwayFromLatest else { return }
                        self.isApplyingProgrammaticUpdate = true
                        self.scrollToBottom(animated: false)
                        self.isApplyingProgrammaticUpdate = false
                        self.lastObservedClipOriginY = self.containerView.scrollView.contentView.bounds.origin.y
                    }
                }
            } else if insetsChanged, hasPositionedInitially, isScrolledToBottom(), !conversation.isAwayFromLatest {
                isApplyingProgrammaticUpdate = true
                scrollToBottom(animated: false)
                isApplyingProgrammaticUpdate = false
                lastObservedClipOriginY = containerView.scrollView.contentView.bounds.origin.y
            }

            if !conversation.isLoadingOlder, topInView, !conversation.olderFailed {
                requestOlder()
            }

            if !conversation.isLoadingNewer {
                readNewerIfAtBottom()
            }
        }

        private func handleBoundsDidChange() {
            let currentOriginY = containerView.scrollView.contentView.bounds.origin.y
            guard !isApplyingProgrammaticUpdate, hasPositionedInitially else {
                lastObservedClipOriginY = currentOriginY
                return
            }
            let movedUp = currentOriginY < lastObservedClipOriginY - 0.5
            let moved = abs(currentOriginY - lastObservedClipOriginY) > 0.5
            lastObservedClipOriginY = currentOriginY
            if moved { showFloatingDayIfScrolledByPerson() }
            if movedUp, !isScrolledToBottom() {
                lastUserScroll = Date()
                stopPinningToBottom()
            }
            evaluateScrollPosition()
            reportVisibleProbes()
        }

        /// The floating date: the day of the message at the top, while the person scrolls. Not for the app's own
        /// moves (a new message, the jump to the newest one, a search result).
        private func showFloatingDayIfScrolledByPerson() {
            guard FloatingDay.showsForScroll(
                isProgrammatic: isApplyingProgrammaticUpdate,
                secondsSinceUserScroll: Date().timeIntervalSince(lastPointerScroll)
            ) else { return }
            floatingDayForTopRow()
        }

        /// Shows the capsule for the row at the top of the visible part of the timeline (under the header). Called on
        /// every scroll event, so the day is looked up only when the row at the top is another one.
        private func floatingDayForTopRow() {
            let scrollView = containerView.scrollView
            let probeY = scrollView.contentView.bounds.origin.y + scrollView.contentInsets.top + 1
            let row = tableView.row(at: NSPoint(x: tableView.bounds.midX, y: probeY))
            let rowID: String? = row >= 0 && row < entries.count ? entries[row].id : nil
            if rowID == nil || rowID != floatingDayRowID || row != floatingDayRow {
                floatingDayRow = row
                floatingDayRowID = rowID
                floatingDayValue = row >= 0
                    ? FloatingDay.day(topRow: row, itemAt: { [entries] in $0 < entries.count ? entries[$0].item : nil })
                    : nil
            }
            containerView.floatingDay.userScrolled(day: floatingDayValue)
        }

        private func evaluateScrollPosition() {
            let conversation = parent.conversation
            let scrollView = containerView.scrollView
            let clipBounds = scrollView.contentView.bounds
            let atBottom = isScrolledToBottom()

            if atBottom != lastAtBottom {
                if atBottom {
                    leavingBottomTask?.cancel()
                    leavingBottomTask = nil
                    lastAtBottom = true
                    conversation.scrolled(toBottom: true)
                    readNewerIfAtBottom()
                } else {
                    lastAtBottom = false
                    leavingBottomTask?.cancel()
                    if Date().timeIntervalSince(lastUserScroll) <= TimelineTableMetrics.userScrollGraceSeconds {
                        leavingBottomTask = nil
                        conversation.scrolled(toBottom: false)
                    } else {
                        leavingBottomTask = Task { @MainActor [weak self] in
                            try? await Task.sleep(nanoseconds: TimelineTableMetrics.leavingBottomConfirmDelayNanoseconds)
                            guard let self, !Task.isCancelled else { return }
                            let conv = self.parent.conversation
                            if conv.isAtBottom, !conv.isAwayFromLatest,
                               !self.isScrolledToBottom(),
                               conv.scrollToMessageRequest == nil,
                               self.restoreAnchor == nil,
                               !self.topInView,
                               Date().timeIntervalSince(self.lastUserScroll) > TimelineTableMetrics.userScrollGraceSeconds {
                                self.isApplyingProgrammaticUpdate = true
                                self.scrollToBottom(animated: false)
                                self.isApplyingProgrammaticUpdate = false
                                self.lastObservedClipOriginY = self.containerView.scrollView.contentView.bounds.origin.y
                                self.lastAtBottom = true
                                return
                            }
                            conv.scrolled(toBottom: false)
                        }
                    }
                }
            } else if atBottom {
                readNewerIfAtBottom()
            }

            let topThreshold = -scrollView.contentInsets.top + max(
                clipBounds.height * TimelineTableMetrics.topTriggerScreenMultiplier,
                TimelineTableMetrics.minimumTopTriggerMargin
            )
            let nearTop = !entries.isEmpty && clipBounds.origin.y <= topThreshold

            if conversation.hasOlder {
                topInView = nearTop
                earlierTopInView = false
                if nearTop, !conversation.isLoadingOlder, !conversation.olderFailed {
                    requestOlder()
                }
            } else if conversation.canLoadEarlier {
                topInView = false
                earlierTopInView = nearTop
                if nearTop, !conversation.isLoadingEarlier,
                   Date().timeIntervalSince(lastScrollGesture) < 1.0 {
                    conversation.loadEarlier()
                }
            } else {
                topInView = false
                earlierTopInView = false
            }
        }

        private func isScrolledToBottom() -> Bool {
            let scrollView = containerView.scrollView
            let clipBounds = scrollView.contentView.bounds
            guard !entries.isEmpty else { return true }
            let contentBottomY = tableView.rect(ofRow: entries.count - 1).maxY
            return clipBounds.maxY - scrollView.contentInsets.bottom >= contentBottomY - 2
        }

        private func requestOlder() {
            let conversation = parent.conversation
            guard conversation.hasOlder, !conversation.isLoadingOlder else { return }
            stopPinningToBottom()
            restoreAnchor = visibleAnchor(preferMessage: true)?.id ?? firstMessageID(in: conversation.items)
            conversation.loadOlder()
        }

        private func readNewerIfAtBottom() {
            let conversation = parent.conversation
            guard lastAtBottom, conversation.isAwayFromLatest, !conversation.isLoadingNewer,
                  let request = conversation.scrollToMessageRequest,
                  scrolledToMessageSerial == request.serial
            else {
                return
            }
            conversation.loadNewer()
        }

        private func scrollToMessage(_ request: ConversationModel.MessageScrollRequest) {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) { [weak self] in
                guard let self, !self.isShutDown else { return }
                self.scrollToRow(id: request.messageID, preferCenter: true)
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { [weak self] in
                    guard let self, !self.isShutDown else { return }
                    self.scrolledToMessageSerial = request.serial
                    self.readNewerIfAtBottom()
                }
            }
        }

        private func scrollToRow(id: String, preferCenter: Bool) {
            guard let row = rowByID[id] else { return }
            isApplyingProgrammaticUpdate = true
            tableView.scrollRowToVisible(row)
            tableView.layoutSubtreeIfNeeded()
            let scrollView = containerView.scrollView
            let rowRect = tableView.rect(ofRow: row)
            let topClearance = scrollView.contentInsets.top
            let bottomClearance = scrollView.contentInsets.bottom
            let clipHeight = scrollView.contentView.bounds.height
            let usableHeight = max(1, clipHeight - topClearance - bottomClearance)

            let targetY: CGFloat
            if preferCenter, rowRect.height < usableHeight {
                let centeredScreenY = topClearance + (usableHeight - rowRect.height) * 0.5
                targetY = rowRect.minY - centeredScreenY
            } else {
                targetY = rowRect.minY - topClearance
            }
            scrollClipView(toY: targetY)
            isApplyingProgrammaticUpdate = false
            evaluateScrollPosition()
            reportVisibleProbes()
        }

        private func scrollToTop(animated: Bool) {
            let topY = -containerView.scrollView.contentInsets.top
            scrollClipView(toY: topY, animated: animated)
        }

        private func scrollToBottom(animated: Bool) {
            let scrollView = containerView.scrollView
            let clipHeight = scrollView.contentView.bounds.height
            let minOriginY = -scrollView.contentInsets.top
            let contentBottomY = entries.isEmpty ? 0 : tableView.rect(ofRow: entries.count - 1).maxY
            let maxOriginY = max(minOriginY, contentBottomY + scrollView.contentInsets.bottom - clipHeight)
            scrollClipView(toY: maxOriginY, animated: animated)
        }

        private func scrollClipView(toY rawY: CGFloat, animated: Bool = false) {
            let scrollView = containerView.scrollView
            let clipView = scrollView.contentView
            let minOriginY = -scrollView.contentInsets.top
            let contentBottomY = entries.isEmpty ? 0 : tableView.rect(ofRow: entries.count - 1).maxY
            let maxOriginY = max(minOriginY, contentBottomY + scrollView.contentInsets.bottom - clipView.bounds.height)
            let clampedY = min(maxOriginY, max(minOriginY, rawY))
            guard abs(clampedY - clipView.bounds.origin.y) > 0.5 else { return }
            let target = NSPoint(x: clipView.bounds.origin.x, y: clampedY)
            if animated {
                NSAnimationContext.runAnimationGroup { ctx in
                    ctx.duration = 0.2
                    ctx.timingFunction = CAMediaTimingFunction(name: .easeOut)
                    clipView.animator().setBoundsOrigin(target)
                }
                scrollView.reflectScrolledClipView(clipView)
            } else {
                clipView.scroll(to: target)
                scrollView.reflectScrolledClipView(clipView)
            }
        }

        // MARK: - Pinning on Open

        private var isPinningToBottom: Bool {
            guard let until = pinToBottomUntil else { return false }
            return Date() < until
        }

        private static func isScrollKeyEvent(_ event: NSEvent) -> Bool {
            switch event.keyCode {
            case 115, 116, 119, 121, 125, 126:
                return true
            default:
                break
            }
            guard let chars = event.charactersIgnoringModifiers else { return false }
            let scrollScalars: [Int] = [
                NSPageUpFunctionKey,
                NSPageDownFunctionKey,
                NSHomeFunctionKey,
                NSEndFunctionKey,
                NSUpArrowFunctionKey,
                NSDownArrowFunctionKey,
            ]
            return chars.unicodeScalars.contains { scalar in
                scrollScalars.contains(Int(scalar.value))
            }
        }

        private func startPinningToBottom() {
            stopPinningToBottom()
            let conversation = parent.conversation
            guard !conversation.isHeldAwayFromLatest, !conversation.isAwayFromLatest,
                  conversation.scrollToMessageRequest == nil else { return }
            pinToBottomUntil = Date().addingTimeInterval(ConversationView.pinToBottomDuration)
            pinScrollMonitor = NSEvent.addLocalMonitorForEvents(
                matching: [.scrollWheel, .keyDown, .leftMouseDown, .leftMouseDragged]
            ) { [weak self] event in
                MainActor.assumeIsolated {
                    guard let self else { return }
                    switch event.type {
                    case .scrollWheel:
                        if (!event.phase.isEmpty || event.momentumPhase.isEmpty), event.scrollingDeltaY != 0 {
                            self.lastUserScroll = Date()
                            self.stopPinningToBottom()
                        }
                    case .keyDown:
                        if Self.isScrollKeyEvent(event) {
                            self.lastUserScroll = Date()
                            self.stopPinningToBottom()
                        }
                    case .leftMouseDown, .leftMouseDragged:
                        if let scroller = self.containerView.scrollView.verticalScroller,
                           event.window === scroller.window {
                            let pt = scroller.convert(event.locationInWindow, from: nil)
                            if scroller.bounds.contains(pt) {
                                self.lastUserScroll = Date()
                                self.stopPinningToBottom()
                            }
                        }
                    default:
                        break
                    }
                }
                return event
            }
            let room = conversation.roomID
            for delay in [0.0, 0.05, 0.15, 0.3, 0.5, 0.75, 1.0, 1.25, ConversationView.pinToBottomDuration] {
                DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
                    guard let self, self.pinToBottomUntil != nil,
                          self.parent.conversation.roomID == room,
                          !self.parent.conversation.isAwayFromLatest,
                          self.parent.conversation.scrollToMessageRequest == nil,
                          self.restoreAnchor == nil
                    else { return }
                    self.isApplyingProgrammaticUpdate = true
                    self.scrollToBottom(animated: false)
                    self.isApplyingProgrammaticUpdate = false
                    self.lastObservedClipOriginY = self.containerView.scrollView.contentView.bounds.origin.y
                    if delay >= ConversationView.pinToBottomDuration {
                        self.stopPinningToBottom()
                    }
                }
            }
        }

        private func stopPinningToBottom() {
            pinToBottomUntil = nil
            if let monitor = pinScrollMonitor {
                NSEvent.removeMonitor(monitor)
                pinScrollMonitor = nil
            }
        }

        // MARK: - External Height Invalidations

        private func handleLearnedImageSize(forPath path: String?) {
            guard let path, !path.isEmpty, hasPositionedInitially, !isShutDown else { return }
            var affected = IndexSet()
            let items = parent.conversation.items
            let offset = entries.first?.kind == .topControl ? 1 : 0

            for (idx, item) in items.enumerated() {
                guard case let .message(msg) = item else { continue }
                let matches = msg.mediaPath == path
                    || msg.linkPreviews.contains(where: {
                        $0.imagePath == path
                            || ($0.imagePath == nil && parent.actions.showLinkPreviews
                                && $0.pageURL.flatMap { parent.conversation.linkPreviewImages.cached(for: $0)?.path } == path)
                    })
                    || msg.thumbnailPath == path
                    || msg.galleryItems.contains(where: { $0.mediaPath == path || $0.thumbnailPath == path })
                guard matches else { continue }
                let row = idx + offset
                guard row < entries.count else { continue }
                heightCache.invalidateItem(id: msg.id)
                entries[row] = TimelineRowEntry.item(
                    item,
                    isSelected: entries[row].isSelected,
                    isHighlighted: entries[row].isHighlighted,
                    showsSent: entries[row].showsSent,
                    actions: parent.actions,
                    ui: parent.ui,
                    messageActions: parent.messageActions,
                    voiceNoteTranscripts: parent.conversation.voiceNoteTranscripts,
                    timerChoicesCount: parent.conversation.timerChoices.count,
                    env: rowEnvironment,
                    isPickingReaction: reactionPickerMessageID(parent.messageActions.request) == msg.id
                )
                affected.insert(row)
            }
            guard !affected.isEmpty else { return }
            let wasAtBottom = isScrolledToBottom()
            let anchor = wasAtBottom ? nil : visibleAnchor(preferMessage: false)
            isApplyingProgrammaticUpdate = true
            NSAnimationContext.runAnimationGroup { ctx in
                ctx.duration = 0
                ctx.allowsImplicitAnimation = false
                tableView.noteHeightOfRows(withIndexesChanged: affected)
                for row in affected {
                    reconfigureVisibleRow(at: row)
                }
                tableView.layoutSubtreeIfNeeded()
                restoreScrollAfterHeightChange(wasAtBottom: wasAtBottom, anchor: anchor)
            }
            isApplyingProgrammaticUpdate = false
            lastObservedClipOriginY = containerView.scrollView.contentView.bounds.origin.y
        }

        private func handleVoiceNoteTranscriptChange() {
            guard hasPositionedInitially, !isShutDown else { return }
            var affected = IndexSet()
            let items = parent.conversation.items
            let offset = entries.first?.kind == .topControl ? 1 : 0
            for (idx, item) in items.enumerated() {
                guard case let .message(msg) = item, msg.kind == .voiceNote else { continue }
                let row = idx + offset
                guard row < entries.count else { continue }
                let oldEntry = entries[row]
                let newEntry = TimelineRowEntry.item(
                    item,
                    isSelected: oldEntry.isSelected,
                    isHighlighted: oldEntry.isHighlighted,
                    showsSent: oldEntry.showsSent,
                    actions: parent.actions,
                    ui: parent.ui,
                    messageActions: parent.messageActions,
                    voiceNoteTranscripts: parent.conversation.voiceNoteTranscripts,
                    timerChoicesCount: parent.conversation.timerChoices.count,
                    env: rowEnvironment,
                    isPickingReaction: reactionPickerMessageID(parent.messageActions.request) == msg.id
                )
                if newEntry.contentRevision != oldEntry.contentRevision {
                    heightCache.invalidateItem(id: msg.id)
                    entries[row] = newEntry
                    affected.insert(row)
                }
            }
            guard !affected.isEmpty else { return }
            let wasAtBottom = isScrolledToBottom()
            let anchor = wasAtBottom ? nil : visibleAnchor(preferMessage: false)
            isApplyingProgrammaticUpdate = true
            NSAnimationContext.runAnimationGroup { ctx in
                ctx.duration = 0
                ctx.allowsImplicitAnimation = false
                tableView.noteHeightOfRows(withIndexesChanged: affected)
                for row in affected {
                    reconfigureVisibleRow(at: row)
                }
                tableView.layoutSubtreeIfNeeded()
                restoreScrollAfterHeightChange(wasAtBottom: wasAtBottom, anchor: anchor)
            }
            isApplyingProgrammaticUpdate = false
            lastObservedClipOriginY = containerView.scrollView.contentView.bounds.origin.y
        }

        // MARK: - Sender Hover Card Popover

        private func syncSenderCardPopover(view: TimelineTableView, environment: EnvironmentValues) {
            let conversation = view.conversation
            guard let card = conversation.activeSenderCard,
                  let row = rowByID[card.messageID],
                  tableView.window != nil
            else {
                dismissSenderPopover()
                return
            }

            let content = SenderHoverPopoverContent(
                card: card,
                sharedGroups: conversation.senderCardSharedGroups,
                contactsBridge: conversation.contactsBridge,
                now: conversation.currentTime,
                showsMessageButton: !(conversation.isDirectChat ?? false),
                appearance: rowEnvironment.appearance,
                themeRoomID: rowEnvironment.themeRoomID,
                themeAccentHex: rowEnvironment.themeAccentHex,
                messagePointSize: environment.courierMessagePointSize,
                zoomMultiplier: environment.courierZoomMultiplier,
                colorScheme: environment.colorScheme,
                onMessage: { [weak conversation] in
                    let userID = card.userID
                    conversation?.dismissSenderCard()
                    Task { _ = await conversation?.messageParticipant(userID: userID) }
                },
                onSelectRoom: { [weak conversation, weak appModel = view.appModel] targetRoomID in
                    conversation?.dismissSenderCard()
                    appModel?.open(.chat(roomID: targetRoomID))
                },
                onHover: { [weak conversation] hovering in
                    conversation?.setCardHovered(hovering)
                }
            )

            if let controller = senderPopoverController {
                controller.rootView = content
            } else {
                let controller = NSHostingController(rootView: content)
                senderPopoverController = controller
                senderPopover.contentViewController = controller
            }

            if senderPopover.isShown, presentedSenderCardMessageID == card.messageID {
                return
            }
            if senderPopover.isShown {
                suppressPopoverCloseCallback = true
                senderPopover.performClose(nil)
                suppressPopoverCloseCallback = false
            }
            presentedSenderCardMessageID = card.messageID
            let rowRect = tableView.rect(ofRow: row)
            senderPopover.show(relativeTo: rowRect, of: tableView, preferredEdge: .minX)
        }

        private func dismissSenderPopover() {
            guard senderPopover.isShown || presentedSenderCardMessageID != nil else { return }
            suppressPopoverCloseCallback = true
            senderPopover.performClose(nil)
            suppressPopoverCloseCallback = false
            presentedSenderCardMessageID = nil
        }

        func popoverDidClose(_: Notification) {
            guard !suppressPopoverCloseCallback else { return }
            presentedSenderCardMessageID = nil
            if parent.conversation.activeSenderCard != nil {
                parent.conversation.dismissSenderCard()
            }
        }

        // MARK: - Probes & Signature Helpers

        private var storedProbe: ((String, CGRect) -> Void)?

        func updateProbe(_ probe: ((String, CGRect) -> Void)?) {
            storedProbe = probe
        }

        private func reportVisibleProbes() {
            reportVisibleProbes(using: storedProbe)
        }

        /// What each row's probe last reported. A probe that stores what it is told in observable state makes SwiftUI
        /// call `updateNSView` again, which reports again: only a rect that changed is passed on, so that ends.
        private var lastReportedProbeRects: [String: CGRect] = [:]
        private var hadProbe = false

        private func reportVisibleProbes(using probe: ((String, CGRect) -> Void)?) {
            storedProbe = probe
            // A probe that comes or goes starts over: the new one has heard nothing yet.
            if (probe != nil) != hadProbe {
                lastReportedProbeRects.removeAll()
                hadProbe = probe != nil
            }
            guard let probe, hasPositionedInitially, measuredWidth > 1 else { return }
            let visibleRange = tableView.rows(in: tableView.visibleRect)
            guard visibleRange.length > 0 else { return }
            var visibleNames = Set<String>()
            for row in visibleRange.location ..< (visibleRange.location + visibleRange.length) {
                guard row >= 0, row < entries.count, let item = entries[row].item else { continue }
                let rowRect = tableView.rect(ofRow: row)
                let rectInContainer = containerView.convert(rowRect, from: tableView)
                let name = "item/\(item.id)"
                visibleNames.insert(name)
                if lastReportedProbeRects[name] == rectInContainer { continue }
                lastReportedProbeRects[name] = rectInContainer
                probe(name, rectInContainer)
            }
            // Rows scrolled out are forgotten, so one that returns to the same place is reported again.
            lastReportedProbeRects = lastReportedProbeRects.filter { visibleNames.contains($0.key) }
        }

        private func currentTopControl(conversation: ConversationModel) -> TimelineTopControlState {
            if conversation.hasOlder {
                return conversation.olderFailed ? .olderRetry : .olderSpinner
            }
            if conversation.canLoadEarlier {
                return conversation.isLoadingEarlier ? .earlierLoading : .earlierSentinel
            }
            return .none
        }

        private func firstMessageID(in items: [TimelineItem]) -> String? {
            for item in items.prefix(3) {
                if case let .message(message) = item { return message.id }
            }
            return nil
        }

        private func reactionPickerMessageID(_ request: MessageActionRequest?) -> String? {
            if case let .reactionPicker(id)? = request { return id }
            return nil
        }

        private func computeActionsHeightSignature(view: TimelineTableView, items: [TimelineItem]) -> Int {
            var hasher = Hasher()
            hasher.combine(view.preferences.showMessageTimestamps)
            hasher.combine(view.preferences.timeFormat.rawValue)
            hasher.combine(view.preferences.loadExternalEmbedsAutomatically)
            hasher.combine(view.preferences.showLinkPreviews)
            hasher.combine(view.conversation.isDirectChat)
            hasher.combine(view.conversation.timerChoices.count)
            if let merged = view.conversation.mergedChat {
                hasher.combine(merged.roomIDs)
                hasher.combine(merged.networks)
            }
            if items.contains(where: { if case let .message(m) = $0 { m.expiresAt != nil } else { false } }) {
                hasher.combine(view.conversation.countdownClock.timeIntervalSinceReferenceDate)
            }
            return hasher.finalize()
        }

        private func computeUISignature(_ ui: MessageUI) -> Int {
            var hasher = Hasher()
            hasher.combine(ui.historyOpen.count)
            for id in ui.historyOpen.sorted() {
                hasher.combine(id)
                hasher.combine(ui.versions[id]?.count ?? -1)
            }
            hasher.combine(ui.loadedEmbeds.count)
            for id in ui.loadedEmbeds.sorted() { hasher.combine(id) }
            hasher.combine(ui.revealed.count)
            for id in ui.revealed.sorted() { hasher.combine(id) }
            return hasher.finalize()
        }

        private func computeTranslationsSignature(_ model: MessageActionsModel) -> Int {
            var hasher = Hasher()
            hasher.combine(model.translatingEventIDs.count)
            for id in model.translatingEventIDs.sorted() { hasher.combine(id) }
            hasher.combine(model.translations.count)
            for id in model.translations.keys.sorted() {
                hasher.combine(id)
                if case let .text(t)? = model.translations[id] {
                    hasher.combine(t)
                } else if case let .unavailable(r)? = model.translations[id] {
                    hasher.combine(r)
                }
            }
            return hasher.finalize()
        }

        private func computeTranscriptsSignature(_ store: VoiceNoteTranscriptStore) -> Int {
            var hasher = Hasher()
            hasher.combine(store.entries.count)
            for id in store.entries.keys.sorted() {
                hasher.combine(id)
                switch store.entries[id] {
                case .transcribing?:
                    hasher.combine(1)
                case let .transcribed(text, _, isCollapsed)?:
                    hasher.combine(2)
                    hasher.combine(isCollapsed)
                    if !isCollapsed { hasher.combine(text) }
                case let .failed(msg)?:
                    hasher.combine(3)
                    hasher.combine(msg)
                case nil:
                    hasher.combine(0)
                }
            }
            return hasher.finalize()
        }
    }
}
