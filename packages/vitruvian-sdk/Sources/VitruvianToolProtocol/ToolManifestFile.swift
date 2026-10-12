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

import Foundation

/// The limits a manifest is held to. They keep the app's lists sane; they
/// are not a safety measure.
public enum ManifestLimits {
    /// The largest manifest file, in bytes: 64 KB.
    public static let maxBytes = 65_536
    public static let maxCommands = 32
    public static let maxPreferences = 16
    /// The longest tool id, command id or preference id, in characters.
    public static let maxNameLength = 128
    /// The longest title of a preference, in each language, in characters
    /// as JSON Schema counts them: Unicode code points.
    public static let maxPreferenceTitleLength = 60
}

/// A piece of text in one or more languages, keyed by language tag (`en`,
/// `fr`, `pt-BR`). It is shown as the tool wrote it.
public struct LocalizedText: Equatable, Sendable {
    public let byLanguage: [String: String]

    public init(_ byLanguage: [String: String]) {
        self.byLanguage = byLanguage
    }

    public var english: String? { byLanguage["en"] }

    /// The text for a language: its own entry, else the entry for the
    /// language without its region (`pt` for `pt-BR`), else English.
    public func text(for languageTag: String) -> String? {
        if let exact = byLanguage[languageTag] { return exact }
        if let base = languageTag.split(separator: "-").first, let text = byLanguage[String(base)] {
            return text
        }
        return english
    }
}

extension LocalizedText: Codable {
    public init(from decoder: any Decoder) throws {
        byLanguage = try decoder.singleValueContainer().decode([String: String].self)
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(byLanguage)
    }
}

/// Where a command may be offered.
public enum SurfaceName: String, CaseIterable, Sendable {
    case commandBar, radial, quickPanel, shortcut
}

/// When the app starts a tool.
public enum ActivationName: String, CaseIterable, Sendable {
    case onCommand, onLaunch
}

/// The kinds of value a preference may hold.
public enum PreferenceKind: String, CaseIterable, Sendable {
    case string, boolean, integer, number

    /// Whether `value` is of this kind.
    public func accepts(_ value: JSONValue) -> Bool {
        switch (self, value) {
        case (.string, .string), (.boolean, .bool), (.number, .number): return true
        case (.integer, .number(let number)): return Int(exactly: number) != nil
        default: return false
        }
    }
}

/// `vitruvian-tool.json`, as it is written: the file at the top of a tool's
/// folder. `protocol/manifest.schema.json` describes the same file, and a
/// test holds the two together. Lists whose members the app must know
/// (`uses`, surfaces, preference types, activation) are held as the text the
/// file has, so that a name nobody knows can be reported by name.
public struct ToolManifestFile: Codable, Equatable, Sendable {
    public struct Contributes: Codable, Equatable, Sendable {
        public let commands: [Command]?
    }

    public struct Command: Codable, Equatable, Sendable {
        /// The command's name within the tool.
        public let id: String
        public let title: LocalizedText
        /// An SF Symbol name; the tool's icon when left out.
        public let icon: String?
        public let surfaces: [String]?
    }

    public struct Preference: Codable, Equatable, Sendable {
        /// The setting's name within the tool.
        public let id: String
        /// What the setting is called where the person changes it. Left
        /// out, the app shows no such setting: only the tool reads and
        /// writes it.
        public let title: LocalizedText?
        public let type: String
        public let `default`: JSONValue
    }

    public struct Runtime: Codable, Equatable, Sendable {
        public let kind: String
        /// The program, as a path inside the tool's folder.
        public let exec: String
    }

    public static let fileName = "vitruvian-tool.json"
    public static let externalRuntime = "external"

    public let id: String
    public let name: LocalizedText
    public let description: LocalizedText?
    public let version: String
    public let `protocol`: String
    public let publisher: String
    public let license: String?
    public let icon: String?
    public let uses: [String]?
    public let contributes: Contributes?
    public let preferences: [Preference]?
    public let activation: [String]?
    public let runtime: Runtime
}

