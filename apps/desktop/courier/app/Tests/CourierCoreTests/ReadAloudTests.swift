// Copyright 2026 VitruvianSoftware
// SPDX-License-Identifier: AGPL-3.0-or-later

import XCTest

@testable import CourierCore

/// Read Aloud (docs/read-aloud.md): what is spoken, where it is spoken (HomeSpeaker's `--say`, or this Mac's voice),
/// what happens when HomeSpeaker fails, and the status Settings ▸ Integrations shows from `--state --json`. HomeSpeaker
/// and the speech synthesizer are fakes: nothing here speaks. All data here is made up.
@MainActor
final class ReadAloudTests: XCTestCase {
    // MARK: Fakes

    private struct FakeLocator: HomeSpeakerLocating {
        var installed: Bool

        func applicationURL() -> URL? {
            installed ? URL(fileURLWithPath: "/Applications/HomeSpeaker.app") : nil
        }

        func binaryURL() -> URL? {
            installed ? URL(fileURLWithPath: "/Applications/HomeSpeaker.app/Contents/MacOS/HomeSpeaker") : nil
        }

        func openApplication(at url: URL) async -> Bool { true }
    }

    private final class FakeRunner: HomeSpeakerCommandRunning, @unchecked Sendable {
        struct Call: Equatable {
            var executable: String
            var arguments: [String]
            var timeout: TimeInterval
        }

        private let lock = NSLock()
        private var recorded: [Call] = []
        var result: HomeSpeakerCommandResult
        var error: Error?

        init(result: HomeSpeakerCommandResult = HomeSpeakerCommandResult(exitCode: 0)) {
            self.result = result
        }

        var calls: [Call] { lock.withLock { recorded } }

        func run(executableURL: URL, arguments: [String], timeout: TimeInterval) async throws
            -> HomeSpeakerCommandResult {
            let (result, error) = lock.withLock { () -> (HomeSpeakerCommandResult, Error?) in
                recorded.append(Call(executable: executableURL.path, arguments: arguments, timeout: timeout))
                return (self.result, self.error)
            }
            if let error { throw error }
            return result
        }
    }

    @MainActor private final class FakeSynthesizer: SpeechSynthesizing {
        private(set) var spoken: [String] = []
        private(set) var stopCount = 0
        private(set) var isSpeaking = false

        func speak(_ text: String) {
            spoken.append(text)
            isSpeaking = true
        }

        func stop() {
            stopCount += 1
            isSpeaking = false
        }
    }

    private func service(installed: Bool, runner: FakeRunner = FakeRunner(),
                         synthesizer: FakeSynthesizer? = nil) -> ReadAloudService {
        let synthesizer = synthesizer ?? FakeSynthesizer()
        return ReadAloudService(locator: FakeLocator(installed: installed), runner: runner, synthesizer: synthesizer)
    }

    // MARK: Messages to build text from

    private let now = Date(timeIntervalSince1970: 1_760_600_600)

    private func message(mine: Bool, content: [String: JSONValue], type: String = "m.room.message") -> TimelineMessage {
        let ts = Int64(now.timeIntervalSince1970 * 1000) - 60_000
        let event = Event(eventID: "$1", roomID: "!a", sender: mine ? Timeline.meUserID : "@ann:example.test",
                          senderName: mine ? "me" : "Ann", mine: mine, type: type, content: .object(content),
                          ts: ts, seq: 1, status: .sent)
        for case let .message(found) in Timeline.build(events: [event], me: Timeline.meUserID, now: now) {
            return found
        }
        fatalError("no message")
    }

    private func text(_ body: String, mine: Bool = false) -> TimelineMessage {
        message(mine: mine, content: ["msgtype": .string("m.text"), "body": .string(body)])
    }

    private func voiceNote(mine: Bool = false) -> TimelineMessage {
        message(mine: mine, content: [
            "msgtype": .string("m.audio"), "body": .string("voice.ogg"), "url": .string("mxc://example.test/v"),
            "org.matrix.msc3245.voice": .object([:]),
        ])
    }

    private func photo(caption: String? = nil) -> TimelineMessage {
        var content: [String: JSONValue] = [
            "msgtype": .string("m.image"), "body": .string(caption ?? "photo.jpg"),
            "url": .string("mxc://example.test/p"),
        ]
        if caption != nil { content["filename"] = .string("photo.jpg") }
        return message(mine: false, content: content)
    }

    // MARK: The spoken text

    func testOtherPeoplesTextIsSaidWithTheirName() {
        XCTAssertEqual(ReadAloudText.forMessage(text("Lunch at noon?")), "Ann says: Lunch at noon?")
    }

    func testMyOwnTextIsYouSaid() {
        XCTAssertEqual(ReadAloudText.forMessage(text("On my way", mine: true)), "You said: On my way")
    }

