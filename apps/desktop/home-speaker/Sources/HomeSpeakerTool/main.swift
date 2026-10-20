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

// The HomeSpeaker extension's program. With one of HomeSpeaker's flags
// (`--say`, `--claude-stop-hook`, …) it is the command line, on the
// extension's engine, and exits. Otherwise it is the tool: it holds the
// extension's `running.lock`, listens for its own messages, runs its chat
// monitor, and answers the app through the kit.
//
// Threads: the kit's loop blocks, so it runs on a thread of its own, and
// the main thread runs its run loop (`MainThreadLoop`). The settings, the
// sign-out and the chat monitor are the main actor's, and each job awaits
// them there, so the main queue must keep running on the main thread
// itself: `dispatchMain()` would hand it to a worker thread, where
// `ExtensionSide.onMain`'s `MainActor.assumeIsolated` traps (1.19.0
// crashed so on every start with the chat monitor on). Nothing here
// starts a plain `Task {}` from this file's main-actor code.

import AppKit
import Foundation
import HomeSpeakerCore
import HomeSpeakerToolCore
import VitruvianToolKit
import VitruvianToolProtocol

/// The app, through the kit. The kit hands an `App` to each handler; the
/// latest one is kept, since each is the same link. Used on the kit's
/// thread only.
final class KitLink: ToolLink, @unchecked Sendable {
    var app: App?
    var panels: [String: Panel] = [:]

    func render(panel: String, _ tree: UITree) { _ = panels[panel]?.render(tree) }
    func showMessage(_ message: String, icon: String) { try? app?.showMessage(message, icon: icon) }
    func log(_ message: String) { app?.log(message) }
    func clipboardText() -> String? { (try? app?.clipboardText()) ?? nil }
    func supports(featureNamed name: String) -> Bool { app?.supports(name) ?? false }

    /// The mark on the closed island. A refusal (an app that cannot show
    /// it) is no failure of the tool's.
    func sendStatus(_ mark: MarkChoice) {
        _ = try? app?.status(mark.state, text: mark.text.map { UIText.plain($0) }, icon: mark.icon)
    }
}

/// What the kit's thread is handed: made on the main thread before the loop
/// starts, and used only on the kit's thread after.
final class KitThread: @unchecked Sendable {
    let tool: Tool
    let link: KitLink
    let speaker: HomeSpeakerTool
    let located: ExtensionLocation
    let program: URL
    let door: DoorFile

    init(tool: Tool, link: KitLink, speaker: HomeSpeakerTool, located: ExtensionLocation, program: URL, door: DoorFile) {
        self.tool = tool
        self.link = link
        self.speaker = speaker
        self.located = located
        self.program = program
        self.door = door
    }

    /// Sets up the kit's handlers and runs its loop on a new thread. The
    /// handlers run on that thread.
    func start() {
        let tool = tool
        let link = link
        let speaker = speaker
        let located = located
        let program = program
        let door = door
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
            // The engine was built from where the program is, or the folder
            // it was started in; the hello says which folder is the tool's.
            if let refusal = located.refusal(helloFolder: app.dataFolder) {
                app.log(refusal)
                FileHandle.standardError.write(Data("error: \(refusal)\n".utf8))
                exit(1)
            }
            do {
                try ExtensionSide.recordInDoor(door, program: program, profile: located.profile)
            } catch {
                app.log("the choice file could not be written: \(error.localizedDescription)")
            }
            speaker.start()
        }
        // A panel the app closed: the tool stops drawing it. One still open
        // that shows the chat monitor is drawn again when it changed. Then
        // the choice file and the app are read again: a change of role
        // starts or stops the monitor, and redraws.
        tool.every(seconds: 5) { _ in
            for (id, panel) in link.panels where !panel.isOpen { speaker.panelClosed(id) }
            speaker.refreshMonitorStatus()
            speaker.refreshRole()
        }
        let thread = Thread { tool.run() }
        thread.name = "HomeSpeaker tool"
        thread.stackSize = 8 << 20
        thread.start()
    }
}

/// HomeSpeaker.app's program, as Launch Services or the usual places find
/// it (`HOMESPEAKER_PROGRAM` names another, or none when empty).
@Sendable func locateApp() -> URL? {
    ProcessDriver.locate(
        environment: ProcessInfo.processInfo.environment,
        known: { NSWorkspace.shared.urlForApplication(withBundleIdentifier: ProcessDriver.bundleID) },
        home: NSHomeDirectory(),
        isExecutable: { FileManager.default.isExecutableFile(atPath: $0) })
}

