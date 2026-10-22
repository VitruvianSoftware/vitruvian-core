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

// The Nexus Agent tool's program: AppKit on the main thread, for the Quick
// Prompt's window and the engine's main-actor work; the kit's loop on a
// thread of its own, which hands each message to the main thread and
// takes what the main thread has for the app through the kit's waker.
// Everything it decides is in NexusAgentToolCore, where the tests reach it.

import AppKit
import Foundation
import NexusAgentCore
import NexusAgentToolCore
import VitruvianToolKit
import VitruvianToolProtocol

/// The kit's objects, used from its thread alone. The box crosses threads
/// so that handed work can reach them; nothing inside is touched elsewhere.
final class Kit: @unchecked Sendable {
    let tool = Tool(version: ToolVersion.current)
    var panels: [String: Panel] = [:]
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
        kit.tool.waker.later { [kit] _ in try? kit.panels[NexusAgentTool.islandPanel]?.badge(count: count, dot: dot) }
    }

    func render(panel: String, _ tree: UITree) {
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
// `window.onDockToNotch` stays nil, so the chat draws no dock button: the
// protocol has no message yet by which the app hands a tool a slot in its
// notch, and `dockIntoSlot(frame:)` waits for one.
let nexus = NexusAgentTool(parts: .init(
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
kit.panels[NexusAgentTool.islandPanel] = tool.panel(NexusAgentTool.islandPanel, onOpen: { _, _ in
    onMain { nexus.islandPage() }
}, onEvent: { _, _, event in
    onMain { nexus.islandEvent(event) }
})
kit.panels[NexusAgentTool.settingsPanel] = tool.panel(NexusAgentTool.settingsPanel, onOpen: { _, _ in
    onMain { nexus.settingsPage() }
}, onEvent: { _, _, event in
    onMain { nexus.settingsEvent(event) }
})
for command in NexusAgentTool.Command.all {
    tool.command(command) { _ in try onMain { try nexus.run(command: command) } }
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
        nexus.start(language: language, handed: values)
    }
}
tool.onPreferencesChanged = { _, values in onMain { nexus.preferencesChanged(values) } }
tool.onLanguageChanged = { app in
    let language = app.language
    onMain {
        languageTag = language
        nexus.languageChanged(language)
        window.languageChanged()
    }
}
// A panel the app closed: the tool stops drawing it.
tool.every(seconds: 5) { _ in
    let open = Set(kit.panels.filter { $0.value.isOpen }.map(\.key))
    onMain { for panel in nexus.openPanels.subtracting(open) { nexus.panelClosed(panel) } }
}

// The kit on its own thread; the app says goodbye, and the program ends
// from the main thread, after the engine has let the bot be.
Thread.detachNewThread {
    let status = kit.tool.serve()
    DispatchQueue.main.async {
        nexus.stop()
        exit(status)
    }
}
application.run()