    func testAVoiceNoteIsItsTranscriptWithTheSamePrefix() {
        XCTAssertEqual(ReadAloudText.forMessage(voiceNote(), transcript: "  See you at six  "),
                       "Ann says: See you at six")
        XCTAssertEqual(ReadAloudText.forMessage(voiceNote(mine: true), transcript: "Running late"),
                       "You said: Running late")
        XCTAssertEqual(ReadAloudText.forTranscript("Hello", mine: false, senderName: "Ann"), "Ann says: Hello")
        XCTAssertEqual(ReadAloudText.forTranscript("Hello", mine: true, senderName: "me"), "You said: Hello")
    }

    func testMessagesWithoutTextHaveNothingToRead() {
        XCTAssertNil(ReadAloudText.forMessage(photo()), "a photo without a caption")
        XCTAssertNil(ReadAloudText.forMessage(voiceNote()), "a voice note nobody has transcribed")
        XCTAssertNil(ReadAloudText.forMessage(voiceNote(), transcript: "   "))
        XCTAssertNil(ReadAloudText.forMessage(text("   \n ")))
        XCTAssertNil(ReadAloudText.forTranscript("  ", mine: false, senderName: "Ann"))
        XCTAssertNil(ReadAloudText.forSummary(" \n "))
    }

    func testACaptionIsReadLikeText() {
        XCTAssertEqual(ReadAloudText.forMessage(photo(caption: "The view")), "Ann says: The view")
    }

    func testASummaryIsSaidAsItIs() {
        XCTAssertEqual(ReadAloudText.forSummary("  Ann and Bob agreed to meet on Friday.\n"),
                       "Ann and Bob agreed to meet on Friday.")
    }

    func testWhatIsSaidStopsAtAThousandCharacters() {
        let long = String(repeating: "a", count: 2_500)
        let said = ReadAloudText.forMessage(text(long))
        XCTAssertEqual(said?.count, 1_000)
        XCTAssertEqual(said?.hasPrefix("Ann says: aaa"), true)
        XCTAssertEqual(ReadAloudText.forSummary(long)?.count, 1_000)
        let exactly = String(repeating: "b", count: 1_000)
        XCTAssertEqual(ReadAloudText.forSummary(exactly), exactly, "1,000 is not cut")
    }

    func testTheMenuOffersReadAloudOnlyWhenThereIsTextAndSaysWhileItRuns() {
        let msg = text("Hello", mine: false)
        let features = ChatFeatures(source: .stored)
        let available = MessageActions.available(for: msg, in: features, network: "whatsapp", now: now)
        func titles(canReadAloud: Bool, isReadingAloud: Bool = false) -> [MessageMenuItem] {
            MessageMenu.sections(for: msg, available: available, features: features, disappearsIn: nil,
                                 time: { _ in "14:02" }, canReadAloud: canReadAloud, isReadingAloud: isReadingAloud)
                .flatMap { $0 }.filter { $0.command == .readAloud }
        }
        XCTAssertTrue(titles(canReadAloud: false).isEmpty)
        let idle = titles(canReadAloud: true)
        XCTAssertEqual(idle.map(\.title), ["Read Aloud"])
        XCTAssertEqual(idle.map(\.isEnabled), [true])
        let busy = titles(canReadAloud: true, isReadingAloud: true)
        XCTAssertEqual(busy.map(\.title), ["Reading Aloud…"])
        XCTAssertEqual(busy.map(\.isEnabled), [false])
    }

    // MARK: Where it is spoken

    func testWithHomeSpeakerInstalledItRunsSayWithTheTextAsOneArgument() async {
        let runner = FakeRunner()
        let synthesizer = FakeSynthesizer()
        let service = service(installed: true, runner: runner, synthesizer: synthesizer)
        let said = "Ann says: it's \"fine\"; $(rm -rf /) && `echo`"
        await service.readAloud(said)
        XCTAssertEqual(runner.calls, [
            FakeRunner.Call(executable: "/Applications/HomeSpeaker.app/Contents/MacOS/HomeSpeaker",
                            arguments: ["--say", said], timeout: 60),
        ])
        XCTAssertEqual(synthesizer.spoken, [], "this Mac's voice is only for when HomeSpeaker is not installed")
        XCTAssertFalse(service.isReadingOnHomeSpeaker, "done")
    }

    func testWithoutHomeSpeakerItSpeaksOnThisMac() async {
        let runner = FakeRunner()
        let synthesizer = FakeSynthesizer()
        let service = service(installed: false, runner: runner, synthesizer: synthesizer)
        await service.readAloud("Ann says: hello")
        XCTAssertEqual(synthesizer.spoken, ["Ann says: hello"])
        XCTAssertEqual(runner.calls, [])
    }

