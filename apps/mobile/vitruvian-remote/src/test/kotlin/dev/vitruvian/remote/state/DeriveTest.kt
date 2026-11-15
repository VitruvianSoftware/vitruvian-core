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

package dev.vitruvian.remote.state

import dev.vitruvian.remote.hid.HidAction
import dev.vitruvian.remote.state.Derive.PeekRegion
import dev.vitruvian.remote.state.Derive.PollPage
import dev.vitruvian.remote.state.Derive.PollSource
import dev.vitruvian.remote.state.Derive.PollView
import dev.vitruvian.remote.state.Derive.PrCheck
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

/** What the v1.2 rows are coloured by. Each of these was a wrong colour waiting to happen. */
public class DeriveTest {

  // --- pairing: reachable is not the same as allowed ---------------------

  @Test
  public fun `a blank token on a reachable Mac is not paired, not connected`() {
    // The incident: the agent answered every read, so the app said "connected" while
    // every act was refused.
    val p = Derive.pairing(hasAgent = true, hasToken = false, rejected = false)
    assertEquals(Derive.Pairing.NotPaired, p)
    assertTrue(Derive.needsPairing(p))
    assertEquals("connected · not paired", Derive.connectionWord(p, "connected"))
  }

  @Test
  public fun `a refused token reads as rejected until a pairing succeeds`() {
    assertEquals(
        Derive.Pairing.Rejected, Derive.pairing(hasAgent = true, hasToken = false, rejected = true))
    // A fresh token clears the stale refusal without anyone resetting the flag.
    val after = Derive.pairing(hasAgent = true, hasToken = true, rejected = true)
    assertEquals(Derive.Pairing.Paired, after)
    assertFalse(Derive.needsPairing(after))
    assertEquals("connected", Derive.connectionWord(after, "connected"))
  }

  @Test
  public fun `no agent means simulated, which needs no pairing banner`() {
    val p = Derive.pairing(hasAgent = false, hasToken = false, rejected = true)
    assertEquals(Derive.Pairing.NoAgent, p)
    assertFalse(Derive.needsPairing(p))
    assertEquals(null, Derive.pairingBanner(p, "atlas"))
  }

  @Test
  public fun `the banner names the Mac and says changes will not work`() {
    val (label, body) = Derive.pairingBanner(Derive.Pairing.NotPaired, "atlas")!!
    assertEquals("Not paired with atlas", label)
    assertEquals(
        "This phone is not paired with atlas. You can look, but changes will not work.", body)
    val (rLabel, rBody) = Derive.pairingBanner(Derive.Pairing.Rejected, "atlas")!!
    assertTrue(rLabel.contains("atlas"))
    assertTrue(rBody.contains("pair again"))
    assertEquals(null, Derive.pairingBanner(Derive.Pairing.Paired, "atlas"))
    assertEquals("Not paired with atlas — pair to make changes", Derive.notPairedText("atlas"))
  }

  // --- phone bridge: on is not the same as linked --------------------------

  private fun bridge(
      enabled: Boolean = true,
      linked: Boolean = false,
      pairing: Derive.Pairing = Derive.Pairing.Paired,
      reachable: Boolean = true,
      status: String = "",
  ) = Derive.bridgeProblem(enabled, linked, pairing, reachable, status)

  @Test
  public fun `a bridge that is off or linked has nothing to say`() {
    assertEquals(Derive.BridgeProblem.None, bridge(enabled = false, status = "off"))
    assertEquals(Derive.BridgeProblem.None, bridge(linked = true, status = "linked"))
    assertEquals(null, Derive.bridgeProblemText(Derive.BridgeProblem.None, "atlas", "linked"))
  }

  @Test
  public fun `an unpaired phone's bridge says not paired, from either side`() {
    // The phone knows before the service does: it re-reads the token between attempts.
    assertEquals(
        Derive.BridgeProblem.NotPaired,
        bridge(pairing = Derive.Pairing.NotPaired, status = "connecting to atlas…"))
    // The service's own refusal, and the Mac's 401 as AgentClient words it.
    assertEquals(
        Derive.BridgeProblem.NotPaired,
        bridge(status = "not paired with atlas — pair on the Hosts screen"))
    assertEquals(Derive.BridgeProblem.NotPaired, bridge(status = "not paired (HTTP 401)"))
    assertEquals(
        "Phone Bridge is on but cannot link: this phone is not paired with atlas.",
        Derive.bridgeProblemText(Derive.BridgeProblem.NotPaired, "atlas", ""))
  }

  @Test
  public fun `a stopped service and an unreachable Mac are told apart`() {
    assertEquals(Derive.BridgeProblem.Stopped, bridge(status = "off"))
    assertEquals(
        Derive.BridgeProblem.Unreachable, bridge(reachable = false, status = "connect timed out"))
    assertEquals(Derive.BridgeProblem.Other, bridge(status = "the Mac closed the link"))
    assertEquals(
        "Phone Bridge is on but not linked: the Mac closed the link",
        Derive.bridgeProblemText(Derive.BridgeProblem.Other, "atlas", "the Mac closed the link"))
  }

  @Test
  public fun `connecting shows on the plate but does not raise the banner`() {
    val p = bridge(status = "connecting to atlas…")
    assertEquals(Derive.BridgeProblem.Connecting, p)
    assertFalse(Derive.bridgeProblemIsBannerWorthy(p))
    // The moment between the switch and the service's first word is not "stopped".
    assertEquals(Derive.BridgeProblem.Connecting, bridge(status = "starting…"))
    assertTrue(Derive.bridgeProblemIsBannerWorthy(Derive.BridgeProblem.NotPaired))
    assertTrue(Derive.bridgeProblemIsBannerWorthy(Derive.BridgeProblem.Stopped))
  }

  // --- module row layout -------------------------------------------------

  @Test
  public fun `a lone switch sits in the row`() {
    assertEquals(
        Derive.RowControl.InlineToggle,
        Derive.rowControl(hasToggle = true, actionCount = 0, choiceCount = 0, hasPrompt = false))
  }

  @Test
  public fun `a lone dropdown, prompt or action sits in the row`() {
    assertEquals(
        Derive.RowControl.InlineDropdown,
        Derive.rowControl(hasToggle = false, actionCount = 0, choiceCount = 8, hasPrompt = false))
    assertEquals(
        Derive.RowControl.InlinePrompt,
        Derive.rowControl(hasToggle = false, actionCount = 0, choiceCount = 0, hasPrompt = true))
    assertEquals(
        Derive.RowControl.InlineAction,
        Derive.rowControl(hasToggle = false, actionCount = 1, choiceCount = 0, hasPrompt = false))
  }

  @Test
  public fun `more than one control goes under the row`() {
    // Announce at a set volume, switched on: switch + -10/+10 + the percent dropdown.
    assertEquals(
        Derive.RowControl.Stacked,
        Derive.rowControl(hasToggle = true, actionCount = 2, choiceCount = 5, hasPrompt = false))
    // Speaker: Remove + the speaker dropdown.
    assertEquals(
        Derive.RowControl.Stacked,
        Derive.rowControl(hasToggle = false, actionCount = 1, choiceCount = 3, hasPrompt = false))
    // Two actions, no dropdown.
    assertEquals(
        Derive.RowControl.Stacked,
        Derive.rowControl(hasToggle = false, actionCount = 2, choiceCount = 0, hasPrompt = false))
  }

  @Test
  public fun `a row with nothing to press has no control`() {
    assertEquals(
        Derive.RowControl.None,
        Derive.rowControl(hasToggle = false, actionCount = 0, choiceCount = 0, hasPrompt = false))
  }

  @Test
  public fun `the switch replaces on and off but not a value`() {
    assertEquals("", Derive.toggleTrailing("on"))
    assertEquals("", Derive.toggleTrailing("off"))
    assertEquals("", Derive.toggleTrailing(" On "))
    assertEquals("60%", Derive.toggleTrailing("60%"))
    assertEquals("running", Derive.toggleTrailing("running"))
    assertEquals("muted", Derive.toggleTrailing("muted"))
  }

  @Test
  public fun `an empty secret says Set, not Replace`() {
    // The rows' trailing text is "missing" when empty; the label must not read it as a value.
    assertEquals("Set…", Derive.promptButtonLabel(secret = true, hasValue = false))
    assertEquals("Replace…", Derive.promptButtonLabel(secret = true, hasValue = true))
    assertEquals("Set…", Derive.promptButtonLabel(secret = false, hasValue = false))
    assertEquals("Edit…", Derive.promptButtonLabel(secret = false, hasValue = true))
  }

  // --- peek zoom ---------------------------------------------------------

  @Test
  public fun `no pinch is the same region`() {
    assertEquals(PeekRegion.Full, Derive.zoomedRegion(PeekRegion.Full, 1f, 0f, 0f, 1000, 300))
  }

  @Test
  public fun `pinching to 2x about the corner is the top-left quarter`() {
    val r = Derive.zoomedRegion(PeekRegion.Full, 2f, 0f, 0f, 1000, 300)
    assertEquals(PeekRegion(0.0, 0.0, 0.5, 0.5), r)
    assertEquals(2.0, r.zoom, 1e-9)
  }

  @Test
  public fun `pinching 2x about the centre is the middle`() {
    // Scaling about the centre of a 1000x300 view moves the origin by half the growth.
    val r = Derive.zoomedRegion(PeekRegion.Full, 2f, -500f, -150f, 1000, 300)
    assertEquals(0.25, r.x, 1e-9)
    assertEquals(0.25, r.y, 1e-9)
    assertEquals(0.5, r.w, 1e-9)
  }

  @Test
  public fun `a second pinch zooms into the current region, not the whole display`() {
    val quarter = PeekRegion(0.5, 0.5, 0.5, 0.5)
    val r = Derive.zoomedRegion(quarter, 2f, 0f, 0f, 1000, 300)
    assertEquals(PeekRegion(0.5, 0.5, 0.25, 0.25), r)
  }

  @Test
  public fun `panning past the edge stops at the edge`() {
    // Dragged far to the right and down at 2x: the window would start past 1.0.
    val r = Derive.zoomedRegion(PeekRegion.Full, 2f, -5000f, -5000f, 1000, 300)
    assertEquals(PeekRegion(0.5, 0.5, 0.5, 0.5), r)
    // And far the other way: never negative.
    assertEquals(
        PeekRegion(0.0, 0.0, 0.5, 0.5),
        Derive.zoomedRegion(PeekRegion.Full, 2f, 5000f, 5000f, 1000, 300))
  }

  @Test
  public fun `zoom is capped at the agent's 16x`() {
    val r = Derive.zoomedRegion(PeekRegion.Full, 40f, 0f, 0f, 1000, 300)
    assertEquals(PeekRegion.MIN_FRACTION, r.w, 1e-9)
    assertEquals(PeekRegion.MIN_FRACTION, r.h, 1e-9)
  }

  @Test
  public fun `pinching out past 1x asks for the whole display`() {
    val quarter = PeekRegion(0.5, 0.5, 0.5, 0.5)
    assertEquals(PeekRegion.Full, Derive.zoomedRegion(quarter, 0.4f, 0f, 0f, 1000, 300))
    assertTrue(Derive.zoomedRegion(quarter, 0.4f, 0f, 0f, 1000, 300).isFull)
  }

  @Test
  public fun `a view that has not measured yet changes nothing`() {
    assertEquals(PeekRegion.Full, Derive.zoomedRegion(PeekRegion.Full, 3f, 0f, 0f, 0, 0))
  }

  @Test
  public fun `all checks passing is green`() {
    assertEquals(
        PrCheck.Green, Derive.prCheck(isDraft = false, success = 12, failure = 0, pending = 0))
  }

  @Test
  public fun `one failure outranks every success`() {
    assertEquals(
        PrCheck.Red, Derive.prCheck(isDraft = false, success = 40, failure = 1, pending = 0))
  }

  @Test
  public fun `a failure outranks a pending check too`() {
    assertEquals(
        PrCheck.Red, Derive.prCheck(isDraft = false, success = 0, failure = 1, pending = 9))
  }

  @Test
  public fun `still running is pending, not green`() {
    assertEquals(
        PrCheck.Pending, Derive.prCheck(isDraft = false, success = 11, failure = 0, pending = 1))
  }

  @Test
  public fun `a draft stays a draft however green it is`() {
    assertEquals(
        PrCheck.Draft, Derive.prCheck(isDraft = true, success = 12, failure = 0, pending = 0))
    assertEquals(
        PrCheck.Draft, Derive.prCheck(isDraft = true, success = 0, failure = 3, pending = 0))
  }

  @Test
  public fun `no checks at all is not success`() {
    assertEquals(
        PrCheck.None, Derive.prCheck(isDraft = false, success = 0, failure = 0, pending = 0))
    assertEquals("no checks", PrCheck.None.label)
  }

  private data class App(val name: String, val sync: String, val health: String)

  @Test
  public fun `argo split keeps the broken ones and counts the rest`() {
    val apps =
        listOf(
            App("a", "Synced", "Healthy"),
            App("b", "OutOfSync", "Healthy"),
            App("c", "Synced", "Degraded"),
            App("d", "Synced", "Healthy"),
            App("e", "Synced", "Healthy"),
        )
    val split = Derive.splitArgo(apps) { Derive.argoOk(it.sync, it.health) }
    assertEquals(listOf("b", "c"), split.attention.map { it.name })
    assertEquals(3, split.restCount)
  }

  @Test
  public fun `argo split preserves the order it was given`() {
    val apps = listOf(App("z", "OutOfSync", "Healthy"), App("a", "Unknown", "Missing"))
    val split = Derive.splitArgo(apps) { Derive.argoOk(it.sync, it.health) }
    assertEquals(listOf("z", "a"), split.attention.map { it.name })
    assertEquals(0, split.restCount)
  }

  @Test
  public fun `sync and health are matched case-insensitively`() {
    assertTrue(Derive.argoOk("synced", "healthy"))
    assertFalse(Derive.argoOk("Synced", "Progressing"))
    assertFalse(Derive.argoOk("", ""))
  }

  @Test
  public fun `the collapsed row does not say one more all`() {
    assertEquals("47 more, all Synced · Healthy", Derive.collapsedArgoLabel(47))
    assertEquals("1 more, Synced · Healthy", Derive.collapsedArgoLabel(1))
  }

  @Test
  public fun `session states are shortened, and unknown ones survive`() {
    assertEquals("waiting", Derive.claudeStateLabel("waiting_for_permission"))
    assertEquals("working", Derive.claudeStateLabel("working"))
    assertEquals("idle", Derive.claudeStateLabel("IDLE"))
    assertEquals("unknown", Derive.claudeStateLabel(""))
    assertEquals("compacting", Derive.claudeStateLabel("compacting"))
  }

  @Test
  public fun `only waiting for permission counts as waiting`() {
    assertTrue(Derive.claudeWaiting("waiting_for_permission"))
    assertFalse(Derive.claudeWaiting("working"))
    assertFalse(Derive.claudeWaiting("waiting"))
  }

  // --- Vitruvian Speaker ---------------------------------------------------------

  @Test
  public fun `the speaker's worst problem is the status, never a cheerful on`() {
    assertEquals("not installed", Derive.vitruvianSpeakerStatus(false, false, false, true, true))
    assertEquals("not set up", Derive.vitruvianSpeakerStatus(false, true, false, true, true))
    assertEquals("not signed in", Derive.vitruvianSpeakerStatus(true, true, false, true, true))
    assertEquals("off", Derive.vitruvianSpeakerStatus(true, true, true, false, true))
    assertEquals("on · app closed", Derive.vitruvianSpeakerStatus(true, true, true, true, false))
    assertEquals("on", Derive.vitruvianSpeakerStatus(true, true, true, true, true))
  }

  @Test
  public fun `a speaker that cannot speak is a problem even when switched on`() {
    assertEquals(
        Derive.SpeakerHealth.Problem, Derive.vitruvianSpeakerHealth(true, true, false, true))
    assertEquals(Derive.SpeakerHealth.Off, Derive.vitruvianSpeakerHealth(true, true, true, false))
    assertEquals(Derive.SpeakerHealth.Ok, Derive.vitruvianSpeakerHealth(true, true, true, true))
  }

  @Test
  public fun `This phone speaking alone needs no Google sign-in and explains its voice`() {
    assertEquals(
        "on",
        Derive.vitruvianSpeakerStatus(
            true,
            true,
            false,
            true,
            true,
            speakHome = false,
            speakLocal = false,
            speakPhone = true))
    assertEquals(
        Derive.SpeakerHealth.Ok,
        Derive.vitruvianSpeakerHealth(
            true, true, false, true, speakHome = false, speakLocal = false, speakPhone = true))
    assertEquals(
        "Voice: Android TTS",
        Derive.phoneVoiceLabel(
            localEngine = "apple",
            geminiVoice = "Kore",
            hasGeminiKey = false,
            phoneConnected = true,
            headphonesOnly = false))
    assertEquals(
        "Voice: Gemini (Aoede) · headphones only",
        Derive.phoneVoiceLabel(
            localEngine = "gemini",
            geminiVoice = "Aoede",
            hasGeminiKey = true,
            phoneConnected = true,
            headphonesOnly = true))
    assertEquals(
        "Voice: Android TTS · link Phone Bridge to receive audio",
        Derive.phoneVoiceLabel(
            localEngine = "gemini",
            geminiVoice = "Aoede",
            hasGeminiKey = false,
            phoneConnected = false,
            headphonesOnly = false))
  }

  @Test
  public fun `headphone device types include wired, USB, Bluetooth and BLE headsets but not speaker`() {
    listOf(3, 4, 7, 8, 22, 23, 26).forEach { type ->
      assertTrue("type $type should be headphone", Derive.isHeadphoneDeviceType(type))
    }
    listOf(1, 2, 15, 18, 24, 27, 30).forEach { type ->
      assertFalse("type $type should not be headphone", Derive.isHeadphoneDeviceType(type))
    }
  }

  @Test
  public fun `both outputs off is a problem, not an on`() {
    assertEquals(
        "no outputs",
        Derive.vitruvianSpeakerStatus(
            true, true, true, true, true, speakHome = false, speakLocal = false))
    assertEquals(
        Derive.SpeakerHealth.Problem,
        Derive.vitruvianSpeakerHealth(
            true, true, true, true, speakHome = false, speakLocal = false))
    // Switched off overall is still just "off": nothing would be spoken either way.
    assertEquals(
        "off",
        Derive.vitruvianSpeakerStatus(
            true, true, true, false, true, speakHome = false, speakLocal = false))
  }

  @Test
  public fun `the Mac speaking alone needs no Google sign-in`() {
    assertEquals(
        "on",
        Derive.vitruvianSpeakerStatus(
            true, true, false, true, true, speakHome = false, speakLocal = true))
    assertEquals(
        Derive.SpeakerHealth.Ok,
        Derive.vitruvianSpeakerHealth(
            true, true, false, true, speakHome = false, speakLocal = true))
    // ...but the home speakers still do.
    assertEquals(
        "not signed in",
        Derive.vitruvianSpeakerStatus(
            true, true, false, true, true, speakHome = true, speakLocal = true))
  }

  @Test
  public fun `the Mac's voice is named, falling back to its identifier`() {
    assertEquals("Voice: Aaron", Derive.macVoiceLabel("Aaron", "com.apple.siri.natural.Aaron"))
    assertEquals(
        "Voice: com.apple.voice.compact.en-US",
        Derive.macVoiceLabel("", "com.apple.voice.compact.en-US"))
    assertEquals(
        "Voice: Gemini (Puck)",
        Derive.macVoiceLabel(
            "Aaron",
            "com.apple.siri.natural.Aaron",
            localEngine = "gemini",
            geminiVoice = "Puck",
            hasGeminiKey = true))
    assertEquals(
        "Voice: Gemini (Kore) · needs API key on Mac",
        Derive.macVoiceLabel(
            "Aaron",
            "com.apple.siri.natural.Aaron",
            localEngine = "gemini",
            geminiVoice = "",
            hasGeminiKey = false))
  }

  @Test
  public fun `Courier's networks Vitruvian Speaker reads itself are read here as well, Beeper's are greyed`() {
    val slack = AgentBeeperNetwork("slack", "Slack", "skipped")
    val beeper = Derive.chatNetworkRow("Beeper", slack)
    assertEquals(Derive.NetworkSwitch.None, beeper.switch)
    assertEquals("Beeper · Slack", beeper.title)

    val direct = Derive.chatNetworkRow("Courier", slack)
    assertEquals(Derive.NetworkSwitch.ReadAnyway, direct.switch)
    assertFalse(direct.on)
    assertEquals("Courier · Slack", direct.title)
    assertEquals("read directly", direct.trailing)

    val also =
        Derive.chatNetworkRow("Courier", AgentBeeperNetwork("slack", "Slack", "reading", true))
    assertEquals(Derive.NetworkSwitch.ReadAnyway, also.switch)
    assertTrue(also.on)

    val muted =
        Derive.chatNetworkRow("Courier", AgentBeeperNetwork("telegram", "Telegram", "muted"))
    assertEquals(Derive.NetworkSwitch.Mute, muted.switch)
    assertFalse(muted.on)
    assertEquals("muted in Courier", muted.subtitle)
    val reading =
        Derive.chatNetworkRow("Courier", AgentBeeperNetwork("whatsapp", "WhatsApp", "reading"))
    assertEquals(Derive.NetworkSwitch.Mute, reading.switch)
    assertTrue(reading.on)
  }

  @Test
  public fun `Courier says where its networks and its token come from`() {
    assertEquals(
        "Other networks show here once Courier is being read.",
        Derive.networksLaterLine("Courier", listed = false))
    assertEquals(null, Derive.networksLaterLine("Courier", listed = true))
    assertEquals(null, Derive.networksLaterLine("Beeper", listed = null))
    assertTrue(Derive.courierTokenSteps.contains("Settings › Integrations › New connection…"))
    assertTrue(Derive.courierTokenSteps.contains("Vitruvian Speaker on your Mac"))
    assertFalse(
        "off until a token is saved", Derive.courierSwitchEnabled(hasToken = false, on = false))
    assertTrue("always switchable off", Derive.courierSwitchEnabled(hasToken = false, on = true))
    assertTrue(Derive.courierSwitchEnabled(hasToken = true, on = false))
  }

  @Test
  public fun `a speaker's volume is never shown as a stale number`() {
    assertEquals("40%", Derive.speakerVolumeLabel(true, true, false, 40))
    assertEquals("muted", Derive.speakerVolumeLabel(true, true, true, 40))
    assertEquals("offline", Derive.speakerVolumeLabel(true, false, false, 40))
    assertEquals("n/a", Derive.speakerVolumeLabel(false, true, false, 40))
  }

  // --- battery (API v1.5.1) ----------------------------------------------

  @Test
  public fun `a missing battery temperature is said, never printed as 0 degrees`() {
    assertEquals("no temperature reading", Derive.batteryTemperatureLabel(null))
    assertEquals("no temperature reading", Derive.batteryTemperatureLabel(Double.NaN))
    assertEquals("battery 31°", Derive.batteryTemperatureLabel(30.6))
    // A real zero is still a reading.
    assertEquals("battery 0°", Derive.batteryTemperatureLabel(0.0))
  }

  @Test
  public fun `on AC the adapter draw is the figure, not the battery's zero`() {
    assertEquals(
        "31.6 W from adapter · on AC",
        Derive.batteryPowerLabel(
            onAc = true, charging = false, drawWatts = 0.0, systemWatts = 31.6))
    assertEquals(
        "on AC",
        Derive.batteryPowerLabel(
            onAc = true, charging = false, drawWatts = 0.0, systemWatts = null))
    assertEquals(
        "40 W from adapter · charging",
        Derive.batteryPowerLabel(onAc = true, charging = true, drawWatts = 0.0, systemWatts = 40.0))
    assertEquals(
        "6.4 W · on battery",
        Derive.batteryPowerLabel(
            onAc = false, charging = false, drawWatts = 6.4, systemWatts = 9.0))
  }

  // --- disk ---------------------------------------------------------------

  @Test
  public fun `disk turns amber at 80 and red at 95`() {
    assertEquals(Derive.Fill.Ok, Derive.diskFill(0.0))
    assertEquals(Derive.Fill.Ok, Derive.diskFill(79.99))
    assertEquals(Derive.Fill.Warn, Derive.diskFill(80.0))
    assertEquals(Derive.Fill.Warn, Derive.diskFill(94.9))
    assertEquals(Derive.Fill.Crit, Derive.diskFill(95.0))
    assertEquals(Derive.Fill.Crit, Derive.diskFill(100.0))
    assertEquals(Derive.Fill.Ok, Derive.diskFill(Double.NaN))
  }

  // --- Claude Code summary ------------------------------------------------

  @Test
  public fun `sessions and processes keep their own nouns`() {
    assertEquals("8 sessions · 7 processes", Derive.claudeSummary(8, 0, 7))
    assertEquals("1 session · 1 process · 1 waiting", Derive.claudeSummary(1, 1, 1))
    // Not asked yet: absent, not "0 processes".
    assertEquals("0 sessions", Derive.claudeSummary(0, 0, null))
  }

  // --- Claude Code permission prompts --------------------------------------

  @Test
  public fun `the real pending count wins over the transcript guess, even at zero`() {
    assertEquals(0, Derive.claudeWaitingCount(0, 3))
    assertEquals(2, Derive.claudeWaitingCount(2, 0))
    // No list (older agent, unpaired, unreachable): the guess is all there is.
    assertEquals(3, Derive.claudeWaitingCount(null, 3))
  }

  @Test
  public fun `time left counts down in minutes and seconds`() {
    val now = 1_000_000L
    assertEquals("1:42", Derive.timeLeft(now + 102_000, now))
    assertEquals("0:05", Derive.timeLeft(now + 5_000, now))
    assertEquals("2:00", Derive.timeLeft(now + 120_000, now))
    // Rounded up: the last answerable second is not "0:00".
    assertEquals("0:01", Derive.timeLeft(now + 1, now))
    assertEquals("0:05", Derive.timeLeft(now + 4_001, now))
  }

  @Test
  public fun `a prompt past its deadline, or with none, is expired`() {
    val now = 1_000_000L
    assertEquals("expired", Derive.timeLeft(now, now))
    assertEquals("expired", Derive.timeLeft(now - 3_000, now))
    // Unparseable expires_at arrives as 0: never a made-up countdown.
    assertEquals("expired", Derive.timeLeft(0, now))
  }

  @Test
  public fun `the waiting tag and line say how many`() {
    assertEquals("1 waiting", Derive.claudeWaitingTag(1))
    assertEquals("3 waiting", Derive.claudeWaitingTag(3))
    assertEquals("1 waiting for you", Derive.claudeWaitingLine(1))
    assertEquals("2 waiting for you", Derive.claudeWaitingLine(2))
  }

  @Test
  public fun `a decision logs the tool and project, never the command`() {
    assertEquals(
        "claude · allowed Bash in vitruvian-core",
        Derive.claudeDecisionLog(true, "Bash", "vitruvian-core"))
    assertEquals("claude · denied Edit in app", Derive.claudeDecisionLog(false, "Edit", "app"))
    assertEquals("claude · denied WebFetch", Derive.claudeDecisionLog(false, "WebFetch", ""))
  }

  @Test
  public fun `the hold time reads in minutes when it is whole minutes`() {
    assertEquals("2 min", Derive.waitLabel(120))
    assertEquals("90 s", Derive.waitLabel(90))
    // Not known yet: the contract's default, not "0 s".
    assertEquals("2 min", Derive.waitLabel(0))
  }

  @Test
  public fun `the hook toggle says what it will change, and how to undo it`() {
    val off = Derive.claudeHookExplanation(false, "atlas", 120)
    assertEquals(
        "Adds a hook to Claude Code on atlas (~/.claude/settings.json, a backup is kept). " +
            "Prompts then come here first; unanswered for 2 min, they show on the Mac as usual. " +
            Derive.CLAUDE_HOOK_REACH,
        off)
    assertTrue(Derive.claudeHookExplanation(true, "atlas", 120).startsWith("Hook installed."))
    // Both states say which sessions it applies to: found on the real Mac.
    assertTrue(
        Derive.claudeHookExplanation(true, "atlas", 120).contains("started after this is on"))
    assertTrue(Derive.claudeHookExplanation(false, "", 0).contains("on the Mac ("))
    val body = Derive.claudeHookDialogBody("atlas", 90)
    assertTrue(body.contains("~/.claude/settings.json on atlas"))
    assertTrue(body.contains("every Claude Code session"))
    assertTrue(body.contains("Unanswered for 90 s"))
    assertEquals("installing…", Derive.claudeHookBusyLabel(true))
    assertEquals("removing…", Derive.claudeHookBusyLabel(false))
  }

  // --- Antigravity parity (API v1.7) ---------------------------------------

  @Test
  public fun `a session's state becomes its tag and its look`() {
    assertEquals("waiting", Derive.claudeStateLabel("waiting_for_permission"))
    assertEquals(Derive.SessionLook.Waiting, Derive.sessionLook("waiting_for_permission"))
    assertEquals(Derive.SessionLook.Working, Derive.sessionLook("working"))
    assertEquals(Derive.SessionLook.Idle, Derive.sessionLook("IDLE"))
    assertEquals("killed", Derive.claudeStateLabel("killed"))
    assertEquals(Derive.SessionLook.Other, Derive.sessionLook("killed"))
    assertEquals(Derive.SessionLook.Other, Derive.sessionLook(""))
    assertEquals(Derive.SessionLook.Other, Derive.sessionLook("compacting"))
  }

