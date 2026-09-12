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

import java.util.Locale

/**
 * The judgements the v1.2 dashboards make about what the Mac said.
 *
 * Split out of `RemoteState` and free of Android imports for the same reason as [Format]: these
 * decide what COLOUR a row is, and a wrong colour is the quietest failure this app can have. A pull
 * request whose only finished check failed drawn as green, or an ArgoCD app that is Synced but
 * Degraded buried under forty healthy ones, look exactly like a working screen. A plain JVM test
 * can pin every boundary here without a phone in the room.
 */
public object Derive {

  // --- screen peek zoom -------------------------------------------------

  /**
   * The part of the Mac's display a peek shows, as fractions of its width and height.
   *
   * Fractions rather than pixels because the phone never learns the display's pixel size and must
   * not need to: it only knows what fraction of the picture it was showing when the user pinched.
   * [Full] is the whole display, which the agent treats as "no crop".
   */
  public data class PeekRegion(val x: Double, val y: Double, val w: Double, val h: Double) {
    public val isFull: Boolean
      get() = x <= 0.0 && y <= 0.0 && w >= 1.0 && h >= 1.0

    /** How many times closer than the whole display this is, for the caption. */
    public val zoom: Double
      get() = if (w <= 0.0) 1.0 else 1.0 / w

    public companion object {
      public val Full: PeekRegion = PeekRegion(0.0, 0.0, 1.0, 1.0)

      /**
       * The agent's cap: 16x. Past it a crop is a few hundred native pixels stretched to phone
       * width.
       */
      public const val MIN_FRACTION: Double = 1.0 / 16
    }
  }

  /**
   * Where a pinch left the picture, as a new region of the display.
   *
   * The plate shows [current] scaled by [scale] about the top-left corner and moved by ([offsetX],
   * [offsetY]) pixels, in a view [viewW] by [viewH] pixels wide. What is visible through the view
   * is the window `(-offset/scale) .. ((view - offset)/scale)` of the picture, and that window, as
   * a fraction of the picture, is the same fraction of [current]. Both axes use one scale, so the
   * region keeps the display's aspect and the next picture fits the same plate.
   *
   * Clamped so it never asks the agent for something it will refuse: at least [MIN_FRACTION] each
   * way, never past the display's edge. Pinching out past 1x is a request for the whole display.
   */
  public fun zoomedRegion(
      current: PeekRegion,
      scale: Float,
      offsetX: Float,
      offsetY: Float,
      viewW: Int,
      viewH: Int,
  ): PeekRegion {
    if (viewW <= 0 || viewH <= 0 || scale <= 0f || scale.isNaN()) return current
    var w = current.w / scale
    var h = current.h / scale
    if (w >= 1.0 || h >= 1.0) return PeekRegion.Full
    // One factor for both axes, so the aspect survives the clamp too.
    val floor = maxOf(PeekRegion.MIN_FRACTION / w, PeekRegion.MIN_FRACTION / h, 1.0)
    w *= floor
    h *= floor
    var x = current.x + current.w * (-offsetX / scale) / viewW
    var y = current.y + current.h * (-offsetY / scale) / viewH
    x = x.coerceIn(0.0, 1.0 - w)
    y = y.coerceIn(0.0, 1.0 - h)
    return PeekRegion(x, y, w, h)
  }

  // --- pull requests ----------------------------------------------------

  /**
   * What a PR's check rollup amounts to, in one word.
   *
   * The order IS the function: a draft is a draft whatever its checks say, one failure outranks any
   * number of successes, and anything still running is pending rather than green. Skipped checks
   * are counted by the agent and deliberately ignored -- a skipped check is not a passing one, but
   * it is not a reason to withhold "green" either.
   */
  public fun prCheck(isDraft: Boolean, success: Int, failure: Int, pending: Int): PrCheck =
      when {
        isDraft -> PrCheck.Draft
        failure > 0 -> PrCheck.Red
        pending > 0 -> PrCheck.Pending
        success > 0 -> PrCheck.Green
        // No checks at all is not success. A repository with no CI, and one
        // whose workflows have not started yet, both land here; calling
        // either "green" would be a claim nothing on the Mac made.
        else -> PrCheck.None
      }

  /** The tag a PR row wears. */
  public enum class PrCheck(public val label: String) {
    Draft("draft"),
    Green("green"),
    Red("red"),
    Pending("pending"),
    None("no checks"),
  }

  // --- ArgoCD -----------------------------------------------------------

  /** Whether an app needs nobody's attention: synced to git AND reporting healthy. */
  public fun argoOk(sync: String, health: String): Boolean =
      sync.equals("Synced", ignoreCase = true) && health.equals("Healthy", ignoreCase = true)

  /**
   * The apps worth a row, and the count of the ones that are not.
   *
   * Fifty apps is fifty rows nobody reads, with the three that are broken somewhere in the middle.
   * The ones needing attention keep their rows and their order; the rest collapse to a single line
   * saying how many there are, which is the only thing about them worth knowing.
   */
  public fun <T> splitArgo(items: List<T>, ok: (T) -> Boolean): ArgoSplit<T> {
    val (fine, attention) = items.partition(ok)
    return ArgoSplit(attention = attention, restCount = fine.size)
  }

  /** [attention] keeps its rows; [restCount] counts everything Synced and Healthy. */
  public data class ArgoSplit<T>(val attention: List<T>, val restCount: Int)

  /** The collapsed row's title: `47 more, all Synced · Healthy`. */
  public fun collapsedArgoLabel(count: Int): String =
      if (count == 1) "1 more, Synced · Healthy" else "$count more, all Synced · Healthy"

  // --- Claude Code sessions ---------------------------------------------

  /**
   * The agent's session state as the tag beside a row.
   *
   * The wire words are the agent's own heuristic -- its contract says so -- and they are shortened
   * here rather than reworded, so what is on the phone can still be matched to what the agent
   * reported. An unrecognised state is passed through instead of being flattened to "unknown": a
   * newer agent inventing a fourth state should show it, not have it erased.
   */
  public fun claudeStateLabel(state: String): String {
    val lower = state.trim().lowercase(Locale.ROOT)
    return when (lower) {
      "waiting_for_permission" -> "waiting"
      "" -> "unknown"
      else -> lower
    }
  }

  /** True only for the state that means a person has to do something. */
  public fun claudeWaiting(state: String): Boolean =
      state.equals("waiting_for_permission", ignoreCase = true)
}
