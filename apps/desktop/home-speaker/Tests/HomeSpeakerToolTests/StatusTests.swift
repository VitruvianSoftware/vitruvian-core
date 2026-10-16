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

import XCTest

import HomeSpeakerCore
import HomeSpeakerToolCore
import VitruvianToolProtocol

/// What the closed island's mark says (design 6): one pure function from
/// what the tool knows to a mark. Nothing here touches a file, a program
/// or the Vitruvian app.
final class StatusTests: XCTestCase {
    /// A HomeSpeaker with nothing to say: running, set up, broadcasting.
    private func inputs(
        role: DoorRole = .active, signInProblem: String? = nil, monitorProblem: String? = nil,
        setUp: Bool = true, speaking: Bool = false, quietUntil: String? = nil,
        broadcasting: Bool = true, defaultSpeaker: String? = "Kitchen"
    ) -> StatusInputs {
        StatusInputs(role: role, signInProblem: signInProblem, monitorProblem: monitorProblem, setUp: setUp,
                     speaking: speaking, quietUntil: quietUntil, broadcasting: broadcasting,
                     defaultSpeaker: defaultSpeaker)
    }

    private func mark(_ inputs: StatusInputs) -> MarkChoice { IslandStatus.mark(inputs) }

    // MARK: One test per row

    func testQuietSideShowsNothing() {
        // Every other thing is wrong, and still the mark is gone: the other
        // HomeSpeaker is the chosen one and speaks for itself.
        let everythingWrong = inputs(role: .quiet(other: .app), signInProblem: "expired", monitorProblem: "no token",
                                     setUp: false, speaking: true, quietUntil: "07:00")
        XCTAssertEqual(mark(everythingWrong), MarkChoice(state: .none, icon: nil, text: nil))
        XCTAssertEqual(mark(inputs(role: .quiet(other: .extension))), MarkChoice(state: .none, icon: nil, text: nil))
    }

    func testNobodyHasPickedAsksForAChoice() {
        let asking = MarkChoice(state: .attention, icon: "exclamationmark.circle", text: "Pick which HomeSpeaker to use")
        XCTAssertEqual(mark(inputs(role: .activeAsking)), asking)
        XCTAssertEqual(mark(inputs(role: .waitingAsking)), asking)
    }

    func testASignInThatStoppedWorkingSaysToSignInAgain() {
        XCTAssertEqual(mark(inputs(signInProblem: "token revoked")),
                       MarkChoice(state: .failure, icon: "exclamationmark.triangle", text: "Sign in to Google again"))
    }

    func testTheChatMonitorsProblemIsShownInItsOwnWords() {
        XCTAssertEqual(mark(inputs(monitorProblem: "Slack: invalid_auth")),
                       MarkChoice(state: .failure, icon: "exclamationmark.triangle", text: "Slack: invalid_auth"))
    }

    func testNotSetUpAsksForSetUp() {
        XCTAssertEqual(mark(inputs(setUp: false)),
                       MarkChoice(state: .attention, icon: "hifispeaker.2", text: "Set up HomeSpeaker"))
    }

    func testSpeakingIsBusy() {
        XCTAssertEqual(mark(inputs(speaking: true)),
                       MarkChoice(state: .busy, icon: "waveform", text: "Speaking"))
    }

    func testQuietHoursSayWhenTheyEnd() {
        XCTAssertEqual(mark(inputs(quietUntil: "07:00")),
                       MarkChoice(state: .ok, icon: "moon.zzz", text: "Quiet hours until 07:00"))
    }

    func testBroadcastingOffIsOkWithTheSlashedSpeaker() {
        XCTAssertEqual(mark(inputs(broadcasting: false)),
                       MarkChoice(state: .ok, icon: "speaker.slash.fill", text: "Broadcasting off"))
    }

    func testBroadcastingNamesTheSpeaker() {
        XCTAssertEqual(mark(inputs()),
                       MarkChoice(state: .ok, icon: "dot.radiowaves.left.and.right", text: "Broadcasting to Kitchen"))
    }

    func testBroadcastingWithNoNamedSpeakerStillSaysBroadcasting() {
        XCTAssertEqual(mark(inputs(defaultSpeaker: nil)).text, "Broadcasting")
        XCTAssertEqual(mark(inputs(defaultSpeaker: "  ")).text, "Broadcasting")
    }

    // MARK: The order is the precedence

    func testFailureBeatsSpeaking() {
        // A broken sign-in must not hide behind a job that is running.
        XCTAssertEqual(mark(inputs(signInProblem: "token revoked", speaking: true)).state, .failure)
        XCTAssertEqual(mark(inputs(monitorProblem: "Slack: invalid_auth", speaking: true)).state, .failure)
    }

    func testUndecidedBeatsEverythingButFailure() {
        let busyAndUnsetAndQuiet = inputs(role: .waitingAsking, setUp: false, speaking: true, quietUntil: "07:00")
        XCTAssertEqual(mark(busyAndUnsetAndQuiet).text, "Pick which HomeSpeaker to use")
        // ...but a failure still wins over the request to pick.
        XCTAssertEqual(mark(inputs(role: .activeAsking, signInProblem: "token revoked")).text, "Sign in to Google again")
        XCTAssertEqual(mark(inputs(role: .waitingAsking, monitorProblem: "boom")).text, "boom")
    }

    func testASignInProblemComesBeforeTheMonitorsProblem() {
        XCTAssertEqual(mark(inputs(signInProblem: "token revoked", monitorProblem: "boom")).text,
                       "Sign in to Google again")
    }

    func testNotSetUpBeatsSpeakingAndQuietHours() {
        XCTAssertEqual(mark(inputs(setUp: false, speaking: true, quietUntil: "07:00")).text, "Set up HomeSpeaker")
    }

    func testSpeakingBeatsQuietHoursAndTheBroadcastingRows() {
        XCTAssertEqual(mark(inputs(speaking: true, quietUntil: "07:00", broadcasting: false)).state, .busy)
    }

    func testQuietHoursBeatBroadcastingOff() {
        XCTAssertEqual(mark(inputs(quietUntil: "07:00", broadcasting: false)).icon, "moon.zzz")
    }

    func testABlankProblemIsNoProblem() {
        XCTAssertEqual(mark(inputs(signInProblem: "", monitorProblem: " \n ")).state, .ok)
    }
}
