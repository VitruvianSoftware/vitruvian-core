// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 VitruvianSoftware

import AppKit
import Carbon.HIToolbox
import Foundation
import VitruvianCore
import VitruvianServices

/// Paste as plain text over a clipboard, a preference suite, a hotkey, a
/// menu bar and a paste helper of its own. Nothing here registers a key,
/// asks Accessibility anything, posts a keystroke or touches the real
/// clipboard, and no test waits for a timer.
@MainActor
enum PastePlainTests {
    static let commandV = GlobalShortcut(keyCode: Int64(kVK_ANSI_V), modifiers: [.command])
    /// Option-Shift-Command-V as the Accessibility menu attributes spell it.
    static let matchStyle: (String, UInt32) = ("V", 3)

    static func run(_ suite: TestSuite) {
        runRule(suite)
        withoutTheGrant(suite)
        press(suite)
        ownShortcut(suite)
        plainText(suite)
        menuWalk(suite)
        whatTheMenuRemembers(suite)
    }

    /// What a made-up menu bar was asked.
    final class MenuLog {
        var reads = 0
        var pressed: [String] = []
        /// Whether the app accepts a press.
        var pressTakes = true
    }

    /// The feature's outside world for one test.
    final class PasteRig {
        /// The clipboard, its lane and the saved preferences.
        let clipboard = URLCleanerTests.CleanerRig()
        /// Whether macOS would give the shortcut's key.
        var keyIsGiven = true
        lazy var key = ToolPlatformTests.FakeHotkey(id: 10, accepts: { [unowned self] in self.keyIsGiven })
        /// Whether Accessibility is granted.
        var trusted = true
        var beeps = 0
        /// How many times the person was asked for Accessibility.
        var prompts = 0
        /// The app in front, and each app's menu bar.
        var frontApp: pid_t? = 501
        var menuBars: [pid_t: MenuItemProbe] = [:]
        /// The apps whose menu bar was asked for, in order.
        var menuBarsAsked: [pid_t] = []
        /// Each paste the helper was asked for, with what it is to call just
        /// before Command-V goes down and once it is up.
        var pastes: [(text: String, willPost: () -> Void, didPost: () -> Void)] = []

        func close() { clipboard.close() }

        /// Installs or removes the feature in the hub, and flips its switch.
        func set(installed: Bool, on: Bool) {
            clipboard.defaults.set(installed, forKey: AppFeature.pastePlain.availabilityKey)
            clipboard.defaults.set(on, forKey: DefaultsKey.pastePlainEnabled)
        }

        /// Saves a shortcut as the recorder in Settings does.
        func save(_ shortcut: GlobalShortcut) {
            clipboard.defaults.set(shortcut.storageValue, forKey: DefaultsKey.pastePlainShortcut)
        }

        /// The front app and its menus, as the menu walk reaches them.
        var menu: FrontAppMenu.Environment {
            FrontAppMenu.Environment(
                frontmostApp: { [unowned self] in self.frontApp },
                menuBar: { [unowned self] app in
                    self.menuBarsAsked.append(app)
                    return self.menuBars[app]
                })
        }
    }

    /// The feature over `rig`: how the app re-decides whether it runs, what
    /// the command bar's row does, and what a full uninstall does first. A
    /// press of the shortcut is `rig.key.onPress?()`.
    static func bench(_ rig: PasteRig)
        -> (tool: PastePlainService, sync: () -> Void, run: () -> Void, suspend: () -> Void) {
        let tool = PastePlainService(environment: .init(
            defaults: rig.clipboard.defaults,
            hotkey: rig.key,
            isTrusted: { rig.trusted },
            beep: { rig.beeps += 1 },
            requestAccessibility: { rig.prompts += 1 },
            clipboard: ClipboardWatcher(environment: rig.clipboard.watching),
            menu: FrontAppMenu(environment: rig.menu),
            paste: { text, willPost, didPost in rig.pastes.append((text, willPost, didPost)) }))
        return (tool, { tool.syncWithPreferences() }, { tool.performPastePlain() }, { tool.suspend() })
    }

    /// A menu element made of values. `key` is its command character and its
    /// modifier mask.
    static func item(_ name: String, key: (String, UInt32)? = nil, enabled: Bool = true, _ log: MenuLog,
                     _ children: [MenuItemProbe] = []) -> MenuItemProbe {
        MenuItemProbe(
            read: {
                log.reads += 1
                return (key?.0, key?.1, enabled)
            },
            children: { children },
            press: {
                log.pressed.append(name)
                return log.pressTakes
            })
    }

