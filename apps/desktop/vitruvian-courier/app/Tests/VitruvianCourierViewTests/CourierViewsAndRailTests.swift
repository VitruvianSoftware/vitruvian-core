// Copyright 2026 VitruvianSoftware
// SPDX-License-Identifier: AGPL-3.0-or-later

import AppKit
import SwiftUI
import VitruvianCourierCore
import XCTest

@testable import VitruvianCourier

@MainActor
final class CourierViewsAndRailTests: XCTestCase {
    private var suites: [String] = []
    private var previousEnhancedUI: NSNumber = false

    override func setUp() async throws {
        _ = NSApplication.shared
        let attribute = "AXEnhancedUserInterface"
        let getter = NSSelectorFromString("accessibilityAttributeValue:")
        let setter = NSSelectorFromString("accessibilitySetValue:forAttribute:")
        previousEnhancedUI = NSApp.perform(getter, with: attribute)?.takeUnretainedValue() as? NSNumber ?? false
        NSApp.perform(setter, with: true, with: attribute)
    }

    override func tearDown() async throws {
        let attribute = "AXEnhancedUserInterface"
        let setter = NSSelectorFromString("accessibilitySetValue:forAttribute:")
        NSApp.perform(setter, with: previousEnhancedUI, with: attribute)
        SendLaterNudgeSession.shared.dismissed = false
        for suite in suites {
            ScratchDefaults.suite(named: suite)?.removePersistentDomain(forName: suite)
        }
        suites = []
    }

    private func defaults() -> UserDefaults {
        let name = "courier.views-and-rail.\(UUID().uuidString)"
        suites.append(name)
        return ScratchDefaults.suite(named: name)!
    }

    private func offlineApp() -> AppModel {
        AppModel(supervisor: EngineSupervisor(
            enginePath: "/nonexistent/vitruvian-courier-engine",
            dataDir: FileManager.default.temporaryDirectory.appendingPathComponent("vitruvian-courier-views-and-rail"),
            environment: [:],
            launcher: FoundationProcessLauncher()
        ))
    }

    private func host<V: View>(_ view: V, size: NSSize = NSSize(width: 360, height: 240)) -> (NSWindow, NSHostingView<V>) {
        _ = NSApplication.shared
        let hosting = NSHostingView(rootView: view)
        let window = NSWindow(contentRect: NSRect(origin: .zero, size: size), styleMask: [.borderless],
                              backing: .buffered, defer: false)
        window.contentView = hosting
        hosting.frame = NSRect(origin: .zero, size: size)
        pump(hosting, in: window)
        return (window, hosting)
    }

    private func pump(_ hosting: NSView, in window: NSWindow) {
        for _ in 0 ..< 20 {
            RunLoop.main.run(mode: .default, before: Date(timeIntervalSinceNow: 0.004))
            hosting.layoutSubtreeIfNeeded()
        }
        window.displayIfNeeded()
    }

    private func accessibilityNodes(in root: NSView) -> [AnyObject] {
        let attrSelector = NSSelectorFromString("accessibilityAttributeValue:")
        func children(of element: AnyObject) -> [AnyObject] {
            var list: [AnyObject] = (element.accessibilityChildren?() ?? []).map { $0 as AnyObject }
            if element.responds(to: attrSelector),
               let unmanaged = element.perform(attrSelector, with: NSAccessibility.Attribute.children.rawValue as NSString),
               let raw = unmanaged.takeUnretainedValue() as? [AnyObject] {
                for item in raw where !list.contains(where: { $0 === item }) {
                    list.append(item)
                }
            }
            return list
        }
        func walk(_ element: AnyObject) -> [AnyObject] {
            [element] + children(of: element).flatMap(walk)
        }
        return walk(root)
    }

    private func extractString(_ object: AnyObject?) -> String? {
        guard let object else { return nil }
        if let attributed = object as? NSAttributedString {
            return attributed.string.isEmpty ? nil : attributed.string
        }
        if let nsString = object as? NSString {
            let string = nsString as String
            return string.isEmpty ? nil : string
        }
        return nil
    }

