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

package dev.vitruvian.wear.common

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

class WearCommonTest {

  @Test
  fun homelabGaugeReflectsHealthyAndAlertStates() {
    val healthy =
        HomelabSummary(
                readyNodes = 3,
                totalNodes = 3,
                healthyPods = 94,
                totalPods = 94,
                firingAlerts = 0,
            )
            .deriveGauge()
    assertEquals("100%", healthy.shortText)
    assertEquals(100f, healthy.value, 0.01f)
    assertEquals(PulseTone.Healthy, healthy.tone)

    val degraded =
        HomelabSummary(
                readyNodes = 3,
                totalNodes = 3,
                healthyPods = 90,
                totalPods = 94,
                firingAlerts = 2,
            )
            .deriveGauge()
    assertEquals("2!", degraded.shortText)
    assertEquals(PulseTone.Critical, degraded.tone)
    assertTrue(degraded.value < 80f)
  }

  @Test
  fun mergeQueueGaugeTracksQueuedAndFailingPrs() {
    val queued = MergeQueueSummary(openPrs = 4, queuedPrs = 1, failingPrs = 0).deriveGauge()
    assertEquals("1Q", queued.shortText)
    assertEquals(PulseTone.Warning, queued.tone)
    assertEquals(100f, queued.value, 0.01f)

    val failing = MergeQueueSummary(openPrs = 4, queuedPrs = 1, failingPrs = 1).deriveGauge()
    assertEquals("1✗", failing.shortText)
    assertEquals(PulseTone.Critical, failing.tone)
    assertEquals(75f, failing.value, 0.01f)
  }

  @Test
  fun roborockGaugeFormatsCleaningAndDockedStates() {
    val cleaning =
        RoborockSummary(
                state = "cleaning",
                batteryPercent = 86,
                roomName = "Lake Office",
                cleanAreaSqm = 18,
            )
            .deriveGauge()
    assertEquals("CLN", cleaning.shortText)
    assertEquals(PulseTone.Warning, cleaning.tone)
    assertTrue(cleaning.longText.contains("Lake Office"))

    val docked = RoborockSummary(state = "docked", batteryPercent = 100).deriveGauge()
    assertEquals("100%", docked.shortText)
    assertEquals(PulseTone.Healthy, docked.tone)
  }

  @Test
  fun rotaryVolumeAccumulatorIntegratesFractionalCrownScrollAndUnmutes() {
    val acc = RotaryVolumeAccumulator(pixelsPerStep = 20f)

    // Sub-detent scroll should not step volume yet.
    val step0 = acc.onScroll(currentVolume = 40, muted = true, scrollPixels = 12f)
    assertEquals(40, step0.newVolume)
    assertEquals(0, step0.deltaSteps)
    assertFalse(step0.unmuted)

    // Crossing the 20px detent steps volume +1 and unmutes.
    val step1 = acc.onScroll(currentVolume = 40, muted = true, scrollPixels = 10f)
    assertEquals(41, step1.newVolume)
    assertEquals(1, step1.deltaSteps)
    assertTrue(step1.unmuted)

    // Reversing direction clears residual and clamps at bounds.
    val stepDown = acc.onScroll(currentVolume = 1, muted = false, scrollPixels = -60f)
    assertEquals(0, stepDown.newVolume)
    assertEquals(-1, stepDown.deltaSteps)
  }

  @Test
  fun speakerRoomAndRoborockPayloadsMatchCliAndMcpContracts() {
    assertEquals(
        "speaker-broadcast --enable --set-target lake_office",
        SpeakerRoom.LAKE_OFFICE.toSpeakerBroadcastCliCommand(),
    )
    assertEquals(
        "speaker-broadcast --disable",
        SpeakerRoom.MUTE.toSpeakerBroadcastCliCommand(),
    )
    assertEquals(
        """{"tool":"roborock","action":"clean_room_office","segmentId":16}""",
        RoborockAction.CLEAN_OFFICE.toJsonPayload(),
    )
  }

  @Test
  fun voiceRouterSelectsSpecialistAgentAndEncodesApprovals() {
    val ridgeReq = VoiceAgentRouter.route("Check why pod grafana is flapping in k3s")
    assertEquals(SpecialistAgent.RIDGE, ridgeReq.routedAgent)

    val scoutReq = VoiceAgentRouter.route("Enqueue pull request 3839 in merge queue")
    assertEquals(SpecialistAgent.SCOUT, scoutReq.routedAgent)

    val atlasReq = VoiceAgentRouter.route("Preview pulumi gateway route changes")
    assertEquals(SpecialistAgent.ATLAS, atlasReq.routedAgent)

    val item =
        PendingApprovalItem(
            id = "pr-3839",
            title = "PR #3839",
            subtitle = "Daytona Platinum 126506",
            agent = SpecialistAgent.SCOUT,
            prNumber = 3839,
        )
    assertEquals(
        """{"itemId":"pr-3839","decision":"approve_enqueue","agent":"scout","prNumber":3839}""",
        VoiceAgentRouter.encodeApproval(item, ApprovalDecision.APPROVE_AND_ENQUEUE),
    )
  }
}
