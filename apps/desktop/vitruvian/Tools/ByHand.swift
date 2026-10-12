// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 VitruvianSoftware

// Looks at, and presses, the controls of the running Vitruvian app from the
// shell, through the macOS Accessibility API. It is how the checks by hand
// of the tools-from-outside work were done on 2026-10-12, kept as one
// command. AGENTS.md, "Checking the app by hand, from the shell", says how
// to use it; `ByHandRules.usage` is what it prints.
//
//   bazel run --config=macos-app //apps/desktop/vitruvian:by-hand -- <command>
//
// A development tool: `manual`, in no bundle and no release. It links
// nothing of the app and finds the app by its bundle id. It never asks for,
// grants or changes a permission: the terminal that runs it must have
// Accessibility already. The choices it makes before it presses anything
// are in `ByHandRules.swift`, which the unit tests hold; nothing here is run
// by a test, because it drives the person's own app.

import AppKit
import ApplicationServices

let bundleID = "com.vitruviansoftware.vitruvian"
typealias Words = ByHandRules.Words

enum Exit: Int32 {
    case done = 0
    case notFound = 1
    case notRunning = 2
    case noAccessibility = 3
    case usage = 64
}

/// Written at once, like `stop`'s line: through a pipe `print` holds its
/// lines back, and a failure then reads as if it came before what led to it.
func say(_ text: String) { FileHandle.standardOutput.write(Data((text + "\n").utf8)) }

func stop(_ status: Exit, _ text: String) -> Never {
    FileHandle.standardError.write(Data((text + "\n").utf8))
    exit(status.rawValue)
}

/// Waits without stopping the run loop, so what AppKit knows stays current.
func pause(_ seconds: TimeInterval) {
    RunLoop.current.run(until: Date().addingTimeInterval(seconds))
}

/// Looks every quarter second until something is there, for at most this
/// long. False when it never was.
func appears(within seconds: TimeInterval = 3, _ isThere: () -> Bool) -> Bool {
    let end = Date().addingTimeInterval(seconds)
    while !isThere() {
        guard Date() < end else { return false }
        pause(0.25)
    }
    return true
}

// MARK: - The app

func runningApp() -> NSRunningApplication? {
    NSRunningApplication.runningApplications(withBundleIdentifier: bundleID).first
}

/// The running app, or the end of the command.
func theApp() -> (process: NSRunningApplication, element: AXUIElement) {
    guard let app = runningApp() else { stop(.notRunning, "Vitruvian (\(bundleID)) is not running.") }
    // Asked, never prompted for: this command changes no permission.
    guard AXIsProcessTrusted() else {
        stop(.noAccessibility, "The terminal running this has no Accessibility permission. Nothing was done.")
    }
    return (app, AXUIElementCreateApplication(app.processIdentifier))
}

// MARK: - Reading controls

func attribute(_ element: AXUIElement, _ name: String) -> AnyObject? {
    var value: AnyObject?
    return AXUIElementCopyAttributeValue(element, name as CFString, &value) == .success ? value : nil
}

func text(_ element: AXUIElement, _ name: String) -> String {
    switch attribute(element, name) {
    case let string as String: return string
    case let number as NSNumber: return number.stringValue
    default: return ""
    }
}

func elements(_ element: AXUIElement, _ name: String) -> [AXUIElement] {
    (attribute(element, name) as? [AXUIElement]) ?? []
}

/// One control, with what the commands ask of it read once.
struct Control {
    let element: AXUIElement
    let role: String
    let subrole: String
    let title: String
    let value: String
    let description: String

    init(_ element: AXUIElement) {
        self.element = element
        role = text(element, kAXRoleAttribute)
        subrole = text(element, kAXSubroleAttribute)
        title = text(element, kAXTitleAttribute)
        value = text(element, kAXValueAttribute)
        description = text(element, kAXDescriptionAttribute)
    }

