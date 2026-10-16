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
import Combine
import SwiftUI
import HomeSpeakerCore

// The choice, in the app (design 7.4): a small window at launch while the
// app asks or is quiet, a line at the top of the menu bar's window, and
// Settings > General's "Which HomeSpeaker" row. Every sentence is
// `DoorWords`, the same as the extension's pages.

/// The window that asks, and carries the steps.
@MainActor
final class DoorWindow {
    static let shared = DoorWindow()

    private var window: NSWindow?
    private var watching: AnyCancellable?

    private init() {
        // Going quiet while running (a choice made in the extension) shows
        // the window too, so the person is told.
        watching = AppSide.shared.door.$plan
            .removeDuplicates()
            .dropFirst()
            .sink { [weak self] plan in
                if plan.showsQuiet { self?.show() }
            }
    }

    /// At launch: the window while the app asks or is quiet.
    func showIfNeeded(_ plan: AppStartup.Plan) {
        if plan.asks || plan.showsQuiet { show() }
    }

    func show() {
        if window == nil {
            let host = NSHostingController(rootView: DoorCard(door: AppSide.shared.door, switcher: AppSide.shared.switcher)
                .padding(20)
                .frame(width: 460))
            let window = NSWindow(contentViewController: host)
            window.title = "HomeSpeaker"
            window.styleMask = [.titled, .closable]
            window.isReleasedWhenClosed = false
            window.center()
            self.window = window
        }
        NSApp.activate()
        window?.makeKeyAndOrderFront(nil)
    }
}

/// The card: step 1, step 2, what follows a choice, and the quiet card.
struct DoorCard: View {
    @ObservedObject var door: AppDoor
    @ObservedObject var switcher: AppSwitch
    /// In the menu: step 1 only, and the steps go to the window.
    var compact = false

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            switch switcher.step {
            case nil:
                if door.plan.showsQuiet {
                    quiet
                } else if door.plan.asks {
                    ask
                } else if door.plan.inTrash {
                    Label(DoorWords.inTheTrash, systemImage: "trash")
                }
            case .compare(let compare):
                if compact { inWindow } else { CompareStep(compare: compare, switcher: switcher) }
            case .appChosen:
                if compact { inWindow } else { appChosen }
            case .extensionChosen(let offers):
                if compact { inWindow } else { extensionChosen(offers) }
            }
            ForEach(Array(switcher.report.enumerated()), id: \.offset) { _, line in
                Text(line).font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func start(_ action: () -> Void) {
        action()
        if compact { DoorWindow.shared.show() }
    }

    private var ask: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(DoorWords.heading).font(.headline)
            Text(DoorWords.body).font(.callout).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            HStack {
                if switcher.canChooseExtension {
                    Button(DoorWords.use(.extension)) { start { switcher.choose(.extension) } }
                        .buttonStyle(.borderedProminent)
                }
                Button(DoorWords.use(.app)) { start { switcher.choose(.app) } }
            }
        }
    }

    private var quiet: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label(DoorWords.quiet(other: .extension), systemImage: "moon.zzz")
                .fixedSize(horizontal: false, vertical: true)
            HStack {
                Button(DoorWords.useThis) { start { switcher.choose(.app) } }
                    .buttonStyle(.borderedProminent)
                Button(DoorWords.quit) { NSApplication.shared.terminate(nil) }
            }
        }
    }

    /// In the menu while a step runs in the window.
    private var inWindow: some View {
        Button(DoorWords.heading) { DoorWindow.shared.show() }
    }

    private var appChosen: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(DoorWords.appChosen).fixedSize(horizontal: false, vertical: true)
            HStack {
                Button(DoorWords.openVitruvian) { switcher.openVitruvian() }
                Button(DoorWords.done) { switcher.done() }.buttonStyle(.borderedProminent)
            }
        }
    }

    private func extensionChosen(_ offers: AppSwitch.Offers) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(DoorWords.quiet(other: .extension)).fixedSize(horizontal: false, vertical: true)
            Toggle(DoorWords.turnOffLoginItem, isOn: Binding(get: { offers.loginItem }, set: { switcher.setLoginItem($0) }))
            Toggle(DoorWords.moveToTrash, isOn: Binding(get: { offers.trash }, set: { switcher.setTrash($0) }))
            Text(DoorWords.trashWarning).font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            HStack {
                Button(DoorWords.openVitruvian) { switcher.openVitruvian() }
                Button(DoorWords.done) { switcher.done() }.buttonStyle(.borderedProminent)
            }
        }
    }
}

/// Step 2: both sides, a row a fact, never a token; then copy or keep, the
/// suggested one first, and Back.
struct CompareStep: View {
    let compare: DoorCompare
    let switcher: AppSwitch

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(compare.purpose == .choose ? DoorWords.heading : DoorWords.copySettingsFrom(compare.from)).font(.headline)
            let app = compare.from == .app ? compare.source : compare.destination
            let ext = compare.from == .extension ? compare.source : compare.destination
            Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 4) {
                GridRow {
                    Text("")
                    Text("App").font(.caption.bold())
                    Text("Extension").font(.caption.bold())
                }
                ForEach(DoorSummary.facts, id: \.title) { fact in
                    GridRow {
                        Text(fact.title).font(.caption)
                        Text(fact.value(app)).font(.caption).foregroundStyle(.secondary)
                        Text(fact.value(ext)).font(.caption).foregroundStyle(.secondary)
                    }
                }
            }
            if compare.signsOut {
                Label(DoorWords.signsOut(from: compare.from, into: compare.into), systemImage: "exclamationmark.triangle.fill")
                    .foregroundStyle(.orange)
                    .fixedSize(horizontal: false, vertical: true)
            }
            HStack {
                if compare.suggestion == .copyFromOther {
                    copyButton.buttonStyle(.borderedProminent)
                    keepButton
                } else {
                    keepButton.buttonStyle(.borderedProminent)
                    copyButton
                }
                Spacer()
                Button(DoorWords.back) { switcher.back() }
            }
            Text(DoorCopy.copyNote).font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            if let problem = compare.problem {
                Label(problem, systemImage: "exclamationmark.triangle.fill")
                    .foregroundStyle(.orange)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private var copyButton: some View {
        Button(DoorWords.copyFrom(compare.from)) { switcher.finish(copy: true) }
    }

    private var keepButton: some View {
        Button(DoorWords.keep) { switcher.finish(copy: false) }
    }
}

/// Settings > General: which one this Mac uses, switch, and copy again
/// (design 7.7), quiet or not: a quiet app is where the person changed
/// something they now want copied. While nobody has picked, or a step is
/// under way, or the app is in the Trash, the card.
struct WhichHomeSpeakerSection: View {
    @ObservedObject var door: AppDoor
    @ObservedObject var switcher: AppSwitch

    var body: some View {
        if door.plan.asks || switcher.step != nil || door.plan.inTrash {
            Section(DoorWords.which) {
                DoorCard(door: door, switcher: switcher, compact: true)
            }
        } else if let inUse = switcher.inUse {
            let other: HomeSpeakerProfile.Door = inUse == .app ? .extension : .app
            Section(DoorWords.which) {
                Text(DoorWords.uses(inUse))
                HStack {
                    Button(DoorWords.useInstead(other)) {
                        switcher.choose(other)
                        DoorWindow.shared.show()
                    }
                    Button(DoorWords.copySettingsFrom(other)) {
                        switcher.copyAgain()
                        DoorWindow.shared.show()
                    }
                }
                ForEach(Array(switcher.report.enumerated()), id: \.offset) { _, line in
                    Text(line).font(.caption).foregroundStyle(.secondary)
                }
            }
        }
    }
}