/// What is wrong with a manifest. Each case carries what is needed to say
/// which part of the file it is about; the words are the caller's.
public enum ManifestProblem: Error, Equatable, Sendable {
    /// The file is larger than `ManifestLimits.maxBytes`.
    case tooLarge(bytes: Int)
    /// The file is not JSON, or is not a JSON object.
    case notJSON
    /// A field that must be there is missing, or holds the wrong kind of
    /// value. `field` is where: `runtime.exec`, `contributes.commands[0].id`.
    case malformed(field: String)
    case idNotWellFormed(String)
    /// An id with no dot is a built-in feature's.
    case idWithoutDot(String)
    case unsupportedProtocol(String)
    case unsupportedRuntime(String)
    /// A text with no `en` entry.
    case noEnglish(field: String)
    /// A text, or one language of it, that is empty or only spaces.
    case blankText(field: String)
    case unknownService(String)
    case duplicateService(String)
    case unknownActivation(String)
    case tooManyCommands(Int)
    case commandNotWellFormed(String)
    case duplicateCommand(String)
    case unknownSurface(command: String, surface: String)
    case tooManyPreferences(Int)
    case preferenceNotWellFormed(String)
    case duplicatePreference(String)
    /// A preference's title that is, in some language, longer than
    /// `ManifestLimits.maxPreferenceTitleLength` or holds a control
    /// character, a line break among them.
    case preferenceTitleNotWellFormed(preference: String)
    case unknownPreferenceType(preference: String, type: String)
    case defaultOfWrongType(preference: String)
    /// `runtime.exec` is not a path that stays inside the tool's folder.
    case programLeavesFolder(String)
}

/// The rules about names and paths, for anything that checks one alone.
public enum ManifestRules {
    /// Letters, digits, dot, hyphen and underscore; no dot at either end and
    /// no two dots together; at most `ManifestLimits.maxNameLength` long.
    public static func isWellFormedName(_ text: String) -> Bool {
        guard !text.isEmpty, text.count <= ManifestLimits.maxNameLength, !text.hasPrefix("."),
              !text.hasSuffix("."), !text.contains("..") else { return false }
        return text.unicodeScalars.allSatisfy { scalar in
            switch scalar {
            case "a"..."z", "A"..."Z", "0"..."9", ".", "-", "_": return true
            default: return false
            }
        }
    }

    /// Whether `path`, read from a tool's folder, cannot name anything
    /// outside it: parts joined by `/`, none of them empty, `.` or `..`.
    /// This reads the text only. A link inside the folder can still point
    /// out of it; whoever has the folder checks that.
    public static func staysInsideFolder(_ path: String) -> Bool {
        let parts = path.split(separator: "/", omittingEmptySubsequences: false)
        return !path.isEmpty && parts.allSatisfy { !$0.isEmpty && $0 != "." && $0 != ".." }
    }

    /// Whether `text` can be a preference's title in one language: at most
    /// `ManifestLimits.maxPreferenceTitleLength` code points, none of them
    /// a control character. That it is not blank is another rule.
    public static func isWellFormedTitle(_ text: String) -> Bool {
        text.unicodeScalars.count <= ManifestLimits.maxPreferenceTitleLength
            && !text.unicodeScalars.contains { $0.properties.generalCategory == .control }
    }

    static func isBlank(_ text: String) -> Bool {
        text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
}

extension ToolManifestFile {
    /// Reads a manifest and applies every rule that needs only the file.
    /// The first problem found is the one given.
    public static func read(_ data: Data) -> Result<ToolManifestFile, ManifestProblem> {
        guard data.count <= ManifestLimits.maxBytes else { return .failure(.tooLarge(bytes: data.count)) }
        let file: ToolManifestFile
        do {
            file = try JSONDecoder().decode(ToolManifestFile.self, from: data)
        } catch let error as DecodingError {
            return .failure(problem(for: error))
        } catch {
            return .failure(.notJSON)
        }
        if let problem = file.problems().first { return .failure(problem) }
        return .success(file)
    }