    /// A menu bar with one menu, Edit, holding `items`: bar, bar item, menu,
    /// items, as every app lays its menus out.
    static func editMenu(_ log: MenuLog, _ items: [MenuItemProbe]) -> MenuItemProbe {
        item("bar", log, [item("Edit", log, [item("menu", log, items)])])
    }

    /// Installed in the hub and switched on: the shortcut is taken. Anything
    /// else: it is not. Accessibility is not asked about.
    static func runRule(_ suite: TestSuite) {
        for installed in [false, true] {
            for on in [false, true] {
                for trusted in [false, true] {
                    let rig = PasteRig()
                    rig.set(installed: installed, on: on)
                    rig.trusted = trusted
                    let (tool, sync, _, _) = bench(rig)
                    sync()
                    let wanted = installed && on
                    suite.expect((rig.key.registered != nil) == wanted && !tool.shortcutRegistrationFailed
                                     && rig.prompts == 0 && rig.beeps == 0,
                                 "installed \(installed), switched on \(on), Accessibility \(trusted): the shortcut is "
                                     + (wanted ? "taken, and nobody is asked for anything" : "left alone"))
                    rig.close()
                }
            }
        }

        let rig = PasteRig()
        defer { rig.close() }
        rig.set(installed: true, on: true)
        let (tool, sync, _, suspend) = bench(rig)
        sync()
        suite.expect(rig.key.registered?.shortcut == .pastePlainDefault
                         && rig.key.registered?.storageKey == DefaultsKey.pastePlainShortcut,
                     "with nothing saved the shortcut is the default one, claimed under its own preference")
        sync()
        suite.expect(rig.key.registrations == 1, "deciding again while it holds its key takes no key twice")

        rig.save(commandV)
        sync()
        suite.expect(rig.key.registered?.shortcut == commandV && rig.key.registrations == 2,
                     "a shortcut recorded in Settings is the one held after the next decision")

        // Recording any shortcut releases every key the app holds
        // (`QuickToolHotkey.unregisterAll`); the decision that follows takes
        // this one back.
        rig.key.unregister()
        sync()
        suite.expect(rig.key.registered?.shortcut == commandV,
                     "a key let go for a recording comes back at the next decision")

        rig.keyIsGiven = false
        rig.save(.pastePlainDefault)
        sync()
        suite.expect(rig.key.registered == nil && tool.shortcutRegistrationFailed,
                     "a combination macOS will not give is reported, for Settings to say so")
        rig.keyIsGiven = true
        sync()
        suite.expect(rig.key.registered != nil && !tool.shortcutRegistrationFailed,
                     "and the report clears once the key is given")

        suspend()
        suite.expect(rig.key.registered == nil,
                     "a full uninstall lets go of the key at once, whatever the switches say")
        sync()
        suite.expect(rig.key.registered != nil, "and the next decision takes it back")

        rig.keyIsGiven = false
        rig.save(commandV)
        sync()
        rig.set(installed: true, on: false)
        sync()
        suite.expect(rig.key.registered == nil && !tool.shortcutRegistrationFailed,
                     "switching it off lets go of the key, and of the report")
        rig.keyIsGiven = true
        rig.set(installed: false, on: true)
        sync()
        suite.expect(rig.key.registered == nil, "removing the feature in the hub lets go of the key")
    }

    /// Never granted, granted while the app runs, taken away while it runs.
    static func withoutTheGrant(_ suite: TestSuite) {
        let rig = PasteRig()
        defer { rig.close() }
        rig.set(installed: true, on: true)
        rig.trusted = false
        rig.clipboard.copy("Plain words")
        let (_, sync, run, _) = bench(rig)
        sync()

        rig.key.onPress?()
        suite.expect(rig.prompts == 1 && rig.beeps == 0 && rig.clipboard.lane.isEmpty && rig.pastes.isEmpty
                         && rig.menuBarsAsked.isEmpty,
                     "without Accessibility the first press asks for it, once, and reads nothing")
        rig.key.onPress?()
        run()
        suite.expect(rig.prompts == 1 && rig.beeps == 2 && rig.clipboard.lane.isEmpty,
                     "every press after that only beeps, from the shortcut or from the command bar")
        sync()
        suite.expect(rig.key.registered != nil, "the shortcut stays taken while Accessibility is missing")

        // Granted in System Settings while the app runs: the very next press
        // pastes, before anything has told the app.
        rig.trusted = true
        rig.key.onPress?()
        rig.clipboard.settle()
        suite.expect(rig.pastes.map { $0.text } == ["Plain words"] && rig.prompts == 1 && rig.beeps == 2,
                     "a press pastes as soon as Accessibility is granted")
        sync()
        suite.expect(rig.key.registrations == 1, "hearing of the grant takes no key twice")

        // Taken away again while the app runs.
        rig.trusted = false
        rig.key.onPress?()
        suite.expect(rig.beeps == 3 && rig.prompts == 1 && rig.pastes.count == 1 && rig.clipboard.lane.isEmpty
                         && rig.key.registered != nil,
                     "with Accessibility taken away a press beeps: the person was asked once this launch already")
    }

