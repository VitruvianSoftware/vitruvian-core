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
import kotlin.math.roundToInt

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

  // --- HomeSpeaker ---------------------------------------------------------

  /** The three values HomeSpeaker's `speech_length` accepts, in the order the buttons show. */
  public val speechLengths: List<String> = listOf("headline", "summary", "full")

  /** The wire value as the button reads; anything unknown is shown as the app's default. */
  public fun speechLengthLabel(wire: String): String =
      when (wire.lowercase(Locale.ROOT)) {
        "headline" -> "Headline"
        "full" -> "Full reply"
        else -> "Summary"
      }

  /**
   * The one word on the HomeSpeaker plate, worst problem first.
   *
   * Order matters: "on" with no sign-in would draw a green status over a speaker that cannot speak,
   * which is the quiet kind of wrong this file exists to prevent. Each earlier condition is a
   * reason the later ones do not matter yet.
   */
  public fun homeSpeakerStatus(
      available: Boolean,
      installed: Boolean,
      signedIn: Boolean,
      enabled: Boolean,
      appRunning: Boolean,
  ): String =
      when {
        !available && !installed -> "not installed"
        !available -> "not set up"
        !signedIn -> "not signed in"
        !enabled -> "off"
        !appRunning -> "on · app closed"
        else -> "on"
      }

  /**
   * The speaker's volume in one word, never a number that is not current: an offline speaker
   * reports the last level it had, which would read as its level now.
   */
  public fun speakerVolumeLabel(
      available: Boolean,
      online: Boolean,
      muted: Boolean,
      percent: Int
  ): String =
      when {
        !available -> "n/a"
        !online -> "offline"
        muted -> "muted"
        else -> "$percent%"
      }

  /** A volume after a − or + tap, inside 0-100. */
  public fun nextVolume(current: Int, delta: Int): Int = (current + delta).coerceIn(0, 100)

  /** HomeSpeaker's own range for the resume margin (its Settings stepper). */
  public const val PAUSE_MARGIN_MAX: Double = 10.0

  /** The resume margin after a − or + tap, kept inside what the Mac accepts. */
  public fun nextPauseMargin(current: Double, delta: Double): Double =
      (current + delta).coerceIn(0.0, PAUSE_MARGIN_MAX)

  /**
   * "resumes 1 s after the speaker" -- whole seconds, as the Mac's stepper shows it, and short
   * enough for one line on the folded screen (the longer form was cut off there).
   */
  public fun pauseMarginLabel(seconds: Double): String =
      "resumes ${seconds.roundToInt()} s after the speaker"

  /** Whether [homeSpeakerStatus]'s word is a good one, an off one, or a problem. */
  public enum class SpeakerHealth {
    Ok,
    Off,
    Problem,
  }

  public fun homeSpeakerHealth(
      available: Boolean,
      installed: Boolean,
      signedIn: Boolean,
      enabled: Boolean,
  ): SpeakerHealth =
      when {
        !available || !installed || !signedIn -> SpeakerHealth.Problem
        !enabled -> SpeakerHealth.Off
        else -> SpeakerHealth.Ok
      }

  // --- battery (API v1.5.1) ---------------------------------------------

  /**
   * The battery sensor, as the thermal tile's sub-line.
   *
   * Null is "macOS did not say", and it is printed as that. The agent used to send 0 for it and the
   * phone printed "battery 0°" -- a temperature no working Mac has ever had, drawn exactly like one
   * it might.
   */
  public fun batteryTemperatureLabel(celsius: Double?): String =
      if (celsius == null || celsius.isNaN()) "no battery reading"
      else "battery ${celsius.roundToInt()}°"

  /**
   * What the Mac is drawing, and from where.
   *
   * On AC the battery's own discharge is 0 by definition, so "0 W · on AC" was true and useless;
   * the adapter figure is the one worth reading there. Off AC the battery IS the supply, so its
   * draw is the figure. A missing adapter figure is left out rather than printed as 0 W.
   */
  public fun batteryPowerLabel(
      onAc: Boolean,
      charging: Boolean,
      drawWatts: Double,
      systemWatts: Double?,
  ): String {
    val adapter = systemWatts?.takeUnless { it.isNaN() }?.let { "${decimal(it)} W from adapter" }
    return when {
      charging -> listOfNotNull(adapter, "charging").joinToString(" · ")
      onAc -> listOfNotNull(adapter, "on AC").joinToString(" · ")
      else -> "${decimal(drawWatts)} W · on battery"
    }
  }

  // --- disk -------------------------------------------------------------

  /** How full a disk is, as the colour its tile wears. */
  public enum class Fill {
    Ok,
    Warn,
    Crit,
  }

  /**
   * Amber from 80%, red from 95%.
   *
   * macOS starts complaining in the low nineties, and APFS snapshots and swap need headroom well
   * before 100%, so red has to arrive while there is still room to act on it.
   */
  public fun diskFill(usedPercent: Double): Fill =
      when {
        usedPercent.isNaN() -> Fill.Ok
        usedPercent >= DISK_CRIT_PERCENT -> Fill.Crit
        usedPercent >= DISK_WARN_PERCENT -> Fill.Warn
        else -> Fill.Ok
      }

  public const val DISK_WARN_PERCENT: Double = 80.0
  public const val DISK_CRIT_PERCENT: Double = 95.0

  // --- Claude Code on Home ------------------------------------------------

  /**
   * The one sentence Home and the Claude dashboard both use for Claude Code.
   *
   * They used to be built separately -- Home said "9 sessions" while the dashboard showed 8
   * sessions and 7 processes -- from a list that changes as transcripts age out of the agent's
   * window, so two screens read a few seconds apart could disagree. Both now come from here, and
   * the two measures keep two different words: a SESSION is a recent transcript under
   * `~/.claude/projects`, a PROCESS is a live `claude` binary. They legitimately differ (a finished
   * session keeps its transcript; a transcript can have no process), so neither may borrow the
   * other's noun. [processes] null means the agent has not answered yet; it is left out, not
   * zeroed.
   */
  public fun claudeSummary(sessions: Int, waiting: Int, processes: Int?): String =
      listOfNotNull(
              "$sessions session${if (sessions == 1) "" else "s"}",
              processes?.let { "$it process${if (it == 1) "" else "es"}" },
              if (waiting > 0) "$waiting waiting" else null,
          )
          .joinToString(" · ")

  // --- Claude Code permission prompts (API v1.6) -------------------------

  /**
   * How many prompts are waiting for a person, from the best source there is.
   *
   * [pending] is the agent's own list of prompts it is holding for the phone -- a fact. [heuristic]
   * is the transcript guess (`waiting_for_permission`) that predates it, used only when the list
   * cannot be had: an older agent, an unpaired phone, a Mac not answering, or the phone hook not
   * installed (the agent then never sees a prompt). Preferring the fact even when it says 0 is the
   * point: the guess over-counts sessions that stopped mid-prompt hours ago.
   */
  public fun claudeWaitingCount(pending: Int?, heuristic: Int): Int = pending ?: heuristic

  /**
   * Time left on a prompt before the Mac's own dialog takes it back: `1:42`, `0:05`, `expired`.
   *
   * Rounded UP to the second, so the last second reads `0:01` rather than a `0:00` that is still
   * answerable. An unreadable deadline ([expiresAtMs] 0) is `expired`: counting down from a time
   * the agent never gave would be an invention, and the Approve button still tells the truth (the
   * agent answers 404 if it is gone).
   */
  public fun timeLeft(expiresAtMs: Long, nowMs: Long): String {
    if (expiresAtMs <= 0L) return "expired"
    val left = expiresAtMs - nowMs
    if (left <= 0L) return "expired"
    val seconds = (left + MS_PER_SECOND - 1) / MS_PER_SECOND
    return String.format(
        Locale.ROOT, "%d:%02d", seconds / SECONDS_PER_MINUTE, seconds % SECONDS_PER_MINUTE)
  }

  /** The amber tag on Home's Claude row: `2 waiting` (the Tag draws it upper case). */
  public fun claudeWaitingTag(count: Int): String = "$count waiting"

  /** The subtitle under it: `1 waiting for you`. */
  public fun claudeWaitingLine(count: Int): String = "$count waiting for you"

  /**
   * The event-stream line for one answer: `claude · allowed Bash in vitruvian-core`. The command
   * itself is left out on purpose, as the agent leaves it out of its own log: the stream is kept
   * and shown, and a command can carry a secret.
   */
  public fun claudeDecisionLog(allow: Boolean, tool: String, project: String): String {
    val verb = if (allow) "allowed" else "denied"
    val where = if (project.isBlank()) "" else " in $project"
    return "claude · $verb ${tool.ifBlank { "a tool" }}$where"
  }

  /**
   * The agent's hold time in words: `2 min`, `90 s`. Unknown (0, not asked yet) is the contract's
   * default of two minutes, which is what an agent that has not said is running with.
   */
  public fun waitLabel(seconds: Int): String {
    val s = if (seconds > 0) seconds else DEFAULT_WAIT_SECONDS
    return if (s % SECONDS_PER_MINUTE.toInt() == 0) "${s / SECONDS_PER_MINUTE.toInt()} min"
    else "$s s"
  }

  /**
   * The line under the "Answer Claude prompts on this phone" toggle.
   *
   * Off, it says exactly what turning it on will do and to which file, because it changes Claude
   * Code's configuration on the Mac and the person should not have to open the dialog to find out.
   * On, it says how to undo it.
   */
  public fun claudeHookExplanation(enabled: Boolean, host: String, waitSeconds: Int): String =
      if (enabled) "Hook installed. Turn off to remove it. $CLAUDE_HOOK_REACH"
      else
          "Adds a hook to Claude Code on ${host.ifBlank { "the Mac" }} " +
              "($CLAUDE_SETTINGS_FILE, a backup is kept). Prompts then come here first; " +
              "unanswered for ${waitLabel(waitSeconds)}, they show on the Mac as usual. " +
              CLAUDE_HOOK_REACH

  /**
   * Which sessions the hook can see, said up front.
   *
   * Claude Code reads hooks when a session starts, so sessions already open when the switch is
   * turned on keep asking on the Mac only; that is what made the first try look broken. Verified on
   * the Mac for both kinds of session started afterwards: a terminal session, and one launched the
   * way the Claude desktop app launches it (stream-json over stdio, the app answering permission
   * requests) -- the prompt reached the phone and a Deny there stopped the command. A session in
   * bypass-permissions mode never asks anyone, so there is nothing to route.
   */
  public const val CLAUDE_HOOK_REACH: String =
      "Applies to Claude Code sessions started after this is on, in the terminal or the Claude " +
          "desktop app; sessions already open keep asking on the Mac."

  /** The confirmation before installing: the file, the reach (every session), the fallback. */
  public fun claudeHookDialogBody(host: String, waitSeconds: Int): String =
      "Adds a permission hook to $CLAUDE_SETTINGS_FILE on ${host.ifBlank { "the Mac" }}, " +
          "for every Claude Code session there; a backup of the file is kept. Prompts then come " +
          "to this phone first. Unanswered for ${waitLabel(waitSeconds)}, they show on the Mac " +
          "as usual, so nothing is lost. Turn it off here to remove the hook."

  /** The toggle's label while a change is on its way to the Mac. */
  public fun claudeHookBusyLabel(installing: Boolean): String =
      if (installing) "installing…" else "removing…"

  private const val CLAUDE_SETTINGS_FILE = "~/.claude/settings.json"
  private const val DEFAULT_WAIT_SECONDS = 120
  private const val MS_PER_SECOND = 1000L
  private const val SECONDS_PER_MINUTE = 60L

  // --- pull requests, as a row ------------------------------------------

  /**
   * `vitruvian-core#2514 · Fix the thing` -- the repository without its owner.
   *
   * Every PR in this list is the user's own, so the owner is the same 19 characters on every row,
   * and on a folded phone they were the only characters of the title that fitted.
   */
  public fun prTitle(repo: String, number: Int, title: String): String {
    val short = repo.substringAfterLast('/').ifBlank { repo }
    return "$short#$number · $title"
  }

  // --- containers ---------------------------------------------------------

  /**
   * A row of the container list: one container, or one Kubernetes pod's worth of them.
   *
   * [members] keeps the originals so the caller can still show an image or a status.
   */
  public data class ContainerGroup<T>(val title: String, val pod: Boolean, val members: List<T>)

  /**
   * The containers worth a row.
   *
   * On a Mac running K3s or Rancher Desktop on dockerd, `docker ps` lists every pod as its `pause`
   * sandbox plus one container per workload, named `k8s_<container>_<pod>_<ns>_<uid>_<n>`.
   * Twenty-four rows of that -- half of them `rancher/mirrored-pause` -- buried the containers
   * anyone started by hand. So pause sandboxes are dropped (plumbing, not workloads), the rest of a
   * pod collapses into one row named for the pod, and anything not named `k8s_` is left exactly as
   * Docker reported it, in Docker's order.
   */
  public fun <T> groupContainers(
      items: List<T>,
      name: (T) -> String,
      image: (T) -> String,
  ): List<ContainerGroup<T>> {
    val rows = mutableListOf<Pair<String?, MutableList<T>>>()
    val podRows = HashMap<String, MutableList<T>>()
    items.forEach { item ->
      if (isPauseContainer(name(item), image(item))) return@forEach
      val pod = k8sPod(name(item))
      if (pod == null) {
        rows += null to mutableListOf(item)
        return@forEach
      }
      // The pod keeps the position of its first container, so the list does
      // not reorder itself when a second one appears.
      val members = podRows[pod]
      if (members != null) {
        members += item
      } else {
        val fresh = mutableListOf(item)
        podRows[pod] = fresh
        rows += pod to fresh
      }
    }
    return rows.map { (pod, members) ->
      if (pod == null) ContainerGroup(name(members.single()), pod = false, members = members)
      else {
        val n = members.size
        ContainerGroup("$pod · $n container${if (n == 1) "" else "s"}", pod = true, members)
      }
    }
  }

  /** How many of [items] [groupContainers] drops as pause sandboxes. */
  public fun <T> pauseCount(items: List<T>, name: (T) -> String, image: (T) -> String): Int =
      items.count { isPauseContainer(name(it), image(it)) }

  /**
   * A pod sandbox. cri-dockerd names it `k8s_POD_...` and its image is some registry's `pause`
   * (`rancher/mirrored-pause`, `registry.k8s.io/pause`); either is enough.
   */
  public fun isPauseContainer(name: String, image: String): Boolean {
    if (name.startsWith("k8s_POD_")) return true
    val repo = image.substringBefore('@').substringBeforeLast(':').substringAfterLast('/')
    return repo == "pause" || repo.endsWith("-pause")
  }

  /**
   * The pod in `k8s_<container>_<pod>_<namespace>_<uid>_<attempt>`, or null for anything else.
   *
   * Container and pod names are DNS labels and cannot contain `_`, so splitting on it is exact.
   */
  public fun k8sPod(name: String): String? {
    if (!name.startsWith("k8s_")) return null
    val parts = name.split('_')
    if (parts.size < K8S_NAME_PARTS) return null
    return parts[2].ifBlank { null }
  }

  private const val K8S_NAME_PARTS = 4

  /** How many container rows the Mac screen shows before "Show all". */
  public const val CONTAINER_ROWS: Int = 8

  /** `0`, `6.4`, `31.6` -- `Format.decimal`'s shape; this library cannot depend on :format. */
  private fun decimal(value: Double): String {
    val rounded = Math.round(value * 10) / 10.0
    return String.format(Locale.ROOT, "%.1f", rounded).removeSuffix(".0")
  }
}