    func testASecondReadAloudOnThisMacStopsTheFirst() async {
        let synthesizer = FakeSynthesizer()
        let service = service(installed: false, synthesizer: synthesizer)
        await service.readAloud("first")
        XCTAssertEqual(synthesizer.stopCount, 0)
        await service.readAloud("second")
        XCTAssertEqual(synthesizer.stopCount, 1)
        XCTAssertEqual(synthesizer.spoken, ["first", "second"])
    }

    func testTextIsTrimmedToAThousandCharactersBeforeItIsSpoken() async {
        let runner = FakeRunner()
        let service = service(installed: true, runner: runner)
        await service.readAloud(String(repeating: "x", count: 1_500))
        XCTAssertEqual(runner.calls.first?.arguments.last?.count, 1_000)
    }

    // MARK: When HomeSpeaker cannot

    func testAFailureIsACalmNoticeWithHomeSpeakersOwnWords() async {
        let runner = FakeRunner(result: HomeSpeakerCommandResult(
            exitCode: 1, stderr: Data("error: No speakers are turned on.\n".utf8)))
        var notices: [String] = []
        let service = service(installed: true, runner: runner)
        await service.readAloud("hello") { notices.append($0) }
        XCTAssertEqual(notices, ["HomeSpeaker couldn’t read it aloud. No speakers are turned on."])
        XCTAssertFalse(service.isReadingOnHomeSpeaker)
    }

    func testATimeoutIsANoticeAndClearsReadingAloud() async {
        // The runner killed HomeSpeaker after the 60 s limit: exit status is whatever the signal left (here 0).
        let runner = FakeRunner(result: HomeSpeakerCommandResult(exitCode: 0, timedOut: true))
        var notices: [String] = []
        let service = service(installed: true, runner: runner)
        await service.readAloud("hello") { notices.append($0) }
        XCTAssertEqual(notices, ["HomeSpeaker couldn’t read it aloud."])
        XCTAssertFalse(service.isReadingOnHomeSpeaker, "“Reading Aloud…” must clear after a timeout")
    }

    func testAFailureWithNothingToSayIsJustTheNotice() async {
        let runner = FakeRunner(result: HomeSpeakerCommandResult(exitCode: 1))
        var notices: [String] = []
        let service = service(installed: true, runner: runner)
        await service.readAloud("hello") { notices.append($0) }
        XCTAssertEqual(notices, ["HomeSpeaker couldn’t read it aloud."])
    }

