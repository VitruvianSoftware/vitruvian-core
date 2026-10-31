// Copyright 2026 VitruvianSoftware
// SPDX-License-Identifier: AGPL-3.0-or-later

import XCTest

@testable import CourierCore

@MainActor
final class SettingsSearchModelTests: XCTestCase {
    override func setUp() {
        AppLockGate.shared.resetForTesting()
    }

    override func tearDown() {
        AppLockGate.shared.resetForTesting()
    }

    func testSearchSuggestionsMatchQueriesAndJumpSwitchesPanes() {
        let model = SettingsNavigationModel()
        XCTAssertEqual(model.selectedPane, .general)
        XCTAssertEqual(model.searchQuery, "")
        XCTAssertTrue(model.suggestions.isEmpty, "empty query shows no dropdown suggestions")

        model.searchQuery = "touch id"
        XCTAssertTrue(model.suggestions.contains { $0.id == "general.requireTouchID" && $0.pane == .general })

        model.searchQuery = "otp"
        let otpPanes = Set(model.suggestions.map(\.pane))
        XCTAssertTrue(otpPanes.contains(.general) || otpPanes.contains(.notifications))
        XCTAssertTrue(model.suggestions.contains { $0.title.localizedCaseInsensitiveContains("OTP") })

        model.searchQuery = "delay"
        let delayMatch = model.suggestions.first { $0.id == "notifications.delay" }
        XCTAssertNotNil(delayMatch)
        XCTAssertEqual(delayMatch?.pane, .notifications)
        XCTAssertEqual(delayMatch?.badge, .labs)

        model.searchQuery = "dock"
        XCTAssertTrue(model.suggestions.contains { $0.id == "appearance.dockBadgeCount" && $0.pane == .appearance })
        XCTAssertTrue(model.suggestions.contains { $0.id == "accounts.dockCleanup" && $0.pane == .accounts })

        model.searchQuery = "composer"
        XCTAssertTrue(model.suggestions.contains { $0.id == "appearance.primaryComposerButton" && $0.pane == .appearance })
        XCTAssertTrue(model.suggestions.contains { $0.id == "appearance.secondaryComposerButton" && $0.pane == .appearance })

        if let target = delayMatch {
            model.jump(to: target)
            XCTAssertEqual(model.selectedPane, .notifications)
            XCTAssertEqual(model.highlightedSettingID, "notifications.delay")
            XCTAssertEqual(model.searchQuery, "", "jumping clears the search field")
        }

        model.openPane(.accounts, accountKey: "whatsapp:wa-1")
        XCTAssertEqual(model.selectedPane, .accounts)
        XCTAssertEqual(model.selectedAccountKey, "whatsapp:wa-1")
    }

    func testEveryVisibleSettingInCatalogIsFindableAndEveryPaneIsCovered() {
        let model = SettingsNavigationModel()
        let catalog = SettingsNavigationModel.allSettings
        XCTAssertFalse(catalog.isEmpty)

        // Every pane in SettingsPaneID has at least one setting definition in the single source-of-truth catalog.
        for pane in SettingsPaneID.allCases {
            XCTAssertTrue(
                catalog.contains { $0.pane == pane },
                "Expected catalog to contain settings for pane \(pane.rawValue)"
            )
            XCTAssertFalse(pane.title.isEmpty)
            XCTAssertFalse(pane.symbolName.isEmpty)
        }

        // Every setting in the catalog is findable by its title and by its keywords.
        for definition in catalog {
            model.searchQuery = definition.title
            XCTAssertTrue(
                model.suggestions.contains(definition),
                "Setting \(definition.id) (\(definition.title)) was not findable by title"
            )
            for keyword in definition.keywords {
                model.searchQuery = keyword
                XCTAssertTrue(
                    model.suggestions.contains(definition),
                    "Setting \(definition.id) was not findable by keyword '\(keyword)'"
                )
            }
        }
    }

    func testSharedSettingsNavigationModelSelectsAccountAndEverySettingHasMatchingHighlightTarget() async throws {
        let server = try TestEngineServer { method, _ in
            if method == "hello" { return TestEngineServer.helloOK }
            return .result([String: Any]())
        }
        defer { server.stop() }

        let launcher = FakeLauncher { _, process in process.printReady(socket: server.path) }
        let supervisor = EngineSupervisor(
            enginePath: "/Applications/Courier.app/Contents/Helpers/courier-engine",
            dataDir: URL(fileURLWithPath: "/tmp/courier-settings-nav-\(UUID().uuidString)"),
            environment: [:],
            launcher: launcher,
            credentials: InMemoryCredentialStore(),
            clientName: "Courier/test",
            timing: FakeTime().timing()
        )
        let app = AppModel(supervisor: supervisor)
        defer { supervisor.stop() }

        let suiteName = "courier.settings.nav.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { UserDefaults.standard.removePersistentDomain(forName: suiteName) }

        let inbox = InboxModel(appModel: app, preferences: InboxPreferences(defaults: defaults))
        let lifecycle = SystemLifecycleModel(defaults: defaults)
        let nav = SettingsNavigationModel()
        let accounts = AccountsAndBridgesModel(appModel: app, dockTileService: NoopDockTileService(), lifecycle: lifecycle)
        nav.bind(accountsAndBridges: accounts)

        var openedWindowCount = 0
        let menuCoordinator = AppMenuCoordinator(
            inbox: inbox,
            lifecycle: lifecycle,
            settingsNavigation: nav,
            showSettingsWindow: { openedWindowCount += 1 }
        )

        XCTAssertTrue(menuCoordinator.settingsNavigation === nav)
        menuCoordinator.openSettings(pane: .accounts, accountKey: "slack:T1-U1")
        XCTAssertEqual(openedWindowCount, 1)
        XCTAssertEqual(nav.selectedPane, .accounts)
        XCTAssertEqual(nav.selectedAccountKey, "slack:T1-U1")
        XCTAssertEqual(accounts.selectedAccountKey, "slack:T1-U1")

        let allIDs = Set(SettingsNavigationModel.allSettings.map(\.id))
        XCTAssertEqual(
            SettingsNavigationModel.anchoredSettingIDs,
            allIDs,
            "Every SettingDefinition in SettingsNavigationModel.allSettings must have a matching .settingAnchor ID"
        )

        for setting in SettingsNavigationModel.allSettings {
            nav.searchQuery = setting.title
            nav.jump(to: setting)
            XCTAssertEqual(nav.selectedPane, setting.pane)
            XCTAssertEqual(nav.highlightedSettingID, setting.id)
            XCTAssertTrue(
                SettingsNavigationModel.anchoredSettingIDs.contains(setting.id),
                "Missing view anchor for \(setting.id)"
            )
        }
    }

