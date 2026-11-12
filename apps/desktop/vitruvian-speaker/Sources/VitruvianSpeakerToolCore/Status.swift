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
import VitruvianToolProtocol

/// What the tool knows that decides the mark on the closed island.
public struct StatusInputs: Equatable {
    /// What this HomeSpeaker does, given the other and the person's choice.
    public var role: DoorRole
    /// A sign-in that stopped working, when there is one.
    public var signInProblem: String?
    /// The chat monitor's problem (`Pages.Chat.runtimeError`): believed only
    /// while its owner runs.
    public var monitorProblem: String?
    /// A sign-in, a speaker, or this Mac on: enough to do something.
    public var setUp: Bool
    public var speaking: Bool
    /// When quiet hours end ("07:00"), while they are on.
    public var quietUntil: String?
    public var broadcasting: Bool
    public var defaultSpeaker: String?

    public init(
        role: DoorRole, signInProblem: String? = nil, monitorProblem: String? = nil, setUp: Bool,
        speaking: Bool = false, quietUntil: String? = nil, broadcasting: Bool, defaultSpeaker: String? = nil
    ) {
        self.role = role
        self.signInProblem = signInProblem
        self.monitorProblem = monitorProblem
        self.setUp = setUp
        self.speaking = speaking
        self.quietUntil = quietUntil
        self.broadcasting = broadcasting
        self.defaultSpeaker = defaultSpeaker
    }
}

/// What `ui/status` should say: the state, an SF Symbol and the words for
/// the tooltip and VoiceOver.
public struct MarkChoice: Equatable {
    public var state: StatusState
    public var icon: String?
    public var text: String?

    public init(state: StatusState, icon: String? = nil, text: String? = nil) {
        self.state = state
        self.icon = icon
        self.text = text
    }
}

/// The mark on the closed island (design 6).
public enum IslandStatus {
    /// The first row that applies wins, and the order is the precedence:
    ///
    /// 1. The other HomeSpeaker is chosen: no mark at all.
    /// 2. A sign-in stopped working, then the chat monitor has a problem.
    /// 3. Both installed and nobody has picked.
    /// 4. Not set up.
    /// 5. Speaking now.
    /// 6. Quiet hours, broadcasting off, broadcasting: all `ok`.
    public static func mark(_ inputs: StatusInputs) -> MarkChoice {
        if inputs.role.isQuiet {
            return MarkChoice(state: .none)
        }
        if Self.words(inputs.signInProblem) != nil {
            return MarkChoice(state: .failure, icon: "exclamationmark.triangle", text: "Sign in to Google again")
        }
        if let problem = Self.words(inputs.monitorProblem) {
            return MarkChoice(state: .failure, icon: "exclamationmark.triangle", text: problem)
        }
        switch inputs.role {
        case .activeAsking, .waitingAsking:
            return MarkChoice(state: .attention, icon: "exclamationmark.circle", text: "Pick which HomeSpeaker to use")
        case .active, .quiet:
            break
        }
        if !inputs.setUp {
            return MarkChoice(state: .attention, icon: "hifispeaker.2", text: "Set up HomeSpeaker")
        }
        if inputs.speaking {
            return MarkChoice(state: .busy, icon: "waveform", text: "Speaking")
        }
        if let until = Self.words(inputs.quietUntil) {
            return MarkChoice(state: .ok, icon: "moon.zzz", text: "Quiet hours until \(until)")
        }
        if !inputs.broadcasting {
            return MarkChoice(state: .ok, icon: "speaker.slash.fill", text: "Broadcasting off")
        }
        let speaker = Self.words(inputs.defaultSpeaker)
        return MarkChoice(state: .ok, icon: "dot.radiowaves.left.and.right",
                          text: speaker.map { "Broadcasting to \($0)" } ?? "Broadcasting")
    }

    /// The text, trimmed, or nil when there is none to say.
    private static func words(_ text: String?) -> String? {
        guard let trimmed = text?.trimmingCharacters(in: .whitespacesAndNewlines), !trimmed.isEmpty else { return nil }
        return trimmed
    }
}
