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
    /// The SDK's version: what `--version` prints, and what `init --template
    /// swift` asks for. release-please writes it at each release (the
    /// extra-files of release-please-config.json); change it only that way.
    static let version = "1.8.1" // x-release-please-version

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

    static func problem(_ problem: NewToolProblem, _ tool: NewTool) -> String {
        switch problem {
        case .folderInUse:
            return "\(tool.folder.path) is already there, and is not an empty folder. Name a new one"
        case .folderIsALink:
            return "\(tool.folder.path) is a symbolic link. A new tool is written into a folder of its own, "
                + "never through a link. Name a new folder"
        case .manifest(let broken):
            return "that would not make a manifest the app takes: " + manifest(broken)
        case .noSDK:
            switch tool.template {
            case .swift:
                return "\(tool.sdk?.path ?? "the path given in --sdk") holds no Package.swift. --sdk names a checkout "
                    + "of the SDK to build against; leave it out to use the published SDK, version \(version)"
            case .typescript, .pythonKit, .python:
                return "--sdk is the path of packages/vitruvian-sdk, or of a copy of the vitruvian-sdk repository, "
                    + "and \(tool.sdk.map { shell($0.path) } ?? "that path") holds no kit for this template"
            case .go, .rust:
                return "--sdk is not a copy of packages/vitruvian-sdk with the \(tool.template.rawValue) kit in it. "
                    + "Leave --sdk out to use the published kit"
            }
        case .notWritten(let why):
            return "the files could not be written: \(why)"
        }
    }

    /// What to do with a tool `init` has just written.
    static func next(_ tool: NewTool) -> String {
        let folder = shell(tool.folder.path)
        switch tool.template {
        case .python:
            return """
                Next, from anywhere:
                  vitruvian-tool validate \(folder)
                  vitruvian-tool run \(folder)
                Then add the folder in Vitruvian: Settings › Extensions, "Add from Folder…".
                """
        case .pythonKit where tool.sdk != nil:
            return """
                The kit from \(tool.sdk.map { shell($0.standardizedFileURL.path) } ?? "") is in lib/. Next:
                  vitruvian-tool validate \(folder)
                  vitruvian-tool run \(folder)
                Then add the folder in Vitruvian: Settings › Extensions, "Add from Folder…".
                To take the published kit instead: rm -r \(folder)/lib, then the pip line below.
                  /usr/bin/python3 -m pip install --target \(folder)/lib -r \(folder)/requirements.txt
                """
        case .pythonKit:
            return """
                Next, put the kit in the tool's folder, with the python3 the app will use:
                  /usr/bin/python3 -m pip install --target \(folder)/lib -r \(folder)/requirements.txt
                  vitruvian-tool validate \(folder)
                  vitruvian-tool run \(folder)
                Then add the folder in Vitruvian: Settings › Extensions, "Add from Folder…" (lib/ goes with it).
                """
        case .typescript:
            let install = tool.sdk == nil
                ? "  cd \(folder) && npm install"
                : "  (cd \(shell(tool.sdk?.standardizedFileURL.appendingPathComponent("kits/typescript").path ?? "")) && npm run build)\n"
                    + "  cd \(folder) && npm install --install-links"
            return """
                Next, put the kit in the tool's folder:
                \(install)
                  vitruvian-tool validate \(folder)
                  vitruvian-tool run \(folder)
                Then add the folder in Vitruvian: Settings › Extensions, "Add from Folder…" (node_modules/ goes with it).
                bin/tool starts Node: if yours is not in /opt/homebrew/bin or /usr/local/bin, say where in it.
                """
        case .swift, .go, .rust:
            let published: String
            switch tool.template {
            case .go: published = "the Go kit, version \(version), through the Go module proxy"
            case .rust: published = "the Rust kit, version \(version), from crates.io"
            default: published = "the SDK, version \(version), from GitHub"
            }
            let fetch = tool.sdk == nil ? "The first build fetches \(published).\n" : ""
            return fetch + """
                Next:
                  \(folder)/build.sh
                  vitruvian-tool validate \(folder)/tool
                  vitruvian-tool run \(folder)/tool
                Then add \(folder)/tool in Vitruvian: Settings › Extensions, "Add from Folder…".
                Build again after each change to the code.
                """
        }
    }

    /// A path as it can be typed after a command: as it is when it is plain,
    /// between single quotation marks when it holds a space or a mark the
    /// shell reads.
    static func shell(_ path: String) -> String {
        let plain = CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ"
            + "0123456789/._-+=:@%,")
        if !path.isEmpty, path.unicodeScalars.allSatisfy(plain.contains) { return path }
        return "'" + path.replacingOccurrences(of: "'", with: #"'\''"#) + "'"
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
            return "`protocol` is \"\(version)\", and this command speaks protocols "
                + ProtocolVersion.supported.map { "\"\($0)\"" }.joined(separator: " and ")
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
        case .preferenceTitleNotWellFormed(let preference):
            return "the title of the preference `\(preference)` is, in some language, over "
                + "\(ManifestLimits.maxPreferenceTitleLength) characters, or holds a line break or another "
                + "control character"
        case .unknownPreferenceType(let preference, let type):
            return "the preference `\(preference)` has the type `\(type)`, which is not one: "
                + PreferenceKind.allCases.map(\.rawValue).joined(separator: ", ")
        case .defaultOfWrongType(let preference):
            return "the default of the preference `\(preference)` is not of its type"
        case .programLeavesFolder(let program):
            return "`runtime.exec` is \"\(program)\", which is not a path that stays inside the folder"
        case .panelsNeedProtocol2(let version):
            return "`contributes.panels` is there, and `protocol` is \"\(version)\": only protocol \"2\" has panels"
        case .tooManyPanels(let count):
            return "\(count) panels, and the most is \(ManifestLimits.maxPanels)"
        case .panelNotWellFormed(let id):
            return "the panel id `\(id)` is not a well-formed name"
        case .duplicatePanel(let id):
            return "two panels have the id `\(id)`"
        case .unknownPlacement(let panel, let placement):
            return "the panel `\(panel)` names the placement `\(placement)`, which is not one: "
                + PanelPlacement.allCases.map(\.rawValue).joined(separator: ", ")
        case .unknownPanelKind(let panel, let kind):
            return "the panel `\(panel)` is of the kind `\(kind)`, which is not one: "
                + PanelKind.allCases.map(\.rawValue).joined(separator: ", ")
        case .placementTaken(let panel, let placement):
            return "the panel `\(panel)` is a second panel in `\(placement)`, and a tool has one there at most"
        case .webPanelWithoutEntry(let panel):
            return "the web panel `\(panel)` names no `entry`, the page it shows"
        case .panelEntryLeavesFolder(let panel, let entry):
            return "the web panel `\(panel)` has the `entry` \"\(entry)\", which is not a path that stays inside "
                + "the folder"
        case .statusNeedsProtocol2(let version):
            return "`contributes.status` is there, and `protocol` is \"\(version)\": only protocol \"2\" has a status"
        case .unknownStatusPlacement(let placement):
            return "`contributes.status` names the placement `\(placement)`, which is not one: "
                + StatusPlacement.allCases.map(\.rawValue).joined(separator: ", ")
        case .optionsNeedString(let preference):
            return "the preference `\(preference)` has `options`, and only a preference of the type `string` may. "
                + "Never write a new type for a list of choices: an app that does not know a type refuses the tool"
        case .optionCountOutOfRange(let preference, let count):
            return "the preference `\(preference)` has \(count) options, and may have from 1 to "
                + "\(ManifestLimits.maxOptions)"
        case .optionValueNotWellFormed(let preference):
            return "an option of the preference `\(preference)` has a value over "
                + "\(ManifestLimits.maxOptionValueLength) characters, or one that holds a line break or another "
                + "control character"
        case .duplicateOption(let preference, let value):
            return "two options of the preference `\(preference)` have the value \"\(value)\""
        case .optionTitleNotWellFormed(let preference):
            return "an option of the preference `\(preference)` has a title that is, in some language, over "
                + "\(ManifestLimits.maxPreferenceTitleLength) characters, or holds a line break or another "
                + "control character"
        case .defaultNotAnOption(let preference):
            return "the default of the preference `\(preference)` is none of its options"
        }
    }

    static let usage = """
        vitruvian-tool: check and try a Vitruvian tool without the app.

          vitruvian-tool init <folder> --id ID --name NAME --publisher WHO [--template T] [--sdk PATH]
              Starts a new tool in a folder that is not there yet, or is
              empty. It writes in that folder and nowhere else.
                --id ID         the tool's id, with a dot: com.you.tool
                --template      python, the default: one file, runs as it is.
                                python-kit: Python with the kit, from PyPI.
                                typescript: JavaScript with the kit, from npm.
                                swift, go or rust: a program that uses the
                                kit in that language, to build
                --sdk PATH      a checkout of the SDK, not the published one:
                                swift builds against it; the kits are taken from it;
                                go and rust build against the kit there

          vitruvian-tool validate <folder>
              Reads a tool's folder the way the app does before it offers to
              add it, and says what the app would refuse it for. It starts
              nothing.

          vitruvian-tool --version
              Prints the version of the SDK this command was built from.

          vitruvian-tool run <folder> [--command ID]... [--refuse] [--app-path] [--wait SECONDS]
              Starts the tool's program and plays the app's side to it, in a
              folder made for the run. With no --command, type a command's
              id to run it, and `quit` to end.
                --command ID   run this command, then the next, then stop
                --refuse       refuse every request the tool makes
                --app-path     start the tool with the short PATH the app has
                --wait SECONDS how long a command may take. The app allows 2
              What the tool asks for is printed and answered as done. Nothing
              is shown, opened, copied, pasted, pressed or ended on this Mac.

        A tool's folder holds a vitruvian-tool.json and the program it names.
        """

    /// What `validate` cannot know, said once at the end of a pass.
    static let validateLimits = """
        This is what the app checks before it asks the person. It cannot promise the rest: an older app \
        may not know a service or a surface this one does; the app refuses an id another tool already has, \
        and a folder inside its own support folder; and nothing here started the program.
        """

    /// Where `run` is not the app, said once when a run starts.
    static let runLimits = """
        This is not the app. Every service the manifest lists is granted, and nothing real is done. \
        There is no idle stop, no restart after a crash and no flood count.
        """
}
