// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 VitruvianSoftware

import Foundation

/// The choices `Tools/ByHand.swift` makes before it presses anything in the
/// running app, as plain functions over text so the unit tests can hold
/// them. Each one is a lesson from doing the checks by hand on 2026-10-12.
/// Nothing here touches the app.
enum ByHandRules {
    /// A control's two names, as the Accessibility API gives them.
    struct Names: Equatable {
        var title: String
        var description: String

        init(title: String = "", description: String = "") {
            self.title = title
            self.description = description
        }
    }

    /// Which control to press for a name: one whose title or description IS
    /// the name, and of several the last, because a sheet's controls come
    /// after its window's. Never one that merely contains the name: a loose
    /// match for a button once turned an unrelated feature off.
    static func exact(_ wanted: String, among controls: [Names]) -> Int? {
        guard !wanted.isEmpty else { return nil }
        return controls.lastIndex { $0.title == wanted || $0.description == wanted }
    }

    /// Where the Extensions page starts among the controls of the Settings
    /// window, each by its value or else its title: at the page's title, the
    /// last control named `title` before its first `button`. The sidebar's
    /// row has the same name and comes earlier, so it is never taken. At the
    /// button when no title is before it; nil when the button is not there,
    /// so the page is not showing.
    static func pageStart(_ title: String, button: String, among labels: [String]) -> Int? {
        guard let at = labels.firstIndex(of: button) else { return nil }
        return labels[..<at].lastIndex(of: title) ?? at
    }

    /// The rows of the Extensions page that are one tool's. A row is labelled
    /// with the tool's name, then its badge, publisher and how it stands, joined
    /// by ". ", so the name is the whole label or everything before the
    /// first ". ". The caller presses a row only when exactly one is found.
    static func toolRows(_ name: String, among labels: [String]) -> [Int] {
        guard !name.isEmpty else { return [] }
        return labels.indices.filter { labels[$0] == name || labels[$0].hasPrefix(name + ". ") }
    }

    /// Where a command is in the command bar's results, counted from 0 at
    /// the top, or nil when the bar does not offer it. A result is described
    /// as its title, then ", " and what it is filed under. Return runs the
    /// TOP result, so the caller presses Down this many times first; the
    /// result that merely starts with the same words is not the command.
    static func resultRow(_ title: String, among descriptions: [String]) -> Int? {
        guard !title.isEmpty else { return nil }
        return descriptions.firstIndex { $0 == title || $0.hasPrefix(title + ", ") }
    }

    /// The app's short on-screen message, read as the text seen most often
    /// over a few looks: the message comes and goes, and other text is on
    /// screen with it. Each look is the texts on screen at one moment. The
    /// most seen first, at most `limit` of them; of two seen as often, the
    /// one seen first.
    static func mostSeen(in looks: [[String]], limit: Int = 3) -> [(text: String, times: Int)] {
        var times: [String: Int] = [:]
        var order: [String] = []
        for text in looks.joined() where !text.isEmpty {
            if times[text] == nil { order.append(text) }
            times[text, default: 0] += 1
        }
        let ranked = order.enumerated().sorted {
            let (a, b) = (times[$0.element] ?? 0, times[$1.element] ?? 0)
            return a != b ? a > b : $0.offset < $1.offset
        }
        return ranked.prefix(max(0, limit)).map { ($0.element, times[$0.element] ?? 0) }
    }

    /// What the app said to a press.
    enum PressAnswer: Equatable {
        case pressed
        /// The app did not answer in time (`kAXErrorCannotComplete`). A
        /// button that opens a folder picker, an alert or a sheet holds the
        /// app there, so the press that worked is answered like this. It
        /// counts as pressed; what appears next says whether it worked.
        case noAnswer
        case refused(Int32)

        var wasPressed: Bool {
            if case .refused = self { return false }
            return true
        }
    }

    static func answer(toPress error: Int32) -> PressAnswer {
        switch error {
        case 0: return .pressed
        case -25204: return .noAnswer
        default: return .refused(error)
        }
    }