    var names: ByHandRules.Names { .init(title: title, description: description) }
    var isEnabled: Bool { (attribute(element, kAXEnabledAttribute) as? Bool) ?? true }
    var isFocused: Bool { (attribute(element, kAXFocusedAttribute) as? Bool) ?? false }
    /// A group, a scroll bar or the like that says nothing: left out of lists.
    var isSilent: Bool {
        ["AXGroup", "AXScrollBar", "AXValueIndicator", "AXSplitter"].contains(role)
            && title.isEmpty && value.isEmpty && description.isEmpty
    }

    /// One line for a list: its kind, its names and its value.
    var line: String {
        func short(_ text: String, _ limit: Int) -> String {
            String(text.prefix(limit)).replacingOccurrences(of: "\n", with: "⏎")
        }
        var line = subrole.isEmpty ? role : "\(role)/\(subrole)"
        if !title.isEmpty { line += " t=\(short(title, 160))" }
        if !value.isEmpty { line += " v=\(short(value, 200))" }
        if !description.isEmpty { line += " d=\(short(description, 160))" }
        if !isEnabled { line += " DISABLED" }
        if isFocused { line += " FOCUSED" }
        return line
    }
}

/// Every control under a window, the window first, a sheet's after its
/// window's own: so of two controls with one name the last is the sheet's.
func controls(under root: AXUIElement) -> [Control] {
    var found: [Control] = []
    func walk(_ element: AXUIElement, _ depth: Int) {
        guard depth <= 40 else { return }
        found.append(Control(element))
        var children = elements(element, kAXChildrenAttribute)
        for sheet in elements(element, "AXSheets") where !children.contains(where: { CFEqual($0, sheet) }) {
            children.append(sheet)
        }
        for child in children { walk(child, depth + 1) }
    }
    walk(root, 0)
    return found
}

func windows(of app: AXUIElement, titled part: String? = nil, except: String? = nil) -> [AXUIElement] {
    elements(app, kAXWindowsAttribute).filter { window in
        let title = text(window, kAXTitleAttribute)
        if let except, title.contains(except) { return false }
        guard let part, !part.isEmpty else { return true }
        return title.localizedCaseInsensitiveContains(part)
    }
}

/// The controls of the app's windows, numbered as `dump` numbers them.
func controls(of app: AXUIElement, window: String?) -> [Control] {
    windows(of: app, titled: window).flatMap(controls(under:))
}

let pressable = ["AXButton", "AXCheckBox", "AXRadioButton", "AXSwitch", "AXDisclosureTriangle", "AXMenuItem"]

// MARK: - Acting through Accessibility

@discardableResult
func press(_ control: Control) -> ByHandRules.PressAnswer {
    ByHandRules.answer(toPress: AXUIElementPerformAction(control.element, kAXPressAction as CFString).rawValue)
}

/// Presses the control with exactly this name, the last of several, or ends
/// the command when there is none or the app refused. It says one line,
/// after the press, and it is true: a press the app did not answer in time
/// is a press, and the caller looks for what it was to open.
func mustPress(_ name: String, in app: AXUIElement, window: String? = Words.settingsWindow) {
    let candidates = controls(of: app, window: window).filter { pressable.contains($0.role) }
    guard let at = ByHandRules.exact(name, among: candidates.map(\.names)) else {
        stop(.notFound, "No button or switch is named exactly \"\(name)\". Nothing was pressed.")
    }
    let matches = candidates.filter { $0.title == name || $0.description == name }.count
    let which = matches == 1 ? "" : " (the last of \(matches) with that name)"
    switch press(candidates[at]) {
    case .pressed:
        say("pressed \"\(name)\"\(which)")
    case .noAnswer:
        say("pressed \"\(name)\"\(which); the app did not answer in time, as when a press opens a panel")
    case .refused(let error):
        stop(.notFound, "\"\(name)\" was found and the app refused the press (error \(error)).")
    }
}

/// Ends the command when what a press was to open is not there in time,
/// saying what was pressed and what was not seen.
func expect(_ what: String, after pressed: String, in step: String, within seconds: TimeInterval = 3,
            _ isThere: () -> Bool) {
    guard appears(within: seconds, isThere) else {
        stop(.notFound, "\(step): pressed \"\(pressed)\", but \(what) appeared within \(Int(seconds)) s.")
    }
}

