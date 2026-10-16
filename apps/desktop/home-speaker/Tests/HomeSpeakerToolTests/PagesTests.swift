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

    /// The extension is HomeSpeaker: no page sends the person to get the
    /// app, or says the app must run, and Open at Login is Vitruvian's.
    func testNoPageSaysHomeSpeakerIsMissing() {
        let gone = ["is not installed on this Mac", "Get HomeSpeaker", "Needs HomeSpeaker running",
                    "isn't running, so nothing is reading chat", "Open HomeSpeaker at Login"]
        for installed in [true, false] {
            var status = Pages.Status()
            status.installed = installed
            status.config = configured
            status.config.effectiveAnnounceVolumeEnabled = true
            status.config.effectiveChatMonitor.slackEnabled = true
            var pages = [Pages.island(status)]
            for section in Pages.Section.allCases {
                status.section = section
                pages.append(Pages.settings(status))
            }
            for page in pages {
                for line in texts(page) {
                    XCTAssertFalse(gone.contains { line.contains($0) }, line)
                }
                XCTAssertFalse(ids(page).contains("loginItem"), "the login-item switch is gone")
            }
            status.section = .general
            XCTAssertTrue(texts(Pages.settings(status)).contains(Pages.DoorWords.runsWithVitruvian))
        }
        XCTAssertEqual(Pages.DoorWords.runsWithVitruvian,
                       "Runs whenever Vitruvian runs. To start it at login, turn on Vitruvian's Open at Login.")
    }

    func testQuietHoursPickerOnNewApps() throws {
        var status = Pages.Status()
        status.config = configured
        status.offersChoice = true
        var page = Pages.settings(status)
        guard case .choice(let from)? = page.blocks.first(where: { $0.id == "quietStart" })?.content,
              case .choice(let until)? = page.blocks.first(where: { $0.id == "quietEnd" })?.content else {
            return XCTFail("no choices")
        }
        XCTAssertEqual(from.options.map(\.value), Pages.halfHours)
        XCTAssertEqual(Pages.halfHours.count, 48)
        XCTAssertEqual(Pages.halfHours.first, "00:00")
        XCTAssertEqual(Pages.halfHours[45], "22:30")
        XCTAssertEqual(Pages.halfHours.last, "23:30")
        XCTAssertEqual(from.value, "22:00")
        XCTAssertEqual(until.value, "07:00")
        XCTAssertEqual(from.title?.text(for: "en"), "From")
        XCTAssertEqual(until.title?.text(for: "en"), "Until")

        // A time typed before, off the half hour, is kept and offered.
        status.config.quietHoursStart = "23:15"
        page = Pages.settings(status)
        guard case .choice(let kept)? = page.blocks.first(where: { $0.id == "quietStart" })?.content else { return XCTFail("no choice") }
        XCTAssertEqual(kept.value, "23:15")
        XCTAssertEqual(kept.options.count, 49)
        XCTAssertEqual(Set(kept.options.map(\.value)).count, kept.options.count, "no two options alike")
        XCTAssertTrue(kept.options.map(\.value).contains("23:15"))

        // An app without the choice block: the typed field, as before.
        status.offersChoice = false
        page = Pages.settings(status)
        guard case .field(let field)? = page.blocks.first(where: { $0.id == "quietStart" })?.content else { return XCTFail("no field") }
        XCTAssertEqual(field.title?.text(for: "en"), "From (HH:mm)")
        XCTAssertEqual(field.value, "23:15")
    }

    func testTheRestoreReportIsTheEngines() {
        var status = Pages.Status()
        status.config = configured
        status.config.effectiveAnnounceVolumeEnabled = true
        let plain = "The speaker goes back to its own volume when the announcement ends, unless someone changes it in the meantime."
        XCTAssertTrue(texts(Pages.settings(status)).contains(plain))
        status.volumeRestoreReport = "Put Kitchen back to 30% after announcing at 60%."
        XCTAssertTrue(texts(Pages.settings(status)).contains("Put Kitchen back to 30% after announcing at 60%."))
        XCTAssertFalse(texts(Pages.settings(status)).contains(plain))
    }

    func testFilesListTheExtensionsThreeFiles() {
        var status = Pages.Status()
        status.section = .googleCloud
        status.files = Pages.Files(settings: "/data/settings.json", secrets: "/data/secrets.json", history: "/data/history.json",
                                   homeSpeakerVersion: "1.19.0")
        let lines = texts(Pages.settings(status))
        XCTAssertTrue(lines.contains("Settings · /data/settings.json"))
        XCTAssertTrue(lines.contains("Secrets · /data/secrets.json"))
        XCTAssertTrue(lines.contains("History · /data/history.json"))
    }

    func testTheIslandPageHasTheFieldTheSwitchesAndTheSpeaker() {
        var status = Pages.Status()
        status.config = configured
        status.account = Pages.Account(isSignedIn: true, hasOAuthClient: true)
        status.volume = Volume(speaker: "Kitchen", percent: 40, muted: false, online: true)
        status.quietNow = true
        let page = Pages.island(status)
        XCTAssertEqual(ids(page), ["say", "broadcasting", "quiet", "mute", "volume", "quieter", "louder", "refresh", "speakers",
                                   "output.home", "output.local"])
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
        XCTAssertEqual(ids(Pages.island(status)), ["say", "broadcasting", "quiet", "speakers", "output.home", "output.local"],
                       "no speaker, no volume controls")
    }

    func testTheGeneralSectionDrawsTheFileAsHomeSpeakersPageDoes() {
        var status = Pages.Status()
        status.config = configured
        status.config.effectiveAnnounceVolumeEnabled = true
        let page = Pages.settings(status)
        XCTAssertEqual(ids(page), ["section", "signIn", "openGoogleCloud", "broadcasting", "speechLength", "announceVolume", "announceLevel",
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
        XCTAssertEqual(ids(more), ["section", "signOut", "broadcasting", "speechLength", "announceVolume", "pauseMedia",
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

    func testTheChatAndSlackSectionDrawsEachBranch() {
        var status = Pages.Status()
        status.section = .monitor
        // Nothing on, nothing saved, nothing installed.
        XCTAssertEqual(ids(Pages.settings(status)), ["section", "slackEnabled", "slackToken", "googleChatEnabled", "chatSource",
                                                    "grantChat", "muteOwnMessages", "pollInterval"])
        // A token saved, Chat granted, gws there.
        status.chat = Pages.Chat(hasSlackToken: true, hasChatAccess: true, gwsPath: "/opt/homebrew/bin/gws", ownerRunning: true)
        XCTAssertEqual(ids(Pages.settings(status)), ["section", "slackEnabled", "slackToken", "clearSlackToken", "googleChatEnabled",
                                                    "chatSource", "disconnectChat", "gwsAccount", "muteOwnMessages", "pollInterval"])
        XCTAssertTrue(texts(Pages.settings(status)).contains("Slack token saved · "))
        XCTAssertTrue(texts(Pages.settings(status)).contains("HomeSpeaker is running · "))
        // The API only, or gws only.
        status.config.effectiveChatMonitor.googleChatSource = .api
        XCTAssertFalse(ids(Pages.settings(status)).contains("gwsAccount"))
        status.config.effectiveChatMonitor.googleChatSource = .gws
        XCTAssertFalse(ids(Pages.settings(status)).contains("disconnectChat"))
        XCTAssertTrue(ids(Pages.settings(status)).contains("gwsAccount"))
        // Sources on with a problem: a warning row, with no id to tap.
        status.chat.hasSlackToken = false
        status.config.effectiveChatMonitor.slackEnabled = true
        XCTAssertTrue(texts(Pages.settings(status)).contains("\(ChatMonitorError.slackTokenMissing.localizedDescription) · "))
        XCTAssertEqual(Pages.chatSourceTitle(.auto), "Automatic")
        XCTAssertEqual(Pages.chatSourceTitle(.api), "Google API (this app's login)")
        XCTAssertEqual(Pages.chatSourceTitle(.gws), "gws command-line tool")
    }

    func testEverySetupJobHasABusyLine() {
        let jobs: [Job] = [.signIn(chatOnly: false), .app(.signOut(chatOnly: false)), .app(.discover(save: false, home: nil)),
                           .app(.discover(save: true, home: "h")), .app(.loginItem(.status)), .app(.loginItem(.enable)),
                           .app(.testMediaPause)]
        XCTAssertEqual(Set(jobs.map(Pages.busyLine)).count, jobs.count)
        XCTAssertTrue(jobs.allSatisfy(\.isSetup))
        XCTAssertFalse([Job.say("x"), .volume, .setVolume(3), .mute, .unmute].contains(where: \.isSetup))
    }

    func testEveryPageAndSectionIsWithinTheProtocolsLimits() throws {
        var status = Pages.Status()
        status.config = configured
        for index in 0..<40 {
            status.config.targets["speaker\(index)"] = SpeakerDevice(id: "d\(index)", type: "SpeakerDevice",
                                                                      name: String(repeating: "n", count: 60), room: String(repeating: "r", count: 40))
        }
        status.account = Pages.Account(isSignedIn: true, hasOAuthClient: true)
        status.notice = String(repeating: "x", count: 300)
        status.configProblem = String(repeating: "p", count: 300)
        status.homes = (0..<80).map { HomeStructure(id: "home\($0)", name: String(repeating: "h", count: 60)) }
        status.voices = (0..<100).map { LocalVoice(id: "com.apple.voice.v\($0)", name: "Voice \($0)", language: "en-US", quality: .enhanced) }
        status.config.effectiveSpeakLocal = true
        status.recentBroadcasts = (0..<30).map { _ in BroadcastLogItem(text: String(repeating: "m", count: 2_000), targetName: "Kitchen", source: "Say") }
        status.config.effectiveChatMonitor = ChatMonitorConfig(slackEnabled: true, googleChatEnabled: true)
        var setup = status
        setup.config.targets = [:]
        setup.account = Pages.Account(isSignedIn: true, hasOAuthClient: true)
        var speakers = status
        speakers.section = .speakers
        var choices = speakers
        choices.offersChoice = true
        var monitor = choices
        monitor.section = .monitor
        monitor.config.effectiveChatMonitor = ChatMonitorConfig(slackEnabled: true, googleChatEnabled: true)
        var agents = choices
        agents.section = .agents
        let rival = URL(fileURLWithPath: "/u/.claude/skills/google-home/hooks/hooks.json")
        agents.agents = Pages.Agents(
            statuses: [AgentIntegration.AgentStatus(agent: .claudeCode, isInstalled: true, hook: .installed, configuredByInstruction: true, rivalHook: rival),
                       AgentIntegration.AgentStatus(agent: .antigravity, isInstalled: true, hook: .notInstalled, configuredByInstruction: false, rivalHook: nil)],
            hookCommands: [.claudeCode: "\"" + String(repeating: "p", count: 1_000) + "\" --claude-stop-hook"], legacyLaunchAgent: true)
        var cloud = choices
        cloud.section = .googleCloud
        cloud.account = Pages.Account(customOAuthClientId: String(repeating: "i", count: 300), hasCustomOAuthClientSecret: true,
                                      hasBundledOAuthClient: true)
        cloud.draftClientId = String(repeating: "d", count: 300)
        cloud.files = Pages.Files(settings: String(repeating: "s", count: 1_000), secrets: String(repeating: "s", count: 1_000),
                                  homeSpeakerVersion: "1.14.0")
        // Both installed: the card at each step, on both pages.
        let snapshot = DoorSnapshot(settingsChanged: Date(), googleEmail: String(repeating: "e", count: 300), hasHomeLogin: true,
                                    homeName: String(repeating: "h", count: 300), speakerCount: 40,
                                    defaultSpeaker: String(repeating: "d", count: 300), quietHours: "22:00 to 07:00",
                                    chatSources: ["Slack", "Google Chat"])
        let compare = Pages.DoorCompare(purpose: .choose, from: .app, into: .extension, source: snapshot, destination: DoorSnapshot(),
                                        problem: String(repeating: "p", count: 300))
        var doors: [Pages.Status] = []
        for step: Pages.DoorStep? in [nil, .compare(compare), .closing,
                                      .offers(Pages.DoorOffers(quit: false, plan: OtherAppPlan.forChoosingTheExtension(appVersion: nil)))] {
            var door = choices
            door.section = .general
            door.door = Pages.DoorState(role: .waitingAsking, otherInstalled: true, step: step,
                                        report: (0..<8).map { _ in String(repeating: "r", count: 300) })
            doors.append(door)
        }
        var quiet = choices
        quiet.door = Pages.DoorState(role: .quiet(other: .app), otherInstalled: true)
        doors.append(quiet)
        let doorPages = doors.flatMap { [Pages.island($0), Pages.settings($0)] }
        for tree in [Pages.island(status), Pages.island(setup), Pages.settings(status), Pages.settings(speakers), Pages.settings(choices),
                     Pages.settings(monitor), Pages.settings(agents), Pages.settings(cloud)] + doorPages {
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
