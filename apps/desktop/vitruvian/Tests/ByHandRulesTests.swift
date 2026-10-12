// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 VitruvianSoftware

import Foundation

/// The choices the by-hand command (`Tools/ByHand.swift`) makes before it
/// presses anything in the running app. The command itself is never run by
/// a test: it drives the person's own app. These hold the lessons of doing
/// the checks by hand, over plain text.
enum ByHandRulesTests {
    typealias Names = ByHandRules.Names

    static func run(_ suite: TestSuite) {
        pressing(suite)
        rows(suite)
        results(suite)
        messages(suite)
        commandLine(suite)
    }

    static func pressing(_ suite: TestSuite) {
        // The Features page, with a sheet open over it.
        let controls = [
            Names(title: "Remove Background", description: "switch"),
            Names(description: "Remove"),
            Names(title: "Cancel"),
            Names(title: "Remove, Keep What It Saved"),
            Names(title: "Remove"),
            Names(title: "Cancel"),
        ]
        suite.expect(ByHandRules.exact("Remove", among: controls) == 4,
                     "a control is pressed by its exact name, and of several with that name the last, "
                         + "because a sheet's controls come after its window's")
        suite.expect(ByHandRules.exact("Remove Back", among: controls) == nil
                         && ByHandRules.exact("remove", among: controls) == nil
                         && ByHandRules.exact("Keep What It Saved", among: controls) == nil,
                     "a name that is only part of a control's name, or differs in case, presses nothing: "
                         + "a loose match once turned an unrelated feature off")
        suite.expect(ByHandRules.exact("switch", among: controls) == 0
                         && ByHandRules.exact("", among: controls + [Names()]) == nil
                         && ByHandRules.exact("Remove", among: []) == nil,
                     "a control may be named by its description; no name presses nothing, not the control "
                         + "that has none")
    }

    static func rows(_ suite: TestSuite) {
        let labels = ["Deploys. Example 0.1.0", "Deploys Pro. Example 2.0.0. Running", "Never, by hand. Example 0.1.0",
                      "Hello"]
        suite.expect(ByHandRules.toolRows("Deploys", among: labels) == [0]
                         && ByHandRules.toolRows("Deploys Pro", among: labels) == [1]
                         && ByHandRules.toolRows("Hello", among: labels) == [3]
                         && ByHandRules.toolRows("Never, by hand", among: labels) == [2],
                     "a tool's row is the one whose label is its name, or its name and then a full stop: "
                         + "a tool whose name starts with another's is not that tool")
        suite.expect(ByHandRules.toolRows("Dep", among: labels).isEmpty
                         && ByHandRules.toolRows("Example", among: labels).isEmpty
                         && ByHandRules.toolRows("", among: labels).isEmpty
                         && ByHandRules.toolRows("Deploys", among: labels + ["Deploys. Other 9.9.9"]) == [0, 4],
                     "part of a name finds no row, and two tools of one name are both found, so the "
                         + "command can refuse to guess")
    }

    static func results(_ suite: TestSuite) {
        let shown = ["Say hello from Swift twice, Hello Twice", "Say hello from Swift, Hello, in Swift",
                     "Say hello, Hello, in Python", "Settings"]
        suite.expect(ByHandRules.resultRow("Say hello from Swift", among: shown) == 1
                         && ByHandRules.resultRow("Say hello", among: shown) == 2
                         && ByHandRules.resultRow("Settings", among: shown) == 3,
                     "a command is the result that IS its title, wherever it stands: Return runs the top "
                         + "result, and the top result is often a longer title that starts the same")
        suite.expect(ByHandRules.resultRow("Say hello from", among: shown) == nil
                         && ByHandRules.resultRow("Hello, in Swift", among: shown) == nil
                         && ByHandRules.resultRow("", among: shown) == nil
                         && ByHandRules.resultRow("Say hello", among: []) == nil,
                     "a command the bar does not offer has no row, so nothing is run in its place: not a "
                         + "result that starts with its words, and not one filed under them")
        suite.expect(ByHandRules.resultRow("Say hello", among: shown + ["Say hello, Other tool"]) == 2,
                     "of two results with one title the first is taken, as the bar orders them")
    }

