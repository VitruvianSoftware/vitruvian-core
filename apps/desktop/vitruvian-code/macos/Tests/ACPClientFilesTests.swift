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
@testable import VitruvianCodeCore
import XCTest

final class ACPClientFilesTests: XCTestCase {
    private func makeSandbox() throws -> (
        root: URL,
        workspace: URL,
        extra: URL,
        outside: URL
    ) {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("acp-files-\(UUID().uuidString)", isDirectory: true)
        let workspace = root.appendingPathComponent("workspace", isDirectory: true)
        let extra = root.appendingPathComponent("extra", isDirectory: true)
        let outside = root.appendingPathComponent("outside", isDirectory: true)
        for dir in [workspace, extra, outside] {
            try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        }
        return (root, workspace, extra, outside)
    }

    func testReadsInsideWorkingAndAdditionalFoldersAndHonoursOneIndexedLineAndLimit() throws {
        let sandbox = try makeSandbox()
        defer { try? FileManager.default.removeItem(at: sandbox.root) }

        let noteURL = sandbox.workspace.appendingPathComponent("notes.txt")
        try "alpha\r\nbeta\ngamma\ndelta\nepsilon".write(to: noteURL, atomically: true, encoding: .utf8)

        let extraFileURL = sandbox.extra.appendingPathComponent("shared.txt")
        try "from-extra".write(to: extraFileURL, atomically: true, encoding: .utf8)

        let files = ACPClientFiles(
            workingDirectory: sandbox.workspace.path,
            additionalDirectories: [sandbox.extra.path]
        )
        let readPolicy = ACPClientPolicy(readTextFile: true)

        let full = try files.readTextFile(
            ACPReadTextFileParams(sessionId: "s1", path: "notes.txt"),
            policy: readPolicy
        )
        XCTAssertEqual(full.content, "alpha\r\nbeta\ngamma\ndelta\nepsilon")

        let sliced = try files.readTextFile(
            ACPReadTextFileParams(sessionId: "s1", path: noteURL.path, line: 2, limit: 2),
            policy: readPolicy
        )
        XCTAssertEqual(sliced.content, "beta\ngamma")

        let fromExtra = try files.readTextFile(
            ACPReadTextFileParams(sessionId: "s1", path: extraFileURL.path),
            policy: readPolicy
        )
        XCTAssertEqual(fromExtra.content, "from-extra")
    }

    func testRefusesReadsOutsideAllowedFolders() throws {
        let sandbox = try makeSandbox()
        defer { try? FileManager.default.removeItem(at: sandbox.root) }

        let secretURL = sandbox.outside.appendingPathComponent("secret.txt")
        try "top-secret".write(to: secretURL, atomically: true, encoding: .utf8)

        let files = ACPClientFiles(workingDirectory: sandbox.workspace.path)
        let readPolicy = ACPClientPolicy(readTextFile: true)

        XCTAssertThrowsError(
            try files.readTextFile(
                ACPReadTextFileParams(sessionId: "s1", path: secretURL.path),
                policy: readPolicy
            )
        ) { error in
            let rpc = error as? ACPRPCError
            XCTAssertEqual(rpc?.code, ACPRPCError.invalidParams)
        }

        XCTAssertThrowsError(
            try files.readTextFile(
                ACPReadTextFileParams(sessionId: "s1", path: "../outside/secret.txt"),
                policy: readPolicy
            )
        ) { error in
            let rpc = error as? ACPRPCError
            XCTAssertEqual(rpc?.code, ACPRPCError.invalidParams)
        }
    }

