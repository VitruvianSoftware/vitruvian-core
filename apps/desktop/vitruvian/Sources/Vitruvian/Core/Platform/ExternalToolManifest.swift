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

/// A tool that runs as its own program, as its manifest file describes it:
/// the manifest the platform already has for a built-in tool, and what only
/// an outside tool carries.
///
/// Nothing in the app reads one yet. The runtime that starts such a tool,
/// and the sheet that asks before adding it, come later.
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
    package let version: String
    package let publisher: String
    package let license: String?
    /// The protocol version the tool speaks.
    package let protocolVersion: String
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
        for preference in file.preferences ?? [] {
            guard let value = value(preference.default, ofKind: preference.type) else {
                return .failure(.notOfferedHere(preference.type))
            }
            preferences.append(PreferenceDeclaration(key: storageKey(tool: id, preference: preference.id),
                                                     default: value))
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
                                             commandTitles: titles, version: file.version,
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
        let inside = file.pathComponents.count > root.count && Array(file.pathComponents.prefix(root.count)) == root
        guard inside else { return .programOutsideFolder(program) }
        guard fileManager.isExecutableFile(atPath: file.path) else { return .programNotExecutable(program) }
        return nil
    }
}