  @Test
  public fun `Antigravity's summary, and the placeholder that says where Send goes`() {
    assertEquals("v1.2.11 · 5 models", Derive.antigravitySummary("1.2.11", 5, null))
    assertEquals("v1.2.11 · 1 model · 1 session", Derive.antigravitySummary("1.2.11", 1, 1))
    assertEquals("New conversation…", Derive.antigravityPlaceholder(null))
    assertEquals("New conversation…", Derive.antigravityPlaceholder(" "))
    assertEquals("Continue \"Fix CI\"…", Derive.antigravityPlaceholder("Fix CI"))
    assertEquals("2 waiting", Derive.claudeWaitingTag(2))
    assertEquals("1 waiting for you", Derive.claudeWaitingLine(1))
  }

  // --- pull request rows --------------------------------------------------

  @Test
  public fun `a PR title drops the owner`() {
    assertEquals(
        "vitruvian-core#2514 · Fix it",
        Derive.prTitle("VitruvianSoftware/vitruvian-core", 2514, "Fix it"))
    assertEquals("solo#3 · T", Derive.prTitle("solo", 3, "T"))
  }

  // --- containers ---------------------------------------------------------

  private data class C(val name: String, val image: String)

  @Test
  public fun `pause sandboxes are recognised by name or image`() {
    assertTrue(Derive.isPauseContainer("k8s_POD_coredns-1_kube-system_uid_0", "whatever"))
    assertTrue(Derive.isPauseContainer("x", "rancher/mirrored-pause:3.6"))
    assertTrue(Derive.isPauseContainer("x", "registry.k8s.io/pause:3.9"))
    assertTrue(Derive.isPauseContainer("x", "registry.k8s.io/pause@sha256:abc"))
    assertFalse(Derive.isPauseContainer("postgres", "postgres:16"))
    assertFalse(Derive.isPauseContainer("x", "someone/pauseless:1"))
  }

  @Test
  public fun `a k8s container name gives its pod`() {
    assertEquals("coredns-1", Derive.k8sPod("k8s_coredns_coredns-1_kube-system_uid_0"))
    assertEquals(null, Derive.k8sPod("postgres"))
    assertEquals(null, Derive.k8sPod("k8s_short"))
  }

  @Test
  public fun `pods collapse, pauses go, plain containers stay in order`() {
    val items =
        listOf(
            C("k8s_POD_web-1_default_u_0", "rancher/mirrored-pause:3.6"),
            C("k8s_app_web-1_default_u_0", "nginx:1"),
            C("postgres", "postgres:16"),
            C("k8s_sidecar_web-1_default_u_0", "envoy:1"),
            C("k8s_coredns_dns-2_kube-system_u_0", "coredns:1"),
        )
    val groups = Derive.groupContainers(items, { it.name }, { it.image })
    assertEquals(
        listOf("web-1 · 2 containers", "postgres", "dns-2 · 1 container"), groups.map { it.title })
    assertEquals(listOf(true, false, true), groups.map { it.pod })
    assertEquals(2, groups[0].members.size)
    assertEquals(1, Derive.pauseCount(items, { it.name }, { it.image }))
  }

  // --- Vitruvian Speaker progressive disclosure ----------------------------------

  @Test
  public fun `quiet hours subtitle reflects active status`() {
    assertEquals(
        "off · plays at any hour", Derive.quietHoursSubtitle(false, false, "22:00", "07:00"))
    assertEquals(
        "active until 07:00 · what you type still plays",
        Derive.quietHoursSubtitle(true, true, "22:00", "07:00"))
    assertEquals(
        "quiet from 22:00 to 07:00", Derive.quietHoursSubtitle(true, false, "22:00", "07:00"))
  }

  @Test
  public fun `tv status orders missing adb and offline ahead of power state`() {
    assertEquals(
        "no adb",
        Derive.tvStatus(available = false, connected = false, awake = false, dreaming = false))
    assertEquals(
        "disconnected",
        Derive.tvStatus(available = true, connected = false, awake = true, dreaming = false))
    assertEquals(
        "dreaming",
        Derive.tvStatus(available = true, connected = true, awake = false, dreaming = true))
    assertEquals(
        "awake",
        Derive.tvStatus(available = true, connected = true, awake = true, dreaming = false))
    assertEquals(
        "standby",
        Derive.tvStatus(available = true, connected = true, awake = false, dreaming = false))
  }

  @Test
  public fun `agent hook status label across all combinations`() {
    // speaksTwice warning takes highest priority
    assertEquals(
        "warning: hook + skill installed (speaks twice)",
        Derive.agentHookStatusLabel(
            hookState = "installed", speaksTwice = true, configuredByInstruction = true))
    assertEquals(
        "warning: hook + skill installed (speaks twice)",
        Derive.agentHookStatusLabel(
            hookState = "stale", speaksTwice = true, configuredByInstruction = false))

    // installed hook
    assertEquals(
        "Stop hook installed",
        Derive.agentHookStatusLabel(
            hookState = "installed", speaksTwice = false, configuredByInstruction = false))
    assertEquals(
        "Stop hook installed",
        Derive.agentHookStatusLabel(
            hookState = "installed", speaksTwice = false, configuredByInstruction = true))

    // stale hook
    assertEquals(
        "Stop hook outdated",
        Derive.agentHookStatusLabel(
            hookState = "stale", speaksTwice = false, configuredByInstruction = false))

    // instruction only
    assertEquals(
        "Instruction configured in prompt",
        Derive.agentHookStatusLabel(
            hookState = "none", speaksTwice = false, configuredByInstruction = true))

    // none
    assertEquals(
        "Not installed",
        Derive.agentHookStatusLabel(
            hookState = "none", speaksTwice = false, configuredByInstruction = false))
    assertEquals(
        "Not installed",
        Derive.agentHookStatusLabel(
            hookState = "", speaksTwice = false, configuredByInstruction = false))
  }

  // --- demand-driven polling ----------------------------------------------

  private val tick = 1500L

  private fun view(
      page: PollPage,
      module: String = "claude",
      dashboards: Boolean = true,
      foreground: Boolean = true,
  ) = PollView(page, module, dashboards, foreground)

  /** Everything fetched at [at], so only cadence decides what is due next. */
  private fun allFetchedAt(at: Long): Map<PollSource, Long> =
      PollSource.values().associateWith { at }

  private val chrome = setOf(PollSource.Metrics, PollSource.Host)

  @Test
  public fun `an idle Home asks only for what Home draws`() {
    val due = Derive.pollDue(view(PollPage.Home), tick, nowMs = 0, lastFetchedMs = emptyMap())
    assertEquals(
        chrome +
            setOf(
                PollSource.ClaudeSessions,
                PollSource.Sessions,
                PollSource.Prs,
                PollSource.Antigravity,
                PollSource.Ollama,
                PollSource.Vms,
                PollSource.K8s,
                PollSource.Argo,
                PollSource.Containers,
                PollSource.VitruvianSpeaker,
            ),
        due,
    )
    // The ones nothing on Home draws: the TV, the speaker's volume, the Mac
    // screen's process list and power plates, the Remote's audio.
    for (hidden in
        listOf(
            PollSource.Tv,
            PollSource.SpeakerVolume,
            PollSource.Processes,
            PollSource.Audio,
            PollSource.Power,
            PollSource.Tools,
            PollSource.Notify,
            PollSource.AntigravitySessions,
        )) {
      assertFalse("$hidden is not on Home", hidden in due)
    }
  }

  @Test
  public fun `Home summary rows refresh slower than an open dashboard`() {
    val home = view(PollPage.Home)
    val fetched = allFetchedAt(0)
    // A slow tick later: an open dashboard would ask again; Home's one-line
    // summary does not, but metrics and the Claude rows still do.
    val atSlowTick = Derive.pollDue(home, tick, tick * Derive.SLOW_POLL_EVERY, fetched)
    assertFalse(PollSource.VitruvianSpeaker in atSlowTick)
    assertFalse(PollSource.Ollama in atSlowTick)
    assertTrue(PollSource.Metrics in atSlowTick)
    assertTrue(PollSource.ClaudeSessions in atSlowTick)
    assertTrue(PollSource.Sessions in atSlowTick)
    val atSummary = Derive.pollDue(home, tick, Derive.SUMMARY_POLL_MS, fetched)
    assertTrue(PollSource.VitruvianSpeaker in atSummary)
    assertTrue(PollSource.Argo in atSummary)
    // GitHub keeps its own minute even on Home.
    assertFalse(PollSource.Prs in atSummary)
    assertTrue(PollSource.Prs in Derive.pollDue(home, tick, Derive.PR_POLL_MS, fetched))
  }

  @Test
  public fun `the Vitruvian Speaker module asks for the speaker and nothing else`() {
    val due = Derive.pollDue(view(PollPage.Apps, "speaker"), tick, 0, lastFetchedMs = emptyMap())
    assertEquals(chrome + setOf(PollSource.VitruvianSpeaker, PollSource.SpeakerVolume), due)
  }

  @Test
  public fun `the TV is asked for only on the TV module`() {
    for (page in PollPage.values()) {
      for (module in listOf("claude", "speaker", "prs", "homelab", "lima", "docker")) {
        assertFalse(
            "tv asked on $page/$module",
            PollSource.Tv in Derive.pollDue(view(page, module), tick, 0, emptyMap()))
      }
    }
    assertEquals(
        chrome + PollSource.Tv, Derive.pollDue(view(PollPage.Apps, "tv"), tick, 0, emptyMap()))
    // The gallery is a different view of Apps: it reads the tool inventory.
    assertEquals(
        chrome + PollSource.Tools,
        Derive.pollDue(view(PollPage.Apps, "tv", dashboards = false), tick, 0, emptyMap()))
  }

  @Test
  public fun `each module asks for its own sources`() {
    fun extras(module: String) =
        Derive.pollDue(view(PollPage.Apps, module), tick, 0, emptyMap()) - chrome
    assertEquals(setOf(PollSource.Argo, PollSource.K8s), extras("homelab"))
    assertEquals(setOf(PollSource.Vms), extras("lima"))
    assertEquals(setOf(PollSource.Ollama), extras("ollama"))
    assertEquals(setOf(PollSource.Prs), extras("prs"))
    assertEquals(setOf(PollSource.Containers), extras("docker"))
    assertEquals(setOf(PollSource.ClaudeSessions, PollSource.Sessions), extras("claude"))
    assertEquals(
        setOf(PollSource.Antigravity, PollSource.AntigravitySessions), extras("antigravity"))
    // Grafana's query is run when the module opens, not on the tick.
    assertEquals(emptySet<PollSource>(), extras("grafana"))
  }

  @Test
  public fun `other screens ask for what they draw`() {
    fun extras(page: PollPage) = Derive.pollDue(view(page), tick, 0, emptyMap()) - chrome
    assertEquals(setOf(PollSource.Audio), extras(PollPage.Remote))
    assertEquals(
        setOf(
            PollSource.Processes,
            PollSource.Vms,
            PollSource.Containers,
            PollSource.K8s,
            PollSource.Power,
        ),
        extras(PollPage.Mac),
    )
    assertEquals(setOf(PollSource.Notify), extras(PollPage.Hosts))
    assertEquals(emptySet<PollSource>(), extras(PollPage.Console))
  }

  @Test
  public fun `opening a module fetches at once rather than at the next slow tick`() {
    // Vitruvian Speaker was read for Home's row two seconds ago: not due on Home,
    // and under the old fixed cadence not due for another slow tick either.
    val last = allFetchedAt(0)
    val now = 2_000L
    assertFalse(PollSource.VitruvianSpeaker in Derive.pollDue(view(PollPage.Home), tick, now, last))
    // The volume has never been asked for at all, so opening the module asks
    // for it immediately.
    val lastNoVolume = last - PollSource.SpeakerVolume
    val opened = Derive.pollDue(view(PollPage.Apps, "speaker"), tick, now, lastNoVolume)
    assertTrue(PollSource.SpeakerVolume in opened)
    // And a source that went stale while it was off screen is due the moment
    // it comes back, whatever the tick count says.
    val tvLast = mapOf(PollSource.Tv to 0L)
    assertTrue(PollSource.Tv in Derive.pollDue(view(PollPage.Apps, "tv"), tick, 60_000, tvLast))
    assertEquals(
        Derive.MIN_POLL_WAIT_MS,
        Derive.pollWaitMs(view(PollPage.Apps, "tv"), tick, 60_000, allFetchedAt(60_000) + tvLast))
  }

  @Test
  public fun `a module that has just come on screen is refreshed whatever its cadence says`() {
    // The 30 s refresh setting: the TV's slow cadence is 90 s, and it was read
    // a minute ago. Without the transition it would sit on that reading for
    // another half minute after being opened.
    val slowTick = 30_000L
    val homeVisible = Derive.pollCadences(view(PollPage.Home), slowTick)
    val tv = view(PollPage.Apps, "tv")
    val last = allFetchedAt(0)
    assertFalse(PollSource.Tv in Derive.pollDue(tv, slowTick, 60_000, last))
    assertTrue(PollSource.Tv in Derive.pollDue(tv, slowTick, 60_000, last, homeVisible))
    // Home read Vitruvian Speaker for its row a moment ago; opening the module
    // still asks again, and for the volume Home never shows.
    val speaker = view(PollPage.Apps, "speaker")
    assertEquals(
        setOf(PollSource.VitruvianSpeaker, PollSource.SpeakerVolume),
        Derive.pollDue(speaker, tick, 100, last, Derive.pollCadences(view(PollPage.Home), tick)))
    // Once it has been on screen for a pass, the cadence takes over again.
    val speakerVisible = Derive.pollCadences(speaker, tick)
    assertEquals(emptySet<PollSource>(), Derive.pollDue(speaker, tick, 100, last, speakerVisible))
    // And coming back to the foreground is a transition too.
    val awayVisible = Derive.pollCadences(speaker.copy(foreground = false), tick)
    // Everything on screen is asked for at once, host identity included.
    assertEquals(
        chrome + setOf(PollSource.VitruvianSpeaker, PollSource.SpeakerVolume),
        Derive.pollDue(speaker, tick, 100, last, awayVisible))
  }

  @Test
  public fun `a visible module keeps its cadence`() {
    val tv = view(PollPage.Apps, "tv")
    val last = allFetchedAt(0)
    val slow = tick * Derive.SLOW_POLL_EVERY
    assertFalse(PollSource.Tv in Derive.pollDue(tv, tick, slow - 1, last))
    assertTrue(PollSource.Tv in Derive.pollDue(tv, tick, slow, last))
    // Metrics keep the tick.
    assertTrue(PollSource.Metrics in Derive.pollDue(tv, tick, tick, last))
  }

  @Test
  public fun `backgrounded, the app asks only whether the Mac still answers`() {
    val away = view(PollPage.Apps, "speaker", foreground = false)
    val last = allFetchedAt(0)
    // Nothing for a long while after the last read...
    assertEquals(
        emptySet<PollSource>(), Derive.pollDue(away, tick, Derive.BACKGROUND_POLL_MS - 1, last))
    // ...and then the reachability check alone: no speaker, no sessions, no
    // PRs, however stale they are.
    assertEquals(
        setOf(PollSource.Metrics), Derive.pollDue(away, tick, 10 * Derive.PR_POLL_MS, last))
    // Host identity only if it was never read (Wake-on-LAN needs the MAC).
    assertEquals(chrome, Derive.pollDue(away, tick, 0, emptyMap()))
    // Coming back is an immediate refresh of what is on screen.
    val back = away.copy(foreground = true)
    assertEquals(
        setOf(PollSource.Metrics, PollSource.VitruvianSpeaker, PollSource.SpeakerVolume),
        Derive.pollDue(back, tick, Derive.BACKGROUND_POLL_MS, last))
  }

  @Test
  public fun `an old agent is asked for Antigravity sessions only on the slow tick`() {
    val legacy = view(PollPage.Apps, "antigravity").copy(antigravitySessionsSupported = false)
    val last = allFetchedAt(0)
    assertFalse(PollSource.AntigravitySessions in Derive.pollDue(legacy, tick, tick, last))
    assertTrue(
        PollSource.AntigravitySessions in
            Derive.pollDue(legacy, tick, tick * Derive.SLOW_POLL_EVERY, last))
    val current = view(PollPage.Apps, "antigravity")
    assertTrue(PollSource.AntigravitySessions in Derive.pollDue(current, tick, tick, last))
  }

  @Test
  public fun `the loop sleeps until the next due source, within bounds`() {
    val home = view(PollPage.Home)
    // Everything just fetched: the next thing due is metrics, one tick out.
    assertEquals(tick, Derive.pollWaitMs(home, tick, 0, allFetchedAt(0)))
    assertEquals(500L, Derive.pollWaitMs(home, tick, 1_000, allFetchedAt(0)))
    // Something due now still sleeps the floor, so an unreachable Mac cannot spin the loop.
    assertEquals(Derive.MIN_POLL_WAIT_MS, Derive.pollWaitMs(home, tick, 0, emptyMap()))
    // Backgrounded, still ticks (pairing and the trust timer ride the loop).
    val away = home.copy(foreground = false)
    assertEquals(tick, Derive.pollWaitMs(away, tick, 0, allFetchedAt(0)))
  }

  /**
   * The point of all this, counted: a minute on an idle Home screen against the old loop, which
   * asked for every endpoint on a fixed cadence whatever was on screen.
   */
  @Test
  public fun `an idle minute on Home costs a fraction of the old fixed cadence`() {
    val minute = 60_000L
    val ticks = (minute / tick).toInt()
    // The old loop, per tick: metrics, processes, audio, Claude sessions,
    // Antigravity sessions; every third tick twelve more plus two PromQL
    // queries; PRs once a minute; host every 40.
    val old = ticks * 5 + (ticks + 2) / 3 * 14 + 1 + 1 + ticks / 40
    fun simulate(v: PollView): Map<PollSource, Int> {
      val last = HashMap<PollSource, Long>()
      val counts = HashMap<PollSource, Int>()
      var now = 0L
      while (now < minute) {
        for (s in Derive.pollDue(v, tick, now, last)) {
          last[s] = now
          counts[s] = (counts[s] ?: 0) + 1
        }
        now += Derive.pollWaitMs(v, tick, now, last)
      }
      return counts
    }
    val home = simulate(view(PollPage.Home))
    val homeTotal = home.values.sum()
    assertTrue("idle Home made $homeTotal requests vs $old", homeTotal * 2 < old)
    assertEquals(null, home[PollSource.Tv])
    assertEquals(null, home[PollSource.SpeakerVolume])
    // Vitruvian Speaker's row: once on arrival, then every SUMMARY_POLL_MS.
    assertEquals((minute / Derive.SUMMARY_POLL_MS).toInt(), home[PollSource.VitruvianSpeaker])
    val speaker = simulate(view(PollPage.Apps, "speaker"))
    assertEquals(
        setOf(
            PollSource.Metrics,
            PollSource.Host,
            PollSource.VitruvianSpeaker,
            PollSource.SpeakerVolume),
        speaker.keys)
    val away = simulate(view(PollPage.Home, foreground = false))
    assertEquals(mapOf(PollSource.Metrics to 2, PollSource.Host to 1), away)
  }

  @Test
  public fun `quiet hours metric sub-line distinguishes disabled, active and scheduled`() {
    assertEquals(
        "always speaks",
        Derive.quietHoursMetricSub(enabled = false, active = false, start = "22:00"))
    assertEquals(
        "always speaks",
        Derive.quietHoursMetricSub(enabled = false, active = true, start = "22:00"))
    assertEquals(
        "quiet now", Derive.quietHoursMetricSub(enabled = true, active = true, start = "22:00"))
    assertEquals(
        "quiet from 22:00",
        Derive.quietHoursMetricSub(enabled = true, active = false, start = "22:00"))
    // No start reported: the phone invents none.
    assertEquals(
        "quiet hours on", Derive.quietHoursMetricSub(enabled = true, active = false, start = ""))
  }

  @Test
  public fun `chat monitor diagnostics and Google Chat account row surface errors and accounts`() {
    assertEquals(
        "Monitoring chat apps · last checked 2 min ago",
        Derive.chatMonitorSubtitle(running = true, lastPollRelative = "2 min ago"))
    assertEquals(
        "Monitoring chat apps in background",
        Derive.chatMonitorSubtitle(running = true, lastPollRelative = ""))
    assertEquals(
        "Stopped · background monitor is not running",
        Derive.chatMonitorSubtitle(running = false, lastPollRelative = "2 min ago"))

    assertEquals(null, Derive.chatDiagnosticError("   "))
    assertEquals("Slack auth_revoked", Derive.chatDiagnosticError(" Slack auth_revoked "))

    assertEquals(
        "Token saved on Mac · signed in as @james",
        Derive.slackTokenSubtitle(hasToken = true, slackIdentity = "@james"))
    assertEquals(
        "Token saved on Mac", Derive.slackTokenSubtitle(hasToken = true, slackIdentity = ""))
    assertEquals(
        "Tap to paste user token (xoxp-...)",
        Derive.slackTokenSubtitle(hasToken = false, slackIdentity = "@james"))

    assertEquals(
        "currently reading via Google API (this app's login)",
        Derive.googleChatSourceSubtitle(
            activeBackendLabel = "Google API (this app's login)", monitorRunning = true))
    assertEquals(
        "currently reading via gws command-line tool",
        Derive.googleChatSourceSubtitle(
            activeBackendLabel = "gws command-line tool", monitorRunning = true))
    assertEquals(
        "which backend reads Google Chat",
        Derive.googleChatSourceSubtitle(activeBackendLabel = "Google API", monitorRunning = false))

    val apiOk =
        Derive.googleChatAccountDiag(
            source = "api",
            activeBackend = "api",
            accountEmail = "james@abrial.ai",
            gwsAccount = "",
            hasChatAccess = true,
            gwsInstalled = false)
    assertTrue(apiOk.healthy)
    assertEquals("james@abrial.ai", apiOk.account)
    assertEquals("james@abrial.ai · Chat access granted", apiOk.subtitle)
    assertEquals("signed in", apiOk.trailing)

    val apiMissing =
        Derive.googleChatAccountDiag(
            source = "api",
            activeBackend = "",
            accountEmail = "james@abrial.ai",
            gwsAccount = "",
            hasChatAccess = false,
            gwsInstalled = true)
    assertFalse(apiMissing.healthy)
    assertEquals("james@abrial.ai · Chat access not granted on Mac", apiMissing.subtitle)

    val gwsOk =
        Derive.googleChatAccountDiag(
            source = "gws",
            activeBackend = "gws",
            accountEmail = "james@gmail.com",
            gwsAccount = "james@work.com",
            hasChatAccess = false,
            gwsInstalled = true)
    assertTrue(gwsOk.healthy)
    assertEquals("james@work.com", gwsOk.account)
    assertEquals("james@work.com · via gws CLI", gwsOk.subtitle)
    assertEquals("gws", gwsOk.trailing)
  }

  @Test
  public fun `visible module ids retain installed modules and drop unknown ids like xcode`() {
    val galleryIds =
        listOf(
            "claude",
            "antigravity",
            "prs",
            "homelab",
            "lima",
            "docker",
            "grafana",
            "ollama",
            "speaker",
            "tv",
        )
    val installed = setOf("claude", "docker", "ollama", "grafana", "xcode")
    val availableDashboards = galleryIds.toSet()
    assertEquals(
        listOf("claude", "docker", "grafana", "ollama"),
        Derive.visibleModuleIds(galleryIds, installed, availableDashboards))
    assertEquals(
        listOf("claude", "docker", "ollama", "grafana"),
        Derive.filterInstalledModules(
            listOf("claude", "xcode", "docker", "ollama", "grafana", "unknown"),
            galleryIds.toSet()))
  }

  @Test
  public fun `Google Cloud OAuth section rows cover empty, client ID only, and both set`() {
    // 1. Empty: Client ID shows "Not set · needed for Google Chat" and is enabled; Secret shows
    // "Not set" and is disabled until a client ID exists.
    val (emptyId, emptySecret) = Derive.oauthSectionRows(clientId = "", hasSecret = false)
    assertEquals("OAuth Client ID", emptyId.title)
    assertEquals("Not set · needed for Google Chat", emptyId.subtitle)
    assertEquals("none", emptyId.trailing)
    assertFalse(emptyId.healthy)
    assertFalse(emptyId.hasValue)
    assertTrue(emptyId.enabled)
    assertEquals("Set…", Derive.promptButtonLabel(secret = false, hasValue = emptyId.hasValue))

    assertEquals("OAuth Client Secret", emptySecret.title)
    assertEquals("Not set", emptySecret.subtitle)
    assertEquals("missing", emptySecret.trailing)
    assertFalse(emptySecret.healthy)
    assertFalse(emptySecret.hasValue)
    assertFalse(emptySecret.enabled)

    // 2. Client ID only: Client ID is configured and editable; Secret becomes enabled for pasting.
    val (idOnlyId, idOnlySecret) =
        Derive.oauthSectionRows(clientId = "12345.apps.googleusercontent.com", hasSecret = false)
    assertEquals("12345.apps.googleusercontent.com", idOnlyId.subtitle)
    assertEquals("configured", idOnlyId.trailing)
    assertTrue(idOnlyId.healthy)
    assertTrue(idOnlyId.hasValue)
    assertTrue(idOnlyId.enabled)
    assertEquals("Edit…", Derive.promptButtonLabel(secret = false, hasValue = idOnlyId.hasValue))

    assertEquals("Tap to paste client secret", idOnlySecret.subtitle)
    assertEquals("missing", idOnlySecret.trailing)
    assertFalse(idOnlySecret.healthy)
    assertFalse(idOnlySecret.hasValue)
    assertTrue(idOnlySecret.enabled)
    assertEquals("Set…", Derive.promptButtonLabel(secret = true, hasValue = idOnlySecret.hasValue))

    // 3. Both set: both rows are healthy, enabled, and carry values.
    val (bothId, bothSecret) =
        Derive.oauthSectionRows(clientId = "12345.apps.googleusercontent.com", hasSecret = true)
    assertEquals("12345.apps.googleusercontent.com", bothId.subtitle)
    assertEquals("configured", bothId.trailing)
    assertTrue(bothId.healthy)
    assertTrue(bothId.hasValue)
    assertTrue(bothId.enabled)

    assertEquals("Client secret saved on Mac", bothSecret.subtitle)
    assertEquals("saved", bothSecret.trailing)
    assertTrue(bothSecret.healthy)
    assertTrue(bothSecret.hasValue)
    assertTrue(bothSecret.enabled)
    assertEquals(
        "Replace…", Derive.promptButtonLabel(secret = true, hasValue = bothSecret.hasValue))
  }

  @Test
  public fun `Vitruvian Speaker Now strip quick actions cover mute, quiet hours, room and replay states`() {
    // 1. Mute / Unmute: enabled whenever volume is available and online (even when speakHome is
    // off); disabled and omits "n/a" when volume is unavailable.
    val unmuted =
        Derive.muteQuickAction(
            paired = true, volumeAvailable = true, volumeOnline = true, muted = false, percent = 45)
    assertEquals("Mute", unmuted.label)
    assertEquals("45%", unmuted.secondary)
    assertTrue(unmuted.enabled)
    assertFalse(unmuted.active)
    assertEquals("Mute speaker, volume 45%", unmuted.contentDescription)

    val muted =
        Derive.muteQuickAction(
            paired = true, volumeAvailable = true, volumeOnline = true, muted = true, percent = 45)
    assertEquals("Unmute", muted.label)
    assertEquals("muted", muted.secondary)
    assertTrue(muted.enabled)
    assertTrue(muted.active)
    assertEquals("Unmute speaker, currently muted", muted.contentDescription)

    val offline =
        Derive.muteQuickAction(
            paired = true,
            volumeAvailable = true,
            volumeOnline = false,
            muted = false,
            percent = 45)
    assertEquals("Mute", offline.label)
    assertEquals("offline", offline.secondary)
    assertFalse(offline.enabled)
    assertFalse(offline.active)

    val unavailable =
        Derive.muteQuickAction(
            paired = true,
            volumeAvailable = false,
            volumeOnline = false,
            muted = false,
            percent = 0)
    assertEquals("Mute", unavailable.label)
    assertNull(unavailable.secondary)
    assertFalse(unavailable.enabled)

    // 2. Quiet hours: active now, enabled but outside window, off, and no Mac (omits default
    // window)
    val quietNow =
        Derive.quietHoursQuickAction(
            paired = true,
            available = true,
            enabled = true,
            active = true,
            start = "22:00",
            end = "07:00")
    assertEquals("Quiet on", quietNow.label)
    assertEquals("22:00–07:00 · now", quietNow.secondary)
    assertTrue(quietNow.enabled)
    assertTrue(quietNow.active)

    val quietStandby =
        Derive.quietHoursQuickAction(
            paired = true,
            available = true,
            enabled = true,
            active = false,
            start = "22:00",
            end = "07:00")
    assertEquals("Quiet on", quietStandby.label)
    assertEquals("22:00–07:00", quietStandby.secondary)
    assertTrue(quietStandby.enabled)
    assertTrue(quietStandby.active)

    val quietOff =
        Derive.quietHoursQuickAction(
            paired = true,
            available = true,
            enabled = false,
            active = false,
            start = "22:00",
            end = "07:00")
    assertEquals("Quiet off", quietOff.label)
    assertEquals("22:00–07:00", quietOff.secondary)
    assertTrue(quietOff.enabled)
    assertFalse(quietOff.active)

    val quietNoMac =
        Derive.quietHoursQuickAction(
            paired = false,
            available = false,
            enabled = false,
            active = false,
            start = "",
            end = "")
    assertEquals("Quiet off", quietNoMac.label)
    assertNull(quietNoMac.secondary)
    assertFalse(quietNoMac.enabled)

    // 3. Room: selected speaker vs none (omits "none")
    val room =
        Derive.roomQuickAction(
            paired = true,
            available = true,
            targetName = "Lake Office display",
            targetRoom = "Lake Office",
            targetType = "Device",
            hasChoices = true)
    assertEquals("Lake Office display", room.label)
    assertEquals("Lake Office", room.secondary)
    assertTrue(room.enabled)
    assertTrue(room.active)

    val noRoom =
        Derive.roomQuickAction(paired = true, available = true, targetName = "", hasChoices = false)
    assertEquals("Room", noRoom.label)
    assertNull(noRoom.secondary)
    assertFalse(noRoom.enabled)

    // 4. Replay: nothing to replay (omits "none") vs newest item available
    val noReplay =
        Derive.replayQuickAction(
            paired = true, available = true, installed = true, hasReplay = false, target = null)
    assertEquals("Replay", noReplay.label)
    assertNull(noReplay.secondary)
    assertFalse(noReplay.enabled)

    val withReplay =
        Derive.replayQuickAction(
            paired = true, available = true, installed = true, hasReplay = true, target = "Kitchen")
    assertEquals("Replay", withReplay.label)
    // No helper line: the room name described nothing about what is replayed.
    assertNull(withReplay.secondary)
    assertTrue(withReplay.enabled)

    // 5. newestBroadcast picks recent.firstOrNull() verbatim (same item as Recent broadcasts row 0)
    val firstBlank =
        AgentLastBroadcast(text = "", target = "Office", source = "cli", at = "now", id = "id-1")
    val secondText =
        AgentLastBroadcast(
            text = "Hello", target = "Office", source = "cli", at = "earlier", id = "id-2")
    assertEquals(
        firstBlank, Derive.newestBroadcast(listOf(firstBlank, secondText), last = secondText))
    assertEquals(secondText, Derive.newestBroadcast(emptyList(), last = secondText))
    assertNull(Derive.newestBroadcast(emptyList(), last = null))

    // Full strip order: mute, quiet_hours, room, replay, snooze
    val strip =
        Derive.vitruvianSpeakerQuickActions(
            paired = true,
            available = true,
            installed = true,
            volumeAvailable = true,
            volumeOnline = true,
            muted = false,
            percent = 60,
            quietEnabled = true,
            quietActive = true,
            quietStart = "22:00",
            quietEnd = "07:00",
            targetName = "Kitchen",
            targetRoom = "Kitchen",
            hasRoomChoices = true,
            hasReplay = true,
            replayTarget = "Kitchen",
        )
    assertEquals(listOf("mute", "quiet_hours", "room", "replay", "snooze"), strip.map { it.id })
  }

