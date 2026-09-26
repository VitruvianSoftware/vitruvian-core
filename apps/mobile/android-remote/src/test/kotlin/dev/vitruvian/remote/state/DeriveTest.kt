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

import dev.vitruvian.remote.state.Derive.PeekRegion
import dev.vitruvian.remote.state.Derive.PrCheck
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

/** What the v1.2 rows are coloured by. Each of these was a wrong colour waiting to happen. */
public class DeriveTest {

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

  // --- HomeSpeaker ---------------------------------------------------------

  @Test
  public fun `the speaker's worst problem is the status, never a cheerful on`() {
    assertEquals("not installed", Derive.homeSpeakerStatus(false, false, false, true, true))
    assertEquals("not set up", Derive.homeSpeakerStatus(false, true, false, true, true))
    assertEquals("not signed in", Derive.homeSpeakerStatus(true, true, false, true, true))
    assertEquals("off", Derive.homeSpeakerStatus(true, true, true, false, true))
    assertEquals("on · app closed", Derive.homeSpeakerStatus(true, true, true, true, false))
    assertEquals("on", Derive.homeSpeakerStatus(true, true, true, true, true))
  }

  @Test
  public fun `a speaker that cannot speak is a problem even when switched on`() {
    assertEquals(Derive.SpeakerHealth.Problem, Derive.homeSpeakerHealth(true, true, false, true))
    assertEquals(Derive.SpeakerHealth.Off, Derive.homeSpeakerHealth(true, true, true, false))
    assertEquals(Derive.SpeakerHealth.Ok, Derive.homeSpeakerHealth(true, true, true, true))
  }

  @Test
  public fun `speech length labels round trip the wire values and default to summary`() {
    assertEquals(listOf("headline", "summary", "full"), Derive.speechLengths)
    assertEquals("Headline", Derive.speechLengthLabel("headline"))
    assertEquals("Full reply", Derive.speechLengthLabel("FULL"))
    assertEquals("Summary", Derive.speechLengthLabel("summary"))
    assertEquals("Summary", Derive.speechLengthLabel(""))
    assertEquals("Summary", Derive.speechLengthLabel("medium"))
  }

  @Test
  public fun `the pause margin stays inside what the Mac accepts`() {
    assertEquals(2.0, Derive.nextPauseMargin(1.0, 1.0), 1e-9)
    assertEquals(0.0, Derive.nextPauseMargin(0.0, -1.0), 1e-9)
    assertEquals(10.0, Derive.nextPauseMargin(10.0, 1.0), 1e-9)
    assertEquals(10.0, Derive.nextPauseMargin(9.5, 1.0), 1e-9)
  }

  @Test
  public fun `the pause margin reads in whole seconds like the Mac's stepper`() {
    assertEquals("resumes 1 s after the speaker", Derive.pauseMarginLabel(1.0))
    assertEquals("resumes 3 s after the speaker", Derive.pauseMarginLabel(2.6))
  }

  @Test
  public fun `a speaker's volume is never shown as a stale number`() {
    assertEquals("40%", Derive.speakerVolumeLabel(true, true, false, 40))
    assertEquals("muted", Derive.speakerVolumeLabel(true, true, true, 40))
    assertEquals("offline", Derive.speakerVolumeLabel(true, false, false, 40))
    assertEquals("n/a", Derive.speakerVolumeLabel(false, true, false, 40))
  }

  @Test
  public fun `volume steps stay inside 0 to 100`() {
    assertEquals(50, Derive.nextVolume(40, 10))
    assertEquals(0, Derive.nextVolume(5, -10))
    assertEquals(100, Derive.nextVolume(95, 10))
  }

  // --- battery (API v1.5.1) ----------------------------------------------

  @Test
  public fun `a missing battery temperature is said, never printed as 0 degrees`() {
    assertEquals("no battery reading", Derive.batteryTemperatureLabel(null))
    assertEquals("no battery reading", Derive.batteryTemperatureLabel(Double.NaN))
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
    // Both states say the desktop app is not covered: found on the real Mac.
    assertTrue(Derive.claudeHookExplanation(true, "atlas", 120).contains("desktop app"))
    assertTrue(Derive.claudeHookExplanation(false, "", 0).contains("on the Mac ("))
    val body = Derive.claudeHookDialogBody("atlas", 90)
    assertTrue(body.contains("~/.claude/settings.json on atlas"))
    assertTrue(body.contains("every Claude Code session"))
    assertTrue(body.contains("Unanswered for 90 s"))
    assertEquals("installing…", Derive.claudeHookBusyLabel(true))
    assertEquals("removing…", Derive.claudeHookBusyLabel(false))
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
}
