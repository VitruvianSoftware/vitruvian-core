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
import RemoteMenuCore
import RemoteToolCore
import VitruvianToolKit
import VitruvianToolProtocol
import XCTest

/// The settings page on an app that draws sections (`ui.sections`): every
/// section at once under its own section heading. On an app without it, the
/// page is the one it always was: four tab buttons and one section.
final class SettingsSectionsTests: XCTestCase {
    private static let tabIDs = RemotePages.SettingsSection.allCases.map(\.blockID)

    private let profile: RemoteProfile = {
        let tmp = URL(fileURLWithPath: "/tmp/remote-sections-test")
        return RemoteProfile.extension(dataFolder: tmp, toolFolder: tmp, home: tmp)
    }()

    private func state(sections: Bool, section: RemotePages.SettingsSection = .general) -> RemotePages.State {
        var state = RemotePages.State(profile: profile, role: .activeAlone, section: section)
        state.offersSections = sections
        return state
    }

    private func sectionHeading(_ block: UIBlock) -> String? {
        guard case .heading(let heading) = block.content, heading.section == true else { return nil }
        return heading.text.text(for: "en")
    }

    private func textBlock(_ block: UIBlock) -> String? {
        guard case .text(let text) = block.content else { return nil }
        return text.text.text(for: "en")
    }

    private func toggleHelp(_ tree: UITree, _ id: String) -> UIText?? {
        for block in tree.blocks where block.id == id {
            if case .toggle(let toggle) = block.content { return .some(toggle.help) }
        }
        return nil
    }

    /// A section's blocks as the tab page shows them: the page less its four
    /// tab buttons and the divider under them.
    private func tabPageSection(_ section: RemotePages.SettingsSection) -> [UIBlock] {
        let blocks = RemotePages.settingsPage(state(sections: false, section: section)).blocks
        XCTAssertEqual(blocks.prefix(4).map(\.id), Self.tabIDs.map(Optional.some))
        XCTAssertEqual(blocks[4].type, "divider")
        return Array(blocks.dropFirst(5))
    }

    // MARK: - With ui.sections

    func testWithSectionsThePageHasNoTabsAndEverySectionUnderItsHeading() throws {
        let tree = RemotePages.settingsPage(state(sections: true))
        let ids = tree.blocks.compactMap(\.id)
        for tab in Self.tabIDs {
            XCTAssertFalse(ids.contains(tab), "\(tab) is still on the page")
        }

        let headingIndexes = tree.blocks.indices.filter { sectionHeading(tree.blocks[$0]) != nil }
        XCTAssertEqual(
            headingIndexes.map { sectionHeading(tree.blocks[$0]) },
            ["General", "Pairing & Bridge", "Notifications", "Integrations"]
        )
        // The page opens with the first section's heading: no tabs, and no
        // divider where they were.
        XCTAssertEqual(headingIndexes.first, 0)
        guard headingIndexes.count == RemotePages.SettingsSection.allCases.count else { return }

        for (n, section) in RemotePages.SettingsSection.allCases.enumerated() {
            let start = headingIndexes[n] + 1
            let end = n + 1 < headingIndexes.count ? headingIndexes[n + 1] : tree.blocks.count
            let drawn = Array(tree.blocks[start..<end])
            var expected = tabPageSection(section)
            if section == .notifications {
                // The caption under the heading moves into the toggle's help.
                expected.removeAll { textBlock($0)?.hasPrefix("Publishes high-priority push notifications") == true }
                XCTAssertEqual(drawn.map(\.id), expected.map(\.id), "\(section)")
                XCTAssertEqual(drawn.map(\.type), expected.map(\.type), "\(section)")
            } else {
                XCTAssertEqual(drawn, expected, "\(section) is not the tab page's section")
            }
        }
    }

