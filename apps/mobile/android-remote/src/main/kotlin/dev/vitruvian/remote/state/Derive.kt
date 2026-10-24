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

  // --- module row layout --------------------------------------------------

  /**
   * Where a module row's one control goes. A row with a single control draws it in the row's own
   * trailing slot; only a row with several (a switch plus steppers, a dropdown plus a button) still
   * gets a line under it. Each of these was a second 44 dp line holding one button.
   */
  public enum class RowControl {
    /** Nothing to press, or the row's onSelect. */
    None,
    /** A switch in the trailing slot; tapping the row flips it. */
    InlineToggle,
    /** The choices dropdown in the trailing slot, in place of the value it would repeat. */
    InlineDropdown,
    /** The Set / Edit / Replace button in the trailing slot; tapping the row opens the prompt. */
    InlinePrompt,
    /** The one action button in the trailing slot. */
    InlineAction,
    /** More than one control: they go under the row (a switch, if any, still sits inline). */
    Stacked,
  }

  public fun rowControl(
      hasToggle: Boolean,
      actionCount: Int,
      choiceCount: Int,
      hasPrompt: Boolean,
  ): RowControl {
    val controls =
        (if (hasToggle) 1 else 0) +
            actionCount +
            (if (choiceCount > 0) 1 else 0) +
            (if (hasPrompt) 1 else 0)
    return when {
      controls == 0 -> RowControl.None
      controls > 1 -> RowControl.Stacked
      hasToggle -> RowControl.InlineToggle
      choiceCount > 0 -> RowControl.InlineDropdown
      hasPrompt -> RowControl.InlinePrompt
      else -> RowControl.InlineAction
    }
  }

  /**
   * The text beside a row's switch: blank when it would only say what the switch already shows
   * ("on", "off"), the value itself when it adds something ("60%", "running", "muted").
   */
  public fun toggleTrailing(trailing: String): String =
      if (trailing.trim().lowercase(Locale.ROOT) in setOf("on", "off")) "" else trailing

  /**
   * The button on a text-prompt row. Keyed on whether a value is saved, not on the row's trailing
   * text: that reads "missing" or "none" when empty, so testing it for blank made every empty
   * secret say Replace….
   */
  public fun promptButtonLabel(secret: Boolean, hasValue: Boolean): String =
      when {
        !hasValue -> "Set…"
        secret -> "Replace…"
        else -> "Edit…"
      }

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
   *
   * [speakHome] / [speakLocal] / [speakPhone] are the three outputs (agent v1.8+ / v1.12+; an older
   * agent means home only). The Google sign-in only matters when the home speakers are used: a Mac
   * or phone speaking on its own needs no Google at all. All off is "no outputs" -- enabled, and
   * still nothing will be said.
   */
  public fun homeSpeakerStatus(
      available: Boolean,
      installed: Boolean,
      signedIn: Boolean,
      enabled: Boolean,
      appRunning: Boolean,
      speakHome: Boolean = true,
      speakLocal: Boolean = false,
      speakPhone: Boolean = false,
  ): String =
      when {
        !available && !installed -> "not installed"
        !available -> "not set up"
        speakHome && !signedIn -> "not signed in"
        !enabled -> "off"
        !speakHome && !speakLocal && !speakPhone -> "no outputs"
        !appRunning -> "on · app closed"
        else -> "on"
      }

  /** What "This Mac" is called wherever an output is named. */
  public const val THIS_MAC: String = "This Mac"

  /** What "This phone" is called wherever an output is named. */
  public const val THIS_PHONE: String = "This phone"

  /**
   * Android `AudioDeviceInfo.TYPE_*` constants that count as headphones or personal audio outputs
   * for `phone_headphones_only`: wired headset (3), wired headphones (4), Bluetooth SCO (7),
   * Bluetooth A2DP (8 — note Android reports A2DP headphones and speakers with the same type), USB
   * headset (22), hearing aid (23), BLE headset (26). BLE speakers (27) and broadcast (30) are
   * excluded.
   */
  private val HEADPHONE_DEVICE_TYPES: Set<Int> = setOf(3, 4, 7, 8, 22, 23, 26)

  /** True when an `AudioDeviceInfo.type` integer represents wired, USB, or Bluetooth headphones. */
  public fun isHeadphoneDeviceType(type: Int): Boolean = type in HEADPHONE_DEVICE_TYPES

  /**
   * Where an announcement will be spoken, in one line: "Lake Office display + This Mac", "This Mac
   * only", "This phone only", or the warning when all outputs are off. [speaker] is the selected
   * home speaker's name, null when none is picked.
   */
  public fun homeSpeakerOutputs(
      speakHome: Boolean,
      speakLocal: Boolean,
      speaker: String?,
      speakPhone: Boolean = false,
  ): String {
    val home = speaker?.takeIf { it.isNotBlank() } ?: "no speaker"
    val parts = buildList {
      if (speakHome) add(home)
      if (speakLocal) add(THIS_MAC)
      if (speakPhone) add(THIS_PHONE)
    }
    return when {
      parts.isEmpty() -> NO_OUTPUTS
      parts.size == 1 && !speakHome -> "${parts.single()} only"
      else -> parts.joinToString(" + ")
    }
  }

  /** All outputs off. Shown in amber: the switches stay as the user left them. */
  public const val NO_OUTPUTS: String = "No outputs — nothing will be spoken"

  /**
   * The Mac's voice as the "This Mac" row's sub-line. For Apple's engine, the agent sends a name
   * ("Aaron") and an empty one falls back to the identifier; for Gemini TTS, it names the prebuilt
   * Gemini voice and notes when the Mac still needs a Gemini API key in secrets.json.
   */
  public fun macVoiceLabel(
      name: String,
      id: String,
      localEngine: String = "apple",
      geminiVoice: String = "Kore",
      hasGeminiKey: Boolean = true,
  ): String =
      if (localEngine.equals("gemini", ignoreCase = true)) {
        val voice = geminiVoice.ifBlank { "Kore" }
        if (!hasGeminiKey) "Voice: Gemini ($voice) · needs API key on Mac"
        else "Voice: Gemini ($voice)"
      } else {
        "Voice: ${name.ifBlank { id }.ifBlank { "the Mac's default" }}"
      }

  /**
   * The phone's voice as the "This phone" row's sub-line: uses Gemini TTS when the Mac has Gemini
   * TTS selected with a key, otherwise Android TTS on the phone.
   */
  public fun phoneVoiceLabel(
      localEngine: String,
      geminiVoice: String,
      hasGeminiKey: Boolean,
      phoneConnected: Boolean,
      headphonesOnly: Boolean = false,
  ): String {
    val voice =
        if (localEngine.equals("gemini", ignoreCase = true) && hasGeminiKey) {
          "Voice: Gemini (${geminiVoice.ifBlank { "Kore" }})"
        } else {
          "Voice: Android TTS"
        }
    return buildList {
          add(voice)
          if (headphonesOnly) add("headphones only")
          if (!phoneConnected) add("link Phone Bridge to receive audio")
        }
        .joinToString(" · ")
  }

  /** The two local speech engines HomeSpeaker's `local_engine` accepts. */
  public val localEngines: List<String> = listOf("apple", "gemini")

  public fun localEngineLabel(engine: String): String =
      when (engine.lowercase(Locale.ROOT)) {
        "gemini" -> "Gemini TTS"
        else -> "Apple (on Mac)"
      }

  /** The built-in Gemini TTS voices HomeSpeaker's `gemini_voice` accepts. */
  public val geminiVoices: List<String> =
      listOf(
          "Kore",
          "Puck",
          "Aoede",
          "Charon",
          "Zephyr",
          "Fenrir",
          "Leda",
          "Orus",
          "voice_vaoo7ayczx69",
      )

  /**
   * The person-facing name of a `gemini_voice`: a cloned voice's name, the built-in Freeman custom
   * voice, else the id itself (the prebuilt voices are their own names).
   */
  public fun geminiVoiceDisplayName(voiceId: String, customVoices: List<AgentCustomVoice>): String =
      customVoices.firstOrNull { it.id == voiceId }?.name
          ?: if (voiceId == "voice_vaoo7ayczx69") "Freeman" else voiceId

  /**
   * The announcement rewrite styles HomeSpeaker's `announcement_style` accepts. `custom` uses the
   * instruction written on the Mac (`custom_style_prompt`).
   */
  public val announcementStyles: List<String> =
      listOf("verbatim", "plain", "briefing", "casual", "custom")

  public fun announcementStyleLabel(style: String): String =
      when (style.lowercase(Locale.ROOT)) {
        "plain" -> "Plain spoken"
        "briefing" -> "Warm briefing"
        "casual" -> "Casual"
        "custom" -> "Custom"
        else -> "Verbatim"
      }

  /** The two rewrite models HomeSpeaker's `style_model` accepts. */
  public val styleModels: List<String> = listOf("apple", "gemini")

  public fun styleModelLabel(model: String): String =
      when (model.lowercase(Locale.ROOT)) {
        "gemini" -> "Gemini Flash"
        else -> "Apple (on Mac)"
      }

  // --- HomeSpeaker progressive disclosure ---------------------------------
  // The HomeSpeaker plate shows a setting only when it can change what is heard. Each rule lives
  // here, not in RemoteState, so a JVM test pins it.

  /**
   * Whether the home-speaker settings (which speaker, its volume, announce volume) matter. Null is
   * an agent too old to switch outputs, where the home speaker is always the output.
   */
  public fun homeSettingsRelevant(speakHome: Boolean?): Boolean = speakHome != false

  /**
   * "Cast selected voice" only means something when the home speaker is on and Gemini is chosen.
   */
  public fun castVoiceRelevant(speakHome: Boolean?, localEngine: String): Boolean =
      speakHome == true && localEngine == "gemini"

  /**
   * Whether any output speaks with the local engine (and so its Gemini voice): this Mac, this
   * phone, or the home speaker (when casting that voice or when switching local engine to reveal
   * casting). Matches Models.swift:467-470 showsVoiceEngine.
   */
  public fun localVoiceInUse(
      speakLocal: Boolean,
      speakPhone: Boolean?,
      speakHome: Boolean?,
      homeCastVoice: Boolean = false,
  ): Boolean = speakLocal || speakPhone == true || speakHome == true

  /** The 48 half-hour slots for quiet hours dropdowns ("00:00" to "23:30"). */
  public val quietHoursSlots: List<String> =
      (0..23).flatMap { h ->
        listOf(String.format(Locale.ROOT, "%02d:00", h), String.format(Locale.ROOT, "%02d:30", h))
      }

  /**
   * Choices for quiet hours start/end times, including all 48 half-hour slots plus [current]
   * preserved if it is an off-step time (e.g. "07:15").
   */
  public fun quietHoursChoices(current: String): List<String> {
    val clean = current.trim()
    if (clean.isBlank() || clean in quietHoursSlots) {
      return quietHoursSlots
    }
    return (quietHoursSlots + clean).sorted()
  }

  /** Subtitle for the Quiet hours row. */
  public fun quietHoursSubtitle(
      enabled: Boolean,
      active: Boolean,
      start: String,
      end: String,
  ): String =
      when {
        !enabled -> "off · plays at any hour"
        active -> "active until $end · what you type still plays"
        else -> "quiet from $start to $end"
      }

  /** Volume dropdown choices from 0% to 100% in 10% steps. */
  public val volumePercentChoices: List<Int> = (0..100 step 10).toList()

  /** Announcement volume dropdown choices from 10% to 100% in 10% steps. */
  public val announceVolumePercentChoices: List<Int> = (10..100 step 10).toList()

  /** Choices for announcement volume dropdown including current value if off-step. */
  public fun announceVolumeChoices(current: Int): List<Int> {
    if (current in announceVolumePercentChoices || current < 0 || current > 100) {
      return announceVolumePercentChoices
    }
    return (announceVolumePercentChoices + current).sorted()
  }

  /** Media pause extra margin choices (0 s to 10 s in 1 s steps). */
  public val pauseMarginSecondChoices: List<Double> = (0..10).map { it.toDouble() }

  /** Poll interval choices for chat monitoring (10s, 15s, 30s, 60s, 120s, 300s). */
  public val pollIntervalChoices: List<Int> = listOf(10, 15, 30, 60, 120, 300)

  public fun pollIntervalLabel(seconds: Int): String =
      if (seconds >= 60 && seconds % 60 == 0) "${seconds / 60} min" else "$seconds s"

  public val googleChatSources: List<String> = listOf("auto", "api", "gws")

  public fun googleChatSourceLabel(source: String): String =
      when (source.lowercase(Locale.ROOT)) {
        "api" -> "Google API"
        "gws" -> "gws CLI"
        else -> "Automatic"
      }

  public fun agentHookStatusLabel(
      hookState: String,
      speaksTwice: Boolean,
      configuredByInstruction: Boolean,
  ): String =
      when {
        speaksTwice -> "warning: hook + skill installed (speaks twice)"
        hookState == "installed" -> "Stop hook installed"
        hookState == "stale" -> "Stop hook outdated"
        configuredByInstruction -> "Instruction configured in prompt"
        else -> "Not installed"
      }

  /**
   * True only when every coding agent is known to be off: the phrasing settings then shape nothing.
   * A null switch (an older agent) is not "off".
   */
  public fun allCodingAgentsOff(
      claudeCode: Boolean?,
      antigravity: Boolean?,
      openCode: Boolean?,
  ): Boolean = claudeCode == false && antigravity == false && openCode == false

  /** How a speaker target reads in the Speaker dropdown. */
  public fun speakerChoiceLabel(name: String, room: String, type: String): String =
      if (type == "Structure") "$name (all rooms)" else "$room · $name"

  /** The two Beeper announcement filter modes HomeSpeaker's `beeper_announce` accepts. */
  public val beeperAnnounceModes: List<String> = listOf("direct_and_mentions", "all")

  public fun beeperAnnounceLabel(mode: String): String =
      when (mode.lowercase(Locale.ROOT)) {
        "all" -> "All messages"
        else -> "Direct & mentions"
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
      speakHome: Boolean = true,
      speakLocal: Boolean = false,
      speakPhone: Boolean = false,
  ): SpeakerHealth =
      when {
        !available || !installed -> SpeakerHealth.Problem
        speakHome && !signedIn -> SpeakerHealth.Problem
        !enabled -> SpeakerHealth.Off
        !speakHome && !speakLocal && !speakPhone -> SpeakerHealth.Problem
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

  // --- Antigravity parity (API v1.7) -----------------------------------------

  /** How a session row looks, from the agent's state word. Shared by Claude and Antigravity. */
  public enum class SessionLook {
    Waiting,
    Working,
    Idle,
    Other,
  }

  /** [claudeStateLabel]'s word, as a look: `killed`, `unknown` and anything new are [Other]. */
  public fun sessionLook(state: String): SessionLook =
      when (claudeStateLabel(state)) {
        "waiting" -> SessionLook.Waiting
        "working" -> SessionLook.Working
        "idle" -> SessionLook.Idle
        else -> SessionLook.Other
      }

  /**
   * The Antigravity dashboard's summary: the version and models it always showed, and the session
   * count once an agent that has them answers.
   */
  public fun antigravitySummary(version: String, models: Int, sessions: Int?): String =
      listOfNotNull(
              "v$version",
              "$models model${if (models == 1) "" else "s"}",
              sessions?.let { "$it session${if (it == 1) "" else "s"}" },
          )
          .joinToString(" · ")

  /** The prompt box's placeholder: which conversation Send continues, or that it starts one. */
  public fun antigravityPlaceholder(selectedTitle: String?): String =
      if (selectedTitle.isNullOrBlank()) "New conversation…" else "Continue \"$selectedTitle\"…"

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

  // --- Sony Google TV -----------------------------------------------------

  /** Status label for the Sony TV module header and tags. */
  public fun tvStatus(
      available: Boolean,
      connected: Boolean,
      awake: Boolean,
      dreaming: Boolean,
  ): String =
      when {
        !available -> "no adb"
        !connected -> "disconnected"
        dreaming -> "dreaming"
        awake -> "awake"
        else -> "standby"
      }

  /** `0`, `6.4`, `31.6` -- `Format.decimal`'s shape; this library cannot depend on :format. */
  private fun decimal(value: Double): String {
    val rounded = Math.round(value * 10) / 10.0
    return String.format(Locale.ROOT, "%.1f", rounded).removeSuffix(".0")
  }
}
