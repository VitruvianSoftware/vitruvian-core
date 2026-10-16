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

import Combine
import Foundation
@preconcurrency import HomeSpeakerCore

// The extension's program on its own engine (plan Task 12): where its files
// are, its chat monitor in its own process, and the tool's parts, every one
// built from the extension's profile. The program (`main.swift`) puts these
// together; the tests build the same parts from a scratch folder.

// MARK: - Where the files are

/// Where the extension keeps its files, worked out when the program starts.
public struct ExtensionLocation: Equatable, Sendable {
    /// Names the data folder outright: a test's, or a build run by hand.
    public static let dataFolderVariable = "HOMESPEAKER_DATA_FOLDER"
    /// The message prefix a test runs under, so a real extension on this
    /// Mac never hears it.
    public static let messagePrefixVariable = "HOMESPEAKER_MESSAGE_PREFIX"
    /// What the command line says when it cannot tell where the files are.
    public static let noProfile = "run the installed extension, or set HOMESPEAKER_DATA_FOLDER"

    /// Where the data folder came from.
    public enum Source: Equatable, Sendable {
        /// `HOMESPEAKER_DATA_FOLDER`.
        case variable
        /// The program's own path, `…/Tools/<id>/bin/tool`.
        case programPath
        /// The folder Vitruvian started the program in, which is the data
        /// folder it gives the tool.
        case workingDirectory
    }

    public let profile: HomeSpeakerProfile
    public let source: Source

    /// The data folder, in this order: the variable; the program's own
    /// path; the working directory, which is the data folder Vitruvian
    /// gives the tool and starts it in (`workingDirectory` is nil for the
    /// command line, which has no Vitruvian behind it). Nil when none
    /// applies. `program` is the program's real path.
    public static func locate(environment: [String: String], program: URL, workingDirectory: URL?) -> ExtensionLocation? {
        let prefix = environment[messagePrefixVariable].flatMap { $0.isEmpty ? nil : $0 }
            ?? HomeSpeakerProfile.extensionMessagePrefix
        // `bin/tool`'s grandparent: the tool's own folder.
        let toolFolder = program.deletingLastPathComponent().deletingLastPathComponent()
        if let named = environment[dataFolderVariable], !named.isEmpty {
            let folders = HomeSpeakerProfile.extensionFolders(program: program)
            return ExtensionLocation(
                profile: .extension(dataFolder: URL(fileURLWithPath: named, isDirectory: true),
                                    toolFolder: folders?.tool ?? toolFolder, messagePrefix: prefix),
                source: .variable)
        }
        if let folders = HomeSpeakerProfile.extensionFolders(program: program) {
            return ExtensionLocation(
                profile: .extension(dataFolder: folders.data, toolFolder: folders.tool, messagePrefix: prefix),
                source: .programPath)
        }
        guard let workingDirectory else { return nil }
        return ExtensionLocation(
            profile: .extension(dataFolder: workingDirectory, toolFolder: toolFolder, messagePrefix: prefix),
            source: .workingDirectory)
    }

    /// The folder the files are in.
    public var dataFolder: URL { profile.settingsURL.deletingLastPathComponent() }

    /// Why the tool will not run on this folder, given the one Vitruvian's
    /// hello named; nil when they are the same, or when the variable named
    /// it on purpose. The engine was built before the hello came, from the
    /// program's path or the folder it was started in: a different hello
    /// means it guessed wrong, and its files would be in the wrong place.
    public func refusal(helloFolder: URL) -> String? {
        guard source != .variable else { return nil }
        func canonical(_ url: URL) -> String { url.standardizedFileURL.resolvingSymlinksInPath().path }
        guard canonical(helloFolder) != canonical(dataFolder) else { return nil }
        return "Vitruvian gave HomeSpeaker the data folder \(helloFolder.path), but it worked out \(dataFolder.path). "
            + "It will not keep its settings and sign-ins in a folder it was not given, so it stops."
    }

    /// The program's own path, links resolved.
    public static func ownProgram() -> URL {
        (Bundle.main.executableURL ?? URL(fileURLWithPath: CommandLine.arguments[0])).resolvingSymlinksInPath()
    }
}

// MARK: - The chat monitor, in this process (its gate, `GatedMonitor`, is HomeSpeakerCore's)

/// The last thing the engine said when it put a speaker back
/// (`VolumeRestoreCoordinator.lastReport`), kept where the kit's thread can
/// read it: the coordinator is the main actor's.
public final class RestoreReport: @unchecked Sendable {
    private let lock = NSLock()
    private var latest: String?
    private var watching: AnyCancellable?

    @MainActor
    public init(_ coordinator: VolumeRestoreCoordinator) {
        latest = coordinator.lastReport
        watching = coordinator.$lastReport.sink { [weak self] report in
            guard let self else { return }
            self.lock.withLock { self.latest = report }
        }
    }

    public var value: String? { lock.withLock { latest } }
}

/// The extension's long-lived parts, put together.
public enum ExtensionSide {
    /// #3341's chat monitor, built from the extension's engine: its
    /// settings, secrets, speakers, announcer and sign-in, and its own
    /// status file, `<data>/speaker_monitor_status.json`.
    @MainActor
    public static func chatMonitor(engine: HomeSpeakerEngine, chatSession: URLSession = .shared) -> ChatMonitorService {
        ChatMonitorService(
            configManager: engine.config, secrets: engine.secrets, home: engine.home, announcer: engine.announcer,
            statusFile: ChatMonitorStatusFile(url: engine.profile.monitorStatusURL), auth: engine.auth,
            chatSession: chatSession)
    }

