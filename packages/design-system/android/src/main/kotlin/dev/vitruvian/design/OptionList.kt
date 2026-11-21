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

package dev.vitruvian.design

/**
 * The pure rules behind [OptionSheet], kept free of Compose so a plain JVM test can pin them.
 *
 * An option sheet lists every value a control can take. Two decisions in it are easy to get wrong
 * and invisible in a screenshot of a short list: where a long list starts when it opens, and what a
 * tap on each kind of row does.
 */
public object OptionList {
  /**
   * How many rows sit above the current value when a long list opens on it, so the value reads in
   * context ("21:00, 22:00 ▸ 23:00") instead of pinned against the header.
   */
  public const val LEAD_ROWS: Int = 2

  /**
   * The index the list's first visible row should be when the sheet opens.
   *
   * The current value scrolled into view, [leadRows] below the top; the top of the list when there
   * is no current value. A list short enough to fit is not scrolled at all: the list itself clamps
   * an index past its end, so this does not need to know the viewport height.
   */
  public fun firstVisibleIndex(selectedIndex: Int, count: Int, leadRows: Int = LEAD_ROWS): Int {
    if (selectedIndex !in 0 until count) return 0
    return (selectedIndex - leadRows.coerceAtLeast(0)).coerceAtLeast(0)
  }

  /** What tapping one row of an option sheet does. */
  public enum class Tap {
    /** A different, available value: apply it and close. */
    Apply,

    /** The current value: nothing to change, so just close. */
    Dismiss,

    /** An unavailable value: do nothing and stay open, so the tap is not mistaken for a choice. */
    Ignore,
  }

  /**
   * The [Tap] for a row. The current value wins over [enabled]: callers disable it to block a
   * re-send.
   */
  public fun tap(enabled: Boolean, selected: Boolean): Tap =
      when {
        selected -> Tap.Dismiss
        enabled -> Tap.Apply
        else -> Tap.Ignore
      }
}
