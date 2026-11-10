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

/// The choice, run from the app (design 7.4 and 7.7): the same steps as the
/// extension's pages, in the app's windows. Step 2 shows both sides and
/// copies or keeps; then the choice is written, the hooks follow it, and
/// the side not chosen goes quiet.
///
/// Forwards every step to the unified switch path in `SettingsActions`.
@MainActor
public final class AppSwitch: ObservableObject {
    public enum Step: Equatable {
        /// Step 2: both sides, then copy or keep.
        case compare(DoorCompare)
        /// The app was chosen: how to remove the extension.
        case appChosen
        /// The extension was chosen: this app is quiet; its two offers.
        case extensionChosen(Offers)
    }

    /// After choosing the extension: what happens on Done.
    public struct Offers: Equatable, Sendable {
        /// Turn off the app's Open at Login. Ticked by default.
        public var loginItem = true
        /// Move HomeSpeaker.app to the Trash. Not ticked by default.
        public var trash = false
        public init(loginItem: Bool = true, trash: Bool = false) {
            self.loginItem = loginItem
            self.trash = trash
        }
    }

    public struct Parts {
        /// The app's files.
        public var appProfile: HomeSpeakerProfile
        /// Where the coding agents keep their files.
        public var home: URL
        public var now: () -> Date
        /// `DoorCopy.copy`.
        public var copy: (HomeSpeakerProfile, HomeSpeakerProfile) throws -> CopyReport
        /// Tells the side that took a copy to re-read its sign-ins, under
        /// that side's names.
        public var credentialsChangedIn: (HomeSpeakerProfile) -> Void
        public var turnOffLoginItem: () throws -> Void
        /// Moves this app to the Trash, never deleting it.
        public var moveToTrash: () throws -> Void
        public var quit: () -> Void
        /// Opens Vitruvian; false when it could not.
        public var openVitruvian: () -> Bool

        public init(
            appProfile: HomeSpeakerProfile, home: URL, now: @escaping () -> Date,
            copy: @escaping (HomeSpeakerProfile, HomeSpeakerProfile) throws -> CopyReport,
            credentialsChangedIn: @escaping (HomeSpeakerProfile) -> Void,
            turnOffLoginItem: @escaping () throws -> Void, moveToTrash: @escaping () throws -> Void,
            quit: @escaping () -> Void, openVitruvian: @escaping () -> Bool
        ) {
            self.appProfile = appProfile
            self.home = home
            self.now = now
            self.copy = copy
            self.credentialsChangedIn = credentialsChangedIn
            self.turnOffLoginItem = turnOffLoginItem
            self.moveToTrash = moveToTrash
            self.quit = quit
            self.openVitruvian = openVitruvian
        }
    }

    /// The step the person is on; nil before they tap anything.
    @Published public private(set) var step: Step?
    /// What the last step did, a sentence each.
    @Published public private(set) var report: [String] = []

    public let door: AppDoor
    private let parts: Parts

    public init(door: AppDoor, parts: Parts) {
        self.door = door
        self.parts = parts
    }

    /// Use the extension is offered only for an extension that runs without
    /// the app (1.19 on: the mark in its block), and never by an app in
    /// the Trash.
    public var canChooseExtension: Bool {
        !door.plan.inTrash && door.extensionInstalled
    }

    /// The one in use, once the person has chosen and both are installed.
    public var inUse: HomeSpeakerProfile.Door? {
        guard door.extensionInstalled, door.record?.chosen != nil else { return nil }
        return door.plan.role.isQuiet ? .extension : .app
    }

    private static func other(of side: HomeSpeakerProfile.Door) -> HomeSpeakerProfile.Door {
        side == .app ? .extension : .app
    }

    private var seam: SeamAdapter {
        SeamAdapter(door: door, parts: parts)
    }

    /// Step 2 for choosing `side`: what the other one has, beside it.
    public func choose(_ side: HomeSpeakerProfile.Door) {
        begin(from: Self.other(of: side), into: side, purpose: .choose)
    }

    /// General's "Copy settings from the other", into the one in use.
    public func copyAgain() {
        guard let inUse else { return }
        begin(from: Self.other(of: inUse), into: inUse, purpose: .copyOnly)
    }

    private func begin(from: HomeSpeakerProfile.Door, into: HomeSpeakerProfile.Door, purpose: DoorCompare.Purpose) {
        guard !door.plan.inTrash, canChooseExtension else { return }
        do {
            guard let compare = try SettingsActions.beginSwitch(
                from: from,
                into: into,
                purpose: purpose,
                seam: seam
            ) else {
                report = [DoorWords.extensionNotFound]
                return
            }
            report = []
            step = .compare(compare)
        } catch let refused as SettingsActions.SwitchRefused {
            report = [refused.message]
        } catch {
            report = [error.localizedDescription]
        }
    }

