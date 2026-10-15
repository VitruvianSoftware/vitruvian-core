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

final class PagesTests: XCTestCase {
    private func ids(_ tree: UITree) -> [String] { tree.blocks.compactMap(\.id) }

    private func texts(_ tree: UITree) -> [String] {
        tree.blocks.compactMap { block in
            switch block.content {
            case .text(let text): return text.text.text(for: "en")
            case .heading(let heading): return heading.text.text(for: "en")
            case .row(let row): return row.title.text(for: "en") + " · " + (row.subtitle?.text(for: "en") ?? "")
            case .link(let link): return link.title.text(for: "en")
            default: return nil
            }
        }
    }

    private var configured: SpeakerConfig {
        SpeakerConfig(enabled: true, defaultTarget: "kitchen", structureId: "s1",
                      targets: ["kitchen": SpeakerDevice(id: "d1", type: "SpeakerDevice", name: "Kitchen", room: "Kitchen"),
                                "all": SpeakerDevice(id: "structure@s1", type: "Structure", name: "Whole Home")],
                      quietHoursEnabled: true, quietHoursStart: "22:00", quietHoursEnd: "07:00")
    }

    func testWithoutHomeSpeakerTheIslandPageSaysSoAndLinksToIt() {
        var status = Pages.Status()
        status.installed = false
        let page = Pages.island(status)
        XCTAssertEqual(ids(page), [])
        XCTAssertTrue(texts(page).contains("Get HomeSpeaker"))
        XCTAssertTrue(texts(page).contains { $0.contains("not installed") })
    }

    func testTheIslandPageHasTheFieldTheSwitchesAndTheSpeaker() {
        var status = Pages.Status()
        status.config = configured
        status.volume = Volume(speaker: "Kitchen", percent: 40, muted: false, online: true)
        status.quietNow = true
        let page = Pages.island(status)
        XCTAssertEqual(ids(page), ["say", "broadcasting", "quiet", "mute", "volume", "refresh", "speakers"])
        XCTAssertTrue(texts(page).contains("Kitchen · Volume 40 %"))
        XCTAssertTrue(texts(page).contains("Quiet hours until 07:00: what you type still plays"))
        guard case .list(let speakers)? = page.blocks.first(where: { $0.id == "speakers" })?.content else { return XCTFail("no list") }
        XCTAssertEqual(speakers.rows.map(\.id), ["kitchen", "all"], "the person's speaker first, the whole home after")
        XCTAssertEqual(speakers.rows.first?.trailing?.text(for: "en"), "✓")
        status.volume?.muted = true
        XCTAssertTrue(ids(Pages.island(status)).contains("unmute"))
        XCTAssertTrue(texts(Pages.island(status)).contains("Kitchen · Muted"))
        status.volume = Volume(speaker: "Kitchen", online: false)
        XCTAssertTrue(texts(Pages.island(status)).contains("Kitchen · Offline"))
        status.busy = .say("x")
        status.notice = "Sent to Kitchen"
        XCTAssertTrue(texts(Pages.island(status)).contains("Speaking…") && texts(Pages.island(status)).contains("Sent to Kitchen"))
        status.config.defaultTarget = ""
        XCTAssertEqual(ids(Pages.island(status)), ["say", "broadcasting", "quiet", "speakers"], "no speaker, no volume controls")
    }

    func testTheGeneralSectionDrawsTheFileAsHomeSpeakersPageDoes() {
        var status = Pages.Status()
        status.config = configured
        status.config.effectiveAnnounceVolumeEnabled = true
        status.loginItem = .enabled
        let page = Pages.settings(status)
        XCTAssertEqual(ids(page), ["section", "signIn", "broadcasting", "loginItem", "speechLength", "announceVolume", "announceLevel",
                                   "pauseMedia", "quiet", "quietStart", "quietEnd"])
        XCTAssertEqual(texts(page).filter { ["Google Home Account", "Broadcast Controls", "Quiet Hours"].contains($0) },
                       ["Google Home Account", "Broadcast Controls", "Quiet Hours"])
        guard case .list(let lengths)? = page.blocks.first(where: { $0.id == "speechLength" })?.content else { return XCTFail("no list") }
        XCTAssertEqual(lengths.rows.map(\.id), ["headline", "summary", "full"])
        XCTAssertEqual(lengths.rows.map { $0.trailing?.text(for: "en") }, [nil, "✓", nil], "summary is the default")
        guard case .field(let level)? = page.blocks.first(where: { $0.id == "announceLevel" })?.content else { return XCTFail("no field") }
        XCTAssertEqual(level.value, "60")
        status.config.effectiveAnnounceVolumeEnabled = false
        XCTAssertFalse(ids(Pages.settings(status)).contains("announceLevel"))
        status.config.effectivePauseMedia = true
        status.account = Pages.Account(isSignedIn: true, email: "me@example.com", hasOAuthClient: true)
        status.offersChoice = true
        let more = Pages.settings(status)
        XCTAssertEqual(ids(more), ["section", "signOut", "broadcasting", "loginItem", "speechLength", "announceVolume", "pauseMedia",
                                   "pauseExtra", "testMediaPause", "quiet", "quietStart", "quietEnd"])
        guard case .choice(let choice)? = more.blocks.first(where: { $0.id == "speechLength" })?.content else { return XCTFail("no choice") }
        XCTAssertEqual(choice.options.map { $0.title.text(for: "en") }, SpeechLength.allCases.map(\.label))
    }

