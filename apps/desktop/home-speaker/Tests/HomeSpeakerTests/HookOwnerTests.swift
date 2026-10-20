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
import Testing
@testable import HomeSpeakerCore

// Who owns the agents' hook. A hook may run the app's program or the
// extension's (`…/Tools/dev.vitruvian.homespeaker/bin/tool`), and the app's
// launch-time repair must never take the hook back from an extension that
// is installed, unless the person chose the app.
//
// Every test works on agent settings inside its own temporary folder.

@Suite struct HookOwnerTests {
    let appProgram = "/Applications/HomeSpeaker.app/Contents/MacOS/HomeSpeaker"

    /// A temporary home, and a Vitruvian folder inside it.
    private func scratch() throws -> (home: URL, vitruvian: URL) {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("homespeaker-hook-owner-\(UUID().uuidString)")
        let home = root.appendingPathComponent("home")
        let vitruvian = root.appendingPathComponent("Vitruvian")
        try FileManager.default.createDirectory(at: home, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: vitruvian, withIntermediateDirectories: true)
        return (home, vitruvian)
    }

    /// The extension's program under `vitruvian`; created on disk when `exists`.
    private func extensionProgram(in vitruvian: URL, exists: Bool) throws -> String {
        let bin = vitruvian.appendingPathComponent("Tools/dev.vitruvian.homespeaker/bin")
        let program = bin.appendingPathComponent("tool")
        if exists {
            try FileManager.default.createDirectory(at: bin, withIntermediateDirectories: true)
            try Data("#!/bin/sh\n".utf8).write(to: program)
        }
        return program.path
    }

    /// Writes Claude Code's settings with one Stop hook running `program`,
    /// and returns the file's bytes.
    @discardableResult
    private func writeHook(home: URL, program: String) throws -> Data {
        let settings = CodingAgent.claudeCode.settingsURL(home: home)
        try FileManager.default.createDirectory(at: settings.deletingLastPathComponent(), withIntermediateDirectories: true)
        let command = AgentIntegration.hookCommand(executable: program, agent: .claudeCode)
        let json: [String: Any] = ["hooks": ["Stop": [["hooks": [["type": "command", "command": command, "timeout": 10]]]]]]
        let data = try JSONSerialization.data(withJSONObject: json)
        try data.write(to: settings)
        return data
    }

    private func settingsBytes(home: URL) throws -> Data {
        try Data(contentsOf: CodingAgent.claudeCode.settingsURL(home: home))
    }

    private func settings(home: URL) throws -> [String: Any] {
        try JSONSerialization.jsonObject(with: settingsBytes(home: home)) as? [String: Any] ?? [:]
    }