  @Test
  public fun `snoozeQuickAction covers ready, active snooze in local time, expired, garbage, unpaired and offline states`() {
    val zone = java.time.ZoneId.of("America/Los_Angeles")
    // 2026-11-10T06:00:00Z -> 1762754400000L
    val nowMs = java.time.Instant.parse("2026-11-10T06:00:00Z").toEpochMilli()

    // 1. Not snoozed (null)
    val idle =
        Derive.snoozeQuickAction(
            paired = true, available = true, snoozeUntil = null, nowMs = nowMs, zoneId = zone)
    assertEquals("snooze", idle.id)
    assertEquals("Snooze 30m", idle.label)
    assertNull(idle.secondary)
    assertTrue(idle.enabled)
    assertFalse(idle.active)
    assertEquals("Snooze announcements for 30 minutes", idle.contentDescription)

    // 2. Actively snoozed (2026-11-10T06:30:00Z is 22:30 on 2026-11-09 in America/Los_Angeles PST)
    val active =
        Derive.snoozeQuickAction(
            paired = true,
            available = true,
            snoozeUntil = "2026-11-10T06:30:00Z",
            nowMs = nowMs,
            zoneId = zone)
    assertEquals("Snoozed", active.label)
    assertEquals("until 22:30", active.secondary)
    assertTrue(active.enabled)
    assertTrue(active.active)
    assertEquals("Snoozed until 22:30, tap to resume", active.contentDescription)

    val activeFractional =
        Derive.snoozeQuickAction(
            paired = true,
            available = true,
            snoozeUntil = "2026-11-10T06:30:00.500Z",
            nowMs = nowMs,
            zoneId = zone)
    assertEquals("Snoozed", activeFractional.label)
    assertEquals("until 22:30", activeFractional.secondary)
    assertTrue(activeFractional.enabled)
    assertTrue(activeFractional.active)
    assertEquals("Snoozed until 22:30, tap to resume", activeFractional.contentDescription)

    // 3. Expired snooze (equal to or before nowMs)
    val exactBoundary =
        Derive.snoozeQuickAction(
            paired = true,
            available = true,
            snoozeUntil = "2026-11-10T06:00:00Z",
            nowMs = nowMs,
            zoneId = zone)
    assertEquals("Snooze 30m", exactBoundary.label)
    assertNull(exactBoundary.secondary)
    assertFalse(exactBoundary.active)

    val expired =
        Derive.snoozeQuickAction(
            paired = true,
            available = true,
            snoozeUntil = "2026-11-10T05:30:00Z",
            nowMs = nowMs,
            zoneId = zone)
    assertEquals("Snooze 30m", expired.label)
    assertNull(expired.secondary)
    assertFalse(expired.active)

    // 4. Unparseable / garbage value treated as not snoozed
    val garbage =
        Derive.snoozeQuickAction(
            paired = true,
            available = true,
            snoozeUntil = "not-a-date",
            nowMs = nowMs,
            zoneId = zone)
    assertEquals("Snooze 30m", garbage.label)
    assertNull(garbage.secondary)
    assertFalse(garbage.active)

    // 5. Unpaired or offline disables the control
    val unpaired =
        Derive.snoozeQuickAction(
            paired = false,
            available = true,
            snoozeUntil = "2026-11-10T06:30:00Z",
            nowMs = nowMs,
            zoneId = zone)
    assertEquals("Snoozed", unpaired.label)
    assertEquals("until 22:30", unpaired.secondary)
    assertFalse(unpaired.enabled)
    assertTrue(unpaired.active)

    val offline =
        Derive.snoozeQuickAction(
            paired = true,
            available = false,
            snoozeUntil = "2026-11-10T06:30:00Z",
            nowMs = nowMs,
            zoneId = zone)
    assertEquals("Snooze 30m", offline.label)
    assertNull(offline.secondary)
    assertFalse(offline.enabled)
    assertFalse(offline.active)
  }

  @Test
  public fun `shouldNotifyAnnouncement suppresses first load, same id, disabled setting and notifies on new id`() {
    // Disabled setting never notifies
    assertFalse(Derive.shouldNotifyAnnouncement(previousId = "b-1", newId = "b-2", enabled = false))

    // First load (previousId == null or blank) never notifies
    assertFalse(Derive.shouldNotifyAnnouncement(previousId = null, newId = "b-1", enabled = true))
    assertFalse(Derive.shouldNotifyAnnouncement(previousId = "  ", newId = "b-1", enabled = true))

    // Same id as already observed when setting was turned on or on previous poll never notifies
    assertFalse(Derive.shouldNotifyAnnouncement(previousId = "b-1", newId = "b-1", enabled = true))
    assertFalse(
        Derive.shouldNotifyAnnouncement(previousId = " b-1 ", newId = "b-1", enabled = true))

    // Missing or sentinel new id never notifies
    assertFalse(Derive.shouldNotifyAnnouncement(previousId = "b-1", newId = null, enabled = true))
    assertFalse(Derive.shouldNotifyAnnouncement(previousId = "b-1", newId = "", enabled = true))
    assertFalse(
        Derive.shouldNotifyAnnouncement(
            previousId = "b-1", newId = Derive.NO_ANNOUNCEMENT_ID, enabled = true))

    // New announcement after an earlier one (or after NO_ANNOUNCEMENT_ID baseline) notifies
    assertTrue(Derive.shouldNotifyAnnouncement(previousId = "b-1", newId = "b-2", enabled = true))
    assertTrue(
        Derive.shouldNotifyAnnouncement(
            previousId = Derive.NO_ANNOUNCEMENT_ID, newId = "b-1", enabled = true))
  }

  @Test
  public fun `mirrorToggle seeds baseline without notifying on enable and cancels active notification on disable or permission denial`() {
    val b1 =
        AgentLastBroadcast(
            text = "Dinner is ready", target = "Kitchen", source = "user", at = "now", id = " b-1 ")
    val b2 =
        AgentLastBroadcast(
            text = "Earlier", target = "Kitchen", source = "user", at = "earlier", id = "b-0")

    // 1. Toggled ON with permission while speaker is available and has broadcasts:
    // seeds baselineId to newest id ("b-1") and emits None (never notifies for already-latest).
    val enabledWithExisting =
        Derive.mirrorToggle(
            requestedOn = true,
            permissionGranted = true,
            state = Derive.MirrorState(),
            available = true,
            recent = listOf(b1, b2),
            last = b2,
        )
    assertTrue(enabledWithExisting.enabled)
    assertEquals("b-1", enabledWithExisting.state.baselineId)
    assertEquals(Derive.MirrorNotificationAction.None, enabledWithExisting.action)

    // 2. Toggled ON when recent is empty and only `last` is populated: falls back to `last`.
    val enabledWithLastFallback =
        Derive.mirrorToggle(
            requestedOn = true,
            permissionGranted = true,
            state = Derive.MirrorState(),
            available = true,
            recent = emptyList(),
            last = b2,
        )
    assertTrue(enabledWithLastFallback.enabled)
    assertEquals("b-0", enabledWithLastFallback.state.baselineId)
    assertEquals(Derive.MirrorNotificationAction.None, enabledWithLastFallback.action)

    // 3. Toggled ON when available with no broadcasts yet: seeds NO_ANNOUNCEMENT_ID so the very
    // next real announcement triggers a notification.
    val enabledEmpty =
        Derive.mirrorToggle(
            requestedOn = true,
            permissionGranted = true,
            state = Derive.MirrorState(),
            available = true,
            recent = emptyList(),
            last = null,
        )
    assertTrue(enabledEmpty.enabled)
    assertEquals(Derive.NO_ANNOUNCEMENT_ID, enabledEmpty.state.baselineId)
    assertEquals(Derive.MirrorNotificationAction.None, enabledEmpty.action)

    // 4. Toggled ON while Vitruvian Speaker is not available yet: keeps baselineId null so the
    // first
    // reachable poll still acts as first load and does not notify.
    val enabledOffline =
        Derive.mirrorToggle(
            requestedOn = true,
            permissionGranted = true,
            state = Derive.MirrorState(baselineId = "stale"),
            available = false,
            recent = listOf(b1),
            last = b1,
        )
    assertTrue(enabledOffline.enabled)
    assertNull(enabledOffline.state.baselineId)
    assertEquals(Derive.MirrorNotificationAction.None, enabledOffline.action)

    // 5. Toggled ON when POST_NOTIFICATIONS permission is denied: stays disabled and cancels any
    // active notification.
    val deniedWithActive =
        Derive.mirrorToggle(
            requestedOn = true,
            permissionGranted = false,
            state =
                Derive.MirrorState(
                    baselineId = "b-1",
                    activeNotificationId = "b-1",
                    activeNotificationText = "Dinner is ready",
                ),
            available = true,
            recent = listOf(b1),
        )
    assertFalse(deniedWithActive.enabled)
    assertNull(deniedWithActive.state.activeNotificationId)
    assertEquals(Derive.MirrorNotificationAction.Cancel("b-1"), deniedWithActive.action)

    // 6. Toggled OFF while a notification is active: disables and cancels the active notification.
    val toggledOff =
        Derive.mirrorToggle(
            requestedOn = false,
            permissionGranted = true,
            state =
                Derive.MirrorState(
                    baselineId = "b-1",
                    activeNotificationId = "b-1",
                    activeNotificationText = "Dinner is ready",
                ),
            available = true,
            recent = listOf(b1),
        )
    assertFalse(toggledOff.enabled)
    assertNull(toggledOff.state.activeNotificationId)
    assertNull(toggledOff.state.activeNotificationText)
    assertEquals(Derive.MirrorNotificationAction.Cancel("b-1"), toggledOff.action)
  }

  @Test
  public fun `observeMirrorAnnouncement decides which id to notify and when to post, update, or cancel`() {
    val b1 =
        AgentLastBroadcast(
            text = "Build passed", target = "Office", source = "claude", at = "10:00", id = "b-1")
    val b2 =
        AgentLastBroadcast(
            text = "Deploy complete",
            target = "Office",
            source = "claude",
            at = "10:05",
            id = "b-2")

    // 1. First load (baselineId == null) with mirror enabled: records baselineId = "b-1", does not
    // post.
    val firstLoad =
        Derive.observeMirrorAnnouncement(
            state = Derive.MirrorState(),
            mirrorEnabled = true,
            permissionGranted = true,
            available = true,
            recent = listOf(b1),
        )
    assertEquals("b-1", firstLoad.state.baselineId)
    assertNull(firstLoad.state.activeNotificationId)
    assertEquals(Derive.MirrorNotificationAction.None, firstLoad.action)

    // 2. Subsequent poll with the same announcement id ("b-1"): None.
    val samePoll =
        Derive.observeMirrorAnnouncement(
            state = firstLoad.state,
            mirrorEnabled = true,
            permissionGranted = true,
            available = true,
            recent = listOf(b1),
        )
    assertEquals("b-1", samePoll.state.baselineId)
    assertEquals(Derive.MirrorNotificationAction.None, samePoll.action)

    // 3. New announcement id ("b-2" at recent[0], "b-1" at recent[1]): Posts notification for
    // "b-2".
    val newArrival =
        Derive.observeMirrorAnnouncement(
            state = samePoll.state,
            mirrorEnabled = true,
            permissionGranted = true,
            available = true,
            recent = listOf(b2, b1),
        )
    assertEquals("b-2", newArrival.state.baselineId)
    assertEquals("b-2", newArrival.state.activeNotificationId)
    assertEquals("Deploy complete", newArrival.state.activeNotificationText)
    assertEquals(Derive.MirrorNotificationAction.Post("b-2", "Deploy complete"), newArrival.action)

    // 4. Same active announcement id ("b-2") observed again with unchanged text: None.
    val unchangedActive =
        Derive.observeMirrorAnnouncement(
            state = newArrival.state,
            mirrorEnabled = true,
            permissionGranted = true,
            available = true,
            recent = listOf(b2, b1),
        )
    assertEquals(Derive.MirrorNotificationAction.None, unchangedActive.action)
    assertEquals("b-2", unchangedActive.state.activeNotificationId)

    // 5. Same active announcement id ("b-2") observed with updated text: emits Update.
    val b2Updated = b2.copy(text = "Deploy complete on prod")
    val updatedActive =
        Derive.observeMirrorAnnouncement(
            state = unchangedActive.state,
            mirrorEnabled = true,
            permissionGranted = true,
            available = true,
            recent = listOf(b2Updated, b1),
        )
    assertEquals(
        Derive.MirrorNotificationAction.Update("b-2", "Deploy complete on prod"),
        updatedActive.action)
    assertEquals("Deploy complete on prod", updatedActive.state.activeNotificationText)

    // 6. Active announcement's text becomes blank: cancels active notification.
    val b2BlankText = b2.copy(text = "   ")
    val blankedActive =
        Derive.observeMirrorAnnouncement(
            state = updatedActive.state,
            mirrorEnabled = true,
            permissionGranted = true,
            available = true,
            recent = listOf(b2BlankText),
        )
    assertEquals(Derive.MirrorNotificationAction.Cancel("b-2"), blankedActive.action)
    assertNull(blankedActive.state.activeNotificationId)

    // 7. History cleared (no broadcasts) while a notification is active: cancels active
    // notification and sets baseline to NO_ANNOUNCEMENT_ID.
    val clearedHistory =
        Derive.observeMirrorAnnouncement(
            state = updatedActive.state,
            mirrorEnabled = true,
            permissionGranted = true,
            available = true,
            recent = emptyList(),
            last = null,
        )
    assertEquals(Derive.MirrorNotificationAction.Cancel("b-2"), clearedHistory.action)
    assertEquals(Derive.NO_ANNOUNCEMENT_ID, clearedHistory.state.baselineId)
    assertNull(clearedHistory.state.activeNotificationId)

    // 8. Next real announcement after NO_ANNOUNCEMENT_ID posts notification (including fallback to
    // `last` when `recent` is empty).
    val afterEmpty =
        Derive.observeMirrorAnnouncement(
            state = clearedHistory.state,
            mirrorEnabled = true,
            permissionGranted = true,
            available = true,
            recent = emptyList(),
            last = b1,
        )
    assertEquals(Derive.MirrorNotificationAction.Post("b-1", "Build passed"), afterEmpty.action)
    assertEquals("b-1", afterEmpty.state.baselineId)
    assertEquals("b-1", afterEmpty.state.activeNotificationId)

    // 9. Permission revoked or setting disabled while a notification is active: cancels active
    // notification.
    val permissionLost =
        Derive.observeMirrorAnnouncement(
            state = afterEmpty.state,
            mirrorEnabled = true,
            permissionGranted = false,
            available = true,
            recent = listOf(b1),
        )
    assertFalse(permissionLost.enabled)
    assertEquals(Derive.MirrorNotificationAction.Cancel("b-1"), permissionLost.action)
    assertNull(permissionLost.state.activeNotificationId)

    // 10. Unavailable poll preserves null baseline so the subsequent first available poll still
    // does not notify.
    val unavailableFirst =
        Derive.observeMirrorAnnouncement(
            state = Derive.MirrorState(),
            mirrorEnabled = true,
            permissionGranted = true,
            available = false,
            recent = listOf(b1),
        )
    assertNull(unavailableFirst.state.baselineId)
    assertEquals(Derive.MirrorNotificationAction.None, unavailableFirst.action)
  }

  @Test
  public fun `Quick Settings Speaker tile maps unpaired, unreachable, volume unavailable, muted and active volume`() {
    assertEquals(
        Derive.SpeakerTileSpec(Derive.SpeakerTileLook.Unavailable, "Not paired"),
        Derive.speakerTileState(paired = false, reachable = true, muted = false, percent = 50))
    assertEquals(
        Derive.SpeakerTileSpec(Derive.SpeakerTileLook.Unavailable, "Mac unreachable"),
        Derive.speakerTileState(paired = true, reachable = false))
    assertEquals(
        Derive.SpeakerTileSpec(Derive.SpeakerTileLook.Unavailable, "Volume unavailable"),
        Derive.speakerTileState(paired = true, reachable = true, available = false))
    assertEquals(
        Derive.SpeakerTileSpec(Derive.SpeakerTileLook.Unavailable, "Volume unavailable"),
        Derive.speakerTileState(paired = true, reachable = true, online = false))
    assertEquals(
        Derive.SpeakerTileSpec(Derive.SpeakerTileLook.Unavailable, "Couldn't reach the Mac"),
        Derive.speakerTileState(paired = true, reachable = false, clickFailed = true))
    assertEquals(
        Derive.SpeakerTileSpec(Derive.SpeakerTileLook.Inactive, "Muted"),
        Derive.speakerTileState(
            paired = true,
            reachable = true,
            available = true,
            online = true,
            muted = true,
            percent = 40))
    assertEquals(
        Derive.SpeakerTileSpec(Derive.SpeakerTileLook.Active, "On · 65%"),
        Derive.speakerTileState(
            paired = true,
            reachable = true,
            available = true,
            online = true,
            muted = false,
            percent = 65))
  }

  @Test
  public fun `a Vitruvian Speaker refusal keeps its own words even when it says refused or reset`() {
    // Vitruvian Speaker's --apply messages now reach the phone verbatim; only real network
    // failures may read as "the Mac didn't answer".
    assertEquals(
        "Couldn't change Speak: Vitruvian Speaker refused this change: not a choice",
        Derive.vitruvianSpeakerInlineError(
            what = "change Speak", reason = "Vitruvian Speaker refused this change: not a choice"))
    assertEquals(
        "Couldn't reset: Reset settings is not available while signing in",
        Derive.vitruvianSpeakerInlineError(
            what = "reset", reason = "Reset settings is not available while signing in"))
    assertEquals(
        "Couldn't mute: the Mac didn't answer",
        Derive.vitruvianSpeakerInlineError(
            what = "mute", reason = "java.net.ConnectException: Connection refused"))
    assertEquals(
        "Couldn't mute: the Mac didn't answer",
        Derive.vitruvianSpeakerInlineError(
            what = "mute", reason = "java.net.SocketException: Connection reset"))
    assertEquals(
        "Couldn't mute: the Mac didn't answer",
        Derive.vitruvianSpeakerInlineError(
            what = "mute", reason = "failed to connect to /10.0.2.2 (port 8765)"))
  }

  @Test
  public fun `Vitruvian Speaker inline errors use plain words for unreachable, auth, agent HTTP errors and explicit reasons`() {
    assertEquals(
        "Couldn't mute: the Mac didn't answer",
        Derive.vitruvianSpeakerInlineError(
            what = "mute", reason = "SocketTimeoutException: timed out"))
    assertEquals(
        "Couldn't mute: the Mac didn't answer",
        Derive.vitruvianSpeakerInlineError(
            what = "mute", reason = "ConnectException: Connection refused"))
    assertEquals(
        "Couldn't quiet hours on: this phone isn't paired",
        Derive.vitruvianSpeakerInlineError(what = "quiet hours on", authFailed = true))
    assertEquals(
        "Couldn't mute: this phone isn't paired",
        Derive.vitruvianSpeakerInlineError(
            what = "mute", reason = "agent: HTTP 401 for /v1/speaker/volume"))
    assertEquals(
        "Couldn't mute: this phone isn't paired",
        Derive.vitruvianSpeakerInlineError(what = "mute", reason = "HTTP 403 Forbidden"))
    assertEquals(
        "Couldn't mute: the Mac returned an error",
        Derive.vitruvianSpeakerInlineError(
            what = "mute", reason = "agent: HTTP 500 for /v1/speaker/volume"))
    assertEquals(
        "Couldn't test: the Mac returned an error",
        Derive.vitruvianSpeakerInlineError(what = "test", reason = "HTTP 502 Bad Gateway"))
    assertEquals(
        "Couldn't mute: the Mac returned an error",
        Derive.vitruvianSpeakerInlineError(what = "mute", reason = "agent: exit status 1"))
    assertEquals(
        "Couldn't replay: speaker is offline",
        Derive.vitruvianSpeakerInlineError(what = "replay", reason = "speaker is offline"))
    assertEquals(
        "A Vitruvian Speaker sign-in is already running on the Mac",
        Derive.vitruvianSpeakerInlineError(
            what = "sign in on Mac",
            reason = "agent: A Vitruvian Speaker sign-in is already running on the Mac"))
    assertEquals(
        "A Vitruvian Speaker sign-in is already running on the Mac",
        Derive.vitruvianSpeakerInlineError(
            what = "grant Google Chat",
            reason = "A Vitruvian Speaker sign-in is already running on the Mac"))
  }

  @Test
  public fun `a blank broadcast with no id is not replayable`() {
    val blank = AgentLastBroadcast(text = "  ", target = "Kitchen", source = "claude", at = "")
    val withId = blank.copy(id = "b-7")
    val withText = blank.copy(text = "Build finished")
    assertFalse(Derive.isReplayable(blank))
    assertFalse(Derive.isReplayable(null))
    assertTrue(Derive.isReplayable(withId))
    assertTrue(Derive.isReplayable(withText))
  }

  @Test
  public fun `inline errors keep plain reasons that merely contain a number`() {
    assertEquals(
        "Couldn't mute: speaker 100 not found",
        Derive.vitruvianSpeakerInlineError(what = "mute", reason = "speaker 100 not found"))
    assertEquals(
        "Couldn't mute: the Mac returned an error",
        Derive.vitruvianSpeakerInlineError(
            what = "mute", reason = "agent: HTTP 500 for /v1/speaker/volume"))
  }

  @Test
  fun hookAgentSlugsMatchVitruvianSpeakerHookAgents() {
    // Vitruvian Speaker's CodingAgent.supportsHook is true for every agent it knows.
    assertEquals(setOf("claude-code", "antigravity", "opencode"), Derive.hookAgentSlugs)
  }

  @Test
  public fun `googleHomeAccountRow covers sign in, pending on Mac, signed in, import login and disabled states`() {
    val signedOut =
        Derive.googleHomeAccountRow(
            signedIn = false,
            accountEmail = "",
            hasAntigravityTokens = true,
            signInPending = false,
            canAct = true,
            installed = true,
        )
    assertEquals("not signed in", signedOut.subtitle)
    assertEquals("sign in", signedOut.trailing)
    assertFalse(signedOut.healthy)
    assertTrue(signedOut.showSignIn)
    assertTrue(signedOut.signInEnabled)
    assertTrue(signedOut.showImportLogin)
    assertTrue(signedOut.importLoginEnabled)
    assertFalse(signedOut.showSignOut)

    val pending =
        Derive.googleHomeAccountRow(
            signedIn = false,
            accountEmail = "",
            hasAntigravityTokens = true,
            signInPending = true,
            canAct = true,
            installed = true,
        )
    assertEquals(Derive.FINISH_SIGN_IN_ON_MAC, pending.subtitle)
    assertEquals("signing in…", pending.trailing)
    assertFalse(pending.healthy)
    assertTrue(pending.showSignIn)
    assertTrue(pending.signInEnabled)

    val signedIn =
        Derive.googleHomeAccountRow(
            signedIn = true,
            accountEmail = "james@example.com",
            hasAntigravityTokens = true,
            signInPending = true,
            canAct = true,
            installed = true,
        )
    assertEquals("james@example.com", signedIn.subtitle)
    assertEquals("signed in", signedIn.trailing)
    assertTrue(signedIn.healthy)
    assertTrue(signedIn.showSignOut)
    assertTrue(signedIn.signOutEnabled)
    assertFalse(signedIn.showSignIn)
    assertFalse(signedIn.showImportLogin)

    val unpaired =
        Derive.googleHomeAccountRow(
            signedIn = false,
            accountEmail = "",
            hasAntigravityTokens = true,
            signInPending = false,
            canAct = false,
            installed = true,
        )
    assertFalse(unpaired.signInEnabled)
    assertFalse(unpaired.importLoginEnabled)

    val uninstalled =
        Derive.googleHomeAccountRow(
            signedIn = false,
            accountEmail = "",
            hasAntigravityTokens = false,
            signInPending = false,
            canAct = true,
            installed = false,
        )
    assertFalse(uninstalled.signInEnabled)
    assertFalse(uninstalled.showImportLogin)
  }

  @Test
  public fun `googleChatAccountDiag covers grant, pending on Mac, disconnect, gws prompt and disabled states`() {
    val needsGrant =
        Derive.googleChatAccountDiag(
            source = "api",
            activeBackend = "",
            accountEmail = "james@example.com",
            gwsAccount = "",
            hasChatAccess = false,
            gwsInstalled = false,
            grantPending = false,
            canAct = true,
            installed = true,
        )
    assertEquals("james@example.com · Chat access not granted on Mac", needsGrant.subtitle)
    assertEquals("no access", needsGrant.trailing)
    assertFalse(needsGrant.healthy)
    assertTrue(needsGrant.showGrant)
    assertTrue(needsGrant.grantEnabled)
    assertFalse(needsGrant.showDisconnect)
    assertFalse(needsGrant.showGwsPrompt)

    val grantPending =
        Derive.googleChatAccountDiag(
            source = "auto",
            activeBackend = "",
            accountEmail = "james@example.com",
            gwsAccount = "",
            hasChatAccess = false,
            gwsInstalled = false,
            grantPending = true,
            canAct = true,
            installed = true,
        )
    assertEquals(Derive.FINISH_SIGN_IN_ON_MAC, grantPending.subtitle)
    assertEquals("signing in…", grantPending.trailing)
    assertFalse(grantPending.healthy)
    assertTrue(grantPending.showGrant)
    assertTrue(grantPending.grantEnabled)
    assertFalse(grantPending.showDisconnect)

    val connected =
        Derive.googleChatAccountDiag(
            source = "api",
            activeBackend = "api",
            accountEmail = "james@example.com",
            gwsAccount = "",
            hasChatAccess = true,
            gwsInstalled = false,
            grantPending = false,
            canAct = true,
            installed = true,
        )
    assertEquals("james@example.com · Chat access granted", connected.subtitle)
    assertEquals("signed in", connected.trailing)
    assertTrue(connected.healthy)
    assertFalse(connected.showGrant)
    assertTrue(connected.showDisconnect)
    assertTrue(connected.disconnectEnabled)

    val uninstalledGrant =
        Derive.googleChatAccountDiag(
            source = "api",
            activeBackend = "api",
            accountEmail = "james@example.com",
            gwsAccount = "",
            hasChatAccess = false,
            gwsInstalled = false,
            grantPending = false,
            canAct = true,
            installed = false,
        )
    assertTrue(uninstalledGrant.showGrant)
    assertFalse(uninstalledGrant.grantEnabled)

    val uninstalledDisconnect =
        Derive.googleChatAccountDiag(
            source = "api",
            activeBackend = "api",
            accountEmail = "james@example.com",
            gwsAccount = "",
            hasChatAccess = true,
            gwsInstalled = false,
            grantPending = false,
            canAct = true,
            installed = false,
        )
    assertTrue(uninstalledDisconnect.showDisconnect)
    assertFalse(uninstalledDisconnect.disconnectEnabled)

    val gwsMode =
        Derive.googleChatAccountDiag(
            source = "gws",
            activeBackend = "gws",
            accountEmail = "james@example.com",
            gwsAccount = "work@example.com",
            hasChatAccess = false,
            gwsInstalled = true,
            grantPending = false,
            canAct = false,
            installed = true,
        )
    assertFalse(gwsMode.showGrant)
    assertFalse(gwsMode.showDisconnect)
    assertTrue(gwsMode.showGwsPrompt)
    assertFalse(gwsMode.gwsPromptEnabled)
  }

