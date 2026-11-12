// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import AppKit
import SwiftUI
import VitruvianCore
import VitruvianDesign
import VitruvianServices

package struct NotchNotificationsView: View {
    package let size: CGSize
    @ObservedObject private var service = NotchNotificationService.shared
    @ObservedObject private var permissions = Permissions.shared
    @ObservedObject private var l10n = L10n.shared
    @AppStorage(Preferences.notchNotificationsLayout) private var layout: String
    @AppStorage(Preferences.notchNotificationsGrouped) private var grouped: Bool
    private var text: NotchNotificationStrings { FeatureStrings.notchNotifications(l10n.language) }

    package var body: some View {
        Group {
            if !permissions.accessibility {
                VStack(alignment: .leading, spacing: 10) {
                    PermissionRow(kind: .accessibility)
                    Text(text.privacy).font(.callout).foregroundStyle(.white.opacity(0.7))
                        .fixedSize(horizontal: false, vertical: true)
                }
            } else if service.items.isEmpty {
                HStack(spacing: 14) {
                    Image(systemName: "bell").font(.system(size: 26, weight: .light)).foregroundStyle(.white.opacity(0.6))
                        .frame(width: 56, height: 56)
                        .background(.white.opacity(0.05), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                    VStack(alignment: .leading, spacing: 4) {
                        Text(service.monitoring ? text.empty : text.waiting).font(.headline)
                        Text(text.privacy).font(.caption).foregroundStyle(.white.opacity(0.65))
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                NotchNotificationPage(items: service.items, size: size, layout: NotchNotificationLayout(saved: layout),
                                      grouped: grouped, service: service, text: text)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .environment(\.locale, l10n.language.formattingLocale())
    }
}

/// The messages themselves, as cards or as a list. It takes the messages it
/// shows, so a test can draw the page with messages of its own.
package struct NotchNotificationPage: View {
    package let items: [NotchSystemNotification]
    package let size: CGSize
    package let layout: NotchNotificationLayout
    /// Only the list groups; the cards ignore it.
    package let grouped: Bool
    /// The stacks open when the page first draws. The page then keeps its own.
    package let expanded: Set<String>
    @ObservedObject package var service: NotchNotificationService
    package let text: NotchNotificationStrings

    // Spelled out because a memberwise initializer never leaves its module.
    package init(items: [NotchSystemNotification], size: CGSize, layout: NotchNotificationLayout, grouped: Bool,
                 expanded: Set<String> = [], service: NotchNotificationService, text: NotchNotificationStrings) {
        self.items = items
        self.size = size
        self.layout = layout
        self.grouped = grouped
        self.expanded = expanded
        self.service = service
        self.text = text
    }

    package var body: some View {
        switch layout {
        case .cards:
            let rows = NotchLayout.railRows(count: items.count,
                                            perRow: NotchLayout.railCapacity(width: size.width, itemWidth: 240, spacing: 8),
                                            rowHeight: 120, spacing: 8, height: size.height)
            let cardHeight = (size.height - CGFloat(rows - 1) * 8) / CGFloat(rows)
            NotchRail(items: items, rows: rows, itemWidth: 240, width: size.width) { item in
                NotchNotificationRow(item: item, service: service, text: text)
                    .frame(height: cardHeight)
            }
        case .list:
            NotchNotificationList(items: items, grouped: grouped, expanded: expanded, service: service, text: text)
        }
    }
}

/// How the list moves when a stack opens or closes, or a row goes: quick and
/// smooth, and not at all with Reduce Motion on.
package enum NotchNotificationListMotion {
    /// How long a stack takes to open or close.
    package static let duration: Double = 0.22
    /// How long a closed stack's one-line summary takes to go as it opens:
    /// well inside `duration`, so its first message never slides in over the
    /// summary while it is still fading (it did in 3.53.0).
    package static let summaryFade: Double = 0.06

    package static func animation(reduceMotion: Bool) -> Animation? {
        reduceMotion ? nil : .smooth(duration: duration)
    }

    /// The summary and time a closed stack shows, leaving and coming back.
    package static func summaryTransition(reduceMotion: Bool) -> AnyTransition {
        reduceMotion ? .identity : .opacity.animation(.easeOut(duration: summaryFade))
    }

    /// A message in a stack fades in just under the stack's row. With Reduce
    /// Motion it only fades.
    package static func transition(reduceMotion: Bool) -> AnyTransition {
        reduceMotion ? .opacity : .opacity.combined(with: .offset(y: -6))
    }
}

/// One compact row per message, newest first, scrolling down when there are
/// more than fit. Grouped, an app with several messages is one row that
/// opens in place.
private struct NotchNotificationList: View {
    let items: [NotchSystemNotification]
    let grouped: Bool
    @ObservedObject var service: NotchNotificationService
    let text: NotchNotificationStrings
    @State private var expanded: Set<String>
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    init(items: [NotchSystemNotification], grouped: Bool, expanded: Set<String>,
         service: NotchNotificationService, text: NotchNotificationStrings) {
        self.items = items
        self.grouped = grouped
        self.service = service
        self.text = text
        _expanded = State(initialValue: expanded)
    }

    var body: some View {
        ScrollView(.vertical) {
            VStack(spacing: NotchNotificationListLayout.rowSpacing) {
                ForEach(NotchNotificationListSupport.entries(items, grouped: grouped, expanded: expanded)) { entry in
                    row(entry).transition(NotchNotificationListMotion.transition(reduceMotion: reduceMotion))
                }
            }
            .padding(.bottom, NotchLayout.scrollBottomPadding)
        }
        .scrollIndicators(.never)
        .notchScrollEdgeFade()
        .onChange(of: items) { _, items in
            expanded = NotchNotificationListSupport.expansion(expanded, keptFor: items)
        }
    }

    @ViewBuilder private func row(_ entry: NotchNotificationListEntry) -> some View {
        switch entry {
        case .single(let item):
            NotchNotificationListRow(item: item, member: false, service: service, text: text, motion: motion)
        case .member(let item, _):
            NotchNotificationListRow(item: item, member: true, service: service, text: text, motion: motion)
                .padding(.leading, NotchNotificationListLayout.memberIndent)
        case .group(let group, let open):
            NotchNotificationGroupRow(group: group, expanded: open, service: service, text: text, motion: motion) {
                withAnimation(motion) { expanded = NotchNotificationListSupport.toggling(group.id, in: expanded) }
            }
        }
    }

    private var motion: Animation? { NotchNotificationListMotion.animation(reduceMotion: reduceMotion) }
}

/// A message as one row: its app and time on top, its title and the start
/// of its message below. Inside an open stack the app is already named, so
/// the row leads with the title instead.
private struct NotchNotificationListRow: View {
    let item: NotchSystemNotification
    let member: Bool
    @ObservedObject var service: NotchNotificationService
    let text: NotchNotificationStrings
    let motion: Animation?
    @State private var feedback: String?

    var body: some View {
        HStack(spacing: 10) {
            if !member {
                NotchNotificationAppIcon(app: item.content.app, size: NotchNotificationListLayout.iconSize)
            }
            VStack(alignment: .leading, spacing: 1) {
                if member {
                    HStack(spacing: 6) {
                        Text(item.content.compactTitle).font(.system(size: 12, weight: .semibold)).lineLimit(1)
                        Spacer(minLength: 4)
                        NotchNotificationTime(date: item.received)
                    }
                    NotchNotificationLine(text: item.content.compactDetail, unavailable: message)
                } else {
                    HStack(spacing: 6) {
                        NotchNotificationAppName(app: item.content.app, text: text)
                        Spacer(minLength: 4)
                        NotchNotificationTime(date: item.received)
                    }
                    NotchNotificationLine(title: item.content.compactTitle, text: item.content.compactDetail,
                                          unavailable: message)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            NotchNotificationRowActions(item: item, service: service, text: text, motion: motion, feedback: $feedback)
        }
        .padding(.leading, NotchNotificationListLayout.horizontalPadding)
        .padding(.trailing, 4)
        .frame(height: NotchNotificationListLayout.rowHeight)
        .background(.white.opacity(0.06),
                    in: RoundedRectangle(cornerRadius: NotchNotificationListLayout.cornerRadius, style: .continuous))
        .accessibilityElement(children: .contain)
        .accessibilityLabel(item.content.accessibilityText)
    }

    /// Opening that could not reach the message says so in place of its text.
    private var message: String? { feedback ?? (service.unavailableID == item.id ? text.unavailable : nil) }
}

/// An app's stack: its newest message with a count while closed, and only
/// its name, count and actions while open, its messages listed below.
private struct NotchNotificationGroupRow: View {
    let group: NotchNotificationGroup
    let expanded: Bool
    @ObservedObject var service: NotchNotificationService
    let text: NotchNotificationStrings
    let motion: Animation?
    let toggle: () -> Void
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        HStack(spacing: 4) {
            Button(action: toggle) {
                HStack(spacing: 10) {
                    NotchNotificationAppIcon(app: group.app, size: expanded ? NotchNotificationListLayout.openGroupIconSize
                                                                            : NotchNotificationListLayout.iconSize)
                    VStack(alignment: .leading, spacing: 1) {
                        HStack(spacing: 6) {
                            NotchNotificationAppName(app: group.app, text: text)
                            NotchNotificationCount(count: group.count)
                            Spacer(minLength: 4)
                            if !expanded {
                                NotchNotificationTime(date: group.newest.received)
                                    .transition(NotchNotificationListMotion.summaryTransition(reduceMotion: reduceMotion))
                            }
                        }
                        if !expanded {
                            NotchNotificationLine(title: group.newest.content.compactTitle,
                                                  text: group.newest.content.compactDetail, unavailable: nil)
                                .transition(NotchNotificationListMotion.summaryTransition(reduceMotion: reduceMotion))
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    Image(systemName: "chevron.right")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.45))
                        .rotationEffect(.degrees(expanded ? 90 : 0))
                        .frame(width: 14)
                        .accessibilityHidden(true)
                }
                .padding(.leading, NotchNotificationListLayout.horizontalPadding)
                .frame(maxHeight: .infinity)
                .contentShape(Rectangle())
            }
            .buttonStyle(NotchButtonStyle(cornerRadius: NotchNotificationListLayout.cornerRadius, lifts: false))
            .help(expanded ? text.showLess : text.showAll)
            .accessibilityLabel(NotchNotificationListSupport.accessibilityLabel(for: group, text: text))
            .accessibilityHint(expanded ? text.showLess : text.showAll)
            NotchIconButton(symbol: "xmark", title: String(format: text.dismissAppFormat, group.app)) {
                withAnimation(motion) { service.dismiss(group.ids) }
            }
            .disabled(service.openingID.map { group.ids.contains($0) } ?? false)
        }
        .padding(.trailing, 4)
        .frame(height: expanded ? NotchNotificationListLayout.openGroupHeight : NotchNotificationListLayout.rowHeight)
        .background(.white.opacity(expanded ? 0.03 : 0.06),
                    in: RoundedRectangle(cornerRadius: NotchNotificationListLayout.cornerRadius, style: .continuous))
        // The row shrinks as it opens; nothing it held may spill over the
        // messages sliding in under it.
        .clipShape(RoundedRectangle(cornerRadius: NotchNotificationListLayout.cornerRadius, style: .continuous))
        .accessibilityElement(children: .contain)
    }
}

/// Open and dismiss, as on a card.
private struct NotchNotificationRowActions: View {
    let item: NotchSystemNotification
    @ObservedObject var service: NotchNotificationService
    let text: NotchNotificationStrings
    let motion: Animation?
    @Binding var feedback: String?

    var body: some View {
        HStack(spacing: 0) {
            if service.openingID == item.id {
                ProgressView().controlSize(.mini).frame(width: NotchLayout.iconButtonSide)
            } else if service.canOpen(item) {
                NotchIconButton(symbol: "arrow.up.forward.app", title: text.open) {
                    feedback = nil
                    service.open(item.id) { result in
                        if result == .unavailable || result == .uncertain { feedback = text.unavailable }
                    }
                }
                .disabled(service.openingID != nil)
            }
            NotchIconButton(symbol: "xmark", title: text.dismiss) { withAnimation(motion) { service.dismiss(item.id) } }
                .disabled(service.openingID == item.id)
        }
    }
}

private struct NotchNotificationAppName: View {
    let app: String
    let text: NotchNotificationStrings

    var body: some View {
        Text(app.isEmpty ? text.title : app)
            .font(.system(size: 11, weight: .medium))
            .foregroundStyle(.white.opacity(0.6))
            .lineLimit(1)
    }
}

private struct NotchNotificationTime: View {
    let date: Date

    var body: some View {
        Text(date, format: .dateTime.hour().minute())
            .font(.system(size: 11)).monospacedDigit()
            .foregroundStyle(.white.opacity(0.45))
            .fixedSize()
    }
}

/// How many messages a stack holds, in the quiet pill the island uses.
private struct NotchNotificationCount: View {
    let count: Int

    var body: some View {
        Text(count, format: .number)
            .font(.system(size: 10, weight: .semibold)).monospacedDigit()
            .foregroundStyle(.white.opacity(0.75))
            .padding(.horizontal, 5)
            .frame(minWidth: 16, minHeight: 14)
            .background(.white.opacity(0.12), in: Capsule())
            .fixedSize()
            .accessibilityHidden(true)
    }
}

/// The one line of message a row has room for: the title in bold where the
/// row shows one, then the message, cut at the end.
private struct NotchNotificationLine: View {
    var title: String = ""
    let text: String
    let unavailable: String?

    var body: some View {
        Group {
            if let unavailable {
                Text(unavailable).foregroundStyle(.orange)
            } else if title.isEmpty {
                Text(text).foregroundStyle(.white.opacity(0.7))
            } else if text.isEmpty {
                Text(title).fontWeight(.semibold).foregroundStyle(.white)
            } else {
                Text(title).fontWeight(.semibold).foregroundStyle(.white)
                    + Text("  ") + Text(text).foregroundStyle(.white.opacity(0.7))
            }
        }
        .font(.system(size: 12))
        .lineLimit(1)
        .truncationMode(.tail)
    }
}

/// The page shows only the cards, so clearing sits in the island's header
/// like the captures page's. Observes the inbox on its own, so a new message
/// does not redraw the island.
struct NotchClearNotificationsButton: View {
    @ObservedObject private var notifications = NotchNotificationService.shared
    @ObservedObject private var l10n = L10n.shared

    var body: some View {
        NotchIconButton(symbol: "trash", title: FeatureStrings.notchNotifications(l10n.language).clearAll,
                        action: Self.confirmClearAboveIsland)
            .disabled(notifications.items.isEmpty || notifications.openingID != nil)
    }

    /// With the system banner dismissed, a banner shown while the island was
    /// closed may never reach Notification Center before macOS 27, so the
    /// island can hold the only copy. Clearing asks first, above the island.
    static func confirmClearAboveIsland() {
        DispatchQueue.main.async {
            let l10n = L10n.shared
            let title = FeatureStrings.notchNotifications(l10n.language).clearAll
            guard NSAlert.confirmAboveIsland(title, message: "", action: title, destructive: true,
                                             cancel: l10n.s.uninstallerCancel) else { return }
            NotchNotificationService.shared.clearAll()
        }
    }
}

/// One card per message: its app and actions on top, the text below taking
/// whatever room the card has.
private struct NotchNotificationRow: View {
    let item: NotchSystemNotification
    @ObservedObject var service: NotchNotificationService
    let text: NotchNotificationStrings
    @State private var feedback: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                NotchNotificationAppIcon(app: item.content.app, size: 18)
                Text(item.content.app.isEmpty ? text.title : item.content.app)
                    .lineLimit(1)
                Spacer(minLength: 4)
                Text(item.received, format: .dateTime.hour().minute()).monospacedDigit()
                if service.openingID == item.id {
                    ProgressView().controlSize(.mini)
                } else if service.canOpen(item) {
                    NotchIconButton(symbol: "arrow.up.forward.app", title: text.open) {
                        feedback = nil
                        service.open(item.id) { result in
                            if result == .unavailable || result == .uncertain { feedback = text.unavailable }
                        }
                    }
                    .disabled(service.openingID != nil)
                }
                NotchIconButton(symbol: "xmark", title: text.dismiss) { service.dismiss(item.id) }
                    .disabled(service.openingID == item.id)
            }
            .font(.system(size: 11)).foregroundStyle(.white.opacity(0.6))
            .frame(height: 22)
            Text(item.content.title).font(.system(size: 13, weight: .semibold)).lineLimit(2)
            if !item.content.subtitle.isEmpty { Text(item.content.subtitle).font(.system(size: 12)).lineLimit(1) }
            if !item.content.body.isEmpty {
                Text(item.content.body).font(.system(size: 12)).foregroundStyle(.white.opacity(0.8))
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            }
            if let message = feedback ?? (service.unavailableID == item.id ? text.unavailable : nil) {
                Text(message).font(.caption).foregroundStyle(.orange).lineLimit(1)
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 14))
        .clipped()
        .accessibilityElement(children: .contain)
    }
}

/// A banner held open under the pointer: the whole message with its actions,
/// laid out with the fonts and limits the service measured it with.
package struct NotchNotificationPreviewView: View {
    package let notice: NotchNotice
    package let content: NotchNotificationContent
    @ObservedObject package var service: NotchService
    @ObservedObject private var notifications = NotchNotificationService.shared
    @ObservedObject private var l10n = L10n.shared
    private var text: NotchNotificationStrings { FeatureStrings.notchNotifications(l10n.language) }
    private var item: NotchSystemNotification? {
        notifications.items.first { $0.id == notice.notificationID }
    }

    package var body: some View {
        VStack(alignment: .leading, spacing: NotchNotificationPreviewLayout.spacing) {
            HStack(spacing: 8) {
                NotchNotificationAppIcon(app: content.app, size: NotchNotificationPreviewLayout.iconSize)
                Text(content.app.isEmpty ? text.title : content.app)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.7))
                    .lineLimit(1)
                Spacer(minLength: 8)
                if let item {
                    Text(item.received, format: .dateTime.hour().minute())
                        .font(.system(size: 11)).monospacedDigit()
                        .foregroundStyle(.white.opacity(0.45))
                }
                NotchIconButton(symbol: "xmark", title: text.dismiss) { service.dismissNotification(notice) }
            }
            .frame(height: NotchNotificationPreviewLayout.headerHeight)
            if !content.title.isEmpty {
                Text(content.title)
                    .font(Font(NotchNotificationPreviewLayout.titleFont as CTFont))
                    .lineLimit(NotchNotificationPreviewLayout.titleLines)
            }
            if !content.subtitle.isEmpty {
                Text(content.subtitle)
                    .font(Font(NotchNotificationPreviewLayout.subtitleFont as CTFont))
                    .foregroundStyle(.white.opacity(0.9))
                    .lineLimit(NotchNotificationPreviewLayout.subtitleLines)
            }
            if !content.body.isEmpty {
                Text(content.body)
                    .font(Font(NotchNotificationPreviewLayout.bodyFont as CTFont))
                    .foregroundStyle(.white.opacity(0.82))
                    .lineLimit(NotchNotificationPreviewLayout.bodyLines)
                    .textSelection(.enabled)
            }
            HStack(spacing: 8) {
                if let item, notifications.canOpen(item) {
                    Button(text.open) { service.activateNotice(notice) }
                        .buttonStyle(.bordered).controlSize(.small)
                        .disabled(notifications.openingID != nil)
                }
                if notifications.openingID == notice.notificationID { ProgressView().controlSize(.small) }
                Spacer(minLength: 8)
                if notifications.items.count > 1 {
                    Button { service.open(.notifications) } label: {
                        HStack(spacing: 5) {
                            Image(systemName: "tray.full").font(.system(size: 11, weight: .medium))
                            Text(notifications.items.count, format: .number)
                                .font(.system(size: 11, weight: .semibold)).monospacedDigit()
                        }
                        .foregroundStyle(.white.opacity(0.8))
                        .padding(.horizontal, 10)
                        .frame(height: 24)
                        .contentShape(Capsule())
                    }
                    .buttonStyle(NotchButtonStyle(cornerRadius: 12))
                    .modifier(NotchControlSurface(cornerRadius: 12))
                    .help(text.title)
                    .accessibilityLabel(text.title)
                    .accessibilityValue(Text(notifications.items.count, format: .number))
                }
            }
            .frame(height: NotchNotificationPreviewLayout.actionHeight)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .fixedSize(horizontal: false, vertical: true)
        .frame(maxHeight: .infinity, alignment: .top)
        .clipped()
        .accessibilityElement(children: .contain)
        .accessibilityLabel(notice.accessibilityText)
        .environment(\.locale, l10n.language.formattingLocale())
    }
}

/// App icons a page is drawn with in place of the ones the service found,
/// for a test that draws the page with messages of its own.
private struct NotchNotificationIconsKey: EnvironmentKey {
    static let defaultValue: [String: NSImage] = [:]
}

extension EnvironmentValues {
    package var notchNotificationIcons: [String: NSImage] {
        get { self[NotchNotificationIconsKey.self] }
        set { self[NotchNotificationIconsKey.self] = newValue }
    }
}

package struct NotchNotificationAppIcon: View {
    package let app: String
    package let size: CGFloat
    @ObservedObject private var service = NotchNotificationService.shared
    @Environment(\.notchNotificationIcons) private var icons

    package var body: some View {
        Group {
            if let icon = icons[app] ?? service.icon(for: app) {
                Image(nsImage: icon).resizable().scaledToFit()
            } else {
                Image(systemName: "bell.badge.fill")
                    .font(.system(size: size * 0.48, weight: .medium))
                    .foregroundStyle(.white.opacity(0.85))
                    .frame(width: size, height: size)
                    .background(.white.opacity(0.09), in: RoundedRectangle(cornerRadius: size * 0.24))
            }
        }
        .frame(width: size, height: size)
        .accessibilityHidden(true)
    }
}