    private func stringFromAttribute(_ attr: NSAccessibility.Attribute, on node: AnyObject) -> String? {
        let selector = NSSelectorFromString("accessibilityAttributeValue:")
        guard node.responds(to: selector),
              let unmanaged = node.perform(selector, with: attr.rawValue as NSString)
        else { return nil }
        return extractString(unmanaged.takeUnretainedValue())
    }

    private func stringFromNoArgSelector(_ name: String, on node: AnyObject) -> String? {
        let selector = NSSelectorFromString(name)
        guard node.responds(to: selector),
              let unmanaged = node.perform(selector)
        else { return nil }
        return extractString(unmanaged.takeUnretainedValue())
    }

    private func accessibilityStrings(in root: NSView) -> [String] {
        var found: [String] = []
        for node in accessibilityNodes(in: root) {
            for sel in ["accessibilityLabel", "accessibilityTitle", "accessibilityValue", "accessibilityHelp"] {
                if let text = stringFromNoArgSelector(sel, on: node) {
                    found.append(text)
                }
            }
            for attr: NSAccessibility.Attribute in [.value, .title, .description, .help] {
                if let text = stringFromAttribute(attr, on: node) {
                    found.append(text)
                }
            }
        }
        return found
    }

    // MARK: - Pinned strip

    func testPinnedChatKeepsLongNamesToOneLineWithFullNameInHelp() {
        let short = Fixture.row("!short", "Ana", network: "whatsapp", ts: 5, preview: "Hi")
        let long = Fixture.row(
            "!long",
            "Alexandria Featherstonehaugh-Wollstonecraft Department Group",
            network: "whatsapp",
            ts: 5,
            preview: "Hi"
        )

        let shortHost = NSHostingView(rootView: PinnedChat(
            row: short, networkName: "WhatsApp", isOpen: false, isSelected: false, showsBadge: true, tinted: true
        ).frame(width: 88))
        let longHost = NSHostingView(rootView: PinnedChat(
            row: long, networkName: "WhatsApp", isOpen: false, isSelected: false, showsBadge: true, tinted: true
        ).frame(width: 88))
        shortHost.layoutSubtreeIfNeeded()
        longHost.layoutSubtreeIfNeeded()

        XCTAssertEqual(longHost.fittingSize.height, shortHost.fittingSize.height, accuracy: 0.5,
                       "long pinned names must stay on one line so every tile has the same height")

        let (window, hostedLong) = host(
            PinnedChat(row: long, networkName: "WhatsApp", isOpen: false, isSelected: false, showsBadge: true, tinted: true)
                .frame(width: 88),
            size: NSSize(width: 100, height: 100)
        )
        defer { window.contentView = nil }
        let strings = accessibilityStrings(in: hostedLong)
        XCTAssertTrue(strings.contains { $0.contains("Alexandria Featherstonehaugh-Wollstonecraft Department Group") },
                      "full untruncated name must remain exposed in accessibility/help: \(strings)")
    }

    // MARK: - Empty state guidance

    func testEmptyStateViewsOfferGoToInboxAndSendLaterGesture() {
        for space in ["send_later", "reminders", "archive", "low_priority"] {
            let query = InboxQuery(space: space, filters: [])
            var wentToInbox = 0
            let (window, hosted) = host(
                EmptyStateView(state: EmptyState.of(query), guidance: EmptyStateGuidance.of(query)) {
                    wentToInbox += 1
                }
            )
            defer { window.contentView = nil }
            let nodes = accessibilityNodes(in: hosted)
            let strings = accessibilityStrings(in: hosted)
            XCTAssertTrue(strings.contains("Go to Inbox"), "missing Go to Inbox in \(space): \(strings)")
            if space == "send_later" {
                XCTAssertTrue(strings.contains("Right-click Send, or choose Send Later from the + menu."),
                              "Send Later empty state must explain how to schedule: \(strings)")
            }
            let button = nodes.first {
                ($0.accessibilityLabel?() == "Go to Inbox" || $0.accessibilityTitle?() == "Go to Inbox")
                    && $0.accessibilityPerformPress != nil
            }
            XCTAssertNotNil(button, "Go to Inbox must be an accessible pressable button in \(space)")
            _ = button?.accessibilityPerformPress?()
            XCTAssertEqual(wentToInbox, 1, "pressing Go to Inbox in \(space) must navigate to inbox")
        }

        let inboxQuery = InboxQuery(space: "inbox", filters: [])
        let (inboxWin, inboxHosted) = host(
            EmptyStateView(state: EmptyState.of(inboxQuery), guidance: EmptyStateGuidance.of(inboxQuery))
        )
        defer { inboxWin.contentView = nil }
        XCTAssertFalse(accessibilityStrings(in: inboxHosted).contains("Go to Inbox"))
    }