  @Test
  public fun `googleCloudOAuthSpec, courierTokenRow and legacyLaunchAgentRow respect pairing and state`() {
    val oauthDefault =
        Derive.googleCloudOAuthSpec(
            customClientId = "",
            hasCustomSecret = false,
            canAct = true,
        )
    assertEquals("Set up in Google Cloud", oauthDefault.setupTitle)
    assertEquals(Derive.GOOGLE_CLOUD_CONSOLE_URL, oauthDefault.setupUrl)
    assertEquals("none", oauthDefault.clientIdTrailing)
    assertEquals("missing", oauthDefault.clientSecretTrailing)
    assertFalse(oauthDefault.clientIdHealthy)
    assertFalse(oauthDefault.clientSecretHealthy)
    assertTrue(oauthDefault.promptsEnabled)

    val oauthCustomUnpaired =
        Derive.googleCloudOAuthSpec(
            customClientId = "123.apps.googleusercontent.com",
            hasCustomSecret = true,
            canAct = false,
        )
    assertEquals("configured", oauthCustomUnpaired.clientIdTrailing)
    assertEquals("saved", oauthCustomUnpaired.clientSecretTrailing)
    assertTrue(oauthCustomUnpaired.clientIdHealthy)
    assertTrue(oauthCustomUnpaired.clientSecretHealthy)
    assertFalse(oauthCustomUnpaired.promptsEnabled)

    val courierMissing = Derive.courierTokenRow(hasToken = false, canAct = true)
    assertEquals("Courier token", courierMissing.title)
    assertEquals("missing", courierMissing.trailing)
    assertFalse(courierMissing.healthy)
    assertNull(courierMissing.clearLabel)
    assertTrue(courierMissing.promptEnabled)

    val courierSavedUnpaired = Derive.courierTokenRow(hasToken = true, canAct = false)
    assertEquals("saved", courierSavedUnpaired.trailing)
    assertTrue(courierSavedUnpaired.healthy)
    assertEquals("Clear Token", courierSavedUnpaired.clearLabel)
    assertFalse(courierSavedUnpaired.promptEnabled)

    val legacyReady = Derive.legacyLaunchAgentRow(canAct = true, busy = false)
    assertEquals("Old chat monitor (from an earlier version)", legacyReady.title)
    assertEquals("", legacyReady.trailing)
    assertEquals("Stop and remove", legacyReady.actionLabel)
    assertTrue(legacyReady.actionEnabled)

    assertFalse(Derive.legacyLaunchAgentRow(canAct = false, busy = false).actionEnabled)
    assertFalse(Derive.legacyLaunchAgentRow(canAct = true, busy = true).actionEnabled)
  }

  @Test
  public fun `googleCloudConsoleUrl matches Pages swift cloudConsole literal`() {
    assertEquals(
        "https://console.cloud.google.com/apis/credentials", Derive.GOOGLE_CLOUD_CONSOLE_URL)
    val spec =
        Derive.googleCloudOAuthSpec(customClientId = "", hasCustomSecret = false, canAct = true)
    assertEquals("https://console.cloud.google.com/apis/credentials", spec.setupUrl)
  }

  @Test
  public fun `pending sign-in clears on the next poll that shows signed in and times out after 5 minutes`() {
    val startMs = 1_000_000L
    val fiveMinMs = Derive.SIGN_IN_TIMEOUT_MS
    assertEquals(5 * 60 * 1000L, fiveMinMs)

    // Still pending before 5 minutes when not yet signed in.
    val stillPending =
        Derive.resolvePendingSignIn(
            pendingSinceMs = startMs,
            signedIn = false,
            nowMs = startMs + fiveMinMs - 1L,
        )
    assertTrue(stillPending.pending)
    assertFalse(stillPending.timedOut)
    assertEquals(startMs, stillPending.pendingSinceMs)
    assertNull(stillPending.inlineNote)

    val rowWhilePending =
        Derive.googleHomeAccountRow(
            signedIn = false,
            accountEmail = "",
            hasAntigravityTokens = false,
            signInPendingSinceMs = startMs,
            nowMs = startMs + 60_000L,
        )
    assertEquals("Finish signing in on your Mac", rowWhilePending.subtitle)
    assertEquals("signing in…", rowWhilePending.trailing)
    assertTrue(rowWhilePending.showSignIn)
    assertNull(rowWhilePending.inlineNote)

    // Clears on the next poll that shows signedIn = true (or hasChatAccess = true).
    val pollSignedIn =
        Derive.updatePendingSignInOnPoll(
            signInPendingSinceMs = startMs,
            chatGrantPendingSinceMs = startMs,
            signedIn = true,
            hasChatAccess = true,
            nowMs = startMs + 10_000L,
        )
    assertFalse(pollSignedIn.signIn.pending)
    assertFalse(pollSignedIn.signIn.timedOut)
    assertNull(pollSignedIn.signIn.pendingSinceMs)
    assertNull(pollSignedIn.signIn.inlineNote)
    assertFalse(pollSignedIn.chatGrant.pending)
    assertFalse(pollSignedIn.chatGrant.timedOut)
    assertNull(pollSignedIn.chatGrant.pendingSinceMs)
    assertNull(pollSignedIn.chatGrant.inlineNote)

    // Times out at 5 minutes: returns to "Sign in on Mac" with inline note.
    val timedOut =
        Derive.resolvePendingSignIn(
            pendingSinceMs = startMs,
            signedIn = false,
            nowMs = startMs + fiveMinMs,
        )
    assertFalse(timedOut.pending)
    assertTrue(timedOut.timedOut)
    assertNull(timedOut.pendingSinceMs)
    assertEquals("Sign-in didn't finish on the Mac. Try again.", timedOut.inlineNote)

    val rowTimedOut =
        Derive.googleHomeAccountRow(
            signedIn = false,
            accountEmail = "",
            hasAntigravityTokens = false,
            signInPendingSinceMs = startMs,
            nowMs = startMs + fiveMinMs,
        )
    assertEquals("not signed in", rowTimedOut.subtitle)
    assertEquals("sign in", rowTimedOut.trailing)
    assertTrue(rowTimedOut.showSignIn)
    assertTrue(rowTimedOut.signInEnabled)
    assertEquals("Sign-in didn't finish on the Mac. Try again.", rowTimedOut.inlineNote)

    val chatTimedOut =
        Derive.googleChatAccountDiag(
            source = "api",
            activeBackend = "api",
            accountEmail = "james@example.com",
            gwsAccount = "",
            hasChatAccess = false,
            gwsInstalled = false,
            grantPendingSinceMs = startMs,
            nowMs = startMs + fiveMinMs + 5_000L,
        )
    assertEquals("james@example.com · Chat access not granted on Mac", chatTimedOut.subtitle)
    assertEquals("no access", chatTimedOut.trailing)
    assertTrue(chatTimedOut.showGrant)
    assertEquals("Sign-in didn't finish on the Mac. Try again.", chatTimedOut.inlineNote)
  }

  @Test
  public fun `noMacLine distinguishes offline paired Macs from unpaired phones`() {
    assertEquals(
        "no Mac is configured, so nothing was asked",
        Derive.noMacLine(paired = false, offline = false, hostName = "", lastSeenAgoSec = null),
    )
    assertEquals(
        "no Mac is configured, so nothing ran",
        Derive.noMacLine(
            paired = false,
            offline = false,
            hostName = "",
            lastSeenAgoSec = null,
            nothingRan = true),
    )
    assertEquals(
        "atlas isn't answering · last seen 2 min ago",
        Derive.noMacLine(paired = true, offline = true, hostName = "atlas", lastSeenAgoSec = 125L),
    )
    assertEquals(
        "10.0.2.2 isn't answering · last seen just now",
        Derive.noMacLine(paired = true, offline = true, hostName = "10.0.2.2", lastSeenAgoSec = 3L),
    )
    assertEquals(
        "atlas isn't answering",
        Derive.noMacLine(paired = true, offline = true, hostName = "atlas", lastSeenAgoSec = null),
    )
    assertEquals(
        "asking…",
        Derive.noMacLine(paired = true, offline = false, hostName = "atlas", lastSeenAgoSec = null),
    )
  }

  @Test
  public fun `displayHostName prefers agent hostname over auto-derived alias but keeps user-typed alias`() {
    // Auto-derived IPv4 alias yields to /v1/host hostname when reported.
    assertEquals(
        "atlas",
        Derive.displayHostName(
            alias = "10.0.2.2", url = "http://10.0.2.2:7411", agentHostname = "atlas.local"),
    )
    // Legacy cut IPv4 alias ("10") also yields to agent hostname or full IPv4 when offline.
    assertEquals(
        "atlas",
        Derive.displayHostName(
            alias = "10", url = "http://10.0.2.2:7411", agentHostname = "atlas.tailnet.ts.net"),
    )
    assertEquals(
        "10.0.2.2",
        Derive.displayHostName(alias = "10", url = "http://10.0.2.2:7411", agentHostname = null),
    )
    // Auto-derived DNS alias yields to reported hostname.
    assertEquals(
        "mac-studio",
        Derive.displayHostName(
            alias = "box", url = "http://box.example.com:7411", agentHostname = "mac-studio.local"),
    )
    // User-typed alias always wins, even when /v1/host reports a different hostname.
    assertEquals(
        "Desk Mac",
        Derive.displayHostName(
            alias = "Desk Mac", url = "http://10.0.2.2:7411", agentHostname = "atlas.local"),
    )
  }

  @Test
  public fun `mirrorRowSpec shows blocked notification error only when permanently denied`() {
    assertTrue(Derive.isNotificationPermissionBlocked(granted = false, shouldShowRationale = false))
    assertFalse(Derive.isNotificationPermissionBlocked(granted = false, shouldShowRationale = true))
    assertFalse(Derive.isNotificationPermissionBlocked(granted = true, shouldShowRationale = false))

    val permanentlyBlocked =
        Derive.mirrorRowSpec(
            mirrorEnabled = true,
            permissionGranted = false,
            permissionBlocked = true,
            shouldShowRationale = false,
        )
    assertFalse(permanentlyBlocked.checked)
    assertEquals("off", permanentlyBlocked.trailing)
    assertEquals("Notifications are blocked for this app", permanentlyBlocked.error)
    assertTrue(permanentlyBlocked.showOpenSettings)
    assertEquals("Open settings", permanentlyBlocked.actionLabel)

    val firstDenial =
        Derive.mirrorRowSpec(
            mirrorEnabled = false,
            permissionGranted = false,
            permissionBlocked =
                Derive.isNotificationPermissionBlocked(granted = false, shouldShowRationale = true),
            shouldShowRationale = true,
        )
    assertFalse(firstDenial.checked)
    assertEquals("off", firstDenial.trailing)
    assertNull(firstDenial.error)
    assertFalse(firstDenial.showOpenSettings)

    val active =
        Derive.mirrorRowSpec(
            mirrorEnabled = true, permissionGranted = true, permissionBlocked = false)
    assertTrue(active.checked)
    assertEquals("on", active.trailing)
    assertNull(active.error)
    assertFalse(active.showOpenSettings)

    val off =
        Derive.mirrorRowSpec(
            mirrorEnabled = false, permissionGranted = true, permissionBlocked = false)
    assertFalse(off.checked)
    assertEquals("off", off.trailing)
    assertNull(off.error)
    assertFalse(off.showOpenSettings)
  }

  @Test
  public fun `notificationsRowSpec covers granted, not asked, denied once and permanently blocked`() {
    assertFalse(
        Derive.isNotificationPermissionBlocked(
            granted = false, shouldShowRationale = false, asked = false))
    assertFalse(
        Derive.isNotificationPermissionBlocked(
            granted = false, shouldShowRationale = true, asked = true))
    assertTrue(
        Derive.isNotificationPermissionBlocked(
            granted = false, shouldShowRationale = false, asked = true))
    assertFalse(
        Derive.isNotificationPermissionBlocked(
            granted = true, shouldShowRationale = false, asked = true))

    val granted =
        Derive.notificationsRowSpec(granted = true, asked = true, shouldShowRationale = false)
    assertEquals("Notifications", granted.title)
    assertEquals("Mac offline/back alerts and finished commands", granted.subtitle)
    assertEquals("On", granted.statusLabel)
    assertEquals(Derive.NotificationPermissionAction.None, granted.action)
    assertNull(granted.actionLabel)
    assertFalse(granted.permanentlyBlocked)

    val notAsked =
        Derive.notificationsRowSpec(granted = false, asked = false, shouldShowRationale = false)
    assertEquals("Notifications", notAsked.title)
    assertEquals("Mac offline/back alerts and finished commands", notAsked.subtitle)
    assertNull(notAsked.statusLabel)
    assertEquals(Derive.NotificationPermissionAction.Allow, notAsked.action)
    assertEquals("Allow", notAsked.actionLabel)
    assertFalse(notAsked.permanentlyBlocked)

    val deniedOnce =
        Derive.notificationsRowSpec(granted = false, asked = true, shouldShowRationale = true)
    assertNull(deniedOnce.statusLabel)
    assertEquals(Derive.NotificationPermissionAction.Allow, deniedOnce.action)
    assertEquals("Allow", deniedOnce.actionLabel)
    assertFalse(deniedOnce.permanentlyBlocked)

    val permanentlyBlocked =
        Derive.notificationsRowSpec(granted = false, asked = true, shouldShowRationale = false)
    assertNull(permanentlyBlocked.statusLabel)
    assertEquals(Derive.NotificationPermissionAction.OpenSettings, permanentlyBlocked.action)
    assertEquals("Open settings", permanentlyBlocked.actionLabel)
    assertTrue(permanentlyBlocked.permanentlyBlocked)
  }

  @Test
  public fun `bridgeNotificationSpec covers off, granted, not asked, denied once and permanently blocked`() {
    assertNull(
        Derive.bridgeNotificationSpec(
            bridgeEnabled = false,
            granted = false,
            asked = false,
            shouldShowRationale = false,
        ))
    assertNull(
        Derive.bridgeNotificationSpec(
            bridgeEnabled = true,
            granted = true,
            asked = true,
            shouldShowRationale = false,
        ))

    val notAsked =
        Derive.bridgeNotificationSpec(
            bridgeEnabled = true,
            granted = false,
            asked = false,
            shouldShowRationale = false,
        )!!
    assertEquals("Approvals can't pop up while notifications are off", notAsked.note)
    assertEquals(Derive.NotificationPermissionAction.Allow, notAsked.action)
    assertEquals("Allow", notAsked.actionLabel)
    assertFalse(notAsked.permanentlyBlocked)

    val deniedOnce =
        Derive.bridgeNotificationSpec(
            bridgeEnabled = true,
            granted = false,
            asked = true,
            shouldShowRationale = true,
        )!!
    assertEquals("Approvals can't pop up while notifications are off", deniedOnce.note)
    assertEquals(Derive.NotificationPermissionAction.Allow, deniedOnce.action)
    assertEquals("Allow", deniedOnce.actionLabel)
    assertFalse(deniedOnce.permanentlyBlocked)

    val permanentlyBlocked =
        Derive.bridgeNotificationSpec(
            bridgeEnabled = true,
            granted = false,
            asked = true,
            shouldShowRationale = false,
        )!!
    assertEquals("Approvals can't pop up while notifications are off", permanentlyBlocked.note)
    assertEquals(Derive.NotificationPermissionAction.OpenSettings, permanentlyBlocked.action)
    assertEquals("Open settings", permanentlyBlocked.actionLabel)
    assertTrue(permanentlyBlocked.permanentlyBlocked)
  }

  @Test
  public fun `MainActivity never asks for POST_NOTIFICATIONS at launch`() {
    val main =
        stripKotlinComments(
            readRunfile(
                "apps/mobile/vitruvian-remote/src/main/kotlin/dev/vitruvian/remote/MainActivity.kt"))
    val remoteState =
        stripKotlinComments(
            readRunfile(
                "apps/mobile/vitruvian-remote/src/main/kotlin/dev/vitruvian/remote/state/RemoteState.kt"))
    assertFalse(
        "askForNotifications launch helper must be removed", main.contains("askForNotifications"))
    val launches = Regex("""\brequestNotifications\.launch\(""").findAll(main).count()
    assertEquals(
        "requestNotifications.launch may only be called from ensurePostNotificationsPermission",
        1,
        launches,
    )
    assertTrue(
        "ensurePostNotificationsPermission must own the single requestNotifications.launch call",
        extractKotlinBlock(main, "private fun ensurePostNotificationsPermission(")
            .contains("requestNotifications.launch(PERMISSION_POST_NOTIFICATIONS)"),
    )

    // onCreate passes ::ensurePostNotificationsPermission into ShadeNotifier's port without
    // invoking it; verify ShadeNotifier.init never invokes ensurePermission and strip that single
    // port-wiring reference before checking onCreate's body for calls/references.
    val rawOnCreate = extractKotlinBlock(main, "override fun onCreate(")
    assertTrue(
        "expected ShadeNotifier port wiring in MainActivity.onCreate",
        rawOnCreate.contains("ensurePermission = ::ensurePostNotificationsPermission"),
    )
    val shadeNotifierInit =
        extractKotlinBlock(main.substringAfter("private class ShadeNotifier("), "init")
    assertFalse(
        "ShadeNotifier.init must not invoke ensurePermission at construction",
        Regex("""\bensurePermission\b""").containsMatchIn(shadeNotifierInit),
    )

    val launchAndForegroundBodies =
        mapOf(
            "MainActivity.onCreate" to
                rawOnCreate.replaceFirst(
                    "ensurePermission = ::ensurePostNotificationsPermission", ""),
            "MainActivity.onStart" to extractKotlinBlock(main, "override fun onStart("),
            "MainActivity.onResume" to extractKotlinBlock(main, "override fun onResume("),
            "MainActivity.onWindowFocusChanged" to
                extractKotlinBlock(main, "override fun onWindowFocusChanged("),
            "MainActivity.pushBridgeStatus" to
                extractKotlinBlock(main, "private fun pushBridgeStatus("),
            "MainActivity.handleIntent" to extractKotlinBlock(main, "private fun handleIntent("),
            "RemoteState.onForeground" to
                extractKotlinBlock(remoteState, "public fun onForeground("),
            "RemoteState.refreshNotificationPermission" to
                extractKotlinBlock(remoteState, "public fun refreshNotificationPermission("),
        )
    val forbiddenSymbols =
        listOf(
            "ensurePostNotificationsPermission",
            "ensureNotificationPermission",
            "requestNotifications",
            "requestNotificationsPermission",
            "askForNotifications",
        )
    val violations = mutableListOf<String>()
    for ((pathName, body) in launchAndForegroundBodies) {
      assertTrue("$pathName body should not be blank", body.isNotBlank())
      for (symbol in forbiddenSymbols) {
        if (Regex("""\b${Regex.escape(symbol)}\b""").containsMatchIn(body)) {
          violations += "$pathName references `$symbol`"
        }
      }
    }
    assertTrue(
        "Launch/foreground lifecycle paths must never ask for POST_NOTIFICATIONS:\n" +
            violations.joinToString("\n"),
        violations.isEmpty(),
    )
  }

  private fun stripKotlinComments(source: String): String {
    val out = StringBuilder(source.length)
    var i = 0
    while (i < source.length) {
      when {
        source.startsWith("//", i) -> {
          while (i < source.length && source[i] != '\n') i++
        }
        source.startsWith("/*", i) -> {
          val end = source.indexOf("*/", i + 2)
          i = if (end == -1) source.length else end + 2
          out.append(' ')
        }
        source.startsWith("\"\"\"", i) -> {
          out.append("\"\"\"")
          i += 3
          val end = source.indexOf("\"\"\"", i)
          if (end == -1) {
            out.append(source.substring(i))
            i = source.length
          } else {
            out.append(source, i, end + 3)
            i = end + 3
          }
        }
        source[i] == '"' || source[i] == '\'' -> {
          val quote = source[i]
          out.append(quote)
          i++
          while (i < source.length) {
            val c = source[i]
            out.append(c)
            i++
            if (c == '\\' && i < source.length) {
              out.append(source[i])
              i++
            } else if (c == quote) {
              break
            }
          }
        }
        else -> {
          out.append(source[i])
          i++
        }
      }
    }
    return out.toString()
  }

  private fun extractKotlinBlock(commentFreeSource: String, anchor: String): String {
    val start = commentFreeSource.indexOf(anchor)
    assertTrue("Anchor `$anchor` not found", start >= 0)
    var i = start + anchor.length
    if (anchor.endsWith("(")) {
      var parenDepth = 1
      while (i < commentFreeSource.length && parenDepth > 0) {
        i =
            skipLiteralOrAdvance(commentFreeSource, i) { c ->
              when (c) {
                '(' -> parenDepth++
                ')' -> parenDepth--
              }
            }
      }
      assertEquals("Unbalanced parameter list for `$anchor`", 0, parenDepth)
    }
    while (i < commentFreeSource.length && commentFreeSource[i] != '{') {
      i = skipLiteralOrAdvance(commentFreeSource, i) {}
    }
    assertTrue("Opening `{` not found for `$anchor`", i < commentFreeSource.length)
    val bodyStart = i + 1
    i = bodyStart
    var braceDepth = 1
    while (i < commentFreeSource.length && braceDepth > 0) {
      i =
          skipLiteralOrAdvance(commentFreeSource, i) { c ->
            when (c) {
              '{' -> braceDepth++
              '}' -> braceDepth--
            }
          }
    }
    assertEquals("Unbalanced body braces for `$anchor`", 0, braceDepth)
    return commentFreeSource.substring(bodyStart, i - 1)
  }

  private inline fun skipLiteralOrAdvance(
      source: String,
      index: Int,
      onCodeChar: (Char) -> Unit,
  ): Int {
    if (source.startsWith("\"\"\"", index)) {
      val end = source.indexOf("\"\"\"", index + 3)
      return if (end == -1) source.length else end + 3
    }
    val ch = source[index]
    if (ch == '"' || ch == '\'') {
      var i = index + 1
      while (i < source.length) {
        if (source[i] == '\\') {
          i += 2
        } else if (source[i] == ch) {
          return i + 1
        } else {
          i++
        }
      }
      return source.length
    }
    onCodeChar(ch)
    return index + 1
  }

  @Test
  public fun `tapReset and resetVitruvianSpeakerRow enforce a 5 second two-tap confirmation window`() {
    val t0 = 100_000L
    val initialRow = Derive.resetVitruvianSpeakerRow(armedAtMs = null, nowMs = t0, canAct = true)
    assertEquals("Reset Vitruvian Speaker", initialRow.title)
    assertEquals("puts every Vitruvian Speaker setting back to default", initialRow.subtitle)
    assertEquals("Reset settings", initialRow.actionLabel)
    assertFalse(initialRow.danger)

    // First tap arms for 5 s without resetting.
    val firstTap = Derive.tapReset(armedAtMs = null, nowMs = t0)
    assertFalse(firstTap.shouldReset)
    assertEquals(t0, firstTap.nextArmedAtMs)

    val armedRow =
        Derive.resetVitruvianSpeakerRow(
            armedAtMs = firstTap.nextArmedAtMs, nowMs = t0 + 2_000L, canAct = true)
    assertEquals("Tap again to reset", armedRow.actionLabel)
    assertTrue(armedRow.danger)

    // Second tap within 5 s confirms and clears armed state.
    val secondTap = Derive.tapReset(armedAtMs = firstTap.nextArmedAtMs, nowMs = t0 + 4_999L)
    assertTrue(secondTap.shouldReset)
    assertNull(secondTap.nextArmedAtMs)

    // After 5 s have elapsed, the row reverts and tapping again re-arms instead of resetting.
    val expiredRow =
        Derive.resetVitruvianSpeakerRow(
            armedAtMs = firstTap.nextArmedAtMs, nowMs = t0 + 5_000L, canAct = true)
    assertEquals("Reset settings", expiredRow.actionLabel)
    assertFalse(expiredRow.danger)

    val tapAfterExpiry = Derive.tapReset(armedAtMs = firstTap.nextArmedAtMs, nowMs = t0 + 5_000L)
    assertFalse(tapAfterExpiry.shouldReset)
    assertEquals(t0 + 5_000L, tapAfterExpiry.nextArmedAtMs)
  }

  @Test
  public fun `stripVitruvianSpeakerErrorPrefixes and vitruvianSpeakerInlineError format sign-in errors cleanly`() {
    assertEquals(
        "token exchange failed",
        Derive.stripVitruvianSpeakerErrorPrefixes("speaker: error: token exchange failed"),
    )
    assertEquals(
        "invalid_grant",
        Derive.stripVitruvianSpeakerErrorPrefixes("✗ speaker · sign in: HTTP 400: invalid_grant"),
    )
    assertEquals(
        "browser closed",
        Derive.stripVitruvianSpeakerErrorPrefixes(
            "agent: speaker: error: browser closed (HTTP 400)"),
    )
    assertEquals(
        "Couldn't sign in: token exchange failed",
        Derive.vitruvianSpeakerInlineError(
            what = "sign in", reason = "speaker: error: token exchange failed"),
    )
    assertEquals(
        "Couldn't sign in: access denied",
        Derive.vitruvianSpeakerInlineError(
            what = "grant Google Chat",
            reason = "✗ speaker · grant Google Chat: error: access denied (HTTP 400)"),
    )
    // UAT 2026-11-12: any helper "<action> failed:" wrapper is technical, not just sign-in's.
    assertEquals(
        "Couldn't choose home: the Mac returned an error",
        Derive.vitruvianSpeakerInlineError(
            what = "choose home", reason = "set structure failed: exit status 1"),
    )
    // UAT 2026-11-10: the agent's own "sign out failed:" prefix reached the row.
    assertEquals(
        "Couldn't sign out: the Mac returned an error",
        Derive.vitruvianSpeakerInlineError(
            what = "sign out", reason = "sign out failed: exit status 1"),
    )
    assertEquals(
        "Couldn't sign in: browser closed",
        Derive.vitruvianSpeakerInlineError(
            what = "sign in", reason = "sign in failed: browser closed"),
    )
    assertEquals(
        "Couldn't sign in: access denied",
        Derive.vitruvianSpeakerInlineError(
            what = "grant", reason = "grant chat failed: access denied"),
    )
    assertEquals(
        "Couldn't sign out: token revoke failed",
        Derive.vitruvianSpeakerInlineError(
            what = "sign out", reason = "speaker: error: token revoke failed"),
    )
    assertEquals(
        "Couldn't disconnect: keychain locked",
        Derive.vitruvianSpeakerInlineError(
            what = "disconnect Google Chat", reason = "speaker: error: keychain locked"),
    )
    assertEquals(
        "Couldn't disconnect: token file busy",
        Derive.vitruvianSpeakerInlineError(
            what = "disconnect", reason = "✗ speaker · disconnect: error: token file busy"),
    )
  }

  @Test
  public fun `showsCourierRow keeps Courier visible when off and hides it only when unsupported`() {
    assertFalse(Derive.showsCourierRow(null))
    assertTrue(Derive.showsCourierRow(false))
    assertTrue(Derive.showsCourierRow(true))
  }

  private fun runfileKotlinFiles(relDir: String): List<String> {
    val roots = mutableListOf(java.io.File("."))
    System.getenv("TEST_SRCDIR")
        ?.takeIf { it.isNotBlank() }
        ?.let { src ->
          for (w in listOf("_main", "vitruvian_core", "")) {
            roots += if (w.isEmpty()) java.io.File(src) else java.io.File(src, w)
          }
        }
    val dir = roots.map { java.io.File(it, relDir) }.firstOrNull { it.isDirectory }
    val names = dir?.listFiles { f -> f.name.endsWith(".kt") }?.map { it.name }.orEmpty().sorted()
    assertTrue("no screens/*.kt found in runfiles under $relDir", names.isNotEmpty())
    return names.map { "$relDir/$it" }
  }

  private fun readRunfile(relPath: String): String {
    val direct = java.io.File(relPath)
    if (direct.exists()) return direct.readText()
    val testSrcDir = System.getenv("TEST_SRCDIR")
    if (!testSrcDir.isNullOrBlank()) {
      for (workspace in listOf("_main", "vitruvian_core", "")) {
        val candidate =
            if (workspace.isEmpty()) java.io.File(testSrcDir, relPath)
            else java.io.File(java.io.File(testSrcDir, workspace), relPath)
        if (candidate.exists()) return candidate.readText()
      }
    }
    error("Runfile not found: $relPath")
  }

