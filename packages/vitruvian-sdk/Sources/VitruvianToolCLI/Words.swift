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
import VitruvianToolProtocol

/// What this command says, in plain words, about what it found.
enum Words {
    static func problem(_ problem: FolderProblem) -> String {
        switch problem {
        case .noManifest:
            return "there is no \(ToolManifestFile.fileName) in the folder, or it cannot be read"
        case .manifest(let broken):
            return "the manifest: " + manifest(broken)
        case .programMissing(let program):
            return "the program `\(program)` is not a file in the folder"
        case .programOutsideFolder(let program):
            return "the program `\(program)` is a link to a file outside the folder. The app runs a copy of the "
                + "folder, and the copy would not hold it"
        case .programNotExecutable(let program):
            return "the program `\(program)` is not a file macOS will run. Give it the execute permission: "
                + "chmod +x \(program)"
        case .quarantined(let program):
            return "macOS has quarantined the program `\(program)`, as it does to a download, and will not start "
                + "it. The app refuses the folder and never clears the mark itself. To clear it yourself: "
                + "xattr -dr com.apple.quarantine <the folder>"
        case .tooBig(let limits):
            return "the folder holds more than a tool's folder may: \(limits.bytes / 1_048_576) MB and "
                + "\(limits.things) things. The app copies the folder whole. Keep build output and "
                + "dependencies you do not ship out of it"
        }
    }

    static func manifest(_ problem: ManifestProblem) -> String {
        switch problem {
        case .tooLarge(let bytes):
            return "the file is \(bytes) bytes, and the most is \(ManifestLimits.maxBytes)"
        case .notJSON:
            return "the file is not a JSON object"
        case .malformed(let field):
            return "`\(field)` is missing, or is not the kind of value it must be"
        case .idNotWellFormed(let id):
            return "the id `\(id)` is not letters, digits, dots, hyphens and underscores, at most "
                + "\(ManifestLimits.maxNameLength) long, with no dot at either end and no two together"
        case .idWithoutDot(let id):
            return "the id `\(id)` has no dot. An id with no dot is one of the app's own tools: use a name like "
                + "com.you.\(id)"
        case .unsupportedProtocol(let version):
            return "`protocol` is \"\(version)\", and this is protocol \"\(ProtocolVersion.current)\""
        case .unsupportedRuntime(let kind):
            return "`runtime.kind` is \"\(kind)\", and the only kind is \"\(ToolManifestFile.externalRuntime)\""
        case .noEnglish(let field):
            return "`\(field)` has no `en` entry. English is required"
        case .blankText(let field):
            return "`\(field)` is empty, or only spaces"
        case .unknownService(let service):
            return "`uses` names `\(service)`, which is not a service: "
                + AppService.allCases.map(\.rawValue).joined(separator: ", ")
        case .duplicateService(let service):
            return "`uses` names `\(service)` twice"
        case .unknownActivation(let name):
            return "`activation` names `\(name)`, and may name "
                + ActivationName.allCases.map(\.rawValue).joined(separator: " and ") + " only"
        case .tooManyCommands(let count):
            return "\(count) commands, and the most is \(ManifestLimits.maxCommands)"
        case .commandNotWellFormed(let id):
            return "the command id `\(id)` is not a well-formed name"
        case .duplicateCommand(let id):
            return "two commands have the id `\(id)`"
        case .unknownSurface(let command, let surface):
            return "the command `\(command)` names the surface `\(surface)`, which is not one: "
                + SurfaceName.allCases.map(\.rawValue).joined(separator: ", ")
        case .tooManyPreferences(let count):
            return "\(count) preferences, and the most is \(ManifestLimits.maxPreferences)"
        case .preferenceNotWellFormed(let id):
            return "the preference id `\(id)` is not a well-formed name"
        case .duplicatePreference(let id):
            return "two preferences have the id `\(id)`"
        case .unknownPreferenceType(let preference, let type):
            return "the preference `\(preference)` has the type `\(type)`, which is not one: "
                + PreferenceKind.allCases.map(\.rawValue).joined(separator: ", ")
        case .defaultOfWrongType(let preference):
            return "the default of the preference `\(preference)` is not of its type"
        case .programLeavesFolder(let program):
            return "`runtime.exec` is \"\(program)\", which is not a path that stays inside the folder"
        }
    }

    static let usage = """
        vitruvian-tool: check and try a Vitruvian tool without the app.

          vitruvian-tool validate <folder>
              Reads a tool's folder the way the app does before it offers to
              add it, and says what the app would refuse it for. It starts
              nothing.

        A tool's folder holds a vitruvian-tool.json and the program it names.
        """

    /// What `validate` cannot know, said once at the end of a pass.
    static let validateLimits = """
        This is what the app checks before it asks the person. It cannot promise the rest: an older app \
        may not know a service or a surface this one does; the app refuses an id another tool already has; \
        and nothing here started the program.
        """
}