    // MARK: - Space rail shortcuts and tooltips

    private struct SpaceBarHost: View {
        @ObservedObject var spaces: SpacesModel
        @ObservedObject var inbox: InboxModel
        let labels: LabelsModel
        @ObservedObject var hotkeys: HotkeyRegistry

        var body: some View {
            SpaceBar(spaces: spaces, inbox: inbox, labels: labels, hotkeys: hotkeys)
        }
    }

    func testSpaceBarTooltipsIncludeShortcutSkipHiddenSpacesAndFollowPresets() {
        let store = defaults()
        let app = offlineApp()
        let inbox = InboxModel(appModel: app, preferences: InboxPreferences(defaults: store))
        let lifecycle = SystemLifecycleModel(loginItemService: SnapshotLoginItemService(),
                                             biometricService: SnapshotBiometricService(), defaults: store)
        let spaces = SpacesModel(appModel: app, inbox: inbox, lifecycle: lifecycle)
        let labels = LabelsModel(appModel: app, lifecycle: lifecycle)
        let hotkeys = HotkeyRegistry(defaults: store)
        hotkeys.applyTextsAppPreset()

        spaces.setSpacesForTesting([
            Space(spaceID: "inbox", kind: .builtin, title: "Inbox", chats: 4, unreadChats: 1),
            Space(spaceID: "archive", kind: .builtin, title: "Archive", hidden: true, chats: 10),
            Space(spaceID: "acc-wa", kind: .account, title: "WhatsApp", network: "whatsapp", chats: 3),
            Space(spaceID: "lbl-work", kind: .label, title: "Work", labelID: 1, color: 2, icon: "briefcase", chats: 2),
        ])

        let (window, hosted) = host(
            SpaceBarHost(spaces: spaces, inbox: inbox, labels: labels, hotkeys: hotkeys),
            size: NSSize(width: 60, height: 260)
        )
        defer { window.contentView = nil }

        let initial = accessibilityStrings(in: hosted)
        XCTAssertTrue(initial.contains { $0.contains("Inbox  ⌃1 · ") }, "expected Inbox ⌃1 tooltip: \(initial)")
        XCTAssertTrue(initial.contains { $0.contains("WhatsApp  ⌃2 · ") },
                      "account icon must expose outer shortcut tooltip without inner badge overriding: \(initial)")
        XCTAssertTrue(initial.contains { $0.contains("Work  ⌃3 · ") },
                      "label icon must expose outer shortcut tooltip after hidden Archive is skipped: \(initial)")
        XCTAssertFalse(initial.contains { $0.contains("Archive") }, "hidden space must not appear on rail")

        // Also check reordering visible spaces updates the shortcut labels on the rail.
        spaces.setSpacesForTesting([
            Space(spaceID: "inbox", kind: .builtin, title: "Inbox", chats: 4, unreadChats: 1),
            Space(spaceID: "lbl-work", kind: .label, title: "Work", labelID: 1, color: 2, icon: "briefcase", chats: 2),
            Space(spaceID: "acc-wa", kind: .account, title: "WhatsApp", network: "whatsapp", chats: 3),
        ])
        pump(hosted, in: window)
        let reordered = accessibilityStrings(in: hosted)
        XCTAssertTrue(reordered.contains { $0.contains("Work  ⌃2 · ") }, "reordered Work must show ⌃2: \(reordered)")
        XCTAssertTrue(reordered.contains { $0.contains("WhatsApp  ⌃3 · ") },
                      "reordered WhatsApp must show ⌃3: \(reordered)")

        // Fresh SpaceBar mounts reflect rebound (⌥) and disabled Switch First 9 Spaces Modifier states.
        _ = hotkeys.record(KeyChord(key: "", option: true), for: "Switch First 9 Spaces Modifier")
        let (optWin, optHosted) = host(
            SpaceBar(spaces: spaces, inbox: inbox, labels: labels, hotkeys: hotkeys),
            size: NSSize(width: 60, height: 260)
        )
        defer { optWin.contentView = nil }
        let optionLabels = accessibilityStrings(in: optHosted)
        XCTAssertTrue(optionLabels.contains { $0.contains("Inbox  ⌥1 · ") }, "expected ⌥1 after rebinding: \(optionLabels)")

        hotkeys.setEnabled(false, for: "Switch First 9 Spaces Modifier")
        let (offWin, offHosted) = host(
            SpaceBar(spaces: spaces, inbox: inbox, labels: labels, hotkeys: hotkeys),
            size: NSSize(width: 60, height: 260)
        )
        defer { offWin.contentView = nil }
        let disabledLabels = accessibilityStrings(in: offHosted)
        XCTAssertFalse(disabledLabels.contains { $0.contains("⌥1") || $0.contains("⌃1") || $0.contains("⌘1") },
                       "disabled Switch First 9 Spaces Modifier must omit shortcut from tooltip: \(disabledLabels)")
        XCTAssertTrue(disabledLabels.contains { $0.contains("Inbox · ") }, "expected plain Inbox · count: \(disabledLabels)")
    }