  @Test
  public fun `catalog labels choices limits and shown come from payload and substitute This phone`() {
    val sources =
        VitruvianSpeakerWire.sources(
            readRunfile("apps/mobile/vitruvian-remote/macagent/golden_speaker_v1.json"))
    val catalog = sources.catalog

    assertTrue(Derive.hasVitruvianSpeakerCatalog(available = true, catalog = catalog))
    assertEquals("Enable Voice Broadcasting", Derive.catalogLabel(catalog, "enabled"))
    assertEquals("Speak", Derive.catalogLabel(catalog, "speech_length"))
    assertEquals(
        "Headline (1-2 sentences)", Derive.catalogChoiceLabel(catalog, "speech_length", "headline"))
    assertEquals("Plain summary", Derive.catalogChoiceLabel(catalog, "announcement_style", "plain"))
    assertEquals("Apple (on this Mac)", Derive.catalogChoiceLabel(catalog, "style_model", "apple"))
    assertEquals("Apple (System)", Derive.catalogChoiceLabel(catalog, "local_engine", "apple"))
    assertEquals("Kore · Warm & clear", Derive.catalogChoiceLabel(catalog, "gemini_voice", "Kore"))
    assertEquals(
        "Studio Narrator (cloned)", Derive.catalogChoiceLabel(catalog, "gemini_voice", "cloned-1"))
    assertEquals(
        "Direct messages and mentions",
        Derive.catalogChoiceLabel(catalog, "beeper_announce", "direct_and_mentions"))
    assertEquals(
        "gws command-line tool", Derive.catalogChoiceLabel(catalog, "google_chat_source", "gws"))
    assertFalse(Derive.catalogShown(catalog, "custom_style_prompt"))
    assertTrue(Derive.catalogShown(catalog, "style_model"))

    // The single phone point-of-view substitution: "Your phone" -> "This phone".
    assertEquals(Derive.THIS_PHONE, Derive.catalogLabel(catalog, "speak_phone"))
    assertEquals("Office Mini + This Mac + This phone", Derive.outputsSummary(sources.outputsLabel))
    val footer = Derive.phoneWording(sources.outputsFooter.orEmpty())
    assertTrue(footer.contains("This phone plays the Gemini voice"))
    assertFalse(footer.contains("Your phone"))

    // Synthetic catalog proves the phone uses whatever labels, choices and step limits arrive
    // without falling back to local copies or clamping step deltas on the phone.
    val custom =
        VitruvianSpeakerCatalog(
            listOf(
                VitruvianSpeakerSetting(
                    key = "speech_length",
                    kind = "choice",
                    label = "Length from Mac",
                    stringValue = "terse",
                    shown = true,
                    choices = listOf(VitruvianSpeakerChoice("terse", "One short line")),
                ),
                VitruvianSpeakerSetting(
                    key = "announce_volume",
                    kind = "number",
                    label = "Custom level",
                    numberValue = 98.0,
                    shown = true,
                    limits =
                        VitruvianSpeakerLimits(
                            min = 10.0, max = 100.0, step = 5.0, defaultValue = 60.0),
                ),
            ))
    assertEquals("Length from Mac", Derive.catalogLabel(custom, "speech_length"))
    assertEquals("One short line", Derive.catalogChoiceLabel(custom, "speech_length", "terse"))
    val stepper =
        Derive.catalogStepper(
            current = 98.0,
            limits = Derive.catalogLimits(custom, "announce_volume")!!,
            canAct = true,
        )
    assertEquals("−5", stepper.minusLabel)
    assertEquals("+5", stepper.plusLabel)
    assertTrue(stepper.minusEnabled)
    assertTrue(stepper.plusEnabled)
    // The stepper stops at Vitruvian Speaker's max: 98 + 5 is sent as 100, never 103.
    assertEquals(100.0, stepper.plusNext, 0.0)
  }

  @Test
  public fun `missing catalog yields helper reason when present or the update sentence`() {
    val empty = VitruvianSpeakerCatalog()
    assertFalse(Derive.hasVitruvianSpeakerCatalog(available = true, catalog = empty))
    assertFalse(
        Derive.hasVitruvianSpeakerCatalog(
            available = false,
            catalog =
                VitruvianSpeakerCatalog(
                    listOf(VitruvianSpeakerSetting("enabled", "toggle", "Enable", shown = true)))))

    assertEquals(
        "Update Vitruvian Speaker on atlas (have 1.38.0, need 1.40.0)",
        Derive.missingCatalogMessage(
            "Update Vitruvian Speaker on atlas (have 1.38.0, need 1.40.0)"),
    )
    assertEquals(
        "Vitruvian Speaker is not installed on this Mac",
        Derive.missingCatalogMessage("  Vitruvian Speaker is not installed on this Mac  "),
    )
    val fallback =
        "Update Vitruvian Speaker and the Vitruvian Remote helper on your Mac to change these settings here."
    assertEquals(fallback, Derive.missingCatalogMessage(null))
    assertEquals(fallback, Derive.missingCatalogMessage(""))
    assertEquals(fallback, Derive.missingCatalogMessage("   "))
  }

  @Test
  public fun `deleted Vitruvian Speaker label constants choice lists and clamps stay out of phone sources`() {
    val files =
        listOf(
            "apps/mobile/vitruvian-remote/src/main/kotlin/dev/vitruvian/remote/state/AgentClient.kt",
            "apps/mobile/vitruvian-remote/src/main/kotlin/dev/vitruvian/remote/state/Derive.kt",
            "apps/mobile/vitruvian-remote/src/main/kotlin/dev/vitruvian/remote/state/RemoteState.kt",
            "apps/mobile/vitruvian-remote/src/main/kotlin/dev/vitruvian/remote/state/Wire.kt",
        ) +
            runfileKotlinFiles(
                "apps/mobile/vitruvian-remote/src/main/kotlin/dev/vitruvian/remote/screens")
    val deletedSymbols =
        listOf(
            "speechLengths",
            "speechLengthLabel",
            "localEngines",
            "localEngineLabel",
            "announcementStyles",
            "announcementStyleLabel",
            "styleModels",
            "styleModelLabel",
            "geminiVoices",
            "geminiVoiceDisplayName",
            "quietHoursChoices",
            "quietHoursSlots",
            "announceVolumeChoices",
            "announceVolumePercentChoices",
            "volumePercentChoices",
            "pauseMarginSecondChoices",
            "pollIntervalChoices",
            "pollIntervalLabel",
            "googleChatSources",
            "googleChatSourceLabel",
            "beeperAnnounceModes",
            "beeperAnnounceLabel",
            "pauseMarginLabel",
            "PAUSE_MARGIN_MAX",
            "nextPauseMargin",
            "nextVolume",
            "MIN_POLL_INTERVAL",
            "MAX_POLL_INTERVAL",
            "speakerChoiceLabel",
            "vitruvianSpeakerOutputs",
            "homeSettingsRelevant",
            "castVoiceRelevant",
            "localVoiceInUse",
            "usesVoiceEngine",
            "showsMacVoice",
            "geminiSpeaks",
            "showsStyleGeminiKey",
            "allCodingAgentsOff",
        )
    val forbiddenLiterals =
        listOf(
            "Headline (1-2 sentences)",
            "Summary (about 4 lines)",
            "Plain summary",
            "Apple (on this Mac)",
            "Apple (System)",
            "Direct messages and mentions",
            "gws command-line tool",
            "Kore · Warm & clear",
            "Enable Voice Broadcasting",
            "Enable Quiet Hours",
            "Plain spoken",
            "Gemini Flash",
            "Direct & mentions",
            "gws CLI",
            "Apple (on Mac)",
            // Old inline-error keys: errors are keyed by catalog key, not by a label.
            "What to say",
            "Style model",
            "Poll interval",
            "Speaker volume",
        )
    val hits = mutableListOf<String>()
    for (path in files) {
      val text = readRunfile(path)
      for (sym in deletedSymbols) {
        if (Regex("""\b${Regex.escape(sym)}\b""").containsMatchIn(text)) {
          hits += "$path contains deleted symbol `$sym`"
        }
      }
      for (lit in forbiddenLiterals) {
        if (text.contains("\"$lit\"")) {
          hits += "$path contains hardcoded Vitruvian Speaker choice/label literal \"$lit\""
        }
      }
    }
    assertTrue(
        "Local Vitruvian Speaker rulebook copies found:\n${hits.joinToString("\n")}",
        hits.isEmpty())
  }

  @Test
  public fun `probe catalog helpers handle shown false unknown keys choice phone substitution and stepper boundaries`() {
    val catalog =
        VitruvianSpeakerCatalog(
            listOf(
                VitruvianSpeakerSetting(
                    key = "hidden_toggle",
                    kind = "toggle",
                    label = "Hidden on Your phone",
                    boolValue = true,
                    shown = false,
                ),
                VitruvianSpeakerSetting(
                    key = "route_mode",
                    kind = "choice",
                    label = "Your phone routing",
                    stringValue = "phone_only",
                    shown = true,
                    choices =
                        listOf(
                            VitruvianSpeakerChoice("phone_only", "Your phone only"),
                            VitruvianSpeakerChoice("both", "Your phone + Mac"),
                        ),
                ),
                VitruvianSpeakerSetting(
                    key = "pause_media_extra_seconds",
                    kind = "number",
                    label = "Resume after",
                    numberValue = 0.0,
                    shown = true,
                    limits =
                        VitruvianSpeakerLimits(
                            min = 0.0, max = 10.0, step = 0.5, defaultValue = 1.0),
                ),
            ))

    assertFalse(Derive.catalogShown(catalog, "hidden_toggle"))
    assertFalse(Derive.catalogShown(catalog, "future_unknown_key"))
    assertEquals("", Derive.catalogLabel(catalog, "future_unknown_key"))
    assertEquals("unlisted_raw", Derive.catalogChoiceLabel(catalog, "route_mode", "unlisted_raw"))

    assertEquals("This phone routing", Derive.catalogLabel(catalog, "route_mode"))
    assertEquals(
        listOf(
            VitruvianSpeakerChoice("phone_only", "This phone only"),
            VitruvianSpeakerChoice("both", "This phone + Mac"),
        ),
        Derive.catalogChoices(catalog, "route_mode"),
    )
    assertEquals("This phone only", Derive.catalogChoiceLabel(catalog, "route_mode", "phone_only"))
    assertEquals(
        "This phone then This phone",
        Derive.outputsSummary("  Your phone then Your phone  "),
    )
    assertEquals(null, Derive.outputsSummary("   "))

    val limits = Derive.catalogLimits(catalog, "pause_media_extra_seconds")!!
    val atMin =
        Derive.catalogStepper(current = 0.0, limits = limits, canAct = true, unitSuffix = "s")
    assertEquals("−0.5s", atMin.minusLabel)
    assertEquals("+0.5s", atMin.plusLabel)
    assertFalse(atMin.minusEnabled)
    assertTrue(atMin.plusEnabled)

    val atMax =
        Derive.catalogStepper(current = 10.0, limits = limits, canAct = true, unitSuffix = "s")
    assertTrue(atMax.minusEnabled)
    assertFalse(atMax.plusEnabled)

    val unpaired = Derive.catalogStepper(current = 5.0, limits = limits, canAct = false)
    assertFalse(unpaired.minusEnabled)
    assertFalse(unpaired.plusEnabled)
  }

  @Test
  public fun `catalog steppers stop at the limits and never send a value outside them`() {
    val volume = VitruvianSpeakerLimits(min = 0.0, max = 100.0, step = 10.0, defaultValue = 60.0)
    val nearMax = Derive.catalogStepper(current = 95.0, limits = volume, canAct = true)
    assertEquals(100.0, nearMax.plusNext, 0.0)
    val atMax = Derive.catalogStepper(current = 100.0, limits = volume, canAct = true)
    assertFalse(atMax.plusEnabled)
    assertEquals(100.0, atMax.plusNext, 0.0)
    val nearMin = Derive.catalogStepper(current = 5.0, limits = volume, canAct = true)
    assertEquals(0.0, nearMin.minusNext, 0.0)
    val poll = VitruvianSpeakerLimits(min = 5.0, max = 300.0, step = 5.0, defaultValue = 15.0)
    assertEquals(5.0, Derive.catalogStepper(7.0, poll, true).minusNext, 0.0)
    assertEquals(300.0, Derive.catalogStepper(298.0, poll, true).plusNext, 0.0)
  }

  @Test
  public fun `the speaker's live volume is kept inside the device's 0 to 100 before sending`() {
    assertEquals(100, Derive.clampSpeakerVolume(105))
    assertEquals(0, Derive.clampSpeakerVolume(-10))
    assertEquals(60, Derive.clampSpeakerVolume(60))
  }

  @Test
  public fun `quiet hours quick action shows no window the Mac did not report`() {
    val spec =
        Derive.quietHoursQuickAction(
            true, true, enabled = true, active = false, start = "", end = "")
    assertNull(spec.secondary)
    assertFalse(spec.contentDescription.contains("22:00"))
    val reported =
        Derive.quietHoursQuickAction(
            true, true, enabled = true, active = false, start = "21:00", end = "06:30")
    assertEquals("21:00–06:30", reported.secondary)
  }

  @Test
  public fun `without a catalog the Now strip keeps only replay, no setting controls`() {
    fun ids(hasCatalog: Boolean) =
        Derive.vitruvianSpeakerQuickActions(
                hasCatalog = hasCatalog,
                paired = true,
                available = true,
                volumeAvailable = true,
                volumeOnline = true,
                muted = false,
                percent = 40,
                quietEnabled = false,
                quietActive = false,
                quietStart = "",
                quietEnd = "",
                targetName = "Office Mini",
                hasReplay = true,
            )
            .map { it.id }
    assertEquals(listOf("replay"), ids(false))
    assertEquals(listOf("mute", "quiet_hours", "room", "replay", "snooze"), ids(true))
  }

  @Test
  public fun `a refusal recorded under a catalog key shows on that row, an old label does not`() {
    val errors = mapOf("speech_length" to "Vitruvian Speaker refused that")
    assertEquals("Vitruvian Speaker refused that", Derive.settingError(errors, "speech_length"))
    assertNull(Derive.settingError(errors, "What to say"))
  }

