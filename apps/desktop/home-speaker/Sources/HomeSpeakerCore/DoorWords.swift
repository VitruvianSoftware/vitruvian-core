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

// What the app and the extension both say and show when both are on this
// Mac (design 7.4 and 7.7, "The strings"): the sentences, the side-by-side
// summary before a copy, and step 2's state. The extension's pages and the
// app's windows draw the same things from here.

/// What the card and the row say ("The strings"; the extension's and
/// the app's use the same sentences).
public enum DoorWords {
    public static let heading = "HomeSpeaker is installed twice"
    public static let body = "The HomeSpeaker app and the Vitruvian extension can both speak on your speakers. Use one, so nothing is said twice."
    public static func use(_ door: HomeSpeakerProfile.Door) -> String { "Use the \(door.rawValue)" }
    public static func copyFrom(_ door: HomeSpeakerProfile.Door) -> String { "Copy from the \(door.rawValue)" }
    public static let keep = "Keep what this one has"
    public static let done = "Done"
    public static func quiet(other: HomeSpeakerProfile.Door) -> String {
        "The HomeSpeaker \(other.rawValue) is in use, so this one stays quiet."
    }
    public static let useThis = "Use this one instead"
    public static let which = "Which HomeSpeaker"
    public static func uses(_ door: HomeSpeakerProfile.Door) -> String { "This Mac uses the \(door.rawValue)." }
    public static func useInstead(_ door: HomeSpeakerProfile.Door) -> String { "Use the \(door.rawValue) instead" }
    public static func copySettingsFrom(_ door: HomeSpeakerProfile.Door) -> String { "Copy settings from the \(door.rawValue)" }
    public static let runsWithVitruvian = "Runs whenever Vitruvian runs. To start it at login, turn on Vitruvian's Open at Login."

    // Not in the plan's table; in the same voice (listed in the task's report).
    public static func signsOut(from: HomeSpeakerProfile.Door, into: HomeSpeakerProfile.Door) -> String {
        "The \(from.rawValue) has no sign-ins, so copying from it signs the \(into.rawValue) out."
    }
    public static let quitting = "Asking the app to quit…"
    public static let didNotQuit = "The app did not quit. Quit it from its menu bar icon."
    public static let loginItemOff = "The app's Open at Login is off."
    public static let inTheTrash = "HomeSpeaker.app is in the Trash."
    public static let back = "Back"
    public static let quitAgain = "Quit the app"
    public static let opening = "Opening the app…"
    public static let starting = "The HomeSpeaker app is starting, so this one stays quiet."
    public static let couldNotOpen = "HomeSpeaker.app could not be opened. Open it from Applications."
    public static let loginItemOn = "The app's Open at Login is on."
    public static let appNotFound = "HomeSpeaker.app can't be found, so nothing was changed."
    public static let choiceChanged = "The choice changed in the other HomeSpeaker, so nothing was changed here."

    // Step 3's offers, as the extension makes them and the app makes them
    // of itself ("The strings").
    public static let turnOffLoginItem = "Turn off the app's Open at Login"
    public static let moveToTrash = "Move HomeSpeaker.app to the Trash"
    public static let trashWarning =
        "Your phone remote and scripts that call HomeSpeaker.app will stop working until they are pointed at the extension."

    // The app's own ("The strings", "App, after choosing it").
    public static let appChosen =
        "The extension is quiet now. To remove it: Vitruvian > Settings > Extensions > HomeSpeaker > Remove."
    public static let openVitruvian = "Open Vitruvian"
    // Not in the plan's table; in the same voice (listed in the task's report).
    public static let quit = "Quit"
    public static let extensionNotFound = "The HomeSpeaker extension can't be found, so nothing was changed."
    public static let couldNotOpenVitruvian = "Vitruvian could not be opened. Open it from Applications."
    /// The app's login item needs the person's approval (macOS 15 on names
    /// the pane "Login Items & Extensions").
    public static let approveLoginItem = "Approve HomeSpeaker under System Settings > General > Login Items & Extensions."
}

/// Step 2 of the choice, in either HomeSpeaker: one side copied into the
/// other, or not (design 7.4).
public struct DoorCompare: Equatable {
    public enum Purpose: Equatable, Sendable {
        /// The person is choosing `into`: the copy, then the choice.
        case choose
        /// General's "Copy settings from": the copy alone.
        case copyOnly
    }