    /// Wires every way the monitor is started or stopped to `monitor`: the
    /// settings watcher, the sign-out and credentials-changed notices, and
    /// the control message, each under the profile's own names. The
    /// settings manager and the listeners hold `monitor` weakly: keep it.
    /// Keep the tokens to stop listening.
    @MainActor
    public static func watch(engine: HomeSpeakerEngine, monitor: GatedMonitor) -> [NSObjectProtocol] {
        engine.config.chatMonitor = monitor
        engine.config.startWatchingConfigFile()
        return engine.listenForNotices(monitor: monitor) + [
            ChatMonitorControlNotice.listen(
                name: ChatMonitorControlNotice.notificationName(for: engine.profile), monitor: monitor),
        ]
    }

    /// Writes this extension's own block into the choice file, under its
    /// lock: where its program and data folder are, its version, and the
    /// mark that says it runs without the app. Nothing else is touched:
    /// the choice is the person's, made on a page.
    public static func recordInDoor(
        _ door: DoorFile, program: URL, profile: HomeSpeakerProfile, version: String = ToolVersion.current
    ) throws {
        try door.update {
            $0.installedExtension = DoorRecord.ExtensionEntry(
                program: program.path, dataFolder: profile.settingsURL.deletingLastPathComponent().path,
                version: version, door: DoorRecord.ExtensionEntry.runsAlone)
        }
    }

    /// Runs `work` on the main actor, later: how the kit's thread reaches
    /// the monitor, whose process keeps its main queue running.
    public static let onMain: @Sendable (@escaping @MainActor @Sendable () -> Void) -> Void = { work in
        DispatchQueue.main.async { MainActor.assumeIsolated { work() } }
    }
}

// MARK: - The tool's parts

extension HomeSpeakerTool.Parts {
    /// The tool's parts on the extension's engine. Every file is the
    /// profile's: its settings, secrets, history and monitor status, never
    /// the app's in `~/.gemini`; every message goes under its names.
    ///
    /// - `driverParts` run the jobs in this process (`EngineDriver`).
    /// - `monitor` is this process's chat monitor: Start and Stop call it
    ///   on the main actor (`onMain`); nothing is posted to the app.
    /// - `check` says which HomeSpeaker runs.
    /// - `appProgram`, `runningApps`, `runProgram` and `openApp` are the app
    ///   as the extension sees it (`SystemOtherApp`): `appProgram` finds it
    ///   afresh each time it is asked; `runProgram` is the one way a program
    ///   of the app's is started, and no job uses it; `openApp` opens it
    ///   when the person picks it.
    /// - `appProfile` is the app's files, which the choice card compares
    ///   with the extension's and copies from or into.
    /// - `home` is where the coding agents keep their files.
    @MainActor
    public static func `extension`(
        engine: HomeSpeakerEngine,
        program: URL,
        link: ToolLink,
        later: @escaping @Sendable (@escaping @Sendable () -> Void) -> Void,
        driverParts: EngineDriver.Parts,
        monitor: GatedMonitor,
        check: DoorCheck,
        appProgram: @escaping @Sendable () -> URL?,
        appProfile: HomeSpeakerProfile,
        runningApps: @escaping @Sendable () -> [any RunningAppHandle],
        runProgram: @escaping ProgramRunning,
        openApp: @escaping @Sendable (URL) async -> Bool,
        home: URL,
        onMain: @escaping @Sendable (@escaping @MainActor @Sendable () -> Void) -> Void = ExtensionSide.onMain,
        voices: @escaping () -> [LocalVoice] = { [] },
        previewVoice: @escaping @Sendable (String) async throws -> Void = { _ in },
        gwsLocation: @escaping () -> String? = { nil },
        sendStatus: @escaping (MarkChoice) -> Void = { _ in }
    ) -> Self {
        let profile = engine.profile
        let permission = monitor.permission
        let other = SystemOtherApp(
            locate: appProgram, runningApps: runningApps, run: runProgram, fileManager: .default,
            wait: { try? await Task.sleep(for: .seconds($0)) }, openApp: openApp)
        let credentialsChanged = CredentialsChangedNotice.notificationName(for: profile)
        let restored = RestoreReport(engine.volumeRestore)
        return Self(
            link: link,
            store: FileConfigStore(url: profile.settingsURL),
            driver: EngineDriver(engine: engine, program: program, parts: driverParts),
            later: later,
            account: SecretStoreAccount(store: engine.secrets, profile: profile),
            voices: voices,
            previewVoice: previewVoice,
            chat: SecretStoreChatCredentials(store: engine.secrets),
            gwsLocation: gwsLocation,
            ownerRunning: { profile.ownerRunning() },
            credentialsChanged: { CredentialsChangedNotice.post(name: credentialsChanged) },
            home: home,
            settingsURL: profile.settingsURL,
            secretsURL: profile.secretsURL,
            homeSpeakerVersion: { HomeSpeakerVersion.current },
            historyURL: profile.historyURL,
            monitorStatusURL: profile.monitorStatusURL,
            controlChatMonitor: { action in onMain { ChatMonitorControlNotice.apply(action, monitor: monitor) } },
            role: { check.role(me: .extension) },
            other: other,
            door: check.file,
            copy: DoorCopy.copy,
            sendStatus: sendStatus,
            monitorMayRun: { permission.set($0) },
            profile: profile,
            appProfile: appProfile,
            appProgram: appProgram,
            repairsHooks: true,
            otherInstalled: { check.appInstalled() },
            // After a copy, the side that took it: the app's names when the
            // app took it, so the running app re-reads its sign-ins.
            credentialsChangedIn: { CredentialsChangedNotice.post(name: CredentialsChangedNotice.notificationName(for: $0)) },
            volumeRestoreReport: { restored.value })
    }
}
