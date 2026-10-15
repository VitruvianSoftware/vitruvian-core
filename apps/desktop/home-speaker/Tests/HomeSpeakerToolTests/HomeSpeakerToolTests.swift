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

import HomeSpeakerCore
import HomeSpeakerToolCore
import VitruvianToolKit
import VitruvianToolProtocol

final class HomeSpeakerToolTests: XCTestCase {
    /// A history file that is never there: the tests never read this
    /// Mac's `~/.gemini/speaker_history.json`.
    static let noHistory = URL(fileURLWithPath: "/nonexistent/homespeaker-tool-tests/speaker_history.json")

    final class Link: ToolLink {
        var rendered: [(panel: String, tree: UITree)] = []
        var messages: [String] = []
        var logged: [String] = []
        var clipboard: String?
        /// What the app named at hello; none, as before 3.48.
        var features: Set<ProtocolFeature> = []
        func render(panel: String, _ tree: UITree) { rendered.append((panel, tree)) }
        func showMessage(_ message: String, icon: String) { messages.append(message) }
        func log(_ message: String) { logged.append(message) }
        func clipboardText() -> String? { clipboard }
        func supports(_ feature: ProtocolFeature) -> Bool { features.contains(feature) }
    }

    final class Store: ConfigStore {
        var config: SpeakerConfig?
        var saves = 0
        var refuses = false
        /// Set: the file is there and does not read, for this reason.
        var corrupt: String?
        func read() -> ConfigFileRead {
            if let corrupt { return .unreadable(.unreadable(path: "/fake/.gemini/speaker_broadcast.json", reason: corrupt)) }
            return config.map { .loaded($0) } ?? .missing
        }
        func save(_ config: SpeakerConfig) throws {
            if refuses || corrupt != nil { throw CocoaError(.fileWriteNoPermission) }
            self.config = config
            saves += 1
        }
    }

    /// A sign-in that says what it is told to.
    final class Account: GoogleAccount {
        var isSignedIn = false
        var email: String?
        var hasOAuthClient = true
        var hasAntigravityTokens = false
        /// Whether the Antigravity file holds a login.
        var importFinds = true
        var imports = 0
        func importFromAntigravity() throws -> Bool {
            imports += 1
            if importFinds { isSignedIn = true }
            return importFinds
        }
        var customOAuthClientId: String?
        var customOAuthClientSecret: String?
        var hasCustomOAuthClientSecret: Bool { customOAuthClientSecret != nil }
        var hasBundledOAuthClient = false
        /// Each save, as it was asked: one call is one write.
        var oauthSaves: [(id: String, secret: String?)] = []
        var oauthClears = 0
        func saveOAuthClient(id: String, secret: String?) throws {
            oauthSaves.append((id, secret))
            let sameClient = id == customOAuthClientId
            customOAuthClientId = id
            if let secret { customOAuthClientSecret = secret } else if !sameClient { customOAuthClientSecret = nil }
        }
        func clearOAuthClient() throws {
            oauthClears += 1
            customOAuthClientId = nil
            customOAuthClientSecret = nil
        }
    }

    /// A HomeSpeaker that records what it was asked and answers when told.
    final class Driver: SpeakerDriver {
        var isInstalled = true
        var program: URL? { isInstalled ? URL(fileURLWithPath: "/Applications/HomeSpeaker.app/Contents/MacOS/HomeSpeaker") : nil }
        var jobs: [Job] = []
        var pending: [(Job, @Sendable (JobResult) -> Void)] = []
        func run(_ job: Job, then: @escaping @Sendable (JobResult) -> Void) {
            jobs.append(job)
            pending.append((job, then))
        }
        func answer(_ result: JobResult) {
            let (_, then) = pending.removeFirst()
            then(result)
        }
        /// Answers the job asked for, wherever it is in the queue.
        func answer(_ job: Job, _ result: JobResult) {
            guard let index = pending.firstIndex(where: { $0.0 == job }) else { return XCTFail("\(job) was not asked") }
            let (_, then) = pending.remove(at: index)
            then(result)
        }
    }

    private var link: Link!
    private var store: Store!
    private var driver: Driver!
    private var now = Date(timeIntervalSince1970: 1_700_000_000)