    static func messages(_ suite: TestSuite) {
        let looks = [["Menu", "Hello from Swift"], ["Hello from Swift", "Menu"], ["Menu"], ["Menu", "Copied"], []]
        let seen = ByHandRules.mostSeen(in: looks)
        suite.expect(seen.map(\.text) == ["Menu", "Hello from Swift", "Copied"] && seen.map(\.times) == [4, 2, 1]
                         && ByHandRules.mostSeen(in: looks, limit: 1).map(\.text) == ["Menu"]
                         && ByHandRules.mostSeen(in: [["b", "a"], ["a", "b"], [""]]).map(\.text) == ["b", "a"]
                         && ByHandRules.mostSeen(in: []).isEmpty,
                     "the on-screen message is read as the texts seen most often over a few looks, the most "
                         + "seen first and of two seen as often the one seen first; an empty text is none")
    }

    static func commandLine(_ suite: TestSuite) {
        func parse(_ line: String) -> ByHandRules.Command? {
            ByHandRules.parse(line.split(separator: " ").map(String.init))
        }
        suite.expect(parse("windows") == .windows && parse("dump") == .dump(from: 0, window: nil)
                         && parse("dump --from 40 --window Settings") == .dump(from: 40, window: "Settings")
                         && parse("find Tools --window Settings") == .find("Tools", window: "Settings")
                         && parse("focused") == .focused(window: nil) && parse("message") == .message
                         && parse("scroll-end") == .scrollEnd(window: nil) && parse("select 18") == .select(18, window: nil)
                         && parse("set-value 7 0.5") == .setValue(7, "0.5", window: nil)
                         && parse("focus-field 1") == .focusField(1, window: nil)
                         && parse("open-settings") == .openSettings && parse("quit") == .quit && parse("launch") == .launch
                         && parse("tools") == .tools(lines: 10) && parse("tools --lines 3") == .tools(lines: 3),
                     "each command that looks, presses one thing, or starts and stops the app is read from "
                         + "the command line, with its window and its numbers")
        suite.expect(ByHandRules.parse(["press", "Add a Tool…"]) == .press("Add a Tool…", window: nil)
                         && ByHandRules.parse(["page", "Command Bar"]) == .page("Command Bar")
                         && ByHandRules.parse(["choose", "Language", "Français", "--window", "Settings"])
                             == .choose(menu: "Language", item: "Français", window: "Settings")
                         && ByHandRules.parse(["run-command", "Say hello from Swift"]) == .runCommand("Say hello from Swift")
                         && ByHandRules.parse(["add-tool", "/tmp/my tool"]) == .addTool(folder: "/tmp/my tool", agreeWith: nil)
                         && ByHandRules.parse(["add-tool", "/tmp/t", "--agree"]) == .addTool(folder: "/tmp/t", agreeWith: "Add Tool")
                         && ByHandRules.parse(["add-tool", "--agree-with", "Update Tool", "/tmp/t"])
                             == .addTool(folder: "/tmp/t", agreeWith: "Update Tool")
                         && ByHandRules.parse(["remove-tool", "Hello, in Swift"]) == .removeTool("Hello, in Swift", deleteData: false)
                         && ByHandRules.parse(["remove-tool", "Hello", "--delete-data"]) == .removeTool("Hello", deleteData: true),
                     "a name with spaces is one word of the command line; adding a tool agrees only when "
                         + "told to, and removing one deletes what it saved only when told to")
        let wrong = ["", "press", "press a b", "select x", "dump --from", "dump --from -1", "tools --lines 0", "frobnicate",
                     "quit now", "add-tool", "add-tool /tmp/t --agree --agree-with X", "remove-tool Hello --delete",
                     "set-value 7", "windows --window"]
        suite.expect(wrong.allSatisfy { parse($0) == nil },
                     "a command line with a word too many, a word too few, a flag it does not know or a "
                         + "number that is none is refused whole: nothing is pressed on a guess")
        suite.expect(["by-hand", "windows", "dump", "find", "focused", "message", "press", "select", "set-value",
                      "focus-field", "choose", "scroll-end", "open-settings", "page", "tools", "add-tool", "remove-tool",
                      "run-command", "quit", "launch", "Exit status"].allSatisfy { ByHandRules.usage.contains($0) },
                     "the usage text names every command, and what each exit status means")
    }
}