    /// A control as the question "where is the keyboard?" sees it.
    struct Seen: Equatable {
        var role: String
        var isFocused: Bool

        init(_ role: String, _ isFocused: Bool) {
            self.role = role
            self.isFocused = isFocused
        }
    }

    /// The kinds of control a key acts on. Every cell and row of a list
    /// says it is focused too, by the hundred, and none is one of these.
    static let keyRoles: Set<String> = ["AXButton", "AXTextField", "AXTextArea", "AXCheckBox", "AXRadioButton",
                                        "AXPopUpButton", "AXSlider"]

    /// Which controls the keyboard is on, of all the app's in the order
    /// `dump` lists them: those a key acts on that say they are focused,
    /// and with a sheet open only the ones in the last sheet, because that
    /// is where a key goes.
    static func keyTargets(in controls: [Seen]) -> [Int] {
        let start = controls.lastIndex { $0.role == "AXSheet" } ?? 0
        return controls.indices.filter { $0 >= start && controls[$0].isFocused && keyRoles.contains(controls[$0].role) }
    }

    /// What was asked for on the command line.
    enum Command: Equatable {
        case windows
        case dump(from: Int, window: String?)
        case find(String, window: String?)
        case focused(window: String?)
        case press(String, window: String?)
        case select(Int, window: String?)
        case setValue(Int, String, window: String?)
        case focusField(Int, window: String?)
        case choose(menu: String, item: String, window: String?)
        case scrollEnd(window: String?)
        case openSettings
        case page(String)
        case tools(lines: Int)
        case addTool(folder: String, agreeWith: String?)
        case removeTool(String, deleteData: Bool)
        case runCommand(String)
        case message
        case quit
        case launch
    }

    /// The app's own English words this command presses or looks for. The
    /// checks by hand are done with the app in English.
    enum Words {
        static let settingsWindow = "Vitruvian Settings"
        static let settingsMenuItem = "Settings…"
        static let quitMenuItem = "Quit Vitruvian"
        /// The Settings page of the tools from outside, and its title.
        static let extensionsPage = "Extensions"
        static let addTool = "Add from Folder…"
        static let agreeToAdd = "Add Tool"
        static let remove = "Remove"
        static let removeKeepingData = "Remove, Keep What It Saved"
        static let removeDeletingData = "Remove and Delete What It Saved"
        static let commandBarPage = "Command Bar"
        static let openCommandBar = "Open the bar now"
        /// The title of the folder picker's window.
        static let folderPicker = "Open"
    }

    static let usage = """
        by-hand: look at, and press, the controls of the running Vitruvian app
        from the shell, to do the checks by hand of
        docs/superpowers/specs/2026-10-10-vitruvian-external-tools-design.md.

          bazel run --config=macos-app //apps/desktop/vitruvian:by-hand -- <command>

        It drives the app that is running, the person's own: say so before you
        start. It finds the app by its bundle id, needs the terminal it runs
        in to have Accessibility already, and never asks for, grants or
        changes a permission. The app must be in English.

        Look (changes nothing):
          windows                       the app's windows
          dump [--from N] [--window W]  every control: number, kind, names, value
          find TEXT [--window W]        the controls whose names or value hold TEXT
          focused [--window W]          the control the keyboard is on: a button,
                                        field, switch, pop-up or slider, and
                                        with a sheet open, one in the sheet
          message                       the short on-screen message, watched for 2 s

        Press one thing:
          press NAME [--window W]       the button or switch named exactly NAME;
                                        of several, the last: a sheet's come last
          select N [--window W]         select the row numbered N in `dump`
          set-value N VALUE [--window W]
                                        set control N to a number or a text
          focus-field N [--window W]    put the keyboard on field N of the last sheet
          choose MENU ITEM [--window W] open the pop-up described MENU, pick ITEM
          scroll-end [--window W]       scroll every list to its end

        Do one step of a check (these send keys, and only while Vitruvian is
        the app the keyboard is on):
          open-settings                 Settings…, from the app's menu
          page TITLE                    the Settings page with that sidebar title
          tools [--lines N]             the Extensions page, from its title: Add
                                        from Folder…, the Installed rows and
                                        the catalog's
          add-tool FOLDER [--agree | --agree-with BUTTON]
                                        Add from Folder…, pick FOLDER (its path is
                                        typed as it is, spaces and all), and
                                        leave the sheet open, saying where the
                                        keyboard is; with --agree press
                                        "Add Tool" on the sheet too
          remove-tool NAME [--delete-data]
                                        open the tool's row, Remove, and keep
                                        or delete what it saved
          run-command TITLE             open Settings on Command Bar, open the
                                        bar, type TITLE, move to the row that
                                        IS that command, Return, close the bar
          quit | launch                 quit the app from its menu; start it again

        W is part of a window's title. Exit status: 0 done; 1 not found, not
        offered, or the app refused; 2 Vitruvian is not running; 3 this
        terminal has no Accessibility; 64 the command line is wrong.
        """