    func testRefusesReadsAndWritesThroughSymlinkPointingOutsideWorkspace() throws {
        let sandbox = try makeSandbox()
        defer { try? FileManager.default.removeItem(at: sandbox.root) }

        let outsideTarget = sandbox.outside.appendingPathComponent("target.txt")
        try "outside-payload".write(to: outsideTarget, atomically: true, encoding: .utf8)

        let escapeFileLink = sandbox.workspace.appendingPathComponent("escape-file.txt")
        try FileManager.default.createSymbolicLink(at: escapeFileLink, withDestinationURL: outsideTarget)

        let escapeDirLink = sandbox.workspace.appendingPathComponent("escape-dir")
        try FileManager.default.createSymbolicLink(at: escapeDirLink, withDestinationURL: sandbox.outside)

        let files = ACPClientFiles(workingDirectory: sandbox.workspace.path)
        let rwPolicy = ACPClientPolicy(readTextFile: true, writeTextFile: true)

        XCTAssertThrowsError(
            try files.readTextFile(
                ACPReadTextFileParams(sessionId: "s1", path: escapeFileLink.path),
                policy: rwPolicy
            )
        )
        XCTAssertThrowsError(
            try files.writeTextFile(
                ACPWriteTextFileParams(
                    sessionId: "s1",
                    path: escapeDirLink.appendingPathComponent("created-outside.txt").path,
                    content: "nope"
                ),
                policy: rwPolicy
            )
        )
        XCTAssertFalse(
            FileManager.default.fileExists(
                atPath: sandbox.outside.appendingPathComponent("created-outside.txt").path
            )
        )
    }

    func testRefusesWhenPathCannotBeResolvedFailingClosed() throws {
        let sandbox = try makeSandbox()
        defer { try? FileManager.default.removeItem(at: sandbox.root) }

        // Dangling symlink inside workspace pointing to a missing file outside.
        let danglingLink = sandbox.workspace.appendingPathComponent("dangling.txt")
        try FileManager.default.createSymbolicLink(
            atPath: danglingLink.path,
            withDestinationPath: sandbox.outside.appendingPathComponent("missing.txt").path
        )

        XCTAssertNil(ACPClientFiles.canonicalPathForContainment(danglingLink.path))
        XCTAssertNil(ACPClientFiles.canonicalPathForContainment("relative/path.txt"))
        XCTAssertNil(ACPClientFiles.canonicalPathForContainment(""))

        let files = ACPClientFiles(workingDirectory: sandbox.workspace.path)
        let rwPolicy = ACPClientPolicy(readTextFile: true, writeTextFile: true)

        XCTAssertThrowsError(
            try files.readTextFile(
                ACPReadTextFileParams(sessionId: "s1", path: danglingLink.path),
                policy: rwPolicy
            )
        )
        XCTAssertThrowsError(
            try files.writeTextFile(
                ACPWriteTextFileParams(sessionId: "s1", path: danglingLink.path, content: "blocked"),
                policy: rwPolicy
            )
        )

        // Relative working directory cannot resolve relative paths safely.
        let unresolvableFiles = ACPClientFiles(workingDirectory: "not-an-absolute-root")
        XCTAssertThrowsError(
            try unresolvableFiles.readTextFile(
                ACPReadTextFileParams(sessionId: "s1", path: "file.txt"),
                policy: rwPolicy
            )
        )
    }

    func testWritesAndReadsRefusedWithMethodNotFoundWhenPolicyIsOff() throws {
        let sandbox = try makeSandbox()
        defer { try? FileManager.default.removeItem(at: sandbox.root) }

        let targetURL = sandbox.workspace.appendingPathComponent("written.txt")
        let files = ACPClientFiles(workingDirectory: sandbox.workspace.path)

        XCTAssertThrowsError(
            try files.writeTextFile(
                ACPWriteTextFileParams(sessionId: "s1", path: targetURL.path, content: "should-not-write"),
                policy: ACPClientPolicy(readTextFile: true, writeTextFile: false)
            )
        ) { error in
            XCTAssertEqual((error as? ACPRPCError)?.code, ACPRPCError.methodNotFound)
        }
        XCTAssertFalse(FileManager.default.fileExists(atPath: targetURL.path))

        XCTAssertThrowsError(
            try files.readTextFile(
                ACPReadTextFileParams(sessionId: "s1", path: targetURL.path),
                policy: ACPClientPolicy.none
            )
        ) { error in
            XCTAssertEqual((error as? ACPRPCError)?.code, ACPRPCError.methodNotFound)
        }

        // Enabling `writeTextFile` allows writing inside the workspace.
        _ = try files.writeTextFile(
            ACPWriteTextFileParams(sessionId: "s1", path: "subdir/written.txt", content: "hello-write"),
            policy: ACPClientPolicy(readTextFile: true, writeTextFile: true)
        )
        let written = try String(
            contentsOf: sandbox.workspace.appendingPathComponent("subdir/written.txt"),
            encoding: .utf8
        )
        XCTAssertEqual(written, "hello-write")
    }

