// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 VitruvianSoftware

import AppKit
import Foundation
import SwiftUI
import VitruvianCore
import VitruvianDesign
import VitruvianServices
import VitruvianUI

/// The Notifications page's list: one compact row per message, newest first,
/// and each app's messages stacked into one row that opens in place.
enum NotchNotificationListTests {
    static func run(_ suite: TestSuite) {
        grouping(suite)
        settings(suite)
        page(suite)
        render(suite)
    }

    /// A morning's messages: four from Slack, and one each from Claude,
    /// Vitruvian and Mail, received a few minutes apart.
    static func sample(at start: Date = sampleStart) -> [NotchSystemNotification] {
        let messages: [(minutes: Double, app: String, title: String, subtitle: String, body: String)] = [
            (0, "Slack", "Priya Raman", "#platform", "Deploy to staging is green, promoting to prod after standup."),
            (3, "Mail", "Northwind Travel", "", "Your itinerary for Lisbon, 22 to 26 October, is ready to view."),
            (6, "Slack", "Marcus Lee", "#design-review", "Left two comments on the island mockups, mostly spacing."),
            (9, "Claude", "Scheduled task completed", "", "Weekly dependency audit finished: 3 updates are ready for review."),
            (12, "Slack", "Priya Raman", "#platform", "Can you look at the cache key change before 11?"),
            (15, "Vitruvian", "App updates", "", "2 apps have updates: Raycast 1.98 and Figma 125.4."),
            (17, "Slack", "Dana Whitfield", "", "Lunch at 12:30? The new ramen place on 4th."),
        ]
        // The inbox keeps each arrival in front.
        return messages.reversed().map {
            NotchSystemNotification(id: UUID(), content: NotchNotificationContent(app: $0.app, title: $0.title,
                                                                                   subtitle: $0.subtitle, body: $0.body),
                                    received: start.addingTimeInterval($0.minutes * 60), canOpen: true)
        }
    }

    /// 9:24 in the morning, local time, on the day this was written.
    static let sampleStart: Date = {
        var components = DateComponents(year: 2026, month: 10, day: 15, hour: 9, minute: 24)
        components.calendar = Calendar(identifier: .gregorian)
        return components.date ?? Date(timeIntervalSince1970: 0)
    }()

    private static func item(_ app: String, _ title: String, at seconds: Double) -> NotchSystemNotification {
        NotchSystemNotification(id: UUID(), content: NotchNotificationContent(app: app, title: title, subtitle: "", body: "Hi"),
                                received: Date(timeIntervalSince1970: 1_000_000 + seconds), canOpen: true)
    }

    // MARK: Grouping, order and counts

