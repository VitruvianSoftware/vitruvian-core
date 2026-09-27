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
    @Published private(set) var opensAtLogin = SMAppService.mainApp.status == .enabled

    private let client = AgentClient()
    private let paths = AgentPaths()
    private let baseIcon: NSImage = {
        let img = NSImage(named: "MenuIcon") ?? NSImage(systemSymbolName: "antenna.radiowaves.left.and.right",
                                                         accessibilityDescription: nil)!
        img.isTemplate = true
        return img
    }()

    init() {
        Task { await pollForever() }
    }

    /// Full-strength glyph while the agent is healthy; faded when it is down
    /// or stale, so a glance at the menu bar answers "is the phone link up?".
    var icon: NSImage {
        // Faded too when only the phone's route is broken: that is the case
        // that looked fine from the Mac and dead from the phone.
        if snapshot.state.isHealthy, snapshot.tailnetReachable != false { return baseIcon }
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
        snapshot = await client.snapshot()
        opensAtLogin = SMAppService.mainApp.status == .enabled
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
            let r = await Runner.run(paths.binary, ["pair", code])
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
            let r = await Runner.run(paths.binary, ["pair", code])
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
            let r = await Runner.run(paths.binary, ["token", "--rotate"])
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
