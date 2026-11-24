// Copyright (c) 2026 VitruvianSoftware
//
// Permission is hereby granted, free of charge, to any person obtaining a copy
// of this software and associated documentation files (the "Software"), to deal
// in the Software without restriction, including without limitation the rights
// to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
// copies of the Software, and to permit persons to whom the Software is
// furnished to do so, subject to the following conditions:
//
// The above copyright notice and this permission notice shall be included in
// all copies or substantial portions of the Software.
//
// THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
// IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
// FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
// AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
// LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
// OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
// SOFTWARE.

// The Vitruvian Code tool's program: AppKit on the main thread, for the Quick
// Prompt's window and the engine's main-actor work; the kit's loop on a
// thread of its own, which hands each message to the main thread and
// takes what the main thread has for the app through the kit's waker.
// Everything it decides is in VitruvianCodeToolCore, where the tests reach it.

import AppKit
import Foundation
import VitruvianCodeCore
import VitruvianCodeToolCore
import VitruvianToolKit
import VitruvianToolProtocol

/// The kit's objects, used from its thread alone. The box crosses threads
/// so that handed work can reach them; nothing inside is touched elsewhere.
final class Kit: @unchecked Sendable {
    let tool = Tool(version: ToolVersion.current)
    var panels: [String: Panel] = [:]
    /// Each panel's last page, for an open the main thread is too busy to
    /// answer in time. Safe from any thread.
    let opener = PanelOpen()
}

/// The app, from the main thread: each call is handed to the kit's thread.
@MainActor
final class WakerLink: ToolLink {
    private let kit: Kit
    /// What the app said it has at hello, read on the kit's thread in
    /// `onStart` and kept here, so the main thread never reads the kit.
    var features: Set<ProtocolFeature> = []

    init(kit: Kit) {
        self.kit = kit
    }

    func badge(count: Int?, dot: Bool) {
        kit.tool.waker.later { [kit] _ in try? kit.panels[VitruvianCodeTool.islandPanel]?.badge(count: count, dot: dot) }
    }

    func render(panel: String, _ tree: UITree) {
        kit.opener.remember(tree, for: panel)
        kit.tool.waker.later { [kit] _ in _ = kit.panels[panel]?.render(tree) }
    }

    func showMessage(_ message: String, icon: String) {
        kit.tool.waker.later { app in try? app.showMessage(message, icon: icon) }
    }

    func log(_ message: String) {
        kit.tool.waker.later { app in app.log(message) }
    }

    func setValue(_ value: JSONValue, for key: String) {
        kit.tool.waker.later { app in try? app.setValue(value, for: key) }
    }

    func setRunnable(_ commands: [String]) {
        kit.tool.waker.later { app in app.setRunnable(commands) }
    }

    func supports(_ feature: ProtocolFeature) -> Bool {
        features.contains(feature)
    }

    func showNotice(title: String, detail: String?, icon: String) {
        kit.tool.waker.later { app in try? app.showNotice(title, detail: detail, icon: icon) }
    }

    func dockToSlot() {
        kit.tool.waker.later { app in _ = try? app.dockToSlot() }
    }

    /// No icon and no text take the mark away; words of activity mean work
    /// under way, and a mark without them waits for the person. The kit
    /// sends nothing to an app without `ui.status`, and leaves the words
    /// out for one without `ui.status.activity`.
    func setStatus(icon: String?, text: String?, activity: String?) {
        let state: StatusState = icon == nil && text == nil ? .none : activity == nil ? .attention : .busy
        kit.tool.waker.later { app in
            _ = try? app.status(state, text: text.map(UIText.plain), icon: icon, activity: activity.map(UIText.plain))
        }
    }
}

/// Runs `work` on the main thread and waits for it: the kit's thread is
/// the only one that waits on the main thread, never the other way.
func onMain<Value: Sendable>(_ work: @MainActor () throws -> Value) rethrows -> Value {
    try DispatchQueue.main.sync { try MainActor.assumeIsolated(work) }
}

/// Reads the preferences the manifest declares, for `start`.
func handed(_ app: App) -> [String: JSONValue] {
    var values: [String: JSONValue] = [:]
    for key in ToolSettings.Key.titled + ToolSettings.Key.untitled {
        if let value = try? app.value(key) { values[key] = value }
    }
    return values
}