    private static func grouping(_ suite: TestSuite) {
        typealias Support = NotchNotificationListSupport
        let slackOld = item("Slack", "first", at: 0), mail = item("Mail", "mail", at: 10)
        let slackNew = item("Slack", "second", at: 20), claude = item("Claude", "done", at: 30)
        let slackNewest = item("Slack", "third", at: 40)
        // Out of order on purpose: the list sorts by arrival, newest first.
        let items = [mail, slackNewest, slackOld, claude, slackNew]

        suite.expect(Support.newestFirst(items).map(\.id) == [slackNewest, claude, slackNew, mail, slackOld].map(\.id),
                     "the list shows the newest message first")
        let tie = Date(timeIntervalSince1970: 5)
        let tied = [item("A", "front", at: 0), item("B", "back", at: 0)].map {
            NotchSystemNotification(id: $0.id, content: $0.content, received: tie, canOpen: true)
        }
        suite.expect(Support.newestFirst(tied).map(\.id) == tied.map(\.id),
                     "messages read in the same pass keep the inbox's order, which puts the latest in front")

        let groups = Support.groups(items)
        suite.expect(groups.map(\.app) == ["Slack", "Claude", "Mail"],
                     "groups are ordered by their newest message: got \(groups.map(\.app))")
        suite.expect(groups.map(\.count) == [3, 1, 1] && groups[0].newest.id == slackNewest.id
                     && groups[0].items.map(\.id) == [slackNewest, slackNew, slackOld].map(\.id),
                     "a group counts its app's messages and lists them newest first")
        let later = item("Mail", "later", at: 50)
        suite.expect(Support.groups(items + [later]).map(\.app) == ["Mail", "Slack", "Claude"],
                     "a new message moves its app's group to the top")

        // A group of one is a plain row.
        let grouped = Support.entries(items, grouped: true, expanded: [])
        suite.expect(grouped.count == 3, "three apps make three rows: got \(grouped.count)")
        if case .group(let group, let open) = grouped.first {
            suite.expect(group.app == "Slack" && group.count == 3 && !open,
                         "the app with several messages is one closed stack")
        } else {
            suite.expect(false, "the app with several messages is one stack")
        }
        suite.expect(grouped.dropFirst().allSatisfy { if case .single = $0 { return true } else { return false } },
                     "an app with a single message is shown as a plain row, not as a group of one")
        suite.expect(Support.entries(items, grouped: false, expanded: ["app:Slack"]).map(\.id)
                     == Support.newestFirst(items).map { $0.id.uuidString },
                     "ungrouped, every message is its own row, newest first, whatever was open")

        // Nameless banners may come from different apps, so they never stack.
        let nameless = [item("", "one", at: 1), item("", "two", at: 2)]
        suite.expect(Support.groups(nameless).count == 2
                     && Support.entries(nameless, grouped: true, expanded: []).count == 2,
                     "banners that name no app are never stacked together")

        // Expanding and collapsing.
        let slack = "app:Slack"
        let open = Support.toggling(slack, in: [])
        suite.expect(open == [slack] && Support.toggling(slack, in: open).isEmpty,
                     "clicking a stack opens it and clicking again closes it")
        let expanded = Support.entries(items, grouped: true, expanded: open)
        suite.expect(expanded.map(\.id) == [slack] + [slackNewest, slackNew, slackOld].map { $0.id.uuidString }
                     + [claude.id.uuidString, mail.id.uuidString],
                     "an open stack lists its messages in place, under its row and above the next app")
        if case .group(_, let isOpen) = expanded.first {
            suite.expect(isOpen, "the stack's row says it is open")
        }
        suite.expect(expanded.dropFirst().prefix(3).allSatisfy { if case .member = $0 { return true } else { return false } },
                     "the open stack's messages are its members, each with its own actions")
        suite.expect(Support.expansion(open, keptFor: [slackNewest, claude]).isEmpty
                     && Support.expansion(open, keptFor: items) == open,
                     "a stack that drops to one message forgets it was open")

        // Dismissing a group.
        var inbox = NotchNotificationInbox()
        _ = inbox.update([])
        let arrivals = [slackOld, mail, slackNew, claude, slackNewest]
        _ = inbox.update(arrivals)
        let stack = Support.groups(inbox.items)[0]
        let afterwards = item("Slack", "after the list was drawn", at: 60)
        _ = inbox.update(arrivals + [afterwards])
        inbox.dismiss(stack.ids)
        suite.expect(Set(inbox.items.map(\.id)) == [mail.id, claude.id, afterwards.id],
                     "dismissing a stack clears that app's messages and no other app's")
        suite.expect(inbox.items.contains { $0.id == afterwards.id },
                     "a message that arrived after the stack was drawn is not dismissed with it")
        suite.expect(inbox.update(arrivals + [afterwards]).isEmpty && inbox.items.count == 3,
                     "a dismissed stack does not come back when its banners are read again")

        // VoiceOver.
        let english = FeatureStrings.notchNotifications(.enUS)
        suite.expect(Support.accessibilityLabel(for: groups[0], text: english) == "Slack, 3 notifications, newest: third, Hi",
                     "VoiceOver reads a stack as its app, its count and its newest message: got "
                     + Support.accessibilityLabel(for: groups[0], text: english))
        for (language, _) in LocalizationTests.languages {
            let text = FeatureStrings.notchNotifications(language)
            suite.expect(TestFormat.parse(text.groupAccessibilityFormat)?.conversions == ["@", "d", "@"],
                         "\(language.rawValue): the stack's VoiceOver label takes the app, the count and the message")
            suite.expect(TestFormat.parse(text.dismissAppFormat)?.conversions == ["@"],
                         "\(language.rawValue): dismissing a stack names its app")
            let fields = [text.layout, text.layoutCards, text.layoutList, text.groupByApp, text.groupByAppHint,
                          text.showAll, text.showLess]
            suite.expect(fields.allSatisfy { !$0.isEmpty } && text.layoutCards != text.layoutList,
                         "\(language.rawValue): the layout choice and grouping switch are translated")
        }

        // Motion.
        suite.expect(NotchNotificationListMotion.animation(reduceMotion: true) == nil
                     && NotchNotificationListMotion.animation(reduceMotion: false) != nil,
                     "a stack opens and closes with a quick animation, and without one under Reduce Motion")

        // Density: the list fits about twice what the cards do.
        let geometry = NotchGeometry(screen: CGRect(x: 0, y: 0, width: 1512, height: 982), safeAreaTop: 32,
                                     cameraWidth: 180, layout: .spacious)
        let rows = NotchNotificationListLayout.visibleRows(height: geometry.contentBudget)
        suite.expect((6...8).contains(rows),
                     "the spacious island shows 6 to 8 list rows where it shows 4 cards: got \(rows)")
    }

