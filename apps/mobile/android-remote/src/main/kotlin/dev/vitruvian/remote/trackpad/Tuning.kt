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

/**
 * How the trackpad feels, as three numbers the user can change at runtime.
 *
 * These were compile-time constants until now, which made them untunable in the only way that
 * matters: the shipped values were guesses, and checking a guess meant a rebuild and a reinstall.
 * Nobody tunes a pointer that way, so nobody tuned it.
 *
 * Deliberately NO Android imports, and deliberately not a Compose type, so the arithmetic below is
 * covered by a plain JVM test - the same reason `hid/HidCodes.kt` is kept separate. Feel cannot be
 * unit-tested, but the conversions can, and those are where an off-by-one silently produces a
 * pointer that crawls or a scroll that flings.
 *
 * Everything is stored as a **percentage of the shipped default**, not as the underlying
 * multiplier. 100% is what the app has always done. That makes the default self-evidently the
 * default, and makes "a bit faster" a number anyone can reason about, which "gain 2.4" is not.
 */
public data class TrackpadTuning(
    /** Pointer speed, percent of default. */
    val pointerPercent: Int = DEFAULT_PERCENT,
    /** Scroll speed, percent of default. */
    val scrollPercent: Int = DEFAULT_PERCENT,
    /** How long a still finger must rest before a drag arms. */
    val dragHoldMillis: Int = DEFAULT_DRAG_HOLD_MILLIS,
) {
  /**
   * Trackpad pixels to mouse units.
   *
   * Above 1.0 at 100% because the pad is a few hundred px wide and a Mac desktop is thousands: at
   * 1:1 you run out of trackpad long before the cursor crosses the screen. Still a flat multiplier
   * rather than an acceleration curve - macOS applies its own acceleration to incoming HID deltas,
   * and curving them here would compound with that and feel wrong at both ends.
   */
  public val pointerGain: Float
    get() = POINTER_GAIN_AT_100 * pointerPercent / PERCENT

  /**
   * Trackpad pixels per wheel notch.
   *
   * INVERSELY proportional to the percentage: this is a divisor, so a bigger number scrolls slower.
   * The user sets a speed and never sees the divisor, which is the whole point of storing percent.
   */
  public val scrollDivisor: Float
    get() = SCROLL_DIVISOR_AT_100 * PERCENT / scrollPercent

  public companion object {
    /** 100%: every default below is the value the app shipped with before this was tunable. */
    public const val PERCENT: Float = 100f

    public const val DEFAULT_PERCENT: Int = 100

    /** entangle's hold time. Evidence-based, but tuned on their hardware, not this Fold. */
    public const val DEFAULT_DRAG_HOLD_MILLIS: Int = 450

    private const val POINTER_GAIN_AT_100 = 2.0f
    private const val SCROLL_DIVISOR_AT_100 = 12f

    /**
     * Speed bounds.
     *
     * The floor is not zero: a 0% pointer is a broken app that looks like a broken Bluetooth link,
     * and the user would have no way to tell which. 25% is slow enough to be clearly deliberate.
     */
    public const val MIN_PERCENT: Int = 25

    public const val MAX_PERCENT: Int = 400

    public const val PERCENT_STEP: Int = 25

    /**
     * Hold-time bounds.
     *
     * Below ~150 ms a drag arms during an ordinary tap; above ~900 ms the hold feels broken and
     * people lift off before it fires. Both ends were chosen to keep an unusable setting out of
     * reach rather than to express a preference about what is right in between.
     */
    public const val MIN_DRAG_HOLD_MILLIS: Int = 150

    public const val MAX_DRAG_HOLD_MILLIS: Int = 900

    public const val DRAG_HOLD_STEP_MILLIS: Int = 50

    /** Clamped so a corrupt or hand-edited preference cannot produce a dead trackpad. */
    public fun clampPercent(value: Int): Int = value.coerceIn(MIN_PERCENT, MAX_PERCENT)

    public fun clampDragHold(value: Int): Int =
        value.coerceIn(MIN_DRAG_HOLD_MILLIS, MAX_DRAG_HOLD_MILLIS)
  }
}
