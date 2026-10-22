// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 VitruvianSoftware

import Combine
import Foundation
import os
import VitruvianCore
import VitruvianToolProtocol

/// The tools from outside that the person added: which they are, that the
/// person agreed to each, whether each is switched on, and where their
/// files are. It answers "installed?" for the capability broker.
///
/// A tool is added in two steps. `offer(from:)` reads a folder and changes
/// nothing. `add` takes the person's consent to that offer, copies the
/// folder and remembers the tool in a file, so the next launch has it too
/// (`restore`).
@MainActor
package final class ExternalToolStore {
    /// What this app has beyond the first release of the protocol version,
    /// as its hello names it. The app's own list, not every name the
    /// protocol has: a name added to the protocol is claimed only once the
    /// app draws it.
    nonisolated package static let features: [ProtocolFeature] = [.status, .choice, .preferenceOptions,
                                                                  .statusActivity, .openSettings,
                                                                  .chips, .sections, .notice, .slot,
                                                                  .folderPicker]
    /// Names of the protocol this app knows but does not claim at hello,
    /// because it does not draw them yet: a tool that asks first sends it
    /// what it sends an app without them. The change that draws one moves
    /// it into `features`. Empty while the app draws every name the
    /// protocol has; the next name added to the protocol starts here.
    nonisolated package static let notDrawnYet: [ProtocolFeature] = []

    /// Why a folder was not added.
    package enum Refusal: Error, Equatable, Sendable {
        /// The folder is not a tool the app can add.
        case manifest(ManifestRefusal)
        /// The app has no support folder to keep a tool in.
        case noSupportFolder
        /// The tool's files could not be put in the app's folder.
        case files(ToolFolders.Problem)
        /// Something else in the app already answers to this id.
        case alreadyInstalled(ToolID)
        /// The folder holds more than a tool's folder may. These are the
        /// most it may: so many bytes, and so many things.
        case tooBig(bytes: Int, items: Int)
        /// macOS has quarantined the tool's program, as it does to what is
        /// downloaded, and will not start it. The folder is the one picked.
        case quarantined(URL)
        /// The folder's manifest is no longer the one the person was shown.
        case changedSinceOffered
        /// The tool could not be written to the file of records, so the
        /// next launch would not have it.
        case notRemembered
    }

    /// What removing a tool did, so that whoever asked can say so.
    package enum Removal: Equatable, Sendable {
        /// Nobody added a tool with this id. Nothing changed.
        case notAdded
        /// The tool is removed, and what it saved is kept, as was asked.
        case keptAsAsked
        /// The tool is removed, and what it saved was to be deleted too, and
        /// its program was gone, so that was done: nothing of it is left.
        case deleted
        /// The tool is removed. What it saved was to be deleted too, and is
        /// kept all the same, its preferences with it, because the tool's
        /// program was still there after the kill. `data` is the folder
        /// that holds what it saved.
        case keptStillRunning(data: URL?)
        /// The tool is removed and its program is gone, but something that
        /// was to be deleted is still there: a folder that is read-only, or
        /// a file in use. `folders` is what is left, the app's copy of the
        /// tool first: one folder, or both. The tool's preferences stay
        /// while the folder of what it saved does.
        case notDeleted(folders: [URL])

        /// True when the tool was removed.
        package var removed: Bool { self != .notAdded }
    }

    /// One of a tool's own settings that its author gave a title, as the
    /// tool's detail shows it.
    package struct Setting: Equatable, Sendable {
        /// The preference's id within the tool, as its manifest and the
        /// protocol's messages name it.
        package let id: String
        /// What it is called, in every language its author wrote.
        package let title: LocalizedText
        /// The saved value, or the manifest's default when none is saved.
        package let value: PreferenceDeclaration.Value
        /// The values the person chooses among, for a text setting whose
        /// author gave some: it is then drawn as a pop-up menu. Empty for a
        /// setting with none. The saved value may be none of them.
        package let options: [PreferenceOption]
        /// How the person picks the value besides typing it: `folder`, a
        /// Choose… button beside the field. Nil for a setting with none.
        package let picker: PreferencePicker?

        package init(id: String, title: LocalizedText, value: PreferenceDeclaration.Value,
                     options: [PreferenceOption] = [], picker: PreferencePicker? = nil) {
            self.id = id
            self.title = title
            self.value = value
            self.options = options
            self.picker = picker
        }
    }

    package struct Installed: Equatable, Sendable {
        package let tool: ExternalToolManifest
        /// The app's copy of the tool's folder. The program runs from here.
        package let files: URL
        /// The folder the tool keeps what it saves in, and runs in.
        package let data: URL

        package init(tool: ExternalToolManifest, files: URL, data: URL) {
            self.tool = tool
            self.files = files
            self.data = data
        }
    }

    /// A tool the person added, as Settings lists it.
    package struct Listed: Equatable, Sendable {
        package let id: ToolID
        /// What the app remembers of it: its switch, and what was agreed.
        package let record: ToolRecord
        /// The tool as the app's copy describes it. Nil for a tool that is
        /// held back.
        package let tool: ExternalToolManifest?
        /// True when the app's copy is not what the person agreed to: its
        /// manifest has other bytes, cannot be read, or is gone. Such a
        /// tool is never started. Updating it from its folder, with the
        /// person's consent, is what brings it back.
        package let isHeld: Bool
        /// How its program stands; nil for a tool that is switched off or
        /// held back.
        package let standing: ExternalTool.Standing?
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
        /// Told, once for each tool, that it stopped working, after the
        /// person has been.
        package var stoppedWorking: @MainActor (ToolID) -> Void
        /// Deletes every preference a tool saved.
        package var forgetPreferences: @MainActor (ToolID) -> Void
        /// Clears the shortcuts the person gave a tool's commands.
        package var forgetShortcuts: @MainActor (ToolID) -> Void
        /// Has the store told each time the person changes the app's
        /// language, with the new language's tag. What it gives back is
        /// kept for as long as the store is: letting go of it ends the
        /// watching.
        package var watchLanguage: @MainActor (@escaping @MainActor (String) -> Void) -> Any?
        /// What draws the tools' panels and badges; nil where nothing does.
        package var panels: @MainActor () -> ToolPanelHost?
        /// Asked before a tool is added, with its id: calls back on the
        /// main thread once what `added` hands the tool can be read without
        /// waiting. At once, unless a feature of the app's must first fetch
        /// something that may take a while, as the GitHub hand-off did while
        /// the Keychain held the old feature's token behind its prompt.
        package var beforeAdding: @MainActor (ToolID, @escaping @MainActor () -> Void) -> Void
        /// Told of a tool just added, with the catalog entry it came from,
        /// before its program is started: a feature of the app's that the
        /// tool takes over hands it what it kept here (as the GitHub
        /// hand-off did, until the first release after 3.50.1).
        package var added: @MainActor (Installed, CatalogueOrigin?) -> Void
        /// Told of a tool just removed, after its program is gone.
        package var removed: @MainActor (ToolID) -> Void

        package init(folders: ToolFolders?, host: @escaping @MainActor () -> ToolHost,
                     registry: @escaping @MainActor () -> ToolRegistry,
                     broker: @escaping @MainActor () -> CapabilityBroker, clock: any ToolClock,
                     limits: ToolLimits = .standard,
                     makeTransport: @escaping @MainActor (URL, URL) -> any ToolTransport,
                     language: @escaping @MainActor () -> String,
                     stoppedWorking: @escaping @MainActor (ToolID) -> Void,
                     forgetPreferences: @escaping @MainActor (ToolID) -> Void = { _ in },
                     forgetShortcuts: @escaping @MainActor (ToolID) -> Void = { _ in },
                     watchLanguage: @escaping @MainActor (@escaping @MainActor (String) -> Void) -> Any? = { _ in nil },
                     panels: @escaping @MainActor () -> ToolPanelHost? = { nil },
                     beforeAdding: @escaping @MainActor (ToolID, @escaping @MainActor () -> Void) -> Void = { _, ready in
                         ready()
                     },
                     added: @escaping @MainActor (Installed, CatalogueOrigin?) -> Void = { _, _ in },
                     removed: @escaping @MainActor (ToolID) -> Void = { _ in }) {
            self.folders = folders
            self.host = host
            self.registry = registry
            self.broker = broker
            self.clock = clock
            self.limits = limits
            self.makeTransport = makeTransport
            self.language = language
            self.stoppedWorking = stoppedWorking
            self.forgetPreferences = forgetPreferences
            self.forgetShortcuts = forgetShortcuts
            self.watchLanguage = watchLanguage
            self.panels = panels
            self.beforeAdding = beforeAdding
            self.added = added
            self.removed = removed
        }

        /// The app as it is. That a tool stopped working is also a line
        /// in the system log, for whoever is making the tool.
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
            },
            forgetPreferences: { ExternalToolStore.forgetPreferences(of: $0, in: .standard) },
            forgetShortcuts: { ToolShortcutRegistrar.shared.forget($0) },
            watchLanguage: { ExternalToolStore.watch(L10n.shared.$language, then: $0) },
            panels: { .shared },
            // The Nexus Agent feature hands its settings to the Nexus Agent
            // tool, as the GitHub feature did to its tool until 3.50.1.
            beforeAdding: { _, ready in ready() },
            added: { installed, origin in NexusAgentHandoff.perform(installed, from: origin, parts: .live) },
            removed: { NexusAgentHandoff.toolRemoved($0, defaults: .standard) })
    }

    /// Hears each language the app changes to, as its tag, on the main
    /// thread. The language it starts with is not a change, and neither is
    /// the same language set again. The watching ends when what this gives
    /// back is let go.
    package static func watch(_ languages: Published<AppLanguage>.Publisher,
                              then changed: @escaping @MainActor (String) -> Void) -> AnyCancellable {
        languages.removeDuplicates().dropFirst().receive(on: DispatchQueue.main)
            .sink { language in MainActor.assumeIsolated { changed(language.rawValue) } }
    }

    /// Deletes every preference saved under a tool's id: the keys that
    /// start with the id and a slash (`ExternalToolManifest.storageKey`).
    /// No preference of the app's own, and none of another tool, has such
    /// a key: an id holds no slash.
    package static func forgetPreferences(of id: ToolID, in defaults: UserDefaults) {
        let prefix = id.rawValue + "/"
        for key in defaults.dictionaryRepresentation().keys where key.hasPrefix(prefix) {
            defaults.removeObject(forKey: key)
        }
    }

    /// Clears the HomeSpeaker extension entry from `speaker_door.json` when
    /// `dev.vitruvian.homespeaker` is removed, and resets `chosen` when it
    /// named the extension.
    nonisolated package static func clearHomeSpeakerDoorOnRemove(
        toolID: ToolID,
        doorFileURL: URL = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".gemini/speaker_door.json")
    ) {
        clearHomeSpeakerDoorOnRemove(toolID: toolID.rawValue, doorFileURL: doorFileURL)
    }

    nonisolated package static func clearHomeSpeakerDoorOnRemove(
        toolID: String,
        doorFileURL: URL = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".gemini/speaker_door.json")
    ) {
        guard toolID == "dev.vitruvian.homespeaker",
              FileManager.default.fileExists(atPath: doorFileURL.path) else {
            return
        }
        let lockURL = doorFileURL.appendingPathExtension("lock")
        let fd = open(lockURL.path, O_RDWR | O_CREAT | O_CLOEXEC, 0o600)
        guard fd >= 0 else { return }
        defer { close(fd) }
        while flock(fd, LOCK_EX) != 0 {
            guard errno == EINTR else { return }
        }
        defer { _ = flock(fd, LOCK_UN) }
        guard let data = try? Data(contentsOf: doorFileURL),
              var dict = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] else {
            return
        }
        dict.removeValue(forKey: "extension")
        if dict["chosen"] as? String == "extension" {
            dict.removeValue(forKey: "chosen")
            dict.removeValue(forKey: "chosen_at")
            dict.removeValue(forKey: "chosen_by")
        }
        guard let updated = try? JSONSerialization.data(
            withJSONObject: dict, options: [.prettyPrinted, .sortedKeys]
        ) else {
            return
        }
        try? updated.write(to: doorFileURL, options: [.atomic])
    }

    package static let shared: ExternalToolStore = ExternalToolStore(parts: .live)

    private let parts: Parts
    /// Every tool the person added, in the order they added them.
    private var records: [ToolRecord] = []
    /// The tools that are switched on and are what the person agreed to:
    /// the ones the host and the registry hold.
    package private(set) var installed: [ToolID: Installed] = [:]
    private var tools: [ToolID: ExternalTool] = [:]
    /// The manifests of the tools that are switched off, so Settings can
    /// still name them and list their commands.
    private var resting: [ToolID: ExternalToolManifest] = [:]
    /// The tools whose copy is not what the person agreed to.
    private var held: Set<ToolID> = []
    /// True when the file of records was there and could not be read. It
    /// is set aside, not written over, the first time a record is saved.
    private var recordsUnreadable = false
    /// The tools the person has been told stopped working, in this run of
    /// the app.
    private var told: Set<ToolID> = []
    /// Keeps the store told of a change of the app's language.
    private var watchingLanguage: Any?
    /// The adds that wait for `Parts.beforeAdding`, by tool: the last one
    /// asked for each. An add that is no longer here when its wait ends is
    /// dropped.
    private var waitingAdds: [ToolID: UUID] = [:]

    package init(parts: Parts) {
        self.parts = parts
        watchingLanguage = parts.watchLanguage { [weak self] in self?.languageChanged($0) }
    }

    /// True for a tool that is added, switched on, and what the person
    /// agreed to. A tool that is switched off is refused everything, as
    /// one that was never added is.
    package func isInstalled(_ id: ToolID) -> Bool {
        installed[id] != nil
    }

    /// How many times each tool was handed to the host in this run of the
    /// app: switched on, updated or added again, each is a new count. A view
    /// that keeps what it showed for a tool knows by it that the tool is
    /// another now.
    package private(set) var activations: [ToolID: Int] = [:]

    /// Whether any tool that is switched on and is what the person agreed
    /// to has an island page: `availableIslandPanels()` is not empty. Worked
    /// out once for each change of the registry, which the store bumps
    /// whenever a tool is added, removed, switched or held back.
    package var hasIslandPanels: Bool {
        let revision = parts.registry().revision
        if let known = islandPanelsKnown, known.revision == revision { return known.any }
        let any = !availableIslandPanels().isEmpty
        islandPanelsKnown = (revision, any)
        return any
    }

    private var islandPanelsKnown: (revision: Int, any: Bool)?

    /// The live tool with this id, for its log and how it stands.
    package func tool(_ id: ToolID) -> ExternalTool? {
        tools[id]
    }

    /// The tools switched on whose manifest puts them in the slot
    /// `placement`, in the order they were added.
    package func slotTools(_ placement: SlotPlacement) -> [ToolID] {
        records.compactMap { record in
            guard let id = ToolID(record.id), installed[id]?.tool.slot == placement else { return nil }
            return id
        }
    }

    /// Whether a tool in the slot `placement` is running now: the Agents
    /// page keeps its Chat tab for it while the feature is replaced.
    package func slotToolRunning(_ placement: SlotPlacement) -> Bool {
        slotTools(placement).contains { tools[$0]?.standing == .running }
    }

    /// Tells every running tool in the slot `placement` where it is now, or
    /// that it went (`ui/slot`). A tool that is not running is told nothing.
    package func tellSlot(_ placement: SlotPlacement, _ params: UISlotParams) {
        for id in slotTools(placement) { tools[id]?.slot(params) }
    }

    /// The app's copy of an added tool's files, for showing where it is;
    /// nil for a tool nobody added.
    package func folder(of id: ToolID) -> URL? {
        guard records.contains(where: { $0.id == id.rawValue }) else { return nil }
        return parts.folders?.place(for: id)?.files
    }

    /// Every tool the person added, in the order they added them.
    package var listed: [Listed] {
        records.compactMap { record in
            guard let id = ToolID(record.id) else { return nil }
            return Listed(id: id, record: record, tool: installed[id]?.tool ?? resting[id],
                          isHeld: held.contains(id), standing: tools[id]?.standing)
        }
    }

    // MARK: - At launch

    /// Brings back the tools the person added before: reads the file of
    /// records and hands each tool that is switched on to the host and the
    /// registry. Called once, at launch. With no file it does nothing.
    ///
    /// A file that cannot be read means no tools, and nothing is deleted:
    /// the file stays, each tool's copy stays, and what each tool saved
    /// stays.
    package func restore() {
        guard records.isEmpty, let folders = parts.folders else { return }
        switch ToolRecords.read(at: folders.records) {
        case .none:
            return
        case .unreadable:
            recordsUnreadable = true
            Logger(subsystem: Bundle.main.bundleIdentifier ?? "vitruvian", category: "tools")
                .error("the record of added tools could not be read: no tool from outside is loaded")
            return
        case .records(let saved):
            records = saved
        }
        for record in records { load(record) }
        parts.registry().noteAvailabilityChanged()
    }

    /// Hands one remembered tool to the host and the registry, when its
    /// copy is what the person agreed to and its switch is on.
    private func load(_ record: ToolRecord) {
        guard let id = ToolID(record.id) else { return }
        held.remove(id)
        resting[id] = nil
        // The copy is what runs, so the copy is what is checked: its
        // manifest must be, byte for byte, the one the person agreed to.
        guard let place = parts.folders?.existing(id),
              ToolFingerprint.ofManifest(in: place.files) == record.agreement.fingerprint,
              case .success(let tool) = ExternalToolManifest.read(folder: place.files),
              tool.manifest.id == id else {
            held.insert(id)
            return
        }
        guard record.isOn else {
            resting[id] = tool
            return
        }
        if !activate(Installed(tool: tool, files: place.files, data: place.data)) { held.insert(id) }
    }

    // MARK: - Adding

    /// The first of the two steps of adding a tool: reads the tool in the
    /// folder the person picked and says what adding it would mean. Nothing
    /// is copied, nothing is run and nothing is saved. The second step is
    /// `add`, and it takes the person's consent to what this returns.
    ///
    /// `catalogue` is the entry a folder the catalog's installer unpacked
    /// came from; nil for a folder the person picked.
    package func offer(from picked: URL, catalogue: CatalogueOrigin? = nil) -> Result<ToolOffer, Refusal> {
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
        let known = records.first { $0.id == tool.manifest.id.rawValue }
        // A tool added from a folder, offered from the catalog: agreeing
        // moves it onto the catalog.
        let movesFromFolder = catalogue != nil && known?.catalogue == nil ? known?.agreement.source : nil
        return .success(ToolOffer(folder: folder, tool: tool, fingerprint: fingerprint, replaces: known?.agreement,
                                  catalogue: catalogue, movesFromFolder: movesFromFolder))
    }

    /// The second step, as the app takes it: `add`, once whatever the app
    /// hands the tool is ready to be handed (`Parts.beforeAdding`). It
    /// returns at once and never holds the main thread; `done` is called on
    /// it, once, with what `add` answered. Usually that is before this
    /// returns; it may be much later when `Parts.beforeAdding` has to fetch
    /// something first.
    ///
    /// Nothing is copied, saved or started while it waits. `done` is given
    /// nil, and nothing is added, when the wait was overtaken: the tool was
    /// removed meanwhile, or the person agreed to it again, and then that
    /// later add is the one that counts. So a tool is added, and handed
    /// over to, once.
    package func add(_ consent: ToolConsent, then done: @escaping @MainActor (Result<Installed, Refusal>?) -> Void) {
        let id = consent.offer.tool.manifest.id
        let turn = UUID()
        waitingAdds[id] = turn
        parts.beforeAdding(id) { [weak self] in
            guard let self, self.waitingAdds[id] == turn else { return done(nil) }
            self.waitingAdds[id] = nil
            done(self.add(consent))
        }
    }

    /// True while an add of this tool waits (`add(_:then:)`).
    package func isAdding(_ id: ToolID) -> Bool {
        waitingAdds[id] != nil
    }

    /// The second step: the person agreed to an offer, so the tool is
    /// added, in place of the one with its id when there is one. Copies the
    /// folder into the app's own, remembers the tool and what was agreed,
    /// and hands it to the host and the registry. Its program is started by
    /// the host's run rule, or by its first command.
    ///
    /// The app reaches this through `add(_:then:)`, which waits for
    /// `Parts.beforeAdding` first. Called alone it waits for nothing, and
    /// `Parts.added` hands over only what is at hand already.
    ///
    /// When it is refused before anything is copied, nothing changes: a
    /// tool that was there before is as it was. A copy that turns out not
    /// to be what was agreed to is left in place and held back.
    @discardableResult
    package func add(_ consent: ToolConsent) -> Result<Installed, Refusal> {
        let offer = consent.offer
        let id = offer.tool.manifest.id
        // What is added is what was shown. The folder could have changed
        // while the person read the sheet, so its manifest is read again.
        guard ToolFingerprint.ofManifest(in: offer.folder) == offer.fingerprint else {
            return .failure(.changedSinceOffered)
        }
        let known = records.firstIndex { $0.id == id.rawValue }
        // An id the store does not hold and something else answers to.
        guard installed[id] != nil || (parts.registry().tool(id) == nil && parts.host().manifest(for: id) == nil) else {
            return .failure(.alreadyInstalled(id))
        }
        guard let folders = parts.folders else { return .failure(.noSupportFolder) }
        // The program of the tool this replaces is stopped before its
        // files are.
        deactivate(id, seeingItOut: true)
        func failed(_ refusal: Refusal) -> Result<Installed, Refusal> {
            // Whatever is in the tool's place now is judged afresh against
            // what the person agreed to before.
            if let known { load(records[known]) }
            parts.registry().noteAvailabilityChanged()
            return .failure(refusal)
        }
        let place: ToolFolders.Place
        switch folders.install(id, from: offer.folder) {
        case .success(let made): place = made
        case .failure(let problem): return failed(.files(problem))
        }
        // The copy is what runs, so the copy is what is read: a link that
        // pointed inside the picked folder may point outside the copy. And
        // the copy's manifest must be the one agreed to, byte for byte.
        guard ToolFingerprint.ofManifest(in: place.files) == offer.fingerprint else {
            return failed(.changedSinceOffered)
        }
        let tool: ExternalToolManifest
        switch ExternalToolManifest.read(folder: place.files) {
        case .success(let copied) where copied.manifest.id == id: tool = copied
        case .success: return failed(.manifest(.noManifest))
        case .failure(let refusal): return failed(.manifest(refusal))
        }

        // A tool from the catalog came from its download, not from the
        // installer's folder, which is gone once the sheet closes.
        let agreement = ToolAgreement(date: consent.date, name: tool.manifest.tool.name, version: tool.version,
                                      publisher: tool.publisher, fingerprint: offer.fingerprint,
                                      source: offer.catalogue?.download ?? offer.folder.path)
        var next = records
        if let known {
            next[known].agreement = agreement
            // Updated from a folder, a tool from the catalog is one added
            // by hand from then on. Updated from the catalog, a tool added
            // from a folder is one from the catalog from then on.
            next[known].catalogue = offer.catalogue
        } else {
            next.append(ToolRecord(id: id.rawValue, isOn: true, agreement: agreement, catalogue: offer.catalogue))
        }
        guard save(next) else { return failed(.notRemembered) }
        records = next
        held.remove(id)
        resting[id] = nil
        let entry = Installed(tool: tool, files: place.files, data: place.data)
        // Before the program starts, so what is handed over is there for
        // its first run.
        parts.added(entry, offer.catalogue)
        let record = records.first { $0.id == id.rawValue }
        if record?.isOn == false {
            // Updated while switched off: it stays off.
            resting[id] = tool
        } else if !activate(entry) {
            held.insert(id)
            parts.registry().noteAvailabilityChanged()
            return .failure(.alreadyInstalled(id))
        }
        parts.registry().noteAvailabilityChanged()
        return .success(entry)
    }

    // MARK: - Switching and removing

    /// The tool's switch in Settings. Off stops its program at once and
    /// takes its commands out of every list; on brings them back. The
    /// tool's files, and what it saved, are not touched either way.
    package func setOn(_ id: ToolID, _ isOn: Bool) {
        guard let known = records.firstIndex(where: { $0.id == id.rawValue }), records[known].isOn != isOn else {
            return
        }
        var next = records
        next[known].isOn = isOn
        guard save(next) else { return }
        records = next
        deactivate(id)
        load(records[known])
        parts.registry().noteAvailabilityChanged()
    }

    /// Removes a tool the person added: stops its program, takes it out of
    /// the host and the registry, forgets it, and deletes the app's copy of
    /// its files. With `deletingData`, what the tool saved goes too: its
    /// data folder, and the preferences saved under its id. Without, both
    /// stay, and adding the tool again finds them.
    ///
    /// Nothing is deleted while the tool's program runs: it is told
    /// goodbye, then asked to end, then killed, and the app waits a short
    /// while for each (`ToolHost.removeAndSeeOut`). Should it still be
    /// there after the kill, what it saved is kept whatever was asked, so
    /// that a program is never left writing into a folder that is gone.
    ///
    /// The shortcuts the person gave the tool's commands are cleared either
    /// way: a tool that is removed has no row to show or clear them on.
    /// Switching a tool off, or updating it, clears none.
    ///
    /// The folder the tool was added from is never touched. What it gives
    /// back says which of these happened, so that the person can be told
    /// when what a tool saved was kept against what they asked, or when a
    /// folder that was to go could not be deleted.
    ///
    /// The record goes first, before anything is deleted, so a tool that
    /// is only half deleted has no record at the next launch: it is never
    /// listed and never started. The preferences under the tool's id are
    /// deleted only together with the folder of what it saved. When that
    /// folder stays, for any reason, they stay with it, and adding the
    /// tool again finds both. Nothing deletes either later.
    @discardableResult
    package func remove(_ id: ToolID, deletingData: Bool) -> Removal {
        // An add of it that still waits is dropped: its late answer adds
        // nothing and hands nothing over.
        waitingAdds[id] = nil
        guard let known = records.firstIndex(where: { $0.id == id.rawValue }) else { return .notAdded }
        var next = records
        next.remove(at: known)
        guard save(next) else { return .notAdded }
        records = next
        let gone = deactivate(id, seeingItOut: true)
        held.remove(id)
        resting[id] = nil
        // Its commands have no row on the Shortcuts page any more, so the
        // keys the person gave them are given back, whatever else is kept.
        parts.forgetShortcuts(id)
        let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "vitruvian", category: "tools")
        // What it saved goes only once its program is gone.
        let data = deletingData && gone
        if deletingData, !gone {
            logger.error("the removed tool \(id.rawValue, privacy: .public) is still running: what it saved is kept")
        }
        // What is still there although it was to go: the copy, and with
        // `data` the folder of what the tool saved.
        var left: [URL] = []
        if parts.folders?.delete(id, data: data) != true {
            logger.error("some files of the removed tool \(id.rawValue, privacy: .public) could not be deleted")
            left = parts.folders?.undeleted(id, data: data) ?? []
        }
        Self.clearHomeSpeakerDoorOnRemove(toolID: id)
        // A tool's preferences stay exactly as long as the folder of what
        // it saved does, whatever kept the folder.
        let dataFolder = parts.folders?.place(for: id)?.data
        if data, !left.contains(where: { $0 == dataFolder }) { parts.forgetPreferences(id) }
        parts.removed(id)
        parts.registry().noteAvailabilityChanged()
        // A program that would not stop comes first: it is the one case
        // where something of the tool may still be running.
        if deletingData, !gone { return .keptStillRunning(data: dataFolder) }
        guard left.isEmpty else { return .notDeleted(folders: left) }
        return deletingData ? .deleted : .keptAsAsked
    }

    // MARK: - A tool's page in the island

    /// Whether the island lists the tool's page as a section. Yes until the
    /// person turns it off in the tool's detail.
    package func showsInIsland(_ id: ToolID) -> Bool {
        records.first { $0.id == id.rawValue }?.showsInIsland ?? true
    }

    /// The island pages the Tools area lists: of each tool that is switched
    /// on and is what the person agreed to, the one island page it has,
    /// unless the person turned it off, in the order the tools were added.
    package func islandPanels() -> [ToolPanelHost.Key] {
        records.compactMap { record in
            guard let id = ToolID(record.id), record.showsInIsland ?? true,
                  let panel = installed[id]?.tool.panel(in: .island) else { return nil }
            return ToolPanelHost.Key(tool: id, panel: panel.id)
        }
    }

    /// Every island page there is to list, whether or not the person turned
    /// it off: of each tool that is switched on and is what the person
    /// agreed to, the one island page it has, in the order the tools were
    /// added. What the island's editor offers to show or hide; a tool that
    /// is switched off or held back is not in `installed`, so not here.
    package func availableIslandPanels() -> [ToolPanelHost.Key] {
        records.compactMap { record in
            guard let id = ToolID(record.id), let panel = installed[id]?.tool.panel(in: .island) else { return nil }
            return ToolPanelHost.Key(tool: id, panel: panel.id)
        }
    }

    /// The switch in the tool's detail. Off closes the tool's island page
    /// when it is open, and the island lists it no more.
    package func setShowsInIsland(_ id: ToolID, _ shows: Bool) {
        guard let known = records.firstIndex(where: { $0.id == id.rawValue }), showsInIsland(id) != shows else { return }
        var next = records
        next[known].showsInIsland = shows ? nil : false
        guard save(next) else { return }
        records = next
        if !shows, let island = installed[id]?.tool.panel(in: .island) {
            parts.panels()?.close(ToolPanelHost.Key(tool: id, panel: island.id))
        }
        parts.registry().noteAvailabilityChanged()
    }

    // MARK: - A tool's status on the closed island

    /// Whether the closed island shows the tool's status. Yes until the
    /// person turns it off in the tool's detail.
    package func showsStatus(_ id: ToolID) -> Bool {
        records.first { $0.id == id.rawValue }?.showsStatus ?? true
    }

    /// The tools whose status the closed island may draw: each that is
    /// switched on and is what the person agreed to, declares a status, and
    /// has it switched on, in the order the tools were added. The status
    /// itself is the panel host's (`ToolPanelHost.statuses`).
    package func statusTools() -> [ToolID] {
        records.compactMap { record in
            guard let id = ToolID(record.id), record.showsStatus ?? true,
                  installed[id]?.tool.showsStatus == true else { return nil }
            return id
        }
    }

    /// The switch in the tool's detail. The tool is not told: off, its
    /// `ui/status` is still answered and kept, and nothing is drawn; on
    /// again, the status it last set is drawn with no restart.
    package func setShowsStatus(_ id: ToolID, _ shows: Bool) {
        guard let known = records.firstIndex(where: { $0.id == id.rawValue }), showsStatus(id) != shows else { return }
        var next = records
        next[known].showsStatus = shows ? nil : false
        guard save(next) else { return }
        records = next
        // Whoever draws the closed island looks again.
        parts.registry().noteAvailabilityChanged()
    }

    // MARK: - A tool's own settings

    /// The settings of an added tool that the person may see and change:
    /// the preferences its manifest gives a title, in the manifest's order,
    /// each with its saved value or its default. A preference with no title
    /// is never here. None for a tool that is held back, whose manifest is
    /// not the one agreed to, and for a tool nobody added.
    package func settings(of id: ToolID) -> [Setting] {
        guard let tool = installed[id]?.tool ?? resting[id] else { return [] }
        let storage = storage(of: tool)
        return tool.manifest.preferences.compactMap { declared in
            // The id within the tool: what follows the tool's id and a slash.
            let name = String(declared.key.dropFirst(id.rawValue.count + 1))
            guard let title = tool.preferenceTitles[declared.key] else { return nil }
            guard case .success(let value) = storage.value(for: declared.key) else { return nil }
            return Setting(id: name, title: title, value: value, options: tool.preferenceOptions[declared.key] ?? [],
                           picker: tool.preferencePickers[declared.key])
        }
    }

    /// The person changed one of a tool's settings in its detail. Returns
    /// why it was not saved, or nil when it was, or was that value already.
    ///
    /// It is saved where the tool itself saves it, under the same key and
    /// by the same rules: a value of another kind is refused, and so is
    /// text over the protocol's limit. Only a preference with a title can
    /// be changed here, since only those are shown. A tool whose program
    /// is running and has answered `initialize` is then sent the
    /// protocol's `preferences/changed`, a notice the app does not wait
    /// on. Any other tool is sent nothing and nothing is started: it reads
    /// the value when it next starts.
    @discardableResult
    package func setSetting(_ value: PreferenceDeclaration.Value, for preference: String,
                            of id: ToolID) -> StorageProblem? {
        guard let tool = installed[id]?.tool ?? resting[id] else { return .undeclared(preference) }
        let key = ExternalToolManifest.storageKey(tool: id, preference: preference)
        guard tool.preferenceTitles[key] != nil else { return .undeclared(preference) }
        // No message can carry a number that is no number.
        if case .double(let number) = value, !number.isFinite { return .wrongKind(key) }
        let storage = storage(of: tool)
        if case .success(let saved) = storage.value(for: key), saved == value { return nil }
        if let problem = storage.set(value, for: key) { return problem }
        tools[id]?.preferencesChanged([preference: ExternalToolCalls.json(value)])
        parts.panels()?.tellPages(of: id, .preferencesChanged,
                                  .object(["values": .object([preference: ExternalToolCalls.json(value)])]))
        return nil
    }

    /// A tool's preferences as the person reaches them from its detail:
    /// the keys, kinds and limits the tool's own `storage` has, over the
    /// same saved values. It is not behind the tool's `uses` or its switch.
    /// Those say what the tool may ask of the app, and here it is the
    /// person who acts.
    private func storage(of tool: ExternalToolManifest) -> StorageAccess {
        StorageAccess(gate: { nil }, manifest: tool.manifest, backing: parts.broker().backings.storage)
    }

    // MARK: - The app's language

    /// The person changed the app's language. Each tool whose program is
    /// running is sent the protocol's `language/changed`, a notice the app
    /// does not wait on, once for each change; one that has not answered
    /// `initialize` yet hears it when it has. Any other tool, one that is
    /// resting, stopped, switched off or held back, is sent nothing and is
    /// not started: `initialize` carries the language when it next starts.
    package func languageChanged(_ language: String) {
        for id in tools.keys.sorted(by: { $0.rawValue < $1.rawValue }) {
            tools[id]?.languageChanged(language)
            parts.panels()?.tellPages(of: id, .languageChanged, .object(["language": .string(language)]))
        }
    }

    // MARK: - A tool that stopped working

    /// The symbol beside the sentence that says a tool stopped working.
    package static let stoppedSymbol = "exclamationmark.triangle"

    /// Tells the person, once for each tool in each run of the app, that a
    /// tool stopped working: one sentence, in the app's short on-screen
    /// message, at the tool's first crash. The message is the app's own, so
    /// it does not depend on what the tool's manifest lists in `uses`.
    private func tellStopped(_ id: ToolID) {
        guard told.insert(id).inserted else { return }
        let tag = parts.language()
        let name = installed[id]?.tool.name.text(for: tag) ?? installed[id]?.tool.manifest.tool.name ?? id.rawValue
        let strings = FeatureStrings.externalTools(AppLanguage(rawValue: tag) ?? .enUS)
        parts.broker().backings.notify.hud(Self.stoppedSymbol, strings.stopped(ToolOwnWords.oneLine(name)))
        parts.stoppedWorking(id)
    }

    /// Lets a tool that crashed too often try again, as if it had never
    /// crashed. For the button in Settings beside a tool that stopped
    /// working. It does nothing for a tool that has not given up.
    package func startAgain(_ id: ToolID) {
        tools[id]?.revive()
    }

    // MARK: - The host, the registry and the file

    /// Hands a tool to the host and the registry. False, with nothing
    /// changed, when either already holds something with its id.
    private func activate(_ entry: Installed) -> Bool {
        let manifest = entry.tool.manifest
        let id = manifest.id
        let hosted = makeTool(entry)
        guard parts.host().add(hosted, manifest: manifest) else { return false }
        do {
            try parts.registry().register(entry.tool, host: parts.host)
        } catch {
            parts.host().remove(id)
            parts.registry().unregister(id)
            return false
        }
        installed[id] = entry
        tools[id] = hosted
        activations[id, default: 0] += 1
        parts.host().sync(id)
        return true
    }

    /// Stops a tool's program and takes it out of the host and the
    /// registry. The store still remembers it. With `seeingItOut` it also
    /// waits a short while for the program to be gone. True when nothing
    /// of the tool is left running, as far as was asked.
    @discardableResult
    private func deactivate(_ id: ToolID, seeingItOut: Bool = false) -> Bool {
        guard installed.removeValue(forKey: id) != nil else { return true }
        tools[id] = nil
        parts.panels()?.forget(id)
        parts.registry().unregister(id)
        guard seeingItOut else {
            parts.host().remove(id)
            return true
        }
        return parts.host().removeAndSeeOut(id)
    }

    /// Writes the records to their file. A file that could not be read at
    /// launch is moved aside first, never written over.
    private func save(_ next: [ToolRecord]) -> Bool {
        guard let folders = parts.folders,
              PrivateFileStore.createDirectory(at: folders.root, container: folders.root) else { return false }
        if recordsUnreadable {
            let aside = folders.root.appendingPathComponent(ToolRecords.unreadableFileName)
            try? FileManager.default.removeItem(at: aside)
            guard (try? FileManager.default.moveItem(at: folders.records, to: aside)) != nil else { return false }
            recordsUnreadable = false
        }
        return ToolRecords.write(next, to: folders.records)
    }

    private func makeTool(_ entry: Installed) -> ExternalTool {
        let parts = self.parts
        let told: @MainActor (ToolID) -> Void = { [weak self] in self?.tellStopped($0) }
        let manifest = entry.tool.manifest
        let id = manifest.id
        let program = entry.files.appendingPathComponent(entry.tool.program)
        let data = entry.data
        return ExternalTool(
            manifest: manifest, clock: parts.clock, limits: parts.limits,
            makeLink: { events in
                let calls = ExternalToolCalls(manifest: manifest, broker: parts.broker(),
                                              badge: { parts.panels()?.badge(id, $0) },
                                              status: { parts.panels()?.status(id, $0)?.error },
                                              notice: { parts.panels()?.notice(id, $0) },
                                              dock: { parts.panels()?.dock(id)?.error })
                return ToolLink(
                    transport: parts.makeTransport(program, data), clock: parts.clock, limits: parts.limits,
                    hello: InitializeParams(protocolVersions: ProtocolVersion.supported, language: parts.language(),
                                            dataFolder: data.path,
                                            features: Self.features.map(\.rawValue)),
                    serve: { method, params, reply in calls.serve(method, params, reply) },
                    events: events)
            },
            events: .init(
                // Whoever lists its commands looks again.
                onChange: { parts.registry().noteAvailabilityChanged() },
                onStoppedWorking: { told(id) },
                // A command that did not run beeps, as a built-in one does.
                onCommandFailed: { parts.broker().backings.notify.beep() },
                onRender: { panel, tree in parts.panels()?.rendered(id, panel: panel, tree: tree) },
                onRunEnded: { parts.panels()?.toolEnded(id) }))
    }
}