func hasButton(_ name: String, in app: AXUIElement) -> Bool {
    controls(of: app, window: Words.settingsWindow).contains {
        pressable.contains($0.role) && ($0.title == name || $0.description == name)
    }
}

/// The folder picker is a window of its own, a dialog titled "Open".
func folderPickerIsOpen(_ app: AXUIElement) -> Bool {
    elements(app, kAXWindowsAttribute).contains {
        text($0, kAXSubroleAttribute) == "AXDialog" || text($0, kAXTitleAttribute) == Words.folderPicker
    }
}

/// The controls the keyboard is on, numbered as `dump` numbers them.
func keyTargets(in app: AXUIElement, window: String?) -> [(number: Int, control: Control)] {
    let all = controls(of: app, window: window)
    return ByHandRules.keyTargets(in: all.map { .init($0.role, $0.isFocused) }).map { ($0, all[$0]) }
}

func scrollToEnd(in app: AXUIElement, window: String?) {
    for control in controls(of: app, window: window)
    where control.role == "AXScrollBar" && text(control.element, kAXOrientationAttribute) == "AXVerticalOrientation" {
        AXUIElementSetAttributeValue(control.element, kAXValueAttribute as CFString, NSNumber(value: 1.0))
    }
}

/// The app's own menu, wherever macOS hangs it: the menu bar, or the extras.
func pressMenuItem(_ title: String, of app: AXUIElement) -> Bool {
    for bar in [kAXMenuBarAttribute, "AXExtrasMenuBar"] {
        guard let menus = attribute(app, bar) else { continue }
        let items = controls(under: menus as! AXUIElement).filter { $0.role == "AXMenuItem" && $0.title == title }
        if let item = items.last, press(item).wasPressed { return true }
    }
    return false
}

/// Selects the Settings page with this title in the sidebar: the one row
/// that holds exactly that text. False when there is none, or several.
func selectPage(_ title: String, in app: AXUIElement) -> Bool {
    let rows = windows(of: app, titled: Words.settingsWindow).flatMap(controls(under:)).filter { $0.role == "AXRow" }
    let holding = rows.filter { row in
        controls(under: row.element).contains { $0.title == title || $0.value == title || $0.description == title }
    }
    guard holding.count == 1 else {
        say("page \"\(title)\": \(holding.count) rows hold exactly that text; one is needed")
        return false
    }
    return AXUIElementSetAttributeValue(holding[0].element, kAXSelectedAttribute as CFString, kCFBooleanTrue) == .success
}

// MARK: - Keys

/// True when Vitruvian is the app the keyboard is on.
func keyboardIsOnTheApp(_ process: NSRunningApplication) -> Bool {
    guard let focused = attribute(AXUIElementCreateSystemWide(), kAXFocusedApplicationAttribute) else { return false }
    var pid: pid_t = 0
    return AXUIElementGetPid(focused as! AXUIElement, &pid) == .success && pid == process.processIdentifier
}

/// Brings the app forward and waits for the keyboard to be on it. Keys go
/// to whichever app is in front, so no key is sent until it is this one:
/// otherwise the command ends, with nothing typed anywhere.
func bringForward(_ app: (process: NSRunningApplication, element: AXUIElement)) {
    AXUIElementSetAttributeValue(app.element, kAXFrontmostAttribute as CFString, kCFBooleanTrue)
    for _ in 0..<20 where !keyboardIsOnTheApp(app.process) { pause(0.1) }
    guard keyboardIsOnTheApp(app.process) else {
        stop(.notFound, "Vitruvian did not come to the front, so no key was sent.")
    }
}

enum Key: CGKeyCode {
    case `return` = 36
    case escape = 53
    case down = 125
    case g = 5
}

func send(_ key: Key, with flags: CGEventFlags = [], to app: (process: NSRunningApplication, element: AXUIElement)) {
    bringForward(app)
    for down in [true, false] {
        let event = CGEvent(keyboardEventSource: nil, virtualKey: key.rawValue, keyDown: down)
        event?.flags = flags
        event?.post(tap: .cghidEventTap)
    }
    pause(0.05)
}