    override func setUp() {
        link = Link()
        store = Store()
        driver = Driver()
        store.config = SpeakerConfig(enabled: true, defaultTarget: "kitchen", structureId: "s1",
                                     targets: ["kitchen": SpeakerDevice(id: "d1", type: "SpeakerDevice", name: "Kitchen"),
                                               "office": SpeakerDevice(id: "d2", type: "SpeakerDevice", name: "Office")])
    }

    private func tool() -> HomeSpeakerTool {
        HomeSpeakerTool(parts: .init(link: link, store: store, driver: driver, later: { $0() }, now: { [now] in now },
                                     historyURL: Self.noHistory))
    }

    func testStartReadsTheVolumeOnceAndSaysWhenHomeSpeakerIsMissing() {
        let tool = tool()
        tool.start()
        XCTAssertEqual(driver.jobs, [.volume])
        XCTAssertEqual(tool.busy, .volume)
        driver.answer(.volume(Volume(speaker: "Kitchen", percent: 30, muted: false, online: true)))
        XCTAssertNil(tool.busy)
        XCTAssertEqual(tool.volume?.percent, 30)
        driver.isInstalled = false
        let missing = self.tool()
        missing.start()
        XCTAssertEqual(driver.jobs.count, 1, "nothing asked of a HomeSpeaker that is not there")
        XCTAssertTrue(link.logged.contains { $0.contains("not installed") })
        XCTAssertThrowsError(try missing.run(command: "mute"))
    }

    func testSayingGoesThroughHomeSpeakerAndIsToldWhereItWasHeard() throws {
        let tool = tool()
        tool.start()
        driver.answer(.volume(Volume(speaker: "Kitchen", percent: 30)))
        _ = tool.islandPage()
        guard case .page(let page) = tool.islandEvent(PanelEvent(block: "say", kind: .submit, value: .string("  dinner  "))) else {
            return XCTFail("no page")
        }
        XCTAssertEqual(driver.jobs.last, .say("dinner"))
        XCTAssertEqual(tool.busy, .say("dinner"))
        XCTAssertTrue(page.blocks.contains { if case .text(let t) = $0.content { return t.text.text(for: "en") == "Speaking…" } else { return false } })
        driver.answer(.spoke("sent to Kitchen"))
        XCTAssertNil(tool.busy)
        XCTAssertEqual(tool.notice, "Sent to Kitchen")
        XCTAssertEqual(link.messages.last, "Sent to Kitchen")
        XCTAssertEqual(link.rendered.last?.panel, "speaker", "the open page is drawn again")
        // Quiet hours hold an automated announcement; what is typed is deliberate, and HomeSpeaker says what it did.
        _ = tool.islandEvent(PanelEvent(block: "say", kind: .submit, value: .string("again")))
        driver.answer(.notSpoken("Quiet hours active until 07:00. Nothing spoken."))
        XCTAssertEqual(link.messages.last, "Quiet hours active until 07:00. Nothing spoken.")
        XCTAssertEqual(tool.islandEvent(PanelEvent(block: "say", kind: .submit, value: .string("   "))), .keep, "nothing to say")
    }

    func testTheClipboardCommandSpeaksTheClipboardOrRefuses() throws {
        let tool = tool()
        tool.start()
        driver.answer(.volume(Volume(speaker: "Kitchen")))
        XCTAssertThrowsError(try tool.run(command: "sayClipboard")) { XCTAssertTrue("\($0)".contains("no text")) }
        link.clipboard = "read me"
        try tool.run(command: "sayClipboard")
        XCTAssertEqual(driver.jobs.last, .say("read me"))
        driver.answer(.spoke("sent to Kitchen"))
        store.config?.enabled = false
        XCTAssertThrowsError(try tool.run(command: "sayClipboard")) { XCTAssertTrue("\($0)".contains("switched off")) }
    }