    /// One press, with Accessibility granted.
    static func press(_ suite: TestSuite) {
        let rig = PasteRig()
        defer { rig.close() }
        rig.set(installed: true, on: true)
        let log = MenuLog()
        let (_, sync, run, _) = bench(rig)
        sync()

        rig.clipboard.board.clearContents()
        rig.key.onPress?()
        suite.expect(rig.clipboard.lane.count == 1,
                     "a press reads the clipboard on its lane, never on the main thread")
        rig.clipboard.settle()
        suite.expect(rig.menuBarsAsked.isEmpty && rig.pastes.isEmpty && rig.beeps == 0,
                     "an empty clipboard pastes nothing, and says nothing")
        rig.clipboard.copy("")
        rig.key.onPress?()
        rig.clipboard.settle()
        suite.expect(rig.menuBarsAsked.isEmpty && rig.pastes.isEmpty, "text of no length pastes nothing")

        // An app with its own matching-style paste.
        rig.menuBars[501] = editMenu(log, [item("Paste", key: ("V", 0), log), item("Match", key: matchStyle, log)])
        rig.clipboard.copy("Plain words")
        let count = rig.clipboard.board.changeCount
        rig.key.onPress?()
        suite.expect(log.pressed.isEmpty, "nothing is pressed until the clipboard has answered")
        rig.clipboard.settle()
        suite.expect(log.pressed == ["Match"] && rig.pastes.isEmpty && rig.clipboard.board.changeCount == count,
                     "an app with its own Paste and Match Style has that item pressed, and the clipboard is not touched")

        // An app without one.
        rig.frontApp = 502
        rig.menuBars[502] = editMenu(log, [item("Paste", key: ("V", 0), log)])
        rig.key.onPress?()
        rig.clipboard.settle()
        suite.expect(rig.pastes.map { $0.text } == ["Plain words"] && log.pressed == ["Match"],
                     "an app without one is handed the text through the paste helper")

        // An app that has the item and refuses the press.
        rig.frontApp = 501
        log.pressTakes = false
        rig.key.onPress?()
        rig.clipboard.settle()
        suite.expect(rig.pastes.count == 2, "an item the app would not press falls back to the paste helper")

        rig.frontApp = nil
        rig.key.onPress?()
        rig.clipboard.settle()
        suite.expect(rig.pastes.count == 3, "with no app in front the paste helper is still asked")

        // A copy that is only rich text.
        rig.frontApp = 502
        let rich = NSAttributedString(string: "Rich words", attributes: [.font: NSFont.boldSystemFont(ofSize: 12)])
        rig.clipboard.board.clearContents()
        rig.clipboard.board.setData(rich.rtf(from: NSRange(location: 0, length: rich.length)), forType: .rtf)
        rig.key.onPress?()
        rig.clipboard.settle()
        suite.expect(rig.pastes.count == 4 && rig.pastes.last?.text == "Rich words",
                     "a copy that is only rich text is pasted as its words")

        // The command bar's row asks only whether the feature is installed.
        rig.set(installed: true, on: false)
        sync()
        run()
        rig.clipboard.settle()
        suite.expect(rig.key.registered == nil && rig.pastes.count == 5,
                     "the command bar's row pastes while the shortcut is switched off")
    }