    public var purpose: Purpose
    public var from: HomeSpeakerProfile.Door
    public var into: HomeSpeakerProfile.Door
    public var source: DoorSnapshot
    public var destination: DoorSnapshot
    /// Why the last copy or choice did not happen.
    public var problem: String?
    /// The choice file's choice, and when it was made, as this step
    /// found them. A choice made elsewhere since is never overridden.
    public var seenChoice: HomeSpeakerProfile.Door?
    public var seenChosenAt: Date?

    public init(purpose: Purpose, from: HomeSpeakerProfile.Door, into: HomeSpeakerProfile.Door,
                source: DoorSnapshot, destination: DoorSnapshot, problem: String? = nil,
                seenChoice: HomeSpeakerProfile.Door? = nil, seenChosenAt: Date? = nil) {
        self.purpose = purpose
        self.from = from
        self.into = into
        self.source = source
        self.destination = destination
        self.problem = problem
        self.seenChoice = seenChoice
        self.seenChosenAt = seenChosenAt
    }

    public var suggestion: DoorCopy.Suggestion { DoorCopy.suggest(chosen: destination, other: source) }

    /// The copy takes the whole sign-in value: from a side with none, it
    /// signs the other out of the ones it has (`DoorCopy.copy`).
    public var signsOut: Bool { !source.hasAnySignIn && destination.hasAnySignIn }
}

/// Each fact the summary shows, in plain words, for one side.
public enum DoorSummary {
    public struct Fact: Sendable {
        public let title: String
        public let value: @Sendable (DoorSnapshot) -> String
    }

    public static let facts: [Fact] = [
        Fact(title: "Google Home") { side in
            guard side.hasHomeLogin else { return "Not signed in" }
            return side.googleEmail.map { "Signed in as \($0)" } ?? "Signed in"
        },
        Fact(title: "Google Chat") { $0.hasChatLogin ? "Access granted" : "No access" },
        Fact(title: "Slack") { $0.hasSlackToken ? "Token saved" : "No token" },
        Fact(title: "Beeper") { $0.hasBeeperToken ? "Token saved" : "No token" },
        Fact(title: "Gemini") { $0.hasGeminiKey ? "Key saved" : "No key" },
        Fact(title: "Own sign-in client") { $0.hasOwnClient ? "Saved" : "None" },
        Fact(title: "Home") { $0.homeName ?? "None" },
        Fact(title: "Speakers") { side in
            guard side.speakerCount > 0 else { return "None" }
            return side.defaultSpeaker.map { "\(side.speakerCount), default \($0)" } ?? "\(side.speakerCount)"
        },
        Fact(title: "Speaks on") { side in
            if side.config.effectiveSpeakPhone {
                switch (side.config.effectiveSpeakHome, side.config.effectiveSpeakLocal) {
                case (true, true): return "Home speakers, this Mac and your phone"
                case (true, false): return "Home speakers and your phone"
                case (false, true): return "This Mac and your phone"
                case (false, false): return "Your phone"
                }
            }
            switch side.outputs {
            case .home: return "Home speakers"
            case .thisMac: return "This Mac"
            case .both: return "Home speakers and this Mac"
            case .nowhere: return "Nowhere"
            }
        },
        Fact(title: "Quiet hours") { $0.quietHours ?? "Off" },
        Fact(title: "Announce volume") { side in
            let config = side.config
            return config.effectiveAnnounceVolumeEnabled ? "\(config.effectiveAnnounceVolume)%" : "Off"
        },
        Fact(title: "Pause media") { $0.config.effectivePauseMedia ? "On" : "Off" },
        Fact(title: "Speak") { $0.config.effectiveSpeechLength.label },
        Fact(title: "Style") { $0.config.effectiveAnnouncementStyle.label },
        Fact(title: "Chat sources") { $0.chatSources.isEmpty ? "Off" : $0.chatSources.joined(separator: ", ") },
        Fact(title: "Settings changed") { side in
            if case .unreadable = side.settingsRead { return "Does not read" }
            return side.settingsChanged.map { $0.formatted(date: .abbreviated, time: .shortened) } ?? "Never saved"
        },
    ]
}

extension DoorSnapshot {
    /// Any sign-in at all: Google Home, Google Chat, Slack, Beeper, Gemini or an own client.
    public var hasAnySignIn: Bool {
        hasHomeLogin || hasChatLogin || hasSlackToken || hasBeeperToken || hasGeminiKey || hasOwnClient
    }

    /// The settings as read, or the defaults this side would run with.
    public var config: SpeakerConfig {
        if case .loaded(let config) = settingsRead { return config }
        return SpeakerConfig()
    }
}
