// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 VitruvianSoftware

import Foundation
import VitruvianToolProtocol

/// Why a folder is not a tool the app can add. Each case carries what is
/// needed to say which part is wrong; the words are for whoever shows it.
package enum ManifestRefusal: Error, Equatable, Sendable {
    /// The folder has no `vitruvian-tool.json`, or the file cannot be read.
    case noManifest
    /// The file breaks one of the manifest's own rules.
    case invalid(ManifestProblem)
    /// The manifest names something the protocol has and this app does not:
    /// a service, a surface, a kind of preference, or a way of starting.
    case notOfferedHere(String)
    /// There is no file at the program's path.
    case programMissing(String)
    /// The program is, through a link, a file outside the tool's folder.
    case programOutsideFolder(String)
    /// The program is not a file macOS will run.
    case programNotExecutable(String)
}

/// One value a preference with options may be set to, and what the person
/// reads for it, in every language its author wrote.
package struct PreferenceOption: Equatable, Sendable {
    package let value: String
    package let title: LocalizedText

    package init(value: String, title: LocalizedText) {
        self.value = value
        self.title = title
    }
}

/// A tool that runs as its own program, as its manifest file describes it:
/// the manifest the platform already has for a built-in tool, and what only
/// an outside tool carries.
///
package struct ExternalToolManifest: Equatable, Sendable {
    /// The tool as the rest of the platform knows a tool. Its name and its
    /// commands' titles are the English ones.
    package let manifest: ToolManifest
    /// The tool's name in every language its author wrote it in.
    package let name: LocalizedText
    /// One sentence on what the tool does.
    package let summary: LocalizedText?
    /// Each command's title in every language its author wrote it in.
    package let commandTitles: [CommandID: LocalizedText]
    /// The title of each preference its author gave one, in every language
    /// they wrote it in, by the key the preference is saved under. A
    /// preference with no title is not here: it is the tool's alone, and
    /// the person is never shown it.
    package let preferenceTitles: [String: LocalizedText]
    /// The options of each preference its author gave some, in the order
    /// written, by the key the preference is saved under. They are how the
    /// app draws the setting, as a pop-up menu, and no rule on its value.
    package let preferenceOptions: [String: [PreferenceOption]]
    /// The picker of each text preference its author gave one, by the key
    /// the preference is saved under: `folder` draws a Choose… button
    /// beside the field.
    package let preferencePickers: [String: PreferencePicker]
    /// Whether the manifest declares a status: the tool may set a small
    /// mark on the closed island with `ui/status`.
    package let showsStatus: Bool
    /// Whether that status may carry a few words for the closed island:
    /// `contributes.status.activity` is true.
    package let showsActivity: Bool
    /// The app's slot the tool is drawn in, when its manifest declares one:
    /// `agents`, the Chat tab of the island's Agents page (`ui/slot`,
    /// `ui/dock`).
    package let slot: SlotPlacement?
    /// What the tool draws, and where: protocol 2's panels, in the order
    /// the manifest lists them. None for a tool of protocol 1.
    package let panels: [ToolPanelDescriptor]
    package let version: String
    package let publisher: String
    package let license: String?
    /// The protocol version the tool speaks.
    package let protocolVersion: String

    /// The tool's panel with this id; nil for one the manifest does not
    /// declare.
    package func panel(_ id: String) -> ToolPanelDescriptor? {
        panels.first { $0.id == id }
    }

    /// The tool's panel in a place where it has at most one: the island or
    /// Settings.
    package func panel(in placement: ToolPanelPlacement) -> ToolPanelDescriptor? {
        panels.first { $0.placement == placement }
    }
    /// The program to start, as a path inside the tool's folder.
    package let program: String

    /// What a tool or a command with no icon draws.
    package static let defaultSymbol = "puzzlepiece.extension"
    /// The hub group every outside tool is filed under.
    package static var group: FeatureGroup { .tools }

    /// The key a tool's preference is saved under: the tool's id, a slash,
    /// and the preference's id, as a command's id is written. No built-in
    /// preference has a slash in its key, and no two tools share an id.
    package static func storageKey(tool: ToolID, preference: String) -> String {
        "\(tool.rawValue)/\(preference)"
    }

    /// Reads the tool in `folder`: its manifest, and that the program the
    /// manifest names is a file inside the folder that macOS will run.
    package static func read(folder: URL,
                             fileManager: FileManager = .default) -> Result<ExternalToolManifest, ManifestRefusal> {
        let path = folder.appendingPathComponent(ToolManifestFile.fileName).path
        // Asked before the file is read, so a huge file is never loaded.
        if let size = (try? fileManager.attributesOfItem(atPath: path))?[.size] as? Int,
           size > ManifestLimits.maxBytes {
            return .failure(.invalid(.tooLarge(bytes: size)))
        }
        guard let data = fileManager.contents(atPath: path) else { return .failure(.noManifest) }
        switch read(data) {
        case .failure(let refusal):
            return .failure(refusal)
        case .success(let tool):
            if let refusal = programRefusal(tool.program, in: folder, fileManager: fileManager) {
                return .failure(refusal)
            }
            return .success(tool)
        }
    }

    /// Reads a manifest's bytes: every rule that needs no folder.
    package static func read(_ data: Data) -> Result<ExternalToolManifest, ManifestRefusal> {
        switch ToolManifestFile.read(data) {
        case .failure(let problem): return .failure(.invalid(problem))
        case .success(let file): return tool(from: file)
        }
    }

    /// Maps a manifest file that passed its own rules onto the app's lists.
    /// Those lists are closed: a name the protocol has and the app does not
    /// is a refusal that names it, never a crash and never a tool with part
    /// of its manifest dropped.
    static func tool(from file: ToolManifestFile) -> Result<ExternalToolManifest, ManifestRefusal> {
        guard let id = ToolID(file.id), !id.isBundledForm else {
            return .failure(.invalid(.idNotWellFormed(file.id)))
        }

        var capabilities: [CapabilityRequest] = []
        for service in file.uses ?? [] {
            guard let capability = Capability(rawValue: service) else { return .failure(.notOfferedHere(service)) }
            capabilities.append(CapabilityRequest(usedByOutsideTool: capability))
        }

        var commands: [CommandDescriptor] = []
        var titles: [CommandID: LocalizedText] = [:]
        for command in file.contributes?.commands ?? [] {
            var surfaces = Set<ToolSurface>()
            for name in command.surfaces ?? [] {
                guard let surface = ToolSurface(rawValue: name) else { return .failure(.notOfferedHere(name)) }
                surfaces.insert(surface)
            }
            guard let commandID = CommandID(tool: id, name: command.id),
                  let descriptor = CommandDescriptor(id: commandID, title: command.title.english ?? "",
                                                     symbol: symbol(command.icon ?? file.icon), surfaces: surfaces)
            else { return .failure(.invalid(.commandNotWellFormed(command.id))) }
            commands.append(descriptor)
            titles[commandID] = command.title
        }

        var preferences: [PreferenceDeclaration] = []
        var preferenceTitles: [String: LocalizedText] = [:]
        var preferenceOptions: [String: [PreferenceOption]] = [:]
        var preferencePickers: [String: PreferencePicker] = [:]
        for preference in file.preferences ?? [] {
            guard let value = value(preference.default, ofKind: preference.type) else {
                return .failure(.notOfferedHere(preference.type))
            }
            let key = storageKey(tool: id, preference: preference.id)
            preferences.append(PreferenceDeclaration(key: key, default: value))
            preferenceTitles[key] = preference.title
            preferenceOptions[key] = preference.options?.map { PreferenceOption(value: $0.value, title: $0.title) }
            // The file's own rules have held a picker to a text preference
            // and to a name there is.
            preferencePickers[key] = preference.knownPicker
        }

        var panels: [ToolPanelDescriptor] = []
        for panel in file.contributes?.panels ?? [] {
            guard let placement = ToolPanelPlacement(rawValue: panel.placement) else {
                return .failure(.notOfferedHere(panel.placement))
            }
            let kind = panel.kind ?? PanelKind.blocks.rawValue
            guard let drawn = PanelKind(rawValue: kind) else { return .failure(.notOfferedHere(kind)) }
            panels.append(ToolPanelDescriptor(id: panel.id, title: panel.title, placement: placement,
                                              symbol: symbol(panel.icon ?? file.icon),
                                              entry: drawn == .web ? panel.entry : nil))
        }

        var activation: [Activation] = []
        for name in file.activation ?? [] {
            guard let when = Activation(rawValue: name) else { return .failure(.notOfferedHere(name)) }
            if !activation.contains(when) { activation.append(when) }
        }
        if activation.isEmpty { activation = [.onCommand] }

        // Not reached while the file's own rules hold: they are the rules
        // these two initializers check again.
        guard let descriptor = ToolDescriptor(id: id, name: file.name.english ?? "", symbol: symbol(file.icon),
                                              commands: commands),
              let manifest = ToolManifest(tool: descriptor, group: group, capabilities: capabilities,
                                          preferences: preferences, activation: activation, enabledBy: nil)
        else { return .failure(.invalid(.malformed(field: "id"))) }

        return .success(ExternalToolManifest(manifest: manifest, name: file.name, summary: file.description,
                                             commandTitles: titles, preferenceTitles: preferenceTitles,
                                             preferenceOptions: preferenceOptions,
                                             preferencePickers: preferencePickers,
                                             // The file's own rules have held the placement to the one
                                             // there is, the island.
                                             showsStatus: file.contributes?.status != nil,
                                             showsActivity: file.contributes?.status?.activity == true,
                                             // Held to a slot there is by the same rules.
                                             slot: file.contributes?.slot?.knownPlacement,
                                             panels: panels, version: file.version,
                                             publisher: file.publisher, license: file.license,
                                             protocolVersion: file.`protocol`, program: file.runtime.exec))
    }

    /// An icon as a symbol name; the plain puzzle piece when there is none.
    /// Whether this Mac has the symbol is for whoever draws it.
    static func symbol(_ icon: String?) -> String {
        guard let icon, !icon.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return defaultSymbol }
        return icon
    }

    /// A preference's default as the app holds one; nil for a kind of
    /// preference the app has no value for.
    package static func value(_ json: JSONValue, ofKind kind: String) -> PreferenceDeclaration.Value? {
        switch (PreferenceKind(rawValue: kind), json) {
        case (.string?, .string(let text)): return .string(text)
        case (.boolean?, .bool(let flag)): return .bool(flag)
        case (.integer?, .number(let number)): return Int(exactly: number).map(PreferenceDeclaration.Value.int)
        case (.number?, .number(let number)): return .double(number)
        default: return nil
        }
    }

    /// Why the program at `program` cannot be started from `folder`, or nil
    /// when it can. Links are followed first: the app runs a copy of the
    /// folder, and a link out of it would point at something the copy does
    /// not hold.
    static func programRefusal(_ program: String, in folder: URL, fileManager: FileManager) -> ManifestRefusal? {
        let root = folder.resolvingSymlinksInPath().standardizedFileURL.pathComponents
        let file = folder.appendingPathComponent(program).resolvingSymlinksInPath().standardizedFileURL
        var isFolder: ObjCBool = false
        guard fileManager.fileExists(atPath: file.path, isDirectory: &isFolder), !isFolder.boolValue else {
            return .programMissing(program)
        }
        // A file, and not only something that is there: a named pipe or a
        // device can carry the execute permission and is no program.
        guard (try? fileManager.attributesOfItem(atPath: file.path))?[.type] as? FileAttributeType == .typeRegular
        else { return .programMissing(program) }
        let inside = file.pathComponents.count > root.count && Array(file.pathComponents.prefix(root.count)) == root
        guard inside else { return .programOutsideFolder(program) }
        guard fileManager.isExecutableFile(atPath: file.path) else { return .programNotExecutable(program) }
        return nil
    }
}