@MainActor
func runProgram() -> Never {
    let arguments = Array(CommandLine.arguments.dropFirst())
    let environment = ProcessInfo.processInfo.environment
    let program = ExtensionLocation.ownProgram()
    let home = FileManager.default.homeDirectoryForCurrentUser
    let door = DoorFile(url: DoorFile.defaultURL(home: home))
    let check = DoorCheck(file: door, appInstalled: { OtherDoorPresence.appInstalled(locate: locateApp) })
    let standsAside: @Sendable () -> Bool = { check.standsAside(me: .extension) }
    // The app's sign-ins, read only, so a sign-out here (the command line's
    // or a page's) never revokes a login the app shares.
    let appSecrets = HomeSpeakerProfile.app().secretsURL

    // The command line: no Vitruvian, so no hello to name the folder.
    if HomeSpeakerCommandLine.recognizes(arguments) {
        guard let located = ExtensionLocation.locate(environment: environment, program: program, workingDirectory: nil) else {
            FileHandle.standardError.write(Data("error: \(ExtensionLocation.noProfile)\n".utf8))
            exit(1)
        }
        HomeSpeakerProfile.useForThisProcess(located.profile)
        let appProfile = HomeSpeakerProfile.app(home: home)
        HomeSpeakerCommandLine.run(
            arguments, engine: HomeSpeakerEngine(profile: located.profile),
            parts: ExtensionSide.commandLineParts(
                check: check, appSecretsURL: appSecrets, appSettingsURL: appProfile.settingsURL,
                appProfile: appProfile))
    }

    // The tool. Vitruvian starts it in its data folder, which the hello
    // names again: the engine is built from it now and checked then.
    let workingDirectory = URL(fileURLWithPath: FileManager.default.currentDirectoryPath, isDirectory: true)
    guard let located = ExtensionLocation.locate(
        environment: environment, program: program, workingDirectory: workingDirectory) else {
        FileHandle.standardError.write(Data("error: \(ExtensionLocation.noProfile)\n".utf8))
        exit(1)
    }
    let profile = located.profile
    HomeSpeakerProfile.useForThisProcess(profile)
    let engine = HomeSpeakerEngine(profile: profile)

    // One long-lived process per side: it puts volumes back and holds
    // paused media for the hook's runs, which ask whether it is alive.
    var live: LiveLock?
    var tokens: [NSObjectProtocol] = []
    if let lockURL = profile.liveLockURL {
        do {
            live = try LiveLock.hold(at: lockURL)
            tokens += engine.listen()
        } catch {
            FileHandle.standardError.write(Data(
                ("another HomeSpeaker extension holds \(lockURL.path): this one does not listen "
                    + "or read chat\n").utf8))
        }
    }

    // The chat monitor, in this process, on the engine; it starts only
    // while this side may run (`HomeSpeakerTool.refreshRole`), and never
    // in a process that does not hold the lock above.
    let monitor = ExtensionSide.chatMonitor(engine: engine)
    let gate = GatedMonitor(monitor)
    tokens += ExtensionSide.watch(engine: engine, monitor: gate)

    let tool = Tool(version: ToolVersion.current)
    let link = KitLink()
    let waker = tool.waker
    let driverParts = EngineDriver.Parts(
        engine: engine,
        otherSecrets: ExtensionSide.appSecrets(check: check, appSecretsURL: appSecrets),
        // The sign-in page opens through the app, on the kit's thread.
        link: { url in waker.later { app in _ = try app.open(url.absoluteString) } },
        standsAside: standsAside)
    let speaker = HomeSpeakerTool(parts: .extension(
        engine: engine, program: program, link: link,
        later: { work in waker.later { _ in work() } },
        driverParts: driverParts, monitor: gate, holdsLiveLock: live != nil, check: check,
        // Found afresh at each switch: the app may be installed, moved or
        // put in the Trash while the extension runs.
        appProgram: { locateApp() },
        appProfile: HomeSpeakerProfile.app(home: home),
        runningApps: { NSRunningApplication.runningApplications(withBundleIdentifier: HomeSpeakerProfile.appBundleID) },
        runProgram: SystemOtherApp.runProgram,
        openApp: SystemOtherApp.openWithWorkspace,
        home: home,
        voices: { LocalSpeaker.shared.englishVoices() },
        previewVoice: { voice in try await LocalSpeaker.shared.speak(Pages.previewText, voiceID: voice) },
        gwsLocation: { GwsChatClient.locate() },
        sendStatus: { link.sendStatus($0) }))

    KitThread(tool: tool, link: link, speaker: speaker, located: located, program: program, door: door).start()
    // The kit's thread exits the process when the app says goodbye.
    withExtendedLifetime((engine, live, tokens, monitor, gate)) { MainThreadLoop.run() }
}

// Top-level code runs on the main thread.
MainActor.assumeIsolated { runProgram() }