    func testClientTerminalsHonourPolicyOutputByteCapKillAndRelease() async throws {
        let sandbox = try makeSandbox()
        defer { try? FileManager.default.removeItem(at: sandbox.root) }

        let files = ACPClientFiles(workingDirectory: sandbox.workspace.path)
        let terminals = ACPClientTerminals(killGrace: 0.12)

        // Policy off -> method not found (-32601).
        do {
            _ = try await terminals.create(
                ACPTerminalCreateParams(sessionId: "s1", command: "echo hi"),
                policy: .none,
                files: files
            )
            XCTFail("Expected methodNotFound when terminal policy is false")
        } catch let error as ACPRPCError {
            XCTAssertEqual(error.code, ACPRPCError.methodNotFound)
        }

        let terminalPolicy = ACPClientPolicy(terminal: true)

        // Output byte cap truncates cleanly from the start on a UTF-8 boundary.
        let created = try await withACPTestTimeout(seconds: 3.0) {
            try await terminals.create(
                ACPTerminalCreateParams(
                    sessionId: "s1",
                    command: "printf '0123456789abcdefFINAL'",
                    outputByteLimit: 10
                ),
                policy: terminalPolicy,
                files: files
            )
        }
        let exitStatus = try await withACPTestTimeout(seconds: 3.0) {
            try await terminals.waitForExit(
                ACPTerminalWaitForExitParams(sessionId: "s1", terminalId: created.terminalId),
                policy: terminalPolicy
            )
        }
        XCTAssertEqual(exitStatus.exitCode, 0)

        let output = try await withACPTestTimeout(seconds: 3.0) {
            try await terminals.output(
                ACPTerminalOutputParams(sessionId: "s1", terminalId: created.terminalId),
                policy: terminalPolicy
            )
        }
        XCTAssertTrue(output.truncated)
        XCTAssertLessThanOrEqual(output.output.utf8.count, 10)
        XCTAssertTrue(output.output.hasSuffix("FINAL"))
        _ = try await terminals.release(
            ACPTerminalReleaseParams(sessionId: "s1", terminalId: created.terminalId),
            policy: terminalPolicy
        )

        // `kill` ends a long-running terminal process group, and `release` removes it.
        let sleeper = try await withACPTestTimeout(seconds: 3.0) {
            try await terminals.create(
                ACPTerminalCreateParams(sessionId: "s1", command: "sleep 60"),
                policy: terminalPolicy,
                files: files
            )
        }
        _ = try await withACPTestTimeout(seconds: 3.0) {
            try await terminals.kill(
                ACPTerminalKillParams(sessionId: "s1", terminalId: sleeper.terminalId),
                policy: terminalPolicy
            )
        }
        _ = try await withACPTestTimeout(seconds: 3.0) {
            try await terminals.release(
                ACPTerminalReleaseParams(sessionId: "s1", terminalId: sleeper.terminalId),
                policy: terminalPolicy
            )
        }

        do {
            _ = try await terminals.output(
                ACPTerminalOutputParams(sessionId: "s1", terminalId: sleeper.terminalId),
                policy: terminalPolicy
            )
            XCTFail("Released terminal must no longer be queryable")
        } catch let error as ACPRPCError {
            XCTAssertEqual(error.code, ACPRPCError.invalidParams)
        }
    }

    func testRefusesInvalidUTF8AndNULContainingFilesOnReadTextFile() throws {
        let sandbox = try makeSandbox()
        defer { try? FileManager.default.removeItem(at: sandbox.root) }

        let invalidUTF8URL = sandbox.workspace.appendingPathComponent("bad-utf8.bin")
        try Data([0x68, 0x69, 0xFF, 0xFE, 0x0A]).write(to: invalidUTF8URL)

        let nulFileURL = sandbox.workspace.appendingPathComponent("contains-nul.txt")
        try Data("hello\0world\n".utf8).write(to: nulFileURL)

        let files = ACPClientFiles(workingDirectory: sandbox.workspace.path)
        let readPolicy = ACPClientPolicy(readTextFile: true)

        XCTAssertThrowsError(
            try files.readTextFile(
                ACPReadTextFileParams(sessionId: "s1", path: "bad-utf8.bin"),
                policy: readPolicy
            )
        ) { error in
            let rpc = error as? ACPRPCError
            XCTAssertEqual(rpc?.code, ACPRPCError.invalidParams)
            XCTAssertTrue(rpc?.message.contains("not a UTF-8 text file") ?? false)
        }

        XCTAssertThrowsError(
            try files.readTextFile(
                ACPReadTextFileParams(sessionId: "s1", path: "contains-nul.txt"),
                policy: readPolicy
            )
        ) { error in
            let rpc = error as? ACPRPCError
            XCTAssertEqual(rpc?.code, ACPRPCError.invalidParams)
            XCTAssertTrue(rpc?.message.contains("contains binary data") ?? false)
        }
    }

