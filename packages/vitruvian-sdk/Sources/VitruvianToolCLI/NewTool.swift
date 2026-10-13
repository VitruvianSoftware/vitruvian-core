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
    /// For the Swift template: a checkout of the SDK to build against, named
    /// by its path. Nil, the tool's package depends on the published SDK, at
    /// the version this command was built from.
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
    /// The path given in `--sdk` holds no `Package.swift`.
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

    /// The files a new tool is made of. Nothing is written.
    public static func files(for tool: NewTool) -> Result<[File], NewToolProblem> {
        let sample = tool.template == .python ? Templates.pythonManifest : Templates.swiftManifest
        let from = tool.template == .python ? "hello-python" : "hello-swift"
        // The sample's manifest with three of its values replaced. Each is
        // in the sample once, written exactly this way. Each is first swapped
        // for a mark no text holds, so that a name the person gives is never
        // taken for one of the sample's values and replaced in its turn.
        let marks = ["\u{1}id\u{1}", "\u{1}name\u{1}", "\u{1}publisher\u{1}"]
        let manifest = sample
            .replacingOccurrences(of: quoted("dev.vitruvian.samples.\(from)"), with: marks[0])
            .replacingOccurrences(of: quoted(tool.template == .python ? "Hello, in Python" : "Hello, in Swift"),
                                  with: marks[1])
            .replacingOccurrences(of: quoted("VitruvianSoftware"), with: marks[2])
            .replacingOccurrences(of: marks[0], with: quoted(tool.id))
            .replacingOccurrences(of: marks[1], with: quoted(tool.name))
            .replacingOccurrences(of: marks[2], with: quoted(tool.publisher))
        // The rules the app reads a manifest by, before anything is written.
        if case .failure(let problem) = ToolManifestFile.read(Data(manifest.utf8)) {
            return .failure(.manifest(problem))
        }
        switch tool.template {
        case .python:
            return .success([File(path: ToolManifestFile.fileName, text: manifest, runs: false),
                             File(path: "bin/tool.py", text: Templates.pythonProgram, runs: true)])
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