    /// Everything wrong with a manifest that could be read, in the order
    /// the fields are written.
    public func problems() -> [ManifestProblem] {
        var found: [ManifestProblem] = []
        if !ManifestRules.isWellFormedName(id) {
            found.append(.idNotWellFormed(id))
        } else if !id.contains(".") {
            found.append(.idWithoutDot(id))
        }
        found += Self.textProblems(name, field: "name")
        if let summary = description { found += Self.textProblems(summary, field: "description") }
        if ManifestRules.isBlank(version) { found.append(.blankText(field: "version")) }
        if !ProtocolVersion.supported.contains(`protocol`) { found.append(.unsupportedProtocol(`protocol`)) }
        if ManifestRules.isBlank(publisher) { found.append(.blankText(field: "publisher")) }

        var services = Set<String>()
        for service in uses ?? [] {
            if AppService(rawValue: service) == nil {
                found.append(.unknownService(service))
            } else if !services.insert(service).inserted {
                found.append(.duplicateService(service))
            }
        }

        let commands = contributes?.commands ?? []
        if commands.count > ManifestLimits.maxCommands { found.append(.tooManyCommands(commands.count)) }
        var commandNames = Set<String>()
        for command in commands {
            guard ManifestRules.isWellFormedName(command.id) else {
                found.append(.commandNotWellFormed(command.id))
                continue
            }
            if !commandNames.insert(command.id).inserted { found.append(.duplicateCommand(command.id)) }
            found += Self.textProblems(command.title, field: "contributes.commands[\(command.id)].title")
            for surface in command.surfaces ?? [] where SurfaceName(rawValue: surface) == nil {
                found.append(.unknownSurface(command: command.id, surface: surface))
            }
        }

        let settings = preferences ?? []
        if settings.count > ManifestLimits.maxPreferences {
            found.append(.tooManyPreferences(settings.count))
        }
        var preferenceNames = Set<String>()
        for preference in settings {
            guard ManifestRules.isWellFormedName(preference.id) else {
                found.append(.preferenceNotWellFormed(preference.id))
                continue
            }
            if !preferenceNames.insert(preference.id).inserted {
                found.append(.duplicatePreference(preference.id))
            }
            if let title = preference.title {
                found += Self.textProblems(title, field: "preferences[\(preference.id)].title")
                if !title.byLanguage.values.allSatisfy(ManifestRules.isWellFormedTitle) {
                    found.append(.preferenceTitleNotWellFormed(preference: preference.id))
                }
            }
            guard let kind = PreferenceKind(rawValue: preference.type) else {
                found.append(.unknownPreferenceType(preference: preference.id, type: preference.type))
                continue
            }
            if !kind.accepts(preference.default) { found.append(.defaultOfWrongType(preference: preference.id)) }
        }

        for name in activation ?? [] where ActivationName(rawValue: name) == nil {
            found.append(.unknownActivation(name))
        }
        if runtime.kind != Self.externalRuntime { found.append(.unsupportedRuntime(runtime.kind)) }
        if !ManifestRules.staysInsideFolder(runtime.exec) { found.append(.programLeavesFolder(runtime.exec)) }
        return found
    }

    private static func textProblems(_ text: LocalizedText, field: String) -> [ManifestProblem] {
        guard text.english != nil else { return [.noEnglish(field: field)] }
        return text.byLanguage.values.contains(where: ManifestRules.isBlank) ? [.blankText(field: field)] : []
    }

    /// Where a file that would not decode went wrong.
    private static func problem(for error: DecodingError) -> ManifestProblem {
        func field(_ path: [any CodingKey]) -> ManifestProblem {
            guard !path.isEmpty else { return .notJSON }
            let text = path.map { key in key.intValue.map { "[\($0)]" } ?? ".\(key.stringValue)" }.joined()
            return .malformed(field: String(text.drop(while: { $0 == "." })))
        }
        switch error {
        case .keyNotFound(let key, let context): return field(context.codingPath + [key])
        case .typeMismatch(_, let context), .valueNotFound(_, let context): return field(context.codingPath)
        case .dataCorrupted(let context): return field(context.codingPath)
        @unknown default: return .notJSON
        }
    }
}
