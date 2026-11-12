// Copyright 2026 VitruvianSoftware
// SPDX-License-Identifier: AGPL-3.0-or-later

import AppKit
import CourierCore
import SwiftUI
import XCTest

@testable import Courier

/// The menu bar's items do what their titles say, with the app's own wiring.
///
/// Each item runs the way the menu runs it (through the app delegate's `HotkeyDispatcher`, or the
/// `AppMenuCoordinator` call the item makes), and the test checks what a person would see: the window that should
/// open is asked for, or the state a view draws from changed. "The item has an action" is not enough: View ▸ Hide
/// Sidebar flipped a flag no view read, and every item that shows a pane of Settings sent `showSettingsWindow:`,
/// which SwiftUI ignores since macOS 14 ("Please use SettingsLink for opening the Settings scene").
///
/// What only a running app shows (a window actually on screen) is checked by hand with the test copy
/// (`bazel run --config=macos-app //apps/desktop/courier/app:run_test_copy`, README.md).
@MainActor
final class MenuEffectTests: XCTestCase {
    private var dataDirectory: URL?

    /// The app delegate, as the app makes it, with its data in a temporary folder (never the real one), and a
    /// stand-in for SwiftUI's openSettings and openWindow, which only a running app has.
    private func makeApp() throws -> (delegate: AppDelegate, settingsOpened: () -> Int, mainWindowOpened: () -> Int) {
        _ = NSApplication.shared
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("courier-menu-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        dataDirectory = folder
        setenv(EngineLocation.dataDirectoryVariable, folder.path, 1)
        let delegate = AppDelegate()
        var settings = 0
        var main = 0
        delegate.windowOpener.registerSettings { settings += 1 }
        delegate.windowOpener.register({ main += 1 })
        return (delegate, { settings }, { main })
    }

    override func tearDown() async throws {
        unsetenv(EngineLocation.dataDirectoryVariable)
        if let dataDirectory { try? FileManager.default.removeItem(at: dataDirectory) }
    }

    /// Courier ▸ About Courier, Check for Updates…, Settings… (and ⌘,), Accounts…, Help ▸ Report a Problem…, Privacy
    /// & Security and Changelog, the ⌘/ sheet's Customize Shortcuts…: each opens the Settings window, at its pane.
    func testEverySettingsItemOpensTheSettingsWindowAtItsPane() throws {
        let app = try makeApp()
        let navigation = app.delegate.settingsNavigation
        let viaCoordinator: [(String, SettingsSection, SettingsPaneID)] = [
            ("About Courier", .about, .about),
            ("Check for Updates…", .updates, .about),
            ("Accounts…", .accounts, .accounts),
            ("Help ▸ Privacy & Security", .privacy, .about),
            ("Help ▸ Changelog", .changelog, .about),
            ("Customize Shortcuts…", .shortcuts, .hotkeys),
        ]
        for (index, (item, section, pane)) in viaCoordinator.enumerated() {
            app.delegate.menuCoordinator.openSettings(section)
            XCTAssertEqual(app.settingsOpened(), index + 1, "\(item) did not open the Settings window")
            XCTAssertEqual(navigation.selectedPane, pane, "\(item) opened Settings at the wrong pane")
        }
        var opened = app.settingsOpened()
        XCTAssertTrue(app.delegate.hotkeyDispatcher.perform("Settings"))
        opened += 1
        XCTAssertEqual(app.settingsOpened(), opened, "Settings… did not open the Settings window")
        XCTAssertTrue(app.delegate.hotkeyDispatcher.perform("Report a Problem"))
        opened += 1
        XCTAssertEqual(app.settingsOpened(), opened, "Report a Problem… did not open the Settings window")
        XCTAssertTrue(navigation.isPresentingProblemReport, "Report a Problem… did not show the report")
    }

    /// The window scene hands its openSettings to the opener as it appears, so Settings opens even when no menu
    /// item has run yet (a click on Customize Shortcuts… in the ⌘/ sheet, say).
    func testTheWindowSceneRegistersOpenSettings() throws {
        let opener = MainWindowOpener()
        XCTAssertFalse(opener.canShowSettings)
        let host = NSHostingView(rootView: OpenWindowRegistrar(opener: opener))
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 10, height: 10), styleMask: [.borderless],
                              backing: .buffered, defer: false)
        window.contentView = host
        host.layoutSubtreeIfNeeded()
        for _ in 0 ..< 10 { RunLoop.main.run(mode: .default, before: Date(timeIntervalSinceNow: 0.005)) }
        XCTAssertTrue(opener.canShowSettings, "OpenWindowRegistrar did not register openSettings")
        window.contentView = nil
    }

    /// The items whose effect is a model a view draws: each changes it, and running it again changes it back.
    func testViewAndChatItemsChangeWhatTheWindowShows() throws {
        let app = try makeApp()
        let delegate = app.delegate
        let dispatcher = delegate.hotkeyDispatcher

        // View ▸ Hide Sidebar: the split view's column follows isSidebarVisible (SidebarSplitView, tested below).
        XCTAssertTrue(delegate.menuCoordinator.isSidebarVisible)
        XCTAssertTrue(dispatcher.perform("Toggle Sidebar"))
        XCTAssertFalse(delegate.menuCoordinator.isSidebarVisible)
        XCTAssertTrue(dispatcher.perform("Toggle Sidebar"))
        XCTAssertTrue(delegate.menuCoordinator.isSidebarVisible)

        // View ▸ Hide Space Bar: MainWindow draws the space bar from showSpaceBar.
        let spaceBar = delegate.inbox.preferences.showSpaceBar
        XCTAssertTrue(dispatcher.perform("Toggle Space Bar"))
        XCTAssertNotEqual(delegate.inbox.preferences.showSpaceBar, spaceBar)
        XCTAssertTrue(dispatcher.perform("Toggle Space Bar"))
        XCTAssertEqual(delegate.inbox.preferences.showSpaceBar, spaceBar)

        // View ▸ Zoom In, Zoom Out, Actual Size: the window's text zoom.
        let zoom = delegate.appearance.zoomPercent
        XCTAssertTrue(dispatcher.perform(HotkeyID.resetZoom))
        XCTAssertEqual(delegate.appearance.zoomPercent, 100)
        XCTAssertTrue(dispatcher.perform(HotkeyID.zoomIn))
        XCTAssertGreaterThan(delegate.appearance.zoomPercent, 100)
        XCTAssertTrue(dispatcher.perform(HotkeyID.resetZoom))
        XCTAssertTrue(dispatcher.perform(HotkeyID.zoomOut))
        XCTAssertLessThan(delegate.appearance.zoomPercent, 100)
        delegate.appearance.zoomPercent = zoom

        // Courier ▸ Search… and Command Bar…: the panels MainWindow overlays.
        XCTAssertTrue(dispatcher.perform("Search"))
        XCTAssertNotEqual(delegate.search.phase, .closed)
        delegate.search.close()
        XCTAssertTrue(dispatcher.perform(HotkeyID.commandBar))
        XCTAssertTrue(delegate.commandBar.isPresented)
        delegate.commandBar.close()

        // Courier ▸ Focus Courier: the main window is asked for (opened again if it was closed).
        let opened = app.mainWindowOpened()
        XCTAssertTrue(dispatcher.perform("Focus App"))
        XCTAssertEqual(app.mainWindowOpened(), opened + 1)
        XCTAssertTrue(dispatcher.perform("Focus App and Command Bar"))
        XCTAssertTrue(delegate.commandBar.isPresented)
        delegate.commandBar.close()

        // Help ▸ Keyboard Shortcuts: MainWindow's sheet.
        XCTAssertTrue(dispatcher.perform("Keyboard Shortcuts"))
        XCTAssertTrue(delegate.hotkeys.isShortcutsSheetPresented)
        delegate.hotkeys.isShortcutsSheetPresented = false

        // Chat ▸ Show Only Unread Chats, Filter: Drafts, Filter: All: the list's filters.
        XCTAssertTrue(dispatcher.perform("Filter: Unread"))
        XCTAssertTrue(delegate.inbox.query.filters.contains(.unread))
        XCTAssertTrue(dispatcher.perform("Filter: Drafts"))
        XCTAssertTrue(delegate.inbox.query.filters.contains(.drafts))
        XCTAssertTrue(dispatcher.perform("Filter: All"))
        XCTAssertTrue(delegate.inbox.query.filters.isEmpty)

        // Message ▸ Show Calendar: the calendar pane.
        delegate.conversation.toggleCalendar()
        XCTAssertTrue(delegate.conversation.isShowingCalendar)
        delegate.conversation.toggleCalendar()
        XCTAssertFalse(delegate.conversation.isShowingCalendar)
    }

    /// View ▸ Hide Sidebar hides the chat list's column, and Show Sidebar brings it back. Drawn, not assumed: the
    /// sidebar is painted a colour the detail is not, and the test looks for it at the window's left edge.
    func testHideSidebarHidesTheChatListColumn() throws {
        let app = try makeApp()
        let coordinator = app.delegate.menuCoordinator
        func sidebarShows() throws -> Bool {
            let view = SidebarSplitView(sidebarState: coordinator) {
                Color(red: 1, green: 0, blue: 0).frame(minWidth: 200)
            } detail: {
                Color(red: 0, green: 0, blue: 1)
            }
            let size = NSSize(width: 800, height: 400)
            let host = NSHostingView(rootView: view.frame(width: size.width, height: size.height))
            let window = NSWindow(contentRect: NSRect(origin: .zero, size: size), styleMask: [.titled],
                                  backing: .buffered, defer: false)
            window.contentView = host
            host.frame = NSRect(origin: .zero, size: size)
            for _ in 0 ..< 25 {
                RunLoop.main.run(mode: .default, before: Date(timeIntervalSinceNow: 0.004))
                host.layoutSubtreeIfNeeded()
            }
            window.displayIfNeeded()
            let bitmap = try XCTUnwrap(host.bitmapImageRepForCachingDisplay(in: host.bounds))
            host.cacheDisplay(in: host.bounds, to: bitmap)
            window.contentView = nil
            let sample = try XCTUnwrap(bitmap.colorAt(x: bitmap.pixelsWide / 16, y: bitmap.pixelsHigh / 2))
                .usingColorSpace(.sRGB)
            let color = try XCTUnwrap(sample)
            return color.redComponent > 0.6 && color.blueComponent < 0.4
        }
        XCTAssertTrue(try sidebarShows(), "the chat list should show at first")
        XCTAssertTrue(app.delegate.hotkeyDispatcher.perform("Toggle Sidebar"))
        XCTAssertFalse(try sidebarShows(), "Hide Sidebar did not hide the chat list")
        XCTAssertTrue(app.delegate.hotkeyDispatcher.perform("Toggle Sidebar"))
        XCTAssertTrue(try sidebarShows(), "Show Sidebar did not bring the chat list back")
    }
}
