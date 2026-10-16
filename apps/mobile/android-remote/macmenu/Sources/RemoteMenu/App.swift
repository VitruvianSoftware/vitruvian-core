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

import AppKit
import RemoteMenuCore
import ServiceManagement
import SwiftUI

@main
struct VitruvianRemoteApp: App {
    @StateObject private var model = RemoteModel()

    var body: some Scene {
        MenuBarExtra {
            MenuContent(model: model)
        } label: {
            Image(nsImage: model.icon)
                .accessibilityLabel("Vitruvian Remote: \(model.snapshot.agentLine)")
        }
        .menuBarExtraStyle(.menu)
    }
}

struct MenuContent: View {
    @ObservedObject var model: RemoteModel

    var body: some View {
        switch model.role {
        case .quietChosen, .quietAsking:
            Text("Vitruvian Extension in Use")
            Text("The Vitruvian Remote extension is managing port 7411.")
            Divider()
            Button("Use the Standalone App Instead…") { model.switchToStandaloneApp() }
            Button("Open Vitruvian") { model.openVitruvianApp() }
        case .activeAsking, .activeChosen, .activeAlone:
            if model.role == .activeAsking {
                Text("Both Standalone App & Extension Installed")
                Button("Use the Vitruvian Extension Instead…") { model.switchToExtension() }
                Button("Keep Using the Standalone App") { model.keepUsingStandaloneApp() }
                Divider()
            } else if model.role == .activeChosen {
                Button("Use the Vitruvian Extension Instead…") { model.switchToExtension() }
                Divider()
            }

            Text(model.snapshot.agentLine)
            if let phone = model.snapshot.phoneLine() {
                Text(phone)
            }
            if let tailnet = model.snapshot.tailnetLine {
                Text(tailnet)
            }
            if let notify = model.snapshot.notificationsLine {
                Text(notify)
            }

            Divider()

            switch model.snapshot.state {
            case .notInstalled:
                Button("Copy Install Command") { model.copyInstallCommand() }
            default:
                Button("Pair with QR Code…") { model.pairWithQR() }
                Button("Pair with a Code…") { model.pairPhone() }
                Button("Restart Agent") { model.restartAgent() }
                Button("Open Agent Log") { model.openLog() }
                Divider()
                Button("Unpair All Phones…") { model.unpairAll() }
            }
        }

        Divider()

        Toggle("Open at Login", isOn: Binding(
            get: { model.opensAtLogin },
            set: { model.setOpensAtLogin($0) }
        ))
        Button("Quit Vitruvian Remote") { NSApp.terminate(nil) }
            .keyboardShortcut("q")
    }
}

@MainActor
final class RemoteModel: ObservableObject {
    @Published private(set) var snapshot = StatusSnapshot(state: .down)
    @Published private(set) var role: RemoteRole = .activeAlone
    @Published private(set) var opensAtLogin = SMAppService.mainApp.status == .enabled

    private let profile = RemoteProfile.app()
    private let client: AgentClient
    private let paths = AgentPaths()
    private let baseIcon: NSImage = {
        let img = NSImage(named: "MenuIcon") ?? NSImage(systemSymbolName: "antenna.radiowaves.left.and.right",
                                                         accessibilityDescription: nil)!
        img.isTemplate = true
        return img
    }()

    init() {
        self.client = AgentClient(binaryURL: profile.agentBinaryURL)
        Task { await pollForever() }
    }

    /// Full-strength glyph while the agent is healthy; faded when it is down,
    /// stale, or quiet because the extension was chosen.
    var icon: NSImage {
        if role.isActive, snapshot.state.isHealthy, snapshot.tailnetReachable != false { return baseIcon }
        let faded = NSImage(size: baseIcon.size, flipped: false) { rect in
            self.baseIcon.draw(in: rect, from: .zero, operation: .sourceOver, fraction: 0.35)
            return true
        }
        faded.isTemplate = true
        return faded
    }

    private func pollForever() async {
        while !Task.isCancelled {
            await refresh()
            try? await Task.sleep(nanoseconds: 5_000_000_000)
        }
    }