    /// The paste types Command-V. When Command-V is also this feature's own
    /// shortcut, the key is let go while the paste is typed.
    static func ownShortcut(_ suite: TestSuite) {
        let rig = PasteRig()
        defer { rig.close() }
        rig.set(installed: true, on: true)
        rig.clipboard.copy("Plain words")
        let (tool, sync, run, _) = bench(rig)

        sync()
        rig.key.onPress?()
        rig.clipboard.settle()
        rig.pastes[0].willPost()
        suite.expect(rig.key.registered != nil, "the default shortcut is kept while the paste is typed")
        rig.pastes[0].didPost()
        suite.expect(rig.key.registrations == 1, "and nothing is taken again after it")

        rig.save(commandV)
        sync()
        rig.key.onPress?()
        rig.clipboard.settle()
        suite.expect(rig.key.registered != nil,
                     "a shortcut saved as Command-V is held until the paste is about to be typed")
        rig.pastes[1].willPost()
        suite.expect(rig.key.registered == nil,
                     "a shortcut saved as Command-V is let go just before the paste is typed")
        rig.keyIsGiven = false
        rig.pastes[1].didPost()
        suite.expect(rig.key.registered == nil && tool.shortcutRegistrationFailed,
                     "it is asked for again once the paste is typed, and a refusal is reported")
        rig.keyIsGiven = true
        sync()
        suite.expect(rig.key.registered?.shortcut == commandV && !tool.shortcutRegistrationFailed,
                     "the next decision takes it")

        // Switched off, the command bar's row still pastes. No key is taken
        // for it, before or after.
        rig.set(installed: true, on: false)
        sync()
        run()
        rig.clipboard.settle()
        rig.pastes[2].willPost()
        rig.pastes[2].didPost()
        suite.expect(rig.key.registered == nil && !tool.shortcutRegistrationFailed,
                     "switched off, typing the paste takes no key")
    }

    /// The clipboard's text without its formatting. The HTML branch is not
    /// here: it builds a web view, which is checked by hand.
    static func plainText(_ suite: TestSuite) {
        let board = NSPasteboard.withUniqueName()
        defer { board.releaseGlobally() }
        board.clearContents()
        suite.expect(ClipboardWatcher.plainText(from: board) == nil, "an empty clipboard has no text")
        let rich = NSAttributedString(string: "Rich words", attributes: [.font: NSFont.boldSystemFont(ofSize: 12)])
        board.setData(rich.rtf(from: NSRange(location: 0, length: rich.length)), forType: .rtf)
        suite.expect(ClipboardWatcher.plainText(from: board) == "Rich words", "rich text is read as its words")
        board.setString("Plain words", forType: .string)
        suite.expect(ClipboardWatcher.plainText(from: board) == "Plain words",
                     "the plain string wins when the copy carries one")
        board.clearContents()
        board.setData(Data([0x89, 0x50, 0x4E, 0x47]), forType: .png)
        suite.expect(ClipboardWatcher.plainText(from: board) == nil, "a picture has no text")
    }

    /// The walk through an app's menus: what it presses, and where it stops.
    static func menuWalk(_ suite: TestSuite) {
        let rig = PasteRig()
        defer { rig.close() }
        let menu = FrontAppMenu(environment: rig.menu)
        let wanted = [QuickToolsSupport.matchStyleEquivalent]
        var app: pid_t = 600
        /// Presses in an app not met before, whose menu bar `build` makes.
        func walk(_ build: (MenuLog) -> MenuItemProbe) -> (pressed: Bool, log: MenuLog) {
            let log = MenuLog()
            app += 1
            rig.frontApp = app
            rig.menuBars[app] = build(log)
            return (menu.pressItem(matching: wanted), log)
        }

        var result = walk { log in
            editMenu(log, [item("Paste", key: ("V", 0), log), item("Match", key: ("v", 3), log),
                           item("Later", key: matchStyle, log)])
        }
        suite.expect(result.pressed && result.log.pressed == ["Match"] && result.log.reads == 5,
                     "the walk presses the first item with the wanted key equivalent, and reads nothing after it")

        result = walk { log in
            editMenu(log, [item("Shift", key: ("V", 1), log), item("Control", key: ("V", 7), log),
                           item("Copy", key: ("C", 3), log), item("None", log)])
        }
        suite.expect(!result.pressed && result.log.pressed.isEmpty,
                     "an item with a modifier more or less, or another letter, is another command")

        result = walk { log in
            editMenu(log, [item("Off", key: matchStyle, enabled: false, log), item("On", key: matchStyle, log)])
        }
        suite.expect(result.pressed && result.log.pressed == ["On"],
                     "a matching item that is switched off is passed over")

        result = walk { log in
            editMenu(log, [item("Submenu", log, [item("Match", key: matchStyle, log)])])
        }
        suite.expect(!result.pressed && result.log.reads == 4,
                     "an item inside a submenu is out of reach, and is not read")

        result = walk { log in
            item("bar", log, (0 ..< 700).map { index in
                item("Menu \(index)", key: index == 650 ? matchStyle : nil, log)
            })
        }
        suite.expect(!result.pressed && result.log.reads == 600, "one walk reads 600 elements and no more")
        result = walk { log in
            item("bar", log, (0 ..< 700).map { index in
                item("Menu \(index)", key: index == 100 ? matchStyle : nil, log)
            })
        }
        suite.expect(result.pressed && result.log.reads == 102, "and it stops as soon as it finds the item")

        result = walk { log in
            log.pressTakes = false
            return editMenu(log, [item("Match", key: matchStyle, log)])
        }
        suite.expect(!result.pressed && result.log.pressed == ["Match"],
                     "an item the app would not press counts as not pressed")
        suite.expect(FrontAppMenu.elementTimeout == 0.35 && FrontAppMenu.elementCap == 600
                         && FrontAppMenu.depthLimit == 3 && FrontAppMenu.rememberedApps == 64,
                     "an element gets 0.35 seconds to answer, a walk reads 600 at most and goes three levels down")
    }