func type(_ text: String, to app: (process: NSRunningApplication, element: AXUIElement)) {
    bringForward(app)
    for character in text {
        let units = Array(String(character).utf16)
        for down in [true, false] {
            let event = CGEvent(keyboardEventSource: nil, virtualKey: 0, keyDown: down)
            event?.keyboardSetUnicodeString(stringLength: units.count, unicodeString: units)
            event?.post(tap: .cghidEventTap)
        }
        pause(0.01)
    }
}

// MARK: - Steps of a check

/// The texts on screen outside the Settings window, where the app's short
/// message is drawn.
func textsOutsideSettings(_ app: AXUIElement) -> [String] {
    windows(of: app, except: Words.settingsWindow).flatMap(controls(under:))
        .filter { $0.role == "AXStaticText" }.map { String($0.value.prefix(200)) }
}

func watchMessage(_ app: AXUIElement) {
    var looks: [[String]] = []
    for _ in 0..<8 {
        looks.append(textsOutsideSettings(app))
        pause(0.25)
    }
    let seen = ByHandRules.mostSeen(in: looks)
    if seen.isEmpty { say("message: none seen in 2 seconds") }
    for (text, times) in seen { say("message: \(times) of 8 looks: \(text)") }
}

/// Opens the Settings window when it is not open, and its page with this
/// title. Every step that needs a page goes there itself.
func showPage(_ title: String, in app: AXUIElement, step: String) {
    if windows(of: app, titled: Words.settingsWindow).isEmpty {
        guard pressMenuItem(Words.settingsMenuItem, of: app) else {
            stop(.notFound, "\(step): Settings is not open, and the app's menu has no \"\(Words.settingsMenuItem)\".")
        }
        expect("no \"\(Words.settingsWindow)\" window", after: Words.settingsMenuItem, in: step) {
            !windows(of: app, titled: Words.settingsWindow).isEmpty
        }
    }
    guard selectPage(title, in: app) else {
        stop(.notFound, "\(step): the Settings window has no page \"\(title)\".")
    }
}

/// Opens the Features page and scrolls it to its end. The page is lazy:
/// the last card, "Tools from outside", is not there to find until it is.
func showToolsCard(_ app: AXUIElement, step: String) -> [Control] {
    showPage(Words.featuresPage, in: app, step: step)
    for _ in 0..<2 {
        pause(0.8)
        scrollToEnd(in: app, window: Words.settingsWindow)
    }
    pause(0.8)
    let all = controls(of: app, window: Words.settingsWindow)
    guard let card = all.firstIndex(where: { $0.value == Words.toolsCard || $0.title == Words.toolsCard }) else {
        stop(.notFound, "\(step): the Features page has no \"\(Words.toolsCard)\" card, even scrolled to its end.")
    }
    return Array(all[card...])
}

/// The first words of the sheet over the Settings window, or nil with none.
func sheetTitle(_ app: AXUIElement) -> String? {
    let all = controls(of: app, window: Words.settingsWindow)
    guard let sheet = all.lastIndex(where: { $0.role == "AXSheet" }) else { return nil }
    return all[sheet...].first { $0.role == "AXStaticText" && !$0.value.isEmpty }?.value
}

/// Where the keyboard is in the sheet, in one line.
func keyboardLine(_ app: AXUIElement) -> String {
    let targets = keyTargets(in: app, window: Words.settingsWindow)
    return targets.isEmpty ? "the keyboard is on no control of the sheet"
        : "the keyboard is on: " + targets.map { String($0.control.line.prefix(120)) }.joined(separator: "; ")
}