    @Test func theExtensionsProgramIsAHomeSpeaker() {
        #expect(AgentIntegration.isHomeSpeakerProgram(
            "/Users/me/Library/Application Support/Vitruvian/Tools/dev.vitruvian.homespeaker/bin/tool"))
        #expect(AgentIntegration.isHomeSpeakerProgram(appProgram), "the app's program still is")
    }

    @Test func aRandomToolIsNot() {
        #expect(!AgentIntegration.isHomeSpeakerProgram(
            "/Users/me/Library/Application Support/Vitruvian/Tools/other.tool/bin/tool"))
        #expect(!AgentIntegration.isHomeSpeakerProgram("tool"))
        #expect(!AgentIntegration.isHomeSpeakerProgram(
            "/Users/me/Library/Application Support/Vitruvian/Tools/dev.vitruvian.homespeaker/tool"))
    }

    @Test(arguments: [nil, HomeSpeakerProfile.Door.extension])
    func theAppLeavesTheExtensionsHookAlone(choice: HomeSpeakerProfile.Door?) throws {
        let (home, vitruvian) = try scratch()
        let ext = try extensionProgram(in: vitruvian, exists: true)
        let before = try writeHook(home: home, program: ext)

        AgentIntegration(home: home, executablePath: appProgram).repairHookIfMoved(choice: choice)

        #expect(try settingsBytes(home: home) == before, "the app wrote nothing: the hook still runs the extension")
    }

    @Test func theAppTakesTheHookBackWhenChosen() throws {
        let (home, vitruvian) = try scratch()
        let ext = try extensionProgram(in: vitruvian, exists: true)
        try writeHook(home: home, program: ext)

        let app = AgentIntegration(home: home, executablePath: appProgram)
        app.repairHookIfMoved(choice: .app)

        #expect(AgentIntegration.installedHookCommand(in: try settings(home: home)) == app.hookCommand)
        #expect(app.hookStatus() == .installed)
    }

    /// The repair asks `extensionProgramExists`, and only it, whether the
    /// extension's program is there: the program here is never on disk, so
    /// the stand-in alone decides.
    @Test(arguments: [true, false])
    func theRepairAsksWhetherTheExtensionsProgramExists(exists: Bool) throws {
        let (home, vitruvian) = try scratch()
        let ext = try extensionProgram(in: vitruvian, exists: false)
        let before = try writeHook(home: home, program: ext)
        var asked: [String] = []

        let app = AgentIntegration(home: home, executablePath: appProgram)
        app.repairHookIfMoved(extensionProgramExists: { asked.append($0); return exists }, choice: nil)

        #expect(asked == [ext], "asked about the hook's own program")
        if exists {
            #expect(try settingsBytes(home: home) == before, "present: the hook still runs the extension")
        } else {
            #expect(AgentIntegration.installedHookCommand(in: try settings(home: home)) == app.hookCommand,
                    "absent: the app takes the hook")
        }
    }

    @Test func theAppRepairsAHookToAMissingProgram() throws {
        let (home, vitruvian) = try scratch()
        let gone = try extensionProgram(in: vitruvian, exists: false)
        try writeHook(home: home, program: gone)

        let app = AgentIntegration(home: home, executablePath: appProgram)
        app.repairHookIfMoved(choice: nil)

        #expect(AgentIntegration.installedHookCommand(in: try settings(home: home)) == app.hookCommand)
    }

    @Test(arguments: [nil, HomeSpeakerProfile.Door.app, HomeSpeakerProfile.Door.extension])
    func theExtensionsProgramNeverRepairs(choice: HomeSpeakerProfile.Door?) throws {
        let (home, vitruvian) = try scratch()
        let ext = try extensionProgram(in: vitruvian, exists: true)
        let before = try writeHook(home: home, program: appProgram)

        AgentIntegration(home: home, executablePath: ext).repairHookIfMoved(choice: choice)

        #expect(try settingsBytes(home: home) == before, "only the app repairs at launch")
    }

    @Test func installingOneReplacesTheOther() throws {
        let (home, vitruvian) = try scratch()
        let ext = try extensionProgram(in: vitruvian, exists: true)

        try AgentIntegration(home: home, executablePath: appProgram).installHook(for: .claudeCode)
        let fromExtension = AgentIntegration(home: home, executablePath: ext)
        try fromExtension.installHook(for: .claudeCode)

        let groups = try #require((try settings(home: home)["hooks"] as? [String: Any])?["Stop"] as? [[String: Any]])
        let commands = groups.flatMap { ($0["hooks"] as? [[String: Any]]) ?? [] }.compactMap { $0["command"] as? String }
        let ours = commands.filter { $0.contains(ClaudeStopHook.argument) }
        #expect(ours == [fromExtension.hookCommand], "exactly one HomeSpeaker hook, the extension's")
        #expect(fromExtension.hookStatus() == .installed)
    }

    @Test func theStatusNamesTheHooksProgram() throws {
        let (home, vitruvian) = try scratch()
        let ext = try extensionProgram(in: vitruvian, exists: true)
        let app = AgentIntegration(home: home, executablePath: appProgram)
        #expect(app.status(of: .claudeCode).hookProgram == nil, "no hook, no program")

        try writeHook(home: home, program: ext)
        #expect(app.status(of: .claudeCode).hookProgram == ext)

        try app.installHook(for: .claudeCode)
        #expect(app.status(of: .claudeCode).hookProgram == appProgram)
    }

    @Test(arguments: [
        "/Volumes/HomeSpeaker/HomeSpeaker.app/Contents/MacOS/HomeSpeaker",
        "/private/var/folders/xx/yy/T/AppTranslocation/1234/d/HomeSpeaker.app/Contents/MacOS/HomeSpeaker",
        "/Users/x/.Trash/HomeSpeaker.app/Contents/MacOS/HomeSpeaker",
    ])
    func anAppOnATemporaryVolumeOrInTrashNeverRepairsHooks(path: String) throws {
        let (home, _) = try scratch()
        let before = try writeHook(home: home, program: appProgram)

        AgentIntegration(home: home, executablePath: path).repairHookIfMoved(choice: .app)

        #expect(try settingsBytes(home: home) == before, "\(path) must not steal the hook")
    }
}
