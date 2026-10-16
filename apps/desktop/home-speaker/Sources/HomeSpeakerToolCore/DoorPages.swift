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
import HomeSpeakerCore
import VitruvianToolKit
import VitruvianToolProtocol

// The extension's pages when the HomeSpeaker app is installed too (design
// 7.4 and 7.7): the choice card, the side-by-side summary before a copy,
// closing the app, the quiet card, and General's "Which HomeSpeaker" row.
// Pure functions of `Pages.Status.door`, as the rest of the pages are.

extension Pages {
    /// Which HomeSpeaker is in use, as the pages need it.
    public struct DoorState: Equatable {
        /// This HomeSpeaker: the extension, for the tool.
        public var me: HomeSpeakerProfile.Door
        public var role: DoorRole
        /// The other HomeSpeaker is installed.
        public var otherInstalled: Bool
        /// The step the person is on, once they have started one.
        public var step: DoorStep?
        /// What the last step did, a sentence each.
        public var report: [String]
        /// An app older than 1.19 is running while this side runs: it
        /// cannot hear the choice, so this side's chat monitor waits.
        public var oldAppRunning: Bool
        /// The app was opened when the person picked it, and has not been
        /// seen running yet.
        public var otherStarting: Bool

        public init(me: HomeSpeakerProfile.Door = .extension, role: DoorRole = .active, otherInstalled: Bool = false,
                    step: DoorStep? = nil, report: [String] = [], oldAppRunning: Bool = false, otherStarting: Bool = false) {
            self.me = me
            self.role = role
            self.otherInstalled = otherInstalled
            self.step = step
            self.report = report
            self.oldAppRunning = oldAppRunning
            self.otherStarting = otherStarting
        }

        /// The one in use, once the person has chosen and both are installed.
        public var inUse: HomeSpeakerProfile.Door? {
            guard otherInstalled else { return nil }
            switch role {
            case .active, .activeAsking: return me
            case .quiet(let other): return other
            case .waitingAsking: return nil
            }
        }
    }

    /// Where the person is, once they have tapped the card (design 7.4).
    public enum DoorStep: Equatable {
        /// Step 2: both sides side by side, then copy or keep.
        case compare(DoorCompare)
        /// The app has been asked to quit; waiting for it.
        case closing
        /// The person picked the app, which was not running: it is being
        /// opened, and its Open at Login turned back on.
        case opening
        /// Step 3: the app has quit (or not), and the two offers.
        case offers(DoorOffers)
    }

    /// Step 2: one side copied into the other, or not (shared with the app).
    public typealias DoorCompare = HomeSpeakerCore.DoorCompare

    /// Step 3, as `OtherAppPlan.forChoosingTheExtension` lays it out.
    public struct DoorOffers: Equatable {
        /// The app quit when asked.
        public var quit: Bool
        /// The app is older than 1.19: it will not hear the choice.
        public var oldApp: Bool
        public var loginItem: Bool
        /// False for an old app: its login item must go.
        public var loginItemOptional: Bool
        public var trash: Bool
        /// Done was tapped and the offers are being carried out.
        public var working = false

        public init(quit: Bool, plan: [OtherAppPlan.Step]) {
            self.quit = quit
            oldApp = plan.contains(.oldAppWarning)
            loginItem = false
            loginItemOptional = true
            trash = false
            for step in plan {
                switch step {
                case .turnOffLoginItem(let ticked, let optional):
                    loginItem = ticked
                    loginItemOptional = optional
                case .moveToTrash(let ticked):
                    trash = ticked
                case .quit, .oldAppWarning:
                    break
                }
            }
        }
    }

    /// What the card and the row say (shared with the app).
    public typealias DoorWords = HomeSpeakerCore.DoorWords

    /// The quiet-hours choices: every half hour, "00:00" to "23:30".
    public static let halfHours: [String] = (0..<48).map { String(format: "%02d:%02d", $0 / 2, ($0 % 2) * 30) }

    // MARK: - The card

