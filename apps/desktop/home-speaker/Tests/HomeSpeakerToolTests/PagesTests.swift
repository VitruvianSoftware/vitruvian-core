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

    /// An app before 3.48: the speaker list and the typed volume, as
    /// before, with Mute a switch and no Quieter, Louder or Read.
    func testTheIslandPageHasTheFieldTheSwitchesAndTheSpeaker() {
        var status = Pages.Status()
        status.config = configured
        status.account = Pages.Account(isSignedIn: true, hasOAuthClient: true)
        status.volume = Volume(speaker: "Kitchen", percent: 40, muted: false, online: true)
        status.quietNow = true
        let page = Pages.island(status)
        XCTAssertEqual(ids(page), ["say", "sayClipboard", "broadcasting", "speechLength", "announcementStyle", "quiet", "quietStart", "quietEnd",
                                     "speakers", "volume", "mute", "output.home", "output.local", "output.phone",
                                     "claudeCodeEnabled", "antigravityEnabled", "opencodeEnabled", "slackEnabled", "googleChatEnabled", "beeperEnabled"])
        XCTAssertFalse(texts(page).contains("HomeSpeaker"), "the island's header names it already")
        XCTAssertTrue(texts(page).contains("Quiet hours until 07:00: what you type still plays"))
        XCTAssertFalse(page.blocks.contains { if case .choice = $0.content { return true } else { return false } },
                       "an app without the choice block gets none")
        guard case .list(let speakers)? = page.blocks.first(where: { $0.id == "speakers" })?.content else { return XCTFail("no list") }
        XCTAssertEqual(speakers.rows.map(\.id), ["kitchen", "all"], "the person's speaker first, the whole home after")
        XCTAssertEqual(speakers.rows.first?.trailing?.text(for: "en"), "✓")
        guard case .field(let volume)? = page.blocks.first(where: { $0.id == "volume" })?.content else { return XCTFail("no field") }
        XCTAssertEqual(volume.value, "40")
        guard case .toggle(let mute)? = page.blocks.first(where: { $0.id == "mute" })?.content else { return XCTFail("no switch") }
        XCTAssertEqual(mute.value, false)
        status.volume?.muted = true
        guard case .toggle(let muted)? = Pages.island(status).blocks.first(where: { $0.id == "mute" })?.content else {
            return XCTFail("no switch")
        }
        XCTAssertEqual(muted.value, true, "muted: the same switch, on")
        status.volume = Volume(speaker: "Kitchen", online: false)
        XCTAssertTrue(texts(Pages.island(status)).contains("Kitchen is offline"))
        status.busy = .say("x")
        status.notice = "Sent to Kitchen"
        XCTAssertTrue(texts(Pages.island(status)).contains("Speaking…") && texts(Pages.island(status)).contains("Sent to Kitchen"))
        status.config.defaultTarget = ""
        XCTAssertEqual(ids(Pages.island(status)), ["say", "sayClipboard", "broadcasting", "speechLength", "announcementStyle", "quiet", "quietStart", "quietEnd",
                                                 "speakers", "output.home", "output.local", "output.phone",
                                                 "claudeCodeEnabled", "antigravityEnabled", "opencodeEnabled", "slackEnabled", "googleChatEnabled", "beeperEnabled"],
                       "no speaker, no volume controls")
        XCTAssertTrue(texts(Pages.island(status)).contains("No speaker picked yet"))
    }

    /// An app from 3.48: the speaker and the volume are a menu each.
    func testTheIslandPageHasMenusWhereTheAppDrawsThem() {
        var status = Pages.Status()
        status.config = configured
        status.account = Pages.Account(isSignedIn: true, hasOAuthClient: true)
        status.volume = Volume(speaker: "Kitchen", percent: 40, muted: false, online: true)
        status.offersChoice = true
        let page = Pages.island(status)
        XCTAssertEqual(ids(page), ["say", "sayClipboard", "broadcasting", "speechLength", "announcementStyle", "quiet", "quietStart", "quietEnd",
                                     "speakers", "volume", "mute", "output.home", "output.local", "output.phone",
                                     "claudeCodeEnabled", "antigravityEnabled", "opencodeEnabled", "slackEnabled", "googleChatEnabled", "beeperEnabled"])
        guard case .choice(let speaker)? = page.blocks.first(where: { $0.id == "speakers" })?.content else { return XCTFail("no menu") }
        XCTAssertEqual(speaker.title?.text(for: "en"), "Speaker")
        XCTAssertEqual(speaker.value, "kitchen")
        XCTAssertEqual(speaker.options.map(\.value), ["kitchen", "all"])
        XCTAssertEqual(speaker.options.map { $0.title.text(for: "en") }, ["Kitchen", "Whole Home"])
        guard case .choice(let volume)? = page.blocks.first(where: { $0.id == "volume" })?.content else { return XCTFail("no menu") }
        XCTAssertEqual(volume.title?.text(for: "en"), "Volume")
        XCTAssertEqual(volume.value, "40")
        XCTAssertEqual(volume.options.map(\.value), Pages.volumeSteps.map(String.init))
        XCTAssertEqual(volume.options.first?.title.text(for: "en"), "0 %")
        XCTAssertEqual(volume.options.count, 11)
        XCTAssertFalse(texts(page).contains("Speaker"), "the menu carries its own title")

        // No default speaker: the menu says so, and nothing about the volume.
        status.config.defaultTarget = ""
        let none = Pages.island(status)
        guard case .choice(let unpicked)? = none.blocks.first(where: { $0.id == "speakers" })?.content else { return XCTFail("no menu") }
        XCTAssertEqual(unpicked.value, "")
        XCTAssertEqual(unpicked.options.first?.title.text(for: "en"), "None picked")
        XCTAssertFalse(ids(none).contains("volume"))
        XCTAssertFalse(ids(none).contains("mute"))
    }

    func testTheVolumeMenuKeepsALevelBetweenTwoSteps() {
        XCTAssertEqual(Pages.volumeOptions(35).map(\.value), ["0", "10", "20", "30", "35", "40", "50", "60", "70", "80", "90", "100"],
                       "35 is kept, in its place")
        XCTAssertEqual(Pages.volumeOptions(30).map(\.value), Pages.volumeSteps.map(String.init), "a step is not added twice")
        let unread = Pages.volumeOptions(nil)
        XCTAssertEqual(unread.first?.value, "")
        XCTAssertEqual(unread.first?.title.text(for: "en"), "—")
        XCTAssertEqual(unread.count, 12)

        var status = Pages.Status()
        status.config = configured
        status.account = Pages.Account(isSignedIn: true, hasOAuthClient: true)
        status.offersChoice = true
        status.volume = Volume(speaker: "Kitchen", percent: 35)
        guard case .choice(let menu)? = Pages.island(status).blocks.first(where: { $0.id == "volume" })?.content else {
            return XCTFail("no menu")
        }
        XCTAssertEqual(menu.value, "35")
        XCTAssertTrue(menu.options.contains { $0.value == "35" && $0.title.text(for: "en") == "35 %" })
        status.volume = nil
        guard case .choice(let notRead)? = Pages.island(status).blocks.first(where: { $0.id == "volume" })?.content else {
            return XCTFail("no menu")
        }
        XCTAssertEqual(notRead.value, "", "not read yet: the menu shows a dash, not a level")
    }

    func testTheIslandEndsWithWhereTheOtherSettingsAre() {
        XCTAssertEqual(Pages.moreSettings, "More settings: Vitruvian Settings › Extensions › HomeSpeaker")
        var status = Pages.Status()
        status.config = configured
        status.account = Pages.Account(isSignedIn: true, hasOAuthClient: true)
        for offersChoice in [false, true] {
            status.offersChoice = offersChoice
            XCTAssertEqual(texts(Pages.island(status)).last, Pages.moreSettings)
        }
        // Before setup, and while the other HomeSpeaker is in use, too.
        status.account.isSignedIn = false
        XCTAssertEqual(texts(Pages.island(status)).last, Pages.moreSettings)
        status.door = Pages.DoorState(role: .quiet(other: .app), otherInstalled: true)
        XCTAssertEqual(texts(Pages.island(status)).last, Pages.moreSettings)
        XCTAssertFalse(texts(Pages.island(status)).contains("HomeSpeaker"), "no heading on the quiet card either")
        XCTAssertFalse(texts(Pages.settings(status)).contains(Pages.moreSettings), "Settings is where it points")
    }

    /// For an app that opens the settings panel, the island's last line is
    /// a "More settings…" button in place of the caption: in every state
    /// the caption was drawn in, and never on Settings itself.
    func testTheIslandEndsWithAMoreSettingsButtonForAnAppThatOpensThem() {
        XCTAssertEqual(Pages.moreSettingsButton, "More settings…")
        var status = Pages.Status()
        status.config = configured
        status.account = Pages.Account(isSignedIn: true, hasOAuthClient: true)
        status.opensSettings = true
        func endsWithTheButton(_ tree: UITree, _ why: String) {
            guard case .button(let button)? = tree.blocks.last?.content else { return XCTFail("\(why): no button last") }
            XCTAssertEqual(tree.blocks.last?.id, Pages.Block.moreSettings, why)
            XCTAssertEqual(button.title.text(for: "en"), Pages.moreSettingsButton, why)
            XCTAssertNil(button.style, "\(why): a plain button, not the page's main action")
            XCTAssertNotEqual(button.enabled, false, why)
            XCTAssertFalse(texts(tree).contains(Pages.moreSettings), "\(why): the button, not the caption too")
        }
        for offersChoice in [false, true] {
            status.offersChoice = offersChoice
            endsWithTheButton(Pages.island(status), "set up, choice \(offersChoice)")
        }
        status.account.isSignedIn = false
        endsWithTheButton(Pages.island(status), "before setup")
        status.door = Pages.DoorState(role: .quiet(other: .app), otherInstalled: true)
        endsWithTheButton(Pages.island(status), "the other HomeSpeaker in use")
        XCTAssertFalse(ids(Pages.settings(status)).contains(Pages.Block.moreSettings), "Settings is where it opens")
    }

    /// The read on every opening says nothing while a level is shown; one
    /// with no level yet, or any other job, still says what it is doing.
    func testTheReadOnOpeningIsQuietWhileALevelIsShown() {
        var status = Pages.Status()
        status.config = configured
        status.account = Pages.Account(isSignedIn: true, hasOAuthClient: true)
        status.busy = .volume
        XCTAssertTrue(texts(Pages.island(status)).contains("Reading the volume…"), "nothing to show yet")
        status.volume = Volume(speaker: "Kitchen", percent: 40)
        XCTAssertFalse(texts(Pages.island(status)).contains("Reading the volume…"))
        status.busy = .setVolume(50)
        XCTAssertTrue(texts(Pages.island(status)).contains("Setting the volume to 50 %…"))
    }

    func testTheGeneralSectionDrawsTheFileAsHomeSpeakersPageDoes() {
        var status = Pages.Status()
        status.config = configured
        status.config.effectiveAnnounceVolumeEnabled = true
        let page = Pages.settings(status)
        XCTAssertEqual(ids(page), ["section", "signIn", "openGoogleCloud", "broadcasting", "speechLength", "announcementStyle", "announceVolume", "announceLevel",
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
        XCTAssertEqual(ids(more), ["section", "signOut", "broadcasting", "speechLength", "announcementStyle", "announceVolume", "pauseMedia",
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
        // The engine for the Home speakers alone: picking Gemini there is
        // what offers casting, which needs it.
        XCTAssertEqual(ids(page), ["section", "speakHome", "speakers", "speakLocal", "speakPhone", "localEngine",
                                   "discover", "targets", "editSpeakers"])
        XCTAssertEqual(texts(page).filter { ["Where to speak", "Discovery", "Speakers & Displays"].contains($0) },
                       ["Where to speak", "Discovery", "Speakers & Displays"])
        status.config.effectiveSpeakLocal = true
        status.homes = [HomeStructure(id: "s1", name: "Home"), HomeStructure(id: "s2", name: "Cabin")]
        XCTAssertEqual(ids(Pages.settings(status)), ["section", "speakHome", "speakers", "speakLocal", "speakPhone",
                                                     "localEngine", "voice", "previewVoice", "home", "discover", "targets", "editSpeakers"])
        XCTAssertEqual(Pages.outputsFooter(status.config).contains("Both speak at the same time"), true)
    }

    func testTheChatAndSlackSectionDrawsEachBranch() {
        var status = Pages.Status()
        status.section = .monitor
        // Nothing on, nothing saved, nothing installed.
        XCTAssertEqual(ids(Pages.settings(status)), ["section", "slackEnabled", "googleChatEnabled", "beeperEnabled",
                                                    "muteOwnMessages", "pollInterval"])
        // Tokens saved, Chat granted, gws there.
        status.config.effectiveChatMonitor.slackEnabled = true
        status.config.effectiveChatMonitor.googleChatEnabled = true
        status.config.effectiveChatMonitor.beeperEnabled = true
        status.chat = Pages.Chat(hasSlackToken: true, hasChatAccess: true, gwsPath: "/opt/homebrew/bin/gws", ownerRunning: true,
                                 hasBeeperToken: true)
        XCTAssertEqual(ids(Pages.settings(status)), ["section", "startChatMonitor", "slackEnabled", "slackToken", "saveSlackToken", "clearSlackToken", "googleChatEnabled",
                                                    "chatSource", "disconnectChat", "gwsAccount", "beeperEnabled", "beeperAnnounce",
                                                    "beeperToken", "saveBeeperToken", "clearBeeperToken", "muteOwnMessages", "pollInterval"])
        XCTAssertTrue(texts(Pages.settings(status)).contains("Beeper token saved · "))
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
        // Every source on with no token: the island draws both token fields.
        status.config.effectiveChatMonitor = ChatMonitorConfig(slackEnabled: true, googleChatEnabled: true, beeperEnabled: true)
        // And Beeper's networks: 30 read, skipped or muted, and 30 more
        // muted that Beeper did not list.
        status.config.effectiveChatMonitor.beeperMutedNetworks = (0..<30).map { "saved-mute-\($0)" }
        status.chat = Pages.Chat(ownerRunning: true, monitor: ChatMonitorStatus(
            isRunning: true, lastError: String(repeating: "e", count: 2_000), beeperNetworkStates: ChatSlackTests.manyNetworkStates()))
        var opens = status
        opens.opensSettings = true
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
        XCTAssertGreaterThanOrEqual(Pages.island(status).blocks.filter { $0.id.map { Pages.Block.beeperNetworkKey($0) != nil } ?? false }.count,
                                    30, "the island draws the networks it is checked with")
        for tree in [Pages.island(status), Pages.island(opens), Pages.island(setup), Pages.settings(status), Pages.settings(speakers), Pages.settings(choices),
                     Pages.settings(monitor), Pages.settings(agents), Pages.settings(cloud)] + doorPages {
            XCTAssertLessThan(try JSONEncoder().encode(tree).count, UILimits.maxTreeBytes)
            XCTAssertLessThanOrEqual(tree.blocks.count, UILimits.maxBlocks)
            // Measured is not read: Vitruvian refuses a page over one id.
            XCTAssertNil(PageIdsTests.whyTheAppRefuses(tree))
        }
        guard case .list(let speakers)? = Pages.island(status).blocks.first(where: { $0.id == "speakers" })?.content else { return XCTFail("no list") }
        XCTAssertEqual(speakers.rows.count, Pages.maxSpeakerRows)
        for block in Pages.settings(choices).blocks {
            if case .choice(let choice) = block.content { XCTAssertLessThanOrEqual(choice.options.count, UILimits.maxChoiceOptions) }
        }
    }

    /// Settings with every section on one page, at its largest: signed out
    /// with every sign-in line, the chat monitor running with problems,
    /// the agents at their longest (Claude Code warning that it speaks
    /// twice; Antigravity, which has no hook to double, not set up), a
    /// door compare step with its report, and 30 Beeper networks as chips.
    /// Measured, and held to the protocol's limits.
    func testTheWholePageFitsTheLimits() throws {
        let long = { (letter: String) in String(repeating: letter, count: 300) }
        var status = Pages.Status()
        status.offersChoice = true
        status.offersChips = true
        status.offersSections = true
        status.opensSettings = true
        status.config = configured
        for index in 0..<40 {
            status.config.targets["speaker\(index)"] = SpeakerDevice(id: "d\(index)", type: "SpeakerDevice",
                                                                      name: String(repeating: "n", count: 60), room: String(repeating: "r", count: 40))
        }
        status.config.effectiveSpeakLocal = true
        status.config.effectiveAnnounceVolumeEnabled = true
        status.config.effectivePauseMedia = true
        status.removingSpeakers = true
        status.account = Pages.Account(isSignedIn: false, hasOAuthClient: false, hasAntigravityTokens: true,
                                       customOAuthClientId: long("i"), hasCustomOAuthClientSecret: true, hasBundledOAuthClient: true)
        status.configProblem = long("p")
        status.setupBusy = .app(.testMediaPause)
        status.setupNotice = long("n")
        status.mediaPauseReport = long("m")
        status.volumeRestoreReport = long("v")
        status.homes = (0..<80).map { HomeStructure(id: "home\($0)", name: String(repeating: "h", count: 60)) }
        status.voices = (0..<100).map { LocalVoice(id: "com.apple.voice.v\($0)", name: "Voice \($0)", language: "en-US", quality: .enhanced) }
        // Every source on, Slack's and Beeper's tokens missing: problems.
        status.config.effectiveChatMonitor = ChatMonitorConfig(slackEnabled: true, googleChatEnabled: true, gwsAccount: long("a"),
                                                               beeperEnabled: true)
        let networks = (0..<30).map { "Network \($0) " + String(repeating: "n", count: 40) }
        status.chat = Pages.Chat(
            gwsPath: "/" + long("g"), ownerRunning: true,
            monitor: ChatMonitorStatus(isRunning: true, lastPollDate: Date(), lastError: String(repeating: "e", count: 2_000),
                                       slackIdentity: long("s"), activeGoogleChatBackend: "api", beeperNetworks: networks,
                                       beeperSkippedNetworks: networks, beeperNetworkStates: ChatSlackTests.manyNetworkStates()))
        let rival = URL(fileURLWithPath: "/u/.claude/skills/google-home/hooks/hooks.json")
        status.agents = Pages.Agents(
            statuses: [AgentIntegration.AgentStatus(agent: .claudeCode, isInstalled: true, hook: .installed, configuredByInstruction: true,
                                                    rivalHook: rival),
                       AgentIntegration.AgentStatus(agent: .antigravity, isInstalled: true, hook: .notInstalled,
                                                    configuredByInstruction: false, rivalHook: nil)],
            hookCommands: [.claudeCode: "\"" + String(repeating: "p", count: 1_000) + "\" --claude-stop-hook"], legacyLaunchAgent: true)
        status.draftClientId = long("d")
        status.draftClientSecretTyped = true
        status.files = Pages.Files(settings: String(repeating: "s", count: 1_000), secrets: String(repeating: "s", count: 1_000),
                                   history: String(repeating: "h", count: 1_000), homeSpeakerVersion: "1.26.0")
        let snapshot = DoorSnapshot(settingsChanged: Date(), googleEmail: long("e"), hasHomeLogin: true, homeName: long("h"),
                                    speakerCount: 40, defaultSpeaker: long("d"), quietHours: "22:00 to 07:00",
                                    chatSources: ["Slack", "Google Chat", "Beeper"])
        let compare = Pages.DoorCompare(purpose: .choose, from: .app, into: .extension, source: snapshot, destination: DoorSnapshot(),
                                        problem: long("p"))
        status.door = Pages.DoorState(role: .waitingAsking, otherInstalled: true, step: .compare(compare),
                                      report: (0..<8).map { _ in long("r") })

        let page = Pages.settings(status)
        // The fixtures reach what they are meant to: every section, the
        // problems, both agents, the compare step and the chips.
        XCTAssertEqual(page.blocks.filter {
            if case .heading(let heading) = $0.content { return heading.section == true }
            return false
        }.count, 5)
        XCTAssertNotNil(page.blocks.first { $0.id == Pages.Block.beeperNetworks })
        guard case .chips(let chips)? = page.blocks.first(where: { $0.id == Pages.Block.beeperNetworks })?.content else {
            return XCTFail("no chips")
        }
        XCTAssertEqual(chips.options.count, 30)
        XCTAssertTrue(texts(page).contains { $0.hasPrefix(ChatMonitorError.slackTokenMissing.localizedDescription) })
        XCTAssertTrue(texts(page).contains { $0.hasPrefix("Every reply is spoken twice") })
        XCTAssertTrue(ids(page).contains(Pages.Block.agent(.installHook, .antigravity)))
        XCTAssertTrue(ids(page).contains(Pages.Block.importAntigravity))
        XCTAssertTrue(ids(page).contains(Pages.Block.removeLegacyAgent))
        XCTAssertTrue(ids(page).contains { $0.hasPrefix("door.") }, "the compare step is drawn")

        let bytes = try JSONEncoder().encode(page).count
        print("HomeSpeaker settings, every section on one page, worst case: \(page.blocks.count) blocks of \(UILimits.maxBlocks), "
              + "\(bytes) bytes of \(UILimits.maxTreeBytes)")
        XCTAssertLessThanOrEqual(page.blocks.count, UILimits.maxBlocks)
        XCTAssertLessThanOrEqual(bytes, UILimits.maxTreeBytes)
        // And read back as Vitruvian reads it, which refuses the whole
        // page over one id (HomeSpeaker 1.27.1's `installHook:claudeCode`).
        XCTAssertNil(PageIdsTests.whyTheAppRefuses(page))

        // The same without chips: a switch a network instead.
        var switches = status
        switches.offersChips = false
        let fallback = Pages.settings(switches)
        let fallbackBytes = try JSONEncoder().encode(fallback).count
        XCTAssertEqual(ids(fallback).filter { Pages.Block.beeperNetworkKey($0) != nil }.count, 30)
        print("HomeSpeaker settings, every section on one page, switches for chips: \(fallback.blocks.count) blocks, "
              + "\(fallbackBytes) bytes")
        XCTAssertLessThanOrEqual(fallback.blocks.count, UILimits.maxBlocks)
        XCTAssertLessThanOrEqual(fallbackBytes, UILimits.maxTreeBytes)
        XCTAssertNil(PageIdsTests.whyTheAppRefuses(fallback))
    }

    /// General follows the same rules as the island: the style while a
    /// coding agent announces, the set volume while the Home speakers speak.
    func testGeneralShowsTheStyleAndTheSetVolumeOnlyWhereTheyApply() {
        var status = Pages.Status()
        status.config = configured
        status.config.announcementStyle = .briefing
        status.config.effectiveAnnounceVolumeEnabled = true
        let style: Set<String> = [Pages.Block.announcementStyle, Pages.Block.styleModel]
        let volume: Set<String> = [Pages.Block.announceVolume, Pages.Block.announceLevel]
        var shown = Set(ids(Pages.settings(status)))
        XCTAssertTrue(style.isSubset(of: shown))
        XCTAssertTrue(volume.isSubset(of: shown))

        for agent in CodingAgent.allCases { status.config.setAnnounces(agent, false) }
        status.config.effectiveSpeakHome = false
        shown = Set(ids(Pages.settings(status)))
        XCTAssertTrue(style.isDisjoint(with: shown), "no agent announces: nothing to reword")
        XCTAssertTrue(volume.isDisjoint(with: shown), "Home speakers off: no speaker volume to set")
        XCTAssertTrue(shown.contains(Pages.Block.speechLength))
        XCTAssertTrue(shown.contains(Pages.Block.pauseMedia))
    }
}