    /// Back: nothing is committed before Copy or Keep.
    public func back() {
        if case .compare? = step { step = nil }
    }

    /// Copy or Keep, then, when choosing, the rest in order (design 7.6),
    /// forwarded to `SettingsActions.finishSwitch`.
    public func finish(copy: Bool) {
        guard case .compare(let compare) = step else { return }
        switch SettingsActions.finishSwitch(compare: compare, copy: copy, seam: seam) {
        case .choiceChanged(let lines):
            step = nil
            report = lines
        case .abortedInTrash:
            step = nil
        case .stayOnCompare(let updatedCompare, let lines):
            report = lines
            step = .compare(updatedCompare)
        case .copiedOnly(let lines):
            report = lines
            step = nil
        case .appChosen(let lines):
            report = lines
            step = .appChosen
        case .extensionChosen(let offers, let lines):
            report = lines
            step = .extensionChosen(offers)
        }
    }

    public func setLoginItem(_ on: Bool) {
        guard case .extensionChosen(var offers) = step else { return }
        offers.loginItem = on
        step = .extensionChosen(offers)
    }

    public func setTrash(_ on: Bool) {
        guard case .extensionChosen(var offers) = step else { return }
        offers.trash = on
        step = .extensionChosen(offers)
    }

    /// Done. After choosing the extension: the offers as ticked, then the
    /// app quits; anything that failed is said, and it stays open. After
    /// choosing the app: the step closes.
    public func done() {
        guard case .extensionChosen(let offers) = step else {
            step = nil
            return
        }
        let result = SettingsActions.applySwitchOffers(offers, seam: seam)
        report = result.report
    }

    /// Opens Vitruvian, where the extension is.
    public func openVitruvian() {
        if !parts.openVitruvian() { report = [DoorWords.couldNotOpenVitruvian] }
    }

    // MARK: - Seam Adapter

    @MainActor
    private struct SeamAdapter: @preconcurrency SettingsActions.DoorSwitchSeam {
        let door: AppDoor
        let parts: Parts

        var me: HomeSpeakerProfile.Door { .app }
        var chosenBy: String { "HomeSpeaker app \(HomeSpeakerVersion.current)" }

        func now() -> Date { parts.now() }

        func inTrash() -> Bool { door.plan.inTrash }

        func readDoor() -> DoorRecord? { door.check.file.read() }

        func otherInstalled(record: DoorRecord?) -> Bool {
            OtherDoorPresence.extensionInstalled(record: record, fileExists: door.check.fileExists)
        }

        func profile(for side: HomeSpeakerProfile.Door, record: DoorRecord?) -> HomeSpeakerProfile? {
            side == .app ? parts.appProfile : AppStartup.extensionProfile(record: record)
        }

        func program(for side: HomeSpeakerProfile.Door, record: DoorRecord?) -> String? {
            switch side {
            case .app:
                // When choosing `.app` from the app, `door.refresh()` runs
                // `effects.repairHooks` using the app's own executable.
                return nil
            case .extension:
                guard OtherDoorPresence.extensionInstalled(record: record, fileExists: door.check.fileExists) else {
                    return nil
                }
                return record?.installedExtension?.program
            }
        }

        func copy(from source: HomeSpeakerProfile, to destination: HomeSpeakerProfile) throws -> CopyReport {
            try parts.copy(source, destination)
        }

        func credentialsChanged(in destination: HomeSpeakerProfile) {
            parts.credentialsChangedIn(destination)
        }

        func writeChoice(_ side: HomeSpeakerProfile.Door, at date: Date, chosenBy: String) throws {
            try door.check.file.update {
                $0.chosen = side
                $0.chosenAt = date
                $0.chosenBy = chosenBy
            }
        }

        func repointHooks(to side: HomeSpeakerProfile.Door, program: String) -> [String] {
            SettingsActions.repointStaleHooks(home: parts.home, to: program)
        }

        func refreshRole() {
            door.refresh()
        }

        func quitOther() -> Bool { true }

        func isOtherRunning() -> Bool { true }

        func openOtherAndEnableLoginItem() -> [String] { [] }

        func turnOffLoginItem() throws {
            try parts.turnOffLoginItem()
        }

        func moveToTrash() throws {
            try parts.moveToTrash()
        }

        func quitSelf() {
            parts.quit()
        }

        func openVitruvian() -> Bool {
            parts.openVitruvian()
        }
    }
}
