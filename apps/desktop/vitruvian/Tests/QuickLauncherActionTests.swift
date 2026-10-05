// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import AppKit
import Carbon.HIToolbox
import Foundation
import VitruvianCore
import VitruvianDesign
import VitruvianServices
import VitruvianUI

/// The launcher's own tile model, activation and keys, and the tile icons,
/// run over doubles for everything outside the grid: no window, tap,
/// capture or tool runs.
enum QuickLauncherContract {
    struct Key: QuickLauncherKey {
        var keyCode: UInt16
        var modifierFlags: NSEvent.ModifierFlags = []
        var inputIsComposing = false
    }

    /// Everything the launcher reaches, recording what it was asked.
    final class World {
        var events: [String] = []
        var unavailable: Set<AppFeature> = []
        /// When set, the feature switches are read from here instead.
        var defaults: UserDefaults?
        var order = QuickLauncherItem.allCases
        var cameraInIsland = false
        var jobs: [(delay: TimeInterval, work: @MainActor () -> Void)] = []

        lazy var launcher: QuickLauncherService = QuickLauncherService(environment: .init(
            isAvailable: { [unowned self] feature in
                self.defaults.map { feature.isAvailable(in: $0) } ?? !self.unavailable.contains(feature)
            },
            itemOrder: { [unowned self] in self.order },
            islandShowsTools: { true },
            collapseIsland: { [unowned self] in self.events.append("hide") },
            showCameraInIsland: { [unowned self] in
                guard self.cameraInIsland else { return false }
                self.events.append("camera in island")
                return true
            },
            perform: { [unowned self] in self.events.append("perform \($0.rawValue)") },
            after: { [unowned self] delay, work in self.jobs.append((delay, work)) }))

        func drain() {
            let pending = jobs
            jobs.removeAll()
            pending.forEach { $0.work() }
        }
    }

    static func run(_ suite: TestSuite) {
        let immediate: Set<QuickLauncherItem> = [.keepAwake, .micMute]
        let delays: [QuickLauncherItem: TimeInterval] = [
            .screenOCR: 0.15, .screenshot: 0.15, .screenRecorder: 0.15, .colorPicker: 0.15,
            .cameraPreview: 0.15, .scratchpad: 0.15, .clipboard: 0.1, .cleaning: 0.1,
        ]
        let utilities: Set<QuickLauncherItem> = [.windowLayout, .homebrew, .media, .urlCleaner, .uninstaller,
                                                 .cleaner, .toggles]
        suite.expect(immediate.union(delays.keys).union(utilities) == Set(QuickLauncherItem.allCases)
                     && immediate.isDisjoint(with: utilities) && utilities.isDisjoint(with: delays.keys),
                     "every launcher tile has one activation contract")
        let features: [QuickLauncherItem: AppFeature] = [
            .keepAwake: .keepAwake, .micMute: .micMute, .screenOCR: .screenOCR, .screenshot: .screenshot,
            .screenRecorder: .screenRecorder, .colorPicker: .colorPicker, .cameraPreview: .cameraPreview,
            .scratchpad: .scratchpad, .clipboard: .clipboardHistory, .cleaning: .cleaningMode,
            .windowLayout: .windowLayout, .homebrew: .homebrew, .media: .mediaTools, .urlCleaner: .urlCleaner,
            .uninstaller: .uninstaller, .cleaner: .cleaner, .toggles: .quickToggles,
        ]
        for item in QuickLauncherItem.allCases {
            let world = World()
            world.launcher.run(item)
            suite.expect(item.feature == features[item], "\(item) follows its own feature switch")
            let action = "perform \(item.rawValue)"
            if let delay = delays[item] {
                suite.expect(world.events == ["hide"] && world.launcher.activeUtility == nil,
                             "\(item) dismisses the launcher before any external action")
                suite.expect(world.jobs.count == 1 && world.jobs.first?.delay == delay,
                             "\(item) schedules exactly one action after dismissal")
                world.drain()
                suite.expect(world.events == ["hide", action], "\(item) executes the intended action exactly once")
            } else if immediate.contains(item) {
                suite.expect(world.events == [action] && world.jobs.isEmpty && world.launcher.activeUtility == nil,
                             "\(item) toggles immediately without dismissing or opening a utility")
            } else {
                suite.expect(world.events.isEmpty && world.jobs.isEmpty && world.launcher.activeUtility == item,
                             "\(item) opens its utility inside the launcher")
            }
            let editing = World()
            editing.launcher.isEditing = true
            editing.launcher.run(item)
            editing.drain()
            suite.expect(editing.events.isEmpty && editing.launcher.activeUtility == nil,
                         "editing \(item) never activates it")
        }
        let embedded = World()
        embedded.cameraInIsland = true
        embedded.launcher.run(.cameraPreview)
        suite.expect(embedded.events == ["camera in island", "hide"] && embedded.jobs.isEmpty,
                     "an embedded camera switches the notch before hiding the launcher, without a close-and-reopen delay")
        tiles(suite)
        presentationContracts(suite)
        compositionContracts(suite)
        keyContracts(suite)
        railContracts(suite)
    }