    func testClientTerminalsRejectSessionIDMismatchOnEveryRequest() async throws {
        let sandbox = try makeSandbox()
        defer { try? FileManager.default.removeItem(at: sandbox.root) }

        let files = ACPClientFiles(workingDirectory: sandbox.workspace.path)
        let terminals = ACPClientTerminals(killGrace: 0.1, waitForExitTimeout: 0.5)
        let policy = ACPClientPolicy(terminal: true)

        // 1. `terminal/create` rejects mismatched or empty `sessionId`.
        do {
            _ = try await terminals.create(
                ACPTerminalCreateParams(sessionId: "wrong-session", command: "printf ok"),
                policy: policy,
                files: files,
                expectedSessionID: "s-active"
            )
            XCTFail("terminal/create must reject mismatched sessionId")
        } catch let error as ACPRPCError {
            XCTAssertEqual(error.code, ACPRPCError.invalidParams)
        }

        let created = try await terminals.create(
            ACPTerminalCreateParams(sessionId: "s-active", command: "sleep 30"),
            policy: policy,
            files: files,
            expectedSessionID: "s-active"
        )

        // 2. `terminal/output` rejects mismatched `sessionId`.
        do {
            _ = try await terminals.output(
                ACPTerminalOutputParams(sessionId: "s-other", terminalId: created.terminalId),
                policy: policy,
                expectedSessionID: "s-active"
            )
            XCTFail("terminal/output must reject mismatched sessionId")
        } catch let error as ACPRPCError {
            XCTAssertEqual(error.code, ACPRPCError.invalidParams)
        }

        // 3. `terminal/wait_for_exit` rejects mismatched `sessionId`.
        do {
            _ = try await terminals.waitForExit(
                ACPTerminalWaitForExitParams(sessionId: "s-other", terminalId: created.terminalId),
                policy: policy,
                expectedSessionID: "s-active"
            )
            XCTFail("terminal/wait_for_exit must reject mismatched sessionId")
        } catch let error as ACPRPCError {
            XCTAssertEqual(error.code, ACPRPCError.invalidParams)
        }

        // 4. `terminal/kill` rejects mismatched `sessionId`.
        do {
            _ = try await terminals.kill(
                ACPTerminalKillParams(sessionId: "s-other", terminalId: created.terminalId),
                policy: policy,
                expectedSessionID: "s-active"
            )
            XCTFail("terminal/kill must reject mismatched sessionId")
        } catch let error as ACPRPCError {
            XCTAssertEqual(error.code, ACPRPCError.invalidParams)
        }

        // 5. `terminal/release` rejects mismatched `sessionId`.
        do {
            _ = try await terminals.release(
                ACPTerminalReleaseParams(sessionId: "s-other", terminalId: created.terminalId),
                policy: policy,
                expectedSessionID: "s-active"
            )
            XCTFail("terminal/release must reject mismatched sessionId")
        } catch let error as ACPRPCError {
            XCTAssertEqual(error.code, ACPRPCError.invalidParams)
        }

        // Matching `sessionId` succeeds and cleans up.
        _ = try await terminals.release(
            ACPTerminalReleaseParams(sessionId: "s-active", terminalId: created.terminalId),
            policy: policy,
            expectedSessionID: "s-active"
        )
    }

