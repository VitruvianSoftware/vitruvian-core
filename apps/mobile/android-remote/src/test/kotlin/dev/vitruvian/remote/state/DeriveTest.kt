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
}