    // MARK: - Message requests (previews on vs previews off)

    func testRequestRowsReplacePlaceholderNameAndShowMessagePreview() {
        let first = InboxRow(
            roomID: "!req1:courier.local", network: "facebook", name: "Facebook user", avatarPath: "",
            isDirect: true, lastTS: Fixture.millis(60 * 24), preview: "Are you still selling the bicycle?",
            previewKind: .text, previewMine: false, unread: 1, muted: false, request: true
        )
        let second = InboxRow(
            roomID: "!req2:courier.local", network: "facebook", name: "Facebook user", avatarPath: "",
            isDirect: true, lastTS: Fixture.millis(60 * 26), preview: "Found your keys near the gate",
            previewKind: .text, previewMine: false, unread: 1, muted: false, request: true
        )

        var previewsOn = RowStyle(InboxPreferences(defaults: defaults()))
        previewsOn.showPreviews = true
        let (win1, host1) = host(InboxRowView(
            row: first, networkName: "Messenger", now: Fixture.now, style: previewsOn,
            isSelecting: false, isSelected: false, isHovered: false, hoverAct: {}, accept: {}, decline: {}
        ) { EmptyView() })
        let (win2, host2) = host(InboxRowView(
            row: second, networkName: "Messenger", now: Fixture.now, style: previewsOn,
            isSelecting: false, isSelected: false, isHovered: false, hoverAct: {}, accept: {}, decline: {}
        ) { EmptyView() })
        defer {
            win1.contentView = nil
            win2.contentView = nil
        }

        let strings1 = accessibilityStrings(in: host1).joined(separator: " | ")
        let strings2 = accessibilityStrings(in: host2).joined(separator: " | ")
        XCTAssertTrue(strings1.contains("Unknown Messenger contact"), strings1)
        XCTAssertFalse(strings1.contains("Facebook user"), strings1)
        XCTAssertTrue(strings1.contains("Are you still selling the bicycle?"), strings1)
        XCTAssertTrue(strings2.contains("Found your keys near the gate"), strings2)
        XCTAssertNotEqual(strings1, strings2, "with previews on, two placeholder requests differ by preview")
    }