    // MARK: The setting

    private static func settings(_ suite: TestSuite) {
        let domain = "com.vitruviansoftware.vitruvian.tests.notch-notification-list"
        let defaults = UserDefaults(suiteName: domain)!
        defaults.removePersistentDomain(forName: domain)
        defer { defaults.removePersistentDomain(forName: domain) }
        suite.expect(NotchNotificationListSupport.layout(in: defaults) == .cards,
                     "with no saved layout the page shows cards, as it always has")
        suite.expect(Defaults.registeredDefaults[DefaultsKey.notchNotificationsLayout] as? String
                     == NotchNotificationLayout.cards.rawValue,
                     "the registered default layout is the cards")
        suite.expect(NotchNotificationLayout(saved: nil) == .cards && NotchNotificationLayout(saved: "grid") == .cards,
                     "an absent or unknown saved layout reads as the cards")
        suite.expect(!NotchNotificationListSupport.groupsByApp(in: defaults),
                     "the cards never group, so an untouched Mac sees no stacks")
        defaults.set(NotchNotificationLayout.list.rawValue, forKey: DefaultsKey.notchNotificationsLayout)
        suite.expect(NotchNotificationListSupport.layout(in: defaults) == .list,
                     "choosing List shows the list")
        suite.expect(NotchNotificationListSupport.groupsByApp(in: defaults),
                     "the list groups by app unless the switch is turned off")
        defaults.set(false, forKey: DefaultsKey.notchNotificationsGrouped)
        suite.expect(!NotchNotificationListSupport.groupsByApp(in: defaults),
                     "turning grouping off lists every message on its own")
        defaults.set(true, forKey: DefaultsKey.notchNotificationsGrouped)
        defaults.set(NotchNotificationLayout.cards.rawValue, forKey: DefaultsKey.notchNotificationsLayout)
        suite.expect(!NotchNotificationListSupport.groupsByApp(in: defaults),
                     "the grouping switch belongs to the list and does nothing to the cards")
        suite.expect(SettingsBackupSupport.exportKeys().isSuperset(of: [DefaultsKey.notchNotificationsLayout,
                                                                         DefaultsKey.notchNotificationsGrouped]),
                     "the layout and grouping choices are part of settings backup")
    }

    // MARK: The page

    /// Cards scroll sideways and the list scrolls down, each drawn by the
    /// layout the page is given.
    private static func page(_ suite: TestSuite) {
        let geometry = NotchGeometry(screen: CGRect(x: 0, y: 0, width: 1512, height: 982), safeAreaTop: 32,
                                     cameraWidth: 180, layout: .spacious)
        let size = CGSize(width: geometry.contentWidth, height: geometry.contentBudget)
        let items = sample()
        func scrollView(_ layout: NotchNotificationLayout) -> NSScrollView? {
            let (host, window) = host(NotchNotificationPage(items: items, size: size, layout: layout, grouped: false,
                                                            service: .shared, text: FeatureStrings.notchNotifications(.enUS)),
                                      size: size)
            defer { window.contentView = nil }
            func find(_ view: NSView) -> NSScrollView? {
                if let scroll = view as? NSScrollView { return scroll }
                return view.subviews.lazy.compactMap { find($0) }.first
            }
            return find(host)
        }
        if let list = scrollView(.list), let documentSize = list.documentView?.frame.size {
            suite.expect(documentSize.height > list.contentSize.height + 1 && documentSize.width <= list.contentSize.width + 1,
                         "List draws one row under another and scrolls down past what fits")
        } else {
            suite.expect(false, "List draws its rows in a scroll view")
        }
        if let cards = scrollView(.cards), let documentSize = cards.documentView?.frame.size {
            suite.expect(documentSize.width > cards.contentSize.width + 1 && documentSize.height <= cards.contentSize.height + 1,
                         "Cards draws the rail that scrolls sideways, as before")
        } else {
            suite.expect(false, "Cards draws its rail in a scroll view")
        }
    }

