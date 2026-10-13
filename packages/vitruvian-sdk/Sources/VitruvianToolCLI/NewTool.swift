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

/// What `vitruvian-tool init` starts a new tool from.
public enum ToolTemplate: String, CaseIterable, Sendable {
    /// One file of plain Python. It runs as it is written.
    case python
    /// Python with the kit. The kit goes in the tool's folder, in lib/.
    case pythonKit = "python-kit"
    /// JavaScript, with the TypeScript kit's types. Node runs it as it is,
    /// with the kit in the tool's node_modules/.
    case typescript
    /// A Swift package that uses the kit. It has to be built first.
    case swift
}

/// A tool to start: where, and what its manifest says of it.
public struct NewTool: Equatable, Sendable {
    public var folder: URL
    public var id: String
    public var name: String
    public var publisher: String
    public var template = ToolTemplate.python
    /// Where `packages/vitruvian-sdk` is, to work from a checkout. The Swift
    /// template's package names it by its path; the TypeScript template's
    /// package.json depends on the kit in it by its path; the Python kit
    /// template copies the kit from it into lib/. The plain Python template
    /// needs no kit.
    public var sdk: URL?

    public init(folder: URL, id: String, name: String, publisher: String) {
        self.folder = folder
        self.id = id
        self.name = name
        self.publisher = publisher
    }
}

/// Why nothing was written.
public enum NewToolProblem: Error, Equatable, Sendable {
    /// Something is already at the folder's path, and it is not an empty
    /// folder. Nothing that exists is ever written over.
    case folderInUse
    /// The folder's path is a symbolic link. A new tool is written into a
    /// folder of its own, never through a link to somewhere else.
    case folderIsALink
    /// The id, the name or the publisher would not make a manifest the app
    /// takes.
    case manifest(ManifestProblem)
    /// The path given with `--sdk` does not hold the kit the template needs.
    case noSDK
    case notWritten(String)
}

public enum NewToolWriter {
    /// Where the SDK is published: the repository a Swift package depends on.
    public static let publishedSDK = "https://github.com/VitruvianSoftware/vitruvian-sdk"

    /// One file to write: its path in the folder, its text, and whether it
    /// is a program.
    public struct File: Equatable, Sendable {
        public let path: String
        public let text: String
        public let runs: Bool
    }

    /// Each template's sample: its folder under samples/, the name its
    /// manifest gives it, and the manifest.
    struct Sample {
        let folder: String
        let name: String
        let manifest: String
    }

    static func sample(_ template: ToolTemplate) -> Sample {
        switch template {
        case .python: Sample(folder: "hello-python", name: "Hello, in Python", manifest: Templates.pythonManifest)
        case .pythonKit:
            Sample(folder: "hello-python-kit", name: "Hello, in Python, with the kit",
                   manifest: Templates.pythonKitManifest)
        case .typescript:
            Sample(folder: "hello-typescript", name: "Hello, in TypeScript", manifest: Templates.typescriptManifest)
        case .swift: Sample(folder: "hello-swift", name: "Hello, in Swift", manifest: Templates.swiftManifest)
        }
    }

    /// The mark sync_templates.py puts where a sample names the kit's version.
    static let versionMark = "{{sdk-version}}"

    /// The files a new tool is made of. Nothing is written.
    public static func files(for tool: NewTool) -> Result<[File], NewToolProblem> {
        let sample = sample(tool.template)
        // The sample's manifest with three of its values replaced. Each is
        // in the sample once, written exactly this way. Each is first swapped
        // for a mark no text holds, so that a name the person gives is never
        // taken for one of the sample's values and replaced in its turn.
        let marks = ["\u{1}id\u{1}", "\u{1}name\u{1}", "\u{1}publisher\u{1}"]
        let manifest = sample.manifest
            .replacingOccurrences(of: quoted("dev.vitruvian.samples.\(sample.folder)"), with: marks[0])
            .replacingOccurrences(of: quoted(sample.name), with: marks[1])
            .replacingOccurrences(of: quoted("VitruvianSoftware"), with: marks[2])
            .replacingOccurrences(of: marks[0], with: quoted(tool.id))
            .replacingOccurrences(of: marks[1], with: quoted(tool.name))
            .replacingOccurrences(of: marks[2], with: quoted(tool.publisher))
        // The rules the app reads a manifest by, before anything is written.
        if case .failure(let problem) = ToolManifestFile.read(Data(manifest.utf8)) {
            return .failure(.manifest(problem))
        }
        let sdk = tool.sdk?.standardizedFileURL
        switch tool.template {
        case .python:
            return .success([File(path: ToolManifestFile.fileName, text: manifest, runs: false),
                             File(path: "bin/tool.py", text: Templates.pythonProgram, runs: true)])
        case .pythonKit:
            var files = [File(path: ToolManifestFile.fileName, text: manifest, runs: false),
                         File(path: "bin/tool.py", text: Templates.pythonKitProgram, runs: true),
                         File(path: "requirements.txt",
                              text: Templates.pythonKitRequirements.replacingOccurrences(of: versionMark,
                                                                                          with: Words.version),
                              runs: false)]
            if let sdk {
                // From a checkout: the kit as it is there, where pip would put it.
                guard let kit = pythonKit(in: sdk) else { return .failure(.noSDK) }
                files += kit
            }
            return .success(files)
        case .typescript:
            var dependency = quoted(Words.version)
            if let sdk {
                let kit = sdk.appendingPathComponent("kits/typescript")
                guard FileManager.default.fileExists(atPath: kit.appendingPathComponent("package.json").path)
                else { return .failure(.noSDK) }
                dependency = quoted("file:" + kit.path)
            }
            let package = Templates.typescriptPackage.replacingOccurrences(of: quoted(versionMark), with: dependency)
            return .success([File(path: ToolManifestFile.fileName, text: manifest, runs: false),
                             File(path: "bin/tool", text: Templates.typescriptLauncher, runs: true),
                             File(path: "bin/tool.mjs", text: Templates.typescriptProgram, runs: false),
                             File(path: "package.json", text: package, runs: false)])
        case .swift:
            // SwiftPM names a package it depends on by the last part of its
            // path or its address, and a product is asked for by that name.
            let dependency: [String]
            let name: String
            if let given = tool.sdk {
                let sdk = given.standardizedFileURL
                guard FileManager.default.fileExists(atPath: sdk.appendingPathComponent("Package.swift").path)
                else { return .failure(.noSDK) }
                dependency = ["// The Vitruvian SDK, from a checkout of it on this Mac.",
                              ".package(path: \"\(swiftText(sdk.path))\"),"]
                name = sdk.lastPathComponent
            } else {
                dependency = ["// The Vitruvian SDK, from the version of vitruvian-tool that wrote this",
                              "// file up to the next major version.",
                              ".package(url: \"\(publishedSDK)\", from: \"\(Words.version)\"),"]
                name = "vitruvian-sdk"
            }
            let package = swiftPackage
                .replacingOccurrences(of: "{{dependency}}", with: dependency.joined(separator: "\n        "))
                .replacingOccurrences(of: "{{package}}", with: swiftText(name))
            return .success([File(path: "Package.swift", text: package, runs: false),
                             File(path: "Sources/Tool/main.swift", text: Templates.swiftProgram, runs: false),
                             File(path: "tool/" + ToolManifestFile.fileName, text: manifest, runs: false),
                             File(path: "build.sh", text: buildScript, runs: true),
                             File(path: ".gitignore", text: ".build/\ntool/bin/\n", runs: false)])
        }
    }