    /// Reads the command line, without the program's own name. Nil when it
    /// is not one of the commands above, or has a word too many or too few.
    static func parse(_ arguments: [String]) -> Command? {
        var words = arguments
        guard !words.isEmpty else { return nil }
        let name = words.removeFirst()

        /// Takes `--flag VALUE` out of the words. Nil when it is not there;
        /// a flag with no value leaves a word behind, which fails the count.
        func value(of flag: String) -> String? {
            guard let at = words.firstIndex(of: flag), at + 1 < words.count else { return nil }
            defer { words.removeSubrange(at...at + 1) }
            return words[at + 1]
        }
        func has(_ flag: String) -> Bool {
            guard let at = words.firstIndex(of: flag) else { return false }
            words.remove(at: at)
            return true
        }
        /// The command, when exactly `count` plain words are left.
        func with(_ count: Int, _ make: ([String]) -> Command?) -> Command? {
            guard words.count == count, !words.contains(where: { $0.hasPrefix("--") }) else { return nil }
            return make(words)
        }

        switch name {
        case "windows": return with(0) { _ in .windows }
        case "dump":
            let from = value(of: "--from")
            let window = value(of: "--window")
            guard let start = Int(from ?? "0"), start >= 0 else { return nil }
            return with(0) { _ in .dump(from: start, window: window) }
        case "find":
            let window = value(of: "--window")
            return with(1) { .find($0[0], window: window) }
        case "focused":
            let window = value(of: "--window")
            return with(0) { _ in .focused(window: window) }
        case "press":
            let window = value(of: "--window")
            return with(1) { .press($0[0], window: window) }
        case "select":
            let window = value(of: "--window")
            return with(1) { words in Int(words[0]).map { Command.select($0, window: window) } }
        case "set-value":
            let window = value(of: "--window")
            return with(2) { words in Int(words[0]).map { Command.setValue($0, words[1], window: window) } }
        case "focus-field":
            let window = value(of: "--window")
            return with(1) { words in Int(words[0]).map { Command.focusField($0, window: window) } }
        case "choose":
            let window = value(of: "--window")
            return with(2) { .choose(menu: $0[0], item: $0[1], window: window) }
        case "scroll-end":
            let window = value(of: "--window")
            return with(0) { _ in .scrollEnd(window: window) }
        case "open-settings": return with(0) { _ in .openSettings }
        case "page": return with(1) { .page($0[0]) }
        case "tools":
            guard let lines = Int(value(of: "--lines") ?? "10"), lines > 0 else { return nil }
            return with(0) { _ in .tools(lines: lines) }
        case "add-tool":
            let named = value(of: "--agree-with")
            let agree = has("--agree")
            guard !(agree && named != nil) else { return nil }
            return with(1) { .addTool(folder: $0[0], agreeWith: named ?? (agree ? Words.agreeToAdd : nil)) }
        case "remove-tool":
            let delete = has("--delete-data")
            return with(1) { .removeTool($0[0], deleteData: delete) }
        case "run-command": return with(1) { .runCommand($0[0]) }
        case "message": return with(0) { _ in .message }
        case "quit": return with(0) { _ in .quit }
        case "launch": return with(0) { _ in .launch }
        default: return nil
        }
    }
}