func addTool(folder: String, agreeWith button: String?, app: (process: NSRunningApplication, element: AXUIElement)) {
    // The picker is given a whole path, typed as it is: no shell reads it,
    // so a space or a quotation mark in it is just a character.
    let path = URL(fileURLWithPath: folder).standardizedFileURL.path
    var isFolder: ObjCBool = false
    guard FileManager.default.fileExists(atPath: path, isDirectory: &isFolder), isFolder.boolValue else {
        stop(.usage, "add-tool: \(path) is not a folder. Nothing was pressed.")
    }
    _ = showToolsCard(app.element, step: "add-tool")
    mustPress(Words.addTool, in: app.element)
    expect("no folder picker", after: Words.addTool, in: "add-tool") { folderPickerIsOpen(app.element) }
    pause(0.5)
    // Command-Shift-G takes a path, Return goes there, Return again
    // chooses it.
    send(.g, with: [.maskCommand, .maskShift], to: app)
    pause(1.0)
    type(path, to: app)
    pause(0.8)
    send(.return, to: app)
    pause(1.2)
    send(.return, to: app)
    guard appears(within: 4, { sheetTitle(app.element) != nil }), let title = sheetTitle(app.element) else {
        stop(.notFound, "add-tool: chose \(path), but no sheet appeared within 4 s. A refusal is an alert: see `dump`.")
    }
    say("add-tool: the sheet says: \(title.prefix(160))")
    guard let button else {
        say("add-tool: the sheet is left open, and nothing is added. " + keyboardLine(app.element))
        return
    }
    mustPress(button, in: app.element)
    guard appears(within: 4, { sheetTitle(app.element) == nil }) else {
        stop(.notFound, "add-tool: pressed \"\(button)\", but a sheet is still open after 4 s: "
            + "\((sheetTitle(app.element) ?? "").prefix(120))")
    }
    say("add-tool: done, no sheet is open")
}

func removeTool(_ name: String, deleteData: Bool, app: AXUIElement) {
    let card = showToolsCard(app, step: "remove-tool").filter { $0.role == "AXButton" }
    let rows = ByHandRules.toolRows(name, among: card.map { $0.description.isEmpty ? $0.title : $0.description })
    guard rows.count == 1 else {
        stop(.notFound, "remove-tool: \(rows.count) rows of the card are the tool \"\(name)\"; one is needed. "
            + "Nothing was pressed.")
    }
    if case .refused(let error) = press(card[rows[0]]) {
        stop(.notFound, "remove-tool: the app refused the press of the tool's row (error \(error)).")
    }
    say("pressed the row of \"\(name)\"")
    expect("no detail of the tool", after: name, in: "remove-tool") { hasButton(Words.remove, in: app) }
    mustPress(Words.remove, in: app)
    let choice = deleteData ? Words.removeDeletingData : Words.removeKeepingData
    expect("no question with the button \"\(choice)\"", after: Words.remove, in: "remove-tool") {
        hasButton(choice, in: app)
    }
    mustPress(choice, in: app)
    pause(2.0)
    say("remove-tool: " + (sheetTitle(app).map { "a sheet is still open: \($0.prefix(120))" } ?? "done, no sheet is open"))
}

/// The command bar's own controls, when it is open: what is outside the
/// Settings window, from the list of results on.
func barResults(_ app: AXUIElement) -> [Control]? {
    let outside = windows(of: app, except: Words.settingsWindow).flatMap(controls(under:))
    return outside.firstIndex { $0.role == "AXOpaqueProviderList" }.map { Array(outside[$0...]) }
}

/// Leaves the bar closed: Escape, twice at most, and only while it is open
/// and the keyboard is on Vitruvian.
func closeBar(_ app: (process: NSRunningApplication, element: AXUIElement)) {
    for _ in 0..<2 where barResults(app.element) != nil && keyboardIsOnTheApp(app.process) {
        send(.escape, to: app)
        pause(0.4)
    }
    say("run-command: the bar is " + (barResults(app.element) == nil ? "closed" : "still open"))
}

