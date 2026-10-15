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

// The HomeSpeaker tool's program: the kit's loop around `HomeSpeakerTool`,
// on the main thread. HomeSpeaker's program is started and not waited for;
// its end is handed to the kit's thread through the kit's waker.

import AppKit
import Foundation
import HomeSpeakerCore
import HomeSpeakerToolCore
import VitruvianToolKit
import VitruvianToolProtocol

/// The app, through the kit. The kit hands an `App` to each handler; the
/// latest one is kept, since each is the same link.
final class KitLink: ToolLink {
    var app: App?
    var panels: [String: Panel] = [:]

    func render(panel: String, _ tree: UITree) { _ = panels[panel]?.render(tree) }
    func showMessage(_ message: String, icon: String) { try? app?.showMessage(message, icon: icon) }
    func log(_ message: String) { app?.log(message) }
    func clipboardText() -> String? { (try? app?.clipboardText()) ?? nil }
    func supports(_ feature: ProtocolFeature) -> Bool { app?.supports(feature) ?? false }
}

let tool = Tool(version: ToolVersion.current)
let link = KitLink()
let binary = ProcessDriver.locate(
    environment: ProcessInfo.processInfo.environment,
    known: { NSWorkspace.shared.urlForApplication(withBundleIdentifier: ProcessDriver.bundleID) },
    home: NSHomeDirectory(),
    isExecutable: { FileManager.default.isExecutableFile(atPath: $0) })
let waker = tool.waker
// HomeSpeaker.app's own bundle, whose Info.plist may carry the OAuth client
// it was packaged with; the program is its Contents/MacOS/HomeSpeaker.
let appBundle = binary.flatMap { program in
    Bundle(url: program.deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent())
}
let speaker = HomeSpeakerTool(parts: .init(
    link: link, store: FileConfigStore(), driver: ProcessDriver(binary: binary),
    later: { work in waker.later { _ in work() } },
    account: SecretStoreAccount(bundle: appBundle ?? .main),
    voices: { LocalSpeaker.shared.englishVoices() },
    previewVoice: { voice in try await LocalSpeaker.shared.speak(Pages.previewText, voiceID: voice) },
    chat: SecretStoreChatCredentials(),
    gwsLocation: { GwsChatClient.locate() },
    isAppRunning: { ProcessDriver.isAppRunning() },
    credentialsChanged: { CredentialsChangedNotice.post() }))

link.panels[HomeSpeakerTool.islandPanel] = tool.panel(HomeSpeakerTool.islandPanel, onOpen: { app, _ in
    link.app = app
    return speaker.islandPage()
}, onEvent: { app, _, event in
    link.app = app
    return speaker.islandEvent(event)
})
link.panels[HomeSpeakerTool.settingsPanel] = tool.panel(HomeSpeakerTool.settingsPanel, onOpen: { app, _ in
    link.app = app
    return speaker.settingsPage()
}, onEvent: { app, _, event in
    link.app = app
    return speaker.settingsEvent(event)
})
for command in HomeSpeakerTool.Command.all {
    tool.command(command) { app in
        link.app = app
        try speaker.run(command: command)
    }
}
tool.onStart = { app in
    link.app = app
    speaker.start()
}
// A panel the app closed: the tool stops drawing it.
tool.every(seconds: 5) { _ in
    for (id, panel) in link.panels where !panel.isOpen { speaker.panelClosed(id) }
}
tool.run()