    func testSwitchesAndVolumeChangeTheFileAndHomeSpeaker() throws {
        let tool = tool()
        tool.start()
        driver.answer(.volume(Volume(speaker: "Kitchen", percent: 30, muted: false)))
        try tool.run(command: "toggleBroadcasting")
        XCTAssertEqual(store.config?.enabled, false)
        XCTAssertEqual(link.messages.last, "Broadcasting off")
        try tool.run(command: "toggleQuietHours")
        XCTAssertEqual(store.config?.quietHoursEnabled, true)
        _ = tool.islandPage()
        _ = tool.islandEvent(PanelEvent(block: "broadcasting", kind: .toggle, value: .bool(true)))
        XCTAssertEqual(store.config?.enabled, true)
        _ = tool.islandEvent(PanelEvent(block: "volume", kind: .submit, value: .string("55")))
        XCTAssertEqual(driver.jobs.last, .setVolume(55))
        driver.answer(.volume(Volume(speaker: "Kitchen", percent: 55, muted: false)))
        XCTAssertEqual(tool.volume?.percent, 55)
        guard case .page(let bad) = tool.islandEvent(PanelEvent(block: "volume", kind: .submit, value: .string("loud"))) else { return XCTFail() }
        XCTAssertEqual(driver.jobs.count, 2, "a volume that is no number asks nothing")
        XCTAssertTrue(bad.blocks.contains { if case .text(let t) = $0.content { return t.text.text(for: "en").contains("0 to 100") } else { return false } })
        try tool.run(command: "mute")
        XCTAssertEqual(driver.jobs.last, .mute)
        XCTAssertThrowsError(try tool.run(command: "unmute")) { XCTAssertTrue("\($0)".contains("busy"), "one job at a time: \($0)") }
        driver.answer(.volume(Volume(speaker: "Kitchen", percent: 55, muted: true)))
        try tool.run(command: "unmute")
        XCTAssertEqual(driver.jobs.last, .unmute)
    }

    func testPickingASpeakerSavesItAndReadsItsVolume() {
        let tool = tool()
        tool.start()
        driver.answer(.volume(Volume(speaker: "Kitchen", percent: 30)))
        _ = tool.islandPage()
        _ = tool.islandEvent(PanelEvent(block: "speakers", kind: .tap, value: .string("office")))
        XCTAssertEqual(store.config?.defaultTarget, "office")
        XCTAssertEqual(driver.jobs.last, .volume)
        XCTAssertNil(tool.volume, "the old speaker's reading is gone until the new one answers")
        XCTAssertEqual(tool.islandEvent(PanelEvent(block: "speakers", kind: .tap, value: .string("nowhere"))), .keep)
    }

    func testTheSettingsPanelWritesTheFileAndKeepsItOnARefusal() {
        let tool = tool()
        tool.start()
        driver.answer(.volume(Volume(speaker: "Kitchen")))
        _ = tool.settingsPage()
        _ = tool.settingsEvent(PanelEvent(block: "speechLength", kind: .tap, value: .string("full")))
        _ = tool.settingsEvent(PanelEvent(block: "speakLocal", kind: .toggle, value: .bool(true)))
        _ = tool.settingsEvent(PanelEvent(block: "quietStart", kind: .submit, value: .string("23:15")))
        XCTAssertEqual(tool.settingsEvent(PanelEvent(block: "quietEnd", kind: .submit, value: .string("soon"))), .keep)
        XCTAssertEqual(store.config?.effectiveSpeechLength, .full)
        XCTAssertEqual(store.config?.effectiveSpeakLocal, true)
        XCTAssertEqual(store.config?.quietHoursStart, "23:15")
        XCTAssertEqual(store.saves, 3)
        store.refuses = true
        _ = tool.settingsEvent(PanelEvent(block: "pauseMedia", kind: .toggle, value: .bool(true)))
        XCTAssertEqual(store.config?.effectivePauseMedia, false)
        XCTAssertEqual(tool.config.effectivePauseMedia, false, "read back from the file")
        XCTAssertTrue(link.logged.contains { $0.contains("could not be saved") })
    }

    func testTheFileIsReadAgainBeforeEachPageSoThePhoneAndTheAppAreSeen() {
        let tool = tool()
        tool.start()
        driver.answer(.volume(Volume(speaker: "Kitchen")))
        store.config?.enabled = false
        let page = tool.islandPage()
        guard case .toggle(let broadcasting)? = page.blocks.first(where: { $0.id == "broadcasting" })?.content else { return XCTFail("no toggle") }
        XCTAssertFalse(broadcasting.value)
        tool.panelClosed("speaker")
        link.rendered.removeAll()
        tool.finished(.volume, .unavailable("gone"))
        XCTAssertTrue(link.rendered.isEmpty, "nothing is drawn for a closed page")
        XCTAssertEqual(tool.notice, "Gone")
    }
}