    private static func host<Content: View>(_ view: Content, size: CGSize) -> (NSHostingView<AnyView>, NSWindow) {
        let host = NSHostingView(rootView: AnyView(view
            .frame(width: size.width, height: size.height, alignment: .topLeading)
            .environment(\.locale, Locale(identifier: "en_US"))
            .environment(\.colorScheme, .dark)))
        host.frame = CGRect(origin: .zero, size: size)
        let window = NSWindow(contentRect: CGRect(x: -10_000, y: -10_000, width: size.width, height: size.height),
                              styleMask: [.borderless], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.appearance = NSAppearance(named: .darkAqua)
        window.contentView = host
        host.layoutSubtreeIfNeeded()
        RunLoop.current.run(until: Date().addingTimeInterval(0.2))
        host.layoutSubtreeIfNeeded()
        return (host, window)
    }

    // MARK: Pictures for a person

    /// The page drawn four ways at the spacious island's page size, on the
    /// island's black with its side insets, kept with the test's outputs.
    private static func render(_ suite: TestSuite) {
        guard let directory = ProcessInfo.processInfo.environment["TEST_UNDECLARED_OUTPUTS_DIR"] else { return }
        let geometry = NotchGeometry(screen: CGRect(x: 0, y: 0, width: 1512, height: 982), safeAreaTop: 32,
                                     cameraWidth: 180, layout: .spacious)
        let page = CGSize(width: geometry.contentWidth, height: geometry.contentBudget)
        let inset = NotchLayout.horizontalInset
        let canvas = CGSize(width: page.width + inset * 2, height: page.height + inset)
        let items = sample()
        var icons: [String: NSImage] = [:]
        for (app, bundle) in [("Slack", "com.tinyspeck.slackmacgap"), ("Claude", "com.anthropic.claudefordesktop"),
                              ("Mail", "com.apple.mail")] {
            if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundle) {
                icons[app] = NSWorkspace.shared.icon(forFile: url.path)
            }
        }
        icons["Vitruvian"] = NSImage(contentsOf: URL(fileURLWithPath: "Resources/Brand/AppIcon-Default.png"))
        let text = FeatureStrings.notchNotifications(.enUS)
        let shots: [(String, NotchNotificationLayout, Bool, Set<String>)] = [
            ("notifications-1-cards.png", .cards, false, []),
            ("notifications-2-list.png", .list, false, []),
            ("notifications-3-list-grouped.png", .list, true, []),
            ("notifications-4-list-grouped-expanded.png", .list, true, ["app:Slack"]),
        ]
        for (name, layout, grouped, expanded) in shots {
            let view = NotchNotificationPage(items: items, size: page, layout: layout, grouped: grouped,
                                             expanded: expanded, service: .shared, text: text)
                .frame(width: page.width, height: page.height, alignment: .topLeading)
                .padding(.horizontal, inset)
                .padding(.top, inset / 2)
                .padding(.bottom, inset / 2)
                .frame(width: canvas.width, height: canvas.height)
                .background(Color.black)
                .environment(\.notchNotificationIcons, icons)
                .foregroundStyle(.white)
            let (host, window) = host(view, size: canvas)
            defer { window.contentView = nil }
            // At twice the points, as a Retina display shows it.
            guard let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(canvas.width * 2),
                                                pixelsHigh: Int(canvas.height * 2), bitsPerSample: 8,
                                                samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                                                colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0) else {
                suite.expect(false, "\(name) can be drawn")
                continue
            }
            bitmap.size = canvas
            host.cacheDisplay(in: host.bounds, to: bitmap)
            let data = bitmap.representation(using: .png, properties: [:])
            suite.expect(data != nil, "\(name) is drawn")
            try? data?.write(to: URL(fileURLWithPath: directory).appendingPathComponent(name))
        }
    }
}