    /// At the top of the island and of General: the card while nobody has
    /// picked, then each step once the person has started one.
    static func doorCardBlocks(_ status: Status) -> [UIBlock] {
        let door = status.door
        switch door.step {
        case nil:
            if door.oldAppRunning, !door.role.isQuiet, door.role != .waitingAsking {
                // An app before 1.19 still runs: it reads chat, so this
                // side's monitor waits until it is quit.
                return [
                    row(nil, UIText.plain(OtherAppPlan.Step.oldAppWarning.text), icon: "exclamationmark.triangle.fill"),
                    button(Block.doorQuitAgain, UIText.plain(DoorWords.quitAgain), style: .prominent),
                ]
            }
            guard door.role == .waitingAsking else { return [] }
            return UITree {
                heading(UIText.plain(DoorWords.heading))
                text(UIText.plain(DoorWords.body), style: .secondary)
                button(Block.doorUseExtension, UIText.plain(DoorWords.use(.extension)), style: .prominent)
                button(Block.doorUseApp, UIText.plain(DoorWords.use(.app)))
            }.blocks
        case .compare(let compare):
            return compareBlocks(compare)
        case .closing:
            return [heading(UIText.plain(DoorWords.heading)), text(UIText.plain(DoorWords.quitting), style: .caption)]
        case .opening:
            return [heading(UIText.plain(DoorWords.heading)), text(UIText.plain(DoorWords.opening), style: .caption)]
        case .offers(let offers):
            return offerBlocks(offers)
        }
    }

    /// Step 2: both sides, a row a fact, never a token; then the two
    /// buttons, the suggested one first.
    static func compareBlocks(_ compare: DoorCompare) -> [UIBlock] {
        let copy = button(Block.doorCopy, UIText.plain(DoorWords.copyFrom(compare.from)),
                          style: compare.suggestion == .copyFromOther ? .prominent : nil)
        let keep = button(Block.doorKeep, UIText.plain(DoorWords.keep), style: compare.suggestion == .keep ? .prominent : nil)
        return UITree {
            heading(UIText.plain(compare.purpose == .choose ? DoorWords.heading : DoorWords.copySettingsFrom(compare.from)))
            summaryBlocks(compare)
            if compare.signsOut {
                row(nil, UIText.plain(DoorWords.signsOut(from: compare.from, into: compare.into)), icon: "exclamationmark.triangle.fill")
            }
            if compare.suggestion == .copyFromOther { [copy, keep] } else { [keep, copy] }
            button(Block.doorBack, UIText.plain(DoorWords.back))
            text(UIText.plain(DoorCopy.copyNote), style: .caption)
            if let problem = compare.problem {
                row(nil, UIText.plain(problem), icon: "exclamationmark.triangle.fill")
            }
        }.blocks
    }

    /// One row a fact: "App: … · Extension: …".
    static func summaryBlocks(_ compare: DoorCompare) -> [UIBlock] {
        let app = compare.from == .app ? compare.source : compare.destination
        let ext = compare.from == .extension ? compare.source : compare.destination
        return DoorSummary.facts.map { fact in
            row(nil, UIText.plain(fact.title), subtitle: UIText.plain("App: \(fact.value(app)) · Extension: \(fact.value(ext))"))
        }
    }

    /// Step 3: the app has quit, and the two offers as toggles.
    static func offerBlocks(_ offers: DoorOffers) -> [UIBlock] {
        UITree {
            heading(UIText.plain(DoorWords.heading))
            text(UIText.plain(offers.quit ? OtherAppPlan.Step.quit.text : DoorWords.didNotQuit))
            if offers.oldApp {
                row(nil, UIText.plain(OtherAppPlan.Step.oldAppWarning.text), icon: "exclamationmark.triangle.fill")
            }
            if !offers.quit {
                button(Block.doorQuitAgain, UIText.plain(DoorWords.quitAgain), enabled: !offers.working)
            }
            toggle(Block.doorLoginItem, UIText.plain(OtherAppPlan.Step.turnOffLoginItem(ticked: true, optional: true).text),
                   isOn: offers.loginItem, enabled: offers.loginItemOptional && !offers.working)
            // A running app is never moved: it is quit first.
            toggle(Block.doorTrash, UIText.plain(OtherAppPlan.Step.moveToTrash(ticked: false).text), isOn: offers.trash,
                   enabled: offers.quit && !offers.working)
            if let warning = OtherAppPlan.Step.moveToTrash(ticked: false).warning {
                text(UIText.plain(warning), style: .caption)
            }
            button(Block.doorDone, UIText.plain(DoorWords.done), style: .prominent, enabled: !offers.working)
        }.blocks
    }