    private static func tiles(_ suite: TestSuite) {
        var state = QuickLauncherTileState()
        func display(_ item: QuickLauncherItem) -> (String, Bool) {
            (QuickLauncherView.icon(for: item, state: state), QuickLauncherView.isActive(item, state: state))
        }
        suite.expect(display(.screenRecorder) == ("record.circle", false), "an idle recording tile offers recording")
        state.recording = true
        suite.expect(display(.screenRecorder) == ("stop.circle", true),
                     "an active recording tile offers stopping and shows its active state")
        state = QuickLauncherTileState(keepAwake: true, micMuted: true)
        suite.expect(display(.keepAwake) == ("bolt.fill", true) && display(.micMute) == ("mic.slash.fill", true)
                     && display(.screenRecorder) == ("record.circle", false),
                     "Keep Awake and a muted microphone show their own active states")
        suite.expect(QuickLauncherItem.allCases.allSatisfy { !display($0).0.isEmpty && (!display($0).1
                         || [.keepAwake, .micMute, .screenRecorder].contains($0)) },
                     "every tile has an icon, and only tools with a state of their own look active")
    }

    private static func presentationContracts(_ suite: TestSuite) {
        let world = World()
        let launcher = world.launcher
        let oldPresentation = launcher.presentationID
        launcher.isEditing = true
        launcher.editingOptionsItem = .clipboard
        launcher.prepareForPresentation()
        suite.expect(launcher.presentationID != oldPresentation && !launcher.isEditing
                     && launcher.editingOptionsItem == nil && launcher.selectedIndex == 0,
                     "a new presentation resets edit controls and selects its first available tile")
        world.events.removeAll()
        let enter = Key(keyCode: UInt16(kVK_Return))
        suite.expect(launcher.takesPanelKey(enter) && world.events == ["perform \(world.order[0].rawValue)"],
                     "Return activates the first item immediately after presentation")
        for item in [QuickLauncherItem.urlCleaner, .homebrew, .uninstaller, .media] {
            launcher.run(item)
            launcher.prepareForPresentation()
            suite.expect(launcher.activeUtility == item,
                         "reopening preserves the working utility while its feature remains installed")
            world.unavailable.insert(item.feature)
            launcher.editingOptionsItem = item
            launcher.refreshAvailability()
            suite.expect(launcher.activeUtility == nil && launcher.editingOptionsItem == nil,
                         "removing a feature clears both its hosted utility and its edit options")
            world.unavailable.remove(item.feature)
            launcher.run(item)
            world.unavailable.insert(item.feature)
            launcher.prepareForPresentation()
            suite.expect(launcher.activeUtility == nil,
                         "a utility removed while the island was closed cannot return on reopening")
            world.events.removeAll()
            launcher.run(item)
            suite.expect(launcher.activeUtility == nil && world.events.isEmpty,
                         "a stale tile action cannot activate a removed feature")
            suite.expect(!launcher.visibleItems.contains(item), "a removed feature leaves the grid")
            world.unavailable.remove(item.feature)
        }
        world.order = []
        launcher.prepareForPresentation()
        world.events.removeAll()
        suite.expect(launcher.selectedIndex == nil && launcher.takesPanelKey(enter) && world.events.isEmpty,
                     "an empty launcher has no imaginary initial action")
    }

