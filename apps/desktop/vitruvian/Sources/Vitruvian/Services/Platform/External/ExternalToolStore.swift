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
        /// The folder holds more than a tool's folder may. These are the
        /// most it may: so many bytes, and so many things.
        case tooBig(bytes: Int, items: Int)
        /// macOS has quarantined the tool's program, as it does to what is
        /// downloaded, and will not start it. The folder is the one picked.
        case quarantined(URL)
        /// The folder's manifest is no longer the one the person was shown.
        case changedSinceOffered
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

    /// The first of the two steps of adding a tool: reads the tool in the
    /// folder the person picked and says what adding it would mean. Nothing
    /// is copied, nothing is run and nothing is saved. The second step is
    /// `add`, and it takes the person's consent to what this returns.
    package func offer(from picked: URL) -> Result<ToolOffer, Refusal> {
        // A picked folder that is a link is followed first, so that what is
        // read, shown and copied is the folder, never the link to it.
        let folder = picked.resolvingSymlinksInPath().standardizedFileURL
        let tool: ExternalToolManifest
        switch ExternalToolManifest.read(folder: folder) {
        case .success(let read): tool = read
        case .failure(let refusal): return .failure(.manifest(refusal))
        }
        guard let fingerprint = ToolFingerprint.ofManifest(in: folder) else { return .failure(.manifest(.noManifest)) }
        if let folders = parts.folders, folders.holds(folder) { return .failure(.files(.insideTheApp)) }
        if ToolFolders.isQuarantined(folder.appendingPathComponent(tool.program)) {
            return .failure(.quarantined(folder))
        }
        let most = ToolFolders.Weight(bytes: parts.limits.folderBytes, items: parts.limits.folderItems)
        guard ToolFolders.weight(of: folder, within: most) != nil else {
            return .failure(.tooBig(bytes: most.bytes, items: most.items))
        }
        return .success(ToolOffer(folder: folder, tool: tool, fingerprint: fingerprint))
    }

    /// The second step: the person agreed to an offer, so the tool is
    /// added. Copies the folder into the app's own and hands the tool to
    /// the host and the registry. Its program is started by the host's run
    /// rule, or by its first command. Nothing is copied, and nothing
    /// changes, when it is refused.
    @discardableResult
    package func add(_ consent: ToolConsent) -> Result<Installed, Refusal> {
        let offer = consent.offer
        let id = offer.tool.manifest.id
        // What is added is what was shown. The folder could have changed
        // while the person read the sheet, so its manifest is read again.
        guard ToolFingerprint.ofManifest(in: offer.folder) == offer.fingerprint else {
            return .failure(.changedSinceOffered)
        }
        guard installed[id] == nil, parts.registry().tool(id) == nil, parts.host().manifest(for: id) == nil else {
            return .failure(.alreadyInstalled(id))
        }
        guard let folders = parts.folders else { return .failure(.noSupportFolder) }
        let place: ToolFolders.Place
        switch folders.install(id, from: offer.folder) {
        case .success(let made): place = made
        case .failure(let problem): return .failure(.files(problem))
        }
        // The copy is what runs, so the copy is what is read: a link that
        // pointed inside the picked folder may point outside the copy. And
        // the copy's manifest must be the one agreed to, byte for byte.
        guard ToolFingerprint.ofManifest(in: place.files) == offer.fingerprint else {
            return .failure(.changedSinceOffered)
        }
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
    /// Both steps at once, with no person asked. Only the development
    /// switch below may use it; the screen that asks replaces both.
    @discardableResult
    package func install(from folder: URL) -> Result<Installed, Refusal> {
        offer(from: folder).flatMap { add(ToolConsent(to: $0)) }
    }

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
