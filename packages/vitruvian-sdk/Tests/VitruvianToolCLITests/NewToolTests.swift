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

final class NewToolTests: XCTestCase {
    private var scratch = Scratch()

    override func setUp() {
        scratch = Scratch()
    }

    override func tearDown() {
        scratch.remove()
    }

    private func tool(_ name: String = "new", id: String = "com.example.fresh") -> NewTool {
        NewTool(folder: scratch.url.appendingPathComponent(name), id: id, name: "Fresh", publisher: "Example")
    }

    private func manifest(at url: URL) throws -> ToolManifestFile {
        try ToolManifestFile.read(try Data(contentsOf: url)).get()
    }

    func testThePythonTemplateIsTheSampleAndAFolderTheAppTakes() throws {
        let new = tool()
        XCTAssertEqual(try NewToolWriter.write(new).get(), ["vitruvian-tool.json", "bin/tool.py"])
        let program = new.folder.appendingPathComponent("bin/tool.py")
        XCTAssertEqual(try Data(contentsOf: program), PackageFiles.data("samples/hello-python/bin/tool.py"),
                       "the program is the sample's, byte for byte")
        XCTAssertTrue(FileManager.default.isExecutableFile(atPath: program.path))
        let written = try manifest(at: new.folder.appendingPathComponent("vitruvian-tool.json"))
        XCTAssertEqual([written.id, written.name.english, written.publisher], ["com.example.fresh", "Fresh", "Example"])
        let sample = try manifest(at: PackageFiles.url("samples/hello-python/vitruvian-tool.json"))
        XCTAssertEqual(written.contributes, sample.contributes, "and everything else is the sample's")
        XCTAssertEqual(written.runtime, sample.runtime)
        XCTAssertEqual(FolderCheck.check(new.folder).verdict, "ok")
    }

    func testAnyNameIsWrittenAsJSONWritesIt() throws {
        var new = tool()
        new.name = #"Dé"ploy \ it/now"#
        new.publisher = "A \"B\" C"
        _ = try NewToolWriter.write(new).get()
        let written = try manifest(at: new.folder.appendingPathComponent("vitruvian-tool.json"))
        XCTAssertEqual(written.name.english, #"Dé"ploy \ it/now"#)
        XCTAssertEqual(written.publisher, "A \"B\" C")
    }

    func testNothingThatIsThereIsWrittenOver() throws {
        let used = tool("used")
        Scratch.write("mine", to: used.folder.appendingPathComponent("notes.txt"))
        XCTAssertEqual(NewToolWriter.write(used), .failure(.folderInUse))
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: used.folder.path), ["notes.txt"])
        XCTAssertEqual(try String(contentsOf: used.folder.appendingPathComponent("notes.txt"), encoding: .utf8), "mine")

        let file = tool("file")
        Scratch.write("mine", to: file.folder)
        XCTAssertEqual(NewToolWriter.write(file), .failure(.folderInUse))