    /// The Python kit's files in a checkout, as `lib/vitruvian_tool_kit/...`;
    /// nil when the checkout holds no kit.
    static func pythonKit(in sdk: URL) -> [File]? {
        let kit = sdk.appendingPathComponent("kits/python/vitruvian_tool_kit")
        guard let walk = FileManager.default.enumerator(atPath: kit.path) else { return nil }
        var files: [File] = []
        while let relative = walk.nextObject() as? String {
            guard relative.hasSuffix(".py"),
                  let text = try? String(contentsOf: kit.appendingPathComponent(relative), encoding: .utf8)
            else { continue }
            files.append(File(path: "lib/vitruvian_tool_kit/" + relative, text: text, runs: false))
        }
        guard files.contains(where: { $0.path == "lib/vitruvian_tool_kit/__init__.py" }) else { return nil }
        return files.sorted { $0.path < $1.path }
    }

    /// Writes a new tool into its folder, which must not exist yet or must
    /// be empty. It writes inside that folder and nowhere else. Returns the
    /// paths written.
    public static func write(_ tool: NewTool) -> Result<[String], NewToolProblem> {
        let manager = FileManager.default
        // Asked of the path itself, with no link followed and no slash at
        // its end: a link there would take every file somewhere else.
        var path = tool.folder.path
        while path.count > 1, path.hasSuffix("/") { path.removeLast() }
        var status = stat()
        if lstat(path, &status) == 0 {
            guard status.st_mode & S_IFMT != S_IFLNK else { return .failure(.folderIsALink) }
            guard status.st_mode & S_IFMT == S_IFDIR,
                  (try? manager.contentsOfDirectory(atPath: path))?.isEmpty == true
            else { return .failure(.folderInUse) }
        }
        let files: [File]
        switch Self.files(for: tool) {
        case .failure(let problem): return .failure(problem)
        case .success(let made): files = made
        }
        do {
            for file in files {
                let url = tool.folder.appendingPathComponent(file.path)
                try manager.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
                // The folder was empty, so nothing is there to write over;
                // were something to appear, this fails and does not replace it.
                try Data(file.text.utf8).write(to: url, options: .withoutOverwriting)
                try manager.setAttributes([.posixPermissions: file.runs ? 0o755 : 0o644], ofItemAtPath: url.path)
            }
        } catch {
            return .failure(.notWritten(error.localizedDescription))
        }
        return .success(files.map(\.path))
    }

    /// A piece of text as JSON writes it, with its quotation marks.
    static func quoted(_ text: String) -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.withoutEscapingSlashes]
        return (try? encoder.encode(text)).map { String(decoding: $0, as: UTF8.self) } ?? "\"\""
    }

    /// A piece of text as it is written between the quotation marks of a
    /// Swift string.
    static func swiftText(_ text: String) -> String {
        text.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"")
    }

    /// The package a Swift tool is built as. The tool's folder, the one the
    /// app is pointed at, is `tool/` beside it: a package's build output
    /// is far more than a tool's folder may hold.
    static let swiftPackage = """
        // swift-tools-version: 6.0

        import PackageDescription

        let package = Package(
            name: "Tool",
            platforms: [.macOS(.v14)],
            dependencies: [
                {{dependency}}
            ],
            targets: [
                .executableTarget(
                    name: "Tool",
                    dependencies: [.product(name: "VitruvianToolKit", package: "{{package}}")],
                    path: "Sources/Tool"
                ),
            ]
        )

        """

    static let buildScript = """
        #!/bin/sh
        # Builds the tool, and puts its program where the manifest says it is.
        set -eu
        cd "$(dirname "$0")"
        swift build -c release
        mkdir -p tool/bin
        cp "$(swift build -c release --show-bin-path)/Tool" tool/bin/tool
        echo "Built. The folder to add to Vitruvian is $(pwd)/tool"

        """
}