  @Test
  public fun `setVitruvianSpeaker files its errors under real catalog keys`() {
    val catalogKeys =
        VitruvianSpeakerWire.sources(
                readRunfile("apps/mobile/vitruvian-remote/macagent/golden_speaker_v1.json"))
            .catalog
            .settings
            .map { it.key }
            .toSet()
    val text =
        readRunfile(
            "apps/mobile/vitruvian-remote/src/main/kotlin/dev/vitruvian/remote/state/RemoteState.kt")
    val block =
        text.substringAfter("    val key =\n        controlId").substringBefore("else -> what")
    val keys = Regex("""-> "([a-z][a-z_]+)"""").findAll(block).map { it.groupValues[1] }.toList()
    assertTrue("no catalog-key error keys found in setVitruvianSpeaker", keys.size >= 30)
    // "snooze" is the phone's own Now-strip control, not a Vitruvian Speaker field.
    val notInCatalog = keys.filter { it !in catalogKeys && it != "snooze" }
    assertTrue("error keys that are not catalog keys: $notInCatalog", notInCatalog.isEmpty())
  }

  @Test
  public fun `genericKeys returns undrawn keys in catalog order and placed refuses duplicates`() {
    // Missing / unplaced key falls through to generic.
    assertEquals(listOf("a", "c"), Derive.genericKeys(listOf("a", "b", "c"), setOf("b")))
    // All drawn gives none.
    assertEquals(emptyList<String>(), Derive.genericKeys(listOf("a", "b"), setOf("a", "b")))
    // Catalog order is preserved.
    assertEquals(
        listOf("z", "m", "b"),
        Derive.genericKeys(listOf("z", "a", "m", "b"), setOf("a")),
    )

    // placed() records on first call and refuses duplicates without running the second builder.
    val placement = Derive.CatalogPlacement()
    var duplicateInvoked = false
    assertEquals("first-row", placement.placed("enabled") { "first-row" })
    assertNull(
        placement.placed("enabled") {
          duplicateInvoked = true
          "duplicate-row"
        })
    assertFalse("duplicate placed() must not invoke its builder", duplicateInvoked)
    assertEquals(setOf("enabled"), placement.drawnKeys)
  }

  @Test
  public fun `every catalog setting in golden payload is either hand-placed or gets a generic row exactly once`() {
    val goldenJson = readRunfile("apps/mobile/vitruvian-remote/macagent/golden_speaker_v1.json")
    val sources = VitruvianSpeakerWire.sources(goldenJson)
    val catalog = sources.catalog
    assertTrue(sources.genericSettings)
    val catalogKeys = catalog.settings.map { it.key }
    assertEquals("duplicate keys in golden catalog", catalogKeys.toSet().size, catalogKeys.size)

    val remoteText =
        readRunfile(
            "apps/mobile/vitruvian-remote/src/main/kotlin/dev/vitruvian/remote/state/RemoteState.kt")
    assertFalse(
        "placedVitruvianSpeakerKeys constant must stay deleted",
        remoteText.contains("placedVitruvianSpeakerKeys"),
    )
    assertTrue(
        "Other settings must read placement.drawnKeys",
        remoteText.contains("drawnKeys = placement.drawnKeys"),
    )

    val placedCalls =
        Regex("""\bplaced\("([a-z][a-z_]+)"\)""")
            .findAll(remoteText)
            .map { it.groupValues[1] }
            .toList()
    assertTrue("expected hand-placed catalog keys in RemoteState.kt", placedCalls.isNotEmpty())

    val placement = Derive.CatalogPlacement()
    val duplicatePlaced = mutableListOf<String>()
    for (key in placedCalls) {
      if (placement.placed(key) { key } == null) {
        duplicatePlaced.add(key)
      }
    }
    assertTrue(
        "duplicate placed() calls in RemoteState.kt: $duplicatePlaced", duplicatePlaced.isEmpty())

    val drawn = placement.drawnKeys
    val stalePlaced = drawn - catalogKeys.toSet()
    assertTrue("placed() has keys absent from golden catalog: $stalePlaced", stalePlaced.isEmpty())

    // Any catalog key directly read by a hand row in RemoteState.kt must go through placed().
    val handReferencedKeys =
        Regex(
                """\b(?:lbl|shown|sourceRow)\(\s*"([a-z][a-z_]+)"|catalog(?:Shown|Label)\([^,]+,\s*"([a-z][a-z_]+)"\)""")
            .findAll(remoteText)
            .map { it.groupValues[1].ifEmpty { it.groupValues[2] } }
            .filter { it in catalogKeys }
            .toSet()
    val unplacedHandKeys = handReferencedKeys - drawn
    assertTrue(
        "hand-rendered catalog keys missing placed() wrapper (would double-render): $unplacedHandKeys",
        unplacedHandKeys.isEmpty(),
    )

    val generic =
        Derive.genericVitruvianSpeakerRows(
                catalog,
                drawnKeys = drawn,
                includeHidden = true,
                genericSettingsSupported = sources.genericSettings,
            )
            .map { it.key }
    assertEquals(Derive.genericKeys(catalogKeys, drawn), generic)

    val overlap = drawn.intersect(generic.toSet())
    assertTrue("keys both hand-placed and generic: $overlap", overlap.isEmpty())

    val dropped = catalogKeys.filter { it !in drawn && it !in generic }
    assertTrue("catalog keys dropped (neither placed nor generic): $dropped", dropped.isEmpty())

    assertEquals(catalogKeys.size, drawn.size + generic.size)
    // Today every golden key has a hand-designed home, so "Other settings" is empty. A key
    // Vitruvian Speaker adds later lands here and shows on the phone with no phone release; this
    // line then names it, which is the prompt to decide whether it deserves a hand-made row.
    assertEquals(emptyList<String>(), generic)
  }

  @Test
  public fun `controls manifest supported ids match VitruvianSpeakerControls constants one to one`() {
    val raw = readRunfile("apps/desktop/vitruvian-speaker/testdata/controls.json")
    val entries = JsonReader(raw).readValue() as List<*>
    val allManifestIds = mutableSetOf<String>()
    val supportedManifestIds = mutableSetOf<String>()
    for (item in entries) {
      val obj = item as Map<*, *>
      val id = obj["id"] as String
      val phone = obj["phone"] as String
      assertTrue("duplicate id in controls.json: $id", allManifestIds.add(id))
      if (phone == "supported") {
        supportedManifestIds.add(id)
      }
    }
    assertTrue("no supported controls parsed from controls.json", supportedManifestIds.isNotEmpty())

    val constFields =
        VitruvianSpeakerControls::class.java.declaredFields.filter {
          java.lang.reflect.Modifier.isStatic(it.modifiers) && it.type == String::class.java
        }
    val phoneIds = constFields.map { it.get(null) as String }
    assertEquals(
        "duplicate constant values in VitruvianSpeakerControls",
        phoneIds.toSet().size,
        phoneIds.size)

    val phoneIdSet = phoneIds.toSet()
    val missingFromPhone = supportedManifestIds - phoneIdSet
    assertTrue(
        "supported controls.json ids missing from VitruvianSpeakerControls: $missingFromPhone",
        missingFromPhone.isEmpty(),
    )
    val notInManifest = phoneIdSet - allManifestIds
    assertTrue(
        "VitruvianSpeakerControls ids missing from controls.json: $notInManifest",
        notInManifest.isEmpty(),
    )
    val excludedInPhone = phoneIdSet - supportedManifestIds
    assertTrue(
        "excluded controls.json ids present in VitruvianSpeakerControls: $excludedInPhone",
        excludedInPhone.isEmpty(),
    )

    val remoteText =
        readRunfile(
            "apps/mobile/vitruvian-remote/src/main/kotlin/dev/vitruvian/remote/state/RemoteState.kt")
    assertFalse("dead manifestId plumbing must stay removed", remoteText.contains("manifestId"))
    assertFalse(
        "dead resolvedManifestId plumbing must stay removed",
        remoteText.contains("resolvedManifestId"),
    )
    val unwiredControls =
        constFields
            .map { it.name }
            .filter { name ->
              !Regex("""controlId\s*=\s*VitruvianSpeakerControls\.${Regex.escape(name)}\b""")
                  .containsMatchIn(remoteText)
            }
    assertTrue(
        "VitruvianSpeakerControls constants missing `controlId = VitruvianSpeakerControls.X` in RemoteState.kt: $unwiredControls",
        unwiredControls.isEmpty(),
    )
  }

  @Test
  public fun `hookWithoutVitruvianSpeaker matches Pages swift`() {
    val pagesSwift =
        readRunfile("apps/desktop/vitruvian-speaker/Sources/VitruvianSpeakerToolCore/Pages.swift")
    val match =
        Regex("""public static let hookWithoutVitruvianSpeaker\s*=\s*"([^"]+)"""").find(pagesSwift)
    assertTrue("hookWithoutVitruvianSpeaker constant not found in Pages.swift", match != null)
    assertEquals(match!!.groupValues[1], Derive.HOOK_WITHOUT_VITRUVIANSPEAKER)
  }

  @Test
  public fun `generic renderer maps toggle choice number text and time kinds and honors shown`() {
    val catalog =
        VitruvianSpeakerCatalog(
            listOf(
                VitruvianSpeakerSetting(
                    key = "future_toggle",
                    kind = "toggle",
                    label = "Chime on Your phone",
                    boolValue = true,
                    shown = true,
                ),
                VitruvianSpeakerSetting(
                    key = "future_choice",
                    kind = "choice",
                    label = "Tone",
                    stringValue = "warm",
                    shown = true,
                    choices =
                        listOf(
                            VitruvianSpeakerChoice("warm", "Warm on Your phone"),
                            VitruvianSpeakerChoice("crisp", "Crisp"),
                        ),
                ),
                VitruvianSpeakerSetting(
                    key = "future_number",
                    kind = "number",
                    label = "Ducking",
                    numberValue = 95.0,
                    shown = true,
                    limits =
                        VitruvianSpeakerLimits(
                            min = 0.0, max = 100.0, step = 10.0, defaultValue = 50.0),
                ),
                VitruvianSpeakerSetting(
                    key = "future_text",
                    kind = "text",
                    label = "Prefix",
                    stringValue = "Heads up:",
                    shown = true,
                ),
                VitruvianSpeakerSetting(
                    key = "future_time",
                    kind = "time",
                    label = "Wake at",
                    stringValue = "07:15",
                    shown = true,
                ),
                VitruvianSpeakerSetting(
                    key = "future_hidden",
                    kind = "toggle",
                    label = "Hidden",
                    boolValue = false,
                    shown = false,
                ),
            ))

    val visible =
        Derive.genericVitruvianSpeakerRows(
            catalog = catalog,
            canAct = true,
            errors = mapOf("future_text" to "Refused"),
            drawnKeys = emptySet(),
        )
    assertEquals(
        listOf("future_toggle", "future_choice", "future_number", "future_text", "future_time"),
        visible.map { it.key },
    )

    val toggleRow = visible[0]
    assertEquals("Chime on This phone", toggleRow.title)
    assertEquals(
        Derive.GenericSettingControl.Toggle(checked = true, enabled = true), toggleRow.control)

    val choiceRow = visible[1]
    assertEquals("Warm on This phone", choiceRow.trailing)
    val choiceCtrl = choiceRow.control as Derive.GenericSettingControl.Choices
    assertEquals("Warm on This phone", choiceCtrl.options.first().label)

    val numRow = visible[2]
    val numCtrl = numRow.control as Derive.GenericSettingControl.NumberStepper
    assertEquals(100.0, numCtrl.stepper!!.plusNext, 0.0)
    assertEquals(85.0, numCtrl.stepper!!.minusNext, 0.0)
    assertTrue(numCtrl.isInteger)

    val textRow = visible[3]
    assertEquals("Heads up:", textRow.subtitle)
    assertEquals("Refused", textRow.error)
    assertEquals(
        Derive.GenericSettingControl.TextPrompt(
            value = "Heads up:", hasValue = true, enabled = true),
        textRow.control,
    )

    val timeRow = visible[4]
    val timeCtrl = timeRow.control as Derive.GenericSettingControl.Choices
    // 48 half-hours + custom off-half-hour 07:15 preserved first.
    assertEquals(49, timeCtrl.options.size)
    assertEquals("07:15", timeCtrl.options.first().value)
    assertEquals("00:00", timeCtrl.options[1].value)
    assertEquals("23:30", timeCtrl.options.last().value)

    assertNull(
        Derive.genericVitruvianSpeakerRow(
            VitruvianSpeakerSetting(key = "unknown", kind = "curve", label = "Curve")))
  }

  @Test
  public fun `home picker speaker remove door copy stale hook remove and visibility parity`() {
    // Home picker: empty degrades quietly; non-empty shows selected and lets user pick others.
    assertNull(Derive.homePickerSpec(emptyList()))
    val homes =
        listOf(
            AgentHome("home-1", "Apartment", selected = false),
            AgentHome("home-2", "Cabin", selected = true),
        )
    val picker = Derive.homePickerSpec(homes, structureId = "home-1", canAct = true)!!
    assertEquals("home-2", picker.selectedId)
    assertEquals("Cabin", picker.trailing)
    assertEquals(listOf("Apartment", "Cabin"), picker.choices.map { it.name })
    assertTrue(picker.choices[0].enabled && !picker.choices[0].selected)
    assertTrue(!picker.choices[1].enabled && picker.choices[1].selected)

    // Remove any speaker: every speaker row gets Remove, not only default.
    val speakers =
        Derive.speakerRowSpecs(
            listOf(
                VitruvianSpeakerTargetWire(
                    "office", "Office Mini", "Office", "Mini", selected = true),
                VitruvianSpeakerTargetWire(
                    "kitchen", "Kitchen Hub", "Kitchen", "Hub", selected = false),
            ),
            canAct = true,
        )
    assertEquals(2, speakers.size)
    assertTrue(speakers.all { it.removeEnabled })
    assertEquals("default", speakers[0].trailing)
    assertEquals("", speakers[1].trailing)

    // Door switch: offers "Copy settings from the <current>" with copy = true, gated on version.
    assertTrue(Derive.supportsDoorCopy("1.41.0"))
    assertTrue(Derive.supportsDoorCopy("1.42.0"))
    assertFalse(Derive.supportsDoorCopy("1.40.9"))
    assertFalse(Derive.supportsDoorCopy(""))
    val fromApp =
        Derive.doorSwitchOptions(
            activeDoor = "app", appInstalled = true, extensionInstalled = true, canAct = true)
    assertEquals(3, fromApp.size)
    val copyFromApp = fromApp.single { it.copy }
    assertEquals("extension", copyFromApp.targetDoor)
    assertEquals("Copy settings from the app", copyFromApp.label)

    val fromExtNoApp =
        Derive.doorSwitchOptions(
            activeDoor = "extension",
            appInstalled = false,
            extensionInstalled = true,
            canAct = true)
    assertEquals(1, fromExtNoApp.size)
    assertTrue(fromExtNoApp.single().selected)

    // Stale hook: missing target Vitruvian Speaker offers both Update hook and Remove when active
    // is
    // installed.
    val staleTrashedApp =
        AgentHookStatus(
            agent = "Claude Code",
            agentSlug = "claude-code",
            hookState = "stale",
            staleCommand =
                "'/Applications/Vitruvian Speaker.app/Contents/MacOS/VitruvianSpeaker' --claude-stop-hook",
            hookProgram = "/Applications/Vitruvian Speaker.app/Contents/MacOS/VitruvianSpeaker",
        )
    val bothInstalled =
        Derive.agentHookRowSpec(
            staleTrashedApp, installed = true, appInstalled = true, extensionInstalled = true)
    assertTrue(bothInstalled.showUpdate)
    assertFalse(bothInstalled.showRemove)

    val appGoneExtActive =
        Derive.agentHookRowSpec(
            staleTrashedApp, installed = true, appInstalled = false, extensionInstalled = true)
    assertTrue(appGoneExtActive.showUpdate)
    assertTrue(appGoneExtActive.showRemove)
    assertEquals("Remove", appGoneExtActive.removeLabel)
    assertEquals(Derive.HOOK_WITHOUT_VITRUVIANSPEAKER, appGoneExtActive.subtitle)

    val neitherInstalled =
        Derive.agentHookRowSpec(
            staleTrashedApp, installed = false, appInstalled = false, extensionInstalled = false)
    assertFalse(neitherInstalled.showUpdate)
    assertTrue(neitherInstalled.showRemove)

    // Older helper (no generic_settings / copy support): hides generic rows and copy-on-switch.
    assertTrue(
        Derive.genericVitruvianSpeakerRows(
                catalog =
                    VitruvianSpeakerCatalog(
                        listOf(
                            VitruvianSpeakerSetting(
                                key = "beeper_address",
                                kind = "text",
                                label = "Address",
                                stringValue = "http://127.0.0.1:23373",
                                shown = true,
                            ))),
                genericSettingsSupported = false,
            )
            .isEmpty())
    val olderDoor =
        Derive.doorSwitchOptions(
            activeDoor = "app",
            appInstalled = null,
            extensionInstalled = true,
            canAct = true,
            copySupported = false,
        )
    assertEquals(listOf("App", "Extension"), olderDoor.map { it.label })
    assertFalse(olderDoor.any { it.copy })

    // Older helper (no stale_command / hook_program): degrades quietly to Update hook only.
    val olderStale = AgentHookStatus(agent = "Claude Code", hookState = "stale")
    val olderSpec = Derive.agentHookRowSpec(olderStale, installed = true)
    assertTrue(olderSpec.showUpdate)
    assertFalse(olderSpec.showRemove)

    // Chat monitor Start/Stop: hidden when ownerRunning is explicitly false; shown on older
    // helpers where ownerRunning is null; gated on anySourceEnabled when ownerRunning is true.
    assertTrue(Derive.showsChatMonitorControl(ownerRunning = true, anySourceEnabled = true))
    assertFalse(Derive.showsChatMonitorControl(ownerRunning = true, anySourceEnabled = false))
    assertFalse(Derive.showsChatMonitorControl(ownerRunning = false, anySourceEnabled = true))
    assertFalse(Derive.showsChatMonitorControl(ownerRunning = false, anySourceEnabled = false))
    assertTrue(Derive.showsChatMonitorControl(ownerRunning = null, anySourceEnabled = true))
    assertTrue(Derive.showsChatMonitorControl(ownerRunning = null, anySourceEnabled = false))

    // Visibility parity in RemoteState.kt: Coding agents and Chat apps are not gated on hs.enabled,
    // while Poll interval and Skip messages I sent stay gated on anyChat.
    val remoteSrc =
        readRunfile(
            "apps/mobile/vitruvian-remote/src/main/kotlin/dev/vitruvian/remote/state/RemoteState.kt")
    assertFalse(remoteSrc.contains("if (hs.enabled && claude != null"))
    assertFalse(remoteSrc.contains("if (hs.enabled && slack != null"))
    assertTrue(
        remoteSrc.contains(
            """if (anyChat && Derive.catalogShown(hs.catalog, "poll_interval_seconds"))"""))
    assertTrue(
        Regex("""placed\("mute_own_messages"\)\s*\{\s*if \(anyChat\)""").containsMatchIn(remoteSrc))
  }

  // --- F2: honest connection state & cold launch polling -----------------

  @Test
  public fun `cold launch starts asking and poll failure sets offline without red flash`() {
    // Saved host before first reply -> "asking…", neither offline nor simulated demo data.
    val initialPhase =
        Derive.hostPhase(
            hasHosts = true,
            demoMode = false,
            hasResponded = false,
            isOffline = false,
        )
    assertEquals(Derive.HostPhase.Asking, initialPhase)
    assertEquals("asking…", Derive.sourceBadgeLabel(initialPhase, needsPairing = false))
    assertEquals(
        "asking…",
        Derive.hostStatusWord(
            initialPhase,
            Derive.Pairing.Paired,
            needsPairing = false,
        ),
    )
    assertFalse(Derive.isStaleReading(initialPhase))
    assertFalse(Derive.mayShowDemoData(initialPhase))

    // First poll fails -> PollOutcome.Offline, turning status red/offline.
    assertEquals(
        Derive.PollOutcome.Offline,
        Derive.afterPoll(hasHosts = true, demoMode = false, pollSucceeded = false),
    )
    val offlinePhase =
        Derive.hostPhase(
            hasHosts = true,
            demoMode = false,
            hasResponded = false,
            isOffline = true,
        )
    assertEquals(Derive.HostPhase.Offline, offlinePhase)
    assertEquals("unreachable", Derive.sourceBadgeLabel(offlinePhase, needsPairing = false))
    assertTrue(Derive.isStaleReading(offlinePhase))

    // Poll succeeds -> PollOutcome.Live -> live badge.
    assertEquals(
        Derive.PollOutcome.Live,
        Derive.afterPoll(hasHosts = true, demoMode = false, pollSucceeded = true),
    )
    val livePhase =
        Derive.hostPhase(
            hasHosts = true,
            demoMode = false,
            hasResponded = true,
            isOffline = false,
        )
    assertEquals(Derive.HostPhase.Live, livePhase)
    assertEquals("live", Derive.sourceBadgeLabel(livePhase, needsPairing = false))
    assertEquals("not paired", Derive.sourceBadgeLabel(livePhase, needsPairing = true))

    val remoteSrc =
        readRunfile(
            "apps/mobile/vitruvian-remote/src/main/kotlin/dev/vitruvian/remote/state/RemoteState.kt")
    assertTrue(remoteSrc.contains("Derive.afterPoll("))
    assertTrue(remoteSrc.contains("Derive.PollOutcome.Offline -> Connection.Offline"))
  }

  // --- F1 & F5: no MockHost data for a saved-but-offline Mac & forgetHost -

  @Test
  public fun `saved but offline host derived Home Mac Remote state never emits MockHost values`() {
    // 1) Never answered offline host.
    val neverReadPhase =
        Derive.hostPhase(hasHosts = true, demoMode = false, hasResponded = false, isOffline = true)
    assertFalse(Derive.mayShowDemoData(neverReadPhase))
    val unansweredHome =
        listOf(
            Derive.sourceBadgeLabel(neverReadPhase, needsPairing = false),
            Derive.hostSummarySubline(
                neverReadPhase,
                osVersion = null,
                agentVersion = null,
                uptimeDays = null,
                lastSeen = ""),
            Derive.unansweredHostLine("macbook"),
            Derive.runningNowEmptyMessage(neverReadPhase, hasFirstReading = false).orEmpty(),
        )
    assertEquals("unreachable", unansweredHome[0])
    assertEquals("unreachable", unansweredHome[1])
    assertEquals("macbook isn't answering", unansweredHome[2])

    // 2) Previously answered host now offline keeps real cached reading with "last seen …".
    val stalePhase =
        Derive.hostPhase(hasHosts = true, demoMode = false, hasResponded = true, isOffline = true)
    assertTrue(Derive.isStaleReading(stalePhase))
    assertFalse(Derive.mayShowDemoData(stalePhase))
    val lastSeen = Format.lastSeen("2026-11-15T00:00:00Z", 1794700920_000L)
    val cachedSummary =
        Derive.hostSummarySubline(
            stalePhase,
            osVersion = "15.3",
            agentVersion = "0.1.40",
            uptimeDays = 5,
            lastSeen = lastSeen,
        )
    val cachedTile = Derive.readingSubline("26.4 / 64 GB used", stale = true, lastSeen = lastSeen)
    assertTrue(cachedSummary.contains("macOS 15.3"))
    assertTrue(cachedSummary.contains("Mac helper v0.1.40"))
    assertFalse(cachedSummary.contains("agent v"))
    assertTrue(cachedSummary.contains("last seen"))
    assertTrue(cachedTile.contains("last seen"))

    assertEquals(
        "macOS 15.3 · Mac helper v0.1.40 · up 5d",
        Derive.hostSummarySubline(
            Derive.HostPhase.Live,
            osVersion = "15.3",
            agentVersion = "0.1.40",
            uptimeDays = 5,
            lastSeen = "",
        ),
    )
    assertFalse(
        Derive.hostSummarySubline(
                Derive.HostPhase.Demo,
                osVersion = null,
                agentVersion = null,
                uptimeDays = null,
                lastSeen = "",
            )
            .contains("Tailscale", ignoreCase = true),
    )

    // Assert zero fabricated MockHost literals appear anywhere in offline derived outputs.
    val mockMarkers = listOf("M4 Max", "64 GB", "2 TB", "492 W", "Brew upgrade", "Screenshot")
    for (line in unansweredHome + cachedSummary) {
      for (marker in mockMarkers) {
        assertFalse(
            "Saved-but-offline derived output leaked mock marker '$marker': $line",
            line.contains(marker),
        )
      }
    }

    // F5: forgetHost state transition & source checks.
    assertEquals(Derive.PollOutcome.Unpaired, Derive.afterForgetHost(0))
    assertEquals(Derive.PollOutcome.Asking, Derive.afterForgetHost(1))

    val remoteSrc =
        readRunfile(
            "apps/mobile/vitruvian-remote/src/main/kotlin/dev/vitruvian/remote/state/RemoteState.kt")
    val forgetBlock =
        remoteSrc
            .substringAfter("public fun forgetHost(id: String)")
            .substringBefore("public fun updateHostAliasDraft")
    assertTrue(forgetBlock.contains("demoMode = false"))
    assertTrue(forgetBlock.contains("resetHostSnapshots()"))
    assertTrue(forgetBlock.contains("metricsSource ="))

    // Every runtime MockHost data read (outside gallery metadata and constructor seed) uses
    // isDemoMode.
    val mockDataReads =
        Regex(
            """MockHost\.(hosts|processes|vms|containers|runningNow|recentCommands|dashboards|builtInMacros|demoInstalled)""")
    val matchingLines =
        remoteSrc.lines().filter { line ->
          mockDataReads.containsMatchIn(line) && !line.trimStart().startsWith("MockHost.")
        }
    assertTrue(
        "Unexpected un-gated MockHost data access in RemoteState.kt: $matchingLines",
        matchingLines.all { it.contains("isDemoMode") },
    )
    assertFalse(
        "MockHost.runningNow must not be returned when !isLive",
        remoteSrc.contains("if (!isLive) return MockHost.runningNow"),
    )
    val remoteScreenSrc =
        readRunfile(
            "apps/mobile/vitruvian-remote/src/main/kotlin/dev/vitruvian/remote/screens/RemoteScreen.kt")
    assertTrue(
        remoteScreenSrc.contains("if (state.isDemoMode) \"Media · Music\" else \"Media keys\""))
    assertTrue(remoteScreenSrc.contains("if (state.isDemoMode) {"))
  }

  // --- F3: first run starts unpaired & demo mode is explicit + non-persisted

  @Test
  public fun `first run starts unpaired with demo behind See a demo banner`() {
    val unpaired =
        Derive.hostPhase(
            hasHosts = false, demoMode = false, hasResponded = false, isOffline = false)
    assertEquals(Derive.HostPhase.Unpaired, unpaired)
    assertEquals(
        Derive.PollOutcome.Unpaired,
        Derive.afterPoll(hasHosts = false, demoMode = false, pollSucceeded = false),
    )
    val demo =
        Derive.hostPhase(hasHosts = false, demoMode = true, hasResponded = false, isOffline = false)
    assertEquals(Derive.HostPhase.Demo, demo)
    assertTrue(Derive.mayShowDemoData(demo))
    assertEquals("simulated", Derive.sourceBadgeLabel(demo, needsPairing = false))

    val hostStatesSrc =
        readRunfile(
            "apps/mobile/vitruvian-remote/src/main/kotlin/dev/vitruvian/remote/overlays/HostStates.kt")
    assertTrue(hostStatesSrc.contains("\"See a demo\""))
    assertTrue(hostStatesSrc.contains("state::enterDemo"))

    val shellSrc =
        readRunfile(
            "apps/mobile/vitruvian-remote/src/main/kotlin/dev/vitruvian/remote/shell/Shell.kt")
    assertTrue(shellSrc.contains("if (state.isDemoMode)"))
    assertTrue(shellSrc.contains("\"Demo data\""))
    assertTrue(shellSrc.contains("\"Exit demo\""))

    val persistSrc =
        readRunfile(
            "apps/mobile/vitruvian-remote/src/main/kotlin/dev/vitruvian/remote/state/Persistence.kt")
    assertFalse(persistSrc.contains("demoMode"))
    assertFalse(persistSrc.contains("demo_mode"))
  }

  // --- F4: persisted settings & defaults --------------------------------

  @Test
  public fun `normalizeRefreshInterval clamps null and unknown values to default`() {
    assertEquals(Derive.DEFAULT_REFRESH_INTERVAL, Derive.normalizeRefreshInterval(null))
    assertEquals(Derive.DEFAULT_REFRESH_INTERVAL, Derive.normalizeRefreshInterval("invalid"))
    assertEquals("5 s", Derive.normalizeRefreshInterval("5 s"))
    assertEquals("30 s", Derive.normalizeRefreshInterval("30 s"))
  }

  // --- F15 & F16: neutral defaults, module discovery, macro edit/delete ---

  @Test
  public fun `neutral defaults ship only discovered modules and Shell macro kind`() {
    val rules =
        listOf(
            Derive.ModuleDiscoveryRule("claude", "claude", autoShow = true),
            Derive.ModuleDiscoveryRule("homelab", "kubectl", autoShow = false),
            Derive.ModuleDiscoveryRule("lima", "limactl", autoShow = false),
            Derive.ModuleDiscoveryRule("speaker", "speaker", autoShow = true),
            Derive.ModuleDiscoveryRule("tv", "adb", autoShow = false),
        )
    assertEquals(setOf("claude"), Derive.discoveredModuleIds(rules, emptySet()))
    assertEquals(
        setOf("claude", "speaker"),
        Derive.discoveredModuleIds(rules, setOf("limactl", "kubectl", "adb", "speaker")),
    )

    assertEquals("Delete", Derive.macroDeleteLabel(armed = false))
    assertEquals("Confirm delete", Derive.macroDeleteLabel(armed = true))

    val mockSrc =
        readRunfile(
            "apps/mobile/vitruvian-remote/src/main/kotlin/dev/vitruvian/remote/state/MockHost.kt")
    assertTrue(mockSrc.contains("defaultInstalled: Set<String> = setOf(\"claude\")"))

    val modelsSrc =
        readRunfile(
            "apps/mobile/vitruvian-remote/src/main/kotlin/dev/vitruvian/remote/state/Models.kt")
    assertTrue(
        "Persisted enum name Ssh stays intact with Shell label",
        modelsSrc.contains("Ssh(\"Shell\")"))

    val remoteSrc =
        readRunfile(
            "apps/mobile/vitruvian-remote/src/main/kotlin/dev/vitruvian/remote/state/RemoteState.kt")
    val restartBlock =
        remoteSrc
            .substringAfter("public data class DialogSpec(")
            .substringAfter("DialogKind.Restart ->")
            .substringBefore("is DialogKind.MergePr ->")
    assertTrue(
        restartBlock.contains("\"Your Mac will restart. Unsaved work in open apps may be lost.\""))
    assertFalse(restartBlock.contains("Lima VMs"))
    assertFalse(restartBlock.contains("homelab node"))

    val editorSrc =
        readRunfile(
            "apps/mobile/vitruvian-remote/src/main/kotlin/dev/vitruvian/remote/overlays/MacroEditor.kt")
    assertTrue(editorSrc.contains("Derive.macroDeleteLabel"))
    assertTrue(editorSrc.contains("ButtonVariant.Danger"))
    assertTrue(editorSrc.contains("placeholder = Derive.MACRO_NAME_HINT"))
    assertTrue(editorSrc.contains("placeholder = Derive.MACRO_COMMAND_HINT"))
    assertTrue(Derive.MACRO_NAME_HINT.contains("Lock screen"))
    assertTrue(Derive.MACRO_COMMAND_HINT.contains("pmset displaysleepnow"))
    assertFalse(editorSrc.contains("Deploy staging"))
    assertFalse(editorSrc.contains("bazel run //tools/gitops:sync"))

    val hostsSrc =
        readRunfile(
            "apps/mobile/vitruvian-remote/src/main/kotlin/dev/vitruvian/remote/screens/HostsScreen.kt")
    assertTrue(hostsSrc.contains("state.editMacro(macro.id)"))
  }

  @Test
  public fun `discoveredModuleIds auto-shows only module-specific tools and never tv homelab or lima`() {
    val rules = MockHost.discoveryRules()
    assertEquals(
        setOf("claude"),
        Derive.discoveredModuleIds(rules, setOf("adb", "kubectl", "limactl", "docker")),
    )
    assertEquals(
        setOf("claude", "antigravity", "prs", "ollama", "speaker"),
        Derive.discoveredModuleIds(
            rules,
            setOf("adb", "kubectl", "limactl", "agy", "gh", "ollama", "speaker"),
        ),
    )
  }

  // --- F6, F33, F36: memory warn parity, push spec, running now empty copy

  @Test
  public fun `small copy and Home memory warn match Mac screen`() {
    assertFalse(Derive.isMemoryWarn(74))
    assertTrue(Derive.isMemoryWarn(75))
    assertTrue(Derive.isMemoryWarn(100))
    assertEquals(100, Derive.memoryUsedPercent(100L, 100L, freePercent = 0))
    assertEquals(100, Derive.memoryUsedPercent(0L, 0L, freePercent = 0))

    val remoteSrc =
        readRunfile(
            "apps/mobile/vitruvian-remote/src/main/kotlin/dev/vitruvian/remote/state/RemoteState.kt")
    val warnCalls = Regex("""Derive\.isMemoryWarn\(""").findAll(remoteSrc).count()
    assertTrue(
        "Expected both Mac memoryPlate and Home mem widget to use Derive.isMemoryWarn",
        warnCalls >= 2)

    val unconfigured =
        Derive.pushNotifySpec(
            paired = true,
            reported = false,
            configured = false,
            enabled = true,
            topic = "",
        )
    assertFalse(unconfigured.checked)
    assertFalse(unconfigured.switchEnabled)
    assertFalse(unconfigured.testEnabled)
    assertEquals("Set up ntfy on the Mac to get alerts.", unconfigured.subtitle)

    val unconfiguredFalse =
        Derive.pushNotifySpec(
            paired = true,
            reported = true,
            configured = false,
            enabled = true,
            topic = "",
        )
    assertFalse(unconfiguredFalse.checked)
    assertFalse(unconfiguredFalse.switchEnabled)
    assertFalse(unconfiguredFalse.testEnabled)
    assertEquals("Set up ntfy on the Mac to get alerts.", unconfiguredFalse.subtitle)

    val configured =
        Derive.pushNotifySpec(
            paired = true,
            reported = true,
            configured = true,
            enabled = true,
            topic = "vitruvian",
        )
    assertTrue(configured.checked)
    assertTrue(configured.switchEnabled)
    assertTrue(configured.testEnabled)
    assertEquals("push · topic vitruvian", configured.subtitle)

    val muted =
        Derive.pushNotifySpec(
            paired = true,
            reported = true,
            configured = true,
            enabled = false,
            topic = "vitruvian",
        )
    assertFalse(muted.checked)
    assertTrue(muted.switchEnabled)
    assertTrue(muted.testEnabled)
    assertEquals("push · topic vitruvian · muted", muted.subtitle)

    assertEquals(
        "Checking…",
        Derive.runningNowEmptyMessage(Derive.HostPhase.Asking, hasFirstReading = false),
    )
    assertEquals(
        "Checking…",
        Derive.runningNowEmptyMessage(Derive.HostPhase.Live, hasFirstReading = false),
    )
    assertEquals(
        "Nothing running",
        Derive.runningNowEmptyMessage(Derive.HostPhase.Live, hasFirstReading = true),
    )
    assertNull(Derive.runningNowEmptyMessage(Derive.HostPhase.Offline, hasFirstReading = false))
    assertNull(Derive.runningNowEmptyMessage(Derive.HostPhase.Demo, hasFirstReading = false))
  }

  @Test
  public fun `disableCrashReporting closes Sentry then removes sentry cache tree without recreating it`() {
    val cacheDir = java.nio.file.Files.createTempDirectory("vitruvian-remote-sentry-off").toFile()
    try {
      val sentryDir = AppInfo.sentryCacheDir(cacheDir)
      val nestedOutbox = java.io.File(sentryDir, "dsn-cache/outbox").apply { mkdirs() }
      java.io.File(sentryDir, "state.json").writeText("enabled=true")
      java.io.File(nestedOutbox, "queued.envelope").writeText("pending")
      val unrelatedFile =
          java.io.File(java.io.File(cacheDir, "http").apply { mkdirs() }, "keep.bin").apply {
            writeText("keep")
          }

      var closed = false
      AppInfo.disableCrashReporting(
          appCacheDir = cacheDir,
          closeSentry = {
            assertTrue("Sentry cache should still exist before close finishes", sentryDir.exists())
            java.io.File(sentryDir, "dsn-cache/flushed-on-close.envelope").writeText("late")
            closed = true
          },
      )
      assertTrue(closed)
      assertFalse("<cacheDir>/sentry tree must be deleted", sentryDir.exists())
      assertTrue("Unrelated cache files must stay untouched", unrelatedFile.exists())

      // Also verify with real Sentry SDK init/close that nothing re-creates <cacheDir>/sentry.
      java.io.File(sentryDir, "nested").mkdirs()
      java.io.File(sentryDir, "nested/queued.envelope").writeText("pending")
      java.io.File(sentryDir, "root.txt").writeText("marker")
      io.sentry.Sentry.init { opts ->
        AppInfo.configureSentryOptions(
            options = opts,
            dsn = "https://public@127.0.0.1:1/0",
            appVersion = "0.1.41",
            appCacheDir = cacheDir,
        )
      }
      assertTrue(io.sentry.Sentry.isEnabled())
      assertTrue(sentryDir.exists())

      AppInfo.disableCrashReporting(cacheDir)
      assertFalse(io.sentry.Sentry.isEnabled())
      assertFalse(
          "<cacheDir>/sentry must not exist after disableCrashReporting", sentryDir.exists())

      io.sentry.Sentry.captureException(RuntimeException("after switch-off"))
      assertFalse(
          "Capture after disableCrashReporting must not recreate <cacheDir>/sentry",
          sentryDir.exists(),
      )
    } finally {
      io.sentry.Sentry.close()
      cacheDir.deleteRecursively()
    }
  }

  @Test
  public fun `disableCrashReporting sets shutdownTimeoutMillis to zero before closing and clearing cache`() {
    val cacheDir =
        java.nio.file.Files.createTempDirectory("vitruvian-remote-sentry-timeout").toFile()
    try {
      val sentryDir = AppInfo.sentryCacheDir(cacheDir)
      java.io.File(sentryDir, "outbox").apply { mkdirs() }
      val queued = java.io.File(sentryDir, "outbox/queued.envelope").apply { writeText("queued") }
      val steps = mutableListOf<String>()
      val recordingOptions =
          object : io.sentry.SentryOptions() {
            override fun setShutdownTimeoutMillis(shutdownTimeoutMillis: Long) {
              super.setShutdownTimeoutMillis(shutdownTimeoutMillis)
              steps += "setTimeout:$shutdownTimeoutMillis"
            }
          }
      assertTrue(recordingOptions.shutdownTimeoutMillis > 0L)

      AppInfo.disableCrashReporting(
          appCacheDir = cacheDir,
          options = recordingOptions,
          closeSentry = {
            assertEquals(0L, recordingOptions.shutdownTimeoutMillis)
            assertTrue(sentryDir.exists())
            steps += "close"
          },
          deleteCache = { dir ->
            steps += "deleteCache"
            AppInfo.clearSentryCache(dir)
          },
      )

      assertEquals(listOf("setTimeout:0", "close", "deleteCache"), steps)
      assertEquals(0L, recordingOptions.shutdownTimeoutMillis)
      assertFalse(queued.exists())
      assertFalse(sentryDir.exists())

      // Also verify default options wiring against a real initialized hub.
      java.io.File(sentryDir, "outbox").apply { mkdirs() }
      java.io.File(sentryDir, "outbox/queued.envelope").writeText("queued")
      io.sentry.Sentry.init { opts ->
        AppInfo.configureSentryOptions(
            options = opts,
            dsn = "https://public@127.0.0.1:1/0",
            appVersion = "0.1.41",
            appCacheDir = cacheDir,
        )
      }
      val liveOptions = io.sentry.Sentry.getCurrentHub().options
      assertEquals(2000L, liveOptions.shutdownTimeoutMillis)

      AppInfo.disableCrashReporting(cacheDir)

      assertEquals(0L, liveOptions.shutdownTimeoutMillis)
      assertFalse(io.sentry.Sentry.isEnabled())
      assertFalse(sentryDir.exists())
    } finally {
      io.sentry.Sentry.close()
      cacheDir.deleteRecursively()
    }
  }

  @Test
  fun themeModeMigrationAndDarkResolution() {
    // New installs default to System; existing darkTheme booleans migrate once to Dark/Light.
    assertEquals(
        ThemeMode.System, Derive.migrateThemeMode(storedMode = null, legacyDarkTheme = null))
    assertEquals(ThemeMode.Dark, Derive.migrateThemeMode(storedMode = null, legacyDarkTheme = true))
    assertEquals(
        ThemeMode.Light, Derive.migrateThemeMode(storedMode = null, legacyDarkTheme = false))
    assertEquals(
        ThemeMode.Light, Derive.migrateThemeMode(storedMode = "Light", legacyDarkTheme = true))
    assertEquals(
        ThemeMode.Dark, Derive.migrateThemeMode(storedMode = "Dark", legacyDarkTheme = false))
    assertEquals(
        ThemeMode.System, Derive.migrateThemeMode(storedMode = "System", legacyDarkTheme = true))
    assertEquals(
        ThemeMode.System, Derive.migrateThemeMode(storedMode = "unknown", legacyDarkTheme = true))

    assertTrue(Derive.isDarkTheme(ThemeMode.System, systemDark = true))
    assertFalse(Derive.isDarkTheme(ThemeMode.System, systemDark = false))
    assertFalse(Derive.isDarkTheme(ThemeMode.Light, systemDark = true))
    assertFalse(Derive.isDarkTheme(ThemeMode.Light, systemDark = false))
    assertTrue(Derive.isDarkTheme(ThemeMode.Dark, systemDark = true))
    assertTrue(Derive.isDarkTheme(ThemeMode.Dark, systemDark = false))
  }

  @Test
  fun remoteBluetoothBannerMatchesCauseAndActions() {
    // Connected HID link needs no banner regardless of flags.
    assertNull(
        Derive.remoteBluetoothBanner(
            connected = true,
            hostName = "Studio Mac",
            hasAdapter = true,
            permissionGranted = true,
            askedBefore = true,
            shouldShowRationale = false,
            bluetoothEnabled = true,
            hasPairedComputer = true,
        ))

    // API 26-27 (HID unsupported) reports the unsupported notice with no action button.
    val unsupported =
        Derive.remoteBluetoothBanner(
            connected = false,
            hostName = "Studio Mac",
            hasAdapter = true,
            permissionGranted = true,
            askedBefore = false,
            shouldShowRationale = false,
            bluetoothEnabled = true,
            hasPairedComputer = false,
            hidSupported = false,
        )!!
    assertEquals(Derive.BluetoothBannerCause.Unsupported, unsupported.cause)
    assertEquals(Derive.BLUETOOTH_UNSUPPORTED_MESSAGE, unsupported.message)
    assertNull(unsupported.action)
    assertNull(unsupported.actionLabel)

    // Device without Bluetooth adapter suppresses the banner when HID is supported.
    assertNull(
        Derive.remoteBluetoothBanner(
            connected = false,
            hostName = "Studio Mac",
            hasAdapter = false,
            permissionGranted = false,
            askedBefore = false,
            shouldShowRationale = false,
            bluetoothEnabled = false,
            hasPairedComputer = false,
        ))

    // First-time missing permission leads with rationale line + Allow Bluetooth.
    val initialPrompt =
        Derive.remoteBluetoothBanner(
            connected = false,
            hostName = "Studio Mac",
            hasAdapter = true,
            permissionGranted = false,
            askedBefore = false,
            shouldShowRationale = false,
            bluetoothEnabled = true,
            hasPairedComputer = false,
        )!!
    assertEquals(Derive.BluetoothBannerCause.PermissionNeeded, initialPrompt.cause)
    assertEquals(Derive.BluetoothBannerAction.AllowPermission, initialPrompt.action)
    assertEquals("Allow Bluetooth", initialPrompt.actionLabel)
    assertEquals(Derive.BLUETOOTH_RATIONALE_LINE, initialPrompt.message)

    // Declined once (rationale shown): names declined cause and keeps Allow Bluetooth.
    val declinedOnce =
        Derive.remoteBluetoothBanner(
            connected = false,
            hostName = "Studio Mac",
            hasAdapter = true,
            permissionGranted = false,
            askedBefore = true,
            shouldShowRationale = true,
            bluetoothEnabled = true,
            hasPairedComputer = false,
        )!!
    assertEquals(Derive.BluetoothBannerCause.PermissionDeclined, declinedOnce.cause)
    assertEquals(Derive.BluetoothBannerAction.AllowPermission, declinedOnce.action)
    assertEquals("Allow Bluetooth", declinedOnce.actionLabel)
    assertEquals("Bluetooth permission declined.", declinedOnce.message)
    assertEquals(Derive.BLUETOOTH_RATIONALE_LINE, declinedOnce.rationale)

    // Permanently denied: switches button to Open app settings.
    val permanentlyDenied =
        Derive.remoteBluetoothBanner(
            connected = false,
            hostName = "Studio Mac",
            hasAdapter = true,
            permissionGranted = false,
            askedBefore = true,
            shouldShowRationale = false,
            bluetoothEnabled = true,
            hasPairedComputer = false,
        )!!
    assertEquals(Derive.BluetoothBannerCause.PermissionPermanentlyDenied, permanentlyDenied.cause)
    assertEquals(Derive.BluetoothBannerAction.OpenAppSettings, permanentlyDenied.action)
    assertEquals("Open app settings", permanentlyDenied.actionLabel)

    // Permission granted but radio off -> Turn on Bluetooth.
    val btOff =
        Derive.remoteBluetoothBanner(
            connected = false,
            hostName = "Studio Mac",
            hasAdapter = true,
            permissionGranted = true,
            askedBefore = true,
            shouldShowRationale = false,
            bluetoothEnabled = false,
            hasPairedComputer = false,
        )!!
    assertEquals(Derive.BluetoothBannerCause.BluetoothOff, btOff.cause)
    assertEquals(Derive.BluetoothBannerAction.TurnOnBluetooth, btOff.action)
    assertEquals("Turn on Bluetooth", btOff.actionLabel)

    // Radio on, Mac unpaired -> Open Bluetooth settings + two pairing steps.
    val unpaired =
        Derive.remoteBluetoothBanner(
            connected = false,
            hostName = "Studio Mac",
            hasAdapter = true,
            permissionGranted = true,
            askedBefore = true,
            shouldShowRationale = false,
            bluetoothEnabled = true,
            hasPairedComputer = false,
        )!!
    assertEquals(Derive.BluetoothBannerCause.MacNotPaired, unpaired.cause)
    assertEquals(Derive.BluetoothBannerAction.OpenBluetoothSettings, unpaired.action)
    assertEquals("Open Bluetooth settings", unpaired.actionLabel)
    assertTrue(unpaired.message.contains("Studio Mac"))
    assertEquals(2, unpaired.steps.size)

    // Paired but currently down -> Reconnect.
    val reconnect =
        Derive.remoteBluetoothBanner(
            connected = false,
            hostName = "Studio Mac",
            hasAdapter = true,
            permissionGranted = true,
            askedBefore = true,
            shouldShowRationale = false,
            bluetoothEnabled = true,
            hasPairedComputer = true,
        )!!
    assertEquals(Derive.BluetoothBannerCause.LinkDown, reconnect.cause)
    assertEquals(Derive.BluetoothBannerAction.Reconnect, reconnect.action)
    assertEquals("Reconnect", reconnect.actionLabel)

    val waiting =
        Derive.remoteBluetoothBanner(
            connected = false,
            waitingForHost = true,
            hostName = "Studio Mac",
            hasAdapter = true,
            permissionGranted = true,
            askedBefore = true,
            shouldShowRationale = false,
            bluetoothEnabled = true,
            hasPairedComputer = true,
        )!!
    assertEquals(Derive.BluetoothBannerCause.WaitingForHost, waiting.cause)
    assertEquals(Derive.BluetoothBannerAction.Reconnect, waiting.action)
    assertTrue(waiting.message.contains("connecting to Studio Mac"))
  }

  @Test
  fun bluetoothBannerCausesMapToExpectedButtonsAndDispatchActions() {
    val expectedByCause =
        mapOf(
            Derive.BluetoothBannerCause.Unsupported to null,
            Derive.BluetoothBannerCause.PermissionNeeded to
                Derive.BluetoothBannerButton(
                    "Allow Bluetooth", Derive.BluetoothBannerAction.AllowPermission),
            Derive.BluetoothBannerCause.PermissionDeclined to
                Derive.BluetoothBannerButton(
                    "Allow Bluetooth", Derive.BluetoothBannerAction.AllowPermission),
            Derive.BluetoothBannerCause.PermissionPermanentlyDenied to
                Derive.BluetoothBannerButton(
                    "Open app settings", Derive.BluetoothBannerAction.OpenAppSettings),
            Derive.BluetoothBannerCause.BluetoothOff to
                Derive.BluetoothBannerButton(
                    "Turn on Bluetooth", Derive.BluetoothBannerAction.TurnOnBluetooth),
            Derive.BluetoothBannerCause.MacNotPaired to
                Derive.BluetoothBannerButton(
                    "Open Bluetooth settings", Derive.BluetoothBannerAction.OpenBluetoothSettings),
            Derive.BluetoothBannerCause.WaitingForHost to
                Derive.BluetoothBannerButton("Reconnect", Derive.BluetoothBannerAction.Reconnect),
            Derive.BluetoothBannerCause.LinkDown to
                Derive.BluetoothBannerButton("Reconnect", Derive.BluetoothBannerAction.Reconnect),
        )
    assertEquals(Derive.BluetoothBannerCause.entries.toSet(), expectedByCause.keys)
    for (cause in Derive.BluetoothBannerCause.entries) {
      assertEquals(
          "Unexpected mapping for $cause",
          expectedByCause[cause],
          Derive.bluetoothBannerButton(cause))
    }

    val bt = FakeBluetoothControl(permissionGranted = false, asked = false)
    var reconnectCount = 0
    val coordinator =
        BluetoothReadinessCoordinator(
            persistence = Persistence(FakePrefsStore()),
            bluetooth = bt,
            onReconnect = { reconnectCount++ },
        )
    coordinator.performBannerAction(Derive.BluetoothBannerAction.AllowPermission)
    assertEquals(1, bt.ensurePermissionCalls)
    coordinator.performBannerAction(Derive.BluetoothBannerAction.OpenAppSettings)
    assertEquals(1, bt.openAppSettingsCalls)
    coordinator.performBannerAction(Derive.BluetoothBannerAction.TurnOnBluetooth)
    assertEquals(1, bt.enableBluetoothCalls)
    coordinator.performBannerAction(Derive.BluetoothBannerAction.OpenBluetoothSettings)
    assertEquals(1, bt.openBluetoothSettingsCalls)

    coordinator.performBannerAction(Derive.BluetoothBannerAction.Reconnect)
    assertEquals(1, reconnectCount)

    // Also prove pure dispatch invokes only the requested callback.
    for (action in Derive.BluetoothBannerAction.entries) {
      val hits = mutableListOf<Derive.BluetoothBannerAction>()
      Derive.dispatchBluetoothBannerAction(
          action = action,
          onAllowPermission = { hits += Derive.BluetoothBannerAction.AllowPermission },
          onOpenAppSettings = { hits += Derive.BluetoothBannerAction.OpenAppSettings },
          onTurnOnBluetooth = { hits += Derive.BluetoothBannerAction.TurnOnBluetooth },
          onOpenBluetoothSettings = { hits += Derive.BluetoothBannerAction.OpenBluetoothSettings },
          onReconnect = { hits += Derive.BluetoothBannerAction.Reconnect },
      )
      assertEquals(listOf(action), hits)
    }
  }

  @Test
  fun unsupportedAndroidSdkShowsNoActionBannerAndCaption() {
    assertFalse(Derive.isBluetoothHidSupported(26))
    assertFalse(Derive.isBluetoothHidSupported(27))
    assertTrue(Derive.isBluetoothHidSupported(28))
    assertTrue(Derive.isBluetoothHidSupported(35))

    assertEquals(
        Derive.BLUETOOTH_UNSUPPORTED_MESSAGE,
        Derive.pointerCaption(
            connected = false,
            hostName = "Studio Mac",
            pointerHint = "drag to move",
            hasAdapter = true,
            permissionGranted = true,
            bluetoothEnabled = true,
            hasPairedComputer = true,
            hidSupported = false,
        ))

    val bt = FakeBluetoothControl(hidSupported = false, permissionGranted = false, asked = false)
    val nav = ScreenNavigationTracker()
    val coordinator =
        BluetoothReadinessCoordinator(persistence = Persistence(FakePrefsStore()), bluetooth = bt)
    nav.go(Screen.Remote)
    coordinator.onRemoteScreenVisited()

    assertEquals(0, bt.ensurePermissionCalls)
    val banner = coordinator.banner(connected = false, hostName = "Studio Mac")
    assertNotNull(banner)
    assertEquals(Derive.BluetoothBannerCause.Unsupported, banner!!.cause)
    assertEquals(Derive.BLUETOOTH_UNSUPPORTED_MESSAGE, banner.message)
    assertNull(banner.action)
    assertNull(banner.actionLabel)
    assertEquals(
        Derive.BLUETOOTH_UNSUPPORTED_MESSAGE,
        coordinator.pointerCaption(
            connected = false,
            hostName = "Studio Mac",
            pointerHint = "drag to move",
        ),
    )
  }

  @Test
  fun bluetoothPromptNeverAutoFiresOnRemoteVisit() {
    val bt = FakeBluetoothControl(permissionGranted = false, asked = false)
    val nav = ScreenNavigationTracker()
    val coordinator =
        BluetoothReadinessCoordinator(persistence = Persistence(FakePrefsStore()), bluetooth = bt)

    // Cold launch / saved-state restore / explicit user navigation to Remote must all keep 0
    // auto-prompts so the user can read the explanation before deciding.
    nav.go(Screen.Remote)
    coordinator.onRemoteScreenVisited()
    assertEquals(0, bt.ensurePermissionCalls)
    val initialBanner = coordinator.banner(connected = false, hostName = "Studio Mac")
    assertNotNull(initialBanner)
    assertEquals(Derive.BluetoothBannerCause.PermissionNeeded, initialBanner!!.cause)
    assertEquals(Derive.BLUETOOTH_RATIONALE_LINE, initialBanner.message)
    assertEquals("Allow Bluetooth", initialBanner.actionLabel)

    nav.restoreScreen("Remote")
    coordinator.onRemoteScreenVisited()
    assertEquals(0, bt.ensurePermissionCalls)

    nav.go(Screen.Home)
    nav.go(Screen.Remote)
    coordinator.onRemoteScreenVisited()
    assertEquals(0, bt.ensurePermissionCalls)

    // Only tapping the banner's Allow Bluetooth action requests permission.
    coordinator.performBannerAction(initialBanner.action!!)
    assertEquals(1, bt.ensurePermissionCalls)
  }

  @Test
  fun restoredScreenAndInitialIntentPrecedence() {
    assertEquals(Screen.Remote, Derive.restoredScreen("Remote"))
    assertEquals(Screen.Hosts, Derive.restoredScreen(" hosts "))
    assertNull(Derive.restoredScreen(null))
    assertNull(Derive.restoredScreen("  "))
    assertNull(Derive.restoredScreen("NotAScreen"))

    val nav = ScreenNavigationTracker()
    nav.restoreScreen("Console")
    assertEquals(Screen.Console, nav.screen)
    assertNull(nav.restoreScreen("invalid"))
    assertEquals(Screen.Console, nav.screen)

    // Manifest handles uiMode live so system dark/light switches don't restart MainActivity,
    // and declares singleTop so links arriving while running go through onNewIntent.
    val manifest = readRunfile("apps/mobile/vitruvian-remote/src/main/AndroidManifest.xml")
    val mainActivityStart = manifest.indexOf("android:name=\".MainActivity\"")
    assertTrue("MainActivity declaration not found", mainActivityStart >= 0)
    val tagStart = manifest.lastIndexOf("<activity", mainActivityStart)
    val tagEnd = manifest.indexOf(">", mainActivityStart)
    val activityTag = manifest.substring(tagStart, tagEnd + 1)
    val configMatch = Regex("""android:configChanges="([^"]+)"""").find(activityTag)
    assertNotNull("android:configChanges missing on MainActivity", configMatch)
    val flags = configMatch!!.groupValues[1].split('|').toSet()
    assertTrue("Expected uiMode in MainActivity configChanges: $flags", "uiMode" in flags)
    assertTrue(
        "Expected singleTop launchMode on MainActivity",
        activityTag.contains("""android:launchMode="singleTop""""),
    )
  }

  @Test
  fun intentDecisionCoversLaunchRecreationProcessDeathAndNewIntent() {
    val remoteUri = "vitruvian-remote://remote"
    val moduleUri = "vitruvian-remote://apps/claude"
    val pairUri =
        "vitruvian-remote://pair?code=482917&name=atlas&url=http%3A%2F%2F100.64.0.12%3A7411"

    // 1. Fresh launch with a link (screen, module, pairing QR, or Quick Settings tile).
    val remoteKey = Derive.intentKey(dataUri = remoteUri, actionExtra = null)
    assertNotNull(remoteKey)
    assertEquals(
        Derive.IntentDecision.Handle,
        Derive.intentDecision(
            intentKey = remoteKey,
            savedHandledKey = null,
            hasActionableData = Derive.hasActionableIntentData(remoteUri, null),
        ),
    )

    val moduleKey = Derive.intentKey(dataUri = moduleUri, actionExtra = null, createdAt = 10L)
    assertEquals(
        Derive.IntentDecision.Handle,
        Derive.intentDecision(
            intentKey = moduleKey,
            savedHandledKey = null,
            hasActionableData = Derive.hasActionableIntentData(moduleUri, null),
        ),
    )

    val pairKey = Derive.intentKey(dataUri = pairUri, actionExtra = null)
    assertEquals(
        Derive.IntentDecision.Handle,
        Derive.intentDecision(
            intentKey = pairKey,
            savedHandledKey = null,
            hasActionableData = Derive.hasActionableIntentData(pairUri, null),
        ),
    )

    val tileKey1 =
        Derive.intentKey(
            dataUri = null,
            actionExtra = Derive.ACTION_DISPLAY_SLEEP,
            createdAt = 100L,
        )
    assertEquals(
        Derive.IntentDecision.Handle,
        Derive.intentDecision(
            intentKey = tileKey1,
            savedHandledKey = null,
            hasActionableData = Derive.hasActionableIntentData(null, Derive.ACTION_DISPLAY_SLEEP),
        ),
    )

    // 2. Rotation or theme recreation with the same link already handled: restore, do not replay.
    assertEquals(
        Derive.IntentDecision.Restore,
        Derive.intentDecision(
            intentKey = pairKey,
            savedHandledKey = pairKey,
            hasActionableData = Derive.hasActionableIntentData(pairUri, null),
        ),
    )
    assertEquals(
        Derive.IntentDecision.Restore,
        Derive.intentDecision(
            intentKey = tileKey1,
            savedHandledKey = tileKey1,
            hasActionableData = Derive.hasActionableIntentData(null, Derive.ACTION_DISPLAY_SLEEP),
        ),
    )

    // 3. Recreation after process death with the same original link re-delivered by Android.
    val nav = ScreenNavigationTracker()
    // Initial launch handled `pairUri`, then user navigated to Console before process death.
    var savedHandledKey: String? = pairKey
    nav.go(Screen.Console)
    val savedScreen = nav.screen.name
    // Process dies and restarts with savedInstanceState + original task intent.
    val decisionAfterDeath =
        Derive.intentDecision(
            intentKey = pairKey,
            savedHandledKey = savedHandledKey,
            hasActionableData = Derive.hasActionableIntentData(pairUri, null),
        )
    assertEquals(Derive.IntentDecision.Restore, decisionAfterDeath)
    nav.restoreScreen(savedScreen)
    assertEquals(Screen.Console, nav.screen)

    // 4. Recreation with a new link (or a second tile tap with a new creation-time extra).
    val consoleUri = "vitruvian-remote://console"
    val consoleKey = Derive.intentKey(dataUri = consoleUri, actionExtra = null, createdAt = 250L)
    assertEquals(
        Derive.IntentDecision.Handle,
        Derive.intentDecision(
            intentKey = consoleKey,
            savedHandledKey = savedHandledKey,
            hasActionableData = Derive.hasActionableIntentData(consoleUri, null),
        ),
    )
    assertEquals(
        Derive.IntentDecision.Handle,
        Derive.intentDecision(
            intentKey = consoleKey,
            savedHandledKey = null,
            hasActionableData = Derive.hasActionableIntentData(consoleUri, null),
        ),
    )
    val tileKey2 =
        Derive.intentKey(
            dataUri = null,
            actionExtra = Derive.ACTION_DISPLAY_SLEEP,
            createdAt = 200L,
        )
    assertEquals(
        Derive.IntentDecision.Handle,
        Derive.intentDecision(
            intentKey = tileKey2,
            savedHandledKey = tileKey1,
            hasActionableData = Derive.hasActionableIntentData(null, Derive.ACTION_DISPLAY_SLEEP),
        ),
    )

    // 4b. onNewIntent with a link already handled (second notification for the same screen,
    // same pairing QR scanned again): a new intent is always a fresh tap, so it is handled.
    assertEquals(
        Derive.IntentDecision.Handle,
        Derive.intentDecision(
            intentKey = pairKey,
            savedHandledKey = pairKey,
            hasActionableData = Derive.hasActionableIntentData(pairUri, null),
            isNewIntent = true,
        ),
    )
    // ...but a new intent with nothing actionable still does nothing.
    assertEquals(
        Derive.IntentDecision.Restore,
        Derive.intentDecision(
            intentKey = null,
            savedHandledKey = pairKey,
            hasActionableData = false,
            isNewIntent = true,
        ),
    )

    // 5. Plain launch with no data (or unrecognized URI/action) restores instead of handling.
    val emptyKey = Derive.intentKey(dataUri = null, actionExtra = null, createdAt = null)
    assertNull(emptyKey)
    assertFalse(Derive.hasActionableIntentData(dataUri = null, actionExtra = null))
    assertEquals(
        Derive.IntentDecision.Restore,
        Derive.intentDecision(
            intentKey = emptyKey,
            savedHandledKey = null,
            hasActionableData = Derive.hasActionableIntentData(null, null),
        ),
    )
    val unknownUri = "https://example.com/not-ours"
    assertFalse(Derive.hasActionableIntentData(dataUri = unknownUri, actionExtra = "unknown"))
    assertEquals(
        Derive.IntentDecision.Restore,
        Derive.intentDecision(
            intentKey = Derive.intentKey(dataUri = unknownUri, actionExtra = "unknown"),
            savedHandledKey = null,
            hasActionableData = Derive.hasActionableIntentData(unknownUri, "unknown"),
        ),
    )

    // 6. onNewIntent with a link while running handles the new link and prevents replay on later
    // recreation.
    savedHandledKey = remoteKey
    val macUri = "vitruvian-remote://mac"
    val macKey = Derive.intentKey(dataUri = macUri, actionExtra = null, createdAt = 300L)
    assertEquals(
        Derive.IntentDecision.Handle,
        Derive.intentDecision(
            intentKey = macKey,
            savedHandledKey = savedHandledKey,
            hasActionableData = Derive.hasActionableIntentData(macUri, null),
        ),
    )
    savedHandledKey = macKey
    assertEquals(
        Derive.IntentDecision.Restore,
        Derive.intentDecision(
            intentKey = macKey,
            savedHandledKey = savedHandledKey,
            hasActionableData = Derive.hasActionableIntentData(macUri, null),
        ),
    )

    // Lifecycle wiring assertions on MainActivity.kt.
    val main =
        stripKotlinComments(
            readRunfile(
                "apps/mobile/vitruvian-remote/src/main/kotlin/dev/vitruvian/remote/MainActivity.kt"))
    val onCreateBody = extractKotlinBlock(main, "override fun onCreate(")
    val onSaveBody = extractKotlinBlock(main, "override fun onSaveInstanceState(")
    val onNewIntentBody = extractKotlinBlock(main, "override fun onNewIntent(")
    val routeIntentBody = extractKotlinBlock(main, "private fun routeIntent(")
    val handleIntentBody = extractKotlinBlock(main, "private fun handleIntent(")

    assertTrue(onCreateBody.contains("KEY_HANDLED_INTENT"))
    assertTrue(onCreateBody.contains("routeIntent("))
    assertTrue(onSaveBody.contains("KEY_HANDLED_INTENT"))
    assertTrue(onNewIntentBody.contains("setIntent(intent)"))
    assertTrue(onNewIntentBody.contains("routeIntent("))
    assertTrue(routeIntentBody.contains("Derive.intentKey("))
    assertTrue(routeIntentBody.contains("Derive.hasActionableIntentData("))
    assertTrue(routeIntentBody.contains("Derive.intentDecision("))
    assertTrue(routeIntentBody.contains("EXTRA_CREATED_AT"))
    assertFalse(handleIntentBody.contains("removeExtra("))
  }

  @Test
  fun persistenceOneTimeThemeMigrationAndIdempotence() {
    // 1. Legacy darkTheme=true migrates to Dark and clears the old key.
    val darkPrefs = FakePrefsStore().apply { edit().putBoolean("darkTheme", true).apply() }
    val darkPersistence = Persistence(darkPrefs)
    assertEquals(ThemeMode.Dark, darkPersistence.themeMode)
    assertFalse(
        "Legacy darkTheme key should be deleted after migration", darkPrefs.contains("darkTheme"))
    assertEquals("Dark", darkPrefs.getString("themeMode", null))

    // 2. Legacy darkTheme=false migrates to Light and clears the old key.
    val lightPrefs = FakePrefsStore().apply { edit().putBoolean("darkTheme", false).apply() }
    val lightPersistence = Persistence(lightPrefs)
    assertEquals(ThemeMode.Light, lightPersistence.themeMode)
    assertFalse(
        "Legacy darkTheme key should be deleted after migration", lightPrefs.contains("darkTheme"))
    assertEquals("Light", lightPrefs.getString("themeMode", null))

    // 3. Fresh install with nothing stored defaults to System without writing themeMode.
    val emptyPrefs = FakePrefsStore()
    val emptyPersistence = Persistence(emptyPrefs)
    assertEquals(ThemeMode.System, emptyPersistence.themeMode)
    assertFalse(emptyPrefs.contains("themeMode"))

    // 4. Subsequent startup does not re-migrate or override user's updated ThemeMode.
    darkPersistence.themeMode = ThemeMode.System
    darkPrefs.edit().putBoolean("darkTheme", true).apply()
    val secondRun = Persistence(darkPrefs)
    assertEquals(ThemeMode.System, secondRun.themeMode)
    assertEquals("System", darkPrefs.getString("themeMode", null))
  }

  @Test
  fun pointerCaptionReflectsBluetoothReadiness() {
    assertEquals(
        "drag to move",
        Derive.pointerCaption(
            connected = true,
            hostName = "Studio Mac",
            pointerHint = "drag to move",
            hasAdapter = true,
            permissionGranted = true,
            bluetoothEnabled = true,
            hasPairedComputer = true,
        ))
    assertEquals(
        "allow Bluetooth to control Studio Mac",
        Derive.pointerCaption(
            connected = false,
            hostName = "Studio Mac",
            pointerHint = "drag to move",
            hasAdapter = true,
            permissionGranted = false,
            bluetoothEnabled = true,
            hasPairedComputer = false,
        ))
    assertEquals(
        "turn on Bluetooth to connect",
        Derive.pointerCaption(
            connected = false,
            hostName = "Studio Mac",
            pointerHint = "drag to move",
            hasAdapter = true,
            permissionGranted = true,
            bluetoothEnabled = false,
            hasPairedComputer = false,
        ))
    assertEquals(
        "pair Studio Mac in Bluetooth settings",
        Derive.pointerCaption(
            connected = false,
            hostName = "Studio Mac",
            pointerHint = "drag to move",
            hasAdapter = true,
            permissionGranted = true,
            bluetoothEnabled = true,
            hasPairedComputer = false,
        ))
    assertEquals(
        "connecting to Studio Mac…",
        Derive.pointerCaption(
            connected = false,
            waitingForHost = true,
            hostName = "Studio Mac",
            pointerHint = "drag to move",
            hasAdapter = true,
            permissionGranted = true,
            bluetoothEnabled = true,
            hasPairedComputer = true,
        ))
  }

  @Test
  fun `MainActivity never asks for BLUETOOTH_CONNECT at launch`() {
    val main =
        stripKotlinComments(
            readRunfile(
                "apps/mobile/vitruvian-remote/src/main/kotlin/dev/vitruvian/remote/MainActivity.kt"))
    val remoteState =
        stripKotlinComments(
            readRunfile(
                "apps/mobile/vitruvian-remote/src/main/kotlin/dev/vitruvian/remote/state/RemoteState.kt"))
    val models =
        stripKotlinComments(
            readRunfile(
                "apps/mobile/vitruvian-remote/src/main/kotlin/dev/vitruvian/remote/state/Models.kt"))
    val launches = Regex("""\brequestBluetooth\.launch\(""").findAll(main).count()
    assertEquals(
        "requestBluetooth.launch may only be called from ensureBluetoothPermission",
        1,
        launches,
    )
    assertTrue(
        extractKotlinBlock(main, "private fun ensureBluetoothPermission(")
            .contains("requestBluetooth.launch(Manifest.permission.BLUETOOTH_CONNECT)"),
    )
    val rawOnCreate = extractKotlinBlock(main, "override fun onCreate(")
    assertTrue(
        "expected ActivityBluetoothControl port wiring in MainActivity.onCreate",
        rawOnCreate.contains("ensurePermission = ::ensureBluetoothPermission"),
    )
    val launchAndForegroundBodies =
        mapOf(
            "MainActivity.onCreate" to
                rawOnCreate.replaceFirst("ensurePermission = ::ensureBluetoothPermission", ""),
            "MainActivity.onStart" to extractKotlinBlock(main, "override fun onStart("),
            "MainActivity.onResume" to extractKotlinBlock(main, "override fun onResume("),
            "MainActivity.onWindowFocusChanged" to
                extractKotlinBlock(main, "override fun onWindowFocusChanged("),
            "MainActivity.handleIntent" to extractKotlinBlock(main, "private fun handleIntent("),
            "RemoteState.restoreScreen" to
                extractKotlinBlock(remoteState, "public fun restoreScreen("),
            "RemoteState.onForeground" to
                extractKotlinBlock(remoteState, "public fun onForeground("),
            "RemoteState.onRemoteScreenVisited" to
                extractKotlinBlock(remoteState, "public fun onRemoteScreenVisited("),
            "BluetoothReadinessCoordinator.onRemoteScreenVisited" to
                extractKotlinBlock(models, "public fun onRemoteScreenVisited("),
        )
    val forbiddenSymbols =
        listOf(
            "ensureBluetoothPermission",
            "requestBluetooth",
            "requestBluetoothPermission",
            "requestPermission",
        )
    val violations = mutableListOf<String>()
    for ((pathName, body) in launchAndForegroundBodies) {
      assertTrue("$pathName body should not be blank", body.isNotBlank())
      for (symbol in forbiddenSymbols) {
        if (Regex("""\b${Regex.escape(symbol)}\b""").containsMatchIn(body)) {
          violations += "$pathName references `$symbol`"
        }
      }
    }
    assertTrue(
        "Launch/foreground paths must never ask for BLUETOOTH_CONNECT:\n" +
            violations.joinToString("\n"),
        violations.isEmpty(),
    )
  }

  @Test
  public fun `Shell and HostsScreen wire About and PhoneBridge outside tabs and rail with back handling`() {
    val shell =
        readRunfile(
            "apps/mobile/vitruvian-remote/src/main/kotlin/dev/vitruvian/remote/shell/Shell.kt")
    val navItemsBlock =
        shell.substringAfter("private fun navItems(").substringBefore("private fun SettingsButton(")
    assertTrue("navItems must use RAIL_SCREENS", navItemsBlock.contains("RAIL_SCREENS.map"))
    val railScreensBlock =
        shell.substringAfter("private val RAIL_SCREENS").substringBefore("private val ICONS")
    assertFalse("RAIL_SCREENS must exclude Screen.About", railScreensBlock.contains("Screen.About"))
    assertFalse(
        "RAIL_SCREENS must exclude Screen.PhoneBridge",
        railScreensBlock.contains("Screen.PhoneBridge"),
    )
    assertTrue(
        "TopBar must pass onBack from state.canGoBack",
        shell.contains("val showBack = state.canGoBack") &&
            shell.contains("onBack = if (showBack) ({ state.navigateBack() }) else null"),
    )

    val remoteApp =
        readRunfile(
            "apps/mobile/vitruvian-remote/src/main/kotlin/dev/vitruvian/remote/RemoteApp.kt")
    assertTrue(
        "RemoteApp must handle system Back via state.canGoBack",
        remoteApp.contains("BackHandler(enabled = state.canGoBack) { state.navigateBack() }"),
    )

    val hosts =
        readRunfile(
            "apps/mobile/vitruvian-remote/src/main/kotlin/dev/vitruvian/remote/screens/HostsScreen.kt")
    assertTrue(hosts.contains("AboutSection(state)"))
    assertTrue(hosts.contains("\"About Vitruvian Remote\""))
    assertTrue(hosts.contains("\"Donate\""))
    assertTrue(hosts.contains("AppInfo.donateURL"))
  }

  @Test
  public fun `F19 secondary navigation stack supports Settings, PhoneBridge, About and back`() {
    val start = Derive.NavState(current = "Home")
    assertFalse(Derive.canGoBack(start, isUnpaired = false))
    assertNull(Derive.popNav(start, isUnpaired = false))

    val onSettings = Derive.navigateToScreen(start, "Hosts", isUnpaired = false)
    assertEquals("Hosts", onSettings.current)
    assertEquals(listOf("Home"), onSettings.backStack)
    assertTrue(Derive.canGoBack(onSettings, isUnpaired = false))

    val onBridge = Derive.navigateToScreen(onSettings, "PhoneBridge", isUnpaired = false)
    assertEquals("PhoneBridge", onBridge.current)
    assertEquals(listOf("Home", "Hosts"), onBridge.backStack)

    val backToSettings = Derive.popNav(onBridge, isUnpaired = false)!!
    assertEquals("Hosts", backToSettings.current)
    assertEquals(listOf("Home"), backToSettings.backStack)

    val onAbout = Derive.navigateToAboutSubPage(backToSettings, "Privacy", isUnpaired = false)
    assertEquals("About", onAbout.current)
    assertEquals("Privacy", onAbout.aboutSubPage)
    assertEquals(listOf("Home", "Hosts"), onAbout.backStack)

    val backToAboutMain = Derive.popNav(onAbout, isUnpaired = false)!!
    assertEquals("About", backToAboutMain.current)
    assertNull(backToAboutMain.aboutSubPage)

    val backToSettingsFromAbout = Derive.popNav(backToAboutMain, isUnpaired = false)!!
    assertEquals("Hosts", backToSettingsFromAbout.current)

    val backToHome = Derive.popNav(backToSettingsFromAbout, isUnpaired = false)!!
    assertEquals("Home", backToHome.current)
    assertTrue(backToHome.backStack.isEmpty())
    assertFalse(Derive.canGoBack(backToHome, isUnpaired = false))

    // Unpaired mode uses the same navigation rules: secondary screens push prior screens and step
    // back.
    val unpairedHosts = Derive.NavState(current = "Hosts")
    assertTrue(Derive.canGoBack(unpairedHosts, isUnpaired = true))
    assertEquals("Home", Derive.popNav(unpairedHosts, isUnpaired = true)?.current)
    val unpairedBridge = Derive.navigateToScreen(unpairedHosts, "PhoneBridge", isUnpaired = true)
    assertTrue(Derive.canGoBack(unpairedBridge, isUnpaired = true))
    assertEquals("Hosts", Derive.popNav(unpairedBridge, isUnpaired = true)?.current)
  }

  @Test
  public fun `unpaired tabs open their own screen and show UnpairedState only on Mac-backed tabs`() {
    val start = Derive.NavState(current = "Home")
    for (tab in listOf("Home", "Remote", "Mac", "Apps", "Console")) {
      val next = Derive.navigateToScreen(start, tab, isUnpaired = true)
      assertEquals(tab, next.current)
      assertTrue(next.backStack.isEmpty())
    }

    val fromMacToSettings =
        Derive.navigateToScreen(Derive.NavState(current = "Mac"), "Hosts", isUnpaired = true)
    assertEquals("Hosts", fromMacToSettings.current)
    assertEquals(listOf("Mac"), fromMacToSettings.backStack)
    assertEquals("Mac", Derive.popNav(fromMacToSettings, isUnpaired = true)?.current)

    for (screen in listOf(Screen.Home, Screen.Mac, Screen.Apps, Screen.Console)) {
      assertTrue(Derive.showsUnpairedEmptyState(screen, isUnpaired = true))
      assertFalse(Derive.showsUnpairedEmptyState(screen, isUnpaired = false))
    }
    for (screen in listOf(Screen.Remote, Screen.Hosts, Screen.PhoneBridge, Screen.About)) {
      assertFalse(Derive.showsUnpairedEmptyState(screen, isUnpaired = true))
      assertFalse(Derive.showsUnpairedEmptyState(screen, isUnpaired = false))
    }
  }

  @Test
  public fun `F35 phone bridge summary and permission subtitles use plain English without raw tool IDs`() {
    val offSummary =
        Derive.phoneBridgeSummarySubtitle(
            enabled = false,
            linked = false,
            linkStatus = "off",
            problemText = null,
            grantedCount = 0,
            totalCount = 8,
        )
    assertEquals(
        "Off · texts, contacts, call history, location, notifications and screen control",
        offSummary,
    )
    for (capability in AppInfo.phoneBridgeCapabilities) {
      assertTrue(
          "Settings summary missing capability '$capability'",
          offSummary.contains(capability),
      )
      assertTrue(
          "PhoneBridgeScreen summary missing capability '$capability'",
          AppInfo.phoneBridgeScreenSummary.contains(capability),
      )
      assertTrue(
          "Privacy statement missing capability '$capability'",
          AppInfo.privacyTrailingStatements[1].contains(capability),
      )
    }
    assertEquals(
        "On · linked · 5 of 8 permissions granted",
        Derive.phoneBridgeSummarySubtitle(
            enabled = true,
            linked = true,
            linkStatus = "linked",
            problemText = null,
            grantedCount = 5,
            totalCount = 8,
        ),
    )
    assertEquals(
        "On · Phone Bridge is turned off",
        Derive.phoneBridgeSummarySubtitle(
            enabled = true,
            linked = false,
            linkStatus = "not linked",
            problemText = "Phone Bridge is turned off",
            grantedCount = 2,
            totalCount = 8,
        ),
    )

    val ids =
        listOf(
            "read_sms",
            "send_sms",
            "read_contacts",
            "read_call_log",
            "call_phone",
            "location",
            "notification_access",
            "accessibility",
        )
    for (id in ids) {
      val grantedLine = Derive.bridgePermissionSubtitle(id, granted = true)
      val deniedLine = Derive.bridgePermissionSubtitle(id, granted = false)
      assertFalse("$id subtitle leaked raw tool dot: $grantedLine", grantedLine.contains('.'))
      assertTrue(deniedLine.endsWith("· not granted"))
    }
  }

  @Test
  public fun `F20 gallery labels use Show, Hide and Not on this Mac without source tags`() {
    assertEquals("Hide", Derive.galleryActionLabel(shown = true, unavailable = false))
    assertEquals("Hide", Derive.galleryActionLabel(shown = true, unavailable = true))
    assertEquals("Not on this Mac", Derive.galleryActionLabel(shown = false, unavailable = true))
    assertEquals("Show", Derive.galleryActionLabel(shown = false, unavailable = false))

    val appsScreen =
        readRunfile(
            "apps/mobile/vitruvian-remote/src/main/kotlin/dev/vitruvian/remote/screens/AppsScreen.kt")
    val galleryPane =
        appsScreen.substringAfter("fun ColumnScope.GalleryPane(").substringBefore("\n@Composable")
    assertFalse(
        "GalleryPane must not show raw command-name tags",
        galleryPane.contains("Tag(text = entry.source"))
    assertTrue(
        "GalleryPane must use Derive.galleryActionLabel",
        galleryPane.contains("Derive.galleryActionLabel("))
  }

  @Test
  public fun `F21 Mac developer tools stay hidden until reported and errors lead with plain text`() {
    val noDevToolsSpec =
        Derive.macDeveloperTools(
            isDemoMode = false,
            availableTools = setOf("git", "claude"),
            containersAvailable = false,
            vmsAvailable = false,
            k8sAvailable = false,
            prometheusReported = false,
        )
    assertFalse(noDevToolsSpec.anyVisible)
    assertFalse(noDevToolsSpec.showContainers)

    listOf("docker", "podman", "colima").forEach { runtime ->
      val containerOnlySpec =
          Derive.macDeveloperTools(
              isDemoMode = false,
              availableTools = setOf(runtime),
              containersAvailable = null,
              vmsAvailable = false,
              k8sAvailable = false,
              prometheusReported = false,
          )
      assertTrue(
          "Expected $runtime to show Containers in Developer tools", containerOnlySpec.anyVisible)
      assertTrue(containerOnlySpec.showContainers)
      assertFalse(containerOnlySpec.showLimaVms)
      assertFalse(containerOnlySpec.showK3sNodes)
      assertFalse(containerOnlySpec.showCustomPanel)
    }

    val liveContainersSpec =
        Derive.macDeveloperTools(
            isDemoMode = false,
            availableTools = emptySet(),
            containersAvailable = true,
            vmsAvailable = false,
            k8sAvailable = false,
            prometheusReported = false,
        )
    assertTrue(liveContainersSpec.anyVisible)
    assertTrue(liveContainersSpec.showContainers)

    val toolsSpec =
        Derive.macDeveloperTools(
            isDemoMode = false,
            availableTools = setOf("limactl", "kubectl"),
            containersAvailable = false,
            vmsAvailable = null,
            k8sAvailable = null,
            prometheusReported = true,
        )
    assertTrue(toolsSpec.anyVisible)
    assertFalse(toolsSpec.showContainers)
    assertTrue(toolsSpec.showLimaVms)
    assertTrue(toolsSpec.showK3sNodes)
    assertTrue(toolsSpec.showCustomPanel)

    val demoSpec =
        Derive.macDeveloperTools(
            isDemoMode = true,
            availableTools = emptySet(),
            containersAvailable = null,
            vmsAvailable = null,
            k8sAvailable = null,
            prometheusReported = false,
        )
    assertTrue(demoSpec.showContainers)
    assertTrue(demoSpec.showLimaVms)
    assertFalse(demoSpec.showK3sNodes)
    assertTrue(demoSpec.showCustomPanel)

    val (vmHeadline, vmDetail) =
        Derive.macToolNoticeLines("limactl", "exec: \"limactl\": executable file not found in PATH")
    assertEquals("Lima isn't installed on this Mac.", vmHeadline)
    assertTrue(vmDetail.contains("executable file not found"))

    val (promHeadline, promDetail) =
        Derive.promqlStatusLines("java.net.ConnectException: Failed to connect to /100.64.0.2:7411")
    assertEquals("Couldn't reach the Mac helper to run this query.", promHeadline)
    assertEquals("Failed to connect to /100.64.0.2:7411", promDetail)

    val (unconfiguredHeadline, unconfiguredDetail) =
        Derive.promqlStatusLines("no Mac helper configured")
    assertEquals("Add a Mac in Settings before running a query.", unconfiguredHeadline)
    assertNull(unconfiguredDetail)

    val macScreen =
        readRunfile(
            "apps/mobile/vitruvian-remote/src/main/kotlin/dev/vitruvian/remote/screens/MacScreen.kt")
    assertTrue(macScreen.contains("state.macDeveloperTools"))
    assertTrue(macScreen.contains("Label(text = \"Developer tools\""))
    assertTrue(macScreen.contains("var devToolsOpen by rememberSaveable { mutableStateOf(false) }"))
    val devToolsIndex = macScreen.indexOf("Label(text = \"Developer tools\"")
    val devToolsOpenIndex = macScreen.indexOf("if (devToolsOpen) {")
    val showContainersIndex = macScreen.indexOf("if (devTools.showContainers) {")
    val containersLabelIndex = macScreen.indexOf("Label(text = state.containersLabel")
    assertTrue(devToolsIndex in 0 until devToolsOpenIndex)
    assertTrue(devToolsOpenIndex in 0 until showContainersIndex)
    assertTrue(showContainersIndex in 0 until containersLabelIndex)
    assertTrue(macScreen.contains("Derive.promqlStatusLines(state.promqlStatus)"))
  }

  @Test
  public fun `F22 Home edit layout offers hidden widgets sheet and uses CLOSE icon`() {
    val allHidden = setOf("cpu", "mem", "temp", "bat")
    assertEquals(
        listOf("cpu", "mem", "temp", "bat"),
        Derive.hiddenWidgetOptions(allHidden).map { it.id },
    )
    assertFalse(Derive.shouldShowAddWidget(editMode = true, hiddenIds = emptySet()))
    assertFalse(Derive.shouldShowAddWidget(editMode = false, hiddenIds = setOf("cpu")))
    assertTrue(Derive.shouldShowAddWidget(editMode = true, hiddenIds = setOf("cpu")))

    val homeScreen =
        readRunfile(
            "apps/mobile/vitruvian-remote/src/main/kotlin/dev/vitruvian/remote/screens/HomeScreen.kt")
    assertTrue(homeScreen.contains("OptionSheet("))
    assertTrue(homeScreen.contains("VitruvianIcons.CLOSE"))
    assertFalse(homeScreen.contains("label = \"×\""))
  }

  @Test
  public fun `F12, F14, F17, F34 Settings order, pairing copy, Forget danger confirmation and plain copy`() {
    val hosts =
        readRunfile(
            "apps/mobile/vitruvian-remote/src/main/kotlin/dev/vitruvian/remote/screens/HostsScreen.kt")
    assertTrue(
        hosts.contains(
            "On your Mac, click Vitruvian Remote in the menu bar and choose Pair with QR Code,"))
    assertTrue(hosts.contains("then scan it. Or enter this code there:"))
    assertTrue(hosts.contains("onClick = state::requestForgetAgent"))
    assertTrue(hosts.contains("variant = ButtonVariant.Danger"))

    val sectionOrder =
        listOf(
            "Label(text = \"Your Macs ·",
            "PhoneBridgeSection(state)",
            "NotificationsSection(state)",
            "AppearanceSection(state)",
            "SafetySection(state)",
            "Label(\"Macros\")",
            "AboutSection(state)",
        )
    val positions = sectionOrder.map { hosts.indexOf(it) }
    assertTrue(
        "All ordered Settings sections must be present: $positions",
        positions.all { it >= 0 },
    )
    assertEquals(
        "Settings sections must follow Your Macs -> Phone Bridge -> Notifications -> Appearance -> Safety -> Macros -> About",
        positions.sorted(),
        positions,
    )

    val phoneBridge =
        readRunfile(
            "apps/mobile/vitruvian-remote/src/main/kotlin/dev/vitruvian/remote/screens/PhoneBridgeScreen.kt")
    assertTrue(phoneBridge.contains("AppInfo.phoneBridgeScreenSummary"))

    val remoteScreen =
        readRunfile(
            "apps/mobile/vitruvian-remote/src/main/kotlin/dev/vitruvian/remote/screens/RemoteScreen.kt")
    assertTrue(remoteScreen.contains("FoldingSection(state, RemoteSection.AGENT, \"Mac helper\")"))

    val userFacingFiles =
        listOf(
            hosts,
            phoneBridge,
            remoteScreen,
            readRunfile(
                "apps/mobile/vitruvian-remote/src/main/kotlin/dev/vitruvian/remote/screens/ConsoleScreen.kt"),
            readRunfile(
                "apps/mobile/vitruvian-remote/src/main/kotlin/dev/vitruvian/remote/screens/AppsScreen.kt"),
            readRunfile(
                "apps/mobile/vitruvian-remote/src/main/kotlin/dev/vitruvian/remote/screens/MacScreen.kt"),
            readRunfile(
                "apps/mobile/vitruvian-remote/src/main/kotlin/dev/vitruvian/remote/screens/HomeScreen.kt"),
            readRunfile(
                "apps/mobile/vitruvian-remote/src/main/kotlin/dev/vitruvian/remote/overlays/HostStates.kt"),
        )
    val bannedTerms =
        listOf(
            "Mac agent",
            "Tailscale address",
            "Parchment (light) theme",
            "Macros · bound to scripts",
            "MCP server",
        )
    for (fileText in userFacingFiles) {
      for (term in bannedTerms) {
        assertFalse("Banned jargon '$term' found in UI screen", fileText.contains(term))
      }
    }
  }

  @Test
  fun foldableHalfOpenDockHidesMainTrackpad() {
    assertTrue(
        Derive.showsDockTrackpad(
            showDock = true,
            isHalfOpen = true,
            isRemoteScreen = true,
        ))
    assertFalse(
        Derive.showsMainTrackpad(
            dockShowsTrackpad =
                Derive.showsDockTrackpad(
                    showDock = true,
                    isHalfOpen = true,
                    isRemoteScreen = true,
                )))

    // Folded or flat tablet does not put the trackpad in the dock, so the main trackpad stays
    // visible.
    assertFalse(
        Derive.showsDockTrackpad(
            showDock = false,
            isHalfOpen = false,
            isRemoteScreen = true,
        ))
    assertFalse(
        Derive.showsDockTrackpad(
            showDock = true,
            isHalfOpen = false,
            isRemoteScreen = true,
        ))
    assertTrue(
        Derive.showsMainTrackpad(
            dockShowsTrackpad =
                Derive.showsDockTrackpad(
                    showDock = false,
                    isHalfOpen = false,
                    isRemoteScreen = true,
                )))
    assertTrue(
        Derive.showsMainTrackpad(
            dockShowsTrackpad =
                Derive.showsDockTrackpad(
                    showDock = true,
                    isHalfOpen = false,
                    isRemoteScreen = true,
                )))
    // Dock shows Console instead of Trackpad when viewing another screen.
    assertFalse(
        Derive.showsDockTrackpad(
            showDock = true,
            isHalfOpen = true,
            isRemoteScreen = false,
        ))

    // Half-open Remote keeps the HID TrackpadDock visible even when Mac HTTP pairing is Unpaired.
    assertTrue(
        Derive.showsShellDock(
            showRail = true,
            dockOpen = true,
            screen = Screen.Remote,
            isUnpaired = true,
            isHalfOpen = true,
        ))
    assertFalse(
        Derive.showsShellDock(
            showRail = true,
            dockOpen = true,
            screen = Screen.Remote,
            isUnpaired = true,
            isHalfOpen = false,
        ))
    assertFalse(
        Derive.showsShellDock(
            showRail = true,
            dockOpen = true,
            screen = Screen.Home,
            isUnpaired = true,
            isHalfOpen = true,
        ))
    assertFalse(
        Derive.showsShellDock(
            showRail = false,
            dockOpen = true,
            screen = Screen.Remote,
            isUnpaired = false,
            isHalfOpen = true,
        ))
    assertFalse(
        Derive.showsShellDock(
            showRail = true,
            dockOpen = false,
            screen = Screen.Remote,
            isUnpaired = false,
            isHalfOpen = true,
        ))
    assertFalse(
        Derive.showsShellDock(
            showRail = true,
            dockOpen = true,
            screen = Screen.Console,
            isUnpaired = false,
            isHalfOpen = true,
        ))
  }

  @Test
  fun adaptiveButtonColumnsLowersAt200PercentScaleToAvoidMidWordTruncation() {
    val secondaryLabels = listOf("Keys", "Trackpad settings", "View screen")
    assertEquals(
        3,
        Derive.adaptiveButtonColumns(
            availableWidthDp = 334f,
            fontScale = 1.0f,
            labels = secondaryLabels,
            maxColumns = 3,
            gapDp = 8f,
            horizontalPaddingDp = 8f,
        ),
    )
    assertEquals(
        2,
        Derive.adaptiveButtonColumns(
            availableWidthDp = 384f,
            fontScale = 2.0f,
            labels = secondaryLabels,
            maxColumns = 3,
            gapDp = 8f,
            horizontalPaddingDp = 8f,
        ),
    )
    assertEquals(
        1,
        Derive.adaptiveButtonColumns(
            availableWidthDp = 300f,
            fontScale = 2.0f,
            labels = secondaryLabels,
            maxColumns = 3,
            gapDp = 8f,
            horizontalPaddingDp = 8f,
        ),
    )

    val windowLabels = listOf("Minimize", "Close Tab", "Maximize", "Fullscreen")
    assertEquals(
        3,
        Derive.adaptiveButtonColumns(
            availableWidthDp = 308f,
            fontScale = 1.0f,
            labels = windowLabels,
            maxColumns = 3,
            gapDp = 5f,
            horizontalPaddingDp = 5f,
        ),
    )
    assertEquals(
        1,
        Derive.adaptiveButtonColumns(
            availableWidthDp = 308f,
            fontScale = 2.0f,
            labels = windowLabels,
            maxColumns = 3,
            gapDp = 5f,
            horizontalPaddingDp = 5f,
        ),
    )
  }

  @Test
  fun topBarSettingsAndRemoteKeyTablesMatchPolishContracts() {
    assertTrue(Derive.showsTopBarSettings(showRail = false))
    assertFalse(Derive.showsTopBarSettings(showRail = true))

    assertTrue(REMOTE_WINDOW_ACTIONS.contains("Minimize" to HidAction.MinimiseWindow))
    assertFalse(
        REMOTE_WINDOW_ACTIONS.any { (label, _) -> label.equals("Minimise", ignoreCase = true) })
    assertTrue(REMOTE_DESKTOP_ACTIONS.any { (_, action) -> action == HidAction.MissionControl })
    assertTrue(REMOTE_PALETTE_KEYS.all { (_, description, _) -> !description.isNullOrBlank() })

    // Scoped composable wiring checks: @maven has runtime Compose artifacts only (no ui-test-junit4
    // or Robolectric), so layout/icon composition inside @Composable functions is pinned per-block
    // via extractKotlinBlock rather than whole-file string scans.
    val shell =
        stripKotlinComments(
            readRunfile(
                "apps/mobile/vitruvian-remote/src/main/kotlin/dev/vitruvian/remote/shell/Shell.kt"))
    val dock =
        stripKotlinComments(
            readRunfile(
                "apps/mobile/vitruvian-remote/src/main/kotlin/dev/vitruvian/remote/shell/Dock.kt"))
    val remote =
        stripKotlinComments(
            readRunfile(
                "apps/mobile/vitruvian-remote/src/main/kotlin/dev/vitruvian/remote/screens/RemoteScreen.kt"))
    val home =
        stripKotlinComments(
            readRunfile(
                "apps/mobile/vitruvian-remote/src/main/kotlin/dev/vitruvian/remote/screens/HomeScreen.kt"))

    val remoteShellBody = extractKotlinBlock(shell, "public fun RemoteShell(")
    assertTrue(remoteShellBody.contains("Derive.showsTopBarSettings(layout.showRail)"))
    assertTrue(remoteShellBody.contains("Derive.showsShellDock("))

    val consoleDockBody = extractKotlinBlock(dock, "private fun ConsoleDock(")
    assertFalse(consoleDockBody.contains("\"Lock\""))
    assertFalse(consoleDockBody.contains("\"Restart\""))
    assertTrue(consoleDockBody.contains("\"Console\""))

    val trackpadDockBody = extractKotlinBlock(dock, "private fun TrackpadDock(")
    assertTrue(trackpadDockBody.contains("NudgeRow("))
    assertTrue(trackpadDockBody.contains("MediaTransportRow("))

    val remoteScreenBody = extractKotlinBlock(remote, "public fun ColumnScope.RemoteScreen(")
    assertTrue(remoteScreenBody.contains("\"Trackpad settings\""))
    assertTrue(remoteScreenBody.contains("\"View screen\""))
    assertFalse(remoteScreenBody.contains("\"Feel\""))
    assertFalse(remoteScreenBody.contains("\"Peek\""))

    val foldHeaderBody = extractKotlinBlock(remote, "private fun FoldHeader(")
    assertTrue(foldHeaderBody.contains("VitruvianIcons.CHEVRON_DOWN"))
    assertTrue(foldHeaderBody.contains("VitruvianIcons.CHEVRON_RIGHT"))
    assertFalse(foldHeaderBody.contains("▸"))
    assertFalse(foldHeaderBody.contains("▾"))

    val mediaRowBody = extractKotlinBlock(remote, "internal fun MediaTransportRow(")
    assertTrue(mediaRowBody.contains("VitruvianIcons.PLAY_PAUSE"))

    val bannerBody = extractKotlinBlock(remote, "private fun BluetoothStatusBanner(")
    assertTrue(bannerBody.contains("state.performBluetoothBannerAction("))

    val homeScreenBody = extractKotlinBlock(home, "public fun ColumnScope.HomeScreen(")
    assertTrue(homeScreenBody.contains("VitruvianIcons.CHEVRON_RIGHT"))
    assertFalse(homeScreenBody.contains("›"))
    assertTrue(
        "Home Running now rows must suppress status dots duplicating tag state words",
        homeScreenBody.contains("statusAdjacentText = item.tag"),
    )

    val apps =
        stripKotlinComments(
            readRunfile(
                "apps/mobile/vitruvian-remote/src/main/kotlin/dev/vitruvian/remote/screens/AppsScreen.kt"))
    val moduleListRowBody = extractKotlinBlock(apps, "private fun ModuleListRow(")
    assertTrue(
        "ModuleListRow must pass onCheckedChange = null to child VSwitch so row owns Role.Switch",
        moduleListRowBody.contains("onCheckedChange = null"),
    )
    assertTrue(
        "ModuleListRow must forward toggle state to ListItem/WrappingRow",
        moduleListRowBody.contains("onCheckedChange = toggle?.onToggle"),
    )
    val wrappingRowBody = extractKotlinBlock(apps, "private fun WrappingRow(")
    assertTrue(
        "WrappingRow must attach Role.Switch toggleable and switchRowDescription to the outer row",
        wrappingRowBody.contains("role = Role.Switch") &&
            wrappingRowBody.contains(".toggleable(") &&
            wrappingRowBody.contains("A11y.switchRowDescription(") &&
            wrappingRowBody.contains("clearAndSetSemantics {}"),
    )
    assertTrue(
        "WrappingRow Status must suppress duplicate state words",
        wrappingRowBody.contains("Status(tone = row.tone, adjacentText = statusAdjacentText"),
    )
  }

  @Test
  public fun `demo sample data uses neutral commands and avoids owner repo or homelab CLI specifics`() {
    val forbidden =
        listOf(
            "bazel",
            "//tools",
            "gitops",
            "staging",
            "homelab status",
            "my-homelab",
            "vitruvian-core")
    val demoStrings = buildList {
      MockHost.builtInMacros.forEach {
        add(it.id)
        add(it.label)
        add(it.command)
      }
      MockHost.runningNow.forEach {
        add(it.title)
        add(it.subtitle)
      }
      MockHost.processes.forEach { add(it.name) }
      MockHost.vms.forEach {
        add(it.name)
        add(it.subtitle)
      }
      MockHost.initialTerminal.forEach {
        add(it.prefix)
        add(it.text)
      }
      MockHost.initialAgentTranscript.forEach {
        add(it.prefix)
        add(it.text)
      }
      addAll(MockHost.recentCommands)
      MockHost.dashboards(MockHost.initialAgentTranscript, agentRunning = true).values.forEach { d
        ->
        add(d.meta)
        add(d.streamLabel)
        d.metrics.forEach {
          add(it.label)
          add(it.value)
          add(it.sub)
        }
        d.lines.forEach {
          add(it.prefix)
          add(it.text)
        }
        d.rows.forEach {
          add(it.title)
          add(it.subtitle)
        }
      }
    }
    forbidden.forEach { token ->
      val hit = demoStrings.firstOrNull { it.contains(token, ignoreCase = true) }
      assertNull("Found owner-specific demo token '$token' in '$hit'", hit)
    }
    assertTrue(MockHost.builtInMacros.any { it.label == "Lock screen" })
    assertTrue(MockHost.builtInMacros.any { it.label == "Mute" })
    assertTrue(MockHost.builtInMacros.any { it.command == "brew upgrade" })
    assertTrue("git status" in MockHost.recentCommands)
    assertTrue("npm test" in MockHost.recentCommands)
    assertTrue("brew upgrade" in MockHost.recentCommands)
  }

  private class FakeBluetoothControl(
      var hidSupported: Boolean = true,
      var hasAdapter: Boolean = true,
      var permissionGranted: Boolean = true,
      var asked: Boolean = false,
      var rationale: Boolean = false,
      var enabled: Boolean = true,
      var pairedComputer: Boolean = true,
      var grantOnEnsure: Boolean = false,
      var rationaleOnEnsure: Boolean = false,
  ) : BluetoothControl {
    var ensurePermissionCalls: Int = 0
    var openAppSettingsCalls: Int = 0
    var enableBluetoothCalls: Int = 0
    var openBluetoothSettingsCalls: Int = 0

    override fun isBluetoothHidSupported(): Boolean = hidSupported

    override fun hasBluetoothAdapter(): Boolean = hasAdapter

    override fun hasBluetoothPermission(): Boolean = permissionGranted

    override fun hasAskedBluetoothPermission(): Boolean = asked

    override fun shouldShowBluetoothRationale(): Boolean = rationale

    override fun isBluetoothEnabled(): Boolean = enabled

    override fun hasPairedComputer(): Boolean = pairedComputer

    override fun ensureBluetoothPermission(
        onResult: (granted: Boolean, shouldShowRationale: Boolean) -> Unit,
    ) {
      ensurePermissionCalls++
      asked = true
      permissionGranted = grantOnEnsure
      rationale = rationaleOnEnsure
      onResult(permissionGranted, rationale)
    }

    override fun openAppSettings() {
      openAppSettingsCalls++
    }

    override fun requestEnableBluetooth() {
      enableBluetoothCalls++
    }

    override fun openBluetoothSettings() {
      openBluetoothSettingsCalls++
    }
  }

  private class FakePrefsStore : PrefsStore {
    private val data = linkedMapOf<String, Any?>()

    override fun contains(key: String): Boolean = data.containsKey(key)

    override fun getString(key: String, defValue: String?): String? =
        if (data.containsKey(key)) data[key] as? String ?: defValue else defValue

    @Suppress("UNCHECKED_CAST")
    override fun getStringSet(key: String, defValues: Set<String>?): Set<String>? {
      val stored = (data[key] as? Set<String>) ?: return defValues
      return stored.toSet()
    }

    override fun getInt(key: String, defValue: Int): Int =
        if (data.containsKey(key)) data[key] as? Int ?: defValue else defValue

    override fun getLong(key: String, defValue: Long): Long =
        if (data.containsKey(key)) data[key] as? Long ?: defValue else defValue

    override fun getBoolean(key: String, defValue: Boolean): Boolean =
        if (data.containsKey(key)) data[key] as? Boolean ?: defValue else defValue

    override fun edit(): PrefsStore.Editor = Editor()

    private inner class Editor : PrefsStore.Editor {
      private val pending = linkedMapOf<String, Any?>()
      private val removals = linkedSetOf<String>()

      override fun putString(key: String, value: String?): PrefsStore.Editor = apply {
        pending[key] = value
      }

      override fun putStringSet(key: String, values: Set<String>?): PrefsStore.Editor = apply {
        pending[key] = values?.toSet()
      }

      override fun putInt(key: String, value: Int): PrefsStore.Editor = apply {
        pending[key] = value
      }

      override fun putLong(key: String, value: Long): PrefsStore.Editor = apply {
        pending[key] = value
      }

      override fun putBoolean(key: String, value: Boolean): PrefsStore.Editor = apply {
        pending[key] = value
      }

      override fun remove(key: String): PrefsStore.Editor = apply {
        removals.add(key)
        pending.remove(key)
      }

      override fun apply() {
        removals.forEach { data.remove(it) }
        for ((k, v) in pending) {
          if (v == null) data.remove(k) else data[k] = v
        }
      }
    }
  }

  @Test
  public fun `running now hides modules the user has not shown and tools this Mac lacks`() {
    val gallery = setOf("claude", "lima", "homelab", "speaker", "docker")
    // (moduleId, tag) rows, the shape Home builds.
    val rows =
        listOf(
            "claude" to "running",
            "lima" to "1 running",
            "homelab" to "3 ready",
            "docker" to Derive.RUNNING_NO_SOURCE_TAG,
            "speaker" to "ready",
            "prs" to "2 open", // not a gallery module
            "ollama" to Derive.RUNNING_NO_SOURCE_TAG, // not in the gallery, no source
        )
    val visible =
        Derive.visibleRunningNow(
                rows,
                gallery,
                shownIds = setOf("claude", "docker"),
                moduleId = { it.first },
                tag = { it.second },
            )
            .map { it.first }
    // lima/homelab/speaker are hidden in the gallery; docker is shown but has no source.
    assertEquals(listOf("claude", "prs"), visible)
  }
}