    /// Apps known to have no such item are not walked at every press.
    static func whatTheMenuRemembers(_ suite: TestSuite) {
        let rig = PasteRig()
        defer { rig.close() }
        let menu = FrontAppMenu(environment: rig.menu)
        let wanted = [QuickToolsSupport.matchStyleEquivalent]
        let log = MenuLog()
        func press(in app: pid_t?, with menu: FrontAppMenu) -> Bool {
            rig.frontApp = app
            return menu.pressItem(matching: wanted)
        }

        suite.expect(!press(in: nil, with: menu) && rig.menuBarsAsked.isEmpty,
                     "with no app in front nothing is asked")
        suite.expect(!press(in: 1, with: menu) && !press(in: 1, with: menu) && rig.menuBarsAsked == [1, 1],
                     "an app that gives no menu bar is asked again the next time")

        rig.menuBars[2] = editMenu(log, [item("Paste", key: ("V", 0), log)])
        suite.expect(!press(in: 2, with: menu) && !press(in: 2, with: menu) && rig.menuBarsAsked == [1, 1, 2],
                     "an app without the item is remembered, and its menus are not walked again")
        rig.menuBars[2] = editMenu(log, [item("Match", key: matchStyle, log)])
        suite.expect(!press(in: 2, with: menu) && rig.menuBarsAsked == [1, 1, 2],
                     "even when its menus have gained the item since: it gets another chance when it is opened again")

        rig.menuBars[3] = editMenu(log, [item("Match", key: matchStyle, log)])
        suite.expect(press(in: 3, with: menu) && press(in: 3, with: menu) && rig.menuBarsAsked == [1, 1, 2, 3, 3],
                     "an app with the item is walked at every press")

        rig.frontApp = 2
        suite.expect(menu.pressItem(matching: [MenuKeyEquivalent(character: "V", modifierMask: 3)])
                         == false && rig.menuBarsAsked.count == 5,
                     "what is remembered is the app and the key equivalents asked for")
        suite.expect(!menu.pressItem(matching: [MenuKeyEquivalent(character: "Z", modifierMask: 0)])
                         && rig.menuBarsAsked.count == 6,
                     "so another command is looked for afresh")

        // Sixty-four are remembered. One more and the list starts again.
        let fresh = FrontAppMenu(environment: rig.menu)
        rig.menuBarsAsked = []
        for app in pid_t(100) ..< pid_t(164) {
            rig.menuBars[app] = editMenu(log, [])
            _ = press(in: app, with: fresh)
        }
        _ = press(in: 100, with: fresh)
        suite.expect(rig.menuBarsAsked.count == 64, "sixty-four apps without the item are remembered")
        rig.menuBars[164] = editMenu(log, [])
        _ = press(in: 164, with: fresh)
        _ = press(in: 164, with: fresh)
        _ = press(in: 100, with: fresh)
        suite.expect(rig.menuBarsAsked.count == 67 && rig.menuBarsAsked.suffix(2) == [164, 100],
                     "the sixty-fifth empties the list, itself included, and every app is walked again")
    }
}