    func testWithSectionsTheNotificationsCaptionIsTheToggleHelp() throws {
        let tabPage = RemotePages.settingsPage(state(sections: false, section: .notifications))
        let caption = try XCTUnwrap(
            tabPage.blocks.compactMap(textBlock).first { $0.hasPrefix("Publishes high-priority push notifications") }
        )

        let page = RemotePages.settingsPage(state(sections: true))
        XCTAssertEqual(toggleHelp(page, RemotePages.Block.notifyEnabledToggle), .some(.plain(caption)))
        XCTAssertFalse(page.blocks.compactMap(textBlock).contains(caption), "the caption is drawn twice")

        // An app without sections still shows it as text, and no help.
        XCTAssertEqual(toggleHelp(tabPage, RemotePages.Block.notifyEnabledToggle), .some(nil))
    }

    func testWithSectionsNoBlockIDRepeats() {
        let tree = RemotePages.settingsPage(largestState(sections: true))
        let ids = tree.blocks.compactMap(\.id)
        XCTAssertEqual(ids.count, Set(ids).count, "repeated ids: \(ids)")
    }

    // MARK: - Without ui.sections

    func testWithoutSectionsThePageIsTheTabPage() {
        for section in RemotePages.SettingsSection.allCases {
            let tree = RemotePages.settingsPage(state(sections: false, section: section))
            XCTAssertEqual(tree.blocks.prefix(4).map(\.id), Self.tabIDs.map(Optional.some))
            for (n, tab) in tree.blocks.prefix(4).enumerated() {
                guard case .button(let button) = tab.content else { return XCTFail("tab \(n) is not a button") }
                XCTAssertEqual(button.style, RemotePages.SettingsSection.allCases[n] == section ? .prominent : nil)
            }
            XCTAssertEqual(tree.blocks[4].type, "divider")
            XCTAssertTrue(tree.blocks.allSatisfy { sectionHeading($0) == nil }, "a section heading on an older app")
            for block in tree.blocks {
                switch block.content {
                case .heading(let heading): XCTAssertNil(heading.section)
                case .toggle(let toggle): XCTAssertNil(toggle.help)
                case .field(let field): XCTAssertNil(field.help)
                default: break
                }
            }
        }
    }

    // MARK: - Limits

    /// Everything on at once: a notice, the extension chosen over a
    /// standalone setup, a QR pairing session open while Tailscale's caption
    /// shows, an unpair being confirmed, a phone with tools, both tokens and
    /// every integration set.
    private func largestState(sections: Bool) -> RemotePages.State {
        let url = QRPairing.pageURL(address: "100.124.228.116", code: "482917")!
        var state = RemotePages.State(profile: profile, role: .activeChosen)
        state.offersSections = sections
        state.notice = String(repeating: "A notice that runs long. ", count: 8)
        state.activeQR = RemotePages.ActiveQRSession(
            code: "482917",
            address: "100.124.228.116",
            url: url,
            pngDataURL: QRPairing.pngDataURL(for: url.absoluteString)!,
            expiresAt: Date().addingTimeInterval(300)
        )
        state.tailscaleAddress = nil
        state.isPairedOnDisk = true
        state.confirmingUnpair = true
        state.hasNtfyToken = true
        state.hasPrometheusToken = true
        state.permissionHookInstalled = true
        state.snapshot = StatusSnapshot(
            state: .running(version: "1.9.1"),
            health: AgentHealth(ok: true, agentVersion: "1.9.1", paired: true,
                                notify: .init(configured: true, enabled: true)),
            phone: PhoneLink(connected: true, device: .init(model: "Pixel Fold", android: "16"),
                             tools: (1...40).map { "phone.tool\($0)" }),
            tailnetReachable: false
        )
        var settings = RemoteSettings()
        settings.ntfyURL = "https://ntfy.example.dev"
        settings.ntfyTopic = "vitruvian-remote"
        settings.execDir = "~/Workspace/vitruvian-core"
        settings.ghExtraRepos = (1...20).map { "owner/repo\($0)" }.joined(separator: ",")
        settings.kubeconfig = "~/.kube/cluster.yaml"
        settings.kubeContext = "homelab"
        settings.prometheusURL = "https://grafana.example.dev/api/datasources/proxy/uid/Prometheus"
        state.settings = settings
        return state
    }