    func testClientTerminalsEnforceMaxRetainedTerminalsAndMaxRetainedOutputBytes() async throws {
        let sandbox = try makeSandbox()
        defer { try? FileManager.default.removeItem(at: sandbox.root) }

        let files = ACPClientFiles(workingDirectory: sandbox.workspace.path)
        let policy = ACPClientPolicy(terminal: true)

        // 1. Verify default `maxRetainedTerminals` (32): releasing 34 terminals evicts the oldest 2
        //    snapshots while retaining the newest 32 for embedded tool-call content.
        let countTerminals = ACPClientTerminals(killGrace: 0.1)
        var createdIDs: [String] = []
        let totalReleased = ACPClientTerminals.maxRetainedTerminals + 2
        for index in 0..<totalReleased {
            let created = try await countTerminals.create(
                ACPTerminalCreateParams(
                    sessionId: "s-ret",
                    command: "/bin/echo",
                    args: ["snap-\(index)"]
                ),
                policy: policy,
                files: files,
                expectedSessionID: "s-ret"
            )
            _ = try await countTerminals.waitForExit(
                ACPTerminalWaitForExitParams(sessionId: "s-ret", terminalId: created.terminalId),
                policy: policy,
                expectedSessionID: "s-ret"
            )
            _ = try await countTerminals.release(
                ACPTerminalReleaseParams(sessionId: "s-ret", terminalId: created.terminalId),
                policy: policy,
                expectedSessionID: "s-ret"
            )
            createdIDs.append(created.terminalId)
        }

        let evictedFirst = await countTerminals.readOutputSnapshot(sessionId: "s-ret", terminalId: createdIDs[0])
        let evictedSecond = await countTerminals.readOutputSnapshot(sessionId: "s-ret", terminalId: createdIDs[1])
        let retainedOldest = await countTerminals.readOutputSnapshot(sessionId: "s-ret", terminalId: createdIDs[2])
        let retainedNewest = await countTerminals.readOutputSnapshot(sessionId: "s-ret", terminalId: createdIDs[totalReleased - 1])
        XCTAssertNil(evictedFirst, "Oldest released snapshot #0 must be pruned past maxRetainedTerminals")
        XCTAssertNil(evictedSecond, "Oldest released snapshot #1 must be pruned past maxRetainedTerminals")
        XCTAssertEqual(retainedOldest?.output.trimmingCharacters(in: .whitespacesAndNewlines), "snap-2")
        XCTAssertEqual(retainedNewest?.output.trimmingCharacters(in: .whitespacesAndNewlines), "snap-\(totalReleased - 1)")
        await countTerminals.closeAll()

        // 2. Verify default `maxRetainedOutputBytes` (16 MiB): three 6 MiB terminals (18 MiB > 16 MiB)
        //    trim oldest live output via `enforceTotalOutputLimit` and prune released snapshots past 16 MiB.
        let byteTerminals = ACPClientTerminals(killGrace: 0.1)
        var bigIDs: [String] = []
        let sixMiB = 6 * 1024 * 1024
        for idx in 0..<3 {
            let ch = ["A", "B", "C"][idx]
            let created = try await byteTerminals.create(
                ACPTerminalCreateParams(
                    sessionId: "s-bytes",
                    command: "head -c \(sixMiB) /dev/zero | tr '\\0' '\(ch)'",
                    outputByteLimit: ACPClientTerminals.maxOutputByteLimit
                ),
                policy: policy,
                files: files,
                expectedSessionID: "s-bytes"
            )
            _ = try await byteTerminals.waitForExit(
                ACPTerminalWaitForExitParams(sessionId: "s-bytes", terminalId: created.terminalId),
                policy: policy,
                expectedSessionID: "s-bytes"
            )
            bigIDs.append(created.terminalId)
        }

        let firstLiveSnap = await byteTerminals.readOutputSnapshot(sessionId: "s-bytes", terminalId: bigIDs[0])
        let secondLiveSnap = await byteTerminals.readOutputSnapshot(sessionId: "s-bytes", terminalId: bigIDs[1])
        let thirdLiveSnap = await byteTerminals.readOutputSnapshot(sessionId: "s-bytes", terminalId: bigIDs[2])
        let totalBufferedBytes = (firstLiveSnap?.output.utf8.count ?? 0)
            + (secondLiveSnap?.output.utf8.count ?? 0)
            + (thirdLiveSnap?.output.utf8.count ?? 0)
        XCTAssertLessThanOrEqual(
            totalBufferedBytes,
            ACPClientTerminals.maxRetainedOutputBytes,
            "Total buffered bytes across terminals must never exceed maxRetainedOutputBytes (16 MiB)"
        )
        XCTAssertEqual(firstLiveSnap?.truncated, true, "Oldest terminal buffer must be trimmed first")
        XCTAssertEqual(thirdLiveSnap?.output.utf8.count, sixMiB)

        await byteTerminals.closeAll()
    }
}
