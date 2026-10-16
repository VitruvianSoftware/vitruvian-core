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
/// - Choosing the app: the extension goes quiet by itself (it reads the
///   choice file), so the app says how to remove it, with Open Vitruvian.
/// - Choosing the extension: the app goes quiet at once, then offers to
///   turn its own Open at Login off (ticked) and to move itself to the
///   Trash (not ticked), and quits. It cannot start the extension, so it
///   offers Open Vitruvian too.
///
/// Every effect outside the files is handed in, so a test records it.
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
    public struct Offers: Equatable {
        /// Turn off the app's Open at Login. Ticked by default.
        public var loginItem = true
        /// Move HomeSpeaker.app to the Trash. Not ticked by default.
        public var trash = false
        public init() {}
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
        let record = door.check.file.read()
        guard let source = profile(from, record: record), let destination = profile(into, record: record) else { return }
        report = []
        step = .compare(DoorCompare(
            purpose: purpose, from: from, into: into,
            source: DoorSnapshot(profile: source), destination: DoorSnapshot(profile: destination),
            seenChoice: record?.chosen, seenChosenAt: record?.chosenAt))
    }

    private func profile(_ side: HomeSpeakerProfile.Door, record: DoorRecord?) -> HomeSpeakerProfile? {
        side == .app ? parts.appProfile : AppStartup.extensionProfile(record: record)
    }

    /// Back: nothing is committed before Copy or Keep.
    public func back() {
        if case .compare? = step { step = nil }
    }

    /// Copy or Keep, then, when choosing, the rest in order (design 7.6):
    /// the copy, the destination told, the choice written, the hooks
    /// pointed at the chosen program, then this app runs or goes quiet.
    public func finish(copy: Bool) {
        guard case .compare(var compare) = step else { return }
        // A choice made elsewhere since step 2 began (in the extension, say)
        // is never overridden.
        let record = door.check.file.read()
        if record?.chosen != compare.seenChoice || record?.chosenAt != compare.seenChosenAt {
            step = nil
            report = [DoorWords.choiceChanged]
            door.refresh()
            return
        }
        // An app in the Trash writes nothing; the extension must be there.
        guard !door.plan.inTrash else {
            step = nil
            return
        }
        guard OtherDoorPresence.extensionInstalled(record: record, fileExists: door.check.fileExists),
              let extensionProfile = AppStartup.extensionProfile(record: record),
              let extensionProgram = record?.installedExtension?.program else {
            compare.problem = DoorWords.extensionNotFound
            step = .compare(compare)
            return
        }
        let source = compare.from == .app ? parts.appProfile : extensionProfile
        let destination = compare.into == .app ? parts.appProfile : extensionProfile
        report = []
        compare.problem = nil
        if copy {
            do {
                report = try parts.copy(source, destination).lines
            } catch let partial as DoorCopyPartial {
                // Stopped part-way: say what came across and what did not,
                // and tell the destination if its sign-ins changed.
                if partial.signInsWritten { parts.credentialsChangedIn(destination) }
                report = partial.copied + partial.notCopied
                step = .compare(compare)
                return
            } catch {
                compare.problem = error.localizedDescription
                step = .compare(compare)
                return
            }
            parts.credentialsChangedIn(destination)
        }
        guard compare.purpose == .choose else {
            step = nil
            return
        }
        do {
            let now = parts.now()
            try door.check.file.update {
                $0.chosen = compare.into
                $0.chosenAt = now
                $0.chosenBy = "HomeSpeaker app \(HomeSpeakerVersion.current)"
            }
        } catch {
            compare.problem = error.localizedDescription
            step = .compare(compare)
            return
        }
        if compare.into == .extension {
            // The hooks go to the extension's program; the app's own repair
            // (on becoming active) covers the other way round.
            report += repointHooks(at: extensionProgram)
            door.refresh()
            step = .extensionChosen(Offers())
        } else {
            door.refresh()
            step = .appChosen
        }
    }

    /// Points every agent's HomeSpeaker hook that runs another program at
    /// `program`. An agent with no HomeSpeaker hook gets none. What could
    /// not be done, a sentence each.
    private func repointHooks(at program: String) -> [String] {
        let integration = AgentIntegration(home: parts.home, executablePath: program, bootout: { _ in })
        var problems: [String] = []
        for agent in CodingAgent.allCases where agent.supportsHook {
            guard case .stale = integration.status(of: agent).hook else { continue }
            do {
                try integration.installHook(for: agent)
            } catch {
                problems.append(error.localizedDescription)
            }
        }
        return problems
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
        var lines: [String] = []
        var failed = false
        if offers.loginItem {
            do {
                try parts.turnOffLoginItem()
                lines.append(DoorWords.loginItemOff)
            } catch {
                failed = true
                lines.append(error.localizedDescription)
            }
        }
        if offers.trash {
            do {
                try parts.moveToTrash()
                lines.append(DoorWords.inTheTrash)
            } catch {
                failed = true
                lines.append(error.localizedDescription)
            }
        }
        report = lines
        guard !failed else { return }
        parts.quit()
    }

    /// Opens Vitruvian, where the extension is.
    public func openVitruvian() {
        if !parts.openVitruvian() { report = [DoorWords.couldNotOpenVitruvian] }
    }
}
