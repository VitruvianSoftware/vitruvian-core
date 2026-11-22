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
import XCTest

import VitruvianCodeCore

final class BundledNodeTests: XCTestCase {

    private var scratch: URL!

    override func setUpWithError() throws {
        scratch = FileManager.default.temporaryDirectory
            .appendingPathComponent("BundledNodeTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: scratch, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: scratch)
    }

    private func writeExecutable(_ url: URL, content: String = "#!/bin/sh\necho v22.21.1\n") throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try content.write(to: url, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: url.path)
    }

    private func writeFile(_ url: URL, content: String) throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try content.write(to: url, atomically: true, encoding: .utf8)
    }

    private func makeApp(name: String = "Sample.app", files: [(path: String, content: String, executable: Bool)]) throws -> Bundle {
        let appRoot = scratch.appendingPathComponent("\(UUID().uuidString)/\(name)", isDirectory: true)
        try writeFile(appRoot.appendingPathComponent("Contents/Info.plist"), content: """
        <?xml version="1.0" encoding="UTF-8"?>
        <plist version="1.0"><dict>
        <key>CFBundleExecutable</key><string>Sample</string>
        <key>CFBundleIdentifier</key><string>test.bundled.node</string>
        <key>CFBundlePackageType</key><string>APPL</string>
        </dict></plist>
        """)
        try writeExecutable(appRoot.appendingPathComponent("Contents/MacOS/Sample"))
        for entry in files {
            let target = appRoot.appendingPathComponent("Contents/" + entry.path)
            if entry.executable {
                try writeExecutable(target, content: entry.content)
            } else {
                try writeFile(target, content: entry.content)
            }
        }
        return try XCTUnwrap(Bundle(url: appRoot))
    }

    func testFindsBundledNodeAndHelperInAppBundleLayout() throws {
        let bundle = try makeApp(files: [
            ("Helpers/node", "#!/bin/sh\n", true),
            ("Resources/claude-helper/claude-helper.mjs", "console.log('helper');\n", false),
        ])

        let found = try XCTUnwrap(BundledNode.locate(in: bundle))
        XCTAssertEqual(found.nodeURL, bundle.bundleURL.appendingPathComponent("Contents/Helpers/node").standardizedFileURL)
        XCTAssertEqual(found.helperURL, bundle.bundleURL.appendingPathComponent("Contents/Resources/claude-helper/claude-helper.mjs").standardizedFileURL)
    }

    func testPrefersAppBundleHelpersAndResourcesOverSiblingOrSwiftPMCopies() throws {
        let bundle = try makeApp(files: [
            ("Helpers/node", "#!/bin/sh\n", true),
            ("Resources/claude-helper/claude-helper.mjs", "// app-resources\n", false),
            ("MacOS/node", "#!/bin/sh\n", true),
            ("MacOS/claude-helper/claude-helper.mjs", "// macos-sibling\n", false),
            ("Resources/VitruvianCode_VitruvianCodeUI.bundle/node", "#!/bin/sh\n", true),
            ("Resources/VitruvianCode_VitruvianCodeUI.bundle/claude-helper/claude-helper.mjs", "// swiftpm\n", false),
        ])

        let found = try XCTUnwrap(BundledNode.locate(in: bundle))
        XCTAssertEqual(found.nodeURL, bundle.bundleURL.appendingPathComponent("Contents/Helpers/node").standardizedFileURL)
        XCTAssertEqual(found.helperURL, bundle.bundleURL.appendingPathComponent("Contents/Resources/claude-helper/claude-helper.mjs").standardizedFileURL)
    }

    func testFindsBundledNodeAndHelperBesideExecutableInToolBinLayout() throws {
        let binDir = scratch.appendingPathComponent("extension/bin", isDirectory: true)
        let toolExe = binDir.appendingPathComponent("tool")
        let node = binDir.appendingPathComponent("node")
        let helper = binDir.appendingPathComponent("claude-helper/claude-helper.mjs")
        try writeExecutable(toolExe)
        try writeExecutable(node)
        try writeFile(helper, content: "export {};\n")

        let found = try XCTUnwrap(BundledNode.locate(bundleURL: binDir, resourceURL: binDir, executableURL: toolExe))
        XCTAssertEqual(found.nodeURL, node.standardizedFileURL)
        XCTAssertEqual(found.helperURL, helper.standardizedFileURL)
    }

    func testFindsBundledNodeAndHelperInSwiftPMResourceBundleLayouts() throws {
        // Flat SwiftPM resource bundle beside executable
        let flatExecDir = scratch.appendingPathComponent("swiftpm-flat", isDirectory: true)
        let flatExe = flatExecDir.appendingPathComponent("VitruvianCode")
        let flatBundle = flatExecDir.appendingPathComponent(BundleResources.swiftPMUIResourceBundleName, isDirectory: true)
        try writeExecutable(flatExe)
        try writeExecutable(flatBundle.appendingPathComponent("node"))
        try writeFile(flatBundle.appendingPathComponent("claude-helper/claude-helper.mjs"), content: "export {};\n")

        let flatFound = try XCTUnwrap(BundledNode.locate(bundleURL: flatExecDir, resourceURL: flatExecDir, executableURL: flatExe))
        XCTAssertEqual(flatFound.nodeURL, flatBundle.appendingPathComponent("node").standardizedFileURL)
        XCTAssertEqual(flatFound.helperURL, flatBundle.appendingPathComponent("claude-helper/claude-helper.mjs").standardizedFileURL)

        // Nested Contents/Resources SwiftPM resource bundle inside Contents/Resources
        let nestedBundle = try makeApp(files: [
            ("Resources/VitruvianCode_VitruvianCodeUI.bundle/Contents/Resources/node", "#!/bin/sh\n", true),
            ("Resources/VitruvianCode_VitruvianCodeUI.bundle/Contents/Resources/claude-helper/claude-helper.mjs", "export {};\n", false),
        ])

        let nestedFound = try XCTUnwrap(BundledNode.locate(in: nestedBundle))
        XCTAssertEqual(
            nestedFound.nodeURL,
            nestedBundle.bundleURL.appendingPathComponent("Contents/Resources/VitruvianCode_VitruvianCodeUI.bundle/Contents/Resources/node").standardizedFileURL
        )
        XCTAssertEqual(
            nestedFound.helperURL,
            nestedBundle.bundleURL.appendingPathComponent("Contents/Resources/VitruvianCode_VitruvianCodeUI.bundle/Contents/Resources/claude-helper/claude-helper.mjs").standardizedFileURL
        )
    }

    func testIgnoresNodeOnPathAndUserHomeWhenBundledNodeIsMissing() throws {
        let fakeBin = scratch.appendingPathComponent("path-bin", isDirectory: true)
        let fakeHome = scratch.appendingPathComponent("home", isDirectory: true)
        let nvmNode = fakeHome.appendingPathComponent(".nvm/versions/node/v22.21.1/bin/node")
        try writeExecutable(fakeBin.appendingPathComponent("node"))
        try writeExecutable(nvmNode)

        let origPath = getenv("PATH").map { String(cString: $0) }
        let origHome = getenv("HOME").map { String(cString: $0) }
        setenv("PATH", fakeBin.path, 1)
        setenv("HOME", fakeHome.path, 1)
        defer {
            if let origPath { setenv("PATH", origPath, 1) } else { unsetenv("PATH") }
            if let origHome { setenv("HOME", origHome, 1) } else { unsetenv("HOME") }
        }

        // Helper is present, but bundled node is absent: must return nil despite PATH and HOME node!
        let bundle = try makeApp(files: [
            ("Resources/claude-helper/claude-helper.mjs", "export {};\n", false),
        ])
        XCTAssertNil(BundledNode.nodeURL(in: bundle))
        XCTAssertNotNil(BundledNode.helperURL(in: bundle))
        XCTAssertNil(BundledNode.locate(in: bundle))
    }

    func testReturnsNilWhenEitherComponentIsMissingInvalidOrMisplacedInAppResources() throws {
        // Node in Contents/Resources/node (instead of Contents/Helpers/node) must NOT be accepted for an .app.
        let misplaced = try makeApp(files: [
            ("Resources/node", "#!/bin/sh\n", true),
            ("Resources/claude-helper/claude-helper.mjs", "export {};\n", false),
        ])
        XCTAssertNil(BundledNode.nodeURL(in: misplaced))
        XCTAssertNil(BundledNode.locate(in: misplaced))

        // Missing helper.
        let noHelper = try makeApp(files: [
            ("Helpers/node", "#!/bin/sh\n", true),
        ])
        XCTAssertNotNil(BundledNode.nodeURL(in: noHelper))
        XCTAssertNil(BundledNode.helperURL(in: noHelper))
        XCTAssertNil(BundledNode.locate(in: noHelper))

        // Non-executable node.
        let nonExecNode = try makeApp(files: [
            ("Helpers/node", "not-exec\n", false),
            ("Resources/claude-helper/claude-helper.mjs", "export {};\n", false),
        ])
        XCTAssertNil(BundledNode.locate(in: nonExecNode))

        // Empty helper file.
        let emptyHelper = try makeApp(files: [
            ("Helpers/node", "#!/bin/sh\n", true),
            ("Resources/claude-helper/claude-helper.mjs", "", false),
        ])
        XCTAssertNil(BundledNode.locate(in: emptyHelper))
    }

    // MARK: - Universal app: two thin Nodes in place of one fat `node`

    func testUniversalAppUsesTheThinNodeForTheArchitectureTheProcessRunsAs() throws {
        let bundle = try makeApp(files: [
            ("Helpers/node-arm64", "#!/bin/sh\n# arm64\n", true),
            ("Helpers/node-x86_64", "#!/bin/sh\n# x86_64\n", true),
            ("Resources/claude-helper/claude-helper.mjs", "export {};\n", false),
        ])
        for architecture in HelperArchitecture.all {
            let found = try XCTUnwrap(BundledNode.locate(in: bundle, architecture: architecture),
                                      "a universal app must give \(architecture) its own Node")
            XCTAssertEqual(
                found.nodeURL,
                bundle.bundleURL.appendingPathComponent("Contents/Helpers/node-\(architecture)").standardizedFileURL
            )
        }
        // A universal app running under Rosetta is an x86_64 process, and must
        // not be handed the arm64 Node (or the reverse).
        let arm = try XCTUnwrap(BundledNode.nodeURL(in: bundle, architecture: "arm64"))
        let intel = try XCTUnwrap(BundledNode.nodeURL(in: bundle, architecture: "x86_64"))
        XCTAssertNotEqual(arm, intel)
        // With no architecture named, the one this process runs as wins.
        XCTAssertEqual(
            try XCTUnwrap(BundledNode.nodeURL(in: bundle)).lastPathComponent,
            "node-\(HelperArchitecture.current)"
        )
    }

    func testThinNodeForThisArchitectureBeatsThePlainNodeInTheSameApp() throws {
        let bundle = try makeApp(files: [
            ("Helpers/node", "#!/bin/sh\n", true),
            ("Helpers/node-arm64", "#!/bin/sh\n", true),
            ("Helpers/node-x86_64", "#!/bin/sh\n", true),
            ("Resources/claude-helper/claude-helper.mjs", "export {};\n", false),
        ])
        XCTAssertEqual(BundledNode.nodeURL(in: bundle, architecture: "arm64")?.lastPathComponent, "node-arm64")
        XCTAssertEqual(BundledNode.nodeURL(in: bundle, architecture: "x86_64")?.lastPathComponent, "node-x86_64")
    }

    func testPlainNodeIsUsedWhenThereIsNoThinNodeForThisArchitecture() throws {
        // A single-architecture app ships `node`, thin, and nothing else.
        let bundle = try makeApp(files: [
            ("Helpers/node", "#!/bin/sh\n", true),
            ("Resources/claude-helper/claude-helper.mjs", "export {};\n", false),
        ])
        for architecture in HelperArchitecture.all {
            XCTAssertEqual(BundledNode.nodeURL(in: bundle, architecture: architecture)?.lastPathComponent, "node")
        }
    }

    func testNeverUsesTheOtherArchitecturesNode() throws {
        // Only the x86_64 Node is there: an arm64 process must find nothing
        // rather than run a program it cannot (and never fall back to PATH).
        let bundle = try makeApp(files: [
            ("Helpers/node-x86_64", "#!/bin/sh\n", true),
            ("Resources/claude-helper/claude-helper.mjs", "export {};\n", false),
        ])
        XCTAssertNil(BundledNode.nodeURL(in: bundle, architecture: "arm64"))
        XCTAssertNil(BundledNode.locate(in: bundle, architecture: "arm64"))
        XCTAssertNotNil(BundledNode.locate(in: bundle, architecture: "x86_64"))
    }

    func testThinNodeInResourcesOfAnAppIsStillRefused() throws {
        let bundle = try makeApp(files: [
            ("Resources/node-arm64", "#!/bin/sh\n", true),
            ("Resources/node-x86_64", "#!/bin/sh\n", true),
            ("Resources/claude-helper/claude-helper.mjs", "export {};\n", false),
        ])
        for architecture in HelperArchitecture.all {
            XCTAssertNil(BundledNode.nodeURL(in: bundle, architecture: architecture),
                         "Mach-O code never lives in Contents/Resources")
        }
    }

    func testToolFolderStillUsesThePlainNodeOnEveryArchitecture() throws {
        let binDir = scratch.appendingPathComponent("extension/bin", isDirectory: true)
        let toolExe = binDir.appendingPathComponent("tool")
        let node = binDir.appendingPathComponent("node")
        try writeExecutable(toolExe)
        try writeExecutable(node)
        try writeFile(binDir.appendingPathComponent("claude-helper/claude-helper.mjs"), content: "export {};\n")
        for architecture in HelperArchitecture.all {
            let found = try XCTUnwrap(
                BundledNode.locate(bundleURL: binDir, resourceURL: binDir, executableURL: toolExe,
                                   architecture: architecture)
            )
            XCTAssertEqual(found.nodeURL, node.standardizedFileURL)
        }
    }

    func testHelperFileNamesPutThisArchitectureFirst() {
        XCTAssertEqual(HelperArchitecture.fileNames("node", architecture: "arm64"), ["node-arm64", "node"])
        XCTAssertEqual(HelperArchitecture.fileNames("bot-engine", architecture: "x86_64"),
                       ["bot-engine-x86_64", "bot-engine"])
        XCTAssertTrue(HelperArchitecture.all.contains(HelperArchitecture.current))
        #if arch(arm64)
        XCTAssertEqual(HelperArchitecture.current, "arm64")
        #elseif arch(x86_64)
        XCTAssertEqual(HelperArchitecture.current, "x86_64")
        #endif
    }

    /// The single-architecture layout `bundle.rs` writes, file for file: the
    /// main program, both helpers, the helper's script and Mermaid's SwiftPM
    /// bundle. This runs under Bazel and SwiftPM alike; it never skips.
    func testFindsBundledNodeAndHelperInThePackagedAppLayout() throws {
        let bundle = try makeApp(files: [
            ("Helpers/bot-engine", "#!/bin/sh\n", true),
            ("Helpers/node", "#!/bin/sh\n", true),
            ("Resources/claude-helper/claude-helper.mjs", "export {};\n", false),
            ("Resources/VitruvianCode_VitruvianCodeUI.bundle/mermaid.min.js", "m\n", false),
        ])
        let found = try XCTUnwrap(BundledNode.locate(in: bundle), "the packaged app must hold bundled node and claude-helper.mjs")
        XCTAssertTrue(found.nodeURL.path.hasSuffix("/Sample.app/Contents/Helpers/node"), found.nodeURL.path)
        XCTAssertTrue(
            found.helperURL.path.hasSuffix("/Sample.app/Contents/Resources/claude-helper/claude-helper.mjs"),
            found.helperURL.path
        )
    }

    /// The universal layout the release and the Bazel app write: two thin
    /// copies of each helper and no fat file.
    func testFindsBundledNodeAndHelperInTheUniversalPackagedAppLayout() throws {
        let bundle = try makeApp(files: [
            ("Helpers/bot-engine-arm64", "#!/bin/sh\n", true),
            ("Helpers/bot-engine-x86_64", "#!/bin/sh\n", true),
            ("Helpers/node-arm64", "#!/bin/sh\n", true),
            ("Helpers/node-x86_64", "#!/bin/sh\n", true),
            ("Resources/claude-helper/claude-helper.mjs", "export {};\n", false),
            ("Resources/VitruvianCode_VitruvianCodeUI.bundle/mermaid.min.js", "m\n", false),
        ])
        let found = try XCTUnwrap(BundledNode.locate(in: bundle), "the universal app must hold a Node for this process")
        XCTAssertTrue(found.nodeURL.path.hasSuffix("/Sample.app/Contents/Helpers/node-\(HelperArchitecture.current)"),
                      found.nodeURL.path)
        XCTAssertTrue(
            found.helperURL.path.hasSuffix("/Sample.app/Contents/Resources/claude-helper/claude-helper.mjs"),
            found.helperURL.path
        )
    }
}