    func testTheSpeakersSectionHasDiscoveryTheSpeakersAndWhereToSpeak() {
        var status = Pages.Status()
        status.config = configured
        status.config.structureName = "Home"
        status.section = .speakers
        status.account = Pages.Account(isSignedIn: true)
        let page = Pages.settings(status)
        XCTAssertEqual(ids(page), ["section", "discover", "targets", "editSpeakers", "speakHome", "speakLocal"])
        XCTAssertEqual(texts(page).filter { ["Discovery", "Speakers & Displays", "Where to speak"].contains($0) },
                       ["Discovery", "Speakers & Displays", "Where to speak"])
        status.config.effectiveSpeakLocal = true
        status.homes = [HomeStructure(id: "s1", name: "Home"), HomeStructure(id: "s2", name: "Cabin")]
        XCTAssertEqual(ids(Pages.settings(status)), ["section", "home", "discover", "targets", "editSpeakers", "speakHome", "speakLocal",
                                                     "voice", "previewVoice"])
        XCTAssertEqual(Pages.outputsFooter(status.config).contains("Both speak at the same time"), true)
    }

    func testEverySetupJobHasABusyLine() {
        let jobs: [Job] = [.signIn(chatOnly: false), .app(.signOut(chatOnly: false)), .app(.discover(save: false, home: nil)),
                           .app(.discover(save: true, home: "h")), .app(.loginItem(.status)), .app(.loginItem(.enable)),
                           .app(.testMediaPause)]
        XCTAssertEqual(Set(jobs.map(Pages.busyLine)).count, jobs.count)
        XCTAssertTrue(jobs.allSatisfy(\.isSetup))
        XCTAssertFalse([Job.say("x"), .volume, .setVolume(3), .mute, .unmute].contains(where: \.isSetup))
    }

    func testBothPagesAreWithinTheProtocolsLimits() throws {
        var status = Pages.Status()
        status.config = configured
        for index in 0..<40 {
            status.config.targets["speaker\(index)"] = SpeakerDevice(id: "d\(index)", type: "SpeakerDevice",
                                                                      name: String(repeating: "n", count: 60), room: String(repeating: "r", count: 40))
        }
        status.notice = String(repeating: "x", count: 300)
        status.configProblem = String(repeating: "p", count: 300)
        status.homes = (0..<80).map { HomeStructure(id: "home\($0)", name: String(repeating: "h", count: 60)) }
        status.voices = (0..<100).map { LocalVoice(id: "com.apple.voice.v\($0)", name: "Voice \($0)", language: "en-US", quality: .enhanced) }
        status.config.effectiveSpeakLocal = true
        var speakers = status
        speakers.section = .speakers
        var choices = speakers
        choices.offersChoice = true
        for tree in [Pages.island(status), Pages.settings(status), Pages.settings(speakers), Pages.settings(choices)] {
            XCTAssertLessThan(try JSONEncoder().encode(tree).count, UILimits.maxTreeBytes)
            XCTAssertLessThanOrEqual(tree.blocks.count, UILimits.maxBlocks)
        }
        guard case .list(let speakers)? = Pages.island(status).blocks.first(where: { $0.id == "speakers" })?.content else { return XCTFail("no list") }
        XCTAssertEqual(speakers.rows.count, Pages.maxSpeakerRows)
        for block in Pages.settings(choices).blocks {
            if case .choice(let choice) = block.content { XCTAssertLessThanOrEqual(choice.options.count, UILimits.maxChoiceOptions) }
        }
    }
}