    func testSharedNotificationPreferencesInstanceReachesNotificationCoordinator() {
        let suiteName = "courier.settings.notif.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { UserDefaults.standard.removePersistentDomain(forName: suiteName) }

        let launcher = FakeLauncher { _, _ in }
        let supervisor = EngineSupervisor(
            enginePath: "/Applications/Courier.app/Contents/Helpers/courier-engine",
            dataDir: URL(fileURLWithPath: "/tmp/courier-settings-notif-\(UUID().uuidString)"),
            environment: [:],
            launcher: launcher,
            credentials: InMemoryCredentialStore(),
            clientName: "Courier/test",
            timing: FakeTime().timing()
        )
        let app = AppModel(supervisor: supervisor)
        let inboxPreferences = InboxPreferences(defaults: defaults)
        let coordinator = NotificationCoordinator(
            appModel: app,
            delivery: NoopNotificationDelivery(),
            row: { _ in nil },
            isLooking: { false },
            restoreDraft: { _, _, _ in },
            showWindow: {},
            preferences: inboxPreferences,
            defaults: defaults
        )

        XCTAssertTrue(coordinator.notificationPreferences === inboxPreferences.notifications)
        inboxPreferences.notifications.delaySeconds = 10
        inboxPreferences.notifications.autoCopyOTP = true
        inboxPreferences.notifications.setAccountOverride(key: "slack:T1-U1", enabled: false)

        XCTAssertEqual(coordinator.notificationPreferences.delaySeconds, 10)
        XCTAssertTrue(coordinator.notificationPreferences.autoCopyOTP)
        XCTAssertFalse(coordinator.notificationPreferences.isAccountNotificationEnabled(network: "slack", accountID: "T1-U1"))
    }

    func testTimeFormatPreferenceFormatsTimestampsAcrossSystem12HourAnd24Hour() {
        let suiteName = "courier.settings.timeformat.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { UserDefaults.standard.removePersistentDomain(forName: suiteName) }

        let prefs = ComposerPreferences(defaults: defaults)
        let utc = TimeZone(secondsFromGMT: 0)!
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = utc
        let afternoon = Date(timeIntervalSince1970: 1_700_055_000) // 2023-11-15 13:30:00 UTC
        let afternoonMillis = Int64(1_700_055_000_000)
        let sameDayNow = Date(timeIntervalSince1970: 1_700_060_000)

        prefs.timeFormat = .twelveHour
        XCTAssertEqual(prefs.formatTime(afternoon, timeZone: utc), "1:30 PM")
        XCTAssertEqual(
            RelativeTime.text(
                forMillis: afternoonMillis,
                now: sameDayNow,
                calendar: calendar,
                locale: Locale(identifier: "en_GB"),
                timeFormat: .twelveHour
            ),
            "1:30 PM"
        )
        XCTAssertEqual(
            SearchDate.text(
                forMillis: afternoonMillis,
                now: sameDayNow,
                calendar: calendar,
                locale: Locale(identifier: "en_GB"),
                timeFormat: .twelveHour
            ),
            "1:30 PM"
        )

        prefs.timeFormat = .twentyFourHour
        XCTAssertEqual(prefs.formatTime(afternoon, timeZone: utc), "13:30")
        XCTAssertEqual(
            RelativeTime.text(
                forMillis: afternoonMillis,
                now: sameDayNow,
                calendar: calendar,
                locale: Locale(identifier: "en_US"),
                timeFormat: .twentyFourHour
            ),
            "13:30"
        )
        XCTAssertEqual(
            SearchDate.text(
                forMillis: afternoonMillis,
                now: sameDayNow,
                calendar: calendar,
                locale: Locale(identifier: "en_US"),
                timeFormat: .twentyFourHour
            ),
            "13:30"
        )

        prefs.timeFormat = .system
        let systemUS = prefs.formatTime(afternoon, locale: Locale(identifier: "en_US"), timeZone: utc)
        let systemGB = prefs.formatTime(afternoon, locale: Locale(identifier: "en_GB"), timeZone: utc)
        XCTAssertTrue(systemUS.contains("1:30"))
        XCTAssertTrue(systemGB.contains("13:30"))
    }
}

@MainActor
private final class NoopNotificationDelivery: NotificationDelivering {
    func requestPermission() {}
    func deliver(_: NotificationContent) {}
    func clear(roomID _: String) {}
    func remove(notificationID _: String) {}
}

private struct NoopDockTileService: DockTileService {
    func isAppInDock(bundleIdentifier _: String) -> Bool { false }
    func removeAppFromDock(bundleIdentifier _: String) -> Bool { false }
}