    func refresh() async {
        let choice = RemoteChoiceFile.read(at: profile.choiceFileURL)
        let extInstalled = RemoteCoexistence.isExtensionInstalled(choice: choice)
        let currentRole = RemoteRole.resolve(
            for: .app,
            choice: choice,
            appInstalled: true,
            extensionInstalled: extInstalled
        )
        role = currentRole
        if currentRole.isActive {
            snapshot = await client.snapshot()
        } else {
            snapshot = StatusSnapshot(state: .down)
        }
        opensAtLogin = SMAppService.mainApp.status == .enabled
    }

    // MARK: Coexistence Actions

    func keepUsingStandaloneApp() {
        _ = try? RemoteChoiceFile.choose(.app, at: profile.choiceFileURL)
        Task { await refresh() }
    }

    func switchToStandaloneApp() {
        NSApp.activate(ignoringOtherApps: true)
        let choice = RemoteChoiceFile.read(at: profile.choiceFileURL)
        let alert = NSAlert()
        alert.messageText = "Use the Standalone Vitruvian Remote App?"
        alert.informativeText = "This will switch port 7411 back to the standalone LaunchAgent and put the Vitruvian extension into quiet mode."
        let copyCheckbox = NSButton(checkboxWithTitle: "Copy pairing, tokens, and settings from the Vitruvian extension", target: nil, action: nil)
        copyCheckbox.state = .on
        alert.accessoryView = copyCheckbox
        alert.addButton(withTitle: "Use Standalone App")
        alert.addButton(withTitle: "Cancel")
        guard alert.runModal() == .alertFirstButtonReturn else { return }

        if copyCheckbox.state == .on,
           let extProfile = RemoteCoexistence.extensionProfile(from: choice)
        {
            _ = try? RemoteDataCopy.copy(from: extProfile, to: profile)
        }
        _ = try? RemoteChoiceFile.choose(.app, at: profile.choiceFileURL)
        let sup = AgentSupervisor(profile: profile)
        let settings = RemoteSettingsStore(profile: profile).load()
        _ = sup.restartAgent(settings: settings)
        Task { await refresh() }
    }

    func switchToExtension() {
        NSApp.activate(ignoringOtherApps: true)
        let choice = RemoteChoiceFile.read(at: profile.choiceFileURL)
        let alert = NSAlert()
        alert.messageText = "Switch to the Vitruvian Remote Extension?"
        alert.informativeText = "The Vitruvian extension will manage the agent on port 7411, and this standalone app will quit."
        let copyCheckbox = NSButton(checkboxWithTitle: "Copy pairing, tokens, and settings into the extension", target: nil, action: nil)
        copyCheckbox.state = .on
        alert.accessoryView = copyCheckbox
        alert.addButton(withTitle: "Switch & Quit Standalone App")
        alert.addButton(withTitle: "Cancel")
        guard alert.runModal() == .alertFirstButtonReturn else { return }

        if copyCheckbox.state == .on,
           let extProfile = RemoteCoexistence.extensionProfile(from: choice)
        {
            _ = try? RemoteDataCopy.copy(from: profile, to: extProfile)
        }
        _ = try? RemoteChoiceFile.choose(.extension, at: profile.choiceFileURL)
        try? SMAppService.mainApp.unregister()
        let sup = AgentSupervisor(profile: profile)
        sup.stopStandaloneAgent(disableLaunchAgentAtLogin: true)
        NSApp.terminate(nil)
    }

    func openVitruvianApp() {
        let candidates = [
            URL(fileURLWithPath: "/Applications/Vitruvian.app"),
            FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Applications/Vitruvian.app"),
        ]
        if let appURL = candidates.first(where: { FileManager.default.fileExists(atPath: $0.path) }) {
            NSWorkspace.shared.openApplication(at: appURL, configuration: NSWorkspace.OpenConfiguration())
        }
    }

    // MARK: Actions

