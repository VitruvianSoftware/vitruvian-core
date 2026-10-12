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

import XCTest

import VitruvianToolCLI
import VitruvianToolProtocol

/// A folder in the temporary folder that is gone when the test is. A test
/// that keeps one for all of its methods removes it in `tearDown`: XCTest
/// holds a test case to the end of the run, so `deinit` comes too late.
final class Scratch {
    let url: URL

    init() {
        url = FileManager.default.temporaryDirectory
            .appendingPathComponent("vitruvian-tool-cli-\(UUID().uuidString)", isDirectory: true)
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    }

    deinit {
        remove()
    }

    func remove() {
        try? FileManager.default.removeItem(at: url)
    }

    /// A folder of its own inside this one.
    func folder(_ name: String) -> URL {
        let folder = url.appendingPathComponent(name, isDirectory: true)
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        return folder
    }

    /// Writes a file, making the folders above it.
    @discardableResult
    static func write(_ text: String, to file: URL, mode: Int = 0o644) -> URL {
        try? FileManager.default.createDirectory(at: file.deletingLastPathComponent(),
                                                 withIntermediateDirectories: true)
        try? Data(text.utf8).write(to: file)
        chmod(file.path, mode_t(mode))
        return file
    }
}

/// A file of the package, by its path from the package's folder: among the
/// test's runfiles under Bazel, beside the sources otherwise.
enum PackageFiles {
    static func url(_ path: String, file: StaticString = #filePath, line: UInt = #line) -> URL {
        var candidates: [String] = []
        let environment = ProcessInfo.processInfo.environment
        if let runfiles = environment["TEST_SRCDIR"] {
            for workspace in [environment["TEST_WORKSPACE"], "_main"].compactMap({ $0 }) {
                candidates.append("\(runfiles)/\(workspace)/packages/vitruvian-sdk/\(path)")
            }
        }
        var package = URL(fileURLWithPath: "\(file)")
        for _ in 0..<3 { package.deleteLastPathComponent() }
        candidates.append(package.appendingPathComponent(path).path)
        if let found = candidates.first(where: { FileManager.default.fileExists(atPath: $0) }) {
            return URL(fileURLWithPath: found)
        }
        XCTFail("\(path) is missing; looked in \(candidates)", file: file, line: line)
        return URL(fileURLWithPath: "/nonexistent")
    }

    static func data(_ path: String, file: StaticString = #filePath, line: UInt = #line) -> Data {
        FileManager.default.contents(atPath: url(path, file: file, line: line).path) ?? Data()
    }
}

/// `protocol/examples/folders.json`: folders this command and the app must
/// judge alike, and the code that makes one.
struct FolderExample {
    let about: String
    let verdict: String
    /// The manifest's rule that is broken, when the verdict is `manifest`.
    let rule: String?
    let limits: FolderLimits
    let make: [JSONValue]

    static func all() throws -> (base: [String: JSONValue], examples: [FolderExample]) {
        let file = try JSONDecoder().decode(JSONValue.self, from: PackageFiles.data("protocol/examples/folders.json"))
        let examples = (file["examples"]?.arrayValue ?? []).map { example in
            FolderExample(about: example["about"]?.stringValue ?? "",
                          verdict: example["verdict"]?.stringValue ?? "",
                          rule: example["rule"]?.stringValue,
                          limits: FolderLimits(
                              bytes: (example["limits"]?["bytes"]?.numberValue).map { Int($0) } ?? FolderLimits().bytes,
                              things: (example["limits"]?["things"]?.numberValue).map { Int($0) } ?? FolderLimits().things),
                          make: example["make"]?.arrayValue ?? [])
        }
        return (file["base"]?.objectValue ?? [:], examples)
    }

    /// Does the example's steps in `folder`, which is empty.
    func build(in folder: URL, base: [String: JSONValue]) throws {
        for step in make {
            if let change = step["manifest"]?.objectValue {
                var fields = base
                for (key, value) in change {
                    if value == .null { fields.removeValue(forKey: key) } else { fields[key] = value }
                }
                try JSONEncoder().encode(JSONValue.object(fields))
                    .write(to: folder.appendingPathComponent(ToolManifestFile.fileName))
            } else if let path = step["file"]?.stringValue {
                let file = folder.appendingPathComponent(path)
                try FileManager.default.createDirectory(at: file.deletingLastPathComponent(),
                                                        withIntermediateDirectories: true)
                try Data(count: Int(step["bytes"]?.numberValue ?? 0)).write(to: file)
                chmod(file.path, mode_t(step["mode"]?.stringValue ?? "644", radix: 8) ?? 0o644)
            } else if let path = step["link"]?.stringValue {
                let link = folder.appendingPathComponent(path)
                try FileManager.default.createDirectory(at: link.deletingLastPathComponent(),
                                                        withIntermediateDirectories: true)
                try FileManager.default.createSymbolicLink(atPath: link.path,
                                                           withDestinationPath: step["to"]?.stringValue ?? "")
            } else if let path = step["pipe"]?.stringValue {
                let pipe = folder.appendingPathComponent(path)
                try FileManager.default.createDirectory(at: pipe.deletingLastPathComponent(),
                                                        withIntermediateDirectories: true)
                let mode = mode_t(step["mode"]?.stringValue ?? "644", radix: 8) ?? 0o644
                XCTAssertEqual(mkfifo(pipe.path, mode), 0, "the named pipe could not be made")
                chmod(pipe.path, mode)
            } else if let path = step["quarantine"]?.stringValue {
                let mark = Array("0081;00000000;Safari;".utf8)
                XCTAssertEqual(setxattr(folder.appendingPathComponent(path).path, "com.apple.quarantine", mark,
                                        mark.count, 0, 0), 0, "the quarantine mark could not be set")
            } else {
                XCTFail("\(about): a step this test does not know: \(step)")
            }
        }
    }
}
