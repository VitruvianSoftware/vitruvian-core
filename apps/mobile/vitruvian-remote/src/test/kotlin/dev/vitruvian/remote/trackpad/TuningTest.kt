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

package dev.vitruvian.remote.trackpad

import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test

/**
 * Pins the tuning arithmetic.
 *
 * Feel is not testable and this does not try. What IS testable is the pair of conversions between
 * the percentage the user sets and the multipliers the pointer and scroll paths actually use -- and
 * those are easy to get subtly wrong, because one is proportional and the other inverse. An error
 * there is not a crash; it is a pointer that crawls or a scroll that flings, on a device nobody
 * runs in CI.
 *
 * The 100% cases are the important ones: they assert that making these tunable did NOT quietly
 * change how the app behaves for someone who never touches the controls.
 */
class TuningTest {

  @Test
  fun `100 percent reproduces the values the app shipped with`() {
    val default = TrackpadTuning()

    assertEquals("pointer gain at 100% must stay 2.0", 2.0f, default.pointerGain, EPSILON)
    assertEquals("scroll divisor at 100% must stay 12", 12f, default.scrollDivisor, EPSILON)
    assertEquals(
        "drag hold at default must stay entangle's 450 ms",
        450,
        default.dragHoldMillis,
    )
  }

  @Test
  fun `pointer speed is proportional`() {
    assertEquals(1.0f, TrackpadTuning(pointerPercent = 50).pointerGain, EPSILON)
    assertEquals(4.0f, TrackpadTuning(pointerPercent = 200).pointerGain, EPSILON)
  }

  @Test
  fun `scroll speed is INVERSE -- a higher percent is a smaller divisor`() {
    // The one that is easy to invert by accident. A bigger divisor scrolls
    // SLOWER, so "200% speed" must halve it, not double it.
    assertEquals(6f, TrackpadTuning(scrollPercent = 200).scrollDivisor, EPSILON)
    assertEquals(24f, TrackpadTuning(scrollPercent = 50).scrollDivisor, EPSILON)

    val faster = TrackpadTuning(scrollPercent = 300).scrollDivisor
    val slower = TrackpadTuning(scrollPercent = 100).scrollDivisor
    assertTrue("raising the percent must lower the divisor", faster < slower)
  }

  @Test
  fun `clamping keeps a corrupt preference from producing a dead trackpad`() {
    // A stored 0 -- from a hand-edited preference, or a future bug -- would
    // give gain 0: a pointer that never moves, indistinguishable on screen
    // from a Bluetooth link that is not connected.
    assertEquals(
        TrackpadTuning.MIN_PERCENT,
        TrackpadTuning.clampPercent(0),
    )
    assertEquals(
        TrackpadTuning.MIN_PERCENT,
        TrackpadTuning.clampPercent(-500),
    )
    assertEquals(
        TrackpadTuning.MAX_PERCENT,
        TrackpadTuning.clampPercent(Int.MAX_VALUE),
    )

    assertEquals(
        TrackpadTuning.MIN_DRAG_HOLD_MILLIS,
        TrackpadTuning.clampDragHold(0),
    )
    assertEquals(
        TrackpadTuning.MAX_DRAG_HOLD_MILLIS,
        TrackpadTuning.clampDragHold(10_000),
    )
  }

  @Test
  fun `every reachable setting produces a usable multiplier`() {
    // Walks the whole range the UI can reach, rather than spot-checking the
    // ends: the guard that matters is that NO setting a user can dial in
    // yields zero, negative or non-finite motion.
    var percent = TrackpadTuning.MIN_PERCENT
    while (percent <= TrackpadTuning.MAX_PERCENT) {
      val tuning = TrackpadTuning(pointerPercent = percent, scrollPercent = percent)

      assertTrue("pointer gain must stay positive at $percent%", tuning.pointerGain > 0f)
      assertTrue("pointer gain must stay finite at $percent%", tuning.pointerGain.isFinite())
      assertTrue("scroll divisor must stay positive at $percent%", tuning.scrollDivisor > 0f)
      assertTrue("scroll divisor must stay finite at $percent%", tuning.scrollDivisor.isFinite())

      percent += TrackpadTuning.PERCENT_STEP
    }
  }

  @Test
  fun `the step divides the range so the ends are reachable`() {
    // A step that does not divide the span leaves the maximum unreachable by
    // tapping +, which looks like a stuck control.
    val span = TrackpadTuning.MAX_PERCENT - TrackpadTuning.MIN_PERCENT
    assertEquals(
        "percent step must land exactly on the maximum", 0, span % TrackpadTuning.PERCENT_STEP)

    val holdSpan = TrackpadTuning.MAX_DRAG_HOLD_MILLIS - TrackpadTuning.MIN_DRAG_HOLD_MILLIS
    assertEquals(
        "hold step must land exactly on the maximum",
        0,
        holdSpan % TrackpadTuning.DRAG_HOLD_STEP_MILLIS,
    )

    // And the shipped default must itself be on the grid, or the first tap of
    // + or - would jump by an odd amount.
    assertEquals(
        "the default percent must sit on the step grid",
        0,
        (TrackpadTuning.DEFAULT_PERCENT - TrackpadTuning.MIN_PERCENT) % TrackpadTuning.PERCENT_STEP,
    )
    assertEquals(
        "the default hold must sit on the step grid",
        0,
        (TrackpadTuning.DEFAULT_DRAG_HOLD_MILLIS - TrackpadTuning.MIN_DRAG_HOLD_MILLIS) %
            TrackpadTuning.DRAG_HOLD_STEP_MILLIS,
    )
  }

  private companion object {
    const val EPSILON = 0.0001f
  }
}