func runCommand(_ title: String, app: (process: NSRunningApplication, element: AXUIElement)) {
    showPage(Words.commandBarPage, in: app.element, step: "run-command")
    guard appears({ hasButton(Words.openCommandBar, in: app.element) }) else {
        stop(.notFound, "run-command: the page \"\(Words.commandBarPage)\" was selected, but no button "
            + "\"\(Words.openCommandBar)\" appeared within 3 s.")
    }
    mustPress(Words.openCommandBar, in: app.element)
    pause(1.0)
    type(title, to: app)
    pause(1.5)
    // The bar's results, in the order it shows them. Pressing a result
    // through Accessibility does nothing, and Return runs the TOP one: so
    // the keyboard is moved to the row that IS the command first.
    guard let list = barResults(app.element) else {
        stop(.notFound, "run-command: pressed \"\(Words.openCommandBar)\" and typed, but no list of results was "
            + "seen. Is the bar open? Nothing was run.")
    }
    let results = list.filter { $0.role == "AXButton" }.map(\.description)
    guard let row = ByHandRules.resultRow(title, among: results) else {
        closeBar(app)
        stop(.notFound, "run-command: NOT OFFERED: the bar has no result that is \"\(title)\" "
            + "(\(results.count) results). Nothing was run.")
    }
    say("run-command: result \(row + 1) of \(results.count)")
    for _ in 0..<row { send(.down, to: app) }
    send(.return, to: app)
    watchMessage(app.element)
    closeBar(app)
}

func quitApp(_ app: (process: NSRunningApplication, element: AXUIElement)) {
    guard pressMenuItem(Words.quitMenuItem, of: app.element) else {
        stop(.notFound, "The app's menu has no \"\(Words.quitMenuItem)\". Nothing was done.")
    }
    for _ in 0..<40 where !app.process.isTerminated { pause(0.25) }
    guard app.process.isTerminated else { stop(.notFound, "Vitruvian was asked to quit and is still running after 10 seconds.") }
    say("quit: Vitruvian has quit")
}

func launchApp() {
    guard runningApp() == nil else { return say("launch: Vitruvian is already running") }
    guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) else {
        stop(.notFound, "No app with the bundle id \(bundleID) is installed.")
    }
    NSWorkspace.shared.openApplication(at: url, configuration: NSWorkspace.OpenConfiguration()) { _, _ in }
    for _ in 0..<40 where runningApp() == nil { pause(0.25) }
    guard runningApp() != nil else { stop(.notFound, "Vitruvian did not start within 10 seconds (\(url.path)).") }
    say("launch: started \(url.path)")
}

// MARK: - The command

guard let command = ByHandRules.parse(Array(CommandLine.arguments.dropFirst())) else {
    stop(.usage, ByHandRules.usage)
}

func numbered(_ number: Int, in app: AXUIElement, window: String?) -> Control {
    let all = controls(of: app, window: window)
    guard all.indices.contains(number) else { stop(.notFound, "There is no control \(number): `dump` lists \(all.count).") }
    return all[number]
}

func report(_ what: String, _ result: AXError) {
    guard result == .success else { stop(.notFound, "\(what): the app refused (error \(result.rawValue)).") }
    say("\(what): ok")
}