    /// Each Esc step, reached while a utility's field holds an input method
    /// that is still composing: none may take the key from it.
    private static func compositionContracts(_ suite: TestSuite) {
        let steps: [(name: String, open: (QuickLauncherService) -> Void, closed: (World) -> Bool)] = [
            ("the hosted utility", { $0.run(.homebrew) }, { $0.launcher.activeUtility == nil }),
            ("the options card", { $0.isEditing = true; $0.editingOptionsItem = .clipboard },
             { $0.launcher.editingOptionsItem == nil && $0.launcher.isEditing }),
            ("edit mode", { $0.isEditing = true }, { !$0.launcher.isEditing }),
            ("the launcher", { _ in }, { $0.events == ["hide"] }),
        ]
        for step in steps {
            let world = World()
            step.open(world.launcher)
            world.events.removeAll()
            suite.expect(!world.launcher.takesPanelKey(Key(keyCode: UInt16(kVK_Escape), inputIsComposing: true))
                         && !step.closed(world) && world.events.isEmpty,
                         "a composing input method keeps Esc from closing \(step.name)")
            suite.expect(world.launcher.takesPanelKey(Key(keyCode: UInt16(kVK_Escape))) && step.closed(world),
                         "Esc closes \(step.name) once composition ends")
        }
    }

    private static func keyContracts(_ suite: TestSuite) {
        let world = World()
        world.order = [.homebrew, .media, .keepAwake, .micMute]
        let launcher = world.launcher
        launcher.prepareForPresentation()
        world.events.removeAll()
        suite.expect(launcher.takesPanelKey(Key(keyCode: UInt16(kVK_ANSI_3))) && world.events == ["perform keepAwake"],
                     "a digit runs the tile in its place")
        world.events.removeAll()
        suite.expect(launcher.takesPanelKey(Key(keyCode: UInt16(kVK_ANSI_9))) && world.events.isEmpty,
                     "a digit past the last tile is taken and runs nothing")
        for modifier in [NSEvent.ModifierFlags.command, .control, .option] {
            let before = launcher.selectedIndex
            suite.expect(!launcher.takesPanelKey(Key(keyCode: UInt16(kVK_RightArrow), modifierFlags: modifier))
                         && launcher.selectedIndex == before,
                         "a key with Command, Control or Option is a shortcut, not the grid's")
        }
        let editing = World()
        editing.launcher.prepareForPresentation()
        editing.launcher.isEditing = true
        suite.expect(!editing.launcher.takesPanelKey(Key(keyCode: UInt16(kVK_Return))) && editing.events.isEmpty,
                     "the grid being edited leaves Return to its options")
        suite.expect(!launcher.takesPanelKey(Key(keyCode: UInt16(kVK_ANSI_A))),
                     "a letter goes on to the app")
    }

    /// Hover and the arrows both select, but only the arrows move the
    /// island's rail: scrolling to a hovered tile slid the next one under the
    /// pointer, and the rail kept going.
    private static func railContracts(_ suite: TestSuite) {
        let world = World()
        let launcher = world.launcher
        launcher.prepareForPresentation()
        suite.expect(launcher.keyboardIndex == 0, "a new presentation starts the rail at its first tile")
        launcher.select(launcher.visibleItems[3])
        suite.expect(launcher.selectedIndex == 3 && launcher.keyboardIndex == nil,
                     "hovering a tile selects it without scrolling the rail")
        suite.expect(launcher.takesPanelKey(Key(keyCode: UInt16(kVK_RightArrow)), flow: .columns(rows: 2))
                     && launcher.selectedIndex == 5 && launcher.keyboardIndex == 5,
                     "an arrow moves on from the hovered tile and scrolls the rail to the new one")
    }
}