        let empty = tool("empty")
        try FileManager.default.createDirectory(at: empty.folder, withIntermediateDirectories: true)
        XCTAssertNoThrow(try NewToolWriter.write(empty).get(), "an empty folder is as good as none")
    }

    func testANameThatIsOneOfTheSamplesOwnValuesIsKept() throws {
        var new = tool()
        new.name = "VitruvianSoftware"
        new.publisher = "Hello, in Python"
        _ = try NewToolWriter.write(new).get()
        let written = try manifest(at: new.folder.appendingPathComponent("vitruvian-tool.json"))
        XCTAssertEqual([written.name.english, written.publisher], ["VitruvianSoftware", "Hello, in Python"])
    }

    func testALinkIsNeverWrittenThrough() throws {
        let elsewhere = scratch.folder("elsewhere")
        var linked = tool("link")
        try FileManager.default.createSymbolicLink(at: linked.folder, withDestinationURL: elsewhere)
        XCTAssertEqual(NewToolWriter.write(linked), .failure(.folderIsALink), "a link to an empty folder")
        linked.folder = URL(fileURLWithPath: linked.folder.path + "/", isDirectory: true)
        XCTAssertEqual(NewToolWriter.write(linked), .failure(.folderIsALink), "and with a slash at its end")
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: elsewhere.path), [],
                       "nothing was written where the link leads")

        let dangling = tool("dangling")
        let nowhere = scratch.url.appendingPathComponent("not-there-yet")
        try FileManager.default.createSymbolicLink(atPath: dangling.folder.path, withDestinationPath: nowhere.path)
        XCTAssertEqual(NewToolWriter.write(dangling), .failure(.folderIsALink), "a link to nothing")
        XCTAssertFalse(FileManager.default.fileExists(atPath: nowhere.path), "and nothing was made there")

        var said: [String] = []
        XCTAssertEqual(VitruvianToolCommand.main(["init", dangling.folder.path, "--id", "a.b", "--name", "N",
                                                  "--publisher", "P"], say: { said.append($0) }), 1)
        XCTAssertTrue(said.first?.contains("is a symbolic link") == true, "\(said)")
        XCTAssertEqual(said.last, "Nothing was written.")
    }

    func testAPathWithSpacesQuotationMarksAndASlashAtItsEnd() throws {
        let name = #"my "new" tool's folder"#
        let folder = scratch.url.appendingPathComponent(name).path
        var said: [String] = []
        XCTAssertEqual(VitruvianToolCommand.main(["init", folder + "/", "--id", "com.example.spaced", "--name",
                                                  "Spaced", "--publisher", "Example"], say: { said.append($0) }), 0)
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: scratch.url.path), [name],
                       "one folder, with the name as it was typed, and nothing beside it")
        XCTAssertEqual(FolderCheck.check(URL(fileURLWithPath: folder)).verdict, "ok")
        let typed = "'" + folder.replacingOccurrences(of: "'", with: #"'\''"#) + "'"
        XCTAssertTrue(said.last?.contains("vitruvian-tool run \(typed)") == true,
                      "what to type next is written so that a shell reads it as one path: \(said)")

        var swift = tool("swift tool")
        swift.template = .swift
        let sdk = scratch.folder(#"my "sdk""#)
        Scratch.write("// swift-tools-version: 6.0\n", to: sdk.appendingPathComponent("Package.swift"))
        swift.sdk = sdk
        _ = try NewToolWriter.write(swift).get()
        let package = try String(contentsOf: swift.folder.appendingPathComponent("Package.swift"), encoding: .utf8)
        XCTAssertTrue(package.contains(#".package(path: "\#(scratch.url.standardizedFileURL.path)/my \"sdk\"")"#),
                      package)
    }

    func testAnIdTheAppWouldRefuseIsSaidInPlainWords() {
        let folder = scratch.url.appendingPathComponent("refused").path
        var said: [String] = []
        XCTAssertEqual(VitruvianToolCommand.main(["init", folder, "--id", "fresh", "--name", "Fresh",
                                                  "--publisher", "Example"], say: { said.append($0) }), 1)
        XCTAssertEqual(said.first, "NOT OK   that would not make a manifest the app takes: the id `fresh` has no "
            + "dot. An id with no dot is one of the app's own tools: use a name like com.you.fresh")
        XCTAssertEqual(said.last, "Nothing was written.")
        XCTAssertFalse(FileManager.default.fileExists(atPath: folder))
    }

    func testAManifestTheAppWouldRefuseIsNeverWritten() {
        let noDot = tool("a", id: "fresh")
        XCTAssertEqual(NewToolWriter.write(noDot), .failure(.manifest(.idWithoutDot("fresh"))))
        var blank = tool("b")
        blank.publisher = "  "
        XCTAssertEqual(NewToolWriter.write(blank), .failure(.manifest(.blankText(field: "publisher"))))
        XCTAssertFalse(FileManager.default.fileExists(atPath: noDot.folder.path)
            || FileManager.default.fileExists(atPath: blank.folder.path), "not even the folder is made")
    }

    func testTheSwiftTemplateUsesThePublishedSDKByDefault() throws {
        var new = tool("published")
        new.template = .swift
        XCTAssertEqual(try NewToolWriter.write(new).get(),
                       ["Package.swift", "Sources/Tool/main.swift", "tool/vitruvian-tool.json", "build.sh", ".gitignore"])
        let package = try String(contentsOf: new.folder.appendingPathComponent("Package.swift"), encoding: .utf8)
        let version = VitruvianToolCommand.version
        XCTAssertTrue(package.contains(#".package(url: "https://github.com/VitruvianSoftware/vitruvian-sdk", from: "\#(version)")"#),
                      package)
        XCTAssertTrue(package.contains(#".product(name: "VitruvianToolKit", package: "vitruvian-sdk")"#), package)
        XCTAssertFalse(package.contains(".package(path:"), package)
        XCTAssertEqual(NewToolWriter.publishedSDK, "https://github.com/VitruvianSoftware/vitruvian-sdk")

        var said: [String] = []
        let folder = scratch.url.appendingPathComponent("said-swift").path
        XCTAssertEqual(VitruvianToolCommand.main(["init", folder, "--id", "com.example.said", "--name", "Said",
                                                  "--publisher", "Example", "--template", "swift"],
                                                 say: { said.append($0) }), 0)
        XCTAssertTrue(said.last?.hasPrefix("The first build fetches the SDK, version \(version), from GitHub.\nNext:\n")
                      == true, "\(said)")
    }

    func testTheSwiftTemplateIsAPackageBesideTheToolsFolder() throws {
        var new = tool("swift")
        new.template = .swift
        new.sdk = scratch.url.appendingPathComponent("no-such-sdk")
        XCTAssertEqual(NewToolWriter.write(new), .failure(.noSDK))
        XCTAssertFalse(FileManager.default.fileExists(atPath: new.folder.path))

        let sdk = scratch.folder("my-sdk")
        Scratch.write("// swift-tools-version: 6.0\n", to: sdk.appendingPathComponent("Package.swift"))
        new.sdk = sdk
        XCTAssertEqual(try NewToolWriter.write(new).get(),
                       ["Package.swift", "Sources/Tool/main.swift", "tool/vitruvian-tool.json", "build.sh", ".gitignore"])
        XCTAssertEqual(try Data(contentsOf: new.folder.appendingPathComponent("Sources/Tool/main.swift")),
                       PackageFiles.data("samples/hello-swift/main.swift"))
        let package = try String(contentsOf: new.folder.appendingPathComponent("Package.swift"), encoding: .utf8)
        XCTAssertTrue(package.contains(#".package(path: "\#(sdk.standardizedFileURL.path)")"#), package)
        XCTAssertTrue(package.contains(#".product(name: "VitruvianToolKit", package: "my-sdk")"#), package)
        XCTAssertTrue(FileManager.default.isExecutableFile(atPath: new.folder.appendingPathComponent("build.sh").path))
        XCTAssertEqual(try manifest(at: new.folder.appendingPathComponent("tool/vitruvian-tool.json")).runtime.exec,
                       "bin/tool")
        XCTAssertEqual(FolderCheck.check(new.folder.appendingPathComponent("tool")).verdict, "programMissing",
                       "until build.sh has put the program there")
    }

    func testTheTypeScriptTemplateIsTheSampleWithTheKitAtThisVersion() throws {
        var new = tool("typescript")
        new.template = .typescript
        XCTAssertEqual(try NewToolWriter.write(new).get(),
                       ["vitruvian-tool.json", "bin/tool", "bin/tool.mjs", "package.json"])
        for path in ["bin/tool", "bin/tool.mjs"] {
            XCTAssertEqual(try Data(contentsOf: new.folder.appendingPathComponent(path)),
                           PackageFiles.data("samples/hello-typescript/\(path)"), "\(path) is the sample's")
        }
        XCTAssertTrue(FileManager.default.isExecutableFile(atPath: new.folder.appendingPathComponent("bin/tool").path))
        let package = try JSONSerialization.jsonObject(
            with: Data(contentsOf: new.folder.appendingPathComponent("package.json"))) as? [String: Any]
        XCTAssertEqual((package?["dependencies"] as? [String: String])?["@vitruviansoftware/tool-kit"],
                       VitruvianToolCommand.version, "the kit this command was built with, from npm")
        let written = try manifest(at: new.folder.appendingPathComponent("vitruvian-tool.json"))
        XCTAssertEqual([written.id, written.name.english, written.runtime.exec], ["com.example.fresh", "Fresh", "bin/tool"])
        XCTAssertEqual(FolderCheck.check(new.folder).verdict, "ok")
    }

    func testThePythonKitTemplateIsTheSampleWithTheKitAtThisVersion() throws {
        var new = tool("python-kit")
        new.template = .pythonKit
        XCTAssertEqual(try NewToolWriter.write(new).get(), ["vitruvian-tool.json", "bin/tool.py", "requirements.txt"])
        XCTAssertEqual(try Data(contentsOf: new.folder.appendingPathComponent("bin/tool.py")),
                       PackageFiles.data("samples/hello-python-kit/bin/tool.py"))
        XCTAssertEqual(try String(contentsOf: new.folder.appendingPathComponent("requirements.txt"), encoding: .utf8),
                       "vitruvian-tool-kit==\(VitruvianToolCommand.version)\n", "the kit this command was built with, from PyPI")
        XCTAssertEqual(try manifest(at: new.folder.appendingPathComponent("vitruvian-tool.json")).name.english, "Fresh")
        XCTAssertEqual(FolderCheck.check(new.folder).verdict, "ok")
    }

    func testTheKitTemplatesTakeTheKitFromACheckout() throws {
        let sdk = scratch.folder("checkout")
        var typescript = tool("ts-sdk")
        typescript.template = .typescript
        typescript.sdk = sdk
        var python = tool("py-sdk")
        python.template = .pythonKit
        python.sdk = sdk
        XCTAssertEqual(NewToolWriter.write(typescript), .failure(.noSDK), "a checkout with no kit in it")
        XCTAssertEqual(NewToolWriter.write(python), .failure(.noSDK))
        XCTAssertFalse(FileManager.default.fileExists(atPath: typescript.folder.path))

        Scratch.write("{}\n", to: sdk.appendingPathComponent("kits/typescript/package.json"))
        Scratch.write("# kit\n", to: sdk.appendingPathComponent("kits/python/vitruvian_tool_kit/__init__.py"))
        Scratch.write("# made\n", to: sdk.appendingPathComponent("kits/python/vitruvian_tool_kit/generated/messages.py"))
        _ = try NewToolWriter.write(typescript).get()
        let package = try String(contentsOf: typescript.folder.appendingPathComponent("package.json"), encoding: .utf8)
        XCTAssertTrue(package.contains(#""@vitruviansoftware/tool-kit": "file:\#(sdk.standardizedFileURL.path)/kits/typescript""#),
                      package)
        XCTAssertEqual(try NewToolWriter.write(python).get(),
                       ["vitruvian-tool.json", "bin/tool.py", "requirements.txt", "lib/vitruvian_tool_kit/__init__.py",
                        "lib/vitruvian_tool_kit/generated/messages.py"], "the kit, where pip would have put it")
        XCTAssertEqual(try String(contentsOf: python.folder.appendingPathComponent("lib/vitruvian_tool_kit/__init__.py"),
                                  encoding: .utf8), "# kit\n")
    }

    func testTheGoAndRustTemplatesAreProgramsBesideTheToolsFolder() throws {
        let sdk = scratch.folder("my-sdk")
        for (template, program, built) in [(ToolTemplate.go, "main.go", "go.mod"),
                                           (ToolTemplate.rust, "src/main.rs", "Cargo.toml")] {
            var new = tool("published-\(template.rawValue)")
            new.template = template
            XCTAssertEqual(try NewToolWriter.write(new).get(),
                           [built, program, "tool/vitruvian-tool.json", "build.sh", ".gitignore"])
            XCTAssertEqual(try Data(contentsOf: new.folder.appendingPathComponent(program)),
                           PackageFiles.data("samples/hello-\(template.rawValue)/\(template == .go ? "main.go" : "src/main.rs")"))
            let text = try String(contentsOf: new.folder.appendingPathComponent(built), encoding: .utf8)
            XCTAssertTrue(text.contains(template == .go
                                        ? "require github.com/VitruvianSoftware/vitruvian-sdk/go v\(NewToolWriter.sdkVersion)\n"
                                        : "vitruvian-tool-kit = \"\(NewToolWriter.sdkVersion)\"\n"),
                          "without --sdk, the published kit of this command's version: \(text)")
            XCTAssertFalse(text.contains("replace") || text.contains("path ="), text)
            XCTAssertTrue(FileManager.default.isExecutableFile(atPath: new.folder.appendingPathComponent("build.sh").path))
            XCTAssertEqual(FolderCheck.check(new.folder.appendingPathComponent("tool")).verdict, "programMissing")

            var local = tool("local-\(template.rawValue)")
            local.template = template
            local.sdk = sdk
            XCTAssertEqual(NewToolWriter.write(local), .failure(.noSDK), "a folder with no kit in it")
            XCTAssertFalse(FileManager.default.fileExists(atPath: local.folder.path))
        }
        Scratch.write("module github.com/VitruvianSoftware/vitruvian-sdk/go\n", to: sdk.appendingPathComponent("go/go.mod"))
        Scratch.write("[package]\n", to: sdk.appendingPathComponent("kits/rust/Cargo.toml"))
        for template in [ToolTemplate.go, .rust] {
            var local = tool("local-\(template.rawValue)")
            local.template = template
            local.sdk = sdk
            _ = try NewToolWriter.write(local).get()
            let built = local.folder.appendingPathComponent(template == .go ? "go.mod" : "Cargo.toml")
            let text = try String(contentsOf: built, encoding: .utf8)
            XCTAssertTrue(text.contains(template == .go
                                        ? "=> \"\(sdk.standardizedFileURL.path)/go\"\n"
                                        : "{ path = \"\(sdk.standardizedFileURL.path)/kits/rust\" }"),
                          "with --sdk, the kit in that checkout: \(text)")
        }
    }

    func testTheCommandSaysWhatItWroteAndWhatToDoNext() {
        let folder = scratch.url.appendingPathComponent("said").path
        let arguments = ["init", folder, "--id", "com.example.said", "--name", "Said", "--publisher", "Example"]
        var said: [String] = []
        XCTAssertEqual(VitruvianToolCommand.main(arguments, say: { said.append($0) }), 0)
        XCTAssertEqual(Array(said.prefix(2)), ["wrote    vitruvian-tool.json", "wrote    bin/tool.py"])
        XCTAssertTrue(said.last?.contains("vitruvian-tool run \(folder)") == true)
        said = []
        XCTAssertEqual(VitruvianToolCommand.main(arguments, say: { said.append($0) }), 1, "a second time")
        XCTAssertTrue(said.first?.hasPrefix("NOT OK   \(folder) is already there") == true)
        XCTAssertEqual(said.last, "Nothing was written.")
        for bad in [["init"], ["init", folder], ["init", folder, "--id", "a.b", "--name", "N"],
                    ["init", folder, "--id", "a.b", "--name", "N", "--publisher", "P", "--template", "cobol"],
                    ["init", folder, "other", "--id", "a.b", "--name", "N", "--publisher", "P"]] {
            XCTAssertEqual(VitruvianToolCommand.main(bad, say: { _ in }), 2, "\(bad)")
        }
    }
}
