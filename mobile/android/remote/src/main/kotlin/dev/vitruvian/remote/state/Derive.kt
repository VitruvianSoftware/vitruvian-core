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