switch command {
case .launch:
    launchApp()
case .windows:
    for window in windows(of: theApp().element) {
        say([kAXRoleAttribute, kAXSubroleAttribute, kAXTitleAttribute].map { text(window, $0) }.joined(separator: " | "))
    }
case .dump(let from, let window):
    let app = theApp().element
    for (number, control) in controls(of: app, window: window).enumerated() where number >= from && !control.isSilent {
        say("\(number) \(control.line)")
    }
    // What Return and Escape press in each window and sheet.
    for control in controls(of: app, window: window) where ["AXWindow", "AXSheet"].contains(control.role) {
        for (name, label) in [(kAXDefaultButtonAttribute, "RETURN PRESSES"), (kAXCancelButtonAttribute, "ESCAPE PRESSES")] {
            if let button = attribute(control.element, name) { say("\(label): \(text(button as! AXUIElement, kAXTitleAttribute))") }
        }
    }
case .find(let wanted, let window):
    let found = controls(of: theApp().element, window: window).enumerated().filter { _, control in
        [control.title, control.value, control.description].contains { $0.localizedCaseInsensitiveContains(wanted) }
    }
    for (number, control) in found { say("\(number) \(control.line)") }
    if found.isEmpty { stop(.notFound, "No control's names or value hold \"\(wanted)\".") }
case .focused(let window):
    // Only what a key would act on, and with a sheet open only what is in
    // it: every cell of every list says it is focused too.
    let found = keyTargets(in: theApp().element, window: window)
    for (number, control) in found { say("\(number) \(control.line)") }
    if found.isEmpty { stop(.notFound, "The keyboard is on no button, field, switch, pop-up or slider of the app.") }
case .message:
    watchMessage(theApp().element)
case .press(let name, let window):
    mustPress(name, in: theApp().element, window: window)
case .select(let number, let window):
    let control = numbered(number, in: theApp().element, window: window)
    report("select \(number) (\(control.line.prefix(80)))",
           AXUIElementSetAttributeValue(control.element, kAXSelectedAttribute as CFString, kCFBooleanTrue))
case .setValue(let number, let value, let window):
    let control = numbered(number, in: theApp().element, window: window)
    let wanted: CFTypeRef = Double(value).map { NSNumber(value: $0) } ?? (value as NSString)
    report("set-value \(number) (\(control.line.prefix(80)))",
           AXUIElementSetAttributeValue(control.element, kAXValueAttribute as CFString, wanted))
case .focusField(let number, let window):
    let all = controls(of: theApp().element, window: window)
    let sheet = all.lastIndex { $0.role == "AXSheet" } ?? 0
    let fields = all[sheet...].filter { $0.role == "AXTextField" }
    guard fields.indices.contains(fields.startIndex + number) else {
        stop(.notFound, "There is no field \(number): the last sheet has \(fields.count).")
    }
    let field = fields[fields.startIndex + number]
    report("focus-field \(number) of \(fields.count), holding \"\(field.value.prefix(60))\"",
           AXUIElementSetAttributeValue(field.element, kAXFocusedAttribute as CFString, kCFBooleanTrue))
case .choose(let menu, let item, let window):
    let app = theApp().element
    let popups = controls(of: app, window: window).filter { $0.role == "AXPopUpButton" && $0.description == menu }
    guard let popup = popups.last else { stop(.notFound, "No pop-up is described exactly \"\(menu)\".") }
    if case .refused(let error) = press(popup) { stop(.notFound, "The app refused to open the pop-up (error \(error)).") }
    pause(0.7)
    let items = controls(under: popup.element).filter { $0.role == "AXMenuItem" }
    guard let wanted = items.last(where: { $0.title == item }) else {
        AXUIElementPerformAction(popup.element, kAXCancelAction as CFString)
        stop(.notFound, "The pop-up has no item \"\(item)\". It has: \(items.map(\.title).joined(separator: ", ")).")
    }
    report("choose \"\(item)\"", AXUIElementPerformAction(wanted.element, kAXPressAction as CFString))
case .scrollEnd(let window):
    scrollToEnd(in: theApp().element, window: window)
    say("scroll-end: done")
case .openSettings:
    let app = theApp().element
    guard pressMenuItem(Words.settingsMenuItem, of: app) else {
        stop(.notFound, "The app's menu has no \"\(Words.settingsMenuItem)\". Nothing was done.")
    }
    pause(2.0)
    guard !windows(of: app, titled: Words.settingsWindow).isEmpty else {
        stop(.notFound, "\"\(Words.settingsMenuItem)\" was pressed and no \"\(Words.settingsWindow)\" window is open.")
    }
    say("open-settings: \"\(Words.settingsWindow)\" is open")
case .page(let title):
    showPage(title, in: theApp().element, step: "page")
    say("page \"\(title)\": selected")
case .tools(let lines):
    let card = showToolsCard(theApp().element, step: "tools").filter { !$0.isSilent && !["AXImage", "AXToolbar"].contains($0.role) }
    for control in card.prefix(lines) { say(String(control.line.prefix(200))) }
case .addTool(let folder, let button):
    addTool(folder: folder, agreeWith: button, app: theApp())
case .removeTool(let name, let deleteData):
    removeTool(name, deleteData: deleteData, app: theApp().element)
case .runCommand(let title):
    runCommand(title, app: theApp())
case .quit:
    quitApp(theApp())
}
