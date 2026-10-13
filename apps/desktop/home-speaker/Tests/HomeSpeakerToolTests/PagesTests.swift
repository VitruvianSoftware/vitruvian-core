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

    func testTheSettingsPanelDrawsTheFileAsHomeSpeakersPageDoes() {
        var status = Pages.Status()
        status.config = configured
        status.config.effectiveAnnounceVolumeEnabled = true
        let page = Pages.settings(status)
        XCTAssertEqual(ids(page), ["speechLength", "speakHome", "speakLocal", "announceVolume", "announceLevel", "pauseMedia",
                                   "quiet", "quietStart", "quietEnd"])
        guard case .list(let lengths)? = page.blocks.first(where: { $0.id == "speechLength" })?.content else { return XCTFail("no list") }
        XCTAssertEqual(lengths.rows.map(\.id), ["headline", "summary", "full"])
        XCTAssertEqual(lengths.rows.map { $0.trailing?.text(for: "en") }, [nil, "✓", nil], "summary is the default")
        guard case .field(let level)? = page.blocks.first(where: { $0.id == "announceLevel" })?.content else { return XCTFail("no field") }
        XCTAssertEqual(level.value, "60")
        status.config.effectiveAnnounceVolumeEnabled = false
        XCTAssertFalse(ids(Pages.settings(status)).contains("announceLevel"))
    }

    func testBothPagesAreWithinTheProtocolsLimits() throws {
        var status = Pages.Status()
        status.config = configured
        for index in 0..<40 {
            status.config.targets["speaker\(index)"] = SpeakerDevice(id: "d\(index)", type: "SpeakerDevice",
                                                                      name: String(repeating: "n", count: 60), room: String(repeating: "r", count: 40))
        }
        status.notice = String(repeating: "x", count: 300)
        for tree in [Pages.island(status), Pages.settings(status)] {
            XCTAssertLessThan(try JSONEncoder().encode(tree).count, UILimits.maxTreeBytes)
            XCTAssertLessThanOrEqual(tree.blocks.count, UILimits.maxBlocks)
        }
        guard case .list(let speakers)? = Pages.island(status).blocks.first(where: { $0.id == "speakers" })?.content else { return XCTFail("no list") }
        XCTAssertEqual(speakers.rows.count, Pages.maxSpeakerRows)
    }
}