    /// In place of the island's body while the other one is in use.
    static func quietCardBlocks(other: HomeSpeakerProfile.Door, starting: Bool = false) -> [UIBlock] {
        [
            row(nil, UIText.plain(starting ? DoorWords.starting : DoorWords.quiet(other: other)), icon: "moon.zzz"),
            button(Block.doorUseThis, UIText.plain(DoorWords.useThis), style: .prominent),
        ]
    }

    /// General's "Which HomeSpeaker" row, while both are installed and the
    /// person has chosen: switch, and copy again (design 7.7).
    static func whichBlocks(_ status: Status) -> [UIBlock] {
        guard status.door.step == nil, let inUse = status.door.inUse else { return [] }
        let other: HomeSpeakerProfile.Door = inUse == .app ? .extension : .app
        return UITree {
            heading(UIText.plain(DoorWords.which))
            text(UIText.plain(DoorWords.uses(inUse)))
            button(Block.doorSwitch, UIText.plain(DoorWords.useInstead(other)))
            button(Block.doorCopyAgain, UIText.plain(DoorWords.copySettingsFrom(other)))
        }.blocks
    }

    /// What the last step did, a caption a sentence.
    static func doorReportBlocks(_ status: Status) -> [UIBlock] {
        status.door.report.map { text(UIText.plain($0), style: .caption) }
    }

    /// Quiet hours: a choice of half hours where the app draws one, else
    /// the typed field. A time typed before, off the half hour, is kept
    /// and offered first, so the choice never quietly changes it.
    static func quietHourBlocks(_ status: Status) -> [UIBlock] {
        let start = status.config.quietHoursStart ?? "22:00"
        let end = status.config.quietHoursEnd ?? "07:00"
        guard status.offersChoice else {
            return [
                field(Block.quietStart, title: "From (HH:mm)", value: start),
                field(Block.quietEnd, title: "Until (HH:mm)", value: end),
            ]
        }
        func options(keeping value: String) -> [UIChoiceOption] {
            let times = halfHours.contains(value) ? halfHours : [value] + halfHours
            return times.map { UIChoiceOption(value: $0, title: UIText.plain($0)) }
        }
        return [
            choice(Block.quietStart, title: "From", value: start, options: options(keeping: start)),
            choice(Block.quietEnd, title: "Until", value: end, options: options(keeping: end)),
        ]
    }

    /// Why nothing reads chat, under Background Monitoring, by role: the
    /// extension is what reads it, so there is no app to open.
    static func notReadingLine(_ role: DoorRole) -> String {
        switch role {
        case .waitingAsking: return HomeSpeakerTool.pickFirst
        case .quiet(let other): return DoorWords.quiet(other: other)
        case .active, .activeAsking: return "Open HomeSpeaker to start: it is what reads the messages."
        }
    }
}

extension Pages.Block {
    // The choice card and its steps, the quiet card and General's row.
    public static let doorPrefix = "door."
    public static let doorUseExtension = "door.useExtension"
    public static let doorUseApp = "door.useApp"
    public static let doorCopy = "door.copy"
    public static let doorKeep = "door.keep"
    public static let doorLoginItem = "door.loginItem"
    public static let doorTrash = "door.trash"
    public static let doorDone = "door.done"
    public static let doorUseThis = "door.useThis"
    public static let doorSwitch = "door.switch"
    public static let doorCopyAgain = "door.copyAgain"
    public static let doorBack = "door.back"
    public static let doorQuitAgain = "door.quitAgain"
}