    func testTheLargestPageFitsTheProtocolLimits() throws {
        let encoder = JSONEncoder()
        for sections in [true, false] {
            let tree = RemotePages.settingsPage(largestState(sections: sections))
            let bytes = try encoder.encode(tree).count
            print("settings page, sections=\(sections): \(tree.blocks.count) blocks, \(bytes) bytes")
            XCTAssertLessThanOrEqual(tree.blocks.count, UILimits.maxBlocks)
            XCTAssertLessThanOrEqual(bytes, UILimits.maxTreeBytes)
            if sections {
                XCTAssertEqual(tree.blocks.compactMap(sectionHeading).count, 4)
            }
        }
    }

    // MARK: - Controller

    private func controller() throws -> (RemoteToolController, URL) {
        let tmp = FileManager.default.temporaryDirectory
            .appendingPathComponent("remote-sections-\(UUID().uuidString)", isDirectory: true)
        let dataDir = tmp.appendingPathComponent("data", isDirectory: true)
        let toolDir = tmp.appendingPathComponent("tool", isDirectory: true)
        try FileManager.default.createDirectory(at: dataDir, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: toolDir.appendingPathComponent("bin"), withIntermediateDirectories: true)
        let controller = RemoteToolController.fromEnvironment(
            env: [
                "REMOTETOOL_HOME": tmp.path,
                "REMOTETOOL_DATA_FOLDER": dataDir.path,
                "REMOTETOOL_TOOL_FOLDER": toolDir.path,
                "REMOTETOOL_AGENT_COMMAND": "",
                "REMOTETOOL_FAKE_STATUS": "paired",
                "REMOTETOOL_TAILSCALE_ADDRESS": "100.124.228.116",
                "REMOTETOOL_STANDALONE_INSTALLED": "0",
            ],
            programPath: toolDir.appendingPathComponent("bin/tool").path
        )
        return (controller, tmp)
    }

    func testTheControllerSaysWhetherTheAppDrawsSections() throws {
        let (controller, tmp) = try controller()
        defer { try? FileManager.default.removeItem(at: tmp) }
        XCTAssertFalse(controller.currentState().offersSections)
        controller.offersSections = true
        XCTAssertTrue(controller.currentState().offersSections)
    }

    func testWithSectionsAStaleTabTapChangesNothing() throws {
        let (controller, tmp) = try controller()
        defer { try? FileManager.default.removeItem(at: tmp) }
        controller.offersSections = true
        // Leave a notice up, so a tap that cleared it would show.
        _ = controller.handleSettingsEvent(
            PanelEvent(block: RemotePages.Block.intervalSeconds, kind: .submit, value: .string("999"))
        )
        let notice = try XCTUnwrap(controller.notice)

        for tab in Self.tabIDs {
            XCTAssertEqual(controller.handleSettingsEvent(PanelEvent(block: tab, kind: .tap)), .keep, tab)
            XCTAssertEqual(controller.section, .general, tab)
            XCTAssertEqual(controller.notice, notice, tab)
        }
    }

    func testWithoutSectionsATabTapSwitchesTheSection() throws {
        let (controller, tmp) = try controller()
        defer { try? FileManager.default.removeItem(at: tmp) }
        let answer = controller.handleSettingsEvent(PanelEvent(block: RemotePages.Block.tabIntegrations, kind: .tap))
        XCTAssertEqual(controller.section, .integrations)
        guard case .page(let tree) = answer else { return XCTFail("no page: \(answer)") }
        XCTAssertEqual(tree, RemotePages.settingsPage(controller.currentState()))
    }
}