    func pairPhone() {
        NSApp.activate(ignoringOtherApps: true)
        let alert = NSAlert()
        alert.messageText = "Pair a Phone"
        alert.informativeText = "Open Vitruvian Remote on the phone and type the six-digit code it shows. The code works once, for five minutes."
        let field = NSTextField(frame: NSRect(x: 0, y: 0, width: 200, height: 24))
        field.placeholderString = "123456"
        alert.accessoryView = field
        alert.addButton(withTitle: "Pair")
        alert.addButton(withTitle: "Cancel")
        alert.window.initialFirstResponder = field
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        guard let code = PairCode.normalize(field.stringValue) else {
            showError("That isn't a six-digit code", "Type exactly the six digits the phone shows.")
            return
        }
        Task {
            let r = await Runner.run(profile.agentBinaryURL, ["pair", code])
            if r.succeeded {
                showInfo("Pairing is open", "The phone showing \(code) will connect within a few seconds.")
            } else {
                showError("Pairing failed", r.firstErrorLine ?? "The agent exited with code \(r.exitCode).")
            }
            await refresh()
        }
    }

    /// Opens a pairing window for a code this Mac chooses, then shows it as a
    /// QR code pointing at the agent's /pair page over Tailscale.
    func pairWithQR() {
        guard let address = QRPairing.tailscaleAddress() else {
            showError("No Tailscale address",
                      "The phone reaches this Mac over Tailscale, and Tailscale isn't up here. Start it, or use Pair with a Code.")
            return
        }
        let code = QRPairing.newCode()
        guard let url = QRPairing.pageURL(address: address, code: code) else { return }
        Task {
            // A QR the phone can't open is worse than none: check first.
            guard await client.answers(on: address) else {
                showError("The phone can't reach the agent",
                          "The agent isn't answering on this Mac's Tailscale address (\(address)). Choose Restart Agent, then try again.")
                return
            }
            let r = await Runner.run(profile.agentBinaryURL, ["pair", code])
            guard r.succeeded else {
                showError("Couldn't open pairing", r.firstErrorLine ?? "The agent exited with code \(r.exitCode).")
                return
            }
            // The agent's window is five minutes from now; show the same.
            QRWindowController.shared.show(url: url, address: address, expires: Date().addingTimeInterval(5 * 60))
        }
    }

    func restartAgent() {
        Task {
            let r = await Runner.run(URL(fileURLWithPath: "/bin/launchctl"), AgentPaths.restartArguments(uid: getuid()))
            if !r.succeeded {
                showError("Couldn't restart the agent", r.firstErrorLine ?? "launchctl exited with code \(r.exitCode).")
            }
            try? await Task.sleep(nanoseconds: 1_500_000_000)
            await refresh()
        }
    }

    func openLog() {
        guard FileManager.default.fileExists(atPath: paths.log.path) else {
            showError("No log yet", "The agent hasn't written \(paths.log.path).")
            return
        }
        let console = URL(fileURLWithPath: "/System/Applications/Utilities/Console.app")
        NSWorkspace.shared.open([paths.log], withApplicationAt: console, configuration: NSWorkspace.OpenConfiguration())
    }

    func unpairAll() {
        NSApp.activate(ignoringOtherApps: true)
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = "Unpair every phone?"
        alert.informativeText = "Every paired phone loses access immediately and has to pair again. Use this if a phone is lost."
        alert.addButton(withTitle: "Unpair All")
        alert.addButton(withTitle: "Cancel")
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        Task {
            // stdout carries the new token: it is dropped here, never shown.
            let r = await Runner.run(profile.agentBinaryURL, ["token", "--rotate"])
            if r.succeeded {
                showInfo("All phones unpaired", "Pair a phone again whenever you're ready.")
            } else {
                showError("Couldn't unpair", r.firstErrorLine ?? "The agent exited with code \(r.exitCode).")
            }
            await refresh()
        }
    }

    func copyInstallCommand() {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(AgentPaths.installCommand, forType: .string)
    }

    func setOpensAtLogin(_ on: Bool) {
        do {
            if on { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
        } catch {
            showError("Couldn't change Open at Login", error.localizedDescription)
        }
        opensAtLogin = SMAppService.mainApp.status == .enabled
    }

    // MARK: Dialogs

    private func showInfo(_ title: String, _ text: String) {
        present(title, text, style: .informational)
    }

    private func showError(_ title: String, _ text: String) {
        present(title, text, style: .warning)
    }

    private func present(_ title: String, _ text: String, style: NSAlert.Style) {
        NSApp.activate(ignoringOtherApps: true)
        let alert = NSAlert()
        alert.alertStyle = style
        alert.messageText = title
        alert.informativeText = text
        alert.runModal()
    }
}
