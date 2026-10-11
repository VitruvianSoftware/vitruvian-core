// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 VitruvianSoftware

import Foundation
import os
import VitruvianCore
import VitruvianToolProtocol

/// The tools from outside that are installed, and where their files are.
/// It answers "installed?" for the capability broker.
///
/// For now it holds them for the life of the app only, and nothing but a
/// development build's switch adds one (`installDevelopmentTool`). Keeping
/// them from one launch to the next, and recording that the person agreed,
/// come with the screen that asks.
@MainActor
package final class ExternalToolStore {
    /// Why a folder was not added.
    package enum Refusal: Error, Equatable, Sendable {
        /// The folder is not a tool the app can add.
        case manifest(ManifestRefusal)
        /// The app has no support folder to keep a tool in.
        case noSupportFolder
        /// The tool's files could not be put in the app's folder.
        case files(ToolFolders.Problem)
        /// A tool with this id is there already.
        case alreadyInstalled(ToolID)
    }

    package struct Installed: Equatable, Sendable {
        package let tool: ExternalToolManifest
        /// The app's copy of the tool's folder. The program runs from here.
        package let files: URL
        /// The folder the tool keeps what it saves in, and runs in.
        package let data: URL
    }

    /// Everything the store reaches, so a test can stand in for each.
    package struct Parts {
        package var folders: ToolFolders?
        package var host: @MainActor () -> ToolHost
        package var registry: @MainActor () -> ToolRegistry
        package var broker: @MainActor () -> CapabilityBroker
        package var clock: any ToolClock
        package var limits: ToolLimits
        /// What carries bytes to one run of a program, given the file to
        /// run and the folder to run it in.
        package var makeTransport: @MainActor (_ program: URL, _ dataFolder: URL) -> any ToolTransport
        /// The language the app is in, as a tag such as `en-US`.
        package var language: @MainActor () -> String
        /// Told, once for each tool, that it stopped working.
        package var stoppedWorking: @MainActor (ToolID) -> Void

        package init(folders: ToolFolders?, host: @escaping @MainActor () -> ToolHost,
                     registry: @escaping @MainActor () -> ToolRegistry,
                     broker: @escaping @MainActor () -> CapabilityBroker, clock: any ToolClock,
                     limits: ToolLimits = .standard,
                     makeTransport: @escaping @MainActor (URL, URL) -> any ToolTransport,
                     language: @escaping @MainActor () -> String,
                     stoppedWorking: @escaping @MainActor (ToolID) -> Void) {
            self.folders = folders
            self.host = host
            self.registry = registry
            self.broker = broker
            self.clock = clock
            self.limits = limits
            self.makeTransport = makeTransport
            self.language = language
            self.stoppedWorking = stoppedWorking
        }

        /// The app as it is. The sentence that tells the person a tool
        /// stopped working comes with the screens; until then it is a line
        /// in the system log.
        ///
        /// The type is written out, here and on `shared`: the broker's own
        /// `live` asks this store what is installed, and without it the
        /// compiler goes round in a circle working the types out.
        @MainActor package static let live: Parts = Parts(
            folders: .live, host: { .shared }, registry: { .shared }, broker: { .shared },
            clock: SystemToolClock.shared,
            makeTransport: { program, dataFolder in ProcessTransport(program: program, directory: dataFolder) },
            language: { L10n.shared.language.rawValue },
            stoppedWorking: { id in
                Logger(subsystem: Bundle.main.bundleIdentifier ?? "vitruvian", category: "tools")
                    .error("the tool \(id.rawValue, privacy: .public) stopped working")
            })
    }

    package static let shared: ExternalToolStore = ExternalToolStore(parts: .live)

    private let parts: Parts
    package private(set) var installed: [ToolID: Installed] = [:]
    private var tools: [ToolID: ExternalTool] = [:]

    package init(parts: Parts) {
        self.parts = parts
    }

    package func isInstalled(_ id: ToolID) -> Bool {
        installed[id] != nil
    }

    /// The live tool with this id, for its log and how it stands.
    package func tool(_ id: ToolID) -> ExternalTool? {
        tools[id]
    }

    /// Adds the tool in `folder`: reads its manifest, copies the folder
    /// into the app's own, and hands the tool to the host and the registry.
    /// Its program is started by the host's run rule, or by its first
    /// command. Nothing is copied, and nothing changes, when it is refused.
    @discardableResult
    package func install(from folder: URL) -> Result<Installed, Refusal> {
        let source: ExternalToolManifest
        switch ExternalToolManifest.read(folder: folder) {
        case .success(let tool): source = tool
        case .failure(let refusal): return .failure(.manifest(refusal))
        }
        let id = source.manifest.id
        guard installed[id] == nil, parts.registry().tool(id) == nil, parts.host().manifest(for: id) == nil else {
            return .failure(.alreadyInstalled(id))
        }
        guard let folders = parts.folders else { return .failure(.noSupportFolder) }
        let place: ToolFolders.Place
        switch folders.install(id, from: folder) {
        case .success(let made): place = made
        case .failure(let problem): return .failure(.files(problem))
        }
        // The copy is what runs, so the copy is what is read: a link that
        // pointed inside the picked folder may point outside the copy.
        let tool: ExternalToolManifest
        switch ExternalToolManifest.read(folder: place.files) {
        case .success(let copied) where copied.manifest.id == id: tool = copied
        case .success: return .failure(.manifest(.noManifest))
        case .failure(let refusal): return .failure(.manifest(refusal))
        }

        let entry = Installed(tool: tool, files: place.files, data: place.data)
        let hosted = makeTool(entry)
        guard parts.host().add(hosted, manifest: tool.manifest) else { return .failure(.alreadyInstalled(id)) }
        do {
            try parts.registry().register(tool, host: parts.host)
        } catch {
            parts.host().remove(id)
            parts.registry().unregister(id)
            return .failure(.alreadyInstalled(id))
        }
        installed[id] = entry
        tools[id] = hosted
        parts.host().sync(id)
        return .success(entry)
    }

    /// Stops the tool and takes it out of the host and the registry. Its
    /// files, and what it saved, stay where they are.
    package func remove(_ id: ToolID) {
        guard installed.removeValue(forKey: id) != nil else { return }
        tools[id] = nil
        parts.host().remove(id)
        parts.registry().unregister(id)
    }

    private func makeTool(_ entry: Installed) -> ExternalTool {
        let parts = self.parts
        let manifest = entry.tool.manifest
        let id = manifest.id
        let program = entry.files.appendingPathComponent(entry.tool.program)
        let data = entry.data
        return ExternalTool(
            manifest: manifest, clock: parts.clock, limits: parts.limits,
            makeLink: { events in
                let calls = ExternalToolCalls(manifest: manifest, broker: parts.broker())
                return ToolLink(
                    transport: parts.makeTransport(program, data), clock: parts.clock, limits: parts.limits,
                    hello: InitializeParams(protocolVersions: ProtocolVersion.supported, language: parts.language(),
                                            dataFolder: data.path),
                    serve: { method, params, reply in calls.serve(method, params, reply) },
                    events: events)
            },
            events: .init(
                // Whoever lists its commands looks again.
                onChange: { parts.registry().noteAvailabilityChanged() },
                onStoppedWorking: { parts.stoppedWorking(id) },
                // A command that did not run beeps, as a built-in one does.
                onCommandFailed: { parts.broker().backings.notify.beep() }))
    }
}

