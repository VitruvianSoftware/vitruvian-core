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
import BridgeCore
import SwiftUI

// The window of the bridge: one line saying Nexus Agent is now Vitruvian Code,
// and what it is doing. On a failure, the error and a button to the download page.

let downloadPage = URL(string: "https://vitruviansoftware.dev/downloads/latest/vitruvian-code.dmg")!

@MainActor
final class Status: ObservableObject {
    @Published var line = "Starting…"
    @Published var error: String?
}

struct BridgeView: View {
    @ObservedObject var status: Status

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Nexus Agent is now Vitruvian Code")
                .font(.headline)
            if let error = status.error {
                Text(error)
                    .font(.callout)
                    .foregroundColor(.red)
                    .fixedSize(horizontal: false, vertical: true)
                HStack {
                    Button("Open the download page") { NSWorkspace.shared.open(downloadPage) }
                        .keyboardShortcut(.defaultAction)
                    Button("Quit") { NSApp.terminate(nil) }
                }
            } else {
                HStack(spacing: 8) {
                    ProgressView().controlSize(.small)
                    Text(status.line).font(.callout)
                }
            }
        }
        .padding(20)
        .frame(width: 380)
    }
}

@MainActor
final class Delegate: NSObject, NSApplicationDelegate {
    let status = Status()
    var window: NSWindow?

    func applicationDidFinishLaunching(_ notification: Notification) {
        let window = NSWindow(contentRect: .zero, styleMask: [.titled, .closable], backing: .buffered, defer: false)
        window.title = "Nexus Agent"
        window.contentView = NSHostingView(rootView: BridgeView(status: status))
        window.center()
        window.isReleasedWhenClosed = false
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        self.window = window
        Task { await run() }
    }

    func run() async {
        let bundle = Bundle.main.bundleURL
        let version = (Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String) ?? ""
        let home = FileManager.default.homeDirectoryForCurrentUser
        let destination = InstallLocation.destination(
            bundleURL: bundle, home: home, isWritable: { FileManager.default.isWritableFile(atPath: $0.path) })
        let scratch = FileManager.default.temporaryDirectory
            .appendingPathComponent("vitruvian-code-bridge-\(UUID().uuidString)", isDirectory: true)
        let status = self.status
        let bridge = Bridge(
            version: version, network: GitHubNetwork(), installer: Installer(unzip: Installer.ditto),
            destination: destination, scratch: scratch,
            progress: { line in Task { @MainActor in status.line = line } })

        let result = await bridge.installAndHandOver(
            open: { app in NSWorkspace.shared.openApplication(at: app, configuration: NSWorkspace.OpenConfiguration()) },
            trashSelf: { try FileManager.default.trashItem(at: bundle, resultingItemURL: nil) })
        switch result {
        case .success:
            // Give the new app a moment to start before this one goes.
            try? await Task.sleep(nanoseconds: 1_500_000_000)
            NSApp.terminate(nil)
        case .failure(let error):
            status.error = error.localizedDescription
        }
    }
}

@main
enum BridgeApp {
    @MainActor
    static func main() {
        let application = NSApplication.shared
        application.setActivationPolicy(.accessory)
        let delegate = Delegate()
        application.delegate = delegate
        application.run()
        _ = delegate
    }
}
