// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 VitruvianSoftware

import Darwin
import Foundation
import VitruvianCore
import VitruvianServices
import VitruvianToolProtocol

/// Folders the app and the SDK's `vitruvian-tool validate` must judge
/// alike. The examples are one file in the SDK's package,
/// `packages/vitruvian-sdk/protocol/examples/folders.json`, which Bazel
/// hands to the tests. The package's own test makes the same folders and
/// asks its own code (`FolderCheckTests`). Neither side is given the
/// other's answer, so a rule changed on one side only fails one of the two.
///
/// The package cannot use the app's code: it is under another licence. This
/// file is how its copy of the rules is kept honest.
enum ToolFolderExamplesTests {
    static func run(_ suite: TestSuite) {
        guard let file = examples, let base = file["base"]?.objectValue,
              let all = file["examples"]?.arrayValue else {
            suite.expect(false, "the folder examples are handed to the tests in VITRUVIAN_FOLDER_EXAMPLES")
            return
        }
        suite.expect(all.count == 22, "the file holds twenty-two folders, and each is judged below")
        for (index, example) in all.enumerated() {
            var limits = ToolLimits.standard
            if let bytes = example["limits"]?["bytes"]?.numberValue { limits.folderBytes = Int(bytes) }
            if let things = example["limits"]?["things"]?.numberValue { limits.folderItems = Int(things) }
            let bench = ExternalToolStoreTests.Bench(limits: limits)
            defer { bench.close() }
            let folder = bench.root.appendingPathComponent("example-\(index)", isDirectory: true)
            try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            let made = make(example["make"]?.arrayValue ?? [], in: folder, base: base)
            let offered = bench.store.offer(from: folder)
            let said = verdict(offered)
            let about = example["about"]?.stringValue ?? "example \(index)"
            suite.expect(made && said == example["verdict"]?.stringValue
                             && rule(offered) == example["rule"]?.stringValue && !bench.exists(bench.support),
                         "\(about): the app says \(said), the examples \(example["verdict"]?.stringValue ?? "nothing"); "
                             + "the rule is \(rule(offered) ?? "none"), the examples' \(example["rule"]?.stringValue ?? "none"); "
                             + "and nothing is copied by looking")
        }
    }

    /// The examples, below the runfiles Bazel gives the test.
    static var examples: JSONValue? {
        let environment = ProcessInfo.processInfo.environment
        guard let path = environment["VITRUVIAN_FOLDER_EXAMPLES"], let runfiles = environment["TEST_SRCDIR"],
              let workspace = environment["TEST_WORKSPACE"],
              let data = FileManager.default.contents(atPath: "\(runfiles)/\(workspace)/\(path)") else { return nil }
        return try? JSONDecoder().decode(JSONValue.self, from: data)
    }

    /// What the app says of a folder, in the examples' words.
    static func verdict(_ offered: Result<ToolOffer, ExternalToolStore.Refusal>) -> String {
        switch offered {
        case .success: return "ok"
        case .failure(.manifest(.noManifest)): return "noManifest"
        case .failure(.manifest(.invalid)): return "manifest"
        case .failure(.manifest(.programMissing)): return "programMissing"
        case .failure(.manifest(.programOutsideFolder)): return "programOutsideFolder"
        case .failure(.manifest(.programNotExecutable)): return "programNotExecutable"
        case .failure(.quarantined): return "quarantined"
        case .failure(.tooBig): return "tooBig"
        case .failure(let other): return "\(other)"
        }
    }

    /// The manifest's rule the app says is broken, by its name alone; nil
    /// when the app refuses for anything else, or not at all.
    static func rule(_ offered: Result<ToolOffer, ExternalToolStore.Refusal>) -> String? {
        guard case .failure(.manifest(.invalid(let problem))) = offered else { return nil }
        return String("\(problem)".prefix { $0 != "(" })
    }

    /// Does an example's steps in `folder`. False for a step this does not
    /// know, or one that could not be done.
    static func make(_ steps: [JSONValue], in folder: URL, base: [String: JSONValue]) -> Bool {
        let files = FileManager.default
        for step in steps {
            if let change = step["manifest"]?.objectValue {
                var fields = base
                for (key, value) in change {
                    if value == .null { fields.removeValue(forKey: key) } else { fields[key] = value }
                }
                guard let bytes = try? JSONEncoder().encode(JSONValue.object(fields)),
                      (try? bytes.write(to: folder.appendingPathComponent(ToolManifestFile.fileName))) != nil
                else { return false }
            } else if let path = step["file"]?.stringValue {
                let file = folder.appendingPathComponent(path)
                let mode = Int(step["mode"]?.stringValue ?? "644", radix: 8) ?? 0o644
                try? files.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
                guard files.createFile(atPath: file.path, contents: Data(count: Int(step["bytes"]?.numberValue ?? 0)),
                                       attributes: [.posixPermissions: mode]) else { return false }
            } else if let path = step["link"]?.stringValue, let target = step["to"]?.stringValue {
                let link = folder.appendingPathComponent(path)
                try? files.createDirectory(at: link.deletingLastPathComponent(), withIntermediateDirectories: true)
                guard (try? files.createSymbolicLink(atPath: link.path, withDestinationPath: target)) != nil
                else { return false }
            } else if let path = step["pipe"]?.stringValue {
                let pipe = folder.appendingPathComponent(path)
                let mode = mode_t(step["mode"]?.stringValue ?? "644", radix: 8) ?? 0o644
                try? files.createDirectory(at: pipe.deletingLastPathComponent(), withIntermediateDirectories: true)
                guard mkfifo(pipe.path, mode) == 0, chmod(pipe.path, mode) == 0 else { return false }
            } else if let path = step["quarantine"]?.stringValue {
                let mark = Array("0081;00000000;Safari;".utf8)
                guard setxattr(folder.appendingPathComponent(path).path, "com.apple.quarantine", mark, mark.count,
                               0, 0) == 0 else { return false }
            } else {
                return false
            }
        }
        return true
    }
}