    func testPlaceholderRequestsAcrossDifferentNetworksStayDistinguishableWithPreviewsOff() {
        var previewsOff = RowStyle(InboxPreferences(defaults: defaults()))
        previewsOff.showPreviews = false

        let fb = InboxRow(
            roomID: "!req-fb:courier.local", network: "facebook", name: "Facebook user", avatarPath: "",
            isDirect: true, lastTS: Fixture.millis(60 * 24), preview: "Hidden text A",
            previewKind: .text, previewMine: false, unread: 1, muted: false, request: true
        )
        let ig = InboxRow(
            roomID: "!req-ig:courier.local", network: "instagram", name: "", avatarPath: "",
            isDirect: true, lastTS: Fixture.millis(60 * 24), preview: "Hidden text B",
            previewKind: .text, previewMine: false, unread: 1, muted: false, request: true
        )

        let (winFB, hostFB) = host(InboxRowView(
            row: fb, networkName: "Messenger", now: Fixture.now, style: previewsOff,
            isSelecting: false, isSelected: false, isHovered: false, hoverAct: {}, accept: {}, decline: {}
        ) { EmptyView() })
        let (winIG, hostIG) = host(InboxRowView(
            row: ig, networkName: "Instagram", now: Fixture.now, style: previewsOff,
            isSelecting: false, isSelected: false, isHovered: false, hoverAct: {}, accept: {}, decline: {}
        ) { EmptyView() })
        defer {
            winFB.contentView = nil
            winIG.contentView = nil
        }

        let fbStrings = accessibilityStrings(in: hostFB).joined(separator: " | ")
        let igStrings = accessibilityStrings(in: hostIG).joined(separator: " | ")
        XCTAssertTrue(fbStrings.contains("Unknown Messenger contact"), fbStrings)
        XCTAssertTrue(fbStrings.contains("Message request"), fbStrings)
        XCTAssertFalse(fbStrings.contains("Hidden text A"), fbStrings)
        XCTAssertTrue(igStrings.contains("Unknown Instagram contact"), igStrings)
        XCTAssertNotEqual(fbStrings, igStrings)
    }

    // MARK: - Late-night nudge session persistence

    func testSendLaterNudgeSessionStaysDismissedAcrossChatsAndComposerViews() {
        let store = defaults()
        let prefs = ComposerPreferences(defaults: store)
        let composer = ComposerModel(
            sender: SnapshotMessageSender(),
            draftDelay: 0,
            sleep: { _ in },
            preferences: prefs,
            entitlement: AlwaysEntitled(),
            now: { Fixture.now }
        )
        composer.open("!chat-1:courier.local")
        composer.text = "Up late writing"

        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Europe/London")!
        let late = calendar.date(from: DateComponents(year: 2026, month: 11, day: 17, hour: 23, minute: 30))!

        XCTAssertFalse(SendLaterNudgeSession.shared.dismissed)
        XCTAssertTrue(SendLaterNudge.shows(
            hasText: composer.canSchedule,
            now: late,
            calendar: calendar,
            dismissed: SendLaterNudgeSession.shared.dismissed
        ))

        // Dismiss once: switching chats or mounting a fresh ComposerView keeps it dismissed for the session.
        SendLaterNudgeSession.shared.dismissed = true
        composer.open("!chat-2:courier.local")
        composer.text = "Another late draft"
        let (window, _) = host(
            ComposerView(
                composer: composer,
                preferences: prefs,
                textHeight: .constant(ComposerTextView.minimumHeight),
                menus: ComposerMenus(sendLater: {}, createPoll: {}, pollsUnavailable: nil)
            ),
            size: NSSize(width: 520, height: 120)
        )
        defer { window.contentView = nil }

        XCTAssertTrue(SendLaterNudgeSession.shared.dismissed)
        XCTAssertFalse(SendLaterNudge.shows(
            hasText: composer.canSchedule,
            now: late,
            calendar: calendar,
            dismissed: SendLaterNudgeSession.shared.dismissed
        ))
        // Late-night ComposerView shows the nudge bar when text is schedulable, hides it when unentitled or in a
        // composer without sendLater (e.g. ThreadPane), and hides it once dismissed.
        let activeComposer = ComposerModel(
            sender: SnapshotMessageSender(),
            draftDelay: 0,
            sleep: { _ in },
            preferences: prefs,
            entitlement: AlwaysEntitled(),
            now: { Fixture.now }
        )
        activeComposer.open("!chat-active:courier.local")
        activeComposer.text = "Text in composer"

        let deniedComposer = ComposerModel(
            sender: SnapshotMessageSender(),
            draftDelay: 0,
            sleep: { _ in },
            preferences: prefs,
            entitlement: NoPlan(),
            now: { Fixture.now }
        )
        deniedComposer.open("!chat-denied:courier.local")
        deniedComposer.text = "Text in composer"
        XCTAssertFalse(deniedComposer.entitlement.isEntitled(.sendLater))
        let (deniedWin, deniedHost) = host(
            ComposerView(
                composer: deniedComposer,
                preferences: prefs,
                textHeight: .constant(ComposerTextView.minimumHeight),
                menus: ComposerMenus(sendLater: {}, createPoll: {}, pollsUnavailable: nil)
            ),
            size: NSSize(width: 520, height: 120)
        )
        defer { deniedWin.contentView = nil }
        XCTAssertFalse(accessibilityStrings(in: deniedHost).contains { $0.contains("send this later?") },
                       "unentitled composer must never show the nudge")

        let (noMenuWin, noMenuHost) = host(
            ComposerView(
                composer: activeComposer,
                preferences: prefs,
                textHeight: .constant(ComposerTextView.minimumHeight),
                menus: ComposerMenus(sendLater: nil, createPoll: nil, pollsUnavailable: nil)
            ),
            size: NSSize(width: 520, height: 120)
        )
        defer { noMenuWin.contentView = nil }
        XCTAssertFalse(accessibilityStrings(in: noMenuHost).contains { $0.contains("send this later?") },
                       "composer without sendLater menu (e.g. ThreadPane) must never show the nudge")
    }

