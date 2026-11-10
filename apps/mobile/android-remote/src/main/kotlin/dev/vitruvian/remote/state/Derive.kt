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

import java.time.Instant
import java.time.OffsetDateTime
import java.time.ZoneId
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
          "voice_o1be80ujj8bb",
      )

  /**
   * The person-facing name of a `gemini_voice`: a cloned voice's name, a built-in custom voice
   * (`Freeman`, `James`), else the id itself (the prebuilt voices are their own names).
   */
  public fun geminiVoiceDisplayName(voiceId: String, customVoices: List<AgentCustomVoice>): String =
      customVoices.firstOrNull { it.id == voiceId }?.name
          ?: when (voiceId) {
            "voice_vaoo7ayczx69" -> "Freeman"
            "voice_o1be80ujj8bb" -> "James"
            else -> voiceId
          }

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

  /**
   * Whether any active output actually synthesizes with the local voice engine: This Mac, This
   * phone, or Google Home when casting the selected voice. Matches Models.swift `usesVoiceEngine`.
   */
  public fun usesVoiceEngine(
      speakLocal: Boolean,
      speakPhone: Boolean?,
      speakHome: Boolean?,
      homeCastVoice: Boolean = false,
  ): Boolean = speakLocal || speakPhone == true || (speakHome == true && homeCastVoice)

  /**
   * Whether the Mac voice picker is shown: whenever This Mac is enabled (labelled "Fallback Mac
   * voice" when Gemini TTS is the engine, and "Mac voice" otherwise). Matches SettingsView.swift
   * (`if configManager.config.effectiveSpeakLocal`).
   */
  public fun showsMacVoice(speakLocal: Boolean, localEngine: String = ""): Boolean = speakLocal

  /**
   * Whether Gemini TTS is actively used by an output, so the Gemini voice picker and Gemini API key
   * appear in the Speakers section. Matches Models.swift `showsGeminiVoice` / `geminiSpeaks`.
   */
  public fun geminiSpeaks(
      speakLocal: Boolean,
      speakPhone: Boolean?,
      speakHome: Boolean?,
      homeCastVoice: Boolean = false,
      localEngine: String,
  ): Boolean =
      usesVoiceEngine(speakLocal, speakPhone, speakHome, homeCastVoice) &&
          localEngine.equals("gemini", ignoreCase = true)

  /**
   * Whether the Gemini API key row appears under Style model: when at least one coding agent is on,
   * the style is not verbatim, the rewrite model is Gemini, and the key is not already shown under
   * the Speakers section (`!geminiSpeaks`). Matches SettingsView.swift:511-525.
   */
  public fun showsStyleGeminiKey(
      allCodingAgentsOff: Boolean,
      announcementStyle: String,
      styleModel: String,
      geminiSpeaks: Boolean,
  ): Boolean =
      !allCodingAgentsOff &&
          !announcementStyle.equals("verbatim", ignoreCase = true) &&
          styleModel.equals("gemini", ignoreCase = true) &&
          !geminiSpeaks

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

  /** Sub-line for the Quiet hours top metric card on the HomeSpeaker dashboard. */
  public fun quietHoursMetricSub(
      enabled: Boolean,
      active: Boolean,
      start: String,
  ): String =
      when {
        !enabled -> "always speaks"
        active -> "quiet now"
        else -> "quiet from ${start.ifBlank { HomeSpeakerWire.DEFAULT_QUIET_START }}"
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

  /** Coding agents HomeSpeaker installs a hook for (Swift `CodingAgent.supportsHook`). */
  public val hookAgentSlugs: Set<String> = setOf("claude-code", "antigravity", "opencode")

  public val googleChatSources: List<String> = listOf("auto", "api", "gws")

  public fun googleChatSourceLabel(source: String): String =
      when (source.lowercase(Locale.ROOT)) {
        "api" -> "Google API"
        "gws" -> "gws CLI"
        else -> "Automatic"
      }

  /** Subtitle for the Chat monitor row, surfacing the last poll relative time when running. */
  public fun chatMonitorSubtitle(running: Boolean, lastPollRelative: String = ""): String =
      when {
        running && lastPollRelative.isNotBlank() ->
            "Monitoring chat apps · last checked $lastPollRelative"
        running -> "Monitoring chat apps in background"
        else -> "Stopped · background monitor is not running"
      }

  /** Trimmed runtime error from the chat monitor, or null when healthy. */
  public fun chatDiagnosticError(runtimeError: String): String? =
      runtimeError.trim().takeIf { it.isNotEmpty() }

  /** Subtitle for the Slack token row, surfacing the signed-in Slack identity when known. */
  public fun slackTokenSubtitle(hasToken: Boolean, slackIdentity: String = ""): String {
    if (!hasToken) return "Tap to paste user token (xoxp-...)"
    val user = slackIdentity.trim()
    return if (user.isNotEmpty()) "Token saved on Mac · signed in as $user"
    else "Token saved on Mac"
  }

  /** Pure specification for a row in the HomeSpeaker "Google Cloud OAuth" section. */
  public data class OAuthRowSpec(
      val title: String,
      val subtitle: String,
      val trailing: String,
      val healthy: Boolean,
      val hasValue: Boolean,
      val enabled: Boolean,
  )

  /**
   * Builds the Client ID and Client Secret row specs for the Google Cloud OAuth section.
   *
   * Always shown so first-time setup is reachable from the phone. When empty, the Client ID row
   * reads "Not set · needed for Google Chat" and the Secret row reads "Not set" and stays disabled
   * until a client ID exists.
   */
  public fun oauthSectionRows(clientId: String, hasSecret: Boolean): List<OAuthRowSpec> {
    val id = clientId.trim()
    val hasClientId = id.isNotEmpty()
    return listOf(
        OAuthRowSpec(
            title = "OAuth Client ID",
            subtitle = id.ifEmpty { "Not set · needed for Google Chat" },
            trailing = if (hasClientId) "configured" else "none",
            healthy = hasClientId,
            hasValue = hasClientId,
            enabled = true,
        ),
        OAuthRowSpec(
            title = "OAuth Client Secret",
            subtitle =
                when {
                  hasSecret -> "Client secret saved on Mac"
                  hasClientId -> "Tap to paste client secret"
                  else -> "Not set"
                },
            trailing = if (hasSecret) "saved" else "missing",
            healthy = hasSecret,
            hasValue = hasSecret,
            enabled = hasClientId || hasSecret,
        ),
    )
  }

  /** Subtitle for the Google Chat source row, showing the active backend when running. */
  public fun googleChatSourceSubtitle(
      activeBackend: String,
      monitorRunning: Boolean,
  ): String {
    val via =
        when (activeBackend.trim().lowercase(Locale.ROOT)) {
          "api" -> "the Google API"
          "gws" -> "gws CLI"
          else -> ""
        }
    return if (monitorRunning && via.isNotEmpty()) {
      "currently reading via $via"
    } else {
      "which backend reads Google Chat"
    }
  }

  /** Signed-in Google Chat account and backend readiness diagnostic. */
  public data class GoogleChatAccountDiag(
      val account: String,
      val subtitle: String,
      val trailing: String,
      val healthy: Boolean,
  )

  /**
   * Derives the Google Chat account and access status row from the fields reported by
   * `/v1/homespeaker`.
   */
  public fun googleChatAccountDiag(
      source: String,
      activeBackend: String,
      accountEmail: String,
      gwsAccount: String,
      hasChatAccess: Boolean,
      gwsInstalled: Boolean,
  ): GoogleChatAccountDiag {
    val effectiveSource =
        activeBackend.trim().lowercase(Locale.ROOT).takeIf { it == "api" || it == "gws" }
            ?: source.trim().lowercase(Locale.ROOT)
    val apiEmail = accountEmail.trim()
    val cliEmail = gwsAccount.trim()
    val email =
        when (effectiveSource) {
          "gws" -> cliEmail.ifEmpty { apiEmail }
          "api" -> apiEmail.ifEmpty { cliEmail }
          else -> apiEmail.ifEmpty { cliEmail }
        }
    return when (effectiveSource) {
      "gws" ->
          if (!gwsInstalled) {
            GoogleChatAccountDiag(
                account = email,
                subtitle =
                    if (email.isNotEmpty()) "$email · gws CLI not installed on Mac"
                    else "gws CLI not installed on Mac",
                trailing = "no gws",
                healthy = false,
            )
          } else if (email.isNotEmpty()) {
            GoogleChatAccountDiag(
                account = email,
                subtitle = "$email · via gws CLI",
                trailing = "gws",
                healthy = true,
            )
          } else {
            GoogleChatAccountDiag(
                account = "",
                subtitle = "gws CLI installed · default account",
                trailing = "gws",
                healthy = true,
            )
          }
      "api" ->
          if (!hasChatAccess) {
            GoogleChatAccountDiag(
                account = email,
                subtitle =
                    if (email.isNotEmpty()) "$email · Chat access not granted on Mac"
                    else "Chat access not granted on Mac",
                trailing = "no access",
                healthy = false,
            )
          } else if (email.isNotEmpty()) {
            GoogleChatAccountDiag(
                account = email,
                subtitle = "$email · Chat access granted",
                trailing = "signed in",
                healthy = true,
            )
          } else {
            GoogleChatAccountDiag(
                account = "",
                subtitle = "Chat access granted on Mac",
                trailing = "signed in",
                healthy = true,
            )
          }
      else ->
          when {
            hasChatAccess && email.isNotEmpty() ->
                GoogleChatAccountDiag(
                    account = email,
                    subtitle = "$email · Chat access granted",
                    trailing = "signed in",
                    healthy = true,
                )
            gwsInstalled && email.isNotEmpty() ->
                GoogleChatAccountDiag(
                    account = email,
                    subtitle = "$email · via gws CLI",
                    trailing = "gws",
                    healthy = true,
                )
            hasChatAccess ->
                GoogleChatAccountDiag(
                    account = "",
                    subtitle = "Chat access granted on Mac",
                    trailing = "signed in",
                    healthy = true,
                )
            gwsInstalled ->
                GoogleChatAccountDiag(
                    account = "",
                    subtitle = "gws CLI installed · default account",
                    trailing = "gws",
                    healthy = true,
                )
            email.isNotEmpty() ->
                GoogleChatAccountDiag(
                    account = email,
                    subtitle = "$email · Chat access or gws CLI needed on Mac",
                    trailing = "not ready",
                    healthy = false,
                )
            else ->
                GoogleChatAccountDiag(
                    account = "",
                    subtitle = "grant Chat access or install gws CLI on Mac",
                    trailing = "not set up",
                    healthy = false,
                )
          }
    }
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

  /** What a chat-app network's switch does on the phone. */
  public enum class NetworkSwitch {
    /** On reads it, off mutes it. */
    Mute,

    /**
     * Courier only: a network HomeSpeaker's own Slack or Google Chat reader covers. On reads it
     * through Courier as well (`courier_read_anyway`); off leaves it to that reader.
     */
    ReadAnyway,

    /** No switch: Beeper's networks that HomeSpeaker reads itself. */
    None,
  }

  /** One Beeper or Courier network as a row on the phone. */
  public data class ChatNetworkRow(
      val title: String,
      val subtitle: String,
      val trailing: String,
      val on: Boolean,
      val switch: NetworkSwitch,
  )

  /**
   * [network] of chat app [app] ("Beeper" or "Courier") as HomeSpeaker's Settings shows it. A
   * network HomeSpeaker reads itself is greyed for Beeper; for Courier its switch reads it through
   * Courier as well, since Courier cannot say which Slack workspace an account is.
   */
  public fun chatNetworkRow(app: String, network: AgentBeeperNetwork): ChatNetworkRow {
    val title = "$app · ${network.name}"
    val skipped = network.state == "skipped"
    if (app == "Courier" && (skipped || network.readAnyway)) {
      return if (network.readAnyway) {
        ChatNetworkRow(
            title,
            "read through Courier as well as directly",
            "also here",
            on = true,
            switch = NetworkSwitch.ReadAnyway)
      } else {
        ChatNetworkRow(
            title,
            "read directly by HomeSpeaker · on reads it through Courier too",
            "read directly",
            on = false,
            switch = NetworkSwitch.ReadAnyway)
      }
    }
    return when {
      skipped ->
          ChatNetworkRow(
              title, "covered by its own chat toggle", "skipped", on = false, NetworkSwitch.None)
      network.state == "reading" ->
          ChatNetworkRow(
              title, "messages on this network are read aloud", "on", on = true, NetworkSwitch.Mute)
      else -> ChatNetworkRow(title, "muted in $app", "muted", on = false, NetworkSwitch.Mute)
    }
  }

  /**
   * Under an app's networks before the running monitor has listed them, in HomeSpeaker's words.
   * Null when it has, or when an older agent cannot say ([listed] null).
   */
  public fun networksLaterLine(app: String, listed: Boolean?): String? =
      if (listed == false) "Other networks show here once $app is being read." else null

  /**
   * Where Courier's token comes from. The phone never carries it: it is pasted into HomeSpeaker on
   * the Mac, where Courier runs.
   */
  public val courierTokenSteps: String =
      "In Courier: Settings › Integrations › New connection…, then paste the token into HomeSpeaker on your Mac"

  /** Courier stays off until a token is saved, as in HomeSpeaker's own Settings. */
  public fun courierSwitchEnabled(hasToken: Boolean, on: Boolean): Boolean = hasToken || on

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

  /** Pure specification for one button in HomeSpeaker's top "Now" strip. */
  public data class QuickActionSpec(
      val id: String,
      val label: String,
      val secondary: String?,
      val enabled: Boolean,
      val active: Boolean,
      val contentDescription: String,
  )

  /**
   * The Mute / Unmute control in HomeSpeaker's Now strip.
   *
   * Label names the action tapping will take ("Mute" when unmuted, "Unmute" when muted). Enabled
   * whenever the speaker volume is available and online (and not mid-request), regardless of
   * whether Google Home speaking is currently toggled on.
   */
  public fun muteQuickAction(
      paired: Boolean,
      volumeAvailable: Boolean,
      volumeOnline: Boolean,
      muted: Boolean,
      percent: Int,
      busy: Boolean = false,
  ): QuickActionSpec {
    val ready = paired && volumeAvailable && volumeOnline && !busy
    val actionLabel = if (volumeAvailable && volumeOnline && muted) "Unmute" else "Mute"
    val sub =
        when {
          !volumeAvailable -> null
          busy -> "…"
          else -> speakerVolumeLabel(true, volumeOnline, muted, percent)
        }
    val desc =
        when {
          !volumeAvailable -> "Mute speaker, volume unavailable"
          !volumeOnline -> "Mute speaker, speaker offline"
          muted -> "Unmute speaker, currently muted"
          else -> "Mute speaker, volume ${percent.coerceIn(0, 100)}%"
        }
    return QuickActionSpec(
        id = "mute",
        label = actionLabel,
        secondary = sub,
        enabled = ready,
        active = volumeAvailable && volumeOnline && muted,
        contentDescription = desc,
    )
  }

  /**
   * The Quiet hours control in HomeSpeaker's Now strip.
   *
   * Label shows "Quiet on" / "Quiet off"; secondary text shows the window ("22:00–07:00") and
   * appends "now" when quiet hours are currently active, or is omitted when no Mac is available.
   */
  public fun quietHoursQuickAction(
      paired: Boolean,
      available: Boolean,
      enabled: Boolean,
      active: Boolean,
      start: String,
      end: String,
  ): QuickActionSpec {
    val label = if (enabled) "Quiet on" else "Quiet off"
    val window = if (!available) null else "${start.ifBlank { "22:00" }}–${end.ifBlank { "07:00" }}"
    val sub =
        when {
          window == null -> null
          enabled && active -> "$window · now"
          else -> window
        }
    val desc =
        when {
          window == null -> "Quiet hours: $label"
          enabled && active -> "Quiet hours: Quiet on, $window, active now"
          else -> "Quiet hours: $label, $window"
        }
    return QuickActionSpec(
        id = "quiet_hours",
        label = label,
        secondary = sub,
        enabled = paired && available,
        active = available && enabled,
        contentDescription = desc,
    )
  }

  /**
   * The Room control in HomeSpeaker's Now strip.
   *
   * Shows the current target speaker's name and opens the speaker picker on tap.
   */
  public fun roomQuickAction(
      paired: Boolean,
      available: Boolean,
      targetName: String,
      targetRoom: String = "",
      targetType: String = "",
      hasChoices: Boolean = true,
  ): QuickActionSpec {
    val name = targetName.trim()
    val label = name.ifEmpty { "Room" }
    val sub =
        when {
          !available || name.isEmpty() -> null
          targetRoom.isNotBlank() -> targetRoom
          targetType == "Structure" -> "all rooms"
          else -> "speaker"
        }
    val desc = if (sub == null) "Room speaker: none selected" else "Room speaker: $name, $sub"
    return QuickActionSpec(
        id = "room",
        label = label,
        secondary = sub,
        enabled = paired && available && hasChoices,
        active = available && name.isNotEmpty(),
        contentDescription = desc,
    )
  }

  /**
   * The Replay control in HomeSpeaker's Now strip.
   *
   * Replays the newest item from Recent broadcasts; disabled when there is nothing to replay.
   */
  public fun replayQuickAction(
      paired: Boolean,
      available: Boolean,
      installed: Boolean = true,
      hasReplay: Boolean,
      target: String? = null,
  ): QuickActionSpec {
    val ready = paired && available && installed && hasReplay
    // No helper line: the room name it used to show described nothing about
    // what would be replayed.
    val sub: String? = null
    val desc =
        if (hasReplay) "Replay last announcement" else "Replay last announcement, nothing to replay"
    return QuickActionSpec(
        id = "replay",
        label = "Replay",
        secondary = sub,
        enabled = ready,
        active = false,
        contentDescription = desc,
    )
  }

  /**
   * Now strip Snooze control:
   * - While not snoozed (or when `snoozeUntil` is missing, unparseable, or in the past): reads
   *   "Snooze 30m" with no secondary text and `active = false`.
   * - While snoozed (`snoozeUntil > nowMs`): reads "Snoozed" with secondary "until HH:mm" in phone
   *   local time (`zoneId`) and `active = true`.
   * - Disabled when offline (`!available`) or unpaired (`!paired`).
   */
  public fun snoozeQuickAction(
      paired: Boolean,
      available: Boolean,
      snoozeUntil: String? = null,
      nowMs: Long = System.currentTimeMillis(),
      zoneId: ZoneId = ZoneId.systemDefault(),
  ): QuickActionSpec {
    val raw = snoozeUntil?.trim().orEmpty()
    val instant =
        if (raw.isEmpty()) null
        else
            runCatching { OffsetDateTime.parse(raw).toInstant() }.getOrNull()
                ?: runCatching { Instant.parse(raw) }.getOrNull()
    val snoozed = available && instant != null && instant.toEpochMilli() > nowMs
    val untilTime =
        if (snoozed && instant != null) {
          val local = instant.atZone(zoneId)
          String.format(Locale.US, "%02d:%02d", local.hour, local.minute)
        } else null
    val label = if (snoozed) "Snoozed" else "Snooze 30m"
    val secondary = untilTime?.let { "until $it" }
    val desc =
        if (snoozed && untilTime != null) "Snoozed until $untilTime, tap to resume"
        else "Snooze announcements for 30 minutes"
    return QuickActionSpec(
        id = "snooze",
        label = label,
        secondary = secondary,
        enabled = paired && available,
        active = snoozed,
        contentDescription = desc,
    )
  }

  /**
   * Sentinel stored as the previously observed announcement id when HomeSpeaker is reachable and
   * has no latest announcement yet (`recent` and `last` both empty), so that the very next real
   * announcement triggers a notification.
   */
  public const val NO_ANNOUNCEMENT_ID: String = "__none__"

  /** Pure tracking state for HomeSpeaker announcement notification mirroring. */
  public data class MirrorState(
      val baselineId: String? = null,
      val activeNotificationId: String? = null,
      val activeNotificationText: String? = null,
  )

  /** Notification side-effect decided by pure HomeSpeaker mirror functions. */
  public sealed interface MirrorNotificationAction {
    public data object None : MirrorNotificationAction

    public data class Post(val id: String, val text: String) : MirrorNotificationAction

    public data class Update(val id: String, val text: String) : MirrorNotificationAction

    public data class Cancel(val id: String) : MirrorNotificationAction
  }

  /** Pure outcome of toggling the mirror setting or observing a HomeSpeaker poll. */
  public data class MirrorDecision(
      val enabled: Boolean,
      val state: MirrorState,
      val action: MirrorNotificationAction,
  )

  /**
   * Whether announcement mirroring is effectively active given the persisted toggle and OS
   * permission.
   */
  public fun isMirrorEnabled(mirrorEnabled: Boolean, permissionGranted: Boolean = true): Boolean =
      mirrorEnabled && permissionGranted

  /**
   * Resolves the announcement id to record as the baseline for future comparisons:
   * - `null` when HomeSpeaker is not available yet (so the first reachable poll still counts as
   *   first load and does not notify).
   * - The newest broadcast's trimmed `id` when non-blank.
   * - [NO_ANNOUNCEMENT_ID] when HomeSpeaker is available but has no broadcast with a non-blank id
   *   (so the very next real announcement triggers a notification).
   */
  public fun mirrorBaselineId(
      available: Boolean,
      recent: List<AgentLastBroadcast>,
      last: AgentLastBroadcast? = null,
  ): String? {
    if (!available) return null
    val newest = newestBroadcast(recent, last)
    return newest?.id?.trim()?.takeIf { it.isNotEmpty() } ?: NO_ANNOUNCEMENT_ID
  }

  /**
   * Pure decision for whether to post a phone notification when HomeSpeaker state is observed:
   * - Never notifies when `enabled` is false.
   * - Never notifies on first load or when the setting was just turned on (`previousId == null` or
   *   blank).
   * - Never notifies when `newId` is null, blank, or [NO_ANNOUNCEMENT_ID].
   * - Notifies only when `newId` differs from `previousId`.
   */
  public fun shouldNotifyAnnouncement(
      previousId: String?,
      newId: String?,
      enabled: Boolean,
  ): Boolean {
    if (!enabled) return false
    val prev = previousId?.trim().orEmpty()
    val next = newId?.trim().orEmpty()
    if (prev.isEmpty()) return false
    if (next.isEmpty() || next == NO_ANNOUNCEMENT_ID) return false
    return next != prev
  }

  /**
   * Pure decision when the "Show announcements as notifications" setting is toggled or its runtime
   * permission result arrives:
   * - Turning the toggle OFF, or requesting ON when `POST_NOTIFICATIONS` is denied, disables the
   *   setting and cancels any active announcement notification.
   * - Turning the toggle ON with permission granted enables the setting, seeds `baselineId` from
   *   the current HomeSpeaker snapshot so the already-latest announcement is never notified, and
   *   emits [MirrorNotificationAction.None].
   */
  public fun mirrorToggle(
      requestedOn: Boolean,
      permissionGranted: Boolean = true,
      state: MirrorState = MirrorState(),
      available: Boolean = false,
      recent: List<AgentLastBroadcast> = emptyList(),
      last: AgentLastBroadcast? = null,
  ): MirrorDecision {
    if (!requestedOn || !permissionGranted) {
      val action =
          state.activeNotificationId?.let { MirrorNotificationAction.Cancel(it) }
              ?: MirrorNotificationAction.None
      return MirrorDecision(
          enabled = false,
          state = state.copy(activeNotificationId = null, activeNotificationText = null),
          action = action,
      )
    }
    val baseline = mirrorBaselineId(available = available, recent = recent, last = last)
    return MirrorDecision(
        enabled = true,
        state = state.copy(baselineId = baseline),
        action = MirrorNotificationAction.None,
    )
  }

  /**
   * Pure decision when a HomeSpeaker status snapshot is observed:
   * - Picks the newest announcement from `recent` (falling back to `last`).
   * - When HomeSpeaker is unavailable (`!available`), preserves `baselineId` so the first reachable
   *   poll will not notify, while still cancelling an active notification if mirroring was disabled
   *   or lost permission.
   * - When mirroring is disabled or lacks permission, updates `baselineId` and cancels any active
   *   notification.
   * - When a new announcement id arrives after an established baseline (`shouldNotifyAnnouncement`)
   *   and has non-blank text, emits [MirrorNotificationAction.Post] (or
   *   [MirrorNotificationAction.Update] if that id is already active with different text).
   * - When the currently active notification's announcement id is observed again with updated
   *   non-blank text, emits [MirrorNotificationAction.Update].
   * - When an active notification's announcement disappears or its text becomes blank, emits
   *   [MirrorNotificationAction.Cancel].
   */
  public fun observeMirrorAnnouncement(
      state: MirrorState,
      mirrorEnabled: Boolean,
      permissionGranted: Boolean = true,
      available: Boolean,
      recent: List<AgentLastBroadcast>,
      last: AgentLastBroadcast? = null,
  ): MirrorDecision {
    val enabled = isMirrorEnabled(mirrorEnabled, permissionGranted)
    if (!available) {
      if (!enabled && state.activeNotificationId != null) {
        return MirrorDecision(
            enabled = false,
            state = state.copy(activeNotificationId = null, activeNotificationText = null),
            action = MirrorNotificationAction.Cancel(state.activeNotificationId),
        )
      }
      return MirrorDecision(
          enabled = enabled,
          state = state,
          action = MirrorNotificationAction.None,
      )
    }
    val newest = newestBroadcast(recent, last)
    val newId = newest?.id?.trim()?.takeIf { it.isNotEmpty() }
    val newText = newest?.text?.trim().orEmpty()
    val nextBaselineId = newId ?: NO_ANNOUNCEMENT_ID

    if (!enabled) {
      val action =
          state.activeNotificationId?.let { MirrorNotificationAction.Cancel(it) }
              ?: MirrorNotificationAction.None
      return MirrorDecision(
          enabled = false,
          state =
              MirrorState(
                  baselineId = nextBaselineId,
                  activeNotificationId = null,
                  activeNotificationText = null,
              ),
          action = action,
      )
    }

    if (shouldNotifyAnnouncement(previousId = state.baselineId, newId = newId, enabled = true)) {
      if (newId != null && newText.isNotEmpty()) {
        val action =
            if (state.activeNotificationId == newId) {
              if (state.activeNotificationText != newText) {
                MirrorNotificationAction.Update(newId, newText)
              } else {
                MirrorNotificationAction.None
              }
            } else {
              MirrorNotificationAction.Post(newId, newText)
            }
        return MirrorDecision(
            enabled = true,
            state =
                MirrorState(
                    baselineId = nextBaselineId,
                    activeNotificationId = newId,
                    activeNotificationText = newText,
                ),
            action = action,
        )
      }
      return MirrorDecision(
          enabled = true,
          state = state.copy(baselineId = nextBaselineId),
          action = MirrorNotificationAction.None,
      )
    }

    if (newId != null && newId == state.activeNotificationId) {
      if (newText.isEmpty()) {
        return MirrorDecision(
            enabled = true,
            state =
                MirrorState(
                    baselineId = nextBaselineId,
                    activeNotificationId = null,
                    activeNotificationText = null,
                ),
            action = MirrorNotificationAction.Cancel(state.activeNotificationId),
        )
      }
      if (newText != state.activeNotificationText) {
        return MirrorDecision(
            enabled = true,
            state =
                MirrorState(
                    baselineId = nextBaselineId,
                    activeNotificationId = newId,
                    activeNotificationText = newText,
                ),
            action = MirrorNotificationAction.Update(newId, newText),
        )
      }
      return MirrorDecision(
          enabled = true,
          state = state.copy(baselineId = nextBaselineId),
          action = MirrorNotificationAction.None,
      )
    }

    if (newId == null && state.activeNotificationId != null) {
      return MirrorDecision(
          enabled = true,
          state =
              MirrorState(
                  baselineId = nextBaselineId,
                  activeNotificationId = null,
                  activeNotificationText = null,
              ),
          action = MirrorNotificationAction.Cancel(state.activeNotificationId),
      )
    }

    return MirrorDecision(
        enabled = true,
        state = state.copy(baselineId = nextBaselineId),
        action = MirrorNotificationAction.None,
    )
  }

  /**
   * The broadcast that Now strip Replay and the Last announcement plate Replay both replay:
   * `recent.firstOrNull()` (falling back to `last` on an older agent), matching the newest row in
   * Recent broadcasts verbatim.
   */
  /** A broadcast can be replayed only if it has words or an id the Mac can look up. */
  public fun isReplayable(b: AgentLastBroadcast?): Boolean =
      b != null && (b.text.isNotBlank() || b.id.isNotBlank())

  public fun newestBroadcast(
      recent: List<AgentLastBroadcast>,
      last: AgentLastBroadcast? = null,
  ): AgentLastBroadcast? = (recent.ifEmpty { listOfNotNull(last) }).firstOrNull()

  /** Builds all five controls for HomeSpeaker's Now strip in display order. */
  public fun homeSpeakerQuickActions(
      paired: Boolean,
      available: Boolean,
      installed: Boolean = true,
      volumeAvailable: Boolean,
      volumeOnline: Boolean,
      muted: Boolean,
      percent: Int,
      volumeBusy: Boolean = false,
      quietEnabled: Boolean,
      quietActive: Boolean,
      quietStart: String,
      quietEnd: String,
      targetName: String,
      targetRoom: String = "",
      targetType: String = "",
      hasRoomChoices: Boolean = true,
      hasReplay: Boolean,
      replayTarget: String? = null,
      snoozeUntil: String? = null,
      nowMs: Long = System.currentTimeMillis(),
      zoneId: ZoneId = ZoneId.systemDefault(),
  ): List<QuickActionSpec> =
      listOf(
          muteQuickAction(
              paired = paired,
              volumeAvailable = volumeAvailable,
              volumeOnline = volumeOnline,
              muted = muted,
              percent = percent,
              busy = volumeBusy,
          ),
          quietHoursQuickAction(
              paired = paired,
              available = available,
              enabled = quietEnabled,
              active = quietActive,
              start = quietStart,
              end = quietEnd,
          ),
          roomQuickAction(
              paired = paired,
              available = available,
              targetName = targetName,
              targetRoom = targetRoom,
              targetType = targetType,
              hasChoices = hasRoomChoices,
          ),
          replayQuickAction(
              paired = paired,
              available = available,
              installed = installed,
              hasReplay = hasReplay,
              target = replayTarget,
          ),
          snoozeQuickAction(
              paired = paired,
              available = available,
              snoozeUntil = snoozeUntil,
              nowMs = nowMs,
              zoneId = zoneId,
          ),
      )

  private val HTTP_CODE_REGEX = Regex("""\bHTTP\s+\d{3}\b""", RegexOption.IGNORE_CASE)
  private val AUTH_CODE_REGEX = Regex("""\bHTTP\s+40[13]\b""", RegexOption.IGNORE_CASE)
  private val LEAKED_PATH_OR_CODE_REGEX = Regex("""(?:/v\d+/|https?://)""", RegexOption.IGNORE_CASE)

  /**
   * One-line inline error shown directly under a HomeSpeaker Now strip control, stream plate, or
   * Settings row when an action fails. Uses plain words rather than exception class names, paths,
   * or raw HTTP codes.
   */
  public fun homeSpeakerInlineError(
      what: String,
      reason: String? = null,
      authFailed: Boolean = false,
  ): String {
    val action = what.trim().ifEmpty { "update speaker" }
    val raw = reason?.trim().orEmpty()
    val lower = raw.lowercase(Locale.ROOT)
    if (authFailed ||
        AUTH_CODE_REGEX.containsMatchIn(raw) ||
        lower.contains("not paired") ||
        lower.contains("unauthorized") ||
        lower.contains("forbidden")) {
      return "Couldn't $action: this phone isn't paired"
    }
    val unreachable =
        raw.isEmpty() ||
            lower.contains("timeout") ||
            lower.contains("timed out") ||
            lower.contains("connect") ||
            lower.contains("unreachable") ||
            lower.contains("refused") ||
            lower.contains("reset") ||
            lower.contains("eof") ||
            lower.contains("broken pipe") ||
            lower.contains("unable to resolve") ||
            lower.contains("unknownhost") ||
            lower.contains("unknown host") ||
            lower.contains("no route")
    if (unreachable) {
      return "Couldn't $action: the Mac didn't answer"
    }
    if (lower.startsWith("agent:") ||
        HTTP_CODE_REGEX.containsMatchIn(raw) ||
        LEAKED_PATH_OR_CODE_REGEX.containsMatchIn(raw) ||
        raw.contains('/')) {
      return "Couldn't $action: the Mac returned an error"
    }
    return "Couldn't $action: $raw"
  }

  /** Visual state for the Quick Settings "Speaker" mute tile. */
  public enum class SpeakerTileLook {
    Unavailable,
    Inactive,
    Active,
  }

  /** State and subtitle for the Quick Settings "Speaker" mute tile. */
  public data class SpeakerTileSpec(
      val look: SpeakerTileLook,
      val subtitle: String,
  )

  /**
   * Maps pairing and `/v1/homespeaker/volume` state to the Quick Settings "Speaker" tile.
   * - Unpaired or no host -> [SpeakerTileLook.Unavailable], `"Not paired"`
   * - POST click failure -> [SpeakerTileLook.Unavailable], `"Couldn't reach the Mac"`
   * - GET unreachable -> [SpeakerTileLook.Unavailable], `"Mac unreachable"`
   * - Reachable but volume unavailable / offline -> [SpeakerTileLook.Unavailable], `"Volume
   *   unavailable"`
   * - Muted -> [SpeakerTileLook.Inactive], `"Muted"`
   * - Unmuted -> [SpeakerTileLook.Active], `"On · NN%"`
   */
  public fun speakerTileState(
      paired: Boolean,
      reachable: Boolean,
      available: Boolean = true,
      online: Boolean = true,
      muted: Boolean = false,
      percent: Int = 0,
      clickFailed: Boolean = false,
  ): SpeakerTileSpec =
      when {
        !paired -> SpeakerTileSpec(SpeakerTileLook.Unavailable, "Not paired")
        clickFailed -> SpeakerTileSpec(SpeakerTileLook.Unavailable, "Couldn't reach the Mac")
        !reachable -> SpeakerTileSpec(SpeakerTileLook.Unavailable, "Mac unreachable")
        !available || !online -> SpeakerTileSpec(SpeakerTileLook.Unavailable, "Volume unavailable")
        muted -> SpeakerTileSpec(SpeakerTileLook.Inactive, "Muted")
        else -> SpeakerTileSpec(SpeakerTileLook.Active, "On · ${percent.coerceIn(0, 100)}%")
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

  // --- pairing: may this phone ACT, or only look ------------------------------

  /**
   * Whether the selected Mac will take orders from this phone.
   *
   * Reachable is not the same as allowed. The agent serves its read tier (metrics, host, processes)
   * to anyone on the tailnet, so a phone holding no token still fills every dashboard and looked
   * fully "connected" -- while every switch, dropdown and button behind the act tier was refused.
   * This is the one question that tells those two apart, and the shell asks it before it says
   * "connected".
   */
  public enum class Pairing {
    /** No Mac configured: the app is simulating, and there is nothing to pair with. */
    NoAgent,
    /** A token is held. Acting will work unless the Mac says otherwise. */
    Paired,
    /** No token was ever issued for this Mac (or it was lost before anything was refused). */
    NotPaired,
    /** The Mac answered 401/403 to a token this phone held, and the token was dropped. */
    Rejected,
  }

  /**
   * [rejected] is only consulted while the token is blank: a token in hand means a pairing has
   * succeeded since the refusal, so the old refusal is history and says nothing about now.
   */
  public fun pairing(hasAgent: Boolean, hasToken: Boolean, rejected: Boolean): Pairing =
      when {
        !hasAgent -> Pairing.NoAgent
        hasToken -> Pairing.Paired
        rejected -> Pairing.Rejected
        else -> Pairing.NotPaired
      }

  /** True when the Mac can be looked at but not changed: the case the banner exists for. */
  public fun needsPairing(pairing: Pairing): Boolean =
      pairing == Pairing.NotPaired || pairing == Pairing.Rejected

  /** The banner's label and body, or null when there is nothing to warn about. */
  public fun pairingBanner(pairing: Pairing, mac: String): Pair<String, String>? =
      when (pairing) {
        Pairing.NotPaired ->
            "Not paired with $mac" to
                "This phone is not paired with $mac. You can look, but changes will not work."
        Pairing.Rejected ->
            "$mac stopped accepting this phone" to
                "$mac refused this phone's pairing key. You can look, but changes will not " +
                    "work until you pair again."
        Pairing.NoAgent,
        Pairing.Paired -> null
      }

  /** What an act refused for want of pairing says, wherever it is shown. Names the Mac. */
  public fun notPairedText(mac: String): String = "Not paired with $mac — pair to make changes"

  /** The one word the status dot beside a host carries. */
  public fun connectionWord(pairing: Pairing, base: String): String =
      if (needsPairing(pairing)) "connected · not paired" else base

  // --- phone bridge: on is not the same as linked --------------------------

  /** Why the bridge is switched on and still not linked. */
  public enum class BridgeProblem {
    /** Off, or linked: nothing to say. */
    None,
    /** Dialling, or between attempts. Transient; the plate says so, the banner does not. */
    Connecting,
    /** No token, or the Mac refused it. The link endpoint is act tier. */
    NotPaired,
    /** The Mac is not answering at all. */
    Unreachable,
    /** Switched on, but the service is not running (killed, or never started). */
    Stopped,
    /** Anything else; the link's own words carry it. */
    Other,
  }

  /**
   * [linkStatus] is what the bridge service last said about its link. `off` is the service's own
   * word for "not running"; `not paired…` is what it says when it refuses to dial with no token,
   * and an `AgentAuthException`'s message (`not paired (HTTP 401)`) when the Mac refused the one it
   * had. Pairing is checked first because the service only re-reads the token between attempts, so
   * for up to a minute its words can lag what the phone already knows.
   */
  public fun bridgeProblem(
      enabled: Boolean,
      linked: Boolean,
      pairing: Pairing,
      reachable: Boolean,
      linkStatus: String,
  ): BridgeProblem {
    val status = linkStatus.trim().lowercase(Locale.ROOT)
    return when {
      !enabled || linked -> BridgeProblem.None
      status == "off" -> BridgeProblem.Stopped
      needsPairing(pairing) || status.startsWith("not paired") -> BridgeProblem.NotPaired
      !reachable -> BridgeProblem.Unreachable
      status.isEmpty() ||
          status.startsWith("connecting") ||
          status.startsWith("starting") ||
          status == "linked" -> BridgeProblem.Connecting
      else -> BridgeProblem.Other
    }
  }

  /** The plate's and the banner's sentence for [problem], or null when there is nothing to say. */
  public fun bridgeProblemText(problem: BridgeProblem, mac: String, linkStatus: String): String? =
      when (problem) {
        BridgeProblem.None -> null
        BridgeProblem.Connecting -> "Phone Bridge is connecting to $mac…"
        BridgeProblem.NotPaired ->
            "Phone Bridge is on but cannot link: this phone is not paired with $mac."
        BridgeProblem.Unreachable -> "Phone Bridge is on but cannot link: $mac is not answering."
        BridgeProblem.Stopped -> "Phone Bridge is on but its service is not running."
        BridgeProblem.Other -> "Phone Bridge is on but not linked: ${linkStatus.trim()}"
      }

  /** Whether the problem deserves the top-of-screen banner, not just the plate's line. */
  public fun bridgeProblemIsBannerWorthy(problem: BridgeProblem): Boolean =
      problem != BridgeProblem.None && problem != BridgeProblem.Connecting

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

  // --- demand-driven polling ----------------------------------------------

  /**
   * One thing the phone can ask the Mac agent for. Mostly one endpoint each; [Power] is the two
   * PromQL power queries, which only ever go together.
   */
  public enum class PollSource {
    Metrics,
    Host,
    Processes,
    Audio,
    ClaudeSessions,
    Sessions,
    AntigravitySessions,
    Antigravity,
    Prs,
    Argo,
    K8s,
    Vms,
    Containers,
    Ollama,
    HomeSpeaker,
    SpeakerVolume,
    Tv,
    Tools,
    Notify,
    Power,
  }

  /**
   * The app's screens, as the poll sees them. A mirror of `Screen`, which lives in the Android
   * library this one cannot depend on; `RemoteState` maps one to the other with an exhaustive
   * `when`, so a new screen fails to compile until it is placed here too.
   */
  public enum class PollPage {
    Home,
    Remote,
    Mac,
    Apps,
    Console,
    Hosts,
  }

  /**
   * What the person can see right now, which is all the poll needs to know about the UI.
   *
   * [module] is the dashboard Apps is showing (already resolved through its fallback), and only
   * counts while [appsDashboards] is true: the gallery shows a different thing entirely.
   */
  public data class PollView(
      val page: PollPage,
      val module: String,
      val appsDashboards: Boolean,
      val foreground: Boolean,
      /** An agent older than v1.7 answers 404 for sessions; ask it on the slow cadence only. */
      val antigravitySessionsSupported: Boolean = true,
  )

  /** How often the cheap reads go round, and the ones that shell out on the Mac, in ticks. */
  public const val SLOW_POLL_EVERY: Int = 3

  /** The contract samples PRs every 60 s on the Mac; asking faster only spends rate limit. */
  public const val PR_POLL_MS: Long = 60_000L

  /**
   * Home's "Running now" rows are one line each about modules nobody has opened. They refresh, but
   * not at the rate of the dashboard that is actually open.
   */
  public const val SUMMARY_POLL_MS: Long = 15_000L

  /**
   * Off screen the only reads left are the ones that keep the connection honest: whether the Mac
   * still answers (the "unreachable" notification and Wake-on-LAN hang off that), nothing else.
   */
  public const val BACKGROUND_POLL_MS: Long = 30_000L

  /** Host identity barely changes; ask again every this many ticks. */
  public const val HOST_REFRESH_TICKS: Int = 40

  /** Never again once fetched: due only while there is nothing at all. */
  public const val ONCE: Long = Long.MAX_VALUE

  /** The sources an Apps dashboard reads, by module id. Grafana's query runs on demand. */
  public fun moduleSources(module: String): Set<PollSource> =
      when (module) {
        "claude" -> setOf(PollSource.ClaudeSessions, PollSource.Sessions)
        "prs" -> setOf(PollSource.Prs)
        "lima" -> setOf(PollSource.Vms)
        "homelab" -> setOf(PollSource.Argo, PollSource.K8s)
        "docker" -> setOf(PollSource.Containers)
        "ollama" -> setOf(PollSource.Ollama)
        "homespeaker" -> setOf(PollSource.HomeSpeaker, PollSource.SpeakerVolume)
        "tv" -> setOf(PollSource.Tv)
        "antigravity" -> setOf(PollSource.Antigravity, PollSource.AntigravitySessions)
        else -> emptySet()
      }

  /** Everything Home's "Running now" list summarises, one row per module. */
  private val homeSummary: Set<PollSource> =
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
          PollSource.HomeSpeaker,
      )

  /**
   * How often a source is worth asking for when it is on screen in full.
   *
   * The reads that move second to second (metrics, processes, audio, Claude and Antigravity
   * sessions) go every tick; the ones that make the Mac shell out (`limactl`, `docker`, `kubectl`,
   * `adb`, `say -v ?`) every [SLOW_POLL_EVERY] ticks; GitHub at its own sampling rate.
   */
  public fun nativeCadenceMs(
      source: PollSource,
      tickMs: Long,
      antigravitySessionsSupported: Boolean = true,
  ): Long {
    val slow = tickMs * SLOW_POLL_EVERY
    return when (source) {
      PollSource.Metrics,
      PollSource.Processes,
      PollSource.Audio,
      PollSource.ClaudeSessions -> tickMs
      PollSource.AntigravitySessions -> if (antigravitySessionsSupported) tickMs else slow
      PollSource.Host -> tickMs * HOST_REFRESH_TICKS
      PollSource.Prs -> PR_POLL_MS
      else -> slow
    }
  }

  /**
   * What is on screen, and how often each of it should be asked for.
   *
   * The answer to "why is the phone asking for that?" is always a row of this map. Metrics and host
   * identity are the global chrome -- the connection state, the host chip, the Home widgets -- and
   * are always in it; everything else is here only while a screen draws it. Backgrounded, nothing
   * but the reachability check remains, at [BACKGROUND_POLL_MS].
   */
  public fun pollCadences(view: PollView, tickMs: Long): Map<PollSource, Long> {
    if (!view.foreground) {
      return mapOf(
          PollSource.Metrics to maxOf(tickMs, BACKGROUND_POLL_MS),
          PollSource.Host to ONCE,
      )
    }

    fun native(source: PollSource) =
        nativeCadenceMs(source, tickMs, view.antigravitySessionsSupported)
    val out = LinkedHashMap<PollSource, Long>()

    fun show(sources: Set<PollSource>, cadence: (PollSource) -> Long) {
      for (source in sources) {
        val ms = cadence(source)
        out[source] = minOf(out[source] ?: Long.MAX_VALUE, ms)
      }
    }

    show(setOf(PollSource.Metrics, PollSource.Host), ::native)
    when (view.page) {
      PollPage.Home ->
          show(homeSummary) { source ->
            // A Claude session waiting on a prompt is the one thing on Home
            // that asks the person to act, so it keeps its own pace.
            if (source == PollSource.ClaudeSessions || source == PollSource.Sessions) {
              native(source)
            } else {
              maxOf(native(source), SUMMARY_POLL_MS)
            }
          }
      PollPage.Remote -> show(setOf(PollSource.Audio), ::native)
      PollPage.Mac ->
          show(
              setOf(
                  PollSource.Processes,
                  PollSource.Vms,
                  PollSource.Containers,
                  PollSource.K8s,
                  PollSource.Power,
              ),
              ::native,
          )
      PollPage.Apps -> {
        // The gallery is a different view of Apps: it reads the tool inventory.
        val shown = if (view.appsDashboards) moduleSources(view.module) else setOf(PollSource.Tools)
        show(shown, ::native)
      }
      PollPage.Console -> Unit
      PollPage.Hosts -> show(setOf(PollSource.Notify), ::native)
    }
    return out
  }

  /**
   * The sources to ask for now.
   *
   * Due when it is on screen and any of: it has never been fetched; it was last fetched at least
   * its cadence ago; or it has just come on screen, or come on screen in more detail (its cadence
   * got shorter, as when Home's one-line row opens into the module). That last one is what makes
   * opening a module refresh it at once, however recently Home's row read the same endpoint: the
   * last value stays up and a fresh one is asked for immediately, rather than at the next tick or
   * the next slow tick.
   *
   * [lastFetchedMs] is a monotonic clock reading per source, of the last time it was asked for.
   * [wasVisible] is [pollCadences] as it stood at the previous pass; null when there is no previous
   * pass to compare with.
   */
  public fun pollDue(
      view: PollView,
      tickMs: Long,
      nowMs: Long,
      lastFetchedMs: Map<PollSource, Long>,
      wasVisible: Map<PollSource, Long>? = null,
  ): Set<PollSource> =
      pollCadences(view, tickMs)
          .filter { (source, cadence) ->
            val last = lastFetchedMs[source] ?: return@filter true
            val before = wasVisible?.let { it[source] ?: Long.MAX_VALUE }
            if (before != null && cadence < before) return@filter true
            cadence != ONCE && nowMs - last >= cadence
          }
          .keys

  /** The shortest the poll loop sleeps, so a source that cannot be fetched never spins it. */
  public const val MIN_POLL_WAIT_MS: Long = 250L

  /**
   * How long the poll loop may sleep before something on screen falls due.
   *
   * Never longer than a tick, because the pairing countdown and the trust timer advance with the
   * loop, and never shorter than [MIN_POLL_WAIT_MS]: a source that is due but cannot be asked for
   * (the Mac is not answering, so the extras wait for it) must not turn the loop into a spin.
   */
  public fun pollWaitMs(
      view: PollView,
      tickMs: Long,
      nowMs: Long,
      lastFetchedMs: Map<PollSource, Long>,
  ): Long {
    val untilDue =
        pollCadences(view, tickMs).mapNotNull { (source, cadence) ->
          val last = lastFetchedMs[source] ?: return@mapNotNull 0L
          if (cadence == ONCE) null else last + cadence - nowMs
        }
    val next = untilDue.minOrNull() ?: tickMs
    return next.coerceIn(MIN_POLL_WAIT_MS, maxOf(tickMs, MIN_POLL_WAIT_MS))
  }

  /**
   * Filters a saved installed-module list down to known [galleryIds], preserving order and dropping
   * unknown or retired module ids silently.
   */
  public fun filterInstalledModules(
      saved: Iterable<String>,
      galleryIds: Set<String>,
  ): List<String> = saved.filter { it in galleryIds }

  /**
   * Gallery module ids that appear in the Dashboards chip bar: every gallery module in [installed]
   * that is present in [availableDashboards]. Both live and simulated modes populate
   * [availableDashboards] for every gallery id, so installing Docker, Ollama, or Grafana in
   * simulated mode keeps its tab visible.
   */
  public fun visibleModuleIds(
      galleryIds: List<String>,
      installed: Set<String>,
      availableDashboards: Set<String>,
  ): List<String> = galleryIds.filter { it in installed && it in availableDashboards }

  /** `0`, `6.4`, `31.6` -- `Format.decimal`'s shape; this library cannot depend on :format. */
  private fun decimal(value: Double): String {
    val rounded = Math.round(value * 10) / 10.0
    return String.format(Locale.ROOT, "%.1f", rounded).removeSuffix(".0")
  }
}