    func testAJSONErrorIsReadToo() async {
        let runner = FakeRunner(result: HomeSpeakerCommandResult(
            exitCode: 1, stdout: Data(#"{"error":"Quiet hours are on."}"#.utf8)))
        var notices: [String] = []
        let service = service(installed: true, runner: runner)
        await service.readAloud("hello") { notices.append($0) }
        XCTAssertEqual(notices, ["HomeSpeaker couldn’t read it aloud. Quiet hours are on."])
    }

    func testAHomeSpeakerThatCannotBeRunIsTheSameNotice() async {
        struct Boom: LocalizedError { var errorDescription: String? { "Not permitted." } }
        let runner = FakeRunner()
        runner.error = Boom()
        var notices: [String] = []
        let service = service(installed: true, runner: runner)
        await service.readAloud("hello") { notices.append($0) }
        XCTAssertEqual(notices, ["HomeSpeaker couldn’t read it aloud. Not permitted."])
    }

    func testASuccessSaysNothing() async {
        var notices: [String] = []
        let service = service(installed: true)
        await service.readAloud("hello") { notices.append($0) }
        XCTAssertEqual(notices, [])
    }

    // MARK: Settings ▸ Integrations ▸ HomeSpeaker

    private func state(courierEnabled: Bool?) -> Data {
        var settings: [[String: Any]] = [["key": "snooze", "kind": "toggle", "value": true]]
        if let courierEnabled {
            settings.append(["key": "courier_enabled", "kind": "toggle", "label": "Announce Courier messages",
                             "shown": true, "value": courierEnabled])
        }
        return try! JSONSerialization.data(withJSONObject: ["app_installed": true, "settings": settings])
    }

    func testTheStatusSaysWhetherHomeSpeakerReadsCourier() async {
        let reading = FakeRunner(result: HomeSpeakerCommandResult(exitCode: 0, stdout: state(courierEnabled: true)))
        let status = await service(installed: true, runner: reading).fetchIntegrationStatus()
        XCTAssertEqual(status, .installedReading)
        XCTAssertEqual(status.statusLine, "Installed · reads Courier messages aloud")
        XCTAssertEqual(reading.calls.map(\.arguments), [["--state", "--json"]])

        let notReading = FakeRunner(result: HomeSpeakerCommandResult(exitCode: 0, stdout: state(courierEnabled: false)))
        let off = await service(installed: true, runner: notReading).fetchIntegrationStatus()
        XCTAssertEqual(off, .installedNotReading)
        XCTAssertEqual(off.statusLine, "Installed · not reading Courier (turn it on in HomeSpeaker)")
    }

    func testTheStatusWithoutHomeSpeakerIsNotInstalledAndAsksNothing() async {
        let runner = FakeRunner()
        let status = await service(installed: false, runner: runner).fetchIntegrationStatus()
        XCTAssertEqual(status, .notInstalled)
        XCTAssertEqual(status.statusLine, "Not installed · Read Aloud uses this Mac’s voice")
        XCTAssertEqual(runner.calls, [])
    }

    func testAnUnreadableStateIsJustInstalled() async {
        let garbage = FakeRunner(result: HomeSpeakerCommandResult(exitCode: 0, stdout: Data("not json".utf8)))
        let a = await service(installed: true, runner: garbage).fetchIntegrationStatus()
        XCTAssertEqual(a, .installed)
        XCTAssertEqual(a.statusLine, "Installed")

        let missing = FakeRunner(result: HomeSpeakerCommandResult(exitCode: 0, stdout: state(courierEnabled: nil)))
        let b = await service(installed: true, runner: missing).fetchIntegrationStatus()
        XCTAssertEqual(b, .installed)

        let failed = FakeRunner(result: HomeSpeakerCommandResult(exitCode: 1, stdout: state(courierEnabled: true)))
        let c = await service(installed: true, runner: failed).fetchIntegrationStatus()
        XCTAssertEqual(c, .installed)

        let broken = FakeRunner()
        broken.error = URLError(.cannotFindHost)
        let d = await service(installed: true, runner: broken).fetchIntegrationStatus()
        XCTAssertEqual(d, .installed)
    }

    func testHomeSpeakerIsNotToldACodingAgentAskedForTheReadAloud() {
        let inherited = ["CLAUDECODE": "1", "ANTIGRAVITY_AGENT": "1", "OPENCODE": "1", "AI_AGENT": "claude-code",
                         "PATH": "/usr/bin", "HOME": "/Users/someone"]
        XCTAssertEqual(
            FoundationHomeSpeakerCommandRunner.childEnvironment(inherited),
            ["PATH": "/usr/bin", "HOME": "/Users/someone"]
        )
    }

    // MARK: - Finding HomeSpeaker

    private func locator(executables: Set<String>, apps: [String: String]) -> WorkspaceHomeSpeakerLocator {
        WorkspaceHomeSpeakerLocator(
            home: URL(fileURLWithPath: "/Users/someone"),
            isExecutable: { executables.contains($0) },
            appLookup: { id in apps[id].map { URL(fileURLWithPath: $0) } }
        )
    }

    private let extensionTool =
        "/Users/someone/Library/Application Support/com.vitruviansoftware.atrium/Tools/dev.vitruvian.homespeaker/bin/tool"

    func testTheVitruvianExtensionsHomeSpeakerIsFoundAndVitruvianIsWhatOpens() {
        let found = locator(executables: [extensionTool],
                            apps: ["com.vitruviansoftware.atrium": "/Applications/Vitruvian Atrium.app"])
        XCTAssertEqual(found.binaryURL()?.path, extensionTool)
        XCTAssertEqual(found.applicationURL()?.path, "/Applications/Vitruvian Atrium.app")
    }

    func testTheInstalledAppIsUsedWhenThereIsNoExtension() {
        let binary = "/Applications/HomeSpeaker.app/Contents/MacOS/HomeSpeaker"
        let found = locator(executables: [binary], apps: ["com.vitruviansoftware.homespeaker": "/Applications/HomeSpeaker.app"])
        XCTAssertEqual(found.binaryURL()?.path, binary)
        XCTAssertEqual(found.applicationURL()?.path, "/Applications/HomeSpeaker.app")
        let inHome = "/Users/someone/Applications/HomeSpeaker.app"
        XCTAssertEqual(
            locator(executables: [inHome + "/Contents/MacOS/HomeSpeaker"],
                    apps: ["com.vitruviansoftware.homespeaker": inHome]).binaryURL()?.path,
            inHome + "/Contents/MacOS/HomeSpeaker")
    }

    func testADevelopmentBuildInACheckoutIsNeverUsed() {
        let dev = "/Users/someone/src/repo/apps/desktop/home-speaker/dist/HomeSpeaker.app"
        let found = locator(executables: [dev + "/Contents/MacOS/HomeSpeaker"],
                            apps: ["com.vitruviansoftware.homespeaker": dev])
        XCTAssertNil(found.binaryURL())
        XCTAssertNil(found.applicationURL())
    }
}