    // MARK: - Request rows: same network, previews off / on

    private func requestRow(_ id: String, ts: Int64, preview: String, kind: PreviewKind = .text) -> InboxRow {
        InboxRow(
            roomID: id, network: "facebook", name: "Facebook user", avatarPath: "",
            isDirect: true, lastTS: ts, preview: preview,
            previewKind: kind, previewMine: false, unread: 1, muted: false, request: true
        )
    }

    private func requestStrings(_ row: InboxRow, showPreviews: Bool, handle: String = "") -> String {
        var style = RowStyle(InboxPreferences(defaults: defaults()))
        style.showPreviews = showPreviews
        let (window, hosted) = host(InboxRowView(
            row: row, requestHandle: handle, networkName: "Messenger", now: Fixture.now, style: style,
            isSelecting: false, isSelected: false, isHovered: false, hoverAct: {}, accept: {}, decline: {}
        ) { EmptyView() })
        defer { window.contentView = nil }
        return accessibilityStrings(in: hosted).joined(separator: " | ")
    }

    func testTwoSameNetworkPlaceholderRequestsDifferWithPreviewsOff() {
        let first = requestRow("!a:courier.local", ts: Fixture.millis(60 * 24), preview: "Secret A")
        let second = requestRow("!b:courier.local", ts: Fixture.millis(60 * 50), preview: "Secret B")
        let one = requestStrings(first, showPreviews: false)
        let two = requestStrings(second, showPreviews: false)
        XCTAssertNotEqual(one, two, "same-network placeholder requests must not read alike with previews off")
        XCTAssertFalse(one.contains("Secret A"), one)
        XCTAssertTrue(one.contains("Unknown Messenger contact"), one)
        XCTAssertTrue(one.contains("Message request"), one)
        // With a handle, the handle is the title and the line.
        let handled = requestStrings(first, showPreviews: false, handle: "@ana.s")
        XCTAssertTrue(handled.contains("@ana.s"), handled)
        XCTAssertFalse(handled.contains("Unknown Messenger contact"), handled)
    }

    func testPreviewsOnShowMediaLabelNotRequestDate() {
        let photo = requestRow("!p:courier.local", ts: Fixture.millis(60 * 24), preview: "", kind: .image)
        let strings = requestStrings(photo, showPreviews: true)
        XCTAssertTrue(strings.contains("Image"), strings) // the row's media label, not "Message request"
        XCTAssertFalse(strings.contains("3:12"), strings)
    }
}
