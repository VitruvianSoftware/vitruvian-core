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

import Testing
@testable import HomeSpeakerCore

// Which settings each surface shows (the menu bar, both Settings, the
// extension's island): one answer, from the config, for all of them.

@Suite struct DisclosureTests {
    @Test func homeControlsFollowTheHomeSpeakers() {
        var c = SpeakerConfig()
        #expect(c.showsHomeControls, "on unless switched off")
        c.speakHome = false
        #expect(!c.showsHomeControls)
    }

    @Test func castingIsOfferedWithTheHomeSpeakersAndGeminiOnly() {
        var c = SpeakerConfig()
        #expect(!c.showsHomeCastVoice, "the system voice cannot be cast")
        c.localEngine = .gemini
        #expect(c.showsHomeCastVoice)
        c.speakHome = false
        #expect(!c.showsHomeCastVoice)
    }

    /// The engine shows with the Home speakers alone, or casting could
    /// never be reached; the Gemini voice only where Gemini speaks.
    @Test func theEngineIsReachableAndTheGeminiVoiceShowsWhereItSpeaks() {
        var c = SpeakerConfig()
        #expect(c.showsVoiceEngine && !c.usesVoiceEngine, "Home alone: the way to casting")
        c.localEngine = .gemini
        #expect(!c.showsGeminiVoice, "casting off: Gemini speaks nowhere")
        c.homeCastVoice = true
        #expect(c.showsGeminiVoice)
        c.speakHome = false
        #expect(!c.showsVoiceEngine && !c.showsGeminiVoice, "every output off")
        c.speakPhone = true
        #expect(c.showsVoiceEngine && c.showsGeminiVoice)
        c.localEngine = .apple
        #expect(c.showsVoiceEngine && !c.showsGeminiVoice)
    }

    @Test func theStyleShowsWhileAnyCodingAgentAnnounces() {
        var c = SpeakerConfig()
        c.announcementStyle = .briefing
        #expect(c.showsAnnouncementStyle, "agents announce unless switched off")
        for agent in CodingAgent.allCases.dropLast() { c.setAnnounces(agent, false) }
        #expect(c.showsAnnouncementStyle, "one agent left is enough")
        c.setAnnounces(CodingAgent.allCases.last!, false)
        #expect(!c.showsAnnouncementStyle)
        #expect(c.effectiveAnnouncementStyle == .briefing, "hidden, not reset")
    }
}