/// A tool's own words, made fit to stand inside one of the app's sentences
/// where there is no room to cut them: an alert, and the app's short
/// on-screen message. A manifest may hold a name, a service or a path of
/// tens of kilobytes, with line breaks in it, and with the characters that
/// turn a line of text round, which would let a tool's name reorder the
/// sentence it is put in.
package enum ToolOwnWords {
    /// The most characters of a tool's words such a sentence shows.
    package static let limit = 120
    /// A character may be built of many parts, an accent upon an accent
    /// without end. So the parts are bounded too: this many for each
    /// character the limit allows.
    package static let scalarsPerCharacter = 4

    /// `text` as one short line of plain text: every line break and control
    /// character a space, the characters that turn text round taken out,
    /// and at most `limit` characters, the last an ellipsis when it was cut.
    /// Letters of any script stay as they are.
    package static func oneLine(_ text: String, limit: Int = limit) -> String {
        let most = max(limit, 1) * scalarsPerCharacter
        var kept = String.UnicodeScalarView()
        var count = 0
        var more = false
        for scalar in text.unicodeScalars where !turnsTextRound(scalar) {
            guard count < most else {
                more = true
                break
            }
            kept.append(breaksTheLine(scalar) ? " " : scalar)
            count += 1
        }
        let line = String(kept)
        guard more || line.count > limit else { return line }
        return String(line.prefix(max(limit, 1) - 1)) + "…"
    }

    /// A line break, a tab, or any other control character.
    private static func breaksTheLine(_ scalar: Unicode.Scalar) -> Bool {
        switch scalar.properties.generalCategory {
        case .control, .lineSeparator, .paragraphSeparator: return true
        default: return false
        }
    }

    /// The marks, embeddings, overrides and isolates that set the direction
    /// text is drawn in. Text in a script written from the right needs none
    /// of them to be drawn from the right.
    private static func turnsTextRound(_ scalar: Unicode.Scalar) -> Bool {
        switch scalar.value {
        case 0x061C, 0x200E, 0x200F, 0x202A...0x202E, 0x2066...0x2069: return true
        default: return false
        }
    }
}
