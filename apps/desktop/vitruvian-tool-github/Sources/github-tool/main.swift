// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 VitruvianSoftware

// The GitHub tool's program: the kit's loop around `GitHubTool`. Everything
// it decides is in GitHubToolCore, where the tests reach it; this file only
// wires the kit's handlers, panels and timer to it.

import Foundation
import GitHubToolCore
import VitruvianToolKit
import VitruvianToolProtocol

/// The app, through the kit. The kit hands an `App` to each handler; the
/// latest one is kept, since each is the same link.
final class KitHost: ToolHost {
    var app: App?
    var panels: [String: Panel] = [:]

    var language: String { app?.language ?? "en" }

    func value(_ key: String) -> JSONValue? {
        try? app?.value(key)
    }

    func setValue(_ value: JSONValue, for key: String) {
        try? app?.setValue(value, for: key)
    }

    func showMessage(_ message: String, icon: String) {
        try? app?.showMessage(message, icon: icon)
    }

    func open(_ url: String) -> Bool {
        (try? app?.open(url)) ?? false
    }

    func log(_ message: String) {
        app?.log(message)
    }

    func badge(count: Int?, dot: Bool) {
        try? panels[GitHubTool.islandPanel]?.badge(count: count, dot: dot)
    }

    /// The kit sends nothing, and says false, to an app without `ui.status`:
    /// that app shows no mark, and the false is ignored.
    func status(_ status: IslandStatus) {
        do {
            try app?.status(status.state, text: status.text, icon: status.icon)
        } catch {
            app?.log("the app did not take the status: \(error)")
        }
    }

    func render(panel: String, _ tree: UITree) {
        panels[panel]?.render(tree)
    }
}

let tool = Tool(version: ToolVersion.current)
let host = KitHost()
let dataFolder = URL(fileURLWithPath: FileManager.default.currentDirectoryPath, isDirectory: true)
let github = GitHubTool(parts: GitHubTool.Parts(host: host, api: GitHubAPI(), secrets: SecretStore(folder: dataFolder)))

host.panels[GitHubTool.islandPanel] = tool.panel(GitHubTool.islandPanel, onOpen: { app, _ in
    host.app = app
    return github.islandPage()
}, onEvent: { app, _, event in
    host.app = app
    return github.islandEvent(event)
})
host.panels[GitHubTool.settingsPanel] = tool.panel(GitHubTool.settingsPanel, onOpen: { app, _ in
    host.app = app
    return github.settingsPage()
}, onEvent: { app, _, event in
    host.app = app
    return github.settingsEvent(event)
})
tool.command("refresh") { app in
    host.app = app
    github.refresh()
}
tool.command("openPulls") { app in
    host.app = app
    github.openPulls()
}
tool.onStart = { app in
    host.app = app
    github.start()
}
tool.onPreferencesChanged = { app, values in
    host.app = app
    github.preferencesChanged(Array(values.keys))
}
tool.every(seconds: GitHubTool.tickSeconds) { app in
    host.app = app
    github.tick()
}
tool.run()