let kit = Kit()
let application = NSApplication.shared
application.setActivationPolicy(.accessory)
let dataFolder = URL(fileURLWithPath: FileManager.default.currentDirectoryPath, isDirectory: true)
let link = WakerLink(kit: kit)
let settings = ToolSettings(folder: dataFolder, log: { message in link.log(message) })
let engine = ToolEngine(environment: .live, host: settings)
nonisolated(unsafe) var languageTag = "en"
let window = ToolWindowController(engine: engine, language: { languageTag })
application.delegate = window
let codeTool = VitruvianCodeTool(parts: .init(
    link: link, settings: settings, engine: engine, window: window,
    chooseFolder: {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.canCreateDirectories = true
        panel.allowsMultipleSelection = false
        return panel.runModal() == .OK ? panel.url?.path : nil
    },
    playDone: { NSSound(named: "Tink")?.play() }))

let tool = kit.tool
/// Opens `id` without holding the app's answer for a busy main thread (a
/// chat window being built, say): see PanelOpen. A page made too late is
/// sent once the kit's thread is free, if the panel is still open.
func opened(_ id: String, _ make: @escaping @Sendable @MainActor () -> UITree) -> UITree {
    kit.opener.open(id, make: make, render: { tree in
        kit.tool.waker.later { [kit] _ in _ = kit.panels[id]?.render(tree) }
    })
}

/// Handles a panel event without holding the app's answer for a busy main
/// thread: see `PanelOpen.event`. A page made too late is sent once the kit's
/// thread is free, if the panel is still open.
func handled(_ id: String, _ handle: @escaping @Sendable @MainActor () -> PanelAnswer) -> PanelAnswer {
    kit.opener.event(id, handle: handle, render: { tree in
        kit.tool.waker.later { [kit] _ in _ = kit.panels[id]?.render(tree) }
    })
}

kit.panels[VitruvianCodeTool.islandPanel] = tool.panel(VitruvianCodeTool.islandPanel, onOpen: { _, _ in
    opened(VitruvianCodeTool.islandPanel) { codeTool.islandPage() }
}, onEvent: { _, _, event in
    handled(VitruvianCodeTool.islandPanel) { codeTool.islandEvent(event) }
})
kit.panels[VitruvianCodeTool.settingsPanel] = tool.panel(VitruvianCodeTool.settingsPanel, onOpen: { _, _ in
    opened(VitruvianCodeTool.settingsPanel) { codeTool.settingsPage() }
}, onEvent: { _, _, event in
    handled(VitruvianCodeTool.settingsPanel) { codeTool.settingsEvent(event) }
})

/// Keeps each panel's page as it would open now, for PanelOpen to fall back on.
@MainActor
func rememberPages() {
    for id in [VitruvianCodeTool.islandPanel, VitruvianCodeTool.settingsPanel] {
        if let page = codeTool.pagePreview(id) { kit.opener.remember(page, for: id) }
    }
}
// A panel the app closed: the tool stops drawing it.
for id in [VitruvianCodeTool.islandPanel, VitruvianCodeTool.settingsPanel] {
    kit.panels[id]?.onClose = { _ in kit.opener.close { codeTool.panelClosed(id) } }
}
for command in VitruvianCodeTool.Command.all + VitruvianCodeTool.Command.ade {
    tool.command(command) { _ in try CommandAnswer.handle(command) { try codeTool.run(command: $0) } }
}
tool.onStart = { app in
    let language = app.language
    let values = handed(app)
    // A loop, not `filter { }`: a closure written here is taken as the main
    // actor's, and this runs on the kit's thread.
    var features = Set<ProtocolFeature>()
    for feature in ProtocolFeature.allCases where app.supports(feature) { features.insert(feature) }
    onMain {
        link.features = features
        languageTag = language
        // The dock button only for an app that keeps the chat a slot.
        window.onDockToNotch = features.contains(.slot) ? { link.dockToSlot() } : nil
        codeTool.start(language: language, handed: values)
        rememberPages()
    }
}
// The app's slot for the chat showed, moved or went.
tool.onSlot = { _, slot in CommandAnswer.slotChanged { codeTool.slotChanged(slot) } }
tool.onPreferencesChanged = { _, values in onMain { codeTool.preferencesChanged(values) } }
tool.onLanguageChanged = { app in
    let language = app.language
    onMain {
        languageTag = language
        codeTool.languageChanged(language)
        window.languageChanged()
        rememberPages()
    }
}

// The kit on its own thread; the app says goodbye, and the program ends
// once the engine has stopped the chat's programs, or at ToolExit's
// deadline if the main thread is too busy: inside the protocol's two
// seconds either way. See ToolExit.
Thread.detachNewThread {
    let status = kit.tool.serve()
    ToolExit.leave(status: status, stop: {
        await codeTool.stopAll(timeout: ToolExit.stopBudget)
    }, end: { ToolExit.endProcess($0) })
}
application.run()
