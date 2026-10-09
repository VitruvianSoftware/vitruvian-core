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
        commandTileContracts(suite)
    }

    /// A launcher over doubles that also holds one registry command.
    final class TileWorld {
        var events: [String] = []
        var unavailable: Set<AppFeature> = []
        var saved: [String] = []
        var commands: [CommandDescriptor] = []
        var runnable = true
        var jobs: [(delay: TimeInterval, work: @MainActor () -> Void)] = []

        lazy var launcher: QuickLauncherService = QuickLauncherService(environment: .init(
            isAvailable: { [unowned self] in !self.unavailable.contains($0) },
            itemOrder: { [.keepAwake, .screenshot] },
            islandShowsTools: { false },
            collapseIsland: {},
            showCameraInIsland: { false },
            perform: { [unowned self] in self.events.append("perform \($0.rawValue)") },
            after: { [unowned self] delay, work in self.jobs.append((delay, work)) },
            savedTileOrder: { [unowned self] in self.saved },
            saveTileOrder: { [unowned self] in self.saved = $0 },
            commands: { [unowned self] in self.commands },
            canRunCommand: { [unowned self] _ in self.runnable },
            runCommand: { [unowned self] in self.events.append("command \($0.rawValue)") }))

        func drain() {
            let pending = jobs
            jobs.removeAll()
            pending.forEach { $0.work() }
        }
    }

    static func commandTileContracts(_ suite: TestSuite) {
        let hello = CommandID("dev.vitruvian.sample/hello")!
        let descriptor = CommandDescriptor(id: hello, title: "Say hello", symbol: "hand.wave", surfaces: [.quickPanel])!

        let plain = TileWorld()
        suite.expect(plain.launcher.visibleTiles == [.builtin(.keepAwake), .builtin(.screenshot)]
                         && plain.launcher.visibleItems == [.keepAwake, .screenshot],
                     "with no command offered, the panel holds exactly its own tiles")

        let world = TileWorld()
        world.commands = [descriptor]
        let launcher = world.launcher
        suite.expect(launcher.visibleTiles == [.builtin(.keepAwake), .builtin(.screenshot), .command(hello)],
                     "a command tile joins after the tiles a saved order names")
        suite.expect(launcher.visibleItems == [.keepAwake, .screenshot],
                     "the built-in tiles are still listed on their own")

        world.saved = ["dev.vitruvian.sample/hello", "screenshot", "keepAwake"]
        suite.expect(launcher.visibleTiles == [.command(hello), .builtin(.screenshot), .builtin(.keepAwake)],
                     "a saved order places a command tile among the others")

        launcher.prepareForPresentation()
        launcher.run(.command(hello))
        suite.expect(world.events.isEmpty && world.jobs.count == 1 && world.jobs[0].delay == 0.15,
                     "a command tile runs after the panel has had time to go")
        world.drain()
        suite.expect(world.events == ["command dev.vitruvian.sample/hello"], "a command tile runs its command once")

        world.events = []
        world.runnable = false
        launcher.run(.command(hello))
        world.drain()
        suite.expect(world.events.isEmpty, "a command tile whose command cannot run does nothing")
        world.runnable = true

        launcher.isEditing = true
        launcher.run(.command(hello))
        world.drain()
        suite.expect(world.events.isEmpty, "a command tile does nothing in edit mode")
        launcher.isEditing = false

        // Digit 1 is the first tile, whatever kind it is.
        launcher.prepareForPresentation()
        launcher.activate(at: 0)
        world.drain()
        suite.expect(world.events == ["command dev.vitruvian.sample/hello"], "the first tile answers to its place, whatever it is")
        world.events = []

        // Reordering saves the tiles showing, and keeps what is not showing.
        world.saved = ["keepAwake", "com.acme.gone/open", "dev.vitruvian.sample/hello", "screenshot"]
        launcher.tileOrderBinding.wrappedValue = [.builtin(.screenshot), .command(hello), .builtin(.keepAwake)]
        suite.expect(world.saved == ["screenshot", "com.acme.gone/open", "dev.vitruvian.sample/hello", "keepAwake"],
                     "reordering keeps the place of a tile that is not showing now")

        // Hiding and showing a command tile.
        launcher.setHidden(.command(hello), true)
        suite.expect(!launcher.visibleTiles.contains(.command(hello)) && launcher.hiddenTiles == [.command(hello)],
                     "a hidden command tile leaves the grid and waits in the tray")
        launcher.setHidden(.command(hello), false)
        suite.expect(launcher.visibleTiles.contains(.command(hello)) && launcher.hiddenTiles.isEmpty,
                     "a command tile shown again returns to the grid")

        // The command goes away while the panel is up.
        launcher.prepareForPresentation()
        launcher.select(.command(hello))
        world.commands = []
        launcher.refreshAvailability()
        suite.expect(!launcher.visibleTiles.contains(.command(hello))
                         && (launcher.selectedIndex ?? 0) < launcher.visibleTiles.count,
                     "a command that goes away takes its tile, and the selection stays inside the grid")

        savedBuiltinOrderContracts(suite)
    }

    /// What a person already has stored: only the app's own tile ids, as
    /// they were saved before command tiles existed. The panel must show them
    /// in the order the old code showed them, through the same storage the
    /// live launcher reads.
    private static func savedBuiltinOrderContracts(_ suite: TestSuite) {
        let key = DefaultsKey.quickLauncherItemOrder
        let defaults = UserDefaults.standard
        let before = defaults.object(forKey: key)
        defer { if let before { defaults.set(before, forKey: key) } else { defaults.removeObject(forKey: key) } }

        for stored in ["screenRecorder,keepAwake,cleaner",
                       "scratchpad,not-a-tile,media,keepAwake",
                       "",
                       QuickLauncherItem.allCases.reversed().map(\.rawValue).joined(separator: ",")] {
            defaults.set(stored, forKey: key)
            let launcher = QuickLauncherService(environment: .init(
                isAvailable: { _ in true },
                itemOrder: { PanelLayout.itemOrder(QuickLauncherItem.self, key: key) },
                islandShowsTools: { false },
                collapseIsland: {},
                showCameraInIsland: { false },
                perform: { _ in },
                after: { _, _ in },
                savedTileOrder: { PanelLayout.rawItemOrder(key: key) },
                saveTileOrder: { PanelLayout.setRawItemOrder($0, key: key) }))
            let expected = PanelLayout.itemOrder(QuickLauncherItem.self, key: key)
            suite.expect(launcher.visibleTiles == expected.map(QuickLauncherTile.builtin)
                             && launcher.visibleItems == expected,
                         "a stored order of the app's own tiles shows in the same order as before (\(stored))")
        }

        // And one spelled out, so the check does not lean on the same code twice.
        defaults.set("screenRecorder,keepAwake,cleaner", forKey: key)
        let spelled = QuickLauncherService(environment: .init(
            isAvailable: { _ in true },
            itemOrder: { PanelLayout.itemOrder(QuickLauncherItem.self, key: key) },
            islandShowsTools: { false },
            collapseIsland: {},
            showCameraInIsland: { false },
            perform: { _ in },
            after: { _, _ in },
            savedTileOrder: { PanelLayout.rawItemOrder(key: key) },
            saveTileOrder: { PanelLayout.setRawItemOrder($0, key: key) }))
        suite.expect(Array(spelled.visibleItems.prefix(3)) == [.screenRecorder, .keepAwake, .cleaner]
                         && spelled.visibleItems.count == QuickLauncherItem.allCases.count,
                     "a stored order puts its tiles first, and the tiles it does not name after them")
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