extension ExternalToolStore {
    /// The preference a development build reads a tool's folder from. No
    /// screen sets it, and a release build never reads it.
    package static let developmentToolFolderKey = "developmentToolFolder"

    /// The development switch: adds the one tool whose folder the hidden
    /// preference names, with no screen and no question. `main.swift` calls
    /// this only in a build made with `--define=vitruvian_external_tools=true`.
    ///
    /// The store forgets its tools when the app quits, so this adds the
    /// folder afresh at each launch: the app's copy is the folder as it is
    /// now, and what the tool saved is kept. Nil when the preference is not
    /// set; then nothing happens at all.
    @discardableResult
    package func installDevelopmentTool(defaults: UserDefaults = .standard) -> Result<Installed, Refusal>? {
        guard let path = defaults.string(forKey: Self.developmentToolFolderKey), !path.isEmpty else { return nil }
        let folder = URL(fileURLWithPath: (path as NSString).expandingTildeInPath, isDirectory: true)
        let result = install(from: folder)
        let log = Logger(subsystem: Bundle.main.bundleIdentifier ?? "vitruvian", category: "tools")
        switch result {
        case .success(let installed):
            log.notice("added the development tool \(installed.tool.manifest.id.rawValue, privacy: .public)")
        case .failure(let refusal):
            log.error("the development tool at \(folder.path, privacy: .public) was not added: \(String(describing: refusal), privacy: .public)")
        }
        return result
    }
}
